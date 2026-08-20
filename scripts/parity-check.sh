#!/usr/bin/env bash
# parity-check.sh — Old-binary vs new-binary parity over the whole corpus.
#
# Runs the app's ACTUAL processing pipeline (from AudioProcessor.swift) through
# both binaries and compares outputs. Report is per-file, per-gate, with MEASURED
# values — margins, not verdicts.
#
# The pipeline is reproduced as SEPARATE ffmpeg invocations writing 24-bit
# intermediates, exactly as the app runs it. Collapsing it into one filter chain
# would skip the inter-stage quantization and test something the app never does.
#
# Policy (frozen — do not edit a threshold after seeing results; take the failing
# data to the owner instead):
#   * Three states: PASS / FAIL / INCOMPLETE. INCOMPLETE never counts as PASS.
#   * Runs EVERY fixture in the corpus; never aborts early; exits non-zero on any
#     FAIL or INCOMPLETE.
#   * Null is diagnostic; LUFS/TP/format/sample-count are the hard gates.
#
# Thresholds (frozen):
NULL_HARD_DB="-90"
LUFS_TOL="0.1"
TP_TOL="0.1"
#
# Pre-registered divergences: NONE. Unlike WaxOnWaxOff — which encodes MP3 and so
# must pre-register a LAME-version bitstream difference — ClipHack only ever
# writes pcm_s24le, and every stage (including dither and dynaudnorm) is
# deterministic for a given binary. So every chain here gets a hard null gate. If
# you add an encoder to the app, add its divergence here BEFORE running.
#
# bash 3.2-safe. Env: CLIPHACK_PARITY_CORPUS, CLIPHACK_OLD_FFMPEG, CLIPHACK_NEW_FFMPEG.

set -uo pipefail
CORPUS="${CLIPHACK_PARITY_CORPUS:?}"; OLD="${CLIPHACK_OLD_FFMPEG:?}"; NEW="${CLIPHACK_NEW_FFMPEG:?}"
METER="$OLD"   # ONE fixed meter for both sides, so we measure output diffs not meter diffs
PROBE="${CLIPHACK_OLD_FFPROBE:-$(dirname "$OLD")/ffprobe}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0; incomplete=0

# App defaults being exercised (ClipHackSettings): 44.1 kHz, mono from left,
# 80 Hz high-pass, -1 dBFS ceiling, -24 LUFS target.
SR=44100; OVERSR=88200; HPF=80; LIMIT="0.891251"; LUFS_TARGET="-24"; TP_TARGET="-1"

state() {
    printf '  %-11s %s\n' "[$1]" "$2"
    case "$1" in
        PASS) pass=$((pass+1));;
        FAIL) fail=$((fail+1));;
        INCOMPLETE) incomplete=$((incomplete+1));;
    esac
}

# Null residual, CHANNEL-SAFE: invert one side and sum, which works at any channel
# count. (Subtracting channel 1 from channel 0 of an amerge compares a file
# against ITSELF on dual-mono input and reports a false -inf.)
null_db() {
    "$METER" -hide_banner -nostats -i "$1" -i "$2" \
        -filter_complex "[1:a]volume=-1[inv];[0:a][inv]amix=inputs=2:normalize=0,astats=metadata=1:reset=0" \
        -f null - 2>&1 | awk -F': ' '/Peak level dB/{v=$2} END{print v}'
}
measure() {  # -> "I TP"
    "$METER" -hide_banner -nostats -i "$1" -af loudnorm=print_format=json -f null - 2>&1 \
        | awk '/"input_i"/{i=$3} /"input_tp"/{t=$3} END{gsub(/[",]/,"",i);gsub(/[",]/,"",t);print i, t}'
}
fmt() { "$PROBE" -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of csv=p=0 "$1" 2>/dev/null | head -1; }
samples() { "$PROBE" -v error -select_streams a:0 -show_entries stream=duration_ts -of csv=p=0 "$1" 2>/dev/null | head -1; }
duration() { "$PROBE" -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null | head -1; }
abs_le() { awk -v a="$1" -v b="$2" 'BEGIN{a=(a<0?-a:a); exit !(a<=b)}'; }

