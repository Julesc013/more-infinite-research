. (Join-Path $PSScriptRoot 'CanonicalJsonV1.ps1')
. (Join-Path $PSScriptRoot 'DiagnosticsV1.ps1')

function Get-MIR4ModuleEcosystemRepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function ConvertTo-MIR4ModuleCanonicalValue {
  param($Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [string] -or $Value -is [bool] -or $Value -is [ValueType]) { return $Value }
  if ($Value -is [Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)) {
      $result[$key] = ConvertTo-MIR4ModuleCanonicalValue $Value[$key]
    }
    return $result
  }
  if ($Value -is [pscustomobject]) {
    $result = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name -CaseSensitive)) {
      $result[$property.Name] = ConvertTo-MIR4ModuleCanonicalValue $property.Value
    }
    return $result
  }
  if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    Write-Output -NoEnumerate @($Value | ForEach-Object { ConvertTo-MIR4ModuleCanonicalValue $_ })
    return
  }
  return $Value
}

function ConvertTo-MIR4ModuleCanonicalJson {
  param([Parameter(Mandatory)]$Value)
  return ConvertTo-MIR4CanonicalJsonV1 -Value $Value
}

function Get-MIR4ModuleDigest {
  param([Parameter(Mandatory)]$Value)
  return Get-MIR4CanonicalDigestV1 -Value $Value -Domain (Get-MIR4RecordDigestDomainV1 -Value $Value) -OmitTopLevelDigest
}

function Add-MIR4ModuleDigest {
  param([Parameter(Mandatory)]$Value)
  $Value.digest = Get-MIR4ModuleDigest $Value
  return $Value
}

function Get-MIR4ModuleFileSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-MIR4ModuleEcosystemAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4ModuleEcosystemRepoRoot $RepoRoot
  $path = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Module-Ecosystem-ProgrammeV1.json'
  $authority = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ([int]$authority.schema -ne 1 -or [string]$authority.kind -cne 'MIR4ModuleEcosystemProgrammeV1') { throw '[mir4-module-authority]' }
  foreach ($flag in @('semantic_authority','player_package_mutation_authorized','prototype_write_authorized','runtime_state_mutation_authorized','migration_execution_authorized','safety_kernel_override_authorized','public_support_authorized','signing_or_sealing_authorized','publication_authorized')) {
    if ([bool]$authority.$flag) { throw "[mir4-module-boundary] $flag" }
  }
  if (@($authority.fragment_kinds | Sort-Object -Unique).Count -ne 12) { throw '[mir4-module-fragment-count]' }
  if (@($authority.api_surfaces | Sort-Object -Unique).Count -ne 9) { throw '[mir4-module-api-surface-count]' }
  if (@($authority.transports.target | Sort-Object -Unique).Count -ne 17) { throw '[mir4-module-transport-count]' }
  if (@($authority.builder_commands | Sort-Object -Unique).Count -ne 11) { throw '[mir4-module-builder-command-count]' }
  foreach ($input in @($authority.inputs)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo ([string]$input)) -PathType Leaf)) { throw "[mir4-module-input] $input" }
  }
  $registry = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json') | ConvertFrom-Json
  $registryTargets = @($registry.identities.target | Sort-Object)
  $transportTargets = @($authority.transports.target | Sort-Object)
  if (($registryTargets -join '|') -cne ($transportTargets -join '|')) { throw '[mir4-module-transport-registry-drift]' }
  return $authority
}

