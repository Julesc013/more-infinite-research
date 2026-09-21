Set-StrictMode -Version Latest

$mir4FactorioOneSourceConvergenceAuthorityRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4FactorioOneSourceConvergenceAuthorityRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR4CanonicalPackageAuthority -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4FactorioOneSourceConvergenceAuthorityRoot 'tools/mir/application/package/PackageAuthority.ps1')
}
if (-not (Get-Command Invoke-MIR4CurrentSourceMaterializerProof -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4FactorioOneSourceConvergenceAuthorityRoot 'tools/mir/application/package/TargetMaterializer.ps1')
}
if (-not (Get-Command Get-MIR4FactorioOneSourceConvergenceProof -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4FactorioOneSourceConvergenceAuthorityRoot 'tools/mir/application/package/FactorioOneSourceConvergence.ps1')
}

function Get-MIR4FactorioOneSourceConvergenceAuthorityPolicy {
  return [ordered]@{
    authority_path = 'governance/repository/factorio-one-source-convergence-v1.json'
    authority_schema = 'contracts/repository/mir4-factorio-one-source-convergence-authority-v1.schema.json'
    receipt_path = 'assurance/repository/factorio-one-source-convergence-v1.json'
    receipt_schema = 'contracts/repository/mir4-factorio-one-source-convergence-receipt-v1.schema.json'
    layout_receipt_path = 'assurance/repository/composable-source-layout-receipt-v1.json'
    layout_receipt_schema = 'contracts/repository/mir4-composable-source-layout-migration-v1.schema.json'
    proof_schema = 'spec/schemas/mir4-factorio-one-source-convergence-proof-v1.schema.json'
    current_materializer_schema = 'spec/schemas/mir4-current-source-materializer-proof-v1.schema.json'
    proof_implementation = 'tools/mir/application/package/FactorioOneSourceConvergence.ps1'
    proof_test = 'tests/mir4/Test-MIR4FactorioOneSourceConvergenceM4202.ps1'
    baseline_revision = '297aa5cc902da96847165a4f9caa1048608839fb'
  }
}

function ConvertTo-MIR4FactorioOneSourceConvergenceCanonicalJson {
  param([Parameter(Mandatory)]$Value)
  return ConvertTo-MIR4BootstrapCanonicalJson -Value $Value
}

function Read-MIR4FactorioOneSourceConvergenceRecord {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$SchemaRelativePath,
    [Parameter(Mandatory)][string]$Code
  )
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[$Code-missing] $RelativePath" }
  $raw = Get-Content -Raw -LiteralPath $path
  $schemaValid = $false
  try { $schemaValid = [bool]($raw | Test-Json -SchemaFile (Join-Path $RepoRoot $SchemaRelativePath) -ErrorAction Stop) } catch { $schemaValid = $false }
  if (-not $schemaValid) { throw "[$Code-schema] $RelativePath" }
  return $raw | ConvertFrom-Json -Depth 100 -DateKind String
}

function Assert-MIR4FactorioOneSourceConvergenceGate {
  param([Parameter(Mandatory)]$Gate,[Parameter(Mandatory)][string]$Code)
  if (-not [bool]$Gate.development_merge -or
      @($Gate.PSObject.Properties | Where-Object { [string]$_.Name -ne 'development_merge' -and [bool]$_.Value }).Count -ne 0) {
    throw "[$Code]"
  }
}

function Get-MIR4FactorioOneSourceConvergenceAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4FactorioOneSourceConvergenceAuthorityPolicy
  $authority = Read-MIR4FactorioOneSourceConvergenceRecord -RepoRoot $repo -RelativePath $policy.authority_path -SchemaRelativePath $policy.authority_schema -Code 'mir4-factorio-one-convergence-authority'
  $expectedInvariants = @(
    'single-canonical-source-per-current-binding', 'no-factorio-one-whole-tree',
    'literal-require-closure-complete', 'factorio-two-executable-content-preserved-presentation-identity-evolved',
    'factorio-one-semantic-content-identities-changed', 'exact-factorio-one-engine-proof-required',
    'release-firewall'
  )
  if ([string]$authority.kind -cne 'MIR4FactorioOneSourceConvergenceAuthorityV1' -or
      [string]$authority.migration_id -cne 'MIR4-FACTORIO-ONE-SOURCE-CONVERGENCE-V1' -or
      [string]$authority.state -cne 'authorized-development-source-convergence' -or
      [string]$authority.predecessor.layout_receipt -cne $policy.layout_receipt_path -or
      [string]$authority.predecessor.source_layout_migration_id -cne 'MIR4-COMPOSABLE-SOURCE-LAYOUT-V1' -or
      [string]$authority.proof.implementation -cne $policy.proof_implementation -or
      [string]$authority.proof.schema -cne $policy.proof_schema -or
      [string]$authority.proof.test -cne $policy.proof_test -or
      [string]$authority.proof.baseline_revision -cne $policy.baseline_revision -or
      (@($authority.required_invariants) -join '|') -cne ($expectedInvariants -join '|') -or
      [string]$authority.rollback -cne 'Revert the exact Factorio-1 convergence change set and restore the immutable composable-source-layout receipt; do not recreate a parallel Factorio-1 source tree as a compatibility shortcut.') {
    throw '[mir4-factorio-one-convergence-authority-binding]'
  }
  Assert-MIR4FactorioOneSourceConvergenceGate -Gate $authority.transition_gate -Code 'mir4-factorio-one-convergence-authority-gate'
  return $authority
}

