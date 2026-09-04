#!/usr/bin/env zsh
# release.sh — Build, verify, package, and publish a ClipHack release.
#
# Usage: ./release.sh <version>
#   e.g. ./release.sh 1.11.8
#
# Requires: xcodebuild, hdiutil, gh (GitHub CLI), git

set -euo pipefail

SOURCE_REPO="sevmorris/ClipHack"          # public — source, tags
RELEASES_REPO="sevmorris/ClipHack-releases" # public — DMG artifacts, updater target

# ── Args ──────────────────────────────────────────────────────────────────────
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <version>"
    echo "  e.g. $0 1.11.8"
    exit 1
fi

VERSION="$1"
TAG="v${VERSION}"
SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="$SCRIPT_DIR"
PROJECT="$PROJECT_DIR/ClipHack.xcodeproj"
SCHEME="ClipHack"
DERIVED_DATA="/tmp/cliphack_build_${VERSION}"
APP_PATH="$DERIVED_DATA/Build/Products/Release/ClipHack.app"
DMG="/tmp/ClipHack-${TAG}.dmg"
MOUNT="/tmp/cliphack_verify_${VERSION}"

# ── Helpers ───────────────────────────────────────────────────────────────────
step()  { echo "\n▶ $*"; }
ok()    { echo "  ✓ $*"; }
fail()  { echo "\n  ✗ $*" >&2; exit 1; }
warn()  { echo "  ! $*" >&2; }

# ── Preflight ─────────────────────────────────────────────────────────────────
step "Preflight checks"
for cmd in xcodebuild hdiutil gh git codesign xcrun curl python3; do
    command -v $cmd &>/dev/null || fail "'$cmd' not found in PATH"
done
python3 -c "import dmgbuild" 2>/dev/null \
    || fail "python3 module 'dmgbuild' not installed — run: python3 -m pip install dmgbuild"
ok "Tools present"

cd "$PROJECT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
    fail "Working tree is dirty — commit or stash changes before releasing"
fi
ok "Working tree clean"

if git tag | grep -q "^${TAG}$"; then
    fail "Tag $TAG already exists — has this version been released?"
fi
ok "Tag $TAG is available"

# ── Version ordering ────────────────────────────────────────────────────────────────────────
# Nothing here stopped a release going backwards. On 2026-09-03 Magic Backup
# Machine published v1.3.9 on top of v1.4.2 — two sessions releasing from one
# clone, neither aware of the other. GitHub served the older build as "latest"
# from that moment, and because the update checker compares numerically, every
# client already on 1.4.2 read 1.3.9 as older and reported itself up to date.
# The release could not reach anyone.
#
# Tags are the record of what is actually published, and what "latest" keys on,
# so they are what this compares against. Set ALLOW_DOWNGRADE=1 to override.
step "Checking version ordering"
version_core() { printf '%s' "${1%%[-+]*}"; }
HIGHEST_TAG=$(git tag --sort=-v:refname | head -1 | sed 's/^v//')
if [[ -n "$HIGHEST_TAG" ]]; then
    NEW_CORE=$(version_core "$VERSION")
    REF_CORE=$(version_core "$HIGHEST_TAG")
    # Numeric cores only: `sort -V` places 1.7.0 ahead of 1.7.0-rc.1, backwards
    # from semver, and comparing raw strings would block any release that
    # follows its own release candidate.
    if [[ "$NEW_CORE" != "$REF_CORE" ]] \
       && [[ "$(printf '%s\n%s\n' "$NEW_CORE" "$REF_CORE" | sort -V | head -1)" == "$NEW_CORE" ]]; then
        if [[ "${ALLOW_DOWNGRADE:-0}" != "0" ]]; then
            warn "$VERSION sorts below tag v$HIGHEST_TAG — continuing, ALLOW_DOWNGRADE is set"
        else
            fail "$VERSION sorts below the highest tag v$HIGHEST_TAG. Publishing it would leave GitHub serving an older build as 'latest', and clients on $HIGHEST_TAG would be told they are up to date. Set ALLOW_DOWNGRADE=1 to override."
        fi
    fi
fi
ok "Version $VERSION does not go backwards"


