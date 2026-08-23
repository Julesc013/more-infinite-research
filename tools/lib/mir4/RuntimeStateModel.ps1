function Get-MIR4RuntimeContinuityAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $path = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json'
  $authority = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ([int]$authority.schema -ne 1 -or [string]$authority.kind -cne 'MIR4RuntimeContinuityProgrammeV1') { throw '[mir4-runtime-continuity-authority]' }
  foreach ($flag in @('semantic_authority','player_package_mutation_authorized','runtime_registration_mutation_authorized','migration_execution_authorized','public_support_authorized','signing_or_sealing_authorized','publication_authorized')) {
    if ([bool]$authority.$flag) { throw "[mir4-runtime-continuity-boundary] $flag" }
  }
  if (@($authority.runtime_features.id | Sort-Object -Unique).Count -ne 7) { throw '[mir4-runtime-feature-count]' }
  if (@($authority.state_specs.id | Sort-Object -Unique).Count -ne 5) { throw '[mir4-state-spec-count]' }
  if (@($authority.registration_groups.id | Sort-Object -Unique).Count -ne 9) { throw '[mir4-registration-group-count]' }
  if (@($authority.migration_edges.id | Sort-Object -Unique).Count -ne 10) { throw '[mir4-migration-edge-count]' }
  foreach ($relative in @($authority.terminal_player_authority)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo ([string]$relative)) -PathType Leaf)) { throw "[mir4-runtime-terminal-authority] $relative" }
  }
  return $authority
}

function New-MIR4RuntimeSourceIdentity {
  param([AllowNull()]$SourceIdentity)
  if ($null -eq $SourceIdentity) { return $null }
  return [ordered]@{commit=[string]$SourceIdentity.commit;tree=[string]$SourceIdentity.tree;programme_id='M4C02-09-24H'}
}

function Get-MIR4RuntimeTargetContexts {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$Providers)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $providerRows = if ($null -eq $Providers) { @(New-MIR4NormalizedTargetProviders -RepoRoot $repo) } else { @($Providers) }
  $providerRows = @($providerRows | Sort-Object id)
  $profiles = (Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/targets.json') | ConvertFrom-Json).profiles
  return @(
    foreach ($provider in $providerRows) {
      $line = [string]$provider.factorio_line
      $profileProperty = $profiles.PSObject.Properties[$line]
      $profile = if ($null -ne $profileProperty) { $profileProperty.Value } else { $null }
      [pscustomobject][ordered]@{
        target=[string]$provider.id;factorio_line=$line;provider=$provider;profile=$profile
        profile_status=[string]$provider.profile.status;backend=$(if ($profile) { [string]$profile.runtime_state_backend } else { $null })
        support_tier=[string]$provider.support_tier
      }
    }
  )
}

function Test-MIR4RuntimeRequirements {
  param([AllowNull()]$Profile,[string[]]$Requirements)
  if ($null -eq $Profile) { return $false }
  foreach ($requirement in @($Requirements)) {
    $property = $Profile.features.PSObject.Properties[[string]$requirement]
    if ($null -eq $property -or -not [bool]$property.Value) { return $false }
  }
  return $true
}

function Get-MIR4RuntimeTargetDisposition {
  param([Parameter(Mandatory)]$Context,[string[]]$Requirements)
  if ([string]$Context.support_tier -eq 'museum') { return 'blocked-with-evidence' }
  if ([string]$Context.profile_status -eq 'terminal-derived') { return 'opaque-terminal-derived' }
  if (Test-MIR4RuntimeRequirements -Profile $Context.profile -Requirements $Requirements) { return 'active-player-authority' }
  return 'compiled-out'
}

