#! /usr/bin/env bash

set -e

cd "$(dirname "${BASH_SOURCE[@]}")"

function show_usage() {
    echo "usage:"
    echo "  $0 <patchname> [qt_source_path]"
    echo "  $0 --help"
    echo ""
    echo "Set up files to edit to create a patch called <patchname.patch>"
    echo "  $0 0001-Fix-missing-macos-inclusion qtbase/src/plugins/platforms/cocoa/qiosurfacegraphicsbuffer.h"
    echo "  $0 0002-Fix-macos-stat64 qt3d/src/3rdparty/assimp/contrib/zip/src/miniz.h"
    echo ""
    echo "Then use create_patch.sh <patchname> to create the patch"
}

if [ "$#" -lt 1 ]; then
    show_usage
    exit 1
fi

PATCHNAME=
QT_FILES=()
while [ "$#" -ge 1 ]; do
    case "$1" in
        --help)
            show_usage
            exit 0
            ;;
        *)
            PATCHNAME="$1"
            shift
            break
            ;;
    esac
done

while [ "$#" -ge 1 ]; do
    QT_FILES+=("$1")
    shift
done

function first() {
    echo "$1"
}

QT_SRC="$(first ../out/build/qt/qt-everywhere-src-*)"

if ! [ -d "$QT_SRC" ]; then
    echo "The Qt source needs to be staged by running the build script before using this script"
    exit 1
fi

# Make sure all files exist before doing anything
for QT_FILE in "${QT_FILES[@]}"; do
    if ! [ -f "$QT_SRC/$QT_FILE" ]; then
        echo "Couldn't find $QT_FILE in Qt source"
        echo "Check that it exists in $QT_SRC and try again"
        exit 1
    fi
done

# Copy the files
for QT_FILE in "${QT_FILES[@]}"; do
    mkdir -p "work/$PATCHNAME/orig/$(dirname "$QT_FILE")"
    mkdir -p "work/$PATCHNAME/new/$(dirname "$QT_FILE")"

    cp "$QT_SRC/$QT_FILE" "work/$PATCHNAME/orig/$QT_FILE"
    cp "$QT_SRC/$QT_FILE" "work/$PATCHNAME/new/$QT_FILE"

    ls -alh "work/$PATCHNAME/new/$QT_FILE"
done
echo

echo "Now edit files in work/$PATCHNAME/new, then do:"
echo "create_patch.sh '$PATCHNAME'"
