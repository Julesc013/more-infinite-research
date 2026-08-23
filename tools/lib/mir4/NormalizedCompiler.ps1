function New-MIR4NormalizedTargetProviders {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $registry = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json') | ConvertFrom-Json
  $supportByTarget = @{}
  foreach ($row in $registry.support_policy) { $supportByTarget[[string]$row.target] = $row }
  $profiles = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/targets.json') | ConvertFrom-Json
  $plan = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV3.json') | ConvertFrom-Json
  $planById = @{}
  foreach ($target in $plan.targets) { $planById[[string]$target.target_id] = $target }
  $historical = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Historical-Private-Candidate-AuthorizationV1.json') | ConvertFrom-Json
  $historicalByKey = @{}
  foreach ($target in $historical.targets) { $historicalByKey[[string]$target.target_key] = $target }

  return @(
    foreach ($target in $registry.identities) {
      $id = [string]$target.target_id
      $code = [string]$target.distribution_target_code
      $targetKey = [string]$target.target
      $support = $supportByTarget[$targetKey]
      if ($null -eq $support) { throw "[mir4-target-support-policy] $targetKey" }
      $planned = $planById[$id]
      $historicalTarget = $historicalByKey[$targetKey]
      $predecessor = [string]$target.mir3_predecessor
      $snapshot = Get-MIR4PlatformPredecessorPath $predecessor
      $maturity = if ($id -in @('factorio-2.1','factorio-2.0','factorio-1.1','factorio-1.0')) { 'preview' } else { 'experimental' }
      if ([string]$support.support_tier -eq 'museum') { $maturity = 'omitted-by-target' }
      $profileProperty = $profiles.profiles.PSObject.Properties[[string]$target.factorio_line]
      $profileStatus = [string]$support.profile
      $profileDigest = if ($null -ne $profileProperty) {
        Get-MIR4PlatformDigest ([pscustomobject][ordered]@{factorio_line=[string]$target.factorio_line;profile=$profileProperty.Value})
      } elseif ($snapshot -and (Test-Path -LiteralPath (Join-Path $repo $snapshot) -PathType Leaf)) {
        'sha256:' + (Get-MIR4PlatformFileSha256 (Join-Path $repo $snapshot))
      } else { $null }
      $provider = [pscustomobject][ordered]@{
        kind = 'MIR4TargetProviderV0'; schema = 0; id = $targetKey; target_id = $id
        factorio_line = [string]$target.factorio_line; distribution_target_code = $code; source_version = '4.0.0'
        distribution_version = [string]$target.distribution_version; support_tier = [string]$support.support_tier
        disposition = [string]$support.disposition; release_blocking = [bool]$support.release_blocking; maturity = $maturity
        authority = if ($maturity -eq 'preview') { 'candidate-programme-only' } else { 'private-experimental-only' }
        predecessor = if ($predecessor) { [ordered]@{ release=$predecessor; snapshot=$snapshot } } else { $null }
        engine_lock = if ($planned) { [ordered]@{ version=[string]$planned.engine_lock.version; sha256=[string]$planned.engine_lock.executable_sha256; authority='MIR4-Bootstrap-Local-Candidate-PlanV3' } } elseif ($historicalTarget -and -not [string]::IsNullOrWhiteSpace([string]$historicalTarget.engine.version)) { [ordered]@{ version=[string]$historicalTarget.engine.version; sha256=[string]$historicalTarget.engine.sha256; authority='MIR4-Historical-Private-Candidate-AuthorizationV1' } } else { $null }
        profile = [ordered]@{ status=$profileStatus; authority=[string]$registry.profile_authority.path; authority_sha256=[string]$registry.profile_authority.sha256; digest=$profileDigest }
        provenance = @(
          [ordered]@{role='identity-and-support';path='.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json';sha256=(Get-MIR4PlatformFileSha256 (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json'))},
          [ordered]@{role='target-profile';path=[string]$registry.profile_authority.path;sha256=[string]$registry.profile_authority.sha256}
        )
        operations = @('identify','normalize-capabilities','explain-omissions','plan-private-candidate')
        forbidden_operations = @('mutate-prototypes','emit-authoritative-output','claim-public-support','weaken-safety')
        digest = ''
      }
      Add-MIR4PlatformDigest $provider
    }
  )
}

function New-MIR4LegacyNormalizedCompilationRuns {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)]$Providers)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $inputs = Get-MIR4PlatformInputs $repo
  return @(
    foreach ($provider in $Providers) {
      $snapshotPath = if ($provider.predecessor) { [string]$provider.predecessor.snapshot } else { '' }
      $snapshot = if ($snapshotPath -and (Test-Path -LiteralPath (Join-Path $repo $snapshotPath))) { Get-Content -Raw -LiteralPath (Join-Path $repo $snapshotPath) | ConvertFrom-Json } else { $null }
      $run = [pscustomobject][ordered]@{
        kind = 'MIR4CompilationRunV0'; schema = 0
        target = [ordered]@{ id=$provider.id; factorio_line=$provider.factorio_line; provider_digest=$provider.digest }
        versions = [ordered]@{ source='4.0.0'; distribution=$provider.distribution_version }
        adapter = 'LegacyCompilerHostAdapterV1'; maturity = 'shadow'; input_digests = $inputs
        feature_manifest = if ($snapshot) { [ordered]@{ adapter='terminal-normalized-snapshot'; mode='read-only'; target=$provider.id; features=$snapshot.inventories.features; technologies=$snapshot.inventories.technologies; capability_omissions=@($snapshot.capability_omissions) } } else { [ordered]@{ adapter='terminal-normalized-snapshot'; mode='read-only'; target=$provider.id; status='unavailable' } }
        setting_spec = if ($snapshot) { [ordered]@{ adapter='terminal-settings-inventory'; mode='read-only'; target=$provider.id; settings=$snapshot.inventories.settings } } else { [ordered]@{ adapter='terminal-settings-inventory'; mode='read-only'; target=$provider.id; status='unavailable' } }
        legacy_snapshot = if ($snapshot) { [ordered]@{ path=$snapshotPath; sha256=(Get-MIR4PlatformFileSha256 (Join-Path $repo $snapshotPath)); top_level_sections=@($snapshot.PSObject.Properties.Name | Sort-Object) } } else { $null }
        parity_baseline = if ($snapshot) { [ordered]@{ release=[string]$snapshot.release; archive_sha256=[string]$snapshot.distribution.archive_sha256; content_sha256=[string]$snapshot.distribution.content_sha256; entries=[int]$snapshot.distribution.entries; expectation='semantic-identity-except-governed-presentation-overlay' } } else { $null }
        stages = @('target-provider','feature-manifest-adapter','setting-spec-adapter','normalized-contribution-model','safety-kernel','policy-engine','public-artifact-projection')
        result = if ($snapshot) { 'deterministic-predecessor-projection-ready' } else { 'blocked-missing-predecessor-snapshot' }
        authoritative_output = $false; mutation_capability = $false
        diagnostics = if ($snapshot) { @() } else { @([ordered]@{ code='mir4-shadow-predecessor-absent'; severity='blocked'; target=$provider.id }) }
        digest = ''
      }
      Add-MIR4PlatformDigest $run
    }
  )
}

