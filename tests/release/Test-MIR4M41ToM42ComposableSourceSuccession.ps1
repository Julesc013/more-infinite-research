# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/Contract.ps1')

function Assert-MIR4M41ToM42Succession([bool]$Condition,[string]$Code){if(-not$Condition){throw "[$Code]"}}
function Copy-MIR4M41ToM42Succession($Value){return $Value|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String}
function Assert-MIR4M41ToM42Rejected([scriptblock]$Action,[string]$Code){$rejected=$false;try{&$Action}catch{$rejected=$_.Exception.Message.Contains($Code)};Assert-MIR4M41ToM42Succession $rejected "mir4-m41-m42-succession-negative-$Code"}

& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M41ToM42ComposableSourceSuccessionAuthority.ps1') -RepoRoot $repo -Check|Out-Null
$proof=Test-MIR4M41ToM42ComposableSourceSuccession -RepoRoot $repo
Assert-MIR4M41ToM42Succession ([string]$proof.status-ceq'passed-historical-mir41-to-current-mir42-composable-source-succession'-and-not[bool]$proof.current_release_operations_authorized) 'mir4-m41-m42-succession-positive'

$inputs=Get-MIR4M41ToM42ComposableSourceSuccessionInputs -RepoRoot $repo
$tamperedReceipt=Copy-MIR4M41ToM42Succession $inputs.layout_receipt
$tamperedReceipt.current.package_source_fingerprint_sha256=('0'*64 -join '')
$tamperedReceipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $tamperedReceipt
Assert-MIR4M41ToM42Rejected {Get-MIR4M41ToM42ComposableSourceSuccessionInputs -RepoRoot $repo -HistoricalReadiness $inputs.historical_readiness -HistoricalSourceFreeze $inputs.historical_source_freeze -LayoutAuthority $inputs.layout_authority -LayoutProof $inputs.layout_proof -LayoutReceipt $tamperedReceipt|Out-Null} 'mir4-m41-m42-succession-current-package-authority'

$tamperedAuthority=Copy-MIR4M41ToM42Succession $inputs.layout_authority
$tamperedAuthority.transition_gate.main_promotion=$true
Assert-MIR4M41ToM42Rejected {Get-MIR4M41ToM42ComposableSourceSuccessionInputs -RepoRoot $repo -HistoricalReadiness $inputs.historical_readiness -HistoricalSourceFreeze $inputs.historical_source_freeze -LayoutAuthority $tamperedAuthority -LayoutProof $inputs.layout_proof -LayoutReceipt $inputs.layout_receipt|Out-Null} 'mir4-m41-m42-succession-layout-gate'

$tamperedHistorical=Copy-MIR4M41ToM42Succession $inputs.historical_readiness
$tamperedHistorical.package_source.current_sha256=('F'*64 -join '')
Assert-MIR4M41ToM42Rejected {Get-MIR4M41ToM42ComposableSourceSuccessionInputs -RepoRoot $repo -HistoricalReadiness $tamperedHistorical -HistoricalSourceFreeze $inputs.historical_source_freeze -LayoutAuthority $inputs.layout_authority -LayoutProof $inputs.layout_proof -LayoutReceipt $inputs.layout_receipt|Out-Null} 'mir4-m41-m42-succession-historical-readiness'

$tamperedRecord=Copy-MIR4M41ToM42Succession (New-MIR4M41ToM42ComposableSourceSuccession -RepoRoot $repo)
$tamperedRecord.transition_gate.main_promotion=$true
$tamperedRecord.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $tamperedRecord
Assert-MIR4M41ToM42Rejected {Test-MIR4M41ToM42ComposableSourceSuccession -RepoRoot $repo -SuccessionRecord $tamperedRecord|Out-Null} 'mir4-m41-m42-succession-release-firewall'

$contract=Get-MIR441ReleaseReadinessContract -RepoRoot $repo
foreach($operation in @('private_build','qualification','technical_seal','promotion')){
  Assert-MIR4M41ToM42Rejected {Assert-MIR441CurrentReleaseOperationAuthorized -Contract $contract -Operation $operation} 'mir441-current-release-operation-not-authorized'
}

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-m41-to-m42-composable-source-succession-v1';historical_contract=$true;current_release_operations_authorized=$false;current_package_source_sha256=[string]$proof.current_package_source_sha256;record_sha256=[string]$proof.record_sha256}|ConvertTo-Json -Compress
