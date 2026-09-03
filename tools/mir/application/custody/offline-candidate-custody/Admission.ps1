function Get-MIR4CustodyAdmissionV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CandidatePath,
    [string]$SchemaRoot = ""
  )

  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemas = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $expectedPlanPath = (Resolve-Path -LiteralPath (Join-Path $repo ".mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV3.json")).Path
  if ((Resolve-Path -LiteralPath $CandidatePlanPath).Path -cne $expectedPlanPath) {
    throw "Offline custody requires the exact current tracked bootstrap plan path."
  }
  $plan = Assert-MIR4GovernedBootstrapRecordFileV1 -Path $CandidatePlanPath `
    -SchemaPath (Join-Path $schemas "mir4-bootstrap-local-candidate-plan-v3.schema.json")
  $governedRoot = [IO.Path]::GetFullPath((Join-Path $repo ([string]$plan.package_policy.output_root)))
  $expectedManifestPath = [IO.Path]::GetFullPath((Join-Path $governedRoot "manifests/f210.json"))
  $expectedCandidatePath = [IO.Path]::GetFullPath((Join-Path $governedRoot "distributions/more-infinite-research_4.0.21000.zip"))
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if (-not [string]::Equals([IO.Path]::GetFullPath($CandidateManifestPath), $expectedManifestPath, $comparison) -or
      [string]::IsNullOrWhiteSpace($CandidatePath) -or
      -not [string]::Equals([IO.Path]::GetFullPath($CandidatePath), $expectedCandidatePath, $comparison)) {
    throw "Offline custody accepts only the exact governed f210 manifest and distribution paths below the plan output root."
  }
  $manifestPath = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $expectedManifestPath -Label "Local candidate manifest"
  $candidate = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $expectedCandidatePath -Label "Local candidate archive"
  $manifest = Assert-MIR4BootstrapRecordFileV1 -Path $manifestPath `
    -SchemaPath (Join-Path $schemas "mir4-bootstrap-local-candidate-manifest.schema.json")
  $checker = Join-Path $repo "tools/commands/release/New-MIR4BootstrapLocalCandidate.ps1"
  $null = & $checker -RepoRoot $repo -PlanPath $CandidatePlanPath -Target f210 -OutputRoot $governedRoot -HistoricalCompatibility -Check

  if ([string]$manifest.target_key -cne "f210" -or [string]$manifest.factorio_line -cne "2.1" -or
      [string]$manifest.distribution_version -cne "4.0.21000" -or
      [string]$manifest.admission -cne "admitted-local-emergency-lane" -or
      [bool]$manifest.public_output_authorized) {
    throw "Offline candidate custody admits only the unpublished f210 emergency-lane manifest."
  }
  if ([string]$plan.source_version -cne "4.0.0" -or [bool]$plan.public_output_authorized) {
    throw "Offline candidate custody requires the current unpublished MIR 4.0.0 bootstrap plan."
  }
  $targetRows = @($plan.targets | Where-Object { [string]$_.target_key -ceq "f210" })
  if ($targetRows.Count -ne 1) { throw "The current bootstrap plan does not contain exactly one f210 admission." }
  $target = $targetRows[0]
  if ([string]$target.target_id -cne "factorio-2.1" -or
      [string]$target.distribution_target_code -cne "210" -or
      [string]$target.distribution_version -cne "4.0.21000" -or
      [string]$target.admission -cne "admitted-local-emergency-lane") {
    throw "The current bootstrap plan does not admit the exact f210 distribution identity."
  }
  if ($null -ne $target.PSObject.Properties['correction_authority'] -or
      $null -ne $manifest.PSObject.Properties['correction_authority']) {
    throw 'Offline candidate custody rejects the superseded correction overlay after the exact 3.2.11 fixed-point predecessor import.'
  }
  $rootSetPath = Join-Path $repo ".mir/releases/waves/mir4-r0/bootstrap-root-set.json"
  $rootSet = Assert-MIR4CheckedRootSetFileV1 -RepoRoot $repo -Path $rootSetPath `
    -SchemaPath (Join-Path $schemas "mir4-bootstrap-root-set.schema.json")
  $rootRows = @($rootSet.targets | Where-Object { [string]$_.target_id -ceq "f210" })
  if ($rootRows.Count -ne 1) { throw "The current bootstrap root set does not contain exactly one f210 row." }
  $rootRow = $rootRows[0]

  $registryPath = Join-Path $repo $script:MIR4TargetRegistryV2Path
  $versionAuthorityPath = Join-Path $repo $script:MIR4VersionAuthorityV2Path
  $null = Assert-MIR4R0DistributionIdentity -RepoRoot $repo
  $registry = Import-MIR4IdentityJson -RepoRoot $repo -RelativePath $script:MIR4TargetRegistryV2Path
  $versionAuthority = Import-MIR4IdentityJson -RepoRoot $repo -RelativePath $script:MIR4VersionAuthorityV2Path
  $projection = Resolve-MIR4DistributionIdentity -TargetRegistry $registry -VersionAuthority $versionAuthority `
    -TargetId ([string]$target.target_id) -SourceMinor 0 -SourcePatch 0
  if ([string]$projection.distribution_target_code -cne "210" -or
      [string]$projection.source_version -cne [string]$plan.source_version -or
      [string]$projection.distribution_version -cne [string]$manifest.distribution_version) {
    throw "The f210 manifest and plan do not match the current V2 distribution identity resolver."
  }

  $archiveName = [IO.Path]::GetFileName([string]$manifest.local_distribution.path)
  if ($archiveName -cne [string]$projection.package_name) {
    throw "The admitted manifest archive name does not match the current V2 distribution identity."
  }
  $candidate = (Resolve-Path -LiteralPath $candidate).Path
  $inventory = Get-MIR4ArchiveInventory -Path $candidate
  $expectedRoot = "more-infinite-research_$($projection.distribution_version)"
  if ([IO.Path]::GetFileName($candidate) -cne $archiveName -or [string]$inventory.root -cne $expectedRoot -or
      [string]$inventory.archive_sha256 -cne [string]$manifest.local_distribution.archive_sha256 -or
      [string]$inventory.content_sha256 -cne [string]$manifest.local_distribution.content_sha256 -or
      [long]$inventory.bytes -ne [long]$manifest.local_distribution.bytes -or
      [long]$inventory.entry_count -ne [long]$manifest.local_distribution.entry_count) {
    throw "The candidate archive inventory and exact package root do not match the admitted self-hashed manifest."
  }
  $predecessorPath = Join-Path $repo ([string]$target.predecessor.archive_path)
  if ((Get-MIR4Sha256File -Path $predecessorPath) -cne [string]$target.predecessor.archive_sha256) {
    throw "The admitted plan predecessor archive does not match its exact bound identity."
  }
  $equivalence = Compare-MIR4BootstrapCandidate -CandidatePath $candidate -PredecessorPath $predecessorPath `
    -ExpectedCandidateRoot $expectedRoot -ExpectedPredecessorRoot "more-infinite-research_$($target.predecessor.release)" `
    -ExpectedCandidateVersion ([string]$projection.distribution_version) `
    -ExpectedPredecessorVersion ([string]$target.predecessor.release) -ThrowOnDifference
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $equivalence) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.equivalence)) {
    throw "The admitted manifest equivalence record does not equal a fresh predecessor comparison."
  }

  $authorities = [pscustomobject][ordered]@{
    target_registry = [pscustomobject][ordered]@{
      kind = [string]$registry.kind
      status = [string]$registry.status
      path = $script:MIR4TargetRegistryV2Path
      file_sha256 = Get-MIR4Sha256File -Path $registryPath
    }
    version_authority = [pscustomobject][ordered]@{
      kind = [string]$versionAuthority.kind
      status = [string]$versionAuthority.status
      path = $script:MIR4VersionAuthorityV2Path
      file_sha256 = Get-MIR4Sha256File -Path $versionAuthorityPath
    }
  }
  return [pscustomobject][ordered]@{
    manifest = $manifest
    plan = $plan
    target = $target
    projection = $projection
    identity_authorities = $authorities
    archive_name = $archiveName
  }
}