function New-MIR4NormalizedCompilationRuns {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Providers)
  return @(New-MIR4SemanticCompilationRuns -RepoRoot $RepoRoot -Providers $Providers)
}

function New-MIR4AffectedTargetPlan {
  param([Parameter(Mandatory)]$Providers)
  $rows = @(foreach ($provider in @($Providers)) {
    $disposition = switch ([string]$provider.disposition) {
      'candidate-mandatory' { 'build-and-qualify-mandatory' }
      'candidate-conditional' { 'build-and-qualify-independently' }
      'private-experimental-bridge' { if ($provider.engine_lock) { 'private-shadow-only' } else { 'blocked-missing-exact-engine' } }
      'private-experimental' { if ($provider.engine_lock) { 'private-build-and-shadow-proof' } else { 'blocked-missing-exact-engine' } }
      default { 'omitted-by-target' }
    }
    $reasons = @()
    if (-not $provider.predecessor) { $reasons += 'missing-governed-predecessor' }
    if (-not $provider.engine_lock) { $reasons += 'missing-exact-engine-lock' }
    if ([string]$provider.support_tier -eq 'museum') { $reasons += 'museum-target-deferred' }
    [ordered]@{
      target = [string]$provider.id
      factorio_line = [string]$provider.factorio_line
      registry_disposition = [string]$provider.disposition
      plan = $disposition
      release_blocking = [bool]$provider.release_blocking
      provider_digest = [string]$provider.digest
      reasons = @($reasons | Sort-Object -Unique)
      authoritative = $false
    }
  })
  $record = [pscustomobject][ordered]@{
    kind='MIR4AffectedTargetPlanV0';schema=0;maturity='preview';mode='affected-target-planning';targets=$rows
    authoritative_output=$false;mutation_capability=$false;digest=''
  }
  return Add-MIR4PlatformDigest $record
}

