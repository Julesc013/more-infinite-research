@echo off
setlocal
set "mir_powershell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%mir_powershell%" (
  echo Windows PowerShell was not found. Run Collect-MIRPlayerReport.ps1 with PowerShell.
  pause
  exit /b 1
)
"%mir_powershell%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-MIRPlayerReport.ps1" -OutputDirectory "%~dp0." -CopyPath -ShowInExplorer %*
set "report_exit=%ERRORLEVEL%"
if not "%report_exit%"=="0" echo MIR could not create a report. The error is shown above.
echo.
pause
exit /b %report_exit%
