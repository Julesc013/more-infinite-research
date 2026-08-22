function Get-MIR4TargetCompilerAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $path = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Target-Compiler-ProgrammeV1.json'
  $authority = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ([int]$authority.schema -ne 1 -or [string]$authority.kind -cne 'MIR4TargetCompilerProgrammeV1') { throw '[mir4-target-compiler-authority-schema]' }
  foreach ($flag in @('semantic_authority','player_package_mutation_authorized','public_support_authorized','signing_or_sealing_authorized','publication_authorized')) {
    if ([bool]$authority.$flag) { throw "[mir4-target-compiler-boundary] $flag" }
  }
  $expectedLaws = @('determinism','supported-subset-round-trip','unowned-field-preservation','idempotence','locality','explicit-loss','no-hidden-product-policy','provenance-completeness','budget-compliance')
  if ((@($authority.provider_abi.laws | Sort-Object) -join '|') -cne (@($expectedLaws | Sort-Object) -join '|')) { throw '[mir4-target-provider-laws]' }
  $registryPath = Join-Path $repo ([string]$authority.identity_authority)
  if (-not ((Get-Content -Raw -LiteralPath $registryPath) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-target-registry-v6.schema.json'))) { throw '[mir4-target-registry-v6-schema]' }
  $registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json
  if (@($registry.identities.target | Sort-Object -Unique).Count -ne 17 -or @($registry.support_policy.target | Sort-Object -Unique).Count -ne 17) { throw '[mir4-target-registry-v6-count]' }
  if ((@($registry.identities.target | Sort-Object) -join '|') -cne (@($registry.support_policy.target | Sort-Object) -join '|')) { throw '[mir4-target-registry-v6-join]' }
  return $authority
}

function Get-MIR4TargetMaturity {
  param([Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)]$Authority)
  $row = @($Authority.target_groups | Where-Object { $Target -in @($_.targets) })
  if ($row.Count -ne 1) { throw "[mir4-target-maturity] $Target" }
  return $row[0]
}

function Get-MIR4TargetInputStatus {
  param([Parameter(Mandatory)]$Provider)
  if ([string]$Provider.support_tier -eq 'museum') {
    return [ordered]@{status='BLOCKED_WITH_EVIDENCE';missing=@('governed-predecessor-package','normalized-predecessor-snapshot','exact-engine-lock','rights-custody-record')}
  }
  $missing = @()
  if (-not $Provider.predecessor) { $missing += 'governed-predecessor-snapshot' }
  if (-not $Provider.engine_lock) { $missing += 'exact-engine-lock' }
  return [ordered]@{status=$(if ($missing.Count) {'BLOCKED_WITH_EVIDENCE'} else {'inputs-recorded'});missing=$missing}
}

