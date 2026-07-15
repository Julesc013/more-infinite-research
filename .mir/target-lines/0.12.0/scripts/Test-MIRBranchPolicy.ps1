param(
  [switch]$SkipFetch
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")

$branches = @{
  main = @{
    FactorioVersion = "2.1"
    BaseDependencyPattern = "^base\s+>=\s+2\.1(\.|$)"
    Description = "latest stable Factorio 2.1.x release line"
  }
  dev = @{
    FactorioVersion = "2.1"
    BaseDependencyPattern = "^base\s+>=\s+2\.1(\.|$)"
    Description = "experimental development branch for the main Factorio 2.1.x line"
  }
  legacy = @{
    FactorioVersion = "2.0"
    BaseDependencyPattern = "^base\s+>=\s+2\.0(\.|$)"
    Description = "Factorio 2.0.x backport branch"
  }
}

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
  throw "Pull requests must target one of main, dev, or legacy; found $baseRef."
}

foreach ($branch in @("main", "dev", "legacy")) {
  $ref = "refs/remotes/origin/$branch"
  if (-not (Test-GitRefExists $ref)) {
    throw "Missing permanent branch origin/$branch."
  }

  $policy = $branches[$branch]
  $info = Read-InfoJsonFromRef $ref
  if ($info.name -ne "more-infinite-research") {
    throw "origin/$branch info.json has unexpected mod name '$($info.name)'."
  }
  if ($info.factorio_version -ne $policy.FactorioVersion) {
    throw "origin/$branch must target Factorio $($policy.FactorioVersion) for the $($policy.Description); found $($info.factorio_version)."
  }

  $baseDependency = @($info.dependencies) | Where-Object { $_ -match "^base\s+>=" } | Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($baseDependency)) {
    throw "origin/$branch must declare a base dependency."
  }
  if ($baseDependency -notmatch $policy.BaseDependencyPattern) {
    throw "origin/$branch has invalid base dependency '$baseDependency' for the $($policy.Description)."
  }
}

Write-Host "[ok] branch policy validated for origin/main, origin/dev, and origin/legacy."
