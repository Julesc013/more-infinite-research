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

function Get-MIR4ReleaseAdapterProofRoot {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Context)
  $value = [string]$Context.plan.identity.proof_root
  $full = if ([IO.Path]::IsPathRooted($value)) { [IO.Path]::GetFullPath($value) } else { [IO.Path]::GetFullPath((Join-Path $RepoRoot $value)) }
  $boundary = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if (-not $full.StartsWith($boundary,$comparison)) { throw "[mir4-release-adapter-proof-boundary] $full" }
  return $full
}

function Get-MIR4TargetQualificationExpectations {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Context)
  $rows = @(Get-MIR4TargetBuildRows -RepoRoot $RepoRoot -Context $Context)
  return @($rows | ForEach-Object {
    [pscustomobject][ordered]@{
      target=([string]$_.target).ToUpperInvariant()
      distribution_version=[string]$_.distribution_version
      package=[pscustomobject][ordered]@{
        sha256=([string]$_.development_package.sha256).ToUpperInvariant()
        content_sha256=([string]$_.development_package.content_sha256).ToUpperInvariant()
        bytes=[long]$_.development_package.bytes
        entry_count=[int]$_.development_package.entry_count
      }
      engine=[pscustomobject][ordered]@{
        version=[string]$_.engine.version
        path=[string]$_.engine.path
        sha256=([string]$_.engine.sha256).ToUpperInvariant()
      }
    }
  })
}

function Invoke-MIR4DefaultQualificationWorkerProvider {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)]$Expected,[Parameter(Mandatory)]$Context)
  $proofRoot = Get-MIR4ReleaseAdapterProofRoot -RepoRoot $RepoRoot -Context $Context
  $path = Join-Path $proofRoot ("qualification-workers/" + $Target.ToLowerInvariant() + ".json")
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-target-qualification-worker-missing] $Target" }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
}

function Assert-MIR4TargetQualificationWorkerReceipt {
  param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$Expected,[Parameter(Mandatory)]$Context)
  if ([string]$Receipt.kind -cne 'MIR4TargetQualificationWorkerReceiptV1' -or [int]$Receipt.schema -ne 1 -or
      [string]$Receipt.status -cne 'passed' -or [string]::IsNullOrWhiteSpace([string]$Receipt.producer_id) -or
      [string]$Receipt.record_sha256 -cne (Get-MIR4ReleasePhaseSelfHash -Record $Receipt -HashProperty 'record_sha256') -or
      [string]$Receipt.source_commit -cne [string]$Context.plan.identity.source_commit -or
      [string]$Receipt.source_tree -cne [string]$Context.plan.identity.source_tree -or
      [string]$Receipt.release_plan_digest -cne [string]$Context.plan.identity.release_plan_digest -or
      [string]$Receipt.target -cne [string]$Expected.target -or
      [string]$Receipt.distribution_version -cne [string]$Expected.distribution_version -or
      ([string]$Receipt.package.sha256).ToUpperInvariant() -cne [string]$Expected.package.sha256 -or
      ([string]$Receipt.package.content_sha256).ToUpperInvariant() -cne [string]$Expected.package.content_sha256 -or
      [long]$Receipt.package.bytes -ne [long]$Expected.package.bytes -or
      [int]$Receipt.package.entry_count -ne [int]$Expected.package.entry_count -or
      [string]$Receipt.engine.version -cne [string]$Expected.engine.version -or
      [string]$Receipt.engine.path -cne [string]$Expected.engine.path -or
      ([string]$Receipt.engine.sha256).ToUpperInvariant() -cne [string]$Expected.engine.sha256 -or
      [string]$Receipt.evidence_sha256 -cnotmatch '^[A-F0-9]{64}$' -or
      [bool]$Receipt.release_identity -or [bool]$Receipt.publication_authorized) {
    throw "[mir4-target-qualification-worker-mismatch] $($Expected.target)"
  }
  return $Receipt
}

function New-MIR4TargetQualificationAdapterResult {
  param([string]$RepoRoot,$Context,[string]$Operation,[object[]]$Targets,[object[]]$Artifacts,[int]$Adopted,[string[]]$Checks)
  $result = [pscustomobject][ordered]@{
    schema=1;kind='MIR4ReleasePhaseAdapterResultV1';phase='target-qualification';phase_result_kind='MIR4TargetQualificationPhaseResultV1'
    operation=$Operation;status='passed';idempotency_key=[string]$Context.idempotency_key
    artifact_root=Get-MIR4ReleaseAdapterRelativePath -RepoRoot $RepoRoot -Path ([string]$Context.artifact_root)
    production_mutation_performed=$false;release_transition_performed=$false
    targets=@($Targets);worker_receipts_adopted=$Adopted;artifacts=@($Artifacts)
    checks=@($Checks|Sort-Object -CaseSensitive -Unique)
  }
  return Test-MIR4ReleaseAdapterResultSchema -RepoRoot $RepoRoot -Schema 'spec/schemas/mir4-release-target-qualification-result-v1.schema.json' -Result $result
}

