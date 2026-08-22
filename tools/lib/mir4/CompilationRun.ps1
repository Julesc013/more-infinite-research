function Get-MIR4SemanticCompilerAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $path = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Semantic-Compiler-ProgrammeV1.json'
  $authority = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ([int]$authority.schema -ne 1 -or [string]$authority.kind -cne 'MIR4SemanticCompilerProgrammeV1') { throw '[mir4-semantic-compiler-authority]' }
  foreach ($flag in @('semantic_authority','player_package_mutation_authorized','runtime_state_mutation_authorized','public_support_authorized','signing_or_sealing_authorized','publication_authorized')) {
    if ([bool]$authority.$flag) { throw "[mir4-semantic-compiler-boundary] $flag" }
  }
  if (@($authority.provider_protocols.id | Sort-Object -Unique).Count -ne 13) { throw '[mir4-semantic-protocol-count]' }
  if (@($authority.merge_laws.id | Sort-Object -Unique).Count -ne 12) { throw '[mir4-semantic-merge-law-count]' }
  if (@($authority.plans.id | Sort-Object -Unique).Count -ne 7) { throw '[mir4-semantic-plan-count]' }
  foreach ($pathValue in @($authority.terminal_player_authority)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo ([string]$pathValue)) -PathType Leaf)) { throw "[mir4-semantic-terminal-authority] $pathValue" }
  }
  return $authority
}

function New-MIR4SemanticAuthorityRef {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Role,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Status,
    [Parameter(Mandatory)][string]$Maturity
  )
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $file = Join-Path $repo $Path
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "[mir4-semantic-reference-missing] ${Role}:$Path" }
  return [ordered]@{role=$Role;authority=$Path;sha256=(Get-MIR4PlatformFileSha256 $file);status=$Status;maturity=$Maturity}
}

function New-MIR4ProviderMicroProtocolMatrix {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $authority = Get-MIR4SemanticCompilerAuthority -RepoRoot $repo
  $rows = @(
    foreach ($protocol in @($authority.provider_protocols | Sort-Object id)) {
      $owner = [string]$protocol.owner
      $ownerRef = New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role ([string]$protocol.id) -Path $owner -Status 'legacy-adapter-current-owner' -Maturity 'shadow'
      [ordered]@{
        protocol=[string]$protocol.id
        owner=$ownerRef
        legacy_field=[string]$protocol.legacy_field
        adapter=[string]$authority.legacy_adapter.kind
        rewrite_required=[bool]$authority.legacy_adapter.rewrite_required
        operations=@('read-declared-provider-field','normalize-reference','emit-shadow-record')
        forbidden_operations=@('invoke-callback','mutate-prototype','write-runtime-state','execute-migration','publish')
        status='adapted-without-provider-rewrite'
      }
    }
  )
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4ProviderMicroProtocolMatrixV1';programme_id=[string]$authority.programme_id;maturity='shadow'
    legacy_contract=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'legacy-provider-contract' -Path ([string]$authority.legacy_adapter.source_contract) -Status 'player-authoritative-unchanged' -Maturity 'stable')
    protocols=$rows;player_package_rewrite=$false;mutation_capability=$false;publication_authorized=$false;digest=''
  }
  return Add-MIR4PlatformDigest $record
}

