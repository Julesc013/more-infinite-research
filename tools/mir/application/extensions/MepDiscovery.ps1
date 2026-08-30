. (Join-Path $PSScriptRoot 'ExtensionDeveloperExperience.ps1')

function Get-MIR4F210MepDiscoveryContractV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4ModuleEcosystemRepoRoot $RepoRoot
  $path = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-F210-MEP-Discovery-ContractV1.json'
  $contract = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([string]$contract.kind -cne 'MIR4F210MepDiscoveryContractV1' -or [int]$contract.schema -ne 1 -or
      [string]$contract.target -cne 'f210' -or [string]$contract.factorio_line -cne '2.1' -or
      [string]$contract.transport -cne 'extension-owned-mod-data-record' -or
      [string]$contract.data_type -cne 'more-infinite-research.extension.v1') {
    throw '[mir4-mep-discovery-contract]'
  }
  foreach ($flag in @('package_visible','player_mutation_authorized','prototype_write_authorized','public_support_authorized','release_authority')) {
    if ([bool]$contract.$flag) { throw "[mir4-mep-discovery-authority] $flag" }
  }
  return $contract
}

function Copy-MIR4F210MepDiscoveryValueV1 {
  param([AllowNull()]$Value)
  if ($null -eq $Value) { return $null }
  return (($Value | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json -Depth 100)
}

function Test-MIR4F210ModDataSnapshotV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Snapshot)
  $repo = Get-MIR4ModuleEcosystemRepoRoot $RepoRoot
  $contract = Get-MIR4F210MepDiscoveryContractV1 -RepoRoot $repo
  $schema = Join-Path $repo 'spec/schemas/preview/mir4-f210-mod-data-snapshot-v1.schema.json'
  try { $valid = (($Snapshot | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schema -ErrorAction Stop) }
  catch { throw '[mir4-mep-discovery-snapshot] Schema validation failed.' }
  if (-not $valid) { throw '[mir4-mep-discovery-snapshot] Schema validation failed.' }
  if ([bool]$Snapshot.host.present) {
    if ([string]::IsNullOrWhiteSpace([string]$Snapshot.host.id) -or [string]::IsNullOrWhiteSpace([string]$Snapshot.host.version)) {
      throw '[mir4-mep-discovery-snapshot] A present host requires an ID and version.'
    }
  } elseif ($null -ne $Snapshot.host.id -or $null -ne $Snapshot.host.version) {
    throw '[mir4-mep-discovery-snapshot] An absent host must not claim an identity.'
  }
  $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($record in @($Snapshot.records)) {
    if (-not $names.Add([string]$record.name)) { throw "[mir4-mep-discovery-duplicate-prototype] $([string]$record.name)" }
  }
  $matching = @($Snapshot.records | Where-Object { [string]$_.data_type -ceq [string]$contract.data_type })
  if ($matching.Count -gt [int]$contract.maximum_extension_records) {
    throw "[mir4-mep-discovery-cardinality] $($matching.Count)"
  }
  return $true
}

function New-MIR4F210MepDiscoveryDiagnosticV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$LegacyId,
    [string]$Path = '$',
    [Collections.IDictionary]$Context = [ordered]@{}
  )
  $code = switch ($LegacyId) {
    'mir4-mep-v1-schema' { 'MIR4-MEP-001' }
    'mir4-mep-v1-forbidden-field' { 'MIR4-MEP-002' }
    'mir4-mep-v1-duplicate-fragment' { 'MIR4-MEP-003' }
    'mir4-mep-v1-target' { 'MIR4-MEP-004' }
    'mir4-mep-v1-digest' { 'MIR4-MEP-005' }
    'mir4-mep-v1-duplicate-extension' { 'MIR4-MEP-006' }
    'mir4-mep-v1-namespace-conflict' { 'MIR4-MEP-007' }
    'mir4-mep-v1-target-not-declared' { 'MIR4-MEP-008' }
    'mir4-mep-v1-missing-dependency' { 'MIR4-MEP-009' }
    'mir4-mep-v1-conflict' { 'MIR4-MEP-010' }
    'mir4-mep-v1-dependency-cycle' { 'MIR4-MEP-011' }
    'mir4-mep-v1-target-order' { 'MIR4-MEP-012' }
    'mir4-mep-discovery-snapshot' { 'MIR4-MEP-013' }
    'mir4-mep-discovery-cardinality' { 'MIR4-MEP-014' }
    'mir4-mep-discovery-duplicate-prototype' { 'MIR4-MEP-015' }
    'mir4-mep-discovery-host-absent' { 'MIR4-MEP-016' }
    default { 'MIR4-MEP-013' }
  }
  return New-MIR4DiagnosticV1 -RepoRoot $RepoRoot -Code $code -Path $Path -Context $Context
}

