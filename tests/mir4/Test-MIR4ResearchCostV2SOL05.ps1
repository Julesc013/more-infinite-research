# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../.."))
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/ResearchCostV2.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')

$receiptPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Research-Cost-V2-SOL05V1.json'
$receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100
$shaPattern = '^[A-F0-9]{64}$'
if ([int]$receipt.schema -ne 1 -or [string]$receipt.kind -ne 'MIR4ResearchCostV2SOL05V1' -or
    [string]$receipt.status -ne 'PASS_WITH_DEFERRED_STABLE_ADMISSION' -or
    [string]$receipt.work_package -ne 'SOL-05' -or $receipt.package_visible -or
    $receipt.publication_authorized) {
  throw 'MIR 4 SOL-05 receipt header is invalid or grants package/publication authority.'
}
if ([string]$receipt.scope.starting_source.commit -ne '65796a468a5247c8b31143a82db5fa3c94926d46' -or
    [string]$receipt.scope.starting_source.reconciled_predecessor_commit -ne 'e190836c8b8f781c4e41dafc08df367ca986b33a' -or
    [string]$receipt.scope.feedback_id -ne 'PF-2026-08-COST-001' -or
    [string]$receipt.scope.classification -notmatch '^B2-conditional') {
  throw 'SOL-05 receipt is not bound to the reconciled source and conditional feedback classification.'
}
$nonInterference = $receipt.candidate_non_interference
if (-not $nonInterference.byte_identical -or
    [string]$nonInterference.before_archive_sha256 -notmatch $shaPattern -or
    [string]$nonInterference.before_archive_sha256 -ne [string]$nonInterference.after_archive_sha256 -or
    [string]$nonInterference.content_sha256 -notmatch $shaPattern -or
    [string]$nonInterference.disposition -ne 'local-development-evidence-only-not-a-release-candidate') {
  throw 'SOL-05 does not prove byte-identical player-package non-interference.'
}
$plan = $receipt.verification_plan
if ([string]$plan.file_sha256 -notmatch $shaPattern -or
    [string]$plan.plan_material_sha256 -notmatch $shaPattern -or
    [string]$plan.required_test_set_sha256 -notmatch $shaPattern -or
    [int]$plan.counts.total -ne 156 -or [int]$plan.counts.run -ne 154 -or
    [int]$plan.counts.invalid -ne 2 -or
    'static.mir4-bootstrap-materialization' -notin @($plan.invalid_future_work) -or
    'static.mir4-offline-custody' -notin @($plan.invalid_future_work)) {
  throw 'SOL-05 verification plan or bounded SOL-09 invalid set is incorrect.'
}

$modelSchemaPath = Join-Path $RepoRoot 'spec/schemas/experimental/mir4-research-cost-model-v2.schema.json'
$profileSchemaPath = Join-Path $RepoRoot 'spec/schemas/experimental/mir4-research-cost-profile-rules-v1.schema.json'
$modelSchema = Get-Content -Raw -LiteralPath $modelSchemaPath | ConvertFrom-Json -Depth 100
$profileSchema = Get-Content -Raw -LiteralPath $profileSchemaPath | ConvertFrom-Json -Depth 100
if ([string]$modelSchema.properties.formula_abi.const -ne 'mir-research-cost-v2-preview' -or
    [string]$modelSchema.properties.maturity.const -ne 'experimental-package-excluded' -or
    [string]$modelSchema.properties.rounding_law.const -ne 'round-half-up-positive-final-v1') {
  throw 'ResearchCostModel V2 schema does not retain its exact experimental ABI and rounding law.'
}
if (@($modelSchema.properties.base_source.enum).Count -ne 5 -or
    'direct-prerequisite-sum' -notin @($modelSchema.properties.base_source.enum) -or
    'transitive-prerequisite-closure' -notin @($modelSchema.properties.base_source.enum)) {
  throw 'ResearchCostModel V2 schema does not retain all five base-source strategies.'
}
if (@($profileSchema.'$defs'.layer.properties.kind.enum).Count -ne 7 -or
    @($profileSchema.'$defs'.rule.properties.selector.properties.kind.enum).Count -ne 8) {
  throw 'Research-cost profile schema does not retain seven layers and eight sparse selectors.'
}

