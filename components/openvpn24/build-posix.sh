#!/usr/bin/env bash

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

set -o errexit
set -o pipefail
# set -o nounset
# set -o xtrace

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file} .sh)"
# __root="$(cd "$(dirname "${__dir}")" && pwd)" # <-- change this as it depends on your app

die() { echo "${__base}:" "$*" 1>&2 ; exit 1; }

cd "${__dir}"

case "$(uname)" in
    Linux)
        host_platform=linux
        # Always use /sbin/ip, don't detect from the host - the host may have
        # ifconfig but some of our supported distributions do not.
        # (openvpn-build does an unquoted expansion of this variable, so it will
        # be arg-split)
        export EXTRA_OPENVPN_CONFIG='IPROUTE=/sbin/ip --enable-iproute2'
        ;;
    Darwin)
        [ "$(uname -m)" = "x86_64" ] || die "Unsupported host platform"
        host_platform=macos
        libtoolize="glibtoolize"
        ;;
    *)
        die "Unsupported host platform"
        ;;
esac

platform="$host_platform"
actual_platform="$host_platform"

openvpn_version="pia"
openvpn_directory="${__dir}/build.tmp/openvpn-${openvpn_version}"
openvpn_build_directory="${__dir}/build.tmp/openvpn-build"

openssl_version="1.1.1g"

output_directory="${__dir}/out/build/${platform}"
artifacts_dir="${__dir}/out/artifacts/${platform}"

rm -rf "${output_directory}" "${artifacts_dir}"
mkdir -p "${output_directory}"
mkdir -p "${artifacts_dir}"

case "${actual_platform}" in
    linux)
        export DO_REALLY_STATIC=1
        ;;
    macos)
        export DO_REALLY_STATIC=1
                ;;
    *)
        die "Unknown platform"
        ;;
esac

# Local changes would be ignored by the build due to the clones below
git -C ./openvpn diff-index --quiet HEAD -- || die "openvpn submodule is not clean, commit or revert changes before building"
git -C ./openvpn-build diff-index --quiet HEAD -- || die "openvpn-build submodule is not clean, commit or revert changes before building"

# Initialize clean OpenVPN sources for patching
rm -rf ./build.tmp
mkdir -p ./build.tmp
git clone ./openvpn-build ${openvpn_build_directory}
git clone ./openvpn ${openvpn_directory}

