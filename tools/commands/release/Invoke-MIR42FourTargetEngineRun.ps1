# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [Parameter(Mandatory)][string]$CandidateManifestPath,
  [Parameter(Mandatory)][string]$F210Engine,
  [Parameter(Mandatory)][string]$F200Engine,
  [Parameter(Mandatory)][string]$F110Engine,
  [Parameter(Mandatory)][string]$F100Engine,
  [Parameter(Mandatory)][string]$F210Predecessor,
  [Parameter(Mandatory)][string]$F200Predecessor,
  [Parameter(Mandatory)][string]$F110Predecessor,
  [Parameter(Mandatory)][string]$F100Predecessor,
  [Parameter(Mandatory)][string]$OutputRoot,
  [ValidateRange(60,900)][int]$RowDeadlineSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')

function Assert-MIR42EngineRunFile {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Label)
  $resolved = [IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "[$Label-missing] $resolved" }
  return $resolved
}

function Get-MIR42EngineRunSha {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-MIR42EngineRunArchiveVersion {
  param([Parameter(Mandatory)][string]$Path)
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entries = @($archive.Entries | Where-Object { $_.FullName -match '^[^/]+/info[.]json$' })
    if ($entries.Count -ne 1) { throw '[mir42-engine-archive-info-entry]' }
    $reader = [IO.StreamReader]::new($entries[0].Open())
    try { $info = $reader.ReadToEnd() | ConvertFrom-Json -Depth 20 -DateKind String }
    finally { $reader.Dispose() }
    return [string]$info.version
  } finally { $archive.Dispose() }
}

