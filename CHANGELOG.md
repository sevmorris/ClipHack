# Changelog

All notable changes to ClipHack are documented here. Version numbers match GitHub releases (`v*` tags).

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
