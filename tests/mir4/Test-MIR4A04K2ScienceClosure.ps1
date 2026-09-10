# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot='',[switch]$RequireLocalEvidence)
$ErrorActionPreference='Stop'
if(-not $RepoRoot){$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path}
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/tooling/CommandInventory.ps1')
function Assert-A04Closure { param([bool]$Condition,[string]$Code) if(-not $Condition){throw $Code} }
function Resolve-A04ClosurePath { param([string]$Relative,[bool]$File=$true)
  Assert-A04Closure ($Relative -cmatch '^[A-Za-z0-9._/-]+$' -and $Relative -notmatch '(^|/)\.\.(/|$)') "[mir4-a04-closure-relative-path] $Relative"
  $path=[IO.Path]::GetFullPath((Join-Path $RepoRoot $Relative));$prefix=$RepoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  Assert-A04Closure $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) "[mir4-a04-closure-path-escape] $Relative"
  if($File){Assert-A04Closure (Test-Path -LiteralPath $path -PathType Leaf) "[mir4-a04-closure-missing] $Relative"}else{Assert-A04Closure (Test-Path -LiteralPath $path -PathType Container) "[mir4-a04-closure-directory-missing] $Relative"}
  return $path
}
function Get-A04ClosureRaw { param([string]$Relative)
  return (Get-MIR4Sha256File -Path (Resolve-A04ClosurePath $Relative $true))
}
function Get-A04ClosureRecord { param([string]$Relative,[string]$Schema)
  $text=Get-Content -Raw -LiteralPath (Resolve-A04ClosurePath $Relative $true)
  Assert-A04Closure ($text|Test-Json -SchemaFile (Resolve-A04ClosurePath $Schema $true)) "[mir4-a04-closure-schema] $Relative"
  Assert-A04Closure ($text-notmatch '(?i)(?:[A-Z]:[\\/]|\\\\)') "[mir4-a04-closure-private-path] $Relative"
  $record=$text|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-A04Closure (Test-MIR4BootstrapRecordHash $record) "[mir4-a04-closure-self-hash] $Relative"
  return $record
}
function Assert-A04ClosureArray { param($Actual,[string[]]$Expected,[string]$Code)
  Assert-A04Closure (((@($Actual)|ForEach-Object{[string]$_})-join'|') -ceq ((@($Expected)|ForEach-Object{[string]$_})-join'|')) $Code
}
function Get-A04ClosureFunctionProjectionHash { param([string[]]$Names)
  $canonical=if(@($Names).Count-eq0){'[]'}else{ConvertTo-MIR4BootstrapCanonicalJson -Value $Names}
  return Get-MIR4Sha256String -Value $canonical
}
function Get-A04ClosureFunctions { param([string]$Relative)
  $tokens=$null;$errors=$null;$path=Resolve-A04ClosurePath $Relative $true;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
  Assert-A04Closure ($errors.Count-eq0) "[mir4-a04-closure-compat-parser] $Relative"
  $names=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object Name)
  return [pscustomobject][ordered]@{path=$Relative;canonical_sha256=(Get-MIR4BootstrapTextSha256 -Path $path);lines=[IO.File]::ReadAllLines($path).Count;function_names=$names;function_projection_sha256=(Get-A04ClosureFunctionProjectionHash $names);parse_errors=0}
}
function Assert-A04ClosureArtifact { param($Artifact,[string]$Code)
  Assert-A04Closure ([string]$Artifact.path -cmatch '^[A-Za-z0-9._/-]+$' -and [string]$Artifact.raw_sha256 -cmatch '^[A-F0-9]{64}$' -and [long]$Artifact.bytes -ge 0) $Code
  if($RequireLocalEvidence){$path=Resolve-A04ClosurePath ([string]$Artifact.path) $true;Assert-A04Closure ((Get-MIR4Sha256File -Path $path)-eq[string]$Artifact.raw_sha256 -and [long](Get-Item -LiteralPath $path).Length-eq[long]$Artifact.bytes) "$Code-local"}
}
$closureRelative='spec/programmes/evidence/synthesis-2026-09-10/a04-k2-science/MIR4-A04-K2-Science-ClosureV1.json'
$proofRelative='spec/programmes/evidence/synthesis-2026-09-10/a04-k2-science/MIR4-A04-K2-Science-Runtime-ProofV1.json'
$programmePath='spec/programmes/mir4-4x-operating-programme-v1.json'
$closure=Get-A04ClosureRecord $closureRelative 'spec/schemas/mir4-a04-k2-science-closure-v1.schema.json'
$proof=Get-A04ClosureRecord $proofRelative 'spec/schemas/mir4-a04-k2-science-runtime-proof-v1.schema.json'
$programme=Get-Content -Raw -LiteralPath (Resolve-A04ClosurePath $programmePath $true)|ConvertFrom-Json -Depth 100 -DateKind String;$programmeA04=@($programme.synthesis.tasks|Where-Object{ $_.id -ceq 'A04' });Assert-A04Closure ($programmeA04.Count-eq1 -and $programmeA04[0].state-ceq'complete') '[mir4-a04-closure-programme-state]';Assert-A04ClosureArray $programmeA04[0].evidence @($proofRelative,$closureRelative) '[mir4-a04-closure-programme-evidence]'
foreach($property in @('candidate','engine','mod_closure','controlled_witness')){Assert-A04Closure ((ConvertTo-MIR4BootstrapCanonicalJson -Value $closure.$property) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $proof.$property)) "[mir4-a04-closure-proof-cross-binding] $property"}
Assert-A04Closure ($closure.kind-eq'MIR4A04K2ScienceClosureV1' -and $closure.status-eq'passed' -and $proof.kind-eq'MIR4A04K2ScienceRuntimeProofV1' -and $proof.status-eq'passed') '[mir4-a04-closure-kinds]'
Assert-A04Closure ($closure.runtime_proof.path-eq$proofRelative -and $closure.runtime_proof.raw_sha256-eq(Get-A04ClosureRaw $proofRelative) -and $closure.runtime_proof.record_sha256-eq$proof.record_sha256) '[mir4-a04-closure-proof-binding]'
Assert-A04Closure ($closure.candidate.archive_sha256-eq'99C020CBA2800179FF2D76EE35F58B27A97CF2A7D89993CFFE06403DC140090E' -and $closure.candidate.content_sha256-eq'2C6829889A140B95BF999D013ADE6A0B651A71FFCE2A52489D2C815ABE872735' -and [int64]$closure.candidate.bytes-eq1103729 -and [int]$closure.candidate.entries-eq337 -and $closure.candidate.source_commit-eq'aed35814232d1ebf629f980ac98869c3e8336903' -and $closure.candidate.source_tree-eq'd68c32d425ae544f73f5762925c3ce429ef6cd3c') '[mir4-a04-closure-candidate]'
Assert-A04Closure ($closure.engine.line-eq'2.1' -and $closure.engine.version-eq'2.1.17.87315' -and $closure.engine.executable_sha256-eq'710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8') '[mir4-a04-closure-engine]'
$enabled=@('base','elevated-rails','quality','recycler','space-age','flib','k2so-assets','Krastorio2','Krastorio2-spaced-out','Krastorio2Assets','Krastorio2MenuSimulations','mir-fixture-assert-k2-science-progressed-reload-a04','mir-validation-settings-overrides','more-infinite-research','xy-k2so-enhancements-nulls-fork')
Assert-A04ClosureArray $closure.mod_closure.enabled_mods $enabled '[mir4-a04-closure-enabled-mods]'
$external=@('flib|0.17.2|0A48C15DC0FC6C13BB3FE8293BA6CB35A07F3B0F37D37ACB50AB30E32E8E019D','k2so-assets|1.0.7|C3E11214407B08120B2EE717405D3B0398F533647695AB2E6EF6DF9267D62017','Krastorio2|2.1.2|89989E60784EA3E94345289E063C64ABFCE5F35693DB7B9A69D656A163620F43','Krastorio2-spaced-out|2.0.13|A2EEB2E5A6119C4117BD3653979D40D305D17539E184BFA6F4ED53EF12A5F242','Krastorio2Assets|2.1.0|39EF950EC8B21A40357DD0240EF8389501EE75CCA82717F2773B98554DA46E29','Krastorio2MenuSimulations|2.1.0|3A485B449B356DC4B3EB4233DE4E803B3A001259FBC251BDC9F9D9120B3C53A7','xy-k2so-enhancements-nulls-fork|0.8.3|930F43B96B04012FEF090C40D8B16A6B3F259D1713C86CF59DFF3E9A5A97E2BE')
Assert-A04ClosureArray @($closure.mod_closure.external_archives|ForEach-Object{"$($_.name)|$($_.version)|$($_.sha256)"}) $external '[mir4-a04-closure-external-mods]'
foreach($binding in @($closure.source_authorities.policy,$closure.source_authorities.planner,$closure.source_authorities.scenario)+@($closure.source_authorities.fixture)){Assert-A04Closure ((Get-MIR4BootstrapTextSha256 -Path (Resolve-A04ClosurePath ([string]$binding.path) $true))-eq[string]$binding.canonical_sha256) "[mir4-a04-closure-source] $($binding.path)"}
Assert-A04ClosureArray @($closure.source_authorities.fixture|ForEach-Object path) @('fixtures/assert-k2-science-progressed-reload-a04/info.json','fixtures/assert-k2-science-progressed-reload-a04/control.lua') '[mir4-a04-closure-fixture-paths]'
Assert-A04ClosureArray @($closure.source_authorities.policy.path,$closure.source_authorities.planner.path,$closure.source_authorities.scenario.path) @('targets/f210/files/prototypes/mir/compatibility/policies/k2_science_phase.lua','targets/f210/files/prototypes/mir/planner/science.lua','validation/scenarios/local-2.1.json') '[mir4-a04-closure-authority-paths]'
$lineageSchemas=[ordered]@{
  'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-execution-proof.json'='spec/schemas/mir4-a03-k2-k2so-execution-proof-v1.schema.json'
  'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-intake-dossier.json'='spec/schemas/mir4-a03-k2-k2so-intake-dossier-v1.schema.json'
  'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-intake-receipt.json'='spec/schemas/mir4-a03-k2-k2so-intake-receipt-v1.schema.json'
  'releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json'='contracts/repository/mir4-m42-02-compatibility-audit-decomposition-v1.schema.json'
}
foreach($binding in @($closure.lineage.a03_execution_proof,$closure.lineage.a03_dossier,$closure.lineage.a03_receipt,$closure.compatibility_audit_evolution.historical_receipt)){
  Assert-A04Closure ($lineageSchemas.Contains([string]$binding.path)) "[mir4-a04-closure-lineage-path] $($binding.path)"
  $path=Resolve-A04ClosurePath ([string]$binding.path) $true;$raw=Get-Content -Raw -LiteralPath $path;Assert-A04Closure ($raw|Test-Json -SchemaFile (Resolve-A04ClosurePath $lineageSchemas[[string]$binding.path] $true)) "[mir4-a04-closure-lineage-schema] $($binding.path)"
  $record=$raw|ConvertFrom-Json -Depth 100 -DateKind String;Assert-A04Closure (Test-MIR4BootstrapRecordHash $record) "[mir4-a04-closure-lineage-self-hash] $($binding.path)";Assert-A04Closure ($binding.raw_sha256-eq(Get-A04ClosureRaw ([string]$binding.path)) -and $binding.record_sha256-eq$record.record_sha256) "[mir4-a04-closure-lineage] $($binding.path)"
}
Assert-A04Closure ($closure.lineage.a03_lock.path-eq'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-current.lock.json' -and $closure.lineage.a03_lock.raw_sha256-eq(Get-A04ClosureRaw $closure.lineage.a03_lock.path)) '[mir4-a04-closure-a03-lock]'
Assert-A04Closure ($closure.controlled_witness.test.path-eq'tests/compiler/Test-MIRSciencePlanning.ps1' -and $closure.controlled_witness.test.raw_sha256-eq(Get-A04ClosureRaw $closure.controlled_witness.test.path) -and $closure.controlled_witness.harness.path-eq'tests/compiler/science_planning.lua' -and $closure.controlled_witness.harness.raw_sha256-eq(Get-A04ClosureRaw $closure.controlled_witness.harness.path) -and $closure.controlled_witness.status-eq'passed' -and $closure.controlled_witness.scope-eq'controlled-modules-not-real-k2-qualification' -and [int]$closure.controlled_witness.assertions-eq33 -and $closure.controlled_witness.configured -and $closure.controlled_witness.additive -and $closure.controlled_witness.required -and $closure.controlled_witness.reduce -and $closure.controlled_witness.skip -and $closure.controlled_witness.default) '[mir4-a04-closure-controlled-witness]'
Assert-A04Closure ((ConvertTo-MIR4BootstrapCanonicalJson -Value $closure.controlled_witness) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $proof.controlled_witness)) '[mir4-a04-closure-controlled-witness-cross-binding]'
$controlledSource=Get-Content -Raw -LiteralPath (Resolve-A04ClosurePath 'tests/compiler/science_planning.lua' $true)
foreach($case in @('S01','S04','P01','L03','L04')){Assert-A04Closure ($controlledSource.Contains("check('$case'")) "[mir4-a04-closure-controlled-case-source] $case"}
Assert-A04Closure ($controlledSource.Contains("check('X-'..mode") -and $controlledSource.Contains("'all'")) '[mir4-a04-closure-controlled-case-source] X-all'
if($RequireLocalEvidence){$witnessResult=Get-Content -Raw -LiteralPath (Resolve-A04ClosurePath $closure.controlled_witness.result.path $true)|ConvertFrom-Json -Depth 100 -DateKind String;Assert-A04Closure ($witnessResult.test_sha256-eq$closure.controlled_witness.harness.raw_sha256 -and $witnessResult.log_sha256-eq$closure.controlled_witness.log.raw_sha256 -and $witnessResult.status-eq$closure.controlled_witness.status -and [int]$witnessResult.assertions-eq[int]$closure.controlled_witness.assertions) '[mir4-a04-closure-controlled-witness-result]'}
$reason='No independent reproduction binds the reported defect to the published 4.1 package, and A04 introduces no package-visible correction: the immutable 4.2 development candidate already contains shipped F210 K2SciencePhasePolicyV1 and passes exact final-emission, progression, and two-reload proof. Retain K2-01 in the 4.2 feature train.'
$requests=Get-Content -Raw -LiteralPath (Resolve-A04ClosurePath 'spec/programmes/community-requests.json' $true)|ConvertFrom-Json -Depth 100 -DateKind String;$k2=@($requests.requests|Where-Object{ $_.id -eq 'K2-01' })
Assert-A04Closure ($closure.patch_eligibility.classification-eq'not-eligible-for-4.1.x-patch' -and $closure.patch_eligibility.reason-eq$reason -and $k2.Count-eq1 -and $k2[0].original_request.patch_candidate-eq'4.1.x only if independently reproduced and repair fits existing compatibility contract') '[mir4-a04-closure-patch-eligibility]'
foreach($source in @($closure.patch_eligibility.k2_request,$closure.patch_eligibility.delivery_rule)){Assert-A04Closure ((Get-MIR4BootstrapTextSha256 -Path (Resolve-A04ClosurePath ([string]$source.path) $true))-eq[string]$source.canonical_sha256) "[mir4-a04-closure-patch-source] $($source.path)"}
Assert-A04ClosureArray @($closure.patch_eligibility.k2_request.path,$closure.patch_eligibility.delivery_rule.path) @('spec/programmes/community-requests.json','docs/releases/mir4-integration-and-delivery-plan.md') '[mir4-a04-closure-patch-source-paths]'
Assert-A04Closure ((ConvertTo-MIR4BootstrapCanonicalJson -Value $closure.patch_eligibility.a03_candidate) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $closure.lineage.a03_execution_proof) -and (ConvertTo-MIR4BootstrapCanonicalJson -Value $closure.patch_eligibility.runtime_proof) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $closure.runtime_proof)) '[mir4-a04-closure-patch-bindings]'
Assert-A04Closure ($proof.scenario.id-eq'local-2-1-krastorio-spaced-out' -and $proof.scenario.runtime_fixtures.Count-eq1 -and $proof.scenario.runtime_fixtures[0]-eq'fixtures/assert-k2-science-progressed-reload-a04' -and $proof.scenario.reload_policy.required_count-eq2 -and $proof.scenario.reload_policy.max_duration_seconds-eq300) '[mir4-a04-closure-runtime-scenario]'
Assert-A04ClosureArray $proof.final_emission.early.required_packs @('automation-science-pack','logistic-science-pack','chemical-science-pack','production-science-pack','electromagnetic-science-pack') '[mir4-a04-closure-early-science]'
Assert-A04ClosureArray $proof.final_emission.late.required_packs @('production-science-pack','space-science-pack') '[mir4-a04-closure-late-science]'
Assert-A04ClosureArray $proof.final_emission.early.observed_packs @('automation-science-pack','chemical-science-pack','electromagnetic-science-pack','logistic-science-pack','production-science-pack') '[mir4-a04-closure-early-observed-science]'
Assert-A04ClosureArray $proof.final_emission.late.observed_packs @('production-science-pack','space-science-pack') '[mir4-a04-closure-late-observed-science]'
$forbiddenEarly=@($proof.source_evidence.initial.forbidden_science_assertions|Where-Object{ $_.stream -eq 'research_advanced_circuit' });$forbiddenLate=@($proof.source_evidence.initial.forbidden_science_assertions|Where-Object{ $_.stream -eq 'research_belts' });Assert-A04Closure ($forbiddenEarly.Count-eq1 -and $forbiddenLate.Count-eq1) '[mir4-a04-closure-forbidden-science-streams]'
Assert-A04ClosureArray $forbiddenEarly[0].forbidden_packs @('kr-basic-tech-card') '[mir4-a04-closure-early-forbidden-science]'
Assert-A04ClosureArray $forbiddenLate[0].forbidden_packs @('kr-basic-tech-card','automation-science-pack','logistic-science-pack','military-science-pack','chemical-science-pack') '[mir4-a04-closure-late-forbidden-science]'
Assert-A04Closure ($proof.final_emission.passed -and [int]$proof.final_emission.early.matching_generated_rows-eq1 -and [int]$proof.final_emission.late.matching_generated_rows-eq1 -and $proof.source_evidence.initial.initial_marker_count-eq1 -and (@($proof.source_evidence.reloads|Where-Object{$_.passed -and $_.save_byte_identical -and $_.marker_count-eq1 -and $_.reload_log_contract_passed -and $_.duration_seconds-le300}).Count-eq2)) '[mir4-a04-closure-runtime-reloads]'
$expectedArtifacts=[ordered]@{
  campaign='build/mir4/a04-k2-science/runtime-attempt-01/campaign-evidence.json|7073765|5EEAFE4DB1DCED05770816AB4EA065DAFB3A4DC9115CA04CEDDE28E8B99BFBB1'
  dependency_lock='build/mir4/a04-k2-science/runtime-attempt-01/compat-candidates.lock.json|19060|433CF56ED355ED4990683ADC348B042F14B4632184DBCA23491F987DBC69574A'
  candidate='build/mir4/a04-k2-science/runtime-attempt-01/runs/u-2b53bbdc18fc/mods/more-infinite-research_4.2.21000.zip|1103729|99C020CBA2800179FF2D76EE35F58B27A97CF2A7D89993CFFE06403DC140090E'
  mod_list='build/mir4/a04-k2-science/runtime-attempt-01/runs/u-2b53bbdc18fc/mods/mod-list.json|1159|C1E5F0CE699CA7C304F53D2CBB02DC8255B5638B8A721D2F6838E55460787D3F'
  mod_settings='build/mir4/a04-k2-science/runtime-attempt-01/runs/u-2b53bbdc18fc/mods/mod-settings.dat|49830|B1AEDF80F4D70621320EB824C9E2CC83D80B0C89096B23D5A6BB830C05411D76'
  save='build/mir4/a04-k2-science/runtime-attempt-01/runs/u-2b53bbdc18fc/saves/local-2-1-krastorio-spaced-out.zip|765763|A197C9994747084E5B893F3739FED2E834B755D4DDFBF7A7D4C562FFCD0BEAF9'
  initial_log='build/mir4/a04-k2-science/runtime-attempt-01/runs/u-2b53bbdc18fc/local-2-1-krastorio-spaced-out.factorio.log|9894920|1766B9FED260ADF717CBD2C389F2195488E62FFA20EF213C0D23D88AD128149D'
  reload_01_log='build/mir4/a04-k2-science/runtime-attempt-01/runs/u-2b53bbdc18fc/local-2-1-krastorio-spaced-out.reload-01.factorio.log|9893607|670F78C11407C7563D8B8A7C24191BCB35D9E0E1CEEDB8D786453C4A2D541EB9'
  reload_02_log='build/mir4/a04-k2-science/runtime-attempt-01/runs/u-2b53bbdc18fc/local-2-1-krastorio-spaced-out.reload-02.factorio.log|9893607|6CDABB39AC52EB7C936E3AECA6AA87A580132E92C8B5D27F6568C7302A728886'
}
$actualArtifacts=[ordered]@{campaign=$proof.source_evidence.campaign;dependency_lock=$proof.source_evidence.dependency_lock;candidate=$proof.source_evidence.candidate;mod_list=$proof.source_evidence.mod_list;mod_settings=$proof.source_evidence.mod_settings;save=$proof.source_evidence.save;initial_log=$proof.source_evidence.initial.factorio_log;reload_01_log=$proof.source_evidence.reloads[0].factorio_log;reload_02_log=$proof.source_evidence.reloads[1].factorio_log}
foreach($key in $expectedArtifacts.Keys){Assert-A04Closure ("$($actualArtifacts[$key].path)|$($actualArtifacts[$key].bytes)|$($actualArtifacts[$key].raw_sha256)" -ceq $expectedArtifacts[$key]) "[mir4-a04-closure-runtime-artifact-exact] $key"}
foreach($artifact in @($proof.source_evidence.campaign,$proof.source_evidence.dependency_lock,$proof.source_evidence.candidate,$proof.source_evidence.mod_list,$proof.source_evidence.mod_settings,$proof.source_evidence.save,$proof.source_evidence.initial.save,$proof.source_evidence.initial.stdout,$proof.source_evidence.initial.stderr,$proof.source_evidence.initial.factorio_log)+@($proof.source_evidence.reloads|ForEach-Object{@($_.stdout,$_.stderr,$_.factorio_log)})){Assert-A04ClosureArtifact $artifact '[mir4-a04-closure-runtime-artifact]'}
$modulePaths=@('tools/lib/compatibility/FactorioRunner.ps1','tools/commands/compatibility/compat-audit/Configuration.ps1','tools/commands/compatibility/compat-audit/InputDiscovery.ps1','tools/commands/compatibility/compat-audit/ScenarioDefinitions.ps1','tools/commands/compatibility/compat-audit/ScenarioSelection.ps1','tools/commands/compatibility/compat-audit/ScenarioResolution.ps1','tools/commands/compatibility/compat-audit/ResultCollation.ps1')
Assert-A04ClosureArray @($closure.compatibility_audit_evolution.modules|ForEach-Object path) $modulePaths '[mir4-a04-closure-compat-module-order]'
$modules=@($modulePaths|ForEach-Object{Get-A04ClosureFunctions $_});foreach($module in $modules){$actual=@($closure.compatibility_audit_evolution.modules|Where-Object{ $_.path -eq $module.path });Assert-A04Closure ($actual.Count-eq1 -and ($actual[0]|ConvertTo-Json -Depth 100 -Compress)-eq($module|ConvertTo-Json -Depth 100 -Compress)) "[mir4-a04-closure-compat-module] $($module.path)"}
$projection=@($modules|ForEach-Object{[pscustomobject][ordered]@{path=$_.path;function_names=$_.function_names}})
Assert-A04Closure ($closure.compatibility_audit_evolution.aggregate_function_projection_sha256-eq(Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $projection))) '[mir4-a04-closure-compat-projection]'
$historical=Get-Content -Raw -LiteralPath (Resolve-A04ClosurePath 'releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json' $true)|ConvertFrom-Json -Depth 100 -DateKind String
$facadePath=Resolve-A04ClosurePath 'tools/commands/compatibility/Invoke-MIRCompatAudit.ps1' $true;$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($facadePath,[ref]$tokens,[ref]$errors);$currentParamHash=Get-MIR4Sha256String -Value ($ast.ParamBlock.Extent.Text.Replace(([string][char]13+[char]10),[string][char]10).Replace([string][char]13,[string][char]10)+[string][char]10)
Assert-A04Closure ($errors.Count-eq0 -and $historical.public_contract.parameter_block_sha256-eq'05DC28344ADFEAD174F6CAAF4E0A4515FD75E58A113824E2EB8422DADA3F842F' -and $closure.compatibility_audit_evolution.facade.historical_parameter_surface_sha256-eq$historical.public_contract.parameter_block_sha256 -and $closure.compatibility_audit_evolution.facade.current_parameter_surface_sha256-eq$currentParamHash -and $closure.compatibility_audit_evolution.facade.current_parameter_surface_sha256-eq$closure.compatibility_audit_evolution.facade.historical_parameter_surface_sha256 -and $closure.compatibility_audit_evolution.facade.parameter_surface_unchanged) '[mir4-a04-closure-facade]'
$semantics=$closure.compatibility_audit_evolution.reload_semantics
Assert-A04Closure ($semantics.scenario_schema-eq2 -and $semantics.activation-eq'explicit-manual-scenario-opt-in-only' -and $semantics.runtime_fixtures_default.Count-eq0 -and $semantics.required_reload_count_default-eq0 -and $semantics.max_reload_duration_seconds_default-eq0 -and $semantics.required_reload_log_fragments_default.Count-eq0 -and $semantics.required_reload_count_minimum-eq0 -and $semantics.required_reload_count_maximum-eq2 -and $semantics.reload_duration_minimum-eq1 -and $semantics.reload_duration_maximum-eq3600 -and $semantics.default_behavior_unchanged) '[mir4-a04-closure-opt-in]'
$inventoryPath=Resolve-A04ClosurePath 'governance/automation/mir4-command-inventory-v1.json' $true;$inventory=Get-Content -Raw -LiteralPath $inventoryPath|ConvertFrom-Json -Depth 100 -DateKind String
Assert-A04Closure ($closure.compatibility_audit_evolution.command_inventory.raw_sha256-eq(Get-MIR4Sha256File -Path $inventoryPath) -and $closure.compatibility_audit_evolution.command_inventory.canonical_sha256-eq(Get-MIR4BootstrapTextSha256 -Path $inventoryPath) -and $closure.compatibility_audit_evolution.command_inventory.digest-eq$inventory.digest -and [int]$closure.compatibility_audit_evolution.command_inventory.command_count-eq[int]$inventory.command_count) '[mir4-a04-closure-inventory]'
Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot -Check|Out-Null
Assert-A04Closure (@($closure.authority_flags.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0 -and (@($closure.non_claims)-join'|') -ceq'No player mutation authority.|No generated-prototype write authority.|No public support, release, signing, or publication authority.') '[mir4-a04-closure-boundary]'
'[ok] MIR4 A04 K2 science closure is exact and bounded.'