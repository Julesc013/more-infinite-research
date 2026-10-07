# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [Parameter(Mandatory)][string]$CandidateZip,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [ValidateSet('2.0','2.1')][string]$Target='2.1',
  [switch]$Enabled,
  [string]$OutputRoot='build/p/passive-repair',
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120
)
$ErrorActionPreference='Stop'
$resources=$null;$lease=$null
# Native execution is retired; the preserved oracle is not current acceptance.
throw '[mir-native-obsolete-runner] This native runner still materializes a mod directory. Use a migrated direct-library consumer; retain this scenario and its historical evidence until conversion. No engine or staging was started.'
$harnessHash=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
$resources=$null;$lease=$null
trap {
  $failure=$_
  if($null-ne$lease -and -not$lease.closed){
    try{$null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed}catch{Write-Warning ('Passive repair input cleanup failed: '+$_.Exception.Message)}
  }
  if($null-ne$resources -and (Test-Path -LiteralPath $resources.root)){
    try{Write-MIRNativeProbeResult -Context $resources -Record ([ordered]@{status='failed';scope='passive-repair-host-probe';error=$failure.Exception.Message;resource_runs=$resources.runs.ToArray()})}catch{Write-Warning ('Passive repair failure receipt could not be written: '+$_.Exception.Message)}
  }
  throw $failure
}
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -RepoRoot $repo -MaxScanSeconds 3 -MaxEntriesPerRoot 400 | Out-Host
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
if(@(Get-Process -Name factorio -ErrorAction SilentlyContinue).Count){throw 'Passive repair requires the one-Factorio-process policy.'}
$run=$resources.root
New-Item -ItemType Directory -Path $run | Out-Null
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$candidate=(Resolve-Path -LiteralPath $CandidateZip).Path
$versionRun=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments @('--version') -TimeoutSeconds 30
$version=(Get-Content -Raw -LiteralPath $versionRun.stdout).Trim()
if($version -notmatch ('Version: '+[regex]::Escape($Target)+'[.]')){throw 'Passive repair requires the selected engine line.'}
$candidateHash=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
$manifest=Get-Content -Raw -LiteralPath (Join-Path $repo 'source/package-source.json') | ConvertFrom-Json -Depth 100
$targetId=if($Target -ceq '2.1'){'f210'}else{'f200'}
$binding=@($manifest.bindings | Where-Object {$_.output_path -ceq 'prototypes/mir/runtime/effects/passive_repair.lua' -and ($targetId -in $_.target_scope)})
if($binding.Count -ne 1){throw 'Selected target has no unique passive repair source binding.'}
$archive=[IO.Compression.ZipFile]::OpenRead($candidate)
try{
  $entries=@($archive.Entries | Where-Object {$_.FullName -like 'more-infinite-research_*/prototypes/mir/runtime/effects/passive_repair.lua'})
  if($entries.Count -ne 1){throw 'Candidate has no unique passive repair module entry.'}
  $stream=$entries[0].Open()
  try{$serviceHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
  if($serviceHash -cne $binding[0].output_sha256 -or $entries[0].Length -ne $binding[0].output_bytes){throw 'Candidate passive repair module does not match selected canonical source binding.'}
}finally{$archive.Dispose()}
$mods=Join-Path $run 'mods'
function New-PassiveRepairInputLease([string]$Candidate,[string]$ExpectedSha256,[string]$RunRoot,[string]$ModsDirectory){
  $inputs=@([ordered]@{source_path=$Candidate;file_name=[IO.Path]::GetFileName($Candidate);expected_sha256=$ExpectedSha256;role='candidate';identity=@{file_name=[IO.Path]::GetFileName($Candidate)};immutable=$true;provenance=@{kind='selected-native-passive-repair-candidate'}})
  New-MIRImmutableInputLease -RunRoot $RunRoot -StageDirectory $ModsDirectory -Inputs $inputs -RequireHardLinks
}
$lease=New-PassiveRepairInputLease -Candidate $candidate -ExpectedSha256 $candidateHash -RunRoot $run -ModsDirectory $mods
Add-MIRNativeProbeImmutableLease -Context $resources -Lease $lease
$fixture=Join-Path $mods 'mir-passive-repair-test_1.0.0'
New-Item -ItemType Directory -Force -Path $fixture | Out-Null
@{name='mir-passive-repair-test';version='1.0.0';title='MIR native passive repair acceptance';author='MIR';factorio_version=$Target;dependencies=@('base','more-infinite-research')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $fixture 'info.json')
Copy-Item -LiteralPath (Join-Path $repo 'tests/runtime/passive_repair_host_probe.lua') -Destination (Join-Path $fixture 'control.lua')
('return {enabled='+ $(if($Enabled){'true'}else{'false'}) +'}') | Set-Content -LiteralPath (Join-Path $fixture 'probe_options.lua')
if($Enabled){'data.raw["bool-setting"]["mir-enable-passive-repair"].default_value=true' | Set-Content -LiteralPath (Join-Path $fixture 'settings-updates.lua')}
@{mods=@(@{name='base';enabled=$true},@{name='space-age';enabled=$false},@{name='elevated-rails';enabled=$false},@{name='quality';enabled=$false},@{name='more-infinite-research';enabled=$true},@{name='mir-passive-repair-test';enabled=$true})} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $mods 'mod-list.json')
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n[other]`ndisable-blueprint-storage=true`nenable-blueprint-storage-cloud-sync=false`n" | Set-Content -LiteralPath (Join-Path $run 'config.ini')
function Invoke-ProbeEngine([string]$Label,[string[]]$Arguments){
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -TimeoutSeconds 60 `
    -Arguments (@('--config',(Join-Path $run 'config.ini'),'--mod-directory',$mods)+$Arguments)
  $log=(Get-Content -Raw -LiteralPath $actor.stdout)+(Get-Content -Raw -LiteralPath $actor.stderr)
  [IO.File]::WriteAllText((Join-Path $run ($Label+'.log')),$log,[Text.UTF8Encoding]::new($false))
  if($log -match 'non-recoverable error|Exception at tick|Error while running event'){throw "Passive repair $Label failed: $run`n$($log.Substring([Math]::Max(0,$log.Length-2000)))"}
}
$save=Join-Path $run 'probe.zip'
Invoke-ProbeEngine 'create' @('--create',$save)
if($Enabled){
  Invoke-ProbeEngine 'pending-save' @('--benchmark-graphics',$save,'--benchmark-ticks','180','--disable-audio','--window-size','1024x768')
  $pending=Join-Path $run 'userdata/saves/_autosave-mir-passive-repair-pending.zip'
  if(-not(Test-Path -LiteralPath $pending)){throw "Pending queue save missing: $run"}
  Invoke-ProbeEngine 'pending-reload' @('--benchmark-graphics',$pending,'--benchmark-ticks','610','--disable-audio','--window-size','1024x768')
  $healing=Join-Path $run 'userdata/saves/_autosave-mir-passive-repair-healing.zip'
  if(-not(Test-Path -LiteralPath $healing)){throw "Healing queue save missing: $run"}
  Invoke-ProbeEngine 'healing-reload' @('--benchmark',$healing,'--benchmark-ticks','130','--benchmark-runs','1')
  $phases=@('pending-reload','healing-reload')
}else{
  Invoke-ProbeEngine 'disabled' @('--benchmark',$save,'--benchmark-ticks','723','--benchmark-runs','1')
  $phases=@('disabled')
}
$rows=@(foreach($phase in $phases){
  $resultPath=Join-Path $run ('userdata/script-output/passive-repair-host-'+$phase+'.json')
  $row=Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
  if($row.status -cne 'passed' -or $row.enabled -ne [bool]$Enabled){throw "Passive repair phase did not pass: $phase"}
  $row
})
if((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -cne $candidateHash){throw 'Candidate changed during passive repair acceptance.'}
if((Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash -cne $harnessHash){throw 'Passive repair harness changed during acceptance.'}
$receipt=[ordered]@{status='passed';scope='materialized-native-host-base-profile-not-overhaul-or-two-client-multiplayer';target=$Target;enabled=[bool]$Enabled;engine=$version;engine_sha256=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash;candidate_sha256=$candidateHash;service_sha256=$serviceHash;fixture_sha256=(Get-FileHash -LiteralPath (Join-Path $fixture 'control.lua') -Algorithm SHA256).Hash;harness_sha256=$harnessHash;phases=$rows}
$terminal=Complete-MIRImmutableInputLease -Lease $lease -Outcome passed
$receipt['immutable_inputs']=$terminal
$receipt['resource_runs']=$resources.runs.ToArray()
$receipt['resource_policy']=[ordered]@{declared_peak_memory_mib=$ExpectedPeakMemoryMiB;max_new_output_mib=$MaxNewOutputMiB;memory_enforcement='sampled-watchdog-not-hard-cap'}
Write-MIRNativeProbeResult -Context $resources -Record $receipt
$receipt | ConvertTo-Json -Depth 8
"Evidence: $run"
