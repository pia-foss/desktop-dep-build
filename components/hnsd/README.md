# hnsd-build

This repository builds hnsd, Unbound and their dependencies for use in desktop.

Since this repository uses submodules, make sure to include `--recursive` when cloning it.  If you forgot, `git submodule update --init` will initialize the submodules.

>>>
:point_right: **Note:** hnsd is no longer shipped with PIA Desktop, but this still builds Unbound, which is used for the built-in resolver.
>>>

## Build environment

This project builds on Linux, Mac OS, and Windows; artifacts are statically linked.  OpenSSL and libunbound are built from source.  Linux builds have been tested on Ubuntu 18.04 and 19.04.

### Ubuntu

You will need the following dependencies:
* build-essential
* bison (needed by OpenSSL build)
* git

### Mac

Just install the Xcode command-line tools.

### Windows

1. Install MSYS2 from https://www.msys2.org - follow the instructions on that page
2. Install dependencies
   - These are also listed on the hnsd README, but note that you do _not_ need to install libunbound since it is built from source.
   - You _do_ need to install git in MSYS2, even if you have Git for Windows; it is needed for the submodules.
   - x86_64: `pacman -S base-devel mingw-w64-x86_64-toolchain git mingw-w64-x86_64-crt-git`
   - x86: `pacman -S base-devel mingw-w64-i686-toolchain git mingw-w64-i686-crt-git`
3. Clone hnsd-build recursively _from the MSYS2 shell_.  Don't use Git for Windows, it handles line endings differently and will cause issues.
   - `git clone --recursive https://gitub.com/pia-foss/desktop-hnsd.git`

On Windows, building in the MSYS2 MinGW 64-bit shell produces a 64-bit build; building in the MSYS2 MinGW 32-bit shell produces a 32-bit build.

## Build

To build, just run: `./build-posix.sh` (even on Windows).  `pia-hnsd` is generated in `./out/artifacts/<platform>/`.

## Submodules, patches, updating dependencies

This project includes dependencies as submodules; patches are applied at build time.

The preferred way to work on the submodule patches is to apply them to the submodule, work in the submodule and commit to Git (locally), then regenerate patches.  See https://github.com/pia-foss/desktop-dep-build#working-on-module-patches.
