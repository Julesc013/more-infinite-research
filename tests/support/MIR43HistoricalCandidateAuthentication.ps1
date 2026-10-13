Set-StrictMode -Version Latest

# Historical 4.3 player inputs are not canonical materializer targets.  Their
# reader therefore authenticates their bytes through the canonical f100 source
# selection plus the historical target record's adapters and patches.  It
# never accepts an archive/member hash supplied solely by the candidate
# manifest.

function Assert-MIR43HistoricalCandidateAuthentication {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "[mir43-historical-current-candidate] $Message" }
}

function Get-MIR43HistoricalCandidateAuthenticationProjection {
  param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target,
    [Parameter(Mandatory)][ValidateSet('4.3.0','4.3.1')][string]$SourceVersion
  )

  $repo = (Resolve-Path -LiteralPath $Repository).Path
  $writer = Join-Path $repo 'tools/commands/release/New-MIR42HistoricalPlaytestCandidate.ps1'
  Assert-MIR43HistoricalCandidateAuthentication (Test-Path -LiteralPath $writer -PathType Leaf) 'authentication projection authority is missing'
  # The command's projection mode is pure: it reads the currently admitted
  # source/target authorities and produces expected member identities without
  # materializing a tree or archive.
  $projection = @(& $writer -RepoRoot $repo -Target $Target -SourceVersion $SourceVersion -AuthenticationProjection)
  Assert-MIR43HistoricalCandidateAuthentication ($projection.Count -eq 1) 'authentication projection result differs'
  $value = $projection[0]
  Assert-MIR43HistoricalCandidateAuthentication (
    [int]$value.schema -eq 1 -and
    [string]$value.kind -ceq 'MIR42HistoricalCandidateAuthenticationProjectionV1' -and
    [string]$value.target -ceq $Target -and
    [string]$value.source_version -ceq $SourceVersion -and
    [string]$value.distribution_root -match '^more-infinite-research_4[.]3[.][0-9]{5}$' -and
    [string]$value.member_projection_sha256 -match '^[0-9A-F]{64}$' -and
    @($value.members).Count -gt 0
  ) 'authentication projection contract differs'
  return $value
}

# The source commit and tree in a historical construction receipt identify the
# committed baseline only.  They do not describe an uncommitted rewrite of a
# source binding and its self-consistent manifest.  Before using the pure
# projection, bind its governed inputs to tracked, clean files.  This is
# intentionally a derived list rather than a repository-wide cleanliness
# rule: unrelated test and harness work remains admissible.
function ConvertTo-MIR43HistoricalAuthorityRelativePath {
  param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Path
  )

  $repo = (Resolve-Path -LiteralPath $Repository).Path
  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw '[mir43-historical-current-candidate] authority input path differs'
  }
  $candidate = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  $full = [IO.Path]::GetFullPath($candidate)
  $prefix = $repo.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw '[mir43-historical-current-candidate] authority input escapes repository'
  }
  $relative = [IO.Path]::GetRelativePath($repo, $full).Replace('\', '/')
  if ([IO.Path]::IsPathRooted($relative) -or $relative -eq '.' -or $relative -match '(^|/)\.\.(/|$)') {
    throw '[mir43-historical-current-candidate] authority input path differs'
  }
  return $relative
}

