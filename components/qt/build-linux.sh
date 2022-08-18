#! /usr/bin/env bash

# Copyright (c) 2022 Private Internet Access, Inc.
#
# This file is part of the Private Internet Access Desktop Client.
#
# The Private Internet Access Desktop Client is free software: you can
# redistribute it and/or modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation, either version 3 of
# the License, or (at your option) any later version.
#
# The Private Internet Access Desktop Client is distributed in the hope that
# it will be useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with the Private Internet Access Desktop Client.  If not, see
# <https://www.gnu.org/licenses/>.

set -e

QT_MAJOR=5
QT_MINOR=15
QT_PATCH=2

QT_VERSION="$QT_MAJOR.$QT_MINOR.$QT_PATCH"
# Disk space required to build Qt (approximate).  The out/ directory
# is usually around 40 GiB for a complete build.
DISK_SPACE_NEEDED=40 # In GiB

source ../../util/platform.sh

function show_usage() {
    echo "usage:"
    echo "$0 [--rebuild] [--repack] [--extra-bin bin_path] [--extra-install path] [--extra_prefix path] [...]"
    echo "$0 --help"
    echo ""
    echo "Builds Qt on Linux for use in PIA Desktop."
    echo "Source is downloaded from download.qt.io and cached in out/cache/."
    echo ""
    echo "Parameters:"
    echo "  --rebuild: Don't clean output, skip verify + extract, and try to"
    echo "    build again.  Useful when iterating on build script, but not"
    echo "    guaranteed to work - perform a clean build to obtain final"
    echo "    build artifacts."
    echo "  --repack: Additionally skips build entirely, just regenerate the"
    echo "    install package.  (Implies --rebuild.)"
    echo "  --extra-bin: Add a binary to the bin/ directory of the bundle."
    echo "    (Used by desktop-dep-build to include patchelf.)"
    echo "    Can be passed multiple times."
    echo "  --extra-install: Include the contents of this directory into the Qt"
    echo "    installation (should contain bin/, lib/, include/, etc., which"
    echo "    will be combined with Qt.)  Used to bundle libicu on Linux.  The"
    echo "    directory is also used as an include/lib prefix (--extra-prefix)."
    echo "    Can be passed multiple times."
    echo "  --extra_prefix: Path to an extra installation prefix add to include"
    echo "    and lib paths when building Qt.  This can be used to configure Qt"
    echo "    with a specific version of OpenSSL, etc."
    echo "    If this isn't provided, Qt will use the system libraries for all"
    echo "    dependencies."
    echo "    Can be passed multiple times."
    echo "  --help: Shows this help."
    echo ""
}

function realpath_compat() {
    ARG="$1"

    case "$PLATFORM" in
        linux)
            realpath "$1"
            ;;
        *)
            local REALDIR
            REALDIR="$(cd "$(dirname "$ARG")" && pwd)"
            echo "$REALDIR/$(basename "$ARG")"
            ;;
    esac
}

function sha256sum_compat() {
    case "$PLATFORM" in
        linux)
            sha256sum "$@"
            ;;
        macos)
            shasum -a 256 "$@"
            ;;
    esac
}

function diskfree_gb() {
    case "$PLATFORM" in
        linux)
            df -BG -P "$1" | awk 'NR==2 { print substr($4, 1, length($4)-1) }'
            ;;
        macos)
            df -g "$1" | awk 'NR==2 { print $4 }'
            ;;
    esac
}

function disk_vol() {
    df "$1" | awk 'NR==2 { print $1 }'
}

EXTRA_BINS=()
EXTRA_INSTALLS=()
EXTRA_PREFIXES=()
ARGS_DONE=0
while [ "$#" -gt 0 ] && [ "$ARGS_DONE" -ne "1" ]; do
    case "$1" in
        "--help")
            show_usage
            exit 0
            ;;
        "--rebuild")
            SKIP_CLEAN=1
            shift
            ;;
        "--repack")
            SKIP_CLEAN=1
            SKIP_BUILD=1
            shift
            ;;
        "--extra-bin")
            EXTRA_BINS+=("$(realpath_compat "$2")")
            shift
            shift
            ;;
        "--extra-install")
            EXTRA_INSTALLS+=("$(realpath_compat "$2")")
            shift
            shift
            ;;
        "--extra-prefix")
            EXTRA_PREFIXES+=("$(realpath_compat "$2")")
            shift
            shift
            ;;
        "--")
            ARGS_DONE=1
            shift
            ;;
        "--"*)
            echo "Unknown option: $1" >&2
            show_usage
            exit 1
            ;;
        *)
            ARGS_DONE=1
            # Don't shift, this is the first positional argument
            ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