function New-MIR4TargetContractSet {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $authority = Get-MIR4TargetCompilerAuthority -RepoRoot $repo
  $providers = @(New-MIR4NormalizedTargetProviders -RepoRoot $repo)
  $profileAuthority = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/targets.json') | ConvertFrom-Json
  $rows = @(
    foreach ($provider in $providers) {
      $group = Get-MIR4TargetMaturity -Target ([string]$provider.id) -Authority $authority
      $profile = $profileAuthority.profiles.PSObject.Properties[[string]$provider.factorio_line]
      $profileValue = if ($null -ne $profile) { $profile.Value } else { $null }
      $inputStatus = Get-MIR4TargetInputStatus -Provider $provider
      $facilities = @(
        [ordered]@{id='distribution-identity';disposition='native';evidence='MIR4-Target-RegistryV5'},
        [ordered]@{id='package-materialization';disposition=$(if ($provider.support_tier -eq 'museum') {'unsupported-with-evidence'} elseif ($provider.support_tier -eq 'historical') {'finite-substitute'} else {'adapted'});evidence=$(if ($provider.support_tier -eq 'historical') {'MIR4-Historical-Private-Candidate-AuthorizationV1'} else {'MIR4-Bootstrap-Local-Candidate-PlanV3'})},
        [ordered]@{id='exact-engine-runtime';disposition=$(if ($provider.engine_lock) {'native'} else {'unsupported-with-evidence'});evidence=$(if ($provider.engine_lock) {$provider.engine_lock.authority} else {'missing-exact-engine-lock'})},
        [ordered]@{id='space-age';disposition=$(if ($profileValue -and [bool]$profileValue.supports_space_age) {'native'} else {'compiled-out'});evidence='.mir/targets.json'},
        [ordered]@{id='quality';disposition=$(if ($profileValue -and [bool]$profileValue.prototype_shapes.quality) {'native'} else {'omitted-by-capability'});evidence='.mir/targets.json'},
        [ordered]@{id='runtime-state';disposition=$(if ($profileValue) {'adapted'} elseif ($provider.support_tier -eq 'museum') {'unsupported-with-evidence'} else {'finite-substitute'});evidence=$(if ($profileValue) {'.mir/targets.json'} else {'terminal-normalized-snapshot'})}
      )
      $record = [pscustomobject][ordered]@{
        kind='MIR4TargetContractV1';schema=1;target=[string]$provider.id;maturity=[string]$group.maturity;mode=[string]$group.mode
        identity=[ordered]@{target_id=[string]$provider.target_id;factorio_line=[string]$provider.factorio_line;distribution_target_code=[string]$provider.distribution_target_code;distribution_version=[string]$provider.distribution_version;authority='MIR4-Target-RegistryV5'}
        support_policy=[ordered]@{tier=[string]$provider.support_tier;disposition=[string]$provider.disposition;release_blocking=[bool]$provider.release_blocking;public_support=$false;authority='MIR4-Target-RegistryV5'}
        profile=[ordered]@{authority='.mir/targets.json';status=$(if ($profileValue) {'explicit'} else {'terminal-derived-or-unavailable'});runtime_state_backend=$(if ($profileValue) {[string]$profileValue.runtime_state_backend} else {$null});features=$(if ($profileValue) {$profileValue.features} else {$null})}
        provider_spec=[ordered]@{kind='MIR4TargetProviderSpecV1';maturity='preview';provider_digest=[string]$provider.digest;owned_fields=@($authority.provider_abi.owned_fields);laws=@($authority.provider_abi.laws);operations=@($provider.operations);forbidden_operations=@($provider.forbidden_operations)}
        distribution=[ordered]@{kind='MIR4TargetDistributionRecordV1';version=[string]$provider.distribution_version;state=$(if ($provider.support_tier -eq 'museum') {'omitted-by-target'} else {'private-build-planned'});publication_authorized=$false}
        facilities=$facilities
        inputs=$inputStatus
        authoritative_output=$false;mutation_capability=$false;public_support_claim=$false;digest=''
      }
      Add-MIR4PlatformDigest $record
    }
  )
  $set = [pscustomobject][ordered]@{schema=1;kind='MIR4TargetContractSetV1';programme_id=[string]$authority.programme_id;maturity='preview';targets=$rows;authoritative_output=$false;mutation_capability=$false;publication_authorized=$false;digest=''}
  return Add-MIR4PlatformDigest $set
}

function Invoke-MIR4TargetProviderProjection {
  param([Parameter(Mandatory)]$Provider,[Parameter(Mandatory)]$InputRecord,[Parameter(Mandatory)]$OwnedChanges)
  $allowed = @($Provider.provider_spec.owned_fields | ForEach-Object { [string]$_ })
  foreach ($name in @($OwnedChanges.PSObject.Properties.Name)) {
    if ([string]$name -notin $allowed) { throw "[mir4-target-provider-unowned-write] $name" }
  }
  $output = $InputRecord | ConvertTo-Json -Depth 100 | ConvertFrom-Json
  if ($null -eq $output.PSObject.Properties['owned']) { Add-Member -InputObject $output -MemberType NoteProperty -Name owned -Value ([pscustomobject][ordered]@{}) }
  foreach ($property in $OwnedChanges.PSObject.Properties) {
    if ($null -eq $output.owned.PSObject.Properties[$property.Name]) { Add-Member -InputObject $output.owned -MemberType NoteProperty -Name $property.Name -Value $property.Value }
    else { $output.owned.($property.Name) = $property.Value }
  }
  return $output
}

