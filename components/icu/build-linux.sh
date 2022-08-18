#! /usr/bin/env bash

set -e

COMPROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$COMPROOT"

source "../../util/platform.sh"
source "../../util/submodule.sh"

check_submodule_clean icu

rm -rf out
mkdir -p out/build
mkdir -p out/install

prep_submodule icu out/build

mkdir -p out/build/make # out-of-source build
pushd out/build/make
../icu/icu4c/source/runConfigureICU Linux --prefix="$COMPROOT/out/install"
make
make install
popd

# Patch rpaths to $ORIGIN/../lib.  As usual, autotools can't handle the $ORIGIN
# in LDFLAGS; there's no point trying to build this correctly, just patch it
# after the fact.
for f in out/install/{bin,lib}/*; do
    # Skip directories (like out/install/lib/pkgconfig), symlinks (like
    # out/install/lib/libicuuc.so) and anything else that's not an ELF
    # (like out/install/bin/icu-config, which is a shell script)
    if [ -f "$f" ] && [ ! -h "$f" ] && [[ $(file "$f") =~ ELF ]]; then
        echo "$f"
        patchelf --set-rpath '$ORIGIN/../lib/' "$f"
        split_symbols "$f"
    fi
done
