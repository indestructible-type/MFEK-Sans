#!/bin/bash
#- largest-image.sh
# smallest-image.sh
###################
# (c) 2023 Fredrick R. Brennan <copypaste@kittens.ph>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

test -e "${BASH_SOURCE[0]}" || \
    { >&2 echo "ERROR: Could not find myself. Call a search party." >&2; exit 1; }
[[ -x "$(command -v perl)" ]] || { >&2 echo "ERROR: Perl is not installed." >&2; exit 1; }
[[ -x "$(command -v parallel)" ]] || { >&2 echo "ERROR: GNU Parallel is not installed." >&2; exit 1; }
[[ -x "$(command -v gm)" ]] || { >&2 echo "ERROR: GraphicsMagick is not installed." >&2; exit 1; }
MY_NAME=$(basename "${BASH_SOURCE[0]}")
case "$MY_NAME" in
    largest-image.sh)
        export MODE="max"
        ;;
    smallest-image.sh)
        export MODE="min"
        ;;
    *)
        >&2 echo "ERROR: Hi! My name is what? My name is who? My name is *bleep-boxes* … … $MY_NAME! Slim shady! \(This script must be named 'largest-image.sh' or 'smallest-image.sh'.\)"
        exit 1
        ;;
esac
_MODE="${MODE:-max}"
[ -t 1 ] && INTERACTIVE=0 || INTERACTIVE=1

ARGS=()
# Check if no arguments
if [ $# -eq 0 ]
then
    # Check if files on stdin by doing a non-blocking read
    read -t 0.005 -n 1 && {
        [ 0 -eq $INTERACTIVE ] && >&2 echo "Reading from stdin."
        mapfile -t ARGS < <(cat <(printf "%s" "$REPLY") /dev/stdin)
    } || {
        >&2 echo "No arguments supplied. Please specify the images."
        exit 1
    }
else
    ARGS=("$@")
fi

PARALLEL="${PARALLEL:-`which parallel`}"

case $_MODE in
    max)
        PIPELINE_COMMAND=`which tail`
        ;;
    min)
        PIPELINE_COMMAND=`which head`
        ;;
    *)
        >&2 echo "ERROR: Invalid mode. Please specify 'max' or 'min'."
        exit 1
        ;;
esac

[ $INTERACTIVE -eq 0 ] && PARALLEL_OPTIONS="--bar" || PARALLEL_OPTIONS=""
[ $INTERACTIVE -eq 0 ] && >&2 echo "Determining the ${_MODE}imum image size. This may take a while." || true

MODEIMUM_IMG=$(((sort -t $'\t' -n -k 1|\
    "$PIPELINE_COMMAND" -n 1) |
    awk -vFS=$"\t" -vOFS=$"\t" '{print $2}') < <($PARALLEL $PARALLEL_OPTIONS \
    $'gm identify -format "%w\t%h" {} 2>/dev/null | awk -vFS=$"\t" -vOFS=$"\t" -v Q={} "{print \\$1*\\$2, Q}"' ::: "${ARGS[@]}"))

__yuvmode() {
    TMPFILE=$(mktemp)
    declare -i -l width height
    IFS=$'\t' read width height < <(gm identify -format $'%w\t%h' "$MODEIMUM_IMG" 2>/dev/null)
    # If the image is already divisible by 2, don't resize
    [[ $((width%2)) -eq 0 ]] && [[ $((height%2)) -eq 0 ]] && return 0
    # Make divisible by 2
    width=$((width+(width%2)))
    height=$((height+(height%2)))
    >&2 echo gm convert "$MODEIMUM_IMG" -colorspace YUV -extent "${width}x${height}" "$TMPFILE"
    gm convert "$MODEIMUM_IMG" -colorspace YUV -extent "${width}x${height}" "$TMPFILE"
    >&2 echo "WARNING: Overwriting $MODEIMUM_IMG with YUV version."
    MODEIMUM_IMG_BAK="${MODEIMUM_IMG%%.*}.bak.${MODEIMUM_IMG##*.}"
    mv -v "$MODEIMUM_IMG" "$MODEIMUM_IMG_BAK"
    mv -v "$TMPFILE" "$MODEIMUM_IMG"
}

YUVMODE="${YUVMODE:-0}"

if [ $YUVMODE -eq 1 ]
then
    __yuvmode
fi

echo "$MODEIMUM_IMG"