QT_BUILD_NAME="clang_$ARCH"
if [ "$ARCH" == 'x86_64' ]; then
    QT_BUILD_NAME="clang_64"
fi
QT_INSTALL_ROOT="$ROOT/out/install/$QT_VERSION/$QT_BUILD_NAME"

set -e

mkdir -p out

if [ -z "$SKIP_CLEAN" ]; then
    # Don't clean out/cache, caches Qt source archive
    echo "Cleaning output from prior build"
    rm -rf out/build
    rm -rf out/install
    rm -rf out/artifacts

    # Check free space - building Qt requires a lot of disk space, no sense
    # building for 6+ hours just to run out
    FREE_SPACE="$(diskfree_gb out)"
    VOLUME="$(disk_vol out)"
    if [ "$FREE_SPACE" -lt "$DISK_SPACE_NEEDED" ]; then
        echo "Building Qt requires approximately $DISK_SPACE_NEEDED GiB." >&2
        echo "This volume ($VOLUME) has $FREE_SPACE GiB free." >&2
        echo "Free space and try again." >&2
        exit 1
    fi
    echo "Free space on $VOLUME: $FREE_SPACE GiB ($DISK_SPACE_NEEDED GiB needed)."
fi

mkdir -p out/cache
mkdir -p out/build
mkdir -p out/install
mkdir -p out/artifacts

# Help out the Qt build scripts to find python.  QtQml really needs an
# executable called 'python', but some distributions only have python3 or
# python2.
rm -rf out/tools
mkdir -p out/tools
export PATH="$PATH:$ROOT/out/tools"

if hash python; then
    echo "Found python: $(command -v python)"
elif hash python3; then
    PYTHON3="$(command -v python3)"
    echo "Found python3: $PYTHON3"
    ln -s "$PYTHON3" out/tools/python
elif hash python2; then
    PYTHON2="$(command -v python2)"
    echo "Found python2: $PYTHON2"
    ln -s "$PYTHON2" out/tools/python
else
    echo "Python (one of python, python2, or python3) is needed to build QtQml." >&2
    exit 1
fi

# Download the Qt source archive if it's not already present
QT_SOURCE_ARCHIVE=out/cache/qt-everywhere-src-$QT_VERSION.tar.xz
if ! [ -f "$QT_SOURCE_ARCHIVE" ]; then
    echo "Downloading Qt $QT_VERSION source"
    curl -L -o "$QT_SOURCE_ARCHIVE" https://download.qt.io/official_releases/qt/$QT_MAJOR.$QT_MINOR/$QT_VERSION/single/qt-everywhere-src-$QT_VERSION.tar.xz
fi

