# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')

$writer = Join-Path $repo 'tools/commands/mir4/Update-MIR4CurrentPackagePresentationV3Authority.ps1'
$before = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$scratch = Join-Path $repo ('build/mir4/test-package-presentation-v3-' + [guid]::NewGuid().ToString('N') + '.json')
$staleRejected = $false
try { & $writer -RepoRoot $repo -Check -CheckAuthorityPath $scratch | Out-Null } catch { $staleRejected = $_.Exception.Message -eq '[mir4-package-presentation-v3-stale]' }
if (-not $staleRejected -or (Test-Path -LiteralPath $scratch)) { throw '[mir4-package-presentation-v3-check-isolation]' }

& $writer -RepoRoot $repo -Check | Out-Null
$v3 = Get-MIR4CurrentPackagePresentationV3 -RepoRoot $repo
Assert-MIR4CurrentPackagePresentationV3 -RepoRoot $repo -PackageSourceSha256 $before | Out-Null
if (
  [string]$v3.predecessor.record_sha256 -cne (Get-MIR4CurrentPackagePresentationV2 -RepoRoot $repo).record_sha256 -or
  [string]$v3.source_manifest.path -cne 'source/package-source.json' -or
  (@($v3.package_source.roots) -join '|') -cne 'source|targets' -or
  [string]$v3.package_source.fingerprint_sha256 -cne $before -or
  [string]$v3.package_authority.record_sha256 -cne (Get-MIR4CanonicalPackageAuthority -RepoRoot $repo).record_sha256 -or
  -not (Test-MIR4BootstrapRecordHash -Record $v3)
) { throw '[mir4-package-presentation-v3-current-source]' }

foreach ($mutation in @(
  @{id='unknown'; mutate={param($r) $r | Add-Member -NotePropertyName unauthorized_gate -NotePropertyValue $true}},
  @{id='root'; mutate={param($r) $r.package_source.roots=@('src/mod','targets')}},
  @{id='gate'; mutate={param($r) $r.transition_gate.publication=$true}},
  @{id='required'; mutate={param($r) [void]$r.PSObject.Properties.Remove('source_manifest')}}
)) {
  $copy = $v3 | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  & $mutation.mutate $copy
  $copy.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $copy
  if (Test-MIR4CurrentPackagePresentationV3Schema -Record $copy -RepoRoot $repo) { throw "[mir4-package-presentation-v3-tamper] $($mutation.id)" }
}

$immutableRejected = $false
try { & $writer -RepoRoot $repo -RecordedAt '2026-09-15T15:00:01+10:00' | Out-Null } catch { $immutableRejected = $_.Exception.Message -eq '[mir4-package-presentation-v3-authority-immutable-overwrite]' }
if (-not $immutableRejected) { throw '[mir4-package-presentation-v3-overwrite]' }
Write-Host '[ok] MIR4 package presentation V3 is source/composition-bound and V2 remains frozen.'
