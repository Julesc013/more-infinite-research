param(
  [string]$RepoRoot = "",
  [string]$SuppliedRoot = "",
  [string]$PastedAttachmentPath = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
} else {
  (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot "tools/lib/mir4/BootstrapMaterialization.ps1")

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

function Test-AgainstSchema([string]$Json, [string]$SchemaPath) {
  try {
    return [bool]($Json | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)
  } catch {
    return $false
  }
}

function Get-ZipEntryInventory([string]$Path) {
  Add-Type -AssemblyName System.IO.Compression
  $archiveItem = Get-Item -LiteralPath $Path
  if ([long]$archiveItem.Length -gt 16777216) { throw "Supplied programme archive exceeds its bounded compressed size." }
  $fileStream = [IO.File]::OpenRead($Path)
  $archive = [IO.Compression.ZipArchive]::new($fileStream, [IO.Compression.ZipArchiveMode]::Read, $false)
  try {
    if ($archive.Entries.Count -eq 0 -or $archive.Entries.Count -gt 128) { throw "Supplied programme archive entry count is outside its bounded range." }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $rows = [Collections.Generic.List[object]]::new()
    [long]$uncompressedBytes = 0
    foreach ($entry in $archive.Entries) {
      if ([long]$entry.Length -gt 16777216) { throw "Supplied programme archive entry exceeds its bounded expanded size: $($entry.FullName)" }
      $uncompressedBytes += [long]$entry.Length
      if ($uncompressedBytes -gt 67108864) { throw "Supplied programme archive exceeds its bounded total expanded size." }
      $name = [string]$entry.FullName
      if ([string]::IsNullOrWhiteSpace($name) -or $name.Contains("\") -or $name.StartsWith("/", [StringComparison]::Ordinal) -or
          @($name.Split('/') | Where-Object { $_ -eq ".." }).Count -ne 0 -or -not $seen.Add($name)) {
        throw "Unsafe or duplicate ZIP entry in supplied programme archive: $name"
      }
      $entryBytes = Read-MIR4BoundedZipEntryBytes -Entry $entry -MaximumBytes 16777216
      $entryHash = Get-MIR4Sha256Bytes -Bytes $entryBytes
      $rows.Add([pscustomobject][ordered]@{ path=$name; bytes=[long]$entry.Length; sha256=$entryHash })
    }

    $sorted = [object[]]$rows.ToArray()
    [Array]::Sort($sorted, [Comparison[object]]{
      param($left, $right)
      [StringComparer]::Ordinal.Compare([string]$left.path, [string]$right.path)
    })
    $material = [Text.StringBuilder]::new()
    [void]$material.Append("MIR4ZipEntryInventoryV1`n")
    foreach ($row in $sorted) {
      [void]$material.Append([string]$row.path)
      [void]$material.Append("`t")
      [void]$material.Append(([long]$row.bytes).ToString([Globalization.CultureInfo]::InvariantCulture))
      [void]$material.Append("`t")
      [void]$material.Append([string]$row.sha256)
      [void]$material.Append("`n")
    }
    return [pscustomobject][ordered]@{
      entry_count = [int]$sorted.Count
      uncompressed_entry_bytes = $uncompressedBytes
      entry_inventory_sha256 = Get-MIR4Sha256Bytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($material.ToString()))
    }
  } finally {
    $archive.Dispose()
    $fileStream.Dispose()
  }
}

$recordPath = Join-Path $RepoRoot ".mir/releases/waves/mir4-r0/MIR4-Final-Programme-ReconciliationV1.json"
$schemaPath = Join-Path $RepoRoot "spec/schemas/mir4-final-programme-reconciliation.schema.json"
Assert-True (Test-Path -LiteralPath $recordPath -PathType Leaf) "MIR 4 final-programme reconciliation authority is missing."
Assert-True (Test-Path -LiteralPath $schemaPath -PathType Leaf) "MIR 4 final-programme reconciliation schema is missing."
Assert-True ($null -ne (Get-Command Test-Json -ErrorAction SilentlyContinue)) "Test-Json is required for strict MIR 4 reconciliation validation."

$recordText = Get-Content -Raw -LiteralPath $recordPath
Assert-True (Test-AgainstSchema $recordText $schemaPath) "MIR 4 final-programme reconciliation failed its strict schema."
$record = $recordText | ConvertFrom-Json -Depth 100
Assert-True ([string]$record.record_sha256 -ceq (Get-MIR4BootstrapRecordSha256 -Record $record)) "MIR 4 final-programme reconciliation self-hash drifted."

$expectedFiles = [ordered]@{
  "MIR4_M4-003_Offline_Emergency_Lane_Sol_Steer_2026-08-16.md" = [pscustomobject]@{bytes=23576;sha256="0C86DB46EA3836120BBEF4F2621B08FFC95A6BE5CB2BEF62A67E384C1E9A4EE3";media_type="text/markdown";role="emergency-lane-solution-steer";source_status="earlier-input-superseded-by-final-pack";governance_effect="proposal-input-subject-to-decision-disposition"}
  "MIR4_BOUNDED_OPEN_QUESTIONS_FINAL.md" = [pscustomobject]@{bytes=4313;sha256="2533D19EAC0D1646964AD57E5E3C2E4D98E3FD54FEE6CE0CF5E1F1EBADB4F5C1";media_type="text/markdown";role="bounded-open-questions";source_status="bounded-unresolved-input";governance_effect="proposal-input-subject-to-decision-disposition"}
  "MIR4_PACKAGE_VALIDATION_REPORT.md" = [pscustomobject]@{bytes=2040;sha256="1F76EA05DC96CAB053D15BECD4A919C71815191906392692670212669807E539";media_type="text/markdown";role="package-validation-report";source_status="self-reported-package-static-validation-only";governance_effect="proposal-input-subject-to-decision-disposition"}
  "MIR4_SOURCE_RECONCILIATION_FINAL.md" = [pscustomobject]@{bytes=9004;sha256="9E57DB6A3D5DCE339F8C719FCBBD0E076FCA0E695B7E928AB6CB448F3D0E5069";media_type="text/markdown";role="source-reconciliation";source_status="supporting-final-analysis";governance_effect="proposal-input-subject-to-decision-disposition"}
  "MIR4_4.0_ACCEPTANCE_MATRIX_FINAL.json" = [pscustomobject]@{bytes=7028;sha256="89B05EFBA2FBBBCAE5329B7B18CA1C35519ABB8617CF697BA5F800625D240711";media_type="application/json";role="acceptance-matrix";source_status="proposed-final";governance_effect="proposal-input-subject-to-decision-disposition"}
  "MIR4_WORK_PACKAGE_CATALOGUE_FINAL.json" = [pscustomobject]@{bytes=15361;sha256="20DD5A40BE2B26DBCC460CA7A6A26FDB1E1D5F3C2AB790CFDAA1BBC992EF1AED";media_type="application/json";role="work-package-catalogue";source_status="proposed-final";governance_effect="proposal-input-subject-to-decision-disposition"}
  "MIR4_AGENTIC_EXECUTION_PLAN_2026-08-16_TO_2026-08-22_FINAL.json" = [pscustomobject]@{bytes=6074;sha256="D440E8BEEB89974F76FA37B6701B1CF80D44B2D179BFDCCF76F5E8A284A3D194";media_type="application/json";role="agentic-calendar-plan";source_status="proposed-final";governance_effect="proposal-input-subject-to-decision-disposition"}
  "M4-003_OFFLINE_EMERGENCY_LANE_FINAL_SPEC.md" = [pscustomobject]@{bytes=12904;sha256="EB82D145C185E6D458C3A50BB0AAED9CD61BB12BC3D3C8BEA0D95B3D0DE70BB8";media_type="text/markdown";role="emergency-lane-final-specification";source_status="proposed-final";governance_effect="proposal-input-subject-to-decision-disposition"}
  "MIR4_REPOSITORY_ARCHITECTURE_FINAL.md" = [pscustomobject]@{bytes=13289;sha256="73549D9AFA261D8C26ABBBA02FFDF6A7DEF4D57B2D6BF0CB327F623D37E3B00D";media_type="text/markdown";role="repository-architecture";source_status="proposed-final";governance_effect="proposal-input-subject-to-decision-disposition"}
  "MIR4_4.0.0_RELEASE_CONTRACT_FINAL.json" = [pscustomobject]@{bytes=5077;sha256="EEE9C527CCEB2AA33EDB5C297CD75578AFCAA45011BF35721D46E9A43E120AC5";media_type="application/json";role="release-contract";source_status="proposed-final-for-human-acceptance";governance_effect="proposal-input-subject-to-decision-disposition"}
  "MIR4_CONSTITUTION_FINAL.md" = [pscustomobject]@{bytes=10711;sha256="05421F6122A86548E978CDE668F5463F1E38DE1F75D614B427168E43F9B3433F";media_type="text/markdown";role="constitution";source_status="proposed-final-for-human-acceptance";governance_effect="proposal-input-subject-to-decision-disposition"}
  "MIR4_EXECUTIVE_DECISION_BRIEF.md" = [pscustomobject]@{bytes=4598;sha256="8E79A08A3032894204A8FB428141A07DDE85401823E140443262934AB9DE1892";media_type="text/markdown";role="executive-decision-brief";source_status="supporting-final-analysis";governance_effect="proposal-input-subject-to-decision-disposition"}
  "MIR4_ULTIMATE_FINAL_MASTER_SPEC_2026-08-16.md" = [pscustomobject]@{bytes=55714;sha256="8A3F00E41C8C12E57D201D86137A358B0CE7BF08A770C0A1EB53AD30FCD7B098";media_type="text/markdown";role="master-specification";source_status="proposed-final-for-human-acceptance";governance_effect="proposal-input-subject-to-decision-disposition"}
  "pasted-text.txt" = [pscustomobject]@{bytes=14804;sha256="4F0FB4F94F3456E654901E8E2C804D5306084A530698DF2E57B9B8C2ED915D6A";media_type="text/plain";role="pasted-live-state-context";source_status="historical-live-state-context";governance_effect="historical-context-evidence-only"}
}

$actualFiles = @($record.supplied_loose_files)
Assert-True ($actualFiles.Count -eq 14) "Reconciliation must bind 13 programme documents plus one pasted context attachment."
Assert-True ((@($actualFiles.name) -join "|") -ceq (@($expectedFiles.Keys) -join "|")) "Supplied-file authority order or membership drifted."
Assert-True (@($actualFiles | Group-Object name | Where-Object Count -ne 1).Count -eq 0) "Supplied-file bindings must be unique."
foreach ($file in $actualFiles) {
  $expected = $expectedFiles[[string]$file.name]
  Assert-True ($null -ne $expected) "Unexpected supplied file binding: $($file.name)"
  foreach ($property in @("bytes", "sha256", "media_type", "role", "source_status", "governance_effect")) {
    Assert-True ([string]$file.$property -ceq [string]$expected.$property) "Supplied-file $property drifted for $($file.name)."
  }
  Assert-True ($file.embedded_instructions_authorized -eq $false) "Embedded instructions became executable for $($file.name)."
}

$counts = $record.scope.source_counts
Assert-True ([int]$counts.programme_loose_documents -eq 13 -and [int]$counts.pasted_context_attachments -eq 1 -and
  [int]$counts.observed_archives -eq 1 -and [int]$counts.total_bound_sources -eq 15) "Reconciliation source counts are not explicit or complete."
$pasted = @($actualFiles | Where-Object name -ceq "pasted-text.txt")
Assert-True ($pasted.Count -eq 1 -and [string]$pasted[0].governance_effect -ceq "historical-context-evidence-only") "Pasted context was promoted into governing programme instructions."

$archive = $record.observed_archive
Assert-True ([string]$archive.name -ceq "MIR-400.ZIP" -and [long]$archive.bytes -eq 334617 -and
  [string]$archive.sha256 -ceq "E3D9BE3E1DAC8077B0A6792A573BE1B9E1D76BB00B5E6D283CF9DB4B18CBA9A6" -and
  [int]$archive.entry_count -eq 18 -and [long]$archive.uncompressed_entry_bytes -eq 331227 -and
  [string]$archive.entry_inventory_algorithm -ceq "MIR4ZipEntryInventoryV1" -and
  [string]$archive.entry_inventory_canonical_form -ceq "UTF-8 without BOM; MIR4ZipEntryInventoryV1 LF header; ordinal-path-sorted path<TAB>decimal-uncompressed-bytes<TAB>uppercase-entry-SHA256<LF> rows" -and
  [string]$archive.entry_inventory_sha256 -ceq "BF83093A055C10D40830D6F377E82CB98EDF05E1ED2FBD3446E8E0BC1FB5F12D" -and
  [string]$archive.disposition -ceq "observed-older-partial-proposal-archive-not-final-package") "Observed MIR-400 archive identity drifted."

$claim = $record.unavailable_claimed_final_package
Assert-True ([string]$claim.name -ceq "MIR4_ULTIMATE_FINAL_PROGRAMME_PACKAGE_2026-08-16.zip" -and
  [int]$claim.claimed_file_count -eq 106 -and
  [string]$claim.claimed_sha256 -ceq "C8F666FF41FEE0358F537DE04D617CE9EBBDAAFAA916A6FC707E0C04BF2849D6" -and
  [string]$claim.availability -ceq "not-supplied-not-observed" -and $claim.observed_archive_is_substitute -eq $false) "Unavailable 106-file package claim was altered or conflated with MIR-400.ZIP."

$expectedAccepted = @("MIR4-FPR-BOOTSTRAP-FIXED-POINT", "MIR4-FPR-TARGET-SET", "MIR4-FPR-DIRECT-TARGET-CODES", "MIR4-FPR-ONE-SOURCE", "MIR4-FPR-MIR3-SUCCESSION", "MIR4-FPR-REPOSITORY-TIMING", "MIR4-FPR-CALENDAR-NOT-VERSION", "MIR4-FPR-MULTIDIMENSIONAL-SUPPORT", "MIR4-FPR-ENTRY-SEQUENCE", "MIR4-FPR-PROOF-BEFORE-DATE")
$expectedDeferred = @("MIR4-FPR-DEFER-PHYSICAL-MIGRATION", "MIR4-FPR-DEFER-FUTURE-PLATFORM")
$expectedPending = @("MIR4-FPR-PENDING-FORMAL-ADOPTION", "MIR4-FPR-PENDING-SIGNING-CUSTODY", "MIR4-FPR-PENDING-MIR3-EOL", "MIR4-FPR-PENDING-F210-ENGINE", "MIR4-FPR-PENDING-MANUAL-REVIEW", "MIR4-FPR-PENDING-RECORD-PROFILES", "MIR4-FPR-PENDING-ARCHIVE-RIGHTS", "MIR4-FPR-PENDING-PUBLIC-MUTATION")
Assert-True ((@($record.decision_dispositions.accepted_for_bootstrap_implementation.id) -join "|") -ceq ($expectedAccepted -join "|")) "Accepted bootstrap decisions drifted."
Assert-True ((@($record.decision_dispositions.deferred_by_accepted_bootstrap_scope.id) -join "|") -ceq ($expectedDeferred -join "|")) "Accepted bootstrap deferrals drifted."
Assert-True ((@($record.decision_dispositions.pending_human_or_external.id) -join "|") -ceq ($expectedPending -join "|")) "Human/external pending decisions drifted."
$allDecisions = @($record.decision_dispositions.accepted_for_bootstrap_implementation) + @($record.decision_dispositions.deferred_by_accepted_bootstrap_scope) + @($record.decision_dispositions.pending_human_or_external)
Assert-True (@($allDecisions | Group-Object id | Where-Object Count -ne 1).Count -eq 0) "Decision disposition IDs must be unique."
foreach ($decision in $allDecisions) {
  foreach ($sourceName in @($decision.source_names)) {
    Assert-True ($expectedFiles.Contains([string]$sourceName)) "Decision $($decision.id) references an unbound source: $sourceName"
  }
}
Assert-True (@($record.decision_dispositions.accepted_for_bootstrap_implementation.source_names | Where-Object { $_ -contains "pasted-text.txt" }).Count -eq 0) "Historical pasted context became an accepted-decision authority."

$falseBoundaryProperties = @("document_commands_authorized", "source_version_allocated", "distribution_versions_allocated", "tags_authorized", "package_construction_authorized", "publication_authorized", "production_signing_authorized", "release_claim_permitted", "package_validation_report_is_live_repository_evidence", "observed_archive_substitutes_for_claimed_final_package")
foreach ($property in $falseBoundaryProperties) {
  Assert-True ($record.boundaries.$property -eq $false) "Reconciliation widened forbidden boundary: $property"
}
Assert-True ($record.scope.embedded_document_instructions_are_commands -eq $false -and $record.scope.public_version_allocation -eq $false) "Reconciliation converted document prose into commands or public allocation."

# Prove that the schema rejects authority expansion rather than silently ignoring it.
$unexpected = $recordText | ConvertFrom-Json -Depth 100
$unexpected | Add-Member -NotePropertyName unexpected_authority -NotePropertyValue $true
Assert-True (-not (Test-AgainstSchema (ConvertTo-MIR4BootstrapCanonicalJson -Value $unexpected) $schemaPath)) "Strict reconciliation schema admitted an unexpected top-level authority."
$allocated = $recordText | ConvertFrom-Json -Depth 100
$allocated.boundaries.source_version_allocated = $true
Assert-True (-not (Test-AgainstSchema (ConvertTo-MIR4BootstrapCanonicalJson -Value $allocated) $schemaPath)) "Strict reconciliation schema admitted public source-version allocation."
$executable = $recordText | ConvertFrom-Json -Depth 100
$executable.supplied_loose_files[0].embedded_instructions_authorized = $true
Assert-True (-not (Test-AgainstSchema (ConvertTo-MIR4BootstrapCanonicalJson -Value $executable) $schemaPath)) "Strict reconciliation schema admitted embedded document instructions as commands."

# External bytes are optional verification inputs, never implicit CI dependencies.
if (-not [string]::IsNullOrWhiteSpace($SuppliedRoot)) {
  $resolvedSuppliedRoot = (Resolve-Path -LiteralPath $SuppliedRoot).Path
  foreach ($file in @($actualFiles | Where-Object name -cne "pasted-text.txt")) {
    $path = Join-Path $resolvedSuppliedRoot ([string]$file.name)
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Supplied programme file is missing: $path"
    Assert-True ([long](Get-Item -LiteralPath $path).Length -eq [long]$file.bytes -and (Get-MIR4Sha256File -Path $path) -ceq [string]$file.sha256) "Supplied programme file bytes drifted: $($file.name)"
  }
  $archivePath = Join-Path $resolvedSuppliedRoot ([string]$archive.name)
  Assert-True (Test-Path -LiteralPath $archivePath -PathType Leaf) "Observed MIR-400.ZIP is missing."
  Assert-True ([long](Get-Item -LiteralPath $archivePath).Length -eq [long]$archive.bytes -and (Get-MIR4Sha256File -Path $archivePath) -ceq [string]$archive.sha256) "Observed MIR-400.ZIP bytes drifted."
  $inventory = Get-ZipEntryInventory $archivePath
  Assert-True ([int]$inventory.entry_count -eq [int]$archive.entry_count -and [long]$inventory.uncompressed_entry_bytes -eq [long]$archive.uncompressed_entry_bytes -and
    [string]$inventory.entry_inventory_sha256 -ceq [string]$archive.entry_inventory_sha256) "Observed MIR-400.ZIP entry inventory drifted."
}
if (-not [string]::IsNullOrWhiteSpace($PastedAttachmentPath)) {
  $resolvedPastedPath = (Resolve-Path -LiteralPath $PastedAttachmentPath).Path
  Assert-True ([long](Get-Item -LiteralPath $resolvedPastedPath).Length -eq [long]$pasted[0].bytes -and
    (Get-MIR4Sha256File -Path $resolvedPastedPath) -ceq [string]$pasted[0].sha256) "Pasted live-state context bytes drifted."
}

Write-Host "[ok] MIR 4 final programme reconciliation binds 13 proposal documents, one historical pasted context, and one observed 18-entry archive without allocating or publishing 4.x"
