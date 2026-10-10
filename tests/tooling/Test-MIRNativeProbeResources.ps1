# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,[switch]$CapOwnershipInputsOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/BrowserContinuityInputs.ps1')
. (Join-Path $repo 'tests/support/MIRMaterialAuditInputs.ps1')
$fixture=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo ('build/tmp/native-probe-fixture-'+[guid]::NewGuid().ToString('N')))
$assertions=0;$lease=$null;$completed=$false
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
function Assert-F210CapSharedInputs {
  . (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
  . (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
  . (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')
  $capRoot=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo ('build/tmp/f210-cap-controls-'+[guid]::NewGuid().ToString('N')))
  $harness=Join-Path $repo 'tests/runtime/Test-MIR42CapOwnershipMultiforce.ps1'
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($harness,[ref]$tokens,[ref]$errors)
  Assert-Probe (@($errors).Count-eq0) 'F210 cap harness no longer parses.'
  foreach($name in @('Assert-MIR42','Assert-Exact','Get-MIR42Sha','New-MIR42CapSettingsSource','New-MIR42Stage','Start-MIR42CapStage','Complete-MIR42CapStage','Invoke-MIR42Engine','Invoke-MIR42ServerSave','Get-MIR42GovernedEngineResolution')){
    $definition=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$false))
    Assert-Probe ($definition.Count-eq1) "Expected one consumed F210 cap function: $name"
    . ([scriptblock]::Create($definition[0].Extent.Text))
  }
  $activeStage=$null;$script:activeStage=$null
  try{
    [IO.Directory]::CreateDirectory($capRoot)|Out-Null
    $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $capRoot -ExpectedPeakMemoryMiB 768 -MaxNewOutputMiB 4
    $run=$resources.root;$engineRoot=Join-Path $capRoot 'engine';$engine=Join-Path $engineRoot 'bin/x64/factorio.exe'
    $FactorioBin='controlled requested engine';$SteamManifest='controlled requested manifest'
    $engineResolution=[pscustomobject]@{engine=[pscustomobject]@{version='2.1.99'}}
    foreach($name in @('base','elevated-rails','quality','recycler','space-age')){
      $data=Join-Path $engineRoot ('data/'+$name);[IO.Directory]::CreateDirectory($data)|Out-Null
      @{name=$name;version='2.1.99';dependencies=@()}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $data 'info.json')
    }
    $library=Join-Path $capRoot 'library';[IO.Directory]::CreateDirectory($library)|Out-Null
    $tiny=Join-Path $capRoot 'tiny-candidate';[IO.Directory]::CreateDirectory($tiny)|Out-Null
    @{name='more-infinite-research';version='4.2.21001';factorio_version='2.1';dependencies=@('base')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $tiny 'info.json')
    $candidateZip=Publish-MIRModDirectoryArchive -Source $tiny -Name more-infinite-research -Version 4.2.21001 -ModsDir $library
    $candidateHash=Get-MIRImmutableInputSha256 $candidateZip
    $candidateInput=[pscustomobject]@{receipt=[pscustomobject]@{archive_sha256=$candidateHash;package_source_sha256=('A'*64)}}
    $fixture=Join-Path $repo 'fixtures/assert-mir42-cap-ownership-multiforce';$fixtureName='mir-fixture-assert-mir42-cap-ownership-multiforce'
    $blockerFixture=Join-Path $repo 'fixtures/late-mir42-cap-binding-blocker';$blockerName='late-mir42-cap-binding-blocker'
    $policyBlockerFixture=Join-Path $repo 'fixtures/late-mir42-policy-binding-blocker';$policyBlockerName='late-mir42-policy-binding-blocker'
    foreach($pair in @(@($fixture,$fixtureName),@($blockerFixture,$blockerName),@($policyBlockerFixture,$policyBlockerName))){$null=Publish-MIRModDirectoryArchive -Source $pair[0] -Name $pair[1] -Version 0.1.0 -ModsDir $library}
    $preparedSettings=@{}
    foreach($cap in @(0,3)){
      $preparedSettings[$cap]=New-MIR42CapSettingsSource (Join-Path $capRoot ('settings-'+$cap)) $cap
      $entry=$preparedSettings[$cap];$null=Publish-MIRModDirectoryArchive -Source $entry.source -Name mir-validation-settings-overrides -Version $entry.version -ModsDir $library
      $replica=New-MIR42CapSettingsSource (Join-Path $capRoot ('replica-'+$cap)) $cap
      Assert-MIRLibraryFixtureArchive -Archive (Join-Path $library $entry.file) -SourceDirectory $replica.source
    }
    [IO.File]::WriteAllText((Join-Path $library 'mod-list.json'),'original selection')
    [IO.File]::WriteAllBytes((Join-Path $library 'mod-settings.dat'),[byte[]](3,1,4))
    $originalList=(Get-FileHash (Join-Path $library 'mod-list.json')).Hash
    $originalSettings=(Get-FileHash (Join-Path $library 'mod-settings.dat')).Hash
    $inventory=@(Get-ChildItem -LiteralPath $library -Filter '*.zip'|ForEach-Object{$_.Name+'|'+(Get-FileHash $_.FullName).Hash})-join "`n"
    $stages=@((New-MIR42Stage seed 0 $false $false),(New-MIR42Stage capped 3 $false $false),(New-MIR42Stage policy-blocked 3 $false $true),(New-MIR42Stage blocked 3 $true $false),(New-MIR42Stage removal 0 $false $false))
    foreach($stage in $stages){
      Assert-Probe ($stage.mods-ceq$library -and -not(Test-Path (Join-Path $stage.root 'mods'))) 'F210 stage materialized another mods directory.'
      $list=Get-Content -Raw -LiteralPath $stage.mod_list|ConvertFrom-Json
      Assert-Probe (($blockerName-in@($list.mods.name))-eq$stage.blocker -and ($policyBlockerName-in@($list.mods.name))-eq$stage.policy_blocker) 'F210 blocker selection changed.'
      Assert-Probe (@($list.mods|Where-Object{-not$_.version}).Count-eq0) 'F210 selection contains an unpinned input.'
      Start-MIR42CapStage $stage
      Assert-Probe (-not(Test-Path (Join-Path $library 'mod-settings.dat'))) 'F210 defaults inherited preceding settings.'
      $active=Get-Content (Join-Path $library 'mod-list.json') -Raw|ConvertFrom-Json
      Assert-Probe (@($active.mods|Where-Object{$_.enabled-and$_.name-eq'mir-validation-settings-overrides'})[0].version-ceq$preparedSettings[$stage.cap].version) 'F210 selected the wrong cap settings release.'
      if(-not$stage.blocker){Assert-Probe (@($active.mods|Where-Object name -EQ $blockerName)[0].enabled-eq$false) 'Unrequested blocker enabled.'}
      [IO.File]::WriteAllBytes((Join-Path $library 'mod-settings.dat'),[byte[]](8,9))
      $log=Join-Path $stage.root 'controlled.log'
      $rows=@('0.000 2026-10-08 12:00:00; Factorio 2.1.99 (build 1)',@($stage.activation.selected|ForEach-Object{'Loading mod '+$_.name+' '+$_.version+' (data.lua)'}))
      [IO.File]::WriteAllLines($log,[string[]]@($rows|ForEach-Object{$_}),[Text.UTF8Encoding]::new($false))
      Complete-MIR42CapStage $stage $log
      Assert-Probe ((Get-FileHash (Join-Path $library 'mod-list.json')).Hash-ceq$originalList -and (Get-FileHash (Join-Path $library 'mod-settings.dat')).Hash-ceq$originalSettings) 'F210 did not restore the original control files.'
    }
    # Repeat A after B and the opposing blockers, then verify refusal before any activation.
    Start-MIR42CapStage $stages[0]
    Complete-MIR42CapStage $stages[0] (Join-Path $stages[0].root 'controlled.log')
    $candidateInput.receipt.archive_sha256='B'*64
    Refuses-Probe {New-MIR42Stage changed-bytes 0 $false $false} 'installed candidate hash'
    $candidateInput.receipt.archive_sha256=$candidateHash
    $missingLibrary=Join-Path $capRoot 'missing';$savedLibrary=$library;$library=$missingLibrary
    Refuses-Probe {New-MIR42Stage missing-input 0 $false $false} 'does not exist'
    $library=$savedLibrary
    Assert-Probe (-not(Test-Path -LiteralPath $missingLibrary)) 'Missing library recreated a profile.'
    Refuses-Probe {& $harness -RepoRoot $repo -FactorioBin absent -CandidateZip absent -OutputRoot (Join-Path $capRoot 'absent-run')} 'mir42-f210-direct-inputs-required'
    Assert-Probe (-not(Test-Path -LiteralPath (Join-Path $capRoot 'absent-run'))) 'Unbound entry point allocated output.'
    Assert-Probe ((@(Get-ChildItem -LiteralPath $library -Filter '*.zip'|ForEach-Object{$_.Name+'|'+(Get-FileHash $_.FullName).Hash})-join "`n")-ceq$inventory) 'Stage switching wrote dependency archives.'
    Assert-Probe (@(Get-ChildItem -LiteralPath $run -Recurse -Filter '*.zip').Count-eq0 -and $resources.shared_alias_bytes-eq0) 'Stage switching copied or linked archives.'
    function Invoke-MIRNativeProbeProcess {
      param($Context,[string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds)
      Assert-Probe ($Context-eq$resources -and $FilePath-ceq(Get-Command pwsh).Source -and $TimeoutSeconds-eq30 -and $Arguments-contains$FactorioBin -and $Arguments-contains$SteamManifest) 'F210 resolver lost its governed inputs.'
      $driver=Get-Content -Raw (Join-Path $Context.root 'resolve-engine.ps1')
      Assert-Probe ($driver.Contains('Resolve-MIR4F210CurrentEngineCapHarnessAdmissionV3')) 'F210 bypassed its admission oracle.'
      [IO.File]::WriteAllText((Join-Path $Context.root 'engine-resolution.json'),'{"engine":{"version":"controlled"},"record_sha256":"controlled"}')
    }
    $resolution=Get-MIR42GovernedEngineResolution
    Assert-Probe ($resolution.engine.version-ceq'controlled') 'Resolver transport changed.'
    $expectedSave=Join-Path $stages[0].userdata 'saves/successor.zip';$reportCompletion=$true
    function Invoke-MIRNativeProbeFactorioProcess {
      param($Context,[string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds,[scriptblock]$CompletionPredicate)
      Assert-Probe ($Context-eq$resources -and $FilePath-ceq$engine -and $Arguments-contains$stages[0].config -and $Arguments-contains$library) 'F210 actor lost its direct library or private configuration.'
      $log=Join-Path $stages[0].userdata 'factorio-current.log'
      $loaded=Get-Content (Join-Path $stages[0].root 'controlled.log') -Raw
      if($null-eq$CompletionPredicate){Assert-Probe ($TimeoutSeconds-eq120 -and $Arguments-contains'--create') 'F210 create actor changed.';[IO.File]::WriteAllText($log,$loaded);return [pscustomobject]@{result=[pscustomobject]@{completion_predicate_observed=$false}}}
      Assert-Probe ($TimeoutSeconds-eq60 -and $Arguments-contains'--start-server') 'F210 server changed.'
      if(Test-Path $expectedSave){Remove-Item -LiteralPath $expectedSave}
      Assert-Probe (-not(&$CompletionPredicate)) 'Completion accepts absent save/log.'
      [IO.File]::WriteAllText($log,'Saving finished');Assert-Probe (-not(&$CompletionPredicate)) 'Completion accepts missing save.'
      [IO.File]::WriteAllText($expectedSave,'tiny save');Assert-Probe (-not(&$CompletionPredicate)) 'Completion accepts missing state.'
      [IO.File]::WriteAllText($log,'[mir42-cap-ownership-multiforce] STATE JSON {"stage":"event-probe"}');Assert-Probe (-not(&$CompletionPredicate)) 'Completion accepts unfinished save.'
      [IO.File]::WriteAllText($log,'[mir42-cap-ownership-multiforce] STATE JSON {"stage":"blocked"} Saving finished');Assert-Probe (-not(&$CompletionPredicate)) 'Completion accepts another stage.'
      [IO.File]::WriteAllText($log,$loaded+'[mir42-cap-ownership-multiforce] STATE JSON {"stage":"event-probe"} Saving finished');Assert-Probe (&$CompletionPredicate) 'Completion rejects original conditions.'
      [pscustomobject]@{result=[pscustomobject]@{completion_predicate_observed=$reportCompletion}}
    }
    $null=Invoke-MIR42Engine $stages[0] seed @('--create','controlled-input.zip')
    $null=Invoke-MIR42ServerSave $stages[0] capped 'controlled-input.zip' $expectedSave event-probe
    $reportCompletion=$false
    Refuses-Probe {Invoke-MIR42ServerSave $stages[0] incomplete 'controlled-input.zip' $expectedSave event-probe} 'did not create incomplete successor'
    Write-Host '[ok] F210 cap direct-library stages, exact settings, restoration, missing/changed input refusal, governed resolution and original save-completion prerequisites; no Factorio.'
  }finally{
    if($null-ne$script:activeStage -and $null-ne$script:activeStage.activation -and -not$script:activeStage.activation.closed){$null=Complete-MIRLibraryActivation $script:activeStage.activation}
    if(Test-Path -LiteralPath $capRoot){$null=Assert-MIRImmutableInputPathWithin -Path $capRoot -Root (Join-Path $repo 'build/tmp') -Context 'owned tiny F210 controls';Remove-Item -LiteralPath $capRoot -Recurse -Force}
  }
}
Assert-F210CapSharedInputs
if($CapOwnershipInputsOnly){return}
try {
  . (Join-Path $repo 'tests/support/MIR421SpaceFakeUpgrade.ps1')
  foreach ($target in @('f210','f200')) {
    $code=$target.Substring(1)
    $sifArguments=@{Target=$target;FromVersion="4.2.${code}00";ToVersion="4.2.${code}01";FixtureName="assert-upgrade-4-0-${code}00-to-4-1-${code}00";Archetype=$(if($target -ceq 'f210'){'base-continuations'}else{'base-default'})}
    $descriptor=Get-MIR421SpaceFakeUpgradeDescriptor @sifArguments
    Assert-Probe ($descriptor.inputs.Count -eq 2 -and ($descriptor.mod_names -join '|') -ceq 'space-is-fake|cr-commons' -and $descriptor.request -ceq 'SIF-01') "exact $target native dependency profile lost its inputs."
    Assert-Probe ($descriptor.scenario-ceq'SIF-01-published-4.2.0-to-4.2.1') 'Default SIF transition identity changed.'
    $sif422=$sifArguments.Clone();$sif422.SourceVersion='4.2.2';$sif422.FromVersion="4.2.${code}01";$sif422.ToVersion="4.2.${code}02"
    $descriptor422=Get-MIR421SpaceFakeUpgradeDescriptor @sif422
    Assert-Probe ($descriptor422.scenario-ceq'SIF-01-published-4.2.1-to-4.2.2'-and
      ($descriptor422.inputs.sha256-join'|')-ceq($descriptor.inputs.sha256-join'|')) '4.2.2 SIF changes dependency bytes or mislabels its predecessor.'
    foreach($field in @('SourceVersion','FromVersion','ToVersion')){
      $bad=$sif422.Clone();$bad[$field]=switch($field){'SourceVersion'{'4.2.1'};'FromVersion'{"4.2.${code}00"};'ToVersion'{"4.2.${code}01"}}
      Refuses-Probe {Get-MIR421SpaceFakeUpgradeDescriptor @bad} 'sif-transition'
    }
    $bad=$sifArguments.Clone();$bad.ToVersion="4.2.${code}02"
    Refuses-Probe {Get-MIR421SpaceFakeUpgradeDescriptor @bad} 'sif-transition'
    $bad=$sifArguments.Clone();$bad.FromVersion="4.1.${code}00"
    Refuses-Probe {Get-MIR421SpaceFakeUpgradeDescriptor @bad} 'sif-transition'
    $bad=$sifArguments.Clone();$bad.Archetype='space-age-native-owner'
    Refuses-Probe {Get-MIR421SpaceFakeUpgradeDescriptor @bad} 'sif-transition'
    $control=Get-Content -Raw -LiteralPath (Join-Path $repo ('fixtures/'+$sifArguments.FixtureName+'/control.lua'))
    $specialized=Add-MIR421SpaceFakeUpgradeOracle -ControlText $control
    if($target-ceq'f200'){
      Assert-Probe ($control.Contains('local technology_name="mining-productivity-4"') -and $specialized.Contains('local technology_name="mining-productivity-3"') -and $specialized.Contains('tech.level=5') -and $specialized.Contains('expected_progress=0.37')) 'SIF must retain level/progress checks on the Space Age native mining owner without changing the base-only fixture.'
    }
    Assert-Probe ($specialized.Contains('sif.capture()') -and $specialized.Contains('sif.verify("upgrade")') -and $specialized.Contains('sif.verify("reload")') -and $specialized.Contains('force.research_progress=expected_progress')) "actual $target staged fixture lost the original research oracle."
    Refuses-Probe {Add-MIR421SpaceFakeUpgradeOracle -ControlText $specialized} 'sif-fixture-anchor'
  }
  Refuses-Probe {Get-MIR421SpaceFakeUpgradeDescriptor -Target f110} 'sif-target'
  Refuses-Probe {Get-MIR421SpaceFakeUpgradeDescriptor -Target F210} 'sif-target'
  foreach($stage in @('source','upgrade','reload')) {
    Assert-MIR421SpaceFakeUpgradeMarker -Text "[mir-fixture] SIF-01 native continuations verified stage=$stage" -Stage $stage
    Refuses-Probe {Assert-MIR421SpaceFakeUpgradeMarker -Text 'generic load passed' -Stage $stage} "sif-$stage-marker"
    Refuses-Probe {Assert-MIR421SpaceFakeUpgradeMarker -Text "[mir-fixture] SIF-01 native continuations verified stage=$stage-incomplete" -Stage $stage} "sif-$stage-marker"
  }
  . (Join-Path $repo 'tools/lib/assurance/evidence/CommandExecution.ps1')
  $catalog=Get-Content -LiteralPath (Join-Path $repo 'validation/tests.yml') -Raw | ConvertFrom-Json
  $command=[string](@($catalog.tests | Where-Object id -CEQ 'runtime.material-route-guard')[0].command)
  foreach($line in @('2.0','2.1')) {
    $engine=if($line -ceq '2.0') { 'D:\Programs\Factorio\2.0\bin\x64\factorio.exe' } else { 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' }
    $resolved=Resolve-MIRAssuranceCommandText -Command $command -Context ([pscustomobject]@{factorio=$engine;target=$line}) -Plan ([pscustomobject]@{})
    Assert-Probe ($resolved.Contains("-FactorioBin '$engine'") -and $resolved.Contains("-ExpectedFactorioLine '$line'") -and $resolved.Contains('-ExpectedPeakMemoryMiB 2048') -and $resolved.Contains('-MaxNewOutputMiB 120')) "selected $line command lost its engine, line or explicit resource budgets."
    $browserCommand=[string](@($catalog.tests | Where-Object id -CEQ 'runtime.research-browser')[0].command)
    $browserResolved=Resolve-MIRAssuranceCommandText -Command $browserCommand -Context ([pscustomobject]@{factorio=$engine;target=$line;candidate='controlled-candidate.zip';mods='controlled-library'}) -Plan ([pscustomobject]@{})
    Assert-Probe ($browserResolved.Contains("-FactorioBin '$engine'") -and $browserResolved.Contains("-Target '$line'") -and $browserResolved.Contains('-ExpectedPeakMemoryMiB 2048') -and $browserResolved.Contains('-MaxNewOutputMiB 120')) "selected browser $line command lost its actual engine, target or resource budgets."
  }
  $arguments=@{RepoRoot=$repo;OutputRoot=$fixture;MaxNewOutputMiB=1}
  Refuses-Probe {New-MIRNativeProbeResourceContext @arguments} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'missing-budget refusal allocated staging.'
  Refuses-Probe {New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot 'D:\outside-native-probe' -ExpectedPeakMemoryMiB 1024} 'resource-output-root'
  foreach($script in @('tests/compiler/Test-MIRMaterialRoutes.ps1','tests/runtime/Test-MIRF210CurrentBobAngelTinRouteObserver.ps1','tests/runtime/Test-MIRF210CurrentBobAngelFinalRoutesObserver.ps1')) {
    $probeArguments=@{RepoRoot=$repo;FactorioBin='absent-engine';OutputRoot=$fixture}
    if($script.StartsWith('tests/runtime/')) {$probeArguments.ExactStageRoot=Join-Path $fixture 'absent-stage'}
    $expectedRefusal=if($script.StartsWith('tests/runtime/')){'mir-native-obsolete-runner'}else{'resource-peak-budget-required'}
    Refuses-Probe {& (Join-Path $repo $script) @probeArguments} $expectedRefusal
    Assert-Probe (-not (Test-Path -LiteralPath $fixture)) "$script allocated staging before refusal."
  }
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelTinRouteObserver.ps1') -RepoRoot $repo -PrepareOnly -OutputRoot $fixture} 'mir-native-obsolete-runner'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'PrepareOnly bypassed allocation admission.'
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelFinalRoutesObserver.ps1') -RepoRoot $repo -PrepareOnly -ExactStageRoot (Join-Path $fixture 'absent-stage') -OutputRoot $fixture} 'mir-native-obsolete-runner'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'Final observer PrepareOnly bypassed allocation admission.'
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRResearchBrowser.ps1') -RepoRoot $repo -FactorioBin 'absent-browser-engine' -CandidateZip 'absent-candidate' -LibraryDirectory 'absent-library' -OutputRoot $fixture} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'Browser harness allocated before peak-budget admission.'
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRPassiveRepair.ps1') -RepoRoot $repo -CandidateZip 'absent-passive-candidate' -FactorioBin 'absent-passive-engine' -OutputRoot $fixture} 'mir-native-obsolete-runner'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'Passive repair allocated or probed an engine before peak-budget admission.'
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRBobTinBrowserExplanation.ps1') -RepoRoot $repo -CandidateZip 'absent-tin-candidate' -BobModsDir 'absent-tin-library' -FactorioBin 'absent-tin-engine' -OutputRoot $fixture} 'mir-native-obsolete-runner'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'Tin browser allocated or probed an input before peak-budget admission.'
  foreach ($prepare in @($false,$true)) {
    Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobTinLevel4Continuation.ps1') -RepoRoot $repo -FactorioBin 'absent-tin-engine' -CandidateZip 'absent-tin-candidate' -SettingsPath 'absent-settings' -OutputRoot $fixture -PrepareOnly:$prepare} 'resource-peak-budget-required'
    Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'Tin continuation prepared inputs before resource admission.'
  }
  $context=New-MIRNativeProbeResourceContext @arguments -ExpectedPeakMemoryMiB 1024
  Assert-Probe (-not (Test-Path -LiteralPath $context.root)) 'successful admission allocated before caller initialization.'
  New-Item -ItemType Directory -Path $context.root | Out-Null
  $retirementPath=Join-Path $context.root 'retired-during-scan'
  $retiredDirectory=[IO.Directory]::CreateDirectory($retirementPath)
  Assert-Probe (-not(Test-MIR441RetiredDirectory $retiredDirectory)) 'a live directory was classified as retired.'
  Remove-Item -LiteralPath $retirementPath
  $retirementObserved=$false
  try {$null=@($retiredDirectory.EnumerateFileSystemInfos())} catch [IO.DirectoryNotFoundException] {$retirementObserved=$true}
  Assert-Probe ($retirementObserved-and(Test-MIR441RetiredDirectory $retiredDirectory)) 'actual native enumeration disappearance was not recognized.'
  [IO.File]::WriteAllText($retirementPath,'keep')
  Assert-Probe (-not(Test-MIR441RetiredDirectory $retiredDirectory)) 'a replacement file was mistaken for a retired directory.'
  $retirementUsage=Get-MIR441TreeUsage -Path $context.root
  Assert-Probe ($retirementUsage.complete-and$retirementUsage.files-eq1-and$retirementUsage.bytes-eq4) 'live output byte accounting changed.'
  Remove-Item -LiteralPath $retirementPath
  # Extract the consumed harness functions, rather than a second validator.
  # These tiny ZIPs contain only identity/module controls, not player packages.
  $browserTokens=$null;$browserErrors=$null
  $browserAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIRResearchBrowser.ps1'),[ref]$browserTokens,[ref]$browserErrors)
  Assert-Probe ($browserErrors.Count -eq 0) 'browser harness syntax differs.'
  # Execute the real argument contract and identity selection without launching
  # the harness, allocating a native environment or duplicating the codec.
  $selectionStatements=@(foreach($variable in @('targetKey','expectedIdentity')){
    $statement=@($browserAst.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -ceq ('$'+$variable)})
    Assert-Probe ($statement.Count-eq1) "browser identity assignment missing: $variable"
    $statement[0].Extent.Text
  })
  $browserBinding=[scriptblock]::Create($browserAst.ParamBlock.Extent.Text+"`n"+($selectionStatements-join"`n")+'; return $expectedIdentity')
  foreach($case in @(
    @{target='2.1';source='4.2.1';version='4.2.21001'},@{target='2.1';source='4.2.2';version='4.2.21002'},
    @{target='2.0';source='4.2.1';version='4.2.20001'},@{target='2.0';source='4.2.2';version='4.2.20002'}
  )){
    $selected=& $browserBinding -RepoRoot $repo -Target $case.target -SourceVersion $case.source
    Assert-Probe ($selected.distribution_version-ceq$case.version) 'browser caller selected the wrong maintenance identity.'
  }
  Assert-Probe ((& $browserBinding -RepoRoot $repo).distribution_version-ceq'4.2.21001') 'browser default changed.'
  Refuses-Probe {& $browserBinding -RepoRoot $repo -SourceVersion '4.2.3'} 'SourceVersion'
  foreach($name in @('Resolve-BrowserEnginePath','Test-BrowserCandidate')) {
    $definitions=@($browserAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false))
    Assert-Probe ($definitions.Count -eq 1) "expected one actual browser admission function: $name"
    . ([scriptblock]::Create($definitions[0].Extent.Text))
  }
  $tinAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIRBobTinBrowserExplanation.ps1'),[ref]$browserTokens,[ref]$browserErrors)
  Assert-Probe ($browserErrors.Count -eq 0) 'tin browser harness syntax differs.'
  foreach($name in @('Resolve-TinBrowserEnginePath','Test-TinBrowserCandidate')) {
    $definitions=@($tinAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false))
    Assert-Probe ($definitions.Count -eq 1) "expected one actual tin browser admission function: $name"
    . ([scriptblock]::Create($definitions[0].Extent.Text))
  }
  $currentTin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
  Assert-Probe ((Resolve-TinBrowserEnginePath $currentTin) -ceq $currentTin) 'tin browser changed its authorized engine path.'
  Refuses-Probe {Resolve-TinBrowserEnginePath 'D:\Programs\Factorio\2.0\bin\x64\factorio.exe'} 'engine-location'
  $browserEngines=@{}
  foreach($line in @('2.0','2.1')){
    $engineRoot=Join-Path $fixture ('configured-engine-'+$line)
    foreach($directory in @('bin/x64','data/base')){[IO.Directory]::CreateDirectory((Join-Path $engineRoot $directory))|Out-Null}
    $executable=Join-Path $engineRoot 'bin/x64/factorio.exe';[IO.File]::WriteAllText($executable,'controlled, never executed')
    [IO.File]::WriteAllText((Join-Path $engineRoot 'data/base/info.json'),(@{name='base';version=($line+'.77')}|ConvertTo-Json))
    $browserEngines[$line]=$executable
  }
  $historical=$browserEngines['2.0'];$current=$browserEngines['2.1']
  Refuses-Probe {Resolve-BrowserEnginePath -Line '2.0' -Requested ''} 'engine-location'
  Assert-Probe ((Resolve-BrowserEnginePath -Line '2.1' -Requested $current) -ceq $current) 'explicit relocated current engine was refused.'
  Assert-Probe ((Resolve-BrowserEnginePath -Line '2.0' -Requested $historical) -ceq $historical) 'explicit historical engine was refused.'
  Refuses-Probe {Resolve-BrowserEnginePath -Line '2.0' -Requested $current} 'engine-target'
  Refuses-Probe {Resolve-BrowserEnginePath -Line '2.1' -Requested $historical} 'engine-target'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  function New-ControlledBrowserArchive([string]$Line,$Identity,[string]$Variant='valid') {
    $directory=Join-Path $fixture ('browser-inputs/'+[guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $directory
    $fileName=if($Variant -ceq 'filename'){'wrong-name.zip'}else{$Identity.package_name}
    $path=Join-Path $directory $fileName
    $root='more-infinite-research_'+$Identity.distribution_version
    $info=[ordered]@{name='more-infinite-research';version=$Identity.distribution_version;factorio_version=$Line}
    if($Variant -ceq 'patch-zero'){$info.version=$info.version.Substring(0,$info.version.Length-2)+'00'}
    if($Variant -ceq 'patch-two'){$info.version=$info.version.Substring(0,$info.version.Length-2)+'02'}
    if($Variant -ceq 'patch-three'){$info.version=$info.version.Substring(0,$info.version.Length-2)+'03'}
    if($Variant -ceq 'wrong-target'){$info.factorio_version=if($Line -ceq '2.1'){'2.0'}else{'2.1'}}
    if($Variant -ceq 'root'){$root='wrong-root'}
    $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
    try {
      $infoText=ConvertTo-Json -InputObject $info -Compress
      if($Variant -ceq 'info-budget'){$infoText+=' '*64KB}
      $entry=$zip.CreateEntry($root+'/info.json');$writer=[IO.StreamWriter]::new($entry.Open())
      try{$writer.Write($infoText)}finally{$writer.Dispose()}
      if($Variant -ceq 'duplicate-info'){$null=$zip.CreateEntry($root+'/info.json')}
      $modules=@('research_browser.lua','research_browser_core.lua','research_browser_factorio_catalogue.lua','research_browser_mir_provider.lua','research_browser_actions.lua')
      foreach($module in $modules) {
        if($Variant -ceq 'missing-module' -and $module -ceq $modules[0]){continue}
        $entryName=$root+'/prototypes/mir/runtime/'+$module
        if($Variant -ceq 'nested-module' -and $module -ceq $modules[0]){$entryName=$root+'/nested/prototypes/mir/runtime/'+$module}
        $bytes=[IO.File]::ReadAllBytes((Join-Path $repo ('source/prototypes/mir/runtime/'+$module)))
        if($Variant -ceq 'changed-module' -and $module -ceq $modules[0]){$bytes[0]=$bytes[0] -bxor 1}
        $entry=$zip.CreateEntry($entryName);$stream=$entry.Open()
        try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
        if($Variant -ceq 'duplicate-module' -and $module -ceq $modules[0]){$null=$zip.CreateEntry($entryName)}
      }
      $target=if($Line -ceq '2.1'){'f210'}else{'f200'}
      $capabilitySources=@{
        'prototypes/mir/platform/factorio/browser_host.lua'='source/prototypes/mir/platform/factorio/browser_host.lua'
        'prototypes/mir/stage/data.lua'='source/prototypes/mir/stage/data.lua'
        'prototypes/mir/stage/control.lua'='source/prototypes/mir/stage/control.lua'
        'prototypes/mir/runtime/scripted_techs.lua'="source/adapters/$target/prototypes/mir/runtime/scripted_techs.lua"
        'prototypes/mir/platform/factorio/target_profiles.lua'="source/adapters/$target/prototypes/mir/platform/factorio/target_profiles.lua"
      }
      foreach($name in $capabilitySources.Keys){
        $bytes=[IO.File]::ReadAllBytes((Join-Path $repo $capabilitySources[$name]))
        if($Variant -ceq 'changed-coordinator' -and $name.EndsWith('/scripted_techs.lua')){$bytes[0]=$bytes[0] -bxor 1}
        if($Variant -ceq 'changed-capability' -and $name.EndsWith('/target_profiles.lua')){$bytes[0]=$bytes[0] -bxor 1}
        if($Variant -ceq 'changed-browser-host' -and $name.EndsWith('/browser_host.lua')){$bytes[0]=$bytes[0] -bxor 1}
        $entry=$zip.CreateEntry($root+'/'+$name);$stream=$entry.Open()
        try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
      }
      $extra=switch -CaseSensitive ($Variant) {
        'outside' {'outside/extra.lua'}
        'root-case' {$root.ToUpperInvariant()+'/extra.lua'}
        'traversal' {$root+'/../outside.lua'}
        'backslash' {$root+'/nested\extra.lua'}
        'forbidden-repo' {$root+'/fixtures/unowned.lua'}
        default {''}
      }
      if($extra){$null=$zip.CreateEntry($extra)}
    }finally{$zip.Dispose()}
    return $path
  }
  foreach($line in @('2.1','2.0')) {
    $code=if($line -ceq '2.1'){'210'}else{'200'}
    $identity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $code -SourceMinor 2 -SourcePatch 1
    $valid=New-ControlledBrowserArchive -Line $line -Identity $identity
    $checked=Test-BrowserCandidate -Candidate $valid -Line $line -Identity $identity -Repository $repo
    foreach($variant in @('changed-coordinator','changed-capability','changed-browser-host')){
      $mismatch=New-ControlledBrowserArchive -Line $line -Identity $identity -Variant $variant
      Refuses-Probe {Test-BrowserCandidate -Candidate $mismatch -Line $line -Identity $identity -Repository $repo} 'differs from the controlled source'
    }
    Assert-Probe ($checked.info.version -ceq $identity.distribution_version -and $checked.sha256 -ceq (Get-FileHash -LiteralPath $valid).Hash) "actual browser $line validator lost exact patch-one identity or input hash."
    if($line -ceq '2.1') {
      $tinChecked=Test-TinBrowserCandidate -Candidate $valid -Line $line -Identity $identity -Repository $repo
      Assert-Probe ($tinChecked.sha256 -ceq $checked.sha256 -and $tinChecked.info.version -ceq '4.2.21001') 'tin browser lost its actual current source-patch identity.'
      $forbidden=New-ControlledBrowserArchive -Line $line -Identity $identity -Variant forbidden-repo
      Refuses-Probe {Test-TinBrowserCandidate -Candidate $forbidden -Line $line -Identity $identity -Repository $repo} 'candidate-exclusions'
    }
    foreach($case in @(
      @{variant='patch-zero';error='candidate-identity'},@{variant='patch-two';error='candidate-identity'},
      @{variant='wrong-target';error='target mismatch'},@{variant='filename';error='candidate-identity'},
      @{variant='root';error='candidate-identity'},@{variant='outside';error='candidate-identity'},
      @{variant='root-case';error='candidate-identity'},@{variant='traversal';error='candidate-identity'},
      @{variant='backslash';error='candidate-identity'},@{variant='duplicate-info';error='one mod identity'},
      @{variant='info-budget';error='info-budget'},@{variant='missing-module';error='exactly one'},
      @{variant='nested-module';error='exactly one'},@{variant='duplicate-module';error='exactly one'},
      @{variant='changed-module';error='differs from the controlled source'}
    )) {
      $invalid=New-ControlledBrowserArchive -Line $line -Identity $identity -Variant $case.variant
      Refuses-Probe {Test-BrowserCandidate -Candidate $invalid -Line $line -Identity $identity -Repository $repo} $case.error
      if($line -ceq '2.1'){Refuses-Probe {Test-TinBrowserCandidate -Candidate $invalid -Line $line -Identity $identity -Repository $repo} $case.error}
    }
    $currentIdentity=& $browserBinding -RepoRoot $repo -Target $line -SourceVersion '4.2.2'
    $currentArchive=New-ControlledBrowserArchive -Line $line -Identity $currentIdentity
    $currentChecked=Test-BrowserCandidate -Candidate $currentArchive -Line $line -Identity $currentIdentity -Repository $repo
    Assert-Probe ($currentChecked.info.version-ceq$currentIdentity.distribution_version-and$currentChecked.sha256-ceq(Get-FileHash $currentArchive).Hash) 'browser rejected or mislabeled the explicit 4.2.2 archive.'
    Refuses-Probe {Test-BrowserCandidate -Candidate $valid -Line $line -Identity $currentIdentity -Repository $repo} 'candidate-identity'
    Refuses-Probe {Test-BrowserCandidate -Candidate $currentArchive -Line $line -Identity $identity -Repository $repo} 'candidate-identity'
    foreach($case in @(@{variant='patch-three';error='candidate-identity'},@{variant='changed-module';error='differs from the controlled source'})){
      $invalid=New-ControlledBrowserArchive -Line $line -Identity $currentIdentity -Variant $case.variant
      Refuses-Probe {Test-BrowserCandidate -Candidate $invalid -Line $line -Identity $currentIdentity -Repository $repo} $case.error
    }
  }
  $continuityAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIRBrowserPersonalStateContinuity.ps1'),[ref]$browserTokens,[ref]$browserErrors)
  Assert-Probe ($browserErrors.Count-eq 0) 'continuity harness syntax differs.'
  $continuityBinding=[scriptblock]::Create($continuityAst.ParamBlock.Extent.Text+'; return $SourceVersion')
  foreach($version in @('4.2.0','4.2.1','4.2.2')){
    Assert-Probe ((& $continuityBinding -CandidateArchive 'controlled' -RepositoryRoot $repo -SourceVersion $version)-ceq$version) 'continuity caller rejected a retained source version.'
  }
  Assert-Probe ((& $continuityBinding -CandidateArchive 'controlled' -RepositoryRoot $repo)-ceq'4.2.1') 'continuity default changed.'
  Refuses-Probe {& $continuityBinding -CandidateArchive 'controlled' -RepositoryRoot $repo -SourceVersion '4.2.3'} 'SourceVersion'
  . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
  foreach($name in @('Fail','Assert-True','Assert-Equal','Get-Sha256','Get-ZipEntry','Get-ZipEntrySha256','Get-ZipEntryText','Normalize-ZipMember','Test-Candidate')){
    $definitions=@($continuityAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$false))
    Assert-Probe ($definitions.Count-eq 1) "expected one continuity admission function: $name"
    . ([scriptblock]::Create($definitions[0].Extent.Text))
  }
  foreach($target in @('f210','f200')){
    $Target=$target.ToUpperInvariant();$line=if($target-ceq'f210'){'2.1'}else{'2.0'};$TargetContract=@{factorio_line=$line}
    $hostPath=Join-Path $repo 'source/prototypes/mir/runtime/research_browser.lua';$locale=Join-Path $repo 'source/locale/en/more-infinite-research.cfg'
    $readmePath=Join-Path $repo "source/presentation/$target/README.md.template"
    foreach($sourceVersion in @('4.2.0','4.2.1','4.2.2')){
      $identity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $target.Substring(1) -SourceMinor 2 -SourcePatch ([int]$sourceVersion.Split('.')[2])
      $ExpectedDistributionVersion=$identity.distribution_version;$ExpectedPackageRoot='more-infinite-research_'+$ExpectedDistributionVersion
      $ExpectedReadmeSha256=Get-MIRBrowserContinuityReadmeSha256 -RepositoryRoot $repo -Target $target -SourceVersion $sourceVersion -ReadmePath $readmePath
      $readmeBytes=[IO.File]::ReadAllBytes($readmePath)
      if($sourceVersion-cin@('4.2.1','4.2.2')){
        $readmeBytes=Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes $readmeBytes -DistributionVersion $ExpectedDistributionVersion -SourceVersion $sourceVersion
        Assert-Probe ((Get-MIR4Sha256Bytes -Bytes (Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes $readmeBytes -DistributionVersion $ExpectedDistributionVersion -SourceVersion $sourceVersion))-ceq$ExpectedReadmeSha256) 'private readme identity transformation is not idempotent.'
      }
      $valid=New-ControlledBrowserArchive -Line $line -Identity $identity
      $zip=[IO.Compression.ZipFile]::Open($valid,[IO.Compression.ZipArchiveMode]::Update)
      try{
        foreach($member in @(@{path='README.md';bytes=$readmeBytes},@{path='locale/en/more-infinite-research.cfg';bytes=[IO.File]::ReadAllBytes($locale)})){
          $entry=$zip.CreateEntry($ExpectedPackageRoot+'/'+$member.path);$stream=$entry.Open()
          try{$stream.Write($member.bytes,0,$member.bytes.Length)}finally{$stream.Dispose()}
        }
      }finally{$zip.Dispose()}
      $checked=Test-Candidate $valid $hostPath $locale $readmePath
      Assert-Probe ($checked.entry_hashes.readme_md-ceq$ExpectedReadmeSha256-and$checked.package_root-ceq$ExpectedPackageRoot) "continuity $target $sourceVersion admission lost materialized identity or README authority."
      if($sourceVersion-ceq'4.2.1'){
        $zip=[IO.Compression.ZipFile]::Open($valid,[IO.Compression.ZipArchiveMode]::Update)
        try{$zip.GetEntry($ExpectedPackageRoot+'/README.md').Delete();$entry=$zip.CreateEntry($ExpectedPackageRoot+'/README.md');$stream=$entry.Open();try{$bytes=[IO.File]::ReadAllBytes($readmePath);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}}finally{$zip.Dispose()}
        Refuses-Probe {Test-Candidate $valid $hostPath $locale $readmePath} 'README differs from expected governed hash'
        $invalid=New-ControlledBrowserArchive -Line $line -Identity $identity -Variant patch-two
        Refuses-Probe {Test-Candidate $invalid $hostPath $locale $readmePath} 'candidate distribution version'
      }
    }
    Refuses-Probe {Get-MIRBrowserContinuityReadmeSha256 -RepositoryRoot $repo -Target $target -SourceVersion '4.2.1' -ReadmePath $hostPath} 'readme-authority'
  }
  Refuses-Probe {Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes ([byte[]]@(65)) -DistributionVersion '4.2.21002'} 'source-patch'
  $source=Join-Path $fixture 'dependency.zip'
  [IO.File]::WriteAllBytes($source,[byte[]]::new(128KB))
  $archiveInput=[ordered]@{source_path=$source;file_name='dependency.zip';expected_sha256=Get-MIRImmutableInputSha256 $source;role='dependency-mod';identity=@{name='controlled'};provenance=@{kind='tiny-controlled-fixture'};immutable=$true}
  $auditCandidate=Join-Path $fixture 'more-infinite-research_4.2.21000.zip';[IO.File]::WriteAllBytes($auditCandidate,[byte[]]::new(64))
  & {
    # Consume the actual passive-repair input and engine adapters. The tiny
    # archive and mocked engine output prove staging/forwarding, not gameplay.
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIRPassiveRepair.ps1'),[ref]$tokens,[ref]$errors)
    Assert-Probe ($errors.Count-eq0) 'passive repair harness parse failed.'
    foreach($name in @('New-PassiveRepairInputLease','Invoke-ProbeEngine')){
      $functions=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$false))
      Assert-Probe ($functions.Count-eq1) "passive repair adapter missing: $name"
      . ([scriptblock]::Create($functions[0].Extent.Text))
    }
    $run=Join-Path $fixture 'passive-repair';$mods=Join-Path $run 'mods'
    New-Item -ItemType Directory -Path $run | Out-Null
    $inputLease=New-PassiveRepairInputLease -Candidate $auditCandidate -ExpectedSha256 (Get-MIRImmutableInputSha256 $auditCandidate) -RunRoot $run -ModsDirectory $mods
    try{
      Assert-Probe ($inputLease.record.require_hard_links-and$inputLease.record.inputs.Count-eq1) 'passive repair did not require one strict archive input.'
      Assert-Probe ((Get-MIRImmutableInputFileIdentity $auditCandidate)-ceq(Get-MIRImmutableInputFileIdentity (Join-Path $mods ([IO.Path]::GetFileName($auditCandidate))))) 'passive repair copied its candidate.'
      $terminal=Complete-MIRImmutableInputLease -Lease $inputLease
      $null=Assert-MIRImmutableInputTerminalReceipt -Receipt $terminal
      Assert-Probe ($terminal.inputs[0].role-ceq'candidate') 'passive repair lost candidate custody.'
    }finally{if(-not$inputLease.closed){$null=Complete-MIRImmutableInputLease -Lease $inputLease -Outcome failed}}
    $resources=[pscustomobject]@{controlled=$true};$engine='controlled-native-engine';$calls=[Collections.Generic.List[object]]::new()
    $stdout=Join-Path $run 'stdout.txt';$stderr=Join-Path $run 'stderr.txt'
    [IO.File]::WriteAllText($stdout,'controlled healthy output');[IO.File]::WriteAllText($stderr,'')
    function Invoke-MIRNativeProbeFactorioProcess {
      param($Context,[string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds)
      $calls.Add([pscustomobject]@{context=$Context;path=$FilePath;arguments=$Arguments;timeout=$TimeoutSeconds})
      [pscustomobject]@{stdout=$stdout;stderr=$stderr}
    }
    Invoke-ProbeEngine -Label controlled -Arguments @('--benchmark','owned-save.zip')
    Assert-Probe ($calls.Count-eq1-and$calls[0].context.controlled-and$calls[0].path-ceq$engine-and$calls[0].timeout-eq60) 'passive repair bypassed the governed actor.'
    $expected=@('--config',(Join-Path $run 'config.ini'),'--mod-directory',$mods,'--benchmark','owned-save.zip')
    Assert-Probe (($calls[0].arguments-join'|')-ceq($expected-join'|')) 'passive repair changed engine arguments.'
    [IO.File]::WriteAllText($stdout,'Exception at tick controlled')
    Refuses-Probe {Invoke-ProbeEngine -Label controlled-error -Arguments @('--create','owned-save.zip')} 'Passive repair controlled-error failed'
    Assert-Probe ((Get-Content -Raw (Join-Path $run 'controlled-error.log'))-ceq'Exception at tick controlled') 'passive repair discarded its failed log.'
  }
  & {
    $functions=@($tinAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Invoke-Engine'},$false))
    Assert-Probe ($functions.Count-eq1) 'tin browser engine adapter is missing.'
    . ([scriptblock]::Create($functions[0].Extent.Text))
    $run=Join-Path $fixture 'tin-browser';$mods=Join-Path $run 'mods'
    New-Item -ItemType Directory -Path (Join-Path $run 'userdata') | Out-Null
    $resources=[pscustomobject]@{controlled=$true};$engine='controlled-tin-engine'
    $calls=[Collections.Generic.List[object]]::new();$budgets=[Collections.Generic.List[object]]::new()
    $stdout=Join-Path $run 'stdout.txt';$stderr=Join-Path $run 'stderr.txt'
    [IO.File]::WriteAllText($stdout,'controlled output');[IO.File]::WriteAllText($stderr,'')
    [IO.File]::WriteAllText((Join-Path $run 'userdata/factorio-current.log'),'controlled native log')
    function Invoke-MIRNativeProbeFactorioProcess {
      param($Context,[string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds)
      $calls.Add([pscustomobject]@{context=$Context;path=$FilePath;arguments=$Arguments;timeout=$TimeoutSeconds})
      if($Arguments -contains 'controlled-failure'){throw 'controlled governed interruption'}
      [pscustomobject]@{stdout=$stdout;stderr=$stderr}
    }
    function Get-MIRNativeProbeRemainingOutputBytes {param($Context);$budgets.Add($Context);return 1MB}
    $log=Invoke-Engine create @('--create','owned-save.zip')
    Assert-Probe ($calls.Count-eq1-and$calls[0].context.controlled-and$calls[0].path-ceq$engine-and$calls[0].timeout-eq120) 'tin browser bypassed the governed actor.'
    $expected=@('--config',(Join-Path $run 'config.ini'),'--mod-directory',$mods,'--create','owned-save.zip')
    Assert-Probe (($calls[0].arguments-join'|')-ceq($expected-join'|')) 'tin browser changed its native arguments.'
    Assert-Probe ((Get-Content -LiteralPath $log -Raw)-ceq'controlled native log'-and$budgets.Count-eq1-and$budgets[0].controlled) 'tin browser lost its original native log or total output check.'
    Refuses-Probe {Invoke-Engine runtime @('controlled-failure')} 'controlled governed interruption'
    Assert-Probe ($budgets.Count-eq1-and-not(Test-Path -LiteralPath (Join-Path $run 'factorio-runtime.log'))) 'tin browser continued after governed failure.'
  }
  & {
    . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
    . (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
    $tokens=$null;$errors=$null
    $path=Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobTinLevel4Continuation.ps1'
    $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    Assert-Probe ($errors.Count-eq0) 'Tin continuation harness parse failed.'
    foreach($name in @('Assert-Tin','Read-TinCurrentCandidate','Invoke-TinGovernedEngine','Invoke-TinBoundedReload','Get-TinSha')) {
      $function=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$false))
      Assert-Probe ($function.Count-eq1) "Tin continuation consumed adapter absent: $name"
      . ([scriptblock]::Create($function[0].Extent.Text))
    }
    $k2Path=Join-Path $repo 'tests/runtime/Test-MIRK2213ImersiteContinuation.ps1'
    $k2Ast=[Management.Automation.Language.Parser]::ParseFile($k2Path,[ref]$tokens,[ref]$errors)
    Assert-Probe ($errors.Count-eq0) 'K2 continuation harness parse failed.'
    foreach($name in @('Fail-K2213','Assert-K2213','Get-K2213Sha256','Get-K2213Property','Read-K2213Json','Get-K2213ZipInfo','Assert-K2213ArchiveIdentity','Read-K2213CurrentCandidate','Read-K2213DependencyInputs','Read-K2213ProfileInputs')) {
      $function=@($k2Ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$false))
      Assert-Probe ($function.Count-eq1) "K2 continuation consumed adapter absent: $name"
      . ([scriptblock]::Create($function[0].Extent.Text))
    }
    $RepoRoot=$repo
    # Synthetic membership isolates the reader; this is not a MIR package.
    $run=Join-Path $fixture 'tin-continuation';New-Item -ItemType Directory -Path $run|Out-Null
    $candidate=Join-Path $run 'more-infinite-research_4.2.21001.zip'
    $receiptPath=Join-Path $run 'materialized.json'
    $bytes=[Text.Encoding]::UTF8.GetBytes('controlled runtime bytes')
    $binding=[pscustomobject]@{output_path='control.lua';output_bytes=$bytes.Length;output_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
    function Get-MIR4TargetMaterializerState {param($RepoRoot,$Target);[pscustomobject]@{manifest=@{record_sha256=('1'*64)};composition=@{record_sha256=('2'*64)}}}
    function Get-MIR4TargetMaterializationBindings {param($State);[pscustomobject]@{bindings=@([pscustomobject]@{output_path='info.json'},$binding)}}
    $zip=[IO.Compression.ZipFile]::Open($candidate,[IO.Compression.ZipArchiveMode]::Create)
    try {
      foreach($member in @(@{path='info.json';bytes=[Text.Encoding]::UTF8.GetBytes('{"name":"more-infinite-research","version":"4.2.21001","factorio_version":"2.1"}')},@{path='control.lua';bytes=$bytes})) {
        $stream=$zip.CreateEntry('more-infinite-research_4.2.21001/'+$member.path).Open()
        try{$stream.Write($member.bytes,0,$member.bytes.Length)}finally{$stream.Dispose()}
      }
    }finally{$zip.Dispose()}
    $inventory=Get-MIR4ArchiveInventory -Path $candidate
    $record=[ordered]@{schema=1;kind='MIR4PackageCompositionResultV1';status='passed-canonical-package-authority-materialization';materializer_abi='mir4-target-materializer/1';target='f210';candidate_id='CONTROLLED';source_version='4.2.1';distribution_version='4.2.21001';package_authority_sha256=('A'*64);package_source_sha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo;source_manifest_sha256=('1'*64);target_registry_sha256=('A'*64);support_policy_sha256=('A'*64);target_overlay_sha256=('2'*64);source_binding_count=2;omission_count=0;tree_path=$run;archive_path=$candidate;archive_sha256=$inventory.archive_sha256;content_sha256=$inventory.content_sha256;entry_count=$inventory.entry_count;invariants=[ordered]@{no_historical_archive_input=$true;all_source_hashes_verified=$true;all_output_hashes_verified=$true;all_target_differences_explicit=$true;scoped_operation_closure=$true;version_identity_verified=$true;canonical_package_authority=$true};transition_gate=[ordered]@{package_cutover=$true;old_writer_retirement=$true;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false};record_sha256=''}
    function Save-ControlledTinRecord {$record.record_sha256=Get-MIR4BootstrapRecordSha256 -Record ([pscustomobject]$record);$record|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $receiptPath -Encoding utf8}
    Save-ControlledTinRecord
    $read=Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath
    Assert-Probe ($read.path-ceq$candidate-and$read.receipt.distribution_version-ceq'4.2.21001') 'Tin continuation lost patch-one identity.'
    $k2Read=Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath
    Assert-Probe ($k2Read.path-ceq$candidate-and$k2Read.receipt.distribution_version-ceq'4.2.21001') 'K2 continuation did not consume the shared current-candidate reader.'
    Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive '' -ReceiptPath ''} 'supply candidate'
    $savedFingerprint=$record.package_source_sha256;$record.package_source_sha256='0'*64;Save-ControlledTinRecord
    Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath} 'candidate source fingerprint differs'
    Refuses-Probe {Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath} 'candidate source fingerprint differs'
    $record.package_source_sha256=$savedFingerprint
    foreach($version in @('4.2.21000','4.2.21002')) {
      $record.distribution_version=$version;Save-ControlledTinRecord
      Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath} 'candidate materialization identity differs'
      Refuses-Probe {Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath} 'candidate materialization identity differs'
    }
    $record.distribution_version='4.2.21001';$record.source_manifest_sha256='0'*64;Save-ControlledTinRecord
    Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath} 'candidate composition authority differs'
    $record.source_manifest_sha256='1'*64;Save-ControlledTinRecord
    $binding.output_sha256='0'*64
    Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath} 'candidate binding hash differs'
    Refuses-Probe {Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath} 'candidate binding hash differs'
    $binding.output_bytes++
    Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath} 'candidate binding size differs'
    Refuses-Probe {Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath} 'candidate binding size differs'

    # Consume the actual current-candidate reader for both explicit maintenance
    # versions. These tiny synthetic ZIPs isolate version/content refusal;
    # their mocked membership is not a player package or native acceptance.
    $binding.output_bytes=$bytes.Length
    $binding.output_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    foreach($target in @('f210','f200')) {
      foreach($sourceVersion in @('4.2.1','4.2.2')) {
        $identity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $target.Substring(1) -SourceMinor 2 -SourcePatch ([int]$sourceVersion.Split('.')[2])
        $caseRoot=Join-Path $run ($target+'-'+$sourceVersion);[IO.Directory]::CreateDirectory($caseRoot)|Out-Null
        $candidate=Join-Path $caseRoot $identity.package_name
        $receiptPath=Join-Path $caseRoot 'materialized.json'
        $line=if($target-ceq'f210'){'2.1'}else{'2.0'}
        $info=@{name='more-infinite-research';version=$identity.distribution_version;factorio_version=$line}|ConvertTo-Json -Compress
        $zip=[IO.Compression.ZipFile]::Open($candidate,[IO.Compression.ZipArchiveMode]::Create)
        try {
          foreach($member in @(@{path='info.json';bytes=[Text.Encoding]::UTF8.GetBytes($info)},@{path='control.lua';bytes=$bytes})) {
            $stream=$zip.CreateEntry(('more-infinite-research_'+$identity.distribution_version)+'/'+$member.path).Open()
            try{$stream.Write($member.bytes,0,$member.bytes.Length)}finally{$stream.Dispose()}
          }
        }finally{$zip.Dispose()}
        $inventory=Get-MIR4ArchiveInventory -Path $candidate
        $record.target=$target;$record.source_version=$sourceVersion;$record.distribution_version=$identity.distribution_version
        $record.archive_path=$candidate;$record.archive_sha256=$inventory.archive_sha256
        $record.content_sha256=$inventory.content_sha256;$record.entry_count=$inventory.entry_count
        Save-ControlledTinRecord
        $selected=@{Repository=$repo;Archive=$candidate;ReceiptPath=$receiptPath;Target=$target;SourceVersion=$sourceVersion}
        $read=Read-MIRNativeProbeCurrentCandidate @selected
        Assert-Probe ($read.path-ceq$candidate-and$read.receipt.source_version-ceq$sourceVersion) "explicit $target/$sourceVersion reader lost its selected identity."
        if($target-ceq'f210') {
          $wrapped=Read-MIRNativeProbeF210CurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath -SourceVersion $sourceVersion
          Assert-Probe ($wrapped.receipt.archive_sha256-ceq$inventory.archive_sha256) 'F210 wrapper lost explicit source selection.'
          $tinRead=Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath -SourceVersion $sourceVersion
          $k2Read=Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath -SourceVersion $sourceVersion
          Assert-Probe ($tinRead.receipt.source_version-ceq$sourceVersion-and$tinRead.receipt.archive_sha256-ceq$inventory.archive_sha256) 'Tin caller lost explicit maintenance identity.'
          Assert-Probe ($k2Read.receipt.source_version-ceq$sourceVersion-and$k2Read.receipt.archive_sha256-ceq$inventory.archive_sha256) 'K2 caller lost explicit maintenance identity.'
        }
        $other=if($sourceVersion-ceq'4.2.1'){'4.2.2'}else{'4.2.1'}
        if($target-ceq'f210') {
          Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath -SourceVersion $other} 'materialization identity differs'
          Refuses-Probe {Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath -SourceVersion $other} 'materialization identity differs'
          if($sourceVersion-ceq'4.2.2') {
            Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath} 'materialization identity differs'
            Refuses-Probe {Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath} 'materialization identity differs'
          }
        }
        Refuses-Probe {Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath -Target $target -SourceVersion $other} 'materialization identity differs'
        if($sourceVersion-ceq'4.2.2') {
          Refuses-Probe {Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath -Target $target} 'materialization identity differs'
        }
        $record.distribution_version=$record.distribution_version.Substring(0,$record.distribution_version.Length-2)+'00';Save-ControlledTinRecord
        Refuses-Probe {Read-MIRNativeProbeCurrentCandidate @selected} 'materialization identity differs'
        $record.distribution_version=$identity.distribution_version;$record.package_source_sha256='0'*64;Save-ControlledTinRecord
        Refuses-Probe {Read-MIRNativeProbeCurrentCandidate @selected} 'source fingerprint differs'
        $record.package_source_sha256=$savedFingerprint;Save-ControlledTinRecord
        $binding.output_sha256='0'*64
        Refuses-Probe {Read-MIRNativeProbeCurrentCandidate @selected} 'binding hash differs'
        if($target-ceq'f210') {
          Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath -SourceVersion $sourceVersion} 'binding hash differs'
          Refuses-Probe {Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath -SourceVersion $sourceVersion} 'binding hash differs'
        }
        $binding.output_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
      }
    }
    Refuses-Probe {Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath -SourceVersion '4.2.3'} 'SourceVersion'

    $flat=Join-Path $run 'flat-library';New-Item -ItemType Directory -Path $flat|Out-Null
    $dependency=Join-Path $flat 'controlled-k2_1.0.0.zip'
    $zip=[IO.Compression.ZipFile]::Open($dependency,[IO.Compression.ZipArchiveMode]::Create)
    try{$stream=[IO.StreamWriter]::new($zip.CreateEntry('controlled-k2_1.0.0/info.json').Open());try{$stream.Write('{"name":"controlled-k2","version":"1.0.0","factorio_version":"2.1"}')}finally{$stream.Dispose()}}finally{$zip.Dispose()}
    $retired=Join-Path $run 'retired-v5-profile/mods/controlled-k2_1.0.0.zip'
    $observation=[pscustomobject]@{staged_inputs=@([pscustomobject]@{source_path=$retired;sha256=Get-K2213Sha256 $dependency;source_match=$true;stage_match=$true})}
    $expected=[ordered]@{'controlled-k2_1.0.0.zip'=@('controlled-k2','1.0.0')}
    $portablePath=Join-Path $run 'portable-inputs.json'
    $portable=[ordered]@{schema=1;target='f210';factorio_line='2.1';engine_version='2.1.21';engine_sha256=('A'*64);runtime_api_sha256=('B'*64);settings_mode='Defaults';mods=@();archive_sha256=@{'controlled-k2_1.0.0.zip'=(Get-K2213Sha256 $dependency)}}
    foreach($name in @('base','elevated-rails','quality','recycler','space-age')){$portable.mods+=@{name=$name;version='2.1.21';enabled=$true}}
    $portable.mods+=@(@{name='controlled-k2';version='1.0.0';enabled=$true},@{name='more-infinite-research';version='4.2.21001';enabled=$true},@{name='mir-fixture-assert-k2-213-imersite-continuation';version='0.1.4';enabled=$true})
    function Save-ControlledK2Profile {$portable|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $portablePath}
    Save-ControlledK2Profile
    $bound=Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat)
    Assert-Probe ($bound.inputs.Count-eq1-and$bound.inputs[0].source_path-ceq$dependency-and$bound.profile.engine_version-ceq'2.1.21'-and$bound.inputs[0].provenance.profile_sha256-ceq(Get-K2213Sha256 $portablePath)) 'Portable K2 inputs lost exact archive or profile provenance.'
    foreach($selectedVersion in @('4.2.1','4.2.2')) {
      $distribution='4.2.2100'+$selectedVersion.Split('.')[2]
      $portable.mods[6].version=$distribution;Save-ControlledK2Profile
      $bound=Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat) -SourceVersion $selectedVersion
      Assert-Probe ($bound.profile.mods[6].version-ceq$distribution-and$bound.inputs[0].source_path-ceq$dependency) 'K2 profile lost explicit candidate or reused dependency.'
      $other=if($selectedVersion-ceq'4.2.1'){'4.2.2'}else{'4.2.1'}
      Refuses-Probe {Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat) -SourceVersion $other} 'input-profile-selection:more-infinite-research'
    }
    Refuses-Probe {Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat)} 'input-profile-selection:more-infinite-research'
    $portable.mods[6].version='4.2.21001';$portable.mods[7].version='0.1.3';Save-ControlledK2Profile
    Refuses-Probe {Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat)} 'input-profile-selection:mir-fixture'
    $portable.mods[7].version='0.1.4';Save-ControlledK2Profile
    Refuses-Probe {Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @((Join-Path $run 'absent-library'))} 'dependency-missing'
    $portable.archive_sha256['controlled-k2_1.0.0.zip']='0'*64;Save-ControlledK2Profile
    Refuses-Probe {Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat)} 'dependency-hash'
    $portable.archive_sha256['controlled-k2_1.0.0.zip']=Get-K2213Sha256 $dependency
    $portable.mods[5].version='1.0.1';Save-ControlledK2Profile
    Refuses-Probe {Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat)} 'input-profile-selection:controlled-k2'
    $portable.mods[5].version='1.0.0';$portable.mods[5].enabled='true';Save-ControlledK2Profile
    Refuses-Probe {Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat)} 'input-profile-selection:controlled-k2'
    $portable.mods[5].enabled=$true;$portable.mods+=@($portable.mods[0]);Save-ControlledK2Profile
    Refuses-Probe {Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat)} 'input-profile-selection-count'
    $portable.mods=@($portable.mods|Select-Object -First 8);$portable.settings_mode='Inherit';Save-ControlledK2Profile
    Refuses-Probe {Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat)} 'input-profile-settings'
    $portable.settings_mode='Defaults';$portable.engine_version='2.1.22';Save-ControlledK2Profile
    Refuses-Probe {Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat)} 'input-profile-engine-version'
    $portable.engine_version='2.1.21';$portable.runtime_api_sha256='';Save-ControlledK2Profile
    Refuses-Probe {Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat)} 'input-profile-hash:runtime_api_sha256'
    $portable.runtime_api_sha256='B'*64;$portable.archive_sha256['unexpected.zip']='C'*64;Save-ControlledK2Profile
    Refuses-Probe {Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($flat)} 'input-profile-archive-count'
    $portable.archive_sha256.Remove('unexpected.zip');Save-ControlledK2Profile
    $relocated=Join-Path $run 'relocated-library'
    $ownedRoot=[IO.Path]::GetFullPath($run).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    foreach($movePath in @($flat,$relocated)){Assert-Probe ([IO.Path]::GetFullPath($movePath).StartsWith($ownedRoot,[StringComparison]::OrdinalIgnoreCase)) 'Tiny relocation escaped its owned fixture root.'}
    Move-Item -LiteralPath $flat -Destination $relocated
    try{
      $moved=Read-K2213ProfileInputs -Path $portablePath -ExpectedDependencies $expected -Libraries @($relocated)
      Assert-Probe ($moved.inputs[0].source_path-ceq(Join-Path $relocated 'controlled-k2_1.0.0.zip')-and$moved.inputs[0].expected_sha256-ceq$portable.archive_sha256['controlled-k2_1.0.0.zip']) 'Portable K2 profile depended on its original library location.'
    }finally{Move-Item -LiteralPath $relocated -Destination $flat}
    Assert-Probe (-not(Test-Path -LiteralPath (Join-Path $run 'retired-v5-profile'))-and@(Get-ChildItem -LiteralPath $flat -File).Count-eq1) 'Portable K2 inputs recreated profiles or archive payloads.'
    $observationPath=Join-Path $run 'controlled-v5.json';$observation|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $observationPath
    $resolved=@(Read-K2213DependencyInputs -Observation $observation -ExpectedDependencies $expected -Libraries @($flat) -ObservationPath $observationPath)
    Assert-Probe ($resolved.Count-eq1-and$resolved[0].source_path-ceq$dependency-and$resolved[0].provenance.historical_source_path-ceq$retired) 'K2 resolution lost shared archive or historical custody.'
    Assert-Probe (-not(Test-Path -LiteralPath (Join-Path $run 'retired-v5-profile'))) 'K2 library resolution recreated a retired profile.'
    Refuses-Probe {Read-K2213DependencyInputs -Observation $observation -ExpectedDependencies $expected -Libraries @((Join-Path $run 'absent-library')) -ObservationPath $observationPath} 'dependency-missing'
    $observation.staged_inputs[0].sha256='0'*64
    Refuses-Probe {Read-K2213DependencyInputs -Observation $observation -ExpectedDependencies $expected -Libraries @($flat) -ObservationPath $observationPath} 'dependency-hash'
    $observation.staged_inputs[0].sha256=Get-K2213Sha256 $dependency
    $observation.staged_inputs+=@($observation.staged_inputs[0])
    Refuses-Probe {Read-K2213DependencyInputs -Observation $observation -ExpectedDependencies $expected -Libraries @($flat) -ObservationPath $observationPath} 'v5-dependency-lock'
    $observation.staged_inputs=@($observation.staged_inputs[0]);$observation.staged_inputs[0].source_match=$false
    Refuses-Probe {Read-K2213DependencyInputs -Observation $observation -ExpectedDependencies $expected -Libraries @($flat) -ObservationPath $observationPath} 'v5-dependency-lock-integrity'
    $observation.staged_inputs[0].source_match=$true
    $expected['controlled-k2_1.0.0.zip']=@('wrong-identity','1.0.0')
    Refuses-Probe {Read-K2213DependencyInputs -Observation $observation -ExpectedDependencies $expected -Libraries @($flat) -ObservationPath $observationPath} 'archive-name'

    $function=@($k2Ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Invoke-MIRCompatFactorioProcess'},$false))
    Assert-Probe ($function.Count-eq1) 'K2 continuation governed collector adapter absent.'
    . ([scriptblock]::Create($function[0].Extent.Text))
    $controlledEngine=Join-Path $run 'engine/bin/x64/factorio.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $controlledEngine),(Join-Path $run 'engine/data'),(Join-Path $run 'saves')|Out-Null
    [IO.File]::WriteAllText($controlledEngine,'controlled actor locator; not an executable')
    $data=Join-Path $run 'engine/data'
    New-Item -ItemType Directory -Path (Join-Path $data 'base')|Out-Null
    [IO.File]::WriteAllText((Join-Path $data 'base/info.json'),'{"name":"base","version":"2.1.20","dependencies":[]}')
    $profilePath=Join-Path $run 'selection.json'
    [IO.File]::WriteAllText($profilePath,'{"mods":[{"name":"base","version":"2.1.20","enabled":true},{"name":"controlled-k2","version":"1.0.0","enabled":true}]}')
    $activation=Start-MIRLibraryActivation -LibraryDirectory $flat -EngineDataDirectory $data -ProfilePath $profilePath -ArchiveHashes @{'controlled-k2_1.0.0.zip'=(Get-K2213Sha256 $dependency)}
    try {
    $resources=[pscustomobject]@{controlled=$true};$engine=$controlledEngine;$calls=[Collections.Generic.List[object]]::new()
    $tinActorStdout=Join-Path $run 'actor.stdout';$tinActorStderr=Join-Path $run 'actor.stderr'
    [IO.File]::WriteAllText($tinActorStdout,'controlled healthy output');[IO.File]::WriteAllText($tinActorStderr,'')
    [IO.File]::WriteAllText((Join-Path $run 'factorio-current.log'),'controlled native log')
    function Invoke-MIRNativeProbeFactorioProcess {param($Context,$FilePath,$Arguments,$TimeoutSeconds);$calls.Add(@{context=$Context;path=$FilePath;arguments=$Arguments;timeout=$TimeoutSeconds});if($Arguments-contains'controlled-failure'){throw 'controlled governed interruption'};[IO.File]::WriteAllLines((Join-Path $run 'factorio-current.log'),@($activation.selected|ForEach-Object {'0.1 Loading mod '+$_.name+' '+$_.version+' (data.lua)'}));[pscustomobject]@{stdout=$tinActorStdout;stderr=$tinActorStderr;result=@{duration_seconds=0.01}}}
    function Get-MIRNativeProbeRemainingOutputBytes {param($Context);return 1MB}
    $config=Join-Path $run 'mir-compat-config.ini'
    [IO.File]::WriteAllText($config,"[path]`nread-data=$data`nwrite-data=$run`n[other]`nenable-new-mods=false`n")
    $save=Join-Path $run 'owned-save.zip' ;[IO.File]::WriteAllText($save,'controlled saved state')
    $reload=Invoke-TinBoundedReload -Factorio $engine -RunRoot $run -Scenario controlled -SavePath $save -Ticks 30000 -TimeoutSeconds 240
    Assert-Probe ($reload.passed-and$reload.save_byte_identical-and$reload.benchmark_ticks-eq30000) 'Tin continuation lost saved-state and tick bounds.'
    Assert-Probe ($calls.Count-eq1-and$calls[0].context.controlled-and$calls[0].path-ceq$engine-and$calls[0].timeout-eq240-and'--benchmark-sanitize'-in$calls[0].arguments) 'Tin continuation bypassed governor or changed reload arguments.'
    Refuses-Probe {Invoke-TinGovernedEngine -Scenario refused -Arguments @($calls[0].arguments+'controlled-failure') -TimeoutSeconds 240} 'controlled governed interruption'
    Assert-Probe (-not(Test-Path -LiteralPath (Join-Path $run 'refused.factorio.log'))) 'Tin continuation wrote a successful log after interruption.'
    Assert-Probe ($calls[0].arguments[[Array]::IndexOf($calls[0].arguments,'--mod-directory')+1]-ceq$flat) 'Tin reload did not use the selected master library.'
    $beforeWrongPath=$calls.Count
    $wrongPathArgs=@($calls[0].arguments);$wrongPathArgs[[Array]::IndexOf($wrongPathArgs,'--mod-directory')+1]=Join-Path $run 'obsolete-mods'
    Refuses-Probe {Invoke-TinGovernedEngine -Scenario wrong-library -Arguments $wrongPathArgs -TimeoutSeconds 240} 'mir-library-launch-directory'
    Assert-Probe ($calls.Count-eq$beforeWrongPath-and-not(Test-Path -LiteralPath (Join-Path $run 'obsolete-mods'))) 'Tin ran or staged after an obsolete library path.'
    $calls.Clear();$budgets=[Collections.Generic.List[object]]::new()
    function Get-MIRNativeProbeRemainingOutputBytes {param($Context);$budgets.Add($Context);return 1MB}
    function Invoke-MIRNativeProbeFactorioProcess {
      param($Context,$FilePath,$Arguments,$TimeoutSeconds)
      $calls.Add(@{context=$Context;path=$FilePath;arguments=$Arguments;timeout=$TimeoutSeconds})
      if($Arguments-contains'controlled-failure'){throw 'controlled governed interruption'}
      $index=[Array]::IndexOf($Arguments,'--create')
      if($index-ge0){[IO.File]::WriteAllText($Arguments[$index+1],'controlled save; not Factorio data');$marker='initial'}else{$marker='reload'}
      $lines=@($activation.selected|ForEach-Object {'0.1 Loading mod '+$_.name+' '+$_.version+' (data.lua)'})
      $lines+=('0.2 Script @__controlled-k2__/data-final-fixes.lua:1: [MIR_ACTIVE_MODS] '+(@($activation.selected|Sort-Object name|ForEach-Object {$_.name+'@'+$_.version})-join '|'))
      $lines+=('[MIR42_K2_213_IMERSITE_CONTINUATION] stage='+$marker+';completed_level=4;next_level=5;bonus=0.08;progress=0.42')
      [IO.File]::WriteAllLines((Join-Path $run 'factorio-current.log'),$lines)
      [pscustomobject]@{stdout=$tinActorStdout;stderr=$tinActorStderr;result=@{passed=$true;exit_code=0;timed_out=$false;duration_seconds=0.01}}
    }
    $create=Invoke-MIRFactorioLoadCheck -FactorioBin $controlledEngine -UserDataDir $run -ScenarioName controlled-k2 -ScenarioTimeoutSeconds 90 -LibraryActivation $activation -ActiveModsObserver controlled-k2
    $reload=Invoke-MIRFactorioReloadContract -FactorioBin $controlledEngine -UserDataDir $run -ScenarioName controlled-k2 -SavePath $create.save -RequiredReloadCount 1 -MaxReloadDurationSeconds 90 -RequiredLogFragments '[MIR42_K2_213_IMERSITE_CONTINUATION] stage=reload;completed_level=4;next_level=5;bonus=0.08;progress=0.42' -LibraryActivation $activation -ActiveModsObserver controlled-k2
    Assert-Probe ($create.passed-and$reload.passed-and$calls.Count-eq2-and$budgets.Count-eq2) 'K2 create/reload collectors did not use the shared governed row.'
    Assert-Probe ($calls[0].context.controlled-and$calls[1].context.controlled-and$calls[0].path-ceq$controlledEngine-and$calls[0].timeout-eq90-and$calls[1].timeout-eq90) 'K2 collector lost actor/context/timeout identity.'
    Assert-Probe ('--create'-in$calls[0].arguments-and'--benchmark'-in$calls[1].arguments-and'--benchmark-sanitize'-in$calls[1].arguments-and$reload.reloads[0].save_byte_identical) 'K2 native create/reload arguments or saved-state custody changed.'
    Assert-Probe ($create.stderr_sha256-ceq'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'-and$reload.reloads[0].reload_log_contract_passed) 'K2 collector lost stderr or exact reload-marker checks.'
    $refusedOut=Join-Path $run 'k2-refused.stdout';$refusedErr=Join-Path $run 'k2-refused.stderr'
    Refuses-Probe {Invoke-MIRCompatFactorioProcess -FactorioBin $controlledEngine -ArgumentList @($calls[0].arguments+'controlled-failure') -StdoutPath $refusedOut -StderrPath $refusedErr -TimeoutSeconds 90 -LibraryActivation $activation} 'controlled governed interruption'
    Assert-Probe ($budgets.Count-eq2-and-not(Test-Path -LiteralPath $refusedOut)-and-not(Test-Path -LiteralPath $refusedErr)) 'K2 collector continued or wrote success after governed interruption.'
    } finally {$null=Complete-MIRLibraryActivation $activation}
  }
  $auditRun=Join-Path $fixture 'material-audit';New-Item -ItemType Directory -Path $auditRun|Out-Null
  $auditLease=New-MIRMaterialAuditInputLease -RunRoot $auditRun -ModsDirectory (Join-Path $auditRun 'mods') -CandidateArchive $auditCandidate -DependencyDirectory $fixture -ExpectedArchives ([ordered]@{'dependency.zip'=$archiveInput.expected_sha256})
  try{
    Assert-Probe ($auditLease.record.require_hard_links-and$auditLease.record.inputs.Count-eq 2) 'material audit did not require strict candidate/dependency inputs.'
    foreach($input in $auditLease.record.inputs){Assert-Probe ((Get-MIRImmutableInputFileIdentity $input.source_path)-ceq(Get-MIRImmutableInputFileIdentity $input.stage_path)) 'material audit copied an archive.'}
    $auditTerminal=Complete-MIRImmutableInputLease -Lease $auditLease
    $null=Assert-MIRImmutableInputTerminalReceipt -Receipt $auditTerminal
    Assert-Probe (($auditTerminal.inputs.role-join'|')-ceq'candidate|dependency-mod') 'material audit lost candidate/dependency roles.'
  }finally{if(-not$auditLease.closed){$null=Complete-MIRImmutableInputLease -Lease $auditLease -Outcome failed}}
  $badRun=Join-Path $fixture 'material-audit-invalid'
  Refuses-Probe {New-MIRMaterialAuditInputLease -RunRoot $badRun -ModsDirectory (Join-Path $badRun 'mods') -CandidateArchive $auditCandidate -DependencyDirectory $fixture -ExpectedArchives ([ordered]@{'dependency.zip'=('0'*64)})} 'dependency-hash'
  Assert-Probe (-not(Test-Path -LiteralPath $badRun)) 'material audit allocated before exact dependency validation.'
  Refuses-Probe {New-MIRMaterialAuditInputLease -RunRoot $badRun -ModsDirectory (Join-Path $badRun 'mods') -CandidateArchive $auditCandidate -DependencyDirectory $fixture -ExpectedArchives ([ordered]@{'absent.zip'=$archiveInput.expected_sha256})} 'dependency-missing'
  . (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
  $compatMods=Join-Path $fixture 'compat-mods';New-Item -ItemType Directory -Path $compatMods | Out-Null
  $compatEntry=[pscustomobject]@{file_name='dependency.zip';source_path=$source;sha256=$archiveInput.expected_sha256}
  Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($compatEntry)
  Assert-Probe ((Get-MIRImmutableInputFileIdentity (Join-Path $compatMods 'dependency.zip')) -ceq (Get-MIRImmutableInputFileIdentity $source)) 'compatibility staging copied a shared archive.'
  Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($compatEntry)
  Assert-Probe ((Get-MIRImmutableInputSha256 $source) -ceq $compatEntry.sha256) 'matching alias reuse changed canonical bytes.'
  Refuses-Probe {Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($compatEntry) -LinkMode Copy} 'Hardlink'
  Refuses-Probe {Copy-MIRModUnderTest -RepoRoot $repo -ModsDir $compatMods} 'package-required'
  $badEntry=[pscustomobject]@{file_name='../outside.zip';source_path=$source}
  Refuses-Probe {Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($badEntry)} 'archive-name'
  $badEntry=[pscustomobject]@{file_name='missing.zip';source_path=(Join-Path $fixture 'missing.zip')}
  Refuses-Probe {Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($badEntry)} 'archive-missing'
  $badEntry=[pscustomobject]@{file_name='wrong-hash.zip';source_path=$source;sha256=('0'*64)}
  Refuses-Probe {Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($badEntry)} 'archive-hash'
  [IO.File]::WriteAllBytes((Join-Path $compatMods 'unrelated.zip'),[byte[]]::new(16))
  $badEntry=[pscustomobject]@{file_name='unrelated.zip';source_path=$source}
  Refuses-Probe {Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($badEntry)} 'archive-alias'
  $packageMods=Join-Path $fixture 'compat-package';New-Item -ItemType Directory -Path $packageMods | Out-Null
  $linkedPackage=Copy-MIRModUnderTest -RepoRoot $repo -ModsDir $packageMods -ZipPath $source
  Assert-Probe ((Get-MIRImmutableInputFileIdentity $linkedPackage) -ceq (Get-MIRImmutableInputFileIdentity $source)) 'mod-under-test ZIP was copied.'
  $sharedLibraryArchive=Join-Path $fixture 'dependency_1.zip'
  New-Item -ItemType HardLink -Path $sharedLibraryArchive -Target $source | Out-Null
  $controlledDescriptor=[pscustomobject]@{line='controlled';target='controlled';inputs=@([pscustomobject]@{name='dependency';version='1';sha256=$archiveInput.expected_sha256})}
  $configuredInputs=@(Resolve-MIR421SpaceFakeUpgradeInputs -RepoRoot $fixture -Descriptor $controlledDescriptor -LocalModLibraryDirs @((Join-Path $fixture 'absent-library'),$fixture))
  Assert-Probe ($configuredInputs.Count -eq 1 -and $configuredInputs[0].source_path -ceq $sharedLibraryArchive) 'SIF inputs did not resolve the retained shared library.'
  Assert-Probe (-not (Test-Path -LiteralPath (Join-Path $fixture 'build/tmp/mir421-sif-input-lookup-controlled'))) 'SIF library lookup created a profile.'
  Refuses-Probe {Resolve-MIR421SpaceFakeUpgradeInputs -RepoRoot $fixture -Descriptor $controlledDescriptor -LocalModLibraryDirs @((Join-Path $fixture 'absent-library'))} 'dependency-missing'
  $emptyStage=Join-Path $fixture 'empty-preserved-stage'
  $lookup=Resolve-MIRNativeProbeDependencyInputs -StageRoot $emptyStage -ExpectedArchives @{'dependency.zip'=$archiveInput.expected_sha256} -LocalModLibraryDirs @($fixture)
  Assert-Probe ($lookup['dependency.zip'].source_path -ceq $source -and $lookup['dependency.zip'].provenance_kind -ceq 'verified-local-dependency-library' -and -not (Test-Path -LiteralPath $emptyStage)) 'missing-stage lookup failed or restored a staging copy.'
  $flatOnly=Resolve-MIRNativeProbeDependencyInputs -ExpectedArchives @{'dependency.zip'=$archiveInput.expected_sha256} -LocalModLibraryDirs @($fixture)
  Assert-Probe ($flatOnly['dependency.zip'].source_path -ceq $source -and $flatOnly['dependency.zip'].provenance_kind -ceq 'verified-local-dependency-library') 'flat-only lookup needed a retained profile.'
  Refuses-Probe {Resolve-MIRNativeProbeDependencyInputs -StageRoot $emptyStage -ExpectedArchives @{'dependency.zip'=$archiveInput.expected_sha256}} 'dependency-missing'
  $lookupStage=Join-Path $fixture 'lookup-stage';New-Item -ItemType Directory -Path (Join-Path $lookupStage 'mods')|Out-Null
  $stageArchive=Join-Path $lookupStage 'mods/dependency.zip';[IO.File]::Copy($source,$stageArchive)
  $lookup=Resolve-MIRNativeProbeDependencyInputs -StageRoot $lookupStage -ExpectedArchives @{'dependency.zip'=$archiveInput.expected_sha256} -LocalModLibraryDirs @($fixture)
  Assert-Probe ($lookup['dependency.zip'].source_path -ceq $stageArchive -and $lookup['dependency.zip'].provenance_kind -ceq 'exact-preserved-stage') 'verified original stage did not retain priority.'
  [IO.File]::WriteAllText($stageArchive,'controlled wrong stage bytes')
  Refuses-Probe {Resolve-MIRNativeProbeDependencyInputs -StageRoot $lookupStage -ExpectedArchives @{'dependency.zip'=$archiveInput.expected_sha256} -LocalModLibraryDirs @($fixture)} 'dependency-hash'
  Refuses-Probe {Resolve-MIRNativeProbeDependencyInputs -StageRoot $emptyStage -ExpectedArchives @{'../dependency.zip'=$archiveInput.expected_sha256} -LocalModLibraryDirs @($fixture)} 'dependency-identity'
  $leaseRoot=Join-Path $context.root 'stage';New-Item -ItemType Directory -Path $leaseRoot | Out-Null
  Refuses-Probe {New-MIRImmutableInputLease -RunRoot $leaseRoot -StageDirectory (Join-Path $leaseRoot 'mods') -Inputs @($archiveInput) -RequireHardLinks -ForceCopy} 'cannot request copy mode'
  $lease=New-MIRImmutableInputLease -RunRoot $leaseRoot -StageDirectory (Join-Path $leaseRoot 'mods') -Inputs @($archiveInput) -RequireHardLinks
  Assert-Probe ((Get-MIRUpgradeLinkedArchiveBytes -Lease $lease) -eq 128KB) 'SIF byte allowance was not backed by the actual strict hardlink lease.'
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

  # Two upgrade phases share dependency/archive bytes and keep distinct custody.
  # These tiny text inputs exercise staging; they are not Factorio packages.
  $sourceProfileLease=$null;$candidateProfileLease=$null;$plainProfileLease=$null
  try {
    $sourceArchive=Join-Path $fixture 'more-infinite-research_4.2.20000.zip'
    $candidateArchive=Join-Path $fixture 'more-infinite-research_4.2.20001.zip'
    [IO.File]::WriteAllText($sourceArchive,'controlled predecessor')
    [IO.File]::WriteAllText($candidateArchive,'controlled candidate')
    $sourceProfileLease=New-MIRUpgradeLinkedProfile -RunRoot (Join-Path $context.root 'source-profile') -Dependencies @($archiveInput) -Archive $sourceArchive -ExpectedSha256 (Get-MIRImmutableInputSha256 $sourceArchive) -Version '4.2.20000' -Role source
    $sourceBytes=Get-MIRUpgradeLinkedArchiveBytes -Lease $sourceProfileLease
    $null=Complete-MIRImmutableInputLease -Lease $sourceProfileLease -Outcome passed
    Assert-Probe ((Get-MIRUpgradeLinkedArchiveBytes -Lease $sourceProfileLease) -eq $sourceBytes) 'completed source-profile aliases lost their verified byte accounting.'
    $candidateProfileLease=New-MIRUpgradeLinkedProfile -RunRoot (Join-Path $context.root 'candidate-profile') -Dependencies @($archiveInput) -Archive $candidateArchive -ExpectedSha256 (Get-MIRImmutableInputSha256 $candidateArchive) -Version '4.2.20001' -Role candidate
    Assert-Probe (@($candidateProfileLease.record.inputs | Where-Object staging_mode -CNE 'hardlink').Count -eq 0) 'candidate profile copied an archive.'
    Assert-Probe (-not (Test-Path -LiteralPath (Join-Path $candidateProfileLease.record.stage_directory 'more-infinite-research_4.2.20000.zip'))) 'candidate profile retained the obsolete MIR version.'
    $sourceMods=$sourceProfileLease.record.stage_directory;$targetMods=$candidateProfileLease.record.stage_directory
    New-Item -ItemType Directory -Path (Join-Path $sourceMods 'controlled-fixture') | Out-Null
    [IO.File]::WriteAllText((Join-Path $sourceMods 'controlled-fixture/control.lua'),'controlled fixture')
    $settingsPath=Join-Path $sourceMods 'mod-settings.dat'
    [IO.File]::WriteAllBytes($settingsPath,[byte[]](1,2,3,4))
    $settingsHash=Get-MIRImmutableInputSha256 $settingsPath
    Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName 'controlled-fixture'
    Assert-Probe ((Get-MIRImmutableInputSha256 (Join-Path $targetMods 'mod-settings.dat')) -ceq $settingsHash -and -not (Test-Path -LiteralPath $settingsPath)) 'profile switch lost or duplicated writable settings.'
    Assert-Probe (Test-Path -LiteralPath (Join-Path $targetMods 'controlled-fixture/control.lua')) 'profile switch lost the specialized fixture.'
    Refuses-Probe {Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName '../outside'} 'move-boundary'
    Refuses-Probe {Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $fixture -FixtureName 'controlled-fixture'} 'move-boundary'
    Refuses-Probe {Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName 'controlled-fixture'} 'fixture-missing'
    New-Item -ItemType Directory -Path (Join-Path $sourceMods 'controlled-fixture') | Out-Null
    Refuses-Probe {Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName 'controlled-fixture'} 'state-collision'
    New-Item -ItemType Directory -Path (Join-Path $sourceMods 'settings-collision-fixture') | Out-Null
    [IO.File]::WriteAllBytes($settingsPath,[byte[]](5,6,7,8))
    Refuses-Probe {Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName 'settings-collision-fixture'} 'state-collision'
    Assert-Probe (Test-Path -LiteralPath (Join-Path $sourceMods 'settings-collision-fixture')) 'settings collision partially moved the fixture.'
    $null=Complete-MIRImmutableInputLease -Lease $candidateProfileLease -Outcome passed
    $plainProfileLease=New-MIRUpgradeLinkedProfile -RunRoot (Join-Path $context.root 'plain-profile') -Dependencies @() -Archive $candidateArchive -ExpectedSha256 (Get-MIRImmutableInputSha256 $candidateArchive) -Version '4.2.20001' -Role candidate
    Assert-Probe ($plainProfileLease.record.inputs.Count -eq 1 -and $plainProfileLease.record.inputs[0].staging_mode -ceq 'hardlink') 'base-only upgrade copied its archive or required a mod-set profile.'
    $plainMods=$plainProfileLease.record.stage_directory
    New-Item -ItemType Directory -Path (Join-Path $plainMods 'controlled-fixture_1.0.0') | Out-Null
    Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $plainMods -TargetMods $targetMods -FixtureName 'controlled-fixture_1.0.0'
    Assert-Probe (Test-Path -LiteralPath (Join-Path $targetMods 'controlled-fixture_1.0.0')) 'versioned historical fixture directory did not survive a profile switch.'
    $null=Complete-MIRImmutableInputLease -Lease $plainProfileLease -Outcome passed
    $sourceProfileLease.record.outcome='failed'
    Refuses-Probe {Get-MIRUpgradeLinkedArchiveBytes -Lease $sourceProfileLease} 'completed passed'
  } finally {
    foreach ($profileLease in @($sourceProfileLease,$candidateProfileLease,$plainProfileLease)) {
      if ($null -ne $profileLease -and -not $profileLease.closed) { Close-MIRImmutableInputLeaseHandles -Lease $profileLease }
    }
  }

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
  Refuses-Probe {New-MIRNativeProbeTargetPackage -Context $context -RepoRoot $fakeRepo -Target f200} 'observer-target'
  foreach($target in @('f210','f200')) {
    $browserPackage=New-MIRNativeProbeTargetPackage -Context $context -RepoRoot $fakeRepo -Target $target -CandidatePrefix BROWSER
    $browserIdentity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $target.Substring(1) -SourceMinor 2 -SourcePatch 1
    Assert-Probe ($browserPackage.target -ceq $target -and $browserPackage.source_version -ceq '4.2.1' -and $browserPackage.distribution_version -ceq $browserIdentity.distribution_version -and $browserPackage.candidate_id.StartsWith($target.ToUpperInvariant()+'-BROWSER-') -and -not $browserPackage.actual_package) "browser driver lost the exact $target source-patch or target identity."
  }
  foreach($target in @('f210','f200')) {
    $nextPackage=New-MIRNativeProbeTargetPackage -Context $context -RepoRoot $fakeRepo -Target $target -CandidatePrefix SCIENCE-LAUNCH -SourceVersion '4.2.2'
    $nextIdentity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $target.Substring(1) -SourceMinor 2 -SourcePatch 2
    Assert-Probe ($nextPackage.target-ceq$target-and$nextPackage.source_version-ceq'4.2.2'-and$nextPackage.distribution_version-ceq$nextIdentity.distribution_version-and$nextPackage.candidate_id.StartsWith($target.ToUpperInvariant()+'-SCIENCE-LAUNCH-')) 'governed child lost explicit source patch two.'
  }
  $driverHash=(Get-FileHash -LiteralPath (Join-Path $context.root 'materialize.ps1')).Hash
  $driverProcessIndex=$context.process_index
  Refuses-Probe {New-MIRNativeProbeTargetPackage -Context $context -RepoRoot $fakeRepo -SourceVersion '4.2.3'} 'SourceVersion'
  Assert-Probe ($driverProcessIndex-eq$context.process_index-and(Get-FileHash -LiteralPath (Join-Path $context.root 'materialize.ps1')).Hash-ceq$driverHash) 'unknown source version changed the driver or launched a process.'
  $echo=Join-Path $context.root 'argv-echo.ps1'
  [IO.File]::WriteAllText($echo,@'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Values)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
[ordered]@{values=@($Values);steam_app=$env:SteamAppId;steam_game=$env:SteamGameId;temp=$env:TEMP} | ConvertTo-Json -Compress
'@,[Text.UTF8Encoding]::new($false))
  $parentApp=[Environment]::GetEnvironmentVariable('SteamAppId');$parentGame=[Environment]::GetEnvironmentVariable('SteamGameId')
  $literalValues=@('path with spaces','literal $(Get-Process) ; "quote" & marker','Unicode: π')
  $nativeActor=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $pwsh -Arguments (@('-NoProfile','-File',$echo)+$literalValues) -TimeoutSeconds 30
  $echoed=Get-Content -LiteralPath $nativeActor.stdout -Raw | ConvertFrom-Json
  Assert-Probe (($echoed.values | ConvertTo-Json -Compress) -ceq ($literalValues | ConvertTo-Json -Compress)) 'native wrapper changed literal argument data.'
  Assert-Probe ($echoed.steam_app -ceq '427520' -and $echoed.steam_game -ceq '427520' -and [Environment]::GetEnvironmentVariable('SteamAppId') -ceq $parentApp -and [Environment]::GetEnvironmentVariable('SteamGameId') -ceq $parentGame) 'Steam launch identifiers escaped the owned child.'
  Assert-Probe ((Test-MIR441PathContained -Root $context.root -Path $echoed.temp) -and -not (Test-Path -LiteralPath $echoed.temp) -and (Test-Path -LiteralPath $nativeActor.ledger)) 'native wrapper bypassed the private-temp or resource ledger authority.'
  $priorIndex=$context.process_index
  Refuses-Probe {Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $pwsh -Arguments @('x'*20KB)} 'argument-budget'
  Assert-Probe ($context.process_index -eq $priorIndex) 'oversized argument data launched an actor.'
  # A console child does not expose PowerShell's GUI launch-and-return behavior.
  # Compile a tiny Windows GUI executable with the installed framework compiler;
  # the real driver must retain it until its delayed output and exit are complete.
  $guiSource=Join-Path $context.root 'gui-wait.cs';$guiBinary=Join-Path $context.root 'gui-wait.exe';$guiMarker=Join-Path $context.root 'gui-finished.txt'
  [IO.File]::WriteAllText($guiSource,'using System.IO; using System.Threading; class WaitControl { static int Main(string[] args) { Thread.Sleep(1500); File.WriteAllText(args[0],"finished"); return 0; } }')
  $compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
  & $compiler /nologo /target:winexe ('/out:'+$guiBinary) $guiSource
  if($LASTEXITCODE-ne0){throw 'Controlled GUI compilation failed'}
  $guiActor=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $guiBinary -Arguments @($guiMarker) -TimeoutSeconds 15
  Assert-Probe ((Test-Path -LiteralPath $guiMarker)-and([IO.File]::ReadAllText($guiMarker)-ceq'finished')-and$guiActor.result.exit_code-eq0) 'native wrapper returned before the GUI child completed.'
  Write-MIRNativeProbeResult -Context $context -Record @{status='controlled-passed';native_factorio=$false;actual_materialization=$false;actor_count=$context.runs.Count}
  Assert-Probe ((Get-Content -LiteralPath (Join-Path $context.root 'result.json') -Raw | ConvertFrom-Json).actor_count -eq 10) 'reserved result did not preserve actual actor inventory.'
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
  $syntheticSourceManifest=Join-Path $recoveryRoot 'controlled-source-manifest.json'
  [IO.File]::WriteAllText($syntheticSourceManifest,'{"controlled_parser_fixture":true,"native_proof":false}')
  $recoverySource=[ordered]@{commit='controlled-source';tree='controlled-tree';package_source_sha256=$archiveInput.expected_sha256;source_manifest_sha256=Get-ObserverSha $syntheticSourceManifest;source_version='4.2.1';distribution_version='4.2.21001'}
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
  Assert-Probe ($recovered.source.source_manifest_sha256 -ceq (Get-ObserverSha $syntheticSourceManifest) -and $recovered.source.source_manifest_sha256 -cne $recovered.source.package_source_sha256) 'controlled recovery conflated manifest custody with its package fingerprint.'
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
    @{change={$args[0].source.package_source_sha256=('A'*64)};error='source fingerprint differs'},
    @{change={$args[0].source.source_manifest_sha256=('A'*64)};error='source fingerprint differs'},
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

  $browserJob=Join-Path $fixture 'browser-lifecycle'
  $browserLibrary=Join-Path $browserJob 'library';$browserData=Join-Path $browserJob 'engine/data'
  [IO.Directory]::CreateDirectory($browserLibrary)|Out-Null
  [IO.Directory]::CreateDirectory((Join-Path $browserData 'base'))|Out-Null
  [IO.File]::WriteAllText((Join-Path $browserData 'base/info.json'),' {"name":"base","version":"2.0.77","dependencies":[]}')
  function New-BrowserInput([string]$Name,[string]$Version,[string]$Role){
    $path=Join-Path $browserLibrary ($Name+'_'+$Version+'.zip')
    $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
    try{$entry=$zip.CreateEntry($Name+'_'+$Version+'/info.json');$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write((@{name=$Name;version=$Version;factorio_version='2.0';dependencies=@('base >= 2.0.0')}|ConvertTo-Json))}finally{$writer.Dispose()}}finally{$zip.Dispose()}
    [ordered]@{source_path=$path;file_name=[IO.Path]::GetFileName($path);expected_sha256=Get-MIRImmutableInputSha256 $path;role=$Role}
  }
  $mirInput=New-BrowserInput 'more-infinite-research' '4.2.20001' 'mir-candidate'
  $fixtureInput=New-BrowserInput 'continuity-fixture' '0.1.0' 'continuity-fixture'
  $extraInput=New-BrowserInput 'unrequested' '1.0.0' 'other'
  $profileInputs=@($mirInput,$fixtureInput)
  $libraryArguments=@{LibraryDirectory=$browserLibrary;EngineDataDirectory=$browserData;EngineVersion='2.0.77'}
  $originalControls=@{'mod-list.json'='{"mods":[]}';'mod-settings.dat'='original controls'}
  foreach($entry in $originalControls.GetEnumerator()){[IO.File]::WriteAllText((Join-Path $browserLibrary $entry.Key),$entry.Value)}
  $archiveIdentities=@{};foreach($row in @($profileInputs)+@($extraInput)){$archiveIdentities[$row.file_name]=Get-MIRImmutableInputFileIdentity $row.source_path}
  Refuses-Probe {New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase initial -Inputs $profileInputs} 'direct-inputs-required'
  $profile=New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase initial -Inputs $profileInputs @libraryArguments
  Assert-Probe ($profile.mods-ceq$browserLibrary-and-not(Test-Path -LiteralPath (Join-Path $browserJob 'profiles'))) 'browser lifecycle recreated a populated profile.'
  Assert-Probe (-not(Test-Path -LiteralPath (Join-Path $profile.mods 'mod-settings.dat'))) 'browser inherited previous library settings.'
  Assert-Probe (-not(@($profile.activation.selected.name)-contains'unrequested')) 'browser enabled an unrelated archive.'
  [IO.File]::WriteAllText((Join-Path $profile.mods 'mod-settings.dat'),'private settings')
  Refuses-Probe {New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase configured -Inputs $profileInputs @libraryArguments -PreviousProfile $profile} 'previous-profile-active'
  $terminal=Complete-MIRBrowserContinuityProfile -Profile $profile
  Assert-MIRBrowserContinuityTerminalReceipt -Receipt $terminal -JobRoot $browserJob
  $changed=($terminal|ConvertTo-Json -Depth 20)|ConvertFrom-Json
  $changed.profile_sha256='A'*64
  Refuses-Probe {Assert-MIRBrowserContinuityTerminalReceipt -Receipt $changed -JobRoot $browserJob} 'selection-custody'
  $changed=($terminal|ConvertTo-Json -Depth 20)|ConvertFrom-Json
  $changed.selected[0].version='99.0.0'
  Refuses-Probe {Assert-MIRBrowserContinuityTerminalReceipt -Receipt $changed -JobRoot $browserJob} 'selected-inputs'
  $changed=($terminal|ConvertTo-Json -Depth 20)|ConvertFrom-Json
  $changed.archive_links_created=1
  Refuses-Probe {Assert-MIRBrowserContinuityTerminalReceipt -Receipt $changed -JobRoot $browserJob} 'direct-receipt'
  foreach($phase in @('configured','removed','readded')){
    foreach($entry in $originalControls.GetEnumerator()){Assert-Probe ((Get-Content -LiteralPath (Join-Path $browserLibrary $entry.Key) -Raw)-ceq$entry.Value) "browser $phase did not restore prior library controls."}
    $phaseInputs=if($phase-ceq'removed'){@($fixtureInput)}else{$profileInputs}
    $profile=New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase $phase -Inputs $phaseInputs @libraryArguments -PreviousProfile $profile
    Assert-Probe ((Get-Content -LiteralPath (Join-Path $profile.mods 'mod-settings.dat') -Raw)-ceq'private settings') "browser $phase lost private settings."
    Assert-Probe ((@($profile.activation.selected.name)-contains'more-infinite-research')-eq($phase-cne'removed')) "browser $phase has the wrong active MIR selection."
    Assert-Probe (Test-Path -LiteralPath $mirInput.source_path) "browser $phase deleted the retained candidate."
    $terminal=Complete-MIRBrowserContinuityProfile -Profile $profile
    Assert-MIRBrowserContinuityTerminalReceipt -Receipt $terminal -JobRoot $browserJob
  }
  foreach($entry in $archiveIdentities.GetEnumerator()){Assert-Probe ((Get-MIRImmutableInputFileIdentity (Join-Path $browserLibrary $entry.Key))-ceq$entry.Value) 'lifecycle changed archive identity.'}
  Assert-Probe (@(Get-ChildItem -LiteralPath (Join-Path $browserJob 'selections') -File|Where-Object Extension -NE '.json').Count-eq0) 'lifecycle selections contain payloads.'
  Refuses-Probe {New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase readded -Inputs $profileInputs @libraryArguments -PreviousProfile $profile} 'profile-preserved'
  Refuses-Probe {New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase '../outside' -Inputs $profileInputs @libraryArguments} 'profile-phase'
  $missing=[ordered]@{};foreach($entry in $fixtureInput.GetEnumerator()){$missing[$entry.Key]=$entry.Value};$missing.file_name='absent_0.1.0.zip'
  Refuses-Probe {New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase missing -Inputs @($missing) @libraryArguments} 'library-input-missing'
  [IO.File]::WriteAllText($profile.terminal.settings.path,'tampered settings')
  Refuses-Probe {New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase tampered -Inputs $profileInputs @libraryArguments -PreviousProfile $profile} 'settings-custody'
  [IO.File]::WriteAllText($profile.terminal.settings.path,'private settings')

  & {
    # Exercise the actual owned-worker protocol with tiny direct-library inputs.
    # This controlled worker has no Factorio process or gameplay oracle.
    $gitExecutable=@(Microsoft.PowerShell.Core\Get-Command git -CommandType Application)[0].Source
    function git {if('status'-in$args){$global:LASTEXITCODE=0;return};& $gitExecutable @args;$global:LASTEXITCODE=$LASTEXITCODE}
    $worker=Join-Path $fixture 'synthetic-browser-worker.ps1'
    $workerText=@'
param($CandidateArchive,$RepositoryRoot,$Target,$FactorioExe,$TimeoutSeconds,$StageLimit,$InputMode,$SourceVersion,$LibraryDirectory,$Operation,$OwnedJobPath,$OwnedJobSha256)
$ErrorActionPreference='Stop'
. (Join-Path $RepositoryRoot 'tools/lib/validation/BrowserContinuityInputs.ps1')
$job=Read-MIRBrowserContinuityOwnedJob -RepositoryRoot $RepositoryRoot -ScriptPath $PSCommandPath -RequestPath $OwnedJobPath -RequestSha256 $OwnedJobSha256
$syntheticInput=[ordered]@{source_path=$CandidateArchive;file_name=[IO.Path]::GetFileName($CandidateArchive);expected_sha256=(Get-FileHash $CandidateArchive).Hash;role='mir-candidate'}
$root=Join-Path $job.root 'worker';$data=Join-Path (Split-Path -Parent $LibraryDirectory) 'engine/data'
$profile=New-MIRBrowserContinuityProfile -JobRoot $root -Phase initial -Inputs @($syntheticInput) -LibraryDirectory $LibraryDirectory -EngineDataDirectory $data -EngineVersion '2.0.77'
$receipt=Complete-MIRBrowserContinuityProfile -Profile $profile
$record=[ordered]@{schema=1;status='checkpointed';scope='synthetic actor protocol, not Factorio';source=@{harness_sha256=$job.harness_sha256};source_version=$SourceVersion;target=@{key=$Target};input_mode=$InputMode;candidate=@{archive_sha256=(Get-FileHash $CandidateArchive).Hash};stages=@(@{stage='initial'});library_input_receipts=@($receipt)}
[IO.File]::WriteAllText((Join-Path $root 'browser-personal-state-continuity-receipt.json'),($record|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
'@
    [IO.File]::WriteAllText($worker,$workerText,[Text.UTF8Encoding]::new($false))
    $currentMirInput=New-BrowserInput 'more-infinite-research' '4.2.20002' 'mir-candidate'
    foreach($sourceVersion in @('4.2.1','4.2.2')){
    $parameters=[ordered]@{CandidateArchive=$mirInput.source_path;RepositoryRoot=$repo;Target='F200';FactorioExe=$pwsh;TimeoutSeconds=30;StageLimit='Initial';InputMode='ScriptedFixture';SourceVersion='4.2.1';LibraryDirectory=$browserLibrary;Operation='Run'}
    $parameters.SourceVersion=$sourceVersion
    if($sourceVersion-ceq'4.2.2'){$parameters.CandidateArchive=$currentMirInput.source_path}
    $output=@(Invoke-MIRBrowserContinuityGovernedRun -RepositoryRoot $repo -ScriptPath $worker -Parameters $parameters -OutputRoot $fixture -ExpectedPeakMemoryMiB 512 -MaxNewOutputMiB 8)
    $resultPath=($output|Where-Object{$_-like'MIR_BROWSER_CONTINUITY_GOVERNED_RESULT=*'}).Substring('MIR_BROWSER_CONTINUITY_GOVERNED_RESULT='.Length)
    $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json -Depth 40 -DateKind String
    Assert-Probe ($result.kind-ceq'MIRBrowserContinuityGovernedRunV2'-and$result.status-ceq'checkpointed'-and-not$result.release_qualification-and$result.whole_process_tree.result.passed-and$result.archive_bytes_discounted-eq0) 'browser synthetic actor lost its governor or claimed qualification.'
    $request=Join-Path (Split-Path -Parent $resultPath) 'owned-job.json'
    Refuses-Probe {Read-MIRBrowserContinuityOwnedJob -RepositoryRoot $repo -ScriptPath $worker -RequestPath $request -RequestSha256 ('0'*64)} 'owned-request-hash'
    Refuses-Probe {Read-MIRBrowserContinuityOwnedJob -RepositoryRoot $repo -ScriptPath $worker -RequestPath $request -RequestSha256 (Get-FileHash $request).Hash} 'owned-request-binding'
    $fallback=& {
      function Get-Command {param([string]$Name) if($Name-ceq'ConvertFrom-Json'){return [pscustomobject]@{Parameters=@{}}};Microsoft.PowerShell.Core\Get-Command $Name}
      Read-MIRBrowserContinuityJson -Path $result.receipt -DocumentOnly
    }
    Assert-MIRBrowserContinuityTerminalReceipt -Receipt $fallback.library_input_receipts[0] -JobRoot (Join-Path (Split-Path -Parent $resultPath) 'worker')
    Assert-Probe ($fallback.library_input_receipts[0].status-ceq'restored-direct-library-controls') 'browser fallback reader lost its direct-library receipt.'
    Assert-Probe ($fallback.source_version-ceq$sourceVersion-and$fallback.candidate.archive_sha256-ceq(Get-FileHash $parameters.CandidateArchive).Hash) 'browser owned worker lost the selected maintenance version or bytes.'
    $expectedVersion=if($sourceVersion-ceq'4.2.2'){'4.2.20002'}else{'4.2.20001'}
    Assert-Probe ((@($fallback.library_input_receipts[0].selected|Where-Object name -CEQ 'more-infinite-research').version)-ceq$expectedVersion) 'browser worker selected a different installed maintenance version.'
    }
  }

  $failedRoot=Join-Path $fixture 'link-failure';New-Item -ItemType Directory -Path $failedRoot | Out-Null
  $copies=0
  function New-Item {
    param([string]$ItemType,[string]$Path,[string]$Target,[switch]$Force)
    if($ItemType -ceq 'HardLink') { throw 'controlled-link-failure' }
    Microsoft.PowerShell.Management\New-Item -ItemType $ItemType -Path $Path -Force:$Force
  }
  function Copy-Item { $script:copies++;throw 'copy fallback was invoked' }
  Refuses-Probe {New-MIRImmutableInputLease -RunRoot $failedRoot -StageDirectory (Join-Path $failedRoot 'mods') -Inputs @($archiveInput) -RequireHardLinks} 'requires a verified hard link'
  Refuses-Probe {Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $failedRoot -LockEntries @($compatEntry)} 'controlled-link-failure'
  Refuses-Probe {Copy-MIRModUnderTest -RepoRoot $repo -ModsDir $failedRoot -ZipPath $source} 'controlled-link-failure'
  Assert-Probe ($copies -eq 0 -and (Get-MIRImmutableInputSha256 $source) -ceq $archiveInput.expected_sha256) 'strict link failure copied or modified the canonical input.'
  $completed=$true
} finally {
  if($null -ne $lease -and -not $lease.closed) { $null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed }
  if($completed-and(Test-Path -LiteralPath $fixture)) {
    $resolved=Resolve-MIR441RecoveryScratchPath -Path $fixture
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }else{Write-Warning "Controlled failure diagnostics retained at $fixture"}
}
[pscustomobject]@{status='passed';assertions=$assertions;native_factorio=$false;actual_materialization=$false;scope='Controlled lease, row budget, preallocation, browser engine/archive admission, owned small actors and completed-row custody parser; no native oracle';memory_enforcement='sampled-watchdog-not-hard-cap'}
