@echo off
setlocal
set "SCRIPT=%~dp0build-release.ps1"

if not exist "%SCRIPT%" (
    echo build-release.ps1 was not found next to this file.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Build release finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
