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
  $path = Join-Path $RepoRoot $RelativePath
  $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$record.kind -cne $Kind -or -not (Test-MIR4BootstrapRecordHash -Record $record)) { throw "[mir4-target-materializer-record] $RelativePath" }
  return $record
}

function Get-MIR4TargetMaterializerState {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $manifest = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'src/mod/package-source.json' -Kind 'MIR4PackageSourceManifestV1'
  $registry = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'targets/registry.json' -Kind 'MIR4TargetRegistryV1'
  $support = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'targets/support-policy.json' -Kind 'MIR4TargetSupportPolicyV1'
  $targetRows = @($registry.targets | Where-Object { [string]$_.target -ceq $Target })
  $supportRows = @($support.targets | Where-Object { [string]$_.target -ceq $Target })
  if ($targetRows.Count -ne 1 -or $supportRows.Count -ne 1) { throw "[mir4-target-materializer-target] $Target" }
  $targetRow = $targetRows[0]
  $overlay = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath ([string]$targetRow.overlay) -Kind 'MIR4TargetOverlayV1'
  if ([string]$overlay.target -cne $Target -or [string]$overlay.family -cne [string]$targetRow.family -or
      [string]$manifest.materializer_abi -cne [string]$registry.materializer_abi -or
      [string]$manifest.materializer_abi -cne [string]$overlay.materializer_abi -or
      [string]$authority.materializer_abi -cne [string]$manifest.materializer_abi -or
      [string]$authority.source_manifest.record_sha256 -cne [string]$manifest.record_sha256 -or
      [string]$authority.target_registry.record_sha256 -cne [string]$registry.record_sha256 -or
      [string]$authority.support_policy.record_sha256 -cne [string]$support.record_sha256) { throw "[mir4-target-materializer-contract] $Target" }
  return [pscustomobject][ordered]@{repo=$repo;authority=$authority;manifest=$manifest;registry=$registry;support=$support;target=$targetRow;support_target=$supportRows[0];overlay=$overlay}
}

function Read-MIR4CanonicalSourceBindingBytes {
  param([Parameter(Mandatory)]$State,[Parameter(Mandatory)]$Binding)
  $relative = [string]$Binding.source_path
  Assert-MIR4PortableArchivePath -Path $relative
  if ($relative -notmatch '^(?:src/mod/|targets/f(?:210|200|110|100)/(?:files|generation)/)') { throw "[mir4-target-materializer-source-boundary] $relative" }
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
  foreach ($binding in @($State.manifest.bindings | Where-Object { [string]$_.layer -ceq 'common' })) {
    if ($target -notin @($binding.target_scope)) { throw "[mir4-target-materializer-common-scope] $($binding.output_path)" }
    $pathMap.Add([string]$binding.output_path, $binding)
  }
  $omissions = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($operation in @($State.overlay.operations)) {
    $path = [string]$operation.path
    Assert-MIR4PortableArchivePath -Path $path
    if ([string]$operation.operation -ceq 'omit') {
      if ($pathMap.ContainsKey($path) -or -not $omissions.Add($path) -or $null -ne $operation.source_path -or $null -ne $operation.expected_sha256) { throw "[mir4-target-materializer-omission] ${target}:$path" }
      continue
    }
    $matches = @($State.manifest.bindings | Where-Object {
      [string]$_.output_path -ceq $path -and [string]$_.source_path -ceq [string]$operation.source_path -and $target -in @($_.target_scope) -and [string]$_.layer -cne 'common'
    })
    if ($matches.Count -ne 1 -or $pathMap.ContainsKey($path) -or [string]$matches[0].output_sha256 -cne [string]$operation.expected_sha256) { throw "[mir4-target-materializer-overlay] ${target}:$path" }
    $pathMap.Add($path, $matches[0])
  }
  return [pscustomobject][ordered]@{bindings=@($pathMap.Values | Sort-Object output_path -CaseSensitive);omissions=@($omissions | Sort-Object -CaseSensitive)}
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
    target_overlay_sha256=[string]$state.overlay.record_sha256
    source_binding_count=@($selection.bindings).Count
    omission_count=@($selection.omissions).Count
    tree_path=$tree
    archive_path=$archive
    archive_sha256=[string]$inventory.archive_sha256
    content_sha256=[string]$inventory.content_sha256
    entry_count=[int]$inventory.entry_count
    invariants=[pscustomobject][ordered]@{no_historical_archive_input=$true;all_source_hashes_verified=$true;all_output_hashes_verified=$true;all_target_differences_explicit=$true;version_identity_verified=$true;canonical_package_authority=$true}
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
    if ([string]$a.archive_sha256 -cne [string]$b.archive_sha256 -or [string]$a.content_sha256 -cne [string]$b.content_sha256 -or [int]$a.entry_count -ne [int]$b.entry_count) { throw "[mir4-target-materializer-determinism] $target" }
    if ([string]$a.content_sha256 -cne [string]$identity.target_authority.baseline_content_sha256 -or
        [int]$a.entry_count -ne [int]$identity.target_authority.baseline_entry_count) { throw "[mir4-target-materializer-baseline-parity] $target" }
    $rows.Add([pscustomobject][ordered]@{target=$target;distribution_version=[string]$a.distribution_version;source_binding_count=[int]$a.source_binding_count;omission_count=[int]$a.omission_count;archive_a=[string]$a.archive_sha256;archive_b=[string]$b.archive_sha256;content_sha256=[string]$a.content_sha256;entry_count=[int]$a.entry_count;deterministic_archive_bytes=$true;composition_record_a=[string]$a.record_sha256;composition_record_b=[string]$b.record_sha256})
    $absoluteOutput = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot)) }
    Remove-MIR4BuildTree -OutputRoot $absoluteOutput -Path (Split-Path -Parent ([string]$a.tree_path))
    Remove-MIR4BuildTree -OutputRoot $absoluteOutput -Path (Split-Path -Parent ([string]$b.tree_path))
  }
  $manifest = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'src/mod/package-source.json' -Kind 'MIR4PackageSourceManifestV1'
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
