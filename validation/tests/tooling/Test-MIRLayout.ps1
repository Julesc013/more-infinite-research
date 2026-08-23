$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
. (Join-Path $repo "tools/lib/workspace/RepoPaths.ps1")

$paths = Read-MIRRepoPathCatalog -RepoRoot $repo
$aliases = Read-MIRRepoAliasCatalog -RepoRoot $repo -PathCatalog $paths
if ($paths.paths.PSObject.Properties["releases.deltas"].Value -ne ".mir/releases/deltas") {
  throw "Release delta path ID changed."
}
foreach ($expectedPath in @{
  "workspace.build.results" = "build/results"
  "workspace.build.results.evidence" = "build/results/evidence"
  "workspace.build.results.verification-context" = "build/results/verification-context"
  "workspace.build" = "build"
  "workspace.build.candidate" = "build/candidate"
  "workspace.build.tmp" = "build/tmp"
  "distributions.playtest" = "dist/playtest"
}.GetEnumerator()) {
  if ($paths.paths.PSObject.Properties[$expectedPath.Key].Value -cne $expectedPath.Value) {
    throw "Generated-data path ID drifted: $($expectedPath.Key)"
  }
}
foreach ($retiredPathId in @("workspace.root", "workspace.output", "workspace.playtest", "workspace.tmp")) {
  if ($paths.paths.PSObject.Properties[$retiredPathId]) {
    throw "Retired workspace path ID remains canonical: $retiredPathId"
  }
}
if (@($aliases.aliases | Where-Object from -eq "approved-delta/").Count -ne 0) {
  throw "Retired root approved-delta alias remains registered."
}
if (@($aliases.aliases | Where-Object {
  $_.introduced -eq "3.2.5" -and $_.sunset -ne "3.3.0"
}).Count -ne 0) {
  throw "Every 3.2.5 migration alias must declare the common 3.3.0 sunset."
}
foreach ($canonicalRoot in @("build/")) {
  if (@($aliases.aliases | Where-Object from -eq $canonicalRoot).Count -ne 0) {
    throw "Canonical generated-data root remains registered as an alias: $canonicalRoot"
  }
}
$legacyOutAlias = @($aliases.aliases | Where-Object from -eq "out/")
if ($legacyOutAlias.Count -ne 1 -or $legacyOutAlias[0].to -ne "workspace.build.results" -or $legacyOutAlias[0].mode -ne "local-read-only") {
  throw "Retired out/ path does not resolve read-only to build/results/."
}
$legacySchemaAlias = "verification/" + "schema/"
if (@($aliases.aliases | Where-Object {
  $_.from -eq $legacySchemaAlias -and $_.to -eq "spec.schemas" -and $_.mode -eq "read-only"
}).Count -ne 1) {
  throw "Historical verification schema alias is missing or writable."
}
if (@($aliases.aliases | Where-Object {
  $_.from -eq ("scripts/" + "MIRCli/") -and $_.to -eq "tools.lib.cli" -and $_.mode -eq "read-only"
}).Count -ne 1) {
  throw "Historical CLI-support alias is missing or writable."
}
if (@($aliases.aliases | Where-Object {
  $_.from -eq ("scripts/" + "mir.ps1") -and $_.to -eq "tools.cli" -and $_.mode -eq "read-only"
}).Count -ne 1) {
  throw "Historical CLI-facade alias is missing or writable."
}
foreach ($packageAlias in @(
  @{from=("scripts/" + "Build-MIRPackage.ps1");to="tools.commands.package.build"},
  @{from=("scripts/" + "Measure-MIRPackageComposition.ps1");to="tools.commands.package.composition"}
)) {
  if (@($aliases.aliases | Where-Object {
    $_.from -eq $packageAlias.from -and $_.to -eq $packageAlias.to -and $_.mode -eq "read-only"
  }).Count -ne 1) { throw "Historical package-command alias is missing or writable: $($packageAlias.from)" }
}
foreach ($workspaceAlias in @(
  @{from=("scripts/" + "Get-MIRLegacyInventory.ps1");to="tools.commands.workspace.inventory"},
  @{from=("scripts/" + "Remove-MIRStaleArtifacts.ps1");to="tools.commands.workspace.cleanup"}
)) {
  if (@($aliases.aliases | Where-Object {
    $_.from -eq $workspaceAlias.from -and $_.to -eq $workspaceAlias.to -and $_.mode -eq "read-only"
  }).Count -ne 1) { throw "Historical workspace-command alias is missing or writable: $($workspaceAlias.from)" }
}
foreach ($docsAlias in @(
  @{from=("scripts/" + "Format-MIRMarkdown.ps1");to="tools.commands.docs.format"},
  @{from=("scripts/" + "Update-MIRGeneratedAuthorityDocs.ps1");to="tools.commands.docs.authority"},
  @{from=("scripts/" + "Update-MIRPipelineDocumentation.ps1");to="tools.commands.docs.pipeline"},
  @{from=("scripts/" + "Update-MIRREADMEStreamDefaults.ps1");to="tools.commands.docs.defaults"}
)) {
  if (@($aliases.aliases | Where-Object {
    $_.from -eq $docsAlias.from -and $_.to -eq $docsAlias.to -and $_.mode -eq "read-only"
  }).Count -ne 1) { throw "Historical documentation-command alias is missing or writable: $($docsAlias.from)" }
}
foreach ($plannerAlias in @(
  @{from=("scripts/" + "Compare-MIRPlannerReports.ps1");to="tools.commands.planner.report-diff"},
  @{from=("scripts/" + "Compare-MIRPlannerSnapshots.ps1");to="tools.commands.planner.snapshot-diff"},
  @{from=("scripts/" + "Export-MIRPlannerSnapshot.ps1");to="tools.commands.planner.snapshot-export"},
  @{from=("scripts/" + "Minimize-MIRPlannerSnapshot.ps1");to="tools.commands.planner.snapshot-minimize"},
  @{from=("scripts/" + "New-MIRCompatibilityPack.ps1");to="tools.commands.compatibility.pack"}
)) {
  if (@($aliases.aliases | Where-Object {
    $_.from -eq $plannerAlias.from -and $_.to -eq $plannerAlias.to -and $_.mode -eq "read-only"
  }).Count -ne 1) { throw "Historical planner/compatibility-command alias is missing or writable: $($plannerAlias.from)" }
}
foreach ($technologyAlias in @(
  @{from=("scripts/" + "Compare-MIRTechnologyDesigns.ps1");to="tools.commands.technology.design-diff"},
  @{from=("scripts/" + "Export-MIRCompilerPreview.ps1");to="tools.commands.technology.preview-export"},
  @{from=("scripts/" + "Export-MIRTechnologyCatalog.ps1");to="tools.commands.technology.catalog-export"},
  @{from=("scripts/" + "New-MIRTechnologyLifecycleRecord.ps1");to="tools.commands.technology.lifecycle-record"},
  @{from=("scripts/" + "New-MIRTechnologyQualityAssessment.ps1");to="tools.commands.technology.quality-assessment"},
  @{from=("scripts/" + "New-MIRTechnologyReviewDossier.ps1");to="tools.commands.technology.review-dossier"},
  @{from=("scripts/" + "Update-MIRTechnologyGovernance.ps1");to="tools.commands.technology.governance"},
  @{from=("scripts/" + "Invoke-MIRRuleSynthesis.ps1");to="tools.commands.technology.rule-synthesis"}
)) {
  if (@($aliases.aliases | Where-Object {
    $_.from -eq $technologyAlias.from -and $_.to -eq $technologyAlias.to -and $_.mode -eq "read-only"
  }).Count -ne 1) { throw "Historical technology-command alias is missing or writable: $($technologyAlias.from)" }
}
foreach ($controlAlias in @(
  @{from=("scripts/" + "Invoke-MIRControlPlane.ps1");to="tools.commands.control.facade"},
  @{from=("scripts/" + "Invoke-MIRControlPlaneWork.ps1");to="tools.commands.control.work"},
  @{from=("scripts/" + "New-MIRVerificationContext.ps1");to="tools.commands.control.context"},
  @{from=("scripts/" + "Update-MIRExecutionRegistry.ps1");to="tools.commands.control.registry"},
  @{from=("scripts/" + "Update-MIRObservationReplay.ps1");to="tools.commands.control.replay"},
  @{from=("scripts/" + "Update-MIRShadowAnalysis.ps1");to="tools.commands.control.shadow-analysis"},
  @{from=("scripts/" + "Update-MIRShadowBaselines.ps1");to="tools.commands.control.shadow-baselines"}
)) {
  if (@($aliases.aliases | Where-Object {
    $_.from -eq $controlAlias.from -and $_.to -eq $controlAlias.to -and $_.mode -eq "read-only"
  }).Count -ne 1) { throw "Historical control-command alias is missing or writable: $($controlAlias.from)" }
}
foreach ($authorityAlias in @(
  @{from=("scripts/" + "Sync-MIRTargetProfiles.ps1");to="tools.commands.targets.sync"},
  @{from=("scripts/" + "Update-MIRCompilerAuthorities.ps1");to="tools.commands.compiler.authorities"},
  @{from=("scripts/" + "Update-MIRLocales.ps1");to="tools.commands.localization.update"}
)) {
  if (@($aliases.aliases | Where-Object {
    $_.from -eq $authorityAlias.from -and $_.to -eq $authorityAlias.to -and $_.mode -eq "read-only"
  }).Count -ne 1) { throw "Historical authority-command alias is missing or writable: $($authorityAlias.from)" }
}
foreach ($compatibilityAlias in @(
  @{from=("scripts/" + "Convert-MIRCompatAuditResults.ps1");to="tools.commands.compatibility.results"},
  @{from=("scripts/" + "Invoke-MIRCompatAudit.ps1");to="tools.commands.compatibility.audit"},
  @{from=("scripts/" + "New-MIRCompatProfileStub.ps1");to="tools.commands.compatibility.profile-stub"},
  @{from=("scripts/" + "New-MIRFactorioLineTestAdapter.ps1");to="tools.commands.compatibility.line-adapter"},
  @{from=("scripts/" + "New-MIRModInteractionGraph.ps1");to="tools.commands.compatibility.interaction-graph"}
)) {
  if (@($aliases.aliases | Where-Object {
    $_.from -eq $compatibilityAlias.from -and $_.to -eq $compatibilityAlias.to -and $_.mode -eq "read-only"
  }).Count -ne 1) { throw "Historical compatibility-command alias is missing or writable: $($compatibilityAlias.from)" }
}
foreach ($museumAlias in @(
  @{from=("scripts/" + "Build-MIRMuseumTarget.ps1");to="tools.commands.museum.build"},
  @{from=("scripts/" + "New-MIRMuseumQualification.ps1");to="tools.commands.museum.qualification"},
  @{from=("scripts/" + "New-MIRMuseumSeal.ps1");to="tools.commands.museum.seal"}
)) {
  if (@($aliases.aliases | Where-Object {
    $_.from -eq $museumAlias.from -and $_.to -eq $museumAlias.to -and $_.mode -eq "read-only"
  }).Count -ne 1) { throw "Historical museum-command alias is missing or writable: $($museumAlias.from)" }
}

