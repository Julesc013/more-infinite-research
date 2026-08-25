function Test-MIR4SafetyContribution {
  param([Parameter(Mandatory)]$Contribution)

  $subject = [string]$Contribution.subject
  if ([string]::IsNullOrWhiteSpace($subject)) { throw '[mir4-safety-subject-required]' }
  $operations = @($Contribution.operations | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  $evidence = @($Contribution.evidence | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
  $violations = @()
  $forbidden = @('arbitrary-callback', 'hard-safety-override', 'opaque-owner-rewrite', 'prototype-write', 'raw-compiler-context', 'unbounded-positive-cycle')
  foreach ($operation in $operations) {
    if ($operation -in $forbidden) { $violations += "forbidden-operation:$operation" }
  }
  $positiveCycle = $null -ne $Contribution.PSObject.Properties['positive_cycle'] -and [bool]$Contribution.positive_cycle
  $provenBounded = $null -ne $Contribution.PSObject.Properties['proven_bounded'] -and [bool]$Contribution.proven_bounded
  $ownerOpaque = $null -ne $Contribution.PSObject.Properties['owner_opaque'] -and [bool]$Contribution.owner_opaque
  $ownerRewrite = $null -ne $Contribution.PSObject.Properties['owner_rewrite'] -and [bool]$Contribution.owner_rewrite
  if ($positiveCycle -and -not $provenBounded) { $violations += 'unbounded-positive-cycle' }
  if ($ownerOpaque -and $ownerRewrite) { $violations += 'opaque-owner-rewrite' }
  if ($evidence.Count -eq 0) { $violations += 'missing-safety-evidence' }
  $violations = @($violations | Sort-Object -Unique)

  return [pscustomobject][ordered]@{
    kind = 'MIR4SafetyDecisionV0'
    schema = 0
    subject = $subject
    status = if ($violations.Count -eq 0) { 'accepted-for-policy-evaluation' } else { 'rejected' }
    violations = $violations
    evidence = $evidence
    hard_safety_overridable = $false
    mutation_authorized = $false
  }
}
