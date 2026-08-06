param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")

function Assert-MIRFreezeFileBinding {
  param([Parameter(Mandatory)]$Binding)
  $relative = [string]$Binding.path
  $path = Join-Path $repo $relative
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Source-freeze authority is missing: $relative"
  }
  $actual = Get-MIRFileContentSha256 -Path $path -RelativePath $relative
  if ($actual -ne [string]$Binding.sha256) {
    throw "Source-freeze authority hash changed: $relative"
  }
}

$packetPath = Join-Path $repo ".mir/releases/freezes/3.2.5-D1.json"
if (-not (Test-Path -LiteralPath $packetPath -PathType Leaf)) {
  throw "MIR 3.2.5 source-freeze packet is missing."
}
$packet = Get-Content -Raw -LiteralPath $packetPath | ConvertFrom-Json
if ([int]$packet.schema -ne 1 -or [string]$packet.kind -ne "mir-source-freeze-packet" -or
    [string]$packet.release -ne "3.2.5" -or [string]$packet.candidate_floor -ne "C32" -or
    [string]$packet.status -notin @("prepared", "admitted")) {
  throw "MIR 3.2.5 source-freeze packet identity is invalid."
}

$sourceCommit = [string]$packet.source.package_source_commit
if ($sourceCommit -notmatch '^[0-9a-f]{40}$') { throw "Source-freeze package commit is invalid." }
& git -C $repo cat-file -e "$sourceCommit^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { throw "Source-freeze package commit is unavailable." }
$sourceTree = (& git -C $repo show -s --format=%T $sourceCommit).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceTree -ne [string]$packet.source.package_source_tree) {
  throw "Source-freeze package source tree is stale."
}
$sourceHash = Get-MIRPackageSourceFingerprint -RepoRoot $repo
if ($sourceHash -ne [string]$packet.source.package_source_sha256 -or
    $sourceHash -ne [string]$packet.package_contract.expected.content_sha256) {
  throw "Current package roots differ from the source-freeze identity."
}
if ((Get-MIRPackageSourceFiles -RepoRoot $repo).Count -ne [int]$packet.package_contract.package_file_count -or
    [int]$packet.package_contract.expected.entries -ne [int]$packet.package_contract.package_file_count) {
  throw "Source-freeze package composition count is stale."
}

$tagCommit = (& git -C $repo rev-parse "$($packet.lineage.public_predecessor.tag)^{commit}").Trim()
$tagObject = (& git -C $repo rev-parse "$($packet.lineage.public_predecessor.tag)^{tag}").Trim()
if ($LASTEXITCODE -ne 0 -or $tagCommit -ne [string]$packet.lineage.public_predecessor.tag_commit -or
    $tagObject -ne [string]$packet.lineage.public_predecessor.tag_object) {
  throw "Public predecessor tag identity is stale."
}
foreach ($lineageArchive in @($packet.lineage.public_predecessor, $packet.lineage.superseded_checkpoint)) {
  $archivePath = Join-Path $repo ([string]$lineageArchive.archive)
  if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne [string]$lineageArchive.archive_sha256) {
    throw "Frozen lineage archive is missing or changed: $($lineageArchive.archive)"
  }
}
$closure = Get-Content -Raw -LiteralPath (Join-Path $repo ([string]$packet.lineage.superseded_checkpoint.closure)) | ConvertFrom-Json
if ([string]$closure.disposition -ne "superseded-unpublished" -or [string]$closure.successor.release -ne "3.2.5") {
  throw "C31 is not preserved as superseded-unpublished lineage."
}

foreach ($binding in @($packet.product_contract.authorities) + @($packet.qualification_authority.authorities) + @($packet.documentation.authorities)) {
  Assert-MIRFreezeFileBinding -Binding $binding
}
Assert-MIRFreezeFileBinding -Binding $packet.package_contract.builder
Assert-MIRFreezeFileBinding -Binding $packet.package_contract.identity_implementation
if (@($packet.product_contract.factorio_2_0_dispositions).Count -ne 9 -or
    @($packet.product_contract.factorio_2_0_dispositions | Where-Object {
      [string]$_.classification -notin @(
        "portable-identical", "portable-with-adapter", "target-native-equivalent",
        "omitted-by-capability", "target-specific", "tooling-only", "unsupported-with-evidence"
      )
    }).Count -ne 0) {
  throw "Shipped-feature Factorio 2.0 dispositions are incomplete."
}

$gateProperties = @($packet.gate.PSObject.Properties)
if ($gateProperties.Count -eq 0 -or @($gateProperties | Where-Object { [string]$_.Value -ne "passed" }).Count -ne 0) {
  throw "Source-freeze gate is incomplete."
}
if ([string]$packet.boundaries.factorio_2_0_release_authority -ne "not-created" -or
    [string]$packet.boundaries.mir_3_3_admission -ne "not-admitted" -or
    [string]$packet.boundaries.main -ne "untouched" -or
    [string]$packet.boundaries.publication -ne "forbidden-before-go-no-go") {
  throw "Source-freeze packet widened a forbidden release boundary."
}

$release = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir/releases/records/3.2.5.json") | ConvertFrom-Json
if ([string]$packet.status -eq "prepared") {
  if ([string]$packet.candidate_id -ne "not-assigned" -or [string]$release.state -ne "planned") {
    throw "A prepared D1 packet must not assign the candidate or advance the release."
  }
} else {
  if ([string]$packet.candidate_id -ne "C32" -or [string]$release.candidate_id -ne "C32" -or
      [string]$release.state -notin @(
        "source-frozen", "package-built", "focused-qualified", "candidate-qualified",
        "manually-accepted", "protected-qualified", "sealed", "promoted", "tagged",
        "published", "publicly-verified"
      )) {
    throw "An admitted D1 packet must bind exact candidate C32 and a valid post-planning state."
  }
  if ([string]$packet.qualification_authority.source_bound_plan.plan_material_sha256 -notmatch '^[A-F0-9]{64}$' -or
      [string]$packet.qualification_authority.source_bound_plan.required_test_set_sha256 -notmatch '^[A-F0-9]{64}$') {
    throw "Admitted D1 packet lacks the exact source-bound plan identity."
  }
}

Write-Host "[ok] MIR 3.2.5 D1 freezes exact lineage, product, package, transition, qualification, and documentation authorities without widening release scope."