compare() {  # label old new   — empty is INCOMPLETE, never a false PASS
    if [ -z "$2" ] || [ -z "$3" ]; then state INCOMPLETE "$1 unmeasurable"
    elif [ "$2" = "$3" ]; then state PASS "$1 = $3"
    else state FAIL "$1: old=$2 new=$3"; fi
}
gate_loud() {  # label oldfile newfile
    om="$(measure "$2")"; nm="$(measure "$3")"
    oI="${om%% *}"; oT="${om##* }"; nI="${nm%% *}"; nT="${nm##* }"
    if [ -z "$oI" ] || [ -z "$nI" ]; then state INCOMPLETE "$1 LUFS/TP unmeasurable"; return; fi
    dI="$(awk -v a="$oI" -v b="$nI" 'BEGIN{printf "%.4f", a-b}')"
    dT="$(awk -v a="$oT" -v b="$nT" 'BEGIN{printf "%.4f", a-b}')"
    if abs_le "$dI" "$LUFS_TOL"; then state PASS "$1 LUFS Δ=${dI} (old ${oI} new ${nI})"
    else state FAIL "$1 LUFS Δ=${dI} > ${LUFS_TOL}"; fi
    if abs_le "$dT" "$TP_TOL"; then state PASS "$1 TP   Δ=${dT} (old ${oT} new ${nT})"
    else state FAIL "$1 TP Δ=${dT} > ${TP_TOL}"; fi
}
gate_null() {  # label oldfile newfile
    nd="$(null_db "$2" "$3")"
    if [ -z "$nd" ]; then state INCOMPLETE "$1 null unmeasurable"
    elif [ "$nd" = "-inf" ]; then state PASS "$1 null = -inf (bit-identical)"
    elif awk -v v="$nd" -v t="$NULL_HARD_DB" 'BEGIN{exit !(v<=t)}'; then state PASS "$1 null = ${nd} dBFS (<= ${NULL_HARD_DB})"
    else state FAIL "$1 null = ${nd} dBFS (want <= ${NULL_HARD_DB})"; fi
}

# --- The app's pipeline, stage for stage (AudioProcessor.swift) ------------------
# run_chain <bin> <input> <output> <leveling:0|1> <loudnorm:0|1>
# Mirrors: mono extract -> highpass+allpass -> [dynaudnorm, mirror-padded]
#          -> [loudnorm two-pass] -> limiter.
run_chain() {
    local bin="$1" in="$2" out="$3" lev="$4" ln="$5"
    local w="$TMP/w"; rm -rf "$w"; mkdir -p "$w"
    local cur="$in"

    # Mono extraction from the left channel (settings.stereoOutput == false).
    "$bin" -y -nostdin -hide_banner -loglevel error -i "$cur" -map 0:a:0 -af "pan=1c|c0=c0" \
        -c:a pcm_s24le -ar "$SR" -ac 1 "$w/ch.wav" || return 1
    cur="$w/ch.wav"

    # High-pass + all-pass phase rotation (always on).
    "$bin" -y -nostdin -hide_banner -loglevel error -i "$cur" \
        -af "highpass=f=${HPF},allpass=f=200:t=q:w=0.707" \
        -c:a pcm_s24le -ar "$SR" -ac 1 "$w/hp.wav" || return 1
    cur="$w/hp.wav"

    # Dynamic leveling, mirror-padded. padDur = min(16, duration); the app skips
    # padding only when ffprobe cannot report a duration, which a well-formed
    # fixture never triggers.
    if [ "$lev" = "1" ]; then
        local d pad tstart dyn
        d="$(duration "$cur")"; [ -n "$d" ] || return 1
        pad="$(awk -v d="$d" 'BEGIN{printf "%.6f", (d<16.0?d:16.0)}')"
        tstart="$(awk -v d="$d" -v p="$pad" 'BEGIN{v=d-p; printf "%.6f", (v<0?0:v)}')"
        dyn="dynaudnorm=f=250:g=15:p=0.95:m=4.0"
        "$bin" -y -nostdin -hide_banner -loglevel error -i "$cur" -filter_complex \
"[0:a]asplit=3[h][m][t];[h]atrim=duration=${pad},areverse,asetpts=PTS-STARTPTS[head];[m]asetpts=PTS-STARTPTS[body];[t]atrim=start=${tstart},areverse,asetpts=PTS-STARTPTS[tail];[head][body][tail]concat=n=3:v=0:a=1,${dyn},atrim=start=${pad}:duration=${d},asetpts=PTS-STARTPTS" \
            -c:a pcm_s24le -ar "$SR" -ac 1 "$w/dyn.wav" || return 1
        cur="$w/dyn.wav"
    fi

    # Two-pass EBU R128 loudness normalization (analysis, then linear apply).
    if [ "$ln" = "1" ]; then
        local m I T L H O
        m="$("$bin" -nostdin -hide_banner -nostats -i "$cur" \
             -af "loudnorm=I=${LUFS_TARGET}:TP=${TP_TARGET}:LRA=20:print_format=json" -f null - 2>&1)"
        I=$(printf '%s' "$m"|awk '/input_i/{gsub(/[",]/,"",$3);print $3}')
        T=$(printf '%s' "$m"|awk '/input_tp/{gsub(/[",]/,"",$3);print $3}')
        L=$(printf '%s' "$m"|awk '/input_lra/{gsub(/[",]/,"",$3);print $3}')
        H=$(printf '%s' "$m"|awk '/input_thresh/{gsub(/[",]/,"",$3);print $3}')
        O=$(printf '%s' "$m"|awk '/target_offset/{gsub(/[",]/,"",$3);print $3}')
        [ -n "$I" ] || return 1
        # The app skips pass 2 on non-finite measurements (near-silent input).
        case "$I$T$L$H$O" in *inf*|*nan*) cur="$cur";; *)
            "$bin" -y -nostdin -hide_banner -loglevel error -i "$cur" \
                -af "loudnorm=I=${LUFS_TARGET}:TP=${TP_TARGET}:LRA=20:measured_I=${I}:measured_TP=${T}:measured_LRA=${L}:measured_thresh=${H}:offset=${O}:linear=true" \
                -c:a pcm_s24le -ar "$SR" -ac 1 "$w/ln.wav" || return 1
            cur="$w/ln.wav";;
        esac
    fi

    # true-peak limiter.
    "$bin" -y -nostdin -hide_banner -loglevel error -i "$cur" -af \
