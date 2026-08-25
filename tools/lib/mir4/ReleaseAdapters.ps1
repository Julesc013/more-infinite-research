Set-StrictMode -Version Latest

function Get-MIR4ReleaseAdapterRelativePath {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
  return ([IO.Path]::GetRelativePath($RepoRoot,[IO.Path]::GetFullPath($Path))).Replace('\','/')
}

function Assert-MIR4ReleaseAdapterContext {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Phase)
  if ([string]$Context.kind -cne 'MIR4ReleasePhaseAdapterContextV1' -or [string]$Context.plan.phase -cne $Phase -or
      -not [bool]$Context.non_production -or [bool]$Context.production_authorized) {
    throw "[mir4-release-adapter-context] $Phase"
  }
  $attempt = [IO.Path]::GetFullPath([string]$Context.attempt_root).TrimEnd('\','/')
  $artifact = [IO.Path]::GetFullPath([string]$Context.artifact_root)
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if (-not $artifact.StartsWith($attempt + [IO.Path]::DirectorySeparatorChar,$comparison)) {
    throw "[mir4-release-adapter-artifact-boundary] $artifact"
  }
  foreach ($port in @($Context.ports)) {
    if ([string]$port.id -in @('sign','publish') -and [string]$port.mode -cne 'denied') {
      throw "[mir4-release-adapter-production-port] $($port.id)"
    }
  }
  return [pscustomobject][ordered]@{repo=(Resolve-Path -LiteralPath $RepoRoot).Path;attempt_root=$attempt;artifact_root=$artifact}
}

function Get-MIR4ReleaseAdapterFileDescriptor {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
  $full = [IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-release-adapter-artifact-missing] $full" }
  $item = Get-Item -LiteralPath $full
  return [pscustomobject][ordered]@{
    path=Get-MIR4ReleaseAdapterRelativePath -RepoRoot $RepoRoot -Path $full
    sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
    bytes=[long]$item.Length
  }
}

function Write-MIR4ReleaseAdapterRecord {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$Path)
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $existing = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100
    if ((ConvertTo-MIR4ReleasePhaseCanonicalJson $existing) -cne (ConvertTo-MIR4ReleasePhaseCanonicalJson $Record)) {
      throw "[mir4-release-adapter-artifact-divergence] $Path"
    }
    return
  }
  Write-MIR4ReleasePhaseJsonCreateNew -Value $Record -Path $Path
}

function Test-MIR4ReleaseAdapterResultSchema {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Schema,[Parameter(Mandatory)]$Result)
  $json = $Result | ConvertTo-Json -Depth 100
  if (-not ($json | Test-Json -SchemaFile (Join-Path $RepoRoot $Schema))) {
    throw "[mir4-release-adapter-result-schema] $Schema"
  }
  return $Result
}

function Get-MIR4ReleaseAdapterSourceState {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Context)
  $commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  $tree = (& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
  $tracked = @(& git -C $RepoRoot status --porcelain=v1 --untracked-files=no)
  if ($commit -cne [string]$Context.plan.identity.source_commit -or $tree -cne [string]$Context.plan.identity.source_tree) {
    throw '[mir4-release-adapter-source-identity]'
  }
  if ($tracked.Count -ne 0) { throw '[mir4-release-adapter-dirty-source]' }
  return [pscustomobject][ordered]@{commit=$commit;tree=$tree;tracked_clean=$true;refs_mutated=$false}
}

function New-MIR4SourceFreezeAdapterResult {
  param([string]$RepoRoot,$Context,[string]$Operation,$Source,[object[]]$Artifacts,[string[]]$Checks)
  $result = [pscustomobject][ordered]@{
    schema=1;kind='MIR4ReleasePhaseAdapterResultV1';phase='source-freeze';phase_result_kind='MIR4SourceFreezePhaseResultV1'
    operation=$Operation;status='passed';idempotency_key=[string]$Context.idempotency_key
    artifact_root=Get-MIR4ReleaseAdapterRelativePath -RepoRoot $RepoRoot -Path ([string]$Context.artifact_root)
    production_mutation_performed=$false;release_transition_performed=$false;source=$Source
    artifacts=@($Artifacts);checks=@($Checks|Sort-Object -CaseSensitive -Unique)
  }
  return Test-MIR4ReleaseAdapterResultSchema -RepoRoot $RepoRoot -Schema 'spec/schemas/mir4-release-source-freeze-result-v1.schema.json' -Result $result
}