function Get-MIR4FactorioOneSourceConvergenceStaticProof {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4FactorioOneSourceConvergenceAuthorityPolicy
  $proof = Get-MIR4FactorioOneSourceConvergenceProof -RepoRoot $repo -BaselineRevision $policy.baseline_revision
  $json = ConvertTo-MIR4FactorioOneSourceConvergenceCanonicalJson -Value $proof
  $schemaValid = $false
  try { $schemaValid = [bool]($json | Test-Json -SchemaFile (Join-Path $repo $policy.proof_schema) -ErrorAction Stop) } catch { $schemaValid = $false }
  if (-not $schemaValid -or -not (Test-MIR4BootstrapRecordHash -Record $proof) -or
      [string]$proof.status -cne 'passed-static-source-convergence-engine-proof-required' -or
      [string]$proof.baseline_revision -cne $policy.baseline_revision -or
      [int]$proof.historical_characterization.factorio_one_pair_count -ne 81 -or
      [int]$proof.current_source.binding_count -ne 359 -or
      [int]$proof.current_source.physical_source_count -ne 359 -or
      [bool]$proof.current_source.whole_factorio_one_tree_present -or
      -not [bool]$proof.exact_engine_proof_required -or [bool]$proof.release_transition_authority) {
    throw '[mir4-factorio-one-convergence-static-proof]'
  }
  foreach ($target in @('f110','f100')) {
    $row = @($proof.targets | Where-Object { [string]$_.target -ceq $target })
    if ($row.Count -ne 1 -or [int]$row[0].binding_count -ne 277 -or [int]$row[0].omission_count -ne 57 -or
        @($row[0].unresolved_literal_requires).Count -ne 0 -or @($row[0].unsupported_bitwise_or_integer_division_sources).Count -ne 0) {
      throw "[mir4-factorio-one-convergence-static-proof-target] $target"
    }
  }
  return $proof
}

function Get-MIR4FactorioOneSourceConvergenceCurrentAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $manifest = Read-MIR4FactorioOneSourceConvergenceRecord -RepoRoot $repo -RelativePath 'source/package-source.json' -SchemaRelativePath 'spec/schemas/mir4-composable-package-source-v3.schema.json' -Code 'mir4-factorio-one-convergence-manifest'
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $registry = Read-MIR4FactorioOneSourceConvergenceRecord -RepoRoot $repo -RelativePath 'targets/registry.json' -SchemaRelativePath 'spec/schemas/mir4-target-registry-v2.schema.json' -Code 'mir4-factorio-one-convergence-registry'
  if (-not (Test-MIR4BootstrapRecordHash -Record $manifest) -or -not (Test-MIR4BootstrapRecordHash -Record $authority) -or -not (Test-MIR4BootstrapRecordHash -Record $registry) -or
      [string]$manifest.kind -cne 'MIR4ComposablePackageSourceV3' -or [string]$manifest.source_state -cne 'canonical-composable-package-source' -or
      [string]$authority.writer.implementation -cne 'tools/mir/application/package/TargetMaterializer.ps1' -or
      [string]$authority.source_manifest.path -cne 'source/package-source.json') {
    throw '[mir4-factorio-one-convergence-current-authority]'
  }
  $compositions = [Collections.Generic.List[object]]::new()
  foreach ($target in @('f210','f200','f110','f100')) {
    $relative = "targets/$target/composition.json"
    $composition = Read-MIR4FactorioOneSourceConvergenceRecord -RepoRoot $repo -RelativePath $relative -SchemaRelativePath 'spec/schemas/mir4-target-composition-v2.schema.json' -Code 'mir4-factorio-one-convergence-composition'
    if (-not (Test-MIR4BootstrapRecordHash -Record $composition) -or [string]$composition.target -cne $target) { throw "[mir4-factorio-one-convergence-composition-record] $target" }
    $compositions.Add([pscustomobject][ordered]@{target=$target;path=$relative;record_sha256=[string]$composition.record_sha256})
  }
  return [pscustomobject][ordered]@{
    source_root = 'source'
    package_source_fingerprint_sha256 = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
    manifest = [pscustomobject][ordered]@{path='source/package-source.json';kind=[string]$manifest.kind;record_sha256=[string]$manifest.record_sha256}
    package_authority = [pscustomobject][ordered]@{path='targets/package-authority.json';kind=[string]$authority.kind;record_sha256=[string]$authority.record_sha256}
    target_registry = [pscustomobject][ordered]@{path='targets/registry.json';kind=[string]$registry.kind;record_sha256=[string]$registry.record_sha256}
    target_compositions = @($compositions)
    sole_writer = [string]$authority.writer.implementation
  }
}