function Invoke-MIR4TargetQualificationAdapter {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Context,[Parameter(Mandatory)][scriptblock]$WorkerProvider)
  $boundary = Assert-MIR4ReleaseAdapterContext -RepoRoot $RepoRoot -Context $Context -Phase 'target-qualification'
  $source = Get-MIR4ReleaseAdapterSourceState -RepoRoot $boundary.repo -Context $Context
  $expected = @(Get-MIR4TargetQualificationExpectations -RepoRoot $boundary.repo -Context $Context)
  $executeRoot = Join-Path $boundary.attempt_root 'artifacts/execute'
  $planPath = Join-Path $executeRoot 'verification-plan.json'
  $targetRoot = Join-Path $executeRoot 'worker-receipts'
  $aggregatePath = Join-Path $executeRoot 'target-qualification.json'
  switch ([string]$Context.operation) {
    'DryRun' {
      $targets = @($expected | ForEach-Object {
        [pscustomobject][ordered]@{target=$_.target;distribution_version=$_.distribution_version;state='planned-exact-qualification';package_sha256=$_.package.sha256;engine_sha256=$_.engine.sha256;evidence_sha256=$null;receipt=$null;release_identity=$false;publication_authorized=$false}
      })
      return New-MIR4TargetQualificationAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation DryRun -Targets $targets -Artifacts @() -Adopted 0 -Checks @(
        'exact-source-identity','mandatory-target-cardinality','package-identities-bound','engine-identities-bound','worker-receipt-import-required','partial-evidence-preserved','production-transition-denied')
    }
    'Execute' {
      New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
      $plan = [pscustomobject][ordered]@{
        schema=1;kind='MIR4TargetQualificationVerificationPlanV1';candidate_id=[string]$Context.plan.identity.candidate_id
        source=$source;release_plan_digest=[string]$Context.plan.identity.release_plan_digest
        targets=@($expected);worker_policy='exact-content-addressed-adopt-or-run';release_identity=$false;production_authorized=$false;record_sha256=''
      }
      $plan.record_sha256 = Get-MIR4ReleasePhaseSelfHash -Record $plan -HashProperty 'record_sha256'
      Write-MIR4ReleaseAdapterRecord -Record $plan -Path $planPath
      $targets = @(); $adopted = 0
      foreach ($expectation in $expected) {
        $receiptPath = Join-Path $targetRoot ($expectation.target.ToLowerInvariant() + '.json')
        if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
          $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100
          $adopted++
        } else {
          $receipt = & $WorkerProvider $boundary.repo ([string]$expectation.target) $expectation $Context
        }
        $receipt = Assert-MIR4TargetQualificationWorkerReceipt -Receipt $receipt -Expected $expectation -Context $Context
        Write-MIR4ReleaseAdapterRecord -Record $receipt -Path $receiptPath
        $targets += [pscustomobject][ordered]@{
          target=[string]$expectation.target;distribution_version=[string]$expectation.distribution_version;state='qualified-private'
          package_sha256=[string]$expectation.package.sha256;engine_sha256=[string]$expectation.engine.sha256
          evidence_sha256=[string]$receipt.evidence_sha256
          receipt=Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $receiptPath
          release_identity=$false;publication_authorized=$false
        }
      }
      $record = [pscustomobject][ordered]@{
        schema=1;kind='MIR4TargetQualificationRehearsalManifestV1';candidate_id=[string]$Context.plan.identity.candidate_id
        source=$source;verification_plan=Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $planPath
        targets=@($targets);successful_partial_evidence_preserved=$true;release_identity=$false;production_authorized=$false;publication_authorized=$false;record_sha256=''
      }
      $record.record_sha256 = Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty 'record_sha256'
      Write-MIR4ReleaseAdapterRecord -Record $record -Path $aggregatePath
      return New-MIR4TargetQualificationAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Execute -Targets $targets -Artifacts @(
        (Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $planPath),
        (Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $aggregatePath)
      ) -Adopted $adopted -Checks @('verification-plan-materialized','exact-worker-receipts-imported','successful-partial-evidence-preserved','aggregate-self-hash','release-identity-not-created')
    }
    'Verify' {
      $plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json -Depth 100
      $record = Get-Content -Raw -LiteralPath $aggregatePath | ConvertFrom-Json -Depth 100
      if ([string]$plan.record_sha256 -cne (Get-MIR4ReleasePhaseSelfHash -Record $plan -HashProperty 'record_sha256') -or
          [string]$record.record_sha256 -cne (Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty 'record_sha256') -or
          [string]$record.source.commit -cne [string]$source.commit -or @($record.targets).Count -ne 2 -or
          -not [bool]$record.successful_partial_evidence_preserved -or [bool]$record.release_identity -or
          [bool]$record.production_authorized -or [bool]$record.publication_authorized) {
        throw '[mir4-target-qualification-verification]'
      }
      foreach ($expectation in $expected) {
        $path = Join-Path $targetRoot ($expectation.target.ToLowerInvariant() + '.json')
        $receipt = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
        $null = Assert-MIR4TargetQualificationWorkerReceipt -Receipt $receipt -Expected $expectation -Context $Context
      }
      return New-MIR4TargetQualificationAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Verify -Targets @($record.targets) -Artifacts @(
        (Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $planPath),
        (Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $aggregatePath)
      ) -Adopted 2 -Checks @('verification-plan-self-hash','worker-receipt-self-hashes','target-engine-package-evidence-bindings','production-boundary-reverified')
    }
    'Compensate' {
      $artifacts = @($planPath,$aggregatePath | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $_ })
      if (Test-Path -LiteralPath $executeRoot -PathType Container) { Remove-Item -LiteralPath $executeRoot -Recurse -Force }
      return New-MIR4TargetQualificationAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Compensate -Targets @() -Artifacts $artifacts -Adopted 0 -Checks @('attempt-local-plan-and-evidence-removed','repository-unchanged','release-identity-not-created')
    }
    default { throw "[mir4-target-qualification-adapter-operation] $($Context.operation)" }
  }
}

