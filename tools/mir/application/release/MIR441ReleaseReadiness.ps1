Set-StrictMode -Version Latest

foreach($module in @('readiness/Common.ps1','readiness/Contract.ps1','readiness/ResourceGovernor.ps1','readiness/CandidateBuild.ps1','readiness/QualificationResume.ps1','readiness/Qualification.ps1','readiness/IndependentVerification.ps1','readiness/TechnicalSeal.ps1','readiness/Promotion.ps1')){
  . (Join-Path $PSScriptRoot $module)
}

function Test-MIR441ReleaseReadiness {
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$WorkRoot='')
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $contract=Test-MIR441ReleaseReadinessContract -RepoRoot $repo
  $git=Get-MIR441GitIdentity -RepoRoot $repo
  $result=[ordered]@{schema=1;kind='MIR441ReleaseReadinessCheckV1';status='MIR-4.1-RELEASE-READINESS-PASSED';contract=$contract;source=$git;working_tree_clean=(@(& git -C $repo status --porcelain).Count-eq0);resources=$null}
  if(-not[string]::IsNullOrWhiteSpace($WorkRoot)){$result.resources=Get-MIR441ResourceSnapshot -WorkRoot $WorkRoot}
  return [pscustomobject]$result
}
