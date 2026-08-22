if (-not (Get-Command Get-MIR4ModuleDigest -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'ModuleEcosystem.ps1')
}

function Get-MIR4W07RepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Import-MIR4W07CanonicalSupport {
  param([Parameter(Mandatory)][string]$RepoRoot)
  foreach ($name in @('ConvertTo-MIR4ModuleCanonicalJson','Get-MIR4ModuleDigest','Add-MIR4ModuleDigest')) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "[mir4-w07-canonical-support] $name" }
  }
}

function Get-MIR4W07FileSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-MIR4InspectorCompatibilityAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4W07RepoRoot $RepoRoot
  $path = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Inspector-Compatibility-ProgrammeV1.json'
  $authority = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([int]$authority.schema -ne 1 -or [string]$authority.kind -cne 'MIR4InspectorCompatibilityProgrammeV1') { throw '[mir4-w07-authority]' }
  foreach ($flag in @(
    'semantic_authority','terminal_compatibility_policy_authority','terminal_claim_authority',
    'player_package_mutation_authorized','prototype_write_authorized','runtime_state_mutation_authorized',
    'migration_execution_authorized','planner_or_emitter_admission_authorized','safety_kernel_override_authorized',
    'arbitrary_code_generation_authorized','network_or_upload_authorized','public_support_authorized',
    'signing_or_sealing_authorized','publication_authorized'
  )) {
    if ([bool]$authority.$flag) { throw "[mir4-w07-boundary] $flag" }
  }
  if (@($authority.inspector_sections).Count -ne 11 -or @($authority.named_ecosystems).Count -ne 10 -or
      @($authority.safe_choice_priority).Count -ne 7 -or @($authority.outputs).Count -ne 2) {
    throw '[mir4-w07-authority-cardinality]'
  }
  foreach ($input in @($authority.inputs)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo ([string]$input)) -PathType Leaf)) { throw "[mir4-w07-input] $input" }
  }
  return $authority
}

function Test-MIR4W07ForbiddenValue {
  param([AllowNull()]$Value,[Parameter(Mandatory)][string[]]$Forbidden,[string]$Path='$')
  if ($null -eq $Value) { return }
  if ($Value -is [pscustomobject]) {
    foreach ($property in $Value.PSObject.Properties) {
      if ([string]$property.Name -cin $Forbidden -or [string]$property.Name -match '(?i)^modpack[_-]?supported$') {
        throw "[mir4-w07-forbidden-field] $Path.$($property.Name)"
      }
      Test-MIR4W07ForbiddenValue -Value $property.Value -Forbidden $Forbidden -Path "$Path.$($property.Name)"
    }
  } elseif ($Value -is [Collections.IDictionary]) {
    foreach ($key in $Value.Keys) {
      if ([string]$key -cin $Forbidden -or [string]$key -match '(?i)^modpack[_-]?supported$') {
        throw "[mir4-w07-forbidden-field] $Path.$key"
      }
      Test-MIR4W07ForbiddenValue -Value $Value[$key] -Forbidden $Forbidden -Path "$Path.$key"
    }
  } elseif ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    $index = 0
    foreach ($item in $Value) {
      Test-MIR4W07ForbiddenValue -Value $item -Forbidden $Forbidden -Path "$Path[$index]"
      $index++
    }
  }
}

function Get-MIR4W07TargetBinding {
  param([Parameter(Mandatory)]$Registry,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$RegistrySha256)
  Import-MIR4W07CanonicalSupport -RepoRoot $script:MIR4W07CurrentRepoRoot
  $row = @($Registry.identities | Where-Object target -eq $Target)
  if ($row.Count -ne 1) { throw "[mir4-w07-target-binding] $Target" }
  $identity = (($row[0] | ConvertTo-Json -Depth 50 -Compress) | ConvertFrom-Json)
  return [ordered]@{
    target=$Target
    factorio_line=[string]$identity.factorio_line
    distribution_version=[string]$identity.distribution_version
    provider_authority='.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json'
    provider_authority_sha256=$RegistrySha256
    provider_identity_digest=(Get-MIR4ModuleDigest $identity)
  }
}

