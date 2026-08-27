$script:MIR4RepositoryRootIds = @('governance','contracts','spec','src','targets','modules','sdk','tools-mir','tests','assurance','changes','releases','docs','examples')
$script:MIR4RepositoryClasses = @('normative-authority','generated-projection','executable-source','test-fixture','reusable-cache','durable-evidence','process-scratch','archive','obsolete','unknown')
$script:MIR4RepositoryFixedPointAuthorityPath = '.mir/control/repository-fixed-point.json'
$script:MIR4RepositoryMigrationAuthorityPath = 'governance/repository/migrations/fixed-point-tooling-v1.json'
$script:MIR4RepositoryMigrationAuthoritySchemaPath = 'contracts/repository/mir4-repository-migration-authority-v1.schema.json'
$script:MIR4RepositoryMigrationProofPath = 'assurance/repository/fixed-point-tooling-v1.json'
$script:MIR4RepositoryMigrationProofSchemaPath = 'contracts/repository/mir4-repository-migration-proof-v1.schema.json'
$script:MIR4RepositoryMigrationReceiptPath = 'releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json'
$script:MIR4RepositoryMigrationReceiptSchemaPath = 'contracts/repository/mir4-repository-migration-receipt-v1.schema.json'

function Get-MIR4RepositoryJsonV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
  $fullPath = Join-Path $RepoRoot $Path
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "[mir4-repository-file-missing] $Path" }
  return Get-Content -Raw -LiteralPath $fullPath | ConvertFrom-Json -Depth 100
}

function Test-MIR4RepositoryJsonSchemaV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$SchemaPath)
  $fullPath = Join-Path $RepoRoot $Path
  $fullSchemaPath = Join-Path $RepoRoot $SchemaPath
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf) -or -not (Test-Path -LiteralPath $fullSchemaPath -PathType Leaf)) { return $false }
  try { return [bool]([IO.File]::ReadAllText($fullPath) | Test-Json -SchemaFile $fullSchemaPath -ErrorAction Stop) }
  catch { return $false }
}

function Get-MIR4RepositoryFixedPointAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authority = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4RepositoryFixedPointAuthorityPath
  if ([int]$authority.schema -ne 2 -or [string]$authority.kind -cne 'MIR4RepositoryFixedPointV2') { throw '[mir4-repository-authority-schema]' }
  if ([string]$authority.state -cne 'PACKAGE-EXCLUDED-AUTHORITY-MIGRATION-ACTIVE' -or [bool]$authority.physical_cutover -or -not [bool]$authority.current_package_source_remains_authoritative) {
    throw '[mir4-repository-cutover-boundary]'
  }
  if ([string]$authority.migration_authority -cne $script:MIR4RepositoryMigrationAuthorityPath) { throw '[mir4-repository-migration-authority-binding]' }
  if (@($authority.migration_sequence).Count -ne 10 -or
      [string]$authority.migration_sequence[0].migration_id -cne 'MIR4-REPOSITORY-FIXED-POINT-TOOLING-V1' -or
      [string]$authority.migration_sequence[0].state -cne 'accepted-immutable-predecessor' -or
      [string]$authority.migration_sequence[1].migration_id -cne 'MIR4-CANONICALIZATION-TOOLING-V1' -or
      [string]$authority.migration_sequence[1].state -cne 'accepted-immutable-predecessor' -or
      [string]$authority.migration_sequence[2].migration_id -cne 'MIR4-DIAGNOSTICS-TOOLING-V1' -or
      [string]$authority.migration_sequence[2].state -cne 'accepted-immutable-predecessor' -or
      [string]$authority.migration_sequence[3].migration_id -cne 'MIR4-TARGET-KEY-TOOLING-V1' -or
      [string]$authority.migration_sequence[3].state -cne 'accepted-immutable-predecessor' -or
      [string]$authority.migration_sequence[4].migration_id -cne 'MIR4-WHOLE-PLATFORM-TOOLING-V1' -or
      [string]$authority.migration_sequence[4].state -cne 'accepted-immutable-predecessor' -or
      [string]$authority.migration_sequence[5].migration_id -cne 'MIR4-TECHNOLOGY-ACCEPTANCE-TOOLING-V1' -or
      [string]$authority.migration_sequence[5].state -cne 'accepted-immutable-predecessor' -or
      [string]$authority.migration_sequence[6].migration_id -cne 'MIR4-TARGET-COMPILER-TOOLING-V1' -or
      [string]$authority.migration_sequence[6].state -cne 'accepted-immutable-predecessor' -or
      [string]$authority.migration_sequence[7].migration_id -cne 'MIR4-SEMANTIC-COMPILER-POLICY-TOOLING-V1' -or
      [string]$authority.migration_sequence[7].state -cne 'accepted-immutable-predecessor' -or
      [string]$authority.migration_sequence[8].migration_id -cne 'MIR4-RUNTIME-CONTINUITY-TOOLING-V1' -or
      [string]$authority.migration_sequence[8].state -cne 'accepted-immutable-predecessor' -or
      [string]$authority.migration_sequence[9].migration_id -cne 'MIR4-MODULE-SDK-MEP-TOOLING-V1' -or
      [string]$authority.migration_sequence[9].state -cne 'current-append-only-successor') {
    throw '[mir4-repository-migration-sequence]'
  }
  $ids = @($authority.visible_roots | ForEach-Object { [string]$_.id })
  $actualRootSet = (@($ids | Sort-Object) -join '|')
  $expectedRootSet = (@($script:MIR4RepositoryRootIds | Sort-Object) -join '|')
  if ($actualRootSet -cne $expectedRootSet) { throw '[mir4-repository-visible-roots]' }
  if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw '[mir4-repository-duplicate-root]' }
  $external = @($authority.external_roots)
  $expectedEnvironment = @('MIR_CACHE_HOME','MIR_STATE_HOME','MIR_TEMP_HOME','MIR_WORKTREE_HOME','MIR_ARCHIVE_HOME','MIR_EVIDENCE_HOME')
  if ((@($external.environment | Sort-Object) -join '|') -cne (@($expectedEnvironment | Sort-Object) -join '|')) { throw '[mir4-repository-external-roots]' }
  if (@($external | Where-Object { [string]$_.class -notin $script:MIR4RepositoryClasses }).Count -ne 0) { throw '[mir4-repository-external-class]' }
  if ([string]$authority.unknown_policy -cne 'block-deletion-and-cutover') { throw '[mir4-repository-unknown-policy]' }
  return $authority
}

