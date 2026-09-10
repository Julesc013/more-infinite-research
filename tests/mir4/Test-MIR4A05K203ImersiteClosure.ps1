# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot='',[switch]$RequireLocalEvidence)
$ErrorActionPreference='Stop'
if(-not $RepoRoot){$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path}
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-A05K203Closure { param([bool]$Condition,[string]$Code) if(-not $Condition){throw $Code} }
function Resolve-A05K203ClosurePath { param([string]$Relative)
  Assert-A05K203Closure ($Relative -cmatch '^[A-Za-z0-9._/-]+$' -and $Relative -notmatch '(^|/)\.\.(/|$)') "[mir4-a05-k2-03-closure-relative] $Relative"
  $path=[IO.Path]::GetFullPath((Join-Path $RepoRoot $Relative))
  $prefix=$RepoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  Assert-A05K203Closure ($path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) "[mir4-a05-k2-03-closure-escape] $Relative"
  Assert-A05K203Closure (Test-Path -LiteralPath $path -PathType Leaf) "[mir4-a05-k2-03-closure-missing] $Relative"
  $path
}
function Get-A05K203ClosureRecord { param([string]$Relative,[string]$Schema)
  $text=Get-Content -Raw -LiteralPath (Resolve-A05K203ClosurePath $Relative)
  Assert-A05K203Closure ($text|Test-Json -SchemaFile (Resolve-A05K203ClosurePath $Schema)) "[mir4-a05-k2-03-closure-schema] $Relative"
  Assert-A05K203Closure ($text-notmatch '(?i)(?:[A-Z]:[\\/]|\\\\)') "[mir4-a05-k2-03-closure-private] $Relative"
  $record=$text|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-A05K203Closure (Test-MIR4BootstrapRecordHash $record) "[mir4-a05-k2-03-closure-self-hash] $Relative"
  $record
}
function Assert-A05K203ClosureArray { param($Actual,[string[]]$Expected,[string]$Code)
  Assert-A05K203Closure (((@($Actual)|ForEach-Object{[string]$_})-join'|') -ceq ((@($Expected)|ForEach-Object{[string]$_})-join'|')) $Code
}
function Assert-A05K203ClosureArtifact { param($Artifact,[string]$Code)
  Assert-A05K203Closure ([string]$Artifact.path -cmatch '^[A-Za-z0-9._/-]+$' -and [string]$Artifact.raw_sha256 -cmatch '^[A-F0-9]{64}$' -and [long]$Artifact.bytes -ge 0) $Code
  if($RequireLocalEvidence){
    $path=Resolve-A05K203ClosurePath ([string]$Artifact.path)
    Assert-A05K203Closure ((Get-MIR4Sha256File -Path $path)-eq[string]$Artifact.raw_sha256 -and [long](Get-Item -LiteralPath $path).Length-eq[long]$Artifact.bytes) "$Code-local"
  }
}
function Get-A05K203ClosureRaw { param([string]$Relative) Get-MIR4Sha256File -Path (Resolve-A05K203ClosurePath $Relative) }

$proofRelative='spec/programmes/evidence/synthesis-2026-09-10/a05-k2-materials/k2-03/MIR4-A05-K2-03-Imersite-Runtime-ProofV1.json'
$closureRelative='spec/programmes/evidence/synthesis-2026-09-10/a05-k2-materials/k2-03/MIR4-A05-K2-03-Imersite-ClosureV1.json'
$proof=Get-A05K203ClosureRecord $proofRelative 'spec/schemas/mir4-a05-k2-03-imersite-runtime-proof-v1.schema.json'
$closure=Get-A05K203ClosureRecord $closureRelative 'spec/schemas/mir4-a05-k2-03-imersite-closure-v1.schema.json'
$evolutionRelative='spec/programmes/evidence/synthesis-2026-09-10/a05-k2-materials/k2-03/MIR4-A05-K2-03-Command-Inventory-EvolutionV1.json'
$evolution=Get-A05K203ClosureRecord $evolutionRelative 'spec/schemas/mir4-a05-k2-03-command-inventory-evolution-v1.schema.json'

