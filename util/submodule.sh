#! /usr/bin/env bash

# Local changes would be ignored due to clones below; make sure submodules are clean
check_submodule_clean() {
    if ! git -C "$1" diff-index --quiet HEAD --; then
        echo "$1 submodule is not clean, commit or revert changes before building" >&2
        exit 1
    fi
}

# Create a build directory for a submodule by cloning it, and apply patches if
# present
prep_submodule() {
    # Submodule is a directory name in the current directory (should not be a path,
    # used to determine build directory names and look for patches
    local SUBMODULE="$1"
    local BUILD_DIR="$2"

    local MODULE_BUILD_DIR="$BUILD_DIR/$SUBMODULE"

    # For normal full builds, always do the clone.  For rebuilds, do the clone
    # only if this build dir doesn't exist yet.
    if [ -z "${REBUILD}" ] || [ ! -d "$MODULE_BUILD_DIR" ]; then
        rm -rf "$MODULE_BUILD_DIR"
        cp -r "$SUBMODULE" "$MODULE_BUILD_DIR"

        for p in "patch-$SUBMODULE"/*.patch; do
            [ -f "$p" ] || continue # empty patch dir
            echo "Applying $p"
            patch -p1 -d "$MODULE_BUILD_DIR" < "$p"
        done
    fi
}
