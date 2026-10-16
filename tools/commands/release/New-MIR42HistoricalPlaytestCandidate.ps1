param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [ValidateSet('f017', 'f016', 'f015', 'f014', 'f013')][string]$Target = 'f017',
  [ValidatePattern('^[A-Z0-9][A-Z0-9.-]*$')][string]$CandidateId = 'MIR42-HISTORICAL',
  [ValidateSet('4.2.0','4.2.1','4.2.2','4.2.3','4.3.0','4.3.1','4.4.0','4.4.1','4.4.2','4.5.0')][string]$SourceVersion = '4.2.0',
  [ValidateRange(2, 3)][int]$Repetitions = 2,
  [string]$OutputRoot = 'build/mir42-historical-playtest',
  [switch]$RefreshSourceBindings,
  [switch]$AuthenticationProjection,
  [switch]$Check
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')

function Set-MIR42HistoricalBaselinePackageIdentity {
  param([string]$Tree, $Record, [string]$BaselineSourceVersion)
  # The verified adapter remains a pinned 4.2 baseline. Project its identity
  # only in this private build tree before the normal patch writer validates
  # the requested minor. Never broaden that writer's accepted input versions.
  if ($BaselineSourceVersion -cnotmatch '^4[.](?<minor>2|3|4|5)[.]0$') {
    throw '[mir42-historical-baseline-projection]'
  }
  $sourceMinor = [int]$Matches.minor
  if ([string]$Record.target -cnotmatch '^f(017|016|015|014|013)$') {
    throw '[mir42-historical-baseline-projection]'
  }
  $code = ([string]$Record.target).Substring(1)
  $pinned = New-MIR4DistributionIdentityProjection -DistributionTargetCode $code -SourceMinor 2 -SourcePatch 0
  $projected = New-MIR4DistributionIdentityProjection -DistributionTargetCode $code -SourceMinor $sourceMinor -SourcePatch 0
  $path = Join-Path $Tree 'info.json'
  $info = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 20 -DateKind String
  if ([string]$Record.distribution_version -cne [string]$pinned.distribution_version -or
      [string]$Record.factorio_line -cne ('0.' + [int]$code) -or
      [string]$info.name -cne 'more-infinite-research' -or
      [string]$info.version -cne [string]$Record.distribution_version -or
      [string]$info.factorio_version -cne [string]$Record.factorio_line) {
    throw '[mir42-historical-baseline-input-identity]'
  }
  if ([string]$info.version -cne [string]$projected.distribution_version) {
    $info.version = [string]$projected.distribution_version
    [IO.File]::WriteAllText($path, (($info | ConvertTo-Json -Depth 20).Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
  }
}

function Get-MIR42HistoricalTargetRecord {
  param([string]$TargetId)
  $path = Join-Path $repo "targets/historical/$TargetId/target.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir42-historical-target-record-missing] $TargetId" }
  $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 50
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42HistoricalPlaytestTargetV1' -or
      [string]$record.target -cne $TargetId -or [string]::IsNullOrWhiteSpace([string]$record.record_sha256) -or
      -not (Test-MIR4BootstrapRecordHash -Record $record)) {
    throw "[mir42-historical-target-record-invalid] $TargetId"
  }
  if ([string]$record.base_materializer_target -cne 'f100' -or [bool]$record.public_output_authorized -or [bool]$record.publication_authorized) {
    throw "[mir42-historical-target-boundary] $TargetId"
  }
  return [pscustomobject]@{ path = $path; record = $record }
}

function Get-MIR42HistoricalSourceManifest {
  return Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'source/package-source.json' -Kind 'MIR4ComposablePackageSourceV3'
}

function Get-MIR42HistoricalSourceBytes {
  param($Adapter, $Record, $SourceManifest)
  $relative = [string]$Adapter.source_path
  if ($relative -notmatch '^source/') { throw "[mir42-historical-adapter-boundary] $relative" }
  $bindings = @($SourceManifest.bindings | Where-Object {
    $Record.target -in @($_.target_scope) -and
    [string]$_.output_path -ceq [string]$Adapter.output_path -and
    [string]$_.source_path -ceq $relative
  })
  if ($bindings.Count -ne 1 -or
      [int64]$bindings[0].source_bytes -ne [int64]$Adapter.source_bytes -or
      [string]$bindings[0].source_sha256 -cne [string]$Adapter.source_sha256) {
    throw "[mir42-historical-adapter-manifest-binding] $($Record.target):$relative"
  }
  $full = [IO.Path]::GetFullPath((Join-Path $repo $relative))
  $prefix = $repo.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
    throw "[mir42-historical-adapter-source-missing] $relative"
  }
  $bytes = [IO.File]::ReadAllBytes($full)
  if ([int64]$bytes.Length -ne [int64]$Adapter.source_bytes -or
      (Get-MIR4Sha256Bytes -Bytes $bytes) -cne [string]$Adapter.source_sha256) {
    throw "[mir42-historical-adapter-source-drift] $relative"
  }
  return $bytes
}

