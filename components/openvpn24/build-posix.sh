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

COMPROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set -e

function show_usage() {
cat << USAGE_END
usage:
  $0 <openssl_install>
  $0 --help

Builds OpenVPN for use in PIA Desktop.

Parameters:
  <openssl_install>: Path to the Openssl installation to use

USAGE_END
}

if [ "$#" -ne 1 ]; then
    show_help
    exit 1
fi

if [ "$0" = "--help" ]; then
    show_help
    exit 0
fi

OPENSSL_INST="$(cd "$1" && pwd)"

cd "$COMPROOT"

source ../../util/platform.sh
source ../../util/submodule.sh

die() { echo "${BASH_SOURCE[0]}:" "$*" 1>&2 ; exit 1; }

PLATFORM_CONFIG_ARGS=()

case "$PLATFORM" in
    linux)
        # Always use /sbin/ip, don't detect from the host - the host may have
        # ifconfig but some of our supported distributions do not.
        export IPROUTE=/sbin/ip
        PLATFORM_CONFIG_ARGS+=(
            "--enable-iproute2"
        )
        export EXTRA_OPENVPN_CONFIG='IPROUTE=/sbin/ip --enable-iproute2'
        ;;
    mingw*)
        # OpenVPN needs tap-windows.h on Windows.
        PLATFORM_CONFIG_ARGS+=(
            "TAP_CFLAGS=-I$COMPROOT/tap-windows-h"
        )
        ;;
esac

BUILD="$COMPROOT/out/build"
INSTALL="$COMPROOT/out/install"
ARTIFACTS="$COMPROOT/out/artifacts"

rm -rf out
mkdir -p "$BUILD"
mkdir -p "$INSTALL"
mkdir -p "$ARTIFACTS"

check_submodule_clean openvpn
prep_submodule openvpn "$BUILD"

JOBS="$(calc_jobs "")"

export OPENSSL_CFLAGS="-I$OPENSSL_INST/include"
export OPENSSL_LIBS="-L$OPENSSL_INST/lib -lssl -lcrypto"

pushd "$BUILD/openvpn"
autoreconf -i -v -f
./configure --disable-lzo --disable-lz4 --disable-plugins --disable-pkcs11 --enable-comp-stub --prefix="$INSTALL" "${PLATFORM_CONFIG_ARGS[@]}"
make -j"$JOBS"
# install-exec just installs the openvpn executable; the 'install' target would
# try to install docs even though 'make' skipped them due to lack of
# python-docutils
make install-exec
popd

cp "$INSTALL/sbin/openvpn" "$ARTIFACTS/pia-openvpn"

case "$PLATFORM" in
    linux)
        # Patch rpaths - there's no point trying to set these in the proper build,
        # the build scripts can't handle the dollar sign
        # Intentional single-quoted '$ORIGIN' below
        # shellcheck disable=SC2016
        patchelf --force-rpath --set-rpath '$ORIGIN/../lib/' "${ARTIFACTS}/pia-openvpn"
        ;;
esac

split_exe_symbols "$ARTIFACTS/pia-openvpn"

echo "Build completed:"
ls -lh "${ARTIFACTS}"
