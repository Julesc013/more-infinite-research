# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')
& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M41ToM42ComposableSourceSuccessionV4Authority.ps1') -RepoRoot $repo -Check | Out-Null
$result=Test-MIR4M41ToM42ComposableSourceSuccession -RepoRoot $repo
if([string]$result.status-cne'passed-historical-mir41-to-current-mir42-proof-input-control-plane-succession'-or[bool]$result.current_release_operations_authorized-or-not[bool]$result.factorio_one_exact_engine_proof_required){throw '[mir4-m41-m42-succession-v4-positive]'}
$record=Get-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $repo
if([string]$record.predecessor.record_sha256-cne'387ECBA18CB90C6F92D6C4D8FA76EF54E85FB21278F93EFD455A55CA7998FA53'-or
   [string]$record.current.package_source_sha256-cne'A476DDAFA5AB62BD6AEC69054E1A162C570DDB946520AF9234FC8FE0D79BEC2F'-or
   [string]$record.current.tooling_inventory_predecessor_sha256-cne'59F98A68D36A085DEDF47B9B60AA8C4157BF6BB9A7A0D3FB4331B0DC772BF35D'-or
   @($record.evolved_bindings).Count-ne16){throw '[mir4-m41-m42-succession-v4-predecessor-or-binding-count]'}
$policy=Get-MIR4M41ToM42ComposableSourceSuccessionV4Policy
foreach($expected in @($policy.control_plane_bindings)){
  $binding=@($record.evolved_bindings|Where-Object{[string]$_.path-ceq[string]$expected.path})
  if($binding.Count-ne1-or[string]$binding[0].previous_sha256-cne[string]$expected.previous_sha256-or
     [string]$binding[0].current_sha256-notmatch'^[A-F0-9]{64}$'-or
     [string]$binding[0].hash_mode-cne'canonical-text-v1'-or[bool]$binding[0].package_visible-or[bool]$binding[0].release_authority){throw "[mir4-m41-m42-succession-v4-binding] $($expected.path)"}
}
$tampered=$record|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String
$tampered.transition_gate.publication=$true;$tampered.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $tampered
$rejected=$false;try{Test-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $repo -SuccessionRecord $tampered|Out-Null}catch{$rejected=$_.Exception.Message-match'v4-gate'}
if(-not$rejected){throw '[mir4-m41-m42-succession-v4-negative-gate]'}
$tampered=$record|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String
$tampered.current.package_source_sha256='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';$tampered.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $tampered
$rejected=$false;try{Test-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $repo -SuccessionRecord $tampered|Out-Null}catch{$rejected=$_.Exception.Message-match'v4-historical-integrity'}
if(-not$rejected){throw '[mir4-m41-m42-succession-v4-negative-package-binding]'}
[pscustomobject][ordered]@{status='passed';test_id='static.mir4-m41-to-m42-composable-source-succession-v4';exact_engine_proof_required=$true;release_authority=$false;record_sha256=[string]$record.record_sha256}|ConvertTo-Json -Compress
