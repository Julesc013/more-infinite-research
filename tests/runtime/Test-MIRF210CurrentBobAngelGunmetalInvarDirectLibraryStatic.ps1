# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Assert-GIStatic([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir-f210-ba-gunmetal-invar-direct-library-static-$Code]"}}
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$dossierPath=Join-Path $repo 'fixtures/run-profiles/f210-bob-angel-gunmetal-invar-2122.json'
$dossier=Get-Content -LiteralPath $dossierPath -Raw|ConvertFrom-Json -Depth 50 -DateKind String
Assert-GIStatic (([int]$dossier.schema -eq 1) -and ([string]$dossier.kind -ceq 'MIRF210CurrentBobAngelGunmetalInvarDirectLibraryQualificationV3')) 'dossier-identity'
Assert-GIStatic (([string]$dossier.target.engine.version -ceq '2.1.22') -and ([string]$dossier.target.engine.sha256 -ceq 'D8C745FD4E8C901BF0FC250C4D0FF75B454987857C1AEAADF8E775F0E65A9E4B')) 'engine-identity'
Assert-GIStatic ((@($dossier.target.official_mods) -join ',') -ceq 'base,elevated-rails,quality,recycler,space-age') 'official-closure'
Assert-GIStatic ((@($dossier.target.archives).Count -eq 11) -and (@($dossier.target.archives|Group-Object file|Where-Object Count -gt 1).Count -eq 0)) 'archive-cardinality'
foreach($archive in @($dossier.target.archives)){Assert-GIStatic (([string]$archive.file -ceq (([string]$archive.name)+'_'+([string]$archive.version)+'.zip')) -and ([string]$archive.sha256 -cmatch '^[0-9A-F]{64}$')) 'archive-identity'}
$portable=(Resolve-Path -LiteralPath (Join-Path $repo ([string]$dossier.settings.portable_path))).Path;$portableSha=(Get-FileHash -LiteralPath $portable -Algorithm SHA256).Hash.ToUpperInvariant()
Assert-GIStatic (([string]$dossier.settings.mode -ceq 'File') -and [bool]$dossier.settings.portable_input_required -and ($portableSha -ceq [string]$dossier.settings.portable_sha256) -and ($portableSha -cne [string]$dossier.historical_2_1_20.settings_sha256)) 'portable-settings'
Assert-GIStatic (([string]$dossier.historical_2_1_20.engine_version -ceq '2.1.20') -and ([string]$dossier.historical_2_1_20.settings_sha256 -ceq '2D258A213E7A4230563651ABD1B7D8268318A2DED5E23F3B20AFB6F1D56ECA6A')) 'historical-provenance'
foreach($mode in @('observe','qualification')){
  $fixture=$dossier.fixtures.$mode;$root=(Resolve-Path -LiteralPath (Join-Path $repo ([string]$fixture.source_path))).Path;$info=Get-Content -LiteralPath (Join-Path $root 'info.json') -Raw|ConvertFrom-Json
  Assert-GIStatic (([string]$info.name -ceq [string]$fixture.name) -and ([string]$info.version -ceq [string]$fixture.version)) "fixture-identity-$mode"
  foreach($file in @('data-final-fixes.lua','control.lua')){Assert-GIStatic (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf) "fixture-file-$mode"}
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
foreach($fragment in @('DATA PASS','unique-owners=true')){Assert-GIStatic ($qualificationData.Contains($fragment,[StringComparison]::Ordinal)) 'qualification-data-marker'}
foreach($fragment in @('RUNTIME PASS','stage=create technologies=researched','RELOAD PASS','technologies=researched save-state=preserved')){Assert-GIStatic ($qualificationControl.Contains($fragment,[StringComparison]::Ordinal)) 'qualification-runtime-marker'}
$runner=Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelGunmetalInvarQualification.ps1';$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors);Assert-GIStatic (@($errors).Count -eq 0) 'runner-parses'
foreach($readerFunction in @('Assert-GI','Read-GIDossier')){
  $readerNodes=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $readerFunction},$true))
  Assert-GIStatic ($readerNodes.Count -eq 1) 'unique-actual-dossier-reader'
  . ([scriptblock]::Create($readerNodes[0].Extent.Text))
}
$actualDossier=Read-GIDossier -Path $dossierPath
Assert-GIStatic ([string]$actualDossier.fixtures.observe.version -ceq [string]$dossier.fixtures.observe.version) 'actual-dossier-reader-accepts-selected-fixture'
$parameters=@($ast.ParamBlock.Parameters.Name.VariablePath.UserPath);$missing=@(@('FactorioBin','LocalModLibraryDirs','SettingsPath','SettingsSha256','CandidateZip','SourceMaterializationPath','Mode','PrepareOnly')|Where-Object {$_ -notin $parameters});Assert-GIStatic ($missing.Count -eq 0) 'runner-inputs'
$outputParameter=@($ast.ParamBlock.Parameters|Where-Object {$_.Name.VariablePath.UserPath -ceq 'OutputRoot'})
Assert-GIStatic ($outputParameter.Count -eq 1) 'runner-output-parameter'
. (Join-Path $repo 'tools/mir/application/release/readiness/ResourceGovernor.ps1')
$defaultOutput=Join-Path $repo ([string]$outputParameter[0].DefaultValue.SafeGetValue())
Assert-GIStatic ((Resolve-MIR441RecoveryScratchPath -Path $defaultOutput) -ceq ([IO.Path]::GetFullPath($defaultOutput))) 'default-output-admitted-by-actual-governor'
$outsideOutputRejected=$false
try{Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo 'build/tests/f210-gi-refusal-control')|Out-Null}catch{$outsideOutputRejected=$_.Exception.Message -match '\[mir441-resource-output-root\]'}
Assert-GIStatic $outsideOutputRejected 'outside-output-rejected-by-actual-governor'
$text=[IO.File]::ReadAllText($runner)
foreach($required in @('Start-MIRLibraryActivation','Complete-MIRLibraryActivation','Resolve-MIRNativeProbeDependencyInputs','Assert-MIRLibraryFixtureArchive','-SettingsMode File','--create','--benchmark','Add-MIRNativeProbeLibraryActivation','Get-GIObservation','failed-terminal-result-retained','controls_restoration','f210-ba-gunmetal-invar.reload-','foreach($ordinal in 1..2)')){Assert-GIStatic ($text.Contains($required,[StringComparison]::Ordinal)) 'runner-direct-library'}
foreach($forbidden in @('mir-native-obsolete-runner','ImmutableInputStaging.ps1','New-MIRImmutableInputLease','RequireHardLinks','Publish-MIRModDirectoryArchive','ExactStageRoot','RecoverRun')){Assert-GIStatic (-not$text.Contains($forbidden,[StringComparison]::Ordinal)) 'runner-no-staging'}
Assert-GIStatic ((@($dossier.certificate.routes|ForEach-Object {[string]$_.technology})-join',') -ceq 'recipe-prod-research_material_gunmetal-1,recipe-prod-research_material_invar-1') 'certificate-subjects'
Write-Host '[ok] F210 Gunmetal/Invar direct-library statics passed; observer fact capture and qualification remain distinct, with no engine process.'