function Get-MIR4MepV1Schema {
  param([Parameter(Mandatory)]$Authority)
  $fragmentData = [ordered]@{
    CompatibilityFragment = [ordered]@{type='object';additionalProperties=$false;required=@('subject_refs','disposition');properties=[ordered]@{subject_refs=@{type='array';minItems=1;maxItems=64;uniqueItems=$true;items=@{type='string';minLength=1;maxLength=256}};disposition=@{enum=@('handle-certified','preserve-opaque','request-review','omit-with-evidence')}}}
    ProfileFragment = [ordered]@{type='object';additionalProperties=$false;required=@('profile_id','setting_refs');properties=[ordered]@{profile_id=@{type='string';pattern='^[a-z][a-z0-9.-]{0,127}$'};setting_refs=@{type='array';maxItems=64;uniqueItems=$true;items=@{type='string';minLength=1;maxLength=256}}}}
    ProofFragment = [ordered]@{type='object';additionalProperties=$false;required=@('evidence_refs','claim_level');properties=[ordered]@{evidence_refs=@{type='array';minItems=1;maxItems=64;uniqueItems=$true;items=@{type='string';minLength=1;maxLength=256}};claim_level=@{enum=@('fixture-backed','load-checked','runtime-qualified','unavailable')}}}
    PresentationFragment = [ordered]@{type='object';additionalProperties=$false;required=@('title','summary');properties=[ordered]@{title=@{type='string';minLength=1;maxLength=128};summary=@{type='string';minLength=1;maxLength=1024}}}
    CapabilityRequirement = [ordered]@{type='object';additionalProperties=$false;required=@('all_of');properties=[ordered]@{all_of=@{type='array';minItems=1;maxItems=64;uniqueItems=$true;items=@{type='string';pattern='^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$'}}}}
    ExtensionDependency = [ordered]@{type='object';additionalProperties=$false;required=@('extension_id','constraint');properties=[ordered]@{extension_id=@{type='string';pattern='^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$'};constraint=@{type='string';minLength=1;maxLength=64}}}
    ExtensionConflict = [ordered]@{type='object';additionalProperties=$false;required=@('extension_ids');properties=[ordered]@{extension_ids=@{type='array';maxItems=64;uniqueItems=$true;items=@{type='string';pattern='^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$'}}}}
    FinalizationRequirement = [ordered]@{type='object';additionalProperties=$false;required=@('phase','writes_allowed');properties=[ordered]@{phase=@{enum=@('after-normalization','after-policy','before-bounded-projection')};writes_allowed=@{const=$false}}}
    ProcessClassificationFragment = [ordered]@{type='object';additionalProperties=$false;required=@('certificate_ref','status','reason');properties=[ordered]@{certificate_ref=@{type=@('string','null');maxLength=256};status=@{enum=@('available','unavailable')};reason=@{type='string';minLength=1;maxLength=512}}}
    MigrationFragment = [ordered]@{type='object';additionalProperties=$false;required=@('edge_ref','graph_digest');properties=[ordered]@{edge_ref=@{type='string';pattern='^migration\.[a-z0-9.-]+$'};graph_digest=@{type='string';pattern='^sha256:[0-9a-f]{64}$'}}}
    TargetDispositionFragment = [ordered]@{type='object';additionalProperties=$false;required=@('target','disposition','provider_ref');properties=[ordered]@{target=@{type='string';pattern='^f[0-9]{3}$'};disposition=@{type='string';minLength=1;maxLength=128};provider_ref=@{type='string';minLength=1;maxLength=256}}}
    ExternalEffectChannelDeclaration = [ordered]@{type='object';additionalProperties=$false;required=@('channel_ref','status','evidence_refs');properties=[ordered]@{channel_ref=@{type=@('string','null');maxLength=256};status=@{enum=@('available','unavailable')};evidence_refs=@{type='array';maxItems=32;uniqueItems=$true;items=@{type='string';minLength=1;maxLength=256}}}}
  }
  $variants = @(
    foreach ($kind in @($Authority.fragment_kinds)) {
      [ordered]@{type='object';additionalProperties=$false;required=@('id','kind','data');properties=[ordered]@{id=@{type='string';pattern='^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$'};kind=@{const=[string]$kind};data=$fragmentData[[string]$kind]}}
    }
  )
  return [ordered]@{
    '$schema'='https://json-schema.org/draft/2020-12/schema';'$id'='https://julesc013.github.io/more-infinite-research/schemas/mir4/v1/extension-envelope.schema.json';title='MIR Extension Protocol V1 Preview';type='object';additionalProperties=$false
    required=@('kind','schema','extension_id','extension_version','namespace','targets','fragments','canonicalization','digest')
    properties=[ordered]@{
      kind=@{const='MIR4ExtensionEnvelopeV1'};schema=@{const=1}
      extension_id=@{type='string';pattern='^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$'}
      extension_version=@{type='string';pattern='^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-z0-9.-]+)?$'}
      namespace=@{type='string';pattern='^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$'}
      targets=@{type='array';minItems=1;maxItems=17;uniqueItems=$true;items=@{type='string';pattern='^f[0-9]{3}$'}}
      fragments=@{type='array';minItems=1;maxItems=64;items=@{oneOf=$variants}}
      canonicalization=@{const='mir-canonical-json/1'};digest=@{type='string';pattern='^sha256:[0-9a-f]{64}$'}
    }
  }
}

