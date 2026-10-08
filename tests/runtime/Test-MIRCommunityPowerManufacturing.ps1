# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='', [string]$LibraryDirectory='',
  [string]$CandidateZip='', [string]$SourceMaterializationPath='',
  [switch]$PrepareInputsOnly,
  [string]$OutputRoot='build/p/community-power',
  [ValidateRange(1,8192)][int]$ExpectedPeakMemoryMiB=1024,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
if(-not $PrepareInputsOnly -and (-not $FactorioBin -or -not $LibraryDirectory -or -not $CandidateZip -or -not $SourceMaterializationPath)){
  throw '[mir-community-power-inputs] Supply the exact engine, flat library, current candidate and materialization receipt.'
}
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
Assert-MIR441CleanTrackedSource -RepoRoot $repo
$source=(&git -C $repo rev-parse HEAD).Trim()
$fixture=Join-Path $repo 'fixtures/assert-community-power-manufacturing'
$fixtureInfo=Get-Content -LiteralPath (Join-Path $fixture 'info.json') -Raw|ConvertFrom-Json
$fixtureName=$fixtureInfo.name+'_'+$fixtureInfo.version+'.zip'
[IO.Directory]::CreateDirectory($resources.root)|Out-Null
if($PrepareInputsOnly){
  $archive=Publish-MIRModDirectoryArchive -Source $fixture -Name $fixtureInfo.name -Version $fixtureInfo.version -ModsDir $resources.root
  Write-MIRNativeProbeResult -Context $resources -Record @{status='prepared-not-native-tested';source_commit=$source;fixture=@{path=$archive;sha256=(Get-FileHash -LiteralPath $archive).Hash};native_factorio=$false;dependency_payload_bytes_copied=0;archive_links_created=0}
  return
}
$activation=$null
$record=[ordered]@{status='started';source_commit=$source;target='f200';dependency_payload_bytes_copied=0;archive_links_created=0;error=''}
try{
  $profilePath=Join-Path $repo 'fixtures/run-profiles/community-power-f200.json'
  $profile=Get-Content -LiteralPath $profilePath -Raw|ConvertFrom-Json -AsHashtable
  $engine=(Resolve-Path -LiteralPath $FactorioBin).Path
  if((Get-FileHash -LiteralPath $engine).Hash-cne$profile.engine_sha256){throw '[mir-community-power-engine]'}
  $candidate=Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $CandidateZip -ReceiptPath $SourceMaterializationPath -Target f200
  $library=(Resolve-Path -LiteralPath $LibraryDirectory).Path
  $fixtureArchive=Join-Path $library $fixtureName
  Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $fixture
  $hashes=$profile.archive_sha256
  $hashes[[IO.Path]::GetFileName($candidate.path)]=$candidate.receipt.archive_sha256
  $hashes[$fixtureName]=(Get-FileHash -LiteralPath $fixtureArchive).Hash
  $data=Join-Path (Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent) 'data'
  $user=Join-Path $resources.root 'user';[IO.Directory]::CreateDirectory($user)|Out-Null
  $config=Join-Path $resources.root 'config.ini'
  [IO.File]::WriteAllLines($config,@('[path]',('read-data='+$data.Replace('\','/')),('write-data='+$user.Replace('\','/')),'[other]','enable-new-mods=false','check-updates=false','disable-blueprint-storage=true','enable-blueprint-storage-cloud-sync=false'),[Text.UTF8Encoding]::new($false))
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profilePath -ArchiveHashes $hashes -SettingsMode Defaults
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  $record.candidate=@{path=$candidate.path;sha256=$candidate.receipt.archive_sha256}
  $record.profile=@{path=$profilePath;sha256=(Get-FileHash -LiteralPath $profilePath).Hash}
  $record.engine=@{path=$engine;sha256=$profile.engine_sha256}
  $record.fixture=@{path=$fixtureArchive;sha256=$hashes[$fixtureName]}
  function Invoke-PowerStage([string]$Name,[string[]]$StageArguments,[scriptblock]$CompletionPredicate){
    $arguments=@('--config',$config,'--mod-directory',$library,'--disable-audio')+$StageArguments
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments
    $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $arguments -TimeoutSeconds 120 -CompletionPredicate $CompletionPredicate
    if(-not $actor.result.passed){throw ('[mir-community-power-native] '+$Name)}
    $log=Join-Path $user 'factorio-current.log'
    $null=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation
    $text=Get-Content -LiteralPath $log -Raw
    if([regex]::Matches($text,'\[mir-community-power\] FINAL-PROTOTYPES-PASS ').Count-ne1){throw '[mir-community-power-final-prototypes]'}
    [IO.File]::Copy($log,(Join-Path $resources.root ($Name+'.factorio.log')),$false)
  }
  $save=Join-Path $resources.root 'source.zip'
  Invoke-PowerStage 'create' @('--create',$save)
  $productionPath=Join-Path $user 'script-output/community-power-production.json'
  $progressed=Join-Path $user 'saves/_autosave-mir-community-power.zip'
  $productionLog=Join-Path $user 'factorio-current.log'
  $serverSettings=Join-Path $resources.root 'server-settings.json'
  @{name='MIR owned community production';description='Local assertion fixture';visibility=@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $serverSettings
  $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
  try{$listener.Start();$port=([Net.IPEndPoint]$listener.LocalEndpoint).Port}finally{$listener.Stop()}
  $finished={
    if(-not(Test-Path -LiteralPath $productionPath) -or -not(Test-Path -LiteralPath $progressed)){return $false}
    try{
      $value=Get-Content -LiteralPath $productionPath -Raw|ConvertFrom-Json
      return $value.status-ceq'passed' -and $value.stage-ceq'production' -and
        ((Get-Content -LiteralPath $productionLog -Raw)-match 'Saving finished')
    }catch{return $false}
  }.GetNewClosure()
  Invoke-PowerStage 'production' @('--start-server',$save,'--bind',('127.0.0.1:'+$port),'--server-settings',$serverSettings) $finished
  $production=Get-Content -LiteralPath $productionPath -Raw|ConvertFrom-Json
  if($production.status-cne'passed' -or $production.stage-cne'production' -or @($production.cases).Count-ne4){throw '[mir-community-power-production]'}
  if(-not(Test-Path -LiteralPath $progressed)){throw '[mir-community-power-save]'}
  Invoke-PowerStage 'reload' @('--benchmark',$progressed,'--benchmark-ticks','10','--benchmark-runs','1')
  $reloadPath=Join-Path $user 'script-output/community-power-reload.json'
  $reload=Get-Content -LiteralPath $reloadPath -Raw|ConvertFrom-Json
  if($reload.status-cne'passed' -or $reload.stage-cne'reload' -or @($reload.cases).Count-ne4){throw '[mir-community-power-reload]'}
  $record.production=@{path=$productionPath;sha256=(Get-FileHash -LiteralPath $productionPath).Hash;observations=$production}
  $record.reload=@{path=$reloadPath;sha256=(Get-FileHash -LiteralPath $reloadPath).Hash;observations=$reload}
  $record.save=@{path=$progressed;sha256=(Get-FileHash -LiteralPath $progressed).Hash}
  foreach($entry in $hashes.GetEnumerator()){
    if((Get-FileHash -LiteralPath (Join-Path $library $entry.Key)).Hash-cne$entry.Value){throw '[mir-community-power-input-changed]'}
  }
  Assert-MIR441CleanTrackedSource -RepoRoot $repo
  if((&git -C $repo rev-parse HEAD).Trim()-cne$source -or (Get-FileHash -LiteralPath $engine).Hash-cne$profile.engine_sha256){throw '[mir-community-power-source-changed]'}
  $record.status='passed-exact-f200-paired-manufacturing-production-and-reload'
}catch{$record.status='failed';$record.error=$_.Exception.Message}
finally{
  if($null-ne$activation){try{$record.library_activation=Complete-MIRLibraryActivation $activation}catch{$record.status='failed';$record.control_restoration_error=$_.Exception.Message}}
  $record.resource_runs=$resources.runs.ToArray()
  Write-MIRNativeProbeResult -Context $resources -Record $record
}
if($record.status-eq'failed'){throw $record.error}
[pscustomobject]@{status=$record.status;result=(Join-Path $resources.root 'result.json')}
