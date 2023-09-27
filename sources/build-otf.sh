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
GENERATING OTF
."
genotf() {
	TT_DIR=../fonts/otf
	rm -rf $TT_DIR
	mkdir -p $TT_DIR

	instances="$(xidel -e '//instances/instance/@name' designspace/MFEK-Sans.designspace)"
	parallel --bar "
	fontmake -m designspace/$fontName.designspace -i {} -o otf --output-dir $TT_DIR
	" <<< "$instances"
}

[ -z "$NO_REBUILD" ] && genotf

genotf() {
	TT_DIR=../fonts/otf

	instances="$(xidel -e '//instances/instance/@name' designspace/MFEK-Sans-Italic.designspace)"
	parallel --bar "
	fontmake -m designspace/$fontName_it.designspace -i {} -o otf --output-dir $TT_DIR
	" <<< "$instances"
}

[ -z "$NO_REBUILD" ] && genotf

##########################################

echo ".
POST-PROCESSING OTF
."
otfs=$(ls $TT_DIR/*.otf)
parallel --bar "
	psautohint {} -o {}.fix
	[ -f {}.fix ] && mv {}.fix {}
	gftools fix-hinting {}
	[ -f {}.fix ] && mv {}.fix {}
" <<< "$otfs"


##########################################

rm -rf instance_ufo/ master_ufo/

echo ".
COMPLETE!
."
