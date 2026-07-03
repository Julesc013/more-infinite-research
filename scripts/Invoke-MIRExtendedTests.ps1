param(
  [ValidateSet(
    "Static",
    "Runtime",
    "AuditSmoke",
    "Top25Base",
    "Top25SpaceAge",
    "ManualScenarios",
    "LocalLibraryScenarios",
    "GeneratedLocalScenarios",
    "LocalModZips",
    "Full10KBase",
    "Full10KSpaceAge",
    "SaveCompat",
    "All"
  )]
  [string[]]$Tier = @("Static"),

  [string]$FactorioBin = $env:FACTORIO_BIN,
  [string]$ModPortalUsername = $env:FACTORIO_USERNAME,
  [string]$ModPortalToken = $env:FACTORIO_TOKEN,
  [string]$OutputRoot = ".\artifacts\extended-tests",
  [string]$FromLockfile,
  [string]$ManualScenariosPath,
  [string[]]$LocalModZipDirs = @(),
  [string[]]$LocalModZips = @(),
  [string[]]$LocalModLibraryDirs = @(),
  [string[]]$LocalModLibraryZips = @(),
  [string[]]$LocalModNames = @(),
  [int]$ShardSize = 25,
  [int]$StartIndex = 0,
  [int]$ScenarioTimeoutSeconds = 900,
  [int]$GeneratedLocalPairwiseLimit = 40,
  [switch]$FailFast,
  [switch]$FailOnAuditFailures,
  [switch]$CollectAll,
  [switch]$ContinueOnDependencyFailure,
  [switch]$IncludeFullAudit,
  [switch]$IncludeGeneratedLocalPairwise,
  [switch]$ShardLocalModZips,
  [switch]$Offline
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$outputRootPath = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
  $OutputRoot
} else {
  Join-Path $repo $OutputRoot
}
if (-not (Test-Path -LiteralPath $outputRootPath)) {
  New-Item -ItemType Directory -Path $outputRootPath | Out-Null
}
$outputRootPath = (Resolve-Path -LiteralPath $outputRootPath).Path

$results = @()
$runtimeValidationRan = $false

function New-MIROutputDirectory {
  param([Parameter(Mandatory)][string]$Name)
  $path = Join-Path $outputRootPath $Name
  if (-not (Test-Path -LiteralPath $path)) {
    New-Item -ItemType Directory -Path $path | Out-Null
  }
  return (Resolve-Path -LiteralPath $path).Path
}

function Assert-MIRFactorioBin {
  if ([string]::IsNullOrWhiteSpace($FactorioBin)) {
    throw "FactorioBin is required for this tier. Set FACTORIO_BIN or pass -FactorioBin."
  }
}

function Assert-MIRModPortalCredentials {
  if ($Offline) { return }
  if ([string]::IsNullOrWhiteSpace($ModPortalUsername) -or [string]::IsNullOrWhiteSpace($ModPortalToken)) {
    throw "Mod Portal credentials are required for download/load tiers. Set FACTORIO_USERNAME and FACTORIO_TOKEN or pass parameters."
  }
}

function Invoke-MIRStep {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][scriptblock]$Action
  )

  Write-Host "[extended] starting $Name"
  $started = Get-Date
  $status = "passed"
  $message = ""
  try {
    & $Action
  } catch {
    $status = "failed"
    $message = $_.Exception.Message
    if ($FailFast) {
      $script:results += [ordered]@{
        name = $Name
        status = $status
        message = $message
        seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
      }
      throw
    }
    Write-Warning "[extended] $Name failed: $message"
  }

  $script:results += [ordered]@{
    name = $Name
    status = $status
    message = $message
    seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
  }
  Write-Host "[extended] $Name $status"
}

function Assert-MIRNoAuditFailures {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$AuditDir
  )

  if (-not $FailOnAuditFailures) { return }

  $groupedPath = Join-Path $AuditDir "compat-failures.grouped.json"
  if (-not (Test-Path -LiteralPath $groupedPath)) {
    throw "Audit tier $Name did not produce grouped failure output: $groupedPath"
  }

  $grouped = Get-Content -Raw -LiteralPath $groupedPath | ConvertFrom-Json
  $unexpectedCount = 0
  if ($null -ne $grouped.PSObject.Properties["unexpected_count"]) {
    $unexpectedCount = [int]$grouped.unexpected_count
  } else {
    $unexpectedCount = [int]$grouped.group_count
  }

  if ($unexpectedCount -gt 0) {
    throw "Audit tier $Name produced $unexpectedCount unexpected grouped failure(s). See $groupedPath"
  }
}

