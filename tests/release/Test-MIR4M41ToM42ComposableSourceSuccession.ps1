# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/Contract.ps1')

function Assert-MIR4M41ToM42HistoricalSuccession([bool]$Condition,[string]$Code){if(-not$Condition){throw "[$Code]"}}
function Assert-MIR4M41ToM42HistoricalRejected([scriptblock]$Action,[string]$Code){$rejected=$false;try{&$Action}catch{$rejected=$_.Exception.Message.Contains($Code)};Assert-MIR4M41ToM42HistoricalSuccession $rejected "mir4-m41-m42-succession-v1-negative-$Code"}

$writer = Join-Path $repo 'tools/commands/mir4/Update-MIR4M41ToM42ComposableSourceSuccessionAuthority.ps1'
$writerResult = & $writer -RepoRoot $repo -Check
Assert-MIR4M41ToM42HistoricalSuccession ([string]$writerResult.status-ceq'historical-current'-and-not[bool]$writerResult.release_authority) 'mir4-m41-m42-succession-v1-writer'
$historical = Test-MIR4M41ToM42ComposableSourceSuccessionV1Historical -RepoRoot $repo
Assert-MIR4M41ToM42HistoricalSuccession ([string]$historical.status-ceq'passed-historical-mir41-to-mir42-composable-source-layout'-and-not[bool]$historical.release_authority) 'mir4-m41-m42-succession-v1-historical'
Assert-MIR4M41ToM42HistoricalRejected { & $writer -RepoRoot $repo } 'mir4-m41-m42-succession-v1-historical-write-retired'

$contract=Get-MIR441ReleaseReadinessContract -RepoRoot $repo
foreach($operation in @('private_build','qualification','technical_seal','promotion')){
  Assert-MIR4M41ToM42HistoricalRejected {Assert-MIR441CurrentReleaseOperationAuthorized -Contract $contract -Operation $operation} 'mir441-current-release-operation-not-authorized'
}

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-m41-to-m42-composable-source-succession-v1';historical_contract=$true;current_release_operations_authorized=$false;record_sha256=[string]$historical.record_sha256}|ConvertTo-Json -Compress
