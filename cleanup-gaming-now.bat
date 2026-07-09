@echo off
setlocal
set "SCRIPT=%~dp0cleanup-windows.ps1"

if not exist "%SCRIPT%" (
    echo cleanup-windows.ps1 was not found next to this file.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Profile Gaming -OpenReport %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Gaming cleanup finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
