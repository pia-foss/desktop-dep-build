@echo off

set SETUP_EWDK_ARG_SHOW_HELP=0
set SETUP_EWDK_ARG_SHOW_HELP_ENV_ONLY=0

:arg_loop
if not "%1"=="" (
  if "%1"=="--help" (
    set SETUP_EWDK_ARG_SHOW_HELP=1
  ) else if "%1"=="--help-env" (
    set SETUP_EWDK_ARG_SHOW_HELP=1
    set SETUP_EWDK_ARG_SHOW_HELP_ENV_ONLY=1
  ) else (
    echo Unknown option %1
    set SETUP_EWDK_ARG_SHOW_HELP=1
  )
  shift
  goto arg_loop
)

if %SETUP_EWDK_ARG_SHOW_HELP% NEQ 0 (
  rem help-env is used to embed the environment help in another script
  if %SETUP_EWDK_ARG_SHOW_HELP_ENV_ONLY% EQU 0 (
    echo usage:
    echo   %0
    echo   %0 --help
    echo.
    echo Locates and sets up the EWDK environment.
    echo Note: The EWDK setup script may turn echo back on.
    echo.
  )
  echo EWDK = path to the EWDK, by default the newest EWDK from C:\EWDK\* is used.
  echo.
  exit /B 0
)

if [%EWDK%] == [] (
  for /D %%G in ("C:\EWDK\*") do set "EWDK=%%G"
)
if not exist "%EWDK%" (
  echo Error: EWDK not found.
  goto error
)
echo * Using EWDK in %EWDK%

call "%EWDK%\BuildEnv\SetupBuildEnv.cmd"

:end
exit /b %errorlevel%

:error
if %errorlevel% equ 0 (
  set errorlevel=1
) else (
  echo.
  echo Build failed with error %errorlevel%!
)
goto end
