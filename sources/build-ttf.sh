#!/bin/bash
. misc/init.sh
set -e
#source ../env/bin/activate

fontName="MFEK-Sans"
fontName_it="MFEK-Sans-Italic"

##########################################

echo ".
CHECKING FOR SOURCE FILES
."
if [ -e ufo ]
then
    echo ".
USING EXISTING UFO SOURCE FILES
."
    UFO_SOURCES=true
else
    UFO_SOURCES=false
fi

##########################################

if [ $UFO_SOURCES = false ]; then
	source ./gen-sources.sh
fi

##########################################

echo ".
GENERATING TTF
."

genttf() {
	TT_DIR=../fonts/ttf
	rm -rf $TT_DIR
	mkdir -p $TT_DIR

	instances="$(xidel -e '//instances/instance/@name' designspace/MFEK-Sans.designspace)"
	parallel --bar "
	fontmake -m designspace/$fontName.designspace -i {} -o ttf --output-dir $TT_DIR
	" <<< "$instances"
}

[ -z "$NO_REBUILD" ] && genttf

genttf() {
	TT_DIR=../fonts/ttf

	instances="$(xidel -e '//instances/instance/@name' designspace/MFEK-Sans-Italic.designspace)"
	parallel --bar "
	fontmake -m designspace/$fontName_it.designspace -i {} -o ttf --output-dir $TT_DIR
	" <<< "$instances"
}

[ -z "$NO_REBUILD" ] && genttf

##########################################

echo ".
POST-PROCESSING TTF
."
ttfs=$(ls $TT_DIR/*.ttf)
parallel --bar "
	python3 -m ttfautohint {} {}.fix
	[ -f {}.fix ] && mv {}.fix {}
	gftools fix-hinting {}
	[ -f {}.fix ] && mv {}.fix {}
" <<< "$ttfs"


##########################################

rm -rf instance_ufo/ master_ufo/

find . | grep -E "(__pycache__|\.pyc|\.pyo$)" | xargs rm -rf

echo ".
COMPLETE!
."