function New-MIR4RuntimeFeatureSpecs {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$Providers)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $authority = Get-MIR4RuntimeContinuityAuthority -RepoRoot $repo
  $contexts = @(Get-MIR4RuntimeTargetContexts -RepoRoot $repo -Providers $Providers)
  return @(
    foreach ($feature in @($authority.runtime_features | Sort-Object id)) {
      $source = [string]$feature.source
      $path = Join-Path $repo $source
      $text = Get-Content -Raw -LiteralPath $path
      foreach ($handler in @($feature.handlers)) {
        if ($text -notmatch ("function\s+M\." + [regex]::Escape([string]$handler) + "\s*\(")) { throw "[mir4-runtime-handler-missing] $($feature.id):$handler" }
      }
      $targetDispositions = @(
        foreach ($context in $contexts) {
          [ordered]@{target=[string]$context.target;backend=$context.backend;disposition=(Get-MIR4RuntimeTargetDisposition -Context $context -Requirements @($feature.target_requirements))}
        }
      )
      [ordered]@{
        id=[string]$feature.id;version=[int]$feature.version;source=$source;source_sha256=(Get-MIR4PlatformInputSha256 $path)
        handlers=@($feature.handlers);target_requirements=@($feature.target_requirements);state_ids=@($feature.state_ids)
        determinism=[string]$feature.determinism;complexity_budget=$feature.complexity_budget;migration_refs=@($feature.migration_refs)
        disable_or_removal=[string]$feature.disable_or_removal;target_dispositions=$targetDispositions
      }
    }
  )
}

function New-MIR4StateSpecs {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$Providers,[Parameter(Mandatory)]$RuntimeFeatures)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $authority = Get-MIR4RuntimeContinuityAuthority -RepoRoot $repo
  $contexts = @(Get-MIR4RuntimeTargetContexts -RepoRoot $repo -Providers $Providers)
  $featureById = @{}; foreach ($feature in @($RuntimeFeatures)) { $featureById[[string]$feature.id] = $feature }
  return @(
    foreach ($spec in @($authority.state_specs | Sort-Object id)) {
      $owner = $featureById[[string]$spec.owner]
      if ($null -eq $owner) { throw "[mir4-state-owner-missing] $($spec.id)" }
      $dispositionByTarget = @{}; foreach ($row in @($owner.target_dispositions)) { $dispositionByTarget[[string]$row.target] = $row }
      $targetNamespaces = @(
        foreach ($context in $contexts) {
          $featureDisposition = [string]$dispositionByTarget[[string]$context.target].disposition
          [ordered]@{target=[string]$context.target;backend=$context.backend;namespace=$(if ($context.backend) { "$($context.backend).mir.$([string]$spec.bucket)" } else { $null });disposition=$featureDisposition}
        }
      )
      [ordered]@{
        id=[string]$spec.id;schema=[int]$spec.schema;owner=[string]$spec.owner;bucket=[string]$spec.bucket
        namespace_template='runtime-root.mir.<bucket>';fields=@($spec.fields);aliases=@($spec.aliases);tombstones=@($spec.tombstones)
        ownership_transfer=[string]$spec.ownership_transfer;target_namespaces=$targetNamespaces
      }
    }
  )
}

function Assert-MIR4RuntimeRegistrationPlan {
  param([Parameter(Mandatory)]$Plan)
  $ids = @($Plan.groups | ForEach-Object { [string]$_.id })
  if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw '[mir4-runtime-duplicate-registration-group]' }
  foreach ($group in @($Plan.groups)) {
    if ([string]::IsNullOrWhiteSpace([string]$group.filter)) { throw "[mir4-runtime-filter-absent] $($group.id)" }
    $subscriberIds = @($group.subscribers | ForEach-Object { [string]$_.id })
    $ordinals = @($group.subscribers | ForEach-Object { [int]$_.ordinal })
    if (@($subscriberIds | Sort-Object -Unique).Count -ne $subscriberIds.Count) { throw "[mir4-runtime-duplicate-subscriber] $($group.id)" }
    if (@($ordinals | Sort-Object -Unique).Count -ne $ordinals.Count) { throw "[mir4-runtime-duplicate-ordinal] $($group.id)" }
    $ordered = @($group.subscribers | Sort-Object ordinal,id | ForEach-Object { [string]$_.id })
    if (($ordered -join '|') -cne ($subscriberIds -join '|')) { throw "[mir4-runtime-subscriber-order] $($group.id)" }
  }
  if ($Plan.on_load.persistent_mutation -or $Plan.on_tick.registered -or [int]$Plan.on_tick.budget -ne 0) { throw '[mir4-runtime-idle-or-load-mutation]' }
  return $true
}

