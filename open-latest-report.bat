@echo off
setlocal
set "SCRIPT=%~dp0open-latest-report.ps1"

if not exist "%SCRIPT%" (
    echo open-latest-report.ps1 was not found next to this file.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Open latest report finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
