param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"

function Read-MIRText { param([string]$Path) Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $Path) }
function Assert-MIRText { param([string]$Path, [string]$Needle)
  $text = Read-MIRText $Path
  if (-not $text.Contains($Needle)) { throw "$Path is missing schema authority marker: $Needle" }
}

$streamManifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\streams\generated_stream_manifest.json") | ConvertFrom-Json
if ($streamManifest.schema -ne 1) { throw "Generated stream manifest schema drifted from 1." }
$streamAuthorityText = Read-MIRText ".mir\streams.yml"
foreach ($manifestProperty in @($streamManifest.streams.PSObject.Properties)) {
  $rowPattern = "(?ms)^    " + [regex]::Escape([string]$manifestProperty.Name) + ":\r?\n(?<body>.*?)(?=^    [A-Za-z0-9_.-]+:\r?\n|\z)"
  $authorityRow = [regex]::Match($streamAuthorityText, $rowPattern)
  if (-not $authorityRow.Success) {
    throw ".mir/streams.yml is missing generated stream authority row: $($manifestProperty.Name)"
  }
  $policyMatch = [regex]::Match(
    $authorityRow.Groups["body"].Value,
    "(?m)^      policy:\s*(?<value>[^\r\n#]+?)\s*$"
  )
  if (-not $policyMatch.Success) {
    throw ".mir/streams.yml stream row is missing policy metadata: $($manifestProperty.Name)"
  }
  $authorityPolicy = $policyMatch.Groups["value"].Value.Trim()
  if ([string]$manifestProperty.Value.policy -ne $authorityPolicy) {
    throw "Generated stream manifest policy differs from .mir/streams.yml for $($manifestProperty.Name): '$($manifestProperty.Value.policy)' != '$authorityPolicy'"
  }
}
$scenarioManifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures\compat-matrix\expected-scenarios.json") | ConvertFrom-Json
if ($scenarioManifest.schema -ne 3) { throw "Runtime scenario manifest schema drifted from 3." }
$contractCoverage = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\compiler-contract-coverage.yml") | ConvertFrom-Json
$compilerSchemaAuthority = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\compiler-schema-authority.json") | ConvertFrom-Json
if ([int]$compilerSchemaAuthority.schema -ne 1 -or
    [string]$compilerSchemaAuthority.unknown_schema_policy -ne "fail-closed" -or
    [string]$compilerSchemaAuthority.downgrade_policy -ne "explicit-projection-only") {
  throw "Compiler schema compatibility authority is invalid."
}
foreach ($entry in @{
  CompilationSnapshot=2; PolicySnapshot=1; CompilerInput=2; CompilerResult=3;
  RuntimeEnvironmentIdentity=2; QualificationEnvironmentIdentity=1;
  TransformationOperation=2; TransformationPlan=2; MutationJournal=2
}.GetEnumerator()) {
  if ([int]$compilerSchemaAuthority.records.($entry.Key).current -ne [int]$entry.Value) {
    throw "Compiler schema authority drifted for $($entry.Key)."
  }
}
$technologyDesignText = Read-MIRText "prototypes\mir\domain\technology\technology_design.lua"
$technologyDesignDoc = Read-MIRText "docs\reference\schemas\technology-design.md"
$publicArtifactsText = Read-MIRText "prototypes\mir\report\public_compiler_artifacts.lua"
$modDataText = Read-MIRText "prototypes\mir\emit\mod_data.lua"
if ([int]$contractCoverage.technology_design_schema -ne 2) { throw "TechnologyDesign governed schema must be 2." }
if ([int]$contractCoverage.public_compiler_artifact_schema -ne 1) { throw "Public compiler artifact schema must be 1." }
foreach ($kind in @($contractCoverage.public_compiler_artifact_kinds)) {
  if (-not $publicArtifactsText.Contains('kind = "' + [string]$kind + '"')) {
    throw "Public compiler artifact projector is missing governed kind: $kind"
  }
}
foreach ($dataType in @($contractCoverage.public_compiler_mod_data_types)) {
  if (-not $modDataText.Contains('data_type = "' + [string]$dataType + '"')) {
    throw "Mod-data adapter is missing governed public data type: $dataType"
  }
}
foreach ($value in @($contractCoverage.technology_design_dimensions) +
  @($contractCoverage.technology_design_subject_categories) +
  @($contractCoverage.technology_design_fingerprints) +
  @($contractCoverage.technology_design_lock_states) +
  @($contractCoverage.technology_design_lock_policies) +
  @($contractCoverage.technology_design_materialization_kinds) +
  @($contractCoverage.technology_design_leaf_provenance)) {
  if (-not $technologyDesignText.Contains('"' + [string]$value + '"')) {
    throw "TechnologyDesign Lua authority is missing governed semantic value: $value"
  }
}
foreach ($axis in @($contractCoverage.technology_design_maturity_axes)) {
  if (-not $technologyDesignText.Contains([string]$axis + " =")) {
    throw "TechnologyDesign Lua authority is missing governed maturity axis: $axis"
  }
}
foreach ($fingerprintName in @($contractCoverage.technology_design_fingerprints)) {
  if (-not $technologyDesignDoc.Contains('`' + [string]$fingerprintName + '`')) {
    throw "TechnologyDesign reference contract is missing fingerprint: $fingerprintName"
  }
}
foreach ($automaticId in @(
  "mir-auto-prod-manufacturing-assembling-machine-1",
  "mir-auto-prod-manufacturing-lab-1"
)) {
  $row = $streamManifest.streams.PSObject.Properties[$automaticId].Value
  if ([string]$row.identity_state -ne "released") {
    throw "Released automatic stream identity lacks manifest authority: $automaticId"
  }
}

