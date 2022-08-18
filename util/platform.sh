#! /usr/bin/env bash

die() { echo "$(basename "${BASH_SOURCE[0]}" .sh):" "$*" 1>&2 ; exit 1; }

function show_exec() {
    echo "$@"
    "$@"
}

# Detect platform
case "$(uname)" in
    Linux)
        PLATFORM=linux
        case "$(uname -m)" in
            x86_64)
                ARCH=x86_64
                ;;
            aarch64)
                ARCH=arm64
                ;;
            arm*)
                # The only 32-bit ARM build we support is armhf
                ARCH=armhf
                ;;
            *)
                die "Unsupported Linux architecture: $(uname -m)"
                ;;
        esac
        ;;
    Darwin)
        PLATFORM=macos
        case "$(uname -m)" in
            x86_64)
                ARCH=x86_64
                ;;
            arm64)
                ARCH=arm64
                ;;
            *)
                die "Unsupported Linux architecture: $(uname -m)"
                ;;
        esac
        ;;
    MINGW64_NT*)
        PLATFORM=mingw64
        ARCH=x86_64
        ;;
    MINGW32_NT*)
        PLATFORM=mingw32
        ARCH=x86
        ;;
    *)
        die "Unsupported platform: $(uname)"
        ;;
esac

function select_platform() {
    case "$PLATFORM" in
        mingw*)
            echo "$1"
            ;;
        macos)
            echo "$2"
            ;;
        linux)
            echo "$3"
            ;;
    esac
}

# Get count of logical CPUs
function get_ncpus() {
    case "$PLATFORM" in
        mingw*)
            echo "$NUMBER_OF_PROCESSORS"
            ;;
        macos)
            sysctl -n hw.ncpu
            ;;
        linux)
            grep -Ec '^processor[[:space:]]+:' /proc/cpuinfo
            ;;
    esac
}

function get_memmb() {
    local MEMRAW MEMBYTES
    case "$PLATFORM" in
        mingw*)
            # Select the second line, WMIC produces output like this, including
            # the two trailing blank lines
            # <name>
            # <value>
            #
            # 
            MEMBYTES="$(wmic ComputerSystem get TotalPhysicalMemory | head -2 | tail -1)"
            ;;
        macos)
            # sysctl gives the count in bytes
            MEMBYTES="$(sysctl -n hw.memsize)"
            ;;
        linux)
            MEMRAW="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
            # It's in KB
            MEMBYTES="$((MEMRAW*1024))"
            ;;
    esac
    local MB="$((1024*1024))"
    echo "$(( ( MEMBYTES + MB/2 ) / MB ))" # Memory, in MB, rounded to nearest MB
}

# Calculate a number of jobs based on the host's CPU count and memory.
#
# This will try to create enough jobs to keep the CPUs busy, unless that would
# exceed the available memory (if a memory estimate is given)
#
# Provide a memory upper-bound (in MB per job) to limit the jobs based on
# memory.
#
# A diagnostic is printed to stderr indicating the number of jobs selected based
# on the observed CPU/memory limits; redirect 2>/dev/null if this is not
# desired.
function calc_jobs() {
    local JOBMEMMB CPUS EXTRACPUJOBS CPUJOBS DETAILS JOBS MEMMB MEMJOBS
    JOBMEMMB="$1"

    CPUS="$(get_ncpus)"
    EXTRACPUJOBS=$(( ( CPUS / 2 < 4 ) ? CPUS / 2 : 4 )) # Add up to 4 extra jobs (or cpus/2 if smaller) to keep CPU busy
    CPUJOBS=$(( CPUS + EXTRACPUJOBS )) # Number of jobs based on CPU cores

    DETAILS=""
    JOBS="$CPUJOBS"
    if [ -n "$JOBMEMMB" ]; then
        MEMMB="$(get_memmb)"
        MEMJOBS=$(( MEMMB / JOBMEMMB ))
        # Use smaller of CPU job limit or RAM job limit
        JOBS=$(( CPUJOBS < MEMJOBS ? CPUJOBS : MEMJOBS ))

        DETAILS=" (suggests $CPUJOBS jobs) and $MEMMB MB RAM (suggests $MEMJOBS jobs)"
    fi

    echo "Detected $CPUS CPUs$DETAILS - build with $JOBS jobs" >&2
    echo "$JOBS"
}

# Get the file name of an executable artifact (add .exe on Windows)
function exe_name() {
    select_platform "$1.exe" "$1" "$1"
}

# Get the file name of a shared library artifact, optionally including a
# version.  (name.dll, name.version.dylib, or name.so.version)
#
# The version can be empty for an artifact not including a version in the file
# name.
#
# The version is ignored on Windows, most libraries do not use versioned names
# on Windows.
function shared_name() {
    local NAME VERSION
    NAME="$1"
    VERSION="$2"
    select_platform "$NAME.dll" "$NAME${VERSION:+.}$VERSION.dylib" "$NAME.so${VERSION:+.}$VERSION"
}

# Split debugging symbols from a built image (executable or shared library).
# Use exe_name() or shared_name() to get the exact platform-dependent file name.
#
# On MinGW (Windows) and Linux, the symbols are preserved in an un-stripped
# copy of the binary placed in a debug/ subdirectory.
#
# On macOS, a .dSYM bundle is generated containing the symbols.
function split_symbols() {
    local FILE DEBUGFILE
    FILE="$1"
    case "$PLATFORM" in
        mingw*|linux)
            DEBUGFILE="$(dirname "$FILE")/debug/$(basename "$FILE")"
            mkdir -p "$(dirname "$FILE")/debug"
            cp "$FILE" "$DEBUGFILE"
            strip --strip-debug "$FILE"
            objcopy --add-gnu-debuglink="$DEBUGFILE" "$FILE"
            ;;
        macos)
            DEBUGFILE="$FILE.dSYM"
            dsymutil -o "$DEBUGFILE" "$FILE"
            strip -S "$FILE"
            ;;
    esac
}

# Split an executable or shared library; combines the platform specific name
# with split_symbols
function split_exe_symbols() {
    split_symbols "$(exe_name "$1")"
}
function split_shared_symbols() {
    split_symbols "$(shared_name "$1" "$2")"
}
