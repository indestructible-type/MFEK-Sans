#!/bin/bash
# This script is for making a specimen video of MFEKfont's MFEK Sans №2
#
# (c) 2023 Fredrick R. Brennan. For license, see file LICENSE in root of MFEK Sans repository.
#
[[ -n "$DEBUG" ]] && set -x || true


set -e
set -o pipefail
shopt -s extglob

#                                        RRGGBBAA
SPECIMEN_BG_COLOR="${SPECIMEN_BG_COLOR:-#000000ff}"
SPECIMEN_FG_COLOR="${SPECIMEN_FG_COLOR:-#ffffffff}"
SPECIMEN_FT_LOAD_FLAGS="${SPECIMEN_FT_LOAD_FLAGS:-0}"
FONTSIZE="${FONTSIZE:-144}"

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

>&2 echo "Warning: Installing the fonts is required for this script to work."
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

frames_setup() {
    TEMPDIR="/tmp/MFEK-Sans"
    mkdir -p "$TEMPDIR"
    PARALLEL_BAR_OPTS=(--bar)
    # -t 1 is a test for whether stdout is a terminal
    [[ -t 1 ]] || PARALLEL_BAR_OPTS=()
    export INTXT=`mktemp`
    read -r -e -p "Draw what text?" -u 0 <<< ' MFEK Sans №2 '
    tee "$INTXT" <<< "$REPLY"
    PNGFILE_TEMPLATE="$TEMPDIR/{1}.png"
}

