@echo off

setlocal

if "%~2" == "" (
    echo usage: %0 ^<...path_to...^>\pia_desktop ^<brand_code^>
    echo.
    echo Builds OpenVPN and the Wireguard service executable for PIA.
    echo.
    echo Does not build WinTUN due to code signing requirements ^(EV CS cert,
    echo WHQL^) - see components/wireguard/scripts/build-wintun-driver.bat
    echo and components/wireguard/scripts/build-wintun-api.bat.
    echo.
    goto :end
)

pushd %~dp0

echo ===Build OpenVPN and OpenSSL===
pushd components\openvpn24
call build-pia.bat
popd

echo ===Build WireGuard===
pushd components\wireguard
call scripts\build-wgservice.bat
popd

rem TODO - collect artifacts

:end
endlocal
popd
exit /b 0
