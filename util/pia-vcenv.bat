@echo off

rem Find and invoke vcvarsall.bat.  Parameters are passed to vcvarsall.bat (to
rem select architecture, etc.)  Note that this is _not_ in its own 'setlocal'
rem scope, as it's intended to spray environment variables in the caller's
rem environment.

set "PIA_VCENV_VSROOT=%ProgramFiles(x86)%\Microsoft Visual Studio\2019"

rem Find an edition of VS
call :probe_vs_edition "Professional" || call :probe_vs_edition "Community" || call :probe_vs_edition "BuildTools" || goto :no_vs_edition

set "PIA_VCENV_VCVARS=%PIA_VCENV_VSROOT%\VC\Auxiliary\Build\vcvarsall.bat"
call "%PIA_VCENV_VCVARS%" %* || goto :error

set PIA_VCENV_VSROOT=

goto end

:probe_vs_edition
if not exist "%PIA_VCENV_VSROOT%\%~1" exit /b 1
set "PIA_VCENV_VSROOT=%PIA_VCENV_VSROOT%\%~1"
exit /b 0

:no_vs_edition
echo Could not find any edition of Visual Studio in path:
echo %PIA_VCENV_VSROOT%
goto :error

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
