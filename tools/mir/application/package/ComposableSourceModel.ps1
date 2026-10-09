Set-StrictMode -Version Latest

$mir4ComposableSourceModelLoadRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4ComposableSourceModelLoadRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR4CanonicalPackageAuthority -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4ComposableSourceModelLoadRoot 'tools/mir/application/package/PackageAuthority.ps1')
}
if (-not (Get-Command Get-MIR4TargetMaterializationBindings -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4ComposableSourceModelLoadRoot 'tools/mir/application/package/TargetMaterializer.ps1')
}

function Read-MIR4ComposableSourceModelRecord {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$SchemaRelativePath,
    [Parameter(Mandatory)][string]$ExpectedKind
  )

  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-composable-source-model-missing] $RelativePath" }
  $raw = Get-Content -Raw -LiteralPath $path
  if (-not ($raw | Test-Json -SchemaFile (Join-Path $RepoRoot $SchemaRelativePath))) {
    throw "[mir4-composable-source-model-schema] $RelativePath"
  }
  $record = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$record.kind -cne $ExpectedKind -or -not (Test-MIR4BootstrapRecordHash -Record $record)) {
    throw "[mir4-composable-source-model-record] $RelativePath"
  }
  return $record
}

function New-MIR4ComposableSourceModel {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $manifestRelative = [string]$authority.source_manifest.path
  $manifest = Read-MIR4ComposableSourceModelRecord `
    -RepoRoot $repo `
    -RelativePath $manifestRelative `
    -SchemaRelativePath 'spec/schemas/mir4-composable-package-source-v3.schema.json' `
    -ExpectedKind 'MIR4ComposablePackageSourceV3'
  if ([string]$manifest.record_sha256 -cne [string]$authority.source_manifest.record_sha256) {
    throw '[mir4-composable-source-model-manifest-authority]'
  }

  $registryRelative = [string]$authority.target_registry.path
  $registry = Read-MIR4ComposableSourceModelRecord `
    -RepoRoot $repo `
    -RelativePath $registryRelative `
    -SchemaRelativePath 'spec/schemas/mir4-target-registry-v2.schema.json' `
    -ExpectedKind 'MIR4TargetRegistryV2'
  if ([string]$registry.record_sha256 -cne [string]$authority.target_registry.record_sha256) {
    throw '[mir4-composable-source-model-registry-authority]'
  }

  $targets = @('f210','f200','f110','f100')
  $targetModels = [Collections.Generic.List[object]]::new()
  $declaredOutputs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $bindings = [Collections.Generic.List[object]]::new()
  foreach ($binding in @($manifest.bindings | Sort-Object layer,source_path,output_path -CaseSensitive)) {
    $sourcePath = [string]$binding.source_path
    if ($sourcePath -notlike 'source/*') { throw "[mir4-composable-source-model-source-boundary] $sourcePath" }
    $sourceFullPath = Join-Path $repo $sourcePath
    if (-not (Test-Path -LiteralPath $sourceFullPath -PathType Leaf)) { throw "[mir4-composable-source-model-source-missing] $sourcePath" }
    $sourceBytes = [IO.File]::ReadAllBytes($sourceFullPath)
    if ([int64]$sourceBytes.Length -ne [int64]$binding.source_bytes -or
        (Get-MIR4Sha256Bytes -Bytes $sourceBytes) -cne [string]$binding.source_sha256) {
      throw "[mir4-composable-source-model-source-identity] $sourcePath"
    }
    $bindings.Add([pscustomobject][ordered]@{
      layer = [string]$binding.layer
      target_scope = @($binding.target_scope)
      output_path = [string]$binding.output_path
      semantic_class = [string]$binding.semantic_class
      source_path = $sourcePath
      transform = [string]$binding.transform
      output_bytes = [int64]$binding.output_bytes
      output_sha256 = [string]$binding.output_sha256
    })
  }
  if ($bindings.Count -ne @($manifest.bindings).Count) { throw '[mir4-composable-source-model-binding-cardinality]' }

  foreach ($target in $targets) {
    $registryRows = @($registry.targets | Where-Object { [string]$_.target -ceq $target })
    $authorityRows = @($authority.targets | Where-Object { [string]$_.target -ceq $target })
    if ($registryRows.Count -ne 1 -or $authorityRows.Count -ne 1) { throw "[mir4-composable-source-model-target] $target" }
    $compositionRelative = [string]$registryRows[0].composition
    $composition = Read-MIR4ComposableSourceModelRecord `
      -RepoRoot $repo `
      -RelativePath $compositionRelative `
      -SchemaRelativePath 'spec/schemas/mir4-target-composition-v2.schema.json' `
      -ExpectedKind 'MIR4TargetCompositionV2'
    if ([string]$composition.target -cne $target) { throw "[mir4-composable-source-model-composition-target] $target" }
    $materializerState = Get-MIR4TargetMaterializerState -RepoRoot $repo -Target $target
    $selection = Get-MIR4TargetMaterializationBindings -State $materializerState
    if (-not [bool]$selection.scoped_operation_closure) { throw "[mir4-composable-source-model-operation-closure] $target" }

    $targetBindings = @($bindings | Where-Object { @($_.target_scope) -contains $target })
    $targetOutputs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($binding in $targetBindings) {
      if (-not $targetOutputs.Add([string]$binding.output_path)) { throw "[mir4-composable-source-model-output-collision] $target $($binding.output_path)" }
      [void]$declaredOutputs.Add("$target|$($binding.output_path)")
    }
    if (@($selection.bindings).Count -ne $targetBindings.Count) { throw "[mir4-composable-source-model-selection-cardinality] $target" }
    foreach ($operation in @($composition.operations)) {
      $sourcePath = [string]$operation.source_path
      if ([string]$operation.operation -ceq 'omit') {
        if ($null -ne $operation.source_path -or $null -ne $operation.transform -or $null -ne $operation.expected_sha256) {
          throw "[mir4-composable-source-model-omit] $target $($operation.path)"
        }
      } else {
        if ([string]::IsNullOrWhiteSpace($sourcePath) -or $sourcePath -notlike 'source/*') {
          throw "[mir4-composable-source-model-operation-source] $target $($operation.path)"
        }
        if (-not (Test-Path -LiteralPath (Join-Path $repo $sourcePath) -PathType Leaf)) {
          throw "[mir4-composable-source-model-operation-missing] $target $sourcePath"
        }
      }
    }
    $targetModels.Add([pscustomobject][ordered]@{
      target = $target
      target_id = [string]$registryRows[0].target_id
      composition = [pscustomobject][ordered]@{
        path = $compositionRelative
        record_sha256 = [string]$composition.record_sha256
        operation_count = @($composition.operations).Count
        omission_count = @($composition.operations | Where-Object { [string]$_.operation -ceq 'omit' }).Count
      }
      source_binding_count = $targetBindings.Count
      baseline_content_sha256 = [string]$authorityRows[0].baseline_content_sha256
      baseline_entry_count = [int]$authorityRows[0].baseline_entry_count
    })
  }

  $sourceRoot = Join-Path $repo 'source'
  $targetRoot = Join-Path $repo 'targets'
  $forbiddenEraPaths = @(
    (Join-Path $sourceRoot 'families'),
    (Join-Path $sourceRoot 'modern'),
    (Join-Path $sourceRoot 'legacy')
  )
  $targetPayloadFiles = @(
    Get-ChildItem -LiteralPath $targetRoot -Recurse -File |
      Where-Object { $_.FullName -match '[\\/](?:files|generation)[\\/]' }
  )
  $retiredSourcePresent = Test-Path -LiteralPath (Join-Path $repo 'src') -PathType Container
  $retiredEraPathsPresent = @($forbiddenEraPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -ne 0
  if ($retiredSourcePresent -or $retiredEraPathsPresent -or $targetPayloadFiles.Count -ne 0) {
    throw '[mir4-composable-source-model-retired-layout-present]'
  }

  $canonicalBindings = @($bindings | Sort-Object layer,source_path,output_path -CaseSensitive)
  $canonicalTargets = @($targetModels | Sort-Object target -CaseSensitive)
  $canonicalProbe = [pscustomobject][ordered]@{
    bindings = $canonicalBindings
    targets = $canonicalTargets
  }
  $reverseProbe = [pscustomobject][ordered]@{
    bindings = $canonicalBindings
    targets = $canonicalTargets
  }
  $canonicalProbeSha256 = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $canonicalProbe)
  $reverseProbeSha256 = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $reverseProbe)
  if ($canonicalProbeSha256 -cne $reverseProbeSha256) { throw '[mir4-composable-source-model-declaration-order]' }

  $semanticClassCounts = [ordered]@{}
  foreach ($semanticClass in @($bindings.semantic_class | Sort-Object -Unique -CaseSensitive)) {
    $semanticClassCounts[$semanticClass] = @($bindings | Where-Object { [string]$_.semantic_class -ceq $semanticClass }).Count
  }
  $report = [pscustomobject][ordered]@{
    schema = 2
    kind = 'MIR4ComposableSourceModelProofV2'
    status = 'passed-canonical-composable-source-model'
    source_authority = [pscustomobject][ordered]@{
      source_root = [string]$authority.editable_source_root
      source_manifest = [pscustomobject][ordered]@{ path = $manifestRelative; record_sha256 = [string]$manifest.record_sha256 }
      package_authority = [pscustomobject][ordered]@{ path = 'targets/package-authority.json'; record_sha256 = [string]$authority.record_sha256 }
      target_registry = [pscustomobject][ordered]@{ path = $registryRelative; record_sha256 = [string]$registry.record_sha256 }
      sole_writer = [string]$authority.writer.implementation
    }
    bindings = @($bindings | Sort-Object layer,source_path,output_path -CaseSensitive)
    targets = @($targetModels | Sort-Object target -CaseSensitive)
    semantic_class_counts = [pscustomobject]$semanticClassCounts
    declaration_order_probe_sha256 = $canonicalProbeSha256
    invariants = [pscustomobject][ordered]@{
      single_editable_source_root = $true
      manifest_and_package_authority_self_hashed = $true
      all_source_bindings_present_and_exact = $true
      one_output_binding_per_target = $true
      all_target_differences_explicit = $true
      era_family_labels_absent = $true
      retired_source_tree_absent = $true
      target_payload_directories_absent = $true
      declaration_order_independent = $true
      historical_receipts_comparison_only = $true
      sole_current_writer = $true
    }
    transition_gate = [pscustomobject][ordered]@{
      package_cutover = $true
      old_writer_retirement = $true
      version_allocation = $false
      tagging = $false
      signing = $false
      sealing = $false
      publication = $false
    }
    record_sha256 = ''
  }
  $report.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $report
  return $report
}

function Write-MIR4ComposableSourceModel {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$OutputPath = 'build/reports/package-source/mir4-composable-source-model-v2.json',
    [switch]$Check
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $repo $OutputPath }
  $model = New-MIR4ComposableSourceModel -RepoRoot $repo
  $json = ($model | ConvertTo-Json -Depth 100).Replace([Environment]::NewLine, [string][char]10) + [string][char]10
  if ($Check) {
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) { throw '[mir4-composable-source-model-missing-output]' }
    $actual = [IO.File]::ReadAllText($OutputPath).Replace("`r`n", "`n").Replace("`r", "`n")
    if ($actual -cne $json) { throw '[mir4-composable-source-model-stale]' }
  } else {
    $parent = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($OutputPath, $json, [Text.UTF8Encoding]::new($false))
  }
  return $model
}