function Get-MIR4F210MepLegacyDiagnosticIdV1 {
  param([Parameter(Mandatory)][string]$Message)
  if ($Message -match '^\[(?<id>[^\]]+)\]') { return [string]$Matches.id }
  return 'mir4-mep-discovery-snapshot'
}

function Test-MIR4F210MepDiscoveryResultV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Result)
  $repo = Get-MIR4ModuleEcosystemRepoRoot $RepoRoot
  $schema = Join-Path $repo 'spec/schemas/preview/mir4-f210-mep-discovery-result-v1.schema.json'
  if (-not (($Result | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schema)) { throw '[mir4-mep-discovery-result-schema]' }
  if ([string]$Result.digest -cne (Get-MIR4ModuleDigest $Result)) { throw '[mir4-mep-discovery-result-digest]' }
  if ([bool]$Result.package_visible -or [bool]$Result.player_mutation_authorized -or [bool]$Result.prototype_write_authorized -or
      [bool]$Result.public_support_authorized -or [bool]$Result.release_authority) {
    throw '[mir4-mep-discovery-result-authority]'
  }
  if ([string]$Result.result -ceq 'host-absent-inert' -and
      (@($Result.records).Count -ne 0 -or @($Result.shadow_plans).Count -ne 0 -or $null -ne $Result.closure)) {
    throw '[mir4-mep-discovery-host-absence-not-inert]'
  }
  return $true
}