function Get-MIR4ApiV1Schema {
  param([Parameter(Mandatory)]$Authority)
  return [ordered]@{
    '$schema'='https://json-schema.org/draft/2020-12/schema';'$id'='https://julesc013.github.io/more-infinite-research/schemas/mir4/v1/api-response.schema.json';title='MIR 4 API Response V1 Preview';type='object';additionalProperties=$false
    required=@('kind','schema','surface','target','versions','capabilities','availability','page','items','canonicalization','extensions','source_identity','package_visible','mutation_authorized','public_support_claim','digest')
    properties=[ordered]@{
      kind=@{const='MIR4ApiResponseV1'};schema=@{const=1};surface=@{enum=@($Authority.api_surfaces)}
      target=@{type='object';additionalProperties=$false;required=@('id','factorio_line','transport');properties=[ordered]@{id=@{type='string';pattern='^f[0-9]{3}$'};factorio_line=@{type='string';pattern='^[0-9]+\.[0-9]+$'};transport=@{type='string';minLength=1;maxLength=128}}}
      versions=@{type='object';additionalProperties=$false;required=@('source','distribution');properties=[ordered]@{source=@{type='string';minLength=1;maxLength=64};distribution=@{type='string';minLength=1;maxLength=64}}}
      capabilities=@{type='array';maxItems=[int]$Authority.response_bounds.max_capabilities;uniqueItems=$true;items=@{type='string';pattern='^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$'}}
      availability=@{type='object';additionalProperties=$false;required=@('status','reason','evidence');properties=[ordered]@{status=@{enum=@('available','unavailable')};reason=@{type='string';minLength=1;maxLength=512};evidence=@{type='array';maxItems=64;uniqueItems=$true;items=@{type='string';minLength=1;maxLength=256}}}}
      page=@{type='object';additionalProperties=$false;required=@('offset','limit','returned','total','next_cursor');properties=[ordered]@{offset=@{type='integer';minimum=0};limit=@{type='integer';minimum=1;maximum=[int]$Authority.response_bounds.max_page_items};returned=@{type='integer';minimum=0;maximum=[int]$Authority.response_bounds.max_page_items};total=@{type=@('integer','null');minimum=0};next_cursor=@{type=@('string','null');maxLength=[int]$Authority.response_bounds.max_cursor_bytes}}}
      items=@{type='array';maxItems=[int]$Authority.response_bounds.max_page_items;items=@{type=@('object','string','integer','boolean','array','null');minimum=-9007199254740991;maximum=9007199254740991}}
      canonicalization=@{const='mir-canonical-json/1'}
      extensions=@{type='object';maxProperties=[int]$Authority.response_bounds.max_extensions;propertyNames=@{pattern='^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$'};additionalProperties=$true}
      source_identity=@{type=@('object','null')};package_visible=@{const=$false};mutation_authorized=@{const=$false};public_support_claim=@{const=$false};digest=@{type='string';pattern='^sha256:[0-9a-f]{64}$'}
    }
  }
}

function Test-MIR4MepV1ForbiddenValue {
  param([AllowNull()]$Value,[Parameter(Mandatory)][string[]]$Forbidden,[string]$Path='$')
  if ($null -eq $Value) { return }
  if ($Value -is [pscustomobject]) {
    foreach ($property in $Value.PSObject.Properties) {
      if ([string]$property.Name -in $Forbidden) { throw "[mir4-mep-v1-forbidden-field] $Path.$($property.Name)" }
      Test-MIR4MepV1ForbiddenValue -Value $property.Value -Forbidden $Forbidden -Path "$Path.$($property.Name)"
    }
  } elseif ($Value -is [Collections.IDictionary]) {
    foreach ($key in $Value.Keys) {
      if ([string]$key -in $Forbidden) { throw "[mir4-mep-v1-forbidden-field] $Path.$key" }
      Test-MIR4MepV1ForbiddenValue -Value $Value[$key] -Forbidden $Forbidden -Path "$Path.$key"
    }
  } elseif ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    $index = 0
    foreach ($item in $Value) {
      Test-MIR4MepV1ForbiddenValue -Value $item -Forbidden $Forbidden -Path "$Path[$index]"
      $index++
    }
  }
}

