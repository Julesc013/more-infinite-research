param(
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [string]$LocalModDir = "C:\Projects\Factorio\testmods_readonly_2.1",
  [string]$OutputRoot = "",
  [int]$ScenarioTimeoutSeconds = 900,
  [switch]$SkipBuild,
  [switch]$SkipRepairSmokes,
  [switch]$SkipBZSuite,
  [switch]$NoGitPull,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location -LiteralPath $repo

function Resolve-MIRReleaseGatePath {
  param([Parameter(Mandatory)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return (Join-Path $repo $Path)
}

function Resolve-MIRReleaseGateFactorioBinary {
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

function Get-MIRReleaseGateGitValue {
  param([Parameter(Mandatory)][string[]]$Arguments)
  $value = & git @Arguments 2>$null
  if ($LASTEXITCODE -ne 0) { return "" }
  return (($value | Select-Object -First 1) -as [string]).Trim()
}

function Invoke-MIRReleaseGateStep {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][scriptblock]$Action
  )

  Write-Host "[release] starting $Name"
  $started = Get-Date
  try {
    & $Action
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
    $script:releaseGateResults += [ordered]@{
      name = $Name
      status = "passed"
      message = ""
      seconds = $seconds
    }
    Write-Host "[release] passed $Name seconds=$seconds"
  } catch {
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
    $script:releaseGateResults += [ordered]@{
      name = $Name
      status = "failed"
      message = $_.Exception.Message
      seconds = $seconds
    }
    Write-Host "[release] failed $Name seconds=$seconds"
    throw
  }
}

function Assert-MIRReleaseGateNoUnexpectedFailures {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$AuditDir
  )

  $groupedPath = Join-Path $AuditDir "compat-failures.grouped.json"
  if (-not (Test-Path -LiteralPath $groupedPath)) {
    throw "$Name did not produce grouped failure output: $groupedPath"
  }

  $grouped = Get-Content -Raw -LiteralPath $groupedPath | ConvertFrom-Json
  $unexpectedCount = 0
  if ($null -ne $grouped.PSObject.Properties["unexpected_count"]) {
    $unexpectedCount = [int]$grouped.unexpected_count
  } else {
    $unexpectedCount = [int]$grouped.group_count
  }

  if ($unexpectedCount -gt 0) {
    throw "$Name produced $unexpectedCount unexpected grouped failure(s). See $groupedPath"
  }
}

function Write-MIRReleaseGateSummary {
  param([string]$FailureMessage = "")

  if (-not $script:resolvedOutputRoot) { return }

  $summaryJson = Join-Path $script:resolvedOutputRoot "release-targeted-summary.json"
  $summaryMd = Join-Path $script:resolvedOutputRoot "release-targeted-summary.md"
  $gitStatus = @(& git -C $repo status --short)
  $gitLog = @(& git -C $repo log --oneline -5)

  [ordered]@{
    schema = 1
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    repo = $repo.Path
    output_root = $script:resolvedOutputRoot
    factorio_bin = $script:resolvedFactorioBin
    local_mod_dir = $script:resolvedLocalModDir
    scenario_timeout_seconds = $ScenarioTimeoutSeconds
    skip_build = [bool]$SkipBuild
    skip_repair_smokes = [bool]$SkipRepairSmokes
    skip_bz_suite = [bool]$SkipBZSuite
    no_git_pull = [bool]$NoGitPull
    dry_run = [bool]$DryRun
    git_branch = Get-MIRReleaseGateGitValue -Arguments @("rev-parse", "--abbrev-ref", "HEAD")
    git_commit = Get-MIRReleaseGateGitValue -Arguments @("rev-parse", "HEAD")
    git_status = $gitStatus
    results = $script:releaseGateResults
    failure_message = $FailureMessage
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryJson -Encoding UTF8

  $md = @()
  $md += "# MIR Release Targeted Gate Summary"
  $md += ""
  $md += ('- Generated: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
  $md += ('- Repo: `{0}`' -f $repo.Path)
  $md += ('- Output root: `{0}`' -f $script:resolvedOutputRoot)
  $md += ('- Factorio: `{0}`' -f $script:resolvedFactorioBin)
  $md += ('- Local mod dir: `{0}`' -f $script:resolvedLocalModDir)
  $md += ('- Scenario timeout seconds: `{0}`' -f $ScenarioTimeoutSeconds)
  $md += ('- Git branch: `{0}`' -f (Get-MIRReleaseGateGitValue -Arguments @("rev-parse", "--abbrev-ref", "HEAD")))
  $md += ('- Git commit: `{0}`' -f (Get-MIRReleaseGateGitValue -Arguments @("rev-parse", "--short", "HEAD")))
  if (-not [string]::IsNullOrWhiteSpace($FailureMessage)) {
    $md += ('- Failure: `{0}`' -f $FailureMessage)
  }
  $md += ""
  $md += "| Step | Status | Seconds | Message |"
  $md += "| --- | --- | ---: | --- |"
  foreach ($result in $script:releaseGateResults) {
    $md += "| $($result.name) | $($result.status) | $($result.seconds) | $($result.message) |"
  }
  $md += ""
  $md += "## Git Status"
  if ($gitStatus.Count -eq 0) {
    $md += ""
    $md += "Clean."
  } else {
    $md += ""
    $md += '```text'
    $md += $gitStatus
    $md += '```'
  }
  $md += ""
  $md += "## Recent Commits"
  $md += ""
  $md += '```text'
  $md += $gitLog
  $md += '```'

  $md -join "`n" | Set-Content -LiteralPath $summaryMd -Encoding UTF8

  Write-Host "[release] wrote $summaryMd"
  Write-Host "[release] wrote $summaryJson"
}

$script:releaseGateResults = @()
$script:resolvedFactorioBin = Resolve-MIRReleaseGateFactorioBinary -Path $FactorioBin
$script:resolvedLocalModDir = ""

$needsLocalModDir = -not ($SkipRepairSmokes -and $SkipBZSuite)
if ($needsLocalModDir) {
  if (-not (Test-Path -LiteralPath $LocalModDir)) {
    throw "Local mod directory does not exist: $LocalModDir"
  }
  $script:resolvedLocalModDir = (Resolve-Path -LiteralPath $LocalModDir).Path
  $localZipCount = @(Get-ChildItem -LiteralPath $script:resolvedLocalModDir -Filter *.zip -File).Count
  if ($localZipCount -eq 0) {
    throw "Local mod directory contains no zip files: $script:resolvedLocalModDir"
  }
} else {
  $script:resolvedLocalModDir = $LocalModDir
  $localZipCount = 0
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = ".\artifacts\release-targeted-$stamp"
}
$script:resolvedOutputRoot = Resolve-MIRReleaseGatePath -Path $OutputRoot
New-Item -ItemType Directory -Force -Path $script:resolvedOutputRoot | Out-Null
$script:resolvedOutputRoot = (Resolve-Path -LiteralPath $script:resolvedOutputRoot).Path
$logPath = Join-Path $script:resolvedOutputRoot "release-targeted.log"

Write-Host "[release] repo: $($repo.Path)"
Write-Host "[release] Factorio: $script:resolvedFactorioBin"
Write-Host "[release] local mod dir: $script:resolvedLocalModDir ($localZipCount zips)"
Write-Host "[release] output root: $script:resolvedOutputRoot"
Write-Host "[release] log: $logPath"

if ($DryRun) {
  Write-Host "[release] dry run only; no validation or load tests will be started."
  Write-MIRReleaseGateSummary
  exit 0
}

$transcriptStarted = $false
$failureMessage = ""
try {
  Start-Transcript -Path $logPath -Force | Out-Null
  $transcriptStarted = $true
} catch {
  Write-Warning "Could not start transcript at ${logPath}: $($_.Exception.Message)"
}

try {
  if (-not $NoGitPull) {
    Invoke-MIRReleaseGateStep -Name "git-pull" -Action {
      & git -C $repo pull origin dev
    }
  }

  Invoke-MIRReleaseGateStep -Name "strict-current-commit-gate" -Action {
    & (Join-Path $repo "scripts\Invoke-MIRExtendedTests.ps1") `
      -Tier Static,Runtime,AuditSmoke `
      -FactorioBin $script:resolvedFactorioBin `
      -FailFast `
      -FailOnAuditFailures `
      -OutputRoot (Join-Path $script:resolvedOutputRoot "strict-gate")
  }

  if (-not $SkipRepairSmokes) {
    Invoke-MIRReleaseGateStep -Name "targeted-repair-local-zips" -Action {
      & (Join-Path $repo "scripts\Invoke-MIRExtendedTests.ps1") `
        -Tier LocalModZips `
        -FactorioBin $script:resolvedFactorioBin `
        -LocalModZipDirs @($script:resolvedLocalModDir) `
        -LocalModLibraryDirs @($script:resolvedLocalModDir) `
        -LocalModNames @("big-mining-drill", "biolabs-in-space") `
        -Offline `
        -CollectAll `
        -FailOnAuditFailures `
        -ScenarioTimeoutSeconds $ScenarioTimeoutSeconds `
        -OutputRoot (Join-Path $script:resolvedOutputRoot "repair-smokes")
    }
  }

  if (-not $SkipBZSuite) {
    Invoke-MIRReleaseGateStep -Name "bz-suite-space-age" -Action {
      $bzDir = Join-Path $script:resolvedOutputRoot "bz-suite"
      & (Join-Path $repo "scripts\Invoke-MIRCompatAudit.ps1") `
        -FactorioBin $script:resolvedFactorioBin `
        -FactorioVersions @("2.1") `
        -MaxCandidates 0 `
        -CatalogPages 0 `
        -RunManualScenarios `
        -ScenarioNames @("local-2-1-bz-suite-space-age") `
        -ManualScenariosPath (Join-Path $repo "fixtures\compat-matrix\local-library-scenarios.json") `
        -LocalModZipDirs @($script:resolvedLocalModDir) `
        -LocalModLibraryDirs @($script:resolvedLocalModDir) `
        -Offline `
        -RunLoadTests `
        -ScenarioTimeoutSeconds $ScenarioTimeoutSeconds `
        -OutputDir $bzDir

      & (Join-Path $repo "scripts\Convert-MIRCompatAuditResults.ps1") -AuditDir $bzDir
      Assert-MIRReleaseGateNoUnexpectedFailures -Name "BZ suite" -AuditDir $bzDir
    }
  }

  if (-not $SkipBuild) {
    Invoke-MIRReleaseGateStep -Name "package-build" -Action {
      & (Join-Path $repo "scripts\Build-MIRPackage.ps1")
      & git -C $repo diff --check
    }
  }

  Invoke-MIRReleaseGateStep -Name "clean-git-status" -Action {
    $status = @(& git -C $repo status --short)
    if ($status.Count -gt 0) {
      throw "Git status is not clean after release gate:`n$($status -join "`n")"
    }
  }
} catch {
  $failureMessage = $_.Exception.Message
  throw
} finally {
  Write-MIRReleaseGateSummary -FailureMessage $failureMessage
  if ($transcriptStarted) {
    Stop-Transcript | Out-Null
  }
}

Write-Host "[release] targeted release checks passed: $script:resolvedOutputRoot"
Write-Host "[release] publish candidate: dist\more-infinite-research_2.1.0.zip"