Assert-A05K203Closure ($proof.kind-eq'MIR4A05K203ImersiteRuntimeProofV1' -and $proof.status-eq'passed-bounded' -and $closure.kind-eq'MIR4A05K203ImersiteClosureV1' -and $closure.status-eq'bounded-slice-passed') '[mir4-a05-k2-03-closure-kinds]'
Assert-A05K203Closure ($closure.runtime_proof.path-eq$proofRelative -and $closure.runtime_proof.raw_sha256-eq(Get-A05K203ClosureRaw $proofRelative) -and $closure.runtime_proof.record_sha256-eq$proof.record_sha256) '[mir4-a05-k2-03-closure-proof-binding]'
foreach($property in @('candidate','engine')){Assert-A05K203Closure ((ConvertTo-MIR4BootstrapCanonicalJson -Value $closure.$property)-ceq(ConvertTo-MIR4BootstrapCanonicalJson -Value $proof.$property)) "[mir4-a05-k2-03-closure-cross-binding] $property"}
Assert-A05K203Closure ($closure.candidate.archive_sha256-eq'99C020CBA2800179FF2D76EE35F58B27A97CF2A7D89993CFFE06403DC140090E' -and $closure.candidate.content_sha256-eq'2C6829889A140B95BF999D013ADE6A0B651A71FFCE2A52489D2C815ABE872735' -and [long]$closure.candidate.bytes-eq1103729 -and [int]$closure.candidate.entries-eq337 -and $closure.candidate.source_commit-eq'aed35814232d1ebf629f980ac98869c3e8336903' -and $closure.candidate.source_tree-eq'd68c32d425ae544f73f5762925c3ce429ef6cd3c') '[mir4-a05-k2-03-closure-candidate]'
Assert-A05K203Closure ($closure.engine.line-eq'2.1' -and $closure.engine.version-eq'2.1.17' -and $closure.engine.executable_sha256-eq'710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8') '[mir4-a05-k2-03-closure-engine]'

$sourcePaths=@('src/mod/families/modern/prototypes/streams/productivity.lua','src/mod/families/modern/prototypes/mir/streams/generated_stream_manifest.json','spec/programmes/community-requests.json','tests/runtime/Test-MIR4A05K203Imersite.ps1','fixtures/assert-k2-03-imersite/info.json','fixtures/assert-k2-03-imersite/data-final-fixes.lua','fixtures/assert-k2-03-imersite/control.lua')
Assert-A05K203ClosureArray @($closure.source_authorities|ForEach-Object path) $sourcePaths '[mir4-a05-k2-03-closure-source-order]'
foreach($source in @($closure.source_authorities)){Assert-A05K203Closure ((Get-MIR4BootstrapTextSha256 -Path (Resolve-A05K203ClosurePath $source.path))-eq[string]$source.canonical_sha256) "[mir4-a05-k2-03-closure-source] $($source.path)"}

$lineageSchemas=[ordered]@{
  'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-execution-proof.json'='spec/schemas/mir4-a03-k2-k2so-execution-proof-v1.schema.json'
  'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-intake-dossier.json'='spec/schemas/mir4-a03-k2-k2so-intake-dossier-v1.schema.json'
  'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-intake-receipt.json'='spec/schemas/mir4-a03-k2-k2so-intake-receipt-v1.schema.json'
}
foreach($binding in @($closure.lineage.a03_execution_proof,$closure.lineage.a03_dossier,$closure.lineage.a03_receipt)){
  Assert-A05K203Closure ($lineageSchemas.Contains([string]$binding.path)) "[mir4-a05-k2-03-closure-lineage-path] $($binding.path)"
  $text=Get-Content -Raw -LiteralPath (Resolve-A05K203ClosurePath $binding.path)
  Assert-A05K203Closure ($text|Test-Json -SchemaFile (Resolve-A05K203ClosurePath $lineageSchemas[[string]$binding.path])) "[mir4-a05-k2-03-closure-lineage-schema] $($binding.path)"
  $record=$text|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-A05K203Closure ((Test-MIR4BootstrapRecordHash $record) -and $binding.raw_sha256-eq(Get-A05K203ClosureRaw $binding.path) -and $binding.record_sha256-eq$record.record_sha256) "[mir4-a05-k2-03-closure-lineage] $($binding.path)"
}
Assert-A05K203Closure ($closure.lineage.a03_lock.path-eq'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-current.lock.json' -and $closure.lineage.a03_lock.raw_sha256-eq(Get-A05K203ClosureRaw $closure.lineage.a03_lock.path)) '[mir4-a05-k2-03-closure-lock]'