# ── Shared-file gate ──────────────────────────────────────────────────────────
# Several files here are vendored copies kept byte-identical with the sibling
# app repos — these projects are deliberately independent, so there is no shared
# package to depend on. The failure mode that costs something is silent drift: a
# fix lands in one repo and the others keep the bug, which is exactly how the
# FFmpeg process hardening reached WaxOnWaxOff and left two latent crashes in
# ClipHack. Release day is when someone is looking, so it is when to say so.
#
# Absent siblings are not drift — a fresh clone or a CI checkout has none, and
# the check passes quietly. Only a content mismatch stops the release.
step "Checking shared files against sibling repos"
"$PROJECT_DIR/scripts/check-shared.sh" \
    || fail "Shared files have drifted from the sibling repos — reconcile them before releasing"
ok "Shared files in sync"

# ── Version bump ──────────────────────────────────────────────────────────────
step "Bumping version to $VERSION"
CURRENT=$(grep MARKETING_VERSION "$PROJECT/project.pbxproj" | head -1 | grep -o '[0-9][0-9.]*')
if [[ "$CURRENT" == "$VERSION" ]]; then
    ok "Already at $VERSION"
else
    ESC_CURRENT=$(printf '%s' "$CURRENT" | sed 's/[.[\*^$]/\\&/g')
    ESC_VERSION=$(printf '%s'  "$VERSION" | sed 's/[.[\*^$]/\\&/g')
    sed -i '' "s/MARKETING_VERSION = ${ESC_CURRENT};/MARKETING_VERSION = ${ESC_VERSION};/g" \
        "$PROJECT/project.pbxproj"
    ok "Bumped $CURRENT → $VERSION"
    git add "$PROJECT/project.pbxproj"
    git commit -m "Bump version to $VERSION"
    ok "Committed version bump"
fi