$canonical = Resolve-MIRRepoPath -RepoRoot $repo -Id "releases.deltas"
if ($canonical.alias -or $canonical.relative_path -ne ".mir/releases/deltas") {
  throw "Canonical release delta resolution failed."
}
$canonicalDelta = Resolve-MIRRepoPath -RepoRoot $repo -Path ".mir/releases/deltas/3.2.1-to-3.2.2.json"
if ($canonicalDelta.alias -or $canonicalDelta.relative_path -ne ".mir/releases/deltas/3.2.1-to-3.2.2.json") {
  throw "Canonical release delta path resolution failed."
}
$legacyRelease = Resolve-MIRRepoPath -RepoRoot $repo -Path ".mir/releases/3.2.5.json"
if (-not $legacyRelease.alias -or $legacyRelease.mode -ne "read-only" -or
    $legacyRelease.sunset -ne "3.3.0" -or
    $legacyRelease.relative_path -ne ".mir/releases/records/3.2.5.json") {
  throw "Exact historical release-record resolution failed."
}
$legacyCompatibilityRoot = "fixtures/" + "compat-matrix"
$legacyScenarioPath = "$legacyCompatibilityRoot/expected-scenarios.json"
$legacyScenario = Resolve-MIRRepoPath -RepoRoot $repo -Path $legacyScenarioPath
if (-not $legacyScenario.alias -or $legacyScenario.mode -ne "read-only" -or
    $legacyScenario.id -ne "validation.scenarios.runtime" -or
    $legacyScenario.relative_path -ne "validation/scenarios/runtime.json") {
  throw "Exact-file scenario alias resolution failed."
}
$legacyBaselineRoot = ".mir/control-plane/" + "baselines"
$legacyBaseline = Resolve-MIRRepoPath -RepoRoot $repo -Path "$legacyBaselineRoot/3.2.2-v5-replay.json"
if (-not $legacyBaseline.alias -or $legacyBaseline.relative_path -ne "validation/baselines/control/3.2.2-v5-replay.json") {
  throw "Reviewed baseline alias resolution failed."
}

