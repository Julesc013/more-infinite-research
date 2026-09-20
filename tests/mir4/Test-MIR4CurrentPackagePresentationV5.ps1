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

$record = Get-MIR4CurrentPackagePresentationV5Historical -RepoRoot $repo
if ([string]$record.record_sha256 -cne 'D2C73297B4A7BA404B13EEC0AB29C5CDE56357F04ED4B48C9B1099F2F2DA7470') { throw '[mir4-package-presentation-v5-historical-identity]' }
$contract = Assert-MIR4CurrentPackageContract -RepoRoot $repo -RequiredPackageSourceSha256 (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)
$proof = Invoke-MIR4CurrentSourceMaterializerProof -RepoRoot $repo -OutputRoot 'build/packages' -ReportPath 'build/reports/package-source/mir4-package-presentation-v5-materialization.json'
foreach ($target in @('f210','f200','f110','f100')) {
  $actual = @($proof.targets | Where-Object { [string]$_.target -ceq $target })
  $current = @($contract.targets | Where-Object { [string]$_.target -ceq $target })
  if ($actual.Count -ne 1 -or $current.Count -ne 1 -or -not [bool]$actual[0].deterministic_archive_bytes -or -not [bool]$current[0].exact_engine_qualification_required) { throw "[mir4-package-presentation-v5-materialization] $target" }
}
$sourceDriftRoot=Join-Path ([IO.Path]::GetTempPath()) ('mir-v5-current-contract-source-drift-'+[guid]::NewGuid().ToString('N'))
try {
  $sourceCommit=(& git -C $repo rev-parse HEAD).Trim()
  if($LASTEXITCODE-ne0-or$sourceCommit-cnotmatch'^[0-9a-f]{40}$'){throw '[mir4-package-presentation-v5-source-drift-commit]'}
  & git clone --quiet --shared --no-checkout $repo $sourceDriftRoot
  if($LASTEXITCODE-ne0){throw '[mir4-package-presentation-v5-source-drift-clone]'}
  & git -C $sourceDriftRoot config core.autocrlf false
  if($LASTEXITCODE-ne0){throw '[mir4-package-presentation-v5-source-drift-line-endings]'}
  & git -C $sourceDriftRoot checkout --quiet --detach $sourceCommit
  if($LASTEXITCODE-ne0){throw '[mir4-package-presentation-v5-source-drift-checkout]'}
  $sourceManifest=Get-Content -Raw -LiteralPath (Join-Path $sourceDriftRoot 'source/package-source.json')|ConvertFrom-Json -Depth 100 -DateKind String
  $sourcePath=Join-Path $sourceDriftRoot ([string]$sourceManifest.bindings[0].source_path)
  [IO.File]::AppendAllText($sourcePath,"`n-- isolated current-package source drift probe`n",[Text.UTF8Encoding]::new($false))
  . (Join-Path $sourceDriftRoot 'tools/lib/mir4/PackagePresentation.ps1')
  $sourceDriftRejected=$false
  try { Assert-MIR4CurrentPackageContract -RepoRoot $sourceDriftRoot|Out-Null } catch { $sourceDriftRejected=$_.Exception.Message-match'mir4-source-refresh-stale' }
  if(-not$sourceDriftRejected){throw '[mir4-package-presentation-v5-source-drift-admitted]'}
} finally {
  if(Test-Path -LiteralPath $sourceDriftRoot){Remove-Item -LiteralPath $sourceDriftRoot -Recurse -Force}
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
Write-Host '[ok] MIR4 historical package presentation V5 is immutable and current package development uses the independent live contract.'