"aresample=${OVERSR}:filter_size=512:cutoff=0.97:phase_shift=10,alimiter=limit=${LIMIT}:attack=5:release=50:level=disabled,aresample=${SR}:filter_size=512:cutoff=0.97:phase_shift=10:dither_method=triangular_hp" \
        -map_metadata 0 -c:a pcm_s24le -ar "$SR" -ac 1 -f wav "$out" || return 1
}

gate_stage() {  # label lev ln input
    local label="$1" lev="$2" ln="$3" f="$4"
    if run_chain "$OLD" "$f" "$TMP/o.wav" "$lev" "$ln" 2>/dev/null \
       && run_chain "$NEW" "$f" "$TMP/n.wav" "$lev" "$ln" 2>/dev/null \
       && [ -s "$TMP/o.wav" ] && [ -s "$TMP/n.wav" ]; then
        gate_null "$label" "$TMP/o.wav" "$TMP/n.wav"
        compare   "$label format"  "$(fmt "$TMP/o.wav")"     "$(fmt "$TMP/n.wav")"
        compare   "$label samples" "$(samples "$TMP/o.wav")" "$(samples "$TMP/n.wav")"
        gate_loud "$label" "$TMP/o.wav" "$TMP/n.wav"
    else
        state INCOMPLETE "$label produced no output"
    fi
}

echo "=== PARITY  old=$("$OLD" -version|awk 'NR==1{print $3}')  new=$("$NEW" -version|awk 'NR==1{print $3}') ==="
echo "=== settings: ${SR} Hz mono(L), HPF ${HPF} Hz, ceiling ${TP_TARGET} dBFS, loudnorm ${LUFS_TARGET} LUFS ==="
echo "=== no pre-registered divergences — every chain gets a hard null gate ==="
echo

# EVERY fixture in the corpus — no hand-picked subset.
for f in "$CORPUS"/*; do
    case "$f" in *.wav|*.mp3|*.flac|*.m4a|*.aac|*.caf|*.aiff|*.aif|*.ogg|*.opus|*.mp4|*.mov) ;; *) continue;; esac
    b="$(basename "$f")"; echo "$b"
    gate_stage "core"       0 0 "$f"   # always-on path: HPF/allpass + limiter
    gate_stage "leveled"    1 0 "$f"   # + dynaudnorm, mirror-padded
    gate_stage "normalized" 0 1 "$f"   # + two-pass loudnorm
    gate_stage "full"       1 1 "$f"   # everything, the app's default-on shape
done

echo
echo "=== PASS=$pass  FAIL=$fail  INCOMPLETE=$incomplete ==="
[ "$fail" -eq 0 ] && [ "$incomplete" -eq 0 ]
