param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$policyPath = Join-Path $repo ".mir\module-dependencies.json"
$policy = Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json
if ($policy.schema -ne 1) { throw "Module dependency policy schema must be 1." }

function Get-RelativePath([string]$Path) {
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
foreach ($exception in $policy.exceptions) {
  $exceptionSet[([string]$exception.source + "`n" + [string]$exception.target)] = $true
}

$forbidden = @{}
foreach ($edge in $policy.forbidden_edges) {
  $forbidden[([string]$edge.from + "`n" + [string]$edge.to)] = $true
}

$moduleFiles = Get-ChildItem -LiteralPath (Join-Path $repo "prototypes\mir") -Recurse -File -Filter "*.lua"
$graph = @{}
foreach ($file in $moduleFiles) {
  $source = Get-RelativePath $file.FullName
  $graph[$source] = [Collections.Generic.List[string]]::new()
  $text = Get-Content -Raw -LiteralPath $file.FullName
  foreach ($match in [regex]::Matches($text, 'require\s*\(\s*["''](prototypes\.mir\.[A-Za-z0-9_\.]+)["'']\s*\)')) {
    $target = $match.Groups[1].Value.Replace('.', '/') + '.lua'
    $targetPath = Join-Path $repo $target.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $targetPath)) {
      throw "Lua require target does not exist: $source -> $target"
    }
    $graph[$source].Add($target)
    $fromLayer = Get-Layer $source
    $toLayer = Get-Layer $target
    $edgeKey = [string]$fromLayer + "`n" + [string]$toLayer
    $exceptionKey = $source + "`n" + $target
    if ($forbidden[$edgeKey] -and -not $exceptionSet[$exceptionKey]) {
      throw "Forbidden MIR module dependency: $source ($fromLayer) -> $target ($toLayer)"
    }
  }
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

$overlayRoot = Join-Path $repo ([string]$policy.overlay_policy.path).Replace('/', '\')
foreach ($file in Get-ChildItem -LiteralPath $overlayRoot -File -Filter "*.lua") {
  $text = Get-Content -Raw -LiteralPath $file.FullName
  foreach ($token in $policy.overlay_policy.forbidden_tokens) {
    if ($text.Contains([string]$token)) {
      throw "Compatibility overlay mutates prototypes directly: $(Get-RelativePath $file.FullName) contains $token"
    }
  }
}

$commandsPath = Join-Path $repo ([string]$policy.command_authority).Replace('/', '\')
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

Write-Host "[ok] MIR module dependencies, require cycles, overlays, and command authority passed."