function Invoke-MIR4DefaultPreviewBuilder {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$OutputRoot)
  . (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
  return New-MIR4PlatformPreviewPackages -RepoRoot $RepoRoot -OutputRoot $OutputRoot
}

function New-MIR4PreviewAssetsAdapterResult {
  param([string]$RepoRoot,$Context,[string]$Operation,[object[]]$Assets,[object[]]$Artifacts,[string[]]$Checks)
  $result = [pscustomobject][ordered]@{
    schema=1;kind='MIR4ReleasePhaseAdapterResultV1';phase='preview-assets';phase_result_kind='MIR4PreviewAssetsPhaseResultV1'
    operation=$Operation;status='passed';idempotency_key=[string]$Context.idempotency_key
    artifact_root=Get-MIR4ReleaseAdapterRelativePath -RepoRoot $RepoRoot -Path ([string]$Context.artifact_root)
    production_mutation_performed=$false;release_transition_performed=$false
    assets=@($Assets);artifacts=@($Artifacts);checks=@($Checks|Sort-Object -CaseSensitive -Unique)
  }
  return Test-MIR4ReleaseAdapterResultSchema -RepoRoot $RepoRoot -Schema 'spec/schemas/mir4-release-preview-assets-result-v1.schema.json' -Result $result
}

function Invoke-MIR4PreviewAssetsAdapter {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Context,[Parameter(Mandatory)][scriptblock]$Builder)
  $boundary = Assert-MIR4ReleaseAdapterContext -RepoRoot $RepoRoot -Context $Context -Phase 'preview-assets'
  $source = Get-MIR4ReleaseAdapterSourceState -RepoRoot $boundary.repo -Context $Context
  $executeRoot = Join-Path $boundary.attempt_root 'artifacts/execute'
  $outputRoot = Join-Path $executeRoot 'preview'
  $manifestPath = Join-Path $outputRoot 'preview-assets.json'
  $contract = @('mir4-api-sdk-v1-preview.zip','mir4-mep-v1-preview.zip','mir4-reference-extension-v1-preview.zip','mir4-inspector-v1-preview.zip')
  switch ([string]$Context.operation) {
    'DryRun' {
      return New-MIR4PreviewAssetsAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation DryRun -Assets @() -Artifacts @() -Checks @(
        'exact-source-identity','tracked-tree-clean','four-asset-contract','deterministic-archive-builder','attempt-local-output','publication-denied')
    }
    'Execute' {
      $manifest = & $Builder $boundary.repo $outputRoot
      if ([string]$manifest.kind -cne 'MIR4PreviewAssetSetV1' -or
          [string]$manifest.source.commit -cne [string]$source.commit -or [string]$manifest.source.tree -cne [string]$source.tree -or
          (@($manifest.asset_contract | Sort-Object) -join '|') -cne (@($contract | Sort-Object) -join '|') -or
          [string]$manifest.candidate_state -cne 'pre-freeze-unallocated' -or [string]$manifest.publication -cne 'github-preview-only-not-mod-portal') {
        throw '[mir4-preview-assets-builder-result]'
      }
      $assets = @($manifest.assets | Sort-Object name | ForEach-Object {
        $path = Join-Path $outputRoot ([string]$_.name)
        $descriptor = Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path
        if ([string]$descriptor.sha256 -cne ([string]$_.sha256).ToUpperInvariant() -or [long]$descriptor.bytes -ne [long]$_.bytes) { throw "[mir4-preview-assets-byte-binding] $($_.name)" }
        [pscustomobject][ordered]@{name=[string]$_.name;sha256=[string]$descriptor.sha256;bytes=[long]$descriptor.bytes}
      })
      return New-MIR4PreviewAssetsAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Execute -Assets $assets -Artifacts @(
        (Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $manifestPath)
      ) -Checks @('four-assets-created','exact-output-set','embedded-manifests-sbom-provenance','source-identity-bound','mod-portal-publication-denied')
    }
    'Verify' {
      . (Join-Path $boundary.repo 'tools/lib/mir4/PlatformPreview.ps1')
      $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
      if ([string]$manifest.digest -cne (Get-MIR4PlatformDigest $manifest) -or [string]$manifest.source.commit -cne [string]$source.commit -or
          [string]$manifest.source.tree -cne [string]$source.tree -or @($manifest.assets).Count -ne 4) { throw '[mir4-preview-assets-verification]' }
      $assets = @($manifest.assets | Sort-Object name | ForEach-Object {
        $path = Join-Path $outputRoot ([string]$_.name)
        $descriptor = Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path
        if ([string]$descriptor.sha256 -cne ([string]$_.sha256).ToUpperInvariant() -or [long]$descriptor.bytes -ne [long]$_.bytes) { throw "[mir4-preview-assets-byte-binding] $($_.name)" }
        [pscustomobject][ordered]@{name=[string]$_.name;sha256=[string]$descriptor.sha256;bytes=[long]$descriptor.bytes}
      })
      return New-MIR4PreviewAssetsAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Verify -Assets $assets -Artifacts @(
        (Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $manifestPath)
      ) -Checks @('manifest-canonical-digest','asset-byte-hashes','exact-source-reverified','publication-boundary-reverified')
    }
    'Compensate' {
      $artifacts = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { @(Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $manifestPath) } else { @() }
      if (Test-Path -LiteralPath $outputRoot -PathType Container) { Remove-Item -LiteralPath $outputRoot -Recurse -Force }
      return New-MIR4PreviewAssetsAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Compensate -Assets @() -Artifacts $artifacts -Checks @('attempt-local-assets-removed','repository-unchanged','publication-not-performed')
    }
    default { throw "[mir4-preview-assets-adapter-operation] $($Context.operation)" }
  }
}

