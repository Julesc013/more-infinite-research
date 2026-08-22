param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../.."))
)

$ErrorActionPreference = "Stop"
$path = Join-Path $RepoRoot ".mir/releases/waves/mir4-r0/MIR4-Public-Feedback-IntakeV1.json"
$record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100

if ([int]$record.schema -ne 1 -or [string]$record.kind -ne "MIR4PublicFeedbackIntakeV1" -or
    [string]$record.status -ne "accepted-pass-with-findings-sol02" -or $record.package_visible) {
  throw "MIR 4 public-feedback intake header is invalid."
}
if ($record.scope.source_pack.embedded_instructions_authorized -or
    [string]$record.scope.source_pack.effect -ne "feedback-and-proposed-acceptance-input-only") {
  throw "Supplied handoff documents were incorrectly promoted to executable authority."
}
if ([string]$record.scope.starting_source.commit -ne "65796a468a5247c8b31143a82db5fa3c94926d46" -or
    [string]$record.scope.starting_source.audited_predecessor_commit -ne "e190836c8b8f781c4e41dafc08df367ca986b33a") {
  throw "SOL02 is not bound to the reconciled M4C01 source identities."
}
$routeProof = $record.scope.route_correction_proof
if ([string]$routeProof.status -ne "passed-generic-runtime-fixture" -or
    [string]$routeProof.result -ne "PASS" -or [int]$routeProof.exit_code -ne 0 -or
    [string]$routeProof.engine_version -ne "2.1.14.87180" -or
    [string]$routeProof.log_sha256 -notmatch '^[A-F0-9]{64}$' -or
    [string]$routeProof.claim_boundary -notmatch "exact Cubium.*Recycler Progression") {
  throw "SOL02 generic route-correction runtime proof is missing or overclaims exact ecosystem coverage."
}

$required = @(
  "REPRO-MAXCAP",
  "REPRO-CUBIUM",
  "REPRO-RECYCLER-PROGRESSION",
  "REPRO-COST-V2-REQUEST",
  "REPRO-K2SO-SCIENCE",
  "REPRO-OVERHAUL-SUPPORT"
)
$families = @($record.families)
if ($families.Count -ne $required.Count -or
    @($families.id | Sort-Object -Unique).Count -ne $required.Count -or
    @($required | Where-Object { $_ -notin @($families.id) }).Count -ne 0) {
  throw "SOL02 must retain exactly one governed reproducer for every supplied feedback family."
}
foreach ($family in $families) {
  if ($null -eq $family.minimal_reproducer -or $null -eq $family.authority_map -or
      @($family.authority_map.PSObject.Properties).Count -eq 0 -or
      [string]::IsNullOrWhiteSpace([string]$family.classification)) {
    throw "Feedback family $($family.id) lacks a minimal reproducer, classification, or authority map."
  }
}

$recycler = @($families | Where-Object id -eq "REPRO-RECYCLER-PROGRESSION")
if ($recycler.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$recycler[0].acquisition_gap) -or
    @($recycler[0].exact_inputs).Count -ne 2 -or
    @($recycler[0].exact_inputs | Where-Object { [string]$_.sha256 -notmatch '^[A-F0-9]{64}$' }).Count -ne 0 -or
    "1.0.0" -notin @($recycler[0].exact_inputs.version) -or "1.1.1" -notin @($recycler[0].exact_inputs.version) -or
    [string]$recycler[0].acquisition_gap -notmatch "target-local proof") {
  throw "Recycler Progression archives and their still-independent target-local proof boundary are not exact."
}
$overhaul = @($families | Where-Object id -eq "REPRO-OVERHAUL-SUPPORT")[0]
if ([string]$overhaul.classification -ne "programme-request-not-single-defect" -or
    [string]$overhaul.admission_rule -notmatch "subject-level") {
  throw "Overhaul intake was collapsed into a blanket compatibility claim."
}
if ([int]$record.exit_gate.minimal_reproducer_count -ne 6 -or
    [int]$record.exit_gate.authority_map_count -ne 6 -or
    $record.exit_gate.publication_authorized) {
  throw "SOL02 exit gate is incomplete or grants publication authority."
}

Write-Host "MIR 4 public-feedback intake and reproduction authority passed."
