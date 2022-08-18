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

DEFAULT_INSTALL_DIR="$HOME/Qt{{QT_VERSION}}-pia"

echo "Private Internet Access - Qt {{QT_VERSION}}"
read -rp "Installation directory: [$DEFAULT_INSTALL_DIR]: " INSTALL_DIR
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

# Extract to the specific version/build directory, so cross builds can also be
# installed at the same time.  For example, /home/user/Qt5.15.0/5.15.0/gcc_64
QT_BUILD_DIR="$INSTALL_DIR/{{QT_VERSION}}/{{QT_BUILD_NAME}}"

if [ -d "$QT_BUILD_DIR" ]; then
    echo "WARNING: Directory $QT_BUILD_DIR exists, existing contents will be deleted."
    read -rp "Continue? [y/N]: " DELETE_EXISTING
    if ! [[ $DELETE_EXISTING =~ ^[yY]$ ]]; then
        echo "Canceled."
        exit 0
    fi
fi

if ! { mkdir -p "$QT_BUILD_DIR" || touch "$QT_BUILD_DIR/install-write-test"; }; then
    echo "Using sudo to install to $QT_BUILD_DIR"
    sudo ./extract.sh "$QT_BUILD_DIR"
else
    ./extract.sh "$QT_BUILD_DIR"
fi

echo "Installed to $QT_BUILD_DIR"
