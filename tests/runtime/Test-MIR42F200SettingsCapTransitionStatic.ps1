# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$harnessPath=Join-Path $repo 'tests/runtime/Test-MIR42F200SettingsCapTransition.ps1'
$fixturesPath=Join-Path $repo '.mir/fixtures.yml'
$expectedExpansions=@('elevated-rails','quality','space-age')

function Assert-MIR42F200Static([bool]$Condition,[string]$Message){if(-not$Condition){throw "[mir42-f200-settings-cap-transition-static] $Message"}}
function Get-MIR42F200StaticFunctionText($Ast,[string]$Name){$matches=@($Ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name},$true));Assert-MIR42F200Static ($matches.Count-eq1) "expected exactly one $Name function, observed $($matches.Count).";$matches[0].Extent.Text}
function Assert-MIR42F200BaseOnlyHarnessContract([string]$Text){
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
  Assert-MIR42F200Static (@($errors).Count-eq0) "harness parser errors: $(@($errors|ForEach-Object Message)-join'; ')"
  $assignments=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -ceq 'officialExpansionMods'},$true))
  Assert-MIR42F200Static ($assignments.Count-eq1) 'official expansion list must have one explicit assignment.'
  $declared=@([regex]::Matches($assignments[0].Right.Extent.Text,"'(?<name>[^']+)'")|ForEach-Object{$_.Groups['name'].Value})
  Assert-MIR42F200Static (($declared-join"`n")-ceq($expectedExpansions-join"`n")) 'official expansion list differs from elevated-rails, quality, and space-age.'
  $baseOnlyList=Get-MIR42F200StaticFunctionText $ast 'New-MIR42F200BaseOnlyModList'
  Assert-MIR42F200Static ($baseOnlyList-match'foreach\s*\(\s*\$name\s+in\s+\$officialExpansionMods\s*\)') 'base-only mod-list builder does not enumerate the explicit official expansion list.'
  Assert-MIR42F200Static ($baseOnlyList-match'\[ordered\]@\{name=\[string\]\$name;enabled=\$false\}') 'base-only mod-list builder does not explicitly disable every official expansion.'
  $newStage=Get-MIR42F200StaticFunctionText $ast 'New-Stage'
  Assert-MIR42F200Static ($newStage-match'\$modList\s*=\s*New-MIR42F200BaseOnlyModList') 'every stage must use the shared explicit base-only mod-list builder.'
  $stageAssertion=Get-MIR42F200StaticFunctionText $ast 'Assert-MIR42F200BaseOnlyStageModList'
  Assert-MIR42F200Static ($stageAssertion-match'\$officialExpansionMods' -and $stageAssertion-match'\.enabled') 'stage mod-list assertion does not verify disabled expansions.'
  Assert-MIR42F200Static ($Text-match'\$stages\s*=\s*@\(\$seed,\$capped,\$relaxed\).*?foreach\s*\(\$stage\s+in\s+\$stages\).*?Assert-MIR42F200BaseOnlyStageModList' ) 'seed, capped, and relaxed stages are not all checked against the base-only mod-list contract.'
  $engineClosure=Get-MIR42F200StaticFunctionText $ast 'Get-MIR42F200EffectiveEngineLoadedClosure'
  Assert-MIR42F200Static ($engineClosure.Contains('Loading mod (?!settings ') -and $engineClosure.Contains('Loading mod settings ') -and $engineClosure-match'\$expectedEngineLoadedModNames' -and $engineClosure-match'\$officialExpansionMods' -and $engineClosure-match'loaded_mods') 'engine-loaded closure assertion is incomplete.'
  Assert-MIR42F200Static ($Text-match'Get-MIR42F200EffectiveEngineLoadedClosure\s+\$seedText\s+seed' -and $Text-match'Get-MIR42F200EffectiveEngineLoadedClosure\s+\$cappedText\s+capped' -and $Text-match'Get-MIR42F200EffectiveEngineLoadedClosure\s+\$relaxedText\s+relaxed') 'engine-loaded closure is not asserted for every stage.'
  Assert-MIR42F200Static ($Text-match'declared_base_only_mod_closure\s*=\s*\[ordered\]@\{' -and $Text-match'effective_engine_loaded_closure\s*=\s*\$effectiveEngineLoadedClosure' -and $Text-match'mod_list_contract\s*=\s*\$stageModListContracts') 'result.json does not retain declared and effective base-only closure evidence.'
}

