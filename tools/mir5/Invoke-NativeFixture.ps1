# Disposable native scenarios share only the process/library custody host.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ArchiveLibrary,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ProfilePath,
  [Parameter(Mandatory)][string[]]$FixtureSources,
  [Parameter(Mandatory)][string]$ExpectedMIRArchiveSha256,
  [Parameter(Mandatory)][string]$CaseName,
  [Parameter(Mandatory)][string]$OutputRoot,
  [ValidateRange(30,600)][int]$TimeoutSeconds=180,
  [ValidateRange(128,8192)][int]$ExpectedPeakMemoryMiB=512,
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Assert-Fixture([bool]$Condition,[string]$Message) {
  if(-not $Condition){throw "[mir5-native-fixture] $Message"}
}
function Get-FixtureSha([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function Assert-FixtureLog([string]$Text) {
  Assert-Fixture (-not [regex]::IsMatch($Text,'(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$')) 'fatal native diagnostic'
}
function Read-FixtureResult([string]$Text,[string]$Stage) {
  $rows=@([regex]::Matches($Text,'\[MIR5_NATIVE_FIXTURE\] RESULT (\{[^\r\n]+\})') | ForEach-Object {$_.Groups[1].Value | ConvertFrom-Json} | Where-Object {$_.case -ceq $CaseName -and $_.stage -ceq $Stage})
  Assert-Fixture ($rows.Count -eq 1 -and $rows[0].status -ceq 'passed') "missing unique passed $Stage witness for $CaseName"
  $rows[0]
}
function Invoke-FixtureStage([string]$Name,[string[]]$StageArguments,[scriptblock]$Completion=$null) {
  $live=Join-Path $writeData 'factorio-current.log'
  if(Test-Path -LiteralPath $live){Remove-Item -LiteralPath $live}
  $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation','--disable-audio')+$StageArguments
  Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments
  $native=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $arguments -TimeoutSeconds $TimeoutSeconds -CompletionPredicate $Completion
  $log=Join-Path $resources.root ($Name+'.factorio.log')
  Assert-Fixture (Test-Path -LiteralPath $live -PathType Leaf) "$Name native log absent"
  Copy-Item -LiteralPath $live -Destination $log
  foreach($path in @($log,$native.stdout,$native.stderr)){Assert-FixtureLog ([IO.File]::ReadAllText($path))}
  Assert-Fixture ($native.result.passed -and -not $native.result.timed_out) "$Name process failed"
  if($null -ne $Completion){
    Assert-Fixture $native.result.completion_predicate_observed "$Name exited before a live completion"
  }else{
    Assert-Fixture ($native.result.exit_code -eq 0) "$Name natural exit was not zero"
  }
  [ordered]@{process=$native;log=$log;log_sha256=Get-FixtureSha $log;loaded_selection=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation}
}

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$library=(Resolve-Path -LiteralPath $ArchiveLibrary).Path
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$engineData=Join-Path (Get-Item -LiteralPath $engine).Directory.Parent.Parent.FullName 'data'
$identityModule=New-Module -Name MIR5FixtureIdentity -ArgumentList (Join-Path $repo 'tools/lib/validation/ImmutableInputStaging.ps1') -ScriptBlock {
  param($Path)
  . $Path
  Export-ModuleMember -Function Get-MIRImmutableInputSha256,Get-MIRImmutableInputFileIdentity,Assert-MIRCheckoutHardLinkBoundary
}
Import-Module $identityModule -Force
. (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
$profile=(Resolve-Path -LiteralPath $ProfilePath).Path
$rows=@((Get-Content -LiteralPath $profile -Raw | ConvertFrom-Json -AsHashtable).mods)
$inventory=@(Get-MIRLibraryInventory -LibraryDirectory $library -EngineDataDirectory $engineData)
$mirRows=@($rows | Where-Object {$_.name -ceq 'more-infinite-research' -and $_.enabled})
Assert-Fixture ($mirRows.Count -eq 1 -and $ExpectedMIRArchiveSha256 -match '^[a-fA-F0-9]{64}$') 'one pinned MIR selection is required'
$mir=@($inventory | Where-Object {$_.name -ceq 'more-infinite-research' -and $_.version -ceq $mirRows[0].version})
Assert-Fixture ($mir.Count -eq 1 -and (Get-FixtureSha $mir[0].path) -ceq $ExpectedMIRArchiveSha256.ToUpperInvariant()) 'MIR archive hash differs'
$fixtureInputs=@()
foreach($source in $FixtureSources){
  $source=(Resolve-Path -LiteralPath $source).Path
  $info=Get-Content -LiteralPath (Join-Path $source 'info.json') -Raw | ConvertFrom-Json
  $archive=Join-Path $library ($info.name+'_'+$info.version+'.zip')
  Assert-MIRLibraryFixtureArchive -Archive $archive -SourceDirectory $source
  Assert-Fixture (@($rows | Where-Object {$_.enabled -and $_.name -ceq $info.name -and $_.version -ceq $info.version}).Count -eq 1) 'fixture is not selected exactly once'
  $fixtureInputs+=@{source=$source;archive=$archive;sha256=Get-FixtureSha $archive}
}
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 2 -MaxEntriesPerRoot 500 | Out-Host
$resources=$null;$activation=$null;$failure=$null
$record=[ordered]@{
  kind='MIR5NativeFixtureV1';status='prepared';case=$CaseName
  source_head=[string](& git -C $repo rev-parse HEAD)
  source_dirty=(@(& git -C $repo status --porcelain=v1).Count -gt 0)
  harness_sha256=Get-FixtureSha $PSCommandPath
  native_probe_sha256=Get-FixtureSha (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
  governor_sha256=Get-FixtureSha (Join-Path $repo 'tools/mir/application/release/readiness/ResourceGovernor.ps1')
  engine=Get-MIRDirectLibraryStartupEngineIdentity -FactorioBin $engine -EngineDataDirectory $engineData
  profile=@{path=$profile;sha256=Get-FixtureSha $profile};fixtures=$fixtureInputs
  mir_archive=@{path=$mir[0].path;sha256=$ExpectedMIRArchiveSha256.ToUpperInvariant()}
  release_qualification=$false
}
try{
  $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB 128 -UseExactOutputRoot
  $writeData=Join-Path $resources.root 'write-data'
  [IO.Directory]::CreateDirectory((Join-Path $writeData 'saves')) | Out-Null
  $config=Join-Path $resources.root 'config.ini'
  New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $engineData -WriteDataDirectory $writeData
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $library -EngineDataDirectory $engineData -BaseRows $rows -MirArchive $null
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $engineData -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  $seed=Join-Path $writeData 'saves/seed.zip'
  $record.create=Invoke-FixtureStage 'create' @('--create',$seed)
  Assert-Fixture (Test-Path -LiteralPath $seed -PathType Leaf) 'seed save absent'
  $server=Join-Path $resources.root 'server-settings.json'
  [IO.File]::WriteAllText($server,(@{name='MIR private native fixture';visibility=@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false;autosave_interval=0} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  $complete=Join-Path $writeData 'saves/mir5-native-complete.zip'
  $live=Join-Path $writeData 'factorio-current.log'
  $completion={
    if(-not(Test-Path -LiteralPath $live -PathType Leaf)){return $false}
    $stream=[IO.File]::Open($live,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader=[IO.StreamReader]::new($stream)
    try{$text=$reader.ReadToEnd()}finally{$reader.Dispose();$stream.Dispose()}
    if([regex]::IsMatch($text,'(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$')){throw 'fatal native production diagnostic'}
    return (Test-Path -LiteralPath $complete -PathType Leaf) -and $text.Contains('[MIR5_NATIVE_FIXTURE] RESULT ') -and $text.Contains('Saving finished')
  }.GetNewClosure()
  $record.production=Invoke-FixtureStage 'production' @('--server-settings',$server,'--bind','127.0.0.1','--start-server',$seed) $completion
  $record.initial=Read-FixtureResult ([IO.File]::ReadAllText($record.production.log)) 'initial'
  $saveHash=Get-FixtureSha $complete
  $record.reloads=@()
  foreach($ordinal in 1..2){
    $stage=Invoke-FixtureStage ('reload-'+$ordinal) @('--benchmark',$complete,'--benchmark-ticks','1','--benchmark-runs','1','--benchmark-sanitize')
    $result=Read-FixtureResult ([IO.File]::ReadAllText($stage.log)) 'reload'
    Assert-Fixture ((Get-FixtureSha $complete) -ceq $saveHash) 'cold reload changed completed save bytes'
    $record.reloads+=@{ordinal=$ordinal;stage=$stage;result=$result;save_sha256=$saveHash;save_byte_identical=$true}
  }
  $record.status='passed-private-native-fixture'
}catch{
  $record.status='failed';$record.failure=$_.Exception.Message;$failure=$_
}finally{
  try{
    if($null -ne $activation -and -not $activation.closed){$record.library_control_restoration=Complete-MIRLibraryActivation -Activation $activation}
  }catch{
    $record.library_control_restoration_failure=$_.Exception.Message
    if($null -eq $failure){$record.status='failed';$record.failure=$_.Exception.Message;$failure=$_}
  }finally{
    if($null -ne $resources){
      $record.process_runs=@($resources.runs.ToArray())
      Write-MIRNativeProbeResult -Context $resources -Record $record
    }
  }
}
if($null -ne $failure){throw $failure}
[pscustomobject]$record
