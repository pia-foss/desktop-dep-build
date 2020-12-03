# openvpn24-client

This repository builds the OpenVPN 2.4 client for use in desktop.

Since this repository uses submodules, make sure to include `--recursive` when cloning it.  If you forgot, `git submodule update --init --recursive` will initialize the submodules.

## Submodules and patches

`openvpn` and `openvpn-build` are included as submodules, and PIA-specific changes are stored as patch files in this repository.

This makes updating the upstream dependencies simple, and makes it easier to keep track of the PIA changes (so we don't lose anything on updates, and so we can see what changes we need to specifically test).

| Submodule | Platform | Patch directory |
|-----------|----------|-----------------|
| openvpn   | Any      | patch-openvpn   |
| openvpn-build | Windows | patch-openvpn-build-windows |
| openvpn-build | Mac/Linux | patch-openvpn-build-posix |

## Submodules, patches, updating dependencies

This project includes dependencies as submodules; patches are applied at build time.

The preferred way to work on the submodule patches is to apply them to the submodule, work in the submodule and commit to Git (locally), then regenerate patches.  See https://github.com/pia-foss/desktop-dep-build#working-on-module-patches.