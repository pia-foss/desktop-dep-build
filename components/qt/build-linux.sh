#! /usr/bin/env bash

# Copyright (c) 2021 Private Internet Access, Inc.
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

QT_MAJOR=5
QT_MINOR=15
QT_PATCH=2

QT_VERSION="$QT_MAJOR.$QT_MINOR.$QT_PATCH"
# Disk space required to build Qt (approximate).  The out/ directory has
# is usually around 40 GiB for a complete build.
DISK_SPACE_NEEDED=40 # In GiB

source ../../util/platform.sh

function show_usage() {
    echo "usage:"
    echo "$0 [--rebuild] [--repack] [--extra-bin bin_path] [extra_prefix [...]]"
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
    echo "  extra_prefix: Path to an extra installation prefix add to include/"
    echo "    lib paths when building Qt.  This can be used to configure Qt"
    echo "    with a specific version of OpenSSL, etc."
    echo "    If this isn't provided, Qt will use the system libraries for all"
    echo "    dependencies."
    echo "  --help: Shows this help."
    echo ""
}

EXTRA_BINS=()
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
            EXTRA_BINS+=("$(realpath "$2")")
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

EXTRA_PREFIXES=()
while [ -n "$1" ]; do
    EXTRA_PREFIXES+=("$(cd "$1" && pwd)")
    shift
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

QT_BUILD_NAME="clang_$ARCH"
if [ "$ARCH" == 'x86_64' ]; then
    QT_BUILD_NAME="clang_64"
fi
QT_INSTALL_ROOT="$ROOT/out/install/$QT_VERSION/$QT_BUILD_NAME"
ARCHIVE_NAME="qt-$QT_VERSION-pia.tar.xz"

set -e

mkdir -p out

if [ -z "$SKIP_CLEAN" ]; then
    # Don't clean out/cache, caches Qt source archive
    echo "Cleaning output from prior build"
    rm -rf out/build
    rm -rf out/install
    rm -rf out/artifacts
    rm -rf out/package

    # Check free space - building Qt requires a lot of disk space, no sense
    # building for 6+ hours just to run out
    FREE_SPACE="$(df -BG -P out | awk 'NR==2 { print substr($4, 1, length($4)-1) }')"
    VOLUME="$(df -BG -P out | awk 'NR==2 { print $1 }')"
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
mkdir -p out/package

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
    QT_SOURCE_ACTUAL="$(pv "$QT_SOURCE_ARCHIVE" | sha256sum | awk '{print $1}')"
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
fi

if [ -z "$SKIP_BUILD" ]; then
    echo "Build ICU"
    pushd icu
    ./build-linux.sh
    popd

    EXTRA_PREFIX_ARGS=()
    # Include the ICU we just built in the extra prefixes
    for p in "${EXTRA_PREFIXES[@]}" "$ROOT/icu/out/install"; do
        EXTRA_PREFIX_ARGS+=(-I "$p/include" -L "$p/lib")
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$p/lib"
    done

    echo "Extra prefix args:" "${EXTRA_PREFIX_ARGS[@]}"

    pushd out/build/qt/qt-everywhere-src-$QT_VERSION
    echo "Configure Qt $QT_VERSION"
    # For Qt's reference CI configurations, refer to:
    # https://code.qt.io/cgit/qt/qt5.git/tree/coin/platform_configs/default.yaml?h=5.15
    # Qt ships the RHEL build as their binary installer on Linux.
    ./configure \
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

    # Determine number of CPUs, amount of memory, and number of make jobs
    CPUS="$(grep -Ec '^processor[[:space:]]+:' /proc/cpuinfo)" # Counts number of processors in cpuinfo
    EXTRACPUJOBS=$(( ( CPUS / 2 < 4 ) ? CPUS / 2 : 4 )) # Add up to 4 extra jobs (or cpus/2 if smaller) to keep CPU busy
    CPUJOBS=$(( CPUS + EXTRACPUJOBS )) # Number of jobs based on CPU cores

    MEMKB="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
    MEMGB=$(( ( MEMKB + 512*1024 ) / (1024*1024) )) # Memory, in GB, rounded to nearest GB
    MEMJOBS="$MEMGB" # Use 1 job per GB of RAM at most
    # Use smaller of CPU job limit or RAM job limit
    JOBS=$(( CPUJOBS < MEMJOBS ? CPUJOBS : MEMJOBS ))
    echo "Detected $CPUS CPUs (suggests $CPUJOBS jobs) and $MEMGB GB RAM (suggests $MEMJOBS jobs)"
    echo "Build Qt $QT_VERSION with $JOBS jobs"
    make "-j$JOBS"

    echo "Installing to $QT_INSTALL_ROOT"
    make install
    popd

    # Include libicu in the Qt installation
    cp -r icu/out/install/* "$QT_INSTALL_ROOT/"

    # Include extra bins passed on command line
    if [ "${#EXTRA_BINS[@]}" -ne 0 ]; then
        cp "${EXTRA_BINS[@]}" "$QT_INSTALL_ROOT/bin/"
    fi

    # Indicate that this is a PIA Qt build, the PIA build script checks this
    touch "$QT_INSTALL_ROOT/share/pia-qt-build"
fi

# Make distribution archive
pushd "$QT_INSTALL_ROOT"
echo "Creating $ARCHIVE_NAME"
tar -c -f - ./* | pv -s "$(du -sb ./ | awk '{print $1}')" | xz > "$ROOT/out/package/$ARCHIVE_NAME"
popd

function script_subst() {
    sed "s/{{QT_VERSION}}/$QT_VERSION/g; s/{{QT_ARCHIVE}}/$ARCHIVE_NAME/g; s/{{QT_BUILD_NAME}}/$QT_BUILD_NAME/g" "$1" > "$2"
    chmod a+x "$2"
}

script_subst src/install.sh out/package/install.sh
script_subst src/extract.sh out/package/extract.sh

INSTALLER_NAME="out/artifacts/qt-$QT_VERSION-pia-$PLATFORM-$ARCH.run"
echo "Creating $INSTALLER_NAME"
# The makeself archive isn't compressed, the payload is already a compressed tar.xz
makeself/makeself.sh --nocomp --tar-quietly --keep-umask --tar-extra "--owner=0 --group=0 --numeric-owner" out/package "$INSTALLER_NAME" "Qt $QT_VERSION - Private Internet Access" "./install.sh"