function Invoke-MIRCompatAuditTier {
  param(
    [Parameter(Mandatory)][string]$Name,
    [switch]$IncludeSpaceAge,
    [int]$MaxCandidates = 25,
    [int]$CatalogPages = 0,
    [switch]$RunManualScenarios,
    [switch]$RunLocalModZips,
    [switch]$RunGeneratedLocalScenarios,
    [switch]$FullAudit,
    [switch]$IncludeRecommendedDependencies,
    [string]$ManualScenariosPathOverride
  )

  Assert-MIRFactorioBin
  if ($MaxCandidates -ne 0 -or $RunManualScenarios -or $RunLocalModZips -or $RunGeneratedLocalScenarios) {
    Assert-MIRModPortalCredentials
  }

  $auditDir = New-MIROutputDirectory -Name $Name
  $auditParams = @{
    FactorioBin = $FactorioBin
    ModPortalUsername = $ModPortalUsername
    ModPortalToken = $ModPortalToken
    MinDownloads = 10000
    FactorioVersions = @("2.1")
    OutputDir = $auditDir
    DownloadMods = $true
    RunLoadTests = $true
    MaxCandidates = $MaxCandidates
    CatalogPages = $CatalogPages
    ScenarioTimeoutSeconds = $ScenarioTimeoutSeconds
  }

  if (-not [string]::IsNullOrWhiteSpace($FromLockfile) -and -not $RunManualScenarios) {
    $auditParams.FromLockfile = $FromLockfile
  }
  if ($IncludeSpaceAge) { $auditParams.IncludeSpaceAge = $true }
  if ($FailFast -and -not $CollectAll) { $auditParams.FailFast = $true }
  if ($ContinueOnDependencyFailure) { $auditParams.ContinueOnDependencyFailure = $true }
  if ($LocalModZipDirs.Count -gt 0) { $auditParams.LocalModZipDirs = $LocalModZipDirs }
  if ($LocalModZips.Count -gt 0) { $auditParams.LocalModZips = $LocalModZips }
  if ($LocalModLibraryDirs.Count -gt 0) { $auditParams.LocalModLibraryDirs = $LocalModLibraryDirs }
  if ($LocalModLibraryZips.Count -gt 0) { $auditParams.LocalModLibraryZips = $LocalModLibraryZips }
  if ($LocalModNames.Count -gt 0) { $auditParams.LocalModNames = $LocalModNames }
  if ($Offline) {
    $auditParams.Offline = $true
    $auditParams.UseCachedDownloads = $true
  }
  if ($RunManualScenarios) {
    $auditParams.RunManualScenarios = $true
    if (-not [string]::IsNullOrWhiteSpace($ManualScenariosPathOverride)) {
      $auditParams.ManualScenariosPath = $ManualScenariosPathOverride
    } elseif (-not [string]::IsNullOrWhiteSpace($script:ManualScenariosPath)) {
      $auditParams.ManualScenariosPath = $script:ManualScenariosPath
    } else {
      $auditParams.ManualScenariosPath = (Join-Path $repo "fixtures\compat-matrix\manual-scenarios.json")
    }
  }
  if ($RunLocalModZips) {
    $auditParams.RunLocalModZips = $true
    $auditParams.IncludeRecommendedDependencies = $true
  }
  if ($RunGeneratedLocalScenarios) {
    $auditParams.RunGeneratedLocalScenarios = $true
    $auditParams.GenerateLocalMegaScenario = $true
    $auditParams.GenerateLocalClusterScenarios = $true
    $auditParams.IncludeRecommendedDependencies = $true
    if ($IncludeGeneratedLocalPairwise) {
      $auditParams.GenerateLocalPairwiseScenarios = $true
      $auditParams.GeneratedLocalPairwiseLimit = $GeneratedLocalPairwiseLimit
    }
  }
  if ($IncludeRecommendedDependencies) {
    $auditParams.IncludeRecommendedDependencies = $true
  }
  if ($FullAudit) {
    $auditParams.StartIndex = $StartIndex
    $auditParams.Count = $ShardSize
  }
  if ($RunLocalModZips -and $ShardLocalModZips) {
    $auditParams.StartIndex = $StartIndex
    $auditParams.Count = $ShardSize
  }

  & (Join-Path $repo "scripts\Invoke-MIRCompatAudit.ps1") @auditParams
  & (Join-Path $repo "scripts\Convert-MIRCompatAuditResults.ps1") -AuditDir $auditDir
  Assert-MIRNoAuditFailures -Name $Name -AuditDir $auditDir
}

$expandedTiers = @()
foreach ($entry in $Tier) {
  if ($entry -eq "All") {
    $expandedTiers += @("Static", "Runtime", "AuditSmoke", "Top25Base", "Top25SpaceAge", "ManualScenarios", "SaveCompat")
    if ($IncludeFullAudit) {
      $expandedTiers += @("Full10KBase", "Full10KSpaceAge")
    }
  } else {
    $expandedTiers += $entry
  }
}
$expandedTiers = @($expandedTiers | Select-Object -Unique)

