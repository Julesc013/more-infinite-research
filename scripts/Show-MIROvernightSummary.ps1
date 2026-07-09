param(
  [Parameter(Mandatory)][string]$OutputRoot,
  [int]$Tail = 300
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $OutputRoot)) {
  throw "Output root does not exist: $OutputRoot"
}

$resolvedOutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
$logPath = Join-Path $resolvedOutputRoot "overnight.log"

Write-Host "[summary] output root: $resolvedOutputRoot"

$manifestPath = Join-Path $resolvedOutputRoot "run-manifest.json"
$artifactIndexPath = Join-Path $resolvedOutputRoot "artifact-index.json"
$htmlPath = Join-Path $resolvedOutputRoot "index.html"

foreach ($path in @($manifestPath, $artifactIndexPath, $htmlPath)) {
  if (Test-Path -LiteralPath $path) {
    Write-Host "[summary] artifact: $path"
  }
}

if (Test-Path -LiteralPath $logPath) {
  Write-Host ""
  Write-Host "## Overnight Log Tail"
  Get-Content -LiteralPath $logPath -Tail $Tail
}

$summaryFiles = @(
  Join-Path $resolvedOutputRoot "release-gate\extended-summary.md"
  Join-Path $resolvedOutputRoot "local-sweep\extended-summary.md"
)

foreach ($summaryFile in $summaryFiles) {
  if (Test-Path -LiteralPath $summaryFile) {
    Write-Host ""
    Write-Host "## $summaryFile"
    Get-Content -LiteralPath $summaryFile
  }
}

$failureRows = @(
  Get-ChildItem -LiteralPath $resolvedOutputRoot -Recurse -Filter compat-failures.grouped.json -File |
    ForEach-Object {
      $json = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
      [pscustomobject]@{
        file = $_.FullName
        groups = [int]$json.group_count
        unexpected = [int]$json.unexpected_count
        expected = [int]$json.expected_count
      }
    }
)

Write-Host ""
Write-Host "## Failure Groups"
if ($failureRows.Count -eq 0) {
  Write-Host "No grouped failure files found."
} else {
  $failureRows | Sort-Object unexpected -Descending | Format-Table -AutoSize | Out-String | Write-Host
}

$missingDependencyRows = @(
  Get-ChildItem -LiteralPath $resolvedOutputRoot -Recurse -Filter missing-dependencies.csv -File |
    ForEach-Object {
      Import-Csv -LiteralPath $_.FullName | ForEach-Object {
        [pscustomobject]@{
          mod = $_.mod
          scenario = $_.scenario
          phase = $_.phase
          error = $_.error
        }
      }
    }
)

Write-Host ""
Write-Host "## Missing Dependencies"
if ($missingDependencyRows.Count -eq 0) {
  Write-Host "No missing dependency rows found."
} else {
  $missingDependencyRows |
    Group-Object mod |
    Sort-Object -Property @{ Expression = "Count"; Descending = $true }, @{ Expression = "Name"; Descending = $false } |
    Select-Object -First 100 |
    ForEach-Object {
      [pscustomobject]@{
        mod = $_.Name
        count = $_.Count
        phases = (@($_.Group | ForEach-Object { $_.phase } | Sort-Object -Unique) -join ", ")
        scenarios = (@($_.Group | ForEach-Object { $_.scenario } | Sort-Object -Unique | Select-Object -First 8) -join ", ")
      }
    } |
    Format-Table -AutoSize |
    Out-String |
    Write-Host
}

$profileRows = @(
  Get-ChildItem -LiteralPath $resolvedOutputRoot -Recurse -Filter profile-candidates.json -File |
    ForEach-Object {
      $json = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
      [pscustomobject]@{
        file = $_.FullName
        candidates = @($json.candidates).Count
      }
    }
)

Write-Host ""
Write-Host "## Profile Candidates"
if ($profileRows.Count -eq 0) {
  Write-Host "No profile-candidate files found."
} else {
  $profileRows | Sort-Object candidates -Descending | Format-Table -AutoSize | Out-String | Write-Host
}

$observationRows = @(
  Get-ChildItem -LiteralPath $resolvedOutputRoot -Recurse -Filter compat-observations.json -File |
    ForEach-Object {
      $json = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
      [pscustomobject]@{
        file = $_.FullName
        observations = [int]$json.observation_count
        recipe_cap = @($json.observations | Where-Object { $_.kind -eq "recipe_cap" }).Count
        roles = @($json.observations | Where-Object { $_.kind -eq "compatibility_role" }).Count
        decisions = @($json.observations | Where-Object { $_.kind -eq "decision" }).Count
        capabilities = @($json.observations | Where-Object { -not [string]::IsNullOrWhiteSpace($_.capability) }).Count
        loop_risks = @($json.observations | Where-Object { $_.kind -eq "loop_risk" }).Count
        rule_surfaces = @($json.observations | Where-Object { $_.kind -eq "rule_mutation" }).Count
        fact_registry = @($json.observations | Where-Object { $_.kind -eq "fact_registry" }).Count
        lab_matrix = @($json.observations | Where-Object { $_.kind -eq "lab_matrix" }).Count
      }
    }
)

Write-Host ""
Write-Host "## Compatibility Observations"
if ($observationRows.Count -eq 0) {
  Write-Host "No compatibility-observation files found."
} else {
  $observationRows | Sort-Object observations -Descending | Format-Table -AutoSize | Out-String | Write-Host
}
