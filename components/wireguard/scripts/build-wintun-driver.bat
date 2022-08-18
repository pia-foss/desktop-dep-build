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

rem === WinTUN driver build script ===
rem
rem This script builds the WinTUN driver with PIA branding.  The output
rem artifact contains a CAB file and scripts for signing with an EV CS
rem certificate, which produces a signed CAB suitable for submission to
rem Microsoft for
rem WHQL signing.
rem
rem The EWDK is found automatically from C:\EWDK\<version>. (See
rem ..\..\util\pia-setup-ewdk.bat --help)
rem 
rem This script does not build wintun.dll, that is handled in a second step
rem by build-wintun-api.bat.  These must be separate since WHQL signing must
rem be done manually between the two steps.

echo Building WinTUN driver

set BUILD_DIR=.\build-wintun-driver
set ARTIFACT_DIR=.\out\artifacts\wintun-driver
rmdir /Q /S "%BUILD_DIR%"
mkdir "%BUILD_DIR%"
rmdir /Q /S "%ARTIFACT_DIR%"
mkdir "%ARTIFACT_DIR%"

rem Set up wintun
rem Check that repos are clean
call ..\..\util\prep_submodule.bat check .\wintun || goto error
rem Clone and patch
call ..\..\util\prep_submodule.bat prep .\wintun %BUILD_DIR%\wintun patch-wintun || goto error

rem Find EWDK to build driver
call ..\..\util\pia-setup-ewdk.bat || goto error
@echo off
rem ^^ EWDK turns echo back on

rem Build driver
call :build_arch x64 amd64 x86_64 || goto error
call :build_arch Win32 x86 x86 || goto error

rem Set up the signing scripts in artifacts/, so the whole artifacts/ directory
rem can be copied to the signing machine without needing this repository
mkdir "%ARTIFACT_DIR%\util"
robocopy ..\..\util "%ARTIFACT_DIR%\util" pia-setup-ewdk.bat pia-sign-driver.bat DigiCert-High-Assurance-EV-Root-CA.crt
copy /y .\src\sign-wintun-driver.bat "%ARTIFACT_DIR%\"

echo.
echo Successfully built WinTUN driver!
echo.
echo Now copy "%ARTIFACT_DIR%" to the signing machine, and sign the driver with
echo with your EV CS certificate:
echo.
echo   sign-wintun-driver.bat ^<your_sha256_thumbprint^>

goto :funcs_end

:build_arch
rem Platform name expected by driver.vcxproj
set PROJ_PLATFORM=%1
rem Architecture name used in output directory (Release\amd64, etc.)
set BUILD_ARCH=%2
rem Architecture name used for PIA artifacts
set OUT_ARCH=%3
mkdir "%ARTIFACT_DIR%\%OUT_ARCH%"
msbuild %BUILD_DIR%\wintun\driver\driver.vcxproj /p:Configuration=Release /p:Platform=%PROJ_PLATFORM% || goto error
copy /y %BUILD_DIR%\wintun\Release\%BUILD_ARCH%\pia-wintun\*.* %ARTIFACT_DIR%\%OUT_ARCH%\

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
