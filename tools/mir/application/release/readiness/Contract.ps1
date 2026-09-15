Set-StrictMode -Version Latest

if (-not (Get-Command Test-MIR4M41ToM42ComposableSourceSuccession -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'ComposableSourceSuccession.ps1')
}

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
  $package = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $currentFingerprint = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
  if ([string]$contract.package_source.current_sha256 -ceq $currentFingerprint -and
      [string]$contract.package_source.authority_record_sha256 -ceq [string]$package.record_sha256) {
    $contract | Add-Member -NotePropertyName authority_disposition -NotePropertyValue 'current-mir41-readiness-authority'
    return $contract
  }

  $successor = Test-MIR4M41ToM42ComposableSourceSuccession -RepoRoot $repo
  $effective = $contract | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $effective | Add-Member -NotePropertyName historical_transition_gate -NotePropertyValue $effective.transition_gate
  $effective.transition_gate = [pscustomobject][ordered]@{
    version_allocation=$false;private_build=$false;qualification=$false;technical_seal=$false
    promotion=$false;tagging=$false;publication=$false
  }
  $effective | Add-Member -NotePropertyName authority_disposition -NotePropertyValue 'historical-mir41-contract-current-mir42-composable-successor'
  $effective | Add-Member -NotePropertyName composable_source_successor -NotePropertyValue $successor
  return $effective
}

function Test-MIR441ReleaseReadinessContract {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $contract = Get-MIR441ReleaseReadinessContract -RepoRoot $RepoRoot
  $historicalSuccessor = [string]$contract.authority_disposition -ceq 'historical-mir41-contract-current-mir42-composable-successor'
  return [pscustomobject][ordered]@{
    schema=1;kind='MIR441ReleaseReadinessContractCheckV1';status=$(if($historicalSuccessor){'MIR-4.1-RELEASE-READINESS-HISTORICAL-SUCCESSOR-CONTRACT-PASSED'}else{'MIR-4.1-RELEASE-READINESS-CONTRACT-PASSED'})
    source_version=[string]$contract.release.source_version;target_count=@($contract.targets).Count
    private_build_authorized=[bool]$contract.transition_gate.private_build
    technical_seal_authorized=[bool]$contract.transition_gate.technical_seal
    exact_main_promotion_authorized=[bool]$contract.transition_gate.promotion
    tagging_authorized=[bool]$contract.transition_gate.tagging
    publication_authorized=[bool]$contract.transition_gate.publication
    historical_contract=$historicalSuccessor
    current_composable_source_successor=if($historicalSuccessor){[string]$contract.composable_source_successor.record_sha256}else{$null}
    publisher_can_build=$false
  }
}