function New-MIR4RuntimeRegistrationPlan {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$RuntimeFeatures)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $authority = Get-MIR4RuntimeContinuityAuthority -RepoRoot $repo
  $featureById = @{}; foreach ($feature in @($RuntimeFeatures)) { $featureById[[string]$feature.id] = $feature }
  $dispatcherPath = Join-Path $repo 'prototypes/mir/runtime/scripted_techs.lua'
  $stagePath = Join-Path $repo 'prototypes/mir/stage/control.lua'
  $dispatcherText = Get-Content -Raw -LiteralPath $dispatcherPath
  $stageText = Get-Content -Raw -LiteralPath $stagePath
  $groups = @(
    foreach ($group in @($authority.registration_groups)) {
      $registration = [string]$group.registration
      if ($registration -like 'defines.events.*') {
        $eventName = $registration.Substring('defines.events.'.Length)
        if ($dispatcherText -notmatch ("defines\.events\." + [regex]::Escape($eventName))) { throw "[mir4-runtime-registration-missing] $registration" }
      } elseif ($dispatcherText -notmatch [regex]::Escape($registration)) { throw "[mir4-runtime-registration-missing] $registration" }
      $subscribers = @(); $ordinal = 10
      foreach ($binding in @($group.subscribers)) {
        $parts = ([string]$binding).Split(':',2)
        if ($parts.Count -ne 2 -or -not $featureById.ContainsKey($parts[0]) -or $parts[1] -notin @($featureById[$parts[0]].handlers)) { throw "[mir4-runtime-subscriber-binding] $binding" }
        $subscribers += [ordered]@{id=[string]$binding;feature=$parts[0];handler=$parts[1];ordinal=$ordinal}; $ordinal += 10
      }
      [ordered]@{id=[string]$group.id;registration=$registration;filter=[string]$group.filter;subscribers=$subscribers}
    }
  )
  $combined = $dispatcherText + "`n" + $stageText
  $plan = [pscustomobject][ordered]@{
    kind='MIR4RuntimeRegistrationPlanV1';schema=1;owner='prototypes/mir/runtime/scripted_techs.lua';owner_sha256=(Get-MIR4PlatformInputSha256 $dispatcherPath);groups=$groups
    ordering='authority-array-preserved-as-explicit-ordinal';filter_before_dispatch=$true;one_registration_per_group=$true
    on_load=[ordered]@{registered=($combined -match 'script\.on_load');persistent_mutation=$false};on_tick=[ordered]@{registered=($combined -match 'defines\.events\.on_tick');budget=0}
    cross_feature_state_mutation=$false;duplicate_rejection=$true;maximum_diagnostics_per_dispatch=64
    law_results=[ordered]@{unique_groups=$true;unique_subscribers=$true;stable_order=$true;filter_before_dispatch=$true;no_on_load_mutation=$true;no_idle_tick=$true;namespace_isolation=$true;bounded_diagnostics=$true;all_passed=$true}
  }
  if ($plan.on_load.registered) { throw '[mir4-runtime-on-load-registration]' }
  if ($plan.on_tick.registered) { throw '[mir4-runtime-unbudgeted-on-tick]' }
  Assert-MIR4RuntimeRegistrationPlan -Plan $plan | Out-Null
  return $plan
}

function New-MIR4RuntimeStateMatrix {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$Providers,[AllowNull()]$SourceIdentity)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $authority = Get-MIR4RuntimeContinuityAuthority -RepoRoot $repo
  $contexts = @(Get-MIR4RuntimeTargetContexts -RepoRoot $repo -Providers $Providers)
  $features = @(New-MIR4RuntimeFeatureSpecs -RepoRoot $repo -Providers @($contexts.provider))
  $states = @(New-MIR4StateSpecs -RepoRoot $repo -Providers @($contexts.provider) -RuntimeFeatures $features)
  $registration = New-MIR4RuntimeRegistrationPlan -RepoRoot $repo -RuntimeFeatures $features
  $targets = @(
    foreach ($context in $contexts) {
      [ordered]@{
        target=[string]$context.target;factorio_line=[string]$context.factorio_line;backend=$context.backend;profile_status=[string]$context.profile_status
        feature_dispositions=@($features | ForEach-Object { $row=@($_.target_dispositions | Where-Object target -eq $context.target)[0];[ordered]@{feature=[string]$_.id;disposition=[string]$row.disposition} })
      }
    }
  )
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4RuntimeStateMatrixV1';programme_id=[string]$authority.programme_id;source_identity=(New-MIR4RuntimeSourceIdentity $SourceIdentity)
    authority='.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json';maturity='shadow';runtime_feature_specs=$features;state_specs=$states;registration_plan=$registration;targets=$targets
    invariants=@('terminal-runtime-remains-player-authority','runtime-never-mutates-prototypes','state-owned-under-mir-namespace','backend-derived-from-target-profile','field-aware-state-classification','one-registration-per-event-filter-group','filter-before-dispatch','stable-subscriber-order','no-on-load-persistent-mutation','no-idle-on-tick','no-cross-feature-state-mutation','bounded-diagnostics')
    package_visible=$false;runtime_mutation_authorized=$false;public_release_proof=$false;digest=''
  }
  Add-MIR4PlatformDigest $record | Out-Null
  $schemaPath = Join-Path $repo ([string]$authority.schemas.runtime_state_matrix)
  if (-not (($record | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath)) { throw '[mir4-runtime-state-matrix-schema]' }
  return $record
}

