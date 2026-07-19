function Get-MIRPerformanceHarnessFiles {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authorities = @(
    ".mir/performance-budgets.json",
    ".mir/performance-campaign.json",
    "fixtures/compat-matrix/local-library-scenarios-2.0.json",
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
