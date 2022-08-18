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
    echo "$0 <openssl_install>"
    echo "$0 --help"
    echo ""
    echo "Builds unbound and hnsd for use in PIA Desktop."
    echo ""
    echo "Parameters:"
    echo "  <openssl_install>: Path to the OpenSSL installation to use (contains"
    echo "    bin, lib, etc.) - passed from main build script."
    echo "  --help: Shows this help"
    echo ""
}

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename "${__file}" .sh)"

die() { echo "${__base}:" "$*" 1>&2 ; exit 1; }

if [ "$#" -ne 1 ]; then
    show_help
    exit 1
fi

if [ "$0" = "--help" ]; then
    show_help
    exit 0
fi

OPENSSL_INST="$1"

cd "$__dir"
source ../../util/submodule.sh
source ../../util/platform.sh

# Set platform based on the host platform
case "$PLATFORM" in
    mingw64)
        # unbound's configure.ac checks for uname=MINGW32, but not MINGW64.
        # Pass --host and --build so it still detects MinGW.
        unbound_platform_cfgargs="--host=${MINGW_CHOST} --build=${MINGW_CHOST}"
        ;;
    mingw32)
        # In addition to the host/build tweak, MinGW32 is missing
        # lib/bfd-plugins/liblto_plugin-0.dll, use gcc-ar and gcc-ranlib instead
        # which know to load that plugin from the gcc lib directory
        unbound_platform_cfgargs="--host=${MINGW_CHOST} --build=${MINGW_CHOST} AR=gcc-ar RANLIB=gcc-ranlib"
        ;;
esac

output_dir="${__dir}/out/build/${PLATFORM}"
artifacts_dir="${__dir}/out/artifacts/${PLATFORM}"
build_dir="${__dir}/build.tmp"

# For quick iterations on the build script itself, setting REBUILD skips the
# clean and clone steps for build dirs that already exist.  It does _not_ make
# sure existing build directories are up to date with the submodules, though.
if [ -z "${REBUILD}" ]; then
    rm -rf "${output_dir}" "${artifacts_dir}" "${build_dir}"
fi

rm -rf "${output_dir}"

mkdir -p "${output_dir}"
mkdir -p "${artifacts_dir}"
mkdir -p "${build_dir}"

check_submodule_clean unbound
check_submodule_clean hnsd

prep_submodule unbound "$build_dir"
prep_submodule hnsd "$build_dir"

JOBS="$(calc_jobs "")"

echo "Building Unbound..."
pushd "${build_dir}/unbound"
# Rerun autoconf due to change to configure.ac
autoreconf -i -v -f
# Configure options
# - Use OpenSSL passed from main build script
# - Don't build shared objects (just build static libraries)
# - Always install to /usr/local prefix (default is different on MinGW)
# shellcheck disable=SC2086
# ^ Intentional wordsplitting of ${unbound_platform_cfgargs}
./configure --with-ssl="$OPENSSL_INST" --disable-shared --enable-static ${unbound_platform_cfgargs} --prefix="${output_dir}/unbound" --disable-flto
make -j"$JOBS"
make install
popd

echo "Building hnsd..."
pushd "${build_dir}/hnsd"
./autogen.sh
# mainnet does not exist yet.  testnet is currently the default.  We'll almost
# certainly switch to mainnet at our first chance, but we don't want the rug
# pulled out from under us.
./configure --with-network=testnet --with-unbound="${output_dir}/unbound"
make -j2

# Copy artifacts
cp "${build_dir}/unbound/unbound" "${artifacts_dir}/pia-unbound"
cp "${build_dir}/hnsd/hnsd" "${artifacts_dir}/pia-hnsd"

case $PLATFORM in
    linux)
        # Set rpaths in shipped executables
        patchelf --force-rpath --set-rpath '$ORIGIN/../lib' "${artifacts_dir}/pia-unbound"
        patchelf --force-rpath --set-rpath '$ORIGIN/../lib' "${artifacts_dir}/pia-hnsd"
        ;;
esac


split_exe_symbols "${artifacts_dir}/pia-unbound"
split_exe_symbols "${artifacts_dir}/pia-hnsd"

popd
