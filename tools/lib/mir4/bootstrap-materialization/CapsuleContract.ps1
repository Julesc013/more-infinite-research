function Get-MIR4CapsuleMemberRole {
  param([Parameter(Mandatory)][string]$RelativePath)

  if ($RelativePath -like '.mir/capsule/git/*') { return 'git-object-proof' }
  if ($RelativePath -eq '.mir/capsule/toolchain-lock.json') { return 'toolchain-lock' }
  if ($RelativePath -eq '.mir/capsule/RECONSTRUCT.md') { return 'reconstruction-instructions' }
  if ($RelativePath -like '.mir/releases/*') { return 'authority' }
  if ($RelativePath -like 'spec/schemas/*') { return 'schema' }
  if ($RelativePath -eq 'tools/commands/package/Build-MIRPackage.ps1') { return 'canonical-package-builder' }
  if ($RelativePath -like 'tools/*') { return 'reconstruction-tool' }
  return 'package-source'
}

function Get-MIR4BootstrapCapsuleControllerPaths {
  return @(
    'tools/commands/package/Build-MIRPackage.ps1',
    'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1',
    'tools/lib/validation/PackageIdentity.ps1',
    'tools/lib/validation/MIR4DistributionIdentity.ps1',
    'tools/lib/mir4/BootstrapMaterialization.ps1'
  )
}

function Get-MIR4BootstrapCapsuleAuthorityPaths {
  param([ValidateSet('emergency', 'local-playtest-shadow')][string]$Lane = 'emergency')

  $paths = @(
    '.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV2.json',
    '.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV3.json',
    '.mir/releases/waves/mir4-r0/MIR4-Entry-GateV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Emergency-LaneV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Equivalence-PolicyV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Approved-Bootstrap-Correction-MIR3-TERM-0033V1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Approved-Bootstrap-Correction-CompositeV2.json',
    '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV2.json',
    '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV3.json',
    '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV4.json',
    '.mir/releases/waves/mir4-r0/MIR4-Versioning-and-Distribution-Identity-ADRv2.json',
    '.mir/releases/waves/mir4-r0/terminal-baseline-import.json',
    '.mir/releases/waves/mir4-r0/bootstrap-root-set.json',
    '.mir/releases/waves/mir4-r0/MIR4-Offline-Release-AuthorityV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Terminal-Import-ContractV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Terminal-Import-ContractV2.json',
    '.mir/releases/waves/mir4-r0/MIR4-Terminal-Predecessor-RefreshV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Terminal-Predecessor-RefreshV2.json',
    '.mir/releases/waves/mir4-r0/MIR4-Terminal-Predecessor-RefreshV3.json',
    '.mir/releases/waves/mir4-r0/MIR4-Terminal-Import-CompositeV3.json',
    '.mir/releases/terminal/baselines/3.2.11/baseline-manifest.json',
    '.mir/releases/terminal/baselines/3.2.11/normalized-snapshot.json',
    '.mir/releases/terminal/baselines/3.2.11/package-composition.json',
    '.mir/releases/records/3.2.11.json',
    '.mir/releases/terminal/baselines/3.2.10/baseline-manifest.json',
    '.mir/releases/terminal/baselines/3.2.10/normalized-snapshot.json',
    '.mir/releases/terminal/baselines/3.2.10/package-composition.json',
    '.mir/releases/records/3.2.10.json',
    '.mir/releases/emergency/MIR3PostTerminalEmergencyHotfixLocalQualificationV1.json',
    '.mir/releases/emergency/findings/MIR3-TERM-0033.json',
    '.mir/releases/terminal/baselines/3.2.9/baseline-manifest.json'
  )
  if ($Lane -ceq 'local-playtest-shadow') {
    $paths += @(
      '.mir/releases/waves/mir4-r0/MIR4-Local-Playtest-Shadow-AuthorizationV1.json',
      '.mir/releases/waves/mir4-r0/MIR4-Private-Lane-AuthorizationV2.json',
      '.mir/releases/waves/mir4-r0/MIR4-Private-Lane-AuthorizationV3.json',
      '.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Target-ReadinessV1.json',
      '.mir/targets.json',
      '.mir/releases/terminal/baselines/2.5.10/baseline-manifest.json',
      '.mir/releases/terminal/baselines/2.5.10/normalized-snapshot.json',
      '.mir/releases/terminal/baselines/2.5.10/package-composition.json',
      '.mir/releases/records/2.5.10.json',
      '.mir/releases/terminal/baselines/2.5.11/baseline-manifest.json',
      '.mir/releases/terminal/baselines/2.5.11/normalized-snapshot.json',
      '.mir/releases/terminal/baselines/2.5.11/package-composition.json',
      '.mir/releases/records/2.5.11.json',
      '.mir/releases/terminal/baselines/2.5.9/baseline-manifest.json',
      '.mir/releases/terminal/baselines/2.5.9/normalized-snapshot.json',
      '.mir/releases/terminal/baselines/2.5.9/package-composition.json',
      '.mir/releases/records/2.5.9.json',
      '.mir/releases/terminal/baselines/1.9.9/baseline-manifest.json',
      '.mir/releases/terminal/baselines/1.9.9/normalized-snapshot.json',
      '.mir/releases/terminal/baselines/1.9.9/package-composition.json',
      '.mir/releases/records/1.9.9.json',
      '.mir/releases/terminal/baselines/1.8.9/baseline-manifest.json',
      '.mir/releases/terminal/baselines/1.8.9/normalized-snapshot.json',
      '.mir/releases/terminal/baselines/1.8.9/package-composition.json',
      '.mir/releases/records/1.8.9.json'
    )
  }
  return $paths
}