function Invoke-MIR4DefaultIndependentReceiptProvider {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)]$Expected,[Parameter(Mandatory)]$Context)
  $proofRoot = Get-MIR4ReleaseAdapterProofRoot -RepoRoot $RepoRoot -Context $Context
  $path = Join-Path $proofRoot ("independent-receipts/" + $Target.ToLowerInvariant() + ".json")
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-independent-verification-receipt-missing] $Target" }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
}

function Assert-MIR4IndependentVerificationReceipt {
  param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$Expected,[Parameter(Mandatory)]$Context)
  if ([string]$Receipt.kind -cne 'MIR4IndependentVerificationReceiptV1' -or [int]$Receipt.schema -ne 1 -or
      [string]$Receipt.status -cne 'passed' -or -not [bool]$Receipt.independent -or
      [string]::IsNullOrWhiteSpace([string]$Receipt.producer_id) -or
      [string]$Receipt.record_sha256 -cne (Get-MIR4ReleasePhaseSelfHash -Record $Receipt -HashProperty 'record_sha256') -or
      [string]$Receipt.source_commit -cne [string]$Context.plan.identity.source_commit -or
      [string]$Receipt.source_tree -cne [string]$Context.plan.identity.source_tree -or
      [string]$Receipt.release_plan_digest -cne [string]$Context.plan.identity.release_plan_digest -or
      [string]$Receipt.target -cne [string]$Expected.target -or
      [string]$Receipt.distribution_version -cne [string]$Expected.distribution_version -or
      ([string]$Receipt.package_sha256).ToUpperInvariant() -cne [string]$Expected.package.sha256 -or
      ([string]$Receipt.engine_sha256).ToUpperInvariant() -cne [string]$Expected.engine.sha256 -or
      [string]$Receipt.evidence_sha256 -cnotmatch '^[A-F0-9]{64}$' -or
      [bool]$Receipt.release_identity -or [bool]$Receipt.publication_authorized) {
    throw "[mir4-independent-verification-receipt-mismatch] $($Expected.target)"
  }
  return $Receipt
}

