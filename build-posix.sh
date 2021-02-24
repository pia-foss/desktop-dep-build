#! /usr/bin/env bash

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

SCRIPT="$(basename "${BASH_SOURCE[0]}")"
die() { echo "$SCRIPT:" "$*" 1>&2; exit 1; }

source util/platform.sh

OUT="$ROOT/out/$PLATFORM_$ARCH"
ARTIFACTS="$OUT/artifacts"

rm -rf "$OUT"
mkdir -p "$ARTIFACTS"

if [ "$PLATFORM" == "linux" ]; then
    BUILD_QT=1
fi

function show_usage() {
    echo "usage:"
    echo "  $0 [--no-qt]"
    echo "  $0 --help"
    echo ""
    echo "Builds external dependencies for PIA Desktop.  Artifacts are placed"
    echo "in out/artifacts."
    echo ""
    echo "Parameters:"
    echo "  --no-qt: Skip building Qt on Linux, only build other dependencies."
    echo "    (Qt takes a long time and a lot of disk space to build.)"
    echo ""
    echo "---Binary artifacts---"
    echo ""
    echo "  On all platforms, OpenVPN, OpenSSL, resolvers, Shadowsocks, and"
    echo "  WireGuard are built to binary artifacts that can be shipped with"
    echo "  PIA.  These artifacts go in pia_desktop/deps/built/$PLATFORM/$ARCH."
    echo ""
    echo "---Qt---"
    echo ""
    echo "  On Linux only, Qt is built to a self-extracting archive that can be"
    echo "  installed to build PIA.  The resulting package is similar to the"
    echo "  official Qt offline installers; it includes headers, libraries, and"
    echo "  build tools."
    echo ""
    echo "  libicu is also built and included in the Qt installer.  Qt is"
    echo "  configured for OpenSSL 1.1 (built by the OpenVPN build scripts)."
    echo "  OpenSSL is located dynamically by Qt at runtime, so this is not"
    echo "  included in the Qt installer."
    echo ""
    echo "  patchelf 0.11 is also built and included.  This is not directly"
    echo "  related to Qt but is used by PIA for Qt deployment on Linux, and"
    echo "  the version of patchelf included in Debian Stretch / Ubuntu 18.04"
    echo "  causes problems with strip (https://github.com/NixOS/patchelf/issues/10)"
}

while [ "$#" -gt 1 ]; do
    case "$1" in
        --help)
            show_usage
            exit 0
            ;;
        --no-qt)
            BUILD_QT=
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
    shift
done

echo "Building for $PLATFORM $ARCH"

function first() {
    echo "$1"
}

QTBUILD_EXTRA_ARGS=()

if [ "$PLATFORM" == "linux" ]; then
    echo "===Build patchelf==="
    pushd components/patchelf
    ./build-linux.sh
    popd
    # Override patchelf in PATH with the one built for all subsequent builds
    PATCHELF_BIN="$(pwd)/components/patchelf/out/install/bin"
    export PATH="$PATCHELF_BIN:$PATH"
    # Include patchelf in the Qt bundle
    QTBUILD_EXTRA_ARGS+=('--extra-bin' "$PATCHELF_BIN/patchelf")
fi

echo "===Build OpenVPN and OpenSSL==="
pushd components/openvpn24
./build-posix.sh
popd

echo "===Build Unbound and hnsd==="
pushd components/hnsd
./build-posix.sh
popd

echo "===Build Shadowsocks==="
pushd components/shadowsocks
./build-posix.sh
popd

echo "===Build WireGuard==="
pushd components/wireguard
"$(select_platform N/A ./scripts/build-mac.sh ./scripts/build-linux.sh)"
popd

# xcb is only built on Linux
if [ "$PLATFORM" == "linux" ]; then
    echo "===Build xcb==="
    pushd components/xcb
    ./build-linux.sh
    popd
fi

# ICU and Qt are only built on Linux and can be skipped with --no-qt
if [ -n "$BUILD_QT" ]; then
    echo "===Build ICU and Qt==="
    pushd components/qt
    # Use the copy of OpenSSL built by OpenVPN, and use the xcb libraries built
    # above
    time ./build-linux.sh "${QTBUILD_EXTRA_ARGS[@]}" \
        "../../components/openvpn24/out/build/$PLATFORM/openvpn" \
        "../../components/xcb/out/install"
    popd
fi

# Collect artifacts
cp \
    "components/hnsd/out/artifacts/$PLATFORM"/* \
    "components/shadowsocks/out/artifacts/$PLATFORM"/* \
    "components/wireguard/out/artifacts"/* \
    "$ARTIFACTS"

if [ "$PLATFORM" == "linux" ]; then
    # - OpenVPN artifacts have bin/lib subdirectories on Linux
    # - Collect xcb libs (just dynamic libs, ignore static libs)
    # - Use -d to preserve versioned symlinks for libs
    cp -d "components/openvpn24/out/artifacts/$PLATFORM"/{bin,lib}/* \
        "components/xcb/out/install/lib/"*.so* \
        "$ARTIFACTS"
else
    cp "components/openvpn24/out/artifacts/$PLATFORM"/* \
        "$ARTIFACTS"
fi

mv "$ARTIFACTS/wireguard-go" "$ARTIFACTS/pia-wireguard-go"

# Separate unstripped binaries on Linux (stripping isn't done on macOS)
if [ "$PLATFORM" != "macos" ]; then
    mkdir -p "$OUT/debug"
    mv "$ARTIFACTS"/*.full "$OUT/debug"
fi

if [ -n "$BUILD_QT" ]; then
    QT_PACKAGE="$(first "components/qt/out/artifacts"/qt-*.run)"
    mkdir -p "$OUT/installers"
    mv "$QT_PACKAGE" "$OUT/installers"
fi
