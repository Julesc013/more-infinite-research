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

# Current validation is allowed to inspect the repository's governance and
# tooling, but must obtain every player-package path through the explicit
# target context. Frozen historical verifiers are deliberately outside this
# check and retain their pinned Git-object readers.
$currentReaders = @(
  'tools/lib/validation/runner/Bootstrap.ps1',
  'tools/lib/validation/runner/StaticCore.ps1',
  'tools/lib/validation/runner/StaticSciencePackSettings.ps1',
  'tools/lib/validation/runner/StaticPrototypeLimits.ps1',
  'tools/lib/validation/runner/StaticCompilerDiagnostics.ps1',
  'tests/architecture/Test-MIRArchitecture.ps1'
)
$rawProductPath = '(?m)Join-Path\s+\$repo\s+["''](?:info\.json|changelog\.txt|thumbnail\.png|settings\.lua|data\.lua|data-updates\.lua|data-final-fixes\.lua|control\.lua|prototypes(?:[\\/]|["''])|locale(?:[\\/]|["''])|migrations(?:[\\/]|["'']))'
foreach ($relative in $currentReaders) {
  $text = Get-Content -Raw -LiteralPath (Join-Path $repo $relative)
  if ($text -match $rawProductPath) { throw "[mir4-current-target-package-raw-root-reader] $relative" }
}

Write-Host '[ok] current validators resolve every player package path through source/composition target authority.'
