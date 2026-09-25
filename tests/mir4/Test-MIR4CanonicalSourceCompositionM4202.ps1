# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/mir/application/package/SourceCompositionProof.ps1')
. (Join-Path $repo 'tools/mir/application/package/FactorioOneSourceConvergence.ps1')

function Assert-MIR4ComposableSource([bool]$Condition,[string]$Code){
  if(-not$Condition){throw "[$Code]"}
}
function Read-MIR4ComposableSourceJson([string]$Relative){
  $path=Join-Path $repo $Relative
  Assert-MIR4ComposableSource (Test-Path -LiteralPath $path -PathType Leaf) 'mir4-composable-source-missing'
  Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100 -DateKind String
}

$authorityRelative='governance/repository/composable-source-layout-v1.json'
$proofRelative='assurance/repository/composable-source-layout-v1.json'
$receiptRelative='assurance/repository/composable-source-layout-receipt-v1.json'
$receiptText=Get-Content -Raw -LiteralPath (Join-Path $repo $receiptRelative)
Assert-MIR4ComposableSource ($receiptText|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-composable-source-layout-migration-v1.schema.json')) 'mir4-composable-source-receipt-schema'
$receipt=$receiptText|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4ComposableSource (Test-MIR4BootstrapRecordHash $receipt) 'mir4-composable-source-receipt-self-hash'
$authority=Read-MIR4ComposableSourceJson $authorityRelative
$proofPolicy=Read-MIR4ComposableSourceJson $proofRelative
Assert-MIR4ComposableSource ([string]$authority.kind-ceq'MIR4ComposableSourceLayoutAuthorityV1'-and[string]$authority.migration_id-ceq[string]$receipt.migration_id) 'mir4-composable-source-authority'
Assert-MIR4ComposableSource ([string]$proofPolicy.kind-ceq'MIR4ComposableSourceLayoutProofPolicyV1'-and[string]$proofPolicy.test_id-ceq'static.mir4-composable-source-layout-v1') 'mir4-composable-source-proof-policy'
Assert-MIR4ComposableSource ((Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $authorityRelative))-ceq[string]$receipt.authority.sha256) 'mir4-composable-source-authority-binding'
Assert-MIR4ComposableSource ((Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $proofRelative))-ceq[string]$receipt.proof_policy.sha256) 'mir4-composable-source-proof-binding'
$attributes=Get-Content -Raw -LiteralPath (Join-Path $repo '.gitattributes')
Assert-MIR4ComposableSource ($attributes-match'(?m)^source/\*\* text eol=lf$') 'mir4-composable-source-checkout-bytes-pinned'

