#!/usr/bin/env bash
# fetch-ytdlp.sh — Download pinned yt-dlp into ClipHackKit/ for bundling.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$PROJECT_DIR/Vendor/ytdlp-manifest.env"
DEST_DIR="$PROJECT_DIR/ClipHackKit"

if [[ ! -f "$MANIFEST" ]]; then
    echo "Missing manifest: $MANIFEST" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$MANIFEST"

YTDLP_PATH="$DEST_DIR/yt-dlp"

sha256_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

verify_binary() {
    [[ -f "$YTDLP_PATH" ]] || return 1
    [[ "$(sha256_file "$YTDLP_PATH")" == "$YTDLP_SHA256" ]] || return 1
    return 0
}

if verify_binary; then
    chmod 755 "$YTDLP_PATH" 2>/dev/null || true
    exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to download the yt-dlp binary." >&2
    exit 1
fi

BASE_URL="${YTDLP_BASE_URL:-https://github.com/${YTDLP_REPO}/releases/download/${YTDLP_TAG}}"
mkdir -p "$DEST_DIR"

TMP="$(mktemp "${TMPDIR:-/tmp}/cliphack-yt-dlp.XXXXXX")"

if ! curl -fL --retry 3 --retry-delay 2 -o "$TMP" "${BASE_URL}/${YTDLP_ASSET}"; then
    rm -f "$TMP"
    echo "Failed to download ${YTDLP_ASSET} from ${BASE_URL}/${YTDLP_ASSET}" >&2
    exit 1
fi

GOT="$(sha256_file "$TMP")"
if [[ "$GOT" != "$YTDLP_SHA256" ]]; then
    rm -f "$TMP"
    echo "Checksum mismatch for ${YTDLP_ASSET}" >&2
    exit 1
fi

mv "$TMP" "$YTDLP_PATH"
chmod 755 "$YTDLP_PATH"

echo "Fetched yt-dlp ${YTDLP_VERSION}"
