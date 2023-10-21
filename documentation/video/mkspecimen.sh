#!/bin/bash
# This script is for making a specimen video of MFEKfont's MFEK Sans №2
#
[[ -n "$DEBUG" ]] && set -x || true

set -e
set -o pipefail
shopt -s extglob

OUTVIDEO='out.mp4'
TEMPDIR="/tmp/MFEK-Sans"
mkdir -p "$TEMPDIR"
PARALLEL_BAR_OPTS=(--bar)
# -t 1 is a test for whether stdout is a terminal
[[ -t 1 ]] || PARALLEL_BAR_OPTS=()

SPECIMEN_BG_COLOR="${SPECIMEN_BG_COLOR:-#000000}"
SPECIMEN_FG_COLOR="${SPECIMEN_FG_COLOR:-#ffffff}"
SPECIMEN_FT_LOAD_FLAGS="${SPECIMEN_FT_LOAD_FLAGS:-2}"

export INTXT=`mktemp`
read -r -e -p "Draw what text?" -u 0 <<< ' MFEK Sans №2 '
tee "$INTXT" <<< "$REPLY"
PNGFILE_TEMPLATE="$TEMPDIR/{1}.png"
>&2 echo "Warning: Installing the fonts is required for this script to work."

check_installed_font() {
    local font="$1"
    local INSTALLED_FONT="$HOME/.fonts/m/$(basename "$font")"
    if [[ ! -f "$INSTALLED_FONT" ]]; then
        if [[ -t 0 ]]; then
            read -r -e -p "Install $font to $INSTALLED_FONT? [Y/n] " -u 0
            if [[ "$REPLY" =~ ^[Yy]$ ]] || [[ -z "$REPLY" ]]; then
                mkdir -p "$HOME/.fonts/m"
                cp "$font" "$INSTALLED_FONT"
                return 0
            else
                >&2 echo "Install font $font to $INSTALLED_FONT on your own."
            fi
        else
            >&2 echo "Error: Cowardly refusing to install $font non-interactively."
            return 1
        fi
    else
        true
    fi
}

for font in ../../fonts/variable/*.ttf; do
    check_installed_font "$font"
done

ffmpeg_setup() {
    which amdgpu_top 2>&1 >/dev/null && export HWACCEL_OPTS=(-hwaccel auto -hwaccel_output_format vulkan) || \
        export HWACCEL_OPTS=()
    [[ 0 -eq "${#HWACCEL_OPTS[@]}" ]] && VCODEC="libx264" || VCODEC="h264_amf"
    [[ -n "$DEBUG" ]] && \
        ([[ 0 -eq "${#HWACCEL_OPTS[@]}" ]] && export LOG_TO_DBG=() || export LOG_TO_DBG=(-log_to_dbg 1)) || \
        export LOG_TO_DBG=()
    [[ 0 -eq "${#HWACCEL_OPTS[@]}" ]] && export VULKAN_ICD_FILENAMES="" || \
        export VULKAN_ICD_FILENAMES="/usr/share/vulkan/icd.d/amd_icd64.json"
    export FFMPEG_OPTS=(-thread_queue_size 65536 -hide_banner -loglevel $(if [[ -n "$DEBUG" ]]; then echo "debug"; else echo "info"; fi) ${HWACCEL_OPTS[@]})
    return 0
}
# end ffmpeg setup

make_vf_specimens() {
    INFONTS=()
    for font in "$HOME/.fonts/m/"*.ttf; do
        INFONTS+=("$font")
    done

    >&2 echo Found fonts: "${INFONTS[@]}"
    local i=0
    for axis in wght wdth TRMA; do
        if [[ "$axis" == "TRMA" ]]; then
            local FRAMES="$( (seq 0 5 1000; seq 1000 -5 0) | awk 'BEGIN {OFS="\t"} {print NR, $0}')"
        else
            local FRAMES="$( (seq 100 900; seq 899 -1 101) | awk 'BEGIN {OFS="\t"} {print NR, $0}')"
        fi
        for font in "${INFONTS[@]}"; do
            >&2 echo "Making frames for $font ($axis)…"
            if [[ "$axis" == "TRMA" ]]; then
                local extra_variations=",wgth=400,wdth=100"
            else
                local extra_variations=""
            fi
            rm -f "$TEMPDIR"/+([[:digit:]]).png
            parallel --colsep '\t' ${PARALLEL_BAR_OPTS[@]} \
                $'hb-view --ft-load-flags='"$SPECIMEN_FT_LOAD_FLAGS"' \
                --variations='"$axis"'={2}'"$extra_variations"' \
                --text="'`cat "$INTXT"`'" --background='"$SPECIMEN_BG_COLOR"' --foreground='"$SPECIMEN_FG_COLOR"' \
                -o '"$PNGFILE_TEMPLATE" \
                "$font" <<< "$FRAMES"

            >&2 echo "Making video for $font ($axis)…"
            pushd "$PWD"
            pushd "$TEMPDIR"
            local OUTVIDEO="$axis-${font##*/}.mp4"
            [[ -f "$OUTVIDEO" ]] && rm "$OUTVIDEO"
            # This will make a 30fps H.264 video with a black background suitable for
            # YouTube / Twitter / README.md &c.
            ffmpeg ${FFMPEG_OPTS[@]} \
                -r 30 -i "%d.png" \
                -f lavfi -i color=color=black:s=1280x720 \
                -filter_complex '[0:v]scale=-1:ih/2,format=yuv420p[v]; [1][v]overlay=shortest=1:ts_sync_mode=1:eof_action=endall,format=nv12' \
                -c:v "$VCODEC" -rc cqp -q:v 18 -r 30 -fps_mode:v cfr -an -sn ${LOG_TO_DBG[@]} \
                "$OUTVIDEO"
            popd
            mv "$TEMPDIR/$OUTVIDEO" .
            i=$((i+1))
        done
    done
}

ffmpeg_setup
make_vf_specimens

[[ -n "$DEBUG" ]] && set +x || true
# vim: set ts=4 sw=4 tw=0 et syntax=bash :