function Test-MIR4TargetProviderLaws {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $authority = Get-MIR4TargetCompilerAuthority -RepoRoot $repo
  $left = New-MIR4TargetContractSet -RepoRoot $repo
  $right = New-MIR4TargetContractSet -RepoRoot $repo
  if ((ConvertTo-MIR4PlatformCanonicalJson $left) -cne (ConvertTo-MIR4PlatformCanonicalJson $right)) { throw '[mir4-target-law-determinism]' }
  $results = @()
  foreach ($provider in @($left.targets)) {
    $fixture = [pscustomobject][ordered]@{kind='MIR4TargetProjectionLawFixtureV1';owned=[pscustomobject][ordered]@{distribution_version='0.0.0';factorio_version='0.0';package_root='fixture';capability_omissions=@()};unowned=[pscustomobject][ordered]@{sentinel='preserve';nested=[ordered]@{value=17}}}
    $changes = [pscustomobject][ordered]@{distribution_version=[string]$provider.identity.distribution_version;factorio_version=[string]$provider.identity.factorio_line;package_root=('more-infinite-research_'+[string]$provider.identity.distribution_version);capability_omissions=@($provider.facilities | Where-Object { $_.disposition -in @('compiled-out','omitted-by-capability','unsupported-with-evidence') } | ForEach-Object id)}
    $once = Invoke-MIR4TargetProviderProjection -Provider $provider -InputRecord $fixture -OwnedChanges $changes
    $twice = Invoke-MIR4TargetProviderProjection -Provider $provider -InputRecord $once -OwnedChanges $changes
    if ((ConvertTo-MIR4PlatformCanonicalJson $once) -cne (ConvertTo-MIR4PlatformCanonicalJson $twice)) { throw "[mir4-target-law-idempotence] $($provider.target)" }
    if ((ConvertTo-MIR4PlatformCanonicalJson $fixture.unowned) -cne (ConvertTo-MIR4PlatformCanonicalJson $once.unowned)) { throw "[mir4-target-law-unowned-preservation] $($provider.target)" }
    if ([string]$once.owned.distribution_version -cne [string]$provider.identity.distribution_version -or [string]$once.owned.factorio_version -cne [string]$provider.identity.factorio_line) { throw "[mir4-target-law-round-trip] $($provider.target)" }
    $serialized = ConvertTo-MIR4PlatformCanonicalJson $provider
    foreach ($field in @($authority.provider_abi.forbidden_policy_fields)) { if ($null -ne $provider.provider_spec.PSObject.Properties[[string]$field]) { throw "[mir4-target-law-hidden-policy] $($provider.target):$field" } }
    if ([Text.Encoding]::UTF8.GetByteCount($serialized) -gt [int]$authority.provider_abi.maximum_provider_bytes -or @($provider.provider_spec.operations).Count -gt [int]$authority.provider_abi.maximum_operations) { throw "[mir4-target-law-budget] $($provider.target)" }
    if (@($provider.facilities | Where-Object { [string]$_.disposition -notin @($authority.facility_dispositions) }).Count -ne 0) { throw "[mir4-target-law-explicit-loss] $($provider.target)" }
    $results += [ordered]@{target=[string]$provider.target;status='passed';laws=@($authority.provider_abi.laws);provider_digest=[string]$provider.provider_spec.provider_digest}
  }
  $record = [pscustomobject][ordered]@{schema=1;kind='MIR4TargetProviderLawResultV1';programme_id=[string]$authority.programme_id;maturity='preview';targets=$results;passed=$true;authoritative_output=$false;mutation_capability=$false;digest=''}
  return Add-MIR4PlatformDigest $record
}