function Invoke-MIR4SemanticMergeOperator {
  param([Parameter(Mandatory)][string]$Law,[Parameter(Mandatory)][object[]]$Values)
  switch ($Law) {
    'hard-safety' {
      return $(if (@($Values | Where-Object { [string]$_ -eq 'deny' }).Count) { 'deny' } else { 'allow' })
    }
    'target-support' {
      $rank = @{supported=0;conditional=1;unsupported=2}
      $value = @($Values | ForEach-Object { [string]$_ } | Sort-Object { $rank[$_] } -Descending | Select-Object -First 1)
      return $value[0]
    }
    'feature-disable' {
      return $(if (@($Values | Where-Object { [string]$_ -eq 'disabled' }).Count) { 'disabled' } else { 'enabled' })
    }
    { $_ -in @('owner','presentation') } {
      return @($Values | Sort-Object @{Expression={[int]$_.precedence};Descending=$true},@{Expression={[string]$_.id};Descending=$false} | Select-Object -First 1)[0]
    }
    { $_ -in @('science-packs','prerequisites','diagnostics','evidence') } {
      return @($Values | ForEach-Object { @($_) } | ForEach-Object { $_ } | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
    }
    'numeric-values' {
      $maximum = ($Values | ForEach-Object { [Math]::Max(0,[Math]::Min(100,[int]$_)) } | Measure-Object -Maximum).Maximum
      return [int]$maximum
    }
    default { throw "[mir4-semantic-merge-operator] $Law" }
  }
}

function Test-MIR4SemanticMergeLaws {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $authority = Get-MIR4SemanticCompilerAuthority -RepoRoot $repo
  $fixtures = @{
    'hard-safety'=@('allow','deny','allow')
    'target-support'=@('supported','unsupported','conditional')
    'feature-disable'=@('enabled','disabled','enabled')
    'owner'=@([pscustomobject]@{id='zeta';precedence=10},[pscustomobject]@{id='alpha';precedence=20},[pscustomobject]@{id='beta';precedence=20})
    'science-packs'=@('space-science-pack','automation-science-pack','space-science-pack')
    'prerequisites'=@('mining-productivity-3','automation-3','automation-3')
    'numeric-values'=@(12,1000,-5,31)
    'presentation'=@([pscustomobject]@{id='fallback';precedence=0},[pscustomobject]@{id='reviewed';precedence=50})
    'diagnostics'=@('mir4-b','mir4-a','mir4-b')
    'evidence'=@('sha256:bbbb','sha256:aaaa','sha256:bbbb')
  }
  $rows = @()
  foreach ($law in @($authority.merge_laws)) {
    $id = [string]$law.id
    $owner = [string]$law.owner
    if ([string]$law.status -eq 'deferred-runtime-owner') {
      $rows += [ordered]@{law=$id;operator=[string]$law.operator;owner=$owner;status='deferred-runtime-owner';declared_properties=@($law.properties);passed=$null;evidence=@('owner:W04')}
      continue
    }
    $ownerRef = New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role "merge-law:$id" -Path $owner -Status 'current-domain-owner' -Maturity 'stable'
    $values = @($fixtures[$id])
    $forward = Invoke-MIR4SemanticMergeOperator -Law $id -Values $values
    $reversed = @($values)
    [Array]::Reverse($reversed)
    $reverse = Invoke-MIR4SemanticMergeOperator -Law $id -Values $reversed
    $permuted = Invoke-MIR4SemanticMergeOperator -Law $id -Values @($values[1..($values.Count-1)] + $values[0])
    $duplicate = Invoke-MIR4SemanticMergeOperator -Law $id -Values @($values + $values)
    $canonicalForward = ConvertTo-MIR4PlatformCanonicalJson $forward
    foreach ($candidate in @($reverse,$permuted,$duplicate)) {
      if ((ConvertTo-MIR4PlatformCanonicalJson $candidate) -cne $canonicalForward) { throw "[mir4-semantic-merge-law] $id" }
    }
    $rows += [ordered]@{law=$id;operator=[string]$law.operator;owner=$ownerRef;status='passed';declared_properties=@($law.properties);passed=$true;evidence=@('forward-reverse-permutation','duplicate-idempotence')}
  }
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4MergeLawCatalogueV1';programme_id=[string]$authority.programme_id;maturity='shadow';laws=$rows
    implemented_passed=(@($rows | Where-Object { $_.status -eq 'passed' }).Count -eq 10)
    deferred_owners=@($rows | Where-Object { $_.status -eq 'deferred-runtime-owner' } | ForEach-Object { [string]$_.law })
    complete=$false;mutation_capability=$false;publication_authorized=$false;digest=''
  }
  return Add-MIR4PlatformDigest $record
}

