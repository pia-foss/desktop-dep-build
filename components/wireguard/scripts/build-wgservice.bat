@echo off

rem This script was originally based on: https://git.zx2c4.com/wireguard-windows/tree/build.bat
rem SPDX-License-Identifier: MIT
rem Copyright (C) 2019 WireGuard LLC. All Rights Reserved.
rem Modifications Copyright (C) 2020 Private Internet Access, Inc., and released under the MIT License. 

setlocal EnableDelayedExpansion
set COMPDIR=%~dp0..
set PATHEXT=.exe
cd /d %COMPDIR% || exit /b 1

set BUILD=.\build-wgservice
rmdir /Q /S %BUILD% 2>NUL
mkdir %BUILD%

rem Set up wireguard-windows and wireguard-go
rem Check that repos are clean
call ..\..\util\prep_submodule.bat check .\wireguard-windows || goto error
call ..\..\util\prep_submodule.bat check .\wireguard-go || goto error
rem Clone and patch
call ..\..\util\prep_submodule.bat prep .\wireguard-windows %BUILD%\wireguard-windows patch-wireguard-windows || goto error
call ..\..\util\prep_submodule.bat prep .\wireguard-go %BUILD%\wireguard-go patch-wireguard-go || goto error

rem wireguard-windows' build scripts expect deps to be set up here
rem Don't rely on it downloading binary deps, these tend to disappear over
rem time which prevents us from reproducing the current build
set DEPS=%BUILD%\wireguard-windows\.deps

rem Install deps
mkdir %DEPS% || goto :error
pushd %DEPS% || goto :error
for %%i in (%COMPDIR%\deps\win\*.zip) do (
	echo [+] Extracting %1
	"C:\Program Files\7-Zip\7z.exe" x "%%i" || goto error
)
rem Indicate that deps are set up (prevents build.bat from doing any setup)
echo "" > prepared
popd

rem Extract vendored Go modules
rem
rem The Go module dependencies have been vendored to ensure that we can still
rem rebuild this version of pia-wgservice even if the dependencies are taken
rem down (which has happened in the past).
rem
rem The vendor directory in the archive was created with "go mod vendor -v" from
rem the prepared wireguard-windows submodule (with patches applied).  The
rem UI-related directories were deleted (manager, ui, updater, main.go) -
rem otherwise go mod will pick them up and re-add the win/walk dependencies that
rem we patched out.
pushd %BUILD%\wireguard-windows
"C:\Program Files\7-Zip\7z.exe" x "%COMPDIR%\vendor-win.zip" || goto error
rmdir /Q /S "vendor\golang.zx2c4.com\wireguard"
move "..\wireguard-go" "vendor\golang.zx2c4.com\wireguard"
dir vendor
dir vendor\golang.zx2c4.com
popd

call %BUILD%\wireguard-windows\embeddable-dll-service\build.bat || goto error

:success
goto :end
:error
echo [-] Failed with error #%errorlevel%.
exit /b %errorlevel%
:end
exit /b 0
