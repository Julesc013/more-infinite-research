# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
$writer = Join-Path $repo 'tools/commands/mir4/Update-MIR4CurrentPackagePresentationV5Authority.ps1'

$record = Get-MIR4CurrentPackagePresentationV5 -RepoRoot $repo
Assert-MIR4CurrentPackagePresentationV5LiveFingerprint -RepoRoot $repo -StoredPackageSourceSha256 ([string]$record.package_source.fingerprint_sha256) -RequiredPackageSourceSha256 (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo) | Out-Null
$proof = Invoke-MIR4CurrentSourceMaterializerProof -RepoRoot $repo -OutputRoot 'build/packages' -ReportPath 'build/reports/package-source/mir4-package-presentation-v5-materialization.json'
foreach ($target in @('f210','f200','f110','f100')) {
  $stored = @($record.target_content_identities | Where-Object { [string]$_.target -ceq $target })
  $actual = @($proof.targets | Where-Object { [string]$_.target -ceq $target })
  if ($stored.Count -ne 1 -or $actual.Count -ne 1 -or [string]$stored[0].content_sha256 -cne [string]$actual[0].content_sha256 -or [int]$stored[0].entry_count -ne [int]$actual[0].entry_count -or -not [bool]$actual[0].deterministic_archive_bytes) { throw "[mir4-package-presentation-v5-materialization] $target" }
}
foreach ($mutation in @(
  @{id='unknown'; mutate={param($r) $r | Add-Member -NotePropertyName unauthorized_gate -NotePropertyValue $true}},
  @{id='v4'; mutate={param($r) $r.predecessor.immutable_historical_receipt=$false}},
  @{id='custody'; mutate={param($r) $r.historical_custody.reviewed_successor.promotion_custody_revalidation_required=$false}},
  @{id='omission'; mutate={param($r) (@($r.target_content_identities | Where-Object target -ceq 'f110'))[0].capability_state='applied'}},
  @{id='gate'; mutate={param($r) $r.transition_gate.publication=$true}}
)) {
  $copy = $record | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  & $mutation.mutate $copy
  $copy.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $copy
  if (Test-MIR4CurrentPackagePresentationV5Schema -Record $copy -RepoRoot $repo) { throw "[mir4-package-presentation-v5-tamper] $($mutation.id)" }
}
$scratch = Join-Path $repo ('build/mir4/test-package-presentation-v5-' + [guid]::NewGuid().ToString('N') + '.json')
$stale = $false
try { & $writer -RepoRoot $repo -Check -CheckAuthorityPath $scratch | Out-Null } catch { $stale = $_.Exception.Message -eq '[mir4-package-presentation-v5-stale]' }
if (-not $stale -or (Test-Path -LiteralPath $scratch)) { throw '[mir4-package-presentation-v5-check-isolation]' }
$immutable = $false
try { & $writer -RepoRoot $repo -RecordedAt '2026-09-16T12:01:00+10:00' | Out-Null } catch { $immutable = $_.Exception.Message -eq '[mir4-package-presentation-v5-authority-immutable-overwrite]' }
if (-not $immutable) { throw '[mir4-package-presentation-v5-overwrite]' }
Write-Host '[ok] MIR4 package presentation V5 preserves V4 and binds the progression successor with pending exact-engine qualification.'
