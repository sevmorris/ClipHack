# Changelog

All notable changes to ClipHack are documented here. Version numbers match GitHub releases (`v*` tags).

## [Unreleased]

**Added**
- **Temporary Session, for a file that isn't for an episode.** Choose it from the session menu and downloads and processed audio go to the Desktop, with no notes file written. The window reads *Temporary Session* over *Desktop*. Your episode is left exactly as it was: the mode is held in memory, never in the saved folders, so the show folder, the episode's folders and its notes file are untouched, and ClipHack opens on the episode again after a relaunch. Choose Temporary Session again, or pick any episode, to leave. While it is on, the Destination and Output Directory controls are off, since both would change the episode's folders. ClipHack writes a test file to the Desktop as the session starts, so on a Mac where it has not yet been allowed into the Desktop, macOS asks then, naming ClipHack, instead of refusing ffmpeg or yt-dlp partway through a job.

**Fixed**
- **A download finished after switching session records its notes where its audio went.** The notes file was chosen when the download finished, so switching episode partway through filed the clip's block in the new episode's notes while its audio sat in the old one's folder. The notes file is now chosen when the download starts.

## [1.26.0] — 2026-09-24

**Changed**
- **The bundled FFmpeg is 9.0.2**, the newest line, up from 8.0.3. FFmpeg's 8.0 line has had no release since June, while 8.1 and 9.0 have had theirs in September, so the pin moves to the maintained newest line. ClipHack runs every downloaded and third-party clip through FFmpeg's file readers, so staying on a maintained line matters most here. Processing is unchanged for the clips ClipHack usually sees: a clip downloaded from Twitter came out bit-identical. The exception is AAC in MP4, MOV or M4A that FFmpeg itself wrote: 9.0 now reads the encoder delay such files record, so they decode 59 samples (1.3 ms) shorter, and the level-ridden result moves by about −70 dBFS, with loudness and true peak unchanged. Every other file processes bit-identically to 1.25.9 (322 of 340 parity checks pass; the rest are those timing differences). The source verified against FFmpeg's release signing key, the licence files are unchanged, and the build is still this project's own reproducible, LGPL, audio-only recipe, now revision r5 (`ffmpeg-deps-9.0.2-audio-arm64-r5`).

**Developer**
- `release.sh` now says when a locked screen, not a missing profile, stops notarization: the notary credentials sit in a keychain that locks with the screen.

## [1.25.9] — 2026-09-23

**Changed**
- **The bundled FFmpeg is 8.0.3**, the third point release on the 8.0 branch, up from 8.0. It carries about 500 fixes, many of them hardening the file readers a downloaded or third-party clip goes through — MOV/MP4, Matroska, WAV and AAC — against overflows, out-of-bounds reads and use-after-frees on malformed files. Processing is unchanged: run through ClipHack's real multi-pass pipeline, the new build's output is bit-identical to the old one's (340 parity gates pass, every null residual at −inf). The source verified against FFmpeg's release signing key, the licence files are unchanged, and the build is still ClipHack's own reproducible, LGPL, audio-only recipe (`ffmpeg-deps-8.0.3-audio-arm64-r4`).

## [1.25.8] — 2026-09-23

**Changed**
- **The bundled yt-dlp is updated from 2026.06.09 to 2026.08.19.** Both releases in between carry YouTube fixes, and yt-dlp only reaches ClipHack with a ClipHack release — 2026.06.09 had begun printing its own warning that it was more than 90 days old. 2026.07.04 also fixed CVE-2026-55404, a command injection through `--write-link` output; ClipHack never passes that option, so it was not exposed. The new binary's checksum file carries a good signature from yt-dlp's signing key, the same key as before, and ClipHack's own download arguments produce the same file with it as with the old one.

## [1.25.7] — 2026-09-23

**Fixed**
- **The app keeps its notarization once it is out of the disk image.** Only the DMG was stapled, so the copy dragged into Applications — the only one anyone runs — carried no ticket of its own, and Gatekeeper had to ask Apple about it on first launch, which needs a working network. The app is now notarized and stapled by itself before the image is built around it, and the release checks the ticket on the copy that ships.
- **The disk image is signed.** Only the app inside it was, so `spctl` reported the download itself as having "no usable signature" even with a valid ticket stapled to it.

