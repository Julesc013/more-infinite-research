param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$OutputRoot = "",
  [switch]$CheckThresholds,
  [int]$MaxMirLegacyActiveModules = 3,
  [int]$MaxRequiresMirLegacy = 3,
  [int]$MaxCompatActiveModules = 0,
  [int]$MaxRequiresCompat = 0,
  [int]$MaxLibActiveModules = 0,
  [int]$MaxRequiresLib = 0,
  [int]$MaxRequiresConfig = 0,
  [int]$MaxRequiresUtil = 0,
  [int]$MaxRequiresDiagnostics = 0,
  [int]$MaxDataRawOutsidePlatform = 32,
  [int]$MaxGeneratedStreamsWithoutManifest = 0
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $repo "artifacts\legacy-inventory"
}
$output = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
  $OutputRoot
} else {
  Join-Path $repo $OutputRoot
}

function Get-MIRRelativePath {
  param([Parameter(Mandatory)][string]$Path)
  return [System.IO.Path]::GetRelativePath($repo, $Path).Replace("\", "/")
}

function Get-MIRCodeLines {
  param([Parameter(Mandatory)][string]$Text)
  return @(
    $Text -split "\r?\n" |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("--") }
  )
}

function Test-MIRShimOnlyLua {
  param([Parameter(Mandatory)][string]$Text)
  $lines = @(Get-MIRCodeLines -Text $Text)
  return $lines.Count -eq 1 -and $lines[0] -match '^return\s+require\("prototypes\.'
}

function Get-MIRLuaFiles {
  $roots = @(
    "control",
    "prototypes"
  )

  $files = @()
  foreach ($root in $roots) {
    $path = Join-Path $repo $root
    if (Test-Path -LiteralPath $path) {
      $files += @(Get-ChildItem -LiteralPath $path -Recurse -File -Filter "*.lua")
    }
  }

  foreach ($rootFile in @("settings.lua", "data.lua", "data-updates.lua", "data-final-fixes.lua", "control.lua")) {
    $path = Join-Path $repo $rootFile
    if (Test-Path -LiteralPath $path) {
      $files += @(Get-Item -LiteralPath $path)
    }
  }

  return @($files | Sort-Object FullName -Unique)
}

function Get-MIRMatches {
  param(
    [Parameter(Mandatory)]$Files,
    [Parameter(Mandatory)][string]$Pattern
  )

  $matches = @()
  foreach ($file in $Files) {
    $relative = Get-MIRRelativePath -Path $file.FullName
    foreach ($match in @(Select-String -LiteralPath $file.FullName -Pattern $Pattern)) {
      $matches += [pscustomobject]@{
        path = $relative
        line = $match.LineNumber
        text = $match.Line.Trim()
      }
    }
  }
  return $matches
}

function Get-MIRMatchesOutsideRoots {
  param(
    [Parameter(Mandatory)]$Matches,
    [Parameter(Mandatory)][string[]]$AllowedRoots
  )

  return @(
    $Matches | Where-Object {
      $path = [string]$_.path
      $allowed = $false
      foreach ($root in $AllowedRoots) {
        if ($path.StartsWith($root)) {
          $allowed = $true
          break
        }
      }
      -not $allowed
    }
  )
}

function Assert-MIRLegacyThreshold {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][int]$Actual,
    [Parameter(Mandatory)][int]$Maximum
  )

  if ($Actual -gt $Maximum) {
    throw "MIR legacy inventory threshold failed: $Name=$Actual exceeds max $Maximum"
  }
}

function Get-MIRModuleInventory {
  param(
    [Parameter(Mandatory)][string]$RelativeRoot,
    [Parameter(Mandatory)][string]$Label
  )

  $root = Join-Path $repo $RelativeRoot
  $rows = @()
  if (Test-Path -LiteralPath $root) {
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.lua" | Sort-Object FullName)) {
      $text = Get-Content -Raw -LiteralPath $file.FullName
      $rows += [pscustomobject]@{
        path = Get-MIRRelativePath -Path $file.FullName
        area = $Label
        shim_only = [bool](Test-MIRShimOnlyLua -Text $text)
        code_lines = @(Get-MIRCodeLines -Text $text).Count
      }
    }
  }
  return $rows
}

function Get-MIRStreamKeysFromSource {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  return @(
    Select-String -LiteralPath $Path -Pattern "^\s*(research_[A-Za-z0-9_]+)\s*=\s*\{" |
      ForEach-Object { $_.Matches[0].Groups[1].Value }
  )
}

New-Item -ItemType Directory -Force -Path $output | Out-Null

$luaFiles = @(Get-MIRLuaFiles)
$legacyModules = @(Get-MIRModuleInventory -RelativeRoot "prototypes\mir\legacy" -Label "mir-legacy")
$compatModules = @(Get-MIRModuleInventory -RelativeRoot "prototypes\compat" -Label "compat-shim")
$libModules = @(Get-MIRModuleInventory -RelativeRoot "prototypes\lib" -Label "lib")

