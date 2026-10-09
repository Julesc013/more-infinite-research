# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
$writer = Join-Path $repo 'tools/commands/mir4/Update-MIR4CurrentPackagePresentationV4Authority.ps1'

$record = Get-MIR4CurrentPackagePresentationV4 -RepoRoot $repo
if ([string]$record.predecessor.record_sha256 -cne '0E66F8BD58371E54BF3783200A73423703BCC539D9538526D1BEABA05C494790' -or
    [string]$record.factorio_one_convergence.receipt.record_sha256 -cne '9821BD60F0E36F32DA9888477CD8F48674A5A0601AA16D06CF396266AD02AB47' -or
    [string]$record.factorio_one_convergence.factorio_two_executable_content_proof.record_sha256 -cne 'F7192DC6BFBF6A21B24CC24922189B376381532B9694E6143DDBAB350D0938D9' -or
    [string]$record.factorio_one_convergence.factorio_two_executable_content_proof.baseline_revision -cne '297aa5cc902da96847165a4f9caa1048608839fb' -or
    -not [bool]$record.authority_invariants.factorio_two_executable_content_preserved -or
    -not [bool]$record.authority_invariants.factorio_one_exact_engine_proof_required) { throw '[mir4-package-presentation-v4-binding]' }

foreach ($mutation in @(
  @{id='unknown'; mutate={param($r) $r | Add-Member -NotePropertyName unauthorized_gate -NotePropertyValue $true}},
  @{id='relation'; mutate={param($r) (@($r.target_content_identities | Where-Object target -ceq 'f210'))[0].relation='changed-semantic-content-exact-engine-proof-required'}},
  @{id='executable-proof'; mutate={param($r) $r.factorio_one_convergence.factorio_two_executable_content_proof.kind='MIR4UnboundExecutableContentProofV1'}},
  @{id='gate'; mutate={param($r) $r.transition_gate.publication=$true}},
  @{id='required'; mutate={param($r) [void]$r.PSObject.Properties.Remove('factorio_one_convergence')}}
)) {
  $copy = $record | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  & $mutation.mutate $copy
  $copy.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $copy
  if (Test-MIR4CurrentPackagePresentationV4Schema -Record $copy -RepoRoot $repo) { throw "[mir4-package-presentation-v4-tamper] $($mutation.id)" }
}
$scratch = Join-Path $repo ('build/mir4/test-package-presentation-v4-' + [guid]::NewGuid().ToString('N') + '.json')
$stale = $false
try { & $writer -RepoRoot $repo -Check -CheckAuthorityPath $scratch | Out-Null } catch { $stale = $_.Exception.Message -eq '[mir4-package-presentation-v4-stale]' }
if (-not $stale -or (Test-Path -LiteralPath $scratch)) { throw '[mir4-package-presentation-v4-check-isolation]' }
$immutable = $false
try { & $writer -RepoRoot $repo -RecordedAt '2026-09-16T09:20:01+10:00' | Out-Null } catch { $immutable = $_.Exception.Message -eq '[mir4-package-presentation-v4-authority-immutable-overwrite]' }
if (-not $immutable) { throw '[mir4-package-presentation-v4-overwrite]' }
& $writer -RepoRoot $repo -Check | Out-Null
Write-Host '[ok] MIR4 package presentation V4 remains immutable historical evidence for the Factorio-1 convergence authority.'
