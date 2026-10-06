# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
$assertions=0
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw "Historical inputs: $Message"};$script:assertions++}
function Refuses([scriptblock]$Action,[string]$Expected){$failure='';try{& $Action|Out-Null}catch{$failure=$_.Exception.Message};Check ($failure.Contains($Expected)) "expected $Expected; got $failure"}
function Get-MIR441ResourceSnapshot {param([string]$WorkRoot);[pscustomobject]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');memory=[pscustomobject]@{total_bytes=16GB;free_bytes=12GB;committed_bytes=4GB;commit_limit_bytes=20GB};system_volume=[pscustomobject]@{free_bytes=100GB};work_volume=[pscustomobject]@{free_bytes=100GB}}}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIR4HistoricalPrivateRuntime.ps1'),[ref]$tokens,[ref]$errors)
Check (@($errors).Count -eq 0) 'runtime harness no longer parses.'
foreach($name in @('New-MIR4HistoricalArchiveStage','Get-MIR4ArchiveInfo','Assert-MIR4RuntimeLog','Invoke-MIR4HistoricalPhase')){
  $definition=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false))
  Check ($definition.Count -eq 1) "consumed function is ambiguous: $name"
  . ([scriptblock]::Create($definition[0].Extent.Text))
}
$scratch=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo ('build/tmp/historical-input-controls-'+[guid]::NewGuid().ToString('N')))
$inputLeases=[Collections.Generic.List[object]]::new()
try {
  $null=New-Item -ItemType Directory -Path $scratch
  $authority=Get-Content -Raw (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Historical-Private-Candidate-AuthorizationV1.json')|ConvertFrom-Json
  $source=Join-Path $scratch 'tiny-shared.zip';[IO.File]::WriteAllText($source,'tiny immutable input')
  $hash=Get-MIRImmutableInputSha256 $source
  Refuses {& (Join-Path $repo 'tests/runtime/Test-MIR4HistoricalPrivateRuntime.ps1') -RepoRoot $repo -Target f017 -FactorioBin $source -CandidateZip $source -PredecessorZip $source -EvidenceRoot (Join-Path $scratch 'refused-native')} '[mir441-resource-peak-budget-required]'
  Check (-not (Test-Path (Join-Path $scratch 'refused-native'))) 'missing native budget created staging.'
  $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $scratch -ExpectedPeakMemoryMiB 256 -MaxNewOutputMiB 4
  $null=New-Item -ItemType Directory -Path $resources.root
  $stages=[Collections.Generic.List[object]]::new()
  foreach($Target in @('f017','f016','f015','f014','f013')){
    $EvidenceRoot=Join-Path $resources.root $Target
    $row=@($authority.targets|Where-Object target_key -CEQ $Target)[0]
    foreach($role in @('predecessor','candidate')){
      $version=if($role -ceq 'predecessor'){$row.predecessor_release}else{$row.distribution_version}
      $stage=New-MIR4HistoricalArchiveStage -Role $role -Source $source -ExpectedSha256 $hash -Version $version;$stages.Add($stage)
      $input=$stage.lease.record.inputs[0]
      Check ($stage.lease.record.require_hard_links -and $input.staging_mode -ceq 'hardlink' -and (Get-MIRImmutableInputFileIdentity $source) -ceq (Get-MIRImmutableInputFileIdentity $input.stage_path)) "$Target $role copied its archive."
      Check ($input.role -ceq $role -and $input.identity.target -ceq $Target -and $input.identity.version -ceq $version) "$Target $role lost its original identity."
      $list=Get-Content -Raw (Join-Path $stage.mods 'mod-list.json')|ConvertFrom-Json
      Check (($list.mods.name -join ',') -ceq 'base,more-infinite-research') "$Target $role lost private enabled mods."
      [IO.File]::WriteAllText((Join-Path $stage.mods 'mod-settings.dat'),($Target+$role))
    }
    $script:archiveCopies=0
    function New-Item {[CmdletBinding()]param([string]$ItemType,[string[]]$Path,[string]$Target,[switch]$Force);if($ItemType -ceq 'HardLink'){throw 'controlled unavailable link'};Microsoft.PowerShell.Management\New-Item @PSBoundParameters}
    function Copy-Item {$script:archiveCopies++;throw 'copy attempted'}
    try{Refuses {New-MIR4HistoricalArchiveStage -Role unavailable -Source $source -ExpectedSha256 $hash -Version $row.distribution_version} 'requires a verified hard link';Check ($script:archiveCopies -eq 0) "$Target attempted archive copying."}finally{Remove-Item Function:\New-Item;Remove-Item Function:\Copy-Item}
  }
  Check (@($stages|ForEach-Object {Get-MIRImmutableInputFileIdentity (Join-Path $_.mods 'mod-settings.dat')}|Sort-Object -Unique).Count -eq 10) 'mutable settings share identities.'
  # Execute the actual predecessor-to-candidate settings transition. It must
  # preserve bytes while moving only private controls between archive stages.
  $statements=@($ast.EndBlock.Statements)
  $settingsStart=@(0..($statements.Count-1)|Where-Object {$statements[$_] -is [Management.Automation.Language.AssignmentStatementAst] -and $statements[$_].Left.Extent.Text -ceq '$startupSettings'})
  Check ($settingsStart.Count -eq 1) 'mutable transition is ambiguous.'
  $transition=[scriptblock]::Create(($statements[$settingsStart[0]..($settingsStart[0]+3)].Extent.Text -join "`n"))
  $predecessorStage=$stages[0];$candidateStage=$stages[1]
  $sourceSettings=Join-Path $predecessorStage.mods 'mod-settings.dat';$privateSettings=Join-Path $candidateStage.mods 'mod-settings.dat'
  Remove-Item -LiteralPath $privateSettings
  $mods=$predecessorStage.mods;$common=@('--config','selected private config','--mod-directory',$mods)
  . $transition
  Check ((Get-MIRImmutableInputSha256 $privateSettings) -ceq (Get-MIRImmutableInputSha256 $sourceSettings) -and (Get-MIRImmutableInputFileIdentity $privateSettings) -cne (Get-MIRImmutableInputFileIdentity $sourceSettings)) 'transition copied different bytes or shared writable settings.'
  Check (($common -join '|') -ceq ('--config|selected private config|--mod-directory|'+$candidateStage.mods)) 'transition changed original engine arguments beyond the selected mods directory.'
  [IO.File]::WriteAllText($privateSettings,'candidate rewrite')
  Check ((Get-Content -Raw $sourceSettings) -ceq 'f017predecessor') 'candidate rewrite changed predecessor settings.'
  Remove-Item -LiteralPath $sourceSettings,$privateSettings
  $mods=$predecessorStage.mods;$common=@('--config','selected private config','--mod-directory',$mods)
  . $transition
  Check (-not (Test-Path $privateSettings) -and $mods -ceq $candidateStage.mods) 'absent settings created a control file or blocked stage selection.'
  $large=[IO.File]::Create($sourceSettings);try{$large.SetLength(4MB+1)}finally{$large.Dispose()}
  $mods=$predecessorStage.mods;$common=@('--config','selected private config','--mod-directory',$mods)
  Refuses {. $transition} 'Historical mutable settings exceed their bounded allowance.'
  Check (-not (Test-Path $privateSettings)) 'oversized settings were written to the candidate stage.'
  Remove-Item -LiteralPath $sourceSettings
  $EvidenceRoot=$resources.root;$live=Join-Path $resources.root 'controlled-factorio.log';$version='4.0.01300';$display='4.0.1300';$observed=$true
  function Invoke-MIRNativeProbeFactorioProcess {
    param($Context,$FilePath,$Arguments,$TimeoutSeconds,[scriptblock]$CompletionPredicate)
    Check ($Context -eq $resources -and $FilePath -ceq 'controlled historical engine' -and $TimeoutSeconds -eq 2) 'phase lost its governed actor/timeout.'
    if($null -eq $CompletionPredicate){Check ($Arguments -contains '--create') 'creation arguments changed.';[IO.File]::WriteAllText($live,"Loading mod more-infinite-research $display");return [pscustomobject]@{result=[pscustomobject]@{exit_code=0}}}
    Check ($Arguments -contains '--start-server') 'server arguments changed.'
    Check (-not (& $CompletionPredicate)) 'completion accepted absent live log.'
    foreach($log in @("Loading mod more-infinite-research $display", "Loading mod more-infinite-research $display Map version 0.13",'Loading mod more-infinite-research 4.0.1400 Map version 0.13 Hosting game at')){[IO.File]::WriteAllText($live,$log);Check (-not (& $CompletionPredicate)) 'completion accepted missing map/hosting or another package.'}
    [IO.File]::WriteAllText($live,"Loading mod more-infinite-research $display Map version 0.13 Hosting game at");Check (& $CompletionPredicate) 'original hosting predicate rejected.'
    [IO.File]::WriteAllText($live,"Loading mod more-infinite-research $display Map version 0.13 changing state from(CreatingGame) to(InGame)");Check (& $CompletionPredicate) 'original InGame predicate rejected.'
    [IO.File]::WriteAllText($live,"Error Loading mod more-infinite-research $display Map version 0.13 Hosting game at");Refuses {& $CompletionPredicate} 'log contains a load failure'
    [IO.File]::WriteAllText($live,"Loading mod more-infinite-research $display Map version 0.13 Hosting game at")
    [pscustomobject]@{result=[pscustomobject]@{exit_code=-1;completion_predicate_observed=$observed}}
  }
  $phase=Invoke-MIR4HistoricalPhase -Name create -Arguments @('--create','controlled save') -ExpectedVersion $version -LiveLog $live -OutputRoot $EvidenceRoot -Binary 'controlled historical engine' -TimeoutMs 2000
  Check ($phase.process_exit_code -eq 0 -and -not $phase.terminated_after_proof -and $phase.log -ceq 'create.log') 'creation proof contract changed.'
  $phase=Invoke-MIR4HistoricalPhase -Name reload -Arguments @('--start-server','controlled save') -ExpectedVersion $version -LiveLog $live -OutputRoot $EvidenceRoot -Binary 'controlled historical engine' -TimeoutMs 2000 -BoundedServer
  Check ($phase.process_exit_code -eq -1 -and $phase.terminated_after_proof -and $phase.log -ceq 'reload.log') 'bounded phase proof contract changed.'
  $observed=$false;Refuses {Invoke-MIR4HistoricalPhase -Name missing -Arguments @('--start-server','controlled save') -ExpectedVersion $version -LiveLog $live -OutputRoot $EvidenceRoot -Binary 'controlled historical engine' -TimeoutMs 2000 -BoundedServer} 'did not reach a proven exact-package loaded-map state'
  foreach($stage in $stages){$terminal=Complete-MIRImmutableInputLease -Lease $stage.lease -Outcome passed;$null=Assert-MIRImmutableInputTerminalReceipt -Receipt $terminal;$null=Assert-MIRImmutableInputLeaseReclaimable -RunRoot $stage.root -Context 'completed controlled historical stage';Remove-Item -LiteralPath $stage.root -Recurse}
  Check ((Get-MIRImmutableInputSha256 $source) -ceq $hash) 'retirement changed shared source.'
  [pscustomobject]@{status='passed';assertions=$assertions;controlled_stages=10;archive_payload_bytes_copied=0;factorio_processes=0;scope='Five historical archive consumers and original loaded-map predicates; no native or release qualification'}
} finally {
  foreach($lease in $inputLeases){if(-not $lease.closed){$null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed}}
  if(Test-Path $scratch){$resolved=Resolve-MIR441RecoveryScratchPath -Path $scratch;$parent=(Resolve-Path (Join-Path $repo 'build/tmp')).Path.TrimEnd('\')+'\';if(-not $resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase)){throw 'Controlled historical cleanup escaped owned parent'};Remove-Item -LiteralPath $resolved -Recurse -Force}
}
