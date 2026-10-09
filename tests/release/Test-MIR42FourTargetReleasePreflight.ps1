# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')

function Assert-MIR42PreflightTest([bool]$Condition,[string]$Code) { if (-not $Condition) { throw "[$Code]" } }
function New-MIR42PreflightTestZip {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Target,[switch]$IncludeForbidden)
  $lines = [ordered]@{f210='2.1';f200='2.0';f110='1.1';f100='1.0';f017='0.17';f016='0.16';f015='0.15';f014='0.14';f013='0.13'}
  $codes = [ordered]@{f210='210';f200='200';f110='110';f100='100';f017='017';f016='016';f015='015';f014='014';f013='013'}
  $version = "4.2.$($codes[$Target])00"
  $package = Join-Path $Root "stage/more-infinite-research_$version"
  New-Item -ItemType Directory -Force -Path $package | Out-Null
  $info = [ordered]@{name='more-infinite-research';version=$version;factorio_version=$lines[$Target];title='Test'}
  [IO.File]::WriteAllText((Join-Path $package 'info.json'),($info | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $package 'data.lua'),'return {}',[Text.UTF8Encoding]::new($false))
  if ($IncludeForbidden) { New-Item -ItemType Directory -Force -Path (Join-Path $package 'docs') | Out-Null; [IO.File]::WriteAllText((Join-Path $package 'docs/private.md'),'no',[Text.UTF8Encoding]::new($false)) }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = Join-Path $Root "more-infinite-research_$version.zip"
  [IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $Root 'stage'),$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
  return $zip
}

