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

function show_usage() {
    echo "usage:"
    echo "$0 <qt_version> <qt_build_name> <platform_name> <arch_name> <qt_install_root>"
    echo "$0 --help"
    echo ""
    echo "Creates the self-installing Qt package for distribution."
    echo ""
    echo "Parameters:"
    echo "  <qt_version> - Qt version number, e.g. \"5.15.2\""
    echo "    (determines install location)"
    echo "  <qt_build_name> - Qt build installation directory, e.g. \"clang_64\""
    echo "    (determines install location)"
    echo "  <platform_name> - Platform name, e.g. \"macos\", \"linux\""
    echo "    (appears in artifact file name)"
    echo "  <arch_name> - Architecture name, e.g. \"x86_64\", \"arm64\""
    echo "    (appears in artifact file name)"
    echo "  <qt_install_root> - Path to built Qt installation"
    echo "    (files here are packaged in the artifact)"
    echo "  --help: Shows this help."
    echo ""
}

if [ "$#" -ne 5 ]; then
    show_usage
    exit 1
fi
if [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

QT_VERSION="$1"
QT_BUILD_NAME="$2"
PLATFORM_NAME="$3"
ARCH_NAME="$4"
QT_INSTALL_ROOT="$(cd "$5" && pwd)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

source ../../util/platform.sh

PKG_BUILD="out/package-$ARCH_NAME"
ARCHIVE_NAME="qt-$QT_VERSION-pia-$PLATFORM_NAME-$ARCH_NAME.tar.xz"

rm -rf "$PKG_BUILD"
mkdir -p "$PKG_BUILD"

# Make distribution archive
pushd "$QT_INSTALL_ROOT"
echo "Creating $ARCHIVE_NAME"
# BSD du cannot do block sizes lower than 512, get it in 1K and multiply
ARCHIVE_SIZE="$(du -sk ./ | awk '{print $1}')"
ARCHIVE_SIZE=$((ARCHIVE_SIZE * 1024))
tar -c -f - ./* | pv -s "$ARCHIVE_SIZE" | xz > "$ROOT/$PKG_BUILD/$ARCHIVE_NAME"
popd

function script_subst() {
    sed "s/{{QT_VERSION}}/$QT_VERSION/g; s/{{QT_ARCHIVE}}/$ARCHIVE_NAME/g; s/{{QT_BUILD_NAME}}/$QT_BUILD_NAME/g" "$1" > "$2"
    chmod a+x "$2"
}

script_subst src/install.sh "$PKG_BUILD/install.sh"
script_subst src/extract.sh "$PKG_BUILD/extract.sh"

INSTALLER_NAME="out/artifacts/qt-$QT_VERSION-pia-$PLATFORM_NAME-$ARCH_NAME.run"
echo "Creating $INSTALLER_NAME"
# The owner and group parameters to tar vary between BSD and GNU tar.  The
# syntax also varies, but both will accept '=0'
TAR_OWNER_ARG="$(select_platform n/a uid owner)"
TAR_GROUP_ARG="$(select_platform n/a gid group)"
# The makeself archive isn't compressed, the payload is already a compressed tar.xz
makeself/makeself.sh --nocomp --tar-quietly --keep-umask --tar-extra "--$TAR_OWNER_ARG=0 --$TAR_GROUP_ARG=0 --numeric-owner" "$PKG_BUILD" "$INSTALLER_NAME" "Qt $QT_VERSION - Private Internet Access" "./install.sh"