function Get-MIR4FactorioOneSourceConvergencePredecessorLayout {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4FactorioOneSourceConvergenceAuthorityPolicy
  $layout = Read-MIR4FactorioOneSourceConvergenceRecord -RepoRoot $repo -RelativePath $policy.layout_receipt_path -SchemaRelativePath $policy.layout_receipt_schema -Code 'mir4-factorio-one-convergence-layout'
  if (-not (Test-MIR4BootstrapRecordHash -Record $layout) -or [string]$layout.kind -cne 'MIR4ComposableSourceLayoutMigrationV1' -or
      [string]$layout.migration_id -cne 'MIR4-COMPOSABLE-SOURCE-LAYOUT-V1' -or -not [bool]$layout.invariants.package_bytes_unchanged) {
    throw '[mir4-factorio-one-convergence-layout-record]'
  }
  $expected = [ordered]@{
    f210 = '56670789F9A759EC81B09214C996B58F07A072B49D5B161228618226A778C852|337'
    f200 = '0FF10FEA35841F9484735C76ECF37F8D52D0AD723D5C66DD693096FAA5891D82|335'
    f110 = 'A95978CA68F33C1685DB0C420B7EF4F50155642D666CEE3ECB9D38FB59078132|174'
    f100 = 'CC6ED492EC3F79A6838DF48D9D8AF304A6B4A4BAF706E27F18EB468C844588D8|174'
  }
  foreach ($target in $expected.Keys) {
    $row = @($layout.target_parity | Where-Object { [string]$_.target -ceq $target })
    if ($row.Count -ne 1 -or "$($row[0].content_sha256)|$($row[0].entry_count)" -cne $expected[$target] -or -not [bool]$row[0].deterministic_archive_bytes) {
      throw "[mir4-factorio-one-convergence-layout-identity] $target"
    }
  }
  return $layout
}

function Get-MIR4FactorioTwoPinnedTargetBindings {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$BaselineRevision,
    [Parameter(Mandatory)][ValidateSet('f210','f200')][string]$Target
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
  $manifestRelative = 'source/package-source.json'
  $manifestRaw = $strictUtf8.GetString((Read-MIR4GitBlobBytes -RepoRoot $repo -Commit $BaselineRevision -RelativePath $manifestRelative))
  try { $manifest = $manifestRaw | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw "[mir4-factorio-two-executable-preservation-baseline-manifest-json] $Target" }
  if ([string]$manifest.kind -cne 'MIR4ComposablePackageSourceV2' -or
      [string]$manifest.source_state -cne 'canonical-composable-package-source' -or
      [string]$manifest.materializer_abi -cne 'mir4-target-materializer/1' -or
      @($manifest.bindings).Count -ne 447 -or
      -not (Test-MIR4BootstrapRecordHash -Record $manifest)) {
    throw "[mir4-factorio-two-executable-preservation-baseline-manifest-record] $Target"
  }

  $compositionRelative = "targets/$Target/composition.json"
  $compositionRaw = $strictUtf8.GetString((Read-MIR4GitBlobBytes -RepoRoot $repo -Commit $BaselineRevision -RelativePath $compositionRelative))
  try { $composition = $compositionRaw | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw "[mir4-factorio-two-executable-preservation-baseline-composition-json] $Target" }
  if ([string]$composition.target -cne $Target -or
      [string]$composition.materializer_abi -cne [string]$manifest.materializer_abi -or
      -not (Test-MIR4BootstrapRecordHash -Record $composition)) {
    throw "[mir4-factorio-two-executable-preservation-baseline-composition-record] $Target"
  }

  $bindingsByOutput = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($binding in @($manifest.bindings | Where-Object { $Target -in @($_.target_scope) } | Sort-Object output_path -CaseSensitive)) {
    $outputPath = [string]$binding.output_path
    Assert-MIR4PortableArchivePath -Path $outputPath
    if (-not $bindingsByOutput.TryAdd($outputPath, $binding)) {
      throw "[mir4-factorio-two-executable-preservation-baseline-output-collision] $Target/$outputPath"
    }
  }
  if ($bindingsByOutput.Count -eq 0) { throw "[mir4-factorio-two-executable-preservation-baseline-empty] $Target" }

  $operationsByOutput = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($operation in @($composition.operations)) {
    $outputPath = [string]$operation.path
    Assert-MIR4PortableArchivePath -Path $outputPath
    if (-not $operationsByOutput.TryAdd($outputPath, $operation)) {
      throw "[mir4-factorio-two-executable-preservation-baseline-operation-collision] $Target/$outputPath"
    }
  }
  foreach ($entry in $bindingsByOutput.GetEnumerator()) {
    $binding = $entry.Value
    $outputPath = [string]$entry.Key
    $hasOperation = $operationsByOutput.ContainsKey($outputPath)
    if ([string]$binding.layer -ceq 'shared') {
      if ($hasOperation) { throw "[mir4-factorio-two-executable-preservation-baseline-shared-operation] $Target/$outputPath" }
      continue
    }
    if (-not $hasOperation) { throw "[mir4-factorio-two-executable-preservation-baseline-operation-closure] $Target/$outputPath" }
    $operation = $operationsByOutput[$outputPath]
    if ([string]$operation.operation -ceq 'omit' -or
        [string]$operation.source_path -cne [string]$binding.source_path -or
        [string]$operation.transform -cne [string]$binding.transform -or
        [string]$operation.semantic_class -cne [string]$binding.semantic_class -or
        [int64]$operation.expected_bytes -ne [int64]$binding.output_bytes -or
        [string]$operation.expected_sha256 -cne [string]$binding.output_sha256) {
      throw "[mir4-factorio-two-executable-preservation-baseline-operation-mismatch] $Target/$outputPath"
    }
  }
  foreach ($entry in $operationsByOutput.GetEnumerator()) {
    $outputPath = [string]$entry.Key
    $operation = $entry.Value
    if ([string]$operation.operation -ceq 'omit') {
      if ($bindingsByOutput.ContainsKey($outputPath)) { throw "[mir4-factorio-two-executable-preservation-baseline-omit] $Target/$outputPath" }
    } elseif (-not $bindingsByOutput.ContainsKey($outputPath)) {
      throw "[mir4-factorio-two-executable-preservation-baseline-unbound-operation] $Target/$outputPath"
    }
  }
  return [pscustomobject][ordered]@{
    manifest = $manifest
    composition = $composition
    bindings = @($bindingsByOutput.Values | Sort-Object output_path -CaseSensitive)
  }
}

