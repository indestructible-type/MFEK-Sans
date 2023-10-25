#!/bin/bash
# vstack.bash - Stack videos vertically
#################################################################
# This script stacks videos vertically. The videos are looped   #
# to match the duration of the longest video.                   #
#################################################################
OUTPUT_VIDEO="${OUTPUT_VIDEO:-output.mkv}"
FFMPEG="${FFMPEG:-`which ffmpeg`}"
FFMPEG_FLAGS="-hide_banner -loglevel error -y"

# Function to get the duration of a video in seconds
get_duration() {
    ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1"
}

# Function to get the frame rate of a video
get_framerate() {
    ffprobe -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "$1"
}

# Function to get the extents of a video
get_extents() {
    WIDTH=$(ffprobe -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=width "$1")
    HEIGHT=$(ffprobe -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=height "$1")
    echo "$WIDTH $HEIGHT"
}

# Function to get the number of frames in a video
get_frames() {
    ffprobe -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=nb_frames "$1"
}

# Reject inputs if not all framerates are the same
FRAMERATE=$(get_framerate "$1")
for file in "$@"; do
    if [[ "$file" == "$1" ]]; then
        continue
    fi
    framerate=$(get_framerate "$file")
    if [[ $framerate != $FRAMERATE ]]; then
        echo "All videos must have the same framerate"
        exit 1
    fi
done

longest_duration=0
longest_duration_file=""
max_width=0

# Get the longest duration and the maximum width
for file in "$@"; do
    >&2 echo "Processing $file"
    duration=$(get_frames "$file")
    if (( $(echo "$duration > $longest_duration" | bc -l) )); then
        longest_duration=$duration
        longest_duration_file=$file
    fi
    extents=$(get_extents "$file")
    width=$(echo "$extents" | cut -d' ' -f1)
    if (( $width > $max_width )); then
        max_width=$width
    fi
    >&2 echo "$file: $duration frames, $width width"
done

mkdir -p temp

ffmpeg() {
    >&2 echo "$FFMPEG" $FFMPEG_FLAGS "$@"
    $FFMPEG $FFMPEG_FLAGS "$@"
}

# Pad the videos to the maximum width
for file in "$@"; do
    extents=$(get_extents "$file")
    width=$(echo "$extents" | cut -d' ' -f1)
    height=$(echo "$extents" | cut -d' ' -f2)
    pad_width=$(( $max_width - $width ))
    ffmpeg -i "$file" -vf "pad=$max_width:$height:0:0" -y temp/"$file"
done

# Loop the videos to be longer than the longest video
for file in "$@"; do
    duration=$(get_frames "$file")
    loop_count=$(echo "($longest_duration / $duration)" | bc)
    if [[ "$duration" == "$longest_duration" ]]; then
        continue
    fi
    >&2 echo "Looping $file $loop_count times"
    ffmpeg -stream_loop $loop_count -i temp/"$file" -y temp/_"$file"
    mv temp/_"$file" temp/"$file"
done

# Stack the videos vertically
>&2 echo "Stacking videos. Longest duration: $longest_duration frames, $max_width width"
ffmpeg_inputs=""
for file in "$@"; do
    ffmpeg_inputs="$ffmpeg_inputs -i temp/$file"
done
ffmpeg $ffmpeg_inputs -t $longest_duration -filter_complex vstack=inputs=$(($#)):shortest=1 \
    -pix_fmt yuv420p -crf 18 -preset veryfast \
    -y -vcodec libx264 -an "$OUTPUT_VIDEO"

# Clean up
rm -rf temp
>&2 echo "Done. Output video: $OUTPUT_VIDEO"

[ -t 0 -a -t 1 ] && (
    read -p "Play video? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ffplay "$OUTPUT_VIDEO" -autoexit &
    fi
)
