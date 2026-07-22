param(
  [Parameter(Mandatory)][string]$GenerationPlanPath,
  [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Get-MIRJsonSha256 {
  param($Value)
  $json = $Value | ConvertTo-Json -Depth 100 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $hash = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ([BitConverter]::ToString($hash)).Replace("-", "")
}

function Get-MIRProperty {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function New-MIRQualification {
  param($Row, $Design, [string]$Action, [bool]$Diagnostic)
  $failed = @()
  if (-not $Diagnostic) {
    foreach ($gateProperty in @($Row.gates.PSObject.Properties | Sort-Object Name)) {
      if ([string]$gateProperty.Value.status -eq "failed") {
        $failed += [ordered]@{
          gate = $gateProperty.Name
          reason = [string]$gateProperty.Value.reason
          evidence = @($gateProperty.Value.evidence)
        }
      }
    }
  }
  $material = [ordered]@{
    schema = 1
    candidate_id = [string]$Design.candidate_id
    design_fingerprint = [string]$Design.design_fingerprint
    context_fingerprint = [string]$Design.qualification_fingerprint
    hard_gates = if ($Diagnostic) { [ordered]@{} } else { $Row.gates }
    quality_metrics = [ordered]@{status="UNMEASURED"}
    decision = if ($failed.Count -gt 0) { "rejected" } elseif ($Action -in @("emit", "adopt", "diagnose")) { "qualified" } else { "proposal" }
    primary_rejection = if ($failed.Count -gt 0) { $failed[0] } else { $null }
    contributing_rejections = $failed
    validation_evidence = if ($Diagnostic) { "candidate-catalog-safe-diagnostic" } else { [string]$Design.maturity.validation_evidence }
  }
  $record = [ordered]@{}
  foreach ($entry in $material.GetEnumerator()) { $record[$entry.Key] = $entry.Value }
  $record.qualification_fingerprint_sha256 = Get-MIRJsonSha256 $material
  return $record
}

$plan = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $GenerationPlanPath) | ConvertFrom-Json
$candidates = @()
$qualifications = @()
$alternativeQualifications = @()
$selections = @()

foreach ($row in @(Get-MIRProperty $plan "rows" @())) {
  $design = Get-MIRProperty $row "technology_design"
  if ($null -eq $design) { throw "GenerationPlan row lacks TechnologyDesign: $($row.stream_key)" }
  $candidateId = [string]$design.candidate_id
  if ([string]::IsNullOrWhiteSpace($candidateId)) { throw "TechnologyDesign candidate_id is required." }
  $selectionKey = "$($row.stream_key):$($row.manifest_id)"
  $candidateMaterial = [ordered]@{
    schema = 1
    candidate_id = $candidateId
    semantic_identity = $design.semantic_identity
    subjects = $design.subjects
    discovery = [ordered]@{
      provider_ids = @($row.provider_ids | ForEach-Object { [string]$_ } | Sort-Object -Unique)
      family_ids = @($row.family_ids | ForEach-Object { [string]$_ } | Sort-Object -Unique)
      source = [string]$row.source
      evidence = [ordered]@{manifest_id=[string]$row.manifest_id; stream_key=[string]$row.stream_key; action=[string]$row.action}
      feature_signature = Get-MIRJsonSha256 ([ordered]@{semantic_identity=$design.semantic_identity; subjects=$design.subjects})
    }
  }
  $candidate = [ordered]@{}
  foreach ($entry in $candidateMaterial.GetEnumerator()) { $candidate[$entry.Key] = $entry.Value }
  $candidate.candidate_fingerprint_sha256 = Get-MIRJsonSha256 $candidateMaterial
  $candidate.selection_key = $selectionKey
  $candidate.alternatives = @()

  $entries = @()
  if ([string]$row.action -in @("emit", "adopt")) {
    $target = [string](Get-MIRProperty $design.materialization "target" (Get-MIRProperty $design "technology_id" $candidateId))
    $entries += [pscustomobject]@{Action=[string]$row.action; Id="$($design.materialization.kind):$target"; Design=$design; Diagnostic=$false}
  }
  $diagnosticDesignFingerprint = Get-MIRJsonSha256 ([ordered]@{design_fingerprint=[string]$design.design_fingerprint; materialization="diagnose"})
  $diagnosticDesign = [ordered]@{
    candidate_id=$candidateId
    design_fingerprint=$diagnosticDesignFingerprint
    prototype_fingerprint=(Get-MIRJsonSha256 ([ordered]@{candidate_id=$candidateId; prototype="none"}))
    qualification_fingerprint=(Get-MIRJsonSha256 ([ordered]@{candidate_id=$candidateId; action="diagnose"}))
    materialization=[ordered]@{kind="diagnose"}
    maturity=[ordered]@{validation_evidence="candidate-catalog-safe-diagnostic"}
  }
  $entries += [pscustomobject]@{Action="diagnose"; Id="diagnose:$candidateId"; Design=$diagnosticDesign; Diagnostic=$true}

  foreach ($entry in $entries) {
    $qualification = New-MIRQualification -Row $row -Design $entry.Design -Action $entry.Action -Diagnostic $entry.Diagnostic
    $alternative = [ordered]@{
      alternative_id=$entry.Id
      action=$entry.Action
      materialization=$entry.Design.materialization
      design_fingerprint=[string]$entry.Design.design_fingerprint
      prototype_fingerprint=[string]$entry.Design.prototype_fingerprint
      qualification_fingerprint=[string]$qualification.qualification_fingerprint_sha256
      qualification_decision=[string]$qualification.decision
    }
    $candidate.alternatives = @($candidate.alternatives) + @($alternative)
    $qualifications += $qualification
    $alternativeQualifications += [ordered]@{
      candidate_id=$candidateId; alternative_id=$entry.Id
      design_fingerprint=$alternative.design_fingerprint
      qualification_fingerprint=$alternative.qualification_fingerprint
      decision=$alternative.qualification_decision
    }
  }
  $candidate.alternatives = @($candidate.alternatives | Sort-Object alternative_id)
  $selectedAction = if ([string]$row.action -in @("emit", "adopt")) { [string]$row.action } else { "diagnose" }
  $selected = @($candidate.alternatives | Where-Object { $_.action -eq $selectedAction })[0]
  if (-not $selected -or $selected.qualification_decision -ne "qualified") {
    throw "TechnologyCatalog selected alternative is absent or rejected: $candidateId/$selectedAction"
  }
  $selections += [ordered]@{
    selection_key=$selectionKey; candidate_id=$candidateId; alternative_id=$selected.alternative_id
    action=$selected.action; reason=[string]$row.reason
    design_fingerprint=$selected.design_fingerprint; qualification_fingerprint=$selected.qualification_fingerprint
  }
  $candidates += $candidate
}

$candidates = @($candidates | Sort-Object candidate_id)
$qualifications = @($qualifications | Sort-Object candidate_id, design_fingerprint)
$alternativeQualifications = @($alternativeQualifications | Sort-Object candidate_id, alternative_id)
$selections = @($selections | Sort-Object candidate_id)
$preselectionMaterial = [ordered]@{
  schema=2; candidates=$candidates; qualifications=$qualifications
  alternative_qualifications=$alternativeQualifications
  source_plan_fingerprint=[string](Get-MIRProperty $plan "plan_fingerprint" "")
  mutation_authority=$false; selection_authority="generation-plan-shadow"
}
$catalog = [ordered]@{}
foreach ($entry in $preselectionMaterial.GetEnumerator()) { $catalog[$entry.Key] = $entry.Value }
$catalog.kind = "mir-technology-catalog"
$catalog.current_selections = $selections
$catalog.candidate_catalog_sha256 = Get-MIRJsonSha256 $candidates
$catalog.qualification_catalog_sha256 = Get-MIRJsonSha256 $qualifications
$catalog.preselection_catalog_sha256 = Get-MIRJsonSha256 $preselectionMaterial
$catalog.selection_sha256 = Get-MIRJsonSha256 $selections
$catalog.catalog_sha256 = Get-MIRJsonSha256 ([ordered]@{preselection=$catalog.preselection_catalog_sha256; selections=$catalog.selection_sha256})

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$catalog | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "[ok] wrote MIR TechnologyCatalog schema 2 $OutputPath candidates=$($candidates.Count) alternatives=$($alternativeQualifications.Count)"
