param(
  [Parameter(Mandatory)][string]$InputPath,
  [Parameter(Mandatory)][string[]]$Subjects,
  [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
$snapshot = Get-Content -Raw -LiteralPath $InputPath | ConvertFrom-Json
if ($snapshot.kind -ne "mir-planner-snapshot") { throw "Input must be a MIR planner snapshot." }
$subjectSet = @{}
foreach ($subject in $Subjects) { $subjectSet[$subject] = $true }

$selected = @($snapshot.all_rows | Where-Object {
  $row = $_
  foreach ($field in @("key", "subject", "recipe", "item", "capability", "rule", "target_stream")) {
    $value = [string]$row.PSObject.Properties[$field].Value
    if ($subjectSet.ContainsKey($value)) { return $true }
  }
  return $false
} | Sort-Object kind, key, subject, recipe)

$artifact = [ordered]@{
  schema = 1
  kind = "mir-planner-snapshot-minimum"
  source_fingerprint = [string]$snapshot.fingerprint_sha256
  target_profile = [string]$snapshot.target_profile
  requested_subjects = @($Subjects | Sort-Object -Unique)
  row_count = $selected.Count
  rows = $selected
}
$artifact | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "[ok] wrote minimized MIR planner snapshot $OutputPath rows=$($selected.Count)"