function Get-MIR4W07SubjectMetadata {
  return [ordered]@{
    'base-and-official'=[ordered]@{title='Base and official closures';capabilities=@('base-startup','space-age-startup');preferred='preserve-review-or-omit'}
    'aai'=[ordered]@{title='AAI';capabilities=@('representative-extension-coexistence','loader-manufacturing-observation');preferred='target-capability-or-provider'}
    'bz'=[ordered]@{title='BZ';capabilities=@('resource-suite-startup','generic-recipe-classification');preferred='generic-compiler-correction'}
    'industrial-revolution-3'=[ordered]@{title='Industrial Revolution 3';capabilities=@('unknown-until-exact-closure');preferred='preserve-review-or-omit'}
    'industrial-revolution-4'=[ordered]@{title='Industrial Revolution 4';capabilities=@('unknown-until-independent-consumer');preferred='preserve-review-or-omit'}
    'k2-k2so'=[ordered]@{title='Krastorio 2 / K2SO';capabilities=@('bounded-science-phase-policy','science-lab-integrity');preferred='generic-compiler-correction'}
    'space-exploration'=[ordered]@{title='Space Exploration';capabilities=@('finalized-recipe-integrity','extension-required');preferred='ecosystem-profile'}
    'bob'=[ordered]@{title='Bob';capabilities=@('named-suite-startup','generic-effect-ownership-observation');preferred='generic-effect-channel-or-operator'}
    'angel'=[ordered]@{title='Angel';capabilities=@('unknown-until-complete-dependency-closure');preferred='preserve-review-or-omit'}
    'pyanodons'=[ordered]@{title='Pyanodons';capabilities=@('finalized-technology-integrity','unknown-until-current-closure');preferred='preserve-review-or-omit'}
  }
}

