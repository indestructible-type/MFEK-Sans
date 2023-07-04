#!/bin/bash
. misc/init.sh

if [[ ! -d ../fonts/webfonts ]]; then
    mkdir ../fonts/webfonts
fi

parallel --bar '
    FA=`basename {}`
    FN=${FA::-4}
    fonttools ttLib.woff2 compress {} --output-file "../fonts/webfonts/$FN.woff2"
' <<< `ls ../fonts/ttf/* ../fonts/variable/*`
