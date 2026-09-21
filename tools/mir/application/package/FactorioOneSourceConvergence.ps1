Set-StrictMode -Version Latest

# Read-only characterization for the governed Factorio-1 source cutover.
# The caller supplies the pinned predecessor explicitly; this script never
# mutates source authorities, composition records, or package identities.

$mir4FactorioOneConvergenceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
if (-not (Get-Command Get-MIR4BootstrapRecordSha256 -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4FactorioOneConvergenceRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Read-MIR4TargetMaterializerRecord -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4FactorioOneConvergenceRoot 'tools/mir/application/package/TargetMaterializer.ps1')
}
if (-not (Get-Command Read-MIR4GitBlobSet -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4FactorioOneConvergenceRoot 'tools/mir/application/package/SourceCompositionProof.ps1')
}

function Get-MIR4FactorioOneRequireSet {
  param([Parameter(Mandatory)][byte[]]$Bytes)
  $text = [Text.UTF8Encoding]::new($false).GetString($Bytes)
  return @(
    [regex]::Matches($text, 'require\s*\(\s*["'']([^"'']+)["'']\s*\)') |
      ForEach-Object { $_.Groups[1].Value } |
      Sort-Object -Unique -CaseSensitive
  )
}

function Get-MIR4FactorioOneSyntaxSignals {
  param([Parameter(Mandatory)][byte[]]$Bytes)
  $text = [Text.UTF8Encoding]::new($false).GetString($Bytes)
  $signals = [ordered]@{}
  foreach ($pair in @(
    @{name='goto'; pattern='(?m)\bgoto\b'},
    @{name='bitwise-operators'; pattern='(?m)(?:<<|>>|//|(?<![~])~(?![=]))'},
    @{name='storage-api'; pattern='(?m)\bstorage\b'},
    @{name='global-api'; pattern='(?m)\bglobal\b'},
    @{name='data-raw'; pattern='(?m)\bdata\.raw\b'},
    @{name='data-extend'; pattern='(?m)\bdata:extend\b'},
    @{name='prototype-defines'; pattern='(?m)\bdefines\.prototypes\b'},
    @{name='runtime-script'; pattern='(?m)\bscript\.'}
  )) {
    $signals[$pair.name] = [regex]::IsMatch($text, $pair.pattern)
  }
  return [pscustomobject]$signals
}

function Get-MIR4FactorioOneLifecycle {
  param([Parameter(Mandatory)][string]$OutputPath)
  if ($OutputPath -match '(^|/)runtime/') { return 'runtime' }
  if ($OutputPath -match '(^|/)settings/') { return 'settings' }
  if ($OutputPath -match '(^|/)stage/') { return 'lifecycle-stage' }
  if ($OutputPath -match '^locale/') { return 'presentation' }
  return 'data-stage'
}

function Get-MIR4FactorioOneDiagnosticOrderSignals {
  param([Parameter(Mandatory)][byte[]]$Bytes)
  $text = [Text.UTF8Encoding]::new($false).GetString($Bytes)
  return [pscustomobject][ordered]@{
    diagnostics = $text -match '(?i)diagnostic|warning|error\('
    stable_order = $text -match 'table\.sort|sort\('
  }
}

