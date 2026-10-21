# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Assert-GIStatic([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir-f210-ba-gunmetal-invar-direct-library-static-$Code]"}}
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$dossierPath=Join-Path $repo 'fixtures/run-profiles/f210-bob-angel-gunmetal-invar-2122.json'
$dossier=Get-Content -LiteralPath $dossierPath -Raw|ConvertFrom-Json -Depth 50 -DateKind String
Assert-GIStatic (([int]$dossier.schema -eq 1) -and ([string]$dossier.kind -ceq 'MIRF210CurrentBobAngelGunmetalInvarDirectLibraryQualificationV4')) 'dossier-identity'
Assert-GIStatic (([string]$dossier.target.engine.version -ceq '2.1.22') -and ([string]$dossier.target.engine.sha256 -ceq 'D8C745FD4E8C901BF0FC250C4D0FF75B454987857C1AEAADF8E775F0E65A9E4B')) 'engine-identity'
Assert-GIStatic ((@($dossier.target.official_mods) -join ',') -ceq 'base,elevated-rails,quality,recycler,space-age') 'official-closure'
Assert-GIStatic ((@($dossier.target.archives).Count -eq 11) -and (@($dossier.target.archives|Group-Object file|Where-Object Count -gt 1).Count -eq 0)) 'archive-cardinality'
foreach($archive in @($dossier.target.archives)){Assert-GIStatic (([string]$archive.file -ceq (([string]$archive.name)+'_'+([string]$archive.version)+'.zip')) -and ([string]$archive.sha256 -cmatch '^[0-9A-F]{64}$')) 'archive-identity'}
$portable=(Resolve-Path -LiteralPath (Join-Path $repo ([string]$dossier.settings.portable_path))).Path;$portableSha=(Get-FileHash -LiteralPath $portable -Algorithm SHA256).Hash.ToUpperInvariant()
Assert-GIStatic (([string]$dossier.settings.mode -ceq 'File') -and [bool]$dossier.settings.portable_input_required -and ($portableSha -ceq [string]$dossier.settings.portable_sha256) -and ($portableSha -cne [string]$dossier.historical_2_1_20.settings_sha256)) 'portable-settings'
Assert-GIStatic (([string]$dossier.historical_2_1_20.engine_version -ceq '2.1.20') -and ([string]$dossier.historical_2_1_20.settings_sha256 -ceq '2D258A213E7A4230563651ABD1B7D8268318A2DED5E23F3B20AFB6F1D56ECA6A')) 'historical-provenance'
foreach($mode in @('observe','qualification')){
  $fixture=$dossier.fixtures.$mode;$fixtureDirectory=(Resolve-Path -LiteralPath (Join-Path $repo ([string]$fixture.source_path))).Path;$info=Get-Content -LiteralPath (Join-Path $fixtureDirectory 'info.json') -Raw|ConvertFrom-Json
  Assert-GIStatic (([string]$info.name -ceq [string]$fixture.name) -and ([string]$info.version -ceq [string]$fixture.version)) "fixture-identity-$mode"
  foreach($file in @('data-final-fixes.lua','control.lua')){Assert-GIStatic (Test-Path -LiteralPath (Join-Path $fixtureDirectory $file) -PathType Leaf) "fixture-file-$mode"}
}
$observer=(Resolve-Path -LiteralPath (Join-Path $repo ([string]$dossier.fixtures.observe.source_path))).Path
Assert-GIStatic (Test-Path -LiteralPath (Join-Path $observer 'settings-updates.lua') -PathType Leaf) 'observer-phase-aware-setting'
$observerData=[IO.File]::ReadAllText((Join-Path $observer 'data-final-fixes.lua'));$observerControl=[IO.File]::ReadAllText((Join-Path $observer 'control.lua'))
foreach($fragment in @('ROUTE family=', 'CERTIFICATE family=', 'BINDING family=', 'EMISSION family=', 'DATA PASS read-only-finalized-fact-capture')){Assert-GIStatic ($observerData.Contains($fragment,[StringComparison]::Ordinal)) 'observer-data-capture'}
foreach($forbidden in @('researched = true','enable_all_prototypes','game.create','force.reset')){Assert-GIStatic (-not$observerControl.Contains($forbidden,[StringComparison]::Ordinal)) 'observer-no-gameplay-mutation'}
foreach($fragment in @('RUNTIME stage=create','RUNTIME stage=reload')){Assert-GIStatic ($observerControl.Contains($fragment,[StringComparison]::Ordinal)) 'observer-runtime-capture'}
Assert-GIStatic ($observerData.Contains('[MIR_ACTIVE_MODS]',[StringComparison]::Ordinal)) 'observer-complete-mod-table'
$qualification=(Resolve-Path -LiteralPath (Join-Path $repo ([string]$dossier.fixtures.qualification.source_path))).Path
$qualificationData=[IO.File]::ReadAllText((Join-Path $qualification 'data-final-fixes.lua'));$qualificationControl=[IO.File]::ReadAllText((Join-Path $qualification 'control.lua'))
Assert-GIStatic ($qualificationData.Contains('[MIR_ACTIVE_MODS]',[StringComparison]::Ordinal)) 'qualification-complete-mod-table'
foreach($fragment in @('DATA PASS','staged-owners=true')){Assert-GIStatic ($qualificationData.Contains($fragment,[StringComparison]::Ordinal)) 'qualification-data-marker'}
$earned=$dossier.fixtures.qualification.earned_modifier
Assert-GIStatic ($null -ne $earned -and [double]$earned.effect_change -eq 0.02 -and [int]$earned.finite_completed_levels -eq 3 -and [double]$earned.finite_productivity_bonus -eq 0.06 -and [int]$earned.continuation_start_level -eq 4 -and [int]$earned.continuation_next_level -eq 5 -and [double]$earned.continuation_productivity_bonus -eq 0.08 -and [double]$earned.progress -eq 0.42 -and ((@($earned.queue)-join ',') -ceq 'recipe-prod-research_material_gunmetal-4,recipe-prod-research_material_invar-4')) 'qualification-earned-contract'
Assert-GIStatic ([string]$dossier.fixtures.qualification.mode -ceq 'earned-productivity-and-queued-next-level') 'qualification-earned-mode'
Assert-GIStatic (-not $qualificationControl.Contains('research_queue_enabled',[StringComparison]::Ordinal)) 'qualification-no-retired-f210-queue-api'
foreach($fragment in @('runtime_marker("RUNTIME PASS stage=create")','runtime_marker("RELOAD PASS stage=reload")','finite=researched continuation-level=5 bonuses=0.08','queue=gunmetal-then-invar progress=0.42','force.add_research(technology)','force.add_research(gunmetal) or not force.add_research(invar)','#queue ~= 2','queue[1].name ~= subjects[1].continuation','queue[2].name ~= subjects[2].continuation','continuation.level ~= 5','next-level queue or progress differs','earned productivity differs','state.version ~= 2')){Assert-GIStatic ($qualificationControl.Contains($fragment,[StringComparison]::Ordinal)) 'qualification-earned-runtime-and-rejection'}
foreach($fragment in @('recipe-prod-research_material_gunmetal-4','recipe-prod-research_material_invar-4','effect.change ~= 0.02','continuation level 4+ range differs')){Assert-GIStatic ($qualificationData.Contains($fragment,[StringComparison]::Ordinal)) 'qualification-staged-effect-contract'}
$runner=Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelGunmetalInvarQualification.ps1';$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors);Assert-GIStatic (@($errors).Count -eq 0) 'runner-parses'
foreach($readerFunction in @('Assert-GI','Read-GIDossier','Get-GISha','Invoke-GIReload','Assert-GIQualificationRuntime','Assert-GIReportedEngineVersion')){
  $readerNodes=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $readerFunction},$true))
  Assert-GIStatic ($readerNodes.Count -eq 1) 'unique-actual-dossier-reader'
  . ([scriptblock]::Create($readerNodes[0].Extent.Text))
}
$actualDossier=Read-GIDossier -Path $dossierPath
Assert-GIStatic ([string]$actualDossier.fixtures.observe.version -ceq [string]$dossier.fixtures.observe.version) 'actual-dossier-reader-accepts-selected-fixture'
$currentDossierPath=Join-Path $repo 'fixtures/run-profiles/f210-bob-angel-gunmetal-invar-2123.json'
$currentDossier=Read-GIDossier -Path $currentDossierPath
Assert-GIStatic ([string]$currentDossier.target.engine.version -ceq '2.1.23' -and [string]$currentDossier.target.engine.sha256 -ceq 'FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060') 'current-engine-identity'
foreach($field in @('settings','fixtures','certificate','historical_2_1_20')){
  Assert-GIStatic (($actualDossier.$field|ConvertTo-Json -Depth 50 -Compress) -ceq ($currentDossier.$field|ConvertTo-Json -Depth 50 -Compress)) ('retained-contract-'+$field)
}
Assert-GIStatic (($actualDossier.target.archives|ConvertTo-Json -Depth 20 -Compress) -ceq ($currentDossier.target.archives|ConvertTo-Json -Depth 20 -Compress)) 'current-upstream-closure-unchanged'
Assert-GIStatic ((@($actualDossier.target.official_mods)-join ',') -ceq (@($currentDossier.target.official_mods)-join ',')) 'current-official-names-unchanged'
$controlledDossierPath=Join-Path $repo ('build/tmp/gi-dossier-input-'+[guid]::NewGuid().ToString('N')+'.json')
$controlledDossierPrefix=[IO.Path]::GetFullPath((Join-Path $repo 'build/tmp')).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
Assert-GIStatic ([IO.Path]::GetFullPath($controlledDossierPath).StartsWith($controlledDossierPrefix,[StringComparison]::OrdinalIgnoreCase)) 'controlled-dossier-contained'
try{
  foreach($engine in @(
    @{version='2.1.24';sha256='FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060'},
    @{version='2.1.22';sha256='FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060'},
    @{version='2.1.23';sha256='D8C745FD4E8C901BF0FC250C4D0FF75B454987857C1AEAADF8E775F0E65A9E4B'}
  )){
    $changed=$currentDossier|ConvertTo-Json -Depth 50|ConvertFrom-Json -Depth 50
    $changed.target.engine.version=$engine.version;$changed.target.engine.sha256=$engine.sha256
    [IO.File]::WriteAllText($controlledDossierPath,($changed|ConvertTo-Json -Depth 50),[Text.UTF8Encoding]::new($false))
    $rejected=$false
    try{Read-GIDossier -Path $controlledDossierPath|Out-Null}catch{$rejected=$_.Exception.Message.Contains('fixture exact engine identity differs')}
    Assert-GIStatic $rejected 'unaccepted-engine-pair-rejected'
  }
}finally{if(Test-Path -LiteralPath $controlledDossierPath -PathType Leaf){Remove-Item -LiteralPath $controlledDossierPath -Force}}
Assert-GIReportedEngineVersion -Text 'Version: 2.1.22 (build retained)' -ExpectedVersion '2.1.22'
Assert-GIReportedEngineVersion -Text 'Version: 2.1.23 (build current)' -ExpectedVersion '2.1.23'
foreach($wrongVersion in @('2.1.22','2.1.230')){
  $rejected=$false
  try{Assert-GIReportedEngineVersion -Text ('Version: '+$wrongVersion+' (build wrong)') -ExpectedVersion '2.1.23'}catch{$rejected=$_.Exception.Message.Contains('engine reported a different version')}
  Assert-GIStatic $rejected 'reported-engine-version-rejected'
}
$qualificationFixture=$actualDossier.fixtures.qualification
Assert-GIQualificationRuntime -LogText (([string]$qualificationFixture.data_marker)+"`n"+([string]$qualificationFixture.create_marker)) -FixtureSpec $qualificationFixture -Stage create
Assert-GIQualificationRuntime -LogText (([string]$qualificationFixture.data_marker)+"`n"+([string]$qualificationFixture.reload_marker)) -FixtureSpec $qualificationFixture -Stage reload
$wrongQualificationMarkerRejected=$false
try{Assert-GIQualificationRuntime -LogText (([string]$qualificationFixture.data_marker)+"`n"+(([string]$qualificationFixture.create_marker).Replace('bonuses=0.08','bonuses=0.06'))) -FixtureSpec $qualificationFixture -Stage create}catch{$wrongQualificationMarkerRejected=$_.Exception.Message -match 'earned research state marker differs'}
Assert-GIStatic $wrongQualificationMarkerRejected 'earned-qualification-opposing-state-marker-rejected'
$run=Join-Path $repo 'build/tmp/gi-controlled-no-process'
$activation=[pscustomobject]@{library='controlled-library-not-opened'}
$controlledProcessPassed=$true
function Invoke-GIGovernedEngine([string]$Scenario,[string[]]$Arguments,[int]$TimeoutSeconds){
  [pscustomobject]@{passed=$controlledProcessPassed;duration_seconds=0;stdout='controlled';stderr='controlled';factorio_log='controlled'}
}
$controlledReload=Invoke-GIReload -SavePath $portable -Ordinal 2 -TimeoutSeconds 1
Assert-GIStatic ($controlledReload.passed -and $controlledReload.cold_process -eq $true -and $controlledReload.ordinal -eq 2 -and $controlledReload.save_byte_identical) 'actual-cold-reload-return-controls'
$controlledProcessPassed=$false
Assert-GIStatic (-not (Invoke-GIReload -SavePath $portable -Ordinal 2 -TimeoutSeconds 1).passed) 'failed-engine-result-is-not-a-passing-reload'
$parameters=@($ast.ParamBlock.Parameters.Name.VariablePath.UserPath);$missing=@(@('FactorioBin','LocalModLibraryDirs','SettingsPath','SettingsSha256','CandidateZip','SourceMaterializationPath','InputProfile','Mode','PrepareOnly')|Where-Object {$_ -notin $parameters});Assert-GIStatic ($missing.Count -eq 0) 'runner-inputs'
$outputParameter=@($ast.ParamBlock.Parameters|Where-Object {$_.Name.VariablePath.UserPath -ceq 'OutputRoot'})
Assert-GIStatic ($outputParameter.Count -eq 1) 'runner-output-parameter'
. (Join-Path $repo 'tools/mir/application/release/readiness/ResourceGovernor.ps1')
$defaultOutput=Join-Path $repo ([string]$outputParameter[0].DefaultValue.SafeGetValue())
Assert-GIStatic ((Resolve-MIR441RecoveryScratchPath -Path $defaultOutput) -ceq ([IO.Path]::GetFullPath($defaultOutput))) 'default-output-admitted-by-actual-governor'
$outsideOutputRejected=$false
try{Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo 'build/tests/f210-gi-refusal-control')|Out-Null}catch{$outsideOutputRejected=$_.Exception.Message -match '\[mir441-resource-output-root\]'}
Assert-GIStatic $outsideOutputRejected 'outside-output-rejected-by-actual-governor'
. (Join-Path $repo 'tools/lib/compatibility/LibraryActivation.ps1')
$oldInvocation="   0.000 2026-10-20 01:00:00; Factorio 2.1.22 (build test)`nold-state`n"
$newInvocation="   0.000 2026-10-20 01:01:00; Factorio 2.1.22 (build test)`nnew-state`n"
Assert-GIStatic ((Get-MIRLibraryLatestInvocationText -Text ($oldInvocation+$newInvocation)) -ceq $newInvocation) 'current-invocation-excludes-prior-state'
Assert-GIStatic ((Get-MIRLibraryLatestInvocationText -Text $newInvocation) -ceq $newInvocation) 'single-current-invocation-preserved'
$missingInvocationRejected=$false
try{Get-MIRLibraryLatestInvocationText -Text 'new-state without a launch boundary'|Out-Null}catch{$missingInvocationRejected=$_.Exception.Message -match '\[mir-library-loaded-invocation\]'}
Assert-GIStatic $missingInvocationRejected 'missing-current-invocation-rejected'
$text=[IO.File]::ReadAllText($runner)
foreach($required in @('Start-MIRLibraryActivation','Complete-MIRLibraryActivation','Resolve-MIRNativeProbeDependencyInputs','Assert-MIRLibraryFixtureArchive','-SettingsMode File','--create','--benchmark','Add-MIRNativeProbeLibraryActivation','Get-GIObservation','failed-terminal-result-retained','controls_restoration','f210-ba-gunmetal-invar.reload-','foreach($ordinal in 1..2)','Assert-GIQualificationRuntime','passed-narrow-earned-productivity-qualification')){Assert-GIStatic ($text.Contains($required,[StringComparison]::Ordinal)) 'runner-direct-library'}
foreach($forbidden in @('mir-native-obsolete-runner','ImmutableInputStaging.ps1','New-MIRImmutableInputLease','RequireHardLinks','Publish-MIRModDirectoryArchive','ExactStageRoot','RecoverRun')){Assert-GIStatic (-not$text.Contains($forbidden,[StringComparison]::Ordinal)) 'runner-no-staging'}
Assert-GIStatic ((@($dossier.certificate.routes|ForEach-Object {[string]$_.technology})-join',') -ceq 'recipe-prod-research_material_gunmetal-1,recipe-prod-research_material_invar-1') 'certificate-subjects'
Write-Host '[ok] F210 Gunmetal/Invar direct-library statics passed; observer fact capture and qualification remain distinct, with no engine process.'