function ConvertTo-MIR42HistoricalAdapterBytes {
  param($Adapter, $Record, $SourceManifest)
  $bytes = Get-MIR42HistoricalSourceBytes -Adapter $Adapter -Record $Record -SourceManifest $SourceManifest
  $transformField = $Adapter.PSObject.Properties['transform']
  $transform = if ($null -eq $transformField -or [string]::IsNullOrWhiteSpace([string]$transformField.Value)) { 'copy-exact-bytes' } else { [string]$transformField.Value }
  if ($transform -eq 'copy-exact-bytes') { $output = $bytes }
  elseif ($transform -eq 'legacy-target-profile-template-v1') {
    $text = [Text.UTF8Encoding]::new($false).GetString($bytes)
    $profile = $Record.profile
    foreach ($pair in @(
      @{ token = '@@FACTORIO_LINE@@'; value = [string]$Record.factorio_line },
      @{ token = '@@SUPPORT_CLASS@@'; value = [string]$profile.support_class },
      @{ token = '@@SCIENCE_FAMILY@@'; value = [string]$profile.science_family },
      @{ token = '@@ASSET_POLICY@@'; value = [string]$profile.asset_policy },
      @{ token = '@@LABORATORY_PRODUCTIVITY_EFFECT@@'; value = if ([bool]$profile.laboratory_productivity) { ",`n        `"laboratory-productivity`"" } else { '' } },
      @{ token = '@@OLD_SCIENCE_VALIDATION@@'; value = if ([bool]$profile.old_science_map) { ',' + [Environment]::NewLine + '        "old-science-map"' } else { '' } },
      @{ token = '@@LEGACY_NUMERIC_RESEARCH_COST@@'; value = if ([bool]$profile.legacy_numeric_research_cost) { 'true' } else { 'false' } }
    )) {
      if ([regex]::Matches($text, [regex]::Escape([string]$pair.token)).Count -lt 1) { throw "[mir42-historical-template-token] $($pair.token)" }
      $text = $text.Replace([string]$pair.token, [string]$pair.value)
    }
    if ($text.Contains('@@')) { throw '[mir42-historical-template-unresolved]' }
    $output = [Text.UTF8Encoding]::new($false).GetBytes($text)
  } elseif ($transform -eq 'historical-readme-template-v1') {
    $text = [Text.UTF8Encoding]::new($false).GetString($bytes)
    $line = [string]$Record.factorio_line
    $version = [string]$Record.distribution_version
    $engineVersion = [string]$Record.engine.version
    $predecessorVersion = [string]$Record.predecessor.version
    $lf = [string][char]10
    # The shared README is authored for the current F100 maintenance package.
    # Resolve that identity from its guarded heading instead of pinning an old
    # source patch in the historical projection.
    $readmeIdentity = [regex]::Match($text, '\A# More Infinite Research (?<version>4\.(?<minor>[234])\.100[0-9]{2})(?:\r?\n|$)')
    if (-not $readmeIdentity.Success) { throw '[mir42-historical-readme-source-identity]' }
    $replacements = @(
      @{ from = '`base >= 1.0`'; to = ('`base >= ' + $line + '`') },
      @{ from = 'It is a reduced target-native projection from the current MIR source. It preserves the eleven supported Factorio 1.0 research streams without importing Space Age, `mod-data`, settings-profile, or modern adoption systems.'; to = 'It is a reduced target-specific projection from the current MIR source. Emitted streams and progression depend on the actual engine and prototype capabilities.' },
      @{ from = 'MIR emits eleven stable, manifest-backed infinite research streams when their target effects are available:'; to = 'MIR presents the following manifest-backed research catalog when the target has the required effects, science packs, and prerequisites. A fresh-load receipt does not assert that every catalog entry emits on every historical line:' },
      @{ from = 'MIR also extends supported Factorio 1.0 base infinite technology families for braking force, research speed, worker robot storage, weapon shooting speed, and laser turret shooting speed. Target-aware science selection uses Factorio 1.0 `tool` prototypes and rejects missing, disabled, cyclic, or unreachable prerequisites before emission.'; to = "MIR may create qualified continuations for supported Factorio $line base infinite technology families when target-state gates pass. Target-aware science selection uses Factorio $line ``tool`` prototypes and rejects missing, disabled, cyclic, or unreachable prerequisites before emission." },
      @{ from = 'Fresh installations default to `only-when-dedicated-tech-enabled`. MIR removes rocket and cannon-shell speed effects from its generated vanilla continuation only when a valid dedicated MIR or preferred exact external infinite owner exists. `off` and `always` remain available, and explicit values are preserved during the 1.8.1 to 1.8.2 upgrade.'; to = "Fresh installations default to ``only-when-dedicated-tech-enabled``. The historical $predecessorVersion predecessor remains a continuity input; upgrade qualification of this exact hotfix package is NOT RUN." },
      @{ from = 'Earlier fresh-load evidence used 1.0.0;'; to = "Earlier fresh-load evidence used $engineVersion;" },
      @{ from = 'Earlier fresh-load evidence remains bound to its original package and Factorio 1.0.0. Consult the matching release record for native qualification of this exact package.'; to = "Earlier fresh-load evidence remains bound to its original package and Factorio $engineVersion. Consult the matching release record for native qualification of this exact package." },
      @{ from = 'The exact published 1.8.1 archive remains a historical predecessor record.'; to = "The exact published $predecessorVersion archive remains a historical predecessor record." },
      @{ from = ('- `docs/releases/1.8.2.md`' + $lf + '- `.mir/backport-source-lock.json`' + $lf + '- `.mir/evidence/1.8.2-qualification.json`' + $lf + '- `.mir/evidence/candidate-seals/mir-1.8.2-factorio-1.0.json`'); to = ('- `targets/historical/' + $Record.target + '/target.json`' + $lf + '- the private historical candidate manifest' + $lf + '- the exact-engine fresh-load receipt' + $lf + '- the published ' + $predecessorVersion + ' predecessor archive identity') },
      @{ from = $readmeIdentity.Groups['version'].Value; to = $version },
      @{ from = 'Factorio 1.0'; to = "Factorio $line" }
    )
    foreach ($replacement in $replacements) {
      if ([regex]::Matches($text, [regex]::Escape([string]$replacement.from)).Count -lt 1) {
        throw "[mir42-historical-readme-anchor] $($replacement.from)"
      }
      $text = $text.Replace([string]$replacement.from, [string]$replacement.to)
    }
    $output = [Text.UTF8Encoding]::new($false).GetBytes($text)
  } else { throw "[mir42-historical-adapter-transform] $transform" }
  $outputBytesField = $Adapter.PSObject.Properties['output_bytes']
  $outputShaField = $Adapter.PSObject.Properties['output_sha256']
  if ($null -ne $outputBytesField -and $null -ne $outputShaField -and
      ([int64]$output.Length -ne [int64]$outputBytesField.Value -or
      (Get-MIR4Sha256Bytes -Bytes $output) -cne [string]$outputShaField.Value)) {
    throw "[mir42-historical-adapter-output-drift] $($Adapter.output_path)"
  }
  return $output
}

function Copy-MIR42HistoricalAdapter {
  param([string]$Tree, $Record, $SourceManifest)
  foreach ($adapter in @($Record.adapter_files)) {
    $output = [string]$adapter.output_path
    Assert-MIR4PortableArchivePath -Path $output
    $destination = [IO.Path]::GetFullPath((Join-Path $Tree $output))
    $treePrefix = $Tree.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $destination.StartsWith($treePrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
      throw "[mir42-historical-adapter-output-missing] $output"
    }
    [IO.File]::WriteAllBytes($destination, (ConvertTo-MIR42HistoricalAdapterBytes -Adapter $adapter -Record $Record -SourceManifest $SourceManifest))
  }
  foreach ($patch in @($Record.patches)) {
    $output = [string]$patch.output_path
    Assert-MIR4PortableArchivePath -Path $output
    $destination = [IO.Path]::GetFullPath((Join-Path $Tree $output))
    $treePrefix = $Tree.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $destination.StartsWith($treePrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
      throw "[mir42-historical-patch-output-missing] $output"
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -cne [string]$patch.base_sha256) {
      throw "[mir42-historical-patch-base-drift] $output"
    }
    $original = [IO.File]::ReadAllText($destination)
    $find = [string]$patch.find
    $count = [regex]::Matches($original, [regex]::Escape($find)).Count
    if ($count -ne 1) { throw "[mir42-historical-patch-anchor] ${output}:$count" }
    [IO.File]::WriteAllText($destination, $original.Replace($find, [string]$patch.replace), [Text.UTF8Encoding]::new($false))
  }
}

# This is deliberately a projection, not a second archive writer.  It starts
# from the canonical f100 materializer selection and applies the same bounded
# historical adapter, patch, and package-identity operations that the writer
# applies to its private tree.  Native input readers use it to verify every
# member of an already-built historical package without materializing another
# tree or ZIP.
function Get-MIR42HistoricalCandidateAuthenticationProjection {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('f017', 'f016', 'f015', 'f014', 'f013')][string]$TargetId,
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)]$SourceManifest,
    [Parameter(Mandatory)][string]$SourceVersion,
    [Parameter(Mandatory)][string]$TargetRecordPath
  )

  if ($SourceVersion -cnotmatch '^4[.](?<minor>2|3|4|5)[.](?<patch>[0-9]{1,2})$') {
    throw '[mir42-historical-authentication-source-version]'
  }
  $sourceMinor = [int]$Matches.minor
  $sourcePatch = [int]$Matches.patch
  $identity = New-MIR4DistributionIdentityProjection -DistributionTargetCode $TargetId.Substring(1) -SourceMinor $sourceMinor -SourcePatch $sourcePatch
  $distributionRoot = 'more-infinite-research_' + [string]$identity.distribution_version
  $baseState = Get-MIR4TargetMaterializerState -RepoRoot $RepoRoot -Target f100
  $baseSelection = Get-MIR4TargetMaterializationBindings -State $baseState
  $memberBytes = [Collections.Generic.Dictionary[string, byte[]]]::new([StringComparer]::Ordinal)
  foreach ($binding in @($baseSelection.bindings)) {
    $path = [string]$binding.output_path
    Assert-MIR4PortableArchivePath -Path $path
    if (-not $memberBytes.TryAdd($path, (Read-MIR4CanonicalSourceBindingBytes -State $baseState -Binding $binding))) {
      throw "[mir42-historical-authentication-base-member-collision] $path"
    }
  }

  foreach ($adapter in @($Record.adapter_files)) {
    $path = [string]$adapter.output_path
    Assert-MIR4PortableArchivePath -Path $path
    if (-not $memberBytes.ContainsKey($path)) {
      throw "[mir42-historical-authentication-adapter-output-missing] $path"
    }
    $memberBytes[$path] = ConvertTo-MIR42HistoricalAdapterBytes -Adapter $adapter -Record $Record -SourceManifest $SourceManifest
  }
  $utf8 = [Text.UTF8Encoding]::new($false)
  foreach ($patch in @($Record.patches)) {
    $path = [string]$patch.output_path
    Assert-MIR4PortableArchivePath -Path $path
    if (-not $memberBytes.ContainsKey($path)) {
      throw "[mir42-historical-authentication-patch-output-missing] $path"
    }
    $originalBytes = $memberBytes[$path]
    if ((Get-MIR4Sha256Bytes -Bytes $originalBytes) -cne [string]$patch.base_sha256) {
      throw "[mir42-historical-authentication-patch-base-drift] $path"
    }
    $original = $utf8.GetString($originalBytes)
    $find = [string]$patch.find
    if ([regex]::Matches($original, [regex]::Escape($find)).Count -ne 1) {
      throw "[mir42-historical-authentication-patch-anchor] $path"
    }
    $memberBytes[$path] = $utf8.GetBytes($original.Replace($find, [string]$patch.replace))
  }

  foreach ($required in @('info.json', 'changelog.txt', 'README.md')) {
    if (-not $memberBytes.ContainsKey($required)) {
      throw "[mir42-historical-authentication-identity-member-missing] $required"
    }
  }
  $pinned = New-MIR4DistributionIdentityProjection -DistributionTargetCode $TargetId.Substring(1) -SourceMinor 2 -SourcePatch 0
  $projectedBaseline = New-MIR4DistributionIdentityProjection -DistributionTargetCode $TargetId.Substring(1) -SourceMinor $sourceMinor -SourcePatch 0
  $baselineInfo = $utf8.GetString($memberBytes['info.json']) | ConvertFrom-Json -Depth 20 -DateKind String
  if ([string]$Record.distribution_version -cne [string]$pinned.distribution_version -or
      [string]$Record.factorio_line -cne ('0.' + [int]$TargetId.Substring(1)) -or
      [string]$baselineInfo.name -cne 'more-infinite-research' -or
      [string]$baselineInfo.version -cne [string]$Record.distribution_version -or
      [string]$baselineInfo.factorio_version -cne [string]$Record.factorio_line) {
    throw '[mir42-historical-authentication-baseline-identity]'
  }
  $baselineInfo.version = [string]$projectedBaseline.distribution_version
  $memberBytes['info.json'] = $utf8.GetBytes((($baselineInfo | ConvertTo-Json -Depth 20).Replace("`r`n", "`n") + "`n"))

  if ($SourceVersion -cne '4.2.0') {
    $baselineVersion = [string]$Record.distribution_version
    $distributionVersion = [string]$identity.distribution_version
    $readme = $utf8.GetString($memberBytes['README.md'])
    foreach ($anchor in @("# More Infinite Research $baselineVersion", "More Infinite Research $baselineVersion is", "more-infinite-research_$baselineVersion.zip")) {
      if ([regex]::Matches($readme, [regex]::Escape($anchor)).Count -ne 1) {
        throw "[mir42-historical-authentication-readme-maintenance-identity] $anchor"
      }
      $readme = $readme.Replace($anchor, $anchor.Replace($baselineVersion, $distributionVersion))
    }
    $memberBytes['README.md'] = $utf8.GetBytes($readme)

    $info = $utf8.GetString($memberBytes['info.json']) | ConvertFrom-Json -Depth 20 -DateKind String
    if ([string]$info.name -cne 'more-infinite-research' -or
        [string]$info.version -notin @([string]$projectedBaseline.distribution_version, [string]$identity.distribution_version) -or
        [string]$info.factorio_version -cne [string]$Record.factorio_line) {
      throw '[mir42-historical-authentication-maintenance-info]'
    }
    $info.version = [string]$identity.distribution_version
    $memberBytes['info.json'] = $utf8.GetBytes((($info | ConvertTo-Json -Depth 20).Replace("`r`n", "`n") + "`n"))

    $changelog = $utf8.GetString($memberBytes['changelog.txt']).Replace("`r`n", "`n")
    $firstVersion = [regex]::Match($changelog, '(?m)^Version:\s*(\S+)')
    if (-not $firstVersion.Success) { throw '[mir42-historical-authentication-changelog-identity]' }
    if ($firstVersion.Groups[1].Value -cne [string]$identity.distribution_version) {
      $entry = "---------------------------------------------------------------------------------------------------`nVersion: $($identity.distribution_version)`n  Info:`n    - Target package from source $SourceVersion.`n"
      if ($SourceVersion -ceq '4.4.1') {
        $entry += "  Fixes:`n    - Prevent multiplayer join failures caused by a load-only on_tick event registration.`n"
      } elseif ($SourceVersion -ceq '4.4.2') {
        $entry += "  Performance:`n    - Reuse lab acceptance data and approved bindings within each compilation.`n    - Avoid copying the public compiler snapshot solely to measure its serialized size.`n  Changes:`n    - Remove the obsolete Classic notice module and its inactive lifecycle hooks.`n"
        if ([string]$Record.factorio_line -ceq '0.15') {
          $entry += "  Fixes:`n    - Recognize Factorio 0.15 satellite launch results and retain approved science progression prerequisites.`n"
        } elseif ([string]$Record.factorio_line -ceq '0.16') {
          $entry += "  Fixes:`n    - Retain published Factorio 0.16 science progression prerequisites through checked declarations.`n"
        }
      }
      $changelog = $entry + $changelog
    }
    $memberBytes['changelog.txt'] = $utf8.GetBytes($changelog)
    $memberBytes['README.md'] = Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes $memberBytes['README.md'] -DistributionVersion ([string]$identity.distribution_version) -SourceVersion $SourceVersion
  }

  $members = @(
    foreach ($path in @($memberBytes.Keys | Sort-Object -CaseSensitive)) {
      $bytes = $memberBytes[$path]
      [pscustomobject][ordered]@{ path = $path; bytes = [int64]$bytes.Length; sha256 = Get-MIR4Sha256Bytes -Bytes $bytes }
    }
  )
  $lines = @($members | ForEach-Object { "$([string]$_.path)`t$([int64]$_.bytes)`t$([string]$_.sha256)" })
  $head = (& git -C $RepoRoot rev-parse HEAD).Trim()
  $tree = (& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
  if ($LASTEXITCODE -ne 0 -or $head -cnotmatch '^[a-f0-9]{40}$' -or $tree -cnotmatch '^[a-f0-9]{40}$') {
    throw '[mir42-historical-authentication-source-identity]'
  }
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42HistoricalCandidateAuthenticationProjectionV1'
    target = $TargetId
    source_version = $SourceVersion
    distribution_version = [string]$identity.distribution_version
    distribution_root = $distributionRoot
    factorio_line = [string]$Record.factorio_line
    source = [ordered]@{ commit = $head; tree = $tree }
    target_record = [ordered]@{ path = [IO.Path]::GetRelativePath($RepoRoot, $TargetRecordPath).Replace('\', '/'); sha256 = [string]$Record.record_sha256 }
    canonical_base = [ordered]@{
      target = 'f100'
      package_authority_sha256 = [string]$baseState.authority.record_sha256
      source_manifest_sha256 = [string]$baseState.manifest.record_sha256
      target_registry_sha256 = [string]$baseState.registry.record_sha256
      support_policy_sha256 = [string]$baseState.support.record_sha256
      target_overlay_sha256 = [string]$baseState.composition.record_sha256
      source_binding_count = @($baseSelection.bindings).Count
    }
    members = $members
    member_projection_sha256 = Get-MIR4Sha256String -Value ($lines -join "`n")
  }
}

function Assert-MIR42HistoricalAuthenticationProjectionInventory {
  param([Parameter(Mandatory)]$Projection, [Parameter(Mandatory)]$Inventory)
  $expected = @{}
  foreach ($entry in @($Projection.members)) {
    $path = [string]$entry.path
    if ($expected.ContainsKey($path)) { throw "[mir42-historical-authentication-projection-collision] $path" }
    $expected[$path] = $entry
  }
  if ([string]$Inventory.root -cne [string]$Projection.distribution_root -or
      [int]$Inventory.entry_count -ne $expected.Count) {
    throw '[mir42-historical-authentication-package-membership]'
  }
  foreach ($entry in @($Inventory.entries)) {
    $path = [string]$entry.path
    if (-not $expected.ContainsKey($path) -or [int64]$entry.raw_bytes -ne [int64]$expected[$path].bytes -or
        [string]$entry.raw_sha256 -cne [string]$expected[$path].sha256) {
      throw "[mir42-historical-authentication-package-member] $path"
    }
  }
}

$targetState = Get-MIR42HistoricalTargetRecord -TargetId $Target
$record = $targetState.record
$sourceManifest = Get-MIR42HistoricalSourceManifest
$sourceVersionParts = $SourceVersion.Split('.')
$sourceMinor = [int]$sourceVersionParts[1]
$sourcePatch = [int]$sourceVersionParts[2]
$baselineSourceVersion = "4.$sourceMinor.0"
$identity = New-MIR4DistributionIdentityProjection -DistributionTargetCode $Target.Substring(1) -SourceMinor $sourceMinor -SourcePatch $sourcePatch
$distributionVersion = [string]$identity.distribution_version
if ($AuthenticationProjection) {
  if ($RefreshSourceBindings -or $Check) { throw '[mir42-historical-authentication-projection-mode]' }
  Get-MIR42HistoricalCandidateAuthenticationProjection -RepoRoot $repo -TargetId $Target -Record $record -SourceManifest $sourceManifest `
    -SourceVersion $SourceVersion -TargetRecordPath $targetState.path
  return
}
if ($RefreshSourceBindings) {
  if ($SourceVersion -cne '4.2.0') { throw '[mir42-historical-refresh-source-version]' }
  if ($Check) { throw '[mir42-historical-refresh-check-conflict]' }
  foreach ($adapter in @($record.adapter_files)) {
    $bindings = @($sourceManifest.bindings | Where-Object {
      $record.target -in @($_.target_scope) -and [string]$_.output_path -ceq [string]$adapter.output_path -and
      [string]$_.source_path -ceq [string]$adapter.source_path
    })
    if ($bindings.Count -ne 1) { throw "[mir42-historical-refresh-binding] $($adapter.output_path)" }
    $adapter.source_bytes = [int64]$bindings[0].source_bytes
    $adapter.source_sha256 = [string]$bindings[0].source_sha256
    # Recompute prospective output pins using the same guarded transform as the
    # builder. Normal construction still checks both input and output pins.
    $prospective = $adapter | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $prospective.PSObject.Properties.Remove('output_bytes')
    $prospective.PSObject.Properties.Remove('output_sha256')
    $bytes = ConvertTo-MIR42HistoricalAdapterBytes -Adapter $prospective -Record $record -SourceManifest $sourceManifest
    $adapter | Add-Member -NotePropertyName output_bytes -NotePropertyValue ([int64]$bytes.Length) -Force
    $adapter | Add-Member -NotePropertyName output_sha256 -NotePropertyValue (Get-MIR4Sha256Bytes -Bytes $bytes) -Force
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  $json = ($record | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"
  [IO.File]::WriteAllText($targetState.path, $json, [Text.UTF8Encoding]::new($false))
  [pscustomobject]@{status='source-bindings-refreshed';target=$Target;build_performed=$false;record_sha256=$record.record_sha256} | ConvertTo-Json
  return
}
$output = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot)) }
$buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
$buildPrefix = $buildRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $output.StartsWith($buildPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "[mir42-historical-output-boundary] $output" }
New-Item -ItemType Directory -Force -Path $output | Out-Null

$sourceCommit = (& git -C $repo rev-parse HEAD).Trim()
$sourceTree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$memberProjection = Get-MIR42HistoricalCandidateAuthenticationProjection -RepoRoot $repo -TargetId $Target -Record $record -SourceManifest $sourceManifest `
  -SourceVersion $SourceVersion -TargetRecordPath $targetState.path
if ([string]$memberProjection.source.commit -cne $sourceCommit -or [string]$memberProjection.source.tree -cne $sourceTree -or
    [string]$memberProjection.distribution_version -cne $distributionVersion) {
  throw '[mir42-historical-authentication-projection-source]'
}
$rows = @()
foreach ($letter in @('A', 'B', 'C') | Select-Object -First $Repetitions) {
  $base = New-MIR4TargetPackage -RepoRoot $repo -Target ([string]$record.base_materializer_target) `
    -CandidateId "$CandidateId-BASE-$letter" -SourceVersion $baselineSourceVersion -OutputRoot (Join-Path $output 'base')
  $candidateParent = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath "$Target/$CandidateId/$letter"
  Remove-MIR4BuildTree -OutputRoot $output -Path $candidateParent
  New-Item -ItemType Directory -Force -Path $candidateParent | Out-Null
  $tree = Join-Path $candidateParent "more-infinite-research_$distributionVersion"
  Copy-Item -LiteralPath ([string]$base.tree_path) -Destination $tree -Recurse
  Copy-MIR42HistoricalAdapter -Tree $tree -Record $record -SourceManifest $sourceManifest
  Set-MIR42HistoricalBaselinePackageIdentity -Tree $tree -Record $record -BaselineSourceVersion $baselineSourceVersion
  if ($SourceVersion -in @('4.2.1','4.2.2','4.2.3','4.3.0','4.3.1','4.4.0','4.4.1','4.4.2','4.5.0')) {
    # Adapter output pins describe the baseline projection. Change only the
    # three current-package identity positions, preserving historical prose.
    $readmePath = Join-Path $tree 'README.md'
    $readme = [IO.File]::ReadAllText($readmePath)
    $baselineVersion = [string]$record.distribution_version
    foreach ($anchor in @("# More Infinite Research $baselineVersion", "More Infinite Research $baselineVersion is", "more-infinite-research_$baselineVersion.zip")) {
      if ([regex]::Matches($readme, [regex]::Escape($anchor)).Count -ne 1) { throw "[mir42-historical-readme-maintenance-identity] $anchor" }
      $readme = $readme.Replace($anchor, $anchor.Replace($baselineVersion, $distributionVersion))
    }
    [IO.File]::WriteAllText($readmePath, $readme, [Text.UTF8Encoding]::new($false))
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion $distributionVersion -SourceVersion $SourceVersion
  }
  $info = Get-Content -Raw -LiteralPath (Join-Path $tree 'info.json') | ConvertFrom-Json -Depth 20
  if ([string]$info.name -cne 'more-infinite-research' -or [string]$info.version -cne $distributionVersion -or
      [string]$info.factorio_version -cne [string]$record.factorio_line) {
    throw "[mir42-historical-info-identity] $Target"
  }
  $archive = Join-Path $candidateParent "more-infinite-research_$distributionVersion.zip"
  Write-MIR4DeterministicRawTreeArchive -SourceRoot $tree -EntryRoot (Split-Path -Leaf $tree) -OutputPath $archive -ContainmentRoot $output
  $inventory = Get-MIR4ArchiveInventory -Path $archive
  Assert-MIR42HistoricalAuthenticationProjectionInventory -Projection $memberProjection -Inventory $inventory
  $forbidden = @($inventory.entries | Where-Object { $_.path -match '^(?:\.mir|\.codex|\.github|build|dist|docs|tests|tools|scripts)/' })
  if ($forbidden.Count -gt 0) { throw "[mir42-historical-package-forbidden-path] $Target" }
  $rows += [pscustomobject][ordered]@{
    id = $letter
    archive_path = [IO.Path]::GetRelativePath($repo, $archive).Replace('\', '/')
    archive_sha256 = [string]$inventory.archive_sha256
    content_sha256 = [string]$inventory.content_sha256
    entry_count = [int]$inventory.entry_count
  }
}
if (@($rows.archive_sha256 | Sort-Object -Unique).Count -ne 1 -or @($rows.content_sha256 | Sort-Object -Unique).Count -ne 1) {
  throw "[mir42-historical-nondeterministic] $Target"
}
$distribution = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath "distributions/more-infinite-research_$distributionVersion.zip"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $distribution) | Out-Null
Copy-Item -LiteralPath (Join-Path $repo ([string]$rows[0].archive_path)) -Destination $distribution -Force
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $distribution).Hash -cne [string]$rows[0].archive_sha256) { throw "[mir42-historical-distribution-copy] $Target" }

$manifest = [pscustomobject][ordered]@{
  schema = 1
  kind = 'MIR42HistoricalPlaytestCandidateManifestV1'
  status = 'built-private-historical-unqualified'
  target = $Target
  maturity = [string]$record.maturity
  source = [ordered]@{ commit = $sourceCommit; tree = $sourceTree; canonical_base_target = [string]$record.base_materializer_target }
  target_record = [ordered]@{ path = [IO.Path]::GetRelativePath($repo, $targetState.path).Replace('\', '/'); sha256 = [string]$record.record_sha256 }
  factorio_line = [string]$record.factorio_line
  distribution_version = $distributionVersion
  engine = $record.engine
  predecessor = $record.predecessor
  authentication_projection = [ordered]@{
    schema = [int]$memberProjection.schema
    kind = [string]$memberProjection.kind
    source_version = [string]$memberProjection.source_version
    distribution_root = [string]$memberProjection.distribution_root
    canonical_base = $memberProjection.canonical_base
    member_count = @($memberProjection.members).Count
    member_projection_sha256 = [string]$memberProjection.member_projection_sha256
  }
  builds = $rows
  distribution = [ordered]@{ path = [IO.Path]::GetRelativePath($repo, $distribution).Replace('\', '/'); sha256 = [string]$rows[0].archive_sha256; content_sha256 = [string]$rows[0].content_sha256; entry_count = [int]$rows[0].entry_count }
  # This row is a construction input for a later combined candidate.  It does
  # not alter the private historical target authority or grant an admission.
  candidate_row = [ordered]@{
    schema = 1
    kind = 'MIR42HistoricalCandidateRowV1'
    status = 'deterministic-historical-candidate-construction-input-unqualified'
    target = $Target
    source = [ordered]@{ commit = $sourceCommit; tree = $sourceTree }
    source_version = $SourceVersion
    distribution_version = $distributionVersion
    base_materializer_target = [string]$record.base_materializer_target
    target_record = [ordered]@{ path = [IO.Path]::GetRelativePath($repo, $targetState.path).Replace('\', '/'); sha256 = [string]$record.record_sha256 }
    asset = [ordered]@{
      path = [IO.Path]::GetRelativePath($output, $distribution).Replace('\', '/')
      bytes = [Int64](Get-Item -LiteralPath $distribution).Length
      sha256 = [string]$rows[0].archive_sha256
    }
    content_sha256 = [string]$rows[0].content_sha256
    entry_count = [int]$rows[0].entry_count
    build_a_sha256 = [string]$rows[0].archive_sha256
    build_b_sha256 = [string]$rows[1].archive_sha256
    deterministic_archive_bytes = $true
    package_excluded_surface = $true
    qualification = 'not-performed-in-this-construction-record'
    technical_seal = 'not-performed'
    signing = 'not-performed'
    public_output_authorized = $false
    publication_authorized = $false
  }
  assertions = @('current-canonical-f100-base-materialization', 'source-manifest-authoritative-adapter-selection', 'target-specific-profile-adapter', 'target-specific-metadata', 'bounded-research-cost-publication-omission', 'byte-identical-repeated-builds', 'package-path-exclusion', 'canonical-in-memory-member-authentication-projection')
  exact_engine_runtime = 'not-run'
  public_output_authorized = $false
  publication_authorized = $false
  record_sha256 = ''
}
$manifest.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $manifest
$manifestPath = Resolve-MIR4ArtifactPath -OutputRoot $output -RelativePath "manifests/$Target.json"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifestPath) | Out-Null
$manifest | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $manifestPath -Encoding utf8
if ($Check) {
  $current = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 50
  if (-not (Test-MIR4BootstrapRecordHash -Record $current) -or [string]$current.distribution.sha256 -cne [string]$rows[0].archive_sha256) {
    throw "[mir42-historical-manifest-check] $Target"
  }
}
$manifest
