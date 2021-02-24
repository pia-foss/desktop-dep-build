#! /usr/bin/env bash

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

SCRIPT="$(basename "${BASH_SOURCE[0]}")"
die() { echo "$SCRIPT:" "$*" 1>&2; exit 1; }

source util/platform.sh

OUT="$ROOT/out/$PLATFORM_$ARCH"
ARTIFACTS="$OUT/artifacts"

rm -rf "$OUT"
mkdir -p "$ARTIFACTS"

echo "Building for $PLATFORM $ARCH"

echo "===Build Unbound and hnsd==="
pushd components/hnsd
./build-posix.sh
popd

echo "===Build Shadowsocks==="
pushd components/shadowsocks
./build-posix.sh
popd

# Collect artifacts
cp \
    "components/hnsd/out/artifacts/$PLATFORM"/* \
    "components/shadowsocks/out/artifacts/$PLATFORM"/* \
    "$ARTIFACTS"

# Separate unstripped binaries
mkdir -p "$OUT/debug"
mv "$ARTIFACTS"/*.full.exe "$OUT/debug"