function New-MIR4ShadowExtensionCompilation {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('^f[0-9]{3}$')][string]$TargetId,
    [Parameter(Mandatory)]$Envelope
  )

  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  Test-MIR4MepEnvelope -Envelope $Envelope -RepoRoot $repo | Out-Null
  if ($TargetId -notin @($Envelope.targets | ForEach-Object { [string]$_ })) { throw "[mir4-shadow-target-not-declared] $TargetId" }
  $providers = @(New-MIR4NormalizedTargetProviders -RepoRoot $repo)
  $provider = @($providers | Where-Object { [string]$_.id -eq $TargetId })
  if ($provider.Count -ne 1) { throw "[mir4-shadow-target-provider] $TargetId" }
  $provider = $provider[0]
  $availableCapabilities = @('diagnostics.read','query.read','settings.read','streams.read','support.snapshot')
  $contributions = @()
  $diagnostics = @()
  foreach ($fragment in @($Envelope.fragments)) {
    $requested = switch ([string]$fragment.kind) {
      'CompatibilityFragment' {
        switch ([string]$fragment.data.disposition) {
          'handle-certified' { 'handle' }
          'preserve-opaque' { 'preserve' }
          'omit-with-evidence' { 'omit-with-evidence' }
          default { 'request-review' }
        }
      }
      'CapabilityRequirement' { 'preserve' }
      'ProofFragment' { 'preserve' }
      default { 'request-review' }
    }
    $required = @()
    if ([string]$fragment.kind -eq 'CapabilityRequirement') { $required = @($fragment.data.all_of | ForEach-Object { [string]$_ } | Sort-Object -Unique) }
    $missing = @($required | Where-Object { $_ -notin $availableCapabilities })
    if ($missing.Count -gt 0) { $requested = 'request-extension' }
    $safetyInput = [pscustomobject][ordered]@{
      subject = [string]$fragment.id
      operations = @('data-only-fragment')
      evidence = @("extension:$([string]$Envelope.digest)", "fragment:$([string]$fragment.id)", "target-provider:$([string]$provider.digest)")
      requested_disposition = $requested
      positive_cycle = $false
      proven_bounded = $true
      owner_opaque = $false
      owner_rewrite = $false
    }
    $decision = Resolve-MIR4PolicyDisposition -Contribution $safetyInput
    if ($missing.Count -gt 0) {
      $diagnostics += [ordered]@{code='mir4-shadow-capability-unavailable';severity='review';subject=[string]$fragment.id;context=[ordered]@{target=$TargetId;missing=$missing}}
    } elseif ($decision.review_required) {
      $diagnostics += [ordered]@{code='mir4-shadow-policy-review-required';severity='info';subject=[string]$fragment.id;context=[ordered]@{target=$TargetId;disposition=[string]$decision.disposition}}
    }
    $contributions += [ordered]@{
      fragment_id = [string]$fragment.id
      fragment_kind = [string]$fragment.kind
      normalized_operation = 'data-only-fragment'
      required_capabilities = $required
      missing_capabilities = $missing
      policy = $decision
      authoritative = $false
      mutation_authorized = $false
    }
  }
  $record = [pscustomobject][ordered]@{
    kind = 'MIR4ShadowExtensionCompilationV0'
    schema = 0
    maturity = 'shadow'
    target = [ordered]@{ id=$TargetId; provider_digest=[string]$provider.digest; factorio_line=[string]$provider.factorio_line }
    extension = [ordered]@{ id=[string]$Envelope.extension_id; digest=[string]$Envelope.digest }
    available_capabilities = $availableCapabilities
    contributions = $contributions
    diagnostics = @($diagnostics | Sort-Object code,subject)
    result = if (@($diagnostics | Where-Object { $_.code -eq 'mir4-shadow-capability-unavailable' }).Count) { 'review-required' } else { 'shadow-complete' }
    authoritative_output = $false
    mutation_capability = $false
    public_support_claim = $false
    digest = ''
  }
  return Add-MIR4PlatformDigest $record
}