function Get-MIR4RepositoryMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4RepositoryMigrationAuthorityPath -SchemaPath $script:MIR4RepositoryMigrationAuthoritySchemaPath)) {
    throw '[mir4-repository-migration-authority-schema]'
  }
  $authority = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4RepositoryMigrationAuthorityPath
  if ([string]$authority.fixed_point_authority -cne $script:MIR4RepositoryFixedPointAuthorityPath) { throw '[mir4-repository-migration-fixed-point-binding]' }
  if (@($authority.writers).Count -ne 1 -or [string]$authority.writers[0].path -cne 'tools/mir/application/repository/RepositoryFixedPoint.ps1') {
    throw '[mir4-repository-migration-single-writer]'
  }
  $finalPaths = @($authority.path_map | ForEach-Object { [string]$_.final_path })
  if (@($finalPaths | Sort-Object -Unique).Count -ne $finalPaths.Count) { throw '[mir4-repository-migration-duplicate-final-path]' }
  if (@($authority.release_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) { throw '[mir4-repository-migration-release-authority]' }
  return $authority
}

function Get-MIR4RepositoryMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4RepositoryMigrationProofPath -SchemaPath $script:MIR4RepositoryMigrationProofSchemaPath)) {
    throw '[mir4-repository-migration-proof-schema]'
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4RepositoryMigrationProofPath
}

function Get-MIR4RepositoryRootMarker {
  param([Parameter(Mandatory)]$Root)
  return [ordered]@{
    schema=2
    kind='MIR4VisibleRootProjectionV2'
    id=[string]$Root.id
    path=[string]$Root.path
    mode=[string]$Root.mode
    current_authorities=@($Root.current_authorities)
    writable_authority=$false
    marker_is_writable_authority=$false
    package_visible=$false
    source=$script:MIR4RepositoryFixedPointAuthorityPath
  }
}

function Get-MIR4RepositoryPathClass {
  param([Parameter(Mandatory)][string]$Path,[switch]$Ignored)
  $path = $Path.Replace('\','/')
  if ($Ignored) {
    if ($path -match '(^|/)(cache)(/|$)') { return 'reusable-cache' }
    if ($path -match '(^|/)(build/results|evidence)(/|$)') { return 'durable-evidence' }
    if ($path -match '(^|/)(dist|archive)(/|$)' -or $path.EndsWith('.zip')) { return 'archive' }
    return 'process-scratch'
  }
  if ($path -match '^\.mir/evidence/' ) { return 'durable-evidence' }
  if ($path -match '^(\.mir/views/|validation/generated/|docs/reference/generated/|sdk/(preview|experimental)/|mir\.lock$|.+/\.mir-root\.json$)') { return 'generated-projection' }
  if ($path -match '^(\.mir/|spec/|mir\.toml$|governance/|contracts/)') { return 'normative-authority' }
  if ($path -match '^(\.agents/|\.codex/)') { return 'normative-authority' }
  if ($path -match '^(fixtures/|validation/|tests/|examples/)') { return 'test-fixture' }
  if ($path -match '^(docs/|targets/|modules/|assurance/|changes/|releases/)') { return 'generated-projection' }
  if ($path -match '^(\.github/|tools/|scripts/|prototypes/|migrations/|locale/|src/)' -or $path -match '^(data|settings)(-updates|-final-fixes)?\.lua$' -or $path -eq 'control.lua') { return 'executable-source' }
  if ($path -match '^dist/' -or $path.EndsWith('.zip')) { return 'archive' }
  if ($path -in @('.gitattributes','.gitignore','AGENTS.md','CONTRIBUTING.md','EXTENSION-PROTOCOL.md','FORKING.md','GOVERNANCE.md','MAINTAINER-HANDOFF.md','PROJECT-CONTINUITY.md','README.md','RELEASE-RUNBOOK.md','SECURITY.md','SUPPORT.md','LICENSE','changelog.txt','info.json','thumbnail.png','todo.md')) { return 'normative-authority' }
  return 'unknown'
}
