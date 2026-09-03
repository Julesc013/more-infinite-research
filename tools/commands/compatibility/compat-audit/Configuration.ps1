$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $compatAuditCommandRoot "../../..")
$moduleRoot = Join-Path $repo "tools\lib\compatibility"
. (Join-Path $moduleRoot "ModPortal.ps1")
. (Join-Path $moduleRoot "DependencyResolver.ps1")
. (Join-Path $moduleRoot "DiagnosticsParser.ps1")
. (Join-Path $moduleRoot "FactorioRunner.ps1")
. (Join-Path $repo "tools\lib\validation\FactorioProcess.ps1")
. (Join-Path $repo "tools\lib\validation\SettingsOverrides.ps1")

$resolvedSanitationBudgetPath = (Resolve-Path -LiteralPath $SanitationBudgetPath).Path
$sanitationPolicy = Get-Content -Raw -LiteralPath $resolvedSanitationBudgetPath | ConvertFrom-Json
if ([int]$sanitationPolicy.schema -ne 1 -or [string]$sanitationPolicy.policy -ne "mir-ecosystem-sanitation-budget-v1") {
  throw "Compatibility audit requires mir-ecosystem-sanitation-budget-v1 schema 1."
}

$resolvedModUnderTestZip = ""
if (-not [string]::IsNullOrWhiteSpace($ModUnderTestZip)) {
  $resolvedModUnderTestZip = (Resolve-Path -LiteralPath $ModUnderTestZip).Path
}
if (-not [string]::IsNullOrWhiteSpace($ModUnderTestSourceCommit) -and $ModUnderTestSourceCommit -notmatch '^[0-9a-fA-F]{40}$') {
  throw "ModUnderTestSourceCommit must be a full 40-character git commit."
}

if ([string]::IsNullOrWhiteSpace($FactorioLine)) {
  $lineCandidates = @($FactorioVersions | Where-Object { $_ -in @("2.0", "2.1") } | Select-Object -Unique)
  if ($lineCandidates.Count -eq 1) {
    $FactorioLine = [string]$lineCandidates[0]
  } else {
    $FactorioLine = "2.1"
  }
}

function New-MIRDirectory {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function New-MIRCompatRuntimeCampaignRoot {
  param([string]$RequestedRoot = "")

  $baseCandidate = if ([string]::IsNullOrWhiteSpace($RequestedRoot)) {
    Join-Path $repo.Path "build\compat-runtime"
  } else {
    $RequestedRoot
  }
  $baseRoot = New-MIRDirectory -Path ([IO.Path]::GetFullPath($baseCandidate))
  $campaignRoot = New-MIRDirectory -Path (Join-Path $baseRoot ("r-" + [guid]::NewGuid().ToString("N").Substring(0, 12)))

  # Factorio 2.1 still loses Lua modules when a Windows runtime path crosses the
  # legacy MAX_PATH boundary. Keep headroom for MIR's longest current module and
  # for diagnostics or fixture suffixes added by a compatibility scenario.
  $maximumRuntimePathLength = 240
  $pathBudgetProbe = Join-Path $campaignRoot "u-000000000000\mods\more-infinite-research\prototypes\mir\capabilities\science_integration\pack_production_reachability.lua"
  if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $pathBudgetProbe.Length -gt $maximumRuntimePathLength) {
    Remove-Item -LiteralPath $campaignRoot -Force
    throw "Compatibility runtime root exceeds the $maximumRuntimePathLength-character Windows path budget. Set MIR_COMPAT_RUNTIME_ROOT or -RuntimeRoot to a shorter directory. Probe: $pathBudgetProbe"
  }

  return [pscustomobject]@{
    base = $baseRoot
    path = $campaignRoot
    maximum_path_length = $maximumRuntimePathLength
    probe_path_length = $pathBudgetProbe.Length
  }
}

function Move-MIRCompatScenarioEvidence {
  param(
    [Parameter(Mandatory)][string]$UserDataDir,
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [Parameter(Mandatory)]$Result
  )

  $resolvedUserData = (Resolve-Path -LiteralPath $UserDataDir).Path
  $resolvedEvidenceRoot = New-MIRDirectory -Path $EvidenceRoot
  $retainedUserData = Join-Path $resolvedEvidenceRoot (Split-Path -Leaf $resolvedUserData)
  if (Test-Path -LiteralPath $retainedUserData) {
    throw "Compatibility evidence destination already exists: $retainedUserData"
  }

  Move-Item -LiteralPath $resolvedUserData -Destination $retainedUserData
  $sourcePrefix = $resolvedUserData.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  foreach ($propertyName in @("save", "stdout", "stderr")) {
    $sourcePath = [string]$Result.$propertyName
    if ([string]::IsNullOrWhiteSpace($sourcePath)) { continue }
    if (-not $sourcePath.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Compatibility result path '$sourcePath' is outside its runtime user-data root '$resolvedUserData'."
    }
    $relativePath = $sourcePath.Substring($sourcePrefix.Length)
    $Result.$propertyName = Join-Path $retainedUserData $relativePath
  }

  return $Result
}

