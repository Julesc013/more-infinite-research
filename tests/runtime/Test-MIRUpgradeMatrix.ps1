# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$FromZip,
  [Parameter(Mandatory)][string]$ToZip,
  [Parameter(Mandatory)][string]$FromVersion,
  [Parameter(Mandatory)][string]$ToVersion,
  [string]$FixtureName = "assert-upgrade-3-2-3-to-3-2-5",
  [string]$OutputPath = "build/results/assurance/3.2.5-upgrade-proof.json",
  [string]$WorkRoot = "",
  [ValidateSet('OnFailure','Always','Never')][string]$Retention = 'Always'
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$runner = Join-Path $RepoRoot "tests\runtime\Test-MIRUpgrade.ps1"
$output = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }
$outputParent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputParent)) { New-Item -ItemType Directory -Force -Path $outputParent | Out-Null }

$cases = @(
  [ordered]@{ id = "base-default"; source_only = @() },
  [ordered]@{ id = "space-age-native-owner"; source_only = @() },
  [ordered]@{ id = "automatic-family-creation"; source_only = @() },
  [ordered]@{ id = "base-continuations"; source_only = @() },
  [ordered]@{ id = "mod-set-configuration-change"; source_only = @("upgrade-modset-source") }
)

$privateLocalPlaytestFixtures = @(
  'assert-upgrade-2-5-11-to-4-0-20000',
  'assert-upgrade-2-5-10-to-4-0-20000',
  'assert-upgrade-2-5-9-to-4-0-20000',
  'assert-upgrade-1-9-9-to-4-0-11000',
  'assert-upgrade-1-8-9-to-4-0-10000',
  'assert-upgrade-4-0-20000-to-4-1-20000',
  'assert-upgrade-4-0-11000-to-4-1-11000',
  'assert-upgrade-4-0-10000-to-4-1-10000'
)
if ($FixtureName -in $privateLocalPlaytestFixtures) {
  # Legacy targets do not have Space Age or the modern automatic-family
  # fixture surface. Their direct-predecessor contract is target-local.
  $cases = @([ordered]@{ id = 'base-default'; source_only = @() })
}

if ($FixtureName -eq "assert-upgrade-3-2-1-to-3-2-2") {
  $cases += [ordered]@{ id = "affected-planet-discovery"; source_only = @() }
}

$rows = @()
foreach ($case in $cases) {
  $rowOutput = Join-Path $outputParent "$ToVersion-upgrade-$($case.id)-from-$FromVersion.json"
  $arguments = @{
    RepoRoot = $RepoRoot
    FactorioBin = $FactorioBin
    FromZip = $FromZip
    ToZip = $ToZip
    FromVersion = $FromVersion
    ToVersion = $ToVersion
    FixtureName = $FixtureName
    Archetype = [string]$case.id
    SourceOnlyFixtureNames = @($case.source_only)
    OutputPath = $rowOutput
    WorkRoot = $WorkRoot
    Retention = $Retention
  }
  & $runner @arguments
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $rowOutput -PathType Leaf)) {
    throw "Upgrade matrix row failed: $($case.id)"
  }
  $result = Get-Content -Raw -LiteralPath $rowOutput | ConvertFrom-Json
  if ([int]$result.schema -ne 2 -or [string]$result.status -ne "passed" -or [string]$result.archetype -ne [string]$case.id) {
    throw "Upgrade matrix row is not an exact passing schema-2 result: $($case.id)"
  }
  $assertions = @($result.assertions | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($assertions.Count -eq 0) {
    throw "Upgrade matrix row published no named assertions: $($case.id)"
  }
  if ($FixtureName -in (@("assert-upgrade-3-2-3-to-3-2-5", "assert-upgrade-3-2-9-to-3-2-10", "assert-upgrade-3-2-11-to-4-0-21000", "assert-upgrade-4-0-21000-to-4-1-21000") + $privateLocalPlaytestFixtures) -and
      ("upgraded-save-reload-passed" -notin $assertions -or
       "upgraded-save-second-reload-passed" -notin $assertions -or
       [string]::IsNullOrWhiteSpace([string]$result.second_reload_log) -or
       [string]::IsNullOrWhiteSpace([string]$result.second_reload_log_sha256))) {
    throw "Upgrade matrix row lacks exact first/second reload evidence: $($case.id)"
  }
  $cleanupPath = Join-Path $outputParent "$ToVersion-upgrade-$($case.id)-cleanup.json"
  if (-not (Test-Path -LiteralPath $cleanupPath -PathType Leaf)) { throw "Upgrade matrix row lacks a cleanup receipt: $($case.id)" }
  $cleanup = Get-Content -Raw -LiteralPath $cleanupPath | ConvertFrom-Json
  $expectedCleanupStatus = if ($Retention -eq 'Always') { 'retained' } else { 'removed' }
  if ([string]$cleanup.status -ne $expectedCleanupStatus -or [string]$cleanup.run_status -ne 'passed' -or -not [bool]$cleanup.contained) {
    throw "Upgrade matrix row cleanup receipt is invalid: $($case.id)"
  }
  $rows += [ordered]@{
    id = [string]$case.id
    status = "passed"
    result = Split-Path -Leaf $rowOutput
    result_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $rowOutput).Hash
    cleanup = Split-Path -Leaf $cleanupPath
    cleanup_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $cleanupPath).Hash
    expanded_root_disposition = [string]$cleanup.status
    expanded_root_bytes = [int64]$cleanup.bytes
    assertions = $assertions
  }
}

$factorio = if ([IO.Path]::IsPathRooted($FactorioBin)) { (Resolve-Path -LiteralPath $FactorioBin).Path } else { (Resolve-Path -LiteralPath (Join-Path $RepoRoot $FactorioBin)).Path }
$from = if ([IO.Path]::IsPathRooted($FromZip)) { (Resolve-Path -LiteralPath $FromZip).Path } else { (Resolve-Path -LiteralPath (Join-Path $RepoRoot $FromZip)).Path }
$to = if ([IO.Path]::IsPathRooted($ToZip)) { (Resolve-Path -LiteralPath $ToZip).Path } else { (Resolve-Path -LiteralPath (Join-Path $RepoRoot $ToZip)).Path }
$factorioVersion = (Get-Item -LiteralPath $factorio).VersionInfo.FileVersion

[ordered]@{
  schema = 1
  kind = "mir-upgrade-matrix"
  status = "passed"
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  source_commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  factorio = [ordered]@{
    version = $factorioVersion
    binary_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $factorio).Hash
  }
  baseline = [ordered]@{
    version = $FromVersion
    archive = (Split-Path -Leaf $from)
    archive_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $from).Hash
  }
  candidate = [ordered]@{
    version = $ToVersion
    archive = (Split-Path -Leaf $to)
    archive_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $to).Hash
  }
  required_archetypes = @($cases | ForEach-Object { [string]$_.id })
  retention = $Retention
  expanded_roots_removed = @($rows | Where-Object expanded_root_disposition -eq 'removed').Count
  expanded_roots_retained = @($rows | Where-Object expanded_root_disposition -eq 'retained').Count
  rows = $rows
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $output -Encoding UTF8

Write-Host "[ok] MIR upgrade matrix: $output"
