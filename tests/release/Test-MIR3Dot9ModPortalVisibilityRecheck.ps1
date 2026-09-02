# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot "tools/lib/mir4/BootstrapMaterialization.ps1")

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) {
  throw "Test-Json is required for fail-closed Mod Portal visibility recheck tests."
}

$recordRelativePath = ".mir/evidence/terminal-publication/2026-08-16/mod-portal/MIR3-Dot9-ModPortal-VisibilityRecheckV1.json"
$recordPath = Join-Path $RepoRoot $recordRelativePath
$schemaPath = Join-Path $RepoRoot "spec/schemas/mir3-dot9-mod-portal-visibility-recheck.schema.json"
$reconciliationRelativePath = ".mir/evidence/terminal-publication/2026-08-16/mod-portal/MIR3-Dot9-ModPortal-Visibility-Canonicalization-ReconciliationV1.json"
$reconciliationPath = Join-Path $RepoRoot $reconciliationRelativePath
$reconciliationSchemaPath = Join-Path $RepoRoot "spec/schemas/mir3-dot9-mod-portal-visibility-canonicalization-reconciliation-v1.schema.json"
$recordText = Get-Content -Raw -LiteralPath $recordPath
$record = $recordText | ConvertFrom-Json -DateKind String
$reconciliationText = Get-Content -Raw -LiteralPath $reconciliationPath
$reconciliation = $reconciliationText | ConvertFrom-Json -DateKind String

Assert-True ($record.observed_at -is [string]) "Governed portal timestamps must remain lexical strings during canonical hash validation."
Assert-True ($recordText | Test-Json -SchemaFile $schemaPath) "MIR 3 .9 Mod Portal visibility recheck schema validation failed."
Assert-True ($reconciliationText | Test-Json -SchemaFile $reconciliationSchemaPath) "MIR 3 .9 Mod Portal canonicalization reconciliation schema validation failed."
Assert-True (Test-MIR3Dot9PortalVisibilityHashReconciliation -HistoricalRecord $record -Reconciliation $reconciliation -HistoricalRecordPath $recordPath) "The historical and corrected portal self-hash interpretations are not reconciled exactly."

$priorPath = Join-Path $RepoRoot ([string]$record.prior_custody_observation.path)
Assert-True (Test-Path -LiteralPath $priorPath -PathType Leaf) "The prior custody observation bound by the visibility recheck is absent."
Assert-True ((Get-MIR4Sha256File -Path $priorPath) -ceq [string]$record.prior_custody_observation.sha256) "The prior custody observation binding is stale."
$prior = Get-Content -Raw -LiteralPath $priorPath | ConvertFrom-Json -DateKind String

Assert-True ((@($record.sources.surface) -join '|') -ceq "official-full-api|official-rendered-download-table") "Visibility source order or coverage drifted."
Assert-True ((@($record.releases.version) -join '|') -ceq "3.2.9|2.5.9") "Terminal release order or coverage drifted."
Assert-True ((@($record.releases | Where-Object { $_.api_visible -and $_.rendered_table_visible -and $_.sha1_matches_sealed }).Count) -eq 2) "Both terminal releases are not proven visible with matching SHA-1 on both public surfaces."

$api = @($record.sources | Where-Object { [string]$_.surface -ceq "official-full-api" })[0]
$rendered = @($record.sources | Where-Object { [string]$_.surface -ceq "official-rendered-download-table" })[0]
Assert-True ((@($api.matched_rows.version) -join '|') -ceq "3.2.9|2.5.9") "The API parser outcome no longer contains both terminal releases."
Assert-True ((@($rendered.matched_rows.version) -join '|') -ceq "2.5.9|3.2.9") "The rendered table parser outcome no longer contains both terminal releases."
Assert-True ([long]$api.response_bytes -gt 0 -and [long]$rendered.response_bytes -gt 0 -and
  [string]$api.response_sha256 -cmatch '^[A-F0-9]{64}$' -and
  [string]$rendered.response_sha256 -cmatch '^[A-F0-9]{64}$' -and
  $api.response_body_retained -eq $false -and $rendered.response_body_retained -eq $false) "Response identities or retention boundaries are malformed."

foreach ($release in @($record.releases)) {
  $priorRows = @($prior.observations | Where-Object { [string]$_.release -ceq [string]$release.version })
  Assert-True ($priorRows.Count -eq 1) "Prior custody does not uniquely contain $($release.version)."
  Assert-True ([string]$priorRows[0].portal_sha1 -ceq [string]$release.portal_sha1 -and
    [string]$priorRows[0].sealed_archive_sha1 -ceq [string]$release.sealed_archive_sha1 -and
    [string]$release.portal_sha1 -ceq [string]$release.sealed_archive_sha1) "Portal and sealed SHA-1 custody drifted for $($release.version)."
}

Assert-True ([int]$record.custody_state.authenticated_redownloads_complete -eq 0 -and
  [int]$record.custody_state.exact_engine_smokes_complete -eq 0 -and
  $record.custody_state.mir3_eol_blocked -eq $true) "The visibility-only recheck falsely closes authenticated custody or MIR 3 EOL."
Assert-True ([string]$record.claim_disposition.api_ui_visibility_discrepancy -ceq "disproven-at-observation-time") "The superseded API/UI discrepancy claim resurfaced."

$authorityValues = @($record.authority.PSObject.Properties | ForEach-Object { [bool]$_.Value })
Assert-True ((@($authorityValues | Where-Object { $_ }).Count) -eq 0) "The visibility recheck grants mutation or release authority."

$badRecord = $recordText | ConvertFrom-Json -DateKind String
$badRecord.authority.upload = $true
$badRecordText = $badRecord | ConvertTo-Json -Depth 100
Assert-True (-not ($badRecordText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) "Visibility schema admitted upload authority."

$badRecord = $recordText | ConvertFrom-Json -DateKind String
$badRecord.releases[1].rendered_table_visible = $false
$badRecordText = $badRecord | ConvertTo-Json -Depth 100
Assert-True (-not ($badRecordText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) "Visibility schema admitted the disproven 2.5.9 rendered-table omission."

Write-Host "[ok] MIR 3 .9 public visibility recheck is immutable, accurate, and non-authoritative"