function Test-MIR4MepV1Envelope {
  param([Parameter(Mandatory)]$Envelope,[Parameter(Mandatory)][string]$RepoRoot)
  $authority = Get-MIR4ModuleEcosystemAuthority -RepoRoot $RepoRoot
  Test-MIR4MepV1ForbiddenValue -Value $Envelope -Forbidden @($authority.forbidden_fields)
  $schema = Get-MIR4MepV1Schema -Authority $authority | ConvertTo-Json -Depth 100 -Compress
  try { $valid = (($Envelope | ConvertTo-Json -Depth 100) | Test-Json -Schema $schema -ErrorAction Stop) }
  catch { throw '[mir4-mep-v1-schema] Envelope schema validation failed.' }
  if (-not $valid) { throw '[mir4-mep-v1-schema] Envelope schema validation failed.' }
  $fragmentIds = @($Envelope.fragments | ForEach-Object { [string]$_.id })
  if (@($fragmentIds | Sort-Object -Unique).Count -ne $fragmentIds.Count) { throw '[mir4-mep-v1-duplicate-fragment]' }
  Test-MIR4OrdinalSortedUniqueV1 -Values @($Envelope.targets | ForEach-Object { [string]$_ }) -Diagnostic 'mir4-mep-v1-target-order' | Out-Null
  $registry = Get-Content -Raw -LiteralPath (Join-Path (Get-MIR4ModuleEcosystemRepoRoot $RepoRoot) '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json') | ConvertFrom-Json
  foreach ($target in @($Envelope.targets)) {
    if ([string]$target -notin @($registry.identities.target)) { throw "[mir4-mep-v1-target] $target" }
  }
  if ([string]$Envelope.digest -cne (Get-MIR4ModuleDigest $Envelope)) { throw '[mir4-mep-v1-digest]' }
  return $true
}

function ConvertFrom-MIR4MepV0ToV1 {
  param([Parameter(Mandatory)]$Envelope)
  if ([string]$Envelope.kind -cne 'MIR4ExtensionEnvelopeV0' -or [int]$Envelope.schema -ne 0) { throw '[mir4-mep-migrate-source]' }
  $fragments = @(
    foreach ($fragment in @($Envelope.fragments)) {
      $data = switch ([string]$fragment.kind) {
        'CompatibilityFragment' { [ordered]@{subject_refs=@($fragment.data.subjects);disposition=[string]$fragment.data.disposition} }
        'ProfileFragment' { [ordered]@{profile_id=[string]$fragment.data.profile;setting_refs=@($fragment.data.settings.PSObject.Properties | ForEach-Object Name | Sort-Object)} }
        'ProofFragment' { [ordered]@{evidence_refs=@($fragment.data.fixtures | ForEach-Object { "fixture:$_" });claim_level=[string]$fragment.data.claim_level} }
        'PresentationFragment' { [ordered]@{title=[string]$fragment.data.title;summary=[string]$fragment.data.summary} }
        'CapabilityRequirement' { [ordered]@{all_of=@($fragment.data.all_of | ForEach-Object { [string]$_ })} }
        'ExtensionDependency' { [ordered]@{extension_id=[string]$fragment.data.extension_id;constraint=[string]$fragment.data.constraint} }
        'ExtensionConflict' { [ordered]@{extension_ids=@($fragment.data.extension_ids | ForEach-Object { [string]$_ })} }
        'FinalizationRequirement' { [ordered]@{phase=[string]$fragment.data.phase;writes_allowed=[bool]$fragment.data.writes_allowed} }
        default { throw "[mir4-mep-migrate-fragment] $([string]$fragment.kind)" }
      }
      [ordered]@{id=[string]$fragment.id;kind=[string]$fragment.kind;data=$data}
    }
  )
  $record = [pscustomobject][ordered]@{
    kind='MIR4ExtensionEnvelopeV1';schema=1;extension_id=[string]$Envelope.extension_id;extension_version='0.0.0-migrated';namespace=[string]$Envelope.extension_id
    targets=@(Get-MIR4OrdinalSortedUniqueV1 -Values @($Envelope.targets | ForEach-Object { [string]$_ }));fragments=$fragments;canonicalization='mir-canonical-json/1';digest=''
  }
  return Add-MIR4ModuleDigest $record
}