function Invoke-MIR42BoundedUpgrade {
  param([Parameter(Mandatory)][string]$PowerShell,[Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$StdoutPath,[Parameter(Mandatory)][string]$StderrPath,
    [Parameter(Mandatory)][int]$DeadlineSeconds)
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = $PowerShell
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::Start($start)
  try {
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($DeadlineSeconds * 1000)
    if ($timedOut) {
      try { $process.Kill($true) } catch { $process.Kill() }
    }
    $process.WaitForExit()
    [IO.File]::WriteAllText($StdoutPath, $stdout.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($StderrPath, $stderr.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false))
    if ($timedOut) { throw "[mir42-engine-row-deadline] $DeadlineSeconds seconds; stderr=$StderrPath" }
    if ($process.ExitCode -ne 0) { throw "[mir42-engine-row-failed] exit=$($process.ExitCode); stderr=$StderrPath" }
    return $process.ExitCode
  } finally {
    $process.Dispose()
  }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$manifestPath = Assert-MIR42EngineRunFile -Path $CandidateManifestPath -Label 'mir42-candidate-manifest'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100 -DateKind String
$manifestSchema = Join-Path $repo 'spec/schemas/mir42-four-target-deterministic-candidate-manifest-v1.schema.json'
if (-not (Test-Path -LiteralPath $manifestSchema -PathType Leaf) -or
    -not ((Get-Content -Raw -LiteralPath $manifestPath) | Test-Json -SchemaFile $manifestSchema -ErrorAction SilentlyContinue)) {
  throw '[mir42-engine-candidate-manifest-schema]'
}
if ([int]$manifest.schema -ne 1 -or
    [string]$manifest.kind -cne 'MIR42FourTargetDeterministicCandidateManifestV1' -or
    [string]$manifest.status -cne 'private-deterministic-four-target-candidate-built-unqualified' -or
    -not [bool]$manifest.build_complete -or
    -not (Test-MIR4BootstrapRecordHash -Record $manifest)) {
  throw '[mir42-engine-candidate-manifest-invalid]'
}
$packageAuthority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
$packageSourceSha = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
if ([string]$manifest.package_authority_sha256 -cne [string]$packageAuthority.record_sha256 -or
    [string]$manifest.package_source_sha256 -cne $packageSourceSha) {
  throw '[mir42-engine-candidate-package-authority]'
}
$head = (& git -C $repo rev-parse HEAD).Trim()
$tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$dirty = @(& git -C $repo status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0 -or
    $head -cne [string]$manifest.source.commit -or $tree -cne [string]$manifest.source.tree) {
  throw '[mir42-engine-candidate-source-snapshot-mismatch]'
}
$candidateRoot = [IO.Path]::GetFullPath((Split-Path -Parent $manifestPath))
$out = [IO.Path]::GetFullPath($OutputRoot)
$buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
if (-not $out.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $out -PathType Leaf) -or
    ((Test-Path -LiteralPath $out -PathType Container) -and @(Get-ChildItem -LiteralPath $out -Force).Count -ne 0)) {
  throw '[mir42-engine-output-admission]'
}
$null = Assert-MIR4NoReparseAncestors -Root $repo -Path $out

$inputAuthorityRelative = '.mir/releases/waves/mir4-r0/MIR42-Direct-Predecessor-InputsV1.json'
$inputAuthorityPath = Assert-MIR42EngineRunFile -Path (Join-Path $repo $inputAuthorityRelative) -Label 'mir42-predecessor-authority'
$inputAuthority = Get-Content -Raw -LiteralPath $inputAuthorityPath | ConvertFrom-Json -Depth 100 -DateKind String
if (-not (Test-MIR4BootstrapRecordHash -Record $inputAuthority) -or
    [string]$inputAuthority.kind -cne 'MIR42DirectPredecessorInputsV1' -or
    [string]$inputAuthority.status -cne 'verified-published-v410-checksum-and-local-custody-private' -or
    [string]$inputAuthority.public_v410_checksums.tag -cne 'v4.1.0' -or
    [bool]$inputAuthority.release_transition_authority -or [bool]$inputAuthority.publication_authorized) {
  throw '[mir42-engine-predecessor-authority-invalid]'
}
$checksumRelative = [string]$inputAuthority.public_v410_checksums.path
if ($checksumRelative -cne '.mir/releases/waves/mir4-r0/MIR42-v410-SHA256SUMS.txt') {
  throw '[mir42-engine-published-checksum-path]'
}
$checksumPath = Assert-MIR42EngineRunFile -Path (Join-Path $repo $checksumRelative) -Label 'mir42-published-checksums'
if ((Get-MIR42EngineRunSha -Path $checksumPath) -cne [string]$inputAuthority.public_v410_checksums.sha256 -or
    [string](& git -C $repo rev-parse 'refs/tags/v4.1.0').Trim() -cne [string]$inputAuthority.public_v410_checksums.tag_object -or
    [string](& git -C $repo rev-parse 'refs/tags/v4.1.0^{}').Trim() -cne [string]$inputAuthority.public_v410_checksums.tagged_commit) {
  throw '[mir42-engine-published-v410-identity]'
}
$signatureText = (& git -C $repo verify-tag v4.1.0 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or -not $signatureText.Contains([string]$inputAuthority.public_v410_checksums.verified_tag_fingerprint)) {
  throw '[mir42-engine-published-v410-tag-signature]'
}
$publishedRelease = (& gh api 'repos/Julesc013/more-infinite-research/releases/tags/v4.1.0' | Out-String) | ConvertFrom-Json -Depth 30 -DateKind String
if ($LASTEXITCODE -ne 0 -or [string]$publishedRelease.tag_name -cne 'v4.1.0' -or [bool]$publishedRelease.draft) {
  throw '[mir42-engine-published-v410-release-metadata]'
}
$checksumAsset = @($publishedRelease.assets | Where-Object { [string]$_.name -ceq 'SHA256SUMS.txt' })
if ($checksumAsset.Count -ne 1 -or
    [int64]$checksumAsset[0].id -ne [int64]$inputAuthority.public_v410_checksums.release_asset_id -or
    [string]$checksumAsset[0].digest -cne ('sha256:' + [string]$inputAuthority.public_v410_checksums.sha256).ToLowerInvariant() -or
    [int64]$checksumAsset[0].size -ne [int64]$inputAuthority.public_v410_checksums.release_asset_bytes -or
    [string]$checksumAsset[0].state -cne 'uploaded') {
  throw '[mir42-engine-published-v410-checksum-asset]'
}
$assetCheckRoot = Join-Path $repo ('build/v410-public-checksum-verification-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $assetCheckRoot | Out-Null
try {
  $null = & gh release download v4.1.0 -R Julesc013/more-infinite-research -p SHA256SUMS.txt -D $assetCheckRoot
  if ($LASTEXITCODE -ne 0) { throw '[mir42-engine-published-v410-checksum-download]' }
  $downloadedChecksum = Assert-MIR42EngineRunFile -Path (Join-Path $assetCheckRoot 'SHA256SUMS.txt') -Label 'mir42-published-v410-checksum-download'
  if ((Get-MIR42EngineRunSha -Path $downloadedChecksum) -cne [string]$inputAuthority.public_v410_checksums.sha256 -or
      [int64](Get-Item -LiteralPath $downloadedChecksum).Length -ne [int64]$checksumAsset[0].size) {
    throw '[mir42-engine-published-v410-checksum-download-content]'
  }
} finally {
  Remove-Item -LiteralPath $assetCheckRoot -Recurse -Force
}

$selected = [ordered]@{
  f210 = [ordered]@{ engine=$F210Engine; predecessor=$F210Predecessor; from='4.1.21000'; to='4.2.21000'; fixture='assert-upgrade-4-0-21000-to-4-1-21000'; engine_major='2.1' }
  f200 = [ordered]@{ engine=$F200Engine; predecessor=$F200Predecessor; from='4.1.20000'; to='4.2.20000'; fixture='assert-upgrade-4-0-20000-to-4-1-20000'; engine_major='2.0' }
  f110 = [ordered]@{ engine=$F110Engine; predecessor=$F110Predecessor; from='4.1.11000'; to='4.2.11000'; fixture='assert-upgrade-4-0-11000-to-4-1-11000'; engine_major='1.1' }
  f100 = [ordered]@{ engine=$F100Engine; predecessor=$F100Predecessor; from='4.1.10000'; to='4.2.10000'; fixture='assert-upgrade-4-0-10000-to-4-1-10000'; engine_major='1.0' }
}
$targets = @('f210','f200','f110','f100')
$manifestTargets = @($manifest.targets | ForEach-Object { [string]$_.target })
if (($manifestTargets -join '|') -cne ($targets -join '|') -or
    (@($inputAuthority.targets | ForEach-Object { [string]$_.target }) -join '|') -cne ($targets -join '|')) {
  throw '[mir42-engine-candidate-target-set]'
}

# Admit every input before starting the first Factorio process.
foreach ($target in $targets) {
  $row = $selected[$target]
  $lock = @($inputAuthority.targets | Where-Object { [string]$_.target -ceq $target })[0]
  $row.engine = Assert-MIR42EngineRunFile -Path $row.engine -Label "mir42-$target-engine"
  $row.predecessor = Assert-MIR42EngineRunFile -Path $row.predecessor -Label "mir42-$target-predecessor"
  $row.engine_sha256 = Get-MIR42EngineRunSha -Path $row.engine
  $row.predecessor_sha256 = Get-MIR42EngineRunSha -Path $row.predecessor
  if (-not $row.engine.Equals([IO.Path]::GetFullPath([string]$lock.engine.path),[StringComparison]::OrdinalIgnoreCase) -or
      -not $row.predecessor.Equals([IO.Path]::GetFullPath([string]$lock.predecessor.path),[StringComparison]::OrdinalIgnoreCase) -or
      $row.engine_sha256 -cne [string]$lock.engine.sha256 -or
      $row.predecessor_sha256 -cne [string]$lock.predecessor.sha256 -or
      [int64](Get-Item -LiteralPath $row.predecessor).Length -ne [int64]$lock.predecessor.bytes -or
      [string]$lock.predecessor.version -cne $row.from -or
      [string]$lock.published_checksum_sha256 -cne $row.predecessor_sha256 -or
      -not (Get-Content -LiteralPath $checksumPath | Where-Object { $_ -ceq "$($row.predecessor_sha256)  $([IO.Path]::GetFileName($row.predecessor))" })) {
    throw "[mir42-$target-input-lock]"
  }
  if ((Get-MIR42EngineRunArchiveVersion -Path $row.predecessor) -cne $row.from) {
    throw "[mir42-$target-predecessor-version]"
  }
  $row.engine_version = [string](Get-Item -LiteralPath $row.engine).VersionInfo.FileVersion
  $productVersion = [string](Get-Item -LiteralPath $row.engine).VersionInfo.ProductVersion
  if (-not $productVersion.StartsWith($row.engine_major + '.', [StringComparison]::Ordinal) -or
      $productVersion -cne [string]$lock.engine.product_version -or
      $row.engine_version -cne [string]$lock.engine.file_version) {
    throw "[mir42-$target-engine-version] $productVersion"
  }
  $candidate = @($manifest.targets | Where-Object { [string]$_.target -ceq $target })[0]
  $targetRowPath = Assert-MIR42EngineRunFile -Path (Join-Path $candidateRoot ([string]$candidate.target_row_path)) -Label "mir42-$target-builder-row"
  $targetRow = Get-Content -Raw -LiteralPath $targetRowPath | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $targetRow) -or
      [string]$targetRow.target -cne $target -or
      [string]$targetRow.asset.sha256 -cne [string]$candidate.asset.sha256 -or
      [string]$targetRow.build_a_sha256 -cne [string]$candidate.asset.sha256 -or
      [string]$targetRow.build_b_sha256 -cne [string]$candidate.asset.sha256 -or
      -not [bool]$targetRow.deterministic_archive_bytes) {
    throw "[mir42-$target-builder-row-binding]"
  }
  if ([string]$candidate.distribution_version -cne $row.to) { throw "[mir42-$target-candidate-version]" }
  $assetRelative = [string]$candidate.asset.path
  if ([IO.Path]::IsPathRooted($assetRelative) -or $assetRelative -match '(^|[\\/])[.][.]([\\/]|$)') {
    throw "[mir42-$target-candidate-asset-path]"
  }
  $row.candidate = Assert-MIR42EngineRunFile -Path (Join-Path $candidateRoot $assetRelative) -Label "mir42-$target-candidate"
  if (-not $row.candidate.StartsWith($candidateRoot.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
      (Get-MIR42EngineRunSha -Path $row.candidate) -cne [string]$candidate.asset.sha256) {
    throw "[mir42-$target-candidate-asset-hash]"
  }
  if ((Get-MIR42EngineRunArchiveVersion -Path $row.candidate) -cne $row.to) {
    throw "[mir42-$target-candidate-archive-version]"
  }
  $inventory = Get-MIR4ArchiveInventory -Path $row.candidate
  if ([string]$inventory.content_sha256 -cne [string]$candidate.content_sha256 -or
      [int]$inventory.entry_count -ne [int]$candidate.entry_count) {
    throw "[mir42-$target-candidate-content]"
  }
  $row.candidate_sha256 = [string]$candidate.asset.sha256
}
$pwsh = Assert-MIR42EngineRunFile -Path (Get-Command pwsh).Source -Label 'mir42-pwsh'
$harness = Assert-MIR42EngineRunFile -Path (Join-Path $repo 'tests/runtime/Test-MIRUpgrade.ps1') -Label 'mir42-upgrade-harness'
$runner = Assert-MIR42EngineRunFile -Path $PSCommandPath -Label 'mir42-engine-runner'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$candidateLocks = [Collections.Generic.List[IDisposable]]::new()
foreach ($target in $targets) {
  $row = $selected[$target]
  $staged = Join-Path $out "staged-assets/$target/$([IO.Path]::GetFileName($row.candidate))"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $staged) | Out-Null
  Copy-Item -LiteralPath $row.candidate -Destination $staged
  if ((Get-MIR42EngineRunSha -Path $staged) -cne $row.candidate_sha256) { throw "[mir42-$target-staged-candidate-hash]" }
  $row.candidate = $staged
  $candidateLocks.Add([IO.File]::Open($staged,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))
}
$results = [Collections.Generic.List[object]]::new()
$processTotal = 0
foreach ($target in $targets) {
  $row = $selected[$target]
  $rowRoot = Join-Path $out $target
  New-Item -ItemType Directory -Force -Path $rowRoot | Out-Null
  $freshLoads = @(
    foreach ($scenario in $(if ($target -eq 'f210') { @('package-zip-base','package-zip-space-age') } else { @('package-zip-base') })) {
      $freshRoot = Join-Path $rowRoot "fresh-$scenario"
      New-Item -ItemType Directory -Force -Path $freshRoot | Out-Null
      $summaryPath = Join-Path $freshRoot 'summary.json'
      $freshStdout = Join-Path $freshRoot 'stdout.txt'
      $freshStderr = Join-Path $freshRoot 'stderr.txt'
      $freshArgs = @('-NoProfile','-File',(Join-Path $repo 'scripts/Invoke-MIRValidation.ps1'),
        '-ScenarioWorker','-Scenario',$scenario,'-FactorioBin',$row.engine,
        '-UserDataDir',(Join-Path $freshRoot 'work'),'-CandidateZip',$row.candidate,
        '-MaxParallel','1','-ValidationSummaryPath',$summaryPath)
      if ((Get-MIR42EngineRunSha -Path $row.engine) -cne $row.engine_sha256) {
        throw "[mir42-$target-$scenario-engine-drift-before]"
      }
      if ((Get-MIR42EngineRunSha -Path $row.candidate) -cne $row.candidate_sha256) {
        throw "[mir42-$target-$scenario-staged-candidate-drift-before]"
      }
      $null = Invoke-MIR42BoundedUpgrade -PowerShell $pwsh -Arguments $freshArgs -StdoutPath $freshStdout -StderrPath $freshStderr -DeadlineSeconds $RowDeadlineSeconds

      if ((Get-MIR42EngineRunSha -Path $row.engine) -cne $row.engine_sha256) {
        throw "[mir42-$target-$scenario-engine-drift-after]"
      }
      if ((Get-MIR42EngineRunSha -Path $row.candidate) -cne $row.candidate_sha256) {
        throw "[mir42-$target-$scenario-staged-candidate-drift-after]"
      }
      $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json -Depth 100 -DateKind String
      $candidateRow = @($manifest.targets | Where-Object { [string]$_.target -ceq $target })[0]
      if ([string]$summary.status -cne 'passed' -or [string]$summary.git_commit -cne $head -or
          [string]$summary.validation_package_sha256 -cne [string]$candidateRow.asset.sha256 -or
          [string]$summary.validation_package_content_sha256 -cne [string]$candidateRow.content_sha256 -or
          @($summary.expected_scenarios).Count -ne 1 -or [string]$summary.expected_scenarios[0] -cne $scenario -or
          @($summary.scenarios).Count -ne 1 -or [string]$summary.scenarios[0].status -cne 'passed') {
        throw "[mir42-$target-$scenario-fresh-summary-binding]"
      }
      $logPath = Assert-MIR42EngineRunFile -Path (Join-Path $freshRoot 'work/factorio-current.log') -Label "mir42-$target-$scenario-fresh-log"
      $logText = Get-Content -Raw -LiteralPath $logPath
      if (-not $logText.Contains("Loading mod more-infinite-research $($row.to)") -or
          -not $logText.Contains('Factorio initialised') -or -not $logText.Contains('Creating new map')) {
        throw "[mir42-$target-$scenario-fresh-log-content]"
      }
      $processTotal++
      [pscustomobject][ordered]@{
        scenario=$scenario
        receipt=[pscustomobject][ordered]@{path=$summaryPath;sha256=(Get-MIR42EngineRunSha -Path $summaryPath)}
        log=[pscustomobject][ordered]@{path=$logPath;sha256=(Get-MIR42EngineRunSha -Path $logPath)}
        stdout=[pscustomobject][ordered]@{path=$freshStdout;sha256=(Get-MIR42EngineRunSha -Path $freshStdout)}
        stderr=[pscustomobject][ordered]@{path=$freshStderr;sha256=(Get-MIR42EngineRunSha -Path $freshStderr)}
      }
    }
  )
  $receiptPath = Join-Path $rowRoot 'upgrade.json'
  $stdoutPath = Join-Path $rowRoot 'harness-stdout.txt'
  $stderrPath = Join-Path $rowRoot 'harness-stderr.txt'
  $args = @('-NoProfile','-File',$harness,'-RepoRoot',$repo,'-FactorioBin',$row.engine,
    '-FromZip',$row.predecessor,'-ToZip',$row.candidate,'-FromVersion',$row.from,'-ToVersion',$row.to,
    '-FixtureName',$row.fixture,'-Archetype','base-default','-OutputPath',$receiptPath,
    '-WorkRoot',(Join-Path $rowRoot 'work'),'-Retention','OnFailure')
  if ((Get-MIR42EngineRunSha -Path $row.candidate) -cne $row.candidate_sha256) { throw "[mir42-$target-staged-candidate-drift-before-upgrade]" }
  if ((Get-MIR42EngineRunSha -Path $row.engine) -cne $row.engine_sha256) { throw "[mir42-$target-engine-drift-before-upgrade]" }
  $exitCode = Invoke-MIR42BoundedUpgrade -PowerShell $pwsh -Arguments $args -StdoutPath $stdoutPath -StderrPath $stderrPath -DeadlineSeconds $RowDeadlineSeconds
  if ((Get-MIR42EngineRunSha -Path $row.engine) -cne $row.engine_sha256) { throw "[mir42-$target-engine-drift-after-upgrade]" }
  if ((Get-MIR42EngineRunSha -Path $row.candidate) -cne $row.candidate_sha256) { throw "[mir42-$target-staged-candidate-drift-after-upgrade]" }
  $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 50 -DateKind String
  $missingAssertions = @(@('exact-candidate-normal-mod-directory-load','upgraded-save-reload-passed','upgraded-save-second-reload-passed') |
    Where-Object { $_ -cnotin @($receipt.assertions) })
  if ([string]$receipt.status -cne 'passed' -or [string]$receipt.git_commit -cne $head -or
      [string]$receipt.factorio_binary_sha256 -cne $row.engine_sha256 -or
      [string]$receipt.from.sha256 -cne $row.predecessor_sha256 -or
      [string]$receipt.to.sha256 -cne $row.candidate_sha256 -or
      [int]$receipt.factorio_processes -lt 4 -or
      $missingAssertions.Count -ne 0) {
    throw "[mir42-$target-upgrade-receipt-binding]"
  }
  $logs = @(
    foreach ($phase in @('create','load','reload','second-reload')) {
      $field = if ($phase -eq 'second-reload') { 'second_reload' } else { $phase }
      $logName = [string]$receipt."${field}_log"
      if ($logName -cne [IO.Path]::GetFileName($logName)) { throw "[mir42-$target-$phase-log-path]" }
      $path = Assert-MIR42EngineRunFile -Path (Join-Path $rowRoot $logName) -Label "mir42-$target-$phase-log"
      $sha = Get-MIR42EngineRunSha -Path $path
      if ($sha -cne [string]$receipt."${field}_log_sha256") { throw "[mir42-$target-$phase-log-hash]" }
      [pscustomobject][ordered]@{phase=$phase;path=$path;sha256=$sha}
    }
  )
  $processTotal += [int]$receipt.factorio_processes
  $results.Add([pscustomobject][ordered]@{
    target=$target
    status='passed'
    archive=[pscustomobject][ordered]@{path=$row.candidate;sha256=(Get-MIR42EngineRunSha -Path $row.candidate)}
    engine_execution=[pscustomobject][ordered]@{
      executable_path=$row.engine;executable_sha256=$row.engine_sha256;version=$row.engine_version
      predecessor=[pscustomobject][ordered]@{path=$row.predecessor;sha256=$row.predecessor_sha256;version=$row.from}
      fresh_loads=$freshLoads
      harness_receipt=[pscustomobject][ordered]@{path=$receiptPath;sha256=(Get-MIR42EngineRunSha -Path $receiptPath)}
      harness_exit_code=$exitCode;logs=$logs;fresh_exact_load=$true;predecessor_upgrade=$true;reload_count=2
    }
  })
  Write-Host "[ok] $target engine upgrade and two reloads: $receiptPath"
}
$record = [ordered]@{
  schema=1;kind='MIR42FourTargetEngineRunV1';status='four-target-base-default-real-engine-probes-passed-private-unqualified'
  source=[ordered]@{commit=$head;tree=$tree}
  candidate_manifest=[ordered]@{path=$manifestPath;sha256=(Get-MIR42EngineRunSha -Path $manifestPath);record_sha256=[string]$manifest.record_sha256}
  predecessor_authority=[ordered]@{path=$inputAuthorityPath;sha256=(Get-MIR42EngineRunSha -Path $inputAuthorityPath);record_sha256=[string]$inputAuthority.record_sha256}
  public_v410_checksum_asset=[ordered]@{release_id=[int64]$publishedRelease.id;asset_id=[int64]$checksumAsset[0].id;digest=[string]$checksumAsset[0].digest;bytes=[int64]$checksumAsset[0].size;download_verified=$true}
  runner=[ordered]@{path=$runner;sha256=(Get-MIR42EngineRunSha -Path $runner)}
  harness=[ordered]@{path=$harness;sha256=(Get-MIR42EngineRunSha -Path $harness)}
  targets=@($results.ToArray())
  factorio_processes=$processTotal
  release_qualification='not-performed'
  publication_authorized=$false
}
$recordPath = Join-Path $out 'engine-run.json'
$null = Write-MIR4BootstrapRecord -Record $record -Path $recordPath
foreach ($lock in $candidateLocks) { $lock.Dispose() }
Write-Host "[ok] private four-target engine run: $recordPath"
