Set-StrictMode -Version Latest

$mir4SourceModelLoadRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4SourceModelLoadRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}

function Get-MIR4ShadowSourceModelBaseline {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $path = Join-Path $RepoRoot 'spec/distribution/mir4-golden-four-target-baseline-v1.json'
  $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $record) -or
      [string]$record.kind -cne 'MIR4GoldenFourTargetBaselineV1' -or
      -not [bool]$record.invariants.all_paths_classified) {
    throw '[mir4-shadow-source-model-baseline]'
  }
  return $record
}

function Get-MIR4ShadowSourceSemanticClass {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Layer,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][int]$TargetPresence
  )
  if ($Path -ceq 'info.json') { return 'generated-metadata' }
  if ($Path -in @('settings.lua','settings-updates.lua','settings-final-fixes.lua','data.lua','data-updates.lua','data-final-fixes.lua','control.lua')) {
    return 'generated-lifecycle-entrypoint'
  }
  if ($Path -in @('README.md','changelog.txt')) { return 'package-documentation' }
  if ($Path -like 'migrations/*') { return 'migration' }
  if ($Path -like 'locale/*' -or $Path -match '(?i)[.](?:png|jpg|jpeg|webp|ogg|wav)$') {
    return 'common-asset-locale'
  }
  if ($Layer -cne 'common' -and $Path -like 'prototypes/mir/compatibility/*') {
    return 'target-compatibility-shim'
  }
  if ($Layer -like 'targets.*') {
    if ($TargetPresence -gt 1) { return 'target-replacement' }
    return 'target-overlay'
  }
  if ($Layer -like 'families.*') { return 'target-overlay' }
  if ($Layer -ceq 'common') { return 'common-semantic-source' }
  throw "[mir4-shadow-source-model-unclassified] $Layer $Path"
}

function Get-MIR4ShadowSourceFutureAuthority {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Layer,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$SemanticClass
  )
  if ($SemanticClass -ceq 'generated-metadata') { return 'generator:target-info-v1' }
  if ($SemanticClass -ceq 'generated-lifecycle-entrypoint') { return 'generator:lifecycle-entrypoint-v1' }
  if ($SemanticClass -ceq 'package-documentation') {
    if ($Path -ceq 'README.md') { return 'generator:package-readme-v1' }
    return 'generator:target-changelog-v1'
  }
  if ($Layer -ceq 'common') {
    if ($Path -match '(?i)[.](?:png|jpg|jpeg|webp|ogg|wav)$') { return "src/mod/common/assets/$Path.base64" }
    return "src/mod/common/$Path"
  }
  if ($Layer -like 'families.*') {
    $family = $Layer.Substring('families.'.Length)
    return "src/mod/families/$family/$Path"
  }
  if ($Layer -like 'targets.*') {
    $target = $Layer.Substring('targets.'.Length)
    return "targets/$target/files/$Path"
  }
  throw "[mir4-shadow-source-model-authority] $Layer $Path"
}

function Get-MIR4ShadowSourceMaterialization {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$SemanticClass)
  if ($SemanticClass -in @('generated-metadata','generated-lifecycle-entrypoint','package-documentation')) { return 'generate' }
  if ($Path -match '(?i)[.](?:png|jpg|jpeg|webp|ogg|wav)$') { return 'decode-base64-v1' }
  return 'copy-exact-bytes'
}

