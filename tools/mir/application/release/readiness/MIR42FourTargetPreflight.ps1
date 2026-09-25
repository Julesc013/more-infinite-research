Set-StrictMode -Version Latest

if (-not (Get-Command Get-MIR4ArchiveInventory -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../../../../lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR4CanonicalPackageAuthority -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../../package/PackageAuthority.ps1')
}

$script:MIR42FourTargetLines = [ordered]@{
  f210 = '2.1'
  f200 = '2.0'
  f110 = '1.1'
  f100 = '1.0'
}

function Assert-MIR42FourTargetOutputRoot {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$OutputRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $root = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot)) }
  $build = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  $prefix = $build.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $root.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-preflight-output-root] OutputRoot must be a new package-excluded build subdirectory.' }
  if ((Test-Path -LiteralPath $root -PathType Container) -and @(Get-ChildItem -LiteralPath $root -Force).Count -gt 0) { throw '[mir42-preflight-output-not-empty]' }
  return $root
}

function Get-MIR42FourTargetSourceIdentity {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$FinalSourceCommit)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $dirty = @(& git -C $repo status --porcelain -- source targets)
  if ($LASTEXITCODE -ne 0) { throw '[mir42-preflight-source-status]' }
  if ($dirty.Count -ne 0) { throw '[mir42-preflight-source-dirty]' }
  $commit = (& git -C $repo rev-parse HEAD).Trim()
  $tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-f0-9]{40}$' -or $tree -notmatch '^[a-f0-9]{40}$') { throw '[mir42-preflight-source-identity]' }
  if ($commit -cne $FinalSourceCommit) { throw '[mir42-preflight-final-source-commit]' }
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  return [pscustomobject][ordered]@{
    commit = $commit
    tree = $tree
    package_source_sha256 = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
    package_authority_record_sha256 = [string]$authority.record_sha256
  }
}

function Assert-MIR42FourTargetPackageExcludedSurface {
  param([Parameter(Mandatory)]$Inventory,[Parameter(Mandatory)][string]$Target)

  $forbidden = '^(?:[.]mir|[.]codex|[.]github|build|dist|docs|fixtures|scripts|tests)(?:/|$)|^(?:AGENTS[.]md)$'
  $matches = @($Inventory.entries | Where-Object { [string]$_.path -match $forbidden })
  if ($matches.Count -ne 0) { throw "[mir42-preflight-package-excluded-entry] ${Target}:$([string]$matches[0].path)" }
}

function Get-MIR42FourTargetArchiveInput {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target,
    [Parameter(Mandatory)][string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "[mir42-preflight-archive-missing] $Target" }
  $archive = (Resolve-Path -LiteralPath $Path).Path
  if ([IO.Path]::GetExtension($archive) -cne '.zip') { throw "[mir42-preflight-archive-extension] $Target" }
  $projection = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $RepoRoot -Target $Target -SourceVersion '4.2.0'
  $expectedLine = [string]$script:MIR42FourTargetLines[$Target]
  if ([string]$projection.target_id -cne "factorio-$expectedLine") { throw "[mir42-preflight-target-authority] $Target" }
  $inventory = Get-MIR4ArchiveInventory -Path $archive
  if ([string]$inventory.root -cne [string]$projection.distribution_root) { throw "[mir42-preflight-package-root] $Target" }
  Assert-MIR42FourTargetPackageExcludedSurface -Inventory $inventory -Target $Target
  try { $info = Read-MIR4ArchiveText -Path $archive -RelativePath 'info.json' | ConvertFrom-Json -Depth 20 -DateKind String }
  catch { throw "[mir42-preflight-info-json] $Target" }
  if ([string]$info.name -cne 'more-infinite-research') { throw "[mir42-preflight-info-name] $Target" }
  if ([string]$info.version -cne [string]$projection.distribution_version) { throw "[mir42-preflight-info-version] $Target" }
  if ([string]$info.factorio_version -cne $expectedLine) { throw "[mir42-preflight-info-factorio-line] $Target" }
  return [pscustomobject][ordered]@{
    target = $Target
    target_id = [string]$projection.target_id
    factorio_line = $expectedLine
    distribution_version = [string]$projection.distribution_version
    package_root = [string]$projection.distribution_root
    archive = [ordered]@{path=$archive;sha256=[string]$inventory.archive_sha256;bytes=[int64]$inventory.bytes}
    content_sha256 = [string]$inventory.content_sha256
    entry_count = [int]$inventory.entry_count
    metadata = [ordered]@{name=[string]$info.name;version=[string]$info.version;factorio_version=[string]$info.factorio_version}
    package_excluded_entries_absent = $true
    qualification = 'not-run'
  }
}

