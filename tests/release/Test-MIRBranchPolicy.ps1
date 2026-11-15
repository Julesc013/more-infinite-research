# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [switch]$SkipFetch,
  [switch]$ReportPolicyOnly,
  [string]$EventPath = $env:GITHUB_EVENT_PATH,
  [string]$ReportCommitsPath
)

$ErrorActionPreference = "Stop"

function Test-ReportResolution {
  param([string]$EventFile, [string]$CommitsFile, [string]$RepositoryRoot)
  if ([string]::IsNullOrWhiteSpace($EventFile)) {
    if ($ReportPolicyOnly) { throw '[mir-report-event-required] Supply the pull-request event JSON.' }
    return
  }
  $event = Get-Content -Raw -LiteralPath $EventFile | ConvertFrom-Json -Depth 64
  if ($null -eq $event.pull_request) {
    if ($ReportPolicyOnly -or $env:GITHUB_EVENT_NAME -eq 'pull_request') {
      throw '[mir-report-event-invalid] Pull-request metadata is missing.'
    }
    return
  }
  $pr = $event.pull_request
  $body = if ($null -eq $pr.body) { '' } elseif ($pr.body -is [string]) { $pr.body }
    else { throw '[mir-report-event-invalid] Pull-request body must be text or null.' }
  $base = [string]$pr.base.sha
  $head = [string]$pr.head.sha
  if ($base -cnotmatch '^[0-9a-f]{40}$' -or $head -cnotmatch '^[0-9a-f]{40}$' -or
      ($pr.commits -isnot [long] -and $pr.commits -isnot [int]) -or $pr.commits -lt 0) {
    throw '[mir-report-event-invalid] Exact base/head SHAs and the commit count are required.'
  }

  # The normal workflow already has these objects. This guard never fetches.
  # A bound local packet permits the same policy to be checked without Git/network.
  if (-not [string]::IsNullOrWhiteSpace($CommitsFile)) {
    if (-not $ReportPolicyOnly) { throw '[mir-report-commits-mode] Local commit input requires -ReportPolicyOnly.' }
    $packet = Get-Content -Raw -LiteralPath $CommitsFile | ConvertFrom-Json -Depth 32
    if ($packet.base_sha -cne $base -or $packet.head_sha -cne $head -or $null -eq $packet.commits) {
      throw '[mir-report-commits-binding] Commit input does not describe the event head/base.'
    }
    $commits = @($packet.commits)
  } else {
    $ids = @(& git --no-lazy-fetch -C $RepositoryRoot rev-list --reverse "$base..$head" --)
    if ($LASTEXITCODE -ne 0) { throw '[mir-report-commits-unavailable] Event commit objects are unavailable; no history was fetched.' }
    if ($ids.Count -ne $pr.commits) { throw '[mir-report-commits-count] Event and local commit range differ.' }
    $commits = @(
      foreach ($id in $ids) {
        if ($id -cnotmatch '^[0-9a-f]{40}$') { throw '[mir-report-commit-invalid] Invalid commit identity.' }
        $message = @(& git --no-lazy-fetch -C $RepositoryRoot show -s --format=%B $id --)
        if ($LASTEXITCODE -ne 0) { throw '[mir-report-commits-unavailable] Unable to read a named commit message.' }
        [pscustomobject]@{ sha = $id; message = $message -join "`n" }
      }
    )
  }
  if ($commits.Count -ne $pr.commits) { throw '[mir-report-commits-count] Commit input is incomplete.' }
  $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($commit in $commits) {
    if ($commit.sha -cnotmatch '^[0-9a-f]{40}$' -or $commit.message -isnot [string] -or -not $seen.Add($commit.sha)) {
      throw '[mir-report-commit-invalid] Commit messages require unique exact identities and text.'
    }
  }
  if ($commits.Count -gt 0 -and -not $seen.Contains($head)) {
    throw '[mir-report-commits-binding] Commit input omits the event head.'
  }

  $scopeRows = [regex]::Matches($body, '(?im)^[ \t]*Report scope:[ \t]*([^\r\n]*)\r?$')
  if ($scopeRows.Count -gt 1) { throw '[mir-report-scope] Declare report scope once.' }
  $scope = if ($scopeRows.Count) { $scopeRows[0].Groups[1].Value.Trim().ToLowerInvariant() } else { '' }
  if ($scope -eq '') { $scope = 'none' }
  if ($scope -notin @('none', 'diagnostic', 'partial', 'unverified', 'functional-candidate', 'complete')) {
    throw '[mir-report-scope] Unknown report scope.'
  }

  # Conservatively recognize documented keyword forms, plus GitHub issue URLs.
  # Manual issue/sidebar actions remain outside this read-only PR check.
  $reference = '(?:#[1-9][0-9]*|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*|https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(?:issues|pull)/[1-9][0-9]*)'
  $closing = '(?i)(?<![A-Za-z0-9_])(?:close[sd]?|fix(?:es|ed)?|resolve[sd]?)(?:[ \t\r\n]*:[ \t\r\n]*|[ \t\r\n]+)(?<target>' + $reference + ')'
  $closingTargets = @([regex]::Matches($body, $closing) | ForEach-Object { $_.Groups['target'].Value })
  foreach ($commit in $commits) {
    $closingTargets += @([regex]::Matches($commit.message, $closing) | ForEach-Object { $_.Groups['target'].Value })
  }
  if ($closingTargets.Count -gt 0 -and $scope -ne 'complete') {
    throw '[mir-report-closure-scope] Automatic issue-closing directives require complete verified delivery. Use related links while report work remains.'
  }
  if ($scope -eq 'complete') {
    function Convert-ReportReference([string]$Value) {
      if ($Value.StartsWith('#')) {
        $repository = [string]$event.repository.full_name
        if ($repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
          throw '[mir-report-event-invalid] A relative issue reference needs the event repository.'
        }
        $Value = $repository + $Value
      }
      $Value = $Value -replace '^https://github\.com/([^/]+/[^/]+)/(?:issues|pull)/', '$1#'
      return $Value.ToLowerInvariant()
    }
    foreach ($field in @('Report', 'Reproduction evidence', 'Regression evidence', 'Native/preservation evidence', 'Delivery evidence')) {
      $rows = [regex]::Matches($body, '(?im)^[ \t]*' + [regex]::Escape($field) + ':[ \t]*([^\r\n]*)\r?$')
      $value = if ($rows.Count -eq 1) { $rows[0].Groups[1].Value.Trim() } else { '' }
      if (-not $value -or $value -match '^(?i:pending|unverified|not run|not reproduced|todo|tbd|none|n/?a)(?:\b|$)' -or
          $value -match '^<.*>$') {
        throw "[mir-report-complete-evidence] Complete resolution needs one non-placeholder '$field' value."
      }
      if ($field -eq 'Report' -and -not [regex]::IsMatch($value, $reference, 'IgnoreCase')) {
        throw '[mir-report-complete-report] Link the original player issue, not only a release summary.'
      }
      if ($field -eq 'Report') {
        $reported = @([regex]::Matches($value, $reference, 'IgnoreCase') | ForEach-Object { Convert-ReportReference $_.Value })
        foreach ($target in $closingTargets) {
          if ((Convert-ReportReference $target) -notin $reported) {
            throw '[mir-report-closure-target] Every closing target needs its own declared report and evidence.'
          }
        }
      }
      if ($value -match '^(?i:not applicable)' -and
          ($field -ne 'Native/preservation evidence' -or $value -notmatch '^(?i:not applicable):\s*\S.+')) {
        throw '[mir-report-native-applicability] Explain native non-applicability explicitly; other evidence cannot be omitted.'
      }
    }
  }
  Write-Host "[ok] report resolution claims: $scope; $($commits.Count) commit messages checked; evidence still requires independent review."
}