foreach ($bad in @("../outside", "C:/absolute", 'docs\bad', "$legacyScenarioPath/child")) {
  $rejected = $false
  try { $null = Resolve-MIRRepoPath -RepoRoot $repo -Path $bad }
  catch { $rejected = $true }
  if (-not $rejected) { throw "Unsafe durable path was accepted: $bad" }
}

$manifest = New-MIRLayoutManifest -RepoRoot $repo
if ($manifest.summary.unclassified -ne 0 -or $manifest.summary.case_collisions -ne 0 -or $manifest.summary.links -ne 0) {
  throw "Layout manifest contains unsafe or unclassified paths: $($manifest.summary | ConvertTo-Json -Compress)"
}
if ($manifest.summary.legacy -eq 0) { throw "Migration baseline unexpectedly contains no legacy paths." }

$migrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Remove-MIRDeprecatedWorkRoot.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($migrationPreview.mode -ne "preview" -or @($migrationPreview.present).Count -ne 0 -or
    (@($migrationPreview.canonical_roots) -join ",") -cne "build,dist") {
  throw "The deprecated .work root remains: $($migrationPreview | ConvertTo-Json -Compress)"
}
$controlRecordMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRControlPlaneRecords.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($controlRecordMigrationPreview.mode -ne "preview" -or $controlRecordMigrationPreview.changed -ne 0 -or
    $controlRecordMigrationPreview.migration -ne "mir-control-plane-paths-v1") {
  throw "Control-plane record migration is incomplete or not idempotent: $($controlRecordMigrationPreview | ConvertTo-Json -Compress)"
}
$schemaMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRSchemaRoot.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($schemaMigrationPreview.mode -ne "preview" -or $schemaMigrationPreview.changed -ne 0) {
  throw "Schema-root migration is not idempotent: $($schemaMigrationPreview | ConvertTo-Json -Compress)"
}
$testMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRTestRoot.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($testMigrationPreview.mode -ne "preview" -or $testMigrationPreview.changed -ne 0 -or $testMigrationPreview.tests -ne 65) {
  throw "Test-root migration is incomplete or not idempotent: $($testMigrationPreview | ConvertTo-Json -Compress)"
}
$definitionMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRValidationDefinitions.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($definitionMigrationPreview.mode -ne "preview" -or $definitionMigrationPreview.changed -ne 0 -or
    $definitionMigrationPreview.definitions -ne 11) {
  throw "Validation-definition migration is incomplete or not idempotent: $($definitionMigrationPreview | ConvertTo-Json -Compress)"
}
$definitionMigrationScratch = [IO.Path]::GetFullPath([IO.Path]::Combine(
  [IO.Path]::GetTempPath(),
  "mir-validation-definition-migration-$([Guid]::NewGuid().ToString('N'))"
))
$resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
if (-not $definitionMigrationScratch.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Validation-definition migration scratch escaped the temporary directory."
}
try {
  foreach ($canonicalDefinition in @(
    "spec/compatibility/claims.json",
    "spec/compatibility/support-lanes.json",
    "validation/assertions/expected-failures.json",
    "validation/adapters/portal-exclusions.json",
    "validation/scenarios/runtime.json",
    "validation/scenarios/manual.json",
    "validation/scenarios/local-2.1.json",
    "validation/scenarios/local-2.0.json",
    "validation/baselines/control/2.5.0-p9-v4.json",
    "validation/baselines/control/3.2.2-v4.json",
    "validation/baselines/control/3.2.2-v5-replay.json"
  )) {
    $canonicalPath = Join-Path $definitionMigrationScratch $canonicalDefinition
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $canonicalPath) -Force
    "{}" | Set-Content -LiteralPath $canonicalPath -Encoding utf8
  }
  $escapedReferencePath = Join-Path $definitionMigrationScratch "fixtures/run-profiles/escaped-reference.json"
  $null = New-Item -ItemType Directory -Path (Split-Path -Parent $escapedReferencePath) -Force
  [ordered]@{manual_scenarios_path="fixtures\compat-matrix\local-library-scenarios.json"} |
    ConvertTo-Json | Set-Content -LiteralPath $escapedReferencePath -Encoding utf8

  $escapedPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRValidationDefinitions.ps1") -RepoRoot $definitionMigrationScratch | ConvertFrom-Json
  if ($escapedPreview.mode -ne "preview" -or $escapedPreview.changed -ne 1 -or
      $escapedPreview.reference_files -ne 1 -or
      @($escapedPreview.rewritten) -notcontains "fixtures/run-profiles/escaped-reference.json") {
    throw "Validation-definition migration did not detect a JSON-escaped legacy path: $($escapedPreview | ConvertTo-Json -Compress)"
  }
  $escapedApply = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRValidationDefinitions.ps1") -RepoRoot $definitionMigrationScratch -Apply | ConvertFrom-Json
  $escapedProfile = Get-Content -Raw -LiteralPath $escapedReferencePath | ConvertFrom-Json
  if ($escapedApply.changed -ne 1 -or
      ([string]$escapedProfile.manual_scenarios_path).Replace("\", "/") -cne "validation/scenarios/local-2.1.json") {
    throw "Validation-definition migration did not rewrite a JSON-escaped legacy path canonically."
  }
  $escapedIdempotence = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRValidationDefinitions.ps1") -RepoRoot $definitionMigrationScratch | ConvertFrom-Json
  if ($escapedIdempotence.changed -ne 0) {
    throw "Validation-definition migration is not idempotent after rewriting a JSON-escaped legacy path."
  }
} finally {
  if (Test-Path -LiteralPath $definitionMigrationScratch) {
    Remove-Item -LiteralPath $definitionMigrationScratch -Recurse -Force
  }
}
$toolLibraryMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRToolLibraries.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($toolLibraryMigrationPreview.mode -ne "preview" -or $toolLibraryMigrationPreview.changed -ne 0 -or
    $toolLibraryMigrationPreview.libraries -ne 7) {
  throw "Tool-library migration is incomplete or not idempotent: $($toolLibraryMigrationPreview | ConvertTo-Json -Compress)"
}
$cliFacadeMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRCliFacade.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($cliFacadeMigrationPreview.mode -ne "preview" -or $cliFacadeMigrationPreview.changed -ne 0 -or
    $cliFacadeMigrationPreview.canonical -ne "tools/mir.ps1" -or $cliFacadeMigrationPreview.legacy -ne "scripts/mir.ps1") {
  throw "CLI-facade migration is incomplete or not idempotent: $($cliFacadeMigrationPreview | ConvertTo-Json -Compress)"
}
$packageCommandMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRPackageCommands.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($packageCommandMigrationPreview.mode -ne "preview" -or $packageCommandMigrationPreview.changed -ne 0 -or
    $packageCommandMigrationPreview.commands -ne 2) {
  throw "Package-command migration is incomplete or not idempotent: $($packageCommandMigrationPreview | ConvertTo-Json -Compress)"
}
$workspaceCommandMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRWorkspaceCommands.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($workspaceCommandMigrationPreview.mode -ne "preview" -or $workspaceCommandMigrationPreview.changed -ne 0 -or
    $workspaceCommandMigrationPreview.commands -ne 2) {
  throw "Workspace-command migration is incomplete or not idempotent: $($workspaceCommandMigrationPreview | ConvertTo-Json -Compress)"
}
$docsCommandMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRDocsCommands.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($docsCommandMigrationPreview.mode -ne "preview" -or $docsCommandMigrationPreview.changed -ne 0 -or
    $docsCommandMigrationPreview.commands -ne 4) {
  throw "Documentation-command migration is incomplete or not idempotent: $($docsCommandMigrationPreview | ConvertTo-Json -Compress)"
}
$plannerCommandMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRPlannerCommands.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($plannerCommandMigrationPreview.mode -ne "preview" -or $plannerCommandMigrationPreview.changed -ne 0 -or
    $plannerCommandMigrationPreview.commands -ne 5) {
  throw "Planner-command migration is incomplete or not idempotent: $($plannerCommandMigrationPreview | ConvertTo-Json -Compress)"
}
$technologyCommandMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRTechnologyCommands.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($technologyCommandMigrationPreview.mode -ne "preview" -or $technologyCommandMigrationPreview.changed -ne 0 -or
    $technologyCommandMigrationPreview.commands -ne 8) {
  throw "Technology-command migration is incomplete or not idempotent: $($technologyCommandMigrationPreview | ConvertTo-Json -Compress)"
}
$controlCommandMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRControlCommands.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($controlCommandMigrationPreview.mode -ne "preview" -or $controlCommandMigrationPreview.changed -ne 0 -or
    $controlCommandMigrationPreview.commands -ne 7) {
  throw "Control-command migration is incomplete or not idempotent: $($controlCommandMigrationPreview | ConvertTo-Json -Compress)"
}
$authorityCommandMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRAuthorityCommands.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($authorityCommandMigrationPreview.mode -ne "preview" -or $authorityCommandMigrationPreview.changed -ne 0 -or
    $authorityCommandMigrationPreview.commands -ne 3) {
  throw "Authority-command migration is incomplete or not idempotent: $($authorityCommandMigrationPreview | ConvertTo-Json -Compress)"
}
$compatibilityCommandMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRCompatibilityCommands.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($compatibilityCommandMigrationPreview.mode -ne "preview" -or $compatibilityCommandMigrationPreview.changed -ne 0 -or
    $compatibilityCommandMigrationPreview.commands -ne 5) {
  throw "Compatibility-command migration is incomplete or not idempotent: $($compatibilityCommandMigrationPreview | ConvertTo-Json -Compress)"
}
$museumCommandMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRMuseumCommands.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($museumCommandMigrationPreview.mode -ne "preview" -or $museumCommandMigrationPreview.changed -ne 0 -or
    $museumCommandMigrationPreview.commands -ne 3) {
  throw "Museum-command migration is incomplete or not idempotent: $($museumCommandMigrationPreview | ConvertTo-Json -Compress)"
}
$legacyPackageCommands = @(
  (Join-Path $repo "scripts/Build-MIRPackage.ps1"),
  (Join-Path $repo "scripts/Measure-MIRPackageComposition.ps1")
)
foreach ($wrapperPath in $legacyPackageCommands) {
  $wrapperText = Get-Content -Raw -LiteralPath $wrapperPath
  if ($wrapperText -notmatch "MIR-L5-LEGACY-COMMAND-WRAPPER" -or $wrapperText.Split([char]10).Count -gt 30) {
    throw "Legacy package command is not a thin parameter-compatible wrapper: $wrapperPath"
  }
}
$legacyWorkspaceCommands = @(
  (Join-Path $repo "scripts/Get-MIRLegacyInventory.ps1"),
  (Join-Path $repo "scripts/Remove-MIRStaleArtifacts.ps1")
)
foreach ($wrapperPath in $legacyWorkspaceCommands) {
  $wrapperText = Get-Content -Raw -LiteralPath $wrapperPath
  if ($wrapperText -notmatch "MIR-L5-LEGACY-COMMAND-WRAPPER" -or $wrapperText.Split([char]10).Count -gt 35) {
    throw "Legacy workspace command is not a thin parameter-compatible wrapper: $wrapperPath"
  }
}
$legacyDocsCommands = @(
  (Join-Path $repo "scripts/Format-MIRMarkdown.ps1"),
  (Join-Path $repo "scripts/Update-MIRGeneratedAuthorityDocs.ps1"),
  (Join-Path $repo "scripts/Update-MIRPipelineDocumentation.ps1"),
  (Join-Path $repo "scripts/Update-MIRREADMEStreamDefaults.ps1")
)
foreach ($wrapperPath in $legacyDocsCommands) {
  $wrapperText = Get-Content -Raw -LiteralPath $wrapperPath
  if ($wrapperText -notmatch "MIR-L5-LEGACY-COMMAND-WRAPPER" -or $wrapperText.Split([char]10).Count -gt 30) {
    throw "Legacy documentation command is not a thin parameter-compatible wrapper: $wrapperPath"
  }
}
$legacyPlannerCommands = @(
  (Join-Path $repo "scripts/Compare-MIRPlannerReports.ps1"),
  (Join-Path $repo "scripts/Compare-MIRPlannerSnapshots.ps1"),
  (Join-Path $repo "scripts/Export-MIRPlannerSnapshot.ps1"),
  (Join-Path $repo "scripts/Minimize-MIRPlannerSnapshot.ps1"),
  (Join-Path $repo "scripts/New-MIRCompatibilityPack.ps1")
)
foreach ($wrapperPath in $legacyPlannerCommands) {
  $wrapperText = Get-Content -Raw -LiteralPath $wrapperPath
  if ($wrapperText -notmatch "MIR-L5-LEGACY-COMMAND-WRAPPER" -or $wrapperText.Split([char]10).Count -gt 30) {
    throw "Legacy planner/compatibility command is not a thin parameter-compatible wrapper: $wrapperPath"
  }
}
$legacyTechnologyCommands = @(
  (Join-Path $repo "scripts/Compare-MIRTechnologyDesigns.ps1"),
  (Join-Path $repo "scripts/Export-MIRCompilerPreview.ps1"),
  (Join-Path $repo "scripts/Export-MIRTechnologyCatalog.ps1"),
  (Join-Path $repo "scripts/New-MIRTechnologyLifecycleRecord.ps1"),
  (Join-Path $repo "scripts/New-MIRTechnologyQualityAssessment.ps1"),
  (Join-Path $repo "scripts/New-MIRTechnologyReviewDossier.ps1"),
  (Join-Path $repo "scripts/Update-MIRTechnologyGovernance.ps1"),
  (Join-Path $repo "scripts/Invoke-MIRRuleSynthesis.ps1")
)
foreach ($wrapperPath in $legacyTechnologyCommands) {
  $wrapperText = Get-Content -Raw -LiteralPath $wrapperPath
  if ($wrapperText -notmatch "MIR-L5-LEGACY-COMMAND-WRAPPER" -or $wrapperText.Split([char]10).Count -gt 20) {
    throw "Legacy technology command is not a thin parameter-compatible wrapper: $wrapperPath"
  }
}
$legacyControlCommands = @(
  (Join-Path $repo "scripts/Invoke-MIRControlPlane.ps1"),
  (Join-Path $repo "scripts/Invoke-MIRControlPlaneWork.ps1"),
  (Join-Path $repo "scripts/New-MIRVerificationContext.ps1"),
  (Join-Path $repo "scripts/Update-MIRExecutionRegistry.ps1"),
  (Join-Path $repo "scripts/Update-MIRObservationReplay.ps1"),
  (Join-Path $repo "scripts/Update-MIRShadowAnalysis.ps1"),
  (Join-Path $repo "scripts/Update-MIRShadowBaselines.ps1")
)
foreach ($wrapperPath in $legacyControlCommands) {
  $wrapperText = Get-Content -Raw -LiteralPath $wrapperPath
  if ($wrapperText -notmatch "MIR-L5-LEGACY-COMMAND-WRAPPER" -or $wrapperText.Split([char]10).Count -gt 40) {
    throw "Legacy control command is not a thin parameter-compatible wrapper: $wrapperPath"
  }
}
$legacyAuthorityCommands = @(
  (Join-Path $repo "scripts/Sync-MIRTargetProfiles.ps1"),
  (Join-Path $repo "scripts/Update-MIRCompilerAuthorities.ps1"),
  (Join-Path $repo "scripts/Update-MIRLocales.ps1")
)
foreach ($wrapperPath in $legacyAuthorityCommands) {
  $wrapperText = Get-Content -Raw -LiteralPath $wrapperPath
  if ($wrapperText -notmatch "MIR-L5-LEGACY-COMMAND-WRAPPER" -or $wrapperText.Split([char]10).Count -gt 20) {
    throw "Legacy authority command is not a thin parameter-compatible wrapper: $wrapperPath"
  }
}
$legacyCompatibilityCommands = @(
  (Join-Path $repo "scripts/Convert-MIRCompatAuditResults.ps1"),
  (Join-Path $repo "scripts/Invoke-MIRCompatAudit.ps1"),
  (Join-Path $repo "scripts/New-MIRCompatProfileStub.ps1"),
  (Join-Path $repo "scripts/New-MIRFactorioLineTestAdapter.ps1"),
  (Join-Path $repo "scripts/New-MIRModInteractionGraph.ps1")
)
foreach ($wrapperPath in $legacyCompatibilityCommands) {
  $wrapperText = Get-Content -Raw -LiteralPath $wrapperPath
  if ($wrapperText -notmatch "MIR-L5-LEGACY-COMMAND-WRAPPER" -or $wrapperText.Split([char]10).Count -gt 60) {
    throw "Legacy compatibility command is not a thin parameter-compatible wrapper: $wrapperPath"
  }
}
$legacyMuseumCommands = @(
  (Join-Path $repo "scripts/Build-MIRMuseumTarget.ps1"),
  (Join-Path $repo "scripts/New-MIRMuseumQualification.ps1"),
  (Join-Path $repo "scripts/New-MIRMuseumSeal.ps1")
)
foreach ($wrapperPath in $legacyMuseumCommands) {
  $wrapperText = Get-Content -Raw -LiteralPath $wrapperPath
  if ($wrapperText -notmatch "MIR-L5-LEGACY-COMMAND-WRAPPER" -or $wrapperText.Split([char]10).Count -gt 25) {
    throw "Legacy museum command is not a thin parameter-compatible wrapper: $wrapperPath"
  }
}
$legacyLibraryNames = @(
  ("MIR" + "Assurance"),
  ("MIR" + "Cli"),
  ("MIR" + "CompatAudit"),
  ("MIR" + "ControlPlane"),
  "localization",
  "Museum",
  "validation"
)
$legacyLibraryWrappers = @($legacyLibraryNames | ForEach-Object {
  Get-ChildItem -LiteralPath (Join-Path $repo "scripts/$_") -File
})
$canonicalLibraries = @(Get-ChildItem -LiteralPath (Join-Path $repo "tools/lib") -Recurse -File |
  Where-Object { $_.Extension -in @(".ps1", ".psm1") -and $_.FullName -notlike "*tools\lib\workspace\*" })