$locked=$proof.cases.locked_2_0_13
$current=$proof.cases.current_2_0_17_fresh_load_only
Assert-A05K203Closure ($locked.k2so.version-eq'2.0.13' -and $locked.k2so.archive_sha256-eq'A2EEB2E5A6119C4117BD3653979D40D305D17539E184BFA6F4ED53EF12A5F242' -and $locked.xy_enabled -and $locked.fresh_load.passed) '[mir4-a05-k2-03-closure-locked]'
Assert-A05K203Closure ($current.k2so.version-eq'2.0.17' -and $current.k2so.archive_sha256-eq'0D48E22858FB4D1259413B65FFA7E5A0C5B5C2439A4918D58BDACC9411FA9284' -and -not $current.xy_enabled -and $current.fresh_load.passed -and $null-eq$current.reloads) '[mir4-a05-k2-03-closure-current]'
Assert-A05K203Closure ($locked.reloads.passed -and [int]$locked.reloads.required_count-eq2 -and [int]$locked.reloads.actual_count-eq2 -and @($locked.reloads.reloads|Where-Object{$_.passed-and-not$_.timed_out-and$_.save_byte_identical-and$_.reload_log_contract_passed-and$_.marker_count-eq1}).Count-eq2) '[mir4-a05-k2-03-closure-reloads]'
Assert-A05K203Closure ($proof.version_parity.owner_effects -and $proof.version_parity.route_matrix -and (ConvertTo-MIR4BootstrapCanonicalJson -Value $locked.observation.effect_owners)-ceq(ConvertTo-MIR4BootstrapCanonicalJson -Value $current.observation.effect_owners) -and (ConvertTo-MIR4BootstrapCanonicalJson -Value $locked.observation.routes)-ceq(ConvertTo-MIR4BootstrapCanonicalJson -Value $current.observation.routes)) '[mir4-a05-k2-03-closure-parity]'

