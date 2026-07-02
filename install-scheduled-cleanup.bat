@echo off
setlocal
set "INSTALLER=%~dp0install-scheduled-cleanup.ps1"

if not exist "%INSTALLER%" (
    echo install-scheduled-cleanup.ps1 was not found next to this file.
    pause
    exit /b 1
)

net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
    echo Requesting administrator rights to install scheduled tasks...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