function Invoke-MIR4ShadowExtensionCompilation {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('^f[0-9]{3}$')][string]$TargetId,
    [Parameter(Mandatory)][string]$ExtensionPath,
    [Parameter(Mandatory)][string]$OutputPath
  )
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $resolvedExtension = if ([IO.Path]::IsPathRooted($ExtensionPath)) { [IO.Path]::GetFullPath($ExtensionPath) } else { [IO.Path]::GetFullPath((Join-Path $repo $ExtensionPath)) }
  $extension = Get-Content -Raw -LiteralPath $resolvedExtension | ConvertFrom-Json
  $record = if ([int]$extension.schema -eq 1 -and [string]$extension.kind -eq 'MIR4ExtensionEnvelopeV1') {
    New-MIR4ShadowExtensionCompilationV1 -RepoRoot $repo -TargetId $TargetId -Envelope $extension
  } else {
    New-MIR4ShadowExtensionCompilation -RepoRoot $repo -TargetId $TargetId -Envelope $extension
  }
  $resolvedOutput = if ([IO.Path]::IsPathRooted($OutputPath)) { [IO.Path]::GetFullPath($OutputPath) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputPath)) }
  $allowedOutput = [IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd('\') + '\'
  if (-not ($resolvedOutput + '\').StartsWith($allowedOutput,[StringComparison]::OrdinalIgnoreCase)) { throw "[mir4-shadow-output-boundary] $resolvedOutput" }
  New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent) | Out-Null
  [IO.File]::WriteAllText($resolvedOutput,(ConvertTo-MIR4PlatformCanonicalJson $record)+"`n",[Text.UTF8Encoding]::new($false))
  return $record
}

function New-MIR4ShadowExtensionCompilationV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('^f[0-9]{3}$')][string]$TargetId,
    [Parameter(Mandatory)]$Envelope
  )
  $closure = Resolve-MIR4ExtensionClosureV1 -RepoRoot $RepoRoot -Extensions @($Envelope) -Target $TargetId
  $transport = @((Get-MIR4ModuleEcosystemAuthority -RepoRoot $RepoRoot).transports | Where-Object target -eq $TargetId)
  $contributions = @(
    foreach ($fragment in @($Envelope.fragments | Sort-Object id)) {
      $availability = if ([string]$fragment.kind -in @('ProcessClassificationFragment','ExternalEffectChannelDeclaration') -and [string]$fragment.data.status -eq 'unavailable') { 'unavailable' } else { 'available' }
      [ordered]@{
        fragment_id=[string]$fragment.id;fragment_kind=[string]$fragment.kind;normalized_operation='data-only-fragment';availability=$availability
        owner=$(switch ([string]$fragment.kind){'MigrationFragment'{'W04'};'ProcessClassificationFragment'{'W06'};'ExternalEffectChannelDeclaration'{'W06'};default{'W05'}})
        authoritative=$false;mutation_authorized=$false
      }
    }
  )
  $record = [pscustomobject][ordered]@{
    kind='MIR4ShadowExtensionCompilationV1';schema=1;maturity='shadow';target=[ordered]@{id=$TargetId;transport=[string]$transport.transport;admission=[string]$transport.admission}
    extension=[ordered]@{id=[string]$Envelope.extension_id;version=[string]$Envelope.extension_version;digest=[string]$Envelope.digest};closure_digest=[string]$closure.digest
    contributions=$contributions;diagnostics=@($contributions | Where-Object availability -eq 'unavailable' | ForEach-Object {[ordered]@{code='mir4-shadow-authority-not-yet-available';severity='info';subject=[string]$_.fragment_id;owner=[string]$_.owner}})
    result=$(if($closure.complete){'shadow-complete'}else{'review-required'});authoritative_output=$false;mutation_capability=$false;public_support_claim=$false;digest=''
  }
  return Add-MIR4PlatformDigest $record
}