function New-MIR4ReferenceExtensionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4ModuleEcosystemRepoRoot $RepoRoot
  $runtimeAuthorityPath = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json'
  $graphAuthorityDigest = 'sha256:' + (Get-MIR4ModuleFileSha256 $runtimeAuthorityPath)
  $record = [pscustomobject][ordered]@{
    kind='MIR4ExtensionEnvelopeV1';schema=1;extension_id='org.more-infinite-research.reference';extension_version='1.0.0-preview';namespace='org.more-infinite-research.reference'
    targets=@('f100','f110','f200','f210')
    fragments=@(
      [ordered]@{id='org.more-infinite-research.reference.compatibility';kind='CompatibilityFragment';data=[ordered]@{subject_refs=@('reference-intermediate');disposition='preserve-opaque'}},
      [ordered]@{id='org.more-infinite-research.reference.profile';kind='ProfileFragment';data=[ordered]@{profile_id='reference-safe';setting_refs=@('mir.default-profile')}},
      [ordered]@{id='org.more-infinite-research.reference.proof';kind='ProofFragment';data=[ordered]@{evidence_refs=@('fixture:mir4-mep-v1-positive');claim_level='fixture-backed'}},
      [ordered]@{id='org.more-infinite-research.reference.presentation';kind='PresentationFragment';data=[ordered]@{title='MIR 4 V1 reference extension';summary='Synthetic external data-only consumer for preview conformance.'}},
      [ordered]@{id='org.more-infinite-research.reference.capability';kind='CapabilityRequirement';data=[ordered]@{all_of=@('continuity.read','query.read','support.snapshot')}},
      [ordered]@{id='org.more-infinite-research.reference.dependency';kind='ExtensionDependency';data=[ordered]@{extension_id='org.more-infinite-research.platform';constraint='0.5.0-preview'}},
      [ordered]@{id='org.more-infinite-research.reference.conflict';kind='ExtensionConflict';data=[ordered]@{extension_ids=@()}},
      [ordered]@{id='org.more-infinite-research.reference.finalization';kind='FinalizationRequirement';data=[ordered]@{phase='after-normalization';writes_allowed=$false}},
      [ordered]@{id='org.more-infinite-research.reference.process';kind='ProcessClassificationFragment';data=[ordered]@{certificate_ref=$null;status='unavailable';reason='W06 ProcessIR certificate authority is not yet part of W05.'}},
      [ordered]@{id='org.more-infinite-research.reference.migration';kind='MigrationFragment';data=[ordered]@{edge_ref='migration.extension-install-remove';graph_digest=$graphAuthorityDigest}},
      [ordered]@{id='org.more-infinite-research.reference.target';kind='TargetDispositionFragment';data=[ordered]@{target='f210';disposition='blocked-by-terminal-emitter';provider_ref='sdk/preview/mir4/reference/target-providers.json#f210'}},
      [ordered]@{id='org.more-infinite-research.reference.effect';kind='ExternalEffectChannelDeclaration';data=[ordered]@{channel_ref=$null;status='unavailable';evidence_refs=@('authority:W06-external-effect-channel')}}
    )
    canonicalization='mir-canonical-json/1';digest=''
  }
  return Add-MIR4ModuleDigest $record
}

