# ClipHack
### Audio Clip Preparation Tool for macOS

<p align="center">
  <strong>Broadcast and Clip Normalization Tool</strong>
  <br />
  <strong>Version:</strong> 1.19.3
  <br />
  <a href="https://github.com/sevmorris/ClipHack-releases/releases/latest/download/ClipHack-v1.19.3.dmg"><strong>Download</strong></a>
</p>

ClipHack is an internal tool. It prepares third-party audio clips (for example: news, promos, and broadcast assets) to mix with other audio. It normalizes loudness and enforces peak ceilings. This makes sure that different audio sources have the same audio level in a podcast or a show.

---

## Primary Features

* **High pass filter:** The filter has three fixed cutoffs: 20 Hz (DC block), 40 Hz, or 80 Hz. The filter operates with all-pass phase rotation. This is always active.
* **Dynamic leveling:** The tool uses `dynaudnorm` for bidirectional leveling. This makes the audio level of different speakers consistent. It uses mirror padding to stop boundary artifacts.
* **Loudness normalization:** The tool does a two-pass EBU R128 normalization. You set the target level (for example, -18 LUFS).
* **Peak control:** The tool applies a brick-wall limiter at the native sample rate, holding sample peaks at the ceiling you set (from -6 dB to -1 dB).
* **Download from URL:** You can paste or drop a web link into the application. The tool downloads the audio into the file list. It uses the included yt-dlp software.

---

## Download from URL

To download audio from a web link directly into the file list, do one of these steps:
* Click the link button in the toolbar (Command + L).
* Drop a web link onto the window.

The tool saves video sources as audio only. It uses the native codec without re-encoding. The tool saves downloads in the `~/Music/ClipHack` directory.

Each download gets its own folder. The tool gives the folder the same name as the file:

```
~/Music/ClipHack/
└── Some Title/
    ├── Some Title.m4a
    └── Some Title.txt
```

Processed output goes into the same folder. Thus, all the parts of one clip stay together. If a second download has the same name, the tool makes a different folder (`Some Title-2`). The tool does not write over the first download.

* **Custom name (optional):** Type a name for the download. The tool changes the file name and the folder name before it saves the file. You can only change the name stem. The tool keeps the original file extension. If you do not type a name, the tool uses the source title.
* **Notes (optional):** Type text to keep with the file row. To make the notes box larger, drag the grip in the bottom-right corner. The tool remembers the size. If you use a link from X (Twitter), the tool automatically gets the post text and puts it in the notes. You can change or delete this text.
* **Save clip notes:** This writes the file name, notes, and source URL to a text file in the clip folder. The record shows the download at the time it occurred. If you rename a file later, the tool does not change the record. This is the correct function.

If you use a link a second time, the tool does not download the clip again. The tool reads the notes files in the destination directory. If it finds the clip, it adds the file to the list and tells you. This is also correct if you downloaded the clip on a different day. If you deleted the audio file, the tool downloads the clip again.

## Notes in the File List

The file list shows the notes below the file name. The tool reads the notes from the text file in the clip folder. Thus, the notes stay with the clip after you close the application. Point at the notes to see the full text.

