Set-StrictMode -Version Latest

$mir4TargetMaterializerRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue) -or
    -not (Get-Command Write-MIR4DeterministicRawTreeArchive -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4TargetMaterializerRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR4CanonicalPackageAuthority -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4TargetMaterializerRoot 'tools/mir/application/package/PackageAuthority.ps1')
}

function Read-MIR4TargetMaterializerRecord {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Kind)
  $definitions = [ordered]@{
    MIR4CanonicalPackageAuthorityV2 = 'spec/schemas/mir4-canonical-package-authority-v2.schema.json'
    MIR4ComposablePackageSourceV2 = 'spec/schemas/mir4-composable-package-source-v2.schema.json'
    MIR4ComposablePackageSourceV3 = 'spec/schemas/mir4-composable-package-source-v3.schema.json'
    MIR4TargetRegistryV2 = 'spec/schemas/mir4-target-registry-v2.schema.json'
    MIR4TargetSupportPolicyV1 = 'spec/schemas/mir4-target-support-policy-v1.schema.json'
    MIR4TargetCompositionV2 = 'spec/schemas/mir4-target-composition-v2.schema.json'
  }
  if (-not $definitions.Contains($Kind)) { throw "[mir4-target-materializer-kind] $Kind" }
  return Read-MIR4CanonicalPackageAuthorityRecord -RepoRoot $RepoRoot -RelativePath $RelativePath -Kind $Kind -Schema ([string]$definitions[$Kind]) -Code 'mir4-target-materializer-record'
}

function Get-MIR4TargetMaterializerState {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $manifest = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'source/package-source.json' -Kind 'MIR4ComposablePackageSourceV3'
  $registry = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'targets/registry.json' -Kind 'MIR4TargetRegistryV2'
  $support = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'targets/support-policy.json' -Kind 'MIR4TargetSupportPolicyV1'
  $targetRows = @($registry.targets | Where-Object { [string]$_.target -ceq $Target })
  $supportRows = @($support.targets | Where-Object { [string]$_.target -ceq $Target })
  if ($targetRows.Count -ne 1 -or $supportRows.Count -ne 1) { throw "[mir4-target-materializer-target] $Target" }
  $targetRow = $targetRows[0]
  $composition = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath ([string]$targetRow.composition) -Kind 'MIR4TargetCompositionV2'
  if ([string]$composition.target -cne $Target -or
      [string]$manifest.materializer_abi -cne [string]$registry.materializer_abi -or
      [string]$manifest.materializer_abi -cne [string]$composition.materializer_abi -or
      [string]$authority.materializer_abi -cne [string]$manifest.materializer_abi -or
      [string]$authority.source_manifest.record_sha256 -cne [string]$manifest.record_sha256 -or
      [string]$authority.target_registry.record_sha256 -cne [string]$registry.record_sha256 -or
      [string]$authority.support_policy.record_sha256 -cne [string]$support.record_sha256) { throw "[mir4-target-materializer-contract] $Target" }
  return [pscustomobject][ordered]@{repo=$repo;authority=$authority;manifest=$manifest;registry=$registry;support=$support;target=$targetRow;support_target=$supportRows[0];composition=$composition}
}

function Read-MIR4CanonicalSourceBindingBytes {
  param([Parameter(Mandatory)]$State,[Parameter(Mandatory)]$Binding)
  $relative = [string]$Binding.source_path
  Assert-MIR4PortableArchivePath -Path $relative
  if ($relative -notmatch '^source/') { throw "[mir4-target-materializer-source-boundary] $relative" }
  $full = [IO.Path]::GetFullPath((Join-Path ([string]$State.repo) $relative))
  $repoPrefix = ([string]$State.repo).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $full.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-target-materializer-source] $relative" }
  $sourceBytes = [IO.File]::ReadAllBytes($full)
  if ([int64]$sourceBytes.Length -ne [int64]$Binding.source_bytes -or (Get-MIR4Sha256Bytes -Bytes $sourceBytes) -cne [string]$Binding.source_sha256) { throw "[mir4-target-materializer-source-hash] $relative" }
  $outputBytes = switch ([string]$Binding.transform) {
    'copy-exact-bytes' { $sourceBytes; break }
    'exact-template-v1' { $sourceBytes; break }
    'decode-base64-v1' { [Convert]::FromBase64String(([Text.UTF8Encoding]::new($false).GetString($sourceBytes)).Trim()); break }
    default { throw "[mir4-target-materializer-transform] $($Binding.transform)" }
  }
  if ([int64]$outputBytes.Length -ne [int64]$Binding.output_bytes -or (Get-MIR4Sha256Bytes -Bytes $outputBytes) -cne [string]$Binding.output_sha256) { throw "[mir4-target-materializer-output-hash] $($Binding.output_path)" }
  return $outputBytes
}

