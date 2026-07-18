param(
  [Parameter(Mandatory)][ValidateSet("Approval", "Quarantine", "Demotion", "Promotion", "Migration")][string]$Kind,
  [Parameter(Mandatory)][string]$InputPath,
  [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Require-MIRText {
  param($Object, [string]$Name)
  $value = [string]$Object.PSObject.Properties[$Name].Value
  if ([string]::IsNullOrWhiteSpace($value)) { throw "$Kind record requires $Name." }
  return $value
}

function Get-MIRJsonSha256 {
  param($Value)
  $json = $Value | ConvertTo-Json -Depth 100 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $hash = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ([BitConverter]::ToString($hash)).Replace("-", "")
}

function ConvertTo-MIRApplicabilityEnvelope {
  param($Envelope)
  if (-not $Envelope) { throw "Approval record requires applicability.structural_envelope." }

  $allowedPredicates = @(
    "family.semantic-signature",
    "output.deterministic-single-item",
    "output.place-result-family",
    "recipe.productivity-eligible",
    "recipe.visible",
    "risk.none"
  )
  $factorioLines = @($Envelope.factorio_lines | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
  $requiredFeatures = @($Envelope.required_features | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
  $positiveExamples = @($Envelope.positive_examples | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
  $negativeExamples = @($Envelope.negative_examples | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
  if ($factorioLines.Count -eq 0 -or $positiveExamples.Count -eq 0 -or $negativeExamples.Count -eq 0) {
    throw "Approval applicability envelope requires Factorio lines, positive examples, and negative examples."
  }

  $requiredMods = @($Envelope.required_mods | ForEach-Object {
    $id = [string]$_.id
    if ([string]::IsNullOrWhiteSpace($id)) { throw "Approval applicability envelope contains an invalid required mod." }
    $row = [ordered]@{id=$id}
    if (-not [string]::IsNullOrWhiteSpace([string]$_.version)) { $row.version = [string]$_.version }
    [pscustomobject]$row
  } | Sort-Object id -Unique)
  if ($requiredMods.Count -eq 0) { throw "Approval applicability envelope requires a mod closure." }

  $structuralPredicates = @($Envelope.structural_predicates | ForEach-Object {
    $predicate = [string]$_.predicate
    if ($predicate -notin $allowedPredicates) {
      throw "Approval applicability envelope contains an unsupported structural predicate: $predicate"
    }
    [pscustomobject][ordered]@{predicate=$predicate}
  } | Sort-Object predicate -Unique)
  if ($structuralPredicates.Count -eq 0) { throw "Approval applicability envelope requires structural predicates." }

  $maximumNewMatches = if ($null -eq $Envelope.maximum_new_matches) { 0 } else { [int]$Envelope.maximum_new_matches }
  if ($maximumNewMatches -lt 0) { throw "Approval applicability envelope maximum_new_matches cannot be negative." }
  $record = [ordered]@{
    schema = 1
    envelope_id = [string]$Envelope.envelope_id
    factorio_lines = $factorioLines
    required_features = $requiredFeatures
    required_mods = $requiredMods
    structural_predicates = $structuralPredicates
    positive_examples = $positiveExamples
    negative_examples = $negativeExamples
    maximum_new_matches = $maximumNewMatches
  }
  if ([string]::IsNullOrWhiteSpace($record.envelope_id)) { throw "Approval applicability envelope requires envelope_id." }
  $record.envelope_fingerprint_sha256 = Get-MIRJsonSha256 $record
  return [pscustomobject]$record
}

$request = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $InputPath) | ConvertFrom-Json
$record = $null
$fingerprintField = ""

if ($Kind -in @("Approval", "Quarantine", "Demotion")) {
  $decision = @{Approval="approved"; Quarantine="quarantined"; Demotion="demoted"}[$Kind]
  $record = [ordered]@{
    schema = 1
    record_type = "TechnologyApproval"
    approval_id = Require-MIRText $request "approval_id"
    decision = $decision
    candidate_selector = [ordered]@{candidate_id=(Require-MIRText $request "candidate_id")}
    applicability = if ($request.applicability) { $request.applicability } else { [ordered]@{} }
    selected_alternative = [string]$request.selected_alternative
    approved_design_fingerprint = [string]$request.approved_design_fingerprint
    qualification_fingerprint = [string]$request.qualification_fingerprint
    locked_fields = @($request.locked_fields | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    adaptive_envelopes = if ($request.adaptive_envelopes) { $request.adaptive_envelopes } else { [ordered]@{} }
    required_evidence = @($request.required_evidence | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    reviewer = Require-MIRText $request "reviewer"
    decided_at = Require-MIRText $request "decided_at"
    reason = [string]$request.reason
  }
  if ($decision -eq "approved") {
    foreach ($field in @("selected_alternative", "approved_design_fingerprint", "qualification_fingerprint")) {
      if ([string]::IsNullOrWhiteSpace([string]$record[$field])) { throw "Approval record requires $field." }
    }
    $exactMods = @($request.applicability.exact_mods | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
    if ($exactMods.Count -eq 0) { throw "Approval record requires applicability.exact_mods." }
    $record.applicability = [ordered]@{
      exact_mods = $exactMods
      structural_envelope = ConvertTo-MIRApplicabilityEnvelope $request.applicability.structural_envelope
    }
  } elseif ([string]::IsNullOrWhiteSpace([string]$record.reason)) {
    throw "$Kind record requires reason."
  }
  $fingerprintField = "approval_fingerprint_sha256"
} elseif ($Kind -eq "Promotion") {
  $before = Require-MIRText $request "prior_identity_state"
  $after = Require-MIRText $request "identity_state"
  $allowed = @{
    "unassigned"=@("provisional"); "provisional"=@("reserved"); "reserved"=@("stable-unreleased")
    "stable-unreleased"=@("released"); "released"=@("retired"); "retired"=@()
  }
  if (-not $allowed.ContainsKey($before) -or $after -notin @($allowed[$before])) {
    throw "TechnologyPromotion identity transition is not permitted: $before -> $after"
  }
  $record = [ordered]@{
    schema = 1
    record_type = "TechnologyPromotion"
    promotion_id = Require-MIRText $request "promotion_id"
    technology_id = Require-MIRText $request "technology_id"
    candidate_id = Require-MIRText $request "candidate_id"
    approval_id = Require-MIRText $request "approval_id"
    approved_design_fingerprint = Require-MIRText $request "approved_design_fingerprint"
    prior_identity_state = $before
    identity_state = $after
    migration_policy = Require-MIRText $request "migration_policy"
    introduced_in = Require-MIRText $request "introduced_in"
    evidence = @($request.evidence | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  }
  $fingerprintField = "promotion_fingerprint_sha256"
} else {
  $strategy = Require-MIRText $request "strategy"
  if ($strategy -notin @("retain-hidden-alias", "retain-visible-alias", "in-place-compatible", "retire-with-replacement")) {
    throw "TechnologyMigration strategy is invalid: $strategy"
  }
  $record = [ordered]@{
    schema = 1
    record_type = "TechnologyMigration"
    migration_id = Require-MIRText $request "migration_id"
    from_technology_id = Require-MIRText $request "from_technology_id"
    to_technology_id = Require-MIRText $request "to_technology_id"
    strategy = $strategy
    save_behavior = Require-MIRText $request "save_behavior"
    approval_id = Require-MIRText $request "approval_id"
    evidence = @($request.evidence | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  }
  if ($record.from_technology_id -eq $record.to_technology_id -and $strategy -ne "in-place-compatible") {
    throw "Identity-preserving migration requires in-place-compatible strategy."
  }
  $fingerprintField = "migration_fingerprint_sha256"
}

$record[$fingerprintField] = Get-MIRJsonSha256 $record
$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$record | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "[ok] wrote $($record.record_type) $OutputPath"
