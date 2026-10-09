# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../.."))
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/CurrentTargetPackage.ps1')
$targetPackage = New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target 'f210'
$policyPath = Join-Path $repo ".mir\module-dependencies.json"
$policy = Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json
if ($policy.schema -ne 2 -or [string]$policy.edge_policy -ne "exact-observed-cross-layer-v1") {
  throw "Module dependency policy schema 2 exact matrix is required."
}

function Get-RelativePath([string]$Path) {
  foreach ($entry in Get-MIR4CurrentTargetPackageOutputEntries -Context $targetPackage -Prefix 'prototypes/') {
    if ([IO.Path]::GetFullPath([string]$entry.source_file) -ceq [IO.Path]::GetFullPath($Path)) { return [string]$entry.output_path }
  }
  return [IO.Path]::GetRelativePath($repo, $Path).Replace('\', '/')
}

function Get-Layer([string]$RelativePath) {
  foreach ($layer in $policy.layers) {
    if ($RelativePath.StartsWith([string]$layer.prefix, [StringComparison]::Ordinal)) {
      return [string]$layer.name
    }
  }
  return $null
}

$exceptionSet = @{}
foreach ($exception in $policy.exceptions) { $exceptionSet[([string]$exception.source + "`n" + [string]$exception.target)] = $true }
if ($exceptionSet.Count -ne 0) { throw "Module dependency exceptions are not permitted in schema 2." }

$forbidden = @{}
foreach ($edge in $policy.forbidden_edges) {
  $forbidden[[string]$edge] = $true
}
$allowed = @{}
foreach ($edge in $policy.allowed_edges) {
  if ([string]$edge -notmatch '^[a-z]+->[a-z]+$' -or $allowed.ContainsKey([string]$edge)) {
    throw "Module dependency allowed edge is invalid or duplicated: $edge"
  }
  $allowed[[string]$edge] = $true
}

$moduleFiles = @(Get-MIR4CurrentTargetPackageOutputEntries -Context $targetPackage -Prefix 'prototypes/mir/' |
  Where-Object { [string]$_.output_path -like '*.lua' })
$graph = @{}
$observedEdges = @{}
foreach ($file in $moduleFiles) {
  $source = [string]$file.output_path
  $sourceLayer = Get-Layer $source
  if (-not $sourceLayer) { throw "MIR Lua source has no governed layer: $source" }
  $graph[$source] = [Collections.Generic.List[string]]::new()
  $text = Get-Content -Raw -LiteralPath $file.source_file
  foreach ($match in [regex]::Matches($text, 'require\s*\(\s*["''](prototypes\.mir\.[A-Za-z0-9_\.]+)["'']\s*\)')) {
    $target = $match.Groups[1].Value.Replace('.', '/') + '.lua'
    $targetPath = Resolve-MIR4CurrentTargetPackageOutputPath -Context $targetPackage -RelativePath $target -AllowMissing
    if ($null -eq $targetPath) {
      throw "Lua require target does not exist: $source -> $target"
    }
    $graph[$source].Add($target)
    $fromLayer = Get-Layer $source
    $toLayer = Get-Layer $target
    if (-not $toLayer) { throw "MIR Lua require target has no governed layer: $target" }
    $edgeKey = [string]$fromLayer + "->" + [string]$toLayer
    if ($fromLayer -ne $toLayer) { $observedEdges[$edgeKey] = $true }
    if ($forbidden[$edgeKey]) {
      throw "Forbidden MIR module dependency: $source ($fromLayer) -> $target ($toLayer)"
    }
    if ($fromLayer -ne $toLayer -and -not $allowed[$edgeKey]) {
      throw "Undeclared MIR module dependency: $source ($fromLayer) -> $target ($toLayer)"
    }
  }
}
foreach ($edge in $allowed.Keys) {
  if (-not $observedEdges[$edge]) { throw "Stale allowed MIR module edge is no longer observed: $edge" }
}

$visiting, $visited = @{}, @{}
$cycleExceptionSet = @{}
foreach ($exception in $policy.cycle_exceptions) {
  $key = (@($exception.members | Sort-Object -Unique) -join "`n")
  $cycleExceptionSet[$key] = $true
}
function Visit-Module([string]$Module, [Collections.Generic.List[string]]$Stack) {
  if ($visiting[$Module]) {
    $cycleStart = $Stack.IndexOf($Module)
    $cycle = @($Stack[$cycleStart..($Stack.Count - 1)]) + $Module
    $cycleKey = (@($cycle | Sort-Object -Unique) -join "`n")
    if (-not $cycleExceptionSet[$cycleKey]) {
      throw "MIR Lua require cycle: $($cycle -join ' -> ')"
    }
    return
  }
  if ($visited[$Module]) { return }
  $visiting[$Module] = $true
  $Stack.Add($Module)
  foreach ($target in $graph[$Module]) {
    if ($graph.ContainsKey($target)) { Visit-Module $target $Stack }
  }
  $Stack.RemoveAt($Stack.Count - 1)
  $visiting.Remove($Module)
  $visited[$Module] = $true
}
foreach ($module in @($graph.Keys | Sort-Object)) {
  Visit-Module $module ([Collections.Generic.List[string]]::new())
}

$overlayPrefix = ([string]$policy.overlay_policy.path).TrimEnd('/') + '/'
foreach ($file in Get-MIR4CurrentTargetPackageOutputEntries -Context $targetPackage -Prefix $overlayPrefix) {
  if (-not ([string]$file.output_path -like '*.lua')) { continue }
  $text = Get-Content -Raw -LiteralPath $file.source_file
  foreach ($token in $policy.overlay_policy.forbidden_tokens) {
    if ($text.Contains([string]$token)) {
      throw "Compatibility overlay mutates prototypes directly: $($file.output_path) contains $token"
    }
  }
}

$commandsPath = Resolve-MIR4CurrentTargetPackageOutputPath -Context $targetPackage -RelativePath ([string]$policy.command_authority)
$commandsText = Get-Content -Raw -LiteralPath $commandsPath
foreach ($required in @('kind = ', 'requires_features = ', 'implementation = ', 'function M.order()', 'function M.run(')) {
  if (-not $commandsText.Contains($required)) {
    throw "Pipeline command authority is incomplete: missing $required"
  }
}
$commandMatches = [regex]::Matches($commandsText, '(?m)^\s*\["([a-z0-9-]+)"\]\s*=\s*\{')
if ($commandMatches.Count -eq 0) { throw "Pipeline command authority defines no commands." }
$commandIds = @{}
foreach ($match in $commandMatches) {
  $id = $match.Groups[1].Value
  $commandIds[$id] = 1 + [int]($commandIds[$id] ?? 0)
}
foreach ($id in $commandIds.Keys) {
  if ($commandIds[$id] -ne 2) {
    throw "Pipeline command must appear exactly once in implementation authority and once in order authority: $id"
  }
}

Write-Host "[ok] exact MIR module dependency matrix, zero planner-to-emit exceptions, require cycles, overlays, and command authority passed."
