#! /usr/bin/env bash

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

SCRIPT="$(basename "${BASH_SOURCE[0]}")"
die() { echo "$SCRIPT:" "$*" 1>&2; exit 1; }

source util/platform.sh

OUT="$ROOT/out/${PLATFORM}_$ARCH"
ARTIFACTS="$OUT/artifacts"

# Each "build component" specifies:
# - 'build' - Whether it is currently being built ('y' or 'n')
# - 'defbuild' - Whether it is built by default when unspecified
# - 'deps' - The other components it depends on
# - 'note' - An extra note for the help text
#
# Bash 3 on macOS lacks associative arrays, so each of these maps are
# emulated with discrete variables of the form "COMP_<property>_<compname>"

function set_propmap() {
    local MAP="$1" # Map name ("COMP")
    local PROP="$2" # Property name ("build", "note", etc.)
    local KEY="$3" # Key name (a component name)
    local VALUE="$4"

    printf -v "${MAP}_${PROP}_${KEY}" "%s" "$VALUE"
}
function get_propmap() {
    local MAP="$1" # Map name ("COMP")
    local PROP="$2" # Property name ("build", "note", etc.)
    local KEY="$3" # Key name (a component name)
    local VAR="${MAP}_${PROP}_${KEY}"
    echo "${!VAR}"
}

# Define a component.  Initially all components are set not to build, defaults
# are applied by set_default_build
COMPONENTS=()
function define_component() {
    local NAME="$1"
    local DEFBUILD="$2"
    local DEPS="$3" # Space-delimited
    local NOTE="$4"

    set_propmap COMP build "$NAME" n
    set_propmap COMP defbuild "$NAME" "$DEFBUILD"
    set_propmap COMP deps "$NAME" "$DEPS"
    set_propmap COMP note "$NAME" "$NOTE"
    COMPONENTS+=("$NAME")
}

function should_build() {
    if [ "$(get_propmap COMP build "$1")" = 'y' ]; then
        return 0
    fi
    return 1
}

function is_component() {
    if [ -n "$(get_propmap COMP build "$1")" ]; then
        return 0
    fi
    return 1
}

function set_build() {
    set_propmap COMP build "$1" "$2"
}

function linux_only() {
    if [ "$PLATFORM" = "linux" ]; then
        echo "$@"
    fi
}

LINUX_DEFBUILD="$(select_platform n n y)"
LINUX_PATCHELF="$(select_platform '' '' patchelf)"
POSIX_DEFBUILD="$(select_platform n y y)"

#                Name           Default build       Dependencies                    Note for help text
define_component patchelf       "$LINUX_DEFBUILD"   ""                              "(Linux only)"
define_component openssl        "y"                 "$LINUX_PATCHELF"               ""
define_component openvpn        "y"                 "$LINUX_PATCHELF openssl"       ""
define_component unbound        "y"                 "$LINUX_PATCHELF openssl"       "(includes hnsd)"
define_component shadowsocks    "y"                 "$LINUX_PATCHELF"               ""
define_component wireguard      "$POSIX_DEFBUILD"   "$LINUX_PATCHELF"               "(macOS and Linux only)"
define_component xcb            "$LINUX_DEFBUILD"   "$LINUX_PATCHELF"               "(Linux only)"
define_component icu            "$LINUX_DEFBUILD"   "$LINUX_PATCHELF"               "(Linux only)"
define_component qt             "$POSIX_DEFBUILD"   "$LINUX_PATCHELF openssl $(linux_only xcb icu)"   "(macOS and Linux only)"

function set_default_build() {
    for comp in "${COMPONENTS[@]}"; do
        set_build "$comp" "$(get_propmap COMP defbuild "$comp")"
    done
}

