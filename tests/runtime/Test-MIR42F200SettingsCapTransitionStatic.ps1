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
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $repo 'tools/lib/assurance/evidence/CommandExecution.ps1')
function Get-MIR441ResourceSnapshot {
  param([string]$WorkRoot)
  [pscustomobject]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');memory=[pscustomobject]@{total_bytes=16GB;free_bytes=12GB;committed_bytes=4GB;commit_limit_bytes=20GB};system_volume=[pscustomobject]@{free_bytes=100GB};work_volume=[pscustomobject]@{free_bytes=100GB}}
}
$scratch=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo ('build/tmp/f200-cap-controls-'+[guid]::NewGuid().ToString('N')))
$inputLeases=[Collections.Generic.List[object]]::new()
$nativeActor=(Get-Command Invoke-MIRNativeProbeFactorioProcess).ScriptBlock
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($harnessText,[ref]$tokens,[ref]$errors)
foreach($name in @('Assert-MIR42F200','Assert-Exact','Assert-Properties','New-MIR42F200BaseOnlyModList','Assert-MIR42F200BaseOnlyStageModList','New-Stage','Invoke-Engine','Invoke-ServerSave')) {
  . ([scriptblock]::Create((Get-MIR42F200StaticFunctionText $ast $name)))
}
try {
  New-Item -ItemType Directory -Path $scratch | Out-Null
  $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $scratch -ExpectedPeakMemoryMiB 1024 -MaxNewOutputMiB 4
  $candidateZip=Join-Path $scratch 'more-infinite-research_4.2.20001.zip'
  [IO.File]::WriteAllText($candidateZip,'tiny immutable archive payload control')
  $candidateHash=Get-MIRImmutableInputSha256 $candidateZip
  $candidateInput=[pscustomobject]@{receipt=[pscustomobject]@{archive_sha256=$candidateHash;package_source_sha256=('A'*64)}}
  $fixture=Join-Path $repo 'fixtures/assert-mir42-f200-settings-cap-transition'
  $fixtureName='mir-fixture-assert-mir42-f200-settings-cap-transition'
  $engineRoot=$scratch;$engine='controlled-engine-never-executed'
  $officialExpansionMods=@('elevated-rails','quality','space-age')
  $expectedEnabledModNames=@('base','more-infinite-research',$fixtureName,'mir-validation-settings-overrides')
  $stages=@((New-Stage seed 0),(New-Stage capped 3),(New-Stage relaxed 0))
  foreach($stage in $stages) {
    $null=Assert-MIR42F200BaseOnlyStageModList $stage
    $row=$stage.lease.record.inputs[0]
    Assert-MIR42F200Static ($stage.lease.record.require_hard_links -and $row.staging_mode -ceq 'hardlink' -and (Get-MIRImmutableInputFileIdentity $candidateZip) -ceq (Get-MIRImmutableInputFileIdentity $row.stage_path)) "$($stage.name) copied its candidate payload."
    $settings=[IO.Compression.ZipFile]::OpenRead($stage.settings_archive)
    try {
      $reader=[IO.StreamReader]::new($settings.GetEntry('mir-validation-settings-overrides_0.1.0/settings-updates.lua').Open())
      try {$settingsText=$reader.ReadToEnd()} finally {$reader.Dispose()}
      Assert-MIR42F200Static ($settingsText.Contains('override("ips-max-level-research_copper", '+$stage.cap+')')) "$($stage.name) lost its original private cap setting."
    } finally {$settings.Dispose()}
    [IO.File]::WriteAllText((Join-Path $stage.mods 'mod-settings.dat'),"private $($stage.name)")
    Assert-MIR42F200Static ((Get-MIRImmutableInputFileIdentity $stage.mod_list) -cne (Get-MIRImmutableInputFileIdentity $row.stage_path)) 'mod-list shares immutable input identity.'
  }
  Assert-MIR42F200Static ($resources.shared_alias_bytes -eq 3*(Get-Item -LiteralPath $candidateZip).Length) 'verified aliases are not excluded from physical output accounting.'
  Assert-MIR42F200Static (@($stages|ForEach-Object {Get-MIRImmutableInputFileIdentity (Join-Path $_.mods 'mod-settings.dat')}|Sort-Object -Unique).Count -eq 3) 'mutable settings share a file between stages.'
  $writeDenied=$false;try {$stream=[IO.File]::Open($candidateZip,[IO.FileMode]::Open,[IO.FileAccess]::Write);$stream.Dispose()} catch [IO.IOException] {$writeDenied=$true}
  Assert-MIR42F200Static $writeDenied 'source is writable during active leases.'

  # A real failed link at the consumed constructor must never invoke copying.
  $script:copyAttempts=0
  function New-Item { [CmdletBinding()]param([string]$ItemType,[string[]]$Path,[string]$Target,[switch]$Force);if($ItemType -ceq 'HardLink'){throw 'controlled unavailable hardlink'};Microsoft.PowerShell.Management\New-Item @PSBoundParameters }
  function Copy-Item { [CmdletBinding()]param([string]$LiteralPath,[string]$Destination);$script:copyAttempts++;throw 'archive copy attempted' }
  try {
    $failure='';try {New-Stage unavailable 0|Out-Null} catch {$failure=$_.Exception.Message}
    Assert-MIR42F200Static ($failure.Contains('hardlink') -and $script:copyAttempts -eq 0) "failed link copied an archive or lost its diagnostic: $failure"
  } finally {Remove-Item Function:\New-Item;Remove-Item Function:\Copy-Item}

  # Exercise the consumed save predicate with each missing prerequisite, then
  # all original conditions. The actor stub never starts a native executable.
  $script:actorCalls=0;$script:reportCompletion=$true
  function Invoke-MIRNativeProbeFactorioProcess {
    param($Context,[string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds,[scriptblock]$CompletionPredicate)
    $script:actorCalls++
    Assert-MIR42F200Static ($Context -eq $resources -and $FilePath -ceq $engine -and $Arguments -contains $stages[0].config) 'actor lost context, engine or private configuration.'
    $log=Join-Path $stages[0].userdata 'factorio-current.log'
    if($null -eq $CompletionPredicate) {
      Assert-MIR42F200Static ($TimeoutSeconds -eq 120 -and $Arguments -contains '--create') 'create invocation lost its timeout or original argument.'
      [IO.File]::WriteAllText($log,'controlled creation log')
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
    [IO.File]::WriteAllText($log,'[mir42-f200-settings-cap-transition] STATE JSON {"stage":"relaxed"} Saving finished')
    Assert-MIR42F200Static (& $CompletionPredicate) 'completion rejected all original conditions.'
    [pscustomobject]@{result=[pscustomobject]@{completion_predicate_observed=$script:reportCompletion}}
  }
  $expectedSave=Join-Path $stages[0].userdata 'saves/successor.zip'
  $null=Invoke-Engine $stages[0] create @('--create','controlled-input.zip')
  $null=Invoke-ServerSave $stages[0] successor 'controlled-input.zip' $expectedSave relaxed
  $script:reportCompletion=$false;$failure=''
  try {Invoke-ServerSave $stages[0] incomplete 'controlled-input.zip' $expectedSave relaxed|Out-Null} catch {$failure=$_.Exception.Message}
  Assert-MIR42F200Static ($failure.Contains('did not create incomplete successor')) 'server accepted actor return without observed completion.'
  Set-Item Function:\Invoke-MIRNativeProbeFactorioProcess -Value $nativeActor

  # The real shared adapter must forward completion, terminate its owned child
  # and wait before returning. Only a tiny PowerShell actor runs here.
  $actorPath=Join-Path $resources.root 'controlled-actor.ps1'
  $actorMarker=Join-Path $resources.root 'controlled-actor.pid'
  [IO.File]::WriteAllText($actorPath,'param([string]$Marker);[IO.File]::WriteAllText($Marker,[string]$PID);while($true){Start-Sleep -Milliseconds 100}')
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile','-File',$actorPath,'-Marker',$actorMarker) -TimeoutSeconds 20 -CompletionPredicate {Test-Path -LiteralPath $actorMarker -PathType Leaf}
  $actorPid=[int](Get-Content -LiteralPath $actorMarker -Raw)
  Assert-MIR42F200Static ($actor.result.completion_predicate_observed -and $null -eq (Get-Process -Id $actorPid -ErrorAction SilentlyContinue)) 'completion returned with its owned child alive.'
  Assert-MIR42F200Static (@($inputLeases|Where-Object closed).Count -eq 0) 'process adapter prematurely released input custody.'

  $catalog=Get-Content -Raw -LiteralPath (Join-Path $repo 'validation/tests.yml')|ConvertFrom-Json
  $command=[string](@($catalog.tests|Where-Object id -CEQ 'runtime.maximum-level-settings-derived-cap-transition-f200')[0].command)
  $context=[pscustomobject]@{factorio='controlled engine';candidate='controlled candidate';candidate_materialization="receipt with ' quote.json"}
  $resolved=Resolve-MIRAssuranceCommandText -Command $command -Context $context -Plan ([pscustomobject]@{})
  Assert-MIR42F200Static ($resolved.Contains("-SourceMaterializationPath 'receipt with '' quote.json'") -and $resolved.Contains('-ExpectedPeakMemoryMiB 2048') -and $resolved.Contains('-MaxNewOutputMiB 120')) 'catalogue command lost supplied receipt, quoting or budgets.'
  $failure='';try {Resolve-MIRAssuranceCommandText -Command $command -Context ([pscustomobject]@{factorio='engine';candidate='candidate'}) -Plan ([pscustomobject]@{})|Out-Null} catch {$failure=$_.Exception.Message}
  Assert-MIR42F200Static ($failure.Contains('requires <candidate-materialization>')) 'missing receipt did not produce the exact required-option diagnostic.'
  Assert-MIR42F200Static ((Resolve-MIRAssuranceCommandText -Command './static-command' -Context ([pscustomobject]@{}) -Plan ([pscustomobject]@{})) -ceq './static-command') 'new optional receipt breaks unrelated static commands.'

  foreach($stage in $stages) {
    $terminal=Complete-MIRImmutableInputLease -Lease $stage.lease -Outcome passed
    $null=Assert-MIRImmutableInputTerminalReceipt -Receipt $terminal
    $null=Assert-MIRImmutableInputLeaseReclaimable -RunRoot $stage.root -Context 'completed tiny F200 stage'
    $null=Assert-MIRImmutableInputPathWithin -Path $stage.root -Root $scratch -Context 'tiny F200 staging cleanup'
    Remove-Item -LiteralPath $stage.root -Recurse
  }
  Assert-MIR42F200Static ((Get-MIRImmutableInputSha256 $candidateZip) -ceq $candidateHash) 'stage retirement removed or changed supplied bytes.'
  Write-Host '[ok] F200 cap runner: three actual strict-link constructors, independent writable controls, no-copy refusal, original completion prerequisites and owned-child shutdown passed; Factorio was not run.'
} finally {
  Set-Item Function:\Invoke-MIRNativeProbeFactorioProcess -Value $nativeActor
  foreach($lease in $inputLeases){if(-not $lease.closed){$null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed}}
  if(Test-Path -LiteralPath $scratch){$null=Assert-MIRImmutableInputPathWithin -Path $scratch -Root (Join-Path $repo 'build/tmp') -Context 'owned tiny F200 fixture cleanup';Remove-Item -LiteralPath $scratch -Recurse -Force}
}
