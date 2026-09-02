# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [switch]$SkipFetch
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $MirLegacyScriptRoot "..")

$branches = @{
  main = @{
    FactorioVersion = "2.1"
    BaseDependencyPattern = "^base\s+>=\s+2\.1(\.|$)"
    Description = "latest stable Factorio 2.1.x release line"
  }
  dev = @{
    FactorioVersion = "2.1"
    BaseDependencyPattern = "^base\s+>=\s+2\.1(\.|$)"
    Description = "next-minor or next-major MIR 4 integration line"
  }
  "release/4.0" = @{
    FactorioVersion = "2.1"
    BaseDependencyPattern = "^base\s+>=\s+2\.1(\.|$)"
    Description = "maintained MIR 4.0.x patch line"
  }
  legacy = @{
    FactorioVersion = "2.1"
    BaseDependencyPattern = "^base\s+>=\s+2\.1(\.|$)"
    Description = "latest MIR 3 Factorio 2.1 compatibility alias"
  }
}

$historicalLegacyCommit = "89719eb8ea5c938b6a0e9d816e6324d4d59b87bb"

function Invoke-Git {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  $output = & git -C $repo @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "git $($Arguments -join ' ') failed: $output"
  }
  return $output
}

function Test-GitRefExists {
  param([string]$Ref)
  & git -C $repo rev-parse --verify --quiet $Ref *> $null
  return $LASTEXITCODE -eq 0
}

function Read-InfoJsonFromRef {
  param([string]$Ref)
  $text = Invoke-Git show "$Ref`:info.json"
  return ($text -join "`n") | ConvertFrom-Json
}

if (-not $SkipFetch) {
  foreach ($branch in $branches.Keys) {
    Invoke-Git fetch --no-tags origin "+refs/heads/$branch`:refs/remotes/origin/$branch" | Out-Null
  }
  Invoke-Git remote set-head origin --auto | Out-Null
}

$originHead = $null
if (Test-GitRefExists "refs/remotes/origin/HEAD") {
  $originHead = (Invoke-Git symbolic-ref refs/remotes/origin/HEAD | Select-Object -First 1).Trim()
}
if ($originHead -and $originHead -ne "refs/remotes/origin/main") {
  throw "origin/HEAD must point to origin/main; found $originHead."
}

$baseRef = $env:GITHUB_BASE_REF
if (-not [string]::IsNullOrWhiteSpace($baseRef) -and -not $branches.ContainsKey($baseRef)) {
  throw "Pull requests must target main, dev, legacy, or release/4.0; found $baseRef."
}

foreach ($branch in @("main", "dev", "legacy", "release/4.0")) {
  $ref = "refs/remotes/origin/$branch"
  if (-not (Test-GitRefExists $ref)) {
    throw "Missing permanent branch origin/$branch."
  }

  $policy = $branches[$branch]
  $info = Read-InfoJsonFromRef $ref
  if ($info.name -ne "more-infinite-research") {
    throw "origin/$branch info.json has unexpected mod name '$($info.name)'."
  }
  $resolvedCommit = (Invoke-Git rev-parse "$ref`^{commit}" | Select-Object -First 1).Trim()
  $legacyTransitionState = ($branch -eq "legacy" -and $resolvedCommit -eq $historicalLegacyCommit -and $info.factorio_version -eq "2.0")
  if (-not $legacyTransitionState -and $info.factorio_version -ne $policy.FactorioVersion) {
    throw "origin/$branch must target Factorio $($policy.FactorioVersion) for the $($policy.Description); found $($info.factorio_version)."
  }

  $baseDependency = @($info.dependencies) | Where-Object { $_ -match "^base\s+>=" } | Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($baseDependency)) {
    throw "origin/$branch must declare a base dependency."
  }
  $baseDependencyPattern = if ($legacyTransitionState) { "^base\s+>=\s+2\.0(\.|$)" } else { $policy.BaseDependencyPattern }
  if ($baseDependency -notmatch $baseDependencyPattern) {
    throw "origin/$branch has invalid base dependency '$baseDependency' for the $($policy.Description)."
  }
}

Write-Host "[ok] branch policy validated for the latest-stable main line, next-release dev line, release/4.0, and the governed legacy alias."