# If --rebuild/--repack was given, skip the verify+extract steps and use the
# existing extracted source
if [ -z "$SKIP_CLEAN" ]; then
    # Verify the source archive
    echo "Verifying Qt $QT_SOURCE_ARCHIVE"
    QT_SOURCE_ACTUAL="$(pv "$QT_SOURCE_ARCHIVE" | sha256sum_compat | awk '{print $1}')"
    QT_SOURCE_EXPECTED="3a530d1b243b5dec00bc54937455471aaa3e56849d2593edb8ded07228202240"

    if [ "$QT_SOURCE_ACTUAL" != "$QT_SOURCE_EXPECTED" ]; then
        echo "Qt source archive does not match expected hash:" >&2
        echo "  actual:   $QT_SOURCE_ACTUAL" >&2
        echo "  expected: $QT_SOURCE_EXPECTED" >&2
        exit 1
    fi

    mkdir -p out/build/qt

    # This takes a while, feeding the input to tar through pv shows progress
    # information
    echo "Extracting $QT_SOURCE_ARCHIVE"
    pv "$QT_SOURCE_ARCHIVE" | tar --xz -xf - -C out/build/qt

    echo "Applying patches..."
    for patch in patch-qt/*; do
        echo "Applying $patch"
        (cd out/build/qt/qt-everywhere-* && patch -p 1) <"$patch"
    done
fi

if [ -z "$SKIP_BUILD" ]; then
    EXTRA_PREFIX_ARGS=()
    LIBPATH_VAR="$(select_platform none DYLD_LIBRARY_PATH LD_LIBRARY_PATH)"
    for p in "${EXTRA_PREFIXES[@]}" "${EXTRA_INSTALLS[@]}"; do
        EXTRA_PREFIX_ARGS+=(-I "$p/include" -L "$p/lib")
        OLDLIBPATH="${!LIBPATH_VAR}"
        export "$LIBPATH_VAR"="${OLDLIBPATH:+$OLDLIBPATH:}$p/lib"
    done

    echo "Extra prefix args:" "${EXTRA_PREFIX_ARGS[@]}"
    echo "$LIBPATH_VAR: ${!LIBPATH_VAR}"

    pushd out/build/qt/qt-everywhere-src-$QT_VERSION
    echo "Configure Qt $QT_VERSION"
    # For Qt's reference CI configurations, refer to:
    # https://code.qt.io/cgit/qt/qt5.git/tree/coin/platform_configs/default.yaml?h=5.15
    # Qt ships the RHEL build as their binary installer on Linux.
    [ "$PLATFORM" = linux ] && ./configure \
        -confirm-license -opensource \
        -release \
        -nomake tests -nomake examples \
        -no-libudev \
        -no-use-gold-linker \
        -force-debug-info -separate-debug-info \
        -no-sql-mysql -plugin-sql-psql -plugin-sql-sqlite \
        -qt-libjpeg \
        -qt-libpng \
        -xcb \
        -system-freetype \
        -bundled-xcb-xinput \
        -sysconfdir /etc/xdg \
        -qt-pcre \
        -qt-harfbuzz \
        -skip doc -skip webchannel -skip webengine -skip webview -skip sensors -skip serialport \
        -R . \
        -openssl \
        "${EXTRA_PREFIX_ARGS[@]}" \
        QMAKE_LFLAGS_APP+=-s \
        -prefix "$QT_INSTALL_ROOT" \
        -icu \
        -fontconfig \
        -platform linux-clang

    # linux opts
        #-no-libudev \
        #-no-use-gold-linker \
        #-xcb \
        #-system-freetype \
        #-bundled-xcb-xinput \
        #-icu \
        #-fontconfig \
    # changed
        #-sysconfdir /etc/xdg \
        #-platform linux-clang
        #-no-sql-psql

    # unsure
        #-qt-libjpeg \
        #-qt-libpng \
        #-qt-pcre \
        #-qt-harfbuzz \
        # fontconfig?
        # psql?
        #-icu \

    # TODO - add llvm freetype harfbuzz to homebrew package list
    # On macOS, we have to explicitly set QMAKE_APPLE_DEVICE_ARCHS=arm64 to get
    # an arm64 build (5.15.2 assumes x86_64 on macOS otherwise).
    #
    # We don't attempt cross builds of Qt; this is difficult to get working
    # since Qt needs some of its built tools to build (qmake, moc, etc.).  We
    # build Qt separately on x86_64 and arm64 hosts, then combine the two into a
    # universal build.
    [ "$PLATFORM" = macos ] && ./configure \
        -confirm-license -opensource \
        -release \
        QMAKE_APPLE_DEVICE_ARCHS="$(uname -m)" \
        -nomake tests -nomake examples \
        -force-debug-info -separate-debug-info \
        -no-sql-mysql -no-sql-psql -plugin-sql-sqlite \
        -qt-libjpeg \
        -qt-libpng \
        -sysconfdir /Library/Preferences/Qt \
        -qt-pcre \
        -qt-harfbuzz \
        -no-xcb \
        -skip doc -skip webchannel -skip webengine -skip webview -skip sensors -skip serialport \
        -R . \
        -openssl \
        "${EXTRA_PREFIX_ARGS[@]}" \
        QMAKE_LFLAGS_APP+=-s \
        -prefix "$QT_INSTALL_ROOT" \
        -platform macx-clang

    # Determine number of CPUs, amount of memory, and number of make jobs.  Use
    # no more than 1 job per ~1000 MB of RAM, many link steps consume a lot of
    # RAM, this can be limiting on small boards in particular
    JOBS="$(calc_jobs 1000)"
    echo "Build Qt $QT_VERSION with $JOBS jobs"
    make "-j$JOBS"

    echo "Installing to $QT_INSTALL_ROOT"
    make install
    popd

    # Include extra libs/headers in the Qt installation
    for p in "${EXTRA_PREFIXES[@]}" "${EXTRA_INSTALLS[@]}"; do
        cp -r "$p"/* "$QT_INSTALL_ROOT/"
    done

    # Include extra bins passed on command line
    if [ "${#EXTRA_BINS[@]}" -ne 0 ]; then
        cp "${EXTRA_BINS[@]}" "$QT_INSTALL_ROOT/bin/"
    fi

    # Indicate that this is a PIA Qt build, the PIA build script checks this
    # (/share doesn't always exist on macOS, but we still put the indicator there)
    mkdir -p "$QT_INSTALL_ROOT/share"
    touch "$QT_INSTALL_ROOT/share/pia-qt-build"
fi

# Make distribution archive
./make-installer-package.sh "$QT_VERSION" "$QT_BUILD_NAME" "$PLATFORM" "$ARCH" "$QT_INSTALL_ROOT"