step "Bumping build number"
BUILD_NUM=$(grep 'CURRENT_PROJECT_VERSION = ' "$PROJECT/project.pbxproj" | head -1 | grep -o '[0-9][0-9]*')
NEXT_BUILD=$((BUILD_NUM + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION = ${BUILD_NUM};/CURRENT_PROJECT_VERSION = ${NEXT_BUILD};/g" \
    "$PROJECT/project.pbxproj"
ok "Build number ${BUILD_NUM} → ${NEXT_BUILD}"

step "Fetching FFmpeg binaries"
chmod +x "$PROJECT_DIR/scripts/fetch-ffmpeg.sh"
"$PROJECT_DIR/scripts/fetch-ffmpeg.sh"
ok "FFmpeg present"

step "Fetching yt-dlp binary"
chmod +x "$PROJECT_DIR/scripts/fetch-ytdlp.sh"
"$PROJECT_DIR/scripts/fetch-ytdlp.sh"
ok "yt-dlp present"

# ── Build ─────────────────────────────────────────────────────────────────────
step "Building (clean, Release)"
rm -rf "$DERIVED_DATA"
rm -rf ~/Library/Caches/com.apple.dt.Xcode*(N) 2>/dev/null || true
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache*(N) 2>/dev/null || true
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -quiet
[[ -d "$APP_PATH" ]] || fail "Build did not produce $APP_PATH"
ok "Build complete"

# ── Sign ──────────────────────────────────────────────────────────────────────
step "Codesigning binaries and app"
IDENTITY="Developer ID Application: Seven Morris (T9RLNAXPWU)"
ENTITLEMENTS="$PROJECT_DIR/ClipHack/ClipHack.entitlements"
YTDLP_ENTITLEMENTS="$PROJECT_DIR/Vendor/ytdlp.entitlements"

# The vendored binaries now live in the embedded ClipHackKit framework's
# Resources (not the app's). Sign inside-out: resource binaries, then the
# framework, then the app.
KIT_RES="$APP_PATH/Contents/Frameworks/ClipHackKit.framework/Versions/A/Resources"
codesign --force --options runtime --sign "$IDENTITY" "$KIT_RES/ffmpeg"
codesign --force --options runtime --sign "$IDENTITY" "$KIT_RES/ffprobe"
# yt-dlp (PyInstaller onefile) needs its own entitlements under the hardened
# runtime — see Vendor/ytdlp.entitlements for why.
codesign --force --options runtime --entitlements "$YTDLP_ENTITLEMENTS" --sign "$IDENTITY" "$KIT_RES/yt-dlp"
codesign --force --options runtime --sign "$IDENTITY" "$APP_PATH/Contents/Frameworks/ClipHackKit.framework"
codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | tail -3
ok "Codesigning complete"

# ── Verify app version ────────────────────────────────────────────────────────
step "Verifying built app version"
BUILT_VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
[[ "$BUILT_VERSION" == "$VERSION" ]] || \
    fail "App version mismatch: expected $VERSION, got $BUILT_VERSION"
ok "App reports $BUILT_VERSION"

# ── Create DMG ────────────────────────────────────────────────────────────────
# Built with dmgbuild rather than bare hdiutil so the installer window is laid
# out: background art with an arrow, the app and the Applications alias pinned
# to its endpoints, chrome hidden. dmgbuild writes the .DS_Store directly, so
# this needs no Finder, no GUI session and no automation permission — styling a
# mounted image with AppleScript would make releases fail for environment
# reasons rather than code ones.
#
# Two PATH subtleties, both load-bearing:
#   * python3 is resolved BEFORE the PATH override, so we keep the interpreter
#     that actually has dmgbuild installed rather than Xcode's bundled one.
#   * /bin is prepended for the child, because dmgbuild shells out to bare
#     `sync` and a personal ~/bin/sync would otherwise shadow the system one
#     and abort the build.
step "Creating DMG"
rm -f "$DMG"
DMG_BACKGROUND="$PROJECT_DIR/tools/dmg/dmg-background-cliphack.png"
[[ -f "$DMG_BACKGROUND" ]] \
    || fail "Missing DMG background: ${DMG_BACKGROUND#$PROJECT_DIR/} — regenerate with tools/dmg/make-background.py"
PY_BIN=$(command -v python3)
PATH="/bin:/usr/bin:$PATH" "$PY_BIN" -m dmgbuild \
    -s "$PROJECT_DIR/tools/dmg/dmg-settings.py" \
    -D app="$APP_PATH" \
    -D background="$DMG_BACKGROUND" \
    "Install ClipHack" \
    "$DMG" >/dev/null
[[ -f "$DMG" ]] || fail "dmgbuild did not produce $DMG"
ok "Created $(du -sh $DMG | cut -f1) styled DMG"

# ── Notarize ──────────────────────────────────────────────────────────────────
step "Notarizing DMG"
xcrun notarytool submit "$DMG" --wait --keychain-profile "WoWoNotary"
xcrun stapler staple "$DMG"
ok "Notarization complete"

# ── Verify DMG ────────────────────────────────────────────────────────────────
step "Verifying DMG contents"
rm -rf "$MOUNT"
mkdir "$MOUNT"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -quiet -nobrowse
DMG_VERSION=$(defaults read "$MOUNT/ClipHack.app/Contents/Info.plist" CFBundleShortVersionString)
hdiutil detach "$MOUNT" -quiet
[[ "$DMG_VERSION" == "$VERSION" ]] || \
    fail "DMG version mismatch: expected $VERSION, got $DMG_VERSION"
ok "DMG contains $DMG_VERSION"

# ── Update README download link ──────────────────────────────────────────────
step "Updating docs to ${TAG}"
# The manual is included deliberately. It was left out until 1.19.4 and drifted
# to v1.12.0 — seven minor versions — with a download button pointing at
# sevmorris/ClipHack, which has never hosted the DMGs, so it 404'd. Anything
# that names a version or a download URL belongs in this list.
MANUAL_IDX="$PROJECT_DIR/docs/manual/index.html"
sed -i '' "s|ClipHack-v[0-9][0-9.]*\.dmg|ClipHack-${TAG}.dmg|g" "$PROJECT_DIR/README.md" "$MANUAL_IDX"
sed -i '' "s|>Download v[0-9][0-9.]*<|>Download ${TAG}<|g" "$MANUAL_IDX"
sed -i '' "s|Manual — v[0-9][0-9.]*|Manual — ${TAG}|g" "$MANUAL_IDX"
sed -i '' "s|<strong>Version:</strong> [0-9][0-9.]*|<strong>Version:</strong> ${VERSION}|g" "$PROJECT_DIR/README.md"
sed -i '' "s|\*\*Version:\*\* [0-9][0-9.]*|**Version:** ${VERSION}|g" "$PROJECT_DIR/README.md"

if grep -E "ClipHack-v[0-9]+\.[0-9]+\.[0-9]+\.dmg" "$PROJECT_DIR/README.md" "$MANUAL_IDX" \
        | grep -v "${TAG}\.dmg" >/dev/null; then
    fail "Stale version references remain in README or manual after rewrite — check sed patterns"
fi

if [[ -n "$(git status --porcelain)" ]]; then
    # Pick up the build-number bump from the pbxproj so it actually lands in the
    # repo (otherwise the build bump stays uncommitted across runs).
    git add "$PROJECT/project.pbxproj" "$PROJECT_DIR/README.md" "$MANUAL_IDX"
    git commit -m "docs: update download link to ${TAG}"
    ok "README and manual point to ${TAG}"
else
    ok "README already up to date"
fi

# ── Tag and push ──────────────────────────────────────────────────────────────
step "Tagging and pushing"
git tag "$TAG"
# Resolve the tracked remote/branch so this works from any branch (e.g. a
# worktree branch whose name differs from its upstream). Fall back to
# `origin` + current branch when no upstream is configured; `-u` sets it
# on first push so subsequent runs resolve cleanly.
if UPSTREAM=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null); then
    REMOTE="${UPSTREAM%%/*}"
    BRANCH="${UPSTREAM#*/}"
else
    REMOTE="origin"
    BRANCH=$(git branch --show-current)
fi
git push -u "$REMOTE" "HEAD:$BRANCH"
git push "$REMOTE" "$TAG"
ok "Pushed $TAG to $REMOTE/$BRANCH"

# ── GitHub release ────────────────────────────────────────────────────────────
step "Creating GitHub release"
PREV_TAG=$(git tag --sort=-creatordate | grep -v "^${TAG}$" | head -1 || true)
if [[ -n "$PREV_TAG" ]]; then
    CHANGES=$(git log "${PREV_TAG}..HEAD" --pretty=format:"- %s" \
        | grep -v "^- Bump version" \
        | grep -v "^- docs: update download link" || true)
else
    CHANGES=$(git log --pretty=format:"- %s" \
        | grep -v "^- Bump version" \
        | grep -v "^- docs: update download link" || true)
fi
[[ -n "$CHANGES" ]] || CHANGES="- Initial release"
RELEASE_NOTES="### Changes
${CHANGES}"
# The releases repo is a separate public repo with no source tree, so target
# its default branch's HEAD when creating the tag remotely.
gh release create "$TAG" "$DMG" \
    --repo "$RELEASES_REPO" \
    --target main \
    --title "ClipHack $TAG" \
    --notes "$RELEASE_NOTES"
ok "Release published to $RELEASES_REPO"

# ── Remove old app releases (keep the ${KEEP_RELEASES} most recent v* tags) ───
KEEP_RELEASES=5
step "Removing old app releases (keeping ${KEEP_RELEASES} most recent v* tags)"
OLD_TAGS=$(gh release list --repo "$RELEASES_REPO" --limit 100 --json tagName \
    --jq '.[].tagName' | grep -E '^v[0-9]' | tail -n +$((KEEP_RELEASES + 1)) || true)
if [[ -z "$OLD_TAGS" ]]; then
    ok "No old releases to remove"
else
    while IFS= read -r old_tag; do
        gh release delete "$old_tag" --repo "$RELEASES_REPO" --yes --cleanup-tag 2>/dev/null || true
        ok "Removed $old_tag from $RELEASES_REPO"
    done <<< "$OLD_TAGS"
fi

# ── Clean up temp files ───────────────────────────────────────────────────────
step "Cleaning up"
rm -rf "$MOUNT" "$DERIVED_DATA"
rm -f "$DMG"
ok "Temp files removed"

RELEASE_URL="https://github.com/${RELEASES_REPO}/releases/tag/${TAG}"
echo "\n✓ ClipHack $TAG released successfully."
echo "  $RELEASE_URL"
open "$RELEASE_URL"
