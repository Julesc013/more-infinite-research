function Invoke-MIRProcess {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$WorkingDirectory = (Get-Location).Path,
    [string]$StdoutPath = "",
    [string]$StderrPath = "",
    [int]$TimeoutSeconds = 0
  )

  $started = Get-Date
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FilePath
  foreach ($argument in $Arguments) {
    [void]$startInfo.ArgumentList.Add($argument)
  }
  $startInfo.WorkingDirectory = $WorkingDirectory
  $startInfo.UseShellExecute = $false

  if (-not [string]::IsNullOrWhiteSpace($StdoutPath)) {
    $stdoutDir = Split-Path -Parent $StdoutPath
    if (-not [string]::IsNullOrWhiteSpace($stdoutDir)) {
      New-Item -ItemType Directory -Force -Path $stdoutDir | Out-Null
    }
    $startInfo.RedirectStandardOutput = $true
  }
  if (-not [string]::IsNullOrWhiteSpace($StderrPath)) {
    $stderrDir = Split-Path -Parent $StderrPath
    if (-not [string]::IsNullOrWhiteSpace($stderrDir)) {
      New-Item -ItemType Directory -Force -Path $stderrDir | Out-Null
    }
    $startInfo.RedirectStandardError = $true
  }

  $process = [System.Diagnostics.Process]::Start($startInfo)
  $stdoutTask = $null
  $stderrTask = $null
  if ($startInfo.RedirectStandardOutput) {
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  }
  if ($startInfo.RedirectStandardError) {
    $stderrTask = $process.StandardError.ReadToEndAsync()
  }

  $timedOut = $false
  if ($TimeoutSeconds -gt 0) {
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      $timedOut = $true
      try { $process.Kill($true) } catch { try { $process.Kill() } catch {} }
      $process.WaitForExit()
    }
  } else {
    $process.WaitForExit()
  }

  if ($stdoutTask) {
    $stdoutTask.Wait()
    $stdoutTask.Result | Set-Content -LiteralPath $StdoutPath -Encoding UTF8
  }
  if ($stderrTask) {
    $stderrTask.Wait()
    $stderrTask.Result | Set-Content -LiteralPath $StderrPath -Encoding UTF8
  }

  [pscustomobject]@{
    name = $Name
    file_path = $FilePath
    arguments = @($Arguments)
    exit_code = $process.ExitCode
    timed_out = $timedOut
    timeout_seconds = $TimeoutSeconds
    seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
    stdout = $StdoutPath
    stderr = $StderrPath
    passed = (-not $timedOut -and $process.ExitCode -eq 0)
  }
}