function Resolve-MIR4ExtensionClosureV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][object[]]$Extensions,[string]$Target='f210')
  $authority = Get-MIR4ModuleEcosystemAuthority -RepoRoot $RepoRoot
  $byId = @{}
  $namespaceOwner = @{}
  foreach ($extension in @($Extensions)) {
    Test-MIR4MepV1Envelope -Envelope $extension -RepoRoot $RepoRoot | Out-Null
    $id = [string]$extension.extension_id
    if ($byId.ContainsKey($id)) { throw "[mir4-mep-v1-duplicate-extension] $id" }
    if ($namespaceOwner.ContainsKey([string]$extension.namespace)) { throw "[mir4-mep-v1-namespace-conflict] $($extension.namespace)" }
    if ($Target -notin @($extension.targets)) { throw "[mir4-mep-v1-target-not-declared] ${id}:$Target" }
    $byId[$id] = $extension
    $namespaceOwner[[string]$extension.namespace] = $id
  }
  $hostId = [string]$authority.host_extensions[0].id
  $edges = @{}
  foreach ($id in @($byId.Keys | Sort-Object)) {
    $dependencies = @($byId[$id].fragments | Where-Object kind -eq 'ExtensionDependency' | ForEach-Object { [string]$_.data.extension_id } | Sort-Object -Unique)
    foreach ($dependency in $dependencies) {
      if ($dependency -ne $hostId -and -not $byId.ContainsKey($dependency)) { throw "[mir4-mep-v1-missing-dependency] $id->$dependency" }
    }
    $edges[$id] = @($dependencies | Where-Object { $_ -ne $hostId })
    foreach ($conflict in @($byId[$id].fragments | Where-Object kind -eq 'ExtensionConflict' | ForEach-Object { @($_.data.extension_ids) })) {
      if ($byId.ContainsKey([string]$conflict)) { throw "[mir4-mep-v1-conflict] $id<->$conflict" }
    }
  }
  $remaining = @{}; foreach ($id in $edges.Keys) { $remaining[$id] = @($edges[$id]) }
  $order = @()
  while ($remaining.Count -gt 0) {
    $ready = @($remaining.Keys | Where-Object { @($remaining[$_]).Count -eq 0 } | Sort-Object)
    if ($ready.Count -eq 0) { throw '[mir4-mep-v1-dependency-cycle]' }
    foreach ($id in $ready) {
      $order += $id
      $remaining.Remove($id)
      foreach ($other in @($remaining.Keys)) { $remaining[$other] = @($remaining[$other] | Where-Object { $_ -ne $id }) }
    }
  }
  $hostCapabilities = @($authority.host_extensions[0].capabilities | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  $rows = @(
    foreach ($id in $order) {
      $extension = $byId[$id]
      $required = @($extension.fragments | Where-Object kind -eq 'CapabilityRequirement' | ForEach-Object { @($_.data.all_of) } | Sort-Object -Unique)
      $missing = @($required | Where-Object { $_ -notin $hostCapabilities })
      [ordered]@{extension_id=$id;version=[string]$extension.extension_version;namespace=[string]$extension.namespace;digest=[string]$extension.digest;dependencies=@($edges[$id]);required_capabilities=$required;missing_capabilities=$missing;status=$(if($missing.Count){'review-required'}else{'admitted-preview'})}
    }
  )
  $record = [pscustomobject][ordered]@{
    kind='MIR4ExtensionClosureV1';schema=1;maturity='preview';target=$Target;host=[ordered]@{id=$hostId;version=[string]$authority.host_extensions[0].version;capabilities=$hostCapabilities}
    order=@($hostId)+@($order);extensions=$rows;complete=(@($rows | Where-Object status -ne 'admitted-preview').Count -eq 0);authoritative_output=$false;mutation_authorized=$false;public_support_claim=$false;digest=''
  }
  return Add-MIR4ModuleDigest $record
}

function New-MIR4TargetTransportPlanV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $authority = Get-MIR4ModuleEcosystemAuthority -RepoRoot $RepoRoot
  $record = [pscustomobject][ordered]@{
    kind='MIR4ExtensionTransportPlanV1';schema=1;maturity='preview';targets=@($authority.transports | Sort-Object target)
    invariants=@('extension-owned-records-only','terminal-emitter-retains-f210-admission','f200-bus-is-build-materializer-local','historical-transports-are-static-or-unavailable','no-prototype-write')
    prototype_write_authorized=$false;package_visible=$false;public_support_claim=$false;digest=''
  }
  return Add-MIR4ModuleDigest $record
}