$snapshot = [pscustomobject]@{nodes=@(
  [pscustomobject]@{id='target'; prerequisites=@('generated','b','a'); realized_cost='1'; generated_continuation=$false},
  [pscustomobject]@{id='a'; prerequisites=@('shared'); realized_cost='100'; generated_continuation=$false},
  [pscustomobject]@{id='b'; prerequisites=@('shared'); realized_cost='200'; generated_continuation=$false},
  [pscustomobject]@{id='shared'; prerequisites=@(); realized_cost='50'; generated_continuation=$false},
  [pscustomobject]@{id='generated'; prerequisites=@(); realized_cost='999'; generated_continuation=$true}
)}
$direct = Resolve-MIR4ResearchCostAnchorV2 -BaseSource direct-prerequisite-sum `
  -TargetId target -Snapshot $snapshot
$transitive = Resolve-MIR4ResearchCostAnchorV2 -BaseSource transitive-prerequisite-closure `
  -TargetId target -Snapshot $snapshot
if ([string]$direct.anchor.numerator -ne '300' -or [string]$direct.anchor.denominator -ne '1' -or
    (@($direct.contributors.id) -join ',') -ne 'a,b') {
  throw 'Direct prerequisite sum is not deduplicated, ordered, or generated-continuation safe.'
}
if ([string]$transitive.anchor.numerator -ne '350' -or
    (@($transitive.contributors.id) -join ',') -ne 'a,b,shared') {
  throw 'Transitive prerequisite closure does not deduplicate the shared prerequisite.'
}

$reorderedSnapshot = [pscustomobject]@{nodes=@($snapshot.nodes | Sort-Object id -Descending | ForEach-Object {
  [pscustomobject]@{
    id=$_.id
    prerequisites=@($_.prerequisites | Sort-Object -Descending)
    realized_cost=$_.realized_cost
    generated_continuation=$_.generated_continuation
  }
})}
$reordered = Resolve-MIR4ResearchCostAnchorV2 -BaseSource transitive-prerequisite-closure `
  -TargetId target -Snapshot $reorderedSnapshot
if (($transitive | ConvertTo-Json -Depth 20 -Compress) -ne ($reordered | ConvertTo-Json -Depth 20 -Compress)) {
  throw 'Prerequisite-derived anchor changes under node or edge reordering.'
}

$model = New-MIR4ResearchCostModelV2 -AnchorResolution $direct -AnchorLevel 1 `
  -BaseMultiplier '2/1' -LinearRatio '1/2' -GrowthFactor '1/1' `
  -Provenance @{vector='PF-2026-08-COST-001'}
$costs = @(1..3 | ForEach-Object { Get-MIR4ResearchCostV2 -Model $model -Level $_ })
if (($costs -join ',') -ne '600,750,900') {
  throw "Canonical public cost vector is incorrect: $($costs -join ',')"
}
$roundingAnchor = Resolve-MIR4ResearchCostAnchorV2 -BaseSource absolute -TargetId rounding -AbsoluteBase '3/2'
$roundingModel = New-MIR4ResearchCostModelV2 -AnchorResolution $roundingAnchor -AnchorLevel 1 `
  -BaseMultiplier '1/1' -LinearRatio '0/1' -GrowthFactor '1/1'
if ((Get-MIR4ResearchCostV2 -Model $roundingModel -Level 1) -ne '2') {
  throw 'Positive half-up rounding is not exact.'
}