function Get-MIR4FactorioOneConvergenceCharacterization {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$BaselineRevision
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $baselineManifestBytes = Read-MIR4GitBlobBytes -RepoRoot $repo -Commit $BaselineRevision -RelativePath 'source/package-source.json'
  $baselineManifest = ([Text.UTF8Encoding]::new($false).GetString($baselineManifestBytes) | ConvertFrom-Json -Depth 100 -DateKind String)
  $currentManifest = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'source/package-source.json' -Kind 'MIR4ComposablePackageSourceV3'
  $baselineF1 = @($baselineManifest.bindings | Where-Object { [string]$_.source_path -like 'source/compatibility/factorio-1/*' } | Sort-Object output_path -CaseSensitive)
  if ($baselineF1.Count -ne 81) { throw "[mir4-factorio-one-convergence-baseline-cardinality] $($baselineF1.Count)" }
  $baselinePeers = @{}
  foreach ($oldBinding in $baselineF1) {
    $outputPath = [string]$oldBinding.output_path
    $peer = @($baselineManifest.bindings | Where-Object { [string]$_.output_path -ceq $outputPath -and $_.target_scope -contains 'f210' })
    if ($peer.Count -ne 1) { throw "[mir4-factorio-one-convergence-baseline-peer] $outputPath" }
    $baselinePeers[$outputPath] = $peer[0]
  }
  $factorioOneBlobs = Read-MIR4GitBlobSet -RepoRoot $repo -Commit $BaselineRevision -RelativePath @($baselineF1.source_path)
  $factorioTwoBlobs = Read-MIR4GitBlobSet -RepoRoot $repo -Commit $BaselineRevision -RelativePath @($baselinePeers.Values.source_path)
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($oldBinding in $baselineF1) {
    $outputPath = [string]$oldBinding.output_path
    $oldBytes = $factorioOneBlobs[[string]$oldBinding.source_path]
    $baselinePeer = $baselinePeers[$outputPath]
    $peerBytes = $factorioTwoBlobs[[string]$baselinePeer.source_path]
    $current = @($currentManifest.bindings | Where-Object { [string]$_.output_path -ceq $outputPath -and $_.target_scope -contains 'f110' -and $_.target_scope -contains 'f100' })
    if ($current.Count -ne 1) { throw "[mir4-factorio-one-convergence-current-selection] $outputPath" }
    $currentSource = [string]$current[0].source_path
    $classification = if ($currentSource -like 'source/adapters/runtime-capabilities/*') {
      'narrow-runtime-capability-adapter'
    } elseif ($currentSource -like 'source/adapters/platform/*') {
      'narrow-platform-representation-adapter'
    } else {
      'shared-semantic-module'
    }
    $oldImports = Get-MIR4FactorioOneRequireSet -Bytes $oldBytes
    $peerImports = Get-MIR4FactorioOneRequireSet -Bytes $peerBytes
    $diagnosticOrder = Get-MIR4FactorioOneDiagnosticOrderSignals -Bytes $oldBytes
    $rows.Add([pscustomobject][ordered]@{
      output_path = $outputPath
      lifecycle = Get-MIR4FactorioOneLifecycle -OutputPath $outputPath
      baseline_factorio_one_source = [string]$oldBinding.source_path
      baseline_factorio_one_sha256 = Get-MIR4Sha256Bytes -Bytes $oldBytes
      baseline_factorio_two_source = [string]$baselinePeer.source_path
      baseline_factorio_two_sha256 = Get-MIR4Sha256Bytes -Bytes $peerBytes
      same_output_path = $true
      byte_divergent_baseline = ((Get-MIR4Sha256Bytes -Bytes $oldBytes) -cne (Get-MIR4Sha256Bytes -Bytes $peerBytes))
      factorio_one_imports = $oldImports
      factorio_two_imports = $peerImports
      imports_only_in_factorio_one = @($oldImports | Where-Object { $_ -notin $peerImports })
      imports_only_in_factorio_two = @($peerImports | Where-Object { $_ -notin $oldImports })
      factorio_one_syntax_and_api = Get-MIR4FactorioOneSyntaxSignals -Bytes $oldBytes
      factorio_two_syntax_and_api = Get-MIR4FactorioOneSyntaxSignals -Bytes $peerBytes
      diagnostics_or_ordering = $diagnosticOrder
      current_source = $currentSource
      convergence_class = $classification
    })
  }
  $classes = [ordered]@{}
  foreach ($class in @($rows.convergence_class | Sort-Object -Unique -CaseSensitive)) {
    $classes[$class] = @($rows | Where-Object { $_.convergence_class -ceq $class }).Count
  }
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4FactorioOneSourceConvergenceCharacterizationV1'
    baseline_revision = $BaselineRevision
    baseline_factorio_one_pair_count = $baselineF1.Count
    current_factorio_one_whole_tree_present = Test-Path -LiteralPath (Join-Path $repo 'source/compatibility/factorio-1') -PathType Container
    convergence_classes = [pscustomobject]$classes
    rows = @($rows)
  }
}

function Get-MIR4FactorioOneSourceConvergenceProof {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [ValidatePattern('^[a-f0-9]{40}$')][string]$BaselineRevision = '297aa5cc902da96847165a4f9caa1048608839fb'
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $manifest = Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'source/package-source.json' -Kind 'MIR4ComposablePackageSourceV3'
  $characterization = Get-MIR4FactorioOneConvergenceCharacterization -RepoRoot $repo -BaselineRevision $BaselineRevision
  $physical = @(
    Get-ChildItem -LiteralPath (Join-Path $repo 'source') -File -Recurse |
      Where-Object { $_.FullName -notin @((Join-Path $repo 'source/package-source.json'), (Join-Path $repo 'source/.mir-root.json')) } |
      ForEach-Object { [IO.Path]::GetRelativePath($repo, $_.FullName).Replace([IO.Path]::DirectorySeparatorChar, '/') } |
      Sort-Object -Unique -CaseSensitive
  )
  $declared = @($manifest.bindings.source_path | Sort-Object -Unique -CaseSensitive)
  if (($declared -join "`n") -cne ($physical -join "`n")) { throw '[mir4-factorio-one-convergence-physical-set]' }
  if (@($manifest.bindings).Count -ne $declared.Count) { throw '[mir4-factorio-one-convergence-duplicate-source-binding]' }
  $bindingSignatures = @($manifest.bindings | ForEach-Object { "$([string]$_.source_path)|$([string]$_.output_path)|$([string]$_.transform)" })
  if (@($bindingSignatures | Sort-Object -Unique -CaseSensitive).Count -ne $bindingSignatures.Count) {
    throw '[mir4-factorio-one-convergence-duplicate-binding-signature]'
  }
  if (Test-Path -LiteralPath (Join-Path $repo 'source/compatibility/factorio-1')) {
    throw '[mir4-factorio-one-convergence-whole-tree-present]'
  }

  $expectedAdapters = @(
    'source/adapters/platform/base-version-profile/target_profiles.lua',
    'source/adapters/runtime-capabilities/disabled-scripted-techs.lua'
  )
  $targetProofs = [Collections.Generic.List[object]]::new()
  foreach ($target in @('f110', 'f100')) {
    $state = Get-MIR4TargetMaterializerState -RepoRoot $repo -Target $target
    $selection = Get-MIR4TargetMaterializationBindings -State $state
    if (-not [bool]$selection.scoped_operation_closure) { throw "[mir4-factorio-one-convergence-operation-closure] $target" }
    $bindings = @($selection.bindings)
    $byOutput = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($binding in $bindings) {
      if (-not $byOutput.TryAdd([string]$binding.output_path, $binding)) {
        throw "[mir4-factorio-one-convergence-output-collision] $target $($binding.output_path)"
      }
    }

    $requires = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $missing = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $bitwiseFiles = [Collections.Generic.List[string]]::new()
    $storageFiles = [Collections.Generic.List[string]]::new()
    $prototypeDefinesFiles = [Collections.Generic.List[string]]::new()
    foreach ($binding in @($bindings | Where-Object { [string]$_.output_path -like '*.lua' })) {
      $sourcePath = [string]$binding.source_path
      $bytes = [IO.File]::ReadAllBytes((Join-Path $repo $sourcePath))
      if ([int64]$bytes.Length -ne [int64]$binding.source_bytes -or
          (Get-MIR4Sha256Bytes -Bytes $bytes) -cne [string]$binding.source_sha256) {
        throw "[mir4-factorio-one-convergence-source-identity] $sourcePath"
      }
      $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
      foreach ($match in [regex]::Matches($text, 'require\s*\(\s*["'']([^"'']+)["'']\s*\)')) {
        $name = $match.Groups[1].Value
        [void]$requires.Add($name)
        $requiredOutput = if ($name.StartsWith('__more-infinite-research__/', [StringComparison]::Ordinal)) {
          $name.Substring('__more-infinite-research__/'.Length)
        } else {
          $name.Replace('.', '/')
        }
        $requiredOutput += '.lua'
        if (-not $byOutput.ContainsKey($requiredOutput)) { [void]$missing.Add("$sourcePath -> $name") }
      }
      if ([regex]::IsMatch($text, '(?m)(?:<<|>>|//|(?<![~=])~(?![=]))')) { [void]$bitwiseFiles.Add($sourcePath) }
      if ([regex]::IsMatch($text, '(?m)\bstorage\b')) { [void]$storageFiles.Add($sourcePath) }
      if ([regex]::IsMatch($text, '(?m)\bdefines\.prototypes\b')) { [void]$prototypeDefinesFiles.Add($sourcePath) }
    }
    if ($missing.Count -ne 0) { throw "[mir4-factorio-one-convergence-require-closure] $target $(@($missing) -join '; ')" }
    if ($bitwiseFiles.Count -ne 0) { throw "[mir4-factorio-one-convergence-lua-syntax] $target $($bitwiseFiles -join '; ')" }

    $adapters = @($bindings | Where-Object { [string]$_.source_path -like 'source/adapters/*' } | ForEach-Object source_path | Sort-Object -Unique -CaseSensitive)
    if (($adapters -join "`n") -cne ($expectedAdapters -join "`n")) { throw "[mir4-factorio-one-convergence-adapter-set] $target" }
    $entrypoints = @('settings.lua','data.lua','data-updates.lua','data-final-fixes.lua','control.lua')
    $missingEntrypoints = @($entrypoints | Where-Object { -not $byOutput.ContainsKey($_) })
    if ($missingEntrypoints.Count -ne 0) { throw "[mir4-factorio-one-convergence-entrypoints] $target $($missingEntrypoints -join ',')" }

    $targetProofs.Add([pscustomobject][ordered]@{
      target = $target
      binding_count = $bindings.Count
      omission_count = @($state.composition.operations | Where-Object { [string]$_.operation -ceq 'omit' }).Count
      output_count = $byOutput.Count
      literal_require_count = $requires.Count
      unresolved_literal_requires = @($missing | Sort-Object -CaseSensitive)
      entrypoints = $entrypoints
      adapter_sources = $adapters
      unsupported_bitwise_or_integer_division_sources = @($bitwiseFiles | Sort-Object -Unique -CaseSensitive)
      storage_reference_sources = @($storageFiles | Sort-Object -Unique -CaseSensitive)
      prototype_defines_reference_sources = @($prototypeDefinesFiles | Sort-Object -Unique -CaseSensitive)
    })
  }

  $profileText = Get-Content -Raw -LiteralPath (Join-Path $repo $expectedAdapters[0])
  if ($profileText -notmatch 'type\(mods\).*mods\.base' -or
      $profileText -notmatch 'script\s+and\s+script\.active_mods' -or
      $profileText -notmatch 'authorities disagree') {
    throw '[mir4-factorio-one-convergence-version-lifecycle-authority]'
  }
  $runtimeStateText = Get-Content -Raw -LiteralPath (Join-Path $repo 'source/prototypes/mir/platform/factorio/runtime_state.lua')
  if ($runtimeStateText -notmatch 'backend == "global"' -or $runtimeStateText -notmatch 'type\(global\)') {
    throw '[mir4-factorio-one-convergence-runtime-state-guard]'
  }
  $prototypeLookupText = Get-Content -Raw -LiteralPath (Join-Path $repo 'source/prototypes/mir/platform/factorio/prototype_lookup.lua')
  if ($prototypeLookupText -notmatch 'type\(defines\) == "table" and defines\.prototypes or nil') {
    throw '[mir4-factorio-one-convergence-prototype-defines-guard]'
  }

  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4FactorioOneSourceConvergenceProofV1'
    status = 'passed-static-source-convergence-engine-proof-required'
    baseline_revision = $BaselineRevision
    historical_characterization = [pscustomobject][ordered]@{
      factorio_one_pair_count = [int]$characterization.baseline_factorio_one_pair_count
      convergence_classes = $characterization.convergence_classes
      byte_divergent_pair_count = @($characterization.rows | Where-Object { [bool]$_.byte_divergent_baseline }).Count
    }
    current_source = [pscustomobject][ordered]@{
      binding_count = @($manifest.bindings).Count
      physical_source_count = $physical.Count
      whole_factorio_one_tree_present = $false
      factorio_one_adapter_sources = $expectedAdapters
    }
    targets = @($targetProofs)
    invariants = [pscustomobject][ordered]@{
      one_canonical_physical_source_per_binding = $true
      no_duplicate_source_output_transform_group = $true
      no_factorio_one_whole_tree = $true
      target_output_collision_free = $true
      literal_require_closure_complete = $true
      required_lifecycle_entrypoints_present = $true
      factorio_one_version_authority_stage_safe = $true
      runtime_state_backend_guarded = $true
      prototype_defines_fallback_guarded = $true
      unsupported_lua_syntax_absent = $true
    }
    exact_engine_proof_required = $true
    release_transition_authority = $false
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}
