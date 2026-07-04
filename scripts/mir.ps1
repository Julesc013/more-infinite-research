param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

$scriptRoot = $PSScriptRoot
$repo = Resolve-Path (Join-Path $scriptRoot "..")
. (Join-Path $scriptRoot "MIRCli\Console.ps1")
. (Join-Path $scriptRoot "MIRCli\PathResolver.ps1")
. (Join-Path $scriptRoot "MIRCli\LocalModIndex.ps1")
. (Join-Path $scriptRoot "MIRCli\Reports.ps1")

function Show-MIRHelp {
  Write-Host @"
MIR developer CLI

Usage:
  .\scripts\mir.ps1 release gate [--no-git-pull]
  .\scripts\mir.ps1 overnight local
  .\scripts\mir.ps1 audit local
  .\scripts\mir.ps1 audit top25 --space-age
  .\scripts\mir.ps1 package build
  .\scripts\mir.ps1 report latest
  .\scripts\mir.ps1 report missing-deps --run <path>
  .\scripts\mir.ps1 profile stub <group-id> --grouped-failures <path>
  .\scripts\mir.ps1 run -Profile <profile-name-or-path>
  .\scripts\mir.ps1 local-index build --mods <path>
"@
}

function Get-MIRArgValue {
  param(
    [string[]]$Items,
    [string]$Name,
    [string]$Default = ""
  )
  for ($i = 0; $i -lt $Items.Count; $i++) {
    if ($Items[$i] -eq $Name -and $i + 1 -lt $Items.Count) { return $Items[$i + 1] }
  }
  return $Default
}

function Test-MIRArgSwitch {
  param([string[]]$Items, [string]$Name)
  return $Items -contains $Name
}

function Get-MIRLatestRunRoot {
  $artifactRoot = Join-Path $repo "artifacts"
  if (-not (Test-Path -LiteralPath $artifactRoot)) { throw "No artifacts directory exists." }
  $run = Get-ChildItem -LiteralPath $artifactRoot -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $run) { throw "No artifact run directories found." }
  return $run.FullName
}

function Resolve-MIRProfilePath {
  param([string]$Profile)
  if ([string]::IsNullOrWhiteSpace($Profile)) { throw "Profile is required." }
  if (Test-Path -LiteralPath $Profile) { return (Resolve-Path -LiteralPath $Profile).Path }

  $candidate = Join-Path $repo ("fixtures\run-profiles\{0}.json" -f $Profile)
  if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }

  throw "Run profile not found: $Profile"
}

