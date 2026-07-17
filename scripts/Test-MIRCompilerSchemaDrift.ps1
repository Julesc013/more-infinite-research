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
$scenarioManifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures\compat-matrix\expected-scenarios.json") | ConvertFrom-Json
if ($scenarioManifest.schema -ne 3) { throw "Runtime scenario manifest schema drifted from 3." }

Assert-MIRText "prototypes\mir\domain\effects\metadata.lua" "M.schema = 1"
Assert-MIRText "prototypes\mir\domain\streams\descriptor.lua" "schema = 1"
Assert-MIRText "prototypes\mir\families\rules.lua" "schema = 2"
Assert-MIRText "prototypes\mir\families\registry.lua" "FamilyRule registry schema must be 2"
Assert-MIRText "prototypes\mir\providers\contract.lua" "M.schema = 1"
Assert-MIRText "prototypes\mir\providers\contract.lua" "Duplicate CompilerProvider id"
Assert-MIRText "prototypes\mir\compatibility\packs\schema.lua" "CompatibilityPack schema must be 2"
Assert-MIRText "prototypes\mir\domain\technology\technology_design.lua" "TechnologyDesign schema 1 record is required"
Assert-MIRText "prototypes\mir\planner\generation_plan.lua" "GenerationPlan row schema must be 3"
Assert-MIRText "prototypes\mir\planner\compilation_plan.lua" "schema = 2"
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
  "| TechnologyDesign | 1 |",
  "| GenerationPlan | 3 |",
  "| CompilationPlan | 2 |",
  "| CompilerEvidence | 1 |",
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
  @{Path="docs\reference\schemas\technology-design.md"; Needle='`TechnologyDesign` schema 1'},
  @{Path="docs\reference\schemas\compiler-evidence.md"; Needle='`CompilerEvidence` schema 1'},
  @{Path="docs\reference\schemas\recipe-fact-v2.md"; Needle="schema-2"},
  @{Path="docs\reference\schemas\scenario-manifest.md"; Needle="schema 3"}
)) {
  Assert-MIRText $docCheck.Path $docCheck.Needle
}

Write-Host "[ok] MIR compiler code, manifests, authority table, and schema reference versions agree."