function show_usage() {
cat << USAGE_END
usage:
  Build everything:
    $0
  Skip specific components ('--skip qt' skips Qt):
    $0 --skip <component> [<component>...]
  Build only specific components:
    $0 --build <component> [<component>...]
  Show help:
    $0 --help

Builds external dependencies for PIA Desktop.  Artifacts are placed in
out/artifacts.

Components:
USAGE_END

    for comp in "${COMPONENTS[@]}"; do
        echo "  $comp $(get_propmap COMP note "$comp")"
    done
    echo ""

cat << USAGE_END
Parameters:"
  --build <component> [<component>...]: Build only the specified
    components.  Note that patchelf is needed for most builds on
    Linux.  Qt depends on OpenSSL from the OpenVPN build and libxcb.
    If dependencies aren't specified, it's assumed that they were
    already built.
  --skip <component> [<component>...]: Build everything except the
    specified components.  Like with --build, dependencies that are
    excluded are assumed to have already been built.

---Binary artifacts---

  On all platforms, OpenVPN, OpenSSL, resolvers, Shadowsocks, and
  WireGuard are built to binary artifacts that can be shipped with
  PIA.  These artifacts go in pia_desktop/deps/built/$PLATFORM/$ARCH.

---Qt---

  On Linux and macOS, Qt is built to a self-extracting archive that can be
  installed to build PIA.  The resulting package is similar to the
  official Qt offline installers; it includes headers, libraries, and
  build tools.

  libicu is also built and included in the Qt installer.  Qt is
  configured for OpenSSL 1.1 (built by the OpenVPN build scripts).
  OpenSSL is located dynamically by Qt at runtime, so this is not
  included in the Qt installer.

  patchelf 0.11 is also built and included.  This is not directly
  related to Qt but is used by PIA for Qt deployment on Linux, and
  the version of patchelf included in Debian Stretch / Ubuntu 18.04
  causes problems with strip (https://github.com/NixOS/patchelf/issues/10)

USAGE_END
case "$PLATFORM" in
mingw*)
cat << USAGE_END
---Windows---

  Build once from the MinGW 64-bit shell for 64-bit artifacts, and once from the
  MinGW 32-bit shell for 32-bit artifacts.

  WireGuard components for Windows are not built by this script due to code
  signing requirements (EV CS signing and WHQL); see
  components/wireguard/README.md.

USAGE_END
;;
macos)
cat << USAGE_END
---macOS---

  To build universal artifacts, including universal Qt:
    1. Build once from an x86_64 host
    2. Build once from an arm64 host
    3. Copy out/macos_<arch> to the same machine (i.e. copy out/macos_x86_64 to
       the arm64 host or vice versa)
    4. Run ./merge-macos-universal.sh to merge the artifacts

  The combined artifacts are placed in out/macos_universal.  Cross builds are
  not supported, each build must be performed natively.

  Note that Qt is very sensitive to libraries present on the host, it is
  recommended not to install any other homebrew packages other than the ones
  specifically needed.  (Specifically, many homebrew packages indirectly install
  libxcb on macOS, which can cause some Qt modules to pick up a dependency on
  libxcb, even if -no-xcb is passed to Qt's configure script.)

USAGE_END
;;
linux)
cat << USAGE_END
---Linux---

  Build in a chroot with the correct dependencies to ensure that the build is
  compatible with older distributions, and to ensure Qt does not pick up any
  additional unintended library dependencies.  Setup scripts are in the desktop
  repo (https://github.com/pia-foss/desktop/tree/master/scripts/chroot).

  Cross builds are not supported, builds for x86_64, arm64, and armhf must each
  be performed on natively.

USAGE_END
esac
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
    # We can only clean the output directory if we are building everything,
    # otherwise we may be reusing prior build output for some components
    rm -rf "$OUT"
    set_default_build
fi
mkdir -p "$ARTIFACTS"

echo "Building for $PLATFORM $ARCH:"
for comp in "${COMPONENTS[@]}"; do
    if should_build "$comp"; then
        echo "  $comp"
    fi
done
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
for dep in "${COMPONENTS[@]}"; do
    if ! should_build "$dep"; then
        # Check if anything being built uses this component
        WARNED=
        for parent in "${COMPONENTS[@]}"; do
            if ! should_build "$parent"; then
                continue    # Not being built, don't care about deps
            fi
            # This parent is being built, see if it depends on this component
            # Intentional word-split of space-delimited dependencies
            for parent_dep in $(get_propmap COMP deps "$parent"); do
                if [ "$parent_dep" = "$dep" ]; then
                    echo "WARNING: using prior build output for $dep" >&2
                    WARNED=y
                    break # Skip rest of dependencies
                fi
            done
            # Skip checking other parents if we already found it in use
            if [ -n "$WARNED" ]; then
                break
            fi
        done
    fi
done


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

if should_build openssl; then
    echo "===Build OpenSSL==="
    pushd components/openssl
    ./build-posix.sh
    popd

    # Only the shared libraries are installed
    case "$PLATFORM" in
        linux)
            # Use cp -d to preserve versioned symlinks
            cp -d "components/openssl/out/artifacts/$PLATFORM/lib"/*.so* "$ARTIFACTS"
            ;;
        macos)
            # cp lacks -d on macOS, but we don't need the versioned symlinks anyway on macOS
            cp "components/openssl/out/artifacts/$PLATFORM/lib"/lib{crypto,ssl}.1.1.dylib "$ARTIFACTS"
            ;;
        mingw*)
            cp "components/openssl/out/artifacts/$PLATFORM/bin"/lib{crypto,ssl}-1_1*.dll "$ARTIFACTS"
            ;;
    esac
fi

if should_build openvpn; then
    echo "===Build OpenVPN and OpenSSL==="
    pushd components/openvpn24
    ./build-posix.sh "$ROOT/components/openssl/out/artifacts/$PLATFORM"
    popd

    cp "$(exe_name "components/openvpn24/out/artifacts/pia-openvpn")" "$ARTIFACTS/"
fi

if should_build unbound; then
    echo "===Build Unbound and hnsd==="
    pushd components/hnsd
    ./build-posix.sh "$ROOT/components/openssl/out/artifacts/$PLATFORM"
    popd
    # Collect artifacts
    cp "$(exe_name "components/hnsd/out/artifacts/$PLATFORM/pia-unbound")" "$ARTIFACTS/"
fi

if should_build shadowsocks; then
    echo "===Build Shadowsocks==="
    pushd components/shadowsocks
    ./build-posix.sh
    popd
    # Collect artifacts
    cp "$(exe_name "components/shadowsocks/out/artifacts/$PLATFORM/pia-ss-local")" "$ARTIFACTS/"
fi

if should_build wireguard; then
    echo "===Build WireGuard==="
    pushd components/wireguard
    ./scripts/build-posix.sh
    popd
    # Collect artifacts
    cp "components/wireguard/out/artifacts"/* "$ARTIFACTS/"
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

if should_build icu; then
    echo "===Build ICU==="
    pushd components/icu
    ./build-linux.sh
    popd
    # icu artifacts are bundled with Qt
fi

if should_build qt; then
    echo "===Build Qt==="
    pushd components/qt

    # Use OpenSSL and libxcb built above, and include patchelf in the Qt
    # bundle
    BUILD_ARGS=('--extra-prefix' "../../components/openssl/out/artifacts/$PLATFORM")
    if [ "$PLATFORM" = "linux" ]; then
        BUILD_ARGS+=('--extra-bin' "$PATCHELF_BIN/patchelf" \
            '--extra-prefix' "../../components/xcb/out/install" \
            '--extra-install' "../../components/icu/out/install")
    fi

    time ./build-linux.sh "${BUILD_ARGS[@]}"

    popd

    QT_PACKAGE="$(first "components/qt/out/artifacts"/qt-*.run)"
    mkdir -p "$OUT/installers"
    mv "$QT_PACKAGE" "$OUT/installers"
fi
