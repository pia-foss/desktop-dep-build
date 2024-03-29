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

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__base="$(basename "${BASH_SOURCE[0]}")"

die() { echo "${__base}:" "$*" 1>&2; exit 1; }

cd "${__dir}"

source ../../util/platform.sh
source ../../util/submodule.sh

JOBS="$(calc_jobs "")"

# Platform-specific arguments to configure or make
LIBPCRE_CONF_ARGS=()
LIBSODIUM_CONF_ARGS=()
MBEDTLS_MAKE_ARGS=()
LIBEV_CONF_ARGS=()
SHADOWSOCKS_CONF_ARGS=()

# Arguments to all 'make' commands
ALL_MAKE_ARGS=("-j$JOBS")
# CPPFLAGS args (for preprocessor), combined into FLAGS_ARGS after
# platform-specific values are added.
# * -DCARES_STATICLIB is needed by c-ares for static libraries, otherwise it
#   will try to link to dynamic symbols when included in shadowsocks-libev.
CPPFLAGS_ARGS="-DCARES_STATICLIB"
# LDFLAGS args (for linker), combined into FLAGS_ARGS after
# platform-specific values are added.
LDFLAGS_ARGS=""

# The shadowsocks project forked libev.  However, they have different branches
# for different platforms that have diverged, there are two copies of the libev
# submodule in this repo pointing to these branches
LIBEV_PLATFORM=""

# Common flags for MinGW 32/64
function apply_mingw_flags() {
    # Stack smash protection (-lssp and _FORTIFY_SOURCE) has problems on
    # MinGW
    LIBSODIUM_CONF_ARGS+=(--disable-ssp)
    SHADOWSOCKS_CONF_ARGS+=(--disable-ssp)
    CPPFLAGS_ARGS="${CPPFLAGS_ARGS} -D_FORTIFY_SOURCE=0"
    # Required by mbedtls for Windows targets
    MBEDTLS_MAKE_ARGS+=(WINDOWS_BUILD=1)
    # Enable "--static" on Windows to statically link libwinpthreads.
    # Don't use it on other platforms though - statically linking glibc on
    # Linux is fraught with problems (getaddrinfo) and we already depend on
    # basic libs from the host (libc, libm, libpthreads, libdl, etc.).
    LDFLAGS_ARGS="${LDFLAGS_ARGS} --static"
}

# Set platform and platform-specific arguments based on the host platform
case "$PLATFORM" in
    linux)
        LIBEV_PLATFORM=posix
        # libev requires libm for 'floor'.  We can turn off floor in
        # libev, but we end up linking to libm anyway from another
        # dependency.
        SHADOWSOCKS_CONF_ARGS+=("LIBS=-lm")
        ;;
    macos)
        LIBEV_PLATFORM=posix
        ;;
    mingw64)
        LIBEV_PLATFORM=windows
        apply_mingw_flags
        ;;
    mingw32)
        LIBEV_PLATFORM=windows
        apply_mingw_flags
        ;;
    *)
        die "Unsupported host platform"
        ;;
esac

# *FLAGS definitions if needed, passed to configure for all packages except
# mbedtls.  mbedtls does not use autoconf, this is passed to make instead.
FLAGS_ARGS=()
FLAGS_ARGS+=("CPPFLAGS=${CPPFLAGS_ARGS}")
FLAGS_ARGS+=("LDFLAGS=${LDFLAGS_ARGS}")

output_dir="${__dir}/out/build/${PLATFORM}"
artifacts_dir="${__dir}/out/artifacts/${PLATFORM}"
build_dir="${__dir}/build.tmp/${PLATFORM}"

# For quick iterations on the build script itself, setting REBUILD skips the
# clean and clone steps for build dirs that already exist.  It does _not_ make
# sure existing build directories are up to date with the submodules, though.
if [ -z "${REBUILD}" ]; then
    rm -rf "${artifacts_dir}" "${build_dir}"
fi

rm -rf "${output_dir}"

