[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$RecordedAt = '2026-09-21T00:00:00+10:00',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/F210QualificationPolicy.ps1')

$policyPath = Join-Path $RepoRoot $script:MIR4F210CurrentPolicyRelativePath
$receiptPath = Join-Path $RepoRoot $script:MIR4F210CurrentPolicySuccessionRelativePath
if ($Check) {
  $policy = Get-MIR4F210CurrentQualificationPolicyV2 -RepoRoot $RepoRoot
  $receipt = Get-MIR4F210CurrentQualificationPolicySuccessionV1 -RepoRoot $RepoRoot
  if ([string]$policy.support_floor -cne '2.1.18' -or
      [string]$receipt.current_policy.record_sha256 -cne [string]$policy.record_sha256) {
    throw '[mir4-f210-current-policy-check]'
  }
  return [pscustomobject][ordered]@{status='current';policy=$script:MIR4F210CurrentPolicyRelativePath;receipt=$script:MIR4F210CurrentPolicySuccessionRelativePath;support_floor=[string]$policy.support_floor}
}

if ((Test-Path -LiteralPath $policyPath -PathType Leaf) -or (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
  throw '[mir4-f210-current-policy-append-only-overwrite]'
}
$policy = New-MIR4F210CurrentQualificationPolicyV2 -RepoRoot $RepoRoot -RecordedAt $RecordedAt
[IO.File]::WriteAllText($policyPath,((ConvertTo-MIR4BootstrapCanonicalJson -Value $policy) + "`n"),[Text.UTF8Encoding]::new($false))
$receipt = New-MIR4F210CurrentQualificationPolicySuccessionV1 -RepoRoot $RepoRoot -RecordedAt $RecordedAt
[IO.File]::WriteAllText($receiptPath,((ConvertTo-MIR4BootstrapCanonicalJson -Value $receipt) + "`n"),[Text.UTF8Encoding]::new($false))
& $PSCommandPath -RepoRoot $RepoRoot -Check | Out-Null
return [pscustomobject][ordered]@{status='generated';policy=$script:MIR4F210CurrentPolicyRelativePath;receipt=$script:MIR4F210CurrentPolicySuccessionRelativePath;support_floor=[string]$policy.support_floor}
