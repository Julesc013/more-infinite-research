# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot 'tools/lib/validation/ImmutableInputStaging.ps1')

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
$fixtureRoot = Join-Path $tempRoot ("mir-immutable-input-staging-{0}" -f [guid]::NewGuid().ToString('N'))
$firstLease = $null
$secondLease = $null
try {
  New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
  $sourceRoot = Join-Path $fixtureRoot 'verified-inputs'
  $runOne = Join-Path $fixtureRoot 'run-one'
  $runTwo = Join-Path $fixtureRoot 'run-two'
  New-Item -ItemType Directory -Force -Path $sourceRoot, $runOne, $runTwo | Out-Null
  $sourceOne = Join-Path $sourceRoot 'candidate.zip'
  $sourceTwo = Join-Path $sourceRoot 'bobplates_2.1.1.zip'
  [IO.File]::WriteAllText($sourceOne, 'candidate bytes', [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($sourceTwo, 'mod bytes', [Text.UTF8Encoding]::new($false))
  $hashOne = Get-MIRImmutableInputSha256 -Path $sourceOne
  $hashTwo = Get-MIRImmutableInputSha256 -Path $sourceTwo

  $firstLease = New-MIRImmutableInputLease -RunRoot $runOne -StageDirectory (Join-Path $runOne 'mods') -Inputs @(
    [ordered]@{
      source_path = $sourceOne
      file_name = 'more-infinite-research_4.2.21000.zip'
      expected_sha256 = $hashOne
      role = 'candidate'
      identity = [ordered]@{ target = 'f210'; materializer = 'TargetMaterializer'; sha256 = $hashOne }
      provenance = [ordered]@{ kind = 'fresh-materializer-output'; source = 'fixture' }
      immutable = $true
    },
    [ordered]@{
      source_path = $sourceTwo
      file_name = 'bobplates_2.1.1.zip'
      expected_sha256 = $hashTwo
      role = 'dependency-mod'
      identity = [ordered]@{ name = 'bobplates'; version = '2.1.1'; sha256 = $hashTwo }
      provenance = [ordered]@{ kind = 'verified-mod-archive'; source = 'fixture' }
      immutable = $true
    }
  )
  if ((Get-MIRImmutableInputLeaseLiveness -RunRoot $runOne).active -ne $true) {
    throw 'Immutable input lease did not present as live while its lock was held.'
  }
  if (@($firstLease.record.inputs | Where-Object { $_.staging_mode -ne 'hardlink' }).Count -ne 0) {
    throw 'Same-volume verified inputs did not use a proven hard-link mode.'
  }
  foreach ($input in @($firstLease.record.inputs)) {
    if ($input.hardlink_file_identity.verified -ne $true -or
        $input.hardlink_file_identity.source -cne $input.hardlink_file_identity.staged) {
      throw 'Hard-link staging did not record equal native file identities.'
    }
  }
  $writeBlocked = $false
  try {
    [IO.File]::WriteAllText((Join-Path $runOne 'mods/more-infinite-research_4.2.21000.zip'), 'mutation')
  } catch [IO.IOException] {
    $writeBlocked = $true
  }
  if (-not $writeBlocked) { throw 'The active immutable lease allowed a staged input write.' }
  $capturedReceipt = Get-MIRImmutableInputLeaseReceipt -Lease $firstLease
  if ($capturedReceipt.state -cne 'receipt-captured' -or $capturedReceipt.inputs_sha256_match -ne $true) {
    throw 'Immutable input receipt was not captured while the no-write lease remained active.'
  }
  if (-not (Get-MIRImmutableInputLeaseLiveness -RunRoot $runOne).active) {
    throw 'Immutable input receipt capture released the active lease before the caller completed its receipt.'
  }
  $firstReceipt = Complete-MIRImmutableInputLease -Lease $firstLease
  $firstLease = $null
  if ($firstReceipt.state -cne 'completed' -or $firstReceipt.inputs_sha256_match -ne $true) {
    throw 'Completed immutable input lease did not preserve exact pre/post hashes.'
  }
  $completedLiveness = Get-MIRImmutableInputLeaseLiveness -RunRoot $runOne
  if ($completedLiveness.active -or $completedLiveness.ambiguous -or $completedLiveness.state -cne 'completed' -or $null -ne $completedLiveness.record.owner_pid -or [string]::IsNullOrWhiteSpace([string]$completedLiveness.record.completed_owner_pid)) {
    throw 'Completed immutable input lease did not clear active ownership into an unambiguous terminal record.'
  }

  $secondLease = New-MIRImmutableInputLease -RunRoot $runTwo -StageDirectory (Join-Path $runTwo 'mods') -ForceCopy -Inputs @(
    [ordered]@{
      source_path = $sourceOne
      file_name = 'more-infinite-research_4.2.21000.zip'
      expected_sha256 = $hashOne
      role = 'candidate'
      identity = [ordered]@{ target = 'f210'; materializer = 'TargetMaterializer'; sha256 = $hashOne }
      provenance = [ordered]@{ kind = 'fresh-materializer-output'; source = 'fixture' }
      immutable = $true
    }
  )
  $copyInput = @($secondLease.record.inputs)[0]
  if ($copyInput.staging_mode -cne 'copy' -or $copyInput.hardlink_fallback_reason -cne 'copy mode was explicitly selected') {
    throw 'Forced copy staging did not record its bounded fallback reason.'
  }
  $secondReceipt = Complete-MIRImmutableInputLease -Lease $secondLease
  $secondLease = $null
  if ($secondReceipt.inputs_sha256_match -ne $true) { throw 'Copy fallback did not preserve the exact input hash.' }

  $mismatchedCandidate = Join-Path $fixtureRoot 'mismatched-f200-candidate.zip'
  [IO.File]::WriteAllText($mismatchedCandidate, 'not the current F200 materialization', [Text.UTF8Encoding]::new($false))
  $f200Harness = Join-Path $RepoRoot 'tests/runtime/Test-MIRF200BobTinProductionGain.ps1'
  $bindingOutput = @(& pwsh -NoProfile -File $f200Harness -RepoRoot $RepoRoot -CandidateZip $mismatchedCandidate -FactorioBin (Join-Path $fixtureRoot 'must-not-resolve-factorio.exe') -BobModsDir (Join-Path $fixtureRoot 'must-not-resolve-bob-mods') -VerifyCandidateBindingOnly 2>&1)
  $bindingExitCode = $LASTEXITCODE
  # The non-zero child exit is the expected negative assertion, not this
  # enclosing test's process result.
  $global:LASTEXITCODE = 0
  if ($bindingExitCode -eq 0) { throw 'F200 production-gain harness accepted a caller candidate whose bytes differ from current materialization.' }
  $bindingText = $bindingOutput | Out-String
  if ($bindingText -notmatch 'supplied[.]candidate[.]sha256 differs') { throw "F200 production-gain mismatch was not rejected by its candidate binding: $bindingText" }
  if ($bindingText -match 'must-not-resolve-factorio|must-not-resolve-bob-mods') { throw "F200 candidate-binding-only path reached an engine or dependency lookup: $bindingText" }

  $aluminiumHarness = Join-Path $RepoRoot 'tests/runtime/Test-MIRA06BobAluminiumQualification.ps1'
  $aluminiumBindingOutput = @(& pwsh -NoProfile -File $aluminiumHarness -RepoRoot $RepoRoot -CandidateZip $mismatchedCandidate -FactorioBin (Join-Path $fixtureRoot 'must-not-resolve-factorio.exe') -BobModsDir (Join-Path $fixtureRoot 'must-not-resolve-bob-mods') -VerifyCandidateBindingOnly 2>&1)
  $aluminiumBindingExitCode = $LASTEXITCODE
  $global:LASTEXITCODE = 0
  if ($aluminiumBindingExitCode -eq 0) { throw 'A06 Aluminium harness accepted supplied bytes that differ from current F210 materialization.' }
  $aluminiumBindingText = $aluminiumBindingOutput | Out-String
  if ($aluminiumBindingText -notmatch 'supplied candidate bytes differ') { throw "A06 Aluminium mismatch was not rejected by its candidate binding: $aluminiumBindingText" }
  if ($aluminiumBindingText -match 'must-not-resolve-factorio|must-not-resolve-bob-mods') { throw "A06 Aluminium candidate-binding-only path reached an engine or dependency lookup: $aluminiumBindingText" }

  $adoptedA06Harnesses = @(
    'tests/runtime/Test-MIRA06BobLeadQualification.ps1',
    'tests/runtime/Test-MIRA06BobGoldQualification.ps1',
    'tests/runtime/Test-MIRA06BobAluminiumQualification.ps1'
  )
  foreach ($relativeHarness in $adoptedA06Harnesses) {
    $harnessPath = Join-Path $RepoRoot $relativeHarness
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($harnessPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if (@($parseErrors).Count -ne 0) {
      throw "$relativeHarness no longer parses after immutable-input adoption: $(@($parseErrors)[0].Message)"
    }
    $harnessSource = [IO.File]::ReadAllText($harnessPath)
    foreach ($requiredText in @(
      'New-MIRImmutableInputLease',
      'Get-MIRImmutableInputLeaseReceipt',
      'Complete-MIRImmutableInputLease',
      'input_staging=$inputStaging'
    )) {
      if (-not $harnessSource.Contains($requiredText, [StringComparison]::Ordinal)) {
        throw "$relativeHarness omitted required immutable-input contract text: $requiredText"
      }
    }
    if ($harnessSource -match 'Copy-Item\s+-LiteralPath\s+\$candidateZip\s+-Destination\s+\$mods' -or
        $harnessSource -match 'Copy-Item\s+-LiteralPath\s+\$source\s+-Destination\s+\$mods') {
      throw "$relativeHarness restored private copies of an immutable candidate or dependency archive."
    }
  }

  $adoptedK2Harnesses = @(
    'tests/runtime/Test-MIR4A03K2K2SOIntake.ps1',
    'tests/runtime/Test-MIR4A05K2Materials.ps1',
    'tests/runtime/Test-MIR4A05K203Imersite.ps1'
  )
  foreach ($relativeHarness in $adoptedK2Harnesses) {
    $harnessPath = Join-Path $RepoRoot $relativeHarness
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($harnessPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if (@($parseErrors).Count -ne 0) {
      throw "$relativeHarness no longer parses after immutable-input adoption: $(@($parseErrors)[0].Message)"
    }
    $harnessSource = [IO.File]::ReadAllText($harnessPath)
    foreach ($requiredText in @(
      'ImmutableInputStaging.ps1',
      'New-MIRImmutableInputLease',
      'Get-MIRImmutableInputLeaseReceipt',
      'Complete-MIRImmutableInputLease',
      'input_staging=$inputStaging',
      'Outcome failed'
    )) {
      if (-not $harnessSource.Contains($requiredText, [StringComparison]::Ordinal)) {
        throw "$relativeHarness omitted required immutable-input contract text: $requiredText"
      }
    }
    if ($harnessSource -match 'Copy-Item\s+-LiteralPath\s+\$candidate\s+-Destination\s+\$mods' -or
        $harnessSource -match 'Copy-Item\s+-LiteralPath\s+\$source\s+-Destination\s+\$mods') {
      throw "$relativeHarness restored private copies of an immutable candidate or dependency archive."
    }
    if ($harnessSource -match 'New-Item\s+-ItemType\s+(?:SymbolicLink|Junction)') {
      throw "$relativeHarness introduced a whole-directory link instead of immutable archive staging."
    }
    $settingsCopy = if ($relativeHarness -ceq 'tests/runtime/Test-MIR4A03K2K2SOIntake.ps1') {
      'Copy-Item -LiteralPath $settingsSourcePath -Destination (Join-Path $mods $settingsSourceItem.Name)'
    } else {
      "Copy-Item -LiteralPath `$settings -Destination (Join-Path `$mods 'mod-settings.dat')"
    }
    if (-not $harnessSource.Contains($settingsCopy, [StringComparison]::Ordinal)) {
      throw "$relativeHarness must retain a private copy of mutable mod-settings.dat."
    }
  }

  $failedRun = Join-Path $fixtureRoot 'failed-run'
  New-Item -ItemType Directory -Force -Path $failedRun | Out-Null
  $rejected = $false
  try {
    New-MIRImmutableInputLease -RunRoot $failedRun -StageDirectory (Join-Path $failedRun 'mods') -Inputs @(
      [ordered]@{
        source_path = $sourceOne
        file_name = 'candidate.zip'
        expected_sha256 = ('0' * 64)
        role = 'candidate'
        identity = [ordered]@{ target = 'f210' }
        provenance = [ordered]@{ kind = 'fixture' }
        immutable = $true
      }
    ) | Out-Null
  } catch {
    $rejected = $true
  }
  if (-not $rejected) { throw 'Immutable input staging accepted an incorrect source hash.' }
  $failedRecord = Get-Content -Raw -LiteralPath (Join-Path $failedRun 'mir-immutable-input-lease.json') | ConvertFrom-Json
  if ($failedRecord.state -cne 'staging-failed') { throw 'Failed staging did not leave a recovery record.' }

  $orphanLockRun = Join-Path $fixtureRoot 'orphan-lock-run'
  New-Item -ItemType Directory -Force -Path $orphanLockRun | Out-Null
  $orphanLock = [IO.File]::Open((Join-Path $orphanLockRun 'mir-immutable-input-lease.lock'), [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try {
    $orphanLive = Get-MIRImmutableInputLeaseLiveness -RunRoot $orphanLockRun
    if (-not $orphanLive.present -or -not $orphanLive.active -or $orphanLive.state -cne 'missing-record') {
      throw 'A lease lock without a record was not treated as active and unsafe.'
    }
  } finally {
    $orphanLock.Dispose()
  }
  $orphanRecovered = Get-MIRImmutableInputLeaseLiveness -RunRoot $orphanLockRun
  if (-not $orphanRecovered.present -or $orphanRecovered.active -or $orphanRecovered.state -cne 'missing-record') {
    throw 'An interrupted lease lock was not retained for recovery classification.'
  }
} finally {
  if ($null -ne $firstLease -and -not $firstLease.closed) {
    try { Complete-MIRImmutableInputLease -Lease $firstLease -Outcome failed | Out-Null } catch {}
  }
  if ($null -ne $secondLease -and -not $secondLease.closed) {
    try { Complete-MIRImmutableInputLease -Lease $secondLease -Outcome failed | Out-Null } catch {}
  }
  if (Test-Path -LiteralPath $fixtureRoot) {
    $resolved = [IO.Path]::GetFullPath($fixtureRoot)
    $prefix = $tempRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Immutable input fixture escaped the system temporary directory: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}

Write-Host '[ok] immutable input staging proves hard-link identity, no-write lease liveness, copy fallback, exact hashes, and failure retention.'
