Set-StrictMode -Version Latest

$mirOrdinaryCandidateRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Get-MIR42ExactFourTargetCandidate -ErrorAction SilentlyContinue)) {
  . (Join-Path $mirOrdinaryCandidateRepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
}
if (-not (Get-Command Get-MIR4ArchiveInventory -ErrorAction SilentlyContinue) -or
    -not (Get-Command Read-MIR4ArchiveText -ErrorAction SilentlyContinue)) {
  . (Join-Path $mirOrdinaryCandidateRepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}

$script:MIROrdinaryCandidateTargets = @('f210', 'f200', 'f110', 'f100', 'f017', 'f016', 'f015', 'f014', 'f013')

function Get-MIROrdinaryCandidateBaseMinimum {
  param(
    [Parameter(Mandatory)]$Info,
    [Parameter(Mandatory)][string]$Target
  )

  $matches = @(
    @($Info.dependencies) | Where-Object {
      $_ -is [string] -and $_ -match '^base\s+>=\s+([0-9]+\.[0-9]+\.[0-9]+)$'
    }
  )
  if ($matches.Count -ne 1) { throw "[mir-ordinary-candidate-base-minimum] $Target" }
  return ([regex]::Match([string]$matches[0], '^base\s+>=\s+([0-9]+\.[0-9]+\.[0-9]+)$').Groups[1].Value)
}

function Get-MIROrdinaryCandidateAssets {
  <#
    Authenticates a complete package candidate for ordinary-release preparation.
    This reader deliberately stops before final acceptance, signing, tagging,
    promotion, publication, or any release-authority decision.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$SourceVersion = '4.7.0'
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath -AllowCurrentCandidateToolingDescendant
  if ([string]$candidate.source_version -cne $SourceVersion) {
    throw '[mir-ordinary-candidate-source-version]'
  }
  if ([string]$candidate.scope -cne 'nine-target') {
    throw '[mir-ordinary-candidate-scope]'
  }

  $rows = @($candidate.targets)
  $actualTargets = @($rows | ForEach-Object { [string]$_.target })
  if ($actualTargets.Count -ne $script:MIROrdinaryCandidateTargets.Count -or
      ($actualTargets -join '|') -cne ($script:MIROrdinaryCandidateTargets -join '|')) {
    throw '[mir-ordinary-candidate-target-set]'
  }

  $assets = [Collections.Generic.List[object]]::new()
  foreach ($row in $rows) {
    $target = [string]$row.target
    foreach ($field in @('distribution_version', 'archive_path', 'archive_sha256', 'content_sha256', 'entry_count')) {
      if ($row.PSObject.Properties.Name -notcontains $field -or [string]$row.$field -eq '') {
        throw "[mir-ordinary-candidate-asset-shape] $target/$field"
      }
    }
    if (-not (Test-Path -LiteralPath ([string]$row.archive_path) -PathType Leaf)) {
      throw "[mir-ordinary-candidate-asset-missing] $target"
    }

    try {
      $inventory = Get-MIR4ArchiveInventory -Path ([string]$row.archive_path)
    } catch {
      throw "[mir-ordinary-candidate-asset-invalid] $target"
    }
    if ([string]$inventory.archive_sha256 -cne [string]$row.archive_sha256 -or
        [string]$inventory.content_sha256 -cne [string]$row.content_sha256 -or
        [int]$inventory.entry_count -ne [int]$row.entry_count) {
      throw "[mir-ordinary-candidate-asset-identity] $target"
    }

    try {
      $info = Read-MIR4ArchiveText -Path ([string]$row.archive_path) -RelativePath 'info.json' | ConvertFrom-Json -Depth 20 -DateKind String
    } catch {
      throw "[mir-ordinary-candidate-info-json] $target"
    }
    if ([string]$info.name -cne 'more-infinite-research' -or
        [string]$info.version -cne [string]$row.distribution_version -or
        [string]$info.factorio_version -notmatch '^[0-9]+\.[0-9]+$') {
      throw "[mir-ordinary-candidate-info-identity] $target"
    }
    $baseMinimum = Get-MIROrdinaryCandidateBaseMinimum -Info $info -Target $target
    $minimumVersion = [version]$baseMinimum
    $lineVersion = [version]([string]$info.factorio_version + '.0')
    if ($minimumVersion.Major -ne $lineVersion.Major -or $minimumVersion.Minor -ne $lineVersion.Minor) {
      throw "[mir-ordinary-candidate-base-line] $target"
    }

    $assets.Add([pscustomobject][ordered]@{
      target = $target
      name = [IO.Path]::GetFileName([string]$row.archive_path)
      path = (Resolve-Path -LiteralPath ([string]$row.archive_path)).Path
      bytes = [int64]$inventory.bytes
      archive_sha256 = [string]$inventory.archive_sha256
      content_sha256 = [string]$inventory.content_sha256
      entry_count = [int]$inventory.entry_count
      distribution_version = [string]$row.distribution_version
      factorio_line = [string]$info.factorio_version
      base_minimum = $baseMinimum
      label = ('MIR {0} for Factorio {1}' -f $SourceVersion, $baseMinimum)
    })
  }

  return [pscustomobject][ordered]@{
    kind = 'MIROrdinaryCandidateAssetsV1'
    status = 'verified-candidate-assets-private-unqualified'
    release_authority = $false
    final_acceptance = 'not-performed'
    source_version = [string]$candidate.source_version
    source = [pscustomobject][ordered]@{
      commit = [string]$candidate.source.commit
      tree = [string]$candidate.source.tree
      package_source_sha256 = [string]$candidate.source.package_source_sha256
    }
    candidate_manifest = [pscustomobject][ordered]@{
      path = [string]$candidate.identity.path
      raw_sha256 = [string]$candidate.identity.sha256
      record_sha256 = [string]$candidate.identity.record.record_sha256
    }
    assets = @($assets.ToArray())
  }
}
