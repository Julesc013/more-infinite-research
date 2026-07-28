param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [switch]$AllPackageLocks
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context", "Shadow")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}

$records = Assert-MIRCPRecords -RepoRoot $repo
$freeze = Assert-MIRCPPackageFreeze -RepoRoot $repo -AllLocks:$AllPackageLocks

foreach ($schemaName in @("change-record.schema.json", "incident-record.schema.json", "release-record.schema.json", "release-transition.schema.json", "task-node.schema.json", "observation.schema.json", "assertion.schema.json", "evaluation.schema.json", "execution-registry.schema.json", "verification-context.schema.json", "evidence-object.schema.json", "evidence-manifest.schema.json", "evidence-revocation.schema.json")) {
  $schema = Read-MIRCPJson -Path "verification/schema/$schemaName" -RepoRoot $repo
  if ([string]$schema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or [string]$schema.type -ne "object" -or $schema.additionalProperties -ne $false) {
    throw "Control-plane schema is not strict JSON Schema 2020-12: $schemaName"
  }
}

$views = Update-MIRCPViews -RepoRoot $repo -Check
if ([string]$views.status -ne "current") { throw "Control-plane generated views are not current." }
$calibration = Assert-MIRCPMutationCalibration -RepoRoot $repo
if ([int]$calibration.false_negative_budget -ne 0) { throw "Impact mutation calibration permits false negatives." }
$planA = New-MIRCPPlan -Mode changed -ChangedPath @("scripts/MIRControlPlane/Planner.ps1") -RepoRoot $repo
$planB = New-MIRCPPlan -Mode changed -ChangedPath @("scripts/MIRControlPlane/Planner.ps1") -RepoRoot $repo
if ([string]$planA.plan_id -ne [string]$planB.plan_id -or [bool]$planA.plan.impact.governance_failure) { throw "Semantic planner is nondeterministic or failed to own its own implementation." }
$releaseForInputs = Get-MIRCPReleaseByVersion -Release "3.2.2" -RepoRoot $repo
$docsInput = Get-MIRCPEffectiveInputManifest -Task ((Get-MIRCPTaskMap -RepoRoot $repo)["docs.schema"]) -ReleaseRecord $releaseForInputs -Target "2.1" -SourceRepoRoot $repo -RepoRoot $repo
$docsManifestRow = @($docsInput.rows | Where-Object input -eq "source:.mir/docs.yml")
$docsFileRow = @($docsManifestRow.matches | Where-Object path -eq ".mir/docs.yml")
if ($docsManifestRow.Count -ne 1 -or [string]$docsManifestRow[0].scope -ne "source" -or [string]$docsManifestRow[0].source_commit -ne ([string](& git -C $repo rev-parse HEAD)).Trim() -or
    $docsFileRow.Count -ne 1 -or [string]$docsFileRow[0].sha256 -ne (Get-MIRCPSha256Text -Value ([IO.File]::ReadAllText((Join-Path $repo ".mir/docs.yml")).Replace("`r`n", "`n").Replace("`r", "`n")))) {
  throw "Effective-input manifest is not bound to canonical repository file content."
}
$freshPlan = New-MIRCPPlan -Mode calibrate-fresh -ChangedPath @("scripts/MIRControlPlane/Planner.ps1") -RepoRoot $repo
$verificationTaskCount = @(Get-MIRCPTaskRecords -RepoRoot $repo | Where-Object {
  ($null -eq $_.PSObject.Properties["activation"] -or [string]$_.activation -eq "verification") -and
  ($null -eq $_.PSObject.Properties["targets"] -or @($_.targets | ForEach-Object { [string]$_ }) -contains "2.1")
}).Count
if ([int]$freshPlan.plan.task_count -ne $verificationTaskCount -or [string]$freshPlan.plan.stage -ne "verification" -or -not [bool]$freshPlan.plan.aggregate_is_result_only) { throw "Fresh calibration does not select the complete verification-stage TaskNode graph or treats aggregates as executable." }
$aggregateRows = @($freshPlan.plan.tasks | Where-Object kind -eq "aggregate")
if ($aggregateRows.Count -ne 2 -or @($aggregateRows | Where-Object action -ne "AGGREGATE").Count -ne 0) { throw "Result-only aggregates were scheduled as executable work." }
$publicationPlan = New-MIRCPPlan -Mode calibrate-fresh -ChangedPath @("scripts/MIRControlPlane/Planner.ps1") -Target "2.0" -Release "2.5.0" -Stage publication -SelectionOnly -RepoRoot $repo
foreach ($requiredPublicationNode in @("tag", "publication", "public-byte-verification", "promotion", "seal", "protected.qualification", "qualification.full", "backport.reconstruction")) {
  if (@($publicationPlan.plan.tasks.id) -notcontains $requiredPublicationNode) { throw "Publication plan omitted prerequisite $requiredPublicationNode." }
}
$registry = Update-MIRCPExecutionRegistry -Target "2.1" -RepoRoot $repo -Check
$registryResult = Assert-MIRCPExecutionRegistry -Registry $registry -RepoRoot $repo
$replay = Update-MIRCPV4ReplayReport -RepoRoot $repo -Check
if ([string]$replay.verdict -ne "passed" -or [int]$replay.metrics.source_evidence -ne 130) { throw "Historical v4 evidence replay is incomplete." }

$backport = Read-MIRCPJson -Path ".mir/backports/2.5.0.json" -RepoRoot $repo
if ([string]$backport.source.tag_state -ne "immutable" -or [string]$backport.source.tag_commit -ne "1138ed55ad7ad42e38cf9e821d1d4e7de5df6378") {
  throw "P9 backport authority is not bound to immutable tag 3.2.2."
}

$docManifest = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir/docs.yml")
if ($docManifest -notmatch [regex]::Escape("docs/architecture/control-plane-v5.md")) {
  throw "Control Plane v5 architecture document is not registered."
}
$modules = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir/modules.yml")
foreach ($token in @("control_plane_policy", "control_plane_entrypoint", "control_plane_gate")) {
  if ($modules -notmatch $token) { throw "Module manifest is missing $token." }
}

Write-Host "[ok] MIR Control Plane v5 records ($($records.changes) changes, $($records.incidents) incidents, $($records.releases) releases, $($records.tasks) tasks), package freeze $($freeze.lock_id), $($registryResult.scenarios) exact-environment scenarios, 130 replayed observations, and $($calibration.cases) zero-false-negative impact mutations are valid."
