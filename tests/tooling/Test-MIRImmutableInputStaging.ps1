# Current MIR5 immutable-input lease controls. No package or engine is used.
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/ImmutableInputStaging.ps1')
$root=Join-Path $repo ('build/tmp/mir5-immutable-input-controls-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Assert-Stage([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir5-immutable-$Code]"};$script:checks++}
function Refuses-Stage([scriptblock]$Action,[string]$Expected){$actual='';try{&$Action|Out-Null}catch{$actual=$_.Exception.Message};if(-not$actual.Contains($Expected)){throw "[mir5-immutable-refusal] expected=$Expected actual=$actual"};$script:checks++}
try {
  $sourceDir=Join-Path $root 'inputs';$run=Join-Path $root 'run';$invalidRun=Join-Path $root 'invalid-run';$externalRun=Join-Path $root 'external-run';$mutationRun=Join-Path $root 'mutation-run'
  [IO.Directory]::CreateDirectory($sourceDir)|Out-Null;[IO.Directory]::CreateDirectory($run)|Out-Null;[IO.Directory]::CreateDirectory($invalidRun)|Out-Null;[IO.Directory]::CreateDirectory($externalRun)|Out-Null;[IO.Directory]::CreateDirectory($mutationRun)|Out-Null
  $source=Join-Path $sourceDir 'input.zip';[IO.File]::WriteAllText($source,'immutable lease control',[Text.UTF8Encoding]::new($false))
  $leaseInput=[ordered]@{source_path=$source;file_name='input.zip';expected_sha256=Get-MIRImmutableInputSha256 $source;role='dependency';identity=@{name='input'};provenance=@{kind='control'};immutable=$true}
  Refuses-Stage {New-MIRImmutableInputLease -RunRoot $invalidRun -StageDirectory (Join-Path $invalidRun 'copy') -Inputs @($leaseInput) -ForceCopy -RequireHardLinks} 'Strict immutable staging cannot request copy mode.'
  $bad=[ordered]@{};foreach($key in $leaseInput.Keys){$bad[$key]=$leaseInput[$key]};$bad.immutable=$false
  Refuses-Stage {New-MIRImmutableInputLease -RunRoot $invalidRun -StageDirectory (Join-Path $invalidRun 'not-immutable') -Inputs @($bad) -RequireHardLinks} 'Strict immutable staging requires immutable input declarations.'
  $lease=New-MIRImmutableInputLease -RunRoot $run -StageDirectory (Join-Path $run 'mods') -Inputs @($leaseInput) -RequireHardLinks
  try {
    $stage=Join-Path $run 'mods/input.zip'
    Assert-Stage ($lease.record.require_hard_links-and$lease.record.inputs.Count-eq1-and$lease.record.inputs[0].staging_mode-ceq'hardlink') 'strict-stage-mode'
    Assert-Stage ((Get-MIRImmutableInputFileIdentity $source)-ceq(Get-MIRImmutableInputFileIdentity $stage)) 'hardlink-identity'
    $receipt=Get-MIRImmutableInputLeaseReceipt -Lease $lease
    Assert-Stage ([bool]$receipt.inputs_sha256_match-and$receipt.state-ceq'receipt-captured') 'active-receipt'
    $terminal=Complete-MIRImmutableInputLease -Lease $lease
    $null=Assert-MIRImmutableInputTerminalReceipt -Receipt $terminal
    Assert-Stage ($terminal.outcome-ceq'passed'-and$lease.closed) 'terminal-receipt'
  } finally {if($null-ne$lease-and-not$lease.closed){Complete-MIRImmutableInputLease -Lease $lease -Outcome failed|Out-Null}}
  $mutationSource=Join-Path $sourceDir 'mutation.zip';[IO.File]::WriteAllText($mutationSource,'mutation control',[Text.UTF8Encoding]::new($false))
  $mutationInput=[ordered]@{source_path=$mutationSource;file_name='mutation.zip';expected_sha256=Get-MIRImmutableInputSha256 $mutationSource;role='dependency';identity=@{name='mutation'};provenance=@{kind='control'};immutable=$true}
  $mutationLease=New-MIRImmutableInputLease -RunRoot $mutationRun -StageDirectory (Join-Path $mutationRun 'mods') -Inputs @($mutationInput) -RequireHardLinks
  try {
    $mutationStage=Join-Path $mutationRun 'mods/mutation.zip';$writeBlocked=$false
    try {[IO.File]::WriteAllText($mutationStage,'blocked mutation',[Text.UTF8Encoding]::new($false))}catch [IO.IOException]{$writeBlocked=$true}
    Assert-Stage $writeBlocked 'active-lease-write-blocked'
    # The operating-system lock normally prevents this state. Release only the
    # test lease handles to prove receipt verification still refuses a bypassed
    # mutation and never records a successful terminal disposition.
    foreach($handle in @($mutationLease.source_handles)+@($mutationLease.staged_handles)){$handle.Dispose()}
    [IO.File]::WriteAllText($mutationStage,'bypassed mutation',[Text.UTF8Encoding]::new($false))
    $mutationFailure='';try{Complete-MIRImmutableInputLease -Lease $mutationLease -Outcome failed|Out-Null}catch{$mutationFailure=$_.Exception.Message}
    Assert-Stage ($mutationFailure.Contains('detected an input mutation before its receipt could be captured')) 'mutation-receipt-refusal'
    $mutationRecord=Get-Content -Raw -LiteralPath (Join-Path $mutationRun 'mir-immutable-input-lease.json')|ConvertFrom-Json -Depth 20
    Assert-Stage ($mutationRecord.state-ceq'receipt-captured'-and-not[bool]$mutationRecord.inputs_sha256_match-and$null-eq$mutationRecord.PSObject.Properties['outcome']) 'mutation-no-success'
  } finally {if($null-ne$mutationLease-and-not$mutationLease.closed){Close-MIRImmutableInputLeaseHandles -Lease $mutationLease}}
  $outside=Join-Path ([IO.Path]::GetTempPath()) ('mir5-immutable-outside-'+[guid]::NewGuid().ToString('N')+'.zip')
  try {[IO.File]::WriteAllText($outside,'outside',[Text.UTF8Encoding]::new($false));$external=[ordered]@{};foreach($key in $leaseInput.Keys){$external[$key]=$leaseInput[$key]};$external.source_path=$outside;$external.expected_sha256=Get-MIRImmutableInputSha256 $outside;Refuses-Stage {New-MIRImmutableInputLease -RunRoot $externalRun -StageDirectory (Join-Path $externalRun 'external') -Inputs @($external) -RequireHardLinks} '[mir-hardlink-outside-checkout]'} finally {if(Test-Path -LiteralPath $outside){Remove-Item -LiteralPath $outside -Force}}
  [pscustomobject]@{status='passed';checks=$checks;native_execution=$false;package_materialization=$false}|ConvertTo-Json -Compress
} finally {
  $admitted=[IO.Path]::GetFullPath((Join-Path $repo 'build/tmp')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
  $actual=[IO.Path]::GetFullPath($root)
  if(-not$actual.StartsWith($admitted,[StringComparison]::OrdinalIgnoreCase)){throw '[mir5-immutable-cleanup-boundary]'}
  if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Force -Recurse}
}
