@echo off
setlocal
setlocal ENABLEDELAYEDEXPANSION

rem Path to desktop-dep-build/components/qt
set QTCOMPDIR=%~dp0

pushd "%QTCOMPDIR%"

call :set_repo_path %QTCOMPDIR%\..\..\

set QT_MAJOR=5
set QT_MINOR=15
set QT_PATCH=0

set QT_VERSION=%QT_MAJOR%.%QT_MINOR%.%QT_PATCH%

rem Find 7-zip
set "P7Z=%PROGRAMFILES%\7-Zip\7z.exe"
if exist "%P7Z%" (
    echo Found 7-Zip installation
) else (
    echo Error: 7-Zip not found ^(install from https://7-zip.org/^)
    goto error
)

set OUT=%QTCOMPDIR%\out
set CACHE=%OUT%\cache
set BUILD=%OUT%\build
rem The Qt build directory is %REPO%\_qt, rather than %OUT%\build\qt, to reduce
rem the length of file paths.  Some Qt paths exceed 200 chars without even
rem counting this prefix, so we need to trim back the prefix as much as we can.
set QTBUILD=%REPO%\_qt
set INSTALL=%OUT%\install
set ARTIFACTS=%OUT%\artifacts

rem TODO - architectures
rem Name of arch used in installer package
set ARCHNAME=x64
rem Arch name given to vcvarsall
set VCARCH=amd64
rem Qt build name (includes arch), determines install directory
set QT_BUILD_NAME=msvc2019_64
set QT_INSTALL_ROOT=%INSTALL%\%QT_VERSION%\%QT_BUILD_NAME%

rem Where the root of the Qt source will be once it is extracted
set QTSRC=%QTBUILD%\qt-everywhere-src-%QT_VERSION%
rem "Shadow build directory" in Qt parlance - just an out-of-source build so we
rem can build more than one architecture from the same source tree
set QTSHADOW=%QTBUILD%\%QT_BUILD_NAME%

rem Parse arguments
rem
rem   --reconf - Skip download/extract - use existing source (reconfigure, rebuild, repack)
rem   --repack - Skip build, just repack installer archive
set ARG_RECONF=
set ARG_REPACK=
:arg_loop
if not "%1"=="" (
  if "%1"=="--reconf" (
    set ARG_RECONF=1
    shift
  ) else if "%1"=="--repack" (
    set ARG_REPACK=1
    shift
  ) else (
    echo Unknown option %1
    goto error
  )
) else (
  goto args_done
)
goto arg_loop
:args_done

if not "%ARG_REPACK%"=="" goto :installer_build

echo Cleaning build directories
mkdir "%OUT%" 2>NUL
echo Clean %ARTIFACTS%
rmdir /Q /S "%ARTIFACTS%"
echo Clean %INSTALL%
rmdir /Q /S "%INSTALL%"
mkdir "%ARTIFACTS%"
mkdir "%INSTALL%"
mkdir "%CACHE%" 2>NUL

if not "%ARG_RECONF%"=="" goto :configure

echo Clean %BUILD%
rmdir /Q /S "%BUILD%"
echo Clean %QTBUILD%
rmdir /Q /S "%QTBUILD%"
mkdir "%BUILD%"
mkdir "%QTBUILD%"

rem Download the Qt source archive if it isn't already present
set QT_SOURCE_ARCHIVE=%CACHE%\qt-everywhere-src-%QT_VERSION%.zip

call :download "Qt %QT_VERSION% source"^
    https://download.qt.io/official_releases/qt/%QT_MAJOR%.%QT_MINOR%/%QT_VERSION%/single/qt-everywhere-src-%QT_VERSION%.zip^
    %QT_SOURCE_ARCHIVE%^
    "8bf073f6ab3147f2fe72b753c1ebea83007deb2606e22a2804ebcf6467749469"

rem Download JOM (parallel replacement for nmake, provided by Qt)
set JOM_ARCHIVE=%CACHE%\jom_1_1_3.zip
call :download "Jom 1.13"^
    http://download.qt.io/official_releases/jom/jom_1_1_3.zip^
    %JOM_ARCHIVE%^
    "128fdd846fe24f8594eed37d1d8929a0ea78df563537c0c1b1861a635013fff8"

echo Extracting %QT_SOURCE_ARCHIVE%
"%P7Z%" x %QT_SOURCE_ARCHIVE% -o%QTBUILD%

echo Extracting Jom
mkdir "%BUILD%\jom"
"%P7Z%" x %JOM_ARCHIVE% -o%BUILD%\jom

:configure

rmdir /Q /S "%QTSHADOW%"
mkdir "%QTSHADOW%"
pushd %QTSHADOW%
echo Configure Qt %QT_VERSION%

rem TODO - find VS toolchain, architecture
call "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" %VCARCH%
@echo off

rem     Configure arguments: '-opensource -confirm-license -verbose -prefix c:\Users\qt\work\install -debug-and-release -release -force-debug-info -nomake tests -opengl dynamic -nomake examples -openssl -I %OPENSSL_INCLUDE_x64% -L %OPENSSL_LIB_x64% -no-sql-mysql -plugin-sql-sqlite -plugin-sql-odbc -I %MYSQL_INCLUDE_x64% -L %MYSQL_LIB_x64% -plugin-sql-psql -I %POSTGRESQL_INCLUDE_x64% -L %POSTGRESQL_LIB_x64% -qt-zlib'

rem TODO - pass openssl directories in from outer build script
rem TODO - need specific OpenSSL build for ARM since deps will still be x86

rm QtWebEngine is skipped; requires python2
set QT_CONF_ARGS=^
    -confirm-license ^
    -opensource ^
    -release ^
    -force-debug-info ^
    -separate-debug-info ^
    -nomake tests ^
    -nomake examples ^
    -opengl dynamic ^
    -openssl ^
    -I %QTCOMPDIR%\..\openvpn24\build.tmp\openvpn-build\msvc\build.tmp\openssl-1.1.1g\include\ ^
    -plugin-sql-sqlite ^
    -qt-zlib ^
    -skip qtwebengine ^
    -prefix "%QT_INSTALL_ROOT%"

rem Use configure.bat to bootstrap qmake and call the qmake-based configuration
call "%QTSRC%\configure" %QT_CONF_ARGS%
if %errorlevel% neq 0 (
    echo Qt configuration failed
    goto :error
)

echo Build Qt %QT_VERSION%
rem Use jom to build - nmake can also be used here, but it is much slower for
rem multicore systems
"%BUILD%\jom\jom.exe"
if %errorlevel% neq 0 (
    echo Qt build failed
    goto :error
)

echo Prepare installation for Qt %QT_VERSION%
"%BUILD%\jom\jom.exe" install
if %errorlevel% neq 0 (
    echo Qt installation failed
    goto :error
)

popd

rem Mark that this is the PIA Qt build, the PIA build scripts check this
mkdir %QT_INSTALL_ROOT%\share
echo "" > %QT_INSTALL_ROOT%\share\pia-qt-build

:installer_build

rem Create the installer payload with 7-zip
echo Create installer archive
pushd "%QT_INSTALL_ROOT%\.."
copy "%QTCOMPDIR%\src\win_install.bat" win_install.bat
call :subst_text win_install.bat "{{QT_VERSION}}" "%QT_VERSION%"
call :subst_text win_install.bat "{{QT_BUILD_NAME}}" "%QT_BUILD_NAME%"
rem Delete the archive if it exists (happens with --repack)
del /Q "%BUILD%\payload.7z"
"%P7Z%" a -mx9 "%BUILD%\payload.7z" "%QT_BUILD_NAME%" win_install.bat
popd

set INSTALLER_NAME=%ARTIFACTS%\qt-%QT_VERSION%-pia-windows-%ARCHNAME%.exe
echo Create installer
rem Perform substitutions on the installer configuration
copy src\win_install_cfg.txt "%BUILD%\win_install_cfg.txt"
call :subst_text "%BUILD%\win_install_cfg.txt" "{{QT_VERSION}}" "%QT_VERSION%"
call :subst_text "%BUILD%\win_install_cfg.txt" "{{QT_BUILD_NAME}}" "%QT_BUILD_NAME%"
copy /B lzma\7zSD.sfx + "%BUILD%\win_install_cfg.txt" + "%BUILD%\payload.7z" "%INSTALLER_NAME%"

rem Functions used throughout script
goto :funcs_end

rem Set REPO to absolute path to repo root - called with %QTCOMPDIR%\..\.. as
rem argument 1, so it can use %~dp1 to resolve the ..\..
:set_repo_path
set REPO=%~dp1
exit /b 0

rem Download and verify an artifact
rem  - %1 - name of download (displayed)
rem  - %2 - URI
rem  - %3 - output location
rem  - %4 - expected SHA256 hash
:download
if exist %3 (
  echo "Skipping download (cached): %3"
  exit /b 0
)
echo Downloading %~1
curl --fail -Lo %~3 %~2
for /f "delims=@ usebackq" %%g in (`powershell -c "(Get-FileHash -Algorithm SHA256 '%3').Hash.ToLower()"`) do if not "%%g"=="%~4" (
    echo %1 does not match expected hash:
    echo   actual:   %%g
    echo   expected: %~4
    exit /b 1
)
exit /b 0

rem Substitute text in a file
rem Usage: call :subst_text <file_path> <old_text> <new_text>
:subst_text
powershell -Command "(gc '%~1' -Raw).Replace('%~2', '%~3') | Set-Content -encoding ASCII -Path '%~1'"
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
