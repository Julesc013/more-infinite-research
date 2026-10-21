[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$RecordedAt = '',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot 'tools/mir/application/release/F210QualificationPolicy.ps1')

function ConvertTo-MIR4F210ObservedTimestamp {
  param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Code)
  try {
    return [DateTimeOffset]::Parse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToString('o')
  } catch {
    throw "[mir4-f210-current-policy-v3-$Code]"
  }
}

$policyPath = Join-Path $RepoRoot $script:MIR4F210CurrentPolicyV3RelativePath
$receiptPath = Join-Path $RepoRoot $script:MIR4F210CurrentPolicySuccessionV2RelativePath
$channelPath = Join-Path $RepoRoot $script:MIR4F210CurrentEngineChannelReviewV2RelativePath
$channel = Get-Content -Raw -LiteralPath $channelPath | ConvertFrom-Json -Depth 100 -DateKind String
$observedAt = ConvertTo-MIR4F210ObservedTimestamp -Value ([string]$channel.current_review.observed_at) -Code 'observed-at-invalid'

if ($Check) {
  $policy = Get-MIR4F210CurrentQualificationPolicyV3 -RepoRoot $RepoRoot
  $receipt = Get-MIR4F210CurrentQualificationPolicySuccessionV2 -RepoRoot $RepoRoot
  if ([string]$policy.support_floor -cne '2.1.18' -or
      [string]$policy.recorded_at -cne $observedAt -or
      [string]$receipt.recorded_at -cne $observedAt -or
      [string]$receipt.current_policy.record_sha256 -cne [string]$policy.record_sha256) {
    throw '[mir4-f210-current-policy-v3-check]'
  }
  return [pscustomobject][ordered]@{status='current';policy=$script:MIR4F210CurrentPolicyV3RelativePath;receipt=$script:MIR4F210CurrentPolicySuccessionV2RelativePath;support_floor=$policy.support_floor;recorded_at=$observedAt}
}

$policyExists = Test-Path -LiteralPath $policyPath -PathType Leaf
$receiptExists = Test-Path -LiteralPath $receiptPath -PathType Leaf
if ($policyExists -xor $receiptExists) { throw '[mir4-f210-current-policy-v3-partial-record-set]' }
if ($policyExists) {
  $policy = Get-MIR4F210CurrentQualificationPolicyV3 -RepoRoot $RepoRoot
  $receipt = Get-MIR4F210CurrentQualificationPolicySuccessionV2 -RepoRoot $RepoRoot
  if ([string]$policy.recorded_at -cne [string]$receipt.recorded_at -or [string]$policy.recorded_at -cne $observedAt) {
    throw '[mir4-f210-current-policy-v3-existing-timestamp]'
  }
  if (-not [string]::IsNullOrWhiteSpace($RecordedAt) -and
      (ConvertTo-MIR4F210ObservedTimestamp -Value $RecordedAt -Code 'requested-at-invalid') -cne [string]$policy.recorded_at) {
    throw '[mir4-f210-current-policy-v3-existing-timestamp-immutable]'
  }
  return [pscustomobject][ordered]@{status='current';policy=$script:MIR4F210CurrentPolicyV3RelativePath;receipt=$script:MIR4F210CurrentPolicySuccessionV2RelativePath;support_floor=$policy.support_floor;recorded_at=[string]$policy.recorded_at}
}

if ([string]::IsNullOrWhiteSpace($RecordedAt)) {
  $RecordedAt = $observedAt
} else {
  $RecordedAt = ConvertTo-MIR4F210ObservedTimestamp -Value $RecordedAt -Code 'requested-at-invalid'
  if ($RecordedAt -cne $observedAt) { throw '[mir4-f210-current-policy-v3-recorded-at-must-match-observation]' }
}

$policy = New-MIR4F210CurrentQualificationPolicyV3 -RepoRoot $RepoRoot -RecordedAt $RecordedAt
[IO.File]::WriteAllText($policyPath,((ConvertTo-MIR4BootstrapCanonicalJson -Value $policy) + "`n"),[Text.UTF8Encoding]::new($false))
$receipt = New-MIR4F210CurrentQualificationPolicySuccessionV2 -RepoRoot $RepoRoot -RecordedAt $RecordedAt
[IO.File]::WriteAllText($receiptPath,((ConvertTo-MIR4BootstrapCanonicalJson -Value $receipt) + "`n"),[Text.UTF8Encoding]::new($false))
& $PSCommandPath -RepoRoot $RepoRoot -Check | Out-Null
return [pscustomobject][ordered]@{status='generated';policy=$script:MIR4F210CurrentPolicyV3RelativePath;receipt=$script:MIR4F210CurrentPolicySuccessionV2RelativePath;support_floor=$policy.support_floor;recorded_at=$RecordedAt}