[CmdletBinding()]
param(
  [string]$RepoRoot = "",
  [string]$Repository = "Julesc013/more-infinite-research",
  [string]$GhExecutable = "gh",
  [string]$OutputPath = "build/results/github-administration/preflight.json"
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

if ($Repository -notmatch '^[^/\s]+/[^/\s]+$') {
  throw "Repository must use the owner/name form."
}

function Invoke-MIRGitHubCli {
  param(
    [Parameter(Mandatory)][string]$Operation,
    [Parameter(Mandatory)][string[]]$CommandArguments
  )

  try {
    $lines = @(& $GhExecutable @CommandArguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
  } catch {
    $lines = @([string]$_.Exception.Message)
    $exitCode = 1
  }

  return [pscustomobject]@{
    operation = $Operation
    exit_code = $exitCode
    lines = $lines
    text = ($lines -join "`n").Trim()
  }
}

function New-MIRGitHubFailure {
  param(
    [Parameter(Mandatory)][pscustomobject]$Response,
    [string]$DefaultClassification = "command-failure"
  )

  $httpStatus = $null
  $classification = $DefaultClassification
  if ($Response.text -match '(?i)\bHTTP\s+(401|403|422)\b') {
    $httpStatus = [int]$Matches[1]
    $classification = switch ($httpStatus) {
      401 { "authentication" }
      403 { "authorization-permission" }
      422 { "api-payload-validation" }
    }
  }

  return [ordered]@{
    operation = [string]$Response.operation
    exit_code = [int]$Response.exit_code
    http_status = $httpStatus
    classification = $classification
  }
}

$generatedAt = [DateTimeOffset]::Now.ToString("o", [Globalization.CultureInfo]::InvariantCulture)
$failure = $null
$login = $null
$permissions = $null
$rulesets = @()
$probes = [ordered]@{
  auth_status = "pending"
  authenticated_login = "pending"
  repository_permissions = "pending"
  repository_rulesets = "pending"
}

$auth = Invoke-MIRGitHubCli -Operation "auth-status" -CommandArguments @("auth", "status", "-h", "github.com")
if ($auth.exit_code -ne 0) {
  $failure = New-MIRGitHubFailure -Response $auth -DefaultClassification "authentication"
  $probes.auth_status = "failed"
} else {
  $probes.auth_status = "passed"
}

if ($null -eq $failure) {
  $user = Invoke-MIRGitHubCli -Operation "authenticated-login" -CommandArguments @("api", "user", "--jq", ".login")
  if ($user.exit_code -ne 0) {
    $failure = New-MIRGitHubFailure -Response $user
    $probes.authenticated_login = "failed"
  } else {
    $login = $user.text
    if ([string]::IsNullOrWhiteSpace($login)) {
      $failure = [ordered]@{ operation = "authenticated-login"; exit_code = 1; http_status = $null; classification = "invalid-response" }
      $probes.authenticated_login = "failed"
    } else {
      $probes.authenticated_login = "passed"
    }
  }
}

if ($null -eq $failure) {
  $repositoryProbe = Invoke-MIRGitHubCli -Operation "repository-permissions" -CommandArguments @(
    "api", "repos/$Repository", "--jq", '{admin:.permissions.admin,push:.permissions.push,pull:.permissions.pull}'
  )
  if ($repositoryProbe.exit_code -ne 0) {
    $failure = New-MIRGitHubFailure -Response $repositoryProbe
    $probes.repository_permissions = "failed"
  } else {
    try {
      $permissions = $repositoryProbe.text | ConvertFrom-Json
    } catch {
      $failure = [ordered]@{ operation = "repository-permissions"; exit_code = 1; http_status = $null; classification = "invalid-response" }
    }
    if ($null -ne $permissions -and -not [bool]$permissions.admin) {
      $failure = [ordered]@{ operation = "repository-permissions"; exit_code = 1; http_status = $null; classification = "authorization-permission" }
    }
    $probes.repository_permissions = if ($null -eq $failure) { "passed" } else { "failed" }
  }
}

if ($null -eq $failure) {
  $rulesetProbe = Invoke-MIRGitHubCli -Operation "repository-rulesets" -CommandArguments @(
    "api", "repos/$Repository/rulesets", "--paginate", "--jq", '.[] | [.id,.name,.target,.enforcement] | @tsv'
  )
  if ($rulesetProbe.exit_code -ne 0) {
    $failure = New-MIRGitHubFailure -Response $rulesetProbe
    $probes.repository_rulesets = "failed"
  } else {
    foreach ($line in @($rulesetProbe.lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
      $fields = @([string]$line -split "`t", 4)
      if ($fields.Count -ne 4 -or [string]$fields[0] -notmatch '^[0-9]+$') {
        $failure = [ordered]@{ operation = "repository-rulesets"; exit_code = 1; http_status = $null; classification = "invalid-response" }
        break
      }
      $rulesets += [pscustomobject][ordered]@{
        id = [long]$fields[0]
        name = [string]$fields[1]
        target = [string]$fields[2]
        enforcement = [string]$fields[3]
      }
    }
    $rulesets = @($rulesets | Sort-Object id)
    $probes.repository_rulesets = if ($null -eq $failure) { "passed" } else { "failed" }
  }
}

$receipt = [ordered]@{
  schema = 1
  kind = "MIRGitHubAdministrationPreflightReceiptV1"
  generated_at = $generatedAt
  repository = $Repository
  status = if ($null -eq $failure) { "ready" } else { "failed" }
  environment = [ordered]@{
    gh_token_present = [bool]$env:GH_TOKEN
    github_token_present = [bool]$env:GITHUB_TOKEN
    gh_config_dir_present = [bool]$env:GH_CONFIG_DIR
    userprofile_present = [bool]$env:USERPROFILE
  }
  probes = $probes
  authenticated_login = $login
  permissions = if ($null -eq $permissions) { $null } else {
    [ordered]@{
      admin = [bool]$permissions.admin
      push = [bool]$permissions.push
      pull = [bool]$permissions.pull
    }
  }
  rulesets = [ordered]@{
    count = @($rulesets).Count
    items = @($rulesets)
  }
  failure = $failure
}

$json = $receipt | ConvertTo-Json -Depth 10
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $resolvedOutput = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }
  $outputDirectory = Split-Path -Parent $resolvedOutput
  if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
  }
  [IO.File]::WriteAllText($resolvedOutput, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

Write-Output $json
if ($null -ne $failure) {
  throw "GitHub administration preflight failed at $($failure.operation) ($($failure.classification))."
}
