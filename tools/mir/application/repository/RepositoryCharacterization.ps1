. (Join-Path $PSScriptRoot '../../domain/repository/RepositoryFixedPoint.ps1')
. (Join-Path $PSScriptRoot '../../../lib/validation/PackageIdentity.ps1')

$script:MIR4RepositoryCharacterizationAuthorityPath = 'governance/repository/migrations/repository-characterization-v1.json'
$script:MIR4RepositoryCharacterizationAuthoritySchemaPath = 'contracts/repository/mir4-repository-characterization-authority-v1.schema.json'
$script:MIR4RepositoryCharacterizationBundleSchemaPath = 'contracts/repository/mir4-repository-characterization-bundle-v1.schema.json'
$script:MIR4RepositoryCharacterizationDefaultOutput = 'build/reports/repository-characterization'
$script:MIR4RepositoryCharacterizationExpectedReadme = '403B993FEF39C5DC99C4A1F641DFF9795A976B32D2C42D327A25488BAC492F20'

function ConvertTo-MIR4RepositoryCharacterizationJsonV1 {
  param([Parameter(Mandatory)]$Value)
  return (($Value | ConvertTo-Json -Depth 100).Replace("`r`n","`n") + "`n")
}

function Get-MIR4RepositoryCharacterizationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4RepositoryCharacterizationAuthorityPath -SchemaPath $script:MIR4RepositoryCharacterizationAuthoritySchemaPath)) {
    throw '[mir4-repository-characterization-authority-schema]'
  }
  $authority = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4RepositoryCharacterizationAuthorityPath
  if (@($authority.writers).Count -ne 1 -or [string]$authority.writers[0].path -cne 'tools/mir/application/repository/RepositoryCharacterization.ps1') {
    throw '[mir4-repository-characterization-single-writer]'
  }
  if (@($authority.release_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
    throw '[mir4-repository-characterization-release-firewall]'
  }
  return $authority
}

function Get-MIR4RepositoryCharacterizationRootIdV1 {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$FixedPoint)
  $normalized = $Path.Replace('\','/')
  foreach ($root in @($FixedPoint.visible_roots | Sort-Object { ([string]$_.path).Length } -Descending)) {
    $rootPath = ([string]$root.path).TrimEnd('/')
    if ($normalized -ceq $rootPath -or $normalized.StartsWith($rootPath + '/', [StringComparison]::Ordinal)) { return [string]$root.id }
  }
  return 'repository-root'
}

function Get-MIR4RepositoryCharacterizationMigrationsV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$FixedPoint)
  $rows = @()
  $ordinal = 0
  foreach ($entry in @($FixedPoint.migration_sequence)) {
    $authorityPath = [string]$entry.authority
    if (-not $authorityPath.StartsWith('governance/repository/migrations/', [StringComparison]::Ordinal)) { continue }
    $migration = Get-MIR4RepositoryJsonV1 -RepoRoot $RepoRoot -Path $authorityPath
    $rows += [pscustomobject][ordered]@{ordinal=$ordinal;authority_path=$authorityPath;sequence_state=[string]$entry.state;value=$migration}
    $ordinal++
  }
  return @($rows)
}