function Get-MIR4TargetMaterializationBindings {
  param([Parameter(Mandatory)]$State)
  $target = [string]$State.target.target
  $pathMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  $expectedBindings = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($binding in @($State.manifest.bindings | Where-Object { $target -in @($_.target_scope) })) {
    $path = [string]$binding.output_path
    Assert-MIR4PortableArchivePath -Path $path
    if (-not $expectedBindings.TryAdd($path, $binding)) { throw "[mir4-target-materializer-manifest-collision] ${target}:$path" }
    if ([string]$binding.layer -ceq 'shared') { $pathMap.Add($path, $binding) }
  }
  if ($expectedBindings.Count -eq 0) { throw "[mir4-target-materializer-empty-target] $target" }
  $omissions = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $operations = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($operation in @($State.composition.operations)) {
    $path = [string]$operation.path
    Assert-MIR4PortableArchivePath -Path $path
    if (-not $operations.TryAdd($path, $operation)) { throw "[mir4-target-materializer-operation-collision] ${target}:$path" }
    if ([string]$operation.operation -ceq 'omit') {
      $otherTargetBindings = @($State.manifest.bindings | Where-Object { [string]$_.output_path -ceq $path -and $target -notin @($_.target_scope) })
      if ($expectedBindings.ContainsKey($path) -or $pathMap.ContainsKey($path) -or -not $omissions.Add($path) -or
          $otherTargetBindings.Count -eq 0 -or [string]$operation.semantic_class -cne 'target-omission' -or
          $null -ne $operation.source_path -or $null -ne $operation.transform -or
          $null -ne $operation.expected_bytes -or $null -ne $operation.expected_sha256) {
        throw "[mir4-target-materializer-omission] ${target}:$path"
      }
      continue
    }
    if (-not $expectedBindings.ContainsKey($path)) { throw "[mir4-target-materializer-operation-unbound] ${target}:$path" }
    $binding = $expectedBindings[$path]
    if ([string]$binding.layer -ceq 'shared' -or $pathMap.ContainsKey($path) -or
        [string]$binding.source_path -cne [string]$operation.source_path -or
        [string]$binding.transform -cne [string]$operation.transform -or
        [string]$binding.semantic_class -cne [string]$operation.semantic_class -or
        [int64]$binding.output_bytes -ne [int64]$operation.expected_bytes -or
        [string]$binding.output_sha256 -cne [string]$operation.expected_sha256) {
      throw "[mir4-target-materializer-operation-mismatch] ${target}:$path"
    }
    $pathMap.Add($path, $binding)
  }
  foreach ($entry in $expectedBindings.GetEnumerator()) {
    $path = [string]$entry.Key
    $binding = $entry.Value
    if ([string]$binding.layer -ceq 'shared') {
      if ($operations.ContainsKey($path)) { throw "[mir4-target-materializer-shared-operation] ${target}:$path" }
    } elseif (-not $operations.ContainsKey($path) -or -not $pathMap.ContainsKey($path)) {
      throw "[mir4-target-materializer-operation-closure] ${target}:$path"
    }
  }
  if ($pathMap.Count -ne $expectedBindings.Count) { throw "[mir4-target-materializer-selection-closure] $target" }
  return [pscustomobject][ordered]@{
    bindings=@($pathMap.Values | Sort-Object output_path -CaseSensitive)
    omissions=@($omissions | Sort-Object -CaseSensitive)
    scoped_operation_closure=$true
  }
}

