@echo off
setlocal
set "SCRIPT=%~dp0cleanup-windows.ps1"

if not exist "%SCRIPT%" (
    echo cleanup-windows.ps1 was not found next to this file.
    pause
    exit /b 1
)

net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
    echo Requesting administrator rights for emergency cleanup...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Deep -AggressiveSafe -CleanDeveloperCaches -CleanRegistry -TempOlderThanDays 0 -CacheOlderThanDays 0 %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Emergency cleanup finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