$predecessorProof = Write-MIR4ComposableSourcePredecessorProof -RepoRoot $repo -OutputPath 'build/reports/package-source/tests/mir4-composable-source-predecessor-proof-v1.json'
$predecessorProofPath = Join-Path $repo 'build/reports/package-source/tests/mir4-composable-source-predecessor-proof-v1.json'
Assert-MIR4ComposableSource (Test-MIR4BootstrapRecordHash $predecessorProof) 'mir4-composable-source-predecessor-self-hash'
Assert-MIR4ComposableSource ((Get-Content -Raw -LiteralPath $predecessorProofPath) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-composable-source-predecessor-proof-v1.schema.json')) 'mir4-composable-source-predecessor-schema'
Assert-MIR4ComposableSource ([int]$predecessorProof.binding_count-eq447-and[int]$predecessorProof.physical_source_count-eq439) 'mir4-composable-source-predecessor-cardinality'
Assert-MIR4ComposableSource ([bool]$predecessorProof.invariants.binary_safe_git_blob_reads-and[bool]$predecessorProof.invariants.source_output_scope_transform_and_identity_equal-and[bool]$predecessorProof.invariants.transformed_output_bytes_and_hash_equal-and[bool]$predecessorProof.invariants.resolver_round_trip_complete) 'mir4-composable-source-predecessor-invariants'

$manifest=Read-MIR4ComposableSourceJson 'source/package-source.json'
$packageAuthority=Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
$registry=Read-MIR4ComposableSourceJson 'targets/registry.json'
Assert-MIR4ComposableSource (Test-MIR4BootstrapRecordHash $manifest) 'mir4-composable-source-manifest-self-hash'
Assert-MIR4ComposableSource (Test-MIR4BootstrapRecordHash $packageAuthority) 'mir4-composable-source-package-authority-self-hash'
Assert-MIR4ComposableSource (Test-MIR4BootstrapRecordHash $registry) 'mir4-composable-source-registry-self-hash'
$v6Presentation=Read-MIR4ComposableSourceJson 'spec/distribution/mir4-current-package-presentation-v6.json'
Assert-MIR4ComposableSource ([string]$manifest.predecessor_record_sha256-ceq[string]$v6Presentation.source_manifest.record_sha256-and[string]$manifest.predecessor_record_sha256-cne[string]$receipt.predecessor.manifest_record_sha256) 'mir4-composable-source-predecessor-binding'
Assert-MIR4ComposableSource ([string]$receipt.predecessor.package_source_fingerprint_sha256-ceq'BD29DCCC6818E3B2593B2DD182E62F8AA68827EC58E1E27AC1CBA915C582AF57'-and[string]$receipt.current.package_source_fingerprint_sha256-ceq'7B0A39E3C5286624C8B6B272E32D1F6DE21F86FE91187E39AEF42FB80FCFC9ED') 'mir4-composable-source-historical-package-fingerprint'
Assert-MIR4ComposableSource ([string]$receipt.current.package_source_fingerprint_sha256-cne(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)) 'mir4-composable-source-current-semantic-succession'
Assert-MIR4ComposableSource ([string]$receipt.predecessor_proof.implementation-ceq'tools/mir/application/package/SourceCompositionProof.ps1'-and[string]$receipt.predecessor_proof.schema-ceq'spec/schemas/mir4-composable-source-predecessor-proof-v1.schema.json'-and[string]$receipt.predecessor_proof.record_sha256-ceq[string]$predecessorProof.record_sha256) 'mir4-composable-source-predecessor-proof-receipt'
$migratedBindings=@($manifest.bindings|Where-Object{[string]$_.provenance.kind-ceq'migrated-predecessor'})
$introducedBindings=@($manifest.bindings|Where-Object{[string]$_.provenance.kind-ceq'current-introduction'})
$historicalBindings=@($introducedBindings|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-HISTORICAL-PRIVATE-TARGET-ADAPTERS'})
Assert-MIR4ComposableSource (@($manifest.bindings).Count-eq372-and@($manifest.bindings.source_path|Sort-Object -Unique).Count-eq372-and$migratedBindings.Count-eq359-and@($migratedBindings.provenance.predecessor_source_path|Sort-Object -Unique).Count-eq359-and$introducedBindings.Count-eq13-and$historicalBindings.Count-eq12-and@($historicalBindings.source_path|Where-Object{$_-notmatch'^source/(?:adapters|presentation)/historical/'}).Count-eq0) 'mir4-composable-source-cardinality'

# publication.lua executes target-line capability decisions after module load.
# Keep its dependency explicit and prove every target composition closes over the
# imported module; otherwise a source move can materialize successfully while
# failing only when the compiler publishes a plan.
$publicationPath='prototypes/mir/pipeline/compiler_orchestrator/publication.lua'
$targetLinePath='prototypes/mir/platform/factorio/target_line.lua'
$publicationBinding=@($manifest.bindings|Where-Object{[string]$_.output_path-ceq$publicationPath})
Assert-MIR4ComposableSource ($publicationBinding.Count-eq1-and[bool]($publicationBinding[0].target_scope -contains 'f210')-and[bool]($publicationBinding[0].target_scope -contains 'f200')-and[bool]($publicationBinding[0].target_scope -contains 'f110')-and[bool]($publicationBinding[0].target_scope -contains 'f100')) 'mir4-composable-source-publication-target-scope'
$publicationText=Get-Content -Raw -LiteralPath (Join-Path $repo ([string]$publicationBinding[0].source_path))
Assert-MIR4ComposableSource ($publicationText-match'(?m)^local target_line = require\("prototypes\.mir\.platform\.factorio\.target_line"\)$'-and$publicationText-match'target_line\.feature_enabled\(' -and$publicationText-match'target_line\.factorio_version') 'mir4-composable-source-publication-target-line-import'
Assert-MIR4ComposableSource (
  $publicationText-match'\["2\.1"\]\s*=\s*"emit"'-and
  $publicationText-match'\["2\.0"\]\s*=\s*"emit"'-and
  $publicationText-match'\["1\.1"\]\s*=\s*"omit-unqualified"'-and
  $publicationText-match'\["1\.0"\]\s*=\s*"omit-unqualified"'-and
  $publicationText-match'if not research_cost_disposition then\s+error\("Research-cost publication target is not admitted:'-and
  $publicationText-match'if research_cost_disposition == "emit" then'
) 'mir4-composable-source-research-cost-target-disposition'
foreach($target in @('f210','f200','f110','f100')){
  $selection=Get-MIR4TargetMaterializationBindings -State (Get-MIR4TargetMaterializerState -RepoRoot $repo -Target $target)
  $selected=@($selection.bindings.output_path)
  Assert-MIR4ComposableSource ($publicationPath-in$selected-and$targetLinePath-in$selected) "mir4-composable-source-publication-target-line-closure-$target"
}

$declared=@($manifest.bindings.source_path|Sort-Object -Unique -CaseSensitive)
$physical=@(Get-ChildItem -LiteralPath (Join-Path $repo 'source') -Recurse -File|Where-Object{$_.FullName-notin@((Join-Path $repo 'source/package-source.json'),(Join-Path $repo 'source/.mir-root.json'))}|ForEach-Object{[IO.Path]::GetRelativePath($repo,$_.FullName).Replace([IO.Path]::DirectorySeparatorChar,'/')}|Sort-Object -Unique -CaseSensitive)
Assert-MIR4ComposableSource (($declared-join"`n")-ceq($physical-join"`n")) 'mir4-composable-source-physical-set'
Assert-MIR4ComposableSource (-not(Test-Path -LiteralPath (Join-Path $repo 'src'))) 'mir4-composable-source-no-src'
Assert-MIR4ComposableSource (-not(Test-Path -LiteralPath (Join-Path $repo 'source/families'))) 'mir4-composable-source-no-era-families'
Assert-MIR4ComposableSource (@(Get-ChildItem -LiteralPath (Join-Path $repo 'targets') -Recurse -File|Where-Object{$_.FullName-match'[\\/](?:files|generation)[\\/]'}).Count-eq0) 'mir4-composable-source-no-target-payload'

$cases=[ordered]@{
  'src/mod/common/prototypes/mir/core/deepcopy.lua'='source/prototypes/mir/core/deepcopy.lua'
  'src/mod/families/modern/prototypes/mir/core/fingerprint.lua'='source/prototypes/mir/core/fingerprint.lua'
  'targets/f200/files/prototypes/mir/planner/stream_compiler.lua'='source/prototypes/mir/planner/stream_compiler.lua'
}
foreach($case in $cases.GetEnumerator()){
  Assert-MIR4ComposableSource ((Resolve-MIR4CanonicalPackageSourcePath -RepoRoot $repo -RelativePath $case.Key)-ceq$case.Value) 'mir4-composable-source-relocation'
}
foreach($bad in @('src/mod/not-declared.lua','src/mod/families/legacy/prototypes/mir/core/fingerprint.lua','targets/f210/files/prototypes/mir/planner/stream_compiler.lua','../source/data.lua','C:/outside.lua')){
  $rejected=$false
  try{[void](Resolve-MIR4CanonicalPackageSourcePath -RepoRoot $repo -RelativePath $bad)}catch{$rejected=$true}
  Assert-MIR4ComposableSource $rejected 'mir4-composable-source-relocation-negative'
}

$targetKeys=@($receipt.target_parity|ForEach-Object target)
Assert-MIR4ComposableSource (($targetKeys-join'|')-ceq'f210|f200|f110|f100') 'mir4-composable-source-receipt-targets'
Assert-MIR4ComposableSource ([int]$receipt.relocation.deduplicated_binding_count-eq8-and[int]$receipt.compatibility_convergence.divergent_predecessor_same_output_modules-eq75) 'mir4-composable-source-honest-convergence-boundary'
Assert-MIR4ComposableSource (@($receipt.transition_gate.PSObject.Properties|Where-Object{$_.Name-ne'development_merge'-and[bool]$_.Value}).Count-eq0) 'mir4-composable-source-release-firewall'

$convergence=Get-MIR4FactorioOneSourceConvergenceProof -RepoRoot $repo
Assert-MIR4ComposableSource (Test-MIR4BootstrapRecordHash $convergence) 'mir4-composable-source-convergence-self-hash'
Assert-MIR4ComposableSource ([string]$convergence.status-ceq'passed-static-source-convergence-engine-proof-required'-and[bool]$convergence.exact_engine_proof_required-and-not[bool]$convergence.release_transition_authority) 'mir4-composable-source-convergence-boundary'
$proof=Invoke-MIR4CurrentSourceMaterializerProof -RepoRoot $repo -OutputRoot 'build/packages' -ReportPath 'build/reports/package-source/composable-source-layout-current.json'
Assert-MIR4ComposableSource (@($proof.targets).Count-eq4-and@($proof.targets|Where-Object{-not[bool]$_.deterministic_archive_bytes}).Count-eq0) 'mir4-composable-source-current-determinism'
$currentPresentation=Read-MIR4ComposableSourceJson 'spec/distribution/mir4-current-package-presentation-v7.json'
foreach($target in @('f210','f200','f110','f100')){$row=@($proof.targets|Where-Object target -ceq $target);$expected=@($currentPresentation.target_content_identities|Where-Object target -ceq $target);Assert-MIR4ComposableSource ($row.Count-eq1-and$expected.Count-eq1-and[string]$row[0].content_sha256-ceq[string]$expected[0].content_sha256-and[int]$row[0].entry_count-eq[int]$expected[0].entry_count) 'mir4-composable-source-reviewed-semantic-identity'}
[pscustomobject][ordered]@{status='passed';test_id='static.mir4-composable-source-layout-v1';bindings=@($manifest.bindings).Count;physical_sources=$physical.Count;deduplicated_bindings=(@($manifest.bindings).Count-$physical.Count);targets=@($proof.targets).Count;factorio_1_historical_pairs=[int]$convergence.historical_characterization.factorio_one_pair_count;factorio_1_exact_engine_proof_required=$true;release_authority=$false}|ConvertTo-Json -Depth 10