$legacyRequires = @(Get-MIRMatches -Files $luaFiles -Pattern 'require\("prototypes\.mir\.legacy')
$compatRequires = @(Get-MIRMatches -Files $luaFiles -Pattern 'require\("prototypes\.compat')
$libRequires = @(Get-MIRMatches -Files $luaFiles -Pattern 'require\("prototypes\.lib')
$configRequires = @(Get-MIRMatches -Files $luaFiles -Pattern 'require\("prototypes\.config"\)')
$utilRequires = @(Get-MIRMatches -Files $luaFiles -Pattern 'require\("prototypes\.util"\)')
$diagnosticsRequires = @(Get-MIRMatches -Files $luaFiles -Pattern 'require\("prototypes\.diagnostics"\)')
$dataExtendMatches = @(Get-MIRMatches -Files $luaFiles -Pattern 'data:extend')
$dataRawMatches = @(Get-MIRMatches -Files $luaFiles -Pattern 'data\.raw')
$dataRawOutsidePlatform = @(Get-MIRMatchesOutsideRoots -Matches $dataRawMatches -AllowedRoots @(
  "prototypes/mir/platform/factorio/"
))

$sourceStreamKeys = @(
  Get-MIRStreamKeysFromSource -Path (Join-Path $repo "prototypes\streams\productivity.lua")
  Get-MIRStreamKeysFromSource -Path (Join-Path $repo "prototypes\streams\direct-effects.lua")
)
$manifestPath = Join-Path $repo "prototypes\planner\generated-stream-manifest.json"
$manifestRows = @()
if (Test-Path -LiteralPath $manifestPath) {
  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  $manifestRows = @($manifest.streams.PSObject.Properties)
}
$manifestStreamKeys = @{}
foreach ($row in $manifestRows) {
  $streamKey = [string]$row.Value.stream_key
  if (-not [string]::IsNullOrWhiteSpace($streamKey)) {
    $manifestStreamKeys[$streamKey] = $true
  }
}
$missingManifestKeys = @($sourceStreamKeys | Where-Object { -not $manifestStreamKeys[[string]$_] } | Sort-Object -Unique)

$shipped = [pscustomobject]@{
  schema = 1
  generated_at = (Get-Date).ToString("o")
  counts = [pscustomobject]@{
    lua_files = $luaFiles.Count
    mir_legacy_modules = $legacyModules.Count
    mir_legacy_active_modules = @($legacyModules | Where-Object { -not $_.shim_only }).Count
    compat_modules = $compatModules.Count
    compat_active_modules = @($compatModules | Where-Object { -not $_.shim_only }).Count
    lib_modules = $libModules.Count
    lib_active_modules = @($libModules | Where-Object { -not $_.shim_only }).Count
    requires_mir_legacy = $legacyRequires.Count
    requires_compat = $compatRequires.Count
    requires_lib = $libRequires.Count
    requires_config = $configRequires.Count
    requires_util = $utilRequires.Count
    requires_diagnostics = $diagnosticsRequires.Count
    data_extend_matches = $dataExtendMatches.Count
    data_raw_matches = $dataRawMatches.Count
    data_raw_matches_outside_platform = $dataRawOutsidePlatform.Count
    source_stream_keys = $sourceStreamKeys.Count
    generated_streams_without_manifest = $missingManifestKeys.Count
  }
  modules = [pscustomobject]@{
    mir_legacy = $legacyModules
    compat = $compatModules
    lib = $libModules
  }
  imports = [pscustomobject]@{
    mir_legacy = $legacyRequires
    compat = $compatRequires
    lib = $libRequires
    config = $configRequires
    util = $utilRequires
    diagnostics = $diagnosticsRequires
  }
  prototype_access = [pscustomobject]@{
    data_extend = $dataExtendMatches
    data_raw = $dataRawMatches
    data_raw_outside_platform = $dataRawOutsidePlatform
  }
  thresholds = [pscustomobject]@{
    max_mir_legacy_active_modules = $MaxMirLegacyActiveModules
    max_requires_mir_legacy = $MaxRequiresMirLegacy
    max_compat_active_modules = $MaxCompatActiveModules
    max_requires_compat = $MaxRequiresCompat
    max_lib_active_modules = $MaxLibActiveModules
    max_requires_lib = $MaxRequiresLib
    max_requires_config = $MaxRequiresConfig
    max_requires_util = $MaxRequiresUtil
    max_requires_diagnostics = $MaxRequiresDiagnostics
    max_data_raw_matches_outside_platform = $MaxDataRawOutsidePlatform
    max_generated_streams_without_manifest = $MaxGeneratedStreamsWithoutManifest
  }
  generated_streams_without_manifest = $missingManifestKeys
}

