@echo off
setlocal

net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
    echo Requesting administrator rights to remove scheduled tasks...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ScheduledTask -TaskPath '\Codex Windows Cleanup\' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false; Write-Host 'Removed Codex Windows Cleanup scheduled tasks, if they existed.'"
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
