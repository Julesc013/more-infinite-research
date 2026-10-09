# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
$writer = Join-Path $repo 'tools/commands/mir4/Update-MIR4CurrentPackagePresentationV6Authority.ps1'

$v5 = Get-MIR4CurrentPackagePresentationV5 -RepoRoot $repo
if ([string]$v5.record_sha256 -cne 'D2C73297B4A7BA404B13EEC0AB29C5CDE56357F04ED4B48C9B1099F2F2DA7470' -or [string]$v5.package_source.fingerprint_sha256 -cne 'A476DDAFA5AB62BD6AEC69054E1A162C570DDB946520AF9234FC8FE0D79BEC2F') { throw '[mir4-package-presentation-v6-v5-history]' }
$v5Canonical = (ConvertTo-MIR4BootstrapCanonicalJson -Value $v5) + [char]10
$v5CrLf = $v5Canonical.Replace("`n", "`r`n")
$v5CrOnly = $v5Canonical.Replace("`n", "`r")
if (-not (Test-MIR4PackagePresentationCanonicalText -Raw $v5Canonical -Record $v5) -or
    -not (Test-MIR4PackagePresentationCanonicalText -Raw $v5CrLf -Record $v5) -or
    (Test-MIR4PackagePresentationCanonicalText -Raw $v5CrOnly -Record $v5) -or
    (Test-MIR4PackagePresentationCanonicalText -Raw ($v5Canonical + ' ') -Record $v5) -or
    (Test-MIR4PackagePresentationCanonicalText -Raw ([char]0xFEFF + $v5Canonical) -Record $v5)) {
  throw '[mir4-package-presentation-v6-cross-host-canonical-text]'
}
$textScratchRoot = Join-Path $repo 'build/mir4'
New-Item -ItemType Directory -Path $textScratchRoot -Force | Out-Null
$textScratch = Join-Path $textScratchRoot ('test-package-presentation-text-' + [guid]::NewGuid().ToString('N') + '.json')
try {
  $utf8 = [Text.UTF8Encoding]::new($false)
  [IO.File]::WriteAllBytes($textScratch, $utf8.GetBytes($v5Canonical))
  $diskLf = Read-MIR4PackagePresentationCanonicalText -Path $textScratch
  if (-not (Test-MIR4PackagePresentationCanonicalText -Raw $diskLf -Record $v5)) { throw '[mir4-package-presentation-v6-disk-lf]' }

  [IO.File]::WriteAllBytes($textScratch, $utf8.GetBytes($v5CrLf))
  $diskCrLf = Read-MIR4PackagePresentationCanonicalText -Path $textScratch
  if (-not (Test-MIR4PackagePresentationCanonicalText -Raw $diskCrLf -Record $v5)) { throw '[mir4-package-presentation-v6-disk-crlf]' }

  [IO.File]::WriteAllBytes($textScratch, $utf8.GetBytes($v5CrOnly))
  $diskCrOnly = Read-MIR4PackagePresentationCanonicalText -Path $textScratch
  if (Test-MIR4PackagePresentationCanonicalText -Raw $diskCrOnly -Record $v5) { throw '[mir4-package-presentation-v6-disk-cr-only-accepted]' }

  [IO.File]::WriteAllBytes($textScratch, $utf8.GetBytes($v5Canonical + ' '))
  $diskWhitespace = Read-MIR4PackagePresentationCanonicalText -Path $textScratch
  if (Test-MIR4PackagePresentationCanonicalText -Raw $diskWhitespace -Record $v5) { throw '[mir4-package-presentation-v6-disk-whitespace-accepted]' }

  $changedContent = $v5Canonical.Replace('"schema":1', '"schema":2')
  [IO.File]::WriteAllBytes($textScratch, $utf8.GetBytes($changedContent))
  $diskContent = Read-MIR4PackagePresentationCanonicalText -Path $textScratch
  if (Test-MIR4PackagePresentationCanonicalText -Raw $diskContent -Record $v5) { throw '[mir4-package-presentation-v6-disk-content-change-accepted]' }

  $bom = [byte[]](@(0xEF, 0xBB, 0xBF) + @($utf8.GetBytes($v5Canonical)))
  [IO.File]::WriteAllBytes($textScratch, $bom)
  $bomRejected = $false
  try { Read-MIR4PackagePresentationCanonicalText -Path $textScratch | Out-Null } catch { $bomRejected = $_.Exception.Message.StartsWith('[mir4-package-presentation-text-bom]', [StringComparison]::Ordinal) }
  if (-not $bomRejected) { throw '[mir4-package-presentation-v6-disk-bom-accepted]' }

  [IO.File]::WriteAllBytes($textScratch, [byte[]](0xC3, 0x28))
  $utf8Rejected = $false
  try { Read-MIR4PackagePresentationCanonicalText -Path $textScratch | Out-Null } catch { $utf8Rejected = $_.Exception.Message.StartsWith('[mir4-package-presentation-text-utf8]', [StringComparison]::Ordinal) }
  if (-not $utf8Rejected) { throw '[mir4-package-presentation-v6-disk-invalid-utf8-accepted]' }
} finally {
  if (Test-Path -LiteralPath $textScratch) { Remove-Item -LiteralPath $textScratch -Force }
}
$record = Get-MIR4CurrentPackagePresentationV6Historical -RepoRoot $repo
$current = Get-MIR4CurrentPackagePresentationV7 -RepoRoot $repo
if ([string]$current.predecessor.record_sha256 -cne [string]$record.record_sha256 -or
    [string]$current.source_succession.predecessor_record_sha256 -cne [string]$record.source_manifest.record_sha256 -or
    [string]$record.source_manifest.kind -cne 'MIR4ComposablePackageSourceV2') { throw '[mir4-package-presentation-v6-successor-binding]' }
