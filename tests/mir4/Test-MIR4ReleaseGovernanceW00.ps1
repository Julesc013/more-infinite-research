# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/ReleaseGovernance.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')

$authority = Test-MIR4ReleaseGovernanceAuthority -RepoRoot $RepoRoot
if ([string]$authority.state -cne 'BLOCKED-HUMAN-SECRET-INPUT' -or [string]$authority.acceptance -cne 'BLOCKED') {
  throw '[mir4-w00-blocker] The current secret-input blocker was not represented honestly.'
}
if (@($authority.blocked_subtasks).Count -ne 3) { throw '[mir4-w00-blocker-set] Expected three key-dependent blockers.' }
if ([string]$authority.signing_ceremony_preparation.state -cne 'MACHINE-PREPARATION-COMPLETE-HUMAN-CEREMONY-REQUIRED' -or
    [bool]$authority.signing_ceremony_preparation.production_signing_authorized -or
    [bool]$authority.signing_ceremony_preparation.protected_roots_configured -or
    [bool]$authority.signing_ceremony_preparation.protected_secret_authority_available -or
    [bool]$authority.signing_ceremony_preparation.maintainer_acceptance_present) {
  throw '[mir4-w00-signing-ceremony-preparation] Machine preparation must not cross the protected signing gate.'
}
if ([string]$authority.archive.environment_variable -cne 'MIR_ARCHIVE_HOME' -or
    [string]$authority.publisher.environment_variable -cne 'MIR_PUBLISHER_HOME') {
  throw '[mir4-w00-logical-roots] Release custody must use logical environment roots.'
}

$rootFixture = Join-Path ([IO.Path]::GetTempPath()) ('mir4-w00-roots-' + [guid]::NewGuid().ToString('N'))
$archiveFixture = Join-Path $rootFixture 'archive'
$publisherRootFixture = Join-Path $rootFixture 'publisher'
try {
  foreach ($path in @($archiveFixture, $publisherRootFixture)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
  $resolved = Get-MIR4ReleaseGovernanceReadiness -RepoRoot $RepoRoot -ArchiveHome $archiveFixture -PublisherHome $publisherRootFixture
  if ([string]$resolved.archive.resolution_source -cne 'explicit-parameter' -or
      [string]$resolved.publisher.resolution_source -cne 'explicit-parameter') {
    throw '[mir4-w00-explicit-root-resolution]'
  }
} finally {
  if (Test-Path -LiteralPath $rootFixture) { Remove-Item -LiteralPath $rootFixture -Recurse -Force }
}

$ledgerSchema = Join-Path $RepoRoot 'spec/schemas/mir4-release-ledger-event.schema.json'
$revocationSchema = Join-Path $RepoRoot 'spec/schemas/mir4-key-revocation.schema.json'
foreach ($schema in @($ledgerSchema, $revocationSchema)) {
  Get-Content -Raw -LiteralPath $schema | ConvertFrom-Json | Out-Null
}
$event = [ordered]@{
  schema=1;kind='MIR4ReleaseLedgerEventV1';event_id='MIR4-LEDGER-20260822T000000Z-INTENT';event_kind='ReleaseIntent';occurred_at='2026-08-22T00:00:00Z';subject='M4C02-09-24H';predecessor_event_sha256=$null;payload_sha256=('a'*64);signing_namespace='mir4-ledger';signer_fingerprint='SHA256:example-public-fixture'
}
if (-not (($event | ConvertTo-Json -Depth 10) | Test-Json -SchemaFile $ledgerSchema)) { throw '[mir4-w00-ledger-schema]' }

$publisherFixture = Join-Path ([IO.Path]::GetTempPath()) ('mir4-w00-publisher-' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Force -Path (Join-Path $publisherFixture 'public-release-records') | Out-Null
  $clean = Test-MIR4PublisherInventory -PublisherHome $publisherFixture
  if (@($clean.forbidden).Count -ne 0) { throw '[mir4-w00-publisher-clean-fixture]' }
  New-Item -ItemType Directory -Force -Path (Join-Path $publisherFixture '.git') | Out-Null
  $dirty = Test-MIR4PublisherInventory -PublisherHome $publisherFixture
  if ('.git' -notin @($dirty.forbidden)) { throw '[mir4-w00-publisher-forbidden-fixture]' }
} finally {
  if (Test-Path -LiteralPath $publisherFixture) { Remove-Item -LiteralPath $publisherFixture -Recurse -Force }
}

$packageFiles = @(Get-MIRPackageSourceFiles -RepoRoot $RepoRoot)
foreach ($path in @(
  '.mir/releases/governance/mir4/release-governance.json',
  '.mir/releases/governance/mir4/allowed-signers.json',
  '.mir/releases/governance/mir4/signing-ceremony-preparation.json',
  'spec/schemas/mir4-signing-ceremony-preparation-authority-v1.schema.json',
  'spec/schemas/mir4-signing-ceremony-preparation-receipt-v1.schema.json',
  'spec/schemas/mir4-protected-signing-ceremony-receipt-v1.schema.json',
  'spec/templates/mir4-protected-signing-ceremony-receipt-v1.template.json',
  'spec/schemas/mir4-release-ledger-event.schema.json',
  'spec/schemas/mir4-key-revocation.schema.json',
  'tools/lib/mir4/ReleaseGovernance.ps1',
  'tools/lib/mir4/SigningCeremonyPreparation.ps1',
  'tools/commands/mir4/Invoke-MIR4ReleaseGovernance.ps1',
  'tools/commands/mir4/Invoke-MIR4SigningCeremonyPreparation.ps1',
  'docs/maintainer/mir4-release-governance.md'
)) {
  if ($path -in $packageFiles) { throw "[mir4-w00-package-visible] $path" }
}

Write-Host '[ok] MIR 4 W00 release-governance contracts passed; protected signing remains BLOCKED-HUMAN-SECRET-INPUT.'