function Invoke-MIR4SourceFreezeAdapter {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Context)
  $boundary = Assert-MIR4ReleaseAdapterContext -RepoRoot $RepoRoot -Context $Context -Phase 'source-freeze'
  $source = Get-MIR4ReleaseAdapterSourceState -RepoRoot $boundary.repo -Context $Context
  $executeArtifactRoot = Join-Path $boundary.attempt_root 'artifacts/execute'
  $manifestPath = Join-Path $executeArtifactRoot 'source-freeze-rehearsal.json'
  switch ([string]$Context.operation) {
    'DryRun' {
      return New-MIR4SourceFreezeAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation DryRun -Source $source -Artifacts @() -Checks @(
        'exact-source-identity','tracked-tree-clean','governed-input-records-bound','git-port-read-only','candidate-unallocated','production-transition-denied')
    }
    'Execute' {
      $record = [pscustomobject][ordered]@{
        schema=1;kind='MIR4SourceFreezeRehearsalManifestV1';candidate_id=[string]$Context.plan.identity.candidate_id
        source=$source;source_release_record=$Context.plan.identity.source_release_record
        target_distribution_record_set=$Context.plan.identity.target_distribution_record_set
        release_plan_digest=[string]$Context.plan.identity.release_plan_digest
        proof_root=[string]$Context.plan.identity.proof_root;seal_root=[string]$Context.plan.identity.seal_root
        source_frozen=$false;candidate_allocated=$false;production_authorized=$false;record_sha256=''
      }
      $record.record_sha256 = Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty 'record_sha256'
      Write-MIR4ReleaseAdapterRecord -Record $record -Path $manifestPath
      $artifact = Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $manifestPath
      return New-MIR4SourceFreezeAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Execute -Source $source -Artifacts @($artifact) -Checks @(
        'sandbox-manifest-created','source-freeze-not-performed','candidate-allocation-not-performed','refs-unchanged')
    }
    'Verify' {
      $record = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
      if ([string]$record.kind -cne 'MIR4SourceFreezeRehearsalManifestV1' -or
          [string]$record.record_sha256 -cne (Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty 'record_sha256') -or
          [string]$record.source.commit -cne [string]$source.commit -or [string]$record.source.tree -cne [string]$source.tree -or
          [bool]$record.source_frozen -or [bool]$record.candidate_allocated -or [bool]$record.production_authorized) {
        throw '[mir4-source-freeze-rehearsal-verification]'
      }
      $artifact = Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $manifestPath
      return New-MIR4SourceFreezeAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Verify -Source $source -Artifacts @($artifact) -Checks @(
        'sandbox-manifest-self-hash','exact-source-reverified','production-boundary-reverified')
    }
    'Compensate' {
      $artifact = Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $manifestPath
      Remove-Item -LiteralPath $manifestPath -Force
      return New-MIR4SourceFreezeAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Compensate -Source $source -Artifacts @($artifact) -Checks @(
        'sandbox-manifest-removed','repository-unchanged','refs-unchanged')
    }
    default { throw "[mir4-source-freeze-adapter-operation] $($Context.operation)" }
  }
}

function Get-MIR4TargetBuildRows {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Context)
  $relative = [string]$Context.plan.identity.target_distribution_record_set.path
  $record = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $relative) | ConvertFrom-Json -Depth 100
  $rows = @($record.targets | Where-Object { ([string]$_.target).ToUpperInvariant() -in @('F210','F200') } | Sort-Object { ([string]$_.target).ToUpperInvariant() })
  $targetSet = (@($rows | ForEach-Object { ([string]$_.target).ToUpperInvariant() } | Sort-Object) -join '|')
  if ($rows.Count -ne 2 -or $targetSet -cne 'F200|F210') {
    throw '[mir4-target-build-mandatory-target-set]'
  }
  foreach ($row in $rows) {
    $target = ([string]$row.target).ToUpperInvariant()
    $expected = if ($target -ceq 'F210') { '4.0.21000' } else { '4.0.20000' }
    if ([string]$row.distribution_version -cne $expected) { throw "[mir4-target-build-version] $target" }
  }
  return @($rows)
}

function Invoke-MIR4DefaultTargetBuildDelegate {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$OutputRoot)
  $key = $Target.ToLowerInvariant()
  $lane = if ($key -ceq 'f210') { 'emergency' } else { 'local-playtest-shadow' }
  & (Join-Path $RepoRoot 'tools/commands/release/New-MIR4BootstrapLocalCandidate.ps1') -RepoRoot $RepoRoot -Target $key -Lane $lane -OutputRoot $OutputRoot -Repetitions 3 | Out-Null
  $manifestPath = Join-Path $OutputRoot "manifests/$key.json"
  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
  $packagePath = Join-Path $OutputRoot ([string]$manifest.local_distribution.path)
  return [pscustomobject][ordered]@{
    target=$Target;distribution_version=[string]$manifest.distribution_version;state='built-private-unqualified'
    manifest=Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $RepoRoot -Path $manifestPath
    package=Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $RepoRoot -Path $packagePath
    content_sha256=[string]$manifest.local_distribution.content_sha256;entry_count=[int]$manifest.local_distribution.entry_count
    source_frozen=$false;release_identity=$false;publication_authorized=$false
  }
}