Assert-MIR42F200Static (Test-Path -LiteralPath $harnessPath -PathType Leaf) 'runtime harness is absent.'
$harnessText=Get-Content -Raw -LiteralPath $harnessPath
Assert-MIR42F200BaseOnlyHarnessContract $harnessText
$disabledExpansionRemoved=$harnessText.Replace('enabled=$false','enabled=$true')
Assert-MIR42F200Static ($disabledExpansionRemoved-cne$harnessText) 'static negative control could not remove the disabled-expansion guard.'
$rejected=$false;try{Assert-MIR42F200BaseOnlyHarnessContract $disabledExpansionRemoved}catch{$rejected=$true}
Assert-MIR42F200Static $rejected 'static contract accepted a harness with expansions enabled.'
$closureReceiptRemoved=$harnessText.Replace('effective_engine_loaded_closure=$effectiveEngineLoadedClosure','effective_engine_loaded_closure_removed=$effectiveEngineLoadedClosure')
Assert-MIR42F200Static ($closureReceiptRemoved-cne$harnessText) 'static negative control could not remove the effective closure receipt.'
$rejected=$false;try{Assert-MIR42F200BaseOnlyHarnessContract $closureReceiptRemoved}catch{$rejected=$true}
Assert-MIR42F200Static $rejected 'static contract accepted a harness without the effective closure receipt.'
Assert-MIR42F200Static (Test-Path -LiteralPath $fixturesPath -PathType Leaf) 'fixture manifest is absent.'
$fixturesText=Get-Content -Raw -LiteralPath $fixturesPath
Assert-MIR42F200Static ($fixturesText-match'mod_lock:\s+exact-engine-2[.]0[.]77-base-only-explicit-elevated-rails-quality-space-age-disabled') 'fixture manifest does not document the explicit base-only expansion lock.'
Write-Host '[ok] MIR42 F200 settings-cap-transition static base-only closure contract passed.'

