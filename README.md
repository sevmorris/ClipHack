# ClipHack
### Audio Clip Prep Utility for macOS

<p align="center">
  <strong>Broadcast & Clip Normalization Utility</strong>
  <br />
  <strong>Version:</strong> 1.8.3
  <br />
  <a href="https://github.com/sevmorris/ClipHack/releases/latest/download/ClipHack-v1.8.11.dmg"><strong>Download</strong></a>
  ·
  <a href="https://sevmorris.github.io/ClipHack/manual/">Manual</a>
  ·
  <a href="https://sevmorris.github.io/ClipHack/manual/theory.html">Theory of Operation</a>
</p>

**ClipHack** is an internal utility designed to prepare third-party audio clips (news, promos, broadcast assets) for seamless integration into a mix. It focuses on leveling dynamics, normalizing loudness, and enforcing peak ceilings so that disparate sources sit at a consistent level within a podcast or show.

This tool was built to solve the specific challenge of "taming" unpredictable broadcast audio. While developed for personal use, it is made publicly available for others who need a reliable, automated pipeline for clip preparation.

---

> [!CAUTION]
> **Manual Authorization Required**
> macOS will block execution because this utility is not notarized. To authorize:
> 1. Move `ClipHack.app` to your `/Applications` folder.
> 2. Run the following command in Terminal:
>    `xattr -cr /Applications/ClipHack.app`

---

## Core Features
* **Noise Reduction:** Optional RNNoise neural network model for removing broadband background hiss and room tone.
* **High Pass Filter:** Configurable cutoff (20–90 Hz) paired with allpass phase rotation (always active).
* **De-esser:** Gentle sibilance reduction at ~7.5 kHz, optimized for voice content and codec-compressed sources.
* **Dynamic Leveling:** Uses `dynaudnorm` to even out volume variations without the "pumping" artifacts of standard compression.
* **Loudness Normalization:** Two-pass EBU R128 normalization to a user-defined target (e.g., -18 LUFS).
* **Peak Control:** 2× oversampled true peak brick-wall limiting with a configurable ceiling (-6 to -1 dB).

---

## Technical Specifications
* **Loudness Measurement:** Full ITU-R BS.1770 gated loudness monitoring per file.
* **Signal Monitoring:** Separate L/R waveform display for stereo files and noise floor detection warnings.
* **Batch Processing:** Parallel file processing with independent progress tracking.
* **Environment:** macOS 14.0+ (Sonoma); Native Apple Silicon and Intel support.
* **Dependencies:** Bundled FFmpeg; no external installation required.

## Processing Pipeline
ClipHack executes the following signal chain in 24-bit WAV format:
1.  **Resampling** to target rate (44.1 kHz or 48 kHz).
2.  **Noise Reduction** (optional).
3.  **Channel Management** (Mono extraction or forced Stereo upmixing).
4.  **High-Pass + Phase Rotation** (always applied).
5.  **De-esser** (optional).
6.  **Dynamic Leveling** (optional).
7.  **Loudness Normalization** (optional).
8.  **True Peak Limiting** (always applied).

---

## Technical Origin
This utility is the result of a **Human-AI Collaboration**. 

I am an audio engineer, not a developer; these tools are built using AI-assisted coding to bridge that technical gap. I act as the **Architect and Executive Producer**, defining the audio signal chains and logic, while the code is generated through iterative stress-testing with Large Language Models. 

This is a personal toolset provided "as-is." It is designed for utility and precision, not as a commercial product.

---

### License
Copyright © 2026 Seven Morris.
Distributed under the [GNU General Public License v3.0](LICENSE).
