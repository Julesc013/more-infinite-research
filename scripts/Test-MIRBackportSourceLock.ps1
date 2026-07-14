param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$lockPath = Join-Path $RepoRoot ".mir\backport-source-lock.json"
$lock = Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json

if ([int]$lock.schema -ne 1 -or [int]$lock.projection_schema -ne 1) {
  throw "Unsupported MIR backport source-lock schema."
}
if ([string]$lock.canonical_version -ne "3.1.9" -or [string]$lock.target -ne "2.0" `
    -or [string]$lock.mir_version -ne "2.4.5") {
  throw "The source lock must bind MIR 2.4.5 for Factorio 2.0 to canonical MIR 3.1.9."
}

$anchor = [string]$lock.canonical_anchor
$packageSource = [string]$lock.canonical_package_source_commit
& git -C $RepoRoot cat-file -e "$anchor`^{commit}"
if ($LASTEXITCODE -ne 0) { throw "Canonical 3.1.9 anchor is unavailable: $anchor" }
& git -C $RepoRoot cat-file -e "$packageSource`^{commit}"
if ($LASTEXITCODE -ne 0) { throw "Canonical 3.1.9 package-source commit is unavailable: $packageSource" }
& git -C $RepoRoot merge-base --is-ancestor $anchor HEAD
if ($LASTEXITCODE -ne 0) { throw "The Factorio 2.0 projection does not contain canonical 3.1.9 in its ancestry." }

$info = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "info.json") | ConvertFrom-Json
if ([string]$info.version -ne [string]$lock.mir_version -or [string]$info.factorio_version -ne [string]$lock.target) {
  throw "Source-lock target identity disagrees with info.json."
}
$targetHash = (Get-FileHash -LiteralPath (Join-Path $RepoRoot ".mir\targets.json") -Algorithm SHA256).Hash
if ($targetHash -ne [string]$lock.target_profile_sha256) {
  throw "Target profile hash drifted from the Factorio 2.0 source lock."
}

$canonicalSealText = & git -C $RepoRoot show "$anchor`:.mir/evidence/candidate-seals/mir-3.1.9-factorio-2.1.json"
if ($LASTEXITCODE -ne 0) { throw "Canonical 3.1.9 seal is unavailable from the source anchor." }
$canonicalSeal = ($canonicalSealText -join "`n") | ConvertFrom-Json
if ([string]$canonicalSeal.package_source_sha256 -ne [string]$lock.canonical_package_source_sha256) {
  throw "Canonical package-source fingerprint disagrees with the sealed 3.1.9 anchor."
}

. (Join-Path $RepoRoot "scripts\validation\PackageIdentity.ps1")
$roots = @(Get-MIRPackageSourceRoots)
$changed = @(& git -C $RepoRoot diff --name-only $packageSource -- @roots)
if ($LASTEXITCODE -ne 0) { throw "Unable to compare the target projection with canonical 3.1.9." }
$changed = @($changed | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique)
$declared = @($lock.adapted_package_paths.PSObject.Properties.Name | Sort-Object -Unique)
$undeclared = @($changed | Where-Object { $declared -notcontains $_ })
$stale = @($declared | Where-Object { $changed -notcontains $_ })
if ($undeclared.Count -gt 0) {
  throw "Portable package files differ without a declared Factorio 2.0 adapter: $($undeclared -join ', ')"
}
if ($stale.Count -gt 0) {
  throw "Declared Factorio 2.0 package adapters no longer differ from canonical source: $($stale -join ', ')"
}

$directEffects = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\streams\direct-effects.lua")
foreach ($unsupported in @("cargo-landing-pad-count", "max-cargo-bay-unloading-distance")) {
  if ($directEffects -match [regex]::Escape($unsupported)) {
    throw "Factorio 2.1-only technology modifier leaked into the 2.0 projection: $unsupported"
  }
}

Write-Host "[ok] MIR 2.4.5 is a declared Factorio 2.0 projection of canonical 3.1.9 with $($changed.Count) target-adapted package paths."
