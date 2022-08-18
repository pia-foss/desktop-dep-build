#! /usr/bin/env bash

set -e

COMPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$COMPDIR"

source ../../util/platform.sh
source ../../util/submodule.sh

BUILDDIR="$COMPDIR/out/build/$PLATFORM"
INSTALLDIR="$COMPDIR/out/install/$PLATFORM"
ARTIFACTSDIR="$COMPDIR/out/artifacts/$PLATFORM"
JOBS="$(calc_jobs "")"

rm -rf "$BUILDDIR" "$ARTIFACTSDIR"
mkdir -p "$BUILDDIR"
mkdir -p "$INSTALLDIR"
mkdir -p "$ARTIFACTSDIR"

CONFIGURE_ARGS=()
# We have to set a platform-specific "prefix" (details below), but tell
# Make not to actually install there, install to our work directory instead.
# THis will get a subdirectory that depends on the prefix; we can't avoid
# that but we can work around it.
MAKE_ARGS=("DESTDIR=$INSTALLDIR/openssl")
INSTALL_SUBDIR=""

# Determine OpenSSL target name based on host platform.
#
# We have to specify some directory prefixes for OpenSSL based on platform.
#
# Unfortunately OpenSSL requires hard-coded absolute paths at configuration
# time where it will try to load configuration files at runtime, so this build
# cannot be completely brand- or product-neutral.  We don't use a configuration
# file, so the exact path isn't critical, but it _must_ be a location that is
# not user- or world-writable since it can cause OpenSSL to load shared libraries.
#
# (It's possible for the application to avoid asking OpenSSL to load a config
# file at all, but Qt always asks it to load one, so this isn't a solution for us,
# and would be fragile anyway.)
#
# IMPORTANT: You MUST verify that the directories in the OpenSSL build are
# restricted to root/Administrators.  Incorrect values can lead to escalation of
# privilege vulnerabilities:
#     strings <libcrypto> | grep 'DIR'
case "$PLATFORM" in
    linux)
        # Set --prefix and --openssldir to the real install location.  This is 
        # safe even if this artifact is picked up by another brand, because
        # /opt should be owned and writable by root.
        CONFIGURE_ARGS+=(
            "--prefix=/opt/piavpn/"
            "--openssldir=/opt/piavpn/etc/ssl/"
        )
        INSTALL_SUBDIR="opt/piavpn"
        case "$ARCH" in
            x86_64)
                openssl_platform=linux-x86_64
                ;;
            arm64)
                openssl_platform=linux-aarch64
                ;;
            armhf)
                openssl_platform=linux-generic32
                ;;
            *) die "Unsupported Linux architecture" ;;
        esac
        ;;
    macos)
        # On macOS, although PIA installs to /Applications, that's a safe place to
        # hard-code in OpenSSL, as members of 'admin' can write to /Applications,
        # and default users are members of admin.  It might barely be safe in PIA
        # as the daemon only runs once the installer has set it up, and the installer
        # also restricts our app directory to root, but this is too close for comfort
        # and leaves a vulnerability open if other brands pick up this artifact.
        #
        # Instead use / and /etc/ssl, which were the defaults we picked up when we
        # allowed OpenVPN to build OpenSSL for us.
        CONFIGURE_ARGS+=(
            "--prefix=/"
            "--openssldir=/etc/ssl/"
        )
        INSTALL_SUBDIR=""
        case "$ARCH" in
            x86_64)
                openssl_platform=darwin64-x86_64-cc
                ;;
            arm64)
                openssl_platform=darwin64-arm64-cc
                ;;
            *) die "Unsupported macOS architecture" ;;
        esac
        ;;
    mingw*)
        # IMPORTANT: It is very easy to create an escalation of privilege vulnerability
        # on Windows with these settings.  Read the details and verify the build result!
        #
        # On Windows, C:\ is _not_ restricted to Administrators - regular users can create
        # directories in the root.  The MinGW build defaults to C:\etc\ssl\ for the
        # config directory, which permits an EOP when our service loads OpenSSL.
        #
        # Point this to the PIA installation directory, which is safe even in another
        # brand because Program Files is writable only by Administrators.
        #
        # Unfortunately, we can't be 100% sure that this is actually the correct path on
        # any machine, as it's not guaranteed that Windows is installed to C:\, but this has
        # to be a hard-coded absolute path, so this is the best we can do.
        CONFIGURE_ARGS+=(
            "--prefix=C:\\Program Files\\Private Internet Access\\"
            "--openssldir=C:\\Program Files\\Private Internet Access\\"
        )
        # The install subdirectory omits the drive specification from the prefix.
        INSTALL_SUBDIR="Program Files/Private Internet Access"
        if [ "$PLATFORM" = "mingw32" ]; then
            openssl_platform=mingw
        else
            openssl_platform="$PLATFORM"
        fi
        ;;
    *)
        die "Unsupported host platform"
        ;;
esac

check_submodule_clean openssl
prep_submodule openssl "$BUILDDIR"

pushd "$BUILDDIR/openssl"
show_exec ./Configure $openssl_platform \
    shared \
    no-dso \
    no-capieng \
    no-autoload-config \
    "${CONFIGURE_ARGS[@]}"
show_exec make -j"$JOBS" "${MAKE_ARGS[@]}"
# The install_sw target skips man pages
show_exec make install_sw "${MAKE_ARGS[@]}"
popd

cp "$(select_platform -rd -R -rd)" "$INSTALLDIR/openssl/$INSTALL_SUBDIR"/* "$ARTIFACTSDIR/"

# Configure dynamic linking; have the linker look for the libs relative to the
# executable
function mac_set_install_name() {
    local TARGET="$1"
    install_name_tool -id "@executable_path/../Frameworks/$(basename "$TARGET")" "$TARGET"
}

function mac_set_loader_path() {
    local LIBNAME="$1"
    local TARGET="$2"

    # Find the dynamic lib entry for the specified module, then tell
    # install_name_tool to change it to look in '@loader_path' instead.
    local LIBPATH
    LIBPATH="$(otool -L "$TARGET" | sed -E $'s|^[ \t]*([^ \t].*/'"$LIBNAME"$').*$|\\1|' | grep "$LIBNAME")"
    install_name_tool -change "$LIBPATH" "@loader_path/$LIBNAME" "$TARGET"
}

case "$PLATFORM" in
    macos)
        mac_set_install_name "$ARTIFACTSDIR/lib/libcrypto.1.1.dylib"
        mac_set_install_name "$ARTIFACTSDIR/lib/libssl.1.1.dylib"
        mac_set_loader_path "libcrypto.1.1.dylib" "$ARTIFACTSDIR/lib/libssl.1.1.dylib"
        ;;
    linux)
        # Intentional single-quoted '$ORIGIN' below
        # shellcheck disable=SC2016
        {
            patchelf --force-rpath --set-rpath '$ORIGIN/' "$ARTIFACTSDIR/lib/libssl.so.1.1"
            patchelf --force-rpath --set-rpath '$ORIGIN/' "$ARTIFACTSDIR/lib/libcrypto.so.1.1"
        }
        ;;
esac
