# Changelog

All notable changes to ClipHack are documented here. Version numbers match GitHub releases (`v*` tags).

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
