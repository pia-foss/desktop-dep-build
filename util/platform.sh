#! /usr/bin/env bash

# NOTE: Windows and macOS builds are not fully implemented yet
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
        ARCH=x86_64
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
        *)
            die "Unexpected platform: $PLATFORM"
            ;;
    esac
}

