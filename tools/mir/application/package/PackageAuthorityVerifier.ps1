Set-StrictMode -Version Latest

$mir4F2EVerifierRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
. (Join-Path $mir4F2EVerifierRoot 'tools/mir/application/package/PackageAuthority.ps1')

function New-MIR4M41F2EPackageAuthorityVerification {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $canonical = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
  $generic = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  if ($canonical -cne $generic) { throw '[mir4-f2e-reader-cutover]' }

  $expected = [ordered]@{
    f210=@('4.0.0','4.0.21000','CA72A8045654FFDC8630D54567F6D04A1B40BA5682ED06E7FACCF2772A2660ED',305)
    f200=@('4.0.0','4.0.20000','5163E45530CB9B4DAEAC27166279809933750C605BA6E3EC785A0267B9428A1F',303)
    f110=@('4.0.0','4.0.11000','B3DAA35E6E72741D8054C4EC22435CC8216CB6A5E2566D10CF9E3B934E3FF682',174)
    f100=@('4.0.0','4.0.10000','1ABDA788DE4B287A48AB0B8787C8F7826256E4ECAB7085C3A6FDDD1E9DF145B2',174)
  }
  $targets = @(
    foreach ($key in $expected.Keys) {
      $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target $key
      $row = $expected[$key]
      if ([string]$identity.source_version -cne $row[0] -or [string]$identity.distribution_version -cne $row[1] -or
          [string]$identity.target_authority.baseline_content_sha256 -cne $row[2] -or
          [int]$identity.target_authority.baseline_entry_count -ne [int]$row[3]) { throw "[mir4-f2e-target] $key" }
      [pscustomobject][ordered]@{target=$key;source_version=$row[0];distribution_version=$row[1];content_sha256=$row[2];entry_count=[int]$row[3]}
    }
  )

  $builder = Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/commands/package/Build-MIRPackage.ps1')
  $bootstrap = Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/commands/release/New-MIR4BootstrapLocalCandidate.ps1')
  $targetProducts = Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/commands/mir4/New-MIR4TargetProductSet.ps1')
  if (-not $builder.Contains('New-MIR4TargetPackage') -or $builder.Contains('Get-MIRPackageSourceFiles') -or
      -not $bootstrap.Contains('[mir4-package-authority-cutover]') -or -not $bootstrap.Contains('HistoricalCompatibility') -or
      -not $targetProducts.Contains('New-MIR4TargetPackage') -or $targetProducts.Contains("'tools/commands/release/New-MIR4BootstrapLocalCandidate.ps1'")) {
    throw '[mir4-f2e-writer-cutover]'
  }

  $priorPath = Join-Path $repo 'releases/migrations/MIR4-M41-F2D-Four-Target-Runtime-Replay-AggregateV1.json'
  $priorHash = (Get-FileHash -LiteralPath $priorPath -Algorithm SHA256).Hash
  $rollbackCommit = 'cc211688e247a439baaf92466a628cba7dcb0b55'
  $rollbackTree = '7f5647c2c304d34c9278738d234753c229a98572'
  & git -C $repo cat-file -e "$rollbackCommit^{commit}" 2>$null
  if ($LASTEXITCODE -ne 0 -or (& git -C $repo rev-parse "$rollbackCommit^{tree}").Trim() -cne $rollbackTree) { throw '[mir4-f2e-rollback-base]' }

  return [pscustomobject][ordered]@{
    status='M41-F2E-PACKAGE-SOURCE-CUTOVER-VERIFIED'
    package_authority_sha256=[string]$authority.record_sha256
    package_source_sha256=$canonical
    legacy_root_projection_sha256=(Get-MIRLegacyRootPackageSourceFingerprint -RepoRoot $repo)
    predecessor_sha256=$priorHash
    targets=$targets
    writer=[pscustomobject][ordered]@{implementation='tools/mir/application/package/TargetMaterializer.ps1';ordinary_facade='tools/commands/package/Build-MIRPackage.ps1';sole_current_writer=$true;bootstrap_writer_historical_only=$true}
    reader=[pscustomobject][ordered]@{generic_package_identity='canonical-src-mod-plus-targets';legacy_root_reader='explicit-historical-reconstruction-only';generic_matches_canonical=$true;silent_fallback_blocked=$true}
    rollback=[pscustomobject][ordered]@{state='ready';commit=$rollbackCommit;tree=$rollbackTree}
  }
}
