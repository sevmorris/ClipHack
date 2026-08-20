# Deferred items

Things noticed and deliberately not acted on, with enough context to pick them
up cold. Mirrors the same file in WaxOnWaxOff.

## Release process

- **`release.sh` has no CI gate.** WaxOnWaxOff's equivalent queries GitHub
  Actions for the release SHA and refuses to publish unless CI concluded
  success, with an explicit `--allow-red-ci` override. It filters on the
  workflow's *path* rather than its name, so renaming `ci.yml`'s `name:` cannot
  silently defeat it, and it treats every degenerate case — `gh` unauthenticated,
  query failure, no run for the commit, run unfinished — as a failure. ClipHack
  publishes regardless of CI state; releases are currently gated only by whoever
  is running the script remembering to look. Porting it is roughly 40 lines.

  Worth knowing why that gate exists: WaxOnWaxOff shipped 2.8.0 with a
  completely unbuildable test suite. CI caught it and went red, and the release
  went out anyway.

- **`release.sh` was considered for the shared-file treatment and declined.**
  The three scripts look heavily duplicated, and pairwise they are — roughly 140
  lines match between any two of DoublEnder, WaxOnWaxOff and ClipHack. Matched
  in order across all three, though, only 37 lines agree, in seven fragments of
  three to eight lines, several of which are section-header comments.

  What looked shared turns out to be app-specific where it counts. Signing
  differs in all three because the bundles differ: DoublEnder signs an app,
  WaxOnWaxOff signs two binaries in Resources, ClipHack signs an embedded
  framework plus yt-dlp under its own entitlements. Publication differs too —
  one repo, a separate releases repo, a GCS permalink. What genuinely is common
  amounts to three one-line echo helpers, the nine-line DMG version check, and
  the dmgbuild invocation: about twenty lines of real logic.

  Extracting that would put a cross-repo sourcing dependency into three
  release-critical scripts to remove twenty lines, and a bug in the shared file
  would break every release at once. The drift it would guard against is also
  the mild kind: nobody expects these scripts to match, so divergence is
  visible rather than silent. That is the opposite of the FFmpeg runner case,
  where the copies were meant to be identical, quietly were not, and two latent
  crashes lived in ClipHack for months.

  Revisit if the scripts converge on their own — if signing ever becomes
  uniform, or a fourth app arrives with the same shape.

## Performance

- **Two-pass loudnorm may be replaceable with a single `ebur128` measurement.**
  ClipHack asks `loudnorm` for `linear=true`, which by definition applies one
  constant gain — so the two-pass apparatus exists to compute a single number.
  WaxOnWaxOff made exactly this change in its 2.9.0 and measured the Edit Prep
  path drop from 8.99 s to 2.80 s on a ten-minute source, with loudness accuracy
  improving rather than degrading (largest miss across a five-source corpus:
  0.23 LU before, 0.00 LU after).

  Not simply portable: ClipHack handles short clips, so the absolute saving may
  not justify the change. Measure first on representative material. If it is
  done, note the silence guard WaxOnWaxOff needed — `ebur128` floors at exactly
  −70 LUFS where `loudnorm` reported `-inf`, so a bare `isFinite` check boosts
  digital silence by 40 dB.

## Technical debt

- **The FFmpeg watchdog timeout is flat, not proportional.** 900 seconds
  regardless of input length. WaxOnWaxOff uses `max(300, duration × 4)`. The flat
  ceiling suits short clips and making it proportional means plumbing a probed
  duration through every call site, so it was left alone — but a long input would
  be killed mid-render with a timeout rather than finishing.

- **`FFmpegRunner`, `release.sh` and `tools/dmg/` are copied between repos, not
  shared.** DoublEnder, WaxOnWaxOff and ClipHack each carry their own copy, and
  they drift. This is not theoretical: WaxOnWaxOff's `FFmpegRunner` was hardened
  by several audits that never propagated here, leaving ClipHack with two latent
  crashes — terminating a never-launched process from an un-disarmed watchdog and
  from an unguarded cancel path — plus every ffmpeg crash being reported as a
  user cancellation. Fixed here in 1.19.2, but nothing prevents the next
  divergence. A shared package would be the real fix; failing that, a periodic
  three-way diff of the shared files is the cheap version.