function Get-MIR4BootstrapCapsuleSchemaPaths {
  param([ValidateSet('emergency', 'local-playtest-shadow')][string]$Lane = 'emergency')

  $paths = @(
    'spec/schemas/mir4-bootstrap-local-candidate-plan.schema.json',
    'spec/schemas/mir4-bootstrap-local-candidate-plan-v2.schema.json',
    'spec/schemas/mir4-bootstrap-local-candidate-plan-v3.schema.json',
    'spec/schemas/mir4-bootstrap-local-candidate-manifest.schema.json',
    'spec/schemas/mir4-approved-bootstrap-correction-delta.schema.json',
    'spec/schemas/mir4-approved-bootstrap-correction-delta-v2.schema.json',
    'spec/schemas/mir4-bootstrap-root-set.schema.json',
    'spec/schemas/mir4-bootstrap-source-capsule.schema.json',
    'spec/schemas/mir4-bootstrap-capsule-manifest.schema.json',
    'spec/schemas/mir4-bootstrap-toolchain-lock.schema.json',
    'spec/schemas/mir3-post-terminal-hotfix-baseline-continuation.schema.json',
    'spec/schemas/mir4-bootstrap-git-source-proof.schema.json',
    'spec/schemas/mir4-bootstrap-reconstruction-receipt.schema.json',
    'spec/schemas/mir4-r0-authority.schema.json',
    'spec/schemas/mir4-target-registry-v2.schema.json',
    'spec/schemas/mir4-target-registry-v3.schema.json',
    'spec/schemas/mir4-target-registry-v4.schema.json',
    'spec/schemas/mir4-versioning-distribution-identity-v2.schema.json'
  )
  if ($Lane -ceq 'local-playtest-shadow') {
    $paths += @(
      'spec/schemas/mir4-local-playtest-shadow-authorization.schema.json',
      'spec/schemas/mir4-private-lane-authorization-v2.schema.json',
      'spec/schemas/mir4-private-lane-authorization-v3.schema.json',
      'spec/schemas/mir4-local-playtest-candidate-manifest.schema.json',
      'spec/schemas/mir4-bootstrap-target-readiness.schema.json'
    )
  }
  return $paths
}

function Assert-MIR4BootstrapCapsuleManifestClosure {
  param(
    [Parameter(Mandatory)]$Manifest,
    [Parameter(Mandatory)]$GitProof,
    [ValidateSet('emergency', 'local-playtest-shadow')][string]$Lane = 'emergency'
  )

  $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($relative in @(
    (Get-MIR4BootstrapCapsuleControllerPaths) +
    (Get-MIR4BootstrapCapsuleAuthorityPaths -Lane $Lane) +
    (Get-MIR4BootstrapCapsuleSchemaPaths -Lane $Lane) +
    @(
      '.mir/capsule/toolchain-lock.json',
      '.mir/capsule/RECONSTRUCT.md',
      '.mir/capsule/git/source-identity.json',
      '.mir/capsule/git/commit.raw'
    )
  )) {
    if (-not $expected.Add([string]$relative)) { throw "Duplicate required MIR 4 capsule closure path: $relative" }
  }
  foreach ($row in @($GitProof.tree_objects)) {
    if (-not $expected.Add([string]$row.payload_path)) { throw "Duplicate MIR 4 capsule Git-tree closure path: $($row.payload_path)" }
  }
  foreach ($row in @($GitProof.package_files)) {
    if (-not $expected.Add([string]$row.path)) { throw "Duplicate MIR 4 capsule package-source closure path: $($row.path)" }
  }

  $actual = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($member in @($Manifest.members)) {
    $relative = [string]$member.path
    if (-not $actual.Add($relative)) { throw "Duplicate MIR 4 capsule manifest closure path: $relative" }
    $expectedRole = Get-MIR4CapsuleMemberRole -RelativePath $relative
    if ([string]$member.role -cne $expectedRole) { throw "MIR 4 capsule member role mismatch for $relative." }
  }
  if ([int]$Manifest.member_count -ne $actual.Count) { throw 'MIR 4 capsule manifest member count is inconsistent.' }
  if ($actual.Count -ne $expected.Count) { throw 'MIR 4 capsule manifest does not contain the exact reconstruction closure.' }
  foreach ($relative in $expected) {
    if (-not $actual.Contains($relative)) { throw "MIR 4 capsule manifest omits required closure path: $relative" }
  }
  foreach ($relative in $actual) {
    if (-not $expected.Contains($relative)) { throw "MIR 4 capsule manifest contains an ungoverned closure path: $relative" }
  }
}

function Copy-MIR4CapsuleClosureFile {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CapsuleRoot,
    [Parameter(Mandatory)][string]$RelativePath
  )

  if ($RelativePath -notmatch '^[A-Za-z0-9._/-]+$' -or $RelativePath -match '(^|/)\.{1,2}(/|$)') {
    throw "Unsafe MIR 4 capsule closure path: $RelativePath"
  }
  $source = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "MIR 4 capsule closure input is absent: $RelativePath" }
  $destination = Join-Path $CapsuleRoot $RelativePath
  $parent = Split-Path -Parent $destination
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $source).Path)
  $canonicalText = $text.Replace("`r`n", "`n").Replace("`r", "`n")
  [IO.File]::WriteAllText($destination, $canonicalText, [Text.UTF8Encoding]::new($false))
}