$coverage = @($record.localization.target_locale_coverage | ForEach-Object { "$($_.target):$($_.locale_count)" }) -join '|'
if ([int]$record.localization.governed_locale_count -ne 50 -or [int]$record.localization.browser_discovery_key_count -ne 29 -or -not [bool]$record.localization.all_governed_locales_complete -or -not [bool]$record.localization.package_visible_locale_coverage_bound -or -not [bool]$record.authority_invariants.current_package_contract_bound -or $coverage -cne 'f210:50|f200:50|f110:9|f100:9') { throw '[mir4-package-presentation-v6-localization-completion]' }
foreach ($mutation in @(
  @{id='unknown'; mutate={param($r) $r | Add-Member -NotePropertyName unauthorized_gate -NotePropertyValue $true}},
  @{id='predecessor'; mutate={param($r) $r.predecessor.immutable_historical_receipt=$false}},
  @{id='locale'; mutate={param($r) $r.localization.governed_locale_count=49}},
  @{id='content'; mutate={param($r) $r.target_content_identities[0].progression_capability_state='omitted-nonclaim'}},
  @{id='gate'; mutate={param($r) $r.transition_gate.publication=$true}}
)) {
  $copy = $record | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  & $mutation.mutate $copy
  $copy.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $copy
  if (Test-MIR4CurrentPackagePresentationV6Schema -Record $copy -RepoRoot $repo) { throw "[mir4-package-presentation-v6-tamper] $($mutation.id)" }
}
$scratch = Join-Path $repo ('build/mir4/test-package-presentation-v6-' + [guid]::NewGuid().ToString('N') + '.json')
$stale = $false
try { & $writer -RepoRoot $repo -AuthorityVersion 6 -Check -CheckAuthorityPath $scratch | Out-Null } catch { $stale = $_.Exception.Message -eq '[mir4-package-presentation-v6-stale]' }
if (-not $stale -or (Test-Path -LiteralPath $scratch)) { throw '[mir4-package-presentation-v6-check-isolation]' }
$immutable = $false
try { & $writer -RepoRoot $repo -AuthorityVersion 6 -RecordedAt '2026-09-16T12:31:00+10:00' | Out-Null } catch { $immutable = $_.Exception.Message -eq '[mir4-package-presentation-v6-authority-immutable-overwrite]' }
if (-not $immutable) { throw '[mir4-package-presentation-v6-overwrite]' }
Write-Host '[ok] MIR4 package presentation V6 remains an immutable historical predecessor of current V7.'
