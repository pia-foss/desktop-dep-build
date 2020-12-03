#! /usr/bin/env bash

# Copyright (c) 2020 Private Internet Access, Inc.
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

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename "${__file}" .sh)"

die() { echo "${__base}:" "$*" 1>&2 ; exit 1; }

cd "$__dir"
source ../../util/submodule.sh

# Set platform based on the host platform
case "$(uname)" in
    Linux)
        case "$(uname -m)" in
            x86_64)
                platform=linux
                openssl_platform=linux-x86_64
                ;;
            aarch64)
                platform=linux
                openssl_platform=linux-aarch64
                ;;
            armv7l)
                platform=linux
                openssl_platform=linux-generic32
                ;;
            *) die "Unsupported Linux architecture" ;;
        esac
        ;;
    Darwin)
        platform=macos
        openssl_platform=darwin64-x86_64-cc
        ;;
    MINGW64_NT*)
        platform=mingw64
        openssl_platform=mingw64
        # unbound's configure.ac checks for uname=MINGW32, but not MINGW64.
        # Pass --host and --build so it still detects MinGW.
        unbound_platform_cfgargs="--host=${MINGW_CHOST} --build=${MINGW_CHOST}"
        ;;
    MINGW32_NT*)
        platform=mingw
        openssl_platform=mingw
        # In addition to the host/build tweak, MinGW32 is missing
        # lib/bfd-plugins/liblto_plugin-0.dll, use gcc-ar and gcc-ranlib instead
        # which know to load that plugin from the gcc lib directory
        unbound_platform_cfgargs="--host=${MINGW_CHOST} --build=${MINGW_CHOST} AR=gcc-ar RANLIB=gcc-ranlib"
        ;;
    *)
        die "Unsupported host platform"
        ;;
esac

output_dir="${__dir}/out/build/${platform}"
artifacts_dir="${__dir}/out/artifacts/${platform}"
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

check_submodule_clean openssl
check_submodule_clean unbound
check_submodule_clean hnsd

prep_submodule openssl "$build_dir"
prep_submodule unbound "$build_dir"
prep_submodule hnsd "$build_dir"

echo "Building OpenSSL..."
pushd "${build_dir}/openssl"
./Configure $openssl_platform --prefix="${output_dir}/openssl"
make -j2
# The install_sw target skips man pages
make install_sw
popd

echo "Building Unbound..."
pushd "${build_dir}/unbound"
# Rerun autoconf due to change to configure.ac
autoconf
# Configure options
# - Use OpenSSL built above
# - Just build libunbound, skip unbound, unbound-anchor, etc.
# - Don't build shared objects (just build static libraries)
# - Always install to /usr/local prefix (default is different on MinGW)
# shellcheck disable=SC2086
# ^ Intentional wordsplitting of ${unbound_platform_cfgargs}
./configure --with-ssl="${output_dir}/openssl" --disable-shared --enable-static ${unbound_platform_cfgargs} --prefix="${output_dir}/unbound" --disable-flto
make -j2
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

# Copy unbound to artifacts
cp "${build_dir}/unbound/unbound" "${artifacts_dir}/pia-unbound"
# Copy hnsd to artifacts
cp "${build_dir}/hnsd/hnsd" "${artifacts_dir}/pia-hnsd"

function strip_symbols() {
    local ARTIFACT=$1
    local EXT=$2

    # Strip debugging symbols from hnsd, but keep a full copy in case it's
    # needed for debugging
    cp "${artifacts_dir}/${ARTIFACT}${EXT}" "${artifacts_dir}/${ARTIFACT}.full${EXT}"
    strip --strip-debug "${artifacts_dir}/${ARTIFACT}${EXT}"
    objcopy --add-gnu-debuglink="${artifacts_dir}/${ARTIFACT}.full${EXT}" "${artifacts_dir}/${ARTIFACT}${EXT}"
}

function mac_set_loader_path() {
   local LIBNAME=$1
   local TARGET=$2

   local LIBPATH="$(otool -L "$TARGET" | sed -E $'s|^[ \t]*([^ \t].*/'"$LIBNAME"$').*$|\\1|' | grep "$LIBNAME")"
   install_name_tool -change "$LIBPATH" "@loader_path/$LIBNAME" "$TARGET"
}

case $platform in
    linux*)
        # OpenSSL is dynamically linked.  We ship the dynamic libraries built from the desktop-openvpn repo,
        # but the rpaths in these binaries need to be set.
        patchelf --force-rpath --set-rpath '$ORIGIN/../lib' "${artifacts_dir}/pia-unbound"
        patchelf --force-rpath --set-rpath '$ORIGIN/../lib' "${artifacts_dir}/pia-hnsd"

        strip_symbols pia-hnsd ""
        strip_symbols pia-unbound ""
        ;;
    mingw*)
        strip_symbols pia-hnsd .exe
        strip_symbols pia-unbound .exe
        ;;
    macos)
        # Like on Linux, OpenSSL is dynamically linked - we ship dylibs from desktop-openvpn, but set the
        # library paths.
        mac_set_loader_path libssl.1.1.dylib "${artifacts_dir}/pia-unbound"
        mac_set_loader_path libcrypto.1.1.dylib "${artifacts_dir}/pia-unbound"
        mac_set_loader_path libssl.1.1.dylib "${artifacts_dir}/pia-hnsd"
        mac_set_loader_path libcrypto.1.1.dylib "${artifacts_dir}/pia-hnsd"
        ;;
esac

popd