Assert-A05K203Closure ($locked.observation.owner.native-eq'kr-imersite-productivity' -and $locked.observation.owner.native_effects-eq'7' -and $locked.observation.owner.native_crystal-eq'0.1' -and $locked.observation.owner.mir-eq'recipe-prod-research_material_imersite-1' -and $locked.observation.owner.mir_effects-eq'1' -and $locked.observation.owner.mir_powder-eq'0.02' -and $locked.observation.owner.exact_owners-eq'2') '[mir4-a05-k2-03-closure-owner]'
Assert-A05K203ClosureArray $locked.observation.science.mir @('automation-science-pack','chemical-science-pack','logistic-science-pack','production-science-pack') '[mir4-a05-k2-03-closure-science]'
Assert-A05K203ClosureArray $locked.observation.science.compatible_labs @('biolab','kr-advanced-lab','kr-singularity-lab','lab') '[mir4-a05-k2-03-closure-labs]'
Assert-A05K203Closure ([int]$locked.observation.route_counts.total-eq19 -and [int]$locked.observation.route_counts.external_exact_owner-eq1 -and [int]$locked.observation.route_counts.generated_family_covered-eq1 -and [int]$locked.observation.route_counts.safe_skip-eq17) '[mir4-a05-k2-03-closure-route-counts]'
$expectedRoutes=@(
'kr-crush-kr-imersite-anti-materiel-rifle-magazine|safe_skip|hidden_recipe|',
'kr-crush-kr-imersite-crystal|safe_skip|hidden_recipe|',
'kr-crush-kr-imersite-powder|safe_skip|hidden_recipe|',
'kr-crush-kr-imersite-rifle-magazine|safe_skip|hidden_recipe|',
'kr-crush-kr-imersite-rounds-magazine|safe_skip|hidden_recipe|',
'kr-imersite-anti-materiel-rifle-magazine|safe_skip|recipe_productivity_not_allowed|',
'kr-imersite-anti-materiel-rifle-magazine-recycling|safe_skip|hidden_recipe|',
'kr-imersite-crystal|external_exact_owner|existing_recipe_productivity_effect|kr-imersite-productivity',
'kr-imersite-crystal-recycling|safe_skip|hidden_recipe|',
'kr-imersite-powder|generated_family_covered|fixed_stream_coverage|recipe-prod-research_material_imersite-1',
'kr-imersite-powder-recycling|safe_skip|hidden_recipe|',
'kr-imersite-recycling|safe_skip|hidden_recipe|',
'kr-imersite-rifle-magazine|safe_skip|recipe_productivity_not_allowed|',
'kr-imersite-rifle-magazine-recycling|safe_skip|hidden_recipe|',
'kr-imersite-rounds-magazine|safe_skip|recipe_productivity_not_allowed|',
'kr-imersite-rounds-magazine-recycling|safe_skip|hidden_recipe|',
'kr-kr-imersite-powder-to-matter|safe_skip|recipe_productivity_not_allowed|',
'kr-kr-imersite-to-matter|safe_skip|recipe_productivity_not_allowed|',
'kr-matter-to-kr-imersite-powder|safe_skip|recipe_productivity_not_allowed|'
)
Assert-A05K203ClosureArray @($locked.observation.routes|ForEach-Object{"$($_.name)|$($_.disposition.category)|$($_.disposition.reason)|$($_.disposition.owners)"}) $expectedRoutes '[mir4-a05-k2-03-closure-route-matrix]'

