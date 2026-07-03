param(
  [Parameter(Mandatory)][string]$AuditDir,
  [string]$OutputDir = $AuditDir
)

$ErrorActionPreference = "Stop"

function New-MIRDirectory {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function Read-MIRJsonFile {
  param([string]$Path, $Fallback)
  if (-not (Test-Path -LiteralPath $Path)) { return $Fallback }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function ConvertTo-MIRArray {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [array]) { return @($Value) }
  return @($Value)
}

function Get-MIRObjectProperty {
  param($Object, [string]$Name, $Default = "")
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function Read-MIRTextIfExists {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return "" }
  return Get-Content -Raw -LiteralPath $Path
}

function New-MIRFailureGroup {
  param(
    [Parameter(Mandatory)][string]$Kind,
    [string]$Scenario = "",
    [string]$Mod = "",
    [string]$Stream = "",
    [string]$Recipe = "",
    [string]$Reason = "",
    [string]$Evidence = "",
    [string]$LikelyRemediation = ""
  )

  [ordered]@{
    id = ""
    kind = $Kind
    scenario = $Scenario
    mod = $Mod
    stream = $Stream
    recipe = $Recipe
    reason = $Reason
    evidence = $Evidence
    likely_remediation = $LikelyRemediation
  }
}

$resolvedAuditDir = (Resolve-Path -LiteralPath $AuditDir).Path
$resolvedOutputDir = New-MIRDirectory -Path $OutputDir

$compatReport = Read-MIRJsonFile -Path (Join-Path $resolvedAuditDir "compat-report.json") -Fallback ([pscustomobject]@{})
$loadResults = ConvertTo-MIRArray (Read-MIRJsonFile -Path (Join-Path $resolvedAuditDir "load-results.json") -Fallback @())
$manualResults = ConvertTo-MIRArray (Read-MIRJsonFile -Path (Join-Path $resolvedAuditDir "manual-results.json") -Fallback @())
$reportFailures = ConvertTo-MIRArray (Get-MIRObjectProperty -Object $compatReport -Name "failures" -Default @())

$groups = @()

foreach ($failure in $reportFailures) {
  $phase = [string](Get-MIRObjectProperty -Object $failure -Name "phase")
  $kind = "dependency_resolution_failure"
  if ($phase -eq "release-selection") { $kind = "dependency_resolution_failure" }
  if ($phase -eq "metadata") { $kind = "dependency_resolution_failure" }
  $groups += New-MIRFailureGroup `
    -Kind $kind `
    -Scenario ([string](Get-MIRObjectProperty -Object $failure -Name "scenario")) `
    -Mod ([string](Get-MIRObjectProperty -Object $failure -Name "name")) `
    -Reason $phase `
    -Evidence ([string](Get-MIRObjectProperty -Object $failure -Name "error")) `
    -LikelyRemediation "Check dependency compatibility, selected Factorio version, and Mod Portal metadata before treating this as a MIR bug."
}

foreach ($result in $loadResults) {
  $scenario = [string](Get-MIRObjectProperty -Object $result -Name "scenario")
  $rootMods = ConvertTo-MIRArray (Get-MIRObjectProperty -Object $result -Name "root_mods" -Default @())
  $primaryMod = if ($rootMods.Count -gt 0) { [string]$rootMods[0] } else { $scenario }
  $stdoutPath = [string](Get-MIRObjectProperty -Object $result -Name "stdout")
  $stderrPath = [string](Get-MIRObjectProperty -Object $result -Name "stderr")
  $logText = (Read-MIRTextIfExists -Path $stdoutPath) + "`n" + (Read-MIRTextIfExists -Path $stderrPath)
  $passed = [bool](Get-MIRObjectProperty -Object $result -Name "passed" -Default $false)
  $auditRows = ConvertTo-MIRArray (Get-MIRObjectProperty -Object $result -Name "audit_rows" -Default @())

  if (-not $passed) {
    $kind = "load_failure"
    if ($logText -match "multiple infinite productivity owners|multiple infinite recipe-productivity owners") {
      $kind = "duplicate_exact_owner"
    } elseif ($logText -match "missing prerequisite|Unknown technology|Technology prerequisite") {
      $kind = "missing_prerequisite"
    } elseif ($logText -match "No lab|science pack|ingredients") {
      $kind = "invalid_science_pack"
    }

    $groups += New-MIRFailureGroup `
      -Kind $kind `
      -Scenario $scenario `
      -Mod $primaryMod `
      -Reason ("exit_code=" + [string](Get-MIRObjectProperty -Object $result -Name "exit_code")) `
      -Evidence $stdoutPath `
      -LikelyRemediation "Inspect the Factorio log for the prototype-stage error, then decide whether MIR policy or the tested modset caused the failure."
  }

  if ($passed -and $auditRows.Count -eq 0) {
    $groups += New-MIRFailureGroup `
      -Kind "no_audit_rows" `
      -Scenario $scenario `
      -Mod $primaryMod `
      -Reason "audit_rows_empty" `
      -Evidence $stdoutPath `
      -LikelyRemediation "Confirm the copied MIR diagnostics patch was applied and the Factorio log was captured."
  }

  foreach ($row in $auditRows) {
    $kind = [string](Get-MIRObjectProperty -Object $row -Name "kind")
    $stream = [string](Get-MIRObjectProperty -Object $row -Name "key")
    $reason = [string](Get-MIRObjectProperty -Object $row -Name "reason")
    $recipe = [string](Get-MIRObjectProperty -Object $row -Name "recipe")
    $ownerKinds = [string](Get-MIRObjectProperty -Object $row -Name "owner_kinds")
    $owners = [string](Get-MIRObjectProperty -Object $row -Name "owners")

    if ($kind -eq "recipe_owner" -and $ownerKinds -match "unknown_external") {
      $groups += New-MIRFailureGroup `
        -Kind "unknown_external_owner" `
        -Scenario $scenario `
        -Mod $primaryMod `
        -Stream $stream `
        -Recipe $recipe `
        -Reason $reason `
        -Evidence $owners `
        -LikelyRemediation "Keep MIR suppressed unless repeated audit evidence supports a declarative compatibility profile."
    } elseif ($kind -eq "recipe_owner" -and $ownerKinds -match "known_competitor") {
      $groups += New-MIRFailureGroup `
        -Kind "known_competitor_not_replaced" `
        -Scenario $scenario `
        -Mod $primaryMod `
        -Stream $stream `
        -Recipe $recipe `
        -Reason $reason `
        -Evidence $owners `
        -LikelyRemediation "Check whether coverage, change value, lab science, or another owner prevented replacement."
    } elseif ($kind -eq "stream" -and $reason -match "no_lab|lab") {
      $groups += New-MIRFailureGroup `
        -Kind "invalid_science_pack" `
        -Scenario $scenario `
        -Mod $primaryMod `
        -Stream $stream `
        -Reason $reason `
        -Evidence ([string](Get-MIRObjectProperty -Object $row -Name "science")) `
        -LikelyRemediation "Review science-pack selection and lab compatibility for this modset."
    } elseif ($kind -eq "stream" -and $reason -match "missing|required") {
      $groups += New-MIRFailureGroup `
        -Kind "missing_prerequisite" `
        -Scenario $scenario `
        -Mod $primaryMod `
        -Stream $stream `
        -Reason $reason `
        -Evidence ([string](Get-MIRObjectProperty -Object $row -Name "prerequisites")) `
        -LikelyRemediation "Check required prototype gates and prerequisite resolution for this stream."
    } elseif ($reason -match "recipe_productivity_not_allowed|productivity_not_allowed") {
      $groups += New-MIRFailureGroup `
        -Kind "recipe_productivity_disallowed" `
        -Scenario $scenario `
        -Mod $primaryMod `
        -Stream $stream `
        -Recipe $recipe `
        -Reason $reason `
        -Evidence $owners `
        -LikelyRemediation "Do not force productivity onto recipes whose prototypes disallow it."
    }
  }
}

$dedup = @{}
$deduped = @()
foreach ($group in $groups) {
  $key = @(
    $group.kind,
    $group.scenario,
    $group.mod,
    $group.stream,
    $group.recipe,
    $group.reason,
    $group.evidence
  ) -join "`u{1f}"
  if ($dedup.ContainsKey($key)) { continue }
  $dedup[$key] = $true
  $deduped += $group
}

$index = 1
foreach ($group in $deduped) {
  $group.id = "FG{0:D4}" -f $index
  $index++
}

$profileCandidates = @(
  $deduped |
    Where-Object { $_.kind -in @("known_competitor_not_replaced", "unknown_external_owner", "duplicate_exact_owner", "split_productivity_family") } |
    ForEach-Object {
      [ordered]@{
        group_id = $_.id
        kind = $_.kind
        mod = $_.mod
        scenario = $_.scenario
        stream = $_.stream
        recipe = $_.recipe
        evidence = $_.evidence
        review_required = $true
      }
    }
)

$groupedPath = Join-Path $resolvedOutputDir "compat-failures.grouped.json"
$summaryPath = Join-Path $resolvedOutputDir "compat-summary.md"
$profilePath = Join-Path $resolvedOutputDir "profile-candidates.json"

[ordered]@{
  schema = 1
  generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
  audit_dir = $resolvedAuditDir
  group_count = $deduped.Count
  groups = $deduped
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $groupedPath -Encoding UTF8

[ordered]@{
  schema = 1
  generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
  candidates = $profileCandidates
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $profilePath -Encoding UTF8

$byKind = @($deduped | Group-Object kind | Sort-Object Name)
$summary = @()
$summary += "# MIR Compatibility Audit Summary"
$summary += ""
$summary += ('- Audit dir: `{0}`' -f $resolvedAuditDir)
$summary += "- Load results: $($loadResults.Count)"
$summary += "- Manual results: $($manualResults.Count)"
$summary += "- Failure groups: $($deduped.Count)"
$summary += "- Profile candidates: $($profileCandidates.Count)"
$summary += ""
$summary += "## Groups By Kind"
$summary += ""
if ($byKind.Count -eq 0) {
  $summary += "No failure groups detected."
} else {
  $summary += "| Kind | Count |"
  $summary += "| --- | ---: |"
  foreach ($group in $byKind) {
    $summary += "| $($group.Name) | $($group.Count) |"
  }
}
$summary += ""
$summary += "## Failure Groups"
$summary += ""
foreach ($group in $deduped) {
  $summary += ('- `{0}` `{1}` scenario=`{2}` mod=`{3}` stream=`{4}` recipe=`{5}` reason=`{6}`' -f $group.id, $group.kind, $group.scenario, $group.mod, $group.stream, $group.recipe, $group.reason)
}

$summary -join "`n" | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "[compat-results] wrote $summaryPath"
Write-Host "[compat-results] wrote $groupedPath"
Write-Host "[compat-results] wrote $profilePath"