foreach ($entry in $expandedTiers) {
  switch ($entry) {
    "Static" {
      Invoke-MIRStep -Name "Static" -Action {
        & (Join-Path $repo "scripts\Invoke-MIRValidation.ps1") -StaticOnly
        git -C $repo diff --check
      }
    }
    "Runtime" {
      Invoke-MIRStep -Name "Runtime" -Action {
        Assert-MIRFactorioBin
        & (Join-Path $repo "scripts\Invoke-MIRValidation.ps1") -FactorioBin $FactorioBin
        $script:runtimeValidationRan = $true
      }
    }
    "AuditSmoke" {
      Invoke-MIRStep -Name "AuditSmoke" -Action {
        $auditDir = New-MIROutputDirectory -Name "audit-smoke"
        $auditParams = @{
          RunManualScenarios = $true
          ManualScenariosPath = (Join-Path $repo "fixtures\compat-matrix\manual-scenarios.json")
          ScenarioNames = @("space-age-baseline")
          CatalogPages = 0
          MaxCandidates = 0
          MinDownloads = 10000
          FactorioVersions = @("2.1")
          ScenarioTimeoutSeconds = $ScenarioTimeoutSeconds
          OutputDir = $auditDir
        }
        if ($FailFast -and -not $CollectAll) { $auditParams.FailFast = $true }
        & (Join-Path $repo "scripts\Invoke-MIRCompatAudit.ps1") @auditParams
        & (Join-Path $repo "scripts\Convert-MIRCompatAuditResults.ps1") -AuditDir $auditDir
        Assert-MIRNoAuditFailures -Name "audit-smoke" -AuditDir $auditDir
      }
    }
    "Top25Base" {
      Invoke-MIRStep -Name "Top25Base" -Action {
        Invoke-MIRCompatAuditTier -Name "top25-base" -MaxCandidates 25 -CatalogPages 0
      }
    }
    "Top25SpaceAge" {
      Invoke-MIRStep -Name "Top25SpaceAge" -Action {
        Invoke-MIRCompatAuditTier -Name "top25-space-age" -IncludeSpaceAge -MaxCandidates 25 -CatalogPages 0
      }
    }
    "ManualScenarios" {
      Invoke-MIRStep -Name "ManualScenarios" -Action {
        Invoke-MIRCompatAuditTier -Name "manual-scenarios" -RunManualScenarios -MaxCandidates 0 -CatalogPages 0
      }
    }
    "LocalLibraryScenarios" {
      Invoke-MIRStep -Name "LocalLibraryScenarios" -Action {
        $scenarioPath = if (-not [string]::IsNullOrWhiteSpace($ManualScenariosPath)) {
          $ManualScenariosPath
        } else {
          Join-Path $repo "fixtures\compat-matrix\local-library-scenarios.json"
        }
        Invoke-MIRCompatAuditTier -Name "local-library-scenarios" -RunManualScenarios -IncludeRecommendedDependencies -MaxCandidates 0 -CatalogPages 0 -ManualScenariosPathOverride $scenarioPath
      }
    }
    "GeneratedLocalScenarios" {
      Invoke-MIRStep -Name "GeneratedLocalScenarios" -Action {
        Invoke-MIRCompatAuditTier -Name "generated-local-scenarios" -RunGeneratedLocalScenarios -MaxCandidates 0 -CatalogPages 0
      }
    }
    "LocalModZips" {
      Invoke-MIRStep -Name "LocalModZips" -Action {
        Invoke-MIRCompatAuditTier -Name "local-mod-zips" -RunLocalModZips -MaxCandidates 0 -CatalogPages 0
      }
    }
    "Full10KBase" {
      Invoke-MIRStep -Name "Full10KBase" -Action {
        if (-not $IncludeFullAudit) {
          throw "Full10KBase requires -IncludeFullAudit to avoid accidental long-running audits."
        }
        Invoke-MIRCompatAuditTier -Name ("full10k-base-{0}-{1}" -f $StartIndex, $ShardSize) -MaxCandidates 10000 -CatalogPages 0 -FullAudit
      }
    }
    "Full10KSpaceAge" {
      Invoke-MIRStep -Name "Full10KSpaceAge" -Action {
        if (-not $IncludeFullAudit) {
          throw "Full10KSpaceAge requires -IncludeFullAudit to avoid accidental long-running audits."
        }
        Invoke-MIRCompatAuditTier -Name ("full10k-space-age-{0}-{1}" -f $StartIndex, $ShardSize) -IncludeSpaceAge -MaxCandidates 10000 -CatalogPages 0 -FullAudit
      }
    }
    "SaveCompat" {
      Invoke-MIRStep -Name "SaveCompat" -Action {
        Assert-MIRFactorioBin
        if (-not $runtimeValidationRan) {
          & (Join-Path $repo "scripts\Invoke-MIRValidation.ps1") -FactorioBin $FactorioBin
          $script:runtimeValidationRan = $true
        } else {
          Write-Host "[extended] SaveCompat covered by the runtime validation suite in this invocation."
        }
      }
    }
  }
}