function New-MIR4TargetPackage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9][A-Z0-9.-]*$')][string]$CandidateId,
    [string]$SourceVersion,
    [string]$DistributionVersion,
    [string]$OutputRoot='build/packages'
  )
  $state = Get-MIR4TargetMaterializerState -RepoRoot $RepoRoot -Target $Target
  $repo = [string]$state.repo
  $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target $Target -SourceVersion $SourceVersion -DistributionVersion $DistributionVersion
  if ([string]$identity.source_version -ceq '4.1.0') {
    throw '[mir4-target-materializer-historical-source-version-requires-pinned-checkout] 4.1.0'
  }
  if (-not [IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot = Join-Path $repo $OutputRoot }
  $output = [IO.Path]::GetFullPath($OutputRoot)
  if (-not (Test-Path -LiteralPath $output -PathType Container)) { New-Item -ItemType Directory -Force -Path $output | Out-Null }
  $candidateRoot = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath "$Target/$CandidateId"
  Remove-MIR4BuildTree -OutputRoot $output -Path $candidateRoot
  New-Item -ItemType Directory -Force -Path $candidateRoot | Out-Null
  $tree = Resolve-MIR4ArtifactPath -OutputRoot $candidateRoot -RelativePath ([string]$identity.distribution_root)
  New-Item -ItemType Directory -Force -Path $tree | Out-Null
  $selection = Get-MIR4TargetMaterializationBindings -State $state
  foreach ($binding in @($selection.bindings)) {
    $destination = Resolve-MIR4ArtifactPath -OutputRoot $tree -RelativePath ([string]$binding.output_path)
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($destination, (Read-MIR4CanonicalSourceBindingBytes -State $state -Binding $binding))
  }
  $infoPath = Join-Path $tree 'info.json'
  $info = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json -Depth 20 -DateKind String
  if ([string]$info.version -cne [string]$identity.target_authority.baseline_distribution_version) {
    throw '[mir4-target-materializer-baseline-info-version]'
  }
  if (-not [bool]$identity.is_baseline_reconstruction) {
    $info.version = [string]$identity.distribution_version
    $infoJson = ($info | ConvertTo-Json -Depth 20).Replace("`r`n","`n") + "`n"
    [IO.File]::WriteAllText($infoPath, $infoJson, [Text.UTF8Encoding]::new($false))
  }
  $archive = Join-Path $candidateRoot ([string]$identity.package_name)
  Write-MIR4DeterministicRawTreeArchive -SourceRoot $tree -EntryRoot ([string]$identity.distribution_root) -OutputPath $archive -ContainmentRoot $output
  $inventory = Get-MIR4ArchiveInventory -Path $archive
  $result = [pscustomobject][ordered]@{
    schema=1
    kind='MIR4PackageCompositionResultV1'
    status='passed-canonical-package-authority-materialization'
    materializer_abi=[string]$state.manifest.materializer_abi
    target=$Target
    candidate_id=$CandidateId
    source_version=[string]$identity.source_version
    distribution_version=[string]$identity.distribution_version
    package_authority_sha256=[string]$state.authority.record_sha256
    package_source_sha256=(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)
    source_manifest_sha256=[string]$state.manifest.record_sha256
    target_registry_sha256=[string]$state.registry.record_sha256
    support_policy_sha256=[string]$state.support.record_sha256
    target_overlay_sha256=[string]$state.composition.record_sha256
    source_binding_count=@($selection.bindings).Count
    omission_count=@($selection.omissions).Count
    tree_path=$tree
    archive_path=$archive
    archive_sha256=[string]$inventory.archive_sha256
    content_sha256=[string]$inventory.content_sha256
    entry_count=[int]$inventory.entry_count
    invariants=[pscustomobject][ordered]@{no_historical_archive_input=$true;all_source_hashes_verified=$true;all_output_hashes_verified=$true;all_target_differences_explicit=$true;scoped_operation_closure=[bool]$selection.scoped_operation_closure;version_identity_verified=$true;canonical_package_authority=$true}
    transition_gate=[pscustomobject][ordered]@{package_cutover=$true;old_writer_retirement=$true;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false}
    record_sha256=''
  }
  $result.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $result
  $resultJson = $result | ConvertTo-Json -Depth 100
  if (-not ($resultJson | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-package-composition-result-v1.schema.json'))) { throw '[mir4-target-materializer-composition-schema]' }
  return $result
}

function Invoke-MIR4TargetMaterializerParity {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [ValidateSet('f210','f200','f110','f100')][string[]]$Targets=@('f210','f200','f110','f100'),
    [string]$OutputRoot='build/packages',
    [string]$ReportPath='build/reports/package-source/mir4-editable-source-materializer-v1.json',
    [switch]$Check
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($target in $Targets) {
    $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target $target
    $a = New-MIR4TargetPackage -RepoRoot $repo -Target $target -CandidateId 'M41-F2E-A' -SourceVersion ([string]$identity.source_version) -OutputRoot $OutputRoot
    $b = New-MIR4TargetPackage -RepoRoot $repo -Target $target -CandidateId 'M41-F2E-B' -SourceVersion ([string]$identity.source_version) -OutputRoot $OutputRoot
    if ([string]$a.archive_sha256 -cne [string]$b.archive_sha256 -or [string]$a.content_sha256 -cne [string]$b.content_sha256 -or [int]$a.entry_count -ne [int]$b.entry_count -or
        -not [bool]$a.invariants.scoped_operation_closure -or -not [bool]$b.invariants.scoped_operation_closure) { throw "[mir4-target-materializer-determinism] $target" }
    if ([string]$a.content_sha256 -cne [string]$identity.target_authority.baseline_content_sha256 -or
        [int]$a.entry_count -ne [int]$identity.target_authority.baseline_entry_count) { throw "[mir4-target-materializer-baseline-parity] $target" }
    $rows.Add([pscustomobject][ordered]@{target=$target;distribution_version=[string]$a.distribution_version;source_binding_count=[int]$a.source_binding_count;omission_count=[int]$a.omission_count;archive_a=[string]$a.archive_sha256;archive_b=[string]$b.archive_sha256;content_sha256=[string]$a.content_sha256;entry_count=[int]$a.entry_count;deterministic_archive_bytes=$true;composition_record_a=[string]$a.record_sha256;composition_record_b=[string]$b.record_sha256})
    $absoluteOutput = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot)) }
    Remove-MIR4BuildTree -OutputRoot $absoluteOutput -Path (Split-Path -Parent ([string]$a.tree_path))
    Remove-MIR4BuildTree -OutputRoot $absoluteOutput -Path (Split-Path -Parent ([string]$b.tree_path))
  }
  $manifest = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'source/package-source.json' -Kind 'MIR4ComposablePackageSourceV3'
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $report = [pscustomobject][ordered]@{schema=1;kind='MIR4EditableSourceMaterializerProofV1';status='passed-four-target-canonical-package-authority-parity';materializer_abi=[string]$manifest.materializer_abi;package_authority_sha256=[string]$authority.record_sha256;package_source_sha256=(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo);source_manifest_sha256=[string]$manifest.record_sha256;targets=@($rows);invariants=[pscustomobject][ordered]@{four_target_determinism=$true;historical_archives_are_comparison_fixtures_only=$true;production_materializer_has_no_archive_input=$true;accepted_baseline_reconstruction=$true;package_cutover_complete=$true};transition_gate=[pscustomobject][ordered]@{package_cutover=$true;old_writer_retirement=$true;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false};record_sha256=''}
  $report.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $report
  $reportJson = ($report | ConvertTo-Json -Depth 100).Replace("`r`n","`n") + "`n"
  if (-not ($reportJson | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-editable-source-materializer-proof-v1.schema.json'))) { throw '[mir4-target-materializer-proof-schema]' }
  if (-not [IO.Path]::IsPathRooted($ReportPath)) { $ReportPath = Join-Path $repo $ReportPath }
  if ($Check) {
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { throw "[mir4-target-materializer-proof-missing] $ReportPath" }
    $current = [IO.File]::ReadAllText($ReportPath).Replace("`r`n","`n")
    if ($current -cne $reportJson) { throw "[mir4-target-materializer-proof-stale] $ReportPath" }
    return $report
  }
  $parent = Split-Path -Parent $ReportPath
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [IO.File]::WriteAllText($ReportPath, $reportJson, [Text.UTF8Encoding]::new($false))
  return $report
}

function Invoke-MIR4CurrentSourceMaterializerProof {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [ValidateSet('f210','f200','f110','f100')][string[]]$Targets=@('f210','f200','f110','f100'),
    [string]$OutputRoot='build/packages',
    [string]$ReportPath='build/reports/package-source/mir4-current-source-materializer-v1.json',
    [switch]$Check
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($target in $Targets) {
    $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target $target
    $a = New-MIR4TargetPackage -RepoRoot $repo -Target $target -CandidateId 'M42-02-CURRENT-A' -SourceVersion ([string]$identity.source_version) -OutputRoot $OutputRoot
    $b = New-MIR4TargetPackage -RepoRoot $repo -Target $target -CandidateId 'M42-02-CURRENT-B' -SourceVersion ([string]$identity.source_version) -OutputRoot $OutputRoot
    if ([string]$a.archive_sha256 -cne [string]$b.archive_sha256 -or [string]$a.content_sha256 -cne [string]$b.content_sha256 -or [int]$a.entry_count -ne [int]$b.entry_count -or
        -not [bool]$a.invariants.scoped_operation_closure -or -not [bool]$b.invariants.scoped_operation_closure) {
      throw "[mir4-current-source-materializer-determinism] $target"
    }
    $absoluteOutput = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot)) }
    $portableCompositionSha256 = @{}
    foreach ($candidate in @($a,$b)) {
      $portable = $candidate | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
      foreach ($pathField in @('tree_path','archive_path')) {
        $relative = [IO.Path]::GetRelativePath($absoluteOutput, [IO.Path]::GetFullPath([string]$portable.$pathField)).Replace('\','/')
        if ($relative -ceq '..' -or $relative.StartsWith('../',[StringComparison]::Ordinal)) { throw "[mir4-current-source-materializer-portable-path] $target/$pathField" }
        $portable.$pathField = $relative
      }
      $portable.record_sha256 = ''
      $portableCompositionSha256[[string]$portable.candidate_id] = Get-MIR4BootstrapRecordSha256 -Record $portable
    }
    $rows.Add([pscustomobject][ordered]@{
      target=$target
      distribution_version=[string]$a.distribution_version
      source_binding_count=[int]$a.source_binding_count
      omission_count=[int]$a.omission_count
      archive_a=[string]$a.archive_sha256
      archive_b=[string]$b.archive_sha256
      content_sha256=[string]$a.content_sha256
      entry_count=[int]$a.entry_count
      baseline_content_sha256=[string]$identity.target_authority.baseline_content_sha256
      baseline_entry_count=[int]$identity.target_authority.baseline_entry_count
      baseline_match=([string]$a.content_sha256 -ceq [string]$identity.target_authority.baseline_content_sha256 -and [int]$a.entry_count -eq [int]$identity.target_authority.baseline_entry_count)
      entry_count_delta=([int]$a.entry_count - [int]$identity.target_authority.baseline_entry_count)
      deterministic_archive_bytes=$true
      composition_record_a=[string]$portableCompositionSha256[[string]$a.candidate_id]
      composition_record_b=[string]$portableCompositionSha256[[string]$b.candidate_id]
    })
    Remove-MIR4BuildTree -OutputRoot $absoluteOutput -Path (Split-Path -Parent ([string]$a.tree_path))
    Remove-MIR4BuildTree -OutputRoot $absoluteOutput -Path (Split-Path -Parent ([string]$b.tree_path))
  }
  $manifest = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'source/package-source.json' -Kind 'MIR4ComposablePackageSourceV3'
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $report = [pscustomobject][ordered]@{
    schema=1
    kind='MIR4CurrentSourceMaterializerProofV1'
    status='passed-four-target-current-source-determinism'
    materializer_abi=[string]$manifest.materializer_abi
    package_authority_sha256=[string]$authority.record_sha256
    package_source_sha256=(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)
    source_manifest_sha256=[string]$manifest.record_sha256
    targets=@($rows)
    invariants=[pscustomobject][ordered]@{
      four_target_determinism=$true
      historical_baseline_authority_immutable=$true
      production_materializer_has_no_archive_input=$true
      current_source_differences_explicit=$true
      package_cutover_complete=$true
    }
    transition_gate=[pscustomobject][ordered]@{package_cutover=$true;old_writer_retirement=$true;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false}
    record_sha256=''
  }
  $report.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $report
  $reportJson = ($report | ConvertTo-Json -Depth 100).Replace("`r`n","`n") + "`n"
  if (-not ($reportJson | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-current-source-materializer-proof-v1.schema.json'))) {
    throw '[mir4-current-source-materializer-proof-schema]'
  }
  if (-not [IO.Path]::IsPathRooted($ReportPath)) { $ReportPath = Join-Path $repo $ReportPath }
  if ($Check) {
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { throw "[mir4-current-source-materializer-proof-missing] $ReportPath" }
    $current = [IO.File]::ReadAllText($ReportPath).Replace("`r`n","`n")
    if ($current -cne $reportJson) { throw "[mir4-current-source-materializer-proof-stale] $ReportPath" }
    return $report
  }
  $parent = Split-Path -Parent $ReportPath
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [IO.File]::WriteAllText($ReportPath, $reportJson, [Text.UTF8Encoding]::new($false))
  return $report
}