$expectedEssential=[ordered]@{
  runtime_result='build/mir4/a05-k2-materials/k2-03-runtime/result.json|28937|10BFDD3213DE435B8688AB78356305BEE1AB27A36918D34B9579DB41228F7A9C'
  current_lock='build/mir4/a05-k2-materials/current-k2so-resolution/compat-candidates.lock.json|12342|6867FA8CE00CABD0D291AEABE18EEBD986C0F98E5D38D42F60C5BCE9313E7756'
  runtime_test='tests/runtime/Test-MIR4A05K203Imersite.ps1|16683|CAFB45046E9CF5FFB15BDDE6C5FE58D5AE2E36CEF6465F39841BB90920A18294'
  locked_save='build/mir4/a05-k2-materials/k2-03-runtime/locked-2.0.13/saves/locked-2.0.13.zip|832775|EB3FB9126AB9DD09D17F4205C645C2570C8E360337A52DCFCBCD72F0FA2DF86C'
  locked_log='build/mir4/a05-k2-materials/k2-03-runtime/locked-2.0.13/locked-2.0.13.factorio.log|9900836|352A1249395DD93D028EC044834C41AB25B0235DC9BD0B92C653B53916F9624C'
  locked_k2so='build/mir4/a05-k2-materials/k2-03-runtime/locked-2.0.13/mods/Krastorio2-spaced-out_2.0.13.zip|208207|A2EEB2E5A6119C4117BD3653979D40D305D17539E184BFA6F4ED53EF12A5F242'
  reload_01_log='build/mir4/a05-k2-materials/k2-03-runtime/locked-2.0.13/locked-2.0.13.reload-01.factorio.log|9898993|EF1ACB67D8A0FD4FD2B53F33FA3BEBDB98D685C1D79C41DFDE6B1484604F8906'
  reload_02_log='build/mir4/a05-k2-materials/k2-03-runtime/locked-2.0.13/locked-2.0.13.reload-02.factorio.log|9898993|FC5BE5FF8064168411EF96DDDAA576B04DBA884B6413A289071EA853A595D36C'
  current_save='build/mir4/a05-k2-materials/k2-03-runtime/current-2.0.17/saves/current-2.0.17.zip|848907|A916E771FDB1CA22F6485CB49A3870A523E1427B09AE707B80A61FB3A07F9624'
  current_log='build/mir4/a05-k2-materials/k2-03-runtime/current-2.0.17/current-2.0.17.factorio.log|9927021|1C73789B41741BC7EDAB936ED6189D22226F5EE02FCDB4A1DE0357253BCE2493'
  current_k2so='build/mir4/a05-k2-materials/k2-03-runtime/current-2.0.17/mods/Krastorio2-spaced-out_2.0.17.zip|210445|0D48E22858FB4D1259413B65FFA7E5A0C5B5C2439A4918D58BDACC9411FA9284'
}
$actualEssential=[ordered]@{
  runtime_result=$proof.source_evidence.runtime_result
  current_lock=$proof.source_evidence.current_resolution_lock
  runtime_test=$proof.source_evidence.runtime_test
  locked_save=$locked.fresh_load.save
  locked_log=$locked.fresh_load.factorio_log
  locked_k2so=@($locked.mod_closure.external_archives|Where-Object path -match 'Krastorio2-spaced-out')[0]
  reload_01_log=$locked.reloads.reloads[0].factorio_log
  reload_02_log=$locked.reloads.reloads[1].factorio_log
  current_save=$current.fresh_load.save
  current_log=$current.fresh_load.factorio_log
  current_k2so=@($current.mod_closure.external_archives|Where-Object path -match 'Krastorio2-spaced-out')[0]
}
foreach($key in $expectedEssential.Keys){$artifact=$actualEssential[$key];Assert-A05K203Closure ("$($artifact.path)|$($artifact.bytes)|$($artifact.raw_sha256)" -ceq $expectedEssential[$key]) "[mir4-a05-k2-03-closure-essential-artifact] $key"}

foreach($artifact in @($proof.source_evidence.runtime_result,$proof.source_evidence.current_resolution_lock,$proof.source_evidence.runtime_test)+@($proof.source_evidence.fixture)){Assert-A05K203ClosureArtifact $artifact '[mir4-a05-k2-03-closure-source-artifact]'}
foreach($case in @($locked,$current)){foreach($artifact in @($case.fresh_load.save,$case.fresh_load.stdout,$case.fresh_load.stderr,$case.fresh_load.factorio_log,$case.mod_closure.candidate,$case.mod_closure.fixture,$case.mod_closure.mod_list,$case.mod_closure.mod_settings)+@($case.mod_closure.external_archives)){Assert-A05K203ClosureArtifact $artifact '[mir4-a05-k2-03-closure-case-artifact]'}}
foreach($reload in @($locked.reloads.reloads)){foreach($artifact in @($reload.stdout,$reload.stderr,$reload.factorio_log)){Assert-A05K203ClosureArtifact $artifact '[mir4-a05-k2-03-closure-reload-artifact]'}}