# Execute the actual changed constructors and adapters with tiny immutable
# inputs. This proves storage/process plumbing, not Factorio gameplay.
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $repo 'tools/lib/assurance/evidence/CommandExecution.ps1')
function Get-MIR441ResourceSnapshot {
  param([string]$WorkRoot)
  [pscustomobject]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');memory=[pscustomobject]@{total_bytes=16GB;free_bytes=12GB;committed_bytes=4GB;commit_limit_bytes=20GB};system_volume=[pscustomobject]@{free_bytes=100GB};work_volume=[pscustomobject]@{free_bytes=100GB}}
}
$scratch=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo ('build/tmp/f200-cap-controls-'+[guid]::NewGuid().ToString('N')))
$activeStage=$null;$stages=@()
$nativeActor=(Get-Command Invoke-MIRNativeProbeFactorioProcess).ScriptBlock
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($harnessText,[ref]$tokens,[ref]$errors)
foreach($name in @('Assert-MIR42F200','Assert-Exact','Assert-Properties','Get-Sha','New-MIR42F200BaseOnlyModList','Assert-MIR42F200BaseOnlyStageModList','New-CapSettingsSource','New-Stage','Start-CapStage','Complete-CapStage','Invoke-Engine','Invoke-ServerSave')) {
  . ([scriptblock]::Create((Get-MIR42F200StaticFunctionText $ast $name)))
}
try {
  New-Item -ItemType Directory -Path $scratch | Out-Null
  $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $scratch -ExpectedPeakMemoryMiB 1024 -MaxNewOutputMiB 4
  $library=Join-Path $scratch 'library';[IO.Directory]::CreateDirectory($library)|Out-Null
  $engineRoot=Join-Path $scratch 'engine';$engine=Join-Path $engineRoot 'bin/x64/factorio.exe'
  [IO.Directory]::CreateDirectory((Split-Path -Parent $engine))|Out-Null
  [IO.File]::WriteAllText($engine,'controlled engine; never executed')
  $officialExpansionMods=@('elevated-rails','quality','space-age')
  foreach($name in @('base')+$officialExpansionMods){
    $dir=Join-Path $engineRoot ('data/'+$name);[IO.Directory]::CreateDirectory($dir)|Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'info.json'),(@{name=$name;version='2.0.77';dependencies=@()}|ConvertTo-Json))
  }
  $tiny=Join-Path $scratch 'candidate-source';[IO.Directory]::CreateDirectory($tiny)|Out-Null
  [IO.File]::WriteAllText((Join-Path $tiny 'info.json'),(@{name='more-infinite-research';version='4.2.20001';factorio_version='2.0';dependencies=@('base >= 2.0.77')}|ConvertTo-Json))
  $candidateZip=Publish-MIRModDirectoryArchive -Source $tiny -Name 'more-infinite-research' -Version '4.2.20001' -ModsDir $library
  $candidateHash=Get-MIRImmutableInputSha256 $candidateZip
  $candidateInput=[pscustomobject]@{receipt=[pscustomobject]@{archive_sha256=$candidateHash;package_source_sha256=('A'*64)}}
  $fixture=Join-Path $repo 'fixtures/assert-mir42-f200-settings-cap-transition'
  $fixtureName='mir-fixture-assert-mir42-f200-settings-cap-transition'
  $null=Publish-MIRModDirectoryArchive -Source $fixture -Name $fixtureName -Version '0.1.0' -ModsDir $library
  $preparedSettings=@{}
  foreach($cap in @(0,3)){
    $preparedSettings[$cap]=New-CapSettingsSource (Join-Path $resources.root ('input-definitions/cap-'+$cap)) $cap
    $input=$preparedSettings[$cap]
    $null=Publish-MIRModDirectoryArchive -Source $input.source -Name 'mir-validation-settings-overrides' -Version $input.version -ModsDir $library
  }
  $before=@{};foreach($file in @(Get-ChildItem -LiteralPath $library -File)){$before[$file.Name]=@{sha256=Get-MIRImmutableInputSha256 $file.FullName;id=Get-MIRImmutableInputFileIdentity $file.FullName}}
  $oldList=[Text.Encoding]::UTF8.GetBytes('{"mods":[{"name":"base","enabled":true}]}')
  $oldSettings=[Text.Encoding]::UTF8.GetBytes('prior private settings control')
  [IO.File]::WriteAllBytes((Join-Path $library 'mod-list.json'),$oldList)
  [IO.File]::WriteAllBytes((Join-Path $library 'mod-settings.dat'),$oldSettings)
  $expectedEnabledModNames=@('base','more-infinite-research',$fixtureName,'mir-validation-settings-overrides')
  $stages=@((New-Stage seed 0),(New-Stage capped 3),(New-Stage relaxed 0))
  function Assert-CapControlsRestored {
    Assert-MIR42F200Static ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $library 'mod-list.json')))-ceq[Convert]::ToBase64String($oldList)) 'previous mod-list not restored'
    Assert-MIR42F200Static ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $library 'mod-settings.dat')))-ceq[Convert]::ToBase64String($oldSettings)) 'previous settings not restored'
  }
  foreach($stage in $stages){
    $null=Assert-MIR42F200BaseOnlyStageModList $stage
    Start-CapStage $stage
    Assert-MIR42F200Static ($stage.activation.library-ceq$library-and-not(Test-Path (Join-Path $stage.root 'mods'))) 'cap stage materialized a mod directory'
    $selected=@($stage.activation.selected|Where-Object name -CEQ 'mir-validation-settings-overrides')
    Assert-MIR42F200Static ($selected.Count-eq1-and$selected[0].version-ceq$preparedSettings[$stage.cap].version) 'cap selected the wrong exact settings version'
    Assert-MIR42F200Static (-not(Test-Path (Join-Path $library 'mod-settings.dat'))) 'cap inherited the previous settings'
    $denied=$false;try{$f=[IO.File]::Open($candidateZip,[IO.FileMode]::Open,[IO.FileAccess]::Write);$f.Dispose()}catch [IO.IOException]{$denied=$true}
    Assert-MIR42F200Static $denied 'active selected candidate is writable'
    $busy=$false;try{Start-CapStage $stages[0]}catch{$busy=$_.Exception.Message.Contains('mir-library-busy')}
    Assert-MIR42F200Static $busy 'second selection was not refused'
    [IO.File]::WriteAllText((Join-Path $library 'mod-settings.dat'),'private writable native settings')
    $stage.terminal=Complete-MIRLibraryActivation $stage.activation;$script:activeStage=$null
    Assert-MIR42F200Static ($stage.terminal.dependency_payload_bytes_copied-eq0-and$stage.terminal.archive_links_created-eq0) 'cap staging copied or linked payloads'
    Assert-CapControlsRestored
  }
  Assert-MIR42F200Static ($resources.shared_alias_bytes-eq0) 'direct library was charged as aliases'
  # Bad supplied hashes fail before selecting controls. Never link or copy as recovery.
  $originalHash=$candidateInput.receipt.archive_sha256;$candidateInput.receipt.archive_sha256='A'*64
  $rejected=$false;try{New-Stage wrong-hash 0|Out-Null}catch{$rejected=$_.Exception.Message.Contains('installed candidate hash')}
  $candidateInput.receipt.archive_sha256=$originalHash
  Assert-MIR42F200Static $rejected 'changed candidate bytes were accepted'
  Assert-CapControlsRestored

  # Exercise the consumed save predicate with each missing prerequisite, then
  # all original conditions. The actor stub never starts a native executable.
  $script:actorCalls=0;$script:reportCompletion=$true
  function Invoke-MIRNativeProbeFactorioProcess {
    param($Context,[string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds,[scriptblock]$CompletionPredicate)
    $script:actorCalls++
    Assert-MIR42F200Static ($Context -eq $resources -and $FilePath -ceq $engine -and $Arguments -contains $stages[0].config) 'actor lost context, engine or private configuration.'
    Assert-MIR42F200Static ($Arguments[[Array]::IndexOf($Arguments,'--mod-directory')+1]-ceq$library) 'native actor received a staged path'
    $prefix="0.000 2026-10-08 00:00:00; Factorio 2.0.77 (controlled)\n".Replace('\n',"`n")+(@($stages[0].activation.selected|ForEach-Object{"0.001 Loading mod $($_.name) $($_.version) (data.lua)"})-join"`n")+"`n"
    $log=Join-Path $stages[0].userdata 'factorio-current.log'
    if($null -eq $CompletionPredicate) {
      Assert-MIR42F200Static ($TimeoutSeconds -eq 120 -and $Arguments -contains '--create') 'create invocation lost its timeout or original argument.'
      [IO.File]::WriteAllText($log,$prefix+'controlled creation log')
      return [pscustomobject]@{result=[pscustomobject]@{completion_predicate_observed=$false}}
    }
    Assert-MIR42F200Static ($TimeoutSeconds -eq 60 -and $Arguments -contains '--start-server' -and $Arguments -contains $stages[0].server) 'server invocation lost its original private controls.'
    if(Test-Path -LiteralPath $expectedSave){Remove-Item -LiteralPath $expectedSave}
    Assert-MIR42F200Static (-not (& $CompletionPredicate)) 'completion accepted missing log and save.'
    [IO.File]::WriteAllText($log,'Saving finished')
    Assert-MIR42F200Static (-not (& $CompletionPredicate)) 'completion accepted missing save.'
    [IO.File]::WriteAllText($expectedSave,'tiny save control')
    Assert-MIR42F200Static (-not (& $CompletionPredicate)) 'completion accepted missing expected state.'
    [IO.File]::WriteAllText($log,'[mir42-f200-settings-cap-transition] STATE JSON {"stage":"relaxed"}')
    Assert-MIR42F200Static (-not (& $CompletionPredicate)) 'completion accepted missing finished-save marker.'
    [IO.File]::WriteAllText($log,'[mir42-f200-settings-cap-transition] STATE JSON {"stage":"capped"} Saving finished')
    Assert-MIR42F200Static (-not (& $CompletionPredicate)) 'completion accepted another stage.'
    [IO.File]::WriteAllText($log,$prefix+'[mir42-f200-settings-cap-transition] STATE JSON {"stage":"relaxed"} Saving finished')
    Assert-MIR42F200Static (& $CompletionPredicate) 'completion rejected all original conditions.'
    [pscustomobject]@{result=[pscustomobject]@{completion_predicate_observed=$script:reportCompletion}}
  }
  $expectedSave=Join-Path $stages[0].userdata 'saves/successor.zip'
  $null=Invoke-Engine $stages[0] create @('--create','controlled-input.zip')
  $null=Invoke-ServerSave $stages[0] successor 'controlled-input.zip' $expectedSave relaxed
  Assert-CapControlsRestored
  $script:reportCompletion=$false;$failure=''
  try {Invoke-ServerSave $stages[0] incomplete 'controlled-input.zip' $expectedSave relaxed|Out-Null} catch {$failure=$_.Exception.Message}
  Assert-MIR42F200Static ($failure.Contains('did not create incomplete successor')) 'server accepted actor return without observed completion.'
  $null=Complete-MIRLibraryActivation $stages[0].activation;$script:activeStage=$null
  Assert-CapControlsRestored
  Set-Item Function:\Invoke-MIRNativeProbeFactorioProcess -Value $nativeActor

  # The real shared adapter must forward completion, terminate its owned child
  # and wait before returning. Only a tiny PowerShell actor runs here.
  $actorPath=Join-Path $resources.root 'controlled-actor.ps1'
  $actorMarker=Join-Path $resources.root 'controlled-actor.pid'
  [IO.File]::WriteAllText($actorPath,'param([string]$Marker);[IO.File]::WriteAllText($Marker,[string]$PID);while($true){Start-Sleep -Milliseconds 100}')
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile','-File',$actorPath,'-Marker',$actorMarker) -TimeoutSeconds 20 -CompletionPredicate {Test-Path -LiteralPath $actorMarker -PathType Leaf}
  $actorPid=[int](Get-Content -LiteralPath $actorMarker -Raw)
  Assert-MIR42F200Static ($actor.result.completion_predicate_observed -and $null -eq (Get-Process -Id $actorPid -ErrorAction SilentlyContinue)) 'completion returned with its owned child alive.'
  Assert-CapControlsRestored

  $catalog=Get-Content -Raw -LiteralPath (Join-Path $repo 'validation/tests.yml')|ConvertFrom-Json
  $command=[string](@($catalog.tests|Where-Object id -CEQ 'runtime.maximum-level-settings-derived-cap-transition-f200')[0].command)
  $context=[pscustomobject]@{factorio='controlled engine';mods='controlled library';candidate='controlled candidate';candidate_materialization="receipt with ' quote.json"}
  $resolved=Resolve-MIRAssuranceCommandText -Command $command -Context $context -Plan ([pscustomobject]@{})
  Assert-MIR42F200Static ($resolved.Contains("-SourceMaterializationPath 'receipt with '' quote.json'") -and $resolved.Contains("-LibraryDirectory 'controlled library'") -and $resolved.Contains('-ExpectedPeakMemoryMiB 2048') -and $resolved.Contains('-MaxNewOutputMiB 120')) 'catalogue command lost supplied receipt, quoting or budgets.'
  $failure='';try {Resolve-MIRAssuranceCommandText -Command $command -Context ([pscustomobject]@{factorio='engine';mods='library';candidate='candidate'}) -Plan ([pscustomobject]@{})|Out-Null} catch {$failure=$_.Exception.Message}
  Assert-MIR42F200Static ($failure.Contains('requires <candidate-materialization>')) 'missing receipt did not produce the exact required-option diagnostic.'
  Assert-MIR42F200Static ((Resolve-MIRAssuranceCommandText -Command './static-command' -Context ([pscustomobject]@{}) -Plan ([pscustomobject]@{})) -ceq './static-command') 'new optional receipt breaks unrelated static commands.'

  foreach($file in @(Get-ChildItem -LiteralPath $library -Filter '*.zip' -File)){
    Assert-MIR42F200Static ($before.ContainsKey($file.Name)-and$before[$file.Name].sha256-ceq(Get-MIRImmutableInputSha256 $file.FullName)-and$before[$file.Name].id-ceq(Get-MIRImmutableInputFileIdentity $file.FullName)) 'archive identity changed while switching cap stages'
  }
  Assert-MIR42F200Static (@(Get-ChildItem -LiteralPath $resources.root -Recurse -Filter '*.zip' -File|Where-Object{$_.FullName-ne$expectedSave}).Count-eq0) 'cap switch wrote an archive payload'
  Write-Host '[ok] F200 cap direct-library A/B/A selection, exact settings versions, private controls, concurrent/hash refusal, unchanged archives, save-completion predicates and owned-child shutdown; no Factorio.'

} finally {
  Set-Item Function:\Invoke-MIRNativeProbeFactorioProcess -Value $nativeActor
  foreach($stage in @($stages)){if($null-ne$stage.activation-and-not$stage.activation.closed){$null=Complete-MIRLibraryActivation $stage.activation}}
  if(Test-Path -LiteralPath $scratch){$null=Assert-MIRImmutableInputPathWithin -Path $scratch -Root (Join-Path $repo 'build/tmp') -Context 'owned tiny F200 fixture cleanup';Remove-Item -LiteralPath $scratch -Recurse -Force}
}