if ($legacyLibraryWrappers.Count -ne 42 -or $canonicalLibraries.Count -lt $legacyLibraryWrappers.Count) {
  throw "Canonical tool-library/wrapper inventory drifted: canonical=$($canonicalLibraries.Count), wrappers=$($legacyLibraryWrappers.Count)."
}
foreach ($wrapper in $legacyLibraryWrappers) {
  $text = Get-Content -Raw -LiteralPath $wrapper.FullName
  if ($text -notmatch "MIR-L5-LEGACY-LIBRARY-WRAPPER" -or $text.Split([char]10).Count -gt 4) {
    throw "Legacy library entrypoint is not a thin dot-source wrapper: $($wrapper.FullName)"
  }
}

function Invoke-MIRInlineProbe {
  param([Parameter(Mandatory)][string]$Command)
  $output = (& pwsh -NoProfile -Command $Command 2>&1 | Out-String).Replace("`r`n", "`n").Trim()
  return [pscustomobject]@{exit_code=$LASTEXITCODE;output=$output}
}

$legacyControlPath = Join-Path $repo ("scripts/" + ("MIR" + "ControlPlane") + "/Core.ps1")
$canonicalControlPath = Join-Path $repo "tools/lib/control/Core.ps1"
$legacyControlProbe = Invoke-MIRInlineProbe -Command ". '$($legacyControlPath.Replace("'", "''"))'; Get-MIRCPRepoRoot"
$canonicalControlProbe = Invoke-MIRInlineProbe -Command ". '$($canonicalControlPath.Replace("'", "''"))'; Get-MIRCPRepoRoot"
if ($legacyControlProbe.exit_code -ne 0 -or $legacyControlProbe.output -cne $canonicalControlProbe.output) {
  throw "Legacy/canonical dot-source library parity failed."
}
$legacyCliSupportPath = Join-Path $repo ("scripts/" + "MIRCli/PathResolver.ps1")
$canonicalCliSupportPath = Join-Path $repo "tools/lib/cli/PathResolver.ps1"
$legacyCliSupportProbe = Invoke-MIRInlineProbe -Command ". '$($legacyCliSupportPath.Replace("'", "''"))'; Get-MIRRepoRoot -StartPath '$($repo.Replace("'", "''"))'"
$canonicalCliSupportProbe = Invoke-MIRInlineProbe -Command ". '$($canonicalCliSupportPath.Replace("'", "''"))'; Get-MIRRepoRoot -StartPath '$($repo.Replace("'", "''"))'"
if ($legacyCliSupportProbe.exit_code -ne 0 -or $legacyCliSupportProbe.output -cne $canonicalCliSupportProbe.output) {
  throw "Legacy/canonical CLI-support library parity failed."
}

