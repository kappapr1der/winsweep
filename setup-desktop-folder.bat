@echo off
setlocal
set "SETUP=%~dp0setup-desktop-folder.ps1"

if not exist "%SETUP%" (
    echo setup-desktop-folder.ps1 was not found next to this file.
    pause
    exit /b 1
)

net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
    echo Requesting administrator rights to create the desktop kit and install scheduled tasks...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SETUP%" -InstallSchedule -SpotifyCache -Registry -ExtraPaths %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