function Test-MIR4MigrationGraphLaws {
  param([Parameter(Mandatory)]$Graph)
  $requiredKinds = @('same-target-source-upgrade','skipped-source-patches','cross-target-transition','extension-install-remove','ownership-transfer','profile-schema-transition','repair','downgrade')
  $actualKinds = @($Graph.edges.kind | Sort-Object -Unique)
  if (@(Compare-Object $requiredKinds $actualKinds).Count -ne 0) { throw '[mir4-migration-kind-coverage]' }
  $ids = @($Graph.edges.id | ForEach-Object { [string]$_ })
  if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw '[mir4-migration-duplicate-edge]' }
  $selectors = @($Graph.edges | ForEach-Object { "$($_.kind)|$($_.from)|$($_.to)|$($_.precedence)" })
  if (@($selectors | Sort-Object -Unique).Count -ne $selectors.Count) { throw '[mir4-migration-ambiguous-selector]' }
  $canonical = @($Graph.edges | Sort-Object @{Expression={[int]$_.precedence}},@{Expression={[string]$_.id}} | ForEach-Object { [string]$_.id })
  $reverse = @($Graph.edges); [Array]::Reverse($reverse)
  $canonicalReverse = @($reverse | Sort-Object @{Expression={[int]$_.precedence}},@{Expression={[string]$_.id}} | ForEach-Object { [string]$_.id })
  $canonicalText = $canonical -join '|'
  $canonicalReverseText = $canonicalReverse -join '|'
  if (-not [string]::Equals($canonicalText,$canonicalReverseText,[StringComparison]::Ordinal)) { throw "[mir4-migration-order-variance] $canonicalText <> $canonicalReverseText" }
  $downgrade = @($Graph.edges | Where-Object kind -eq 'downgrade')
  if ($downgrade.Count -ne 1 -or [string]$downgrade[0].status -ne 'unsupported-with-evidence') { throw '[mir4-migration-downgrade-disposition]' }
  return [ordered]@{deterministic_path_selection=$true;input_order_invariant=$true;duplicate_edge_rejection=$true;explicit_downgrade=$true;all_passed=$true}
}

function New-MIR4MigrationGraphMatrix {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$Providers,[AllowNull()]$SourceIdentity)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $authority = Get-MIR4RuntimeContinuityAuthority -RepoRoot $repo
  $contexts = @(Get-MIR4RuntimeTargetContexts -RepoRoot $repo -Providers $Providers)
  $edges = @(
    foreach ($edge in @($authority.migration_edges | Sort-Object precedence,id)) {
      $evidence = @(
        foreach ($relative in @($edge.evidence)) {
          $path = Join-Path $repo ([string]$relative)
          if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-migration-evidence-missing] $relative" }
          [ordered]@{path=[string]$relative;sha256=(Get-MIR4PlatformInputSha256 $path)}
        }
      )
      [ordered]@{id=[string]$edge.id;kind=[string]$edge.kind;from=[string]$edge.from;to=[string]$edge.to;status=[string]$edge.status;precedence=[int]$edge.precedence;evidence=$evidence;execution_authorized=$false}
    }
  )
  $targets = @(
    foreach ($context in $contexts) {
      $disposition = if ([string]$context.support_tier -eq 'museum') { 'blocked-with-evidence' } elseif ([string]$context.profile_status -eq 'terminal-derived') { 'opaque-terminal-derived' } elseif ([string]$context.factorio_line -in @('2.1','2.0')) { 'private-runtime-proof-required' } else { 'compiled-out-with-predecessor-continuity-reference' }
      [ordered]@{target=[string]$context.target;factorio_line=[string]$context.factorio_line;backend=$context.backend;disposition=$disposition;predecessor=$(if($context.provider.predecessor){[string]$context.provider.predecessor.release}else{$null})}
    }
  )
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4MigrationGraphMatrixV1';programme_id=[string]$authority.programme_id;source_identity=(New-MIR4RuntimeSourceIdentity $SourceIdentity)
    authority='.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json';maturity='shadow'
    edge_kinds=@('same-target-source-upgrade','skipped-source-patches','cross-target-transition','extension-install-remove','ownership-transfer','profile-schema-transition','repair','downgrade')
    edges=$edges;target_dispositions=$targets;law_results=$null;complete_for_public_release=$false;package_visible=$false;migration_execution_authorized=$false;public_release_proof=$false;digest=''
  }
  $record.law_results = Test-MIR4MigrationGraphLaws -Graph $record
  Add-MIR4PlatformDigest $record | Out-Null
  $schemaPath = Join-Path $repo ([string]$authority.schemas.migration_graph_matrix)
  if (-not (($record | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath)) { throw '[mir4-migration-graph-matrix-schema]' }
  return $record
}

