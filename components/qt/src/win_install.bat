@echo off
setlocal

set INSTALLTEMPDIR=%~dp0

echo Creating installation directory...
mkdir C:\Qt{{QT_VERSION}}-pia\{{QT_VERSION}}
echo Cleaning any existing installation...
rmdir /S /Q C:\Qt{{QT_VERSION}}-pia\{{QT_VERSION}}\{{QT_BUILD_NAME}}
echo Move extracted files to installation directory...
move /Y "%INSTALLTEMPDIR%\{{QT_BUILD_NAME}}" C:\Qt{{QT_VERSION}}-pia\{{QT_VERSION}}
echo Installation complete
