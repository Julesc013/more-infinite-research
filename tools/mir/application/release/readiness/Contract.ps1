Set-StrictMode -Version Latest

function Get-MIR441ReleaseReadinessContract {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo 'governance/release/mir4-4.1-release-readiness-v1.json'
  $schema = Join-Path $repo 'contracts/repository/mir4-4.1-release-readiness-v1.schema.json'
  $raw = Get-Content -Raw -LiteralPath $path
  if (-not ($raw | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) { throw '[mir441-readiness-contract-schema]' }
  $contract = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  $targets = @($contract.targets)
  if (@($targets.target | Sort-Object -Unique).Count -ne 4 -or
      (@($targets.target | Sort-Object) -join '|') -cne 'f100|f110|f200|f210') { throw '[mir441-readiness-target-set]' }
  if (@($targets | Where-Object { [string]$_.qualification_role -cne 'technical-required' }).Count -ne 0) { throw '[mir441-readiness-four-target-role]' }
  $package=Get-Content -Raw -LiteralPath (Join-Path $repo 'targets/package-authority.json')|ConvertFrom-Json -Depth 100 -DateKind String
  if([string]$contract.package_source.current_sha256-cne(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)-or
     [string]$contract.package_source.authority_record_sha256-cne[string]$package.record_sha256){throw '[mir441-readiness-package-source-succession]'}
  return $contract
}

function Test-MIR441ReleaseReadinessContract {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $contract = Get-MIR441ReleaseReadinessContract -RepoRoot $RepoRoot
  return [pscustomobject][ordered]@{
    schema=1;kind='MIR441ReleaseReadinessContractCheckV1';status='MIR-4.1-RELEASE-READINESS-CONTRACT-PASSED'
    source_version=[string]$contract.release.source_version;target_count=@($contract.targets).Count
    private_build_authorized=[bool]$contract.transition_gate.private_build
    technical_seal_authorized=[bool]$contract.transition_gate.technical_seal
    exact_main_promotion_authorized=[bool]$contract.transition_gate.promotion
    tagging_authorized=[bool]$contract.transition_gate.tagging
    publication_authorized=[bool]$contract.transition_gate.publication
    publisher_can_build=$false
  }
}
