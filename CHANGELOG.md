# Changelog

All notable changes to ClipHack are documented here. Version numbers match GitHub releases (`v*` tags).

## [Unreleased]

- **`scripts/build-ffmpeg.sh`** — builds the pinned audio-only ffmpeg/ffprobe from SHA-256-verified upstream source (FFmpeg 8.0 + LAME 3.100), with fail-closed gates asserting the binaries execute, carry no `--enable-gpl` / `--enable-nonfree` / `--enable-version3`, link libmp3lame, have no non-system dynamic dependencies, and target the project's deployment target. ClipHack can now produce its own Corresponding Source rather than relying on a third-party build
- **`scripts/parity-check.sh`** and **`scripts/parity-corpus-gen.sh`** — old-binary vs new-binary parity over a generated corpus, running the app's real multi-pass pipeline (mono extract → high-pass/all-pass → mirror-padded dynaudnorm → two-pass loudnorm → 2× oversampled limiter → dithered downsample) as separate stages, exactly as `AudioProcessor` runs it. Gates on null residual, LUFS, true peak, format, and sample count with frozen thresholds and PASS/FAIL/INCOMPLETE states, where INCOMPLETE never counts as a pass. Verified against an independently built binary: 340 gates, all PASS, every null `-inf`

## [1.17.0] — 2026-08-10

- **Switched to an audio-only LGPL FFmpeg build.** The previous pin was a third-party GPL build (OSXExperts.NET, linking x264/x265/libvidstab). Its assets were withdrawn from distribution because the exact Corresponding Source for that build could not be obtained, so the GPL obligations that come with distributing it could not be met — which also left `fetch-ffmpeg.sh` returning 404, making the project unbuildable from a clean checkout. The replacement is built from pinned, SHA-256-verified upstream source with no `--enable-gpl`, no `--enable-nonfree`, no `--enable-version3`, and no video or image libraries; libmp3lame is the only external library, and full Corresponding Source is available. Output is **bit-identical** to the old build across ClipHack's processing chain, with matching loudnorm measurements. Bundled binaries drop from 51.5 MB to 21.9 MB each
- The pinned FFmpeg binaries are now mirrored in ClipHack's own releases repo, so building no longer depends on another project's release lifecycle

- **One folder per download** — each clip now lands in its own folder named after the file (`Some Title/Some Title.m4a`) inside the download destination, so its audio, notes, and processed output stay together. A repeated title gets `-2`, `-3`, … rather than overwriting the earlier download
- **Save clip list** is now **Save clip notes** — instead of appending to a daily `clip-list-YYYY-MM-DD.txt`, each clip gets its own `Some Title.txt` beside the audio. The file body is unchanged (file name / notes / source URL), so concatenating the sidecars reproduces the old clip-list format. Existing clip lists are left alone; the preference carries over
- The download popover's **Notes** box is now resizable — drag the grip in its bottom-right corner, and the height is remembered across launches
- **Notes survive the session** — they're read back from the clip's notes file whenever it is added, so a clip re-added days later still knows what it is, and they're shown under the file name in the list (point at them for the full text)
- **Folder drops** — dropping a folder adds every audio file inside it, at any depth, so one clip folder or a whole show's worth can be added at once. Dropping the same file twice no longer doubles the row
- **Cross-session duplicate downloads** — downloading a link you already used adds the clip you have instead of fetching a second copy under a `-2` name. ClipHack reads the notes files in the destination, so it works in a new session days later; deleting a clip's audio lets the link download again

## [1.16.1] — 2026-07-20

- Fixed file-browser rows sometimes needing repeated clicks to select (a double-click gesture on each row was intermittently swallowing single clicks)
- Rename is now right-click → Rename… or select + press Return (Finder-style); double-click no longer renames

## [1.16.0] — 2026-07-06

- **Configurable download destination** — pick any folder for downloaded audio from the "Destination" row in the Add-from-URL popover; the choice is remembered for future downloads. Defaults to ~/Music/ClipHack, so nothing changes until you choose a folder. If a chosen folder is missing at download time (moved, deleted, drive unmounted), ClipHack asks for a new one rather than silently falling back

## [1.15.2] — 2026-07-06

- X-post Notes auto-fill now triggers when you paste a link straight into the URL field (⌘V), not only when it arrives by drag-and-drop, clipboard prefill, or pressing Return
- Changing the URL to a different X post now refreshes Notes with the new post's text instead of leaving the previous post's text behind — while notes you've typed or edited yourself are still never touched

## [1.15.1] — 2026-07-05

- The **Add from URL** download popover no longer closes when you click outside it. It stays open through typing, a failed download (so the error stays visible for a retry), and idle/prefilled states — closing only on a successful download or its new Close (✕) button

## [1.15.0] — 2026-07-05

- X/Twitter post links dropped or pasted into the download popover auto-fill Notes with the post's text (best-effort; silently skipped if unavailable, and never overwrites text you've typed)

## [1.14.1] — 2026-07-04

- Updated app icon (no functional changes)

## [1.14.0] — 2026-07-04

- **Download from URL** — paste or drop a web link (toolbar button, ⌘L) to pull a clip's audio into the file list. yt-dlp is bundled and pinned (official universal2 standalone, signed with hardened-runtime entitlements at release) — no external install. Video sources are saved as audio only (native codec, no re-encode) into `~/Music/ClipHack`
- Optional custom file name for downloads — stem only, sanitized, auto-uniquified against the download folder
- Optional per-download notes, kept on the file row
- **Save clip list** — appends file name / notes / source URL to a daily `clip-list-YYYY-MM-DD.txt` next to downloads. Entries are a point-in-time log and are not rewritten when a file is renamed later (by design)
- **Rename** any file-list row (right-click → Rename…, or double-click) — renames on disk; stem only, extension fixed. Busy rows (analyzing/processing) refuse rename; name collisions are rejected, not auto-suffixed
- Duplicate-URL downloads select the already-added row instead of re-downloading
- Fixed a macOS 15 abort when view models deallocate (back-deployed isolated-deinit runtime bug; opted affected deinits out of MainActor isolation)

## [1.12.0] — 2026-05-31

- Apple Silicon only (`arm64`); README and docs aligned with bundled FFmpeg
- CI workflow (macOS 15, Xcode 16.4, arm64 tests)
- High-quality resampling (`filter_size=512`), triangular HP dither on final export, `-map_metadata 0`
- Skip loudnorm pass 2 on silent/near-silent sources; ffprobe audio-stream validation
- Update checker: app `v*` tag filter with GitHub fallback list
- Re-process warning for `*clipped*.wav` outputs; output-directory fallback notices
- Cancel in-flight processing on app quit
- **Zoom 48 kHz** built-in preset
- Expanded unit and FFmpeg integration tests