function Remove-MIRCompatRuntimeCampaignRootIfEmpty {
  param([Parameter(Mandatory)]$Campaign)

  if (-not (Test-Path -LiteralPath $Campaign.path -PathType Container)) { return }
  $resolvedCampaign = (Resolve-Path -LiteralPath $Campaign.path).Path
  $resolvedBase = (Resolve-Path -LiteralPath $Campaign.base).Path
  $expectedPrefix = $resolvedBase.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $resolvedCampaign.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
      (Split-Path -Leaf $resolvedCampaign) -notmatch '^r-[0-9a-f]{12}$') {
    throw "Refusing to clean an unrecognized compatibility runtime campaign root: $resolvedCampaign"
  }
  if (@(Get-ChildItem -LiteralPath $resolvedCampaign -Force).Count -eq 0) {
    Remove-Item -LiteralPath $resolvedCampaign -Force
  } else {
    Write-Warning "Compatibility runtime evidence could not be transferred completely; preserving $resolvedCampaign"
  }
}

function Read-MIRJsonFile {
  param([string]$Path, $Fallback)
  if (-not (Test-Path -LiteralPath $Path)) { return $Fallback }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-MIRObjectProperty {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function Test-MIRCompatAuditRowMatch {
  param(
    [Parameter(Mandatory)]$Row,
    [Parameter(Mandatory)]$Expected
  )

  foreach ($property in @($Expected.PSObject.Properties)) {
    $actual = $Row.PSObject.Properties[[string]$property.Name]
    if ($null -eq $actual -or [string]$actual.Value -cne [string]$property.Value) {
      return $false
    }
  }
  return $true
}

function Select-MIRWindow {
  param([object[]]$Items)

  $out = @($Items)
  if ($StartIndex -gt 0) {
    $out = @($out | Select-Object -Skip $StartIndex)
  }
  if ($Count -gt 0) {
    $out = @($out | Select-Object -First $Count)
  }
  return $out
}

function Test-MIRInterestingCategory {
  param($Mod)

  $category = [string]$Mod.category
  if ($category -in @("content", "overhaul", "mod-packs", "tweaks")) { return $true }

  foreach ($tag in @($Mod.tags)) {
    if ([string]$tag -in @("manufacturing", "mining", "fluids", "planets", "transportation", "power", "logistics")) {
      return $true
    }
  }

  return $false
}

function Test-MIRKnownExcluded {
  param($Mod, $Exclusions)

  $name = [string]$Mod.name
  $category = [string]$Mod.category
  foreach ($excludedName in @($Exclusions.mod_names)) {
    if ($name -eq [string]$excludedName) { return $true }
  }
  foreach ($excludedCategory in @($Exclusions.categories)) {
    if ($category -eq [string]$excludedCategory) { return $true }
  }
  return $false
}

function ConvertTo-MIRLockEntry {
  param(
    [Parameter(Mandatory)]$FullMod,
    [Parameter(Mandatory)]$Release,
    [Parameter(Mandatory)]$Dependencies
  )

  [pscustomobject][ordered]@{
    name = [string]$FullMod.name
    title = [string]$FullMod.title
    version = [string]$Release.version
    factorio_version = [string]$Release.info_json.factorio_version
    downloads_count = [int]$FullMod.downloads_count
    category = [string]$FullMod.category
    owner = [string]$FullMod.owner
    file_name = [string]$Release.file_name
    sha1 = [string]$Release.sha1
    sha256 = [string](Get-MIRObjectProperty -Object $Release -Name "sha256" -Default "")
    download_url = [string]$Release.download_url
    source = ""
    source_path = ""
    dependencies = @($Dependencies | ForEach-Object {
      [ordered]@{
        name = $_.name
        kind = $_.kind
        required = $_.required
        raw = $_.raw
      }
    })
  }
}

function ConvertTo-MIRLocalFullMod {
  param([Parameter(Mandatory)][string]$ZipPath)

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $resolvedZip = (Resolve-Path -LiteralPath $ZipPath).Path
  $zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedZip)
  try {
    $entry = $zip.Entries | Where-Object { $_.FullName -match "^[^/]+/info\.json$" } | Select-Object -First 1
    if (-not $entry) {
      throw "Local mod zip does not contain a top-level info.json: $resolvedZip"
    }

    $reader = [System.IO.StreamReader]::new($entry.Open())
    try {
      $infoJson = $reader.ReadToEnd()
      try {
        $info = $infoJson | ConvertFrom-Json -ErrorAction Stop
      } catch {
        $infoTable = $infoJson | ConvertFrom-Json -AsHashTable -ErrorAction Stop
        $info = [pscustomobject]@{
          name = [string]$infoTable["name"]
          title = [string]$infoTable["title"]
          version = [string]$infoTable["version"]
          factorio_version = [string]$infoTable["factorio_version"]
          dependencies = @($infoTable["dependencies"])
        }
      }
    } finally {
      $reader.Dispose()
    }
  } finally {
    $zip.Dispose()
  }

  $dependencies = @($info.dependencies | ForEach-Object {
    if (-not [string]::IsNullOrWhiteSpace([string]$_)) { [string]$_ }
  })
  $file = Get-Item -LiteralPath $resolvedZip
  $sha1 = (Get-FileHash -Algorithm SHA1 -LiteralPath $resolvedZip).Hash.ToLowerInvariant()
  $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedZip).Hash.ToLowerInvariant()

  [pscustomobject]@{
    name = [string]$info.name
    title = if ([string]::IsNullOrWhiteSpace([string]$info.title)) { [string]$info.name } else { [string]$info.title }
    owner = "local"
    downloads_count = 0
    category = "local"
    releases = @(
      [pscustomobject]@{
        version = [string]$info.version
        file_name = $file.Name
        sha1 = $sha1
        sha256 = $sha256
        download_url = ""
        source_path = $resolvedZip
        source = "local_zip"
        info_json = [pscustomobject]@{
          factorio_version = [string]$info.factorio_version
          dependencies = $dependencies
        }
      }
    )
  }
}