function New-MIR4F210MepDiscoveryV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Snapshot)
  $repo = Get-MIR4ModuleEcosystemRepoRoot $RepoRoot
  $contract = Get-MIR4F210MepDiscoveryContractV1 -RepoRoot $repo
  $input = Copy-MIR4F210MepDiscoveryValueV1 $Snapshot
  Test-MIR4F210ModDataSnapshotV1 -RepoRoot $repo -Snapshot $input | Out-Null
  $snapshotRecords = @($input.records)
  $matching = @($snapshotRecords | Where-Object { [string]$_.data_type -ceq [string]$contract.data_type } | Sort-Object name -CaseSensitive)
  $diagnostics = @()

  if (-not [bool]$input.host.present) {
    $diagnostics += New-MIR4F210MepDiscoveryDiagnosticV1 -RepoRoot $repo -LegacyId 'mir4-mep-discovery-host-absent' -Path '$.host'
    $record = [pscustomobject][ordered]@{
      schema=1;kind='MIR4F210MepDiscoveryResultV1';maturity='developer-preview';target='f210';factorio_line='2.1'
      environment_lock_digest=[string]$input.environment_lock_digest
      host=[ordered]@{present=$false;id=$null;version=$null;status='absent-inert'}
      transport=[ordered]@{name=[string]$contract.transport;data_type=[string]$contract.data_type;mode='read-only-discovery';admission=[string]$contract.admission}
      counts=[ordered]@{snapshot_records=$snapshotRecords.Count;matching_records=$matching.Count;ignored_records=($snapshotRecords.Count-$matching.Count);validated_records=0;accepted_records=0;quarantined_records=0}
      records=@();closure=$null;shadow_plans=@();diagnostics=@(Sort-MIR4DiagnosticsV1 $diagnostics);result='host-absent-inert'
      canonicalization='mir-canonical-json/1';package_visible=$false;player_mutation_authorized=$false;prototype_write_authorized=$false
      public_support_authorized=$false;release_authority=$false;digest=''
    }
    $record.digest = Get-MIR4ModuleDigest $record
    Test-MIR4F210MepDiscoveryResultV1 -RepoRoot $repo -Result $record | Out-Null
    return $record
  }

  $validRows = @()
  $envelopes = @()
  for ($index = 0; $index -lt $matching.Count; $index++) {
    $transportRecord = $matching[$index]
    try {
      Test-MIR4MepV1Envelope -Envelope $transportRecord.data -RepoRoot $repo | Out-Null
      $envelope = Copy-MIR4F210MepDiscoveryValueV1 $transportRecord.data
      $envelopes += $envelope
      $validRows += [pscustomobject][ordered]@{
        prototype_name=[string]$transportRecord.name;extension_id=[string]$envelope.extension_id
        extension_version=[string]$envelope.extension_version;namespace=[string]$envelope.namespace
        extension_digest=[string]$envelope.digest;status='quarantined'
      }
    } catch {
      $legacy = Get-MIR4F210MepLegacyDiagnosticIdV1 -Message $_.Exception.Message
      $diagnostics += New-MIR4F210MepDiscoveryDiagnosticV1 -RepoRoot $repo -LegacyId $legacy -Path "$.records[$index].data" -Context ([ordered]@{prototype_name=[string]$transportRecord.name})
    }
  }

  $closure = $null
  $plans = @()
  if ($diagnostics.Count -eq 0) {
    try {
      $closure = Resolve-MIR4ExtensionClosureV1 -RepoRoot $repo -Extensions $envelopes -Target f210
      $byId = @{}; foreach ($envelope in $envelopes) { $byId[[string]$envelope.extension_id] = $envelope }
      foreach ($id in @($closure.order | Select-Object -Skip 1)) {
        $plans += New-MIR4ExtensionClosureShadowPlanV1 -RepoRoot $repo -Envelope $byId[[string]$id] -Closure $closure
      }
      foreach ($row in $validRows) { $row.status = 'accepted-shadow' }
    } catch {
      $legacy = Get-MIR4F210MepLegacyDiagnosticIdV1 -Message $_.Exception.Message
      $diagnostics += New-MIR4F210MepDiscoveryDiagnosticV1 -RepoRoot $repo -LegacyId $legacy -Path '$.records' -Context ([ordered]@{extension_count=$envelopes.Count})
      $closure = $null
      $plans = @()
    }
  }
  $quarantined = if ($diagnostics.Count -gt 0) { $matching.Count } else { 0 }
  $accepted = if ($diagnostics.Count -eq 0) { $validRows.Count } else { 0 }
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4F210MepDiscoveryResultV1';maturity='developer-preview';target='f210';factorio_line='2.1'
    environment_lock_digest=[string]$input.environment_lock_digest
    host=[ordered]@{present=$true;id=[string]$input.host.id;version=[string]$input.host.version;status='active-preview'}
    transport=[ordered]@{name=[string]$contract.transport;data_type=[string]$contract.data_type;mode='read-only-discovery';admission=[string]$contract.admission}
    counts=[ordered]@{snapshot_records=$snapshotRecords.Count;matching_records=$matching.Count;ignored_records=($snapshotRecords.Count-$matching.Count);validated_records=$validRows.Count;accepted_records=$accepted;quarantined_records=$quarantined}
    records=@($validRows);closure=$closure;shadow_plans=@($plans);diagnostics=@(Sort-MIR4DiagnosticsV1 $diagnostics)
    result=$(if($diagnostics.Count -eq 0){'shadow-complete'}else{'quarantined'})
    canonicalization='mir-canonical-json/1';package_visible=$false;player_mutation_authorized=$false;prototype_write_authorized=$false
    public_support_authorized=$false;release_authority=$false;digest=''
  }
  $record.digest = Get-MIR4ModuleDigest $record
  Test-MIR4F210MepDiscoveryResultV1 -RepoRoot $repo -Result $record | Out-Null
  return $record
}
