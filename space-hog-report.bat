@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "SCRIPT=%~dp0space-hog-report.ps1"
if not exist "%SCRIPT%" (
    echo space-hog-report.ps1 was not found next to this file.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -OpenReport %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Space diagnostics finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
