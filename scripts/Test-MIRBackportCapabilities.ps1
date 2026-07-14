param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$profilePath = Join-Path $repo ".mir\target-reconstruction.json"
if (-not (Test-Path -LiteralPath $profilePath)) { throw "Missing target reconstruction profile: .mir/target-reconstruction.json" }
$profile = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
$info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
if ($profile.release -ne $info.version -or $profile.factorio.line -ne $info.factorio_version) {
  throw "Target profile does not match info.json."
}

$classes = @("native", "adapted", "generated_fallback", "finite_reconstruction", "omitted_by_capability")
foreach ($class in $classes) {
  if (-not $profile.classification.PSObject.Properties.Name.Contains($class)) {
    throw "Target profile is missing classification: $class"
  }
}

$targetText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\platform\factorio\target_line.lua")
if ($targetText -notmatch 'recipe_productivity\s*=\s*false') {
  throw "Legacy target must explicitly disable unsupported recipe productivity effects."
}
foreach ($snippet in @(
  'if not target_line.feature_enabled("recipe_productivity") then',
  '"recipe_productivity_unsupported"'
)) {
  $compilerText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\planner\stream_compiler.lua")
  if (-not $compilerText.Contains($snippet)) { throw "Missing recipe-productivity target guard: $snippet" }
}

$settingsBuilder = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\stage_builder.lua")
if (-not $settingsBuilder.Contains('target_line.stream_supported(key, stream)')) {
  throw "Settings stage does not omit target-unsupported stream settings."
}

$manifest = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\streams\generated_stream_manifest.json") | ConvertFrom-Json
$rows = @($manifest.streams.PSObject.Properties)
if ($rows.Count -eq 0) { throw "Stream manifest is empty." }
$recipeRows = @($rows | Where-Object { $_.Value.capability -eq "recipe-productivity" })
$directRows = @($rows | Where-Object { $_.Value.capability -eq "native-modifier" })
if ($recipeRows.Count -eq 0 -or $directRows.Count -eq 0 -or ($recipeRows.Count + $directRows.Count) -ne $rows.Count) {
  throw "Every manifest stream must classify as target-omitted recipe productivity or a native modifier candidate."
}
foreach ($row in $rows) {
  if (-not $row.Value.stable -or [string]::IsNullOrWhiteSpace($row.Value.generated_technology) -or
      [string]::IsNullOrWhiteSpace($row.Value.stream_key) -or [string]::IsNullOrWhiteSpace($row.Value.migration_policy)) {
    throw "Incomplete stable stream row: $($row.Name)"
  }
}

$settingsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\stage_builder.lua")
foreach ($key in @("research_low_density_structure", "research_plastic", "research_processing_unit", "research_rocket_fuel")) {
  if (-not $settingsText.Contains($key)) { throw "Legacy source inventory lost expected stream key: $key" }
}

$policyText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\compatibility.yml")
if ($policyText -match 'data:extend|data\.raw\s*\[[^\]]+\]\s*=') {
  throw "Compatibility policy manifest appears to mutate prototypes."
}
$emissionText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\platform\factorio\data_raw.lua")
if ($emissionText -notmatch 'factorio_data:extend') { throw "Technology emission boundary is missing." }

$migrationFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo "migrations") -File -ErrorAction SilentlyContinue)
$result = [ordered]@{
  schema = 1
  target = $profile.factorio.line
  release = $profile.release
  manifest_rows = $rows.Count
  native_modifier_candidates = $directRows.Count
  omitted_recipe_productivity_rows = $recipeRows.Count
  migration_files = $migrationFiles.Count
  extended_vanilla_setting_policy = "omitted-by-capability"
  status = "passed"
}
$result | ConvertTo-Json | Write-Host
Write-Host "[ok] legacy target capability classification passed."
