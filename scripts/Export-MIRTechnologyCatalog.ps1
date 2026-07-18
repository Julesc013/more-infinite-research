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

$plan = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $GenerationPlanPath) | ConvertFrom-Json
$candidateMap = @{}
$qualifications = @()

foreach ($row in @(Get-MIRProperty $plan "rows" @())) {
  $design = Get-MIRProperty $row "technology_design"
  if ($null -eq $design) { throw "GenerationPlan row lacks TechnologyDesign: $($row.stream_key)" }
  $candidateId = [string]$design.candidate_id
  if ([string]::IsNullOrWhiteSpace($candidateId)) { throw "TechnologyDesign candidate_id is required." }

  $candidateMaterial = [ordered]@{
    schema = 1
    candidate_id = $candidateId
    semantic_identity = $design.semantic_identity
    subjects = $design.subjects
    discovery = [ordered]@{
      provider_ids = @($row.provider_ids | ForEach-Object { [string]$_ } | Sort-Object -Unique)
      family_ids = @($row.family_ids | ForEach-Object { [string]$_ } | Sort-Object -Unique)
      source = [string]$row.source
      evidence = [ordered]@{
        manifest_id = [string]$row.manifest_id
        stream_key = [string]$row.stream_key
        action = [string]$row.action
      }
    }
  }
  $candidateFingerprint = Get-MIRJsonSha256 $candidateMaterial
  if ($candidateMap.ContainsKey($candidateId) -and
      $candidateMap[$candidateId].candidate_fingerprint_sha256 -ne $candidateFingerprint) {
    throw "Candidate identity has contradictory discovery material: $candidateId"
  }
  if (-not $candidateMap.ContainsKey($candidateId)) {
    $candidate = [ordered]@{}
    foreach ($entry in $candidateMaterial.GetEnumerator()) { $candidate[$entry.Key] = $entry.Value }
    $candidate["candidate_fingerprint_sha256"] = $candidateFingerprint
    $candidate["alternatives"] = @()
    $candidateMap[$candidateId] = $candidate
  }

  $target = [string](Get-MIRProperty $design.materialization "target" (Get-MIRProperty $design "technology_id" $candidateId))
  $alternative = [ordered]@{
    alternative_id = "$($design.materialization.kind):$target"
    action = [string]$row.action
    materialization = $design.materialization
    design_fingerprint = [string]$design.design_fingerprint
    prototype_fingerprint = [string]$design.prototype_fingerprint
    qualification_fingerprint = [string]$design.qualification_fingerprint
  }
  $candidateMap[$candidateId]["alternatives"] = @($candidateMap[$candidateId]["alternatives"]) + @($alternative)

  $failed = @()
  foreach ($gateProperty in @($row.gates.PSObject.Properties | Sort-Object Name)) {
    if ([string]$gateProperty.Value.status -eq "failed") {
      $failed += [ordered]@{
        gate = $gateProperty.Name
        reason = [string]$gateProperty.Value.reason
        evidence = @($gateProperty.Value.evidence)
      }
    }
  }
  if ($failed.Count -eq 0 -and [string]$row.action -eq "skip") {
    $failed += [ordered]@{gate="materialization"; reason=[string]$row.reason; evidence=@("generation-plan:$($row.reason)")}
  }
  $qualificationMaterial = [ordered]@{
    schema = 1
    candidate_id = $candidateId
    design_fingerprint = [string]$design.design_fingerprint
    context_fingerprint = [string]$design.qualification_fingerprint
    hard_gates = $row.gates
    quality_metrics = [ordered]@{status="unmeasured"}
    decision = if ($failed.Count -gt 0) { "rejected" } elseif ([string]$row.action -in @("emit", "adopt")) { "qualified" } else { "proposal" }
    primary_rejection = if ($failed.Count -gt 0) { $failed[0] } else { $null }
    contributing_rejections = $failed
  }
  $qualification = [ordered]@{}
  foreach ($entry in $qualificationMaterial.GetEnumerator()) { $qualification[$entry.Key] = $entry.Value }
  $qualification["qualification_fingerprint_sha256"] = Get-MIRJsonSha256 $qualificationMaterial
  $qualifications += $qualification
}

$candidates = @($candidateMap.Values | Sort-Object { $_["candidate_id"] })
foreach ($candidate in $candidates) {
  $candidate["alternatives"] = @($candidate["alternatives"] | Sort-Object { $_["alternative_id"] })
}
$qualifications = @($qualifications | Sort-Object { $_["candidate_id"] }, { $_["design_fingerprint"] })
$catalogMaterial = [ordered]@{
  schema = 1
  kind = "mir-technology-catalog"
  source_plan_fingerprint = [string](Get-MIRProperty $plan "plan_fingerprint" "")
  candidates = $candidates
  qualifications = $qualifications
}
$catalog = [ordered]@{}
foreach ($entry in $catalogMaterial.GetEnumerator()) { $catalog[$entry.Key] = $entry.Value }
$catalog["candidate_catalog_sha256"] = Get-MIRJsonSha256 $candidates
$catalog["qualification_catalog_sha256"] = Get-MIRJsonSha256 $qualifications
$catalog["catalog_sha256"] = Get-MIRJsonSha256 $catalogMaterial

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$catalog | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "[ok] wrote MIR technology catalog $OutputPath candidates=$($candidates.Count) qualifications=$($qualifications.Count)"