$summaryJson = Join-Path $outputRootPath "extended-summary.json"
$summaryMd = Join-Path $outputRootPath "extended-summary.md"

[ordered]@{
  schema = 1
  generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
  tiers = $expandedTiers
  include_full_audit = [bool]$IncludeFullAudit
  fail_on_audit_failures = [bool]$FailOnAuditFailures
  collect_all = [bool]$CollectAll
  continue_on_dependency_failure = [bool]$ContinueOnDependencyFailure
  offline = [bool]$Offline
  from_lockfile = $FromLockfile
  manual_scenarios_path = $ManualScenariosPath
  local_mod_zip_dirs = @($LocalModZipDirs)
  local_mod_zips = @($LocalModZips)
  local_mod_library_dirs = @($LocalModLibraryDirs)
  local_mod_library_zips = @($LocalModLibraryZips)
  local_mod_names = @($LocalModNames)
  include_generated_local_pairwise = [bool]$IncludeGeneratedLocalPairwise
  generated_local_pairwise_limit = $GeneratedLocalPairwiseLimit
  shard_local_mod_zips = [bool]$ShardLocalModZips
  scenario_timeout_seconds = $ScenarioTimeoutSeconds
  start_index = $StartIndex
  shard_size = $ShardSize
  results = $results
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryJson -Encoding UTF8

$md = @()
$md += "# MIR Extended Test Summary"
$md += ""
$md += "- Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")"
$md += ('- Output root: `{0}`' -f $outputRootPath)
$md += ('- Tiers: `{0}`' -f ($expandedTiers -join ', '))
$md += ('- Include full audit: `{0}`' -f ([bool]$IncludeFullAudit))
$md += ('- Fail on audit failures: `{0}`' -f ([bool]$FailOnAuditFailures))
$md += ('- Collect all audit scenarios: `{0}`' -f ([bool]$CollectAll))
$md += ('- Continue on dependency failure: `{0}`' -f ([bool]$ContinueOnDependencyFailure))
$md += ('- Offline: `{0}`' -f ([bool]$Offline))
$md += ('- Scenario timeout seconds: `{0}`' -f $ScenarioTimeoutSeconds)
if (-not [string]::IsNullOrWhiteSpace($ManualScenariosPath)) {
  $md += ('- Manual scenarios path: `{0}`' -f $ManualScenariosPath)
}
if (-not [string]::IsNullOrWhiteSpace($FromLockfile)) {
  $md += ('- From lockfile: `{0}`' -f $FromLockfile)
}
if ($LocalModZipDirs.Count -gt 0) {
  $md += ('- Local mod zip dirs: `{0}`' -f ($LocalModZipDirs -join ', '))
}
if ($LocalModZips.Count -gt 0) {
  $md += ('- Local mod zips: `{0}`' -f ($LocalModZips -join ', '))
}
if ($LocalModLibraryDirs.Count -gt 0) {
  $md += ('- Local mod library dirs: `{0}`' -f ($LocalModLibraryDirs -join ', '))
}
if ($LocalModLibraryZips.Count -gt 0) {
  $md += ('- Local mod library zips: `{0}`' -f ($LocalModLibraryZips -join ', '))
}
if ($LocalModNames.Count -gt 0) {
  $md += ('- Local mod names: `{0}`' -f ($LocalModNames -join ', '))
}
$md += ('- Include generated local pairwise: `{0}`' -f ([bool]$IncludeGeneratedLocalPairwise))
$md += ('- Generated local pairwise limit: `{0}`' -f $GeneratedLocalPairwiseLimit)
$md += ('- Shard local mod zips: `{0}`' -f ([bool]$ShardLocalModZips))
$md += ""
$md += "| Step | Status | Seconds | Message |"
$md += "| --- | --- | ---: | --- |"
foreach ($result in $results) {
  $md += "| $($result.name) | $($result.status) | $($result.seconds) | $($result.message) |"
}
$md -join "`n" | Set-Content -LiteralPath $summaryMd -Encoding UTF8

$failed = @($results | Where-Object { $_.status -ne "passed" })
if ($failed.Count -gt 0) {
  throw "Extended tests completed with $($failed.Count) failed step(s). See $summaryMd"
}

Write-Host "[extended] wrote $summaryMd"
Write-Host "[extended] wrote $summaryJson"
