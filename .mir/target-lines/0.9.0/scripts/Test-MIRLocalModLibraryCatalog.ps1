param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [Parameter(Mandatory)][string[]]$LocalModLibraryDirs,
  [string]$ScenarioPath = "fixtures\compat-matrix\local-library-scenarios.json",
  [int]$MinimumZipCount = 1,
  [string]$OutputPath = "",
  [switch]$Recurse,
  [switch]$AllowMissingScenarioMods
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Resolve-MIRInputPath {
  param([Parameter(Mandatory)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return (Resolve-Path -LiteralPath $Path).Path
  }
  return (Resolve-Path -LiteralPath (Join-Path $repo $Path)).Path
}

function Read-MIRJsonStringProperty {
  param(
    [Parameter(Mandatory)][string]$Json,
    [Parameter(Mandatory)][string]$Name
  )

  $pattern = '"' + [regex]::Escape($Name) + '"\s*:\s*"((?:\\.|[^"\\])*)"'
  $match = [regex]::Match($Json, $pattern)
  if (-not $match.Success) { return "" }

  $value = $match.Groups[1].Value
  $value = $value.Replace('\"', '"')
  return $value.Replace("\\", "\")
}

function Read-MIRModInfoFromZip {
  param([Parameter(Mandatory)][string]$Path)

  $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entry = @(
      $zip.Entries |
        Where-Object {
          $_.FullName -match '(^|/)info\.json$' -and
          $_.FullName -notmatch '(^|/)__MACOSX/'
        } |
        Sort-Object FullName |
        Select-Object -First 1
    )

    if ($entry.Count -eq 0) {
      throw "zip has no info.json"
    }

    $stream = $entry[0].Open()
    $reader = [System.IO.StreamReader]::new($stream)
    try {
      $json = $reader.ReadToEnd()
    } finally {
      $reader.Dispose()
      $stream.Dispose()
    }

    $name = Read-MIRJsonStringProperty -Json $json -Name "name"
    if ([string]::IsNullOrWhiteSpace($name)) {
      throw "info.json has no mod name"
    }

    return [pscustomobject]@{
      name = $name
      version = Read-MIRJsonStringProperty -Json $json -Name "version"
      factorio_version = Read-MIRJsonStringProperty -Json $json -Name "factorio_version"
      path = $Path
    }
  } finally {
    $zip.Dispose()
  }
}

function Get-MIRScenarioRootMods {
  param([Parameter(Mandatory)][string]$Path)

  $scenarioFile = Resolve-MIRInputPath -Path $Path
  $json = Get-Content -Raw -LiteralPath $scenarioFile | ConvertFrom-Json
  $mods = @{}
  $scenarioCount = 0

  foreach ($scenario in @($json.scenarios)) {
    $scenarioCount++
    foreach ($mod in @($scenario.mods)) {
      if (-not [string]::IsNullOrWhiteSpace([string]$mod)) {
        $mods[[string]$mod] = $true
      }
    }
  }

  return [pscustomobject]@{
    path = $scenarioFile
    scenario_count = $scenarioCount
    mods = @($mods.Keys | Sort-Object)
  }
}

$resolvedDirs = @(
  foreach ($dir in $LocalModLibraryDirs) {
    Resolve-MIRInputPath -Path $dir
  }
)

$zipPaths = @(
  @(
    foreach ($dir in $resolvedDirs) {
      if ($Recurse) {
        Get-ChildItem -LiteralPath $dir -Recurse -File -Filter "*.zip"
      } else {
        Get-ChildItem -LiteralPath $dir -File -Filter "*.zip"
      }
    }
  ) |
    Sort-Object FullName |
    ForEach-Object { $_.FullName }
)

if ($zipPaths.Count -lt $MinimumZipCount) {
  throw "Local mod library catalog expected at least $MinimumZipCount zip(s), found $($zipPaths.Count)."
}

$records = @()
$malformed = @()
foreach ($zipPath in $zipPaths) {
  try {
    $records += Read-MIRModInfoFromZip -Path $zipPath
  } catch {
    $malformed += [pscustomobject]@{
      path = $zipPath
      error = $_.Exception.Message
    }
  }
}

if ($malformed.Count -gt 0) {
  $first = $malformed | Select-Object -First 1
  throw "Local mod library catalog found malformed zip metadata: $($first.path): $($first.error)"
}

$byName = @{}
foreach ($record in $records) {
  if (-not $byName.ContainsKey($record.name)) {
    $byName[$record.name] = @()
  }
  $byName[$record.name] = @($byName[$record.name]) + $record
}

$scenario = Get-MIRScenarioRootMods -Path $ScenarioPath
$missingScenarioMods = @(
  foreach ($mod in $scenario.mods) {
    if (-not $byName.ContainsKey($mod)) { $mod }
  }
) | Sort-Object

$duplicateNames = @(
  $byName.Keys |
    Where-Object { @($byName[$_]).Count -gt 1 } |
    Sort-Object
)

$report = [ordered]@{
  schema = 1
  generated_at = (Get-Date).ToString("o")
  local_mod_library_dirs = @($resolvedDirs)
  scenario_path = $scenario.path
  zip_count = $zipPaths.Count
  catalog_mod_count = $byName.Keys.Count
  duplicate_name_count = $duplicateNames.Count
  scenario_count = $scenario.scenario_count
  scenario_mod_count = $scenario.mods.Count
  missing_scenario_mod_count = $missingScenarioMods.Count
  missing_scenario_mods = @($missingScenarioMods)
  duplicate_names = @($duplicateNames)
  mods = @(
    $records |
      Sort-Object name, version, path |
      ForEach-Object {
        [ordered]@{
          name = $_.name
          version = $_.version
          factorio_version = $_.factorio_version
          path = $_.path
        }
      }
  )
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
  } else {
    Join-Path $repo $OutputPath
  }
  $outputDir = Split-Path -Parent $resolvedOutput
  if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
  }
  $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
}

Write-Host ("[local-catalog] zip_count={0} catalog_mods={1} scenario_mods={2} missing_scenario_mods={3} duplicate_names={4}" -f `
  $report.zip_count,
  $report.catalog_mod_count,
  $report.scenario_mod_count,
  $report.missing_scenario_mod_count,
  $report.duplicate_name_count)

if ($missingScenarioMods.Count -gt 0 -and -not $AllowMissingScenarioMods) {
  throw "Local mod library is missing scenario root mod(s): $($missingScenarioMods -join ', ')"
}