Assert-MIRText "prototypes\mir\domain\effects\metadata.lua" "M.schema = 1"
Assert-MIRText "prototypes\mir\domain\streams\descriptor.lua" "schema = 1"
Assert-MIRText "prototypes\mir\families\rules.lua" "schema = 2"
Assert-MIRText "prototypes\mir\families\registry.lua" "FamilyRule registry schema must be 2"
Assert-MIRText "prototypes\mir\providers\contract.lua" "M.schema = 1"
Assert-MIRText "prototypes\mir\providers\contract.lua" "Duplicate CompilerProvider id"
Assert-MIRText "prototypes\mir\compatibility\packs\schema.lua" "CompatibilityPack schema must be 2"
Assert-MIRText "prototypes\mir\domain\technology\technology_design.lua" "TechnologyDesign schema 2 record is required"
Assert-MIRText "prototypes\mir\planner\generation_plan.lua" "GenerationPlan row schema must be 3"
Assert-MIRText "prototypes\mir\planner\compilation_plan.lua" "schema = 2"
Assert-MIRText "prototypes\mir\domain\compiler\compiler_input.lua" "CompilerInput schema 2 record is required"
Assert-MIRText "prototypes\mir\domain\compiler\compiler_result.lua" "CompilerResult schema 3 planned or final record is required"
Assert-MIRText "prototypes\mir\domain\environment_identity.lua" "RuntimeEnvironmentIdentity schema 2"
Assert-MIRText "prototypes\mir\domain\compiler\compiler_input.lua" "function M.compatibility_projection"
Assert-MIRText "prototypes\mir\domain\compiler\compiler_result.lua" "function M.compatibility_projection"
Assert-MIRText "prototypes\mir\domain\environment_identity.lua" "function M.compatibility_projection"
Assert-MIRText "prototypes\mir\emit\mod_data.lua" "more-infinite-research.compiler-evidence"
Assert-MIRText "prototypes\mir\settings\effect_contracts.lua" 'require("prototypes.mir.domain.effects.metadata")'

$authorityTable = Read-MIRText "docs\reference\compiler-authority-table.md"
foreach ($row in @(
  "| Effect metadata | 1 |",
  "| Stable generated streams | 1 |",
  "| Canonical StreamSpec descriptor | 1 |",
  "| FamilyRule | 2 |",
  "| CompilerProvider | 1 |",
  "| CompatibilityPack | 2 |",
  "| TechnologyDesign | 2 |",
  "| GenerationPlan | 3 |",
  "| CompilationPlan | 2 |",
  "| CompilationSnapshot | 2 |",
  "| PolicySnapshot | 1 |",
  "| CompilerInput | 2 |",
  "| CompilerResult | 3 |",
  "| RuntimeEnvironmentIdentity | 2 |",
  "| QualificationEnvironmentIdentity | 1 |",
  "| TransformationOperation | 2 |",
  "| TransformationPlan | 2 |",
  "| MutationJournal | 2 |",
  "| CompilerEvidence | 2 |",
  "| Public compiler artifact projections | 1 |",
  "| RecipeFactV2 | 2 |",
  "| Runtime scenario declaration | 3 |",
  "| Campaign scenario declaration | 2 |"
)) {
  if (-not $authorityTable.Contains($row)) { throw "Compiler authority table is missing or version-drifted: $row" }
}

foreach ($docCheck in @(
  @{Path="docs\reference\schemas\family-rule.md"; Needle='schema-2 `FamilyRule`'},
  @{Path="docs\reference\schemas\compiler-provider.md"; Needle='`CompilerProvider` schema 1'},
  @{Path="docs\reference\schemas\compatibility-pack.md"; Needle='schema-2 `CompatibilityPack`'},
  @{Path="docs\reference\schemas\generation-plan.md"; Needle="schema 3"},
  @{Path="docs\reference\schemas\technology-design.md"; Needle='`TechnologyDesign` schema 2'},
  @{Path="docs\reference\schemas\compiler-evidence.md"; Needle='`CompilerEvidence` schema 2'},
  @{Path="docs\reference\schemas\recipe-fact-v2.md"; Needle="schema-2"},
  @{Path="docs\reference\schemas\scenario-manifest.md"; Needle="schema 3"}
  @{Path="docs\reference\schemas\compiler-boundary.md"; Needle='`CompilerResult` | 3'}
)) {
  Assert-MIRText $docCheck.Path $docCheck.Needle
}

Write-Host "[ok] MIR compiler code, stream policies, manifests, authority table, and schema reference versions agree."