function New-MIR4RepositoryCharacterizationBundleV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authority = Get-MIR4RepositoryCharacterizationAuthorityV1 -RepoRoot $repo
  $fixedPoint = Get-MIR4RepositoryFixedPointAuthority -RepoRoot $repo
  $packageSourceBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  $packageFiles = @(Get-MIRPackageSourceFiles -RepoRoot $repo)
  $packageSet = @{}; foreach ($path in $packageFiles) { $packageSet[[string]$path] = $true }

  $physicalPaths = @(& git -C $repo ls-files --cached --others --exclude-standard | ForEach-Object { $_.Replace('\','/') } | Sort-Object -Unique)
  if ($LASTEXITCODE -ne 0) { throw '[mir4-repository-characterization-git-files]' }
  $physicalRows = @(
    foreach ($path in $physicalPaths) {
      [ordered]@{
        path=$path
        class=(Get-MIR4RepositoryPathClass -Path $path)
        logical_root=(Get-MIR4RepositoryCharacterizationRootIdV1 -Path $path -FixedPoint $fixedPoint)
        package_visible=$packageSet.ContainsKey($path)
      }
    }
  )
  $unknownPaths = @($physicalRows | Where-Object { [string]$_.class -ceq 'unknown' })

  $migrations = @(Get-MIR4RepositoryCharacterizationMigrationsV1 -RepoRoot $repo -FixedPoint $fixedPoint)
  $facts = @(); $writers = @(); $readers = @(); $bridges = @(); $currentByPath = [ordered]@{}
  foreach ($record in $migrations) {
    $migration = $record.value
    $migrationId = [string]$migration.migration_id
    $index = 0
    foreach ($binding in @($migration.path_map)) {
      $finalPath = [string]$binding.final_path
      $fact = [ordered]@{
        fact_id=("{0}#{1:D3}" -f $migrationId,$index)
        migration_id=$migrationId
        migration_ordinal=[int]$record.ordinal
        family=[string]$binding.family
        current_path=$(if($null -eq $binding.current_path){$null}else{[string]$binding.current_path})
        final_path=$finalPath
        state=[string]$binding.state
        package_visible=[bool]$binding.package_visible
        authority_path=[string]$record.authority_path
      }
      $facts += $fact
      $currentByPath[$finalPath] = $fact
      $index++
    }
    foreach ($writer in @($migration.writers)) {
      $writers += [ordered]@{migration_id=$migrationId;fact_family=[string]$writer.fact_family;path=[string]$writer.path;command=[string]$writer.command;writable=$true}
    }
    foreach ($reader in @($migration.compatibility_entrypoints)) {
      $row = [ordered]@{migration_id=$migrationId;path=[string]$reader.path;role=[string]$reader.role;writable=[bool]$reader.writable}
      $readers += $row
      $bridges += [ordered]@{
        migration_id=$migrationId
        path=[string]$reader.path
        role=[string]$reader.role
        writable=[bool]$reader.writable
        declared_sunset_state=[string]$migration.sunset.state
        disposition='retained-blocked-pending-declared-gates'
        required_gates=@($migration.sunset.required_gates | ForEach-Object { [string]$_ })
        deletion_authorized=$false
      }
    }
  }
  $bridgeAuthorityPath = Join-Path $repo 'governance/repository/migrations/current-product-bridge-retirement-v1.json'
  if (Test-Path -LiteralPath $bridgeAuthorityPath -PathType Leaf) {
    . (Join-Path $repo 'tools/mir/application/repository/BridgeRetirement.ps1')
    $bridgeAuthority = Get-MIR4CurrentProductBridgeRetirementAuthority -RepoRoot $repo
    $dispositions = @{}
    foreach ($entry in @($bridgeAuthority.bridge_dispositions)) {
      $dispositions["$([string]$entry.migration_id)|$([string]$entry.path)"] = $entry
    }
    foreach ($bridge in $bridges) {
      $key = "$([string]$bridge.migration_id)|$([string]$bridge.path)"
      if (-not $dispositions.ContainsKey($key)) { throw "[mir4-repository-characterization-unclassified-bridge] $key" }
      $disposition = $dispositions[$key]
      $bridge['disposition'] = [string]$disposition.disposition
      $bridge['canonical_replacements'] = @($disposition.canonical_replacements | ForEach-Object { [string]$_ })
      $bridge['package_visible'] = [bool]$disposition.package_visible
      $bridge['current_semantic_use'] = [bool]$disposition.current_semantic_use
      $bridge['current_authority'] = [bool]$disposition.current_authority
      $bridge['owner'] = [string]$disposition.owner
      $bridge['proof'] = [string]$disposition.proof
      $bridge['expiry_condition'] = [string]$disposition.expiry_condition
      $bridge['rollback'] = [string]$disposition.rollback
      $bridge['deletion_authorized'] = [bool]$disposition.deletion_authorized
    }
  }
  $currentBindings = @($currentByPath.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Value })
  $duplicateCurrent = @(
    foreach ($group in @($facts | Group-Object { [string]$_['final_path'] })) {
      $maximumOrdinal = @($group.Group | ForEach-Object { [int]$_['migration_ordinal'] } | Measure-Object -Maximum).Maximum
      $latest = @($group.Group | Where-Object { [int]$_['migration_ordinal'] -eq [int]$maximumOrdinal })
      if ($latest.Count -gt 1) { [ordered]@{final_path=[string]$group.Name;migration_ordinal=[int]$maximumOrdinal;declarations=$latest.Count} }
    }
  )
  $writerCountByMigration = @{}; foreach ($group in @($writers | Group-Object { [string]$_['migration_id'] })) { $writerCountByMigration[[string]$group.Name] = $group.Count }
  $invalidCurrentWriterBindings = @($currentBindings | Where-Object { -not $writerCountByMigration.ContainsKey([string]$_['migration_id']) -or [int]$writerCountByMigration[[string]$_['migration_id']] -ne 1 })

  $nodes = [ordered]@{}; $edges = @()
  foreach ($writer in $writers) {
    $writerId = 'writer:' + [string]$writer.path; $migrationId = 'migration:' + [string]$writer.migration_id
    $nodes[$writerId] = [ordered]@{id=$writerId;kind='writer';label=[string]$writer.path}
    $nodes[$migrationId] = [ordered]@{id=$migrationId;kind='migration';label=[string]$writer.migration_id}
    $edges += [ordered]@{from=$writerId;to=$migrationId;relation='declared-writer-for'}
  }
  foreach ($binding in $currentBindings) {
    $migrationId = 'migration:' + [string]$binding.migration_id; $pathId = 'path:' + [string]$binding.final_path
    $nodes[$migrationId] = [ordered]@{id=$migrationId;kind='migration';label=[string]$binding.migration_id}
    $nodes[$pathId] = [ordered]@{id=$pathId;kind='path';label=[string]$binding.final_path}
    $edges += [ordered]@{from=$migrationId;to=$pathId;relation='governs-current-binding'}
  }
  foreach ($reader in $readers) {
    $readerId = 'reader:' + [string]$reader.path; $migrationId = 'migration:' + [string]$reader.migration_id
    $nodes[$readerId] = [ordered]@{id=$readerId;kind='reader';label=[string]$reader.path}
    $edges += [ordered]@{from=$readerId;to=$migrationId;relation='compatibility-reader-for'}
  }

  $packageRows = @(
    foreach ($path in $packageFiles) {
      [ordered]@{path=$path;source_root=(@(Get-MIRPackageSourceRoots | Where-Object { $path -ceq $_ -or $path.StartsWith($_ + '/', [StringComparison]::Ordinal) }) | Select-Object -First 1);class=(Get-MIR4RepositoryPathClass -Path $path);package_visible=$true}
    }
  )
  $packageSourceSha = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  $readmeSha = Get-MIRFileContentSha256 -Path (Join-Path $repo 'README.md') -RelativePath 'README.md'

  $documentationRows = @($physicalRows | Where-Object { ([string]$_.path).StartsWith('docs/', [StringComparison]::Ordinal) -and ([string]$_.path).EndsWith('.md', [StringComparison]::OrdinalIgnoreCase) })
  $statusCounts = [ordered]@{}
  foreach ($row in $documentationRows) {
    $text = [IO.File]::ReadAllText((Join-Path $repo ([string]$row.path)))
    $status = if ($text -match '(?m)^status:\s*([^\r\n]+)') { $Matches[1].Trim() } else { 'unclassified' }
    if (-not $statusCounts.Contains($status)) { $statusCounts[$status] = 0 }
    $statusCounts[$status]++
  }

  $reportValues = [ordered]@{
    'authority-ledger.json'=[ordered]@{schema=1;kind='MIR4AuthorityLedgerV1';migration_order=@($migrations | ForEach-Object { [ordered]@{ordinal=[int]$_.ordinal;migration_id=[string]$_.value.migration_id;authority_path=[string]$_.authority_path;sequence_state=[string]$_.sequence_state} });facts=@($facts);current_bindings=@($currentBindings);duplicate_current_bindings=@($duplicateCurrent);invalid_current_writer_bindings=@($invalidCurrentWriterBindings | ForEach-Object { [string]$_['final_path'] });deletion_authorized=$false}
    'writer-records.json'=[ordered]@{schema=1;kind='MIR4WriterRecordsV1';writers=@($writers | Sort-Object migration_id,path);sole_characterization_writer=[string]$authority.writers[0].path;deletion_authorized=$false}
    'reader-records.json'=[ordered]@{schema=1;kind='MIR4ReaderRecordsV1';readers=@($readers | Sort-Object migration_id,path);source='declared-compatibility-entrypoints';inferred_from_source=$false;deletion_authorized=$false}
    'reader-writer-graph.json'=[ordered]@{schema=1;kind='MIR4ReaderWriterGraphV1';nodes=@($nodes.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Value });edges=@($edges | Sort-Object from,to,relation);inferred_from_source=$false;deletion_authorized=$false}
    'bridge-expiry.json'=[ordered]@{schema=1;kind='MIR4BridgeExpiryReportV1';bridges=@($bridges | Sort-Object migration_id,path);summary=[ordered]@{declared=$bridges.Count;retained_historical=@($bridges | Where-Object disposition -ceq 'retained-historical-compatibility').Count;retired=@($bridges | Where-Object disposition -ceq 'retired-reassigned').Count;current_product=@($bridges | Where-Object { [bool]$_['current_authority'] -or [bool]$_['current_semantic_use'] }).Count;dual_write_authority=@($bridges | Where-Object { [bool]$_['writable'] -and [bool]$_['current_authority'] }).Count;package_authority_bridge=@($bridges | Where-Object { [bool]$_['package_visible'] -or [string]$_['role'] -match 'package-authority' }).Count;release_current_state_authority_bridge=0;runtime_state_migration_authority_bridge=0;public_claim_authority_bridge=0;unowned=@($bridges | Where-Object { [string]::IsNullOrWhiteSpace([string]$_['owner']) }).Count;unbounded=@($bridges | Where-Object { [string]::IsNullOrWhiteSpace([string]$_['expiry_condition']) }).Count};deletion_authorized=$false}
    'physical-file-inventory.json'=[ordered]@{schema=1;kind='MIR4PhysicalFileInventoryV1';files=@($physicalRows);summary=[ordered]@{files=$physicalRows.Count;unknown=$unknownPaths.Count;package_visible=@($physicalRows | Where-Object package_visible).Count};ignored_outputs_excluded=$true;deletion_authorized=$false}
    'package-membership.json'=[ordered]@{schema=1;kind='MIR4PackageMembershipInventoryV1';source_roots=@(Get-MIRPackageSourceRoots);files=@($packageRows);package_source_sha256=$packageSourceSha;expected_package_source_sha256=$packageSourceBefore;root_readme=[ordered]@{path='README.md';sha256=$readmeSha;expected_sha256=$script:MIR4RepositoryCharacterizationExpectedReadme;package_visible=$false;disposition='repository-documentation-package-excluded-m41-05b-complete'};repository_docs_package_excluded=$true;package_mutation_authorized=$false}
    'documentation-routing.json'=[ordered]@{schema=1;kind='MIR4DocumentationRoutingInventoryV1';routes=[ordered]@{tutorials='docs/tutorials/README.md';how_to='docs/how-to/README.md';reference='docs/reference/README.md';explanation='docs/explanation/README.md'};markdown_files=$documentationRows.Count;front_matter_status_counts=$statusCounts;root_readme_sha256=$readmeSha;root_readme_byte_stable=($readmeSha -ceq $script:MIR4RepositoryCharacterizationExpectedReadme);root_readme_changed=$false;package_visible_delta=@()}
  }

  $reportDescriptors = @()
  foreach ($entry in $reportValues.GetEnumerator()) {
    $json = ConvertTo-MIR4RepositoryCharacterizationJsonV1 -Value $entry.Value
    $rowCount = switch ([string]$entry.Key) {
      'authority-ledger.json' { $facts.Count }
      'writer-records.json' { $writers.Count }
      'reader-records.json' { $readers.Count }
      'reader-writer-graph.json' { $edges.Count }
      'bridge-expiry.json' { $bridges.Count }
      'physical-file-inventory.json' { $physicalRows.Count }
      'package-membership.json' { $packageRows.Count }
      'documentation-routing.json' { $documentationRows.Count }
    }
    $reportDescriptors += [ordered]@{name=[string]$entry.Key;kind=[string]$entry.Value.kind;sha256=(Get-MIRStringSha256 -Value $json);row_count=[int]$rowCount}
  }
  $bundle = [ordered]@{
    schema=1;kind='MIR4RepositoryCharacterizationBundleV1';programme_id='M41-05A-M42-00A'
    source=[ordered]@{repository_fixed_point_sha256=(Get-MIRFileSha256 -Path (Join-Path $repo '.mir/control/repository-fixed-point.json'));migration_count=$migrations.Count;package_source_sha256=$packageSourceSha;root_readme_sha256=$readmeSha}
    reports=@($reportDescriptors)
    summary=[ordered]@{physical_files=$physicalRows.Count;authority_facts=$facts.Count;current_bindings=$currentBindings.Count;writers=$writers.Count;readers=$readers.Count;bridges=$bridges.Count;package_files=$packageRows.Count}
    invariants=[ordered]@{unknown_paths=$unknownPaths.Count;duplicate_current_bindings=$duplicateCurrent.Count;invalid_current_writer_bindings=$invalidCurrentWriterBindings.Count;current_product_bridges=@($bridges | Where-Object { [bool]$_['current_authority'] -or [bool]$_['current_semantic_use'] }).Count;unowned_bridges=@($bridges | Where-Object { [string]::IsNullOrWhiteSpace([string]$_['owner']) }).Count;unbounded_bridges=@($bridges | Where-Object { [string]::IsNullOrWhiteSpace([string]$_['expiry_condition']) }).Count;package_source_unchanged=($packageSourceSha -ceq $packageSourceBefore);root_readme_byte_stable=($readmeSha -ceq $script:MIR4RepositoryCharacterizationExpectedReadme);deletion_authorized=$false}
    transition_gate=[ordered]@{source_move=$false;package_cutover=$false;readme_rewrite=$false;bridge_retirement=$false;version_allocation=$false;publication=$false}
  }
  if ($unknownPaths.Count -ne 0) { throw "[mir4-repository-characterization-unknown-paths] $($unknownPaths.path -join ',')" }
  if ($duplicateCurrent.Count -ne 0) { throw '[mir4-repository-characterization-duplicate-current-binding]' }
  if ($invalidCurrentWriterBindings.Count -ne 0) { throw '[mir4-repository-characterization-invalid-current-writer-binding]' }
  if ($packageSourceSha -cne $packageSourceBefore) { throw '[mir4-repository-characterization-package-source-mutation]' }
  if ($readmeSha -cne $script:MIR4RepositoryCharacterizationExpectedReadme) { throw '[mir4-repository-characterization-root-readme]' }
  return [pscustomobject][ordered]@{bundle=$bundle;reports=$reportValues}
}

