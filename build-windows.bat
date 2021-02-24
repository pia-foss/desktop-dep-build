@echo off

setlocal

if "%~2" == "" (
    echo usage: %0 ^<...path_to...^>\pia_desktop ^<brand_code^>
    echo.
    echo Builds OpenVPN, the Wireguard service executable, and the WinTUN MSI distribution for PIA.
    echo.
    call components/wireguard/scripts/build-wintun.bat --help-details
    goto :end
)

rem Get an absolute path from %1 before changing directories
set PIA_DESKTOP_PATH=%~f1

pushd %~dp0

echo ===Build OpenVPN and OpenSSL===
pushd components\openvpn24
call build-pia.bat
popd

echo ===Build WireGuard and WinTUN===
pushd components\wireguard
call scripts\build-windows.bat "%PIA_DESKTOP_PATH%" %2
popd

rem TODO - collect artifacts

:end
endlocal
popd
exit /b 0
