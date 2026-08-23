# Changelog

All notable changes to ClipHack are documented here. Version numbers match GitHub releases (`v*` tags).

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