function Invoke-MIR4RepositoryCharacterizationV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$OutputPath=$script:MIR4RepositoryCharacterizationDefaultOutput,[switch]$Check)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $result = New-MIR4RepositoryCharacterizationBundleV1 -RepoRoot $repo
  $outputRoot = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repo $OutputPath }
  $values = [ordered]@{}; foreach ($entry in $result.reports.GetEnumerator()) { $values[[string]$entry.Key] = $entry.Value }; $values['manifest.json'] = $result.bundle
  foreach ($entry in $values.GetEnumerator()) {
    $path = Join-Path $outputRoot ([string]$entry.Key)
    $json = ConvertTo-MIR4RepositoryCharacterizationJsonV1 -Value $entry.Value
    if ($Check) {
      if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.File]::ReadAllText($path).Replace("`r`n","`n") -cne $json) { throw "[mir4-repository-characterization-stale] $($entry.Key)" }
    } else {
      [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path))
      [IO.File]::WriteAllText($path,$json,[Text.UTF8Encoding]::new($false))
    }
  }
  $manifestPath = Join-Path $outputRoot 'manifest.json'
  if (-not ((Get-Content -Raw -LiteralPath $manifestPath) | Test-Json -SchemaFile (Join-Path $repo $script:MIR4RepositoryCharacterizationBundleSchemaPath))) { throw '[mir4-repository-characterization-bundle-schema]' }
  return [pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});output_path=$OutputPath;reports=$result.bundle.reports.Count;summary=$result.bundle.summary;invariants=$result.bundle.invariants}
}