echo "Applying OpenVPN build patches..."
for p in ${__dir}/patch-openvpn-build-posix/*.patch; do
        [ -f "$p" ] || continue # handle empty patch dir
        echo "+ Applying $p..."
        git -C "${openvpn_build_directory}" am "$p"
done

# Apply local patches to OpenVPN
echo "Applying OpenVPN patches..."
for p in ${__dir}/patch-openvpn/*.patch; do
        [ -f "$p" ] || continue # handle empty patch dir
        echo "+ Applying $p..."
        git -C "${openvpn_directory}" am "$p"
done

# Keep openvpn-build from pulling any sources
export LZO_URL=' '
export OPENSSL_URL=' '
export PKCS11_HELPER_URL=' '
export TAP_WINDOWS_URL=' '
export OPENVPN_URL=' '
export OPENVPN_GUI_URL=' '

# Tell openvpn-build where the checkout is
export OPENVPN_VERSION="${openvpn_version}"
# Forward other parameters
export OPENSSL_VERSION="${openssl_version}"
# Extra openvpn-build options
export EXTRA_OPENVPN_CONFIG="$EXTRA_OPENVPN_CONFIG --enable-password-save --enable-management --disable-server --disable-debug --disable-silent-rules --disable-plugins --disable-plugin-auth-pam --disable-plugin-down-root"

# Configure openvpn-build
echo "Configuring OpenVPN build..."
rm -f "${openvpn_directory}/configure"
[ -f "${openvpn_directory}/configure" ] || ( cd "${openvpn_directory}" && "${libtoolize:-libtoolize}" --force && aclocal && autoconf && autoheader && automake --force-missing --add-missing && autoreconf -v -i -f )

# Package sources into tarball where openvpn-build expects it
echo "Packaging sources..."
mkdir "${openvpn_build_directory}/generic/sources"
( cd ./build.tmp && tar cf "${openvpn_build_directory}/generic/sources/openvpn-${OPENVPN_VERSION}.tar" "openvpn-pia" )

# Copy other source archives
cp ./source-archives/* "${openvpn_build_directory}/generic/sources"
# - There's a dummy OpenVPN GUI archive placeholder in source-archives-posix/
#   because the openvpn-build has a dumb check that it has exactly 6 archives,
#   even though we won't be building the GUI or TAP adapter for Mac/Linux.
# - The Mac/Linux build expects a built TAP adapter, not a source archive like
#   on Windows, and it actually uses headers from this package
cp ./source-archives-posix/* "${openvpn_build_directory}/generic/sources"

# Execute main openvpn-build script
echo "Building OpenVPN..."
rm -rf "${openvpn_build_directory}/generic/tmp"
( cd "${openvpn_build_directory}/generic" && IMAGEROOT="${output_directory}" PIA_PLATFORM="${actual_platform}" ./build )

case "$platform" in
    linux)
        mkdir -p "$artifacts_dir/bin"
        mkdir -p "$artifacts_dir/lib"
        cp "${output_directory}/openvpn/sbin/openvpn" "${artifacts_dir}/bin/pia-openvpn"
        cp "${output_directory}/openvpn/lib"/*.so.1.1 "${artifacts_dir}/lib/"
        pushd "${artifacts_dir}/lib"
        ln -s libssl.so.1.1 libssl.so
        ln -s libcrypto.so.1.1 libcrypto.so
        popd

        # Patch rpaths - there's no point trying to set these in the proper build,
        # the build scripts can't handle the dollar sign
        chmod u+w "${artifacts_dir}/lib"/*.so.1.1
        patchelf --force-rpath --set-rpath '$ORIGIN/../lib/' "${artifacts_dir}/bin/pia-openvpn"
        patchelf --force-rpath --set-rpath '$ORIGIN/' "${artifacts_dir}/lib/libssl.so.1.1"
        patchelf --force-rpath --set-rpath '$ORIGIN/' "${artifacts_dir}/lib/libcrypto.so.1.1"
        ;;
    macos)
        cp "${output_directory}/openvpn/sbin/openvpn" "${artifacts_dir}/pia-openvpn"
        cp "${output_directory}/openvpn/lib/"*.1.1.dylib "${artifacts_dir}/"
        chmod u+w "${artifacts_dir}/"*.dylib
        install_name_tool -change "////libssl.1.1.dylib" "@loader_path/libssl.1.1.dylib" "${artifacts_dir}/pia-openvpn"
        install_name_tool -change "////libcrypto.1.1.dylib" "@loader_path/libcrypto.1.1.dylib" "${artifacts_dir}/pia-openvpn"
        install_name_tool -change "////libssl.1.1.dylib" "@loader_path/libssl.1.1.dylib" "${artifacts_dir}/libcrypto.1.1.dylib"
        install_name_tool -change "////libcrypto.1.1.dylib" "@loader_path/libcrypto.1.1.dylib" "${artifacts_dir}/libcrypto.1.1.dylib"
        install_name_tool -change "////libssl.1.1.dylib" "@loader_path/libssl.1.1.dylib" "${artifacts_dir}/libssl.1.1.dylib"
        install_name_tool -change "////libcrypto.1.1.dylib" "@loader_path/libcrypto.1.1.dylib" "${artifacts_dir}/libssl.1.1.dylib"
        ;;
esac

# Done!
echo "Build completed:"
ls -l "${artifacts_dir}"
for dir in "${artifacts_dir}"/*/; do
  [ -d "$dir" ] && ls -l "$dir"
done

exit 0