function Get-MIR4FactorioTwoExecutableContentPreservationProof {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4FactorioOneSourceConvergenceAuthorityPolicy
  $allowedPresentationPath = 'README.md'
  $targetRows = [Collections.Generic.List[object]]::new()
  foreach ($target in @('f210', 'f200')) {
    $baseline = Get-MIR4FactorioTwoPinnedTargetBindings -RepoRoot $repo -BaselineRevision $policy.baseline_revision -Target $target
    $baselineByOutput = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($binding in @($baseline.bindings)) { [void]$baselineByOutput.Add([string]$binding.output_path, $binding) }
    $baselineBlobs = Read-MIR4GitBlobSet -RepoRoot $repo -Commit $policy.baseline_revision -RelativePath @($baseline.bindings.source_path)

    $state = Get-MIR4TargetMaterializerState -RepoRoot $repo -Target $target
    $selection = Get-MIR4TargetMaterializationBindings -State $state
    $currentByOutput = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($binding in @($selection.bindings)) {
      $outputPath = [string]$binding.output_path
      if (-not $currentByOutput.TryAdd($outputPath, $binding)) { throw "[mir4-factorio-two-executable-preservation-current-output-collision] $target/$outputPath" }
    }
    $baselineMemberSet = (@($baselineByOutput.Keys | Sort-Object -CaseSensitive) -join "`n")
    $currentMemberSet = (@($currentByOutput.Keys | Sort-Object -CaseSensitive) -join "`n")
    if ($baselineByOutput.Count -ne $currentByOutput.Count -or $baselineMemberSet -cne $currentMemberSet) {
      throw "[mir4-factorio-two-executable-preservation-member-set] $target"
    }

    $outputRoot = Join-Path $repo 'build/packages/factorio-two-executable-preservation-v1'
    $candidate = New-MIR4TargetPackage -RepoRoot $repo -Target $target -CandidateId 'M42-02-EXECUTABLE-PRESERVATION' -OutputRoot $outputRoot
    $candidateRoot = Split-Path -Parent ([string]$candidate.tree_path)
    try {
      $treeByOutput = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
      foreach ($item in @(Get-ChildItem -LiteralPath ([string]$candidate.tree_path) -File -Recurse)) {
        $outputPath = [IO.Path]::GetRelativePath([string]$candidate.tree_path, $item.FullName).Replace('\', '/')
        Assert-MIR4PortableArchivePath -Path $outputPath
        if (-not $treeByOutput.TryAdd($outputPath, $item.FullName)) { throw "[mir4-factorio-two-executable-preservation-tree-collision] $target/$outputPath" }
      }
      $actualTreeMemberSet = (@($treeByOutput.Keys | Sort-Object -CaseSensitive) -join "`n")
      $currentMemberSet = (@($currentByOutput.Keys | Sort-Object -CaseSensitive) -join "`n")
      if ($actualTreeMemberSet -cne $currentMemberSet) {
        throw "[mir4-factorio-two-executable-preservation-tree-member-set] $target"
      }

      $baselineMembers = [Collections.Generic.List[object]]::new()
      $currentMembers = [Collections.Generic.List[object]]::new()
      $presentationDelta = $null
      foreach ($outputPath in @($currentByOutput.Keys | Sort-Object -CaseSensitive)) {
        $currentBinding = $currentByOutput[$outputPath]
        $baselineBinding = $baselineByOutput[$outputPath]
        $baselineSourcePath = [string]$baselineBinding.source_path
        if (-not $baselineBlobs.ContainsKey($baselineSourcePath)) { throw "[mir4-factorio-two-executable-preservation-baseline-blob-missing] $target/$baselineSourcePath" }
        $baselineSourceBytes = $baselineBlobs[$baselineSourcePath]
        if ([int64]$baselineSourceBytes.Length -ne [int64]$baselineBinding.source_bytes -or
            (Get-MIR4Sha256Bytes -Bytes $baselineSourceBytes) -cne [string]$baselineBinding.source_sha256) {
          throw "[mir4-factorio-two-executable-preservation-baseline-source-identity] $target/$outputPath"
        }
        $baselineBytes = Get-MIR4PredecessorProofOutputBytes -Transform ([string]$baselineBinding.transform) -SourceBytes $baselineSourceBytes
        if ([int64]$baselineBytes.Length -ne [int64]$baselineBinding.output_bytes -or
            (Get-MIR4Sha256Bytes -Bytes $baselineBytes) -cne [string]$baselineBinding.output_sha256) {
          throw "[mir4-factorio-two-executable-preservation-baseline-output-identity] $target/$outputPath"
        }
        $currentBytes = [IO.File]::ReadAllBytes($treeByOutput[$outputPath])
        $currentExpectedBytes = Read-MIR4CanonicalSourceBindingBytes -State $state -Binding $currentBinding
        if (-not (Test-MIR4ExactByteSequence -Left $currentBytes -Right $currentExpectedBytes)) {
          throw "[mir4-factorio-two-executable-preservation-materialized-output-identity] $target/$outputPath"
        }
        if ($outputPath -ceq $allowedPresentationPath) {
          if ([string]$baselineBinding.semantic_class -cne 'package-documentation' -or
              [string]$currentBinding.semantic_class -cne 'package-documentation' -or
              [string]$baselineBinding.transform -cne 'exact-template-v1' -or
              [string]$currentBinding.transform -cne 'exact-template-v1' -or
              [string]$currentBinding.source_path -cne "source/presentation/$target/README.md.template" -or
              (Test-MIR4ExactByteSequence -Left $baselineBytes -Right $currentBytes)) {
            throw "[mir4-factorio-two-executable-preservation-presentation-delta] $target/$outputPath"
          }
          $presentationDelta = [pscustomobject][ordered]@{
            output_path = $outputPath
            baseline_bytes = [int]$baselineBytes.Length
            baseline_sha256 = Get-MIR4Sha256Bytes -Bytes $baselineBytes
            current_bytes = [int]$currentBytes.Length
            current_sha256 = Get-MIR4Sha256Bytes -Bytes $currentBytes
          }
          continue
        }
        if (-not (Test-MIR4ExactByteSequence -Left $baselineBytes -Right $currentBytes)) {
          throw "[mir4-factorio-two-executable-preservation-byte-difference] $target/$outputPath"
        }
        $baselineMembers.Add([pscustomobject][ordered]@{output_path=$outputPath;bytes=[int]$baselineBytes.Length;sha256=(Get-MIR4Sha256Bytes -Bytes $baselineBytes)})
        $currentMembers.Add([pscustomobject][ordered]@{output_path=$outputPath;bytes=[int]$currentBytes.Length;sha256=(Get-MIR4Sha256Bytes -Bytes $currentBytes)})
      }
      if ($null -eq $presentationDelta -or $baselineMembers.Count -ne ($currentByOutput.Count - 1) -or $currentMembers.Count -ne $baselineMembers.Count) {
        throw "[mir4-factorio-two-executable-preservation-delta-closure] $target"
      }
      $baselineDigest = Get-MIR4DomainSha256 -Domain 'mir4.factorio-two.executable-content.v1' -Fields ([ordered]@{target=$target;members=@($baselineMembers)})
      $currentDigest = Get-MIR4DomainSha256 -Domain 'mir4.factorio-two.executable-content.v1' -Fields ([ordered]@{target=$target;members=@($currentMembers)})
      if ($baselineDigest -cne $currentDigest) { throw "[mir4-factorio-two-executable-preservation-digest] $target" }
      $targetRows.Add([pscustomobject][ordered]@{
        target = $target
        baseline_entry_count = $baselineByOutput.Count
        current_entry_count = $currentByOutput.Count
        executable_entry_count = $currentMembers.Count
        allowed_presentation_delta_paths = @($allowedPresentationPath)
        baseline_executable_content_sha256 = $baselineDigest
        current_executable_content_sha256 = $currentDigest
        presentation_delta = $presentationDelta
        executable_content_preserved = $true
      })
    } finally {
      if (Test-Path -LiteralPath $candidateRoot -PathType Container) {
        Remove-MIR4BuildTree -OutputRoot $outputRoot -Path $candidateRoot
      }
    }
  }
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4FactorioTwoExecutableContentPreservationProofV1'
    status = 'passed-exact-pinned-predecessor-executable-content-preservation'
    baseline_revision = $policy.baseline_revision
    allowed_presentation_delta_paths = @($allowedPresentationPath)
    targets = @($targetRows)
    invariants = [pscustomobject][ordered]@{
      exact_pinned_predecessor_source_read = $true
      actual_current_packages_materialized = $true
      member_sets_equal = $true
      only_readme_presentation_content_changed = $true
      executable_content_preserved = $true
    }
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function Get-MIR4FactorioOneSourceConvergenceRecordedTargetIdentities {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  # The four-target materializer proof is already the selected layout proof.
  # This append-only receipt binds its exact checked identities; it does not
  # launch a second equivalent four-target materialization merely to rewrite
  # an authority record. The layout test is the execution owner.
  $layout = Get-MIR4FactorioOneSourceConvergencePredecessorLayout -RepoRoot $repo
  $expected = [ordered]@{
    f210 = 'BD5F3DF80B033FB1E0EC1CFD3C7DD31B8B053B135D96E3E5DCBF13C8A77137D6|337|presentation-only-content-change-executable-preserved|True|False'
    f200 = '04494C4EC3AF8A8C18E45DAAEFAE914C7E99F40C6E51EFC573AD22DA1A49E27B|335|presentation-only-content-change-executable-preserved|True|False'
    f110 = '73D29EF07F02B8C7AC267280B5551F094D35E7FA86496C8A3CB21C9061D4E89B|277|changed-semantic-content-exact-engine-proof-required|False|True'
    f100 = '1EE69576BD18F4062BE2428F04CF965191C542614852A75E1FB40FBF2AC5D780|277|changed-semantic-content-exact-engine-proof-required|False|True'
  }
  $identities = [Collections.Generic.List[object]]::new()
  foreach ($target in @('f210','f200','f110','f100')) {
    $segments = $expected[$target].Split('|')
    $relation = $segments[2]
    $executableContentPreserved = [bool]::Parse($segments[3])
    $engineRequired = [bool]::Parse($segments[4])
    $predecessor = @($layout.target_parity | Where-Object { [string]$_.target -ceq $target })
    if ($predecessor.Count -ne 1 -or
        (($relation -ceq 'presentation-only-content-change-executable-preserved') -and ([string]$predecessor[0].content_sha256 -ceq $segments[0] -or [int]$predecessor[0].entry_count -ne [int]$segments[1] -or -not $executableContentPreserved -or $engineRequired)) -or
        (($relation -ceq 'changed-semantic-content-exact-engine-proof-required') -and ([string]$predecessor[0].content_sha256 -ceq $segments[0] -or [int]$predecessor[0].entry_count -eq [int]$segments[1]))) {
      throw "[mir4-factorio-one-convergence-recorded-identity] $target"
    }
    $identities.Add([pscustomobject][ordered]@{
      target = $target
      content_sha256 = [string]$segments[0]
      entry_count = [int]$segments[1]
      predecessor_content_sha256 = [string]$predecessor[0].content_sha256
      predecessor_entry_count = [int]$predecessor[0].entry_count
      relation = $relation
      deterministic_archive_bytes = $true
      executable_content_preserved = $executableContentPreserved
      exact_engine_proof_required = $engineRequired
    })
  }
  return @($identities)
}

function New-MIR4FactorioOneSourceConvergenceReceipt {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$RecordedAt = '2026-09-16T00:43:00+10:00'
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4FactorioOneSourceConvergenceAuthorityPolicy
  $authority = Get-MIR4FactorioOneSourceConvergenceAuthority -RepoRoot $repo
  $layout = Get-MIR4FactorioOneSourceConvergencePredecessorLayout -RepoRoot $repo
  $staticProof = Get-MIR4FactorioOneSourceConvergenceStaticProof -RepoRoot $repo
  $factorioTwoExecutableContentProof = Get-MIR4FactorioTwoExecutableContentPreservationProof -RepoRoot $repo
  $current = Get-MIR4FactorioOneSourceConvergenceCurrentAuthority -RepoRoot $repo
  $identities = Get-MIR4FactorioOneSourceConvergenceRecordedTargetIdentities -RepoRoot $repo
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4FactorioOneSourceConvergenceReceiptV1'
    status = 'passed-static-factorio-one-source-convergence-exact-engine-proof-required'
    recorded_at = $RecordedAt
    migration_id = 'MIR4-FACTORIO-ONE-SOURCE-CONVERGENCE-V1'
    authority = [pscustomobject][ordered]@{path=$policy.authority_path;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $policy.authority_path))}
    predecessor_layout = [pscustomobject][ordered]@{path=$policy.layout_receipt_path;kind=[string]$layout.kind;record_sha256=[string]$layout.record_sha256}
    proof = [pscustomobject][ordered]@{implementation=$policy.proof_implementation;schema=$policy.proof_schema;test=$policy.proof_test;record_sha256=[string]$staticProof.record_sha256}
    factorio_two_executable_content_proof = [pscustomobject][ordered]@{
      kind = [string]$factorioTwoExecutableContentProof.kind
      status = [string]$factorioTwoExecutableContentProof.status
      baseline_revision = [string]$factorioTwoExecutableContentProof.baseline_revision
      record_sha256 = [string]$factorioTwoExecutableContentProof.record_sha256
    }
    current = $current
    target_content_identities = $identities
    invariants = [pscustomobject][ordered]@{
      source_layout_predecessor_immutable = $true
      whole_factorio_one_tree_removed = $true
      one_canonical_physical_source_per_binding = $true
      factorio_two_presentation_content_changed = $true
      factorio_two_executable_content_preserved = $true
      factorio_one_content_changed = $true
      factorio_one_exact_engine_proof_required = $true
      release_transition_authority = $false
    }
    transition_gate = [pscustomobject][ordered]@{development_merge=$true;private_build=$false;qualification=$false;technical_seal=$false;main_promotion=$false;version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  $json = ConvertTo-MIR4FactorioOneSourceConvergenceCanonicalJson -Value $record
  if (-not ($json | Test-Json -SchemaFile (Join-Path $repo $policy.receipt_schema))) { throw '[mir4-factorio-one-convergence-receipt-schema]' }
  return $record
}

function Read-MIR4FactorioOneSourceConvergenceReceipt {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4FactorioOneSourceConvergenceAuthorityPolicy
  $receipt = Read-MIR4FactorioOneSourceConvergenceRecord -RepoRoot $repo -RelativePath $policy.receipt_path -SchemaRelativePath $policy.receipt_schema -Code 'mir4-factorio-one-convergence-receipt'
  if (-not (Test-MIR4BootstrapRecordHash -Record $receipt) -or
      [string]$receipt.kind -cne 'MIR4FactorioOneSourceConvergenceReceiptV1' -or
      [string]$receipt.status -cne 'passed-static-factorio-one-source-convergence-exact-engine-proof-required') {
    throw '[mir4-factorio-one-convergence-receipt-integrity]'
  }
  return $receipt
}

function Assert-MIR4FactorioOneSourceConvergenceReceiptCurrent {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Receipt)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4FactorioOneSourceConvergenceAuthorityPolicy
  $authority = Get-MIR4FactorioOneSourceConvergenceAuthority -RepoRoot $repo
  $layout = Get-MIR4FactorioOneSourceConvergencePredecessorLayout -RepoRoot $repo
  $proof = Get-MIR4FactorioOneSourceConvergenceStaticProof -RepoRoot $repo
  $factorioTwoExecutableContentProof = Get-MIR4FactorioTwoExecutableContentPreservationProof -RepoRoot $repo
  $current = Get-MIR4FactorioOneSourceConvergenceCurrentAuthority -RepoRoot $repo
  if ([string]$Receipt.migration_id -cne 'MIR4-FACTORIO-ONE-SOURCE-CONVERGENCE-V1' -or
      [string]$Receipt.authority.path -cne $policy.authority_path -or
      [string]$Receipt.authority.sha256 -cne (Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $policy.authority_path)) -or
      [string]$Receipt.predecessor_layout.path -cne $policy.layout_receipt_path -or
      [string]$Receipt.predecessor_layout.kind -cne [string]$layout.kind -or
      [string]$Receipt.predecessor_layout.record_sha256 -cne [string]$layout.record_sha256 -or
      [string]$Receipt.proof.implementation -cne $policy.proof_implementation -or
      [string]$Receipt.proof.schema -cne $policy.proof_schema -or
      [string]$Receipt.proof.test -cne $policy.proof_test -or
      [string]$Receipt.proof.record_sha256 -cne [string]$proof.record_sha256 -or
      [string]$Receipt.factorio_two_executable_content_proof.kind -cne 'MIR4FactorioTwoExecutableContentPreservationProofV1' -or
      [string]$Receipt.factorio_two_executable_content_proof.status -cne 'passed-exact-pinned-predecessor-executable-content-preservation' -or
      [string]$Receipt.factorio_two_executable_content_proof.baseline_revision -cne $policy.baseline_revision -or
      [string]$Receipt.factorio_two_executable_content_proof.record_sha256 -cne [string]$factorioTwoExecutableContentProof.record_sha256 -or
      (ConvertTo-MIR4FactorioOneSourceConvergenceCanonicalJson -Value $Receipt.current) -cne (ConvertTo-MIR4FactorioOneSourceConvergenceCanonicalJson -Value $current)) {
    throw '[mir4-factorio-one-convergence-receipt-current-binding]'
  }
  Assert-MIR4FactorioOneSourceConvergenceGate -Gate $Receipt.transition_gate -Code 'mir4-factorio-one-convergence-receipt-gate'
  if (-not [bool]$Receipt.invariants.source_layout_predecessor_immutable -or
      -not [bool]$Receipt.invariants.whole_factorio_one_tree_removed -or
      -not [bool]$Receipt.invariants.one_canonical_physical_source_per_binding -or
      -not [bool]$Receipt.invariants.factorio_two_presentation_content_changed -or
      -not [bool]$Receipt.invariants.factorio_two_executable_content_preserved -or
      -not [bool]$Receipt.invariants.factorio_one_content_changed -or
      -not [bool]$Receipt.invariants.factorio_one_exact_engine_proof_required -or
      [bool]$Receipt.invariants.release_transition_authority) {
    throw '[mir4-factorio-one-convergence-receipt-firewall]'
  }
  $expected = [ordered]@{
    f210 = 'BD5F3DF80B033FB1E0EC1CFD3C7DD31B8B053B135D96E3E5DCBF13C8A77137D6|337|56670789F9A759EC81B09214C996B58F07A072B49D5B161228618226A778C852|337|presentation-only-content-change-executable-preserved|True|False'
    f200 = '04494C4EC3AF8A8C18E45DAAEFAE914C7E99F40C6E51EFC573AD22DA1A49E27B|335|0FF10FEA35841F9484735C76ECF37F8D52D0AD723D5C66DD693096FAA5891D82|335|presentation-only-content-change-executable-preserved|True|False'
    f110 = '73D29EF07F02B8C7AC267280B5551F094D35E7FA86496C8A3CB21C9061D4E89B|277|A95978CA68F33C1685DB0C420B7EF4F50155642D666CEE3ECB9D38FB59078132|174|changed-semantic-content-exact-engine-proof-required|False|True'
    f100 = '1EE69576BD18F4062BE2428F04CF965191C542614852A75E1FB40FBF2AC5D780|277|CC6ED492EC3F79A6838DF48D9D8AF304A6B4A4BAF706E27F18EB468C844588D8|174|changed-semantic-content-exact-engine-proof-required|False|True'
  }
  foreach ($target in @('f210','f200','f110','f100')) {
    $row = @($Receipt.target_content_identities | Where-Object { [string]$_.target -ceq $target })
    if ($row.Count -ne 1 -or -not [bool]$row[0].deterministic_archive_bytes -or
        "$($row[0].content_sha256)|$($row[0].entry_count)|$($row[0].predecessor_content_sha256)|$($row[0].predecessor_entry_count)|$($row[0].relation)|$($row[0].executable_content_preserved)|$($row[0].exact_engine_proof_required)" -cne $expected[$target]) {
      throw "[mir4-factorio-one-convergence-receipt-identity] $target"
    }
  }
  return $true
}

