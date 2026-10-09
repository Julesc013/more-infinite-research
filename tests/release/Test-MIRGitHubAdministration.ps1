# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$toolPath = Join-Path $RepoRoot "tools/commands/release/Test-MIRGitHubAdministration.ps1"
if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
  throw "Canonical GitHub administration preflight is missing."
}

$scratch = Join-Path $RepoRoot ("build/results/github-administration-self-test/" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
$fakeScript = Join-Path $scratch "fake-gh.ps1"
$fakeCommand = Join-Path $scratch "fake-gh.cmd"
$sentinelGh = "MIR_GH_TOKEN_MUST_NOT_LEAK_619C4E24"
$sentinelGitHub = "MIR_GITHUB_TOKEN_MUST_NOT_LEAK_8D5F210B"
$originalGhToken = $env:GH_TOKEN
$originalGitHubToken = $env:GITHUB_TOKEN
$originalMode = $env:MIR_GH_ADMIN_TEST_MODE

try {
  @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandArguments)

if ($CommandArguments.Count -ge 2 -and $CommandArguments[0] -eq "auth" -and $CommandArguments[1] -eq "status") {
  "github.com"
  exit 0
}

if ($env:MIR_GH_ADMIN_TEST_MODE -match '^http(401|403|422)$') {
  [Console]::Error.WriteLine("gh: simulated API failure (HTTP $($Matches[1]))")
  exit 1
}

if ($CommandArguments.Count -ge 2 -and $CommandArguments[0] -eq "api" -and $CommandArguments[1] -eq "user") {
  "Julesc013"
  exit 0
}

if ($CommandArguments.Count -ge 2 -and $CommandArguments[0] -eq "api" -and $CommandArguments[1] -match '/rulesets$') {
  "101`tMIR terminal dev integrity`tbranch`tactive"
  "102`tMIR terminal tag integrity`ttag`tactive"
  exit 0
}

if ($CommandArguments.Count -ge 2 -and $CommandArguments[0] -eq "api" -and $CommandArguments[1] -match '/immutable-releases$') {
  switch ($env:MIR_GH_ADMIN_TEST_MODE) {
    'immutable-enabled' { '{"enabled":true,"enforced_by_owner":false}' }
    'immutable-owner' { '{"enabled":false,"enforced_by_owner":true}' }
    'immutable-invalid' { '{"enabled":"false","enforced_by_owner":false}' }
    default { '{"enabled":false,"enforced_by_owner":false}' }
  }
  exit 0
}

if ($CommandArguments.Count -ge 2 -and $CommandArguments[0] -eq "api" -and $CommandArguments[1] -match '^repos/') {
  '{"admin":true,"push":true,"pull":true}'
  exit 0
}

[Console]::Error.WriteLine("gh: unexpected simulated command")
exit 2
'@ | Set-Content -LiteralPath $fakeScript -Encoding utf8
  '@pwsh -NoProfile -File "%~dp0fake-gh.ps1" %*' + [Environment]::NewLine + '@exit /b %ERRORLEVEL%' |
    Set-Content -LiteralPath $fakeCommand -Encoding ascii

  $env:GH_TOKEN = $sentinelGh
  $env:GITHUB_TOKEN = $sentinelGitHub
  $env:MIR_GH_ADMIN_TEST_MODE = "success"
  $successReceiptPath = Join-Path $scratch "success.json"
  & pwsh -NoProfile -File $toolPath -RepoRoot $RepoRoot -GhExecutable $fakeCommand -OutputPath $successReceiptPath | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "GitHub administration success self-test failed." }
  $successRaw = Get-Content -Raw -LiteralPath $successReceiptPath
  $success = $successRaw | ConvertFrom-Json -Depth 20
  if ([string]$success.kind -ne "MIRGitHubAdministrationPreflightReceiptV1" -or
      [string]$success.status -ne "ready" -or [string]$success.authenticated_login -ne "Julesc013" -or
      -not [bool]$success.permissions.admin -or @($success.rulesets.items).Count -ne 2 -or
      [string]$success.probes.auth_status -ne "passed" -or [string]$success.probes.repository_rulesets -ne "passed" -or
      [string]$success.probes.release_immutability -ne 'passed' -or $success.release_immutability.enabled -or $success.release_immutability.enforced_by_owner -or
      -not [bool]$success.environment.gh_token_present -or -not [bool]$success.environment.github_token_present) {
    throw "GitHub administration success receipt is incomplete."
  }
  if ($successRaw.Contains($sentinelGh) -or $successRaw.Contains($sentinelGitHub)) {
    throw "GitHub administration receipt leaked an environment token value."
  }

  $expectedClassifications = @{
    401 = "authentication"
    403 = "authorization-permission"
    422 = "api-payload-validation"
  }
  foreach ($httpStatus in @(401, 403, 422)) {
    $env:MIR_GH_ADMIN_TEST_MODE = "http$httpStatus"
    $failureReceiptPath = Join-Path $scratch "failure-$httpStatus.json"
    & pwsh -NoProfile -File $toolPath -RepoRoot $RepoRoot -GhExecutable $fakeCommand -OutputPath $failureReceiptPath 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { throw "GitHub administration HTTP $httpStatus self-test unexpectedly passed." }
    $failureRaw = Get-Content -Raw -LiteralPath $failureReceiptPath
    $failure = $failureRaw | ConvertFrom-Json -Depth 20
    if ([string]$failure.status -ne "failed" -or [int]$failure.failure.http_status -ne $httpStatus -or
        [string]$failure.failure.classification -ne [string]$expectedClassifications[$httpStatus] -or
        $failureRaw.Contains($sentinelGh) -or $failureRaw.Contains($sentinelGitHub)) {
      throw "GitHub administration HTTP $httpStatus classification is incorrect or unsafe."
    }
  }
  foreach ($mode in @('immutable-enabled','immutable-owner','immutable-invalid')) {
    $env:MIR_GH_ADMIN_TEST_MODE = $mode
    $receiptPath = Join-Path $scratch "$mode.json"
    & pwsh -NoProfile -File $toolPath -RepoRoot $RepoRoot -GhExecutable $fakeCommand -OutputPath $receiptPath 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { throw "Unsafe immutability state accepted: $mode" }
    $raw = Get-Content -LiteralPath $receiptPath -Raw
    $failure = $raw | ConvertFrom-Json
    $classification = if ($mode -eq 'immutable-invalid') { 'invalid-response' } else { 'release-policy-immutable' }
    if ($failure.failure.operation -cne 'release-immutability' -or $failure.failure.classification -cne $classification -or
        $raw.Contains($sentinelGh) -or $raw.Contains($sentinelGitHub)) { throw "Incorrect immutability rejection: $mode" }
  }
} finally {
  $env:GH_TOKEN = $originalGhToken
  $env:GITHUB_TOKEN = $originalGitHubToken
  $env:MIR_GH_ADMIN_TEST_MODE = $originalMode
  if (Test-Path -LiteralPath $scratch) {
    $resolvedScratch = (Resolve-Path -LiteralPath $scratch).Path
    $allowedRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build/results/github-administration-self-test/'))
    if (-not $resolvedScratch.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside this test staging root.' }
    Remove-Item -LiteralPath $resolvedScratch -Recurse -Force
  }
}

$global:LASTEXITCODE = 0
Write-Host "[ok] GitHub administration preflight is secret-safe, classifies HTTP failures and rejects enabled, owner-enforced or unrecognized release immutability."
