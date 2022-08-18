#! /usr/bin/env bash

set -e

function show_usage() {
    echo "usage:"
    echo "  $0"
    echo "  $0 --help"
    echo ""
    echo "Combines the macOS artifacts from out/macos_x86_64 and out/macos_arm64"
    echo "into universal artifacts under out/macos_universal".
    echo ""
    echo "Perform each architecture build first (natively on a host of that arch,"
    echo "cross builds are not supported), then copy both output directories to"
    echo "one machine and run this script."
}

if [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi
if [ "$#" -ne 0 ]; then
    show_usage
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [ ! -d out/macos_x86_64 ] || [ ! -d out/macos_arm64 ]; then
    echo "Per-arch builds are not present in out/macos_x86_64 and out/macos_arm64"
    echo "Perform each build separately (on native hosts), then copy both builds"
    echo "to the same machine before running this script"
    exit 1
fi

function first() {
    echo "$1"
}

rm -rf out/macos_universal
mkdir -p out/macos_universal/artifacts
mkdir -p out/macos_universal/qtbuild
mkdir -p out/macos_universal/installers

# Combine artifacts under out/<arch>/artifacts.  These are just a handful of
# mach-o binaries, so we don't need to provide --header_condition or
# --install_subst
./util/lipo_recursive.rb \
    ./out/macos_x86_64/artifacts \
    ./out/macos_arm64/artifacts \
    ./out/macos_universal/artifacts

# Combine Qt installers under out/<arch>/installers
INST_PKG_NAME="$(basename "$(first ./out/macos_x86_64/installers/qt*.run)" -x86_64.run)"

if [[ $INST_PKG_NAME =~ qt-([0-9]+\.[0-9]+\.[0-9]+)-pia-macos ]]; then
    QT_VERSION="${BASH_REMATCH[1]}"
else
    echo "Couldn't extract Qt version from package name $INST_PKG_NAME"
    exit 1
fi

function extract_qt() {
    local ARCH QT_ARCH_SUFFIX ARCH_PKG ARCH_INSTALL
    ARCH="$1"
    QT_ARCH_SUFFIX="$2"
    ARCH_PKG="./out/macos_$ARCH/installers/$INST_PKG_NAME-$ARCH.run"
    ARCH_TMP="./out/macos_universal/qtbuild/tmp_$ARCH"
    ARCH_INSTALL="./out/macos_universal/qtbuild/clang$QT_ARCH_SUFFIX"

    # Extract the payload from the installer - don't run the install script
    mkdir -p "$ARCH_TMP"
    "$ARCH_PKG" --noexec --keep --target "$ARCH_TMP"
    # Then extract the actual installation
    mkdir -p "$ARCH_INSTALL"
    tar -xf "$(first "$ARCH_TMP"/*.tar.xz)" --xz -C "$ARCH_INSTALL"
    # Remove the temporary installer payload
    rm -rf "$ARCH_TMP"
}

extract_qt x86_64 _64
extract_qt arm64 _arm64

# Merge the two builds into a universal build
./util/lipo_recursive.rb \
    --header_condition '#ifndef __aarch64__' \
    --install_subst clang_64 clang_arm64 clang_universal \
    ./out/macos_universal/qtbuild/clang_{64,arm64,universal}

# Create a new installer package from the merged result
./components/qt/make-installer-package.sh "$QT_VERSION" clang_universal macos \
    universal ./out/macos_universal/qtbuild/clang_universal
mv ./components/qt/out/artifacts/*.run ./out/macos_universal/installers/

echo "Installers produced:"
ls -lh out/macos_universal/installers/
