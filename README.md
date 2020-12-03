# desktop-dep-build

This repository builds external dependencies for use in PIA Desktop.  The dependencies are then checked into the PIA Desktop repository, under deps/ (or brands/pia for the few dependencies that are brand-specific).

Since this repository uses submodules, make sure to include `--recursive` when cloning it.  If you forgot, `git submodule update --init --recursive` will initialize the submodules.

The component builds were recently moved from separate repositories, and are not fully integrated yet (in particular, OpenSSL is built twice - in the OpenVPN and unbound/hnsd component builds).

>>>
:point_right: **Note:** This repository is replacing the separate dependency build repositories listed below.  An overall build script has been written for Linux, but is still in progress for Windows and Mac.

This repository is used to build PIA Desktop 2.6.1-beta.1, and the separate repositories will be deprecated when this reaches a general release.

* Previous OpenVPN build: https://github.com/pia-foss/desktop-openvpn
* Previous hnsd/Unbound build: https://github.com/pia-foss/desktop-hnsd
* Previous Shadowsocks build: https://github.com/pia-foss/desktop-shadowsocks
* Previous WireGuard and WinTUN build: https://github.com/pia-foss/desktop-wireguard
>>>

# Linux

## Build environment

This build has been tested on:

* Debian Stretch / Buster
* Raspberry Pi OS
* Armbian Focal

Builds are done natively on x86_64, arm64, and armhf, cross builds are not implemented.

>>>
:point_right: **Note:** Building Qt may take a long time and is best done with at least ~4 CPU cores, ~8 GB RAM, and at least 40 GB free disk space.  Use `./build-linux.sh --no-qt` to skip Qt and only build the other dependencies.  When building Qt, read the notes below.  Make sure your machine has sufficient resources and can handle high CPU load for several hours, especially for embedded ARM devices (use a fan/heatsink).
>>>

## Chroot build

For best compatibility, build in a Debian Stretch chroot configured with the setup script in pia_desktop.  The script installs all dependencies needed for the dependency builds in the chroot.  Install `schroot` and `debootstrap` prior to running the script.

```
# set up native chroot using script from pia_desktop repo:
$ <path>/pia-foss/desktop/scripts/chroot/setup.sh  # use --help to see options, will prompt if additional bind mounts are required, etc.
# enter the chroot:
$ <path>/pia-foss/desktop/scripts/chroot/enter.sh
# navigate to desktop-dep-build inside the chroot, and build:
$ ./build-linux.sh
```

## Host build

You will need the following build dependencies (see individual component READMEs for details):

```
build-essential curl pv bison git automake libtool libmnl-dev python2 libclang-dev libssl-dev libxcb-xinerama0-dev libxcb-render0-dev libxcb-render-util0-dev libxcb-shape0-dev libxcb-randr0-dev libxcb-xfixes0-dev libxcb-sync-dev libxcb-shm0-dev libxcb-icccm4-dev libxcb-keysyms1-dev libxcb-image0-dev libxkbcommon-x11-dev libxi-dev libxrender-dev libxext-dev libx11-dev libx11-xcb-dev libxcb1-dev libfontconfig1-dev libfreetype6-dev libsm-dev libice-dev libglib2.0-dev libpq-dev libatspi2.0-dev libglvnd-dev
```

Notes:

* bison - needed by OpenSSL
* libmnl-dev - needed by WireGuard
* python2 - needed by mbedTLS for Shadowsocks, called `python` on Debian Stretch
* libglvnd-dev - called `libgl-dev` on Debian Stretch

Build with:

```
./build-linux.sh
```

Artifacts are produced in `out/artifacts`.

## Building Qt

Building Qt is resource intensive and can take a long time:

| Machine | Approximate build time |
|---------|------------------------|
| Intel Core i9 (8 core VM, 8 GB RAM + swap) | ~1-2 hours |
| Raspberry Pi 4 (4 cores, 8 GB RAM) | ~6-8 hours |
| RockPro64 (6 cores, 4 GB RAM + swap) | ~6-8 hours |

The Qt build will generate high CPU load for the duration of the build.  Be sure your system is properly cooled and can handle that (usually not a problem on desktops/laptops, but can be a problem on embedded ARM devices - make sure you have a fan/heatsink).

Be sure you have sufficient RAM; at least ~1 GB per CPU thread, ~2 GB per thread is preferred.  Keep in mind swap may not be available on embedded ARM devices; you may need swap to get through some large link steps.  (Use a device that can handle swap like a hard disk or SSD, don't put swap on SD/eMMC as it may wear out the card quickly.)

Building Qt requires roughly 40 GB of free disk space (can vary considerably).  The build script will abort if there isn't enough disk space to avoid filling up the disk.

# Submodules and patches

Most of the component sources are referenced using Git submodules, and PIA-specific changes are stored as patch files.  For example, OpenVPN is in `components/openvpn24/openvpn`, and PIA patches are in `components/openvpn24/patch-openvpn`.  In some cases, PIA has platform-specific patches, such as `components/openvpn24/patch-openvpn-build-windows` (patches used on Windows only for `openvpn-build`).

This format makes updating the upstream dependencies simple, and makes it easier to keep track of the PIA changes (so we don't lose anything on updates, and so we can see what changes we need to specifically test).  It's also possible to review changes to the patches, which is more difficult to do if the patches were committed directly onto the submodule repositories.

# Working on module patches

The workflow for working on the patches themselves is somewhat more involved than normal changes, but should not cause too much pain once you get the hang of it.

For simple changes, feel free to edit the patches manually (make sure to adjust line counts).  For more complex changes, you can turn the patches into Git commits on the submodule, edit the submodule normally, then regenerate patches.

In the procedure below, do everything from the submodule directory (and in bash on Windows); except for the full build in step 5, which is done from the component directory (where the build script is).

1. Create a work branch in the submodule
   * `git checkout -B my-work-branch` (create a new branch on current HEAD, name doesn't matter because you won't push it)
2. Apply patches
   * `git am ../patch-openvpn/*.patch`
3. Delete patches
   * Delete these so the build process won't apply them again (you'll regenerate them later)
   * `rm ../patch-openvpn/*.patch`
4. Make changes and commit to submodule
   * Commit author & message matter; these will go into the patch files
   * You can make any changes you want, including rewriting/squashing/amending the commits generated from the patches
5. Test build
   * From the component directory, run the appropriate build script to build that component
   * Repeat 4+5 as many times as you need to
6. Regenerate patches
   * `git format-patch -o ../patch-openvpn/ v2.4.9`, where `v2.4.9` is the original commit that this submodule was on
7. Revert submodule to original commit
   * `git checkout v2.4.9` (or whatever version that submodule was on)

You can now check in your changes to the patches (and/or build-pia.bat, etc.)

The submodule itself should not show any changes in the submodule repo's `git status`, since it's on the same commit that it was on initially.

# Updating a submodule to a new version

1. `cd` into the submodule
2. `git fetch` and and `git checkout <new_version>`
3. `cd` back to the component directory
4. Test build to make sure the patches still apply
   - If they don't update and regenerate them using the procedure above; resolve merge conflicts as necessary.
   - Commit the patch updates and submodule update together (since they probably depend on each other).
5. The submodule should show a change to the new commit; commit this to `desktop-dep-build`
