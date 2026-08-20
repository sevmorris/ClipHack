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

- **`FFmpegRunner`, `release.sh` and `tools/dmg/` were copied between repos, not
  shared** — mostly resolved. DoublEnder, WaxOnWaxOff and ClipHack each carried
  their own copy, and they drifted. That was not theoretical: WaxOnWaxOff's
  `FFmpegRunner` was hardened by several audits that never propagated here,
  leaving ClipHack with two latent crashes — terminating a never-launched process
  from an un-disarmed watchdog and from an unguarded cancel path — plus every
  ffmpeg crash being reported as a user cancellation. Fixed in 1.19.2.

  What changed since: the launch machinery is now `FFmpegProcess.swift`,
  byte-identical here and in WaxOnWaxOff, and `tools/dmg/` is byte-identical
  across all four app repos (FilmStrip joined). `scripts/check-shared.sh`
  compares every file carrying the shared marker against the sibling checkouts
  and fails this repo's release preflight on a mismatch, so the next divergence
  stops a release instead of going unnoticed. Registration is by marker rather
  than manifest, so adding a file to the set is a header comment.

  A shared package was considered and rejected: these repos are deliberately
  independent, there is no in-tree home for one, and an SPM dependency would put
  a version bump in three places behind every fix. `release.sh` was measured and
  deliberately left duplicated — see the entry under *Release process*.

  Still open: policy and parsing stay per-repo by design, so `FFmpegRunner`
  itself is not shared, only the process machinery underneath it. And
  `scripts/build-ffmpeg.sh` cannot join the set — each copy bakes its own build
  directory into the binary it produces, which is what makes those builds
  reproducible.