function New-MIR4FeatureSettingCutoverMatrix {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Providers)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $settingsRefs = @(
    (New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'setting-spec-catalog' -Path '.mir/settings.yml' -Status 'player-authoritative-unchanged' -Maturity 'stable'),
    (New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'setting-catalog-implementation' -Path 'prototypes/mir/settings/catalog.lua' -Status 'player-authoritative-unchanged' -Maturity 'stable'),
    (New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'effective-settings' -Path 'prototypes/mir/settings/effective.lua' -Status 'player-authoritative-unchanged' -Maturity 'stable')
  )
  $rows = @(
    foreach ($provider in @($Providers)) {
      $snapshotPath = if ($provider.predecessor) { [string]$provider.predecessor.snapshot } else { '' }
      $snapshotRef = if ($snapshotPath -and (Test-Path -LiteralPath (Join-Path $repo $snapshotPath) -PathType Leaf)) {
        New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'terminal-feature-setting-snapshot' -Path $snapshotPath -Status 'reference-available' -Maturity 'stable'
      } else {
        [ordered]@{role='terminal-feature-setting-snapshot';authority=$null;sha256=$null;status='blocked-missing-predecessor-snapshot';maturity='omitted-by-target'}
      }
      [ordered]@{
        target=[string]$provider.id
        feature_manifest=[ordered]@{kind='MIR4FeatureManifestRefV1';aggregate_only=$true;snapshot=$snapshotRef;provider_digest=[string]$provider.digest;status=$(if($snapshotPath){'legacy-authority-referenced'}else{'omitted-by-target'})}
        setting_spec=[ordered]@{kind='MIR4SettingSpecRefV1';aggregate_only=$true;authorities=$settingsRefs;profile_digest=[string]$provider.profile.digest;status=$(if($snapshotPath){'legacy-authority-referenced'}else{'omitted-by-target'})}
        duplicated_fact_or_policy_authority=$false
        package_visible=$false
      }
    }
  )
  $record = [pscustomobject][ordered]@{schema=1;kind='MIR4FeatureSettingCutoverMatrixV1';programme_id='M4C02-09-24H';maturity='shadow';targets=$rows;mutation_capability=$false;publication_authorized=$false;digest=''}
  return Add-MIR4PlatformDigest $record
}

