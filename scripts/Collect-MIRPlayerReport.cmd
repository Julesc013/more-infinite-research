@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-MIRPlayerReport.ps1" -OutputDirectory "%~dp0" -CopyPath %*
echo.
pause
