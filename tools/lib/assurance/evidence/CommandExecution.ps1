function Quote-MIRAssuranceCommandArgument {
  param([Parameter(Mandatory)][string]$Value)
  return "'" + $Value.Replace("'", "''") + "'"
}

function Resolve-MIRAssuranceCommandText {
  param(
    [Parameter(Mandatory)][string]$Command,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$Plan,
    [string]$TestOutput = ""
  )
  $approvedDeltaPath = if ($Command.Contains("<approved-delta-path>")) {
    Resolve-MIRAssuranceApprovedDeltaPath -VerificationProfile $Context.verification_profile
  } else { "" }
  $values = [ordered]@{
    "<factorio>"=[string]$Context.factorio
    "<candidate>"=[string]$Context.candidate
    "<prior-release>"=[string]$Context.prior_release
    "<mods>"=[string]$Context.mods
    "<baseline>"=[string]$Plan.baseline
    "<seal>"=[string]$Context.seal
    "<target>"=[string]$Context.target
    "<upgrade-from>"=[string]$Context.verification_profile.upgrade.from_version
    "<upgrade-to>"=[string]$Context.verification_profile.upgrade.to_version
    "<upgrade-fixture>"=[string]$Context.verification_profile.upgrade.fixture
    "<approved-delta-path>"=[string]$approvedDeltaPath
    "<source-commit>"=[string]$Plan.source_commit
    "<package-source-commit>"=[string]$Plan.package_source_commit
    "<qualification-factorio-version>"=[string]$Context.verification_profile.qualification_factorio_version
    "<test-output>"=[string]$TestOutput
  }
  $resolved = $Command
  foreach ($entry in $values.GetEnumerator()) {
    if ($resolved.Contains([string]$entry.Key)) {
      if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) { throw "Command requires $($entry.Key), but no matching option was supplied." }
      $resolved = $resolved.Replace([string]$entry.Key, (Quote-MIRAssuranceCommandArgument -Value ([string]$entry.Value)))
    }
  }
  if ($resolved -match '<[^>]+>') { throw "Unresolved assurance command placeholder: $resolved" }
  return $resolved
}

function Invoke-MIRAssuranceCommandText {
  param(
    [Parameter(Mandatory)][string]$Command,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)][string]$StdoutPath,
    [Parameter(Mandatory)][string]$StderrPath,
    [string]$TestOutput = ""
  )
  $resolved = Resolve-MIRAssuranceCommandText -Command $Command -Context $Context -Plan $Plan -TestOutput $TestOutput
  $tokens = [Management.Automation.PSParser]::Tokenize($resolved, [ref]$null) | Where-Object { $_.Type -notin @("Comment", "NewLine") }
  if ($tokens.Count -eq 0) { throw "Empty assurance command." }
  $commandPath = [string]$tokens[0].Content
  if ($commandPath.StartsWith("./")) { $commandPath = Join-Path $repo $commandPath.Substring(2) }
  $argumentTokens = @($tokens | Select-Object -Skip 1)
  $global:LASTEXITCODE = 0
  $exitCode = 0
  $thrownMessage = ""
  if ([IO.Path]::GetFileName($commandPath) -eq "mir.ps1") {
    $arguments = @($argumentTokens | ForEach-Object { [string]$_.Content })
    try { & $commandPath @arguments 1> $StdoutPath 2> $StderrPath 3>&1 4>&1 5>&1 6>&1 }
    catch { $exitCode = 1; $thrownMessage = $_.Exception.Message }
  } else {
    $named = @{}
    $positional = @()
    for ($i = 0; $i -lt $argumentTokens.Count; $i++) {
      $token = $argumentTokens[$i]
      if ($token.Type -eq [Management.Automation.PSTokenType]::CommandParameter) {
        $name = ([string]$token.Content).TrimStart("-")
        $value = $true
        if ($i + 1 -lt $argumentTokens.Count -and $argumentTokens[$i + 1].Type -ne [Management.Automation.PSTokenType]::CommandParameter) {
          $i++
          $value = [string]$argumentTokens[$i].Content
        }
        $named[$name] = $value
      } else {
        $positional += [string]$token.Content
      }
    }
    try { & $commandPath @named @positional 1> $StdoutPath 2> $StderrPath 3>&1 4>&1 5>&1 6>&1 }
    catch { $exitCode = 1; $thrownMessage = $_.Exception.Message }
  }
  if ($exitCode -eq 0 -and $LASTEXITCODE -ne 0) { $exitCode = [int]$LASTEXITCODE }
  if ($thrownMessage) {
    [IO.File]::AppendAllText($StderrPath, $thrownMessage + "`n", [Text.UTF8Encoding]::new($false))
  }
  if (Test-Path -LiteralPath $StdoutPath -PathType Leaf) {
    Get-Content -LiteralPath $StdoutPath | ForEach-Object { Write-Host $_ }
  }
  if (Test-Path -LiteralPath $StderrPath -PathType Leaf) {
    Get-Content -LiteralPath $StderrPath | ForEach-Object { Write-Warning $_ }
  }
  return [ordered]@{
    resolved_command=$resolved
    exit_code=$exitCode
    thrown_message=$thrownMessage
  }
}

function Test-MIRAssuranceCanReuseTest {
  param([Parameter(Mandatory)][string]$TestId, [Parameter(Mandatory)]$Context)
  if (-not [bool]$Context.reuse_enabled) { return $false }
  if (@($Context.rerun_tests | Where-Object { $_ -eq $TestId }).Count -gt 0) { return $false }
  return $true
}
