# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = "")
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $MirLegacyScriptRoot "..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$fixtureRoot = Join-Path $tempRoot ("mir-artifact-cleanup-{0}" -f [guid]::NewGuid().ToString("N"))
$cleanupScript = Join-Path $RepoRoot "tools\commands\workspace\Remove-MIRStaleArtifacts.ps1"
$activeLeaseLock = $null
$gitEnvironmentNames = @(
  "GIT_INDEX_FILE", "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR",
  "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"
)
$savedGitEnvironment = @{}
foreach ($name in $gitEnvironmentNames) {
  $item = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
  if ($null -ne $item) {
    $savedGitEnvironment[$name] = [string]$item.Value
    Remove-Item -LiteralPath "Env:$name"
  }
}

try {
  New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
  & git -C $fixtureRoot init --quiet
  if ($LASTEXITCODE -ne 0) { throw "Unable to initialize artifact-cleanup fixture repository." }
  "/build/" | Set-Content -LiteralPath (Join-Path $fixtureRoot ".gitignore") -Encoding UTF8

  $artifactRoot = Join-Path $fixtureRoot "build/results"
  $testRoot = Join-Path $fixtureRoot "build/tests"
  $packageRoot = Join-Path $fixtureRoot "build/packages"
  $protectedAssurance = Join-Path $artifactRoot "assurance"
  $protectedValidation = Join-Path $artifactRoot "validation"
  $staleRun = Join-Path $artifactRoot "stale-run"
  $recentRun = Join-Path $artifactRoot "recent-run"
  $staleTestRun = Join-Path $testRoot "series/stale-run"
  $changingTestRun = Join-Path $testRoot "series/changing-run"
  $pinnedTestRun = Join-Path $testRoot "series/pinned-run"
  $activeLeaseRun = Join-Path $testRoot "series/active-lease-run"
  $receiptCapturedLeaseRun = Join-Path $testRoot "series/receipt-captured-crash-run"
  $failedLeaseRun = Join-Path $testRoot "series/interrupted-lease-run"
  $orphanLeaseRun = Join-Path $testRoot "series/orphan-lease-run"
  $stalePackage = Join-Path $packageRoot "stale-package"
  $pinnedPackage = Join-Path $packageRoot "pinned-package"
  $developmentContracts = Join-Path $packageRoot 'development-contracts'
  $staleDevelopmentContract = Join-Path $developmentContracts '11111111111111111111111111111111'
  $recentDevelopmentContract = Join-Path $developmentContracts '22222222222222222222222222222222'
  $referencedDevelopmentContract = Join-Path $developmentContracts '33333333333333333333333333333333'
  foreach ($path in @($protectedAssurance, $protectedValidation, $staleRun, $recentRun, $staleTestRun, $changingTestRun, $pinnedTestRun, $activeLeaseRun, $receiptCapturedLeaseRun, $failedLeaseRun, $orphanLeaseRun, $stalePackage, $pinnedPackage, $staleDevelopmentContract, $recentDevelopmentContract, $referencedDevelopmentContract)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    "fixture" | Set-Content -LiteralPath (Join-Path $path "result.txt") -Encoding UTF8
  }
  "[path]`n" | Set-Content -LiteralPath (Join-Path $staleTestRun "config.ini") -Encoding UTF8
  "[path]`n" | Set-Content -LiteralPath (Join-Path $changingTestRun "config.ini") -Encoding UTF8
  "pinned evidence" | Set-Content -LiteralPath (Join-Path $pinnedTestRun "result.json") -Encoding UTF8
  "candidate" | Set-Content -LiteralPath (Join-Path $stalePackage "candidate.zip") -Encoding UTF8
  "pinned candidate" | Set-Content -LiteralPath (Join-Path $pinnedPackage "candidate-pin.json") -Encoding UTF8
  "{}" | Set-Content -LiteralPath (Join-Path $staleDevelopmentContract 'receipt.json') -Encoding UTF8
  "{}" | Set-Content -LiteralPath (Join-Path $referencedDevelopmentContract 'receipt.json') -Encoding UTF8
  'build/packages/development-contracts/33333333333333333333333333333333' | Set-Content -LiteralPath (Join-Path $fixtureRoot 'tracked-reference.txt') -Encoding UTF8
  & git -C $fixtureRoot add -- .gitignore tracked-reference.txt
  if ($LASTEXITCODE -ne 0) { throw 'Unable to establish tracked-reference fixture.' }
  $leaseRecord = [ordered]@{schema=1;kind='MIRImmutableInputLeaseV1';lease_id='fixture';owner_pid=$PID;state='active'}
  ($leaseRecord | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $activeLeaseRun 'mir-immutable-input-lease.json') -Encoding UTF8
  $failedLeaseRecord = [ordered]@{schema=1;kind='MIRImmutableInputLeaseV1';lease_id='fixture-failed';owner_pid=2147483647;state='staging-failed'}
  ($failedLeaseRecord | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $failedLeaseRun 'mir-immutable-input-lease.json') -Encoding UTF8
  $receiptCapturedLeaseRecord = [ordered]@{schema=1;kind='MIRImmutableInputLeaseV1';lease_id='fixture-receipt-captured';owner_pid=2147483647;state='receipt-captured'}
  ($receiptCapturedLeaseRecord | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $receiptCapturedLeaseRun 'mir-immutable-input-lease.json') -Encoding UTF8
  $orphanLeaseLock = [IO.File]::Open((Join-Path $orphanLeaseRun 'mir-immutable-input-lease.lock'), [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  $orphanLeaseLock.Dispose()

  $staleTimestamp = [DateTime]::UtcNow.AddDays(-10)
  foreach ($stalePath in @($staleRun, $staleTestRun, $changingTestRun, $pinnedTestRun, $activeLeaseRun, $receiptCapturedLeaseRun, $failedLeaseRun, $orphanLeaseRun, $stalePackage, $pinnedPackage, $staleDevelopmentContract, $referencedDevelopmentContract)) {
    Get-ChildItem -LiteralPath $stalePath -Force -Recurse | ForEach-Object { $_.LastWriteTimeUtc = $staleTimestamp }
    (Get-Item -LiteralPath $stalePath).LastWriteTimeUtc = $staleTimestamp
  }
  foreach ($protectedPath in @($protectedAssurance, $protectedValidation)) {
    Get-ChildItem -LiteralPath $protectedPath -Force -Recurse | ForEach-Object { $_.LastWriteTimeUtc = $staleTimestamp }
    (Get-Item -LiteralPath $protectedPath).LastWriteTimeUtc = $staleTimestamp
  }
  $activeLeaseLock = [IO.File]::Open((Join-Path $activeLeaseRun 'mir-immutable-input-lease.lock'), [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)

  $reparseTarget = Join-Path $fixtureRoot 'reparse-target'
  $reparseRun = Join-Path $artifactRoot 'reparse-run'
  New-Item -ItemType Directory -Path $reparseTarget -Force | Out-Null
  "outside" | Set-Content -LiteralPath (Join-Path $reparseTarget 'outside.txt') -Encoding UTF8
  New-Item -ItemType Junction -Path $reparseRun -Target $reparseTarget | Out-Null

  $planBoundCaught = $false
  try { & $cleanupScript -RepoRoot $fixtureRoot -OlderThanDays 7 -MaxPlanEntries 1 -PassThru | Out-Null } catch { $planBoundCaught = $_.Exception.Message -match 'bounded 1-entry limit' }
  if (-not $planBoundCaught) { throw 'Cleanup did not stop before removal when its bounded plan limit was exceeded.' }

  $preview = @(& $cleanupScript -RepoRoot $fixtureRoot -OlderThanDays 7 -PassThru)
  if (-not (Test-Path -LiteralPath $staleRun)) { throw "Dry-run cleanup removed a stale artifact." }
  if (@($preview | Where-Object { $_.relative_path -ceq 'build/results/stale-run' -and $_.status -eq "eligible" }).Count -ne 1) {
    throw "Dry-run cleanup did not identify the stale artifact exactly once."
  }
  foreach ($protectedName in @("assurance", "validation")) {
    if (@($preview | Where-Object { $_.item -eq $protectedName -and $_.status -eq "protected" }).Count -ne 1) {
      throw "Cleanup did not protect build/results/$protectedName."
    }
  }
  foreach ($expected in @(
    @{path='build/tests/series/stale-run';status='eligible'},
    @{path='build/packages/stale-package';status='eligible'},
    @{path='build/tests/series/pinned-run';status='pinned-custody'},
    @{path='build/packages/pinned-package';status='pinned-custody'},
    @{path='build/tests/series/active-lease-run';status='active-lease'},
    @{path='build/tests/series/receipt-captured-crash-run';status='interrupted-lease'},
    @{path='build/tests/series/interrupted-lease-run';status='interrupted-lease'},
    @{path='build/tests/series/orphan-lease-run';status='interrupted-lease'},
    @{path='build/packages/development-contracts/11111111111111111111111111111111';status='eligible'},
    @{path='build/packages/development-contracts/22222222222222222222222222222222';status='recent'},
    @{path='build/packages/development-contracts/33333333333333333333333333333333';status='pinned-reference'},
    @{path='build/results/reparse-run';status='unsafe-reparse'}
  )) {
    if (@($preview | Where-Object { $_.relative_path -ceq $expected.path -and $_.status -ceq $expected.status }).Count -ne 1) {
      throw "Cleanup did not classify $($expected.path) as $($expected.status)."
    }
  }

  $resultOnlyPreview = @(& $cleanupScript -RepoRoot $fixtureRoot -OlderThanDays 7 -ArtifactType result -PassThru)
  if ($resultOnlyPreview.Count -eq 0 -or @($resultOnlyPreview | Where-Object { $_.artifact_type -cne 'result' }).Count -ne 0) {
    throw 'Typed cleanup selection did not remain bounded to build/results.'
  }
  if (@($resultOnlyPreview | Where-Object { $_.relative_path -ceq 'build/results/stale-run' -and $_.status -ceq 'eligible' }).Count -ne 1) {
    throw 'Typed cleanup selection did not retain result-root classification.'
  }

  $selectedPreview = @(& $cleanupScript -RepoRoot $fixtureRoot -OlderThanDays 7 -ArtifactType result,package -PassThru)
  if (@($selectedPreview | Where-Object { $_.artifact_type -ceq 'test' }).Count -ne 0 -or
      @($selectedPreview | Where-Object { $_.artifact_type -ceq 'result' }).Count -eq 0 -or
      @($selectedPreview | Where-Object { $_.artifact_type -ceq 'package' }).Count -eq 0) {
    throw 'Multi-type cleanup selection did not include exactly the requested typed roots.'
  }

  "new write before apply" | Set-Content -LiteralPath (Join-Path $changingTestRun 'result.txt') -Encoding UTF8
  (Get-Item -LiteralPath $changingTestRun).LastWriteTimeUtc = [DateTime]::UtcNow

  $applied = @(& $cleanupScript -RepoRoot $fixtureRoot -OlderThanDays 7 -Apply -PassThru -SkipActiveProcessCheck -Confirm:$false)
  if (Test-Path -LiteralPath $staleRun) { throw "Applied cleanup retained the stale artifact." }
  if ((Test-Path -LiteralPath $staleTestRun) -or (Test-Path -LiteralPath $stalePackage) -or (Test-Path -LiteralPath $staleDevelopmentContract)) { throw 'Applied cleanup retained an eligible typed-root artifact.' }
  if (-not (Test-Path -LiteralPath $recentRun)) { throw "Applied cleanup removed a recent artifact." }
  if (-not (Test-Path -LiteralPath $changingTestRun)) { throw 'Applied cleanup removed an artifact that received a write before apply.' }
  foreach ($retained in @($pinnedTestRun, $pinnedPackage, $activeLeaseRun, $receiptCapturedLeaseRun, $failedLeaseRun, $orphanLeaseRun, $reparseRun, $recentDevelopmentContract, $referencedDevelopmentContract)) {
    if (-not (Test-Path -LiteralPath $retained)) { throw "Applied cleanup removed protected or unsafe state: $retained" }
  }
  if (-not (Test-Path -LiteralPath $protectedAssurance) -or -not (Test-Path -LiteralPath $protectedValidation)) {
    throw "Applied cleanup removed a protected artifact root."
  }
  if (@($applied | Where-Object { $_.relative_path -ceq 'build/results/stale-run' -and $_.status -eq "deleted" }).Count -ne 1) {
    throw "Applied cleanup did not report the stale artifact as deleted."
  }
  foreach ($path in @('build/tests/series/stale-run', 'build/packages/stale-package', 'build/packages/development-contracts/11111111111111111111111111111111')) {
    if (@($applied | Where-Object { $_.relative_path -ceq $path -and $_.status -ceq 'deleted' }).Count -ne 1) {
      throw "Apply did not preserve dry-run eligibility for $path."
    }
  }
  if (@($applied | Where-Object { $_.relative_path -ceq 'build/tests/series/changing-run' -and $_.status -eq 'deleted' }).Count -ne 0) {
    throw 'Apply deleted a target with a newer write.'
  }
  $secondApply = @(& $cleanupScript -RepoRoot $fixtureRoot -OlderThanDays 7 -Apply -PassThru -SkipActiveProcessCheck -Confirm:$false)
  if (@($secondApply | Where-Object { $_.status -eq 'deleted' }).Count -ne 0) {
    throw 'A repeated cleanup was not idempotent after exact stale targets were removed.'
  }
} finally {
  if ($null -ne $activeLeaseLock) { $activeLeaseLock.Dispose() }
  if (Test-Path -LiteralPath $fixtureRoot) {
    $resolvedFixture = [System.IO.Path]::GetFullPath($fixtureRoot)
    $tempPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedFixture.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Artifact-cleanup fixture escaped the system temp directory: $resolvedFixture"
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
  }
  foreach ($name in $gitEnvironmentNames) {
    if ($savedGitEnvironment.ContainsKey($name)) { Set-Item -LiteralPath "Env:$name" -Value $savedGitEnvironment[$name] }
    else { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
  }
}

Write-Host '[ok] artifact cleanup is dry-run-first, typed-root-only, no-follow, lease-aware, custody-preserving, and re-audits before deletion.'
