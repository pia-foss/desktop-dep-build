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

# This script is called by install.sh, either as the regular user if the
# directory is writable, or with 'sudo' to become root otherwise

set -e

INSTALL_DIR="$1"

mkdir -p "$INSTALL_DIR"
touch "$INSTALL_DIR/install-write-test"
rm -rf "${INSTALL_DIR:?}"/*

tar -xf "{{QT_ARCHIVE}}" --xz -C "$INSTALL_DIR"
