@echo off
setlocal
set "SCRIPT=%~dp0publish-release.ps1"

if not exist "%SCRIPT%" (
    echo publish-release.ps1 was not found next to this file.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Publish release finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