function Get-MIR42FourTargetGovernanceContext {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $relative = '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json'
  $path = Join-Path $RepoRoot $relative
  $schema = Join-Path $RepoRoot 'spec/schemas/mir4-pre-freeze-execution-programme-v1.schema.json'
  $raw = Get-Content -Raw -LiteralPath $path
  if (-not ($raw | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) { throw '[mir42-preflight-governance-schema]' }
  $context = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$context.status -cne 'T15-COMPLETE-T16-T17-HUMAN-BLOCKED-RELEASE-BLOCKED' -or
      @($context.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
    throw '[mir42-preflight-governance-boundary]'
  }
  return [pscustomobject][ordered]@{
    path = $relative
    sha256 = Get-MIR4Sha256File -Path $path
    status = [string]$context.status
    transition_gate = [ordered]@{
      source_freeze = [bool]$context.transition_gate.source_freeze
      candidate_allocation = [bool]$context.transition_gate.candidate_allocation
      production_signing = [bool]$context.transition_gate.production_signing
      promotion_to_main = [bool]$context.transition_gate.promotion_to_main
      tagging = [bool]$context.transition_gate.tagging
      publication = [bool]$context.transition_gate.publication
    }
  }
}

function Test-MIR42FourTargetPreflightRecord {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$SchemaPath,[Parameter(Mandatory)][string]$Code)

  if (-not ((ConvertTo-MIR4BootstrapCanonicalJson -Value $Record) | Test-Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)) { throw "[$Code-schema]" }
  if (-not (Test-MIR4BootstrapRecordHash -Record $Record)) { throw "[$Code-hash]" }
}

function Invoke-MIR42FourTargetReleasePreflight {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$FinalSourceCommit,
    [Parameter(Mandatory)][string]$F210Zip,
    [Parameter(Mandatory)][string]$F200Zip,
    [Parameter(Mandatory)][string]$F110Zip,
    [Parameter(Mandatory)][string]$F100Zip,
    [Parameter(Mandatory)][string]$OutputRoot
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $output = Assert-MIR42FourTargetOutputRoot -RepoRoot $repo -OutputRoot $OutputRoot
  $source = Get-MIR42FourTargetSourceIdentity -RepoRoot $repo -FinalSourceCommit $FinalSourceCommit
  $targets = @(
    Get-MIR42FourTargetArchiveInput -RepoRoot $repo -Target f210 -Path $F210Zip
    Get-MIR42FourTargetArchiveInput -RepoRoot $repo -Target f200 -Path $F200Zip
    Get-MIR42FourTargetArchiveInput -RepoRoot $repo -Target f110 -Path $F110Zip
    Get-MIR42FourTargetArchiveInput -RepoRoot $repo -Target f100 -Path $F100Zip
  )
  $governance = Get-MIR42FourTargetGovernanceContext -RepoRoot $repo

  $candidate = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetCandidateManifestV1'
    status = 'MIR-4.2-FOUR-TARGET-CANDIDATE-INPUTS-BOUND-UNQUALIFIED'
    source_version = '4.2.0'
    candidate_id = $null
    source = $source
    archive_source_provenance = 'unproven-by-zip-inputs'
    targets = $targets
    package_excluded_surface_checked = $true
    release_transition_authorized = $false
    publication_authorized = $false
    record_sha256 = ''
  }
  $candidate.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $candidate
  $candidateSchema = Join-Path $repo 'spec/schemas/mir42-four-target-candidate-manifest-v1.schema.json'
  Test-MIR42FourTargetPreflightRecord -Record $candidate -SchemaPath $candidateSchema -Code 'mir42-preflight-candidate'
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  $candidatePath = Join-Path $output 'candidate-manifest.json'
  Write-MIR4BootstrapRecord -Record $candidate -Path $candidatePath | Out-Null

  $readiness = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetTechnicalReadinessV1'
    status = 'MIR-4.2-FOUR-TARGET-TECHNICAL-READINESS-NOT-READY'
    candidate_manifest = [ordered]@{path='candidate-manifest.json';sha256=Get-MIR4Sha256File -Path $candidatePath;record_sha256=[string]$candidate.record_sha256}
    source = $source
    governance_context = $governance
    target_qualification = @($targets | ForEach-Object { [ordered]@{target=[string]$_.target;distribution_version=[string]$_.distribution_version;status='not-run'} })
    blockers = @(
      'archive-source-provenance-not-supplied',
      'four-target-exact-qualification-not-run',
      'independent-verification-not-run',
      'source-freeze-not-authorized',
      'protected-production-signing-and-recovery-open',
      'protected-main-promotion-not-authorized',
      'maintainer-go-not-recorded',
      'tagging-and-publication-not-authorized'
    )
    transition_gate = [ordered]@{
      source_freeze = $false
      candidate_allocation = $false
      production_signing = $false
      technical_seal = $false
      promotion_to_main = $false
      human_go = $false
      tagging = $false
      publication = $false
    }
    release_transition_authorized = $false
    production_authorized = $false
    publication_authorized = $false
    record_sha256 = ''
  }
  $readiness.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $readiness
  $readinessSchema = Join-Path $repo 'spec/schemas/mir42-four-target-technical-readiness-v1.schema.json'
  Test-MIR42FourTargetPreflightRecord -Record $readiness -SchemaPath $readinessSchema -Code 'mir42-preflight-readiness'
  $readinessPath = Join-Path $output 'technical-readiness.json'
  Write-MIR4BootstrapRecord -Record $readiness -Path $readinessPath | Out-Null
  return [pscustomobject][ordered]@{candidate_manifest=$candidatePath;technical_readiness=$readinessPath;status=[string]$readiness.status}
}