Test-ReportResolution -EventFile $EventPath -CommitsFile $ReportCommitsPath -RepositoryRoot (Join-Path $PSScriptRoot '../..')
if ($ReportPolicyOnly) { return }
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
    Description = "next-minor or next-major MIR integration line"
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
  $rootInfo = 'info.json'
  $nativeInfo = 'source/info.json'
  $nativeTargets = 'targets/editions.json'
  $composedInfo = 'source/presentation/f210/info.json.template'
  & git -C $repo cat-file -e "$Ref`:$nativeInfo" 2>$null
  if ($LASTEXITCODE -eq 0) {
    & git -C $repo cat-file -e "$Ref`:$nativeTargets" 2>$null
    if ($LASTEXITCODE -ne 0) { throw "$Ref has native source without its edition record." }
    $targets = ((Invoke-Git show "$Ref`:$nativeTargets") -join "`n") | ConvertFrom-Json
    if ($null -eq $targets) { throw "$Ref has an unreadable native edition record." }
    return ((Invoke-Git show "$Ref`:$nativeInfo") -join "`n") | ConvertFrom-Json
  }
  & git -C $repo cat-file -e "$Ref`:$rootInfo" 2>$null
  $hasRootInfo = $LASTEXITCODE -eq 0
  if ($hasRootInfo) {
    $path = $rootInfo
  } else {
    foreach ($requiredPath in @($composedInfo, 'source/package-source.json', 'targets/package-authority.json')) {
      & git -C $repo cat-file -e "$Ref`:$requiredPath" 2>$null
      if ($LASTEXITCODE -ne 0) {
        throw "$Ref has neither root info.json nor a complete composed F210 package authority; missing $requiredPath."
      }
    }
    $path = $composedInfo
  }
  $text = Invoke-Git show "$Ref`:$path"
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
    throw "origin/$branch package info has unexpected mod name '$($info.name)'."
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