make_vf_specimens() {
    INFONTS=()
    for font in "$HOME/.fonts/m/"*.ttf; do
        INFONTS+=("$font")
    done

    >&2 echo Found fonts: "${INFONTS[@]}"
    AXES=(wdth wght TRMA)
    local i=0
    for axis in "${AXES[@]}"; do
        case "$axis" in
            wght)
                local axis_name="Weight"
                export FRAMES="$( (seq 100 900; seq 899 -1 101) | awk $'BEGIN {OFS="\t"} {print NR-1, $0}')"
                ;;
            wdth)
                local axis_name="Width"
                export FRAMES="$( (seq 100 -0.1 50 && seq 50 0.1 100) | awk $'BEGIN {OFS="\t"} {print NR-1, $0}')"
                ;;
            TRMA)
                local axis_name="Terminal Radius Multiplicand Axis"
                export FRAMES="$( (seq 0 10 1000; seq 1000 -10 0) | awk $'BEGIN {OFS="\t"} {print NR-1, $0}')"
                ;;
            *)
                >&2 echo "Error: Unknown axis $axis"
                return 1
                ;;
        esac
        # Remove blank lines
        export FRAMES="$(echo "$FRAMES" | sed '/^$/d')"
        [[ -n "$DEBUG" ]] && echo "FRAMES: $FRAMES"
        for font in "${INFONTS[@]}"; do
            >&2 echo "Making frames for $font ($axis)…"
            case "$axis" in
                wght)
                    local extra_variations=""
                    ;;
                wdth)
                    local extra_variations=",wght=400"
                    ;;
                TRMA)
                    local extra_variations=",wght=400"
                    ;;
                *)
                    >&2 echo "Error: Unknown axis $axis"
                    return 1
                    ;;
            esac
            [[ -n "$DEBUG" ]] && >&2 echo "extra_variations: $extra_variations"
            rm -f "$TEMPDIR"/*.png
            parallel --colsep '\t' ${PARALLEL_BAR_OPTS[@]} \
                $'hb-view --ft-load-flags='"$SPECIMEN_FT_LOAD_FLAGS"' \
                --variations='"$axis"'={2}'"$extra_variations"' \
                --text="'`cat "$INTXT"`'" --background='"$SPECIMEN_BG_COLOR"' --foreground='"$SPECIMEN_FG_COLOR"' \
                --font-size='"$FONTSIZE"' \
                --font-file='"$font"' --output-format=png --output-file='"$PNGFILE_TEMPLATE" <<< "$FRAMES"
                #$'gm convert '"$PNGFILE_TEMPLATE"' -gravity center -extent 1280x720 '"temp.$PNGFILE_TEMPLATE"' \
                #&& mv '"temp.$PNGFILE_TEMPLATE"' '"$PNGFILE_TEMPLATE" <<< "$FRAMES"
                LARGEST_IMAGE="$(YUVMODE=0 ./largest-image.sh "$TEMPDIR"/+([[:digit:]]).png)"
                >&2 echo "Largest image: $LARGEST_IMAGE"
                # Get extent of largest image
                local EXTENT=($(gm identify -format $'%w\t%h' "$LARGEST_IMAGE"))
                >&2 echo "Extent: $EXTENT"
                # Round up to nearest multiple of 2
                EXTENT[0]=$(( (EXTENT[0] + 1) / 2 * 2 ))
                EXTENT[1]=$(( (EXTENT[1] + 1) / 2 * 2 ))
                EXTENT="${EXTENT[0]}x${EXTENT[1]}"

                find "$TEMPDIR" -maxdepth 1 -type f -name '*.png' \
                    | parallel -j$((`nproc`*2)) ${PARALLEL_BAR_OPTS[@]} \
                    $'magick convert {} -gravity NorthWest -background '"${SPECIMEN_BG_COLOR@Q}"' -extent '"$EXTENT"' -alpha remove -flatten -alpha off {.}.temp.png'
                
                find "$TEMPDIR" -maxdepth 1 -type f -name '*.temp.png' \
                    | parallel -j$((`nproc`*2)) ${PARALLEL_BAR_OPTS[@]} \
                    mv '{}' '{=s/\.temp//=}'

            >&2 echo "Making video for $font ($axis)…"
            pushd "$PWD"
            pushd "$TEMPDIR"
            local OUTVIDEO="$axis-${font##*/}.mp4"
            [[ -f "$OUTVIDEO" ]] && rm "$OUTVIDEO"
            # This will make a 30fps H.264 video with a black background suitable for
            # YouTube / Twitter / README.md &c.
            rm -f drawtext.txt
            while read -r frame; do
                frame=($frame)
                local frame_number="${frame[0]}"
                local frame_value="${frame[1]}"
                #frame_number=$(bc <<< "scale=8; $frame_number + 1")
                frame_time=$(bc <<< "scale=16; $frame_number / 60")
                next_frame_time=$(bc <<< "scale=16; ($frame_number + 1) / 60")
                #frame_number=$(bc <<< "scale=8; $frame_number / 30")
                frame_time=$(printf "%0.8f" "$frame_time")
                next_frame_time=$(printf "%0.8f" "$next_frame_time")
                echo "$frame_time-$next_frame_time
                drawtext@1 text 'Axis: $axis ($axis_name=$frame_value) @ Frame № $frame_number',
                drawtext@1 x (w-tw),
                drawtext@1 y (h-th),
                drawtext@1 reload 0,
                drawtext@1 fontcolor white,
                drawtext@1 fontsize 14,
                drawtext@1 fontfile /usr/share/fonts/TTF/DejaVuSansMono.ttf,
                drawtext@t rate 60;
                
                " >> "drawtext.txt"
            done <<< "$FRAMES"
            ffmpeg ${FFMPEG_OPTS[@]} \
                -framerate 60 -i "%d.png" \
                -f lavfi -i color=color="$SPECIMEN_BG_COLOR":s="$EXTENT":rate=60 \
                -filter_complex '[0:v]format=yuva420p[v];
                [v]sendcmd=filename=drawtext.txt,drawtext@1=text=overwritten[o];
                [o]format=nv12[o];' \
                -map '[o]' \
                -c:v "$VCODEC" -b:v 2000k -fps_mode:v cfr -an -sn ${LOG_TO_DBG[@]} \
                "$OUTVIDEO"
            popd
            mv "$TEMPDIR/$OUTVIDEO" .
            i=$((i+1))
        done
    done
}

ffmpeg_setup
frames_setup

cleanup() {
    rm -f "$INTXT" || true
}

trap cleanup EXIT
trap cleanup SIGINT
trap cleanup SIGTERM

make_vf_specimens
cleanup

[[ -n "$DEBUG" ]] && set +x || true

./vstack.bash *.mp4

exit 0

# vim: set ts=4 sw=4 tw=0 et syntax=bash :
