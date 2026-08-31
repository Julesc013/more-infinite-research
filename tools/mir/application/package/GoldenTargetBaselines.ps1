Set-StrictMode -Version Latest

function Get-MIR4GoldenRepoRoot {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4GoldenTargetDefinitions {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4GoldenRepoRoot -RepoRoot $RepoRoot
  $registry = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json') | ConvertFrom-Json -Depth 100 -DateKind String
  $distributions = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/distributions.json') | ConvertFrom-Json -Depth 100 -DateKind String
  $plan = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV3.json') | ConvertFrom-Json -Depth 100 -DateKind String
  $profiles = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/targets.json') | ConvertFrom-Json -Depth 100 -DateKind String
  $result = [Collections.Generic.List[object]]::new()
  foreach ($target in @('f210', 'f200', 'f110', 'f100')) {
    $identity = @($registry.identities | Where-Object { [string]$_.target -ceq $target })
    $support = @($registry.support_policy | Where-Object { [string]$_.target -ceq $target })
    $planTarget = @($plan.targets | Where-Object { [string]$_.target_key -ceq $target })
    if ($identity.Count -ne 1 -or $support.Count -ne 1 -or $planTarget.Count -ne 1) { throw "[mir4-golden-target-definition] $target" }
    $distribution = @($distributions.distributions | Where-Object { [string]$_.version -ceq [string]$identity[0].distribution_version })
    if ($distribution.Count -ne 1) { throw "[mir4-golden-target-distribution] $target" }
    $result.Add([pscustomobject][ordered]@{
      target=$target
      target_id=[string]$identity[0].target_id
      factorio_line=[string]$identity[0].factorio_line
      distribution_target_code=[string]$identity[0].distribution_target_code
      distribution_version=[string]$identity[0].distribution_version
      support_tier=[string]$support[0].support_tier
      release_blocking=[bool]$support[0].release_blocking
      predecessor=[string]$identity[0].mir3_predecessor
      runtime_state_backend=[string]$profiles.profiles.([string]$identity[0].factorio_line).runtime_state_backend
      engine=$planTarget[0].engine_lock
      distribution=$distribution[0]
    })
  }
  return @($result)
}

function Get-MIR4GoldenArchiveIdentitySurface {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ArchivePath,[Parameter(Mandatory)]$Inventory,[Parameter(Mandatory)][string]$RuntimeStateBackend)
  $paths = @($Inventory.entries.path)
  $streamIds = @()
  $technologyIds = @()
  if ($paths -ccontains 'prototypes/mir/streams/generated_stream_manifest.json') {
    $streamManifest = Read-MIR4ArchiveText -Path $ArchivePath -RelativePath 'prototypes/mir/streams/generated_stream_manifest.json' | ConvertFrom-Json -Depth 100 -DateKind String
    $streamIds = @($streamManifest.streams.PSObject.Properties.Name | Sort-Object -Unique)
    $technologyIds = @($streamManifest.streams.PSObject.Properties.Value.generated_technology | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  }
  $settingIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $stateNamespaces = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $sourcePaths = @($paths | Where-Object {
    $_ -ceq 'settings.lua' -or $_ -ceq 'control.lua' -or $_ -like 'migrations/*.lua' -or
    $_ -like 'prototypes/mir/settings/*.lua' -or $_ -like 'prototypes/mir/stage/settings*.lua' -or
    $_ -like 'prototypes/mir/runtime/*.lua'
  })
  foreach ($relative in $sourcePaths) {
    $text = Read-MIR4ArchiveText -Path $ArchivePath -RelativePath $relative
    foreach ($match in [regex]::Matches($text, '(?m)\bname\s*=\s*["''](?<id>mir-[^"'']+)["'']')) {
      $null = $settingIds.Add([string]$match.Groups['id'].Value)
    }
    foreach ($match in [regex]::Matches($text, '\b(?<root>storage|global)\s*(?:\.\s*(?<dot>[A-Za-z_][A-Za-z0-9_]*)|\[\s*["''](?<index>[^"'']+)["'']\s*\])')) {
      $key = if ($match.Groups['dot'].Success) { $match.Groups['dot'].Value } else { $match.Groups['index'].Value }
      if ($key) { $null = $stateNamespaces.Add("$($match.Groups['root'].Value).$key") }
    }
  }
  if ($paths -ccontains 'prototypes/mir/runtime/state.lua') {
    $stateText = Read-MIR4ArchiveText -Path $ArchivePath -RelativePath 'prototypes/mir/runtime/state.lua'
    if ($stateText -cmatch '\bstate_root\.mir\b') { $null = $stateNamespaces.Add("$RuntimeStateBackend.mir") }
  }
  return [pscustomobject][ordered]@{
    lifecycle_entrypoints=@($paths | Where-Object { $_ -in @('settings.lua','data.lua','data-updates.lua','data-final-fixes.lua','control.lua') } | Sort-Object)
    setting_paths=@($paths | Where-Object { $_ -ceq 'settings.lua' -or $_ -like 'prototypes/mir/settings/*.lua' -or $_ -like 'prototypes/mir/stage/settings*.lua' } | Sort-Object)
    locale_paths=@($paths | Where-Object { $_ -like 'locale/*' } | Sort-Object)
    asset_paths=@($paths | Where-Object { $_ -match '(?i)\.(png|jpg|jpeg|webp|ogg|wav)$' } | Sort-Object)
    migration_paths=@($paths | Where-Object { $_ -like 'migrations/*' } | Sort-Object)
    runtime_paths=@($paths | Where-Object { $_ -ceq 'control.lua' -or $_ -like 'prototypes/mir/runtime/*' -or $_ -like 'prototypes/mir/stage/control*' } | Sort-Object)
    stable_stream_ids=$streamIds
    stable_technology_ids=$technologyIds
    setting_ids=@($settingIds | Sort-Object)
    state_namespaces=@($stateNamespaces | Sort-Object)
  }
}

function Get-MIR4GoldenLayerEntry {
  param([Parameter(Mandatory)]$Entry)
  return [pscustomobject][ordered]@{path=[string]$Entry.path;bytes=[int64]$Entry.raw_bytes;sha256=[string]$Entry.raw_sha256}
}

function New-MIR4GoldenClassification {
  [CmdletBinding()]
  param([Parameter(Mandatory)][Collections.IDictionary]$Inventories)
  $keys = @('f210','f200','f110','f100')
  $maps = [ordered]@{}
  foreach ($key in $keys) {
    $map = @{}
    foreach ($entry in @($Inventories[$key].entries)) { $map[[string]$entry.path] = $entry }
    $maps[$key] = $map
  }
  $allPaths = @($maps.Values | ForEach-Object { $_.Keys } | Sort-Object -Unique)
  $common = [Collections.Generic.List[object]]::new()
  $modern = [Collections.Generic.List[object]]::new()
  $legacy = [Collections.Generic.List[object]]::new()
  $targets = [ordered]@{f210=[Collections.Generic.List[object]]::new();f200=[Collections.Generic.List[object]]::new();f110=[Collections.Generic.List[object]]::new();f100=[Collections.Generic.List[object]]::new()}
  foreach ($path in $allPaths) {
    $allPresent = @($keys | Where-Object { $maps[$_].ContainsKey($path) }).Count -eq 4
    $allHashes = @()
    if ($allPresent) { $allHashes = @($keys | ForEach-Object { [string]$maps[$_][$path].raw_sha256 } | Sort-Object -Unique) }
    if ($allPresent -and @($allHashes).Count -eq 1) {
      $common.Add((Get-MIR4GoldenLayerEntry -Entry $maps.f210[$path]))
      continue
    }
    $modernSame = $maps.f210.ContainsKey($path) -and $maps.f200.ContainsKey($path) -and [string]$maps.f210[$path].raw_sha256 -ceq [string]$maps.f200[$path].raw_sha256
    if ($modernSame) { $modern.Add((Get-MIR4GoldenLayerEntry -Entry $maps.f210[$path])) }
    $legacySame = $maps.f110.ContainsKey($path) -and $maps.f100.ContainsKey($path) -and [string]$maps.f110[$path].raw_sha256 -ceq [string]$maps.f100[$path].raw_sha256
    if ($legacySame) { $legacy.Add((Get-MIR4GoldenLayerEntry -Entry $maps.f110[$path])) }
    foreach ($key in $keys) {
      $covered = if ($key -in @('f210','f200')) { $modernSame } else { $legacySame }
      if (-not $covered -and $maps[$key].ContainsKey($path)) { $targets[$key].Add((Get-MIR4GoldenLayerEntry -Entry $maps[$key][$path])) }
    }
  }
  return [pscustomobject][ordered]@{
    algorithm='byte-identical-maximal-four-target-common-then-family-common-then-target-overlay-v1'
    common=@($common)
    families=[pscustomobject][ordered]@{modern=@($modern);legacy=@($legacy)}
    targets=[pscustomobject][ordered]@{f210=@($targets.f210);f200=@($targets.f200);f110=@($targets.f110);f100=@($targets.f100)}
    reconstruction=[pscustomobject][ordered]@{
      f210=@('common','families.modern','targets.f210')
      f200=@('common','families.modern','targets.f200')
      f110=@('common','families.legacy','targets.f110')
      f100=@('common','families.legacy','targets.f100')
    }
  }
}

function New-MIR4GoldenTargetBaselineRecord {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$RecordedAt='2026-09-01T14:00:00+10:00')
  $repo = Get-MIR4GoldenRepoRoot -RepoRoot $RepoRoot
  if (-not (Get-Command Get-MIR4ArchiveInventory -ErrorAction SilentlyContinue)) { . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1') }
  $definitions = @(Get-MIR4GoldenTargetDefinitions -RepoRoot $repo)
  $inventories = [ordered]@{}
  $targetRecords = [Collections.Generic.List[object]]::new()
  foreach ($definition in $definitions) {
    $archiveRelative = [string]$definition.distribution.path
    $archivePath = Join-Path $repo $archiveRelative
    $inventory = Get-MIR4ArchiveInventory -Path $archivePath
    $inventories[[string]$definition.target] = $inventory
    if ([string]$inventory.archive_sha256 -cne [string]$definition.distribution.sha256 -or [int64]$inventory.bytes -ne [int64]$definition.distribution.bytes) { throw "[mir4-golden-target-archive-binding] $($definition.target)" }
    $info = Read-MIR4ArchiveText -Path $archivePath -RelativePath 'info.json' | ConvertFrom-Json -Depth 30 -DateKind String
    if ([string]$info.version -cne [string]$definition.distribution_version -or [string]$info.factorio_version -cne [string]$definition.factorio_line) { throw "[mir4-golden-target-info-binding] $($definition.target)" }
    $targetRecords.Add([pscustomobject][ordered]@{
      target=[string]$definition.target
      target_id=[string]$definition.target_id
      factorio_line=[string]$definition.factorio_line
      support_tier=[string]$definition.support_tier
      release_blocking=[bool]$definition.release_blocking
      distribution_target_code=[string]$definition.distribution_target_code
      distribution_version=[string]$definition.distribution_version
      distribution_tag="dist/$($definition.target)/v$($definition.distribution_version)"
      predecessor=[string]$definition.predecessor
      exact_engine=$definition.engine
      archive=[pscustomobject][ordered]@{path=$archiveRelative;root=[string]$inventory.root;sha256=[string]$inventory.archive_sha256;content_sha256=[string]$inventory.content_sha256;bytes=[int64]$inventory.bytes;entry_count=[int]$inventory.entry_count}
      info=$info
      identity_surface=Get-MIR4GoldenArchiveIdentitySurface -ArchivePath $archivePath -Inventory $inventory -RuntimeStateBackend ([string]$definition.runtime_state_backend)
      entries=@($inventory.entries | ForEach-Object { Get-MIR4GoldenLayerEntry -Entry $_ })
      runtime_proof=[pscustomobject][ordered]@{release_state='published-immutable-baseline';fresh_load_reload_upgrade_replay='required-before-package-authority-cutover';historical_release_proof_may_not_substitute_for_fresh_4_1_qualification=$true}
    })
  }
  $inputPaths = @('.mir/distributions.json','.mir/targets.json','.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV3.json','.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json')
  $inputs = @($inputPaths | ForEach-Object { [pscustomobject][ordered]@{path=$_;sha256=Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $_)} })
  $record = [pscustomobject][ordered]@{
    schema=1
    kind='MIR4GoldenFourTargetBaselineV1'
    status='accepted-byte-structure-and-identity-baseline-runtime-replay-required-before-cutover'
    recorded_at=$RecordedAt
    source_release=[pscustomobject][ordered]@{tag='v4.0.0';commit='5CA449820BDFA5595CA03686F32C74904C46DAF3';tree='83527C89F58E2D49EDBC06DBAE8FE747081EBC68'}
    inputs=$inputs
    targets=@($targetRecords)
    classification=New-MIR4GoldenClassification -Inventories $inventories
    invariants=[pscustomobject][ordered]@{exact_archive_bytes_bound=$true;every_archive_entry_inventoried=$true;all_paths_classified=$true;overlays_are_byte_deltas_not_full_target_copies=$true;package_source_unchanged=$true;version_allocated=$false}
    transition_gate=[pscustomobject][ordered]@{source_move=$false;package_cutover=$false;old_writer_retirement=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
    record_sha256=''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function Write-MIR4GoldenTargetBaseline {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$OutputPath='spec/distribution/mir4-golden-four-target-baseline-v1.json',[switch]$Check)
  $repo = Get-MIR4GoldenRepoRoot -RepoRoot $RepoRoot
  if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $repo $OutputPath }
  $expected = New-MIR4GoldenTargetBaselineRecord -RepoRoot $repo
  $lf = [string][char]10
  $json = ($expected | ConvertTo-Json -Depth 100).Replace([Environment]::NewLine, $lf) + $lf
  if ($Check) {
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) { throw '[mir4-golden-target-baseline-missing]' }
    $actualText = [IO.File]::ReadAllText($OutputPath).Replace(([string][char]13 + $lf), $lf).Replace([string][char]13, $lf)
    if ($actualText -cne $json) { throw '[mir4-golden-target-baseline-stale]' }
  } else {
    $parent = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($OutputPath, $json, [Text.UTF8Encoding]::new($false))
  }
  return $expected
}