if ($CheckThresholds) {
  Assert-MIRLegacyThreshold -Name "mir_legacy_active_modules" -Actual ([int]$shipped.counts.mir_legacy_active_modules) -Maximum $MaxMirLegacyActiveModules
  Assert-MIRLegacyThreshold -Name "requires_mir_legacy" -Actual ([int]$shipped.counts.requires_mir_legacy) -Maximum $MaxRequiresMirLegacy
  Assert-MIRLegacyThreshold -Name "compat_active_modules" -Actual ([int]$shipped.counts.compat_active_modules) -Maximum $MaxCompatActiveModules
  Assert-MIRLegacyThreshold -Name "requires_compat" -Actual ([int]$shipped.counts.requires_compat) -Maximum $MaxRequiresCompat
  Assert-MIRLegacyThreshold -Name "lib_active_modules" -Actual ([int]$shipped.counts.lib_active_modules) -Maximum $MaxLibActiveModules
  Assert-MIRLegacyThreshold -Name "requires_lib" -Actual ([int]$shipped.counts.requires_lib) -Maximum $MaxRequiresLib
  Assert-MIRLegacyThreshold -Name "requires_config" -Actual ([int]$shipped.counts.requires_config) -Maximum $MaxRequiresConfig
  Assert-MIRLegacyThreshold -Name "requires_util" -Actual ([int]$shipped.counts.requires_util) -Maximum $MaxRequiresUtil
  Assert-MIRLegacyThreshold -Name "requires_diagnostics" -Actual ([int]$shipped.counts.requires_diagnostics) -Maximum $MaxRequiresDiagnostics
  Assert-MIRLegacyThreshold -Name "data_raw_matches_outside_platform" -Actual ([int]$shipped.counts.data_raw_matches_outside_platform) -Maximum $MaxDataRawOutsidePlatform
  Assert-MIRLegacyThreshold -Name "generated_streams_without_manifest" -Actual ([int]$shipped.counts.generated_streams_without_manifest) -Maximum $MaxGeneratedStreamsWithoutManifest
}

$repoLegacy = [pscustomobject]@{
  schema = 1
  generated_at = (Get-Date).ToString("o")
  root_policy = [pscustomobject]@{
    todo_md_present = [bool](Test-Path -LiteralPath (Join-Path $repo "todo.md"))
    dist_dir_present = [bool](Test-Path -LiteralPath (Join-Path $repo "dist"))
    artifacts_dir_present = [bool](Test-Path -LiteralPath (Join-Path $repo "artifacts"))
  }
  scripts = [pscustomobject]@{
    count = @(Get-ChildItem -LiteralPath (Join-Path $repo "scripts") -Recurse -File -Filter "*.ps1").Count
    mir_cli_present = [bool](Test-Path -LiteralPath (Join-Path $repo "scripts\mir.ps1"))
    legacy_inventory_command = ".\scripts\mir.ps1 legacy inventory"
  }
}

$summaryPath = Join-Path $output "legacy-summary.md"
$shippedPath = Join-Path $output "shipped-mod-legacy.json"
$repoPath = Join-Path $output "repo-legacy.json"

$shipped | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $shippedPath -Encoding UTF8
$repoLegacy | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $repoPath -Encoding UTF8

$summary = @()
$summary += "# MIR Legacy Inventory"
$summary += ""
$summary += "Generated: $($shipped.generated_at)"
$summary += ""
$summary += "## Shipped Mod"
$summary += ""
$summary += "| Metric | Count |"
$summary += "| --- | ---: |"
foreach ($property in $shipped.counts.PSObject.Properties) {
  $summary += "| $($property.Name) | $($property.Value) |"
}
$summary += ""
$summary += "## Repo"
$summary += ""
$summary += "| Metric | Value |"
$summary += "| --- | --- |"
$summary += "| todo_md_present | $($repoLegacy.root_policy.todo_md_present) |"
$summary += "| dist_dir_present | $($repoLegacy.root_policy.dist_dir_present) |"
$summary += "| scripts_count | $($repoLegacy.scripts.count) |"
$summary += "| legacy_inventory_command | $($repoLegacy.scripts.legacy_inventory_command) |"
$summary += ""
$summary += "## Outputs"
$summary += ""
$summary += "- shipped-mod-legacy.json"
$summary += "- repo-legacy.json"
if ($CheckThresholds) {
  $summary += ""
  $summary += "## Thresholds"
  $summary += ""
  $summary += "Passed."
}

$summary | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "[ok] wrote MIR legacy inventory to $output"
Write-Host "  - $shippedPath"
Write-Host "  - $repoPath"
Write-Host "  - $summaryPath"
if ($CheckThresholds) {
  Write-Host "[ok] MIR legacy inventory thresholds passed."
}