function New-MIR4TargetBuildAdapterResult {
  param([string]$RepoRoot,$Context,[string]$Operation,[string]$PackageSourceSha256,[object[]]$Targets,[object[]]$Artifacts,[string[]]$Checks)
  $result = [pscustomobject][ordered]@{
    schema=1;kind='MIR4ReleasePhaseAdapterResultV1';phase='target-build';phase_result_kind='MIR4TargetBuildPhaseResultV1'
    operation=$Operation;status='passed';idempotency_key=[string]$Context.idempotency_key
    artifact_root=Get-MIR4ReleaseAdapterRelativePath -RepoRoot $RepoRoot -Path ([string]$Context.artifact_root)
    production_mutation_performed=$false;release_transition_performed=$false
    package_source_sha256=$PackageSourceSha256;targets=@($Targets);artifacts=@($Artifacts)
    checks=@($Checks|Sort-Object -CaseSensitive -Unique)
  }
  return Test-MIR4ReleaseAdapterResultSchema -RepoRoot $RepoRoot -Schema 'spec/schemas/mir4-release-target-build-result-v1.schema.json' -Result $result
}

function Invoke-MIR4TargetBuildAdapter {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Context,[Parameter(Mandatory)][scriptblock]$Constructor)
  $boundary = Assert-MIR4ReleaseAdapterContext -RepoRoot $RepoRoot -Context $Context -Phase 'target-build'
  $source = Get-MIR4ReleaseAdapterSourceState -RepoRoot $boundary.repo -Context $Context
  $rows = @(Get-MIR4TargetBuildRows -RepoRoot $boundary.repo -Context $Context)
  . (Join-Path $boundary.repo 'tools/lib/validation/PackageIdentity.ps1')
  $packageSource = Get-MIRPackageSourceFingerprint -RepoRoot $boundary.repo
  $executeArtifactRoot = Join-Path $boundary.attempt_root 'artifacts/execute'
  $aggregatePath = Join-Path $executeArtifactRoot 'target-build-rehearsal.json'
  switch ([string]$Context.operation) {
    'DryRun' {
      $targets = @($rows | ForEach-Object {
        [pscustomobject][ordered]@{target=([string]$_.target).ToUpperInvariant();distribution_version=[string]$_.distribution_version;state='planned-private-build';manifest=$null;package=$null;content_sha256=$null;entry_count=$null;source_frozen=$false;release_identity=$false;publication_authorized=$false}
      })
      return New-MIR4TargetBuildAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation DryRun -PackageSourceSha256 $packageSource -Targets $targets -Artifacts @() -Checks @(
        'exact-source-identity','tracked-tree-clean','mandatory-target-cardinality','distribution-identities','package-source-fingerprint','attempt-local-output','production-transition-denied')
    }
    'Execute' {
      $targets = @()
      foreach ($row in $rows) {
        $target = ([string]$row.target).ToUpperInvariant()
        $targetRoot = Join-Path $boundary.artifact_root ("targets/" + $target.ToLowerInvariant())
        New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
        $built = & $Constructor $boundary.repo $target $targetRoot
        if ([string]$built.target -cne $target -or [string]$built.distribution_version -cne [string]$row.distribution_version -or
            [bool]$built.source_frozen -or [bool]$built.release_identity -or [bool]$built.publication_authorized) {
          throw "[mir4-target-build-delegate-result] $target"
        }
        $targets += $built
      }
      $record = [pscustomobject][ordered]@{
        schema=1;kind='MIR4TargetBuildRehearsalManifestV1';candidate_id=[string]$Context.plan.identity.candidate_id
        source=$source;package_source_sha256=$packageSource;targets=@($targets)
        source_frozen=$false;release_identity=$false;production_authorized=$false;publication_authorized=$false;record_sha256=''
      }
      $record.record_sha256 = Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty 'record_sha256'
      Write-MIR4ReleaseAdapterRecord -Record $record -Path $aggregatePath
      $artifact = Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $aggregatePath
      return New-MIR4TargetBuildAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Execute -PackageSourceSha256 $packageSource -Targets $targets -Artifacts @($artifact) -Checks @(
        'delegated-existing-materializers','f210-f200-private-products','aggregate-self-hash','release-identity-not-created','dist-untouched')
    }
    'Verify' {
      $record = Get-Content -Raw -LiteralPath $aggregatePath | ConvertFrom-Json -Depth 100
      if ([string]$record.kind -cne 'MIR4TargetBuildRehearsalManifestV1' -or
          [string]$record.record_sha256 -cne (Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty 'record_sha256') -or
          [string]$record.source.commit -cne [string]$source.commit -or [string]$record.package_source_sha256 -cne $packageSource -or
          @($record.targets).Count -ne 2 -or [bool]$record.source_frozen -or [bool]$record.release_identity -or
          [bool]$record.production_authorized -or [bool]$record.publication_authorized) {
        throw '[mir4-target-build-rehearsal-verification]'
      }
      foreach ($target in @($record.targets)) {
        foreach ($artifact in @($target.manifest,$target.package)) {
          $path = Join-Path $boundary.repo ([string]$artifact.path)
          if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$artifact.sha256) {
            throw "[mir4-target-build-artifact-hash] $($artifact.path)"
          }
        }
      }
      $artifact = Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $aggregatePath
      return New-MIR4TargetBuildAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Verify -PackageSourceSha256 $packageSource -Targets @($record.targets) -Artifacts @($artifact) -Checks @(
        'aggregate-self-hash','package-byte-hashes','manifest-byte-hashes','mandatory-target-cardinality','production-boundary-reverified')
    }
    'Compensate' {
      $artifact = Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $aggregatePath
      $targetsRoot = Join-Path $boundary.artifact_root 'targets'
      if (Test-Path -LiteralPath $targetsRoot -PathType Container) { Remove-Item -LiteralPath $targetsRoot -Recurse -Force }
      Remove-Item -LiteralPath $aggregatePath -Force
      return New-MIR4TargetBuildAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Compensate -PackageSourceSha256 $packageSource -Targets @() -Artifacts @($artifact) -Checks @(
        'attempt-local-products-removed','repository-unchanged','dist-untouched')
    }
    default { throw "[mir4-target-build-adapter-operation] $($Context.operation)" }
  }
}