function New-MIR4IndependentVerificationAdapterResult {
  param([string]$RepoRoot,$Context,[string]$Operation,[object[]]$Targets,[object[]]$Artifacts,[int]$Adopted,[string[]]$Checks)
  $result = [pscustomobject][ordered]@{
    schema=1;kind='MIR4ReleasePhaseAdapterResultV1';phase='independent-verification';phase_result_kind='MIR4IndependentVerificationPhaseResultV1'
    operation=$Operation;status='passed';idempotency_key=[string]$Context.idempotency_key
    artifact_root=Get-MIR4ReleaseAdapterRelativePath -RepoRoot $RepoRoot -Path ([string]$Context.artifact_root)
    production_mutation_performed=$false;release_transition_performed=$false
    targets=@($Targets);independent_receipts_adopted=$Adopted;artifacts=@($Artifacts)
    checks=@($Checks|Sort-Object -CaseSensitive -Unique)
  }
  return Test-MIR4ReleaseAdapterResultSchema -RepoRoot $RepoRoot -Schema 'spec/schemas/mir4-release-independent-verification-result-v1.schema.json' -Result $result
}

function Invoke-MIR4IndependentVerificationAdapter {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Context,[Parameter(Mandatory)][scriptblock]$ReceiptProvider)
  $boundary = Assert-MIR4ReleaseAdapterContext -RepoRoot $RepoRoot -Context $Context -Phase 'independent-verification'
  $source = Get-MIR4ReleaseAdapterSourceState -RepoRoot $boundary.repo -Context $Context
  $expected = @(Get-MIR4TargetQualificationExpectations -RepoRoot $boundary.repo -Context $Context)
  $executeRoot = Join-Path $boundary.attempt_root 'artifacts/execute'
  $receiptRoot = Join-Path $executeRoot 'independent-receipts'
  $aggregatePath = Join-Path $executeRoot 'independent-verification.json'
  switch ([string]$Context.operation) {
    'DryRun' {
      $targets = @($expected | ForEach-Object { [pscustomobject][ordered]@{target=$_.target;distribution_version=$_.distribution_version;state='planned-independent-import';package_sha256=$_.package.sha256;engine_sha256=$_.engine.sha256;evidence_sha256=$null;receipt=$null;independent=$true;release_identity=$false;publication_authorized=$false} })
      return New-MIR4IndependentVerificationAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation DryRun -Targets $targets -Artifacts @() -Adopted 0 -Checks @(
        'exact-source-identity','mandatory-target-cardinality','independent-producer-required','target-engine-package-evidence-bound','partial-evidence-preserved','production-transition-denied')
    }
    'Execute' {
      New-Item -ItemType Directory -Path $receiptRoot -Force | Out-Null
      $targets=@();$adopted=0
      foreach($expectation in $expected) {
        $path=Join-Path $receiptRoot ($expectation.target.ToLowerInvariant()+'.json')
        if(Test-Path -LiteralPath $path -PathType Leaf){$receipt=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100;$adopted++}
        else{$receipt=&$ReceiptProvider $boundary.repo ([string]$expectation.target) $expectation $Context}
        $receipt=Assert-MIR4IndependentVerificationReceipt -Receipt $receipt -Expected $expectation -Context $Context
        Write-MIR4ReleaseAdapterRecord -Record $receipt -Path $path
        $targets += [pscustomobject][ordered]@{
          target=[string]$expectation.target;distribution_version=[string]$expectation.distribution_version;state='independently-verified-private'
          package_sha256=[string]$expectation.package.sha256;engine_sha256=[string]$expectation.engine.sha256;evidence_sha256=[string]$receipt.evidence_sha256
          receipt=Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path;independent=$true;release_identity=$false;publication_authorized=$false
        }
      }
      $record=[pscustomobject][ordered]@{
        schema=1;kind='MIR4IndependentVerificationRehearsalManifestV1';candidate_id=[string]$Context.plan.identity.candidate_id
        source=$source;targets=@($targets);successful_partial_evidence_preserved=$true;release_identity=$false;production_authorized=$false;publication_authorized=$false;record_sha256=''
      }
      $record.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty record_sha256
      Write-MIR4ReleaseAdapterRecord -Record $record -Path $aggregatePath
      return New-MIR4IndependentVerificationAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Execute -Targets $targets -Artifacts @(
        (Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $aggregatePath)
      ) -Adopted $adopted -Checks @('independent-receipts-imported','exact-identity-replay','successful-partial-evidence-preserved','aggregate-self-hash','release-identity-not-created')
    }
    'Verify' {
      $record=Get-Content -Raw -LiteralPath $aggregatePath|ConvertFrom-Json -Depth 100
      if([string]$record.record_sha256-cne(Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty record_sha256)-or
         [string]$record.source.commit-cne[string]$source.commit-or@($record.targets).Count-ne2-or-not[bool]$record.successful_partial_evidence_preserved-or
         [bool]$record.release_identity-or[bool]$record.production_authorized-or[bool]$record.publication_authorized){throw '[mir4-independent-verification-verification]'}
      foreach($expectation in $expected){
        $path=Join-Path $receiptRoot ($expectation.target.ToLowerInvariant()+'.json')
        $receipt=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100
        $null=Assert-MIR4IndependentVerificationReceipt -Receipt $receipt -Expected $expectation -Context $Context
      }
      return New-MIR4IndependentVerificationAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Verify -Targets @($record.targets) -Artifacts @(
        (Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $aggregatePath)
      ) -Adopted 2 -Checks @('independent-receipt-self-hashes','target-engine-package-evidence-bindings','aggregate-self-hash','production-boundary-reverified')
    }
    'Compensate' {
      $artifacts=if(Test-Path -LiteralPath $aggregatePath -PathType Leaf){@(Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $aggregatePath)}else{@()}
      if(Test-Path -LiteralPath $executeRoot -PathType Container){Remove-Item -LiteralPath $executeRoot -Recurse -Force}
      return New-MIR4IndependentVerificationAdapterResult -RepoRoot $boundary.repo -Context $Context -Operation Compensate -Targets @() -Artifacts $artifacts -Adopted 0 -Checks @('attempt-local-independent-receipts-removed','repository-unchanged','release-identity-not-created')
    }
    default { throw "[mir4-independent-verification-adapter-operation] $($Context.operation)" }
  }
}

