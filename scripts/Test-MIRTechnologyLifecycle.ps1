param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")))

$ErrorActionPreference = "Stop"
$manifestPath = Join-Path $RepoRoot ".mir\technology-lifecycle.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schema -ne 1) { throw "Technology lifecycle authority schema is invalid." }
foreach ($record in @(
  "TechnologyCandidate", "TechnologyDesign", "TechnologyQualification", "TechnologyApproval",
  "TechnologyPromotion", "TechnologyMigration", "TechnologyCatalog", "TechnologyApplicabilityEnvelope"
)) {
  if ([int]$manifest.records.$record -lt 1) { throw "Technology lifecycle authority omits $record." }
}
$expectedTransitions = @(
  "unassigned->provisional", "provisional->reserved", "reserved->stable-unreleased",
  "stable-unreleased->released", "released->retired"
)
$actualTransitions = @()
foreach ($property in $manifest.identity_transitions.PSObject.Properties) {
  foreach ($target in @($property.Value)) { $actualTransitions += "$($property.Name)->$target" }
}
if (@(Compare-Object $expectedTransitions $actualTransitions).Count -ne 0) {
  throw "Technology lifecycle identity transitions differ from the governed state machine."
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir-technology-lifecycle-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
  $subjects = [ordered]@{
    recipes=@("iron-gear-wheel"); products=@(); items=@(); fluids=@(); entities=@(); technologies=@()
    effect_targets=@([ordered]@{type="recipe"; name="iron-gear-wheel"})
    science_packs=@("automation-science-pack"); surfaces=@()
  }
  function New-FixtureDesign {
    param([string]$Name, [string]$Fingerprint)
    return [ordered]@{
      schema=2
      candidate_id="mir-candidate/recipe-productivity/fixture"
      technology_id="mir-fixture-technology"
      semantic_identity=[ordered]@{capability="recipe-productivity"; family="fixture"; partition="default"}
      subjects=$subjects
      materialization=[ordered]@{kind="create"}
      design_fingerprint=$Fingerprint
      prototype_fingerprint="prototype-$Fingerprint"
      qualification_fingerprint="qualification-$Fingerprint"
      provenance=[ordered]@{fields=[ordered]@{
        "identity.technology_id"=[ordered]@{value="mir-fixture-technology"}
        "presentation.localised_name"=[ordered]@{value=@("", $Name)}
      }}
    }
  }
  function Copy-FixtureMap {
    param([System.Collections.IDictionary]$Value)
    $copy = [ordered]@{}
    foreach ($entry in $Value.GetEnumerator()) { $copy[$entry.Key] = $entry.Value }
    return $copy
  }
  $before = New-FixtureDesign -Name "Before" -Fingerprint "design-before"
  $after = New-FixtureDesign -Name "Reviewed" -Fingerprint "design-after"
  $drift = New-FixtureDesign -Name "Drifted" -Fingerprint "design-drift"
  $beforePath = Join-Path $tempRoot "before.json"
  $afterPath = Join-Path $tempRoot "after.json"
  $driftPath = Join-Path $tempRoot "drift.json"
  $before | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $beforePath -Encoding UTF8
  $after | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $afterPath -Encoding UTF8
  $drift | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $driftPath -Encoding UTF8

  $plan = [ordered]@{
    schema=3; plan_fingerprint="fixture-plan"; rows=@([ordered]@{
      schema=3; stream_key="fixture"; manifest_id="fixture"; action="emit"; source="fixture"
      provider_ids=@("fixture-provider"); family_ids=@("fixture-family"); technology_design=$after
      gates=[ordered]@{target_supported=[ordered]@{status="passed"; evidence=@("fixture")}}
    })
  }
  $planPath = Join-Path $tempRoot "generation-plan.json"
  $catalogPath = Join-Path $tempRoot "catalog.json"
  $plan | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $planPath -Encoding UTF8
  & (Join-Path $RepoRoot "scripts\Export-MIRTechnologyCatalog.ps1") -GenerationPlanPath $planPath -OutputPath $catalogPath
  $catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
  if ($catalog.schema -ne 1 -or @($catalog.candidates).Count -ne 1 -or @($catalog.qualifications).Count -ne 1 `
      -or [string]::IsNullOrWhiteSpace([string]$catalog.catalog_sha256)) {
    throw "Technology catalog exporter did not produce a fingerprinted candidate and qualification."
  }

  $approvalRequest = [ordered]@{
    approval_id="approval/fixture/1"; candidate_id=$after.candidate_id
    applicability=[ordered]@{
      exact_mods=@("base")
      structural_envelope=[ordered]@{
        schema=1; envelope_id="fixture-v1"; factorio_lines=@("2.1")
        required_features=@("recipe-productivity")
        required_mods=@([ordered]@{id="base"})
        structural_predicates=@(
          [ordered]@{predicate="recipe.visible"},
          [ordered]@{predicate="recipe.productivity-eligible"}
        )
        positive_examples=@("positive-fixture"); negative_examples=@("negative-fixture")
        maximum_new_matches=0
      }
    }
    selected_alternative="create:mir-fixture-technology"
    approved_design_fingerprint=$after.design_fingerprint
    qualification_fingerprint=$catalog.qualifications[0].qualification_fingerprint_sha256
    locked_fields=@("identity.technology_id", "presentation.localised_name")
    adaptive_envelopes=[ordered]@{}
    required_evidence=@("negative-fixture", "positive-fixture")
    reviewer="fixture-reviewer"; decided_at="2026-07-18T00:00:00Z"; reason=""
  }
  $approvalRequestPath = Join-Path $tempRoot "approval-request.json"
  $approvalPath = Join-Path $tempRoot "approval.json"
  $approvalRequest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $approvalRequestPath -Encoding UTF8
  & (Join-Path $RepoRoot "scripts\New-MIRTechnologyLifecycleRecord.ps1") -Kind Approval -InputPath $approvalRequestPath -OutputPath $approvalPath
  $approval = Get-Content -Raw -LiteralPath $approvalPath | ConvertFrom-Json
  if ($approval.decision -ne "approved" -or [string]::IsNullOrWhiteSpace([string]$approval.approval_fingerprint_sha256) `
      -or [string]::IsNullOrWhiteSpace([string]$approval.applicability.structural_envelope.envelope_fingerprint_sha256)) {
    throw "Approval tooling did not bind an exact reviewed decision."
  }

  $approvedDiffPath = Join-Path $tempRoot "approved-diff.json"
  $driftDiffPath = Join-Path $tempRoot "drift-diff.json"
  & (Join-Path $RepoRoot "scripts\Compare-MIRTechnologyDesigns.ps1") -BeforePath $beforePath -AfterPath $afterPath -ApprovalPath $approvalPath -OutputPath $approvedDiffPath
  & (Join-Path $RepoRoot "scripts\Compare-MIRTechnologyDesigns.ps1") -BeforePath $beforePath -AfterPath $driftPath -ApprovalPath $approvalPath -OutputPath $driftDiffPath
  if ((Get-Content -Raw -LiteralPath $approvedDiffPath | ConvertFrom-Json).status -ne "APPROVED") {
    throw "Exact approved TechnologyDesign was not accepted."
  }
  if ((Get-Content -Raw -LiteralPath $driftDiffPath | ConvertFrom-Json).status -ne "REJECTED_LOCK_VIOLATION") {
    throw "Locked TechnologyDesign drift was not rejected."
  }

  foreach ($decision in @("Quarantine", "Demotion")) {
    $decisionRequest = Copy-FixtureMap $approvalRequest
    $decisionRequest["approval_id"] = "approval/fixture/$($decision.ToLowerInvariant())"
    $decisionRequest["reason"] = "fixture-$($decision.ToLowerInvariant())"
    $decisionRequestPath = Join-Path $tempRoot "$($decision.ToLowerInvariant())-request.json"
    $decisionPath = Join-Path $tempRoot "$($decision.ToLowerInvariant()).json"
    $decisionRequest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $decisionRequestPath -Encoding UTF8
    & (Join-Path $RepoRoot "scripts\New-MIRTechnologyLifecycleRecord.ps1") -Kind $decision -InputPath $decisionRequestPath -OutputPath $decisionPath
  }

  $promotionRequest = [ordered]@{
    promotion_id="promotion/fixture/1"; technology_id="mir-fixture-technology"; candidate_id=$after.candidate_id
    approval_id=$approval.approval_id; approved_design_fingerprint=$after.design_fingerprint
    prior_identity_state="reserved"; identity_state="stable-unreleased"; migration_policy="stable"
    introduced_in="3.2.0"; evidence=@($approval.approval_fingerprint_sha256)
  }
  $promotionRequestPath = Join-Path $tempRoot "promotion-request.json"
  $promotionPath = Join-Path $tempRoot "promotion.json"
  $promotionRequest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $promotionRequestPath -Encoding UTF8
  & (Join-Path $RepoRoot "scripts\New-MIRTechnologyLifecycleRecord.ps1") -Kind Promotion -InputPath $promotionRequestPath -OutputPath $promotionPath
  $invalidPromotion = Copy-FixtureMap $promotionRequest
  $invalidPromotion["prior_identity_state"] = "released"
  $invalidPromotion["identity_state"] = "reserved"
  $invalidPromotionPath = Join-Path $tempRoot "invalid-promotion.json"
  $invalidPromotion | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $invalidPromotionPath -Encoding UTF8
  $invalidRejected = $false
  try {
    & (Join-Path $RepoRoot "scripts\New-MIRTechnologyLifecycleRecord.ps1") -Kind Promotion -InputPath $invalidPromotionPath -OutputPath (Join-Path $tempRoot "invalid-output.json")
  } catch { $invalidRejected = $true }
  if (-not $invalidRejected) { throw "Identity-state regression was not rejected." }

  $migrationRequest = [ordered]@{
    migration_id="migration/fixture/1"; from_technology_id="old-fixture"; to_technology_id="mir-fixture-technology"
    strategy="retain-hidden-alias"; save_behavior="preserve researched state"; approval_id=$approval.approval_id
    evidence=@((Get-Content -Raw -LiteralPath $promotionPath | ConvertFrom-Json).promotion_fingerprint_sha256)
  }
  $migrationRequestPath = Join-Path $tempRoot "migration-request.json"
  $migrationRequest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $migrationRequestPath -Encoding UTF8
  & (Join-Path $RepoRoot "scripts\New-MIRTechnologyLifecycleRecord.ps1") -Kind Migration -InputPath $migrationRequestPath -OutputPath (Join-Path $tempRoot "migration.json")
} finally {
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Host "[ok] MIR technology lifecycle schemas, catalogs, diffs, decisions, transitions, and migrations passed."