You can drop a folder onto the window. The tool finds all the audio files in the folder and in the directories below it. Thus, you can drop one clip folder, or all the clip folders for a show. If you drop the same file two times, the tool does not add it two times.

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
./scripts/fetch-ffmpeg.sh   # This downloads the correct ffmpeg and ffprobe files (approximately 42 MB).
./scripts/fetch-ytdlp.sh    # This downloads the correct yt-dlp file (approximately 35 MB).
open ClipHack.xcodeproj
```

The scripts download the FFmpeg files (arm64 only) from the [ClipHack dependencies release](https://github.com/sevmorris/ClipHack-releases/releases/tag/ffmpeg-deps-8.0-audio-arm64-r2). They download the yt-dlp file from the [official yt-dlp releases](https://github.com/yt-dlp/yt-dlp/releases). The tool records the correct versions and checksums in the `Vendor/ffmpeg-manifest.env` and `Vendor/ytdlp-manifest.env` files. Xcode operates both fetch scripts before it builds the software.

To read the release history, look at the [CHANGELOG.md](CHANGELOG.md) file.

### Build the FFmpeg Binaries

The release binaries are pre-built. To build them again from source, use this command:

```bash
./scripts/build-ffmpeg.sh
```

The script downloads FFmpeg 8.0 and LAME 3.100. It verifies the SHA-256 checksum of each file. Then it builds the audio-only binaries. The script stops with an error if the result uses a GPL option, links a library that is not part of the system, or does not agree with the deployment target. This script is the Corresponding Source recipe for the included binaries.

### Check DSP Parity

Before you change the FFmpeg binaries, make sure the audio output does not change:

```bash
export CLIPHACK_PARITY_CORPUS=/path/outside/the/repo
export CLIPHACK_OLD_FFMPEG=./ClipHackKit/ffmpeg
./scripts/parity-corpus-gen.sh              # Makes the test files one time.
export CLIPHACK_NEW_FFMPEG=./build/ffmpeg-audio/ffmpeg
./scripts/parity-check.sh
```

The check operates the full processing sequence of the application through both binaries. It compares the null residual, the loudness, the true peak, the format, and the number of samples. A result is PASS, FAIL, or INCOMPLETE. An INCOMPLETE result is never a PASS. The check operates on all the test files and stops with an error if there is one FAIL or one INCOMPLETE.

## Processing Pipeline

ClipHack operates this sequence in 24-bit WAV format:
1. **Resampling:** It changes the sample rate to 44.1 kHz or 48 kHz.
2. **Channel management:** It extracts a mono signal or forces a stereo signal.
3. **High-pass filter and phase rotation:** It always applies these functions.
4. **Dynamic leveling:** It can apply bidirectional compression (this is optional).
5. **Loudness normalization:** It can apply linear gain (this is optional).
6. **Peak limiting:** It always applies this function.

---

## Technical Origin

ClipHack is a signal chain that uses FFmpeg. I designed the digital signal processing (DSP) logic and parameters for professional podcasting standards. I used AI assistance to write the Swift user interface and the process orchestration.

This software is a personal tool. It is supplied "as-is". It is not a commercial product.

---

### Included Software

ClipHack includes these programs. It does not change them.

* **FFmpeg 8.0 (arm64):** ClipHack uses FFmpeg for all audio processing. This is an audio-only build. It does not use the `--enable-gpl`, `--enable-nonfree`, or `--enable-version3` options, and it includes no video or image libraries. The only external library is libmp3lame (LAME 3.100). The FFmpeg core is supplied under the GNU Lesser General Public License v2.1 or later. LAME is supplied under the LGPL v2.0 or later. The `arnndn` filter is supplied under the BSD 2-Clause License. No GPL components are included.
  * FFmpeg source code: [ffmpeg-8.0.tar.xz](https://ffmpeg.org/releases/ffmpeg-8.0.tar.xz) ([signature](https://ffmpeg.org/releases/ffmpeg-8.0.tar.xz.asc))
  * LAME source code: [lame-3.100.tar.gz](https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz)
  * Build recipe: `scripts/build-ffmpeg.sh` in this repository. It rebuilds the shipped binaries byte for byte, so the checksums in `Vendor/ffmpeg-manifest.env` are independently verifiable. To see the build configuration of the included binary, run `ffmpeg -version`.
* **yt-dlp 2026.06.09 (universal2):** ClipHack uses yt-dlp to download audio from web links. It is public domain software (the Unlicense). Get the yt-dlp source code from [yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp).

---

### License

Copyright © 2026 Seven Morris.
This software is distributed under the [GNU General Public License v3.0](LICENSE).
