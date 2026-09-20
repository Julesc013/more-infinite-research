# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')
Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check | Out-Null
& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M41ToM42ComposableSourceSuccessionV4Authority.ps1') -RepoRoot $repo -Check | Out-Null
$result=Test-MIR4M41ToM42ComposableSourceSuccession -RepoRoot $repo
if([string]$result.status-cne'passed-historical-mir41-to-current-mir42-proof-input-control-plane-succession'-or[bool]$result.current_release_operations_authorized-or-not[bool]$result.factorio_one_exact_engine_proof_required){throw '[mir4-m41-m42-succession-v4-positive]'}
$record=Get-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $repo
if([string]$record.record_sha256-cne'F4C9D487B5E1A304978020391069DC7EE8BF84C0FB5946C87E78B45C033CCEFB'-or
   [string]$record.predecessor.record_sha256-cne'387ECBA18CB90C6F92D6C4D8FA76EF54E85FB21278F93EFD455A55CA7998FA53'-or
   [string]$record.current.package_source_sha256-cne'A476DDAFA5AB62BD6AEC69054E1A162C570DDB946520AF9234FC8FE0D79BEC2F'-or
   [string]$record.current.tooling_inventory_predecessor_sha256-cne'59F98A68D36A085DEDF47B9B60AA8C4157BF6BB9A7A0D3FB4331B0DC772BF35D'-or
   @($record.evolved_bindings).Count-ne16){throw '[mir4-m41-m42-succession-v4-predecessor-or-binding-count]'}
$policy=Get-MIR4M41ToM42ComposableSourceSuccessionV4Policy
foreach($expected in @($policy.control_plane_bindings)){
  $binding=@($record.evolved_bindings|Where-Object{[string]$_.path-ceq[string]$expected.path})
  if($binding.Count-ne1-or[string]$binding[0].previous_sha256-cne[string]$expected.previous_sha256-or
     [string]$binding[0].hash_mode-cne'canonical-text-v1'-or[bool]$binding[0].package_visible-or[bool]$binding[0].release_authority){throw "[mir4-m41-m42-succession-v4-binding] $($expected.path)"}
}

function Copy-MIR4V4Record { return $record|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String }
function Assert-MIR4V4RejectedByBothPaths([string]$Name,[scriptblock]$Mutation){
  $tampered=Copy-MIR4V4Record
  & $Mutation $tampered
  $tampered.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $tampered
  $directRejected=$false
  try{Test-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $repo -SuccessionRecord $tampered|Out-Null}catch{$directRejected=$_.Exception.Message-match'mir4-m41-m42-succession-v4-record'}
  if(-not$directRejected){throw "[mir4-m41-m42-succession-v4-negative-direct-$Name]"}
  $path=Join-Path $negativeRoot 'assurance/repository/mir4-m41-to-m42-composable-source-succession-v4.json'
  [IO.File]::WriteAllText($path,(ConvertTo-MIR4BootstrapCanonicalJson -Value $tampered)+[char]10,[Text.UTF8Encoding]::new($false))
  $diskRejected=$false
  try{Get-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $negativeRoot|Out-Null}catch{$diskRejected=$_.Exception.Message-match'mir4-m41-m42-succession-v4-record'}
  if(-not$diskRejected){throw "[mir4-m41-m42-succession-v4-negative-disk-$Name]"}
}
$negativeRoot=Join-Path ([IO.Path]::GetTempPath()) ('mir-v4-record-negatives-'+[guid]::NewGuid().ToString('N'))
try{
  & git clone --quiet --shared --no-checkout $repo $negativeRoot
  if($LASTEXITCODE-ne0){throw '[mir4-m41-m42-succession-v4-negative-clone]'}
  & git -C $negativeRoot checkout --quiet HEAD
  if($LASTEXITCODE-ne0){throw '[mir4-m41-m42-succession-v4-negative-checkout]'}
  . (Join-Path $negativeRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
  . (Join-Path $negativeRoot 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')
  Assert-MIR4V4RejectedByBothPaths 'altered-rehashed' {param($value)$value.recorded_at='2026-09-16T12:31:00+10:00'}
  Assert-MIR4V4RejectedByBothPaths 'substituted-predecessor' {param($value)$value.predecessor.record_sha256='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'}
  Assert-MIR4V4RejectedByBothPaths 'missing-binding' {param($value)$value.evolved_bindings=@($value.evolved_bindings|Select-Object -Skip 1)}
  Assert-MIR4V4RejectedByBothPaths 'duplicated-binding' {param($value)$items=@($value.evolved_bindings);$items[$items.Count-1]=$items[0];$value.evolved_bindings=$items}
  Assert-MIR4V4RejectedByBothPaths 'wrong-current-binding' {param($value)$value.current.package_authority.record_sha256='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'}
  Assert-MIR4V4RejectedByBothPaths 'unauthorized-gate' {param($value)$value.transition_gate.publication=$true}
}finally{
  if(Test-Path -LiteralPath $negativeRoot){Remove-Item -LiteralPath $negativeRoot -Recurse -Force}
}
[pscustomobject][ordered]@{status='passed';test_id='static.mir4-m41-to-m42-composable-source-succession-v4';exact_engine_proof_required=$true;release_authority=$false;record_sha256=[string]$record.record_sha256}|ConvertTo-Json -Compress
