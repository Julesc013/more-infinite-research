. (Join-Path $PSScriptRoot 'TargetKey.ps1')

function Get-MIR4AcceptanceSha256 {
  param([Parameter(Mandatory)]$Value)
  $digestValue = $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
  if ($null -ne $digestValue.PSObject.Properties['queue_sha256']) { $digestValue.queue_sha256 = '' }
  $json = $digestValue | ConvertTo-Json -Depth 100 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $hash = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ([BitConverter]::ToString($hash)).Replace('-', '')
}

function New-MIR4TechnologyAcceptanceQueue {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CatalogPath,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$Ecosystem
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $programme = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json') | ConvertFrom-Json -Depth 100
  if ($Ecosystem -cnotin @($programme.ecosystem_order | ForEach-Object { [string]$_ })) {
    throw "[mir4-acceptance-ecosystem] Unknown ecosystem '$Ecosystem'."
  }
  $catalog = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $CatalogPath) | ConvertFrom-Json -Depth 100
  if ([int]$catalog.schema -ne 3 -or [string]$catalog.phase -cne 'final' -or [bool]$catalog.mutation_authority -or
      [string]$catalog.selection_authority -cne 'deterministic-policy-v2') {
    throw '[mir4-acceptance-catalog] Exact non-mutating final TechnologyCatalog schema 3 is required.'
  }
  foreach ($field in @('catalog_fingerprint', 'selection_fingerprint')) {
    if ([string]::IsNullOrWhiteSpace([string]$catalog.$field)) { throw "[mir4-acceptance-catalog-field] $field" }
  }
  $projection = New-MIR4TargetKeyProjection -Target $Target
  $candidateById = @{}
  foreach ($candidate in @($catalog.candidates)) {
    $candidateId = [string]$candidate.candidate_id
    if ([string]::IsNullOrWhiteSpace($candidateId) -or $candidateById.ContainsKey($candidateId)) {
      throw "[mir4-acceptance-candidate] Candidate identity is missing or duplicated: $candidateId"
    }
    $candidateById[$candidateId] = $candidate
  }
  $requiredRecords = @($programme.technology_acceptance_contract.required_records | ForEach-Object { [string]$_ })
  $entries = @()
  $ordinal = 0
  foreach ($selection in @($catalog.current_selections | Sort-Object candidate_id)) {
    $candidateId = [string]$selection.candidate_id
    if (-not $candidateById.ContainsKey($candidateId)) { throw "[mir4-acceptance-selection] Unknown candidate: $candidateId" }
    $alternatives = @($candidateById[$candidateId].alternatives | Where-Object { [string]$_.alternative_id -ceq [string]$selection.alternative_id })
    if ($alternatives.Count -ne 1) { throw "[mir4-acceptance-alternative] Selection is missing or ambiguous: $candidateId" }
    $alternative = $alternatives[0]
    if ([string]$alternative.design_fingerprint -cne [string]$selection.design_fingerprint -or
        [string]$alternative.qualification_fingerprint -cne [string]$selection.qualification_fingerprint) {
      throw "[mir4-acceptance-selection-fingerprint] $candidateId"
    }
    $ordinal++
    $qualificationDecision = [string]$alternative.qualification_decision
    $materializes = [string]$alternative.disposition -ceq 'materialize' -or [string]$alternative.action -ceq 'emit'
    $acceptanceState = if ($qualificationDecision -cne 'qualified') {
      'blocked-qualification'
    } elseif ($materializes) {
      'awaiting-quality-and-review'
    } else {
      'diagnostic-or-nonmaterializing'
    }
    $technologyId = $null
    if ($null -ne $alternative.technology_design -and $null -ne $alternative.technology_design.PSObject.Properties['technology_id']) {
      $technologyId = [string]$alternative.technology_design.technology_id
    }
    $entries += [pscustomobject][ordered]@{
      ordinal = $ordinal
      candidate_id = $candidateId
      technology_id = $technologyId
      alternative_id = [string]$alternative.alternative_id
      action = [string]$alternative.action
      disposition = [string]$alternative.disposition
      design_fingerprint = [string]$alternative.design_fingerprint
      qualification_fingerprint = [string]$alternative.qualification_fingerprint
      qualification_decision = $qualificationDecision
      acceptance_state = $acceptanceState
      maintainer_decision = 'pending'
      required_records = $requiredRecords
      review_checklist = @(
        'semantic membership and exclusions',
        'technology-tree placement and prerequisite arrows',
        'science and accepting-lab reachability',
        'effect magnitude and cost curve',
        'cross-version additions and removals',
        'identity migration and locked fields'
      )
    }
  }
  if ($entries.Count -ne $candidateById.Count) {
    throw '[mir4-acceptance-totality] Every catalog candidate must have exactly one current selection.'
  }
  $queue = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4TechnologyAcceptanceQueueV1'
    programme_id = [string]$programme.programme_id
    source_version = [string]$programme.source_version
    target = [string]$projection.target
    legacy_target = [string]$projection.legacy_target
    ecosystem = $Ecosystem
    catalog_fingerprint = [string]$catalog.catalog_fingerprint
    selection_fingerprint = [string]$catalog.selection_fingerprint
    candidate_count = $entries.Count
    entries = $entries
    rules = @(
      'Queue creation never accepts or promotes a technology.',
      'Each entry binds one exact candidate selected design and qualification.',
      'Maintainer review remains mandatory for every materializing technology.',
      'Pack-level compatibility claims never follow from queue membership.'
    )
    mutation_authorized = $false
    compatibility_claim_authorized = $false
    publication_authorized = $false
    queue_sha256 = ''
  }
  $queue.queue_sha256 = Get-MIR4AcceptanceSha256 -Value $queue
  return $queue
}