$legacyMuseumPath = Join-Path $repo ("scripts/" + "Museum/MuseumCompiler.psm1")
$canonicalMuseumPath = Join-Path $repo "tools/lib/museum/MuseumCompiler.psm1"
$legacyMuseumProbe = Invoke-MIRInlineProbe -Command "Import-Module '$($legacyMuseumPath.Replace("'", "''"))' -Force; Get-MIRTextSha256 -Text 'layout-parity'"
$canonicalMuseumProbe = Invoke-MIRInlineProbe -Command "Import-Module '$($canonicalMuseumPath.Replace("'", "''"))' -Force; Get-MIRTextSha256 -Text 'layout-parity'"
if ($legacyMuseumProbe.exit_code -ne 0 -or $legacyMuseumProbe.output -cne $canonicalMuseumProbe.output) {
  throw "Legacy/canonical module import parity failed."
}
foreach ($legacyDefinitionRoot in @($legacyCompatibilityRoot, $legacyBaselineRoot)) {
  $legacyFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo $legacyDefinitionRoot) -File -ErrorAction SilentlyContinue)
  if ($legacyFiles.Count -ne 0) { throw "Legacy definition files remain under $legacyDefinitionRoot." }
}
$legacyTestWrappers = @(Get-ChildItem -LiteralPath (Join-Path $repo "scripts") -Filter "Test-MIR*.ps1" -File)
$canonicalMovedTests = @(Get-ChildItem -LiteralPath (Join-Path $repo "validation/tests") -Filter "Test-MIR*.ps1" -Recurse -File |
  Where-Object Name -ne "Test-MIRLayout.ps1")