function ConvertTo-MIRLocalLockEntry {
  param(
    [Parameter(Mandatory)]$FullMod,
    [Parameter(Mandatory)]$Release,
    [Parameter(Mandatory)]$Dependencies
  )

  $entry = ConvertTo-MIRLockEntry -FullMod $FullMod -Release $Release -Dependencies $Dependencies
  $entry.source = "local_zip"
  $entry.source_path = [string]$Release.source_path
  return $entry
}

function ConvertTo-MIRScenarioLockEntry {
  param(
    [Parameter(Mandatory)]$FullMod,
    [Parameter(Mandatory)]$Release,
    [Parameter(Mandatory)]$Dependencies
  )

  if ($Release.PSObject.Properties["source_path"] -and -not [string]::IsNullOrWhiteSpace([string]$Release.source_path)) {
    return ConvertTo-MIRLocalLockEntry -FullMod $FullMod -Release $Release -Dependencies $Dependencies
  }

  return ConvertTo-MIRLockEntry -FullMod $FullMod -Release $Release -Dependencies $Dependencies
}

function New-MIRScenario {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Type,
    [string[]]$RequestedMods = @(),
    [string[]]$RootMods = @(),
    [string[]]$ResolvedMods = @(),
    [string[]]$OfficialMods = @(),
    [object[]]$LockEntries = @(),
    [object[]]$Failures = @(),
    [string]$ClaimLevel = "loads",
    [int]$TimeoutSeconds = $ScenarioTimeoutSeconds,
    $Settings = $null,
    $ExpectedPlan = $null,
    [string]$SourceManifest = "",
    [string]$Notes = ""
  )

  [pscustomobject]@{
    name = $Name
    type = $Type
    requested_mods = @($RequestedMods | Sort-Object -Unique)
    root_mods = @($RootMods | Sort-Object -Unique)
    resolved_mods = @($ResolvedMods | Sort-Object -Unique)
    official_mods = @($OfficialMods | Sort-Object -Unique)
    lock_entries = @($LockEntries | Sort-Object name, version -Unique)
    dependency_failures = @($Failures)
    claim_level = $ClaimLevel
    timeout_seconds = $TimeoutSeconds
    settings = if ($null -eq $Settings) { [pscustomobject]@{} } else { $Settings }
    expected_plan = if ($null -eq $ExpectedPlan) { [pscustomobject]@{} } else { $ExpectedPlan }
    source_manifest = $SourceManifest
    notes = $Notes
  }
}

function Get-MIRLockEntriesByName {
  param([object[]]$LockEntries)

  $out = @{}
  foreach ($entry in @($LockEntries)) {
    $out[[string]$entry.name] = $entry
  }
  return $out
}
