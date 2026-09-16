# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/FactorioOneSourceConvergenceAuthority.ps1')

function Assert-MIR4FactorioOneSourceConvergenceAuthority([bool]$Condition, [string]$Code) {
  if (-not $Condition) { throw "[$Code]" }
}
function Copy-MIR4FactorioOneSourceConvergenceAuthority($Value) {
  return $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
}
function Assert-MIR4FactorioOneSourceConvergenceAuthorityRejected([scriptblock]$Action, [string]$Code) {
  $rejected = $false
  try { & $Action } catch { $rejected = $_.Exception.Message.Contains($Code) }
  Assert-MIR4FactorioOneSourceConvergenceAuthority $rejected "mir4-factorio-one-convergence-negative-$Code"
}

$writer = Join-Path $repo 'tools/commands/mir4/Update-MIR4FactorioOneSourceConvergenceAuthority.ps1'
& $writer -RepoRoot $repo -Check | Out-Null
$receipt = Read-MIR4FactorioOneSourceConvergenceReceipt -RepoRoot $repo
$proof = Test-MIR4FactorioOneSourceConvergenceReceipt -RepoRoot $repo -Receipt $receipt
Assert-MIR4FactorioOneSourceConvergenceAuthority ([string]$proof.status -ceq 'passed-historical-factorio-one-source-convergence' -and [bool]$proof.factorio_one_exact_engine_proof_required -and -not [bool]$proof.release_transition_authority) 'mir4-factorio-one-convergence-positive'

$tamperedIdentity = Copy-MIR4FactorioOneSourceConvergenceAuthority $receipt
$tamperedIdentity.target_content_identities[2].relation = 'presentation-only-content-change-executable-preserved'
$tamperedIdentity.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $tamperedIdentity
Assert-MIR4FactorioOneSourceConvergenceAuthorityRejected { Test-MIR4FactorioOneSourceConvergenceReceipt -RepoRoot $repo -Receipt $tamperedIdentity | Out-Null } 'mir4-factorio-one-convergence-historical-integrity'

$tamperedExecutableContentProof = Copy-MIR4FactorioOneSourceConvergenceAuthority $receipt
$tamperedExecutableContentProof.factorio_two_executable_content_proof.record_sha256 = '0' * 64
$tamperedExecutableContentProof.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $tamperedExecutableContentProof
Assert-MIR4FactorioOneSourceConvergenceAuthorityRejected { Test-MIR4FactorioOneSourceConvergenceReceipt -RepoRoot $repo -Receipt $tamperedExecutableContentProof | Out-Null } 'mir4-factorio-one-convergence-historical-integrity'

$tamperedGate = Copy-MIR4FactorioOneSourceConvergenceAuthority $receipt
$tamperedGate.transition_gate.main_promotion = $true
$tamperedGate.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $tamperedGate
Assert-MIR4FactorioOneSourceConvergenceAuthorityRejected { Test-MIR4FactorioOneSourceConvergenceReceipt -RepoRoot $repo -Receipt $tamperedGate | Out-Null } 'mir4-factorio-one-convergence-receipt-schema'

$unknown = Copy-MIR4FactorioOneSourceConvergenceAuthority $receipt
$unknown | Add-Member -NotePropertyName unauthorized_gate -NotePropertyValue $true
$unknown.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $unknown
Assert-MIR4FactorioOneSourceConvergenceAuthorityRejected { Test-MIR4FactorioOneSourceConvergenceReceipt -RepoRoot $repo -Receipt $unknown | Out-Null } 'mir4-factorio-one-convergence-receipt-schema'

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-factorio-one-source-convergence-authority-v1';historical=$true;exact_engine_proof_required=$true;release_authority=$false;record_sha256=[string]$receipt.record_sha256} | ConvertTo-Json -Compress