function New-MIR4SemanticCompilationRuns {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Providers)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $authority = Get-MIR4SemanticCompilerAuthority -RepoRoot $repo
  $contracts = New-MIR4TargetContractSet -RepoRoot $repo
  $contractByTarget = @{}; foreach($row in @($contracts.targets)){$contractByTarget[[string]$row.target]=$row}
  $cutover = New-MIR4FeatureSettingCutoverMatrix -RepoRoot $repo -Providers $Providers
  $cutoverByTarget = @{}; foreach($row in @($cutover.targets)){$cutoverByTarget[[string]$row.target]=$row}
  $protocols = New-MIR4ProviderMicroProtocolMatrix -RepoRoot $repo
  $mergeLaws = Test-MIR4SemanticMergeLaws -RepoRoot $repo
  $runtimeInventory = New-MIR4RuntimeStateInventory -RepoRoot $repo
  $inputs = Get-MIR4PlatformInputs $repo
  $inputLock = [pscustomobject][ordered]@{kind='MIR4PlatformInputLockV1';inputs=$inputs;digest=''}; Add-MIR4PlatformDigest $inputLock|Out-Null
  $schemaPath = Join-Path $repo ([string]$authority.compilation_run_schema)
  $runs = @(
    foreach ($provider in @($Providers)) {
      $target = [string]$provider.id
      $contract = $contractByTarget[$target]
      $featureSetting = $cutoverByTarget[$target]
      $snapshotPath = if ($provider.predecessor) { [string]$provider.predecessor.snapshot } else { '' }
      $hasSnapshot = $snapshotPath -and (Test-Path -LiteralPath (Join-Path $repo $snapshotPath) -PathType Leaf)
      $snapshotRef = if ($hasSnapshot) { New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'normalized-terminal-snapshot' -Path $snapshotPath -Status 'reference-available' -Maturity 'stable' } else { [ordered]@{role='normalized-terminal-snapshot';authority=$null;sha256=$null;status='blocked-missing-predecessor-snapshot';maturity='omitted-by-target'} }
      $planRows = @(
        foreach($plan in @($authority.plans)){
          $owner=[string]$plan.owner
          $ownerValue=if($owner -eq 'W04'){[ordered]@{role=[string]$plan.id;authority='W04';sha256=$null;status=[string]$plan.status;maturity='deferred'}}else{New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role ([string]$plan.id) -Path $owner -Status ([string]$plan.status) -Maturity $(if([string]$plan.status -match 'blocked'){'blocked'}else{'stable'})}
          [ordered]@{id=[string]$plan.id;owner=$ownerValue;executor_authorized=$false}
        }
      )
      $proofs = @(
        [ordered]@{id='old-new-semantic-parity';status=$(if($hasSnapshot){'shadow-reference-ready'}else{'blocked-missing-predecessor-snapshot'});evidence=$snapshotRef},
        [ordered]@{id='target-parity';status='passed-provider-contract-laws';evidence=[ordered]@{contract_digest=[string]$contract.digest;provider_digest=[string]$provider.digest}},
        [ordered]@{id='migration-parity';status='deferred-W04';evidence=$null},
        [ordered]@{id='package-parity';status='no-W03-package-delta';evidence='package-source-fingerprint-gate'},
        [ordered]@{id='rollback';status='recorded';evidence=[string]$authority.rollback},
        [ordered]@{id='luna-acceptance';status='pending-independent-audit';evidence=$null}
      )
      $run = [pscustomobject][ordered]@{
        kind='MIR4CompilationRunV1';schema=1;programme_id=[string]$authority.programme_id
        target=[ordered]@{id=$target;factorio_line=[string]$provider.factorio_line;provider_digest=[string]$provider.digest;contract_digest=[string]$contract.digest}
        versions=[ordered]@{source='4.0.0';distribution=[string]$provider.distribution_version}
        adapter='LegacyCompilerHostAdapterV1';maturity='shadow'
        contract_set=[ordered]@{kind=[string]$contracts.kind;digest=[string]$contracts.digest;target_contract_digest=[string]$contract.digest;authority='.mir/releases/waves/mir4-r0/MIR4-Target-Compiler-ProgrammeV1.json'}
        platform_profile=[ordered]@{authority=[string]$provider.profile.authority;authority_sha256=[string]$provider.profile.authority_sha256;profile_digest=[string]$provider.profile.digest;status=[string]$provider.profile.status}
        environment_lock=[ordered]@{kind=[string]$inputLock.kind;digest=[string]$inputLock.digest;engine_lock=$provider.engine_lock;immutable_inputs=$true}
        target_provider=[ordered]@{kind=[string]$contract.provider_spec.kind;digest=[string]$provider.digest;maturity=[string]$contract.provider_spec.maturity;authority='MIR4-Target-RegistryV6'}
        module_extension_closure=[ordered]@{module_graph=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'module-dependency-graph' -Path '.mir/module-dependencies.json' -Status 'reference-available' -Maturity 'stable');provider_protocol_digest=[string]$protocols.digest;external_extension_closure='deferred-W05';mutation_authorized=$false}
        feature_manifest=$featureSetting.feature_manifest
        setting_spec=$featureSetting.setting_spec
        normalized_facts=[ordered]@{snapshot=$snapshotRef;adapter=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'compilation-snapshot-adapter' -Path 'prototypes/mir/pipeline/compilation_snapshot_adapter.lua' -Status 'player-authoritative-unchanged' -Maturity 'stable');duplicated_facts=$false}
        graphs=[ordered]@{qualification=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'graph-qualification' -Path 'prototypes/mir/graph/qualification.lua' -Status 'player-authoritative-unchanged' -Maturity 'stable');snapshot=$snapshotRef;duplicated_graph=$false}
        process_ir=[ordered]@{authority=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'process-ir-shadow-owner' -Path 'tools/lib/mir4/ProcessIR.ps1' -Status 'opaque-reference-deferred-W06' -Maturity 'shadow');semantic_owner='W06';duplicated_process_facts=$false}
        policy=[ordered]@{compatibility=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'compatibility-policy' -Path '.mir/compatibility.yml' -Status 'player-authoritative-unchanged' -Maturity 'stable');snapshot=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'policy-snapshot' -Path 'prototypes/mir/domain/compiler/policy_snapshot.lua' -Status 'player-authoritative-unchanged' -Maturity 'stable');merge_law_digest=[string]$mergeLaws.digest}
        claims=[ordered]@{registry=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'compatibility-claim-registry' -Path 'prototypes/mir/compatibility/claim_registry.lua' -Status 'player-authoritative-unchanged' -Maturity 'stable');provider_claim=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'provider-claim' -Path 'prototypes/mir/providers/pipeline/provider_claim.lua' -Status 'player-authoritative-unchanged' -Maturity 'stable')}
        resolutions=[ordered]@{owner=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'owner-arbitration' -Path 'prototypes/mir/providers/pipeline/owner_arbitration.lua' -Status 'player-authoritative-unchanged' -Maturity 'stable');decision=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'provider-decision' -Path 'prototypes/mir/providers/pipeline/decision.lua' -Status 'player-authoritative-unchanged' -Maturity 'stable')}
        plans=$planRows
        operations=[ordered]@{plan=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'transformation-plan' -Path 'prototypes/mir/domain/compiler/transformation_plan.lua' -Status 'player-authoritative-unchanged' -Maturity 'stable');executor=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'technology-operation-executor' -Path 'prototypes/mir/emit/technology_operation_executor.lua' -Status 'existing-authoritative-not-invoked' -Maturity 'stable');execution_authorized=$false}
        runtime_state=[ordered]@{inventory_kind=[string]$runtimeInventory.kind;inventory_digest=[string]$runtimeInventory.digest;authority='tools/lib/mir4/RuntimeStateModel.ps1';status='opaque-reference-deferred-W04';mutation_authorized=$false}
        proof_obligations=$proofs
        bounded_public_projections=[ordered]@{authority=(New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'public-compiler-artifacts' -Path 'prototypes/mir/report/public_compiler_artifacts.lua' -Status 'player-authoritative-unchanged' -Maturity 'stable');mode='reference-only';new_projection_authorized=$false;budget='existing-public-artifact-bounds'}
        merge_law_catalogue=[ordered]@{kind=[string]$mergeLaws.kind;digest=[string]$mergeLaws.digest;implemented_passed=[bool]$mergeLaws.implemented_passed;deferred_owners=@($mergeLaws.deferred_owners)}
        input_digests=$inputs
        stages=@('contract-admission','environment-lock','legacy-provider-adaptation','feature-setting-reference-aggregation','safety-kernel','policy-engine','merge-law-evaluation','plan-reference-projection','bounded-public-reference')
        result=$(if($hasSnapshot){'shadow-reference-aggregate-complete'}else{'blocked-missing-predecessor-snapshot'})
        authoritative_output=$false;mutation_capability=$false;runtime_state_mutation_capability=$false;public_support_claim=$false
        diagnostics=[object[]]$(if($hasSnapshot){@()}else{@([ordered]@{code='mir4-semantic-predecessor-absent';severity='blocked';target=$target})})
        digest=''
      }
      Add-MIR4PlatformDigest $run|Out-Null
      if (-not (($run|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile $schemaPath)) { throw "[mir4-compilation-run-v1-schema] $target" }
      $run
    }
  )
  return $runs
}