if ($legacyTestWrappers.Count -ne 65 -or $canonicalMovedTests.Count -lt 69) {
  throw "Canonical test/wrapper inventory drifted: canonical=$($canonicalMovedTests.Count), wrappers=$($legacyTestWrappers.Count)."
}
foreach ($wrapper in $legacyTestWrappers) {
  $text = Get-Content -Raw -LiteralPath $wrapper.FullName
  if ($text -notmatch "MIR-L4-LEGACY-TEST-WRAPPER" -or $text.Split([char]10).Count -gt 30) {
    throw "Legacy test entrypoint is not a thin forwarding wrapper: $($wrapper.Name)"
  }
}
$legacySchemaGlob = ("verification/" + "schema/**")
$legacySchemaFiles = @(& git -C $repo ls-files $legacySchemaGlob)
if ($LASTEXITCODE -ne 0 -or $legacySchemaFiles.Count -ne 0) {
  throw "Legacy physical verification schema files remain tracked."
}

$deprecatedOutputPattern = '(?i)(?:^|[^A-Za-z0-9_])\.work(?:[\\/]|["''])'
$deprecatedReferenceExclusions = @(
  (Join-Path $repo "tools/maintenance/Remove-MIRDeprecatedWorkRoot.ps1"),
  (Join-Path $repo "tools/commands/package/Measure-MIRPackageComposition.ps1"),
  (Join-Path $repo "validation/tests/tooling/Test-MIRLayout.ps1"),
  (Join-Path $repo "validation/tests/tooling/Test-MIRPowerShellQuality.ps1")
)
$activeAutomationFiles = @(
  foreach ($root in @(".github", "scripts", "tools", "validation", ".mir/lifecycle/tasks")) {
    Get-ChildItem -LiteralPath (Join-Path $repo $root) -File -Recurse
  }
  Get-Item -LiteralPath (Join-Path $repo ".mir/assurance.json")
  Get-Item -LiteralPath (Join-Path $repo ".mir/fixtures.yml")
  Get-Item -LiteralPath (Join-Path $repo ".mir/control-plane/control-plane.json")
)
foreach ($file in $activeAutomationFiles) {
  if ($file.FullName -in $deprecatedReferenceExclusions) { continue }
  if ((Get-Content -Raw -LiteralPath $file.FullName) -match $deprecatedOutputPattern) {
    throw "Active automation still references the retired .work root: $($file.FullName.Substring($repo.Length + 1))"
  }
}
$legacyCliText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts/mir.ps1")
$publicCliText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools/mir.ps1")
if ($legacyCliText -notmatch "MIR-L5-LEGACY-CLI-WRAPPER" -or
    $legacyCliText -notmatch 'tools[/\\]mir\.ps1' -or $legacyCliText.Split([char]10).Count -gt 15) {
  throw "Legacy CLI is not a thin forwarder to the public facade."
}
if ($publicCliText -match "MIR-L5-LEGACY-CLI-WRAPPER" -or
    $publicCliText -match 'Join-Path \$repo "scripts[/\\]mir\.ps1"' -or
    -not $publicCliText.Contains("function Show-MIRHelp")) {
  throw "Public CLI does not own the command dispatcher."
}