function Copy-MIR4ModuleData {
  param([AllowNull()]$Value)
  if ($null -eq $Value) { return $null }
  return (($Value | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json)
}

function New-MIR4ApiV1Response {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Surface,[Parameter(Mandatory)][ValidatePattern('^f[0-9]{3}$')][string]$Target,
    [object[]]$Items=@(),[ValidateSet('available','unavailable')][string]$Availability='available',[string]$Reason='Preview data is available.',[string[]]$Evidence=@(),
    [int]$Limit=128,[AllowNull()][string]$Cursor=$null,[hashtable]$Extensions=@{},[AllowNull()]$SourceIdentity=$null
  )
  $repo = Get-MIR4ModuleEcosystemRepoRoot $RepoRoot
  $authority = Get-MIR4ModuleEcosystemAuthority -RepoRoot $repo
  $contracts = Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/api/mir4-v1/contracts.json') | ConvertFrom-Json
  $contract = @($contracts.surfaces | Where-Object id -eq $Surface)
  if ($contract.Count -ne 1) { throw "[mir4-api-v1-surface] $Surface" }
  $transport = @($authority.transports | Where-Object target -eq $Target)
  if ($transport.Count -ne 1) { throw "[mir4-api-v1-target] $Target" }
  $registry = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json') | ConvertFrom-Json
  $identity = @($registry.identities | Where-Object target -eq $Target)
  if ($identity.Count -ne 1) { throw "[mir4-api-v1-target-identity] $Target" }
  $max = [int]$authority.response_bounds.max_page_items
  if ($Limit -lt 1 -or $Limit -gt $max) { throw "[mir4-api-v1-limit] $Limit" }
  $offset = 0
  if ($Cursor -and (-not [int]::TryParse($Cursor,[ref]$offset) -or $offset -lt 0)) { throw '[mir4-api-v1-cursor]' }
  $all = @(Copy-MIR4ModuleData @($Items))
  $pageItems = if ($Availability -eq 'available' -and $offset -lt $all.Count) { @($all | Select-Object -Skip $offset -First $Limit) } else { @() }
  $pageItems = @($pageItems)
  $next = if ($Availability -eq 'available' -and ($offset + $pageItems.Count) -lt $all.Count) { [string]($offset + $pageItems.Count) } else { $null }
  $extensionCopy = Copy-MIR4ModuleData $Extensions
  $record = [pscustomobject][ordered]@{
    kind='MIR4ApiResponseV1';schema=1;surface=$Surface
    target=[ordered]@{id=$Target;factorio_line=[string]$identity[0].factorio_line;transport=[string]$transport[0].transport}
    versions=[ordered]@{source='4.0.0';distribution=[string]$identity[0].distribution_version}
    capabilities=@([string]$contract[0].capability)
    availability=[ordered]@{status=$Availability;reason=$Reason;evidence=@($Evidence | Sort-Object -Unique)}
    page=[ordered]@{offset=$offset;limit=$Limit;returned=$pageItems.Count;total=$(if($Availability -eq 'available'){$all.Count}else{$null});next_cursor=$next}
    items=$pageItems;canonicalization='mir-canonical-json/1';extensions=$extensionCopy;source_identity=$SourceIdentity
    package_visible=$false;mutation_authorized=$false;public_support_claim=$false;digest=''
  }
  Test-MIR4ExplicitAvailabilityV1 -Availability $record.availability -Page $record.page | Out-Null
  Add-MIR4ModuleDigest $record | Out-Null
  $schema = Get-MIR4ApiV1Schema -Authority $authority | ConvertTo-Json -Depth 100 -Compress
  if (-not (($record | ConvertTo-Json -Depth 100) | Test-Json -Schema $schema)) { throw '[mir4-api-v1-schema]' }
  return $record
}