mkdir -p "${output_dir}"
mkdir -p "${artifacts_dir}"
mkdir -p "${build_dir}"

check_submodule_clean libsodium
check_submodule_clean mbedtls
check_submodule_clean c-ares
check_submodule_clean "libev-${LIBEV_PLATFORM}/libev"
check_submodule_clean shadowsocks-libev

prep_submodule libsodium "${build_dir}"
prep_submodule mbedtls "${build_dir}"
prep_submodule c-ares "${build_dir}"
prep_submodule "libev-${LIBEV_PLATFORM}/libev" "${build_dir}"
prep_submodule shadowsocks-libev "${build_dir}"

# Configure args for shadowsocks-libev specifying all the libraries we build
SHADOWSOCKS_WITH_ARGS=()

echo "Building libpcre..."
mkdir -p "${build_dir}/libpcre"
pushd "${build_dir}/libpcre"
if [ -z "${REBUILD}" ] || [ ! -d "./pcre-8.44" ]; then
    tar xvzf "${__dir}/deps/pcre-8.44.tar.gz"
fi
cd ./pcre-8.44
./configure --prefix="${output_dir}/libpcre" --disable-shared "${FLAGS_ARGS[@]}" "${LIBPCRE_CONF_ARGS[@]}"
make "${ALL_MAKE_ARGS[@]}"
make install
SHADOWSOCKS_WITH_ARGS+=(--with-pcre="${output_dir}/libpcre")
popd

echo "Building libsodium..."
pushd "${build_dir}/libsodium"
./configure --prefix="${output_dir}/libsodium" --disable-shared "${FLAGS_ARGS[@]}" "${LIBSODIUM_CONF_ARGS[@]}"
make "${ALL_MAKE_ARGS[@]}"
make install
SHADOWSOCKS_WITH_ARGS+=(--with-sodium="${output_dir}/libsodium")
popd

echo "Building mbedtls..."
pushd "${build_dir}/mbedtls"
##win64
make "${ALL_MAKE_ARGS[@]}" "${FLAGS_ARGS[@]}" "${MBEDTLS_MAKE_ARGS[@]}"
make DESTDIR="${output_dir}/mbedtls" install
SHADOWSOCKS_WITH_ARGS+=(--with-mbedtls="${output_dir}/mbedtls")
popd

echo "Building c-ares..."
pushd "${build_dir}/c-ares"
autoreconf --install --force
./configure --prefix="${output_dir}/c-ares" --disable-shared "${FLAGS_ARGS[@]}" "${LIBCARES_CONF_ARGS[@]}"
make "${ALL_MAKE_ARGS[@]}"
make install
SHADOWSOCKS_WITH_ARGS+=(--with-cares="${output_dir}/c-ares")
popd

echo "Building libev..."
pushd "${build_dir}/libev"
chmod a+x autogen.sh # Missing in repo
./autogen.sh
./configure --prefix="${output_dir}/libev" --disable-shared --enable-static "${FLAGS_ARGS[@]}" "${LIBEV_CONF_ARGS[@]}"
make "${ALL_MAKE_ARGS[@]}"
make install
SHADOWSOCKS_WITH_ARGS+=(--with-ev="${output_dir}/libev")
popd

echo "Building shadowsocks-libev..."
pushd "${build_dir}/shadowsocks-libev"
./autogen.sh
./configure "${SHADOWSOCKS_WITH_ARGS[@]}" --disable-documentation --prefix="${output_dir}/shadowsocks-libev" "${FLAGS_ARGS[@]}" "${SHADOWSOCKS_CONF_ARGS[@]}"
make "${ALL_MAKE_ARGS[@]}"
make install
popd

# Copy ss-local to artifacts
cp "${output_dir}/shadowsocks-libev/bin/ss-local" "${artifacts_dir}/pia-ss-local"

split_exe_symbols "${artifacts_dir}/pia-ss-local"

echo "Artifacts produced:"
ls -alh "${artifacts_dir}"
