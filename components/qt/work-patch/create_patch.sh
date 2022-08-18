#! /usr/bin/env bash

set -e

cd "$(dirname "${BASH_SOURCE[@]}")"

function show_usage() {
    echo "usage:"
    echo "  $0 <patchname>"
    echo "  $0 --help"
    echo ""
    echo "Create a patch called <patchname.patch> from files previously set up by add_patch.sh"
    echo "  $0 0001-Fix-missing-macos-inclusion"
    echo "  $0 0002-Fix-macos-stat64"
}

if [ "$#" -lt 1 ]; then
    show_usage
    exit 1
fi

PATCHNAME=
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

if ! [ -d "work/$PATCHNAME/orig" ] || ! [ -d "work/$PATCHNAME/new" ]; then
    echo "Set up the files to patch first with:"
    echo "./prep_patch.sh '$PATCHNAME' <qt-files>"
    exit 1
fi

pushd "work/$PATCHNAME"
# Diff returns 1 meaning "differences found" which is really success here.
# 2+ indicate errors.  0 indicates no differences, which is unexpected here.
DIFF_RESULT="0"
diff -ur orig/ new/ >"../../../patch-qt/$PATCHNAME.patch" || DIFF_RESULT="$?"
popd

ls -alh "../patch-qt/$PATCHNAME.patch"

if [ "$DIFF_RESULT" -eq 0 ]; then
    echo "No differences found - empty patch generated"
    echo "Did you edit the files in 'work/$PATCHNAME/new'?"
elif [ "$DIFF_RESULT" -gt 1 ]; then
    echo "Diff returned $DIFF_RESULT, generated patch may be invalid"
fi