**Changed**
- **The waveform scan uses Accelerate.** Each bucket's peak is found with `vDSP_maxmgv`, a vectorized maximum over a run of samples, instead of a per-sample loop over every channel. A maximum is exact, so the waveform is the same as before; the scan does less work to reach it.
- **A leaner Release build.** ClipHackKit no longer builds its Release configuration for testability — the tests run in Debug — so the shipped framework stops exporting internals only the tests needed, and the project now strips dead code.

## [1.25.6] — 2026-09-17

**Fixed**
- **Picking a session files into its clips folder, even one that arrived after the menu was built.** The session menu recorded each episode's clips folder when it built its list — at launch, or after the last switch. An episode folder made in the Finder usually gets its `clips` folder a moment later, and a session listed in between opened into the episode folder itself, so downloads and processed audio landed beside `clips` rather than in it. The folder is now looked up when you pick the session.
- **An episode folder made while ClipHack is open appears in the session menu.** It used to wait for a relaunch or a session switch. The menu is now read again whenever ClipHack comes to the front.

**Changed**
- **OUTPUT DIR and the download Destination name the session's clips folder the same way: `HT_0382 2026-09-22/clips`.** OUTPUT DIR showed just "clips", the same for every session, so switching sessions looked like it changed nothing. Destination showed only the episode, which reads as the episode folder rather than its clips folder.

## [1.25.5] — 2026-09-17

**Fixed**
- **A broken FFmpeg no longer passes itself off as a file with no audio.** Whenever the bundled ffprobe could not run — missing, unlaunchable, crashed or timed out — the file was reported as "No audio stream found — file may be misnamed or unsupported." That is how 1.17.1 through 1.25.2 described every file on macOS 26.7, where the fault was ffprobe being refused at launch, and it sent the first diagnosis after the files. Those cases now say the bundled ffprobe failed to run, give the reason, and say the file was not checked. A file ffprobe reads and finds no audio in is reported as before, without the "FFmpeg failed (-1):" prefix a failed job used to add. Cancelling a batch while a file is being probed now cancels it, instead of recording that file as having no audio.

## [1.25.4] — 2026-09-17