function Get-MIR4ReleasePhaseAdapter {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Phase,
    [scriptblock]$TargetConstructor,[string]$TargetConstructorIdentity='',
    [scriptblock]$QualificationWorkerProvider,[string]$QualificationWorkerProviderIdentity='',
    [scriptblock]$PreviewBuilder,[string]$PreviewBuilderIdentity='',
    [scriptblock]$IndependentReceiptProvider,[string]$IndependentReceiptProviderIdentity='',
    [scriptblock]$PublicationTransferProvider,[string]$PublicationTransferProviderIdentity='',
    [scriptblock]$PublicReadbackProvider,[string]$PublicReadbackProviderIdentity=''
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $phaseEngineLibraryPath = Join-Path $repo 'tools/lib/mir4/ReleasePhaseEngine.ps1'
  $adapterLibraryPath = Join-Path $repo 'tools/lib/mir4/ReleaseAdapters.ps1'
  $lifecycleAdapterLibraryPath = Join-Path $repo 'tools/lib/mir4/ReleaseLifecycleAdapters.ps1'
  $implementation = (Get-FileHash -LiteralPath $adapterLibraryPath -Algorithm SHA256).Hash.ToUpperInvariant()
  $lifecycleImplementation = (Get-FileHash -LiteralPath $lifecycleAdapterLibraryPath -Algorithm SHA256).Hash.ToUpperInvariant()
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
    'target-qualification' {
      $useDefaultProvider = $null -eq $QualificationWorkerProvider
      if ($useDefaultProvider) { $QualificationWorkerProvider = ${function:Invoke-MIR4DefaultQualificationWorkerProvider} }
      if ([string]::IsNullOrWhiteSpace($QualificationWorkerProviderIdentity)) { $QualificationWorkerProviderIdentity = Get-MIR4ReleasePhaseSha256 ([string]$QualificationWorkerProvider) }
      $provider=$QualificationWorkerProvider
      $invoke={
        param($Context)
        . $phaseEngineLibraryPath
        . $adapterLibraryPath
        $effectiveProvider=if($useDefaultProvider){${function:Invoke-MIR4DefaultQualificationWorkerProvider}}else{$provider}
        Invoke-MIR4TargetQualificationAdapter -RepoRoot $repo -Context $Context -WorkerProvider $effectiveProvider
      }.GetNewClosure()
      return [pscustomobject][ordered]@{
        descriptor=[pscustomobject][ordered]@{id='mir4.target-qualification.rehearsal.v1';version=1;implementation_sha256=$implementation;delegate_sha256=$QualificationWorkerProviderIdentity;production_capable=$false;supported_operations=@('DryRun','Execute','Verify','Compensate');required_ports=@('git','build','engine');result_schema='spec/schemas/mir4-release-target-qualification-result-v1.schema.json'}
        invoke=$invoke
      }
    }
    'preview-assets' {
      $useDefaultBuilder=$null-eq$PreviewBuilder
      if($useDefaultBuilder){$PreviewBuilder=${function:Invoke-MIR4DefaultPreviewBuilder}}
      if([string]::IsNullOrWhiteSpace($PreviewBuilderIdentity)){$PreviewBuilderIdentity=Get-MIR4ReleasePhaseSha256 ([string]$PreviewBuilder)}
      $builder=$PreviewBuilder
      $invoke={
        param($Context)
        . $phaseEngineLibraryPath
        . $adapterLibraryPath
        $effectiveBuilder=if($useDefaultBuilder){${function:Invoke-MIR4DefaultPreviewBuilder}}else{$builder}
        Invoke-MIR4PreviewAssetsAdapter -RepoRoot $repo -Context $Context -Builder $effectiveBuilder
      }.GetNewClosure()
      return [pscustomobject][ordered]@{
        descriptor=[pscustomobject][ordered]@{id='mir4.preview-assets.rehearsal.v1';version=1;implementation_sha256=$implementation;delegate_sha256=$PreviewBuilderIdentity;production_capable=$false;supported_operations=@('DryRun','Execute','Verify','Compensate');required_ports=@('git','build');result_schema='spec/schemas/mir4-release-preview-assets-result-v1.schema.json'}
        invoke=$invoke
      }
    }
    'independent-verification' {
      $useDefaultProvider=$null-eq$IndependentReceiptProvider
      if($useDefaultProvider){$IndependentReceiptProvider=${function:Invoke-MIR4DefaultIndependentReceiptProvider}}
      if([string]::IsNullOrWhiteSpace($IndependentReceiptProviderIdentity)){$IndependentReceiptProviderIdentity=Get-MIR4ReleasePhaseSha256 ([string]$IndependentReceiptProvider)}
      $provider=$IndependentReceiptProvider
      $invoke={
        param($Context)
        . $phaseEngineLibraryPath
        . $adapterLibraryPath
        $effectiveProvider=if($useDefaultProvider){${function:Invoke-MIR4DefaultIndependentReceiptProvider}}else{$provider}
        Invoke-MIR4IndependentVerificationAdapter -RepoRoot $repo -Context $Context -ReceiptProvider $effectiveProvider
      }.GetNewClosure()
      return [pscustomobject][ordered]@{
        descriptor=[pscustomobject][ordered]@{id='mir4.independent-verification.rehearsal.v1';version=1;implementation_sha256=$implementation;delegate_sha256=$IndependentReceiptProviderIdentity;production_capable=$false;supported_operations=@('DryRun','Execute','Verify','Compensate');required_ports=@('git','build');result_schema='spec/schemas/mir4-release-independent-verification-result-v1.schema.json'}
        invoke=$invoke
      }
    }
    'release-seal' {
      $invoke={param($Context). $phaseEngineLibraryPath;. $adapterLibraryPath;. $lifecycleAdapterLibraryPath;Invoke-MIR4ReleaseSealAdapter -RepoRoot $repo -Context $Context}.GetNewClosure()
      return [pscustomobject][ordered]@{
        descriptor=[pscustomobject][ordered]@{id='mir4.release-seal.rehearsal.v1';version=1;implementation_sha256=$lifecycleImplementation;production_capable=$false;supported_operations=@('DryRun','Execute','Verify','Compensate');required_ports=@('git','build');result_schema='spec/schemas/mir4-release-seal-result-v1.schema.json'}
        invoke=$invoke
      }
    }
    'promotion' {
      $invoke={param($Context). $phaseEngineLibraryPath;. $adapterLibraryPath;. $lifecycleAdapterLibraryPath;Invoke-MIR4PromotionAdapter -RepoRoot $repo -Context $Context}.GetNewClosure()
      return [pscustomobject][ordered]@{
        descriptor=[pscustomobject][ordered]@{id='mir4.promotion.rehearsal.v1';version=1;implementation_sha256=$lifecycleImplementation;production_capable=$false;supported_operations=@('DryRun','Execute','Verify','Compensate');required_ports=@('git','build');result_schema='spec/schemas/mir4-release-promotion-result-v1.schema.json'}
        invoke=$invoke
      }
    }
    'target-publication' {
      $useDefaultProvider=$null-eq$PublicationTransferProvider
      if($useDefaultProvider){$PublicationTransferProvider=${function:Invoke-MIR4DefaultPublicationTransferProvider}}
      if([string]::IsNullOrWhiteSpace($PublicationTransferProviderIdentity)){$PublicationTransferProviderIdentity=Get-MIR4ReleasePhaseSha256 ([string]$PublicationTransferProvider)}
      $provider=$PublicationTransferProvider
      $invoke={
        param($Context)
        . $phaseEngineLibraryPath;. $adapterLibraryPath;. $lifecycleAdapterLibraryPath
        $effectiveProvider=if($useDefaultProvider){${function:Invoke-MIR4DefaultPublicationTransferProvider}}else{$provider}
        Invoke-MIR4TargetPublicationAdapter -RepoRoot $repo -Context $Context -TransferProvider $effectiveProvider
      }.GetNewClosure()
      return [pscustomobject][ordered]@{
        descriptor=[pscustomobject][ordered]@{id='mir4.target-publication.rehearsal.v1';version=1;implementation_sha256=$lifecycleImplementation;delegate_sha256=$PublicationTransferProviderIdentity;production_capable=$false;supported_operations=@('DryRun','Execute','Verify','Compensate');required_ports=@();result_schema='spec/schemas/mir4-release-target-publication-result-v1.schema.json'}
        invoke=$invoke
      }
    }
    'public-readback' {
      $useDefaultProvider=$null-eq$PublicReadbackProvider
      if($useDefaultProvider){$PublicReadbackProvider=${function:Invoke-MIR4DefaultPublicReadbackProvider}}
      if([string]::IsNullOrWhiteSpace($PublicReadbackProviderIdentity)){$PublicReadbackProviderIdentity=Get-MIR4ReleasePhaseSha256 ([string]$PublicReadbackProvider)}
      $provider=$PublicReadbackProvider
      $invoke={
        param($Context)
        . $phaseEngineLibraryPath;. $adapterLibraryPath;. $lifecycleAdapterLibraryPath
        $effectiveProvider=if($useDefaultProvider){${function:Invoke-MIR4DefaultPublicReadbackProvider}}else{$provider}
        Invoke-MIR4PublicReadbackAdapter -RepoRoot $repo -Context $Context -ReadbackProvider $effectiveProvider
      }.GetNewClosure()
      return [pscustomobject][ordered]@{
        descriptor=[pscustomobject][ordered]@{id='mir4.public-readback.rehearsal.v1';version=1;implementation_sha256=$lifecycleImplementation;delegate_sha256=$PublicReadbackProviderIdentity;production_capable=$false;supported_operations=@('DryRun','Execute','Verify','Compensate');required_ports=@();result_schema='spec/schemas/mir4-release-public-readback-result-v1.schema.json'}
        invoke=$invoke
      }
    }
    'restore-drill' {
      $invoke={param($Context). $phaseEngineLibraryPath;. $adapterLibraryPath;. $lifecycleAdapterLibraryPath;Invoke-MIR4RestoreDrillAdapter -RepoRoot $repo -Context $Context}.GetNewClosure()
      return [pscustomobject][ordered]@{
        descriptor=[pscustomobject][ordered]@{id='mir4.restore-drill.rehearsal.v1';version=1;implementation_sha256=$lifecycleImplementation;production_capable=$false;supported_operations=@('DryRun','Execute','Verify','Compensate');required_ports=@('build');result_schema='spec/schemas/mir4-release-restore-drill-result-v1.schema.json'}
        invoke=$invoke
      }
    }
    default { throw "[mir4-release-adapter-not-implemented] $Phase" }
  }
}