function Assert-MIR43HistoricalAuthorityInputsClean {
  param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string[]]$RelativePaths
  )

  $repo = (Resolve-Path -LiteralPath $Repository).Path
  $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($path in @($RelativePaths)) {
    $relative = ConvertTo-MIR43HistoricalAuthorityRelativePath -Repository $repo -Path ([string]$path)
    if (-not $paths.Add($relative)) { continue }
  }
  if ($paths.Count -eq 0) {
    throw '[mir43-historical-current-candidate] authority input set differs'
  }
  $ordered = @($paths | Sort-Object -CaseSensitive)
  foreach ($relative in $ordered) {
    $full = Join-Path $repo $relative
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
      throw "[mir43-historical-current-candidate] authority input missing: $relative"
    }
  }

  # Keep the operating-system command line bounded while avoiding a Git
  # process per bound source.  The largest current f100 selection has a few
  # hundred paths, so batches of 64 retain prompt native-reader admission.
  function Invoke-MIR43HistoricalAuthorityGitPathQuery {
    param([string[]]$Arguments)
    $rows = [Collections.Generic.List[string]]::new()
    for ($offset = 0; $offset -lt $ordered.Count; $offset += 64) {
      $last = [Math]::Min($offset + 63, $ordered.Count - 1)
      $batch = @($ordered[$offset..$last])
      $output = @(& git -C $repo @Arguments -- @batch 2>$null)
      $exitCode = $LASTEXITCODE
      if ($exitCode -ne 0) {
        throw '[mir43-historical-current-candidate] authority input status unavailable'
      }
      foreach ($row in $output) { $rows.Add(([string]$row).Replace('\', '/')) }
    }
    return @($rows)
  }

  $tracked = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($path in @(Invoke-MIR43HistoricalAuthorityGitPathQuery -Arguments @('ls-files'))) { [void]$tracked.Add($path) }
  foreach ($relative in $ordered) {
    if (-not $tracked.Contains($relative)) {
      throw "[mir43-historical-current-candidate] authority input is not tracked: $relative"
    }
  }
  # Comparing the worktree to HEAD covers both index and working-tree changes.
  # A self-hashed dirty manifest therefore cannot authenticate a dirty bound
  # player source under the unchanged HEAD/tree identifiers.
  $dirty = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($path in @(Invoke-MIR43HistoricalAuthorityGitPathQuery -Arguments @('diff','--name-only','--no-renames','HEAD'))) { [void]$dirty.Add($path) }
  foreach ($relative in $ordered) {
    if ($dirty.Contains($relative)) {
      throw "[mir43-historical-current-candidate] authority input is dirty: $relative"
    }
  }
  $untracked = @(Invoke-MIR43HistoricalAuthorityGitPathQuery -Arguments @('ls-files','--others','--exclude-standard'))
  if ($untracked.Count -ne 0) {
    throw "[mir43-historical-current-candidate] authority input is untracked: $([string]$untracked[0])"
  }
  return $ordered
}

function Get-MIR43HistoricalCandidateAuthorityInputPaths {
  param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target
  )

  $repo = (Resolve-Path -LiteralPath $Repository).Path
  $state = Get-MIR4TargetMaterializerState -RepoRoot $repo -Target f100
  $selection = Get-MIR4TargetMaterializationBindings -State $state
  $targetRecordPath = "targets/historical/$Target/target.json"
  $targetRecord = Get-Content -LiteralPath (Join-Path $repo $targetRecordPath) -Raw | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR43HistoricalCandidateAuthentication (
    [string]$targetRecord.target -ceq $Target -and
    [string]$targetRecord.base_materializer_target -ceq 'f100'
  ) 'authority target record differs'

  $inputs = [Collections.Generic.List[string]]::new()
  # Canonical authority validates all four registered composition records,
  # not merely f100, before returning the f100 materializer state.
  $inputs.Add('targets/package-authority.json')
  $inputs.Add([string]$state.authority.source_manifest.path)
  $inputs.Add([string]$state.authority.target_registry.path)
  $inputs.Add([string]$state.authority.support_policy.path)
  $inputs.Add([string]$state.authority.versioning_authority.path)
  foreach ($targetRow in @($state.registry.targets)) {
    $inputs.Add([string]$targetRow.composition)
    $inputs.Add([string]$targetRow.support_policy)
  }
  # These schemas participate in the canonical record admission that the
  # projection relies on.  The historical record is bounded by its own record
  # hash and field contract in the projection command.
  foreach ($schema in @(
    'spec/schemas/mir4-canonical-package-authority-v2.schema.json',
    'spec/schemas/mir4-composable-package-source-v3.schema.json',
    'spec/schemas/mir4-target-registry-v2.schema.json',
    'spec/schemas/mir4-target-support-policy-v1.schema.json',
    'spec/schemas/mir4-target-composition-v2.schema.json'
  )) {
    $inputs.Add($schema)
  }
  foreach ($binding in @($selection.bindings)) {
    $inputs.Add([string]$binding.source_path)
  }
  $inputs.Add($targetRecordPath)
  foreach ($adapter in @($targetRecord.adapter_files)) {
    $inputs.Add([string]$adapter.source_path)
  }
  # These are the exact command/module implementations that calculate and
  # validate the byte projection.  They are authority code, unlike unrelated
  # harness scripts and tests.
  foreach ($implementation in @(
    'tools/commands/release/New-MIR42HistoricalPlaytestCandidate.ps1',
    'tools/mir/application/package/TargetMaterializer.ps1',
    'tools/mir/application/package/PackageAuthority.ps1',
    'tools/lib/mir4/BootstrapMaterialization.ps1',
    'tools/lib/validation/MIR4DistributionIdentity.ps1',
    'tools/lib/validation/PackageIdentity.ps1'
  )) {
    $inputs.Add($implementation)
  }
  return Assert-MIR43HistoricalAuthorityInputsClean -Repository $repo -RelativePaths @($inputs)
}

# A self-hashed construction receipt is not custody of a particular combined
# candidate.  A caller that has already read the frozen target row supplies
# its exact descriptor here, binding both raw receipt bytes and record hash.
function Assert-MIR43HistoricalReceiptDescriptor {
  param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)]$Descriptor,
    [Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target
  )

  $fields = @($Descriptor.PSObject.Properties.Name)
  $expectedFields = @('path','bytes','sha256','record_sha256')
  Assert-MIR43HistoricalCandidateAuthentication (
    $fields.Count -eq $expectedFields.Count -and
    ((@($fields | Sort-Object -CaseSensitive) -join '|') -ceq (@($expectedFields | Sort-Object -CaseSensitive) -join '|'))
  ) 'candidate receipt descriptor shape differs'
  Assert-MIR43HistoricalCandidateAuthentication (
    [string]$Descriptor.path -ceq "materializations/$Target.json" -and
    [int64]$Descriptor.bytes -gt 0 -and
    [string]$Descriptor.sha256 -cmatch '^[0-9A-F]{64}$' -and
    [string]$Descriptor.record_sha256 -cmatch '^[0-9A-F]{64}$'
  ) 'candidate receipt descriptor differs'

  $identity = Get-MIR4RawFileIdentity -Path $ManifestPath
  Assert-MIR43HistoricalCandidateAuthentication (
    [int64]$identity.bytes -eq [int64]$Descriptor.bytes -and
    [string]$identity.sha256 -ceq [string]$Descriptor.sha256
  ) 'candidate receipt raw identity differs'
  $record = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR43HistoricalCandidateAuthentication (
    (Test-MIR4BootstrapRecordHash -Record $record) -and
    [string]$record.record_sha256 -ceq [string]$Descriptor.record_sha256
  ) 'candidate receipt record differs'

  return [pscustomobject][ordered]@{
    path = [string]$Descriptor.path
    bytes = [int64]$Descriptor.bytes
    sha256 = [string]$Descriptor.sha256
    record_sha256 = [string]$Descriptor.record_sha256
  }
}

