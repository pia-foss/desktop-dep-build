#! /usr/bin/env bash

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

SCRIPT="$(basename "${BASH_SOURCE[0]}")"
die() { echo "$SCRIPT:" "$*" 1>&2; exit 1; }

source util/platform.sh

OUT="$ROOT/out/${PLATFORM}_$ARCH"
ARTIFACTS="$OUT/artifacts"

rm -rf "$OUT"
mkdir -p "$ARTIFACTS"

# Map of all build components to 'y' or 'n' indicating whether they're being
# built.
# Bash 3 on macOS lacks associative arrays, so emulate one with discrete
# variables of the form "BUILD_COMP_<name>"
function get_build_comp() {
    VAR="BUILD_COMP_$1"
    echo "${!VAR}"
}
function should_build() {
    if [ "$(get_build_comp "$1")" = 'y' ]; then
        return 0
    fi
    return 1
}

function is_component() {
    if [ -n "$(get_build_comp "$1")" ]; then
        return 0
    fi
    return 1
}

function set_build() {
    COMP="$1"
    VAL="$2"
    printf -v "BUILD_COMP_$COMP" "%s" "$VAL"
}

set_build patchelf "n" # Linux only
set_build openvpn "n" # Includes OpenSSL
set_build unbound "n" # Includes hnsd
set_build shadowsocks "n"
set_build wireguard "n"
set_build xcb "n" # Linux only
set_build qt "n" # Linux only, includes libicu

function set_default_build() {
    set_build openvpn "y"
    set_build unbound "y"
    set_build shadowsocks "y"
    set_build wireguard "y"

    if [ "$PLATFORM" == "linux" ]; then
        set_build patchelf "y"
        set_build xcb "y"
        set_build qt "y"
    fi
}

function show_usage() {
    echo "usage:"
    echo "  Build everything:"
    echo "    $0"
    echo "  Skip specific components ('--skip qt' skips Qt):"
    echo "    $0 --skip <component> [<component>...]"
    echo "  Build only specific components:"
    echo "    $0 --build <component> [<component>...]"
    echo "  Show help:"
    echo "    $0 --help"
    echo ""
    echo "Builds external dependencies for PIA Desktop.  Artifacts are placed"
    echo "in out/artifacts."
    echo ""
    echo "Components:"
    echo "  patchelf (Linux only)"
    echo "  openvpn (includes OpenSSL)"
    echo "  unbound (includes hnsd)"
    echo "  shadowsocks"
    echo "  wireguard"
    echo "  xcb (Linux only)"
    echo "  qt (Linux only, includes libicu, requires patchelf/openvpn/xcb)"
    echo ""
    echo "Parameters:"
    echo "  --build <component> [<component>...]: Build only the specified"
    echo "    components.  Note that patchelf is needed for most builds on"
    echo "    Linux.  Qt depends on OpenSSL from the OpenVPN build and libxcb."
    echo "    If dependencies aren't specified, it's assumed that they were"
    echo "    already built."
    echo "  --skip <component> [<component>...]: Build everything except the"
    echo "    specified components.  Like with --build, dependencies that are"
    echo "    excluded are assumed to have already been built."
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

# What to do when a component name is observed on the command line
# - "y" enable builds for specified components
# - "n" disable builds for specified components
# - "default" neither --build nor --skip specified, use default components
CLI_COMPONENT_MODE="default"

while [ "$#" -ge 1 ]; do
    case "$1" in
        --help)
            show_usage
            exit 0
            shift
            ;;
        --build)
            if [ "$CLI_COMPONENT_MODE" != "default" ]; then
                echo "Only one --build/--skip option can be specified" >&2
                exit 1
            fi
            # Don't apply default components; enable anything that was listed
            CLI_COMPONENT_MODE="y"
            shift
            ;;
        --skip)
            if [ "$CLI_COMPONENT_MODE" != "default" ]; then
                echo "Only one --build/--skip option can be specified" >&2
                exit 1
            fi
            # Use default components, then disable anything that was listed
            set_default_build
            CLI_COMPONENT_MODE="n"
            shift
            ;;
        *)
            if is_component "$1" && [ "$CLI_COMPONENT_MODE" != "default" ]; then
                set_build "$1" "$CLI_COMPONENT_MODE"
                shift
            else
                echo "Unknown option: $1" >&2
                exit 1
            fi
            ;;
    esac
done

if [ "$CLI_COMPONENT_MODE" = "default" ]; then
    set_default_build
fi

function print_build() {
    if should_build "$1"; then
        echo "  $1"
    fi
}

