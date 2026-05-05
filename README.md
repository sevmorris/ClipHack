# ClipHack
### Audio Clip Prep Utility for macOS

<p align="center">
  <strong>Broadcast & Clip Normalization Utility</strong>
  <br />
  <strong>Version:</strong> 1.8.3
  <br />
  <a href="https://github.com/sevmorris/ClipHack/releases/latest/download/ClipHack-v1.9.7.dmg"><strong>Download</strong></a>
  ·
  <a href="https://sevmorris.github.io/ClipHack/manual/">Manual</a>
  ·
  <a href="https://sevmorris.github.io/ClipHack/manual/theory.html">Theory of Operation</a>
</p>

**ClipHack** is an internal utility designed to prepare third-party audio clips (news, promos, broadcast assets) for seamless integration into a mix. It focuses on leveling dynamics, normalizing loudness, and enforcing peak ceilings so that disparate sources sit at a consistent level within a podcast or show.

This tool was built to solve the specific challenge of "taming" unpredictable broadcast audio. While developed for personal use, it is made publicly available for others who need a reliable, automated pipeline for clip preparation.

---

## Core Features
* **High Pass Filter:** Configurable cutoff (20–90 Hz) paired with allpass phase rotation (always active).
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
2.  **Channel Management** (Mono extraction or forced Stereo upmixing).
3.  **High-Pass + Phase Rotation** (always applied).
4.  **Dynamic Leveling** (optional).
5.  **Loudness Normalization** (optional).
6.  **True Peak Limiting** (always applied).

---

## Technical Origin
ClipHack is an expert-driven signal chain built on FFmpeg. I designed the DSP logic and parameters based on professional podcasting standards, and used AI assistance to implement the Swift UI and process orchestration. 

This is a personal toolset provided "as-is." It is designed for utility and precision, not as a commercial product.

---

### License
Copyright © 2026 Seven Morris.
Distributed under the [GNU General Public License v3.0](LICENSE).
