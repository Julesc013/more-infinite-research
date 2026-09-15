param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/CurrentTargetPackage.ps1')

foreach ($target in @('f210','f200','f110','f100')) {
  $context = New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target $target
  if ($context.outputs.Count -eq 0 -or $context.package_source_sha256 -notmatch '^[A-F0-9]{64}$') {
    throw "[mir4-current-target-package-empty] $target"
  }
  foreach ($required in @('info.json','settings.lua','data.lua','data-updates.lua','data-final-fixes.lua','control.lua')) {
    $path = Resolve-MIR4CurrentTargetPackageOutputPath -Context $context -RelativePath $required
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not $path.StartsWith((Join-Path $repo 'source'), [StringComparison]::OrdinalIgnoreCase)) {
      throw "[mir4-current-target-package-source-boundary] $target $required"
    }
  }
  if ($null -ne (Resolve-MIR4CurrentTargetPackageOutputPath -Context $context -RelativePath 'prototypes/mir/not-declared.lua' -AllowMissing)) {
    throw "[mir4-current-target-package-root-fallback] $target"
  }
}

# The former repository-root player projection has no current source or test
# authority.  Package-shaped paths belong only to source plus a selected
# composition (or to pinned historical Git/archive readers outside this test).
foreach ($retiredRoot in @(
  'info.json', 'changelog.txt', 'thumbnail.png',
  'settings.lua', 'data.lua', 'data-updates.lua', 'data-final-fixes.lua', 'control.lua',
  'prototypes', 'locale', 'migrations'
)) {
  if (Test-Path -LiteralPath (Join-Path $repo $retiredRoot)) {
    throw "[mir4-current-target-package-retired-root-present] $retiredRoot"
  }
}

# Current validation is allowed to inspect the repository's governance and
# tooling, but must obtain every player-package path through the explicit
# target context.  Scan all executable current-tool surfaces by default: a
# hand-maintained list would let a new reader restore the retired root
# projection unnoticed.  The two exceptions below deliberately operate on an
# immutable historical reconstruction, never this checkout; each is tagged at
# the read site and must retain its named proof mechanism.
$historicalReaderExceptions = @{
  'scripts/Invoke-MIRBackportQualification.ps1' = [pscustomobject]@{
    marker = 'MIR4-ROOT-PROJECTION-HISTORICAL-EXCEPTION: backport-source-historical-root-v1'
    proof = '-HistoricalSourceRoot'
  }
  'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1' = [pscustomobject]@{
    marker = 'MIR4-ROOT-PROJECTION-HISTORICAL-EXCEPTION: bootstrap-capsule-historical-root-v1'
    proof = 'Assert-MIR4GitSourceProof'
  }
}
$rawProductPath = '(?im)Join-Path\s+\$(?:repo|repoRoot|repository|root|workspace)\s+["''](?:info\.json|changelog\.txt|thumbnail\.png|settings\.lua|data\.lua|data-updates\.lua|data-final-fixes\.lua|control\.lua|prototypes(?:[\\/]|["''])|locale(?:[\\/]|["''])|migrations(?:[\\/]|["'']))'
$rawRootCounterexample = 'Join-Path $repo ' + '"info.json"'
$fixtureCounterexample = 'Join-Path $fixture ' + '"info.json"'
if ($rawRootCounterexample -notmatch $rawProductPath -or
    $fixtureCounterexample -match $rawProductPath) {
  throw '[mir4-current-target-package-raw-root-reader-guard-invalid]'
}
$toolRoots = @('scripts', 'tests', 'tools')
foreach ($toolRoot in $toolRoots) {
  $toolPath = Join-Path $repo $toolRoot
  if (-not (Test-Path -LiteralPath $toolPath -PathType Container)) { continue }
  Get-ChildItem -LiteralPath $toolPath -Recurse -File -Filter '*.ps1' | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($repo, $_.FullName).Replace('\', '/')
    $text = Get-Content -Raw -LiteralPath $_.FullName
    if ($text -notmatch $rawProductPath) { return }
    $exception = $historicalReaderExceptions[$relative]
    if ($null -eq $exception) {
      throw "[mir4-current-target-package-raw-root-reader] $relative"
    }
    if ($text -notmatch [regex]::Escape([string]$exception.marker) -or
        $text -notmatch [regex]::Escape([string]$exception.proof)) {
      throw "[mir4-current-target-package-historical-reader-ungoverned] $relative"
    }
  }
}

Write-Host '[ok] current validators resolve every player package path through source/composition target authority.'
