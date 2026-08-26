$script:MIR4RepositoryRootIds = @('governance','contracts','spec','src','targets','modules','sdk','tools-mir','tests','assurance','changes','releases','docs','examples')
$script:MIR4RepositoryClasses = @('normative-authority','generated-projection','executable-source','test-fixture','reusable-cache','durable-evidence','process-scratch','archive','obsolete','unknown')

function Get-MIR4RepositoryFixedPointAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo '.mir/control/repository-fixed-point.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw '[mir4-repository-authority-missing]' }
  $authority = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ([int]$authority.schema -ne 1 -or [string]$authority.kind -cne 'MIR4RepositoryFixedPointV1') { throw '[mir4-repository-authority-schema]' }
  if ([string]$authority.state -cne 'REPOSITORY-SHADOW-FIXED-POINT-ACCEPTED' -or [bool]$authority.physical_cutover -or -not [bool]$authority.current_package_source_remains_authoritative) {
    throw '[mir4-repository-cutover-boundary]'
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

function Get-MIR4RepositoryRootMarker {
  param([Parameter(Mandatory)]$Root)
  return [ordered]@{
    schema=1
    kind='MIR4VisibleRootProjectionV1'
    id=[string]$Root.id
    path=[string]$Root.path
    mode=[string]$Root.mode
    current_authorities=@($Root.current_authorities)
    writable_authority=$false
    package_visible=$false
    source='.mir/control/repository-fixed-point.json'
  }
}

function Invoke-MIR4RepositoryRootProjection {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authority = Get-MIR4RepositoryFixedPointAuthority -RepoRoot $repo
  foreach ($root in @($authority.visible_roots)) {
    $path = Join-Path $repo (([string]$root.path) + '/.mir-root.json')
    $json = (Get-MIR4RepositoryRootMarker -Root $root | ConvertTo-Json -Depth 20) + "`n"
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json.Replace("`r`n","`n"))
    if ($Check) {
      if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not [Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path), [byte[]]$bytes)) {
        throw "[mir4-repository-root-projection-stale] $($root.path)"
      }
    } else {
      New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
      [IO.File]::WriteAllBytes($path, $bytes)
    }
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
  if ($path -match '^(\.mir/|spec/|mir\.toml$)') { return 'normative-authority' }
  if ($path -match '^(\.agents/|\.codex/)') { return 'normative-authority' }
  if ($path -match '^(fixtures/|validation/|tests/|examples/)') { return 'test-fixture' }
  if ($path -match '^(docs/|governance/|contracts/|targets/|modules/|assurance/|changes/|releases/)') { return 'generated-projection' }
  if ($path -match '^(\.github/|tools/|scripts/|prototypes/|migrations/|locale/|src/)' -or $path -match '^(data|settings)(-updates|-final-fixes)?\.lua$' -or $path -eq 'control.lua') { return 'executable-source' }
  if ($path -match '^dist/' -or $path.EndsWith('.zip')) { return 'archive' }
  if ($path -in @('.gitattributes','.gitignore','AGENTS.md','CONTRIBUTING.md','EXTENSION-PROTOCOL.md','FORKING.md','GOVERNANCE.md','MAINTAINER-HANDOFF.md','PROJECT-CONTINUITY.md','README.md','RELEASE-RUNBOOK.md','SECURITY.md','SUPPORT.md','LICENSE','changelog.txt','info.json','thumbnail.png','todo.md')) { return 'normative-authority' }
  return 'unknown'
}

function Get-MIR4RepositoryInventory {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authority = Get-MIR4RepositoryFixedPointAuthority -RepoRoot $repo
  $tracked = @(
    foreach ($path in @(& git -C $repo ls-files)) {
      [ordered]@{path=$path.Replace('\','/');source='git-tracked';class=(Get-MIR4RepositoryPathClass -Path $path)}
    }
  )
  $ignored = @(
    foreach ($path in @(& git -C $repo ls-files --others --ignored --exclude-standard)) {
      [ordered]@{path=$path.Replace('\','/');source='git-ignored';class=(Get-MIR4RepositoryPathClass -Path $path -Ignored)}
    }
  )
  $untracked = @(
    foreach ($path in @(& git -C $repo ls-files --others --exclude-standard)) {
      [ordered]@{path=$path.Replace('\','/');source='git-untracked';class=(Get-MIR4RepositoryPathClass -Path $path)}
    }
  )
  $external = @(
    foreach ($root in @($authority.external_roots)) {
      [ordered]@{environment=[string]$root.environment;path=[string]$root.path;class=[string]$root.class;exists=(Test-Path -LiteralPath ([string]$root.path) -PathType Container)}
    }
  )
  $unknown = @($tracked + $untracked + $ignored | Where-Object { [string]$_.class -eq 'unknown' })
  return [pscustomobject][ordered]@{
    schema=1
    kind='MIR4RepositoryInventoryV1'
    tracked=$tracked
    untracked=$untracked
    ignored=$ignored
    external=$external
    summary=[ordered]@{tracked=$tracked.Count;untracked=$untracked.Count;ignored=$ignored.Count;external=$external.Count;unknown=$unknown.Count}
    deletion_authorized=($unknown.Count -eq 0 -and $false)
  }
}

function Initialize-MIR4ExternalRepositoryRoots {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $authority = Get-MIR4RepositoryFixedPointAuthority -RepoRoot $RepoRoot
  foreach ($root in @($authority.external_roots)) {
    New-Item -ItemType Directory -Force -Path ([string]$root.path) | Out-Null
    [Environment]::SetEnvironmentVariable([string]$root.environment, [string]$root.path, 'User')
  }
  return Get-MIR4RepositoryInventory -RepoRoot $RepoRoot
}