function New-MIR4W05Records {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$SourceIdentity,[AllowNull()][string]$CandidateZip)
  $repo = Get-MIR4ModuleEcosystemRepoRoot $RepoRoot
  $authority = Get-MIR4ModuleEcosystemAuthority -RepoRoot $repo
  $reference = New-MIR4ReferenceExtensionV1 -RepoRoot $repo
  $closure = Resolve-MIR4ExtensionClosureV1 -RepoRoot $repo -Extensions @($reference) -Target f210
  $transport = New-MIR4TargetTransportPlanV1 -RepoRoot $repo
  $candidate = $null
  if (-not [string]::IsNullOrWhiteSpace($CandidateZip)) {
    $candidatePath = if ([IO.Path]::IsPathRooted($CandidateZip)){$CandidateZip}else{Join-Path $repo $CandidateZip}
    $candidatePath = (Resolve-Path -LiteralPath $candidatePath).Path
    $candidate = [ordered]@{path=[IO.Path]::GetRelativePath($repo,$candidatePath).Replace('\','/');bytes=(Get-Item -LiteralPath $candidatePath).Length;sha256=(Get-MIR4ModuleFileSha256 $candidatePath);status='present-private-unqualified'}
  }
  $apiSamples = @(
    foreach ($surface in @($authority.api_surfaces)) {
      New-MIR4ApiV1Response -RepoRoot $repo -Surface $surface -Target f210 -Items @([ordered]@{reference_extension_digest=[string]$reference.digest;closure_digest=[string]$closure.digest}) -Evidence @('fixture:mir4-mep-v1-positive') -SourceIdentity $SourceIdentity
    }
  )
  $mep = [pscustomobject][ordered]@{
    schema=1;kind='MIR4MepConformanceV1';programme_id=[string]$authority.programme_id;source_identity=$SourceIdentity;candidate=$candidate;maturity='developer-preview'
    fragment_kinds=@($authority.fragment_kinds);fragment_count=@($authority.fragment_kinds).Count;reference_extension=[ordered]@{id=[string]$reference.extension_id;digest=[string]$reference.digest;fragment_count=@($reference.fragments).Count}
    closure=[ordered]@{digest=[string]$closure.digest;complete=[bool]$closure.complete;order=@($closure.order)};transport_plan=[ordered]@{digest=[string]$transport.digest;target_count=@($transport.targets).Count}
    forbidden_boundary=[ordered]@{recursive=$true;direct_prototype_writes=$false;mutable_compiler_context=$false;safety_kernel_override=$false};passed=$true;package_visible=$false;public_support_claim=$false;digest=''
  }; Add-MIR4ModuleDigest $mep | Out-Null
  $sdk = [pscustomobject][ordered]@{
    schema=1;kind='MIR4ApiSdkGraduationMatrixV1';programme_id=[string]$authority.programme_id;source_identity=$SourceIdentity;maturity='developer-preview';graduated=$false
    api_surfaces=@($apiSamples | ForEach-Object { [ordered]@{id=[string]$_.surface;digest=[string]$_.digest;bounded=$true;copied=$true;data_only=$true;paginated=$true;capability_aware=$true;explicit_unavailable=$true} })
    bindings=@('json-schema','lua','luals','typescript','python','powershell','markdown');canonical_vectors=$true;migration_helpers=$true;builder_commands=@($authority.builder_commands)
    blockers=@('BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER');public_support_claim=$false;package_visible=$false;digest=''
  }; Add-MIR4ModuleDigest $sdk | Out-Null
  $consumer = [pscustomobject][ordered]@{
    schema=1;kind='MIR4ReferenceConsumerResultV1';programme_id=[string]$authority.programme_id;source_identity=$SourceIdentity;preferred_consumer='industrial-revolution-4'
    production_consumer_status=[string]$authority.independent_consumer.status;reason=[string]$authority.independent_consumer.reason
    fallback=[ordered]@{kind='synthetic-external-reference-extension';external_to_player_package=$true;extension_id=[string]$reference.extension_id;extension_digest=[string]$reference.digest;closure_digest=[string]$closure.digest;result='passed'}
    maturity='developer-preview';graduated=$false;public_support_claim=$false;package_visible=$false;digest=''
  }; Add-MIR4ModuleDigest $consumer | Out-Null
  return [ordered]@{mep=$mep;sdk=$sdk;consumer=$consumer;reference=$reference;closure=$closure;transport=$transport;api_samples=$apiSamples}
}
