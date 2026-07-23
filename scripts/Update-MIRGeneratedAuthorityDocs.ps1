param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")),
  [switch]$Check
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

function Read-MIRJson([string]$RelativePath) {
  return Get-Content -Raw -LiteralPath (Join-Path $repo $RelativePath) | ConvertFrom-Json
}

function ConvertTo-MIRDisplay($Value) {
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return "pending" }
  return [string]$Value
}

function Set-MIRGeneratedDocument([string]$RelativePath, [string[]]$Lines) {
  $path = Join-Path $repo $RelativePath
  $content = ($Lines -join "`n") + "`n"
  if ($Check) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Generated document is missing: $RelativePath" }
    $existing = (Get-Content -Raw -LiteralPath $path).Replace("`r`n", "`n")
    if ($existing -cne $content) { throw "Generated document is stale: $RelativePath" }
    return
  }
  $parent = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $parent)
  }
  [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))
}

$ledger = Read-MIRJson ".mir/releases.json"
if ([int]$ledger.schema -ne 1 -or [string]$ledger.authority -ne "canonical-release-ledger") {
  throw "Canonical release ledger schema 1 is required."
}
$candidate = $ledger.development."factorio-2.1"
$superseded = $candidate.supersedes_candidate
$candidateLines = @(
  "---",
  "title: `"Current Development Candidate`"",
  "status: current",
  "applies_to: `"$($candidate.mir_version)`"",
  "audience: release-manager",
  "doc_type: reference",
  "owner: mir-maintainers",
  "last_reviewed: $($ledger.updated_at)",
  "supersedes: []",
  "superseded_by: []",
  "---",
  "",
  "# Current Development Candidate",
  "",
  "> Generated from ``.mir/releases.json`` by ``scripts/Update-MIRGeneratedAuthorityDocs.ps1``. Do not edit candidate identity here.",
  "",
  "## Factorio 2.1 development line",
  "",
  "| Field | Authority |",
  "| --- | --- |",
  "| MIR version | ``$(ConvertTo-MIRDisplay $candidate.mir_version)`` |",
  "| Candidate | ``$(ConvertTo-MIRDisplay $candidate.candidate_id)`` |",
  "| Branch | ``$(ConvertTo-MIRDisplay $candidate.branch)`` |",
  "| Package source commit | ``$(ConvertTo-MIRDisplay $candidate.package_source_commit)`` |",
  "| Package source tree | ``$(ConvertTo-MIRDisplay $candidate.package_source_tree)`` |",
  "| Package source SHA-256 | ``$(ConvertTo-MIRDisplay $candidate.package_source_sha256)`` |",
  "| Archive | ``$(ConvertTo-MIRDisplay $candidate.archive)`` |",
  "| Archive bytes | ``$(ConvertTo-MIRDisplay $candidate.archive_bytes)`` |",
  "| Archive entries | ``$(ConvertTo-MIRDisplay $candidate.archive_entries)`` |",
  "| Archive SHA-256 | ``$(ConvertTo-MIRDisplay $candidate.archive_sha256)`` |",
  "| Package content SHA-256 | ``$(ConvertTo-MIRDisplay $candidate.package_content_sha256)`` |",
  "| Qualification | ``$(ConvertTo-MIRDisplay $candidate.qualification)`` |",
  "| Publication | ``$(ConvertTo-MIRDisplay $candidate.publication_status)`` |",
  "| Status | ``$(ConvertTo-MIRDisplay $candidate.status)`` |",
  "",
  "## Superseded candidate",
  "",
  "| Field | Authority |",
  "| --- | --- |",
  "| Candidate | ``$(ConvertTo-MIRDisplay $superseded.candidate_id)`` |",
  "| Package source commit | ``$(ConvertTo-MIRDisplay $superseded.package_source_commit)`` |",
  "| Archive bytes | ``$(ConvertTo-MIRDisplay $superseded.archive_bytes)`` |",
  "| Archive entries | ``$(ConvertTo-MIRDisplay $superseded.archive_entries)`` |",
  "| Archive SHA-256 | ``$(ConvertTo-MIRDisplay $superseded.archive_sha256)`` |",
  "| Reason | $(ConvertTo-MIRDisplay $superseded.reason) |",
  "",
  "Published baselines remain immutable and development candidates remain unreleased until exact automated, manual, protected, and seal authority agree."
)
Set-MIRGeneratedDocument "docs/releases/current-candidate.md" $candidateLines

