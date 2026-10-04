# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
$fixture=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo ('build/tmp/native-probe-fixture-'+[guid]::NewGuid().ToString('N')))
$assertions=0;$lease=$null
function Assert-Probe([bool]$Condition,[string]$Message) {
  if(-not $Condition) { throw "Native probe resources: $Message" }
  $script:assertions++
}
function Refuses-Probe([scriptblock]$Action,[string]$Expected) {
  $failure=''
  try { & $Action | Out-Null } catch { $failure=$_.Exception.Message }
  Assert-Probe ($failure.Contains($Expected)) "expected $Expected; got $failure"
}
# Fake capacity is confined to tiny controlled process/metadata fixtures.
# This suite never launches Factorio or the real package materializer.
function Get-MIR441ResourceSnapshot {
  param([string]$WorkRoot)
  [pscustomobject]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');memory=[pscustomobject]@{total_bytes=16GB;free_bytes=12GB;committed_bytes=4GB;commit_limit_bytes=20GB};system_volume=[pscustomobject]@{free_bytes=100GB};work_volume=[pscustomobject]@{free_bytes=100GB}}
}
try {
  . (Join-Path $repo 'tools/lib/assurance/evidence/CommandExecution.ps1')
  $catalog=Get-Content -LiteralPath (Join-Path $repo 'validation/tests.yml') -Raw | ConvertFrom-Json
  $command=[string](@($catalog.tests | Where-Object id -CEQ 'runtime.material-route-guard')[0].command)
  foreach($line in @('2.0','2.1')) {
    $engine=if($line -ceq '2.0') { 'D:\Programs\Factorio\2.0\bin\x64\factorio.exe' } else { 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' }
    $resolved=Resolve-MIRAssuranceCommandText -Command $command -Context ([pscustomobject]@{factorio=$engine;target=$line}) -Plan ([pscustomobject]@{})
    Assert-Probe ($resolved.Contains("-FactorioBin '$engine'") -and $resolved.Contains("-ExpectedFactorioLine '$line'") -and $resolved.Contains('-ExpectedPeakMemoryMiB 2048') -and $resolved.Contains('-MaxNewOutputMiB 120')) "selected $line command lost its engine, line or explicit resource budgets."
  }
  $arguments=@{RepoRoot=$repo;OutputRoot=$fixture;MaxNewOutputMiB=1}
  Refuses-Probe {New-MIRNativeProbeResourceContext @arguments} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'missing-budget refusal allocated staging.'
  Refuses-Probe {New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot 'D:\outside-native-probe' -ExpectedPeakMemoryMiB 1024} 'resource-output-root'
  foreach($script in @('tests/compiler/Test-MIRMaterialRoutes.ps1','tests/runtime/Test-MIRF210CurrentBobAngelTinRouteObserver.ps1','tests/runtime/Test-MIRF210CurrentBobAngelFinalRoutesObserver.ps1')) {
    $probeArguments=@{RepoRoot=$repo;FactorioBin='absent-engine';OutputRoot=$fixture}
    if($script.StartsWith('tests/runtime/')) {$probeArguments.ExactStageRoot=Join-Path $fixture 'absent-stage'}
    Refuses-Probe {& (Join-Path $repo $script) @probeArguments} 'resource-peak-budget-required'
    Assert-Probe (-not (Test-Path -LiteralPath $fixture)) "$script allocated staging before refusal."
  }
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelTinRouteObserver.ps1') -RepoRoot $repo -PrepareOnly -OutputRoot $fixture} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'PrepareOnly bypassed allocation admission.'
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelFinalRoutesObserver.ps1') -RepoRoot $repo -PrepareOnly -ExactStageRoot (Join-Path $fixture 'absent-stage') -OutputRoot $fixture} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'Final observer PrepareOnly bypassed allocation admission.'
  $context=New-MIRNativeProbeResourceContext @arguments -ExpectedPeakMemoryMiB 1024
  Assert-Probe (-not (Test-Path -LiteralPath $context.root)) 'successful admission allocated before caller initialization.'
  New-Item -ItemType Directory -Path $context.root | Out-Null
  $source=Join-Path $fixture 'dependency.zip'
  [IO.File]::WriteAllBytes($source,[byte[]]::new(128KB))
  $archiveInput=[ordered]@{source_path=$source;file_name='dependency.zip';expected_sha256=Get-MIRImmutableInputSha256 $source;role='dependency-mod';identity=@{name='controlled'};provenance=@{kind='tiny-controlled-fixture'};immutable=$true}
  $leaseRoot=Join-Path $context.root 'stage';New-Item -ItemType Directory -Path $leaseRoot | Out-Null
  Refuses-Probe {New-MIRImmutableInputLease -RunRoot $leaseRoot -StageDirectory (Join-Path $leaseRoot 'mods') -Inputs @($archiveInput) -RequireHardLinks -ForceCopy} 'cannot request copy mode'
  $lease=New-MIRImmutableInputLease -RunRoot $leaseRoot -StageDirectory (Join-Path $leaseRoot 'mods') -Inputs @($archiveInput) -RequireHardLinks
  Add-MIRNativeProbeImmutableLease -Context $context -Lease $lease
  Assert-Probe ($context.shared_alias_bytes -eq 128KB) 'strict leased alias bytes were not identified.'
  Refuses-Probe {Add-MIRNativeProbeImmutableLease -Context $context -Lease $lease} 'shared-alias-identity'
  Assert-Probe ($context.shared_alias_bytes -eq 128KB) 'duplicate registration widened the byte exemption.'
  $before=Get-MIRNativeProbeRemainingOutputBytes -Context $context
  $budgetFile=Join-Path $context.root 'new-output.bin'
  [IO.File]::WriteAllBytes($budgetFile,[byte[]]::new(64KB))
  Assert-Probe ((Get-MIRNativeProbeRemainingOutputBytes -Context $context) -eq $before-64KB) 'ordinary new output escaped the cumulative row budget.'
  [IO.File]::WriteAllBytes($budgetFile,[byte[]]::new(1MB))
  Refuses-Probe {Get-MIRNativeProbeRemainingOutputBytes -Context $context} 'resource-output-budget'
  Remove-Item -LiteralPath $budgetFile
  $pwsh=(Get-Command pwsh).Source
  $run=Invoke-MIRNativeProbeProcess -Context $context -FilePath $pwsh -Arguments @('-NoProfile','-Command','Write-Output $env:TEMP') -TimeoutSeconds 20
  Assert-Probe ($run.result.passed -and (Test-Path -LiteralPath $run.ledger)) 'actual owned small process did not retain its resource ledger.'
  $privateTemp=(Get-Content -LiteralPath $run.stdout -Raw).Trim()
  Assert-Probe ((Test-MIR441PathContained -Root $context.root -Path $privateTemp) -and -not (Test-Path -LiteralPath $privateTemp)) 'process temp was not isolated and retired.'
  Refuses-Probe {Invoke-MIRNativeProbeProcess -Context $context -FilePath $pwsh -Arguments @('-NoProfile','-Command','exit 7') -TimeoutSeconds 20} 'mir441-process-exit'
  Assert-Probe ($context.runs[$context.runs.Count-1].status -ceq 'interrupted' -and (Test-Path -LiteralPath $context.runs[$context.runs.Count-1].ledger)) 'failed actor lost its ledger reference.'
  $terminal=Complete-MIRImmutableInputLease -Lease $lease -Outcome passed
  $lease=$null
  Assert-Probe ($terminal.state -ceq 'completed' -and $terminal.inputs_sha256_match) 'strict lease did not retain verified terminal custody.'

  # Exercise the production driver and process adapter with a tiny fake
  # materializer dependency. There is no Git clone or actual player package.
  $fakeRepo=Join-Path $fixture 'driver-fixture'
  $library=Join-Path $fakeRepo 'tools/mir/application/package/TargetMaterializer.ps1'
  New-Item -ItemType Directory -Path (Split-Path -Parent $library) | Out-Null
  $stub=@'
function New-MIR4TargetPackage {
  param([string]$RepoRoot,[string]$Target,[string]$CandidateId,[string]$SourceVersion,[string]$DistributionVersion,[string]$OutputRoot)
  if($CandidateId -cnotmatch '^[A-Z0-9][A-Z0-9.-]*$') { throw 'candidate id outside canonical contract' }
  [pscustomobject]@{target=$Target;candidate_id=$CandidateId;source_version=$SourceVersion;distribution_version=$DistributionVersion;output=[IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputRoot));actual_package=$false}
}
'@
  [IO.File]::WriteAllText($library,$stub,[Text.UTF8Encoding]::new($false))
  $package=New-MIRNativeProbeTargetPackage -Context $context -RepoRoot $fakeRepo
  Assert-Probe ($package.source_version -ceq '4.2.1' -and $package.distribution_version -ceq '4.2.21001' -and $package.target -ceq 'f210') 'driver lost the required patch/target identity.'
  Assert-Probe ($package.output -ceq (Join-Path $context.root 'packages') -and -not $package.actual_package) 'driver output escaped its row or fixture became a real materializer.'
  $finalPackage=New-MIRNativeProbeTargetPackage -Context $context -RepoRoot $fakeRepo -CandidatePrefix 'F210-CURRENT-BA-FINAL-ROUTES-OBSERVER'
  Assert-Probe ($finalPackage.candidate_id -cmatch '^F210-CURRENT-BA-FINAL-ROUTES-OBSERVER-[0-9A-F]{8}$' -and $finalPackage.distribution_version -ceq '4.2.21001' -and -not $finalPackage.actual_package) 'final observer driver lost its candidate or patch identity.'
  Write-MIRNativeProbeResult -Context $context -Record @{status='controlled-passed';native_factorio=$false;actual_materialization=$false;actor_count=$context.runs.Count}
  Assert-Probe ((Get-Content -LiteralPath (Join-Path $context.root 'result.json') -Raw | ConvertFrom-Json).actor_count -eq 4) 'reserved result did not preserve actual actor inventory.'
  $resultPath=Join-Path $context.root 'result.json';Remove-Item -LiteralPath $resultPath
  [IO.File]::WriteAllBytes($budgetFile,[byte[]]::new(960KB))
  Refuses-Probe {Write-MIRNativeProbeResult -Context $context -Record @{payload=('x'*128KB)}} 'resource-output-budget'
  Assert-Probe (-not (Test-Path -LiteralPath $resultPath)) 'oversized result was written as success.'
  # A missing shared alias must refuse even when other output masks the
  # subtraction in the logical tree total. The strict lease is closed here.
  Remove-Item -LiteralPath $context.aliases[0].stage_path
  Refuses-Probe {Get-MIRNativeProbeRemainingOutputBytes -Context $context} 'shared-alias-identity'
  Assert-Probe ((Get-MIRImmutableInputSha256 $source) -ceq $archiveInput.expected_sha256) 'alias retirement changed its canonical archive.'

  # Test the actual completed-row custody reader with synthetic archives,
  # three tiny pwsh actors and a dummy log/save. This is not a native oracle.
  $parseTokens=$null;$parseErrors=$null
  $observerPath=Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelFinalRoutesObserver.ps1'
  $observerAst=[Management.Automation.Language.Parser]::ParseFile($observerPath,[ref]$parseTokens,[ref]$parseErrors)
  Assert-Probe ($parseErrors.Count -eq 0) 'final observer syntax differs.'
  foreach($name in @('Assert-Observer','Get-ObserverSha','Get-ObserverArtifact','Get-ObserverZipInfo','Get-ObserverCompletedRecovery')) {
    $definitions=@($observerAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false))
    Assert-Probe ($definitions.Count -eq 1) "expected one actual recovery function: $name"
    . ([scriptblock]::Create($definitions[0].Extent.Text))
  }
  $recoveryContext=New-MIRNativeProbeResourceContext @arguments -ExpectedPeakMemoryMiB 1024
  $recoveryRoot=$recoveryContext.root
  New-Item -ItemType Directory -Path (Join-Path $recoveryRoot 'packages'),(Join-Path $recoveryRoot 'userdata'),(Join-Path $recoveryRoot 'stage')|Out-Null
  $syntheticCandidate=Join-Path $recoveryRoot 'packages/more-infinite-research_4.2.21001.zip'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipFile]::Open($syntheticCandidate,[IO.Compression.ZipArchiveMode]::Create)
  try {$entry=$zip.CreateEntry('more-infinite-research_4.2.21001/info.json');$writer=[IO.StreamWriter]::new($entry.Open());try {$writer.Write('{"name":"more-infinite-research","version":"4.2.21001","factorio_version":"2.1"}')}finally{$writer.Dispose()}}finally{$zip.Dispose()}
  $candidateInput=[ordered]@{source_path=$syntheticCandidate;file_name=[IO.Path]::GetFileName($syntheticCandidate);expected_sha256=Get-MIRImmutableInputSha256 $syntheticCandidate;role='candidate';identity=@{fixture='synthetic-archive-only'};provenance=@{kind='controlled-parser-fixture'};immutable=$true}
  $lease=New-MIRImmutableInputLease -RunRoot (Join-Path $recoveryRoot 'stage') -StageDirectory (Join-Path $recoveryRoot 'stage/mods') -Inputs @($candidateInput,$archiveInput) -RequireHardLinks
  Add-MIRNativeProbeImmutableLease -Context $recoveryContext -Lease $lease
  foreach($number in 1..3){$null=Invoke-MIRNativeProbeProcess -Context $recoveryContext -FilePath $pwsh -Arguments @('-NoProfile','-Command','Write-Output controlled-recovery-parser-actor') -TimeoutSeconds 20}
  $terminal=Complete-MIRImmutableInputLease -Lease $lease -Outcome passed;$lease=$null
  # A serialized custody control with significant trailing timestamp zeros
  # must retain its exact strings through the reader's JSON round trip.
  foreach($name in @('started_utc','receipt_captured_utc','completed_utc')) {$terminal.$name='2026-10-04T00:00:00.1200000Z'}
  $terminal.terminal_record_sha256=Get-MIRImmutableInputRecordSha256 -Record $terminal
  $dummyLog=Join-Path $recoveryRoot 'userdata/factorio-current.log';[IO.File]::WriteAllText($dummyLog,'controlled custody fixture; no native engine or final oracle')
  $dummySave=Join-Path $recoveryRoot 'observer.zip';[IO.File]::WriteAllText($dummySave,'controlled custody fixture; not a Factorio save')
  $recoverySource=[ordered]@{commit='controlled-source';tree='controlled-tree';package_source_sha256=$archiveInput.expected_sha256;source_version='4.2.1';distribution_version='4.2.21001'}
  $fixtureDirectory=Join-Path $repo 'fixtures/assert-f210-current-bob-angel-final-routes-observer'
  $lastActor=$recoveryContext.runs[2]
  $controlledRecord=[ordered]@{
    schema=2;kind='MIR4F210CurrentBobAngelFinalRoutesObservationV1';status='observed';run_root=$recoveryRoot;source=$recoverySource
    harness=Get-ObserverArtifact $observerPath;exact_stage=@{receipt_sha256=Get-ObserverSha $source;engine_sha256=Get-ObserverSha $pwsh}
    engine=@{executable_sha256=Get-ObserverSha $pwsh;version='Version: 2.1.20 controlled-parser-fixture'}
    fixture=@('info.json','data-final-fixes.lua','control.lua','material-outcome-inventory.lua'|ForEach-Object{Get-ObserverArtifact (Join-Path $fixtureDirectory $_)})
    candidate=Get-ObserverArtifact $syntheticCandidate;input_lease=$terminal;resource_runs=$recoveryContext.runs.ToArray()
    logs=@{stdout=Get-ObserverArtifact $lastActor.stdout;stderr=Get-ObserverArtifact $lastActor.stderr;factorio=Get-ObserverArtifact $dummyLog};save=Get-ObserverArtifact $dummySave
  }
  $recoveryArguments=@{RunRoot=$recoveryRoot;OutputRoot=$fixture;Source=$recoverySource;Fixture=$fixtureDirectory;HarnessPath=$observerPath;StageReceiptPath=$source;ExpectedArchives=@{'dependency.zip'=$archiveInput.expected_sha256};Engine=$pwsh}
  Write-MIRNativeProbeResult -Context $recoveryContext -Record $controlledRecord
  $rowPath=Join-Path $recoveryRoot 'result.json';$rowHash=Get-ObserverSha $rowPath
  $recovered=Get-ObserverCompletedRecovery @recoveryArguments
  Assert-Probe ($recovered.source.distribution_version -ceq '4.2.21001' -and (Get-ObserverSha $rowPath) -ceq $rowHash) 'completed custody replay wrote its historical receipt.'
  Assert-Probe ($recovered.input_lease.started_utc -is [string] -and $recovered.input_lease.started_utc -ceq '2026-10-04T00:00:00.1200000Z') 'recovery normalized a timestamp covered by its custody hash.'
  $fallbackRecovered=& {
    function Get-Command {
      param([string]$Name)
      if($Name -ceq 'ConvertFrom-Json'){return [pscustomobject]@{Parameters=@{}}}
      Microsoft.PowerShell.Core\Get-Command $Name
    }
    Get-ObserverCompletedRecovery @recoveryArguments
  }
  Assert-Probe ($fallbackRecovered.input_lease.started_utc -ceq '2026-10-04T00:00:00.1200000Z' -and (Get-ObserverSha $rowPath) -ceq $rowHash) 'older-PowerShell recovery fallback altered timestamp custody or wrote the receipt.'
  foreach($case in @(
    @{change={$args[0].schema=1};error='completed governed observation'},
    @{change={$args[0].source.distribution_version='4.2.21002'};error='source fingerprint differs'},
    @{change={$args[0].harness.sha256=('A'*64)};error='harness fingerprint differs'},
    @{change={$args[0].fixture=$args[0].fixture[0..2]};error='fixture inventory differs'},
    @{change={$args[0].input_lease.outcome='failed'};error='completed passed immutable-input receipt'},
    @{change={$args[0].resource_runs[2].index=2};error='duplicated identity'},
    @{change={$args[0].logs.factorio.sha256=('A'*64)};error='log custody differs'},
    @{change={$args[0].save.sha256=('A'*64)};error='save custody differs'}
  )) {
    $changed=($controlledRecord|ConvertTo-Json -Depth 30)|ConvertFrom-Json -AsHashtable -Depth 30
    foreach($name in @('started_utc','receipt_captured_utc','completed_utc')) {$changed.input_lease[$name]=$terminal.$name}
    & $case.change $changed
    Write-MIRNativeProbeResult -Context $recoveryContext -Record $changed
    Refuses-Probe {Get-ObserverCompletedRecovery @recoveryArguments} $case.error
  }
  Assert-Probe ((Get-MIRImmutableInputSha256 $source) -ceq $archiveInput.expected_sha256) 'controlled recovery changed a canonical input.'

  $failedRoot=Join-Path $fixture 'link-failure';New-Item -ItemType Directory -Path $failedRoot | Out-Null
  $copies=0
  function New-Item {
    param([string]$ItemType,[string]$Path,[string]$Target,[switch]$Force)
    if($ItemType -ceq 'HardLink') { throw 'controlled-link-failure' }
    Microsoft.PowerShell.Management\New-Item -ItemType $ItemType -Path $Path -Force:$Force
  }
  function Copy-Item { $script:copies++;throw 'copy fallback was invoked' }
  Refuses-Probe {New-MIRImmutableInputLease -RunRoot $failedRoot -StageDirectory (Join-Path $failedRoot 'mods') -Inputs @($archiveInput) -RequireHardLinks} 'requires a verified hard link'
  Assert-Probe ($copies -eq 0 -and (Get-MIRImmutableInputSha256 $source) -ceq $archiveInput.expected_sha256) 'strict link failure copied or modified the canonical input.'
} finally {
  if($null -ne $lease -and -not $lease.closed) { $null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed }
  if(Test-Path -LiteralPath $fixture) {
    $resolved=Resolve-MIR441RecoveryScratchPath -Path $fixture
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
[pscustomobject]@{status='passed';assertions=$assertions;native_factorio=$false;actual_materialization=$false;scope='Controlled lease, row budget, preallocation, owned small actors and completed-row custody parser; no native oracle';memory_enforcement='sampled-watchdog-not-hard-cap'}
