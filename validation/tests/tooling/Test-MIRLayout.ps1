$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
. (Join-Path $repo "tools/lib/workspace/RepoPaths.ps1")

$paths = Read-MIRRepoPathCatalog -RepoRoot $repo
$aliases = Read-MIRRepoAliasCatalog -RepoRoot $repo -PathCatalog $paths
if ($paths.paths.PSObject.Properties["releases.deltas"].Value -ne ".mir/releases/deltas") {
  throw "Release delta path ID changed."
}
if (@($aliases.aliases | Where-Object from -eq "approved-delta/").Count -ne 1) {
  throw "Historical approved-delta alias is missing."
}

$canonical = Resolve-MIRRepoPath -RepoRoot $repo -Id "releases.deltas"
if ($canonical.alias -or $canonical.relative_path -ne ".mir/releases/deltas") {
  throw "Canonical release delta resolution failed."
}
$legacy = Resolve-MIRRepoPath -RepoRoot $repo -Path "approved-delta/3.2.1-to-3.2.2.json"
if (-not $legacy.alias -or $legacy.mode -ne "historical-read-only" -or
    $legacy.relative_path -ne ".mir/releases/deltas/3.2.1-to-3.2.2.json") {
  throw "Historical release delta resolution failed."
}

foreach ($bad in @("../outside", "C:/absolute", 'docs\bad')) {
  $rejected = $false
  try { $null = Resolve-MIRRepoPath -RepoRoot $repo -Path $bad }
  catch { $rejected = $true }
  if (-not $rejected) { throw "Unsafe durable path was accepted: $bad" }
}

$manifest = New-MIRLayoutManifest -RepoRoot $repo
if ($manifest.summary.unclassified -ne 0 -or $manifest.summary.case_collisions -ne 0 -or $manifest.summary.links -ne 0) {
  throw "Layout manifest contains unsafe or unclassified paths: $($manifest.summary | ConvertTo-Json -Compress)"
}
if ($manifest.summary.legacy -eq 0) { throw "Migration baseline unexpectedly contains no legacy paths." }

function Invoke-MIRCliProbe {
  param([Parameter(Mandatory)][string]$Entrypoint, [Parameter(Mandatory)][string[]]$Arguments)
  $output = (& pwsh -NoProfile -File $Entrypoint @Arguments 2>&1 | Out-String).Replace("`r`n", "`n").Trim()
  return [pscustomobject]@{exit_code=$LASTEXITCODE;output=$output}
}

foreach ($arguments in @(
  [string[]]@("help"),
  [string[]]@("path", "resolve", "releases.deltas"),
  [string[]]@("path", "resolve", "--path", "approved-delta/3.2.1-to-3.2.2.json")
)) {
  $legacyCli = Invoke-MIRCliProbe -Entrypoint (Join-Path $repo "scripts/mir.ps1") -Arguments $arguments
  $stableCli = Invoke-MIRCliProbe -Entrypoint (Join-Path $repo "tools/mir.ps1") -Arguments $arguments
  if ($legacyCli.exit_code -ne $stableCli.exit_code -or $legacyCli.output -cne $stableCli.output) {
    throw "Stable CLI parity failed for: $($arguments -join ' ')"
  }
}

Write-Host "[ok] repository paths, historical aliases, ownership inventory, layout safety, and CLI facade parity agree."
