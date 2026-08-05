# ClipHack
### Audio Clip Preparation Tool for macOS

<p align="center">
  <strong>Broadcast and Clip Normalization Tool</strong>
  <br />
  <strong>Version:</strong> 1.16.3
  <br />
  <a href="https://github.com/sevmorris/ClipHack-releases/releases/latest/download/ClipHack-v1.16.3.dmg"><strong>Download</strong></a>
</p>

ClipHack is an internal tool. It prepares third-party audio clips (for example: news, promos, and broadcast assets) to mix with other audio. It normalizes loudness and enforces peak ceilings. This makes sure that different audio sources have the same audio level in a podcast or a show.

---

## Primary Features

* **High pass filter:** The filter has three fixed cutoffs: 20 Hz (DC block), 40 Hz, or 80 Hz. The filter operates with all-pass phase rotation. This is always active.
* **Dynamic leveling:** The tool uses `dynaudnorm` for bidirectional leveling. This makes the audio level of different speakers consistent. It uses mirror padding to stop boundary artifacts.
* **Loudness normalization:** The tool does a two-pass EBU R128 normalization. You set the target level (for example, -18 LUFS).
* **Peak control:** The tool does a 2x oversampled true peak brick-wall limit. You set the maximum limit (from -6 dB to -1 dB).
* **Download from URL:** You can paste or drop a web link into the application. The tool downloads the audio into the file list. It uses the included yt-dlp software.

---

## Download from URL

To download audio from a web link directly into the file list, do one of these steps:
* Click the link button in the toolbar (Command + L).
* Drop a web link onto the window.

The tool saves video sources as audio only. It uses the native codec without re-encoding. The tool saves downloads in the `~/Music/ClipHack` directory.

* **Custom name (optional):** Type a name for the download. The tool changes the file name before it saves the file. You can only change the name stem. The tool keeps the original file extension. If you do not type a name, the tool uses the source title.
* **Notes (optional):** Type text to keep with the file row. If you use a link from X (Twitter), the tool automatically gets the post text and puts it in the notes. You can change or delete this text.
* **Save clip list:** This adds the file name, notes, and source URL to a daily text file (`clip-list-YYYY-MM-DD.txt`). This file is in the same directory as the download. The entries are a permanent record. If you rename a file later, the tool does not change the old record. This is the correct function.

To rename a file in the list, do one of these steps:
* Right-click the row and select **Rename…**.
* Select the row and push **Return**.

The tool renames the file on your disk. You can only change the name stem. The file extension does not change.

The yt-dlp software is included with each release. You do not need Homebrew or other external software.

---

## Technical Specifications

* **Loudness measurement:** The tool monitors loudness for each file with the ITU-R BS.1770 standard.
* **Signal monitoring:** The tool shows separate Left and Right waveforms for stereo files. It gives warnings for noise floor detection.
* **Boundary integrity:** The tool uses custom mirror-padding logic for dynamic leveling. This stops gain changes at the start and the end of the file.
* **Batch processing:** The tool processes multiple files at the same time. It tracks the progress for each file independently.
* **Environment:** You must use macOS 14.0 (Sonoma) or newer on an Apple Silicon (arm64) processor.
* **Dependencies:** The tool includes FFmpeg 8.0 (arm64) and yt-dlp (universal2). You do not need to install external software.

> **Security warning:** The App Sandbox is disabled. This lets ClipHack operate the included `ffmpeg`, `ffprobe`, and `yt-dlp` files. Only download the software from the [official releases](https://github.com/sevmorris/ClipHack-releases/releases) page.

## Build from Source

To build the software from source code, run these commands in your terminal:

```bash
git clone https://github.com/sevmorris/ClipHack.git
cd ClipHack
./scripts/fetch-ffmpeg.sh   # This downloads the correct ffmpeg and ffprobe files (approximately 100 MB).
./scripts/fetch-ytdlp.sh    # This downloads the correct yt-dlp file (approximately 35 MB).
open ClipHack.xcodeproj
```

The scripts download the FFmpeg files (arm64 only) from the [WaxOnWaxOff dependencies release](https://github.com/sevmorris/WaxOnWaxOff/releases/tag/ffmpeg-deps-8.0-arm64). They download the yt-dlp file from the [official yt-dlp releases](https://github.com/yt-dlp/yt-dlp/releases). The tool records the correct yt-dlp version in the `Vendor/ytdlp-manifest.env` file. Xcode operates both fetch scripts before it builds the software.

To read the release history, look at the [CHANGELOG.md](CHANGELOG.md) file.

## Processing Pipeline

ClipHack operates this sequence in 24-bit WAV format:
1. **Resampling:** It changes the sample rate to 44.1 kHz or 48 kHz.
2. **Channel management:** It extracts a mono signal or forces a stereo signal.
3. **High-pass filter and phase rotation:** It always applies these functions.
4. **Dynamic leveling:** It can apply bidirectional compression (this is optional).
5. **Loudness normalization:** It can apply linear gain (this is optional).
6. **True peak limiting:** It always applies this function.

---

## Technical Origin

ClipHack is a signal chain that uses FFmpeg. I designed the digital signal processing (DSP) logic and parameters for professional podcasting standards. I used AI assistance to write the Swift user interface and the process orchestration.

This software is a personal tool. It is supplied "as-is". It is not a commercial product.

---

### License

Copyright © 2026 Seven Morris.
This software is distributed under the [GNU General Public License v3.0](LICENSE).