$root = Join-Path $repo ("build/test-results/mir42-four-target-preflight-" + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $zips = [ordered]@{}
  foreach ($target in @('f210','f200','f110','f100')) { $zips[$target] = New-MIR42PreflightTestZip -Root (Join-Path $root $target) -Target $target }
  $historicalZips = @{}
  foreach ($target in @('f017','f016','f015','f014','f013')) { $historicalZips[$target] = New-MIR42PreflightTestZip -Root (Join-Path $root $target) -Target $target }
  $historicalInputs = @(Get-MIR42HistoricalZipInputs -HistoricalZips $historicalZips)
  Assert-MIR42PreflightTest ((@($historicalInputs.target) -join '|') -ceq 'f017|f016|f015|f014|f013') 'mir42-preflight-historical-input-order'
  $historicalIdentity = Get-MIR42ReleaseTargetIdentity -RepoRoot $repo -Target f017
  Assert-MIR42PreflightTest (([string]$historicalIdentity.target_record_record_sha256 -match '^[A-Fa-f0-9]{64}$') -and ([string]$historicalIdentity.target_record_file_sha256 -match '^[A-Fa-f0-9]{64}$') -and ([string]$historicalIdentity.target_record_record_sha256 -cne [string]$historicalIdentity.target_record_file_sha256)) 'mir42-preflight-historical-record-hash-contract'
  foreach ($input in $historicalInputs) {
    $archive = Get-MIR42FourTargetArchiveInput -RepoRoot $repo -Target ([string]$input.target) -Path ([string]$input.path)
    Assert-MIR42PreflightTest ([string]$archive.target_id -ceq ('factorio-' + [string]$archive.factorio_line) -and [string]$archive.distribution_version -match '^4[.]2[.]0(?:17|16|15|14|13)00$') "mir42-preflight-historical-identity-$($input.target)"
  }
  $partialHistoricalRejected = $false
  try { Get-MIR42HistoricalZipInputs -HistoricalZips @{f017=$historicalZips.f017;f016=$historicalZips.f016;f015=$historicalZips.f015;f014=$historicalZips.f014} | Out-Null } catch { $partialHistoricalRejected = $_.Exception.Message -match 'mir42-preflight-historical-target-set' }
  Assert-MIR42PreflightTest $partialHistoricalRejected 'mir42-preflight-historical-partial-rejected'
  $unknownHistoricalRejected = $false
  try { Get-MIR42HistoricalZipInputs -HistoricalZips @{f017=$historicalZips.f017;f016=$historicalZips.f016;f015=$historicalZips.f015;f014=$historicalZips.f014;f999=$historicalZips.f013} | Out-Null } catch { $unknownHistoricalRejected = $_.Exception.Message -match 'mir42-preflight-historical-target-set' }
  Assert-MIR42PreflightTest $unknownHistoricalRejected 'mir42-preflight-historical-unknown-rejected'
  $head = (& git -C $repo rev-parse HEAD).Trim()
  $result = (& (Join-Path $repo 'tools/commands/release/Invoke-MIR42FourTargetReleasePreflight.ps1') -RepoRoot $repo -FinalSourceCommit $head -F210Zip $zips.f210 -F200Zip $zips.f200 -F110Zip $zips.f110 -F100Zip $zips.f100 -HistoricalZips $historicalZips -OutputRoot (Join-Path $root 'result')) | ConvertFrom-Json -Depth 20 -DateKind String
  Assert-MIR42PreflightTest ([string]$result.status -ceq 'MIR-4.2-NINE-TARGET-TECHNICAL-READINESS-NOT-READY') 'mir42-preflight-status'
  $candidateText = Get-Content -Raw -LiteralPath $result.candidate_manifest
  $candidate = $candidateText | ConvertFrom-Json -Depth 100 -DateKind String
  $readinessText = Get-Content -Raw -LiteralPath $result.technical_readiness
  $readiness = $readinessText | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR42PreflightTest ($candidateText | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir42-four-target-candidate-manifest-v1.schema.json')) 'mir42-preflight-candidate-schema'
  Assert-MIR42PreflightTest ($readinessText | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir42-four-target-technical-readiness-v1.schema.json')) 'mir42-preflight-readiness-schema'
  Assert-MIR42PreflightTest ((Test-MIR4BootstrapRecordHash -Record $candidate) -and (Test-MIR4BootstrapRecordHash -Record $readiness)) 'mir42-preflight-self-hashes'
  Assert-MIR42PreflightTest ((@($candidate.targets.target) -join '|') -ceq 'f210|f200|f110|f100|f017|f016|f015|f014|f013') 'mir42-preflight-target-order'
  Assert-MIR42PreflightTest ((@($candidate.targets.distribution_version) -join '|') -ceq '4.2.21000|4.2.20000|4.2.11000|4.2.10000|4.2.01700|4.2.01600|4.2.01500|4.2.01400|4.2.01300') 'mir42-preflight-versions'
  Assert-MIR42PreflightTest ([string]$candidate.archive_source_provenance -ceq 'unproven-by-zip-inputs' -and $null -eq $candidate.candidate_id -and -not [bool]$candidate.release_transition_authorized) 'mir42-preflight-no-candidate-allocation'
  Assert-MIR42PreflightTest (@($readiness.target_qualification | Where-Object status -ne 'not-run').Count -eq 0 -and @($readiness.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0 -and -not [bool]$readiness.production_authorized) 'mir42-preflight-gates-closed'
  $legacyResult = (& (Join-Path $repo 'tools/commands/release/Invoke-MIR42FourTargetReleasePreflight.ps1') -RepoRoot $repo -FinalSourceCommit $head -F210Zip $zips.f210 -F200Zip $zips.f200 -F110Zip $zips.f110 -F100Zip $zips.f100 -OutputRoot (Join-Path $root 'result-four')) | ConvertFrom-Json -Depth 20 -DateKind String
  $legacyCandidate = Get-Content -Raw -LiteralPath $legacyResult.candidate_manifest | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR42PreflightTest ([string]$legacyResult.status -ceq 'MIR-4.2-FOUR-TARGET-TECHNICAL-READINESS-NOT-READY' -and @($legacyCandidate.targets).Count -eq 4 -and [string]$legacyCandidate.status -ceq 'MIR-4.2-FOUR-TARGET-CANDIDATE-INPUTS-BOUND-UNQUALIFIED') 'mir42-preflight-four-target-contract-retained'
  $sourceRejected = $false
  try { Invoke-MIR42FourTargetReleasePreflight -RepoRoot $repo -FinalSourceCommit ('0' * 40) -F210Zip $zips.f210 -F200Zip $zips.f200 -F110Zip $zips.f110 -F100Zip $zips.f100 -OutputRoot (Join-Path $root 'source-mismatch-result') | Out-Null } catch { $sourceRejected = $_.Exception.Message -match 'mir42-preflight-final-source-commit' }
  Assert-MIR42PreflightTest $sourceRejected 'mir42-preflight-final-source-rejected'
  $bad = New-MIR42PreflightTestZip -Root (Join-Path $root 'bad') -Target f100 -IncludeForbidden
  $rejected = $false
  try { Invoke-MIR42FourTargetReleasePreflight -RepoRoot $repo -FinalSourceCommit $head -F210Zip $zips.f210 -F200Zip $zips.f200 -F110Zip $zips.f110 -F100Zip $bad -OutputRoot (Join-Path $root 'bad-result') | Out-Null } catch { $rejected = $_.Exception.Message -match 'mir42-preflight-package-excluded-entry' }
  Assert-MIR42PreflightTest $rejected 'mir42-preflight-package-excluded-rejected'
  Write-Host '[ok] MIR 4.2 nine-target preflight binds exact archive inputs and keeps all qualification and release gates closed.'
} finally {
  if (Test-Path -LiteralPath $root) {
    $resolvedRoot = (Resolve-Path -LiteralPath $root).Path
    $null = Assert-MIR4DescendantPath -Root (Join-Path $repo 'build') -Path $resolvedRoot
    $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $resolvedRoot
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
  }
}
