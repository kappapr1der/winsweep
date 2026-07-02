@echo off
setlocal
set "SCRIPT=%~dp0disk-space-report.ps1"

if not exist "%SCRIPT%" (
    echo disk-space-report.ps1 was not found next to this file.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -AllFixedDrives -Top 12 %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Disk report finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