function New-MIR4CompatibilitySubjectLedger {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$SourceIdentity=$null)
  $repo = Get-MIR4W07RepoRoot $RepoRoot
  $script:MIR4W07CurrentRepoRoot = $repo
  Import-MIR4W07CanonicalSupport -RepoRoot $repo
  $authority = Get-MIR4InspectorCompatibilityAuthority -RepoRoot $repo
  $solPath = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Compatibility-Campaign-SOL07V1.json'
  $registryPath = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json'
  $compatPath = Join-Path $repo '.mir/compatibility.yml'
  $claimsPath = Join-Path $repo 'spec/compatibility/claims.json'
  $sol = Get-Content -Raw -LiteralPath $solPath | ConvertFrom-Json -Depth 100
  $registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json -Depth 100
  $solSha = Get-MIR4W07FileSha256 $solPath
  $registrySha = Get-MIR4W07FileSha256 $registryPath
  $metadata = Get-MIR4W07SubjectMetadata
  $bindingById = @{}; foreach ($binding in @($sol.evidence_bindings)) { $bindingById[[string]$binding.id] = $binding }
  $subjects = @(
    foreach ($id in @($authority.named_ecosystems)) {
      $source = @($sol.subjects | Where-Object id -eq ([string]$id))
      if ($source.Count -ne 1) { throw "[mir4-w07-sol07-subject] $id" }
      $source = $source[0]
      $hasEvidence = @($source.evidence_ids).Count -gt 0
      $evidence = @(
        foreach ($evidenceId in @($source.evidence_ids | Sort-Object)) {
          if (-not $bindingById.ContainsKey([string]$evidenceId)) { throw "[mir4-w07-sol07-evidence] $evidenceId" }
          $binding = $bindingById[[string]$evidenceId]
          [ordered]@{
            id=[string]$evidenceId
            status='historical-development-evidence-nontransferable'
            path=[string]$binding.path
            file_sha256=([string]$binding.file_sha256).ToLowerInvariant()
            candidate_sha256=([string]$binding.candidate_sha256).ToLowerInvariant()
            engine_sha256=([string]$binding.engine_sha256).ToLowerInvariant()
            accepted_scenarios=@($binding.accepted_scenarios | ForEach-Object { [string]$_ } | Sort-Object)
            claim_eligible=$false
          }
        }
      )
      $targets = if ($id -eq 'k2-k2so') { @('f210','f200') } else { @('f210') }
      $targetBindings = @($targets | ForEach-Object { Get-MIR4W07TargetBinding -Registry $registry -Target $_ -RegistrySha256 $registrySha })
      $proofStatus = if ($hasEvidence) { 'historical-development-evidence-nontransferable' } else { 'review-required/no-governed-exact-archive-closure' }
      $availability = switch ([string]$source.outcome) {
        'LOAD' { 'narrow-load-observed' }
        'INTEGRITY' { 'named-integrity-observed' }
        'extension-required' { 'extension-required' }
        default { 'review-required' }
      }
      $blockers = @()
      if (-not [string]::IsNullOrWhiteSpace([string]$source.blocker)) { $blockers += [string]$source.blocker }
      if ($id -eq 'industrial-revolution-4') { $blockers += 'BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER' }
      $row = [pscustomobject][ordered]@{
        ecosystem=[string]$metadata[$id].title
        subject_id=[string]$id
        subject_kind='ecosystem-profile'
        target_bindings=$targetBindings
        capabilities_or_streams=@($metadata[$id].capabilities)
        availability=[ordered]@{state=$availability;qualified_surface=[string]$source.qualified_surface;excluded_surface=@($source.excluded_surface | ForEach-Object { [string]$_ })}
        hard_safety=[ordered]@{state=$(if($hasEvidence){'preserved-within-historical-scope'}else{'unknown-no-exact-closure'});override_authorized=$false}
        implementation=[ordered]@{preferred_safe_choice=[string]$metadata[$id].preferred;automatic_mutation=$false;exact_fragment_admitted=$false}
        target_portability=[ordered]@{state=$(if($hasEvidence){'historical-target-bound-nontransferable'}else{'not-assessed'});cross_target_transfer_authorized=$false}
        migration=[ordered]@{state='unproven';execution_authorized=$false}
        proof=[ordered]@{state=$proofStatus;evidence=$evidence;synthetic_can_satisfy_exact=$false;public_release_proof=$false}
        claim=[ordered]@{source_level=[string]$source.claim_level;state='not-claim-eligible';eligible=$false;public_authorized=$false;blanket=$false}
        evidence=[ordered]@{authority_path='.mir/releases/waves/mir4-r0/MIR4-Compatibility-Campaign-SOL07V1.json';authority_sha256=$solSha;status=$proofStatus;scenario_ids=@($source.exact_scenarios | ForEach-Object { [string]$_ } | Sort-Object)}
        revocation=[ordered]@{state=$(if($hasEvidence){'active-private-source-binding'}else{'missing-evidence-blocked'});actual_claim_revocation_authority=$false;invalid_if=@('authority-digest-changes','target-provider-digest-changes','evidence-binding-disappears')}
        blockers=@($blockers | Sort-Object -Unique)
      }
      $row
    }
  )
  $targetDispositions = @(
    foreach ($identity in @($registry.identities | Sort-Object target)) {
      $target = [string]$identity.target
      [ordered]@{
        target=$target
        factorio_line=[string]$identity.factorio_line
        distribution_version=[string]$identity.distribution_version
        provider_identity_digest=(Get-MIR4ModuleDigest $identity)
        disposition=$(if($target -in @('f210','f200')){'private-target-bound-evidence-only'}elseif($target -in @('f110','f100')){'independent-private-preview'}elseif($target -in @('f018','f017','f016','f015','f014','f013')){'target-local-private-experimental'}else{'BLOCKED_WITH_EVIDENCE'})
        cross_target_transfer_authorized=$false
      }
    }
  )
  $record = [pscustomobject][ordered]@{
    schema=1
    kind='MIR4CompatibilitySubjectLedgerV1'
    programme_id=[string]$authority.programme_id
    source_identity=$SourceIdentity
    maturity='developer-preview'
    authority='W07-normalized-private-assessment-only'
    input_digests=[ordered]@{
      w07_authority=(Get-MIR4W07FileSha256 (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Inspector-Compatibility-ProgrammeV1.json'))
      sol07=$solSha
      target_registry=$registrySha
      terminal_compatibility=(Get-MIR4W07FileSha256 $compatPath)
      terminal_claims=(Get-MIR4W07FileSha256 $claimsPath)
    }
    evidence_policy=[ordered]@{inherited_sol07='historical-development-evidence-nontransferable';synthetic='synthetic-fixture/nonclaim-preview';missing_closure='review-required/no-governed-exact-archive-closure';public_claim_transfer_authorized=$false}
    subject_count=$subjects.Count
    subjects=$subjects
    target_dispositions=$targetDispositions
    blanket_support_boolean_present=$false
    package_visible=$false
    public_release_proof=$false
    player_mutation_authorized=$false
    public_support_authorized=$false
    digest=''
  }
  Add-MIR4ModuleDigest $record | Out-Null
  Test-MIR4CompatibilitySubjectLedger -Ledger $record -RepoRoot $repo | Out-Null
  return $record
}

function Test-MIR4CompatibilitySubjectLedger {
  param([Parameter(Mandatory)]$Ledger,[Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4W07RepoRoot $RepoRoot
  Import-MIR4W07CanonicalSupport -RepoRoot $repo
  $authority = Get-MIR4InspectorCompatibilityAuthority -RepoRoot $repo
  Test-MIR4W07ForbiddenValue -Value $Ledger -Forbidden @($authority.forbidden_import_fields)
  if ([int]$Ledger.schema -ne 1 -or [string]$Ledger.kind -cne 'MIR4CompatibilitySubjectLedgerV1' -or
      [string]$Ledger.maturity -cne 'developer-preview' -or [int]$Ledger.subject_count -ne 10 -or
      @($Ledger.subjects).Count -ne 10 -or @($Ledger.target_dispositions).Count -ne 17 -or
      [bool]$Ledger.blanket_support_boolean_present -or [bool]$Ledger.package_visible -or
      [bool]$Ledger.public_release_proof -or [bool]$Ledger.player_mutation_authorized -or [bool]$Ledger.public_support_authorized) {
    throw '[mir4-w07-ledger-header]'
  }
  $ids = @($Ledger.subjects | ForEach-Object { [string]$_.subject_id })
  if (@($ids | Sort-Object -Unique).Count -ne 10 -or (@($ids | Sort-Object) -join '|') -cne (@($authority.named_ecosystems | Sort-Object) -join '|')) {
    throw '[mir4-w07-ledger-subject-set]'
  }
  foreach ($subject in @($Ledger.subjects)) {
    if ([bool]$subject.claim.eligible -or [bool]$subject.claim.public_authorized -or [bool]$subject.claim.blanket -or
        [bool]$subject.implementation.automatic_mutation -or [bool]$subject.target_portability.cross_target_transfer_authorized -or
        @($subject.target_bindings).Count -eq 0) { throw "[mir4-w07-ledger-boundary] $($subject.subject_id)" }
    foreach ($target in @($subject.target_bindings)) {
      if ([string]$target.provider_identity_digest -cnotmatch '^sha256:[0-9a-f]{64}$' -or
          [string]$target.provider_authority_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw "[mir4-w07-target-digest] $($subject.subject_id)" }
    }
    foreach ($evidence in @($subject.proof.evidence)) {
      if ([string]$evidence.status -cne 'historical-development-evidence-nontransferable' -or [bool]$evidence.claim_eligible) {
        throw "[mir4-w07-evidence-transfer] $($subject.subject_id)"
      }
    }
  }
  foreach ($id in @('industrial-revolution-3','industrial-revolution-4','angel','pyanodons')) {
    $row = @($Ledger.subjects | Where-Object subject_id -eq $id)[0]
    if ([string]$row.proof.state -cne 'review-required/no-governed-exact-archive-closure') { throw "[mir4-w07-missing-closure] $id" }
  }
  $se = @($Ledger.subjects | Where-Object subject_id -eq 'space-exploration')[0]
  if ([string]$se.availability.state -cne 'extension-required' -or [string]$se.proof.state -cne 'review-required/no-governed-exact-archive-closure') { throw '[mir4-w07-se-boundary]' }
  $ir4 = @($Ledger.subjects | Where-Object subject_id -eq 'industrial-revolution-4')[0]
  if ('BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER' -notin @($ir4.blockers)) { throw '[mir4-w07-ir4-blocker]' }
  if ([string]$Ledger.digest -cne (Get-MIR4ModuleDigest $Ledger)) { throw '[mir4-w07-ledger-digest]' }
  return $true
}
