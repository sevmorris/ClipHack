<p align="center">
  <img src="assets/header.png" alt="WavShaver">
</p>


**Brick-Wall Limiter for macOS**

WavShaver shaves peaks off audio files. Set your ceiling, drop your files, get limited WAV out. That's it.

## Design Philosophy

WavShaver is intentionally minimal. It does one thing — applies brick-wall peak limiting — and gets out of the way. No filtering, no normalization, no encoding. Just a limiter.

## Download

**[WavShaver v1.0 (DMG)](https://github.com/sevmorris/WavShaver/releases/latest/download/WavShaver-v1.0.dmg)**

> ⚠️ **Important — Read Before First Launch**
>
> macOS will block the app with a malware warning because it is not notarized with Apple. After mounting the DMG and dragging WavShaver to Applications, **you must run this command in Terminal:**
>
> ```
> xattr -cr /Applications/WavShaver.app
> ```
>
> Without this step, macOS will refuse to open the app.

## Features

- **Brick-Wall Limiting**: Configurable ceiling (-6 to -1 dB) with 2x oversampled true peak limiting
- **Channel Passthrough**: Preserves original channel layout (mono in = mono out, stereo in = stereo out)
- **Sample Rate Conversion**: 44.1 kHz or 48 kHz output
- **Drag & Drop**: Drop audio files onto the window to process
- **Batch Processing**: Process multiple files in parallel with per-file progress
- **Waveform Preview**: Select a file to view its waveform with dB scale
- **Custom Output Directory**: Optionally set a dedicated output folder

## System Requirements

- macOS 14.0 (Sonoma) or later

## Output Naming

```
{original-name}-{samplerate}shaved-{limit}dB.wav
```

Example: `episode-01-44kshaved-1dB.wav`

## Settings

- **Sample Rate**: Output sample rate — 44.1 kHz or 48 kHz
- **Ceiling**: Brick-wall limiter ceiling, from -6 dB to -1 dB
- **Output Directory**: Custom output folder (default: same as source file)

## Processing Pipeline

WavShaver uses FFmpeg with a simple pipeline:

1. **Resampling** to the target sample rate (skipped if already matching)
2. **Brick-wall limiting** with 2x oversampled true peak control

Output format: 24-bit WAV

## Building

```bash
xcodebuild -project WavShaver.xcodeproj -scheme WavShaver -configuration Release
```

## License

Copyright © 2026. This app was designed and directed by Seven Morris, with code primarily generated through AI collaboration using [OpenClaw](https://openclaw.ai) and Claude (Anthropic).

This program is free software: you can redistribute it and/or modify it under the terms of the [GNU General Public License v3.0](LICENSE).