function Update-MIR4CurrentSourceBindings {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  # Refresh only existing, admitted paths. Membership, target scope, transforms,
  # versioning and support remain separately reviewed authorities.
  $manifest=Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'source/package-source.json' -Kind 'MIR4ComposablePackageSourceV3'
  $authority=Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'targets/package-authority.json' -Kind 'MIR4CanonicalPackageAuthorityV2'
  $records=[ordered]@{}
  $identities=@{}
  $changed=[Collections.Generic.List[string]]::new()
  foreach($binding in @($manifest.bindings)) {
    $relative=[string]$binding.source_path
    Assert-MIR4PortableArchivePath -Path $relative
    if($relative -notmatch '^source/') { throw "[mir4-source-refresh-boundary] $relative" }
    $full=[IO.Path]::GetFullPath((Join-Path $repo $relative))
    if(-not $full.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-source-refresh-path]' }
    $source=[IO.File]::ReadAllBytes($full)
    $sha=Get-MIR4Sha256Bytes -Bytes $source
    if([string]$binding.source_sha256 -cne $sha) { $changed.Add($relative) }
    $output=switch([string]$binding.transform) {
      'copy-exact-bytes' { $source; break }
      'exact-template-v1' { $source; break }
      'decode-base64-v1' { [Convert]::FromBase64String([Text.UTF8Encoding]::new($false).GetString($source).Trim()); break }
      default { throw "[mir4-source-refresh-transform] $relative" }
    }
    $binding.source_bytes=[int64]$source.Length
    $binding.source_sha256=$sha
    $binding.output_bytes=[int64]$output.Length
    $binding.output_sha256=Get-MIR4Sha256Bytes -Bytes $output
    $identities[$relative]=$sha
  }
  $manifest.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $manifest
  $records['source/package-source.json']=@{record=$manifest;schema='mir4-composable-package-source-v3.schema.json'}
  foreach($target in @('f210','f200','f110','f100')) {
    $path="targets/$target/composition.json"
    $composition=Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath $path -Kind 'MIR4TargetCompositionV2'
    foreach($operation in @($composition.operations)) {
      if([string]$operation.operation -ceq 'omit') { continue }
      $rows=@($manifest.bindings | Where-Object { [string]$_.output_path -ceq [string]$operation.path -and [string]$_.source_path -ceq [string]$operation.source_path -and $target -in @($_.target_scope) })
      if($rows.Count -ne 1 -or [string]$rows[0].transform -cne [string]$operation.transform) { throw "[mir4-source-refresh-overlay] $target/$($operation.path)" }
      $operation.expected_bytes=[int64]$rows[0].output_bytes
      $operation.expected_sha256=[string]$rows[0].output_sha256
    }
    $composition.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $composition
    $records[$path]=@{record=$composition;schema='mir4-target-composition-v2.schema.json'}
  }
  $authority.source_manifest.record_sha256=[string]$manifest.record_sha256
  $authority.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $authority
  $records['targets/package-authority.json']=@{record=$authority;schema='mir4-canonical-package-authority-v2.schema.json'}
  $writes=[ordered]@{}
  foreach($entry in $records.GetEnumerator()) {
    $json=($entry.Value.record | ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n"
    if(-not($json | Test-Json -SchemaFile (Join-Path $repo "spec/schemas/$($entry.Value.schema)"))) { throw "[mir4-source-refresh-schema] $($entry.Key)" }
    if([IO.File]::ReadAllText((Join-Path $repo $entry.Key)).Replace("`r`n","`n") -cne $json) { $writes[$entry.Key]=$json }
  }
  if($Check -and $writes.Count -gt 0) { throw "[mir4-source-refresh-stale] $($writes.Keys -join ', ')" }
  foreach($entry in $identities.GetEnumerator()) {
    if((Get-MIR4Sha256Bytes -Bytes ([IO.File]::ReadAllBytes((Join-Path $repo $entry.Key)))) -cne [string]$entry.Value) { throw "[mir4-source-refresh-input-drift] $($entry.Key)" }
  }
  if(-not $Check) {
    foreach($entry in $writes.GetEnumerator()) {
      $path=Join-Path $repo $entry.Key
      $temporary=$path+'.refresh-tmp'
      [IO.File]::WriteAllText($temporary,[string]$entry.Value,[Text.UTF8Encoding]::new($false))
      [IO.File]::Move($temporary,$path,$true)
    }
  }
  [pscustomobject][ordered]@{status='current';changed_sources=@($changed.ToArray() | Sort-Object -Unique);projections=@($writes.Keys);membership_changed=$false;publication_authorized=$false}
}
