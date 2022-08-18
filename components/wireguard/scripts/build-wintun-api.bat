rem Copyright (c) 2022 Private Internet Access, Inc.
rem
rem This file is part of the Private Internet Access Desktop Client.
rem
rem The Private Internet Access Desktop Client is free software: you can
rem redistribute it and/or modify it under the terms of the GNU General Public
rem License as published by the Free Software Foundation, either version 3 of
rem the License, or (at your option) any later version.
rem
rem The Private Internet Access Desktop Client is distributed in the hope that
rem it will be useful, but WITHOUT ANY WARRANTY; without even the implied
rem warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
rem GNU General Public License for more details.
rem
rem You should have received a copy of the GNU General Public License
rem along with the Private Internet Access Desktop Client.  If not, see
rem <https://www.gnu.org/licenses/>.

@echo off
setlocal
setlocal EnableDelayedExpansion

set COMPDIR=%~dp0..
cd /d %COMPDIR% || exit /b 1

rem === WinTUN API build script ===
rem
rem This script builds the WinTUN API DLL with PIA branding, which embeds the
rem PIA-branded WinTUN driver (built by build-wintun-driver.bat).
rem
rem Before running this script, build the driver with build-wintun-driver.bat,
rem then submit the driver to Microsoft for WHQL signing.  Signing is performed
rem separately after build to permit using a separate signing machine to hold the
rem EV CS certificate.
rem
rem Place the signed CABs before building the API:
rem - EV CS signed - wintun-signed\pia-wintun-release-<ARCH>.cab
rem - WHQL signed  - wintun-signed\whql\pia-wintun-release-<ARCH>.cab
rem
rem pia-wintun.dll can then be included in PIA Desktop.  pia-wintun.dll is not
rem signed by this script; that occurs as part of the PIA Desktop build.

echo Building WinTUN API

set BUILD_DIR=.\build-wintun-api
set ARTIFACT_DIR=.\out\artifacts\wintun-api
rmdir /Q /S "%BUILD_DIR%"
mkdir "%BUILD_DIR%"
rmdir /Q /S "%ARTIFACT_DIR%"
mkdir "%ARTIFACT_DIR%"

rem Find the VS toolchain
call ..\..\util\pia-vcenv.bat x64 || goto error

rem TODO - Make sure WHQL-signed drivers are present, warn if not, copy to wintun\Release\<arch>\whql

rem Set up wintun
rem Check that repos are clean
call ..\..\util\prep_submodule.bat check .\wintun || goto error
rem Clone and patch
call ..\..\util\prep_submodule.bat prep .\wintun %BUILD_DIR%\wintun patch-wintun || goto error

rem Build API
call :build_arch x64 amd64 x86_64 || goto error
call :build_arch Win32 x86 x86 || goto error

goto :funcs_end

:build_arch
rem Platform name expected by driver.vcxproj
set PROJ_PLATFORM=%1
rem Architecture name used in output directory (Release\amd64, etc.)
set BUILD_ARCH=%2
rem Architecture name used for PIA artifacts
set OUT_ARCH=%3
mkdir "%ARTIFACT_DIR%\%OUT_ARCH%"
rem Pull in WinTUN driver artifacts, which are embedded in the API DLL
rem First, non-WHQL artifacts (Win <=8.1)
set WINTUN_ARTIFACT_DIR=%BUILD_DIR%\wintun\Release\%BUILD_ARCH%
mkdir "%WINTUN_ARTIFACT_DIR%"
expand .\wintun-signed\pia-wintun-release-%OUT_ARCH%.cab -F:* "%WINTUN_ARTIFACT_DIR%" || goto error
ren "%WINTUN_ARTIFACT_DIR%\Package" "pia-wintun"
rem Second, pull in WHQL artifacts (Win 10)
rem TODO TODO TODO - "%WINTUN_ARTIFACT_DIR%\whql"
msbuild %BUILD_DIR%\wintun\api\api.vcxproj /p:Configuration=Release /p:Platform=%PROJ_PLATFORM% || goto error
copy /y %BUILD_DIR%\wintun\Release\%BUILD_ARCH%\pia-wintun.dll %ARTIFACT_DIR%\%OUT_ARCH%\
exit /b 0

:funcs_end
set rc=0
goto :end
:error
set rc=1
:end
endlocal
popd
exit /b %rc%