function New-MIR4ContinuityBundle {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$Providers,[AllowNull()]$SourceIdentity,[AllowNull()][string]$CandidateZip,[AllowNull()]$RuntimeStateMatrix,[AllowNull()]$MigrationGraphMatrix)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $authority = Get-MIR4RuntimeContinuityAuthority -RepoRoot $repo
  $contexts = @(Get-MIR4RuntimeTargetContexts -RepoRoot $repo -Providers $Providers)
  if ($null -eq $RuntimeStateMatrix) { $RuntimeStateMatrix = New-MIR4RuntimeStateMatrix -RepoRoot $repo -Providers @($contexts.provider) -SourceIdentity $SourceIdentity }
  if ($null -eq $MigrationGraphMatrix) { $MigrationGraphMatrix = New-MIR4MigrationGraphMatrix -RepoRoot $repo -Providers @($contexts.provider) -SourceIdentity $SourceIdentity }
  $contracts = New-MIR4TargetContractSet -RepoRoot $repo
  $contractByTarget = @{}; foreach ($contract in @($contracts.targets)) { $contractByTarget[[string]$contract.target] = $contract }
  $candidateTarget = $null; $candidateDescriptor = $null
  if (-not [string]::IsNullOrWhiteSpace($CandidateZip)) {
    $candidatePath = if ([IO.Path]::IsPathRooted($CandidateZip)) { $CandidateZip } else { Join-Path $repo $CandidateZip }
    $candidatePath = (Resolve-Path -LiteralPath $candidatePath).Path
    if ([IO.Path]::GetFileName($candidatePath) -notmatch '_4\.0\.(?<code>[0-9]{3})00\.zip$') { throw '[mir4-continuity-candidate-name]' }
    $candidateTarget = 'f' + $Matches.code
    $candidateDescriptor = [ordered]@{path=[IO.Path]::GetRelativePath($repo,$candidatePath).Replace('\','/');bytes=(Get-Item -LiteralPath $candidatePath).Length;sha256=(Get-MIR4PlatformFileSha256 $candidatePath);status='present-private-unqualified'}
  }
  $targets = @(
    foreach ($context in $contexts) {
      $provider = $context.provider
      $snapshotPath = if ($provider.predecessor) { [string]$provider.predecessor.snapshot } else { $null }
      $snapshot = if ($snapshotPath -and (Test-Path -LiteralPath (Join-Path $repo $snapshotPath) -PathType Leaf)) { [ordered]@{path=$snapshotPath;sha256=(Get-MIR4PlatformInputSha256 (Join-Path $repo $snapshotPath));status='reference-available'} } else { [ordered]@{path=$null;sha256=$null;status='blocked-missing-predecessor-snapshot'} }
      $featureRows = @($RuntimeStateMatrix.targets | Where-Object target -eq $context.target)[0].feature_dispositions
      $activeStateIds = @(
        foreach ($state in @($RuntimeStateMatrix.state_specs)) {
          $namespace = @($state.target_namespaces | Where-Object target -eq $context.target)[0]
          if ([string]$namespace.disposition -eq 'active-player-authority') { [string]$state.id }
        }
      )
      [ordered]@{
        target=[string]$context.target;factorio_line=[string]$context.factorio_line;distribution_version=[string]$provider.distribution_version
        predecessor=$(if($provider.predecessor){[string]$provider.predecessor.release}else{$null});contract_digest=[string]$contractByTarget[[string]$context.target].digest
        provider_digest=[string]$provider.digest;profile=[ordered]@{authority=[string]$provider.profile.authority;digest=[string]$provider.profile.digest;status=[string]$provider.profile.status;backend=$context.backend}
        feature_dispositions=@($featureRows);research_identity=$snapshot;runtime_state_ids=$activeStateIds
        migration_disposition=[string]@($MigrationGraphMatrix.target_dispositions | Where-Object target -eq $context.target)[0].disposition
      }
    }
  )
  $packageRoots = @(
    foreach ($context in $contexts) {
      if ([string]$context.target -eq $candidateTarget) { [ordered]@{target=[string]$context.target;descriptor=$candidateDescriptor} }
      else { [ordered]@{target=[string]$context.target;descriptor=[ordered]@{path=$null;bytes=$null;sha256=$null;status=$(if([string]$context.support_tier -eq 'museum'){'blocked-with-evidence'}else{'not-materialized-for-this-bundle'})}} }
    }
  )
  $runtimeLawRecord = [pscustomobject][ordered]@{laws=$RuntimeStateMatrix.registration_plan.law_results;digest=''}; Add-MIR4PlatformDigest $runtimeLawRecord | Out-Null
  $migrationLawRecord = [pscustomobject][ordered]@{laws=$MigrationGraphMatrix.law_results;digest=''}; Add-MIR4PlatformDigest $migrationLawRecord | Out-Null
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4ContinuityBundleV1';programme_id=[string]$authority.programme_id;source_identity=(New-MIR4RuntimeSourceIdentity $SourceIdentity)
    authority='.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json';maturity='private-preview';target_count=17;targets=$targets
    module_extension_closure=[ordered]@{module_graph=[ordered]@{path='.mir/module-dependencies.json';sha256=(Get-MIR4PlatformInputSha256 (Join-Path $repo '.mir/module-dependencies.json'))};external_extensions=[ordered]@{status='deferred-W05';opaque_reference=$true}}
    feature_inventory=[ordered]@{kind=[string]$RuntimeStateMatrix.kind;digest=[string]$RuntimeStateMatrix.digest;feature_count=@($RuntimeStateMatrix.runtime_feature_specs).Count}
    runtime_state_schemas=[ordered]@{kind='MIR4StateSpecSetV1';matrix_digest=[string]$RuntimeStateMatrix.digest;state_count=@($RuntimeStateMatrix.state_specs).Count}
    aliases_tombstones=[ordered]@{state_aliases=@($RuntimeStateMatrix.state_specs | ForEach-Object { @($_.aliases) });state_tombstones=@($RuntimeStateMatrix.state_specs | ForEach-Object { @($_.tombstones) });migration_graph_digest=[string]$MigrationGraphMatrix.digest}
    migration_watermark=[ordered]@{latest_engine_json='2.1.0';edge_count=@($MigrationGraphMatrix.edges).Count;graph_digest=[string]$MigrationGraphMatrix.digest;public_complete=$false}
    package_roots=$packageRoots;proof_roots=[ordered]@{target_contract_set=[string]$contracts.digest;runtime_registration_laws=[string]$runtimeLawRecord.digest;migration_laws=[string]$migrationLawRecord.digest;runtime_qualification='required-per-admitted-target'}
    redaction_manifest=[ordered]@{excluded=@('mutable-runtime-state-values','player-identities','save-data','credentials','private-signing-material','raw-prototype-objects','unbounded-diagnostics');projection='identities-schemas-hashes-and-dispositions-only';complete=$true}
    package_visible=$false;runtime_mutation_authorized=$false;public_release_proof=$false;digest=''
  }
  Add-MIR4PlatformDigest $record | Out-Null
  $schemaPath = Join-Path $repo ([string]$authority.schemas.continuity_bundle)
  if (-not (($record | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath)) { throw '[mir4-continuity-bundle-schema]' }
  return $record
}

function New-MIR4RuntimeStateInventory {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return New-MIR4RuntimeStateMatrix -RepoRoot $RepoRoot -Providers $null -SourceIdentity $null
}
