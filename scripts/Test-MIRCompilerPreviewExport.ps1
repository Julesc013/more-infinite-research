param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")))

$ErrorActionPreference = "Stop"
$root = Join-Path ([IO.Path]::GetTempPath()) ("mir-compiler-preview-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $root | Out-Null

try {
  $catalogPath = Join-Path $root "catalog.json"
  $evidencePath = Join-Path $root "evidence.json"
  $outputPath = Join-Path $root "preview"
  [ordered]@{
    schema = 3; phase = "final"; catalog_fingerprint = "CATALOG"
    generation_plan_fingerprint = "GENERATION"; compilation_plan_fingerprint = "COMPILATION"
    candidates = @([ordered]@{candidate_id="alpha"; alternatives=@()})
    current_selections = @([ordered]@{candidate_id="alpha"; alternative_id="alpha/create"; action="emit"; design_fingerprint="DESIGN"; qualification_fingerprint="QUALIFIED"})
    qualifications = @(
      [ordered]@{candidate_id="beta"; alternative_id="beta/create"; qualification_decision="review-required"; reasons=@("ambiguous-membership"); design_fingerprint="BETA"; qualification_fingerprint="BETA-Q"},
      [ordered]@{candidate_id="gamma"; alternative_id="gamma/create"; qualification_decision="rejected"; rejection_reasons=@("hard-gate-failed"); design_fingerprint="GAMMA"; qualification_fingerprint="GAMMA-Q"}
    )
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding UTF8
  [ordered]@{
    provider_resolution = [ordered]@{decisions=@([ordered]@{
      provider_id="fixture-provider"; prototype_type="recipe"; prototype_name="gear"; target_stream="alpha"
      compatibility_pack="fixture-pack"; final_state="review-required"; risk_disposition="REVIEW_REQUIRED"
      reason="provider budget exceeded"; code="provider-budget"; decision_fingerprint="DECISION"
    })}
    telemetry = [ordered]@{counters=[ordered]@{
      generation_plan_public_bytes=1024; technology_catalog_public_bytes=2048
      coverage_public_bytes=512; compiler_evidence_public_bytes=4096
    }}
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

  & (Join-Path $RepoRoot "scripts\Export-MIRCompilerPreview.ps1") `
    -CatalogPath $catalogPath -EvidencePath $evidencePath -OutputDirectory $outputPath -Top 10
  $summary = Get-Content -Raw -LiteralPath (Join-Path $outputPath "compiler-preview-summary.json") | ConvertFrom-Json
  $markdown = Get-Content -Raw -LiteralPath (Join-Path $outputPath "compiler-preview-summary.md")
  if ([int]$summary.schema -ne 1 -or [string]$summary.kind -ne "mir-compiler-preview-summary" -or
      $summary.counts.ambiguous_or_review_required -ne 1 -or $summary.counts.rejected -ne 1 -or
      @($summary.ecosystem_dependent_decisions).Count -ne 1 -or @($summary.provider_budget_reviews).Count -ne 1 -or
      @($summary.public_artifact_budgets | Where-Object status -eq "pass").Count -ne 4 -or
      [string]::IsNullOrWhiteSpace([string]$summary.summary_sha256)) {
    throw "Compiler PREVIEW JSON summary is incomplete or incorrect."
  }
  foreach ($heading in @("Selected decisions", "Ambiguous or review-required cases", "Rejected designs", "Ecosystem-dependent provider decisions", "Public artifact budgets")) {
    if (-not $markdown.Contains($heading)) { throw "Compiler PREVIEW Markdown omits: $heading" }
  }
  if (-not (Test-Path -LiteralPath (Join-Path $outputPath "technology-catalog.full.json"))) {
    throw "Compiler PREVIEW export omitted the exact full catalog."
  }
} finally {
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $resolvedRoot = [IO.Path]::GetFullPath($root)
  if ($resolvedRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
      (Split-Path -Leaf $resolvedRoot) -like "mir-compiler-preview-*") {
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "[ok] MIR compiler PREVIEW full-catalog and reviewer-summary export passed."
