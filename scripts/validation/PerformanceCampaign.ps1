function Get-MIRPerformanceHarnessFiles {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authorities = @(
    ".mir/performance-budgets.json",
    ".mir/performance-campaign.json",
    ".mir/sanitation-budgets.json",
    "fixtures/compat-matrix/local-library-scenarios.json",
    "fixtures/performance-regression-probe",
    "scripts/Invoke-MIRCompatAudit.ps1",
    "scripts/Measure-MIRPerformanceRegression.ps1",
    "scripts/MIRCompatAudit",
    "scripts/validation/PackageIdentity.ps1",
    "scripts/validation/PerformanceCampaign.ps1",
    "scripts/validation/ReleaseAttestations.ps1",
    "scripts/validation/SettingsOverrides.ps1"
  )
  $files = @()
  foreach ($relative in $authorities) {
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $files += $relative.Replace("\", "/")
      continue
    }
    if (Test-Path -LiteralPath $path -PathType Container) {
      $files += @(
        Get-ChildItem -LiteralPath $path -Recurse -File |
          ForEach-Object { [IO.Path]::GetRelativePath($repo, $_.FullName).Replace("\", "/") }
      )
      continue
    }
    throw "Performance harness authority is absent: $relative"
  }
  return @($files | Sort-Object -Unique)
}

function Get-MIRPerformanceHarnessFingerprint {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $rows = foreach ($relative in Get-MIRPerformanceHarnessFiles -RepoRoot $repo) {
    $identity = Get-MIRFileContentIdentity -Path (Join-Path $repo $relative) -RelativePath $relative
    "{0}`t{1}`t{2}" -f $relative, $identity.Length, $identity.Sha256
  }
  return Get-MIRStringSha256 -Value ($rows -join "`n")
}

function ConvertTo-MIRPerformanceSettingsMap {
  param($Value)

  $map = [ordered]@{}
  if ($null -eq $Value) { return $map }
  foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
    $map[[string]$property.Name] = $property.Value
  }
  return $map
}

function Get-MIRPerformanceSettingsFingerprint {
  param([Parameter(Mandatory)]$Campaign)

  $rows = @(
    foreach ($lane in @($Campaign.lanes | Sort-Object id)) {
      $settingsJson = (ConvertTo-MIRPerformanceSettingsMap -Value $lane.settings) | ConvertTo-Json -Depth 10 -Compress
      "$($lane.id)`t$settingsJson"
    }
  )
  return Get-MIRStringSha256 -Value ($rows -join "`n")
}

function Get-MIRPerformanceRunDirectoryName {
  param(
    [Parameter(Mandatory)][string]$LaneId,
    [Parameter(Mandatory)][ValidateSet("warmup", "measured", "compat-smoke", "probe-smoke")][string]$Phase,
    [Parameter(Mandatory)][ValidateRange(1, 99)][int]$Index,
    [Parameter(Mandatory)][ValidateSet("baseline", "candidate")][string]$PackageLabel
  )

  if ([string]::IsNullOrWhiteSpace($LaneId)) {
    throw "Performance run directory requires a non-empty lane ID."
  }
  $hasher = [Security.Cryptography.SHA256]::Create()
  try {
    $laneHash = [Convert]::ToHexString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($LaneId))).Substring(0, 16).ToLowerInvariant()
  } finally {
    $hasher.Dispose()
  }
  $phaseToken = @{
    "warmup" = "w"
    "measured" = "m"
    "compat-smoke" = "s"
    "probe-smoke" = "p"
  }[$Phase]
  $packageToken = if ($PackageLabel -eq "baseline") { "b" } else { "c" }
  return "l-$laneHash-$phaseToken$($Index.ToString('D2'))-$packageToken"
}

function Get-MIRPerformanceRunPathBudget {
  param(
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunDirectoryName
  )

  $userDataPath = Join-Path $RunRoot (Join-Path $RunDirectoryName "c\runs\u-000000000000")
  $tempPath = Join-Path $userDataPath "temp\currently-playing\locale\ar\freeplay.cfg"
  return [pscustomobject]@{
    maximum_path_length = 240
    projected_user_data_path = $userDataPath
    projected_user_data_path_length = $userDataPath.Length
    projected_temp_path = $tempPath
    projected_temp_path_length = $tempPath.Length
  }
}

function Assert-MIRPerformanceRunPathBudget {
  param(
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunDirectoryName
  )

  $budget = Get-MIRPerformanceRunPathBudget -RunRoot $RunRoot -RunDirectoryName $RunDirectoryName
  if ($budget.projected_temp_path_length -gt $budget.maximum_path_length) {
    throw "Performance run path exceeds the Factorio temporary-path budget ($($budget.projected_temp_path_length) > $($budget.maximum_path_length)): $($budget.projected_temp_path)"
  }
  return $budget
}

function Get-MIRPerformanceCounterValue {
  param(
    [Parameter(Mandatory)]$Counters,
    [Parameter(Mandatory)][string]$Name
  )

  if ($Counters -is [Collections.IDictionary]) {
    if (-not $Counters.Contains($Name)) {
      return [pscustomobject]@{found=$false; value=[long]0}
    }
    return [pscustomobject]@{found=$true; value=[long]$Counters[$Name]}
  }

  $property = $Counters.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return [pscustomobject]@{found=$false; value=[long]0}
  }
  return [pscustomobject]@{found=$true; value=[long]$property.Value}
}
