# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/FactorioOneSourceConvergence.ps1')

function Assert-MIR4FactorioOneConvergence([bool]$Condition, [string]$Code) {
  if (-not $Condition) { throw "[$Code]" }
}

$proof = Get-MIR4FactorioOneSourceConvergenceProof -RepoRoot $repo
$json = ConvertTo-MIR4BootstrapCanonicalJson -Value $proof
Assert-MIR4FactorioOneConvergence (Test-MIR4BootstrapRecordHash -Record $proof) 'mir4-factorio-one-convergence-self-hash'
Assert-MIR4FactorioOneConvergence ($json | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-factorio-one-source-convergence-proof-v1.schema.json')) 'mir4-factorio-one-convergence-schema'
Assert-MIR4FactorioOneConvergence ([string]$proof.status -ceq 'passed-static-source-convergence-engine-proof-required') 'mir4-factorio-one-convergence-status'
Assert-MIR4FactorioOneConvergence (@($proof.targets | Where-Object { @($_.unresolved_literal_requires).Count -ne 0 -or @($_.unsupported_bitwise_or_integer_division_sources).Count -ne 0 }).Count -eq 0) 'mir4-factorio-one-convergence-static-suitability'
Assert-MIR4FactorioOneConvergence ([bool]$proof.exact_engine_proof_required -and -not [bool]$proof.release_transition_authority) 'mir4-factorio-one-convergence-firewall'

[pscustomobject][ordered]@{
  status = 'passed'
  test_id = 'static.mir4-factorio-one-source-convergence-m42-02'
  bindings = [int]$proof.current_source.binding_count
  physical_sources = [int]$proof.current_source.physical_source_count
  targets = @($proof.targets | ForEach-Object { [ordered]@{ target = [string]$_.target; bindings = [int]$_.binding_count; omissions = [int]$_.omission_count } })
  historical_pairs = [int]$proof.historical_characterization.factorio_one_pair_count
  exact_engine_proof_required = $true
  release_authority = $false
  record_sha256 = [string]$proof.record_sha256
} | ConvertTo-Json -Depth 10