**Fixed**
- **The installer window is back.** The 1.25.2 and 1.25.3 disk images open as a plain folder holding only the app — no background, no layout, and no Applications shortcut to drag it onto. On the Mac they were built on, the Python that runs dmgbuild crashed on its first subprocess (it had been compiled against Xcode 27's macOS 27 SDK, on macOS 26.7), and a fallback added that day built a bare image instead while still reporting a styled one. The fallback is gone. `release.sh` now tests the interpreter before building anything, fails rather than ships an image without its layout, and checks the mounted image for it.

**Developer**
- **The bundled FFmpeg is repinned to r4: the same machine code as 1.25.3's r3, now rebuildable byte for byte.** r3 restored the `LC_UUID` load command, but its recipe could not reproduce it — the linker folds object-file timestamps into the UUID, so every rebuild differed in 48 bytes. `scripts/build-ffmpeg.sh` now sets `ZERO_AR_DATE=1`, keeping `LC_UUID` and reproducibility both, and refuses a binary without the load command. Parity against r3: 340 gates pass, every null residual at −inf.
- **`release.sh` can no longer publish half a release.** It checked only this clone's tags, so a version already tagged on GitHub passed, was built, notarized and pushed to `main`, and only then had its tag refused — which is how a second commit for 1.25.2 reached `main` with nothing tagging it. It now fetches the remote's tags first, stops when a local tag disagrees with one or the releases repo already has the version, and pushes the branch and the tag in one atomic push. The version and build-number bump is committed only after notarization and reverted on any earlier failure, where the build number used to be left in the working tree for the next run to trip over. It also checks the notarytool profile up front (`notarytool`, or `NOTARY_PROFILE`), and builds for `generic/platform=macOS`.
- Builds with Xcode 27 without warnings. Swift 6.4 flags main-actor code reached from `AudioProcessor` and from function values, and the pure helpers involved are now `nonisolated`.

## [1.25.3] — 2026-09-16

**Fixed**
- **FFmpeg runs on macOS 26.7 again.** From 1.17.1 the bundled `ffmpeg` and `ffprobe` were built without an `LC_UUID` load command — that is what made them reproducible — and dyld on macOS 26.7 refuses to load an executable without one, so processing failed there in every version from 1.17.1 through 1.25.2. The binaries are rebuilt with it (`ffmpeg-deps-8.0-audio-arm64-r3`).

## [1.25.2] — 2026-09-16

**Changed**
- **A bundled tool that is not executable is no longer run in place.** ClipHack checked only that `ffmpeg`, `ffprobe` and `yt-dlp` existed inside the app. It now requires them to be executable too, and otherwise runs a copy from its temporary folder with the permission set.

## [1.25.1] — 2026-09-13

**Changed**
- **The session's notes file records the file name, the cut and the source URL — nothing else.** The person and the notes are no longer written to it. They still go on the clip's row in the file list, and last as long as the row does.
  The file name is now written every time, including a name you typed yourself. It used to be left out as a repeat of the name just typed, but with the notes gone it is the only line saying which clip a cut belongs to. A side effect: the already-downloaded check now recognises a clip named by hand, which it could not before.
  The source URL stays because the file is matched on it — re-downloading a link replaces its block rather than adding a second, and a link whose clip is still on disk adds that clip instead of fetching it again.
  Nothing already in a file is taken out. Blocks an earlier version wrote keep their notes, including when the file is rewritten around a new download: the parser cannot always tell a free-form cut from notes, so stripping notes on the way out would take cuts with them.

## [1.25.0] — 2026-09-06

**Added**
- **Output channels can be set per clip.** Right-click a row and use *Output Channels* to put that clip on Stereo, Mono — Left or Mono — Right, or back on *Follow Settings*. It applies to the whole selection at once, and a clip that overrides the panel carries a badge beside its name.
  Channel handling was the one batch-wide setting that is really a property of the recording rather than of the run: mono output pans to the channel you name rather than downmixing, so a clip whose audio sits on the right came out silent in a batch set to Left. Getting a mixed set through meant two passes, because Process runs the whole queue rather than the selection — it is now one.
  Deliberately narrow: only channel handling can be overridden. Sample rate, ceiling, filters and loudness stay batch-wide, and a queue with no overrides behaves exactly as before. The override lives in the file list and is not written to the notes file, so it does not survive quitting.

## [1.24.1] — 2026-09-05

**Documentation**
- **The manual covers downloading, sessions and clip notes.** It had only ever documented the processing side, so the two controls furthest left in the window — the session menu and Add from URL — were the two it did not mention. Three new sections now cover the download form field by field, what switching session moves and why, and the shape of the session's notes file. The Interface section gains the two missing toolbar entries.
- **The manual is published.** GitHub Pages is enabled for the repo, serving `docs/` at [sevmorris.github.io/ClipHack/manual](https://sevmorris.github.io/ClipHack/manual/). It had been written and version-stamped by every release for months without being reachable anywhere.
- **Links to it from the README and the Help window.** Neither pointed at the manual, so finding it meant already knowing the URL.

## [1.24.0] — 2026-09-05

**Removed**
- **The clip list.** ClipHack no longer assembles a numbered list of a session's clips: the panel (⇧⌘L), the Copy List button (⇧⌘C) and the numbered export are gone. Nothing else about how a clip is recorded changes — the person, the notes, the cut and the source URL are still written to the session's notes file exactly as before, and that file is still folded together from any per-clip files an older version left behind. What is gone is only the reading side: the notes are now read in a text editor rather than in a panel.

**Fixed**
- **The app no longer claims each download gets its own folder.** That stopped being true in 1.23.1, but the download popover and the Help window still said it, and Help still described naming a download as naming "its folder". Downloads land flat in the session's folder, and the text now says so.

## [1.23.1] — 2026-08-24

**Changed**
- **Downloads land straight in the session's folder.** Each one used to be filed into a folder of its own, so that a clip's audio, its notes and whatever was rendered from it stayed together. None of that is true any more — notes moved to the session's own file, processed output goes flat beside it, and the source is trashed once processed — so the folder was left behind empty. It is no longer created.

**Fixed**
- **A clip can no longer be given another clip's audio.** yt-dlp skips rather than overwrites, so with flat filenames a download whose title matched one already in the session would silently resolve to that existing file. ClipHack checks a link against the session before downloading, so a skip at that point means a genuinely different clip sharing a title: it now stops with a message naming the file and asking for a custom name. Not reachable before, because filing each download into its own folder always left the flat name free.
- **The test suite no longer trips over itself.** Its scratch preferences suite had one fixed name while xcodebuild runs test classes in parallel processes, so one class's teardown could wipe another's settings mid-test. Keyed on the process now.

## [1.23.0] — 2026-08-24

**Changed**
- **One notes file per session, instead of one per clip.** A session keeps `HT_0379 2026-08-24/clips/HT_0379 2026-08-24.txt`, holding every clip in it, blocks separated by a `---` rule. Each block is the same shape as before — filename, entry, cut, source URL, a blank line between each — so nothing about how a clip reads has changed, only how many files it takes.
  Maintained rather than appended. ClipHack rewrites the file from what it holds, so a re-download or an edit replaces a clip's block instead of stacking a second one after it. That is why the per-clip files existed: the daily appending log this returns to grew a history that had to be pruned by hand. The name is recorded only when ClipHack chose it, exactly as before, but it now carries weight — in a shared file it is what ties a block back to a clip on disk, so the already-downloaded check works for auto-named clips and not for ones named by hand.
- **Existing per-clip files are folded in automatically** the first time a session is opened or a link is checked, in the order they were written and without duplicating a clip already recorded. The originals are left exactly where they are: they are your files, and a migration that deletes them has no undo. They are simply no longer read.

**Fixed**
- **An edit in the clip list could be written into the wrong clip.** The panel's fields were bound to a row's position, and reloading re-sorts the rows — Refresh, ⇧⌘C and switching session all reload. Typing after a reload therefore wrote into whichever clip had taken that slot, destroying what was there. Fields now follow the row itself.
- A clip dropped in from outside the session keeps its notes: the per-clip file beside it is still read when the session file has nothing for it.
- The 1.22.0 entry below was dated 2026-08-22; its tag is 2026-08-24.

## [1.22.0] — 2026-08-24

**Added**
- **A box for the cut.** The download popover takes a timestamp — `1:13 to :55` — beside the person, and writes it on its own line in the clip's notes file. It is deliberately kept out of the copied clip list, which stays one line per clip. The clip list panel shows it per row so it can be corrected later.

**Changed**
- **The notes file separates every element with a blank line**, so the source URL, the cut and the clip's entry each stand apart instead of running together.
- **A clip you name yourself no longer records its filename.** The line only repeated the name just typed. Nothing needs it to find the audio — the notes file already shares the clip's stem, which is what lookup falls back to.
- Sidecars written before this change still read correctly, and a cut sitting at the end of their notes is lifted into its own field. Files are migrated as they are edited rather than rewritten in bulk.

**Fixed**
- A clip with no recorded filename could resolve to its own folder rather than its audio, because appending an empty name lands back on the directory and that exists. Only reachable via the new hand-named form, and caught before it shipped.

## [1.21.1] — 2026-08-22

**Added**
- **The window title carries the session**, with the show folder as its subtitle — so which episode you are in is readable without opening a menu.
- **An existing setup is picked up on launch.** Before sessions, only the *output* folder pointed at an episode while downloads went to the shared default. That shape is now recognised and adopted, so upgrading lands you in the right session instead of showing a bare title bar and an empty clip list until one is chosen by hand. Deliberately narrow: only a folder actually named `clips` counts, so an unrelated output folder is never adopted.

**Fixed**
- **Choosing the episode as the show folder now resolves upward.** "Choose Show Folder…" took whatever was picked, so selecting `HT_0379 2026-08-24` rather than the show above it made the session menu list `ads`, `clips` and `recordings` as if each were an episode. A folder named like an episode, or holding a `clips` folder, is now understood as one and its parent becomes the show; a root already stored wrong is repaired on launch.
- **Episodes sort above everything else in the session menu.** A show folder also holds templates, shared assets and incoming audio, and sorting purely by name buried the episodes beneath them — `TEMPLATES` sat above `HT_0379`. Numbered episodes now come first, highest number first, with the rest following in reading order.

## [1.21.0] — 2026-08-22

**Added**
- **Saved sessions.** One episode is one folder, and the folder's name is the session title — `HT_0380 2026-08-24`. The toolbar menu lists every episode under the show folder, newest first, and switching to one points downloads, processed output, and the clip list at that episode's `clips` folder in a single move. New Session suggests the next episode number by reading the highest one already on disk and stamps today's date, then creates `<episode>/clips` and switches to it. The session name is also the window title.
  Nothing about a session is stored: it is read back from the folder path, so renaming or moving a folder in Finder cannot leave a stale record behind, and an episode folder made by hand shows up on its own. The show folder is adopted automatically the first time a session folder is chosen — it is simply the episode's parent — so there is no separate setup step.
  Pointing both the download and output folders at the episode is what makes the clip list genuinely per-episode rather than reading a scratch folder shared by every show, and it leaves an old episode still browsable months later.

**Fixed**
- **Applying a preset no longer moves the folders you chose.** `applyPreset` replaced the whole settings struct and restored only the output folder, so picking any preset silently reset the download folder back to `~/Music/ClipHack`. A preset says how audio is processed, not where files live; the download folder, the output folder and the show folder are all preserved now. Without this, switching preset would also have dropped you out of the current session.

**Developer**
- Preferences now persist through one overridable store, and the tests point it at a scratch suite. The test target builds real view models and assigns settings, which save on every change — so running the suite rewrote the real user's download and output folders. It no longer touches them.

## [1.20.0] — 2026-08-22

**Added**
- **A clip list.** Every clip in the download folder as one numbered list, ready to paste — `⇧⌘L` to edit it, `⇧⌘C` to copy it without opening anything. Lines come out as `1) TRUMP traveled to South Dakota…`: the name is capitalized on the way out, which separates it from the description without needing a dash. The notes file stores the name as typed, so a row edited later shows what you wrote rather than a shout. Rows are the clips' own notes files edited in place, not a document of their own: change a person or a description and it is written straight back to that clip's `.txt`. That keeps one source of truth, and it means the list survives everything the audio does not — a week of prep, quitting, processing, and originals being trashed — because the sidecars already outlive the files they describe. A clip whose audio is gone keeps its line, marked "audio removed". Scope comes from the download folder, so pointing ClipHack at an episode's folder makes the list that episode; there is no separate notion of a show to keep in sync.
- **A Person field in the download popover**, and a name read out of an X post's own text to fill it. Both shapes clips arrive in put the speaker first — `Trump: we're going to…` and `Trump traveled all the way to…` — so one rule covers both: the opening run of capitalized words, stopping at a colon or at the first word that isn't one, after any `BREAKING:` style marker is dropped. It abstains rather than guesses, leaving the field blank when no name reads confidently, because a wrong name looks correct and an empty field does not. The account that posted a clip is deliberately never used: aggregator accounts post most clips and are almost never the person in them.

**Changed**
- **The first line of a clip's notes is now its list entry** — `Person — what they said` — with every line below it left free for timings and scratch, exactly as before. The notes sidecar's format is unchanged and stays byte-compatible, since its body was always free text; nothing already reading those files has to change.
- The Notes box placeholder now says what its first line is for.

## [1.19.3] — 2026-08-20

**Interface**
- **A styled installer window.** The disk image now opens to a laid-out window with the app, an arrow, and the Applications folder, instead of a bare list of two icons.

**Developer**
- The ffmpeg process machinery — watchdog, capture, cancellation, and telling a crash from a cancel — is now one file shared verbatim with the sibling app repos rather than a copy in each. That is the code whose drift produced the two crashes fixed in 1.19.2: the hardening had existed in WaxOnWaxOff for months and never reached here. No behavior change; what a timeout should be and what the output means stay in ClipHack's own runner.
- The DMG tooling is likewise byte-identical across repos, and `release.sh` now refuses to publish when a shared file has diverged from its siblings.

## [1.19.2] — 2026-08-20

**Fixed**
- **Two latent crashes in the FFmpeg runner.** Terminating a process that never launched raises an Objective-C exception Swift cannot catch, and two paths could do exactly that. The watchdog was armed before the process started and was never disarmed when a launch failed, so a missing or unlaunchable ffmpeg left a timer that fired at a dead handle fifteen minutes later. Cancelling a job before its process started did the same thing immediately. Both call sites are now guarded by a flag set only once the process is genuinely running.
- **An ffmpeg crash no longer reports itself as a cancellation.** Every signal-terminated child was surfaced as `CancellationError`, so a real crash — a segfault, an out-of-memory kill — silently aborted the batch with no error shown anywhere. Crashes, timeouts and genuine user cancellations are now told apart. The distinction needs an explicit flag because FFmpeg catches SIGTERM and exits normally with code 255, so the termination reason alone cannot identify who killed the process.

**Documentation**
- **The limiter is described accurately.** 1.19.0 removed the 2× oversampling, which leaves `alimiter` running at the native sample rate — where it constrains *sample* peaks, not true peaks. Six places still promised true-peak limiting, and the theory document contradicted itself inside one section: "prevents any sample from exceeding the configured ceiling" in one paragraph, "uses `alimiter` for true peak control" two paragraphs later, directly under a heading explaining why those differ. Measured with the bundled ffmpeg on a quarter-sample-rate test tone: in at +0.41 dBTP, out at −0.14 dBTP against a −1.0 ceiling, because the limiter never engaged. No processing changed — ClipHack is a prep tool rather than a delivery step, and a fraction of a dB of overshoot on a clip headed into a mix costs nothing. Corrected in the README, the manual, the theory document, and the app's own Ceiling caption, tooltip and Help text.

## [1.19.1] — 2026-08-19

**Documentation**
- Concurrency documentation updated to describe the `cores - 1` scaling introduced in 1.19.0. No code changed.

## [1.19.0] — 2026-08-19

**Performance & Core Processing**
- **Concurrency Scaling:** Batch jobs now scale up to `cores - 1` parallel jobs. The previous 8-core hard cap artificially limited throughput on larger Apple Silicon machines.
- **Filter Graph Fusion:** When loudness normalization is enabled, the second pass (linear gain) and the true peak limiter are now combined into a single, fused FFmpeg filter graph. This eliminates an intermediate WAV file write and read, significantly speeding up the pipeline.
- **Limiter Simplification:** ClipHack now uses a standard sample-rate peak limiter instead of a 2x oversampled limiter. Since ClipHack is an edit-prep tool and does not require delivery-grade true-peak compliance, dropping the oversampling saves significant processing time.
- **Disk Space Preflight:** Reduced the temporary disk space requirements from 5x to 3x the input size to reflect the leaner processing pipeline.

## [1.18.0] — 2026-08-13

- **Trash Originals** — a new setting, on by default: once a file's processed output is written, its source file moves to the Trash. Trash rather than delete, so a result you don't like stays recoverable from the Finder. The output is confirmed on disk and non-empty before anything is moved, and a file that fails to process always keeps its original. Sources are left alone — with a notice on the run summary — when the volume has no Trash. The setting is not part of presets, so switching preset never changes what happens to your files. Note that reusing a download link whose clip has been trashed fetches it again, since "already downloaded" detection looks for the clip's audio
- Fixed the Help window showing literal `**asterisks**` around **Save Current Settings…** and **Delete Preset** instead of rendering them in bold

## [1.17.1] — 2026-08-10

- **`scripts/build-ffmpeg.sh`** — builds the pinned audio-only ffmpeg/ffprobe from SHA-256-verified upstream source (FFmpeg 8.0 + LAME 3.100), with fail-closed gates asserting the binaries execute, carry no `--enable-gpl` / `--enable-nonfree` / `--enable-version3`, link libmp3lame, have no non-system dynamic dependencies, and target the project's deployment target. ClipHack can now produce its own Corresponding Source rather than relying on a third-party build
- **The bundled FFmpeg is now built by this project.** The pin moves from mirrored WaxOnWaxOff artifacts to binaries produced by ClipHack's own `scripts/build-ffmpeg.sh`, so the Corresponding Source recipe covers exactly what ships. The build is **reproducible** — two runs on the same toolchain produce byte-identical binaries, so the pinned SHA-256 can be verified independently rather than taken on trust. Verified equivalent to the previous pin by `parity-check.sh`: 340 gates, all PASS, every null residual `-inf`
- **`scripts/parity-check.sh`** and **`scripts/parity-corpus-gen.sh`** — old-binary vs new-binary parity over a generated corpus, running the app's real multi-pass pipeline (mono extract → high-pass/all-pass → mirror-padded dynaudnorm → two-pass loudnorm → 2× oversampled limiter → dithered downsample) as separate stages, exactly as `AudioProcessor` runs it. Gates on null residual, LUFS, true peak, format, and sample count with frozen thresholds and PASS/FAIL/INCOMPLETE states, where INCOMPLETE never counts as a pass. Verified against an independently built binary: 340 gates, all PASS, every null `-inf`

## [1.17.0] — 2026-08-10

- **Switched to an audio-only LGPL FFmpeg build.** The previous pin was a third-party GPL build (OSXExperts.NET, linking x264/x265/libvidstab). Its assets were withdrawn from distribution because the exact Corresponding Source for that build could not be obtained, so the GPL obligations that come with distributing it could not be met — which also left `fetch-ffmpeg.sh` returning 404, making the project unbuildable from a clean checkout. The replacement is built from pinned, SHA-256-verified upstream source with no `--enable-gpl`, no `--enable-nonfree`, no `--enable-version3`, and no video or image libraries; libmp3lame is the only external library, and full Corresponding Source is available. Output is **bit-identical** to the old build across ClipHack's processing chain, with matching loudnorm measurements. Bundled binaries drop from 51.5 MB to 21.9 MB each
- The pinned FFmpeg binaries are now mirrored in ClipHack's own releases repo, so building no longer depends on another project's release lifecycle

- **One folder per download** — each clip now lands in its own folder named after the file (`Some Title/Some Title.m4a`) inside the download destination, so its audio, notes, and processed output stay together. A repeated title gets `-2`, `-3`, … rather than overwriting the earlier download
- **Save clip list** is now **Save clip notes** — instead of appending to a daily `clip-list-YYYY-MM-DD.txt`, each clip gets its own `Some Title.txt` beside the audio. The file body is unchanged (file name / notes / source URL), so concatenating the sidecars reproduces the old clip-list format. Existing clip lists are left alone; the preference carries over
- The download popover's **Notes** box is now resizable — drag the grip in its bottom-right corner, and the height is remembered across launches
- **Notes survive the session** — they're read back from the clip's notes file whenever it is added, so a clip re-added days later still knows what it is, and they're shown under the file name in the list (point at them for the full text)
- **Folder drops** — dropping a folder adds every audio file inside it, at any depth, so one clip folder or a whole show's worth can be added at once. Dropping the same file twice no longer doubles the row
- **Cross-session duplicate downloads** — downloading a link you already used adds the clip you have instead of fetching a second copy under a `-2` name. ClipHack reads the notes files in the destination, so it works in a new session days later; deleting a clip's audio lets the link download again

## [1.16.3] — 2026-08-04

**Developer**
- Swift 6 concurrency warnings cleared in `KitBundle` and `YtDlpService`. The project still builds in Swift 5 language mode; these were the diagnostics that become hard errors under Swift 6.
- The README was rewritten to the ASD-STE100 simplified-English standard.

## [1.16.2] — 2026-07-29

**Interface**
- The Notes field in the download popover grows with its content, from four lines up to twelve, instead of staying fixed at four.

## [1.16.1] — 2026-07-20

- Fixed file-browser rows sometimes needing repeated clicks to select (a double-click gesture on each row was intermittently swallowing single clicks)
- Rename is now right-click → Rename… or select + press Return (Finder-style); double-click no longer renames

## [1.16.0] — 2026-07-06

- **Configurable download destination** — pick any folder for downloaded audio from the "Destination" row in the Add-from-URL popover; the choice is remembered for future downloads. Defaults to ~/Music/ClipHack, so nothing changes until you choose a folder. If a chosen folder is missing at download time (moved, deleted, drive unmounted), ClipHack asks for a new one rather than silently falling back

## [1.15.2] — 2026-07-06

- X-post Notes auto-fill now triggers when you paste a link straight into the URL field (⌘V), not only when it arrives by drag-and-drop, clipboard prefill, or pressing Return
- Changing the URL to a different X post now refreshes Notes with the new post's text instead of leaving the previous post's text behind — while notes you've typed or edited yourself are still never touched

## [1.15.1] — 2026-07-05

- The **Add from URL** download popover no longer closes when you click outside it. It stays open through typing, a failed download (so the error stays visible for a retry), and idle/prefilled states — closing only on a successful download or its new Close (✕) button

## [1.15.0] — 2026-07-05

- X/Twitter post links dropped or pasted into the download popover auto-fill Notes with the post's text (best-effort; silently skipped if unavailable, and never overwrites text you've typed)

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

## [1.13.0] — 2026-06-11

**Structural**
- **Releases moved to a separate public repository.** `release.sh` now distinguishes a private source repo, which holds the tags and the code, from a public `ClipHack-releases` repo, which holds the DMG artifacts. `UpdateChecker` queries the public repo, so the in-app updater keeps working once the source repo is private.
- The Pages publication step was dropped along with the hosted manual site.

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
