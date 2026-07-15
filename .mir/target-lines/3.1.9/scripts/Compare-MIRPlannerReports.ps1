param(
  [Parameter(Mandatory)][string]$Before,
  [Parameter(Mandatory)][string]$After,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

function Find-MIRFile {
  param([string]$Root, [string]$Name)
  $resolved = Resolve-Path -LiteralPath $Root -ErrorAction Stop
  $direct = Join-Path $resolved.Path $Name
  if (Test-Path -LiteralPath $direct) { return $direct }
  $match = Get-ChildItem -LiteralPath $resolved.Path -Recurse -Filter $Name -File | Select-Object -First 1
  if ($match) { return $match.FullName }
  return $null
}

function Read-MIRJsonArray {
  param([string]$Path, [string]$Property)
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return @() }
  $json = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  $value = $json.PSObject.Properties[$Property].Value
  if ($null -eq $value) { return @() }
  if ($value -is [array]) { return @($value) }
  return @($value)
}

function Row-Key {
  param($Row)
  return (@(
    [string]$Row.kind,
    [string]$Row.key,
    [string]$Row.subject,
    [string]$Row.recipe,
    [string]$Row.capability,
    [string]$Row.decision,
    [string]$Row.emitted
  ) -join "|")
}

function Compare-RowSet {
  param([object[]]$BeforeRows, [object[]]$AfterRows, [string]$Label)
  $beforeMap = @{}
  $afterMap = @{}
  foreach ($row in $BeforeRows) { $beforeMap[(Row-Key -Row $row)] = $row }
  foreach ($row in $AfterRows) { $afterMap[(Row-Key -Row $row)] = $row }

  $added = @($afterMap.Keys | Where-Object { -not $beforeMap.ContainsKey($_) } | Sort-Object)
  $removed = @($beforeMap.Keys | Where-Object { -not $afterMap.ContainsKey($_) } | Sort-Object)

  [pscustomobject]@{
    label = $Label
    before = $BeforeRows.Count
    after = $AfterRows.Count
    added = $added.Count
    removed = $removed.Count
    added_keys = @($added | Select-Object -First 25)
    removed_keys = @($removed | Select-Object -First 25)
  }
}

function Select-MIRRows {
  param([object[]]$Rows, [scriptblock]$Predicate)
  return @($Rows | Where-Object $Predicate)
}

$beforeObservationFile = Find-MIRFile -Root $Before -Name "compat-observations.json"
$afterObservationFile = Find-MIRFile -Root $After -Name "compat-observations.json"
$beforeClaimsFile = Find-MIRFile -Root $Before -Name "claims.json"
$afterClaimsFile = Find-MIRFile -Root $After -Name "claims.json"

$beforeRows = Read-MIRJsonArray -Path $beforeObservationFile -Property "observations"
$afterRows = Read-MIRJsonArray -Path $afterObservationFile -Property "observations"
$beforeClaims = Read-MIRJsonArray -Path $beforeClaimsFile -Property "claims"
$afterClaims = Read-MIRJsonArray -Path $afterClaimsFile -Property "claims"

$sections = @(
  Compare-RowSet -Label "generated streams" -BeforeRows (Select-MIRRows $beforeRows { $_.kind -eq "stream" -and $_.status -eq "generated" }) -AfterRows (Select-MIRRows $afterRows { $_.kind -eq "stream" -and $_.status -eq "generated" })
  Compare-RowSet -Label "capability decisions" -BeforeRows (Select-MIRRows $beforeRows { -not [string]::IsNullOrWhiteSpace($_.capability) }) -AfterRows (Select-MIRRows $afterRows { -not [string]::IsNullOrWhiteSpace($_.capability) })
  Compare-RowSet -Label "unknown/proposed candidates" -BeforeRows (Select-MIRRows $beforeRows { $_.decision -match "observe_unknown|propose_stream" }) -AfterRows (Select-MIRRows $afterRows { $_.decision -match "observe_unknown|propose_stream" })
  Compare-RowSet -Label "loop risks" -BeforeRows (Select-MIRRows $beforeRows { $_.kind -eq "loop_risk" }) -AfterRows (Select-MIRRows $afterRows { $_.kind -eq "loop_risk" })
  Compare-RowSet -Label "external/native owners" -BeforeRows (Select-MIRRows $beforeRows { $_.kind -eq "native_modifier_overlap" -or $_.reason -match "owner" }) -AfterRows (Select-MIRRows $afterRows { $_.kind -eq "native_modifier_overlap" -or $_.reason -match "owner" })
  Compare-RowSet -Label "science and lab rows" -BeforeRows (Select-MIRRows $beforeRows { $_.kind -eq "lab_matrix" -or -not [string]::IsNullOrWhiteSpace($_.labs) -or -not [string]::IsNullOrWhiteSpace($_.science) }) -AfterRows (Select-MIRRows $afterRows { $_.kind -eq "lab_matrix" -or -not [string]::IsNullOrWhiteSpace($_.labs) -or -not [string]::IsNullOrWhiteSpace($_.science) })
  Compare-RowSet -Label "cap diagnostics" -BeforeRows (Select-MIRRows $beforeRows { $_.kind -eq "recipe_cap" -or $_.cap_state }) -AfterRows (Select-MIRRows $afterRows { $_.kind -eq "recipe_cap" -or $_.cap_state })
  Compare-RowSet -Label "claim levels" -BeforeRows $beforeClaims -AfterRows $afterClaims
)

$report = [ordered]@{
  schema = 1
  generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
  before = (Resolve-Path -LiteralPath $Before).Path
  after = (Resolve-Path -LiteralPath $After).Path
  before_observations = $beforeObservationFile
  after_observations = $afterObservationFile
  sections = $sections
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

Write-Host "# MIR Planner Report Diff"
Write-Host ""
Write-Host ("- Before: {0}" -f $report.before)
Write-Host ("- After: {0}" -f $report.after)
Write-Host ""
Write-Host "| Section | Before | After | Added | Removed |"
Write-Host "| --- | ---: | ---: | ---: | ---: |"
foreach ($section in $sections) {
  Write-Host ("| {0} | {1} | {2} | {3} | {4} |" -f $section.label, $section.before, $section.after, $section.added, $section.removed)
}
