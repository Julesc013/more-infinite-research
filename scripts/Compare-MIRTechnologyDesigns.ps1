param(
  [Parameter(Mandatory)][string]$BeforePath,
  [Parameter(Mandatory)][string]$AfterPath,
  [string]$ApprovalPath = "",
  [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Get-MIRJsonText { param($Value) return ($Value | ConvertTo-Json -Depth 100 -Compress) }

$before = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $BeforePath) | ConvertFrom-Json
$after = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $AfterPath) | ConvertFrom-Json
$approval = if ($ApprovalPath) {
  Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $ApprovalPath) | ConvertFrom-Json
} else { $null }

if ($before.schema -ne 2 -or $after.schema -ne 2) { throw "TechnologyDesign schema 2 inputs are required." }
if ([string]$before.candidate_id -ne [string]$after.candidate_id) { throw "Cannot diff different candidate identities." }
$beforeFields = $before.provenance.fields
$afterFields = $after.provenance.fields
if ($null -eq $beforeFields -or $null -eq $afterFields) { throw "TechnologyDesign field provenance is required." }

$locked = @{}
$adaptive = @{}
if ($approval) {
  foreach ($path in @($approval.locked_fields)) { $locked[[string]$path] = $true }
  foreach ($property in @($approval.adaptive_envelopes.PSObject.Properties)) { $adaptive[$property.Name] = $true }
}
$paths = @($beforeFields.PSObject.Properties.Name + $afterFields.PSObject.Properties.Name | Sort-Object -Unique)
$changes = @()
$lockViolation = $false
$adaptiveReview = $false
foreach ($path in $paths) {
  $beforeProperty = $beforeFields.PSObject.Properties[$path]
  $afterProperty = $afterFields.PSObject.Properties[$path]
  $beforeValue = if ($beforeProperty) { $beforeProperty.Value.value } else { $null }
  $afterValue = if ($afterProperty) { $afterProperty.Value.value } else { $null }
  if ((Get-MIRJsonText $beforeValue) -eq (Get-MIRJsonText $afterValue)) { continue }
  $classification = "unreviewed"
  if ($locked.ContainsKey($path)) { $classification = "locked"; $lockViolation = $true }
  elseif ($adaptive.ContainsKey($path)) { $classification = "adaptive-envelope-review"; $adaptiveReview = $true }
  $changes += [ordered]@{
    path = $path
    before = $beforeValue
    after = $afterValue
    classification = $classification
  }
}

$exactApproved = $approval -and [string]$approval.decision -eq "approved" -and
  [string]$approval.approved_design_fingerprint -eq [string]$after.design_fingerprint
$status = if ($exactApproved) { "APPROVED" }
  elseif ($lockViolation) { "REJECTED_LOCK_VIOLATION" }
  elseif ($adaptiveReview) { "TARGETED_REVIEW" }
  elseif ($changes.Count -eq 0) { "UNCHANGED" }
  else { "REVIEW_REQUIRED" }
$artifact = [ordered]@{
  schema = 1
  kind = "mir-technology-design-diff"
  candidate_id = [string]$before.candidate_id
  before_design_fingerprint = [string]$before.design_fingerprint
  after_design_fingerprint = [string]$after.design_fingerprint
  approval_id = if ($approval) { [string]$approval.approval_id } else { "" }
  status = $status
  changes = $changes
}
$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$artifact | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "[ok] wrote MIR TechnologyDesign diff $OutputPath status=$status changes=$($changes.Count)"
