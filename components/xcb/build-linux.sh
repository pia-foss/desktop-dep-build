#! /usr/bin/env bash

COMPROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set -e

cd "$COMPROOT"

source "../../util/submodule.sh"

rm -rf out
mkdir -p out/build
mkdir -p out/install

PREFIX="$COMPROOT/out/install"
# Set PKG_CONFIG_PATH so all the later libxcb packages can find the prior builds
export PKG_CONFIG_PATH="$COMPROOT/out/install/lib/pkgconfig"

function build_submodule() {
    local SUBMODULE="$1"

    echo "===xcb: Build $SUBMODULE==="
    prep_submodule "$SUBMODULE" "$COMPROOT/out/build"
    pushd "$COMPROOT/out/build/$SUBMODULE"
    ./autogen.sh --prefix="$PREFIX"
    make
    make install
    popd
}

# xcbproto is the base X protocol definition, must precede libxcb
build_submodule xcbproto
build_submodule libxcb
# Build util next since others require it
build_submodule libxcb-util
# Then build everything else
build_submodule libxcb-image
build_submodule libxcb-keysyms
build_submodule libxcb-render-util
build_submodule libxcb-wm
