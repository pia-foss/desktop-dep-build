#! /usr/bin/env bash

# The libxcb-* libraries all reference a common M4 macros library from
# anongit.freedesktop.org.
#
# However, anongit.freedesktop.org goes down from time to time.  The repo
# is also available from gitlab.freedesktop.org (which is the remote we
# use for libxcb-* anyway).
#
# This script changes all the locally configured remotes for this library
# to gitlab.freedesktop.org.  (This is nontrivial since they are nested
# submodules.)

set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

# libxcb itself doesn't reference the m4 utils.  All of the libxcb-* libs do.
for config in .git/modules/components/xcb/libxcb-*/config; do
    echo "editing $config"
    git config --file="$config" submodule.m4.url "https://gitlab.freedesktop.org/xorg/util/xcb-util-m4.git"
done

echo "Edited all util-common-m4 remotes.  Try to pull again:"
echo "  git submodule update --init --recursive"
echo "To revert, run:"
echo "  git submodule sync --recursive"
