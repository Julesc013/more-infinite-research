# MIR4-RUNTIME-CONTINUITY-CANONICAL-APPLICATION
function Get-MIR4RuntimeCurrentTargetPackageContext {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  if (-not (Get-Command New-MIR4CurrentTargetPackageContext -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/lib/validation/CurrentTargetPackage.ps1')
  }
  $cached = Get-Variable -Scope Script -Name MIR4RuntimeCurrentTargetPackageContext -ErrorAction SilentlyContinue
  if ($null -eq $cached -or $null -eq $cached.Value -or [string]$cached.Value.repo -cne $repo) {
    $script:MIR4RuntimeCurrentTargetPackageContext = New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target 'f210'
  }
  return $script:MIR4RuntimeCurrentTargetPackageContext
}

function Resolve-MIR4RuntimeProgrammePath {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RelativePath)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  if (-not (Get-Command Resolve-MIR4CurrentTargetPackageOutputPath -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/lib/validation/CurrentTargetPackage.ps1')
  }
  $relative = $RelativePath.Replace('\','/')
  $targetPackage = Get-MIR4RuntimeCurrentTargetPackageContext -RepoRoot $repo
  $packagePath = Resolve-MIR4CurrentTargetPackageOutputPath -Context $targetPackage -RelativePath $relative -AllowMissing
  if ($null -ne $packagePath) { return $packagePath }
  return Join-Path $repo $relative
}

function Get-MIR4RuntimeContinuityAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $path = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json'
  $authority = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ([int]$authority.schema -ne 1 -or [string]$authority.kind -cne 'MIR4RuntimeContinuityProgrammeV1') { throw '[mir4-runtime-continuity-authority]' }
  foreach ($flag in @('semantic_authority','player_package_mutation_authorized','runtime_registration_mutation_authorized','migration_execution_authorized','public_support_authorized','signing_or_sealing_authorized','publication_authorized')) {
    if ([bool]$authority.$flag) { throw "[mir4-runtime-continuity-boundary] $flag" }
  }
  # This is a frozen W04 predecessor.  Current runtime additions are read from
  # a separate append-only authority below; do not rewrite this inventory.
  if (@($authority.runtime_features.id | Sort-Object -Unique).Count -ne 7) { throw '[mir4-runtime-feature-count]' }
  if (@($authority.state_specs.id | Sort-Object -Unique).Count -ne 5) { throw '[mir4-state-spec-count]' }
  if (@($authority.registration_groups.id | Sort-Object -Unique).Count -ne 9) { throw '[mir4-registration-group-count]' }
  if (@($authority.migration_edges.id | Sort-Object -Unique).Count -ne 10) { throw '[mir4-migration-edge-count]' }
  foreach ($relative in @($authority.terminal_player_authority)) {
    $path = Resolve-MIR4RuntimeProgrammePath -RepoRoot $repo -RelativePath ([string]$relative)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-runtime-terminal-authority] $relative" }
  }
  return $authority
}

function Get-MIR4ClassicRuntimeNoticeAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $relative = 'governance/repository/mir430-classic-runtime-notice-v1.json'
  $path = Join-Path $repo $relative
  $schemaPath = Join-Path $repo 'spec/schemas/mir430-classic-runtime-notice-v1.schema.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
    throw '[mir430-classic-runtime-notice-authority-missing]'
  }
  $raw = Get-Content -Raw -LiteralPath $path
  if (-not ($raw | Test-Json -SchemaFile $schemaPath)) { throw '[mir430-classic-runtime-notice-authority-schema]' }
  $authority = $raw | ConvertFrom-Json
  if ([string]$authority.predecessor.path -cne '.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json' -or
      [string]$authority.predecessor.kind -cne 'MIR4RuntimeContinuityProgrammeV1' -or
      [string]$authority.predecessor.programme_id -cne 'M4C02-09-24H') { throw '[mir430-classic-runtime-notice-predecessor]' }
  foreach ($flag in @('runtime_registration_mutation_authorized','migration_execution_authorized','public_support_authorized','signing_or_sealing_authorized','publication_authorized')) {
    if ($authority.$flag -isnot [bool] -or [bool]$authority.$flag) { throw "[mir430-classic-runtime-notice-boundary] $flag" }
  }
  $feature = $authority.feature
  if ([string]$feature.id -cne 'runtime.compiler-profile-notice' -or [int]$feature.version -ne 1 -or
      [string]$feature.source -cne 'prototypes/mir/runtime/compiler_profile_notice.lua' -or
      (@($feature.handlers) -join '|') -cne 'on_init|on_load|on_configuration_changed' -or
      (@($feature.target_requirements) -join '|') -cne 'scripted_techs' -or @($feature.state_ids).Count -ne 0 -or
      [string]$feature.determinism -cne 'one-shot-load-selection-and-connected-player-order' -or
      [int]$feature.complexity_budget.one_shot_tick -ne 1 -or [string]$feature.complexity_budget.player_scan -cne 'O(connected_players)' -or
      [int]$feature.complexity_budget.idle_tick -ne 0 -or [int]$feature.complexity_budget.diagnostics_per_dispatch -ne 0 -or
      (@($feature.migration_refs) -join '|') -cne 'migration.same-target|migration.profile-schema' -or
      [string]$feature.disable_or_removal -cne 'full-profile-is-silent-and-no-persistent-notice-state-is-retained') {
    throw '[mir430-classic-runtime-notice-feature]'
  }
  $expectedSubscribers = [ordered]@{
    'lifecycle.init' = [ordered]@{registration='script.on_init';placement='append';subscriber='runtime.compiler-profile-notice:on_init'}
    'lifecycle.configuration-changed' = [ordered]@{registration='script.on_configuration_changed';placement='before:runtime.planet-discovery-recovery:on_configuration_changed';subscriber='runtime.compiler-profile-notice:on_configuration_changed'}
  }
  $actualGroups = @($authority.registration_subscribers | ForEach-Object { [string]$_.group_id })
  if ($actualGroups.Count -ne $expectedSubscribers.Count -or (@($actualGroups | Sort-Object) -join '|') -cne (@($expectedSubscribers.Keys | Sort-Object) -join '|')) {
    throw '[mir430-classic-runtime-notice-subscriber-groups]'
  }
  foreach ($groupId in @($expectedSubscribers.Keys)) {
    $row = @($authority.registration_subscribers | Where-Object { [string]$_.group_id -ceq $groupId })
    $expected = $expectedSubscribers[$groupId]
    if ($row.Count -ne 1 -or [string]$row[0].registration -cne [string]$expected.registration -or [string]$row[0].placement -cne [string]$expected.placement -or
        (@($row[0].subscribers) -join '|') -cne [string]$expected.subscriber) { throw "[mir430-classic-runtime-notice-subscriber] $groupId" }
  }
  if ([string]$authority.on_load.owner -cne 'prototypes/mir/runtime/scripted_techs.lua' -or
      [string]$authority.on_load.handler -cne 'anonymous-coordinator' -or
      (@($authority.on_load.callbacks) -join '|') -cne 'compiler_profile_notice.on_load' -or
      $authority.on_load.read_only_restoration -isnot [bool] -or -not [bool]$authority.on_load.read_only_restoration -or
      [int]$authority.on_load.registration_count -ne 1) { throw '[mir430-classic-runtime-notice-on-load]' }
  if ([string]$authority.on_tick.owner -cne 'compiler_profile_notice.on_load' -or
      [string]$authority.on_tick.handler -cne 'compiler_profile_notice.deliver_deferred_load_notice' -or
      $authority.on_tick.registered -isnot [bool] -or -not [bool]$authority.on_tick.registered -or
      $authority.on_tick.conditional_one_shot -isnot [bool] -or -not [bool]$authority.on_tick.conditional_one_shot -or
      $authority.on_tick.unsubscribes_before_delivery -isnot [bool] -or -not [bool]$authority.on_tick.unsubscribes_before_delivery -or
      [int]$authority.on_tick.budget -ne 1) { throw '[mir430-classic-runtime-notice-on-tick]' }
  return $authority
}

function Get-MIR4RuntimeEffectiveContinuityAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $base = Get-MIR4RuntimeContinuityAuthority -RepoRoot $repo
  $current = Get-MIR4ClassicRuntimeNoticeAuthority -RepoRoot $repo
  $effective = $base | ConvertTo-Json -Depth 100 | ConvertFrom-Json
  $featureIds = @($base.runtime_features | ForEach-Object { [string]$_.id })
  if ($featureIds -contains [string]$current.feature.id) { throw '[mir430-classic-runtime-notice-feature-collision]' }
  $effective.runtime_features = @($base.runtime_features) + @($current.feature)
  $additionsByGroup = @{}
  foreach ($addition in @($current.registration_subscribers)) {
    $groupId = [string]$addition.group_id
    if ($additionsByGroup.ContainsKey($groupId)) { throw "[mir430-classic-runtime-notice-duplicate-group] $groupId" }
    $additionsByGroup[$groupId] = [ordered]@{placement=[string]$addition.placement;subscribers=@($addition.subscribers | ForEach-Object { [string]$_ })}
  }
  $effectiveGroups = @(
    foreach ($group in @($base.registration_groups)) {
      $groupId = [string]$group.id
      $subscribers = @($group.subscribers | ForEach-Object { [string]$_ })
      if ($additionsByGroup.ContainsKey($groupId)) {
        $addition = $additionsByGroup[$groupId]
        if ([string]$addition.placement -ceq 'append') {
          $subscribers += @($addition.subscribers)
        } elseif ([string]$addition.placement -clike 'before:*') {
          $anchor = ([string]$addition.placement).Substring('before:'.Length)
          $index = [array]::IndexOf([string[]]$subscribers, $anchor)
          if ($index -lt 0) { throw "[mir430-classic-runtime-notice-placement-anchor] $groupId" }
          $before = if ($index -eq 0) { @() } else { @($subscribers[0..($index - 1)]) }
          $subscribers = $before + @($addition.subscribers) + @($subscribers[$index..($subscribers.Count - 1)])
        } else { throw "[mir430-classic-runtime-notice-placement] $groupId" }
        $additionsByGroup.Remove($groupId)
      }
      [pscustomobject][ordered]@{id=$groupId;registration=[string]$group.registration;filter=[string]$group.filter;subscribers=$subscribers}
    }
  )
  if ($additionsByGroup.Count -ne 0) { throw '[mir430-classic-runtime-notice-unknown-group]' }
  $effective.registration_groups = $effectiveGroups
  $reference = [ordered]@{
    path='governance/repository/mir430-classic-runtime-notice-v1.json';kind=[string]$current.kind;authority_id=[string]$current.authority_id
    sha256=(Get-MIR4PlatformInputSha256 (Join-Path $repo 'governance/repository/mir430-classic-runtime-notice-v1.json'))
  }
  $effective | Add-Member -NotePropertyName current_additive_authority -NotePropertyValue $reference
  return $effective
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
  $authority = Get-MIR4RuntimeEffectiveContinuityAuthority -RepoRoot $repo
  $contexts = @(Get-MIR4RuntimeTargetContexts -RepoRoot $repo -Providers $Providers)
  return @(
    foreach ($feature in @($authority.runtime_features | Sort-Object id)) {
      $source = [string]$feature.source
      $path = Resolve-MIR4RuntimeProgrammePath -RepoRoot $repo -RelativePath $source
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
  # State buckets remain entirely owned by the frozen W04 predecessor.  The
  # current notice authority declares no persistent state.
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
  $onLoadProperty = $Plan.PSObject.Properties['on_load']
  if ($null -eq $onLoadProperty -or $null -eq $onLoadProperty.Value) { throw '[mir4-runtime-on-load-registration]' }
  $onLoad = $onLoadProperty.Value
  $onLoadDictionary = $onLoad -is [Collections.IDictionary]
  $registeredProperty = if ($onLoadDictionary) { $null } else { $onLoad.PSObject.Properties['registered'] }
  $mutationProperty = if ($onLoadDictionary) { $null } else { $onLoad.PSObject.Properties['persistent_mutation'] }
  $registeredPresent = if ($onLoadDictionary) { $onLoad.Contains('registered') } else { $null -ne $registeredProperty }
  $mutationPresent = if ($onLoadDictionary) { $onLoad.Contains('persistent_mutation') } else { $null -ne $mutationProperty }
  $registeredValue = if ($onLoadDictionary) { $onLoad['registered'] } elseif ($registeredPresent) { $registeredProperty.Value } else { $null }
  $mutationValue = if ($onLoadDictionary) { $onLoad['persistent_mutation'] } elseif ($mutationPresent) { $mutationProperty.Value } else { $null }
  $handlerPresent = if ($onLoadDictionary) { $onLoad.Contains('handler') } else { $null -ne $onLoad.PSObject.Properties['handler'] }
  $callbacksPresent = if ($onLoadDictionary) { $onLoad.Contains('callbacks') } else { $null -ne $onLoad.PSObject.Properties['callbacks'] }
  $callbackIds = @(
    if ($callbacksPresent) { $onLoad.callbacks | ForEach-Object { [string]$_ } }
  )
  $approvedCallbackIds = @('passive_repair.on_load','research_browser.on_load','compiler_profile_notice.on_load')
  $countPresent = if ($onLoadDictionary) { $onLoad.Contains('registration_count') } else { $null -ne $onLoad.PSObject.Properties['registration_count'] }
  $readonlyPresent = if ($onLoadDictionary) { $onLoad.Contains('read_only_restoration') } else { $null -ne $onLoad.PSObject.Properties['read_only_restoration'] }
  if (-not $registeredPresent -or -not $mutationPresent -or $registeredValue -isnot [bool] -or $mutationValue -isnot [bool]) { throw '[mir4-runtime-on-load-registration]' }
  if ($readonlyPresent -and $onLoad.read_only_restoration -isnot [bool]) { throw '[mir4-runtime-on-load-registration]' }
  if ([bool]$registeredValue) {
    $hosts = @($onLoad.hosts)
    if ([string]$Plan.owner -cne 'prototypes/mir/runtime/scripted_techs.lua' -or
        [string]$onLoad.handler -cne 'anonymous-coordinator' -or
        -not $callbacksPresent -or
        $callbackIds.Count -ne $approvedCallbackIds.Count -or
        ($callbackIds -join '|') -cne ($approvedCallbackIds -join '|') -or
        -not [bool]$onLoad.read_only_restoration -or
        [int]$onLoad.registration_count -ne 1 -or
        $hosts.Count -ne 2 -or
        (@($hosts.target | Sort-Object -Unique) -join '|') -cne 'f200|f210') { throw '[mir4-runtime-on-load-registration]' }
    foreach ($hostEntry in $hosts) {
      $hostCallbackIds = @($hostEntry.approved_callbacks | ForEach-Object { [string]$_ })
      if ([string]$hostEntry.approved_handler -cne 'anonymous-coordinator' -or
          $hostCallbackIds.Count -ne $approvedCallbackIds.Count -or
          ($hostCallbackIds -join '|') -cne ($approvedCallbackIds -join '|') -or
          [int]$hostEntry.registration_count -ne 1 -or
          [int]$hostEntry.approved_registration_count -ne 1 -or
          [string]$hostEntry.source_identity.dispatcher.path -cne 'prototypes/mir/runtime/scripted_techs.lua' -or
          [string]$hostEntry.source_identity.stage.path -cne 'prototypes/mir/stage/control.lua' -or
          [string]$hostEntry.source_identity.dispatcher.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
          [string]$hostEntry.source_identity.stage.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw '[mir4-runtime-on-load-registration]' }
    }
  } else {
    if (($handlerPresent -and -not [string]::IsNullOrWhiteSpace([string]$onLoad.handler)) -or
        ($callbacksPresent -and $callbackIds.Count -ne 0) -or
        ($countPresent -and [int]$onLoad.registration_count -ne 0) -or
        ($readonlyPresent -and [bool]$onLoad.read_only_restoration)) { throw '[mir4-runtime-on-load-registration]' }
  }
  $onTickProperty = $Plan.PSObject.Properties['on_tick']
  if ($null -eq $onTickProperty -or $null -eq $onTickProperty.Value) { throw '[mir4-runtime-idle-or-load-mutation]' }
  $onTick = $onTickProperty.Value
  $onTickDictionary = $onTick -is [Collections.IDictionary]
  $tickRegisteredPresent = if ($onTickDictionary) { $onTick.Contains('registered') } else { $null -ne $onTick.PSObject.Properties['registered'] }
  $tickBudgetPresent = if ($onTickDictionary) { $onTick.Contains('budget') } else { $null -ne $onTick.PSObject.Properties['budget'] }
  $tickConditionalPresent = if ($onTickDictionary) { $onTick.Contains('conditional_one_shot') } else { $null -ne $onTick.PSObject.Properties['conditional_one_shot'] }
  $tickOwnerPresent = if ($onTickDictionary) { $onTick.Contains('owner') } else { $null -ne $onTick.PSObject.Properties['owner'] }
  $tickHandlerPresent = if ($onTickDictionary) { $onTick.Contains('handler') } else { $null -ne $onTick.PSObject.Properties['handler'] }
  $tickUnsubscribePresent = if ($onTickDictionary) { $onTick.Contains('unsubscribes_before_delivery') } else { $null -ne $onTick.PSObject.Properties['unsubscribes_before_delivery'] }
  if (-not $tickRegisteredPresent -or -not $tickBudgetPresent -or -not $tickConditionalPresent -or
      -not $tickOwnerPresent -or -not $tickHandlerPresent -or -not $tickUnsubscribePresent -or
      $onTick.registered -isnot [bool] -or $onTick.conditional_one_shot -isnot [bool] -or
      $onTick.unsubscribes_before_delivery -isnot [bool] -or
      ($onTick.budget -isnot [int] -and $onTick.budget -isnot [long]) -or $onTick.budget -ne 1 -or
      -not [bool]$onTick.registered -or -not [bool]$onTick.conditional_one_shot -or
      -not [bool]$onTick.unsubscribes_before_delivery -or
      [string]$onTick.owner -cne 'compiler_profile_notice.on_load' -or
      [string]$onTick.handler -cne 'compiler_profile_notice.deliver_deferred_load_notice' -or
      $mutationValue) { throw '[mir4-runtime-idle-or-load-mutation]' }
  return $true
}

function Get-MIR4RuntimeOnLoadSourceRegistration {
  param([Parameter(Mandatory)][string]$HostText,[string]$NoticeCallback='compiler_profile_notice.on_load')
  $registrations = @([regex]::Matches($HostText, 'script\s*\.\s*on_load\s*\('))
  # Recognize the reviewed coordinator, including its Library capability guard.
  # Additional statements, alternate guards and extra registrations stay denied.
  $approvedPattern = 'script\s*\.\s*on_load\s*\(\s*function\s*\(\s*\)\s*passive_repair\s*\.\s*on_load\s*\(\s*\)\s*if\s+research_browser\s+then\s+research_browser\s*\.\s*on_load\s*\(\s*\)\s*end\s*' + [regex]::Escape($NoticeCallback) + '\s*\(\s*\)\s*end\s*\)'
  $approved = @([regex]::Matches($HostText, $approvedPattern))
  if ($registrations.Count -ne 1 -or $approved.Count -ne 1) { throw '[mir4-runtime-on-load-registration]' }
  return [pscustomobject]@{registration_count=$registrations.Count;approved_registration_count=$approved.Count}
}

function New-MIR4RuntimeRegistrationPlan {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$RuntimeFeatures)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  if (-not (Get-Command New-MIR4CurrentTargetPackageContext -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/lib/validation/CurrentTargetPackage.ps1')
  }
  $targetPackage = New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target 'f210'
  $authority = Get-MIR4RuntimeEffectiveContinuityAuthority -RepoRoot $repo
  $noticeAuthority = Get-MIR4ClassicRuntimeNoticeAuthority -RepoRoot $repo
  $onLoadCallbacks = @('passive_repair.on_load','research_browser.on_load') + @($noticeAuthority.on_load.callbacks | ForEach-Object { [string]$_ })
  $featureById = @{}; foreach ($feature in @($RuntimeFeatures)) { $featureById[[string]$feature.id] = $feature }
  $dispatcherPath = Resolve-MIR4CurrentTargetPackageOutputPath -Context $targetPackage -RelativePath 'prototypes/mir/runtime/scripted_techs.lua'
  $stagePath = Resolve-MIR4CurrentTargetPackageOutputPath -Context $targetPackage -RelativePath 'prototypes/mir/stage/control.lua'
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
  $noticePath = Resolve-MIR4RuntimeProgrammePath -RepoRoot $repo -RelativePath ([string]$noticeAuthority.feature.source)
  $noticeText = Get-Content -Raw -LiteralPath $noticePath
  $onTickSourceHandler = @([string]$noticeAuthority.on_tick.handler -split '\.')[-1]
  $runtimeSourceRoot = Join-Path $repo 'source/prototypes/mir/runtime'
  $onTickSources = @(
    Get-ChildItem -LiteralPath $runtimeSourceRoot -Recurse -File -Filter '*.lua' |
      Where-Object { (Get-Content -Raw -LiteralPath $_.FullName) -match 'defines\.events\.on_tick' } |
      ForEach-Object { [System.IO.Path]::GetRelativePath((Join-Path $repo 'source'), $_.FullName).Replace('\','/') }
  )
  if ($onTickSources.Count -ne 1 -or $onTickSources[0] -cne [string]$noticeAuthority.feature.source -or
      @([regex]::Matches($noticeText, 'script\s*\.\s*on_event\s*\(\s*defines\s*\.\s*events\s*\.\s*on_tick\s*,')).Count -ne 2 -or
      $noticeText -notmatch ('script\s*\.\s*on_event\s*\(\s*defines\s*\.\s*events\s*\.\s*on_tick\s*,\s*' + [regex]::Escape($onTickSourceHandler) + '\s*\)') -or
      $noticeText -notmatch 'script\s*\.\s*on_event\s*\(\s*defines\s*\.\s*events\s*\.\s*on_tick\s*,\s*nil\s*\)') { throw '[mir4-runtime-unbudgeted-on-tick]' }
  $onLoadHosts = @(
    foreach ($hostTarget in @('f210','f200')) {
      $hostPackage = if ($hostTarget -ceq 'f210') { $targetPackage } else { New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target $hostTarget }
      $hostDispatcherPath = Resolve-MIR4CurrentTargetPackageOutputPath -Context $hostPackage -RelativePath 'prototypes/mir/runtime/scripted_techs.lua'
      $hostStagePath = Resolve-MIR4CurrentTargetPackageOutputPath -Context $hostPackage -RelativePath 'prototypes/mir/stage/control.lua'
      $hostText = (Get-Content -Raw -LiteralPath $hostDispatcherPath) + "`n" + (Get-Content -Raw -LiteralPath $hostStagePath)
      $registration = Get-MIR4RuntimeOnLoadSourceRegistration -HostText $hostText -NoticeCallback ([string]$noticeAuthority.on_load.callbacks[0])
      [ordered]@{
        target=$hostTarget;approved_handler=[string]$noticeAuthority.on_load.handler;approved_callbacks=$onLoadCallbacks;registration_count=$registration.registration_count;approved_registration_count=$registration.approved_registration_count
        source_identity=[ordered]@{
          dispatcher=[ordered]@{path='prototypes/mir/runtime/scripted_techs.lua';sha256=(Get-MIR4PlatformInputSha256 $hostDispatcherPath)}
          stage=[ordered]@{path='prototypes/mir/stage/control.lua';sha256=(Get-MIR4PlatformInputSha256 $hostStagePath)}
        }
      }
    }
  )
  $plan = [pscustomobject][ordered]@{
    kind='MIR4RuntimeRegistrationPlanV1';schema=1;owner='prototypes/mir/runtime/scripted_techs.lua';owner_sha256=(Get-MIR4PlatformInputSha256 $dispatcherPath);groups=$groups
    ordering='authority-array-preserved-as-explicit-ordinal';filter_before_dispatch=$true;one_registration_per_group=$true
    on_load=[ordered]@{
      registered=$true;handler=[string]$noticeAuthority.on_load.handler;callbacks=$onLoadCallbacks;read_only_restoration=[bool]$noticeAuthority.on_load.read_only_restoration;registration_count=[int]$noticeAuthority.on_load.registration_count;hosts=$onLoadHosts
      persistent_mutation=$false
    };on_tick=[ordered]@{registered=[bool]$noticeAuthority.on_tick.registered;conditional_one_shot=[bool]$noticeAuthority.on_tick.conditional_one_shot;owner=[string]$noticeAuthority.on_tick.owner;handler=[string]$noticeAuthority.on_tick.handler;budget=[int]$noticeAuthority.on_tick.budget;unsubscribes_before_delivery=[bool]$noticeAuthority.on_tick.unsubscribes_before_delivery}
    cross_feature_state_mutation=$false;duplicate_rejection=$true;maximum_diagnostics_per_dispatch=64
    law_results=[ordered]@{unique_groups=$true;unique_subscribers=$true;stable_order=$true;filter_before_dispatch=$true;no_on_load_mutation=$true;one_shot_on_load_tick=$true;no_idle_tick=$true;namespace_isolation=$true;bounded_diagnostics=$true;all_passed=$true}
  }
  Assert-MIR4RuntimeRegistrationPlan -Plan $plan | Out-Null
  return $plan
}

function New-MIR4RuntimeStateMatrix {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$Providers,[AllowNull()]$SourceIdentity)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $authority = Get-MIR4RuntimeContinuityAuthority -RepoRoot $repo
  $effectiveAuthority = Get-MIR4RuntimeEffectiveContinuityAuthority -RepoRoot $repo
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
    authority='.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json';current_additive_authority=$effectiveAuthority.current_additive_authority;maturity='shadow';runtime_feature_specs=$features;state_specs=$states;registration_plan=$registration;targets=$targets
    invariants=@('terminal-runtime-remains-player-authority','runtime-never-mutates-prototypes','state-owned-under-mir-namespace','backend-derived-from-target-profile','field-aware-state-classification','one-registration-per-event-filter-group','filter-before-dispatch','stable-subscriber-order','no-on-load-persistent-mutation','one-shot-on-load-notice-tick','no-idle-on-tick','no-cross-feature-state-mutation','bounded-diagnostics')
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
          $path = Resolve-MIR4RuntimeProgrammePath -RepoRoot $repo -RelativePath ([string]$relative)
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
