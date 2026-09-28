@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-MIRPlayerReport.ps1" -OutputDirectory "%~dp0" -CopyPath -ShowInExplorer %*
set "report_exit=%ERRORLEVEL%"
if not "%report_exit%"=="0" echo MIR could not create a report. The error is shown above.
echo.
pause
exit /b %report_exit%
