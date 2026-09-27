# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42IndependentEvidenceRehash.ps1')
$fixtureRoot = Join-Path $repo ('build/test-results/mir42-nine-entrypoint-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
try {
  # A valid, self-hashed four-target manifest and exactly four keyed maps.
  # Structural fixture only: no engine, qualification, signing or release claim.
  $manifest = [pscustomobject][ordered]@{
    schema=1;kind='MIR42FourTargetDeterministicCandidateManifestV1'
    status='private-deterministic-four-target-candidate-built-unqualified';build_complete=$true
    source=[pscustomobject][ordered]@{commit=('a' * 40);tree=('b' * 40)}
    package_authority_sha256=('C' * 64);package_source_sha256=('D' * 64)
    target_authority=@(foreach ($target in $script:MIR42QualificationTargets) {
      [pscustomobject][ordered]@{target=$target;target_id=('factorio-' + $script:MIR42QualificationLines[$target]);source_version='4.2.0';distribution_version=('4.2.' + $target.Substring(1) + '00')}
    })
    resource_admission=[pscustomobject][ordered]@{admitted=$true;minimum_free_memory_bytes=1;minimum_free_work_bytes=1}
    targets=@(foreach ($target in $script:MIR42QualificationTargets) {
      $version='4.2.' + $target.Substring(1) + '00'
      [pscustomobject][ordered]@{
        target=$target;distribution_version=$version;target_row_path=('target-rows/' + $target + '.json')
        asset=[pscustomobject][ordered]@{path=('assets/' + $target + '/more-infinite-research_' + $version + '.zip');bytes=1;sha256=('E' * 64)}
        content_sha256=('F' * 64);entry_count=1
      }
    })
    failures=@();qualification='not-performed';technical_seal='not-performed';signing='not-performed';tagging='not-performed'
    publication_authorized=$false;record_sha256=''
  }
  $manifestPath=Join-Path $fixtureRoot 'candidate-manifest.json'
  Write-MIR4BootstrapRecord -Record $manifest -Path $manifestPath | Out-Null
  if (-not (Get-Content -Raw -LiteralPath $manifestPath | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir42-four-target-deterministic-candidate-manifest-v1.schema.json'))) { throw '[mir42-nine-entrypoint-invalid-fixture]' }
  $maps=@{}
  foreach ($target in $script:MIR42QualificationTargets) { $maps[$target]=Join-Path $fixtureRoot ($target + '.zip') }
  foreach ($entry in @(
    @{name='reconciliation-function';command='Invoke-MIR42NineTargetEvidenceReconciliation';rehash=$false;code='[mir42-reconciliation-entrypoint-target-scope]'},
    @{name='rehash-function';command='Invoke-MIR42NineTargetIndependentEvidenceRehash';rehash=$true;code='[mir42-independent-entrypoint-target-scope]'},
    @{name='reconciliation-command';command=(Join-Path $repo 'tools/commands/release/Invoke-MIR42NineTargetEvidenceReconciliation.ps1');rehash=$false;code='[mir42-reconciliation-entrypoint-target-scope]'},
    @{name='rehash-command';command=(Join-Path $repo 'tools/commands/release/Invoke-MIR42NineTargetIndependentEvidenceRehash.ps1');rehash=$true;code='[mir42-independent-entrypoint-target-scope]'}
  )) {
    $outputRoot=Join-Path $fixtureRoot $entry.name
    $arguments=@{RepoRoot=$repo;CandidateManifestPath=$manifestPath;PredecessorZips=$maps;UpgradeReceipts=$maps;OutputRoot=$outputRoot}
    if ($entry.rehash) { $arguments.QualificationPath=$manifestPath }
    $rejected=$false
    try { & $entry.command @arguments | Out-Null } catch { $rejected=$_.Exception.Message -ceq $entry.code }
    if (-not $rejected -or (Test-Path -LiteralPath $outputRoot)) { throw ('[mir42-nine-entrypoint-scope-or-output] ' + $entry.name) }
  }
  Write-Output 'MIR42-NINE-TARGET-ENTRYPOINT-SCOPE-PASSED rejected=4 output_writes=0 engines=0'
} finally {
  $buildRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build'))
  if (-not $fixtureRoot.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-nine-entrypoint-fixture-containment]' }
  if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
