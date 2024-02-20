#!/bin/bash

# Only needed when relying on a local install of mkvtoolnix
# which mkvmerge >/dev/null
# if [[ $? == 1 ]]
# then
#     echo "Run 'brew install mkvtoolnix' to install mkvmerge"
#     exit 1
# fi
# which mkvextract >/dev/null
# if [[ $? == 1 ]]
# then
#     echo "Run 'brew install mkvtoolnix' to install mkvextract"
#     exit 1
# fi

# Keep working files generated during processing
keepFiles=false

while true
do
    case "$1" in
    --keep-files)
        echo "Option enabled to keep working files"
        keepFiles=true
        shift;;
    "")
        break;;
    *)
        targetDir=$1
        shift;;
    esac
done

if [[ ! -d $targetDir ]]
then
    echo "Directory not found: '$targetDir'"
    exit 1
fi

echo "Processing directory: '$targetDir'"

# Get the script's directory path; do this before pushing the targetDir
scriptDir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

pushd "$targetDir" > /dev/null

# Get the subdirectory paths
toolsPath=$scriptDir/tools
configPath=$scriptDir/config

# Reference the dovi_tool, mkvextract, and mkvmerge executables and the JSON file in their respective subdirectories
languageCodesPath=$toolsPath/language_codes.applescript
doviToolPath=$toolsPath/dovi_tool
mkvextractPath=$toolsPath/mkvextract
mkvmergePath=$toolsPath/mkvmerge
jsonFilePath=$configPath/DV7toDV8.json

languageCodes=$(osascript "$languageCodesPath")

for mkvFile in "$targetDir"/*.mkv
do
    mkvBase=$(basename "$mkvFile" .mkv)

    echo "Demuxing BL+EL+RPU HEVC from MKV..."
    "$mkvextractPath" "$mkvFile" tracks 0:"$mkvBase.BL_EL_RPU.hevc"

    if [[ $? != 0 ]] || [[ ! -f "$mkvBase.BL_EL_RPU.hevc" ]]
    then
        echo "Failed to extract HEVC track from MKV. Quitting."
        exit 1
    fi

    echo "Demuxing DV7 EL+RPU HEVC..."
    "$doviToolPath" demux --el-only "$mkvBase.BL_EL_RPU.hevc" -e "$mkvBase.DV7.EL_RPU.hevc"

    if [[ $? != 0 ]] || [[ ! -f "$mkvBase.DV7.EL_RPU.hevc" ]]
    then
        echo "Failed to demux EL+RPU HEVC file. Quitting."
        exit 1
    fi

    echo "Converting BL+EL+RPU to DV8 BL+RPU..."
    "$doviToolPath" --edit-config "$jsonFilePath" convert --discard "$mkvBase.BL_EL_RPU.hevc" -o "$mkvBase.DV8.BL_RPU.hevc"

    if [[ $? != 0 ]] || [[ ! -f "$mkvBase.DV8.BL_RPU.hevc" ]]
    then
        echo "File to convert BL+RPU. Quitting."
        exit 1
    fi

    echo "Deleting BL+EL+RPU HEVC..."
    if [[ $keepFiles == false ]]
    then
        rm "$mkvBase.BL_EL_RPU.hevc"
    fi

    echo "Extracting DV8 RPU..."
    "$doviToolPath" extract-rpu "$mkvBase.DV8.BL_RPU.hevc" -o "$mkvBase.DV8.RPU.bin"

    echo "Plotting L1..."
    "$doviToolPath" plot "$mkvBase.DV8.RPU.bin" -o "$mkvBase.DV8.L1_plot.png"

    echo "Remuxing DV8 MKV..."
    if [[ $languageCodes != "" ]]
    then
        echo "Remuxing audio and subtitle languages: $languageCodes"
        "$mkvmergePath" -o "$mkvBase.DV8.mkv" -D -a $languageCodes -s $languageCodes "$mkvFile" "$mkvBase.DV8.BL_RPU.hevc" --track-order 1:0
    else
        "$mkvmergePath" -o "$mkvBase.DV8.mkv" -D "$mkvFile" "$mkvBase.DV8.BL_RPU.hevc" --track-order 1:0
    fi

    if [[ $keepFiles == false ]]
    then
        echo "Cleaning up..."
        rm "$mkvBase.DV8.RPU.bin" 
        rm "$mkvBase.DV8.BL_RPU.hevc"
    fi
done

popd > /dev/null
echo "Done."
