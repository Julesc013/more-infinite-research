param(
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [AllowEmptyString()]
  [ValidateSet("", "2.0", "2.1")]
  [string]$FactorioLine = "",
  [string]$LocalModDir = $env:MIR_LOCAL_MOD_DIR,
  [string[]]$RepairSmokeModNames = @("big-mining-drill", "biolabs-in-space"),
  [string]$RepresentativeScenarioName = "local-2-1-bz-suite-space-age",
  [string]$ManualScenariosPath = "validation\scenarios\local-2.1.json",
  [string[]]$AuditFactorioVersions = @(),
  [string]$PullRemote = "origin",
  [string]$PullBranch = "",
  [string]$OutputRoot = "",
  [string]$PackageOutputDir = "",
  [string]$CandidateZip = "",
  [string]$CandidateSourceCommit = "",
  [int]$ScenarioTimeoutSeconds = 900,
  [switch]$SkipBuild,
  [switch]$SkipCleanGitStatus,
  [switch]$SkipStrictGate,
  [switch]$SkipRepairSmokes,
  [Alias("SkipRepresentativeScenario")]
  [switch]$SkipBZSuite,
  [switch]$NoGitPull,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location -LiteralPath $repo
. (Join-Path $repo "tools\lib\mir4\BootstrapMaterialization.ps1")

function Assert-MIRReleaseGateCrossTargetCandidate {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$FactorioLine,
    [Parameter(Mandatory)][string]$CandidateZip,
    [Parameter(Mandatory)][string]$CandidateSourceCommit,
    [Parameter(Mandatory)][string]$FactorioBin
  )

  $targetByLine = @{
    "2.0" = "f200"
  }
  if (-not $targetByLine.ContainsKey($FactorioLine)) {
    throw "Cross-target release-gate testing is not authorized for Factorio line '$FactorioLine'."
  }
  $targetKey = [string]$targetByLine[$FactorioLine]
  $laneRoot = Join-Path $RepoRoot "build\mir4\local-playtest-shadow"
  $authorityPath = Join-Path $RepoRoot ".mir\releases\waves\mir4-r0\MIR4-Private-Lane-AuthorizationV3.json"
  $manifestPath = Join-Path $laneRoot "manifests\$targetKey.json"
  if (-not (Test-Path -LiteralPath $authorityPath -PathType Leaf) -or
      -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Cross-target release-gate testing requires the exact V3 private-lane authority and target manifest."
  }

  $authority = Get-Content -Raw -LiteralPath $authorityPath | ConvertFrom-Json -Depth 100
  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
  if (-not (Test-MIR4BootstrapRecordHash -Record $authority) -or
      -not (Test-MIR4BootstrapRecordHash -Record $manifest) -or
      [string]$authority.kind -cne "MIR4PrivateLaneAuthorizationV3" -or
      [string]$authority.authority_family -cne "MIRLocalArtifactLaneAuthorizationV1" -or
      [bool]$authority.package_visible -or
      [bool]$authority.release_admission_authorized -or
      [bool]$authority.public_identity_authorized -or
      [bool]$authority.public_output_authorized -or
      [bool]$authority.signing_or_sealing_authorized -or
      [bool]$authority.publication_authorized -or
      [bool]$authority.wildcard_targets_authorized -or
      [bool]$authority.gate_waivers_authorized) {
    throw "Cross-target release-gate testing requires a valid, private, release-orthogonal V3 authority."
  }

  $rows = @($authority.authorized_targets | Where-Object {
    [string]$_.target_key -ceq $targetKey -and [string]$_.factorio_line -ceq $FactorioLine
  })
  if ($rows.Count -ne 1) { throw "Cross-target release-gate testing requires one exact authorized target row." }
  $row = $rows[0]
  if ([string]$CandidateSourceCommit -cne [string]$row.source_commit -or
      [string]$manifest.kind -cne "MIR4LocalPlaytestCandidateManifestV1" -or
      [string]$manifest.lane -cne "local-playtest-shadow" -or
      [string]$manifest.target_key -cne $targetKey -or
      [string]$manifest.factorio_line -cne $FactorioLine -or
      [string]$manifest.distribution_version -cne [string]$row.distribution_version -or
      [string]$manifest.admission -cne "non-authoritative-shadow-blocked-by-eol" -or
      [bool]$manifest.public_output_authorized -or
      [bool]$manifest.release_claim_permitted -or
      [string]$manifest.local_lane_authority.record_sha256 -cne [string]$authority.record_sha256) {
    throw "Cross-target release-gate testing inputs do not match the exact authorized target identity."
  }

  $expectedCandidate = [IO.Path]::GetFullPath((Join-Path $laneRoot ([string]$manifest.local_distribution.path)))
  if (-not $expectedCandidate.Equals([IO.Path]::GetFullPath($CandidateZip), [StringComparison]::OrdinalIgnoreCase) -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateZip).Hash -cne [string]$manifest.local_distribution.archive_sha256) {
    throw "Cross-target release-gate testing requires the exact governed candidate path and bytes."
  }
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $FactorioBin).Hash -cne [string]$row.engine_sha256) {
    throw "Cross-target release-gate testing requires the exact target-bound Factorio engine."
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($CandidateZip)
  try {
    $infoEntries = @($archive.Entries | Where-Object { $_.FullName -match "^[^/]+/info\.json$" })
    if ($infoEntries.Count -ne 1) { throw "Cross-target candidate must contain one package-root info.json." }
    $reader = [IO.StreamReader]::new($infoEntries[0].Open(), [Text.Encoding]::UTF8, $true)
    try { $candidateInfo = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
  } finally {
    $archive.Dispose()
  }
  if ([string]$candidateInfo.name -cne "more-infinite-research" -or
      [string]$candidateInfo.version -cne [string]$row.distribution_version -or
      [string]$candidateInfo.factorio_version -cne $FactorioLine) {
    throw "Cross-target candidate metadata does not match the authorized distribution and Factorio line."
  }

  return [pscustomobject][ordered]@{
    authority = "MIR4PrivateLaneAuthorizationV3"
    target_key = $targetKey
    factorio_line = $FactorioLine
    cross_target_candidate_authorization = $script:crossTargetCandidateAuthorization
    distribution_version = [string]$row.distribution_version
    candidate_sha256 = [string]$manifest.local_distribution.archive_sha256
    engine_sha256 = [string]$row.engine_sha256
    release_authority = $false
  }
}

$modInfo = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
$modName = [string]$modInfo.name
$modVersion = [string]$modInfo.version
$targetFactorioVersion = [string]$modInfo.factorio_version
if ([string]::IsNullOrWhiteSpace($FactorioLine)) {
  $FactorioLine = $targetFactorioVersion
}
$requiresCrossTargetAuthorization = $FactorioLine -ne $targetFactorioVersion
if (-not $AuditFactorioVersions -or $AuditFactorioVersions.Count -eq 0) {
  $AuditFactorioVersions = @($FactorioLine)
}
if ([string]::IsNullOrWhiteSpace($LocalModDir)) {
  $LocalModDir = "C:\Projects\Factorio\testmods_$FactorioLine"
}
if (-not $SkipRepairSmokes -and @($RepairSmokeModNames).Count -eq 0) {
  throw "RepairSmokeModNames is empty. Pass -SkipRepairSmokes or provide at least one local mod name."
}
if (-not $SkipBZSuite -and [string]::IsNullOrWhiteSpace($RepresentativeScenarioName)) {
  throw "RepresentativeScenarioName is empty. Pass -SkipRepresentativeScenario or provide a scenario name."
}

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
    package_output_dir = $script:packageOutputDir
    factorio_bin = $script:resolvedFactorioBin
    candidate_zip = $script:resolvedCandidateZip
    candidate_sha256 = if ($script:resolvedCandidateZip) { (Get-FileHash -Algorithm SHA256 -LiteralPath $script:resolvedCandidateZip).Hash } else { "" }
    candidate_source_commit = $CandidateSourceCommit
    local_mod_dir = $script:resolvedLocalModDir
    repair_smoke_mod_names = @($RepairSmokeModNames)
    representative_scenario_name = $RepresentativeScenarioName
    manual_scenarios_path = $script:resolvedManualScenariosPath
    audit_factorio_versions = @($AuditFactorioVersions)
    factorio_line = $FactorioLine
    scenario_timeout_seconds = $ScenarioTimeoutSeconds
    skip_build = [bool]$SkipBuild
    skip_clean_git_status = [bool]$SkipCleanGitStatus
    skip_strict_gate = [bool]$SkipStrictGate
    skip_repair_smokes = [bool]$SkipRepairSmokes
    skip_representative_scenario = [bool]$SkipBZSuite
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
  $md += ('- Package output dir: `{0}`' -f $script:packageOutputDir)
$md += ('- Candidate ZIP: `{0}`' -f $script:resolvedCandidateZip)
$md += ('- Candidate SHA-256: `{0}`' -f $(if ($script:resolvedCandidateZip) { (Get-FileHash -Algorithm SHA256 -LiteralPath $script:resolvedCandidateZip).Hash } else { "" }))
$md += ('- Factorio: `{0}`' -f $script:resolvedFactorioBin)
$md += ('- Factorio line: `{0}`' -f $FactorioLine)
$md += ('- Local mod dir: `{0}`' -f $script:resolvedLocalModDir)
  $md += ('- Repair smoke mods: `{0}`' -f (($RepairSmokeModNames | ForEach-Object { [string]$_ }) -join ", "))
  $md += ('- Representative scenario: `{0}`' -f $RepresentativeScenarioName)
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
$script:crossTargetCandidateAuthorization = $null
$script:resolvedFactorioBin = Resolve-MIRReleaseGateFactorioBinary -Path $FactorioBin
$script:resolvedCandidateZip = ""
if (-not [string]::IsNullOrWhiteSpace($CandidateZip)) {
  $script:resolvedCandidateZip = (Resolve-Path -LiteralPath $CandidateZip).Path
}
if (-not [string]::IsNullOrWhiteSpace($CandidateSourceCommit) -and $CandidateSourceCommit -notmatch '^[0-9a-fA-F]{40}$') {
  throw "CandidateSourceCommit must be a full 40-character git commit."
}
if ($requiresCrossTargetAuthorization) {
  if ([string]::IsNullOrWhiteSpace($script:resolvedCandidateZip) -or
      [string]::IsNullOrWhiteSpace($CandidateSourceCommit)) {
    throw "Cross-target release-gate testing requires an exact candidate ZIP and source commit."
  }
  $script:crossTargetCandidateAuthorization = Assert-MIRReleaseGateCrossTargetCandidate `
    -RepoRoot $repo.Path `
    -FactorioLine $FactorioLine `
    -CandidateZip $script:resolvedCandidateZip `
    -CandidateSourceCommit $CandidateSourceCommit `
    -FactorioBin $script:resolvedFactorioBin
}
$script:resolvedLocalModDir = ""
$script:packageOutputDir = $PackageOutputDir
if ([string]::IsNullOrWhiteSpace($script:packageOutputDir)) {
  $script:packageOutputDir = "dist"
}
$script:resolvedManualScenariosPath = Resolve-MIRReleaseGatePath -Path $ManualScenariosPath
if (-not (Test-Path -LiteralPath $script:resolvedManualScenariosPath)) {
  throw "Manual scenarios file does not exist: $script:resolvedManualScenariosPath"
}

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
  $OutputRoot = ".\build\results\release-targeted-$stamp"
}
$script:resolvedOutputRoot = Resolve-MIRReleaseGatePath -Path $OutputRoot
New-Item -ItemType Directory -Force -Path $script:resolvedOutputRoot | Out-Null
$script:resolvedOutputRoot = (Resolve-Path -LiteralPath $script:resolvedOutputRoot).Path
$logPath = Join-Path $script:resolvedOutputRoot "release-targeted.log"

Write-Host "[release] repo: $($repo.Path)"
Write-Host "[release] mod: $modName $modVersion (Factorio $targetFactorioVersion)"
Write-Host "[release] Factorio: $script:resolvedFactorioBin"
Write-Host "[release] Factorio line: $FactorioLine"
Write-Host "[release] candidate ZIP: $script:resolvedCandidateZip"
Write-Host "[release] local mod dir: $script:resolvedLocalModDir ($localZipCount zips)"
Write-Host "[release] repair smoke mods: $($RepairSmokeModNames -join ', ')"
Write-Host "[release] representative scenario: $RepresentativeScenarioName"
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
      $branch = $PullBranch
      if ([string]::IsNullOrWhiteSpace($branch)) {
        $branch = Get-MIRReleaseGateGitValue -Arguments @("rev-parse", "--abbrev-ref", "HEAD")
      }
      & git -C $repo pull $PullRemote $branch
    }
  }

  if (-not $SkipStrictGate) {
    Invoke-MIRReleaseGateStep -Name "strict-current-commit-gate" -Action {
      & (Join-Path $repo "scripts\Invoke-MIRExtendedTests.ps1") `
        -Tier Static,Runtime,AuditSmoke `
        -FactorioBin $script:resolvedFactorioBin `
        -FactorioLine $FactorioLine `
        -FailFast `
        -FailOnAuditFailures `
        -OutputRoot (Join-Path $script:resolvedOutputRoot "strict-gate")
    }
  }

  if (-not $SkipRepairSmokes) {
    Invoke-MIRReleaseGateStep -Name "targeted-repair-local-zips" -Action {
      & (Join-Path $repo "scripts\Invoke-MIRExtendedTests.ps1") `
        -Tier LocalModZips `
        -FactorioBin $script:resolvedFactorioBin `
        -FactorioLine $FactorioLine `
        -ModUnderTestZip $script:resolvedCandidateZip `
        -ModUnderTestSourceCommit $CandidateSourceCommit `
        -LocalModZipDirs @($script:resolvedLocalModDir) `
        -LocalModLibraryDirs @($script:resolvedLocalModDir) `
        -LocalModNames @($RepairSmokeModNames) `
        -Offline `
        -CollectAll `
        -FailOnAuditFailures `
        -ScenarioTimeoutSeconds $ScenarioTimeoutSeconds `
        -OutputRoot (Join-Path $script:resolvedOutputRoot "repair-smokes")
    }
  }

  if (-not $SkipBZSuite) {
    Invoke-MIRReleaseGateStep -Name "representative-local-scenario" -Action {
      $representativeDir = Join-Path $script:resolvedOutputRoot "representative-local-scenario"
      & (Join-Path $repo "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1") `
        -FactorioBin $script:resolvedFactorioBin `
        -FactorioLine $FactorioLine `
        -FactorioVersions @($AuditFactorioVersions) `
        -ModUnderTestZip $script:resolvedCandidateZip `
        -ModUnderTestSourceCommit $CandidateSourceCommit `
        -MaxCandidates 0 `
        -CatalogPages 0 `
        -RunManualScenarios `
        -ScenarioNames @($RepresentativeScenarioName) `
        -ManualScenariosPath $script:resolvedManualScenariosPath `
        -LocalModZipDirs @($script:resolvedLocalModDir) `
        -LocalModLibraryDirs @($script:resolvedLocalModDir) `
        -Offline `
        -RunLoadTests `
        -ScenarioTimeoutSeconds $ScenarioTimeoutSeconds `
        -OutputDir $representativeDir

      & (Join-Path $repo "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1") -AuditDir $representativeDir
      Assert-MIRReleaseGateNoUnexpectedFailures -Name $RepresentativeScenarioName -AuditDir $representativeDir
    }
  }

  if (-not $SkipBuild) {
    Invoke-MIRReleaseGateStep -Name "package-build" -Action {
      & (Join-Path $repo "tools\commands\package\Build-MIRPackage.ps1") -OutputDir $script:packageOutputDir
      & git -C $repo diff --check
    }
  }

  if (-not $SkipCleanGitStatus) {
    Invoke-MIRReleaseGateStep -Name "clean-git-status" -Action {
      $status = @(& git -C $repo status --short)
      if ($status.Count -gt 0) {
        throw "Git status is not clean after release gate:`n$($status -join "`n")"
      }
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
$packageCandidate = if ($script:resolvedCandidateZip) {
  $script:resolvedCandidateZip
} else {
  Join-Path $script:packageOutputDir ("{0}_{1}.zip" -f $modName, $modVersion)
}
Write-Host "[release] package candidate: $packageCandidate"
