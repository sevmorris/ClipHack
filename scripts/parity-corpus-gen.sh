#!/usr/bin/env bash
# parity-corpus-gen.sh — Generate the parity corpus OUTSIDE the repo tree.
#
# Real speech (macOS `say`, two distinct voices) is the primary material because
# the DSP under test is data-dependent: a sine never trips loudnorm's relative
# gate and gives dynaudnorm nothing to move. Synthetic tones are generated too,
# but only for the structural gates (format, sample-count) — never trusted for
# LUFS/TP/null.
#
# Everything is produced with the OLD binary (CLIPHACK_OLD_FFMPEG): if a later
# build strips a demuxer from the NEW binary, the generator is unaffected and you
# get a clean parity result, not a generator error.
#
# Corpus lives at $CLIPHACK_PARITY_CORPUS — no default inside the repo. Audio is
# never committed; this script is.
#
# bash 3.2-safe. Env: CLIPHACK_PARITY_CORPUS (out dir), CLIPHACK_OLD_FFMPEG.

set -euo pipefail

CORPUS="${CLIPHACK_PARITY_CORPUS:?set CLIPHACK_PARITY_CORPUS to a path OUTSIDE the repo}"
OLD="${CLIPHACK_OLD_FFMPEG:?set CLIPHACK_OLD_FFMPEG to the current ffmpeg binary}"
PROBE="${CLIPHACK_OLD_FFPROBE:-$(dirname "$OLD")/ffprobe}"
case "$CORPUS" in
  "$PWD"*|*/ClipHack/*) echo "refusing: corpus path is inside the repo tree" >&2; exit 1;;
esac
mkdir -p "$CORPUS"

# --- Voice selection: pick the first TWO *installed* voices from a preference
# list. Named voices are download-on-demand on current macOS, so hardcoding two
# risks `say` silently falling back to the system default and producing a
# "stereo" fixture that is really dual-mono — passing every gate while testing
# nothing. Fewer than two distinct installed voices => INCOMPLETE, never a fallback.
VOICE_PREFS="Alex Samantha Daniel Albert Fred Karen Moira Tessa Serena Allison"
avail() { say -v '?' 2>/dev/null | awk '{print $1}' | grep -qx "$1"; }
V1=""; V2=""
for v in $VOICE_PREFS; do
    if avail "$v"; then
        if [ -z "$V1" ]; then V1="$v"
        elif [ -z "$V2" ]; then V2="$v"; break
        fi
    fi
done
if [ -z "$V1" ] || [ -z "$V2" ]; then
    echo "INCOMPLETE: need two installed 'say' voices for decorrelated fixtures; found: ${V1:-none} ${V2:-}" >&2
    echo "  installed candidates: $(say -v '?' 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ' | cut -c1-200)" >&2
    exit 3
fi
echo "▶ voices: $V1 (L) / $V2 (R)"

say_wav() {  # voice  text  out.wav
    say -v "$1" -o "$CORPUS/_tmp.aiff" "$2"
    "$OLD" -y -loglevel error -i "$CORPUS/_tmp.aiff" -ar 48000 -ac 1 -c:a pcm_s16le "$3"
    rm -f "$CORPUS/_tmp.aiff"
}

TXT="This is a parity corpus sample. It has pauses, and varied dynamics, so that loudness gating and the leveler actually have something to work on."
TXT2="A second speaker reads different words, at a different pace, to decorrelate the channels for real stereo testing."

echo "▶ mono speech"
say_wav "$V1" "$TXT" "$CORPUS/speech-mono48.wav"

echo "▶ decorrelated stereo (two voices → L/R, verified distinct)"
say_wav "$V1" "$TXT"  "$CORPUS/_L.wav"
say_wav "$V2" "$TXT2" "$CORPUS/_R.wav"
"$OLD" -y -loglevel error -i "$CORPUS/_L.wav" -i "$CORPUS/_R.wav" \
    -filter_complex "[0:a][1:a]amerge=inputs=2,pan=stereo|c0=c0|c1=c1[a]" -map "[a]" \
    -ar 48000 -c:a pcm_s16le "$CORPUS/speech-stereo48.wav"
# Verify the channels actually differ. ClipHack's default extracts the LEFT
# channel only, so a dual-mono fixture would make the mono-extract stage
# untestable while still passing every gate. Fail loudly instead.
lr_rms="$("$OLD" -hide_banner -nostats -i "$CORPUS/speech-stereo48.wav" \
     -af "aeval=val(0)-val(1):c=1,astats=metadata=1:reset=0" -f null - 2>&1 \
     | awk -F': ' '/RMS level dB/{v=$2} END{print v}')"
case "$lr_rms" in
  ""|*inf*) echo "INCOMPLETE: stereo fixture is dual-mono (L-R nulls to ${lr_rms:-nothing}) — voices did not differ" >&2; exit 3;;
esac
awk -v v="$lr_rms" 'BEGIN{exit !(v > -60)}' \
  || { echo "INCOMPLETE: stereo L-R residual ${lr_rms} dB is near-silent — channels are effectively identical" >&2; exit 3; }
echo "   stereo decorrelation verified: L-R residual RMS ${lr_rms} dB"
rm -f "$CORPUS/_L.wav" "$CORPUS/_R.wav"

# Mirror padding uses padDur = min(16, duration), so the branch boundary is 16s.
echo "▶ duration fixtures (mirror-pad boundary is 16s: padDur = min(16, duration))"
"$OLD" -y -loglevel error -i "$CORPUS/speech-mono48.wav" -t 1.5 -c:a pcm_s16le "$CORPUS/speech-1p5s.wav"   # very short
"$OLD" -y -loglevel error -i "$CORPUS/speech-mono48.wav" -t 9.0 -c:a pcm_s16le "$CORPUS/speech-9s.wav"     # under the cap: pad = duration
"$OLD" -y -loglevel error -stream_loop 3 -i "$CORPUS/speech-mono48.wav" -t 20 -c:a pcm_s16le "$CORPUS/speech-20s.wav"  # over the cap: pad = 16s
# NOTE: the third branch — duration unknown, padding skipped — is NOT reachable
# from a generated fixture: the app only takes it when ffprobe cannot report a
# duration. Recorded as not-coverable rather than left silently uncovered.

echo "▶ noisy speech (exercises the high-noise-floor warning path)"
"$OLD" -y -loglevel error -i "$CORPUS/speech-mono48.wav" -f lavfi -i "anoisesrc=color=pink:amplitude=0.03:d=999" \
    -filter_complex "[0:a][1:a]amix=inputs=2:duration=first:weights=1 0.15[a]" -map "[a]" \
    -ar 48000 -ac 1 -c:a pcm_s16le "$CORPUS/speech-noisy.wav"

echo "▶ near-silent (loudnorm emits non-finite measurements; app skips pass 2)"
"$OLD" -y -loglevel error -f lavfi -i "anoisesrc=color=white:amplitude=0.00002:d=3" \
    -ar 48000 -ac 1 -c:a pcm_s16le "$CORPUS/near-silent.wav"

echo "▶ format matrix (every extension ClipHack accepts, via OLD binary)"
"$OLD" -y -loglevel error -i "$CORPUS/speech-mono48.wav" -c:a flac        "$CORPUS/speech.flac"
"$OLD" -y -loglevel error -i "$CORPUS/speech-mono48.wav" -c:a libmp3lame -b:a 160k "$CORPUS/speech.mp3"
"$OLD" -y -loglevel error -i "$CORPUS/speech-mono48.wav" -c:a aac -b:a 192k "$CORPUS/speech.m4a"
"$OLD" -y -loglevel error -i "$CORPUS/speech-mono48.wav" -c:a aac -b:a 192k -f adts "$CORPUS/speech.aac"
"$OLD" -y -loglevel error -i "$CORPUS/speech-mono48.wav" -c:a pcm_s16le   "$CORPUS/speech.caf"
"$OLD" -y -loglevel error -i "$CORPUS/speech-mono48.wav" -c:a pcm_s16be -f aiff "$CORPUS/speech.aiff"
"$OLD" -y -loglevel error -i "$CORPUS/speech-mono48.wav" -c:a libopus -b:a 96k "$CORPUS/speech.opus" 2>/dev/null \
    || echo "   NOTE: libopus not in this build — .opus fixture skipped (ClipHack still accepts the extension)"

echo "▶ MP4/MOV WITH a video stream (so the app's -map 0:a:0 ignore-video path runs)"
for ext in mp4 mov; do
    "$OLD" -y -loglevel error -i "$CORPUS/speech-mono48.wav" \
        -f lavfi -i "color=c=black:s=64x64:r=15" -shortest \
        -c:a aac -b:a 192k -c:v mpeg4 "$CORPUS/speech-in.$ext"
done
# Confirm they carry video — the whole point of these fixtures is that the app's
# `-map 0:a:0` must skip a real video stream. Use ffprobe (-show_entries is an
# ffprobe option; calling ffmpeg with it silently yields nothing).
for ext in mp4 mov; do
    hasv="$("$PROBE" -v error -show_entries stream=codec_type -of csv=p=0 "$CORPUS/speech-in.$ext" 2>/dev/null | grep -c video)"
    if [ "${hasv:-0}" -ge 1 ]; then
        echo "   speech-in.$ext: video stream present ✓"
    else
        echo "INCOMPLETE: speech-in.$ext has no video stream — the -map 0:a:0 path would not be exercised" >&2
        exit 3
    fi
done

echo "▶ synthetic (structural gates only — format + sample-count; NOT LUFS/TP/null)"
"$OLD" -y -loglevel error -f lavfi -i "sine=frequency=440:duration=3"           -ar 44100 -c:a pcm_s16le "$CORPUS/synth-sine.wav"
"$OLD" -y -loglevel error -f lavfi -i "anoisesrc=color=white:amplitude=0.5:d=3" -ar 48000 -c:a pcm_s16le "$CORPUS/synth-noise.wav"

echo "✓ corpus at $CORPUS:"; ls -1 "$CORPUS"