function Read-MIR43HistoricalCurrentCandidate {
  param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target,
    [Parameter(Mandatory)][ValidateSet('4.3.0','4.3.1')][string]$SourceVersion,
    $ExpectedReceiptDescriptor = $null
  )

  $repo = (Resolve-Path -LiteralPath $Repository).Path
  . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
  . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
  $candidate = (Resolve-Path -LiteralPath $Archive).Path
  $manifestFile = (Resolve-Path -LiteralPath $ManifestPath).Path
  $receiptDescriptor = $null
  if ($null -ne $ExpectedReceiptDescriptor) {
    $receiptDescriptor = Assert-MIR43HistoricalReceiptDescriptor -ManifestPath $manifestFile -Descriptor $ExpectedReceiptDescriptor -Target $Target
  }
  $manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR43HistoricalCandidateAuthentication (Test-MIR4BootstrapRecordHash -Record $manifest) 'candidate manifest record hash differs'
  Assert-MIR43HistoricalCandidateAuthentication (
    [int]$manifest.schema -eq 1 -and
    [string]$manifest.kind -ceq 'MIR42HistoricalPlaytestCandidateManifestV1' -and
    [string]$manifest.status -ceq 'built-private-historical-unqualified' -and
    [string]$manifest.target -ceq $Target -and
    [string]$manifest.candidate_row.kind -ceq 'MIR42HistoricalCandidateRowV1' -and
    [string]$manifest.candidate_row.status -ceq 'deterministic-historical-candidate-construction-input-unqualified' -and
    [string]$manifest.candidate_row.target -ceq $Target -and
    [string]$manifest.candidate_row.source_version -ceq $SourceVersion -and
    [bool]$manifest.candidate_row.deterministic_archive_bytes -and
    [bool]$manifest.candidate_row.package_excluded_surface -and
    [string]$manifest.candidate_row.qualification -ceq 'not-performed-in-this-construction-record' -and
    [string]$manifest.candidate_row.technical_seal -ceq 'not-performed' -and
    [string]$manifest.candidate_row.signing -ceq 'not-performed' -and
    -not [bool]$manifest.candidate_row.public_output_authorized -and
    -not [bool]$manifest.candidate_row.publication_authorized -and
    -not [bool]$manifest.public_output_authorized -and
    -not [bool]$manifest.publication_authorized
  ) 'candidate manifest identity differs'

  $authorityInputs = Get-MIR43HistoricalCandidateAuthorityInputPaths -Repository $repo -Target $Target
  $projection = Get-MIR43HistoricalCandidateAuthenticationProjection -Repository $repo -Target $Target -SourceVersion $SourceVersion
  $head = (& git -C $repo rev-parse HEAD).Trim()
  $tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  Assert-MIR43HistoricalCandidateAuthentication ($LASTEXITCODE -eq 0 -and
    [string]$manifest.source.commit -ceq $head -and [string]$manifest.source.tree -ceq $tree -and
    [string]$manifest.source.commit -ceq [string]$projection.source.commit -and
    [string]$manifest.source.tree -ceq [string]$projection.source.tree -and
    [string]$manifest.candidate_row.source.commit -ceq [string]$projection.source.commit -and
    [string]$manifest.candidate_row.source.tree -ceq [string]$projection.source.tree -and
    [string]$manifest.factorio_line -ceq [string]$projection.factorio_line -and
    [string]$manifest.distribution_version -ceq [string]$projection.distribution_version -and
    [string]$manifest.candidate_row.distribution_version -ceq [string]$projection.distribution_version
  ) 'candidate source or distribution identity differs'
  Assert-MIR43HistoricalCandidateAuthentication (
    [string]$manifest.target_record.path -ceq [string]$projection.target_record.path -and
    [string]$manifest.target_record.sha256 -ceq [string]$projection.target_record.sha256 -and
    [string]$manifest.candidate_row.target_record.path -ceq [string]$projection.target_record.path -and
    [string]$manifest.candidate_row.target_record.sha256 -ceq [string]$projection.target_record.sha256
  ) 'candidate target record differs'
  Assert-MIR43HistoricalCandidateAuthentication (
    [string]$manifest.authentication_projection.kind -ceq 'MIR42HistoricalCandidateAuthenticationProjectionV1' -and
    [string]$manifest.authentication_projection.member_projection_sha256 -ceq [string]$projection.member_projection_sha256 -and
    [int]$manifest.authentication_projection.member_count -eq @($projection.members).Count -and
    [string]$manifest.authentication_projection.canonical_base.package_authority_sha256 -ceq [string]$projection.canonical_base.package_authority_sha256 -and
    [string]$manifest.authentication_projection.canonical_base.source_manifest_sha256 -ceq [string]$projection.canonical_base.source_manifest_sha256 -and
    [string]$manifest.authentication_projection.canonical_base.target_registry_sha256 -ceq [string]$projection.canonical_base.target_registry_sha256 -and
    [string]$manifest.authentication_projection.canonical_base.support_policy_sha256 -ceq [string]$projection.canonical_base.support_policy_sha256 -and
    [string]$manifest.authentication_projection.canonical_base.target_overlay_sha256 -ceq [string]$projection.canonical_base.target_overlay_sha256
  ) 'candidate canonical source authority differs'

  $expectedName = 'more-infinite-research_' + [string]$projection.distribution_version + '.zip'
  Assert-MIR43HistoricalCandidateAuthentication ([IO.Path]::GetFileName($candidate) -ceq $expectedName) 'candidate archive filename differs'
  $inventory = Get-MIR4ArchiveInventory -Path $candidate
  Assert-MIR43HistoricalCandidateAuthentication (
    [string]$inventory.root -ceq [string]$projection.distribution_root -and
    [string]$inventory.archive_sha256 -ceq [string]$manifest.distribution.sha256 -and
    [string]$inventory.archive_sha256 -ceq [string]$manifest.candidate_row.asset.sha256 -and
    [string]$inventory.archive_sha256 -ceq [string]$manifest.candidate_row.build_a_sha256 -and
    [string]$inventory.archive_sha256 -ceq [string]$manifest.candidate_row.build_b_sha256 -and
    [string]$inventory.content_sha256 -ceq [string]$manifest.distribution.content_sha256 -and
    [string]$inventory.content_sha256 -ceq [string]$manifest.candidate_row.content_sha256 -and
    [int]$inventory.entry_count -eq [int]$manifest.distribution.entry_count -and
    [int]$inventory.entry_count -eq [int]$manifest.candidate_row.entry_count
  ) 'candidate archive inventory differs'

  $actual = @{}
  foreach ($entry in @($inventory.entries)) {
    if ($actual.ContainsKey([string]$entry.path)) { throw '[mir43-historical-current-candidate] duplicate archive member differs' }
    $actual[[string]$entry.path] = $entry
  }
  $expected = @{}
  foreach ($entry in @($projection.members)) {
    $path = [string]$entry.path
    Assert-MIR43HistoricalCandidateAuthentication (-not $expected.ContainsKey($path)) 'projection member collision differs'
    $expected[$path] = $entry
  }
  Assert-MIR43HistoricalCandidateAuthentication ($actual.Count -eq $expected.Count) 'candidate package membership differs'
  foreach ($path in @($expected.Keys | Sort-Object -CaseSensitive)) {
    $actualEntry = $actual[$path]
    $expectedEntry = $expected[$path]
    Assert-MIR43HistoricalCandidateAuthentication ($null -ne $actualEntry -and
      [int64]$actualEntry.raw_bytes -eq [int64]$expectedEntry.bytes -and
      [string]$actualEntry.raw_sha256 -ceq [string]$expectedEntry.sha256) "candidate member differs: $path"
  }

  $info = Read-MIR4ArchiveText -Path $candidate -RelativePath 'info.json' | ConvertFrom-Json -Depth 20 -DateKind String
  Assert-MIR43HistoricalCandidateAuthentication (
    [string]$info.name -ceq 'more-infinite-research' -and
    [string]$info.version -ceq [string]$projection.distribution_version -and
    [string]$info.factorio_version -ceq [string]$projection.factorio_line
  ) 'candidate metadata differs'
  return [pscustomobject][ordered]@{
    path = $candidate
    receipt = $manifest.candidate_row
    manifest = $manifest
    projection = $projection
    inventory = $inventory
    authority_inputs = @($authorityInputs)
    receipt_custody = if ($null -ne $receiptDescriptor) { 'combined-candidate-bound' } else { 'standalone-projection-only' }
    receipt_descriptor = $receiptDescriptor
  }
}