function Get-MIRProfileProperty {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function Test-MIRProfileFlag {
  param($Object, [string]$Name)
  $value = Get-MIRProfileProperty -Object $Object -Name $Name -Default $false
  return [bool]$value
}

function Invoke-MIRRunProfile {
  param([string]$Profile)

  $profilePath = Resolve-MIRProfilePath -Profile $Profile
  $profileData = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
  $kind = [string](Get-MIRProfileProperty -Object $profileData -Name "kind" -Default "")
  if ([string]::IsNullOrWhiteSpace($kind)) { $kind = "extended" }

  switch ($kind) {
    "release-targeted" {
      $params = @{}
      $factorioBin = Get-MIRProfileProperty -Object $profileData -Name "factorio_bin"
      $localModDir = Get-MIRProfileProperty -Object $profileData -Name "local_mod_dir"
      $timeout = Get-MIRProfileProperty -Object $profileData -Name "scenario_timeout_seconds"
      if ($factorioBin) { $params.FactorioBin = Resolve-MIRFactorioBin -Path ([string]$factorioBin) }
      if ($localModDir) { $params.LocalModDir = [string]$localModDir }
      if ($timeout) { $params.ScenarioTimeoutSeconds = [int]$timeout }
      & (Join-Path $scriptRoot "Invoke-MIRReleaseTargetedGate.ps1") @params
    }
    "overnight-local" {
      $params = @{}
      $factorioBin = Get-MIRProfileProperty -Object $profileData -Name "factorio_bin"
      $localModDir = Get-MIRProfileProperty -Object $profileData -Name "local_mod_dir"
      $timeout = Get-MIRProfileProperty -Object $profileData -Name "scenario_timeout_seconds"
      $pairwiseLimit = Get-MIRProfileProperty -Object $profileData -Name "generated_local_pairwise_limit"
      if ($factorioBin) { $params.FactorioBin = Resolve-MIRFactorioBin -Path ([string]$factorioBin) }
      if ($localModDir) { $params.LocalModDir = [string]$localModDir }
      if ($timeout) { $params.ScenarioTimeoutSeconds = [int]$timeout }
      if ($pairwiseLimit) { $params.GeneratedLocalPairwiseLimit = [int]$pairwiseLimit }
      & (Join-Path $scriptRoot "Start-MIROvernightLocalSweep.ps1") @params
    }
    default {
      $tiers = Get-MIRProfileProperty -Object $profileData -Name "tiers" -Default @("Static")
      $params = @{
        Tier = @($tiers | ForEach-Object { [string]$_ })
      }
      $factorioBin = Get-MIRProfileProperty -Object $profileData -Name "factorio_bin"
      $outputRoot = Get-MIRProfileProperty -Object $profileData -Name "output_root"
      $localModZipDirs = Get-MIRProfileProperty -Object $profileData -Name "local_mod_zip_dirs"
      $localModLibraryDirs = Get-MIRProfileProperty -Object $profileData -Name "local_mod_library_dirs"
      $scenarioNames = Get-MIRProfileProperty -Object $profileData -Name "scenario_names"
      $localModNames = Get-MIRProfileProperty -Object $profileData -Name "local_mod_names"
      $timeout = Get-MIRProfileProperty -Object $profileData -Name "scenario_timeout_seconds"
      $pairwiseLimit = Get-MIRProfileProperty -Object $profileData -Name "generated_local_pairwise_limit"
      if ($factorioBin) { $params.FactorioBin = Resolve-MIRFactorioBin -Path ([string]$factorioBin) }
      if ($outputRoot) { $params.OutputRoot = [string]$outputRoot }
      if ($localModZipDirs) { $params.LocalModZipDirs = @($localModZipDirs | ForEach-Object { [string]$_ }) }
      if ($localModLibraryDirs) { $params.LocalModLibraryDirs = @($localModLibraryDirs | ForEach-Object { [string]$_ }) }
      if ($scenarioNames) { $params.ScenarioNames = @($scenarioNames | ForEach-Object { [string]$_ }) }
      if ($localModNames) { $params.LocalModNames = @($localModNames | ForEach-Object { [string]$_ }) }
      if ($timeout) { $params.ScenarioTimeoutSeconds = [int]$timeout }
      if (Test-MIRProfileFlag -Object $profileData -Name "collect_all") { $params.CollectAll = $true }
      if (Test-MIRProfileFlag -Object $profileData -Name "offline") { $params.Offline = $true }
      if (Test-MIRProfileFlag -Object $profileData -Name "fail_fast") { $params.FailFast = $true }
      if (Test-MIRProfileFlag -Object $profileData -Name "fail_on_audit_failures") { $params.FailOnAuditFailures = $true }
      if (Test-MIRProfileFlag -Object $profileData -Name "include_generated_local_pairwise") { $params.IncludeGeneratedLocalPairwise = $true }
      if ($pairwiseLimit) { $params.GeneratedLocalPairwiseLimit = [int]$pairwiseLimit }
      & (Join-Path $scriptRoot "Invoke-MIRExtendedTests.ps1") @params
    }
  }
}

if ($Args.Count -eq 0 -or $Args[0] -in @("-h", "--help", "help")) {
  Show-MIRHelp
  exit 0
}

$area = $Args[0]
$verb = if ($Args.Count -gt 1) { $Args[1] } else { "" }

switch ($area) {
  "release" {
    if ($verb -ne "gate") { throw "Unknown release command: $verb" }
    $params = @{}
    if (Test-MIRArgSwitch -Items $Args -Name "--no-git-pull") { $params.NoGitPull = $true }
    & (Join-Path $scriptRoot "Invoke-MIRReleaseTargetedGate.ps1") @params
  }
  "overnight" {
    if ($verb -ne "local") { throw "Unknown overnight command: $verb" }
    & (Join-Path $scriptRoot "Start-MIROvernightLocalSweep.ps1")
  }
  "audit" {
    switch ($verb) {
      "local" {
        & (Join-Path $scriptRoot "Invoke-MIRExtendedTests.ps1") `
          -Tier LocalLibraryScenarios,GeneratedLocalScenarios,LocalModZips `
          -LocalModZipDirs "C:\Projects\Factorio\testmods_readonly_2.1" `
          -LocalModLibraryDirs "C:\Projects\Factorio\testmods_readonly_2.1" `
          -Offline `
          -CollectAll `
          -IncludeGeneratedLocalPairwise
      }
      "top25" {
        $includeSpaceAge = Test-MIRArgSwitch -Items $Args -Name "--space-age"
        $tier = if ($includeSpaceAge) { "Top25SpaceAge" } else { "Top25Base" }
        & (Join-Path $scriptRoot "Invoke-MIRExtendedTests.ps1") -Tier $tier -CollectAll
      }
      default { throw "Unknown audit command: $verb" }
    }
  }
  "package" {
    if ($verb -ne "build") { throw "Unknown package command: $verb" }
    & (Join-Path $scriptRoot "Build-MIRPackage.ps1")
  }
  "report" {
    switch ($verb) {
      "latest" {
        & (Join-Path $scriptRoot "Show-MIROvernightSummary.ps1") -OutputRoot (Get-MIRLatestRunRoot)
      }
      "missing-deps" {
        $run = Get-MIRArgValue -Items $Args -Name "--run" -Default (Get-MIRLatestRunRoot)
        Get-ChildItem -LiteralPath $run -Recurse -Filter missing-dependencies.csv -File |
          ForEach-Object { Import-Csv -LiteralPath $_.FullName } |
          Group-Object mod |
          Sort-Object Count -Descending |
          Select-Object @{Name='mod';Expression={$_.Name}},Count |
          Format-Table -AutoSize
      }
      default { throw "Unknown report command: $verb" }
    }
  }
  "profile" {
    if ($verb -ne "stub") { throw "Unknown profile command: $verb" }
    if ($Args.Count -lt 3) { throw "profile stub requires a group id." }
    $groupId = $Args[2]
    $groupedFailures = Get-MIRArgValue -Items $Args -Name "--grouped-failures"
    if ([string]::IsNullOrWhiteSpace($groupedFailures)) { throw "--grouped-failures is required." }
    & (Join-Path $scriptRoot "New-MIRCompatProfileStub.ps1") -GroupedFailures $groupedFailures -GroupId $groupId
  }
  "run" {
    $profile = Get-MIRArgValue -Items $Args -Name "-Profile"
    if ([string]::IsNullOrWhiteSpace($profile)) { $profile = Get-MIRArgValue -Items $Args -Name "--profile" }
    Invoke-MIRRunProfile -Profile $profile
  }
  "local-index" {
    if ($verb -ne "build") { throw "Unknown local-index command: $verb" }
    $mods = Get-MIRArgValue -Items $Args -Name "--mods" -Default "C:\Projects\Factorio\testmods_readonly_2.1"
    $out = Get-MIRArgValue -Items $Args -Name "--out" -Default (Join-Path $repo "build\cache\local-mod-index\local-mod-index.2.1.json")
    New-MIRLocalModIndex -Dirs @($mods) -OutputPath $out | Out-Null
    Write-MIRSuccess "wrote $out"
  }
  default {
    throw "Unknown command area: $area"
  }
}
