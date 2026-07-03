param(
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [string]$LocalModDir = "C:\Projects\Factorio\testmods_readonly_2.1",
  [string]$OutputRoot = "",
  [int]$ScenarioTimeoutSeconds = 900,
  [int]$GeneratedLocalPairwiseLimit = 40,
  [switch]$SkipStrictGate,
  [switch]$SkipLocalSweep,
  [switch]$SkipGeneratedLocalPairwise,
  [switch]$SkipPowerConfig,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location -LiteralPath $repo

function Resolve-MIROvernightPath {
  param([Parameter(Mandatory)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return (Join-Path $repo $Path)
}

function Resolve-MIRFactorioBinary {
  param([string]$Path)

  $candidates = @()
  if (-not [string]::IsNullOrWhiteSpace($Path)) { $candidates += $Path }
  $candidates += @(
    "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe",
    "C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe",
    "C:\Program Files\Factorio\bin\x64\factorio.exe"
  )

  foreach ($candidate in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  throw "Could not find factorio.exe. Pass -FactorioBin or set FACTORIO_BIN."
}

$resolvedFactorioBin = Resolve-MIRFactorioBinary -Path $FactorioBin
if (-not (Test-Path -LiteralPath $LocalModDir)) {
  throw "Local mod directory does not exist: $LocalModDir"
}
$resolvedLocalModDir = (Resolve-Path -LiteralPath $LocalModDir).Path
$localZipCount = @(Get-ChildItem -LiteralPath $resolvedLocalModDir -Filter *.zip -File).Count
if ($localZipCount -eq 0) {
  throw "Local mod directory contains no zip files: $resolvedLocalModDir"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = ".\artifacts\overnight-local-2.1-$stamp"
}
$resolvedOutputRoot = Resolve-MIROvernightPath -Path $OutputRoot
New-Item -ItemType Directory -Force -Path $resolvedOutputRoot | Out-Null
$resolvedOutputRoot = (Resolve-Path -LiteralPath $resolvedOutputRoot).Path
$logPath = Join-Path $resolvedOutputRoot "overnight.log"

Write-Host "[overnight] repo: $($repo.Path)"
Write-Host "[overnight] Factorio: $resolvedFactorioBin"
Write-Host "[overnight] local mod dir: $resolvedLocalModDir ($localZipCount zips)"
Write-Host "[overnight] output root: $resolvedOutputRoot"
Write-Host "[overnight] log: $logPath"

if ($DryRun) {
  Write-Host "[overnight] dry run only; no validation or load tests will be started."
  exit 0
}

$transcriptStarted = $false
try {
  Start-Transcript -Path $logPath -Force | Out-Null
  $transcriptStarted = $true
} catch {
  Write-Warning "Could not start transcript at ${logPath}: $($_.Exception.Message)"
}

try {
  if (-not $SkipPowerConfig) {
    $powercfg = Get-Command powercfg -ErrorAction SilentlyContinue
    if ($powercfg) {
      Write-Host "[overnight] disabling AC standby and hibernate while this terminal stays open"
      & powercfg /change standby-timeout-ac 0 | Out-Host
      & powercfg /change hibernate-timeout-ac 0 | Out-Host
    } else {
      Write-Warning "powercfg was not found; skipping power-setting changes."
    }
  }

  if (-not $SkipStrictGate) {
    Write-Host "[overnight] strict release gate"
    & (Join-Path $repo "scripts\Invoke-MIRExtendedTests.ps1") `
      -Tier Static,Runtime,AuditSmoke `
      -FactorioBin $resolvedFactorioBin `
      -FailFast `
      -FailOnAuditFailures `
      -OutputRoot (Join-Path $resolvedOutputRoot "release-gate")
  }

  if (-not $SkipLocalSweep) {
    $sweepParams = @{
      Tier = @("LocalLibraryScenarios", "GeneratedLocalScenarios", "LocalModZips")
      FactorioBin = $resolvedFactorioBin
      LocalModZipDirs = @($resolvedLocalModDir)
      LocalModLibraryDirs = @($resolvedLocalModDir)
      Offline = $true
      CollectAll = $true
      ScenarioTimeoutSeconds = $ScenarioTimeoutSeconds
      OutputRoot = (Join-Path $resolvedOutputRoot "local-sweep")
    }
    if (-not $SkipGeneratedLocalPairwise) {
      $sweepParams.IncludeGeneratedLocalPairwise = $true
      $sweepParams.GeneratedLocalPairwiseLimit = $GeneratedLocalPairwiseLimit
    }

    Write-Host "[overnight] prioritized local 2.1 sweep"
    & (Join-Path $repo "scripts\Invoke-MIRExtendedTests.ps1") @sweepParams
  }

  Write-Host "[overnight] done: $resolvedOutputRoot"
  Write-Host "[overnight] morning checks:"
  Write-Host ('  .\scripts\Show-MIROvernightSummary.ps1 -OutputRoot "{0}"' -f $resolvedOutputRoot)
  Write-Host ('  Get-Content "{0}" -Tail 300' -f $logPath)
  Write-Host ('  Get-Content "{0}"' -f (Join-Path $resolvedOutputRoot "release-gate\extended-summary.md"))
  Write-Host ('  Get-Content "{0}"' -f (Join-Path $resolvedOutputRoot "local-sweep\extended-summary.md"))
  Write-Host ('  Get-ChildItem "{0}" -Recurse -Filter compat-summary.md' -f $resolvedOutputRoot)
  Write-Host ('  Get-ChildItem "{0}" -Recurse -Filter missing-dependencies.md' -f $resolvedOutputRoot)
  Write-Host ('  Get-ChildItem "{0}" -Recurse -Filter compat-failures.grouped.json' -f $resolvedOutputRoot)
} finally {
  if ($transcriptStarted) {
    Stop-Transcript | Out-Null
  }
}