# Focused archive-admission controls.  The caller supplies one writer-produced
# private archive and an empty, controlled scratch directory; this helper does
# not invoke a materializer or native engine.
function Invoke-MIR43HistoricalCurrentCandidateAuthenticationControls {
  param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target,
    [Parameter(Mandatory)][ValidateSet('4.3.0','4.3.1')][string]$SourceVersion,
    [Parameter(Mandatory)][string]$WorkRoot
  )

  $repo = (Resolve-Path -LiteralPath $Repository).Path
  # Archive inventory and record hashing are used to forge a self-consistent
  # caller manifest.  Import the canonical helpers in this caller scope: the
  # reader imports them only inside its own function scope.
  . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
  . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
  $inputArchive = (Resolve-Path -LiteralPath $Archive).Path
  $inputManifest = (Resolve-Path -LiteralPath $ManifestPath).Path
  $root = [IO.Path]::GetFullPath($WorkRoot)
  if (Test-Path -LiteralPath $root) { throw '[mir43-historical-current-candidate] controlled output already exists' }
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $script:mir43HistoricalCandidateAuthenticationControlAssertions = 0
  function Assert-MIR43HistoricalCandidateControlRejects {
    param([scriptblock]$Action,[string]$Needle)
    $failure = ''
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    if (-not $failure.Contains($Needle, [StringComparison]::Ordinal)) {
      throw "[mir43-historical-current-candidate] expected $Needle; got $failure"
    }
    $script:mir43HistoricalCandidateAuthenticationControlAssertions++
  }
  $script:mir43HistoricalCandidateAuthorityInputControlAssertions = 0
  function Assert-MIR43HistoricalCandidateAuthorityInputControlRejects {
    param([scriptblock]$Action,[string]$Needle)
    $failure = ''
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    if (-not $failure.Contains($Needle, [StringComparison]::Ordinal)) {
      throw "[mir43-historical-current-candidate] expected $Needle; got $failure"
    }
    $script:mir43HistoricalCandidateAuthorityInputControlAssertions++
  }
  $script:mir43HistoricalCandidateReceiptCustodyControlAssertions = 0
  function Assert-MIR43HistoricalCandidateReceiptCustodyControlRejects {
    param([scriptblock]$Action,[string]$Needle)
    $failure = ''
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    if (-not $failure.Contains($Needle, [StringComparison]::Ordinal)) {
      throw "[mir43-historical-current-candidate] expected $Needle; got $failure"
    }
    $script:mir43HistoricalCandidateReceiptCustodyControlAssertions++
  }
  try {
    $verified = Read-MIR43HistoricalCurrentCandidate -Repository $repo -Archive $inputArchive -ManifestPath $inputManifest -Target $Target -SourceVersion $SourceVersion
    if ([string]$verified.receipt.distribution_version -cne [string]$verified.projection.distribution_version) {
      throw '[mir43-historical-current-candidate] controlled accepted identity differs'
    }
    $script:mir43HistoricalCandidateAuthenticationControlAssertions++

    $inputReceipt = Get-Content -LiteralPath $inputManifest -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    $inputReceiptIdentity = Get-MIR4RawFileIdentity -Path $inputManifest
    $receiptDescriptor = [pscustomobject][ordered]@{
      path = "materializations/$Target.json"
      bytes = [int64]$inputReceiptIdentity.bytes
      sha256 = [string]$inputReceiptIdentity.sha256
      record_sha256 = [string]$inputReceipt.record_sha256
    }
    $boundVerified = Read-MIR43HistoricalCurrentCandidate -Repository $repo -Archive $inputArchive -ManifestPath $inputManifest -Target $Target -SourceVersion $SourceVersion -ExpectedReceiptDescriptor $receiptDescriptor
    if ([string]$boundVerified.receipt_custody -cne 'combined-candidate-bound' -or
        [string]$boundVerified.receipt_descriptor.sha256 -cne [string]$receiptDescriptor.sha256) {
      throw '[mir43-historical-current-candidate] controlled receipt custody differs'
    }
    $script:mir43HistoricalCandidateReceiptCustodyControlAssertions++
    foreach ($tamper in @('path','bytes','sha256','record_sha256')) {
      $forgedDescriptor = $receiptDescriptor | ConvertTo-Json -Depth 10 | ConvertFrom-Json -Depth 10 -DateKind String
      switch ($tamper) {
        'path' { $forgedDescriptor.path = "materializations/$Target-other.json" }
        'bytes' { $forgedDescriptor.bytes = [int64]$forgedDescriptor.bytes + 1 }
        'sha256' { $forgedDescriptor.sha256 = '0' * 64 }
        'record_sha256' { $forgedDescriptor.record_sha256 = '0' * 64 }
      }
      $needle = if ($tamper -ceq 'path') { 'candidate receipt descriptor differs' } elseif ($tamper -ceq 'record_sha256') { 'candidate receipt record differs' } else { 'candidate receipt raw identity differs' }
      Assert-MIR43HistoricalCandidateReceiptCustodyControlRejects {
        Read-MIR43HistoricalCurrentCandidate -Repository $repo -Archive $inputArchive -ManifestPath $inputManifest -Target $Target -SourceVersion $SourceVersion -ExpectedReceiptDescriptor $forgedDescriptor
      } $needle
    }
    $reformattedManifest = Join-Path $root 'reformatted-receipt.json'
    [IO.File]::WriteAllText($reformattedManifest, (($inputReceipt | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Assert-MIR43HistoricalCandidateReceiptCustodyControlRejects {
      Read-MIR43HistoricalCurrentCandidate -Repository $repo -Archive $inputArchive -ManifestPath $reformattedManifest -Target $Target -SourceVersion $SourceVersion -ExpectedReceiptDescriptor $receiptDescriptor
    } 'candidate receipt raw identity differs'

    $forgedArchive = Join-Path $root ([IO.Path]::GetFileName($inputArchive))
    $forgedManifest = Join-Path $root 'forged-player-byte.json'
    Copy-Item -LiteralPath $inputArchive -Destination $forgedArchive
    Copy-Item -LiteralPath $inputManifest -Destination $forgedManifest
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open($forgedArchive, [IO.Compression.ZipArchiveMode]::Update)
    try {
      $entry = $zip.GetEntry(([string]$verified.projection.distribution_root) + '/data.lua')
      if ($null -eq $entry) { throw '[mir43-historical-current-candidate] controlled data member missing' }
      $entry.Delete()
      $replacement = $zip.CreateEntry(([string]$verified.projection.distribution_root) + '/data.lua')
      $writer = [IO.StreamWriter]::new($replacement.Open(), [Text.UTF8Encoding]::new($false))
      try { $writer.Write("return { forged = true }`n") } finally { $writer.Dispose() }
    } finally { $zip.Dispose() }
    $forged = Get-Content -LiteralPath $forgedManifest -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    $forgedInventory = Get-MIR4ArchiveInventory -Path $forgedArchive
    $forged.distribution.sha256 = [string]$forgedInventory.archive_sha256
    $forged.distribution.content_sha256 = [string]$forgedInventory.content_sha256
    $forged.distribution.entry_count = [int]$forgedInventory.entry_count
    $forged.candidate_row.asset.bytes = [int64](Get-Item -LiteralPath $forgedArchive).Length
    $forged.candidate_row.asset.sha256 = [string]$forgedInventory.archive_sha256
    $forged.candidate_row.content_sha256 = [string]$forgedInventory.content_sha256
    $forged.candidate_row.entry_count = [int]$forgedInventory.entry_count
    $forged.candidate_row.build_a_sha256 = [string]$forgedInventory.archive_sha256
    $forged.candidate_row.build_b_sha256 = [string]$forgedInventory.archive_sha256
    $forged.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $forged
    [IO.File]::WriteAllText($forgedManifest, (($forged | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Assert-MIR43HistoricalCandidateControlRejects {
      Read-MIR43HistoricalCurrentCandidate -Repository $repo -Archive $forgedArchive -ManifestPath $forgedManifest -Target $Target -SourceVersion $SourceVersion
    } 'candidate member differs: data.lua'

    $forgedSourceManifest = Join-Path $root 'forged-source-pin.json'
    $forgedSource = Get-Content -LiteralPath $inputManifest -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    $forgedSource.source.tree = '0' * 40
    $forgedSource.candidate_row.source.tree = '0' * 40
    $forgedSource.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $forgedSource
    [IO.File]::WriteAllText($forgedSourceManifest, (($forgedSource | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Assert-MIR43HistoricalCandidateControlRejects {
      Read-MIR43HistoricalCurrentCandidate -Repository $repo -Archive $inputArchive -ManifestPath $forgedSourceManifest -Target $Target -SourceVersion $SourceVersion
    } 'candidate source or distribution identity differs'

    $forgedTargetManifest = Join-Path $root 'forged-target-pin.json'
    $forgedTarget = Get-Content -LiteralPath $inputManifest -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    $forgedTarget.target_record.sha256 = '0' * 64
    $forgedTarget.candidate_row.target_record.sha256 = '0' * 64
    $forgedTarget.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $forgedTarget
    [IO.File]::WriteAllText($forgedTargetManifest, (($forgedTarget | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Assert-MIR43HistoricalCandidateControlRejects {
      Read-MIR43HistoricalCurrentCandidate -Repository $repo -Archive $inputArchive -ManifestPath $forgedTargetManifest -Target $Target -SourceVersion $SourceVersion
    } 'candidate target record differs'

    # This isolated Git repository exercises the authority guard without
    # touching governed player sources in the checkout running the release
    # test.  The changed source and rehashed manifest deliberately retain the
    # same committed HEAD/tree identifiers.
    $authorityRepo = Join-Path $root 'authority-input-repository'
    New-Item -ItemType Directory -Force -Path (Join-Path $authorityRepo 'source'), (Join-Path $authorityRepo 'targets/historical/f017'), (Join-Path $authorityRepo 'tests') | Out-Null
    [IO.File]::WriteAllText((Join-Path $authorityRepo 'source/governed.lua'), 'return "clean"' + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $authorityRepo 'source/package-source.json'), '{"record_sha256":"clean"}' + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $authorityRepo 'targets/historical/f017/target.json'), '{"record_sha256":"clean"}' + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $authorityRepo 'tests/harness.txt'), 'clean' + "`n", [Text.UTF8Encoding]::new($false))
    & git -C $authorityRepo init --quiet
    if ($LASTEXITCODE -ne 0) { throw '[mir43-historical-current-candidate] authority control git init differs' }
    & git -C $authorityRepo config user.email 'mir-auth-control@example.invalid'
    if ($LASTEXITCODE -ne 0) { throw '[mir43-historical-current-candidate] authority control git email differs' }
    & git -C $authorityRepo config user.name 'MIR authentication control'
    if ($LASTEXITCODE -ne 0) { throw '[mir43-historical-current-candidate] authority control git name differs' }
    & git -C $authorityRepo config core.autocrlf false
    if ($LASTEXITCODE -ne 0) { throw '[mir43-historical-current-candidate] authority control git line-ending mode differs' }
    & git -C $authorityRepo add --all
    if ($LASTEXITCODE -ne 0) { throw '[mir43-historical-current-candidate] authority control git add differs' }
    & git -C $authorityRepo commit --quiet -m 'authority control baseline'
    if ($LASTEXITCODE -ne 0) { throw '[mir43-historical-current-candidate] authority control git commit differs' }
    $guarded = @('source/governed.lua', 'source/package-source.json', 'targets/historical/f017/target.json')
    $cleanInputs = Assert-MIR43HistoricalAuthorityInputsClean -Repository $authorityRepo -RelativePaths $guarded
    if (@($cleanInputs).Count -ne $guarded.Count) { throw '[mir43-historical-current-candidate] authority control clean inputs differ' }
    $script:mir43HistoricalCandidateAuthorityInputControlAssertions++

    [IO.File]::WriteAllText((Join-Path $authorityRepo 'source/governed.lua'), 'return "dirty"' + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $authorityRepo 'source/package-source.json'), '{"record_sha256":"self-rehashed-dirty"}' + "`n", [Text.UTF8Encoding]::new($false))
    Assert-MIR43HistoricalCandidateAuthorityInputControlRejects {
      Assert-MIR43HistoricalAuthorityInputsClean -Repository $authorityRepo -RelativePaths $guarded
    } 'authority input is dirty: source/governed.lua'
    & git -C $authorityRepo checkout -- source/governed.lua source/package-source.json | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '[mir43-historical-current-candidate] authority control git restore source differs' }

    [IO.File]::WriteAllText((Join-Path $authorityRepo 'targets/historical/f017/target.json'), '{"record_sha256":"self-rehashed-staged"}' + "`n", [Text.UTF8Encoding]::new($false))
    & git -C $authorityRepo add -- targets/historical/f017/target.json
    if ($LASTEXITCODE -ne 0) { throw '[mir43-historical-current-candidate] authority control git stage target differs' }
    Assert-MIR43HistoricalCandidateAuthorityInputControlRejects {
      Assert-MIR43HistoricalAuthorityInputsClean -Repository $authorityRepo -RelativePaths $guarded
    } 'authority input is dirty: targets/historical/f017/target.json'
    & git -C $authorityRepo reset --hard HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '[mir43-historical-current-candidate] authority control git reset target differs' }

    [IO.File]::WriteAllText((Join-Path $authorityRepo 'source/untracked-governed.lua'), 'return "untracked"' + "`n", [Text.UTF8Encoding]::new($false))
    Assert-MIR43HistoricalCandidateAuthorityInputControlRejects {
      Assert-MIR43HistoricalAuthorityInputsClean -Repository $authorityRepo -RelativePaths @('source/untracked-governed.lua')
    } 'authority input is not tracked: source/untracked-governed.lua'

    [IO.File]::WriteAllText((Join-Path $authorityRepo 'tests/unrelated-harness.txt'), 'dirty-but-not-authority' + "`n", [Text.UTF8Encoding]::new($false))
    $unrelatedAllowed = Assert-MIR43HistoricalAuthorityInputsClean -Repository $authorityRepo -RelativePaths $guarded
    if (@($unrelatedAllowed).Count -ne $guarded.Count) { throw '[mir43-historical-current-candidate] authority control unrelated harness differs' }
    $script:mir43HistoricalCandidateAuthorityInputControlAssertions++
  } finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  }
  return [pscustomobject][ordered]@{
    status = 'passed'
    assertions = $script:mir43HistoricalCandidateAuthenticationControlAssertions
    authority_input_assertions = $script:mir43HistoricalCandidateAuthorityInputControlAssertions
    receipt_custody_assertions = $script:mir43HistoricalCandidateReceiptCustodyControlAssertions
    native_factorio = $false
    package_materialization = $false
  }
}