$profiles = Read-MIRJson ".mir/technology-quality-profiles.json"
$governance = Read-MIRJson ".mir/technology-governance.json"
if ([int]$profiles.schema -ne 2 -or [string]$profiles.authority -ne "mir-technology-quality-profiles-v2") {
  throw "Technology quality profile authority schema 2 is required."
}
$governanceLines = [Collections.Generic.List[string]]::new()
foreach ($line in @(
  "---", "title: `"Technology Quality And Promotion Inventory`"", "status: current",
  "applies_to: `"3.2.0+`"", "audience: maintainer", "doc_type: reference",
  "owner: mir-maintainers", "last_reviewed: $($ledger.updated_at)", "supersedes: []", "superseded_by: []", "---", "",
  "# Technology Quality And Promotion Inventory", "",
  "> Generated from ``.mir/technology-quality-profiles.json`` and ``.mir/technology-governance.json``. Governance records, not this table, are authoritative.", "",
  "## Quality profiles", "",
  "| Profile | Candidate class | Members | Clusters max | Progression max | Science tiers max | Labs min | Owner conflicts max |",
  "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"
)) { $governanceLines.Add($line) }
foreach ($profile in @($profiles.profiles | Sort-Object profile_id)) {
  $governanceLines.Add("| ``$($profile.profile_id)`` | ``$($profile.candidate_class)`` | $($profile.minimum_members)-$($profile.maximum_members) | $($profile.maximum_semantic_clusters) | $($profile.maximum_progression_span) | $($profile.maximum_science_tier_span) | $($profile.minimum_accepting_labs) | $($profile.maximum_owner_conflicts) |")
}
$governanceLines.Add("")
$governanceLines.Add("Every profile also binds explicit semantic and observational evidence lists in the machine authority. Missing measurements remain incomplete and cannot pass promotion admission.")
$governanceLines.Add("")
$governanceLines.Add("## Reviewed automatic-generation authorizations")
$governanceLines.Add("")
$governanceLines.Add("| Authorization | Trust | Pack | Family | Stream | Provider version |")
$governanceLines.Add("| --- | --- | --- | --- | --- | --- |")
foreach ($row in @($governance.authorizations | Sort-Object authorization_id)) {
  $governanceLines.Add("| ``$($row.authorization_id)`` | ``$($row.trust_class)`` | ``$($row.pack)`` | ``$($row.family)`` | ``$($row.stream)`` | ``$($row.provider_version)`` |")
}
$governanceLines.Add("")
$governanceLines.Add("## Lifecycle record counts")
$governanceLines.Add("")
$governanceLines.Add("| Record class | Count |")
$governanceLines.Add("| --- | ---: |")
foreach ($field in @("approvals", "promotions", "applicability_envelopes", "migrations")) {
  $governanceLines.Add("| ``$field`` | $(@($governance.$field).Count) |")
}
$governanceLines.Add("")
$governanceLines.Add("A zero promotion count is explicit: broad automatic creation remains disabled and no candidate is represented as promoted without a passing assessment, human approval, applicability envelope, migration decision, and upgrade evidence.")
Set-MIRGeneratedDocument "docs/reference/generated/technology-quality-and-promotion.md" $governanceLines

$schemas = Read-MIRJson ".mir/compiler-schema-authority.json"
$schemaLines = [Collections.Generic.List[string]]::new()
foreach ($line in @(
  "---", "title: `"Compiler Schema Registry`"", "status: current", "applies_to: `"3.2.0+`"",
  "audience: developer", "doc_type: reference", "owner: mir-maintainers", "last_reviewed: $($ledger.updated_at)",
  "supersedes: []", "superseded_by: []", "---", "", "# Compiler Schema Registry", "",
  "> Generated from ``.mir/compiler-schema-authority.json``. The machine registry is authoritative.", "",
  "| Record | Current | Readable | Writable | Compatibility projection |", "| --- | ---: | --- | --- | ---: |"
)) { $schemaLines.Add($line) }
foreach ($property in @($schemas.records.PSObject.Properties | Sort-Object Name)) {
  $record = $property.Value
  $projection = if ($record.PSObject.Properties["compatibility_projection"]) { [string]$record.compatibility_projection } else { "none" }
  $schemaLines.Add("| ``$($property.Name)`` | $($record.current) | $(@($record.readable) -join ', ') | $(@($record.writable) -join ', ') | $projection |")
}
$schemaLines.Add("")
$schemaLines.Add("Unknown schema versions fail closed. Downgrades exist only through explicit compatibility projections.")
Set-MIRGeneratedDocument "docs/reference/generated/compiler-schema-registry.md" $schemaLines

if ($Check) { Write-Host "[ok] generated release, quality/promotion, and compiler-schema documentation is current." }
