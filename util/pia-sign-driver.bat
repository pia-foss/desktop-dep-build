@echo off
setlocal EnableDelayedExpansion

set SIGN_DRIVER_ARG_SHOW_HELP=0
set SIGN_DRIVER_ARG_SHOW_HELP_ENV_ONLY=0

:arg_loop
set PARAM_TEST=%~1
if not "%PARAM_TEST%" == "" (
  set PARAM_TEST=%PARAM_TEST:~0,2%
)
if "%PARAM_TEST%"=="--" (
  if "%1"=="--help" (
    set SIGN_DRIVER_ARG_SHOW_HELP=1
  ) else if "%1"=="--help-env" (
    set SIGN_DRIVER_ARG_SHOW_HELP=1
    set SIGN_DRIVER_ARG_SHOW_HELP_ENV_ONLY=1
  ) else if "%1"=="--" (
    shift
    goto args_done
  ) else (
    echo Unknown option %1
    set SIGN_DRIVER_ARG_SHOW_HELP=1
  )
  shift
  goto arg_loop
)

if "%4" == "" (
  set SIGN_DRIVER_ARG_SHOW_HELP=1
)

if %SIGN_DRIVER_ARG_SHOW_HELP% NEQ 0 (
  rem help-env is used to embed the environment help in another script
  if %SIGN_DRIVER_ARG_SHOW_HELP_ENV_ONLY% EQU 0 (
    echo usage:
    echo   %0 [--] cert_thumbprint driver.cat cab-path cab-name
    echo   %0 --help
    echo.
    echo Signs the specified cat files using the certificates and authorities specified by
    echo the certificate thumbprint, PIA_SIGN_CROSSCERT, and PIA_SIGN_TIMESTAMP.
    echo.
    echo   cert_thumbprint - Thumbprint of the SHA-256 EV CS certificate to sign with.
    echo   driver.cat - Path to the catalog file to sign
    echo   cab-path - Path to the folder where the cab should be generated
    echo   cab-name - Name of the cabinet archive to build, excluding extension
    echo   -- - Can be used to terminate switches if paths begin with "--"
    echo.
    echo The built cabinet archive contains all files from the directory containing driver.cat,
    echo including driver.cat itself.
    echo.
  )

  echo PIA_SIGN_CROSSCERT = CA certificate file for EV certificate ^(default: DigiCert EV^)
  echo PIA_SIGN_TIMESTAMP = timestamp server for signing ^(default: DigiCert^)
  echo.
  exit /B 0
)

set SIGN_SHA256_CERT=%~1
set DRIVER_CAT=%2
set DRIVER_CAT_PATH=%~dp2
set CAB_PATH=%3
set CAB_NAME=%4

if [%PIA_SIGN_CROSSCERT%] == [] set "PIA_SIGN_CROSSCERT=%~dp0\DigiCert-High-Assurance-EV-Root-CA.crt"
if [%PIA_SIGN_TIMESTAMP%] == [] set "PIA_SIGN_TIMESTAMP=http://timestamp.digicert.com"

rem Sign driver artifacts
if not [%SIGN_SHA256_CERT%] == [] (
    echo * Signing driver with SHA256 certificate...
        
    for /R "%DRIVER_CAT_PATH%" %%G in (*.sys) do (
        call :sha256_sign_file %%G
        if !errorlevel! neq 0 goto error
    )
        
    call :sha256_sign_file %DRIVER_CAT%
    if !errorlevel! neq 0 goto error
)
    
rem Build CAB archive for submission to Microsoft.
rem This is still done even if signing isn't enabled to test the build process.

>"%CAB_PATH%\%CAB_NAME%.ddf" (
    echo .option explicit
    echo .set CabinetFileCountThreshold=0
    echo .set FolderFileCountThreshold=0
    echo .set FolderSizeThreshold=0
    echo .set MaxCabinetSize=0
    echo .set MaxDiskFileCount=0
    echo .set MaxDiskSize=0
    echo .set Cabinet=on
    echo .set Compress=on
    echo .set DiskDirectoryTemplate=%CAB_PATH%
    echo .set DestinationDir=Package
    echo .set CabinetNameTemplate=%CAB_NAME%.cab
    echo .set SourceDir=%DRIVER_CAT_PATH%
)
    
for /R "%DRIVER_CAT_PATH%" %%G in (*.*) do (
    echo %%~nxG >> "%CAB_PATH%\%CAB_NAME%.ddf"
)
    
makecab /F "%CAB_PATH%\%CAB_NAME%.ddf" >NUL
if !errorlevel! neq 0 (
    set errorlevel=!errorlevel!
    del /Q /F "%CAB_PATH%\%CAB_NAME%.ddf"
    goto error
)
del /Q /F "%CAB_PATH%\%CAB_NAME%.ddf"
rem These are always created in the current directory by makecab
del "setup.inf"
del "setup.rpt"
   
rem Sign the CAB archive with the same certificate (SHA256 only)
if not [%SIGN_SHA256_CERT%] == [] (
    echo * Signing CAB for Microsoft submission...
    signtool.exe sign /ac "%PIA_SIGN_CROSSCERT%" /fd sha256 /tr "%PIA_SIGN_TIMESTAMP%" /td sha256 /sha1 "%SIGN_SHA256_CERT%" "%CAB_PATH%\%CAB_NAME%.cab"
    if !errorlevel! neq 0 goto error
    
    echo.
    echo To get Microsoft certified drivers for Windows 10, submit the
    echo signed CAB files to the Microsoft Dev Center at:
    echo.
    echo https://developer.microsoft.com/en-us/dashboard/hardware
    echo.
) else (
    echo * No certificates specified; drivers will not be installable
)

goto end

:sha256_sign_file
echo * Signing %~nx1 with SHA256...
signtool.exe sign /ac "%PIA_SIGN_CROSSCERT%" /fd sha256 /tr "%PIA_SIGN_TIMESTAMP%" /td sha256 /sha1 "%SIGN_SHA256_CERT%" "%~1"
exit /b

:end
endlocal
exit /b %errorlevel%

:error
if %errorlevel% equ 0 (
  set errorlevel=1
) else (
  echo.
  echo Build failed with error %errorlevel%!
)
goto end
