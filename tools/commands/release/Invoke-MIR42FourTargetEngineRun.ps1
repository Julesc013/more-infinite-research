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
if ([int]$manifest.schema -ne 1 -or
    [string]$manifest.kind -cnotin @('MIR42FourTargetDeterministicCandidateManifestV1','MIR42FourTargetCandidateManifestV1') -or
    [string]$manifest.status -cne 'private-deterministic-four-target-candidate-built-unqualified' -or
    -not [bool]$manifest.build_complete -or
    -not (Test-MIR4BootstrapRecordHash -Record $manifest)) {
  throw '[mir42-engine-candidate-manifest-invalid]'
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

$selected = [ordered]@{
  f210 = [ordered]@{ engine=$F210Engine; predecessor=$F210Predecessor; from='4.1.21000'; to='4.2.21000'; fixture='assert-upgrade-4-0-21000-to-4-1-21000'; engine_major='2.1' }
  f200 = [ordered]@{ engine=$F200Engine; predecessor=$F200Predecessor; from='4.0.20000'; to='4.2.20000'; fixture='assert-upgrade-4-0-20000-to-4-1-20000'; engine_major='2.0' }
  f110 = [ordered]@{ engine=$F110Engine; predecessor=$F110Predecessor; from='4.1.11000'; to='4.2.11000'; fixture='assert-upgrade-4-0-11000-to-4-1-11000'; engine_major='1.1' }
  f100 = [ordered]@{ engine=$F100Engine; predecessor=$F100Predecessor; from='4.1.10000'; to='4.2.10000'; fixture='assert-upgrade-4-0-10000-to-4-1-10000'; engine_major='1.0' }
}
$targets = @('f210','f200','f110','f100')
$manifestTargets = @($manifest.targets | ForEach-Object { [string]$_.target })
if (($manifestTargets -join '|') -cne ($targets -join '|')) { throw '[mir42-engine-candidate-target-set]' }

# Admit every input before starting the first Factorio process.
foreach ($target in $targets) {
  $row = $selected[$target]
  $row.engine = Assert-MIR42EngineRunFile -Path $row.engine -Label "mir42-$target-engine"
  $row.predecessor = Assert-MIR42EngineRunFile -Path $row.predecessor -Label "mir42-$target-predecessor"
  $row.engine_sha256 = Get-MIR42EngineRunSha -Path $row.engine
  $row.predecessor_sha256 = Get-MIR42EngineRunSha -Path $row.predecessor
  if ((Get-MIR42EngineRunArchiveVersion -Path $row.predecessor) -cne $row.from) {
    throw "[mir42-$target-predecessor-version]"
  }
  $row.engine_version = [string](Get-Item -LiteralPath $row.engine).VersionInfo.FileVersion
  $productVersion = [string](Get-Item -LiteralPath $row.engine).VersionInfo.ProductVersion
  if (-not $productVersion.StartsWith($row.engine_major + '.', [StringComparison]::Ordinal)) {
    throw "[mir42-$target-engine-version] $productVersion"
  }
  $candidate = @($manifest.targets | Where-Object { [string]$_.target -ceq $target })[0]
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
}
$pwsh = Assert-MIR42EngineRunFile -Path (Get-Command pwsh).Source -Label 'mir42-pwsh'
$harness = Assert-MIR42EngineRunFile -Path (Join-Path $repo 'tests/runtime/Test-MIRUpgrade.ps1') -Label 'mir42-upgrade-harness'
$runner = Assert-MIR42EngineRunFile -Path $PSCommandPath -Label 'mir42-engine-runner'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$results = [Collections.Generic.List[object]]::new()
$processTotal = 0
foreach ($target in $targets) {
  $row = $selected[$target]
  $rowRoot = Join-Path $out $target
  New-Item -ItemType Directory -Force -Path $rowRoot | Out-Null
  $receiptPath = Join-Path $rowRoot 'upgrade.json'
  $stdoutPath = Join-Path $rowRoot 'harness-stdout.txt'
  $stderrPath = Join-Path $rowRoot 'harness-stderr.txt'
  $args = @('-NoProfile','-File',$harness,'-RepoRoot',$repo,'-FactorioBin',$row.engine,
    '-FromZip',$row.predecessor,'-ToZip',$row.candidate,'-FromVersion',$row.from,'-ToVersion',$row.to,
    '-FixtureName',$row.fixture,'-Archetype','base-default','-OutputPath',$receiptPath,
    '-WorkRoot',(Join-Path $rowRoot 'work'),'-Retention','OnFailure')
  $exitCode = Invoke-MIR42BoundedUpgrade -PowerShell $pwsh -Arguments $args -StdoutPath $stdoutPath -StderrPath $stderrPath -DeadlineSeconds $RowDeadlineSeconds
  $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 50 -DateKind String
  $missingAssertions = @(@('exact-candidate-normal-mod-directory-load','upgraded-save-reload-passed','upgraded-save-second-reload-passed') |
    Where-Object { $_ -cnotin @($receipt.assertions) })
  if ([string]$receipt.status -cne 'passed' -or [string]$receipt.git_commit -cne $head -or
      [string]$receipt.factorio_binary_sha256 -cne $row.engine_sha256 -or
      [string]$receipt.from.sha256 -cne $row.predecessor_sha256 -or
      [string]$receipt.to.sha256 -cne (Get-MIR42EngineRunSha -Path $row.candidate) -or
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
  runner=[ordered]@{path=$runner;sha256=(Get-MIR42EngineRunSha -Path $runner)}
  harness=[ordered]@{path=$harness;sha256=(Get-MIR42EngineRunSha -Path $harness)}
  targets=@($results.ToArray())
  factorio_processes=$processTotal
  release_qualification='not-performed'
  publication_authorized=$false
}
$recordPath = Join-Path $out 'engine-run.json'
$null = Write-MIR4BootstrapRecord -Record $record -Path $recordPath
Write-Host "[ok] private four-target engine run: $recordPath"