function Test-MIR4FactorioOneSourceConvergenceReceipt {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [object]$Receipt,
    [switch]$VerifyMaterialization
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if ($null -eq $Receipt) { $Receipt = Read-MIR4FactorioOneSourceConvergenceReceipt -RepoRoot $repo }
  $policy = Get-MIR4FactorioOneSourceConvergenceAuthorityPolicy
  $schemaValid = $false
  try { $schemaValid = [bool]((ConvertTo-MIR4FactorioOneSourceConvergenceCanonicalJson -Value $Receipt) | Test-Json -SchemaFile (Join-Path $repo $policy.receipt_schema) -ErrorAction Stop) } catch { $schemaValid = $false }
  if (-not $schemaValid) { throw '[mir4-factorio-one-convergence-receipt-schema]' }
  if (-not (Test-MIR4BootstrapRecordHash -Record $Receipt)) { throw '[mir4-factorio-one-convergence-receipt-hash]' }
  # V1 is frozen convergence evidence. Do not rebuild its F210/F200 equality
  # claim against a later semantic progression package or overwrite it.
  if ($VerifyMaterialization) { throw '[mir4-factorio-one-convergence-historical-materialization-not-current]' }
  if ([string]$Receipt.record_sha256 -cne '9821BD60F0E36F32DA9888477CD8F48674A5A0601AA16D06CF396266AD02AB47' -or
      [string]$Receipt.current.package_source_fingerprint_sha256 -cne '909D8F0F1CA8B59E42CFBED5C854734B57DE40308D2E05752BD8694E1EC1821E' -or
      -not [bool]$Receipt.invariants.factorio_two_executable_content_preserved -or
      [bool]$Receipt.invariants.release_transition_authority) {
    throw '[mir4-factorio-one-convergence-historical-integrity]'
  }
  return [pscustomobject][ordered]@{
    status = 'passed-historical-factorio-one-source-convergence'
    factorio_one_exact_engine_proof_required = $true
    release_transition_authority = $false
    record_sha256 = [string]$Receipt.record_sha256
  }
}
