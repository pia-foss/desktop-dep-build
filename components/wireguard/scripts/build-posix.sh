#!/bin/bash

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

ROOT=${ROOT:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}
OUT="$ROOT/out/artifacts"
BUILD="$ROOT/build-wireguard-go"
DEPS="$BUILD/.deps"

die() { echo "${__base}:" "$*" 1>&2; exit 1; }

cd "$ROOT"

# The shellcheck source is relative to the scripts/ directory since
# that's where this file is; $ROOT is actually the parent wireguard-build
# directory so there is one fewer '../'.
# shellcheck source=../../../util/platform.sh
source "../../util/platform.sh"
# shellcheck source=../../../util/submodule.sh
source "../../util/submodule.sh"

function strip_symbols() {
    local binaryPath="$1"

    # Strip debugging symbols, but keep a full copy in case it's
    # needed for debugging
    cp "$binaryPath" "$binaryPath.full"
    strip --strip-debug "$binaryPath"
    objcopy --add-gnu-debuglink="$binaryPath.full" "$binaryPath"
}

check_submodule_clean "wireguard-go"

rm -rf "$OUT"
rm -rf "$BUILD"
mkdir -p "$OUT"
mkdir -p "$BUILD"

prep_submodule "wireguard-go" "$BUILD"

echo "Extracting go..."
mkdir -p "$DEPS/"
tar -xf "$ROOT/deps/$PLATFORM/$ARCH"/go*.tar.gz -C "$DEPS/"

export PATH="$DEPS/go/bin":$PATH

cd "$BUILD/wireguard-go/"

# The go module dependencies have been vendored to ensure that we can still
# rebuild this version of pia-wireguard-go even if the dependencies are taken
# down (which has happened in the past).
#
# The vendor directory in the archive was created with "go mod vendor -v" from
# the wireguard-go submodule.  (Note that unlike wireguard-windows, it doesn't
# matter if this is patched; the only patch we carry for wireguard-go only
# applies on Windows.)
tar -xzf "$ROOT/vendor-posix.tar.gz"

make
cp "$BUILD/wireguard-go/wireguard-go" "$OUT/pia-wireguard-go"

if [ "$PLATFORM" = "linux" ]; then
    strip_symbols "$OUT/pia-wireguard-go"
fi
