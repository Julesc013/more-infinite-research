param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")))

$ErrorActionPreference = "Stop"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir-rule-synthesis-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
  $outputs = @()
  foreach ($family in @("mining-drill-manufacturing", "assembling-machine-manufacturing", "logistics-manufacturing")) {
    $output = Join-Path $tempRoot ($family + ".json")
    & (Join-Path $RepoRoot "scripts\Invoke-MIRRuleSynthesis.ps1") -Family $family -OutputPath $output
    $proposal = Get-Content -Raw -LiteralPath $output | ConvertFrom-Json
    if ($proposal.schema -ne 1 -or $proposal.kind -ne "mir-family-rule-proposal" -or $proposal.status -ne "REVIEW_REQUIRED") {
      throw "Rule synthesis did not produce a review-required proposal for $family."
    }
    if ($proposal.production_mutation_authorized -ne $false -or @($proposal.selected_predicates).Count -eq 0 `
        -or @($proposal.new_unreviewed_matches).Count -ne 0 -or [string]::IsNullOrWhiteSpace([string]$proposal.proposal_sha256)) {
      throw "Rule synthesis proposal is not bounded and fingerprinted for $family."
    }
    foreach ($required in @("recipe.visible", "recipe.productivity-eligible", "output.deterministic-single-item", "risk.none")) {
      if ($required -notin @($proposal.selected_predicates)) { throw "Rule synthesis dropped hard predicate $required for $family." }
    }
    $outputs += $output
  }
  $repeat = Join-Path $tempRoot "repeat.json"
  & (Join-Path $RepoRoot "scripts\Invoke-MIRRuleSynthesis.ps1") -Family "mining-drill-manufacturing" -OutputPath $repeat
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $outputs[0]).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $repeat).Hash) {
    throw "Rule synthesis output is not byte deterministic."
  }
} finally {
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Host "[ok] MIR offline rule synthesis is deterministic, hard-gated, counterexample-bound, and review-only."
