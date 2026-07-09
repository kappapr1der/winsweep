@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "SCRIPT=%~dp0cleanup-windows.ps1"
set "CONFIG=%~dp0winsweep-config.json"

if not exist "%SCRIPT%" (
    echo cleanup-windows.ps1 was not found next to this file.
    pause
    exit /b 1
)

if not exist "%CONFIG%" (
    echo winsweep-config.json was not found next to this file.
    echo The menu can still run, but config defaults will not be loaded.
    echo.
    pause
)

:menu
cls
echo.
echo ==============================
echo WinSweep
echo ==============================
echo.
echo 1. Scan results (no deletion)
echo 2. Safe cleanup
echo 3. Gaming cleanup
echo 4. Deep cleanup (admin)
echo 5. Emergency cleanup (admin)
echo 6. Disk space report
echo 7. Open logs
echo 8. Install scheduled tasks (admin)
echo 9. Edit config
echo Q. Quit
echo.
set "PICK="
set /p "PICK=Choose: "

if /i "%PICK%"=="q" exit /b 0

if "%PICK%"=="1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Analyze -Profile Emergency
    goto after
)

if "%PICK%"=="2" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Profile Safe
    goto after
)

if "%PICK%"=="3" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Profile Gaming
    goto after
)

if "%PICK%"=="4" (
    call "%~dp0cleanup-deep-now.bat"
    goto menu
)

if "%PICK%"=="5" (
    call "%~dp0cleanup-emergency-now.bat"
    goto menu
)

if "%PICK%"=="6" (
    call "%~dp0disk-space-report.bat"
    goto menu
)

if "%PICK%"=="7" (
    call "%~dp0open-cleanup-logs.bat"
    goto menu
)

if "%PICK%"=="8" (
    call "%~dp0install-scheduled-cleanup.bat"
    goto menu
)

if "%PICK%"=="9" (
    start "" notepad.exe "%CONFIG%"
    goto menu
)

echo.
echo Unknown choice: %PICK%

:after
echo.
pause
goto menu