$cycleSnapshot = [pscustomobject]@{nodes=@(
  [pscustomobject]@{id='target'; prerequisites=@('a'); realized_cost='1'; generated_continuation=$false},
  [pscustomobject]@{id='a'; prerequisites=@('b'); realized_cost='10'; generated_continuation=$false},
  [pscustomobject]@{id='b'; prerequisites=@('a'); realized_cost='20'; generated_continuation=$false}
)}
$cycleMessage = ''
try {
  Resolve-MIR4ResearchCostAnchorV2 -BaseSource transitive-prerequisite-closure `
    -TargetId target -Snapshot $cycleSnapshot | Out-Null
} catch {
  $cycleMessage = $_.Exception.Message
}
if ($cycleMessage -ne 'research_cost_v2_graph_cycle:a>b>a') {
  throw "Cycle did not fail closed with its deterministic witness: $cycleMessage"
}

$subject = [pscustomobject]@{
  target='f210'; owner='mir'; source_mod='base'; effect_channel='recipe-productivity'
  family='science-pack'; stream='research_science_pack_productivity'; technology='recipe-prod-research_science_pack_productivity-1'
}
$layers = @(
  [pscustomobject]@{id='defaults';kind='safe-default';rules=@(
    [pscustomobject]@{id='all';selector=[pscustomobject]@{kind='all';value=''};values=[pscustomobject]@{base_multiplier='1/1';linear_ratio='0/1'}}
  )},
  [pscustomobject]@{id='users';kind='user';rules=@(
    [pscustomobject]@{id='family';selector=[pscustomobject]@{kind='family';value='science-pack'};values=[pscustomobject]@{base_multiplier='3/1'}}
  )},
  [pscustomobject]@{id='exact';kind='explicit';rules=@(
    [pscustomobject]@{id='technology';selector=[pscustomobject]@{kind='technology';value=$subject.technology};values=[pscustomobject]@{base_multiplier='4/1'}}
  )},
  [pscustomobject]@{id='safety';kind='hard-safety';rules=@(
    [pscustomobject]@{id='clamp';selector=[pscustomobject]@{kind='all';value=''};values=[pscustomobject]@{growth_factor='1/1';base_multiplier='2/1'}}
  )}
)
$profile = Resolve-MIR4ResearchCostProfileV1 -Subject $subject -Layers $layers
$profileReordered = Resolve-MIR4ResearchCostProfileV1 -Subject $subject -Layers @($layers | Sort-Object id -Descending)
if ([string]$profile.effective.base_multiplier -ne '2/1' -or
    [string]$profile.field_sources.base_multiplier.layer_kind -ne 'hard-safety' -or
    ($profile | ConvertTo-Json -Depth 30 -Compress) -ne ($profileReordered | ConvertTo-Json -Depth 30 -Compress)) {
  throw 'Sparse profile layering is not deterministic or hard-safety final.'
}

$currentModel = New-MIR4ResearchCostModelV2 -AnchorResolution $direct -AnchorLevel 1 `
  -BaseMultiplier '4/1' -LinearRatio '1/1' -GrowthFactor '1/1'
$transition = Convert-MIR4ResearchProgressV2 -Fraction '1/2' -PreviousModel $model `
  -CurrentModel $currentModel -Level 1
if ([string]$transition.previous_cost -ne '600' -or [string]$transition.current_cost -ne '1200' -or
    [string]$transition.converted_fraction.numerator -ne '1' -or
    [string]$transition.converted_fraction.denominator -ne '4' -or
    [string]$transition.application -notmatch 'once-only.*not-admitted') {
  throw 'V2 analytical research-progress transition is not exact and once-only bounded.'
}

$authority = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir/compiler-schema-authority.json') | ConvertFrom-Json
if ([int]$authority.records.ResearchCostModel.current -ne 1 -or
    @($authority.records.ResearchCostModel.writable) -ne 1) {
  throw 'Stable ResearchCostModel authority was changed by the V2 preview.'
}
$dispositions = Get-MIR4ResearchCostV2TargetDispositions
if ([string]$dispositions.f210 -notmatch '^preview-only' -or
    [string]$dispositions.f200 -notmatch 'target-local-runtime-proof-required' -or
    [string]$dispositions.f018_to_f013 -ne 'private-target-omitted') {
  throw 'ResearchCostModel V2 target dispositions overstate admission.'
}

$previewPaths = @(
  'spec/schemas/experimental/mir4-research-cost-model-v2.schema.json',
  'spec/schemas/experimental/mir4-research-cost-profile-rules-v1.schema.json',
  'tools/lib/mir4/ResearchCostV2.ps1',
  'docs/reference/research-cost-v2-preview.md'
)
$shipped = @(Get-MIRPackageSourceFiles -RepoRoot $RepoRoot)
foreach ($previewPath in $previewPaths) {
  if ($previewPath -in $shipped) { throw "ResearchCostModel V2 preview entered player package: $previewPath" }
}

if ([int]$receipt.stable_authority.schema -ne 1 -or
    [string]$receipt.stable_authority.formula_abi -ne 'mir-research-cost-v1' -or
    @($receipt.stable_authority.writable_versions).Count -ne 1 -or
    [int]$receipt.stable_authority.writable_versions[0] -ne 1 -or
    @($receipt.stable_authority.regression_tests | Where-Object result -ne 'passed').Count -ne 0) {
  throw 'SOL-05 receipt does not retain the stable V1 authority and its regression results.'
}
$preview = $receipt.preview_contract
if ([int]$preview.schema -ne 2 -or [string]$preview.formula_abi -ne 'mir-research-cost-v2-preview' -or
    [string]$preview.maturity -ne 'experimental-package-excluded' -or
    @($preview.base_sources).Count -ne 5 -or @($preview.profile_layers).Count -ne 7 -or
    @($preview.selectors).Count -ne 8) {
  throw 'SOL-05 receipt does not freeze the complete V2 preview contract.'
}
foreach ($artifact in @($preview.artifacts)) {
  if ([string]$artifact.file_sha256 -notmatch $shaPattern) {
    throw "SOL-05 preview artifact lacks a SHA-256 binding: $($artifact.path)"
  }
  $artifactPath = Join-Path $RepoRoot ([string]$artifact.path)
  if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
    throw "SOL-05 preview artifact differs from its receipt: $($artifact.path)"
  }
  $artifactMatches = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifactPath).Hash -ceq [string]$artifact.file_sha256
  if (-not $artifactMatches -and [string]$artifact.path -like 'docs/*.md') {
    $artifactMatches = Test-MIR4T14HistoricalDocumentationSha256 -RepoRoot $RepoRoot `
      -RelativePath ([string]$artifact.path) -ExpectedSha256 ([string]$artifact.file_sha256)
  }
  if (-not $artifactMatches) { throw "SOL-05 preview artifact differs from its receipt: $($artifact.path)" }
}
$vectors = $receipt.proof_vectors
if (($vectors.public_vector.levels_1_to_3 -join ',') -ne '600,750,900' -or
    [string]$vectors.shared_prerequisite_deduplication.transitive_anchor -ne '350/1' -or
    ($vectors.cycle_block.witness -join '>') -ne 'a>b>a' -or
    -not $vectors.profile_layering.hard_safety_final -or
    [string]$vectors.analytical_transition.converted_fraction -ne '1/4') {
  throw 'SOL-05 receipt does not bind the required arithmetic, graph, profile, and transition vectors.'
}
$admission = $receipt.stable_admission_decision
if ([string]$admission.decision -ne 'DEFER_TO_EXPERIMENTAL_PREVIEW' -or
    @($admission.blocking_obligations).Count -ne 8 -or $admission.v1_regression -or
    $admission.player_package_changed -or [string]$admission.public_claim -ne 'none') {
  throw 'SOL-05 stable-admission decision is incomplete or overclaims the V2 preview.'
}
if (-not $receipt.exit_gate.schema_frozen -or
    -not $receipt.exit_gate.exact_arithmetic_and_rounding_proven -or
    -not $receipt.exit_gate.graph_deduplication_and_cycle_witness_proven -or
    -not $receipt.exit_gate.sparse_profile_layering_proven -or
    -not $receipt.exit_gate.package_non_interference_proven -or
    $receipt.exit_gate.stable_v2_admitted -or -not $receipt.exit_gate.stable_v1_retained -or
    $receipt.exit_gate.publication_authorized -or
    [string]$receipt.exit_gate.next_work_package -ne 'SOL-06') {
  throw 'SOL-05 exit gate is incomplete or grants stable/public authority.'
}

Write-Host 'MIR 4 SOL-05 ResearchCostModel V2 exact preview and stable-defer boundary passed.'
