# ClipHack
### Audio Clip Preparation Tool for macOS

<p align="center">
  <strong>Broadcast and Clip Normalization Tool</strong>
  <br />
  <strong>Version:</strong> 1.32.0
  <br />
  <a href="https://github.com/sevmorris/ClipHack-releases/releases/latest/download/ClipHack-v1.32.0.dmg"><strong>Download</strong></a>
  &nbsp;&middot;&nbsp;
  <a href="https://sevmorris.github.io/ClipHack/manual/"><strong>Manual</strong></a>
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

The tool saves video sources as audio only. It uses the native codec without re-encoding. The tool saves downloads in the `clips` folder of the newest episode (see [Sessions](#sessions)). If no show folder is set, the tool saves downloads in the `~/Music/ClipHack` directory.

Downloads go straight into the session's folder. The tool does not make a folder for each clip:

```
HT_0379 2026-08-24/clips/
├── Some Title 1.13 to .55.m4a          ← the download, with its cut
├── Some Title 1.13 to .55-44knorm-clipped-1dB.wav  ← the processed clip, with its cut
└── HT_0379 2026-08-24.txt              ← the session's notes file
```

If a clip with the same name is already there, the tool stops and tells you. Type a custom name and download the clip again. The tool never writes over a clip you already have.

* **Custom name (optional):** Type a name for the download. The tool changes the file name before it saves the file. You can only change the name stem. The tool keeps the original file extension. If you do not type a name, the tool uses the source title.
* **The cut (optional):** Type the part of the clip you want, for example `1:13 to :55` or `:18 to end`. The tool adds the cut to the end of the downloaded file's name. A file name cannot contain a colon, thus the tool writes each colon as a period: `Some Title 1.13 to .55.m4a`. When you process the clip, the processed file keeps the cut in its name: `Some Title 1.13 to .55-44knorm-clipped-1dB.wav`. Thus you can read the cut from the name when you make it. The show's clip skill does not put the cut in the name that it files the clip under. The tool also writes the cut, with its colons, in the session's [notes file](#the-notes-file).
### The notes file

The tool keeps its own record of the episode's clips in one text file:

```
HT_0379 2026-08-24/clips/HT_0379 2026-08-24.txt
```

For each download, the tool writes the file name, the cut if you typed one, and the source link. For a file that you add from your disk, the tool writes the file name and the cut only when you set a cut. You do not need to open this file. The tool uses it for two things:

* To recognise a link that you use a second time (see below).
* To give a clip its cut when you add it to the list again.

The tool does not append to this file. The tool writes the file again from what it holds. Thus a second download of the same link replaces that clip's block. In a temporary session, the tool does not write a notes file.

If you use a link a second time, the tool reads the session's notes file. If the clip's file is still in the folder with the name that it had when you downloaded it, the tool adds that file to the list and tells you. It does not download the clip again. If the file is not there now, the tool tells you and asks. For example, you processed the clip and the original went to the Trash, or the clip skill renamed the clip and moved it. To download the clip again, select **Download Again**.

The yt-dlp software is included with each release. You do not need Homebrew or other external software.

## Per-Clip Output Channels

The settings panel applies to every file in the queue. Channel handling is the exception: one clip can override it.

Right-click a row and open **Output Channels**:

* **Follow Settings** — use the settings panel. This is the default.
* **Stereo** — this clip only.
* **Mono — Left** / **Mono — Right** — this clip only.

The choice applies to every selected row, so you can mark several clips at once. A clip that overrides the panel shows a badge beside its name.

This matters because mono output takes the channel you name; it does not downmix. If a clip's audio sits on the right, a Left setting gives you silence. Which channel carries the audio is a fact about that recording, so it belongs on the clip.

Only channel handling works this way. Sample rate, ceiling, filters, and loudness are the same for the whole batch. Process runs the whole queue, not your selection, so this is what lets a mixed batch go through in one pass.

The override lives in the file list for the current session. It is not written to the notes file, so it does not survive quitting the application.

## The File List

You can drop a folder onto the window. The tool finds all the audio files in the folder and in the directories below it, but not in an `orig` folder (see below). Thus, you can drop one clip folder, or all the clip folders for a show. If you drop the same file two times, the tool does not add it two times.

When the tool processes a clip, it also saves an uncut copy of the processed file in an `orig` folder next to it. The copy has the same name. Thus, if you must do a cut again, you can start from the copy. To add a copy to the list, drop the `orig` folder onto the window. The tool does not write over a copy that is already there. It gives the new copy a ` (1)` name. The show's clip skill does not process the copies. When it files a clip, it gives the clip's copy the same new name, and keeps the cut in brackets: `13 - TRUMP - know more about inflation [1.13 to .55].wav`. In a temporary session, the tool does not save copies.

To rename a file in the list, do one of these steps:
* Right-click the row and select **Rename…**.
* Select the row and push **Return**.

The tool renames the file on your disk. You can only change the name stem. The file extension does not change.

To record the cut of a clip, right-click the row and select **Set Cut…**. Type the part of the clip that you want, for example `1:13 to :55` or `:18 to end`. The tool renames the file on your disk: the cut goes on the end of the file name, with a period for each colon. The tool also writes the cut in the notes file. The row shows the cut below the file name. When you process the clip, the processed file keeps the cut in its name. To change the cut, select **Change Cut…**. The new cut replaces the old cut in the file name. To remove the cut, select **Change Cut…** and delete the text. You can use **Set Cut…** for a downloaded clip too. You cannot set a cut while the tool analyzes or processes the clip. In a temporary session, the tool puts the cut in the file name only.

## Sessions

One episode is one folder. The folder's name is the session title:

```
~/Desktop/Hacks on Tap/          ← the show folder
├── HT_0378 2026-08-18/
├── HT_0379 2026-08-24/
│   └── clips/                   ← downloads, notes files, and processed audio
└── HT_0380 2026-08-31/
```

The tool does not make these folders. The weekly prep makes each episode folder and its `clips` folder.

The tool always uses the newest episode: the episode with the highest number in the show folder. The tool points the download folder and the output folder at that episode's `clips` folder. The tool looks for the newest episode when it starts, each time that you go back to it, and before each download. Thus, when the prep makes the next episode, the tool uses it. You do not select it. The current session is the window title.

The session menu shows the current episode. It also has these items:

* **Temporary Session:** For a file that is not for an episode. Downloads and processed audio go to the Desktop. The tool does not write a notes file.
* **Choose Show Folder:** Sets the folder that holds your episode folders. If no show folder is set, the tool uses the folder above the episode that it used last. If you pick an episode folder by mistake, the tool uses the folder above it.

The show folder usually holds other folders too, for example templates and shared audio. The tool uses only the numbered episodes.

---

## Technical Specifications

* **Loudness measurement:** The tool monitors loudness for each file with the ITU-R BS.1770 standard.
* **Signal monitoring:** The tool shows separate Left and Right waveforms for stereo files. It gives warnings for noise floor detection.
* **Boundary integrity:** The tool uses custom mirror-padding logic for dynamic leveling. This stops gain changes at the start and the end of the file.
* **Batch processing:** The tool processes multiple files at the same time. It tracks the progress for each file independently.
* **Environment:** You must use macOS 15.0 (Sequoia) or newer on an Apple Silicon (arm64) processor.
* **Dependencies:** The tool includes FFmpeg 9.0.2 (arm64) and yt-dlp (universal2). You do not need to install external software.

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

The scripts download the FFmpeg files (arm64 only) from the [ClipHack dependencies release](https://github.com/sevmorris/ClipHack-releases/releases/tag/ffmpeg-deps-9.0.2-audio-arm64-r5). They download the yt-dlp file from the [official yt-dlp releases](https://github.com/yt-dlp/yt-dlp/releases). The tool records the correct versions and checksums in the `Vendor/ffmpeg-manifest.env` and `Vendor/ytdlp-manifest.env` files. Xcode operates both fetch scripts before it builds the software.

To read the release history, look at the [CHANGELOG.md](CHANGELOG.md) file.

### Build the FFmpeg Binaries

The release binaries are pre-built. To build them again from source, use this command:

```bash
./scripts/build-ffmpeg.sh
```

The script downloads FFmpeg 9.0.2 and LAME 4.0. It verifies the SHA-256 checksum of each file. Then it builds the audio-only binaries. The script stops with an error if the result uses a GPL option, links a library that is not part of the system, or does not agree with the deployment target. This script is the Corresponding Source recipe for the included binaries.

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

* **FFmpeg 9.0.2 (arm64):** ClipHack uses FFmpeg for all audio processing. This is an audio-only build. It does not use the `--enable-gpl`, `--enable-nonfree`, or `--enable-version3` options, and it includes no video or image libraries. The only external library is libmp3lame (LAME 4.0). The FFmpeg core is supplied under the GNU Lesser General Public License v2.1 or later. LAME is supplied under the LGPL v2.0 or later. The `arnndn` filter is supplied under the BSD 2-Clause License. No GPL components are included.
  * FFmpeg source code: [ffmpeg-9.0.2.tar.xz](https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz) ([signature](https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz.asc))
  * LAME source code: [lame-4.0.tar.gz](https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz)
  * Build recipe: `scripts/build-ffmpeg.sh` in this repository. It rebuilds the shipped binaries byte for byte, so the checksums in `Vendor/ffmpeg-manifest.env` are independently verifiable. To see the build configuration of the included binary, run `ffmpeg -version`.
* **yt-dlp 2026.10.21 (universal2):** ClipHack uses yt-dlp to download audio from web links. It is public domain software (the Unlicense). Get the yt-dlp source code from [yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp).

---

### License

Copyright © 2026 Seven Morris.
This software is distributed under the [GNU General Public License v3.0](LICENSE).
