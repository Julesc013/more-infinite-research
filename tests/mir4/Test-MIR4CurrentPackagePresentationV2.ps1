# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')

$authorityPath = Join-Path $repo 'spec/distribution/mir4-current-package-presentation-v2.json'
$schemaPath = Join-Path $repo 'spec/schemas/mir4-current-package-presentation-v2.schema.json'
$writer = Join-Path $repo 'tools/commands/mir4/Update-MIR4CurrentPackagePresentationV2Authority.ps1'
$raw = Get-Content -Raw -LiteralPath $authorityPath
if (-not ($raw | Test-Json -SchemaFile $schemaPath)) { throw '[mir4-package-presentation-v2-schema]' }
$v2 = $raw | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4CurrentPackagePresentationV2Record -Record $v2

if (
  -not (Test-MIR4BootstrapRecordHash -Record $v2) -or
  [string]$v2.record_sha256 -cne 'C33F1B568CA247108D88C4F2A109C45E29F2C77C4EE026CB4C9047BAA3A2360F' -or
  [string]$v2.package_source.fingerprint_sha256 -cne '2BE9A0C5510F6369DBE239746BB525F77952DC5E64C0C0D2DCD9E002B059779E'
) { throw '[mir4-package-presentation-v2-historical-identity]' }

$current = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
if ($current -ceq [string]$v2.package_source.fingerprint_sha256) {
  throw '[mir4-package-presentation-v2-unexpected-current-identity]'
}

$historicalReaderRejectedCurrent = $false
try {
  Assert-MIR4CurrentPackagePresentationV2 -RepoRoot $repo -PackageSourceSha256 $current | Out-Null
} catch {
  $historicalReaderRejectedCurrent = $_.Exception.Message -match '\[mir4-package-presentation-v2-binding\]|\[mir4-package-presentation-v2-live-fingerprint\]'
}
if (-not $historicalReaderRejectedCurrent) { throw '[mir4-package-presentation-v2-accepted-current-drift]' }

$historicalWriterRejectedCurrent = $false
try {
  & $writer -RepoRoot $repo -Check | Out-Null
} catch {
  $historicalWriterRejectedCurrent = $_.Exception.Message -match '\[mir4-package-presentation-v2-bindings\]|\[mir4-package-presentation-v2-stale\]'
}
if (-not $historicalWriterRejectedCurrent) { throw '[mir4-package-presentation-v2-writer-advanced-history]' }

$tampered = $v2 | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$tampered.package_source.fingerprint_sha256 = '0' * 64
$tampered.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $tampered
$tamperRejected = $false
try { Assert-MIR4CurrentPackagePresentationV2Record -Record $tampered | Out-Null } catch { $tamperRejected = $true }
if (-not $tamperRejected) { throw '[mir4-package-presentation-v2-historical-tamper]' }

Write-Host '[ok] MIR4 current package presentation V2 remains immutable historical authority and rejects current-source advancement.'