Assert-A05K203Closure ($closure.route_admission.material-eq'Imersite' -and $closure.route_admission.stream-eq'research_material_imersite' -and $closure.route_admission.technology-eq'recipe-prod-research_material_imersite-1' -and [double]$closure.route_admission.effect_per_tier-eq0.02 -and [int]$closure.route_admission.eligible_routes-eq2 -and $closure.route_admission.weighted_process_qualification-eq'not-proven') '[mir4-a05-k2-03-closure-admission]'
Assert-A05K203Closure ([int]$closure.progression.finite_tiers-eq3 -and $closure.progression.locked_save_continuity-eq'two-byte-identical-reloads-at-0.42' -and $closure.progression.infinite_continuation-eq'not-proven') '[mir4-a05-k2-03-closure-progression]'
Assert-A05K203Closure ($closure.current_qualification.scope-eq'fresh-load-owner-and-route-parity-only' -and $closure.current_qualification.xy_enhancement-eq'not-included' -and $closure.current_qualification.reload_continuity-eq'not-proven') '[mir4-a05-k2-03-closure-current-boundary]'
Assert-A05K203Closure ($closure.projection_gap.status-eq'unresolved-pre-release' -and $closure.projection_gap.blocks_release -and $closure.projection_gap.package_source.path-eq'src/mod/families/modern/prototypes/mir/streams/generated_stream_manifest.json' -and [int]$closure.projection_gap.package_source.rows-eq98 -and $closure.projection_gap.package_source.raw_sha256-eq'107EBC191467C3AFEAFC513026CB2CA64E4792E248781429F70AE53908FA8208' -and $closure.projection_gap.root_projection.path-eq'prototypes/mir/streams/generated_stream_manifest.json' -and [int]$closure.projection_gap.root_projection.rows-eq76 -and $closure.projection_gap.root_projection.raw_sha256-eq'58CCF482A05D8C3E2E3D8274F0D29CA9E5FBF973C7790F20894B88242937A202' -and $closure.projection_gap.mir_projection_authority.raw_sha256-eq(Get-A05K203ClosureRaw '.mir/streams.yml')) '[mir4-a05-k2-03-closure-projection-gap]'
Assert-A05K203Closure (@($closure.authority_flags.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0 -and $closure.remaining_obligations.Count-ge4 -and $closure.non_claims.Count-ge5) '[mir4-a05-k2-03-closure-boundary]'
$programme=Get-Content -Raw -LiteralPath (Resolve-A05K203ClosurePath 'spec/programmes/mir4-4x-operating-programme-v1.json')|ConvertFrom-Json -Depth 100 -DateKind String
$a05=@($programme.synthesis.tasks|Where-Object id -CEQ 'A05')
Assert-A05K203Closure ($a05.Count-eq1 -and $a05[0].state-ne'complete' -and (@($a05[0].requests)-join'|')-ceq'K2-02|K2-03|K2-04|K2-05|K2-06|K2-07') '[mir4-a05-k2-03-closure-a05-remains-open]'
$tokens=$null;$errors=$null
[Management.Automation.Language.Parser]::ParseFile((Resolve-A05K203ClosurePath 'tools/commands/mir4/Write-MIR4A05K203ImersiteClosure.ps1'),[ref]$tokens,[ref]$errors)|Out-Null
Assert-A05K203Closure ($errors.Count-eq0) '[mir4-a05-k2-03-closure-writer-parser]'
Assert-A05K203Closure ($evolution.kind-eq'MIR4A05K203CommandInventoryEvolutionV1' -and $evolution.status-eq'append-only-successor-passed') '[mir4-a05-k2-03-inventory-evolution-kind]'
$a04ClosureRelative='spec/programmes/evidence/synthesis-2026-09-10/a04-k2-science/MIR4-A04-K2-Science-ClosureV1.json'
$a04Closure=Get-A05K203ClosureRecord $a04ClosureRelative 'spec/schemas/mir4-a04-k2-science-closure-v1.schema.json'
Assert-A05K203Closure ($evolution.predecessor.a04_closure.path-eq$a04ClosureRelative -and $evolution.predecessor.a04_closure.raw_sha256-eq(Get-A05K203ClosureRaw $a04ClosureRelative) -and $evolution.predecessor.a04_closure.record_sha256-eq$a04Closure.record_sha256) '[mir4-a05-k2-03-inventory-evolution-a04]'
$historical=$a04Closure.compatibility_audit_evolution.command_inventory
Assert-A05K203Closure ($evolution.predecessor.inventory.raw_sha256-eq$historical.raw_sha256 -and $evolution.predecessor.inventory.canonical_sha256-eq$historical.canonical_sha256 -and $evolution.predecessor.inventory.digest-eq$historical.digest -and [int]$evolution.predecessor.inventory.canonical_internal_count-eq378) '[mir4-a05-k2-03-inventory-evolution-predecessor]'
$inventoryPath=Resolve-A05K203ClosurePath 'governance/automation/mir4-command-inventory-v1.json'
$inventory=Get-Content -Raw -LiteralPath $inventoryPath|ConvertFrom-Json -Depth 100 -DateKind String
Assert-A05K203Closure ($evolution.current.raw_sha256-eq(Get-MIR4Sha256File -Path $inventoryPath) -and $evolution.current.canonical_sha256-eq(Get-MIR4BootstrapTextSha256 -Path $inventoryPath) -and $evolution.current.digest-eq$inventory.digest -and [int]$evolution.current.command_count-eq85 -and [int]$evolution.current.canonical_internal_count-eq379) '[mir4-a05-k2-03-inventory-evolution-current]'
$added=@($inventory.implementation_files|Where-Object path -CEQ 'tools/commands/mir4/Write-MIR4A05K203ImersiteClosure.ps1')
Assert-A05K203Closure ($added.Count-eq1 -and $evolution.transition.added_implementation_files.Count-eq1 -and (ConvertTo-MIR4BootstrapCanonicalJson -Value $added[0])-ceq(ConvertTo-MIR4BootstrapCanonicalJson -Value $evolution.transition.added_implementation_files[0]) -and $evolution.transition.classification-eq'append-only-one-canonical-internal-writer' -and $evolution.transition.public_command_count_unchanged -and $evolution.transition.non_added_summary_counts_unchanged -and $evolution.transition.transition_gates_remain_closed) '[mir4-a05-k2-03-inventory-evolution-delta]'
$predecessor=[ordered]@{schema=[int]$inventory.schema;kind=[string]$inventory.kind;state=[string]$inventory.state;public_entrypoint=[string]$inventory.public_entrypoint;router=[string]$inventory.router;command_count=[int]$inventory.command_count;commands=@($inventory.commands);implementation_files=@($inventory.implementation_files|Where-Object path -CNE 'tools/commands/mir4/Write-MIR4A05K203ImersiteClosure.ps1');summary=[ordered]@{canonical_public=1;canonical_internal=378;compatibility_wrapper=168;migration_only=48;historical=16;obsolete=0;unknown=0;duplicate_command_keys=0};transition_gate=[ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false};digest=''}
$digestMaterial=[ordered]@{};foreach($property in $predecessor.GetEnumerator()){if([string]$property.Key-cne'digest'){$digestMaterial[$property.Key]=$property.Value}}
$predecessor.digest=Get-MIR4CommandInventoryDigestV1 -Value $digestMaterial
$predecessorText=(($predecessor|ConvertTo-Json -Depth 100)+[string][char]10).Replace(([string][char]13+[char]10),[string][char]10).Replace([string][char]13,[string][char]10)
$predecessorScratch=Join-Path $RepoRoot 'build/a05-k2-03-closure-test/reconstructed-a04-command-inventory.json'
[IO.Directory]::CreateDirectory((Split-Path -Parent $predecessorScratch))|Out-Null
[IO.File]::WriteAllText($predecessorScratch,$predecessorText,[Text.UTF8Encoding]::new($false))
Assert-A05K203Closure ($predecessor.digest-eq$historical.digest -and (Get-MIR4Sha256File -Path $predecessorScratch)-eq$historical.raw_sha256 -and $evolution.transition.reconstructed_predecessor_sha256-eq$historical.raw_sha256) '[mir4-a05-k2-03-inventory-evolution-reconstruction]'
Assert-A05K203Closure (@($evolution.authority_flags.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) '[mir4-a05-k2-03-inventory-evolution-authority]'
Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot -Check|Out-Null
'[ok] MIR4 A05/K2-03 Imersite closure is exact, bounded, and leaves A05 open.'