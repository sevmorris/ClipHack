**Clip Prep for macOS**

[ClipHack](https://sevmorris.github.io/ClipHack/) prepares audio clips for use in a mix — leveling dynamics, normalizing loudness, and brick-wall limiting peaks. It's designed for broadcast clips (news, promos) that need to sit at a consistent level before dropping into a podcast or show. For your own raw recordings before editing, use [WaxOn](https://sevmorris.github.io/WaxOnWaxOff/).

## Download

**[ClipHack v1.4.1 (DMG)](https://github.com/sevmorris/ClipHack/releases/latest/download/ClipHack-v1.4.1.dmg)** · **[Manual](https://sevmorris.github.io/ClipHack/manual/)**

> ⚠️ **Important — Read Before First Launch**
>
> macOS will block the app with a malware warning because it is not notarized with Apple. After mounting the DMG and dragging ClipHack to Applications, **you must run this command in Terminal:**
>
> ```
> xattr -cr /Applications/ClipHack.app
> ```
>
> Without this step, macOS will refuse to open the app.

## Features

- **Noise Reduction**: RNNoise neural network model (arnndn) — removes broadband background noise (hiss, room tone, HVAC). Applied per-channel on stereo files.
- **Level Audio**: Dynamic leveling via FFmpeg's dynaudnorm — evens out level variation across a clip without compressor pumping. Designed for broadcast sources, not dialog.
- **Loudness Norm**: Two-pass EBU R128 loudness normalization to a target LUFS. Runs before the limiter.
- **Brick-Wall Limiting**: Configurable ceiling (-6 to -1 dB) with 2× oversampled true peak limiting
- **Stereo Output**: Optionally force stereo output (upmixes mono sources)
- **LUFS Measurement**: Full ITU-R BS.1770 gated loudness displayed per file
- **Noise Floor Detection**: Warns when high noise floor may affect level accuracy
- **Stereo Waveform**: L/R channels displayed separately for stereo files
- **Batch Processing**: Process multiple files in parallel with per-file progress
- **Drag & Drop**: Drop audio files onto the window to process
- **Custom Output Directory**: Optionally set a dedicated output folder
- **Update Checker**: Checks for new releases on launch and via Help menu

## System Requirements

- macOS 14.0 (Sonoma) or later

## Output Naming

Output filenames reflect what processing was applied:

```
{original-name}-{rate}{nr-}{leveled-}{norm-}clipped-{limit}dB.wav
```

Examples:
```
clip-44kclipped-1dB.wav
clip-44knr-leveled-norm-clipped-1dB.wav
```

## Settings

- **Sample Rate**: Output sample rate — 44.1 kHz or 48 kHz
- **Stereo Output**: Force stereo output; upmixes mono sources
- **Ceiling**: Brick-wall limiter ceiling, from -6 dB to -1 dB
- **Noise Reduction**: Enable RNNoise neural network noise reduction
- **Level Audio**: Enable dynamic leveling (dynaudnorm)
- **Aggressiveness**: Controls leveler responsiveness — frame size, Gaussian smoothing, and max gain scale together from Gentle to Aggressive
- **Loudness Norm**: Enable two-pass EBU R128 loudness normalization
- **Target**: Normalization target in LUFS (-30 to -14). -16 LUFS is a common podcast insertion target.
- **Output Directory**: Custom output folder (default: same as source file)

## Processing Pipeline

ClipHack uses FFmpeg. Each stage is optional except the final limiter:

1. **Resample** to the target sample rate (skipped if already matching)
2. **Noise Reduction** — RNNoise neural network model via arnndn (optional)
3. **Level Audio** — dynaudnorm dynamic normalization (optional)
4. **Loudness Norm** — two-pass EBU R128 normalization (optional)
5. **Brick-wall limiting** with 2× oversampled true peak control

Output format: 24-bit WAV

## Building

```bash
xcodebuild -project ClipHack.xcodeproj -scheme ClipHack -configuration Release
```

## License

Copyright © 2026. This app was designed and directed by Seven Morris, with code primarily generated through AI collaboration using [OpenClaw](https://openclaw.ai) and Claude (Anthropic).

This program is free software: you can redistribute it and/or modify it under the terms of the [GNU General Public License v3.0](LICENSE).

## A Note on AI

I'm a freelance audio engineer, not a software developer. These tools exist because AI made it possible for me to build things I couldn't build alone. It's exciting, but complicated.

AI-assisted development raises real questions about labor displacement, resource consumption, and the concentration of power in a handful of tech companies. I don't have clean answers. I do think it matters that the people using these tools are honest about the trade-offs rather than pretending they don't exist.
