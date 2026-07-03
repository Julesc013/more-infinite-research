param(
  [ValidateSet(
    "Static",
    "Runtime",
    "AuditSmoke",
    "Top25Base",
    "Top25SpaceAge",
    "ManualScenarios",
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
  [int]$ShardSize = 25,
  [int]$StartIndex = 0,
  [switch]$FailFast,
  [switch]$IncludeFullAudit
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$outputRootPath = Join-Path $repo $OutputRoot
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

function Invoke-MIRCompatAuditTier {
  param(
    [Parameter(Mandatory)][string]$Name,
    [switch]$IncludeSpaceAge,
    [int]$MaxCandidates = 25,
    [int]$CatalogPages = 0,
    [switch]$RunManualScenarios,
    [switch]$FullAudit
  )

  Assert-MIRFactorioBin
  if ($MaxCandidates -ne 0 -or $RunManualScenarios) {
    Assert-MIRModPortalCredentials
  }

  $auditDir = New-MIROutputDirectory -Name $Name
  $args = @(
    "-FactorioBin", $FactorioBin,
    "-ModPortalUsername", $ModPortalUsername,
    "-ModPortalToken", $ModPortalToken,
    "-MinDownloads", "10000",
    "-FactorioVersions", "2.1",
    "-OutputDir", $auditDir,
    "-DownloadMods",
    "-RunLoadTests",
    "-MaxCandidates", "$MaxCandidates",
    "-CatalogPages", "$CatalogPages"
  )

  if ($IncludeSpaceAge) { $args += "-IncludeSpaceAge" }
  if ($RunManualScenarios) {
    $args += "-RunManualScenarios"
    $args += @("-ManualScenarios", (Join-Path $repo "fixtures\compat-matrix\manual-scenarios.json"))
  }
  if ($FullAudit) {
    $args += @("-StartIndex", "$StartIndex", "-Count", "$ShardSize")
  }

  & (Join-Path $repo "scripts\Invoke-MIRCompatAudit.ps1") @args
  & (Join-Path $repo "scripts\Convert-MIRCompatAuditResults.ps1") -AuditDir $auditDir
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
        & (Join-Path $repo "scripts\Invoke-MIRCompatAudit.ps1") `
          -CatalogPages 1 `
          -MaxCandidates 1 `
          -MinDownloads 10000 `
          -FactorioVersions "2.1" `
          -OutputDir $auditDir
        & (Join-Path $repo "scripts\Convert-MIRCompatAuditResults.ps1") -AuditDir $auditDir
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
