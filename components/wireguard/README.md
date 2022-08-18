# wireguard-build

This repository contains scripts and submodules used to build binary WireGuard®  assets for distrubtion with the Private Internet Access Desktop Application.

### macOS/Linux

```
$ scripts/build-posix.sh
-> Creates out/artifacts/wireguard-go
```

### Windows

The Windows desktop application requires two components built using this repository:

* `pia-wintun.dll` - The WinTUN API, including an embedded build of the signed WinTUN driver
* `pia-wgservice.exe` - a wrapper based on `wireguard-windows/embeddable-dll-service` intended to be installed and run as a Windows Service.

Build on Windows 10, and place the EWDK at `C:\EWDK\<version>` (see `desktop-dep-build\util\pia-setup-ewdk.bat`).

#### pia-wgservice.exe

Build with `scripts\build-wgservice.bat`.  The main Windows build script in desktop-dep-build (build-windows.bat) also invokes this.

No signing certificates are needed for this; the binary is signed during the PIA Desktop build.

#### pia-wintun.dll

Due to signing requirements, pia-wintun.dll must be built in several steps:

1. Build the WinTUN drivers - `scripts\build-wintun-driver.bat`
2. Sign the WinTUN drivers with your EV CS certificate - copy the artifacts to the signing machine, and call `sign-wintun-driver.bat <your_sha256_thumbprint>`
3. Upload the signed x86 and x86_64 drivers to Microsoft for WHQL signing: https://developer.microsoft.com/en-us/dashboard/hardware
4. Place all the signed artifacts in the repo:
   * EV CS signed - `wintun-signed\pia-wintun-release-<ARCH>.cab`
   * WHQL signed - `wintun-signed\whql\pia-wintun-release-<ARCH>.cab`
5. Build the WinTUN API - `scripts\build-wintun-api.bat`

### Disclaimer

All product and company names are trademarks™ or registered® trademarks of their respective holders. Use of them does not imply any affiliation with or endorsement by them.   

WireGuard® is a trademark of Jason A. Donenfeld, an individual
