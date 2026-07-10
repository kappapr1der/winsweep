@echo off
setlocal
set "SCRIPT=%~dp0save-github-token.ps1"

if not exist "%SCRIPT%" (
    echo save-github-token.ps1 was not found next to this file.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Save GitHub token finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
