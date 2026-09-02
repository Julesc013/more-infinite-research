Set-StrictMode -Version Latest

$mir4PackageAuthorityRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4PackageAuthorityRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command New-MIR4DistributionIdentityProjection -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4PackageAuthorityRoot 'tools/lib/validation/MIR4DistributionIdentity.ps1')
}
if (-not (Get-Command Get-MIRFileContentIdentity -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4PackageAuthorityRoot 'tools/lib/validation/PackageIdentity.ps1')
}

function Get-MIR4CanonicalPackageAuthority {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $relative = 'targets/package-authority.json'
  $path = Join-Path $repo $relative
  $raw = Get-Content -Raw -LiteralPath $path
  if (-not ($raw | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-canonical-package-authority-v1.schema.json'))) {
    throw '[mir4-package-authority-schema]'
  }
  $authority = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $authority)) { throw '[mir4-package-authority-record-hash]' }
  foreach ($bindingName in @('source_manifest','target_registry','support_policy')) {
    $binding = $authority.$bindingName
    $bindingPath = Join-Path $repo ([string]$binding.path)
    $record = Get-Content -Raw -LiteralPath $bindingPath | ConvertFrom-Json -Depth 100 -DateKind String
    if ([string]$record.record_sha256 -cne [string]$binding.record_sha256 -or
        -not (Test-MIR4BootstrapRecordHash -Record $record)) {
      throw "[mir4-package-authority-binding] $bindingName"
    }
  }
  $versionBinding = $authority.versioning_authority
  $versionPath = Join-Path $repo ([string]$versionBinding.path)
  if ((Get-MIR4BootstrapTextSha256 -Path $versionPath) -cne [string]$versionBinding.file_sha256) {
    throw '[mir4-package-authority-binding] versioning_authority'
  }
  return $authority
}

function Resolve-MIR4CanonicalPackageIdentity {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target,
    [string]$SourceVersion,
    [string]$DistributionVersion
  )

  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $RepoRoot
  $rows = @($authority.targets | Where-Object { [string]$_.target -ceq $Target })
  if ($rows.Count -ne 1) { throw "[mir4-package-authority-target] $Target" }
  $row = $rows[0]

  if ([string]::IsNullOrWhiteSpace($SourceVersion) -and [string]::IsNullOrWhiteSpace($DistributionVersion)) {
    $SourceVersion = [string]$row.baseline_source_version
  }
  if (-not [string]::IsNullOrWhiteSpace($SourceVersion)) {
    if ($SourceVersion -notmatch '^4[.]([0-9]{1,5})[.]([0-9]{1,2})$') { throw '[mir4-package-source-version]' }
    $minor = [int]$Matches[1]
    $patch = [int]$Matches[2]
  } else {
    if ($DistributionVersion -notmatch '^4[.]([0-9]{1,5})[.]([0-9]{5})$') { throw '[mir4-package-distribution-version]' }
    $minor = [int]$Matches[1]
    $decoded = ConvertFrom-MIR4DistributionComponent -EncodedComponentText ([string]$Matches[2])
    if ([string]$decoded.distribution_target_code -cne [string]$row.distribution_target_code) {
      throw '[mir4-package-distribution-target]'
    }
    $patch = [int]$decoded.source_patch
    $SourceVersion = "4.$minor.$patch"
  }

  $projection = New-MIR4DistributionIdentityProjection `
    -DistributionTargetCode ([string]$row.distribution_target_code) `
    -SourceMinor $minor `
    -SourcePatch $patch
  if (-not [string]::IsNullOrWhiteSpace($DistributionVersion) -and
      [string]$projection.distribution_version -cne [string]$DistributionVersion) {
    throw '[mir4-package-distribution-projection]'
  }
  return [pscustomobject][ordered]@{
    authority = $authority
    target_authority = $row
    target = $Target
    target_id = [string]$row.target_id
    distribution_target_code = [string]$row.distribution_target_code
    source_version = [string]$projection.source_version
    source_minor = [int]$projection.source_minor
    source_patch = [int]$projection.source_patch
    distribution_version = [string]$projection.distribution_version
    distribution_root = "more-infinite-research_$([string]$projection.distribution_version)"
    package_name = [string]$projection.package_name
    is_baseline_reconstruction = (
      [string]$projection.source_version -ceq [string]$row.baseline_source_version -and
      [string]$projection.distribution_version -ceq [string]$row.baseline_distribution_version
    )
  }
}

function Get-MIR4CanonicalPackageSourceRoots {
  return @('src/mod','targets')
}

function Get-MIR4CanonicalPackageSourceFiles {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $files = @()
  foreach ($relativeRoot in Get-MIR4CanonicalPackageSourceRoots) {
    $path = Join-Path $repo $relativeRoot
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "[mir4-package-source-root] $relativeRoot" }
    $files += @(
      Get-ChildItem -LiteralPath $path -Recurse -File |
        ForEach-Object { [IO.Path]::GetRelativePath($repo, $_.FullName).Replace('\','/') }
    )
  }
  return @($files | Sort-Object -Unique -CaseSensitive)
}

function Get-MIR4CanonicalPackageSourceFingerprint {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $rows = @(
    foreach ($relative in Get-MIR4CanonicalPackageSourceFiles -RepoRoot $repo) {
      $identity = Get-MIRFileContentIdentity -Path (Join-Path $repo $relative) -RelativePath $relative
      "{0}`t{1}`t{2}" -f $relative, $identity.Length, $identity.Sha256
    }
  )
  return Get-MIRStringSha256 -Value ($rows -join "`n")
}

function Test-MIR4CanonicalPackageSourceGitDirty {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $roots = @(Get-MIR4CanonicalPackageSourceRoots)
  $status = @(& git -C $RepoRoot status --porcelain -- @roots 2>$null)
  if ($LASTEXITCODE -ne 0) { throw '[mir4-package-source-git-status]' }
  return $status.Count -gt 0
}