echo "Building for $PLATFORM $ARCH:"
print_build patchelf
print_build openvpn
print_build unbound
print_build shadowsocks
print_build wireguard
print_build xcb
print_build qt
echo ""

function first() {
    echo "$1"
}
# Test if a glob matches anything.  For example:
#     if any "out/artifacts"/*.full; then
#         mv "out/artifacts"/*.full "out/debug/"
#     fi
#
# Works just by testing if $1 exists - if it does, the glob matched and was
# expanded; if it does not, then we got the glob itself which matched nothing.
function glob_any() {
    if [ -e "$1" ]; then
        return 0
    fi
    return 1
}

# Check build dependencies - warn if we're building a dependant but not a
# dependency, this is OK for testing but the final build should usually be
# rebuilt to ensure everything is up to date

# patchelf is used for nearly everything on Linux
if [ "$PLATFORM" == "linux" ] && ! should_build patchelf; then
    echo "WARNING: using prior build output for patchelf dependency" >&2
fi
# Qt uses OpenSSL from the OpenVPN build and libxcb
if should_build qt; then
    if ! should_build openvpn; then
        echo "WARNING: using prior build output for OpenSSL dependency" >&2
    fi
    if ! should_build xcb; then
        echo "WARNING: using prior build output for libxcb dependency" >&2
    fi
fi
echo ""

if should_build patchelf; then
    echo "===Build patchelf==="
    pushd components/patchelf
    ./build-linux.sh
    popd
fi
if [ "$PLATFORM" == "linux" ]; then
    # Override patchelf in PATH with the one built for all subsequent builds
    PATCHELF_BIN="$(pwd)/components/patchelf/out/install/bin"
    export PATH="$PATCHELF_BIN:$PATH"
fi

if should_build openvpn; then
    echo "===Build OpenVPN and OpenSSL==="
    pushd components/openvpn24
    ./build-posix.sh
    popd

    if [ "$PLATFORM" == "linux" ]; then
        # OpenVPN artifacts have bin/lib subdirectories on Linux
        # Use -d to preserve versioned symlinks for libs
        cp -d "components/openvpn24/out/artifacts/$PLATFORM"/{bin,lib}/* "$ARTIFACTS"
    else
        cp "components/openvpn24/out/artifacts/$PLATFORM"/* "$ARTIFACTS"
    fi
fi

if should_build unbound; then
    echo "===Build Unbound and hnsd==="
    pushd components/hnsd
    ./build-posix.sh
    popd
    # Collect artifacts
    cp "components/hnsd/out/artifacts/$PLATFORM"/* "$ARTIFACTS"
fi

if should_build shadowsocks; then
    echo "===Build Shadowsocks==="
    pushd components/shadowsocks
    ./build-posix.sh
    popd
    # Collect artifacts
    cp "components/shadowsocks/out/artifacts/$PLATFORM"/* "$ARTIFACTS"
fi

if should_build wireguard; then
    echo "===Build WireGuard==="
    pushd components/wireguard
    eval "$(select_platform N/A ./scripts/build-mac.sh ./scripts/build-linux.sh)"
    popd
    # Collect artifacts
    cp "components/wireguard/out/artifacts"/* "$ARTIFACTS"
    mv "$ARTIFACTS/wireguard-go" "$ARTIFACTS/pia-wireguard-go"
fi

if should_build xcb; then
    echo "===Build xcb==="
    pushd components/xcb
    ./build-linux.sh
    popd
    # Collect xcb libs (just dynamic libs, ignore static libs)
    # Use -d to preserve versioned symlinks for libs
    cp -d "components/xcb/out/install/lib/"*.so* "$ARTIFACTS"
fi

# ICU and Qt are only built on Linux and can be skipped with --skip qt
if should_build qt; then
    echo "===Build ICU and Qt==="
    pushd components/qt
    # Use the copy of OpenSSL built by OpenVPN, use the xcb libraries built
    # above, and include patchelf in the Qt bundle
    time ./build-linux.sh '--extra-bin' "$PATCHELF_BIN/patchelf" \
        "../../components/openvpn24/out/build/$PLATFORM/openvpn" \
        "../../components/xcb/out/install"
    popd

    QT_PACKAGE="$(first "components/qt/out/artifacts"/qt-*.run)"
    mkdir -p "$OUT/installers"
    mv "$QT_PACKAGE" "$OUT/installers"
fi


# Separate unstripped binaries on Linux (stripping isn't done on macOS)
if [ "$PLATFORM" != "macos" ]; then
    mkdir -p "$OUT/debug"
    if glob_any "$ARTIFACTS"/*.full; then
        mv "$ARTIFACTS"/*.full "$OUT/debug"
    fi
fi
