. (Join-Path $PSScriptRoot '../safety/SafetyKernel.ps1')

function Resolve-MIR4PolicyDisposition {
  param([Parameter(Mandatory)]$Contribution)

  $safety = Test-MIR4SafetyContribution -Contribution $Contribution
  if ([string]$safety.status -eq 'rejected') {
    return [pscustomobject][ordered]@{
      kind = 'MIR4PolicyDecisionV0'
      schema = 0
      subject = [string]$Contribution.subject
      disposition = 'fail-hard-safety'
      maturity = 'shadow'
      safety = $safety
      mutation_authorized = $false
      review_required = $true
    }
  }

  $requested = [string]$Contribution.requested_disposition
  $allowed = @('handle', 'preserve', 'request-extension', 'request-review', 'omit-with-evidence')
  $disposition = if ($requested -in $allowed) { $requested } else { 'request-review' }
  return [pscustomobject][ordered]@{
    kind = 'MIR4PolicyDecisionV0'
    schema = 0
    subject = [string]$Contribution.subject
    disposition = $disposition
    maturity = 'shadow'
    safety = $safety
    mutation_authorized = $false
    review_required = $true
  }
}