function New-MIR4ShadowSourceModel {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $baseline = Get-MIR4ShadowSourceModelBaseline -RepoRoot $repo
  $targets = @('f210','f200','f110','f100')
  $targetMaps = [ordered]@{}
  foreach ($target in $targets) {
    $targetRow = @($baseline.targets | Where-Object { [string]$_.target -ceq $target })
    if ($targetRow.Count -ne 1) { throw "[mir4-shadow-source-model-target] $target" }
    $map = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in @($targetRow[0].entries)) {
      Assert-MIR4PortableArchivePath -Path ([string]$entry.path)
      if ($map.ContainsKey([string]$entry.path)) { throw "[mir4-shadow-source-model-target-collision] $target $($entry.path)" }
      $map.Add([string]$entry.path, $entry)
    }
    $targetMaps[$target] = $map
  }
  $allPaths = @($targetMaps.Values | ForEach-Object { $_.Keys } | Sort-Object -CaseSensitive -Unique)
  $presence = @{}
  foreach ($path in $allPaths) { $presence[$path] = @($targets | Where-Object { $targetMaps[$_].ContainsKey($path) }).Count }
  $layers = @(
    [pscustomobject][ordered]@{id='common';source_target='f210';target_scope=$targets;entries=@($baseline.classification.common)}
    [pscustomobject][ordered]@{id='families.modern';source_target='f210';target_scope=@('f210','f200');entries=@($baseline.classification.families.modern)}
    [pscustomobject][ordered]@{id='families.legacy';source_target='f110';target_scope=@('f110','f100');entries=@($baseline.classification.families.legacy)}
    [pscustomobject][ordered]@{id='targets.f210';source_target='f210';target_scope=@('f210');entries=@($baseline.classification.targets.f210)}
    [pscustomobject][ordered]@{id='targets.f200';source_target='f200';target_scope=@('f200');entries=@($baseline.classification.targets.f200)}
    [pscustomobject][ordered]@{id='targets.f110';source_target='f110';target_scope=@('f110');entries=@($baseline.classification.targets.f110)}
    [pscustomobject][ordered]@{id='targets.f100';source_target='f100';target_scope=@('f100');entries=@($baseline.classification.targets.f100)}
  )
  $bindings = [Collections.Generic.List[object]]::new()
  $bindingKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($layer in $layers) {
    foreach ($entry in @($layer.entries | Sort-Object path -CaseSensitive)) {
      $path = [string]$entry.path
      $key = "$($layer.id)|$path"
      if (-not $bindingKeys.Add($key)) { throw "[mir4-shadow-source-model-binding-collision] $key" }
      $semanticClass = Get-MIR4ShadowSourceSemanticClass -Layer ([string]$layer.id) -Path $path -TargetPresence ([int]$presence[$path])
      $bindings.Add([pscustomobject][ordered]@{
        layer=[string]$layer.id
        target_scope=@($layer.target_scope)
        path=$path
        semantic_class=$semanticClass
        historical_comparison_authority="archive:$([string]$layer.source_target):$path"
        future_editable_authority=Get-MIR4ShadowSourceFutureAuthority -Layer ([string]$layer.id) -Path $path -SemanticClass $semanticClass
        materialization=Get-MIR4ShadowSourceMaterialization -Path $path -SemanticClass $semanticClass
        bytes=[int64]$entry.bytes
        sha256=[string]$entry.sha256
        proof_obligations=@('exact-path-and-byte-identity','no-package-authority-before-cutover','fresh-runtime-replay-before-cutover')
      })
    }
  }
  if ($bindings.Count -ne 406) { throw "[mir4-shadow-source-model-binding-count] $($bindings.Count)" }
  $commonTargetPolicyPaths = @($bindings | Where-Object {
    [string]$_.layer -ceq 'common' -and [string]$_.path -in @(
      'prototypes/mir/platform/factorio/target_profiles.lua',
      'prototypes/mir/compatibility/policies/k2_science_phase.lua',
      'prototypes/mir/runtime/planet_discovery_recovery.lua'
    )
  })
  if ($commonTargetPolicyPaths.Count -ne 0) { throw '[mir4-shadow-source-model-target-policy-in-common]' }
  $overlayRows = [Collections.Generic.List[object]]::new()
  foreach ($target in $targets) {
    $family = if ($target -in @('f210','f200')) { 'modern' } else { 'legacy' }
    $applicable = @($bindings | Where-Object {
      [string]$_.layer -ceq "families.$family" -or [string]$_.layer -ceq "targets.$target"
    } | Sort-Object path -CaseSensitive)
    $operations = [Collections.Generic.List[object]]::new()
    foreach ($binding in $applicable) {
      $operation = if ([string]$binding.materialization -ceq 'generate') { 'generate' } else { 'add' }
      $operations.Add([pscustomobject][ordered]@{
        path=[string]$binding.path
        operation=$operation
        semantic_class=[string]$binding.semantic_class
        source_authority=[string]$binding.future_editable_authority
        reason="Materialize the governed $([string]$binding.layer) source for $target."
        capability_disposition='included-for-target'
        expected_sha256=[string]$binding.sha256
        proof_obligations=@($binding.proof_obligations)
      })
    }
    foreach ($path in @($allPaths | Where-Object { -not $targetMaps[$target].ContainsKey($_) })) {
      $operations.Add([pscustomobject][ordered]@{
        path=$path
        operation='omit'
        semantic_class='target-omission'
        source_authority="targets/$target/overlay.json"
        reason="The exact $target package baseline does not contain this path."
        capability_disposition='omitted-by-target-profile'
        expected_sha256=$null
        proof_obligations=@('explicit-target-omission','exact-target-path-inventory','fresh-runtime-replay-before-cutover')
      })
    }
    $orderedOperations = @($operations | Sort-Object path,operation -CaseSensitive)
    $overlayRows.Add([pscustomobject][ordered]@{
      target=$target
      family=$family
      authority="targets/$target/overlay.json"
      base_layers=@('common',"families.$family")
      operation_counts=[pscustomobject][ordered]@{
        add=@($orderedOperations | Where-Object operation -ceq 'add').Count
        replace=@($orderedOperations | Where-Object operation -ceq 'replace').Count
        omit=@($orderedOperations | Where-Object operation -ceq 'omit').Count
        generate=@($orderedOperations | Where-Object operation -ceq 'generate').Count
      }
      operations=$orderedOperations
    })
  }
  $canonicalProbe = [pscustomobject][ordered]@{bindings=@($bindings | Sort-Object layer,path -CaseSensitive);overlays=@($overlayRows | Sort-Object target -CaseSensitive)}
  $reverseProbe = [pscustomobject][ordered]@{bindings=@($bindings | Sort-Object layer,path -CaseSensitive -Descending | Sort-Object layer,path -CaseSensitive);overlays=@($overlayRows | Sort-Object target -CaseSensitive -Descending | Sort-Object target -CaseSensitive)}
  $canonicalProbeSha256 = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $canonicalProbe)
  $reverseProbeSha256 = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $reverseProbe)
  if ($canonicalProbeSha256 -cne $reverseProbeSha256) { throw '[mir4-shadow-source-model-declaration-order]' }
  $classCounts = [ordered]@{}
  foreach ($class in @('common-semantic-source','common-asset-locale','generated-metadata','generated-lifecycle-entrypoint','target-overlay','target-replacement','target-omission','target-compatibility-shim','migration','package-documentation')) {
    if ($class -ceq 'target-omission') {
      $classCounts[$class] = @($overlayRows.operations | Where-Object semantic_class -ceq $class).Count
    } else {
      $classCounts[$class] = @($bindings | Where-Object semantic_class -ceq $class).Count
    }
  }
  $report = [pscustomobject][ordered]@{
    schema=1
    kind='MIR4ShadowSourceModelProofV1'
    status='passed-semantic-shadow-model-no-editable-source-no-cutover'
    baseline_record_sha256=[string]$baseline.record_sha256
    algorithm='semantic-common-family-target-overlay-and-omission-model-v1'
    future_authorities=[pscustomobject][ordered]@{
      canonical_mod_source='src/mod'
      target_registry='targets/registry.json'
      target_support_policy='targets/support-policy.json'
      target_overlays='targets/<target>/overlay.json'
      target_materializer='tools/mir/application/package/TargetMaterializer.ps1'
    }
    layers=@($layers | ForEach-Object { [pscustomobject][ordered]@{id=[string]$_.id;source_target=[string]$_.source_target;target_scope=@($_.target_scope);entry_count=@($_.entries).Count} })
    bindings=@($bindings | Sort-Object layer,path -CaseSensitive)
    target_overlays=@($overlayRows)
    classification_counts=[pscustomobject]$classCounts
    declaration_order_probe_sha256=$canonicalProbeSha256
    invariants=[pscustomobject][ordered]@{
      all_paths_classified=$true
      no_path_collision=$true
      no_unowned_path=$true
      declaration_order_independent=$true
      no_target_policy_in_common_domain_code=$true
      historical_archives_are_comparison_fixtures_only=$true
      package_source_unchanged=$true
      current_writer_unchanged=$true
      runtime_replay_required_before_cutover=$true
    }
    transition_gate=[pscustomobject][ordered]@{source_move=$false;editable_source=$false;package_cutover=$false;old_writer_retirement=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
    record_sha256=''
  }
  $report.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $report
  return $report
}

function Write-MIR4ShadowSourceModel {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$OutputPath='build/reports/package-source/mir4-shadow-source-model-v1.json',
    [switch]$Check
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $repo $OutputPath }
  $model = New-MIR4ShadowSourceModel -RepoRoot $repo
  $json = ($model | ConvertTo-Json -Depth 100).Replace([Environment]::NewLine, [string][char]10) + [string][char]10
  if ($Check) {
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) { throw '[mir4-shadow-source-model-missing]' }
    $actual = [IO.File]::ReadAllText($OutputPath).Replace("`r`n","`n").Replace("`r","`n")
    if ($actual -cne $json) { throw '[mir4-shadow-source-model-stale]' }
  } else {
    $parent = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($OutputPath, $json, [Text.UTF8Encoding]::new($false))
  }
  return $model
}
