@echo off
setlocal ENABLEDELAYEDEXPANSION

rem 'check' - check if a submodule is clean
rem %2 - repo path
if "%1" == "check" (
	git -C %2 diff-index --quiet HEAD --
	if not errorlevel 0 (
		echo submodule is not clean, commit or revert changes before building
		echo in submodule: %2
		goto error
	)
	goto success
)

rem 'prep' - clone submodule and apply patches
rem %2 - repo path
rem %3 - clone path
rem %4 - patch dir name
if "%1" == "prep" (
	git clone %2 %3 || goto error
	for %%i in (.\%4\*.patch) do (
		git -C %3 am < %%i || goto error
	)
	goto success
)

echo unknown command - %1
goto error

:success
set rc=0
goto end
:error
set rc=1
:end
exit /b %rc%