function Get-MIR4ReleasePhaseAdapter {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Phase,[scriptblock]$TargetConstructor,[string]$TargetConstructorIdentity='')
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $phaseEngineLibraryPath = Join-Path $repo 'tools/lib/mir4/ReleasePhaseEngine.ps1'
  $adapterLibraryPath = Join-Path $repo 'tools/lib/mir4/ReleaseAdapters.ps1'
  $implementation = (Get-FileHash -LiteralPath $adapterLibraryPath -Algorithm SHA256).Hash.ToUpperInvariant()
  switch ($Phase) {
    'source-freeze' {
      $invoke = { param($Context) . $phaseEngineLibraryPath; . $adapterLibraryPath; Invoke-MIR4SourceFreezeAdapter -RepoRoot $repo -Context $Context }.GetNewClosure()
      return [pscustomobject][ordered]@{
        descriptor=[pscustomobject][ordered]@{id='mir4.source-freeze.rehearsal.v1';version=1;implementation_sha256=$implementation;production_capable=$false;supported_operations=@('DryRun','Execute','Verify','Compensate');required_ports=@('git','build');result_schema='spec/schemas/mir4-release-source-freeze-result-v1.schema.json'}
        invoke=$invoke
      }
    }
    'target-build' {
      $useDefaultConstructor = $null -eq $TargetConstructor
      if ($useDefaultConstructor) { $TargetConstructor = ${function:Invoke-MIR4DefaultTargetBuildDelegate} }
      if ([string]::IsNullOrWhiteSpace($TargetConstructorIdentity)) { $TargetConstructorIdentity = Get-MIR4ReleasePhaseSha256 ([string]$TargetConstructor) }
      $constructor = $TargetConstructor
      $invoke = {
        param($Context)
        . $phaseEngineLibraryPath
        . $adapterLibraryPath
        $effectiveConstructor = if ($useDefaultConstructor) { ${function:Invoke-MIR4DefaultTargetBuildDelegate} } else { $constructor }
        Invoke-MIR4TargetBuildAdapter -RepoRoot $repo -Context $Context -Constructor $effectiveConstructor
      }.GetNewClosure()
      return [pscustomobject][ordered]@{
        descriptor=[pscustomobject][ordered]@{id='mir4.target-build.rehearsal.v1';version=1;implementation_sha256=$implementation;delegate_sha256=$TargetConstructorIdentity;production_capable=$false;supported_operations=@('DryRun','Execute','Verify','Compensate');required_ports=@('git','build');result_schema='spec/schemas/mir4-release-target-build-result-v1.schema.json'}
        invoke=$invoke
      }
    }
    default { throw "[mir4-release-adapter-not-implemented] $Phase" }
  }
}
