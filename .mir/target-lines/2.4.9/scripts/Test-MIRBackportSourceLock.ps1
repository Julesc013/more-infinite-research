param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$lockPath = Join-Path $RepoRoot ".mir\backport-source-lock.json"
$lock = Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json

if ([int]$lock.schema -ne 2 -or [int]$lock.projection_schema -ne 2 -or
    [string]$lock.backport_kind -ne "legacy-stability-patch") {
  throw "Unsupported MIR legacy stability source-lock schema."
}
if ([string]$lock.baseline_version -ne "2.4.5" -or [string]$lock.target -ne "2.0" -or
    [string]$lock.mir_version -ne "2.4.9") {
  throw "The source lock must bind MIR 2.4.9 for Factorio 2.0 to the published MIR 2.4.5 baseline."
}

foreach ($field in @("baseline_release_commit", "baseline_package_source_commit", "portable_fix_source_commit")) {
  $commit = [string]$lock.$field
  & git -C $RepoRoot cat-file -e "$commit`^{commit}"
  if ($LASTEXITCODE -ne 0) { throw "Backport authority commit is unavailable: $field=$commit" }
}
$info = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "info.json") | ConvertFrom-Json
if ([string]$info.version -ne [string]$lock.mir_version -or [string]$info.factorio_version -ne [string]$lock.target) {
  throw "Source-lock target identity disagrees with info.json."
}
$targetHash = (Get-FileHash -LiteralPath (Join-Path $RepoRoot ".mir\targets.json") -Algorithm SHA256).Hash
if ($targetHash -ne [string]$lock.target_profile_sha256) {
  throw "Target profile hash drifted from the Factorio 2.0 source lock."
}

. (Join-Path $RepoRoot "scripts\validation\PackageIdentity.ps1")
$roots = @(Get-MIRPackageSourceRoots)
$baseline = [string]$lock.baseline_package_source_commit
$baselineRows = @()
foreach ($line in @(& git -C $RepoRoot ls-tree -r $baseline -- @roots)) {
  if ($line -match '^\d+\s+blob\s+([0-9a-f]+)\t(.+)$') {
    $baselineRows += "$($Matches[2])`t$($Matches[1])"
  }
}
if ($LASTEXITCODE -ne 0 -or $baselineRows.Count -eq 0) {
  throw "Unable to fingerprint the published MIR 2.4.5 package source."
}
$baselineHash = Get-MIRStringSha256 -Value (($baselineRows | Sort-Object) -join "`n")
if ($baselineHash -ne [string]$lock.baseline_package_source_sha256) {
  throw "Published MIR 2.4.5 package-source fingerprint disagrees with the source lock."
}

$changed = @(& git -C $RepoRoot diff --name-only $baseline -- @roots)
if ($LASTEXITCODE -ne 0) { throw "Unable to compare the stability patch with MIR 2.4.5." }
$untracked = @(& git -C $RepoRoot ls-files --others --exclude-standard -- @roots)
$changed = @(($changed + $untracked) | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique)
$declared = @($lock.adapted_package_paths.PSObject.Properties.Name | Sort-Object -Unique)
$undeclared = @($changed | Where-Object { $declared -notcontains $_ })
$stale = @($declared | Where-Object { $changed -notcontains $_ })
if ($undeclared.Count -gt 0) {
  throw "Package files differ from MIR 2.4.5 without a declared 2.4.9 backport reason: $($undeclared -join ', ')"
}
if ($stale.Count -gt 0) {
  throw "Declared 2.4.9 package paths no longer differ from MIR 2.4.5: $($stale -join ', ')"
}

$directEffects = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\streams\direct-effects.lua")
foreach ($unsupported in @("cargo-landing-pad-count", "max-cargo-bay-unloading-distance")) {
  if ($directEffects -match [regex]::Escape($unsupported)) {
    throw "Factorio 2.1-only technology modifier leaked into the 2.0 backport: $unsupported"
  }
}
$targetProfileText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\platform\factorio\target_profiles.lua")
if ($targetProfileText -notmatch '(?s)\["2\.0"\].*?mod_data\s*=\s*false') {
  throw "Factorio 2.0 target profile must explicitly disable mod-data prototypes."
}
$modDataEmitterText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\emit\mod_data.lua")
if (-not $modDataEmitterText.Contains("target_line.mod_data_supported()")) {
  throw "The mod-data emitter is not guarded by the target capability."
}
$adoptionText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\runtime\productivity_family_adoption.lua")
if ($adoptionText.Contains("reset_technology_effects")) {
  throw "The 2.4.9 stability patch must not perform a global technology-effect reset."
}

Write-Host "[ok] MIR 2.4.9 is a bounded Factorio 2.0 stability patch over published MIR 2.4.5 with $($changed.Count) declared package paths."