function Invoke-MIRCliProbe {
  param([Parameter(Mandatory)][string]$Entrypoint, [Parameter(Mandatory)][string[]]$Arguments)
  $output = (& pwsh -NoProfile -File $Entrypoint @Arguments 2>&1 | Out-String).Replace("`r`n", "`n").Trim()
  return [pscustomobject]@{exit_code=$LASTEXITCODE;output=$output}
}

$legacySchemaTestPath = "scripts/" + "Test-MIRVerificationSchemas.ps1"
$legacyTest = Invoke-MIRCliProbe -Entrypoint (Join-Path $repo $legacySchemaTestPath) -Arguments @("-RepoRoot", $repo)
$canonicalTest = Invoke-MIRCliProbe -Entrypoint (Join-Path $repo "validation/tests/tooling/Test-MIRVerificationSchemas.ps1") -Arguments @("-RepoRoot", $repo)
if ($legacyTest.exit_code -ne $canonicalTest.exit_code -or $legacyTest.output -cne $canonicalTest.output) {
  throw "Legacy/canonical test entrypoint parity failed."
}

foreach ($arguments in @(
  [string[]]@("help"),
  [string[]]@("path", "resolve", "releases.deltas"),
  [string[]]@("path", "resolve", "--path", ".mir/releases/deltas/3.2.1-to-3.2.2.json")
)) {
  $legacyCli = Invoke-MIRCliProbe -Entrypoint (Join-Path $repo "scripts/mir.ps1") -Arguments $arguments
  $stableCli = Invoke-MIRCliProbe -Entrypoint (Join-Path $repo "tools/mir.ps1") -Arguments $arguments
  if ($legacyCli.exit_code -ne $stableCli.exit_code -or $legacyCli.output -cne $stableCli.output) {
    throw "Stable CLI parity failed for: $($arguments -join ' ')"
  }
}

Write-Host "[ok] repository paths, canonical tests, legacy wrappers, output roots, hidden artifact uploads, historical aliases, ownership inventory, layout safety, and CLI facade parity agree."
