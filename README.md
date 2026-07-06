# ClipHack
### Audio Clip Prep Utility for macOS

<p align="center">
  <strong>Broadcast & Clip Normalization Utility</strong>
  <br />
  <strong>Version:</strong> 1.16.0
  <br />
  <a href="https://github.com/sevmorris/ClipHack-releases/releases/latest/download/ClipHack-v1.16.0.dmg"><strong>Download</strong></a>
</p>

**ClipHack** is an internal utility designed to prepare third-party audio clips (news, promos, broadcast assets) for seamless integration into a mix. It focuses on normalizing loudness and enforcing peak ceilings so that disparate sources sit at a consistent level within a podcast or show.

---

## Core Features
* **High Pass Filter:** Three fixed cutoffs — DC block (20 Hz), 40 Hz, or 80 Hz — paired with allpass phase rotation (always active).
* **Dynamic Leveling:** Intelligent bidirectional leveling via `dynaudnorm` to tame inconsistent speakers or wildly dynamic clips. Includes mirror padding to prevent boundary artifacts.
* **Loudness Normalization:** Two-pass EBU R128 normalization to a user-defined target (e.g., -18 LUFS).
* **Peak Control:** 2× oversampled true peak brick-wall limiting with a configurable ceiling (-6 to -1 dB).
* **Download from URL:** Paste or drop a web link to pull a clip's audio straight into the file list via bundled yt-dlp.

---

## Download from URL
Click the link button in the toolbar (⌘L), or drop a web link onto the window, to download a clip's audio directly into the file list. Video sources are saved as **audio only** (native codec, no re-encode). Downloads land in `~/Music/ClipHack`.

* **Custom name:** Optional — names the download before it lands. Stem only; the extension always matches the source audio. Leave blank to keep the source title.
* **Notes:** Optional free text kept with the file row. For X/Twitter post links, the post's text is fetched and pre-filled here automatically (best-effort; edit or clear it as you like).
* **Save clip list:** Appends file name, notes, and source URL to a daily `clip-list-YYYY-MM-DD.txt` next to the download. Entries are a point-in-time log: renaming a file afterwards does **not** rewrite earlier entries (accepted behavior, not a bug).

Any row in the file list — dropped or downloaded — can be renamed via right-click → **Rename…** or by double-clicking it. The file is renamed on disk; only the name stem is editable, the extension is fixed.

yt-dlp is bundled and pinned per release, the same way FFmpeg is — no Homebrew or other external installation is required.

---

## Technical Specifications
* **Loudness Measurement:** Full ITU-R BS.1770 gated loudness monitoring per file.
* **Signal Monitoring:** Separate L/R waveform display for stereo files and noise floor detection warnings.
* **Boundary Integrity:** Custom mirror-padding logic for Dynamic Leveling prevents gain ramps at file start/end.
* **Batch Processing:** Parallel file processing with independent progress tracking.
* **Environment:** macOS 14.0+ (Sonoma) on **Apple Silicon** (arm64).
* **Dependencies:** Bundled arm64 FFmpeg 8.0 and yt-dlp (official universal2 standalone); no external installation required.

> **Security:** App Sandbox is disabled so ClipHack can run bundled `ffmpeg`/`ffprobe`/`yt-dlp`. Download builds from [official releases](https://github.com/sevmorris/ClipHack-releases/releases) only.

## Building from Source

```bash
git clone https://github.com/sevmorris/ClipHack.git
cd ClipHack
./scripts/fetch-ffmpeg.sh   # downloads pinned ffmpeg/ffprobe (~100 MB)
./scripts/fetch-ytdlp.sh    # downloads pinned yt-dlp (~35 MB)
open ClipHack.xcodeproj
```

FFmpeg binaries (arm64 only) are fetched from the shared [WaxOnWaxOff deps release](https://github.com/sevmorris/WaxOnWaxOff/releases/tag/ffmpeg-deps-8.0-arm64); yt-dlp comes from its [official releases](https://github.com/yt-dlp/yt-dlp/releases) (version pinned in `Vendor/ytdlp-manifest.env`). Xcode runs both fetch scripts before each build.

See [CHANGELOG.md](CHANGELOG.md) for release history.

## Processing Pipeline
ClipHack executes the following signal chain in 24-bit WAV format:
1.  **Resampling** to target rate (44.1 kHz or 48 kHz).
2.  **Channel Management** (Mono extraction or forced Stereo upmixing).
3.  **High-Pass + Phase Rotation** (always applied).
4.  **Dynamic Leveling** (optional bidirectional compression).
5.  **Loudness Normalization** (optional linear gain).
6.  **True Peak Limiting** (always applied).

---

## Technical Origin
ClipHack is an expert-driven signal chain built on FFmpeg. I designed the DSP logic and parameters based on professional podcasting standards, and used AI assistance to implement the Swift UI and process orchestration. 

This is a personal toolset provided "as-is." It is designed for utility and precision, not as a commercial product.

---

### License
Copyright © 2026 Seven Morris.
Distributed under the [GNU General Public License v3.0](LICENSE).
