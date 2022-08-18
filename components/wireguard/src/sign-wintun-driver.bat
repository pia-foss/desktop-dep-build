@echo off

rem === WinTUN driver signing script ===
rem
rem This script is deployed into the artifacts package by
rem build-wintun-driver.bat.  It's then executed on the signing machine;
rem utility scripts are deployed into utils/.
rem
rem Drivers are signed with the EV CS certificate specified, then packaged into
rem signed CAB artifacts suitable for submission to Microsoft for WHQL signing.
rem
rem The EWDK is found automatically from C:\EWDK\<version>. (See
rem ..\..\util\pia-setup-ewdk.bat --help)

setlocal
setlocal EnableDelayedExpansion

set ARTIFACT_DIR=%~dp0
cd /d %ARTIFACT_DIR% || exit /b 1

set SIGN_WINTUN_ARG_SHOW_HELP=0

:arg_loop
set PARAM_TEST=%1
if not "%PARAM_TEST%" == "" (
  set PARAM_TEST=%PARAM_TEST:~0,2%
)
if "%PARAM_TEST%"=="--" (
  if "%1"=="--help" (
    set SIGN_WINTUN_ARG_SHOW_HELP=1
  ) else if "%1"=="--" (
    shift
    goto args_done
  ) else (
    echo Unknown option %1
    set SIGN_WINTUN_ARG_SHOW_HELP=1
  )
  shift
  goto arg_loop
)

if "%1" == "" (
  set SIGN_WINTUN_ARG_SHOW_HELP=1
)

if %SIGN_WINTUN_ARG_SHOW_HELP% NEQ 0 (
  echo usage:
  echo   %0 [--] ^<cert_thumbprint^>
  echo   %0 --help
  echo.
  echo Signs the WinTUN driver, and creates signed CAB archives for WHQL
  echo submission.
  echo.
  echo   cert_thumbprint - Thumbprint of the SHA-256 EV CS certificate to sign with.
  echo.
  call .\util\pia-setup-ewdk --help-env
  call .\util\pia-sign-driver --help-env
  exit /B 0
)

set SIGN_SHA256_THUMBPRINT=%~1

rem Find EWDK to build driver
call .\util\pia-setup-ewdk.bat || goto error
@echo off
rem ^^ EWDK turns echo back on

rem Sign drivers
call :sign_arch x86_64 || goto error
call :sign_arch x86 || goto error

goto :funcs_end

:sign_arch
rem Architecture name used for PIA artifacts
set OUT_ARCH=%1
call .\util\pia-sign-driver.bat "%SIGN_SHA256_THUMBPRINT%" %ARTIFACT_DIR%\%OUT_ARCH%\pia-wintun.cat %ARTIFACT_DIR% pia-wintun-Release-%OUT_ARCH% || goto error
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
