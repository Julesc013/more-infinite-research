[CmdletBinding()]
param(
  [switch]$PlanOnly,
  [switch]$Preflight,
  [switch]$Execute,
  [switch]$HostSwapSelfTest,
  [string]$FactorioBin = '',
  [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedFactorioSha256 = '',
  [ValidatePattern('^2[.]1[.]23$')][string]$ExpectedEngineVersion = '2.1.23',
  [string]$ArchiveLibrary = '',
  [string]$ProfilePath = '',
  [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedProfileSha256 = '',
  [string]$PublishedArchive = '',
  [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedPublishedSha256 = '',
  [string]$ReplayArchive = '',
  [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedReplaySha256 = '',
  [string]$OrdinaryPlayerConfigPath = '',
  [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedOrdinaryPlayerConfigSha256 = '',
  [string]$PlayerDataPath = '',
  [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedPlayerDataSha256 = '',
  [string]$OutputRoot = '',
  [ValidateRange(1,300)][int]$TimeoutSeconds = 300,
  [ValidateRange(1,8192)][int]$ExpectedPeakMemoryMiB = 2048,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB = 512,
  [ValidateRange(0,300)][int]$AdmissionWaitSeconds = 0,
  [ValidateRange(0,5000)][int]$LibraryIdleWaitMilliseconds = 5000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-MIR5MenuComparisonPlan {
  $specifications = [Collections.Generic.List[object]]::new()
  foreach($arm in @('without-mir', 'published-4.7', 'replay')) {
    $specifications.Add([ordered]@{phase='warmup';arm=$arm;block=0;position=$specifications.Count+1})
  }
  $specifications.Add([ordered]@{phase='aa-pilot';arm='published-4.7';block=0;position=1})
  $specifications.Add([ordered]@{phase='aa-pilot';arm='published-4.7';block=0;position=2})
  $rotations = @(
    @('without-mir', 'published-4.7', 'replay'),
    @('published-4.7', 'replay', 'without-mir'),
    @('replay', 'without-mir', 'published-4.7')
  )
  for($block = 1; $block -le $rotations.Count; $block++) {
    for($index = 0; $index -lt $rotations[$block - 1].Count; $index++) {
      $specifications.Add([ordered]@{phase='counterbalanced-comparison';arm=$rotations[$block - 1][$index];block=$block;position=$index+1})
    }
  }
  $rows = [Collections.Generic.List[object]]::new()
  $ordinal = 0
  foreach($specification in $specifications) {
    $ordinal++
    $rows.Add([ordered]@{
      ordinal = $ordinal
      phase = [string]$specification.phase
      arm = [string]$specification.arm
      block = [int]$specification.block
      position = [int]$specification.position
      label = ('{0:D2}-{1}-{2}' -f $ordinal, ([string]$specification.phase).ToLowerInvariant().Replace('/', '-').Replace(' ', '-'), [string]$specification.arm)
    })
  }
  return @($rows)
}

function New-MIR5MenuComparisonPlanRecord {
  $plan = @(New-MIR5MenuComparisonPlan)
  [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR5ResponsiveMenuComparisonPlanV1'
    status = 'planned-not-executed'
    endpoint = 'ordinary-responsive-menu'
    samples = $plan
    fixed_before_execution = $true
    claims = [ordered]@{
      native_execution = $false
      performance_measurement = $false
      performance_comparison = $false
      release_qualification = $false
    }
    limitations = @(
      'The plan is a private first-batch comparison design, not a performance result.',
      'A real credential-free engine-prepared player-data seed and a root-owned exclusive native window are still required.'
    )
  }
}

function Test-MIR5MenuRequiredInput {
  param([string]$Name, [string]$Path, [string]$Hash, [Collections.Generic.List[object]]$Missing)
  if([string]::IsNullOrWhiteSpace($Path)) {
    $Missing.Add([ordered]@{name=$Name; reason='path-required'})
    return
  }
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)) {
    $Missing.Add([ordered]@{name=$Name; reason='file-missing'; path=$Path})
  }
  if([string]::IsNullOrWhiteSpace($Hash) -or $Hash -cnotmatch '^[A-Fa-f0-9]{64}$') {
    $Missing.Add([ordered]@{name=$Name; reason='sha256-required'})
  }
}

function Get-MIR5MenuPreflight {
  $missing = [Collections.Generic.List[object]]::new()
  Test-MIR5MenuRequiredInput -Name 'FactorioBin' -Path $FactorioBin -Hash $ExpectedFactorioSha256 -Missing $missing
  if([string]::IsNullOrWhiteSpace($ArchiveLibrary) -or -not(Test-Path -LiteralPath $ArchiveLibrary -PathType Container)) {
    $missing.Add([ordered]@{name='ArchiveLibrary'; reason='directory-required'; path=$ArchiveLibrary})
  }
  Test-MIR5MenuRequiredInput -Name 'ProfilePath' -Path $ProfilePath -Hash $ExpectedProfileSha256 -Missing $missing
  Test-MIR5MenuRequiredInput -Name 'PublishedArchive' -Path $PublishedArchive -Hash $ExpectedPublishedSha256 -Missing $missing
  Test-MIR5MenuRequiredInput -Name 'ReplayArchive' -Path $ReplayArchive -Hash $ExpectedReplaySha256 -Missing $missing
  Test-MIR5MenuRequiredInput -Name 'OrdinaryPlayerConfigPath' -Path $OrdinaryPlayerConfigPath -Hash $ExpectedOrdinaryPlayerConfigSha256 -Missing $missing
  if([string]::IsNullOrWhiteSpace($PlayerDataPath)) {
    $missing.Add([ordered]@{
      name = 'PlayerDataPath'
      reason = 'actual-credential-free-engine-prepared-player-data-required'
      expected_engine_version = $ExpectedEngineVersion
    })
  } else {
    Test-MIR5MenuRequiredInput -Name 'PlayerDataPath' -Path $PlayerDataPath -Hash $ExpectedPlayerDataSha256 -Missing $missing
  }
  if([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $missing.Add([ordered]@{name='OutputRoot'; reason='path-required'})
  }
  [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR5ResponsiveMenuComparisonPreflightV1'
    status = $(if($missing.Count) {'blocked-prerequisites'} else {'inputs-present-not-executed'})
    required_engine_version = $ExpectedEngineVersion
    missing = @($missing)
    plan = @(New-MIR5MenuComparisonPlan)
    claims = [ordered]@{native_execution=$false; performance_measurement=$false; performance_comparison=$false; release_qualification=$false}
  }
}

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/lib/validation/ImmutableInputStaging.ps1')
. (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')

function Assert-MIR5MenuComparison {
  param([bool]$Condition, [string]$Code)
  if(-not $Condition) { throw "[mir5-menu-$Code]" }
}

function Assert-MIR5MenuSha256 {
  param([string]$Path, [string]$Expected, [string]$Code)
  $actual = Get-MIRImmutableInputSha256 -Path $Path
  Assert-MIR5MenuComparison ($actual -ceq $Expected.ToUpperInvariant()) $Code
  return $actual
}

function Read-MIR5MenuArchive {
  param([string]$Path, [string]$ExpectedSha256, [string]$Code)
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  Assert-MIRLibraryPath $resolved
  $item = Get-Item -LiteralPath $resolved
  Assert-MIR5MenuComparison (-not $item.PSIsContainer -and $item.Length -gt 0 -and $item.Length -le 2GB) "$Code-size"
  $sha256 = Assert-MIR5MenuSha256 -Path $resolved -Expected $ExpectedSha256 -Code "$Code-sha256"
  $zip = [IO.Compression.ZipFile]::OpenRead($resolved)
  try {
    $entries = @($zip.Entries | Where-Object {$_.FullName -match '^[^/]+/info[.]json$'})
    Assert-MIR5MenuComparison ($entries.Count -eq 1 -and $entries[0].Length -gt 0 -and $entries[0].Length -le 64KB) "$Code-info"
    $reader = [IO.StreamReader]::new($entries[0].Open())
    try { $info = $reader.ReadToEnd() | ConvertFrom-Json -AsHashtable } finally { $reader.Dispose() }
  } finally { $zip.Dispose() }
  $root = $entries[0].FullName.Substring(0, $entries[0].FullName.Length - '/info.json'.Length)
  Assert-MIR5MenuComparison ([string]$info.name -ceq 'more-infinite-research') "$Code-name"
  Assert-MIR5MenuComparison ([string]$info.version -match '^\d+[.]\d+[.]\d+$') "$Code-version"
  Assert-MIR5MenuComparison ([IO.Path]::GetFileName($resolved) -ceq ('more-infinite-research_' + [string]$info.version + '.zip')) "$Code-filename"
  Assert-MIR5MenuComparison ($root -ceq ([string]$info.name + '_' + [string]$info.version)) "$Code-root"
  [pscustomobject][ordered]@{path=$resolved;sha256=$sha256;name=[string]$info.name;version=[string]$info.version;root=$root;factorio_version=[string]$info.factorio_version;bytes=[int64]$item.Length}
}

function Enter-MIR5MenuLibrarySwapLock {
  param([string]$LibraryDirectory, [int]$WaitMilliseconds)
  Assert-MIRLibraryIdle -WaitMilliseconds $WaitMilliseconds
  $library = (Resolve-Path -LiteralPath $LibraryDirectory).Path
  Assert-MIRLibraryPath $library
  $journal = Join-Path $library '.mir-active-profile.json'
  Assert-MIR5MenuComparison (-not(Test-Path -LiteralPath $journal)) 'library-active-profile'
  $lockPath = Join-Path $library '.mir-library.lock'
  if(Test-Path -LiteralPath $lockPath) { Assert-MIRLibraryPath $lockPath }
  try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
  catch { throw '[mir5-menu-library-busy]' }
  try {
    Assert-MIRLibraryIdle -WaitMilliseconds $WaitMilliseconds
    Assert-MIR5MenuComparison (-not(Test-Path -LiteralPath $journal)) 'library-active-profile'
    return $lock
  } catch {
    $lock.Dispose()
    throw
  }
}

function Invoke-MIR5MenuReplaySwap {
  param(
    [string]$LibraryDirectory,
    [Parameter(Mandatory)]$Published,
    [Parameter(Mandatory)]$Replay,
    [int]$WaitMilliseconds,
    [Parameter(Mandatory)][scriptblock]$Action,
    [Parameter(Mandatory)][string]$RecordRoot
  )
  $library = (Resolve-Path -LiteralPath $LibraryDirectory).Path
  Assert-MIR5MenuComparison ([IO.Path]::GetDirectoryName([string]$Published.path) -ceq $library) 'published-library-location'
  Assert-MIR5MenuComparison ([IO.Path]::GetDirectoryName([string]$Replay.path) -cne $library) 'replay-source-location'
  Assert-MIR5MenuComparison ($Published.name -ceq $Replay.name -and $Published.version -ceq $Replay.version -and $Published.root -ceq $Replay.root) 'same-metadata-required'
  Assert-MIR5MenuComparison ($Published.sha256 -cne $Replay.sha256) 'replay-different-bytes-required'

  $swapId = [guid]::NewGuid().ToString('N')
  $retained = [string]$Published.path + '.mir5-menu-retained-' + $swapId
  $journalPath = Join-Path $RecordRoot ('swap-' + $swapId + '.json')
  $record = [ordered]@{
    kind = 'MIR5ResponsiveMenuArchiveSwapV1'
    status = 'prepared'
    id = $swapId
    library_archive = [string]$Published.path
    replay_source = [string]$Replay.path
    retained_library_path = $retained
    published_sha256 = [string]$Published.sha256
    replay_sha256 = [string]$Replay.sha256
    restored = $false
  }
  [IO.File]::WriteAllText($journalPath, ($record | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))

  $publishedMoved = $false
  $replayInstalled = $false
  $stageError = $null
  $lock = $null
  try {
    $lock = Enter-MIR5MenuLibrarySwapLock -LibraryDirectory $library -WaitMilliseconds $WaitMilliseconds
    Assert-MIR5MenuComparison (-not(Test-Path -LiteralPath $retained)) 'swap-retained-path'
    Assert-MIR5MenuComparison (Test-Path -LiteralPath $Published.path -PathType Leaf) 'published-missing-before-swap'
    Assert-MIR5MenuComparison (Test-Path -LiteralPath $Replay.path -PathType Leaf) 'replay-missing-before-swap'
    $null = Assert-MIR5MenuSha256 -Path $Published.path -Expected $Published.sha256 -Code 'published-before-swap'
    $null = Assert-MIR5MenuSha256 -Path $Replay.path -Expected $Replay.sha256 -Code 'replay-before-swap'
    [IO.File]::Move([string]$Published.path, $retained, $false)
    $publishedMoved = $true
    [IO.File]::Move([string]$Replay.path, [string]$Published.path, $false)
    $replayInstalled = $true
    $null = Assert-MIR5MenuSha256 -Path $Published.path -Expected $Replay.sha256 -Code 'replay-installed'
    $record.status = 'replay-installed'
    [IO.File]::WriteAllText($journalPath, ($record | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
  } catch { $stageError = $_ }
  finally {
    if($null -ne $lock) { $lock.Dispose() }
  }

  $actionResult = $null
  try {
    if($null -ne $stageError) { throw $stageError }
    $actionResult = & $Action
    $record.status = 'action-completed-awaiting-restore'
  } finally {
    $restoreLock = $null
    try {
      if($publishedMoved -or $replayInstalled) {
        $restoreLock = Enter-MIR5MenuLibrarySwapLock -LibraryDirectory $library -WaitMilliseconds $WaitMilliseconds
        if($replayInstalled) {
          Assert-MIR5MenuComparison (Test-Path -LiteralPath $Published.path -PathType Leaf) 'replay-missing-before-restore'
          $null = Assert-MIR5MenuSha256 -Path $Published.path -Expected $Replay.sha256 -Code 'replay-before-restore'
          Assert-MIR5MenuComparison (-not(Test-Path -LiteralPath $Replay.path)) 'replay-source-occupied-before-restore'
          [IO.File]::Move([string]$Published.path, [string]$Replay.path, $false)
          $null = Assert-MIR5MenuSha256 -Path $Replay.path -Expected $Replay.sha256 -Code 'replay-restored'
        }
        if($publishedMoved) {
          Assert-MIR5MenuComparison (Test-Path -LiteralPath $retained -PathType Leaf) 'published-retained-missing'
          Assert-MIR5MenuComparison (-not(Test-Path -LiteralPath $Published.path)) 'published-destination-occupied-before-restore'
          $null = Assert-MIR5MenuSha256 -Path $retained -Expected $Published.sha256 -Code 'published-retained'
          [IO.File]::Move($retained, [string]$Published.path, $false)
          $null = Assert-MIR5MenuSha256 -Path $Published.path -Expected $Published.sha256 -Code 'published-restored'
        }
        $record.status = 'restored'
        $record.restored = $true
      } else {
        $record.status = 'not-swapped'
        $record.restored = $true
      }
    } catch {
      $record.status = 'restore-failed'
      $record.restore_error = $_.Exception.Message
      throw
    } finally {
      [IO.File]::WriteAllText($journalPath, ($record | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
      if($null -ne $restoreLock) { $restoreLock.Dispose() }
    }
  }
  [pscustomobject][ordered]@{sample=$actionResult;swap=$record;swap_record=[IO.Path]::GetFileName($journalPath)}
}

function Invoke-MIR5MenuHostSwapSelfTest {
  # This is a host-only mutation control. It creates ordinary byte files under
  # this checkout's build/tmp, never launches Factorio, and deletes the exact
  # temporary root after exercising action failure and lock refusal.
  $temporaryRoot = Join-Path $repo ('build/tmp/mir5-menu-swap-host-' + [guid]::NewGuid().ToString('N'))
  $temporaryParent = (Resolve-Path -LiteralPath (Join-Path $repo 'build/tmp')).Path
  [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
  $temporaryRoot = (Resolve-Path -LiteralPath $temporaryRoot).Path
  Assert-MIR5MenuComparison ($temporaryRoot.StartsWith($temporaryParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) 'host-swap-root'

  try {
    $library = Join-Path $temporaryRoot 'library'
    $source = Join-Path $temporaryRoot 'source'
    $records = Join-Path $temporaryRoot 'records'
    [IO.Directory]::CreateDirectory($library) | Out-Null
    [IO.Directory]::CreateDirectory($source) | Out-Null
    [IO.Directory]::CreateDirectory($records) | Out-Null
    $publishedPath = Join-Path $library 'more-infinite-research_4.7.21000.zip'
    $replayPath = Join-Path $source 'more-infinite-research_4.7.21000.zip'
    [IO.File]::WriteAllText($publishedPath, 'published-bytes', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($replayPath, 'replay-bytes', [Text.UTF8Encoding]::new($false))
    $published = [pscustomobject]@{path=$publishedPath;name='more-infinite-research';version='4.7.21000';root='more-infinite-research_4.7.21000';sha256=(Get-MIRImmutableInputSha256 -Path $publishedPath)}
    $replay = [pscustomobject]@{path=$replayPath;name='more-infinite-research';version='4.7.21000';root='more-infinite-research_4.7.21000';sha256=(Get-MIRImmutableInputSha256 -Path $replayPath)}

    $governedActor = Get-Command -Name Invoke-MIRDirectLibraryResponsiveMenuSample -CommandType Function -ErrorAction Stop
    $closedActorName = { [string]$governedActor.Name }.GetNewClosure()
    Assert-MIR5MenuComparison ((& $closedActorName) -ceq 'Invoke-MIRDirectLibraryResponsiveMenuSample') 'host-governed-actor-closure'

    $actionFailureObserved = $false
    try {
      $action = {
        if([IO.File]::ReadAllText($publishedPath) -cne 'replay-bytes') {
          throw '[mir5-menu-host-action-replay-not-visible]'
        }
        throw '[mir5-menu-host-action-failure]'
      }.GetNewClosure()
      $null = Invoke-MIR5MenuReplaySwap -LibraryDirectory $library -Published $published -Replay $replay -WaitMilliseconds 0 -Action $action -RecordRoot $records
    } catch {
      if($_.Exception.Message -notmatch 'host-action-failure') { throw }
      $actionFailureObserved = $true
    }
    Assert-MIR5MenuComparison $actionFailureObserved 'host-action-failure-not-observed'
    Assert-MIR5MenuComparison ((Get-MIRImmutableInputSha256 -Path $publishedPath) -ceq $published.sha256) 'host-published-not-restored'
    Assert-MIR5MenuComparison ((Get-MIRImmutableInputSha256 -Path $replayPath) -ceq $replay.sha256) 'host-replay-not-restored'
    Assert-MIR5MenuComparison (@(Get-ChildItem -LiteralPath $library -Filter '*.mir5-menu-retained-*' -File).Count -eq 0) 'host-retained-left-behind'
    $actionJournal = @(Get-ChildItem -LiteralPath $records -Filter 'swap-*.json' -File | Sort-Object Name | Select-Object -Last 1)
    Assert-MIR5MenuComparison ($actionJournal.Count -eq 1) 'host-action-journal'
    $actionRecord = Get-Content -LiteralPath $actionJournal[0].FullName -Raw | ConvertFrom-Json -AsHashtable
    Assert-MIR5MenuComparison ($actionRecord.status -ceq 'restored' -and $actionRecord.restored -eq $true) 'host-action-receipt'

    $lockPath = Join-Path $library '.mir-library.lock'
    $held = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
      $lockFailureObserved = $false
      try {
        $never = { throw '[mir5-menu-host-action-should-not-run]' }
        $null = Invoke-MIR5MenuReplaySwap -LibraryDirectory $library -Published $published -Replay $replay -WaitMilliseconds 0 -Action $never -RecordRoot $records
      } catch {
        if($_.Exception.Message -notmatch 'library-busy') { throw }
        $lockFailureObserved = $true
      }
      Assert-MIR5MenuComparison $lockFailureObserved 'host-lock-failure-not-observed'
      Assert-MIR5MenuComparison ((Get-MIRImmutableInputSha256 -Path $publishedPath) -ceq $published.sha256) 'host-lock-published-mutated'
      Assert-MIR5MenuComparison ((Get-MIRImmutableInputSha256 -Path $replayPath) -ceq $replay.sha256) 'host-lock-replay-mutated'
    } finally {
      $held.Dispose()
    }

    [pscustomobject][ordered]@{
      schema = 1
      kind = 'MIR5MenuSwapHostControlV1'
      status = 'passed'
      action_failure_restored = $true
      busy_lock_refused_without_mutation = $true
      claims = [ordered]@{native_execution=$false;performance_measurement=$false;performance_comparison=$false;release_qualification=$false}
    }
  } finally {
    if(Test-Path -LiteralPath $temporaryRoot) {
      [IO.Directory]::Delete($temporaryRoot, $true)
    }
  }
}

if($HostSwapSelfTest) {
  Invoke-MIR5MenuHostSwapSelfTest
  return
}
if($PlanOnly) {
  New-MIR5MenuComparisonPlanRecord
  return
}

$preflightRecord = Get-MIR5MenuPreflight
if($Preflight -or $preflightRecord.status -ceq 'blocked-prerequisites') {
  $preflightRecord
  return
}
if(-not $Execute) {
  throw '[mir5-menu-execute-required] Review the preflight, then use -Execute only with exclusive native ownership.'
}

function Invoke-MIR5MenuComparisonSample {
  param(
    [Parameter(Mandatory)]$PlanRow,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$Inputs,
    [Parameter(Mandatory)]$OrdinaryPlayerConfig,
    [Parameter(Mandatory)]$OrdinaryMenuPreparation,
    [Parameter(Mandatory)][string]$WriteDataRoot,
    [Parameter(Mandatory)][string]$RecordRoot
  )
  $runRoot = Join-Path $Context.root ('runs/' + [string]$PlanRow.label)
  # A replay action crosses a function boundary during the guarded library
  # swap. Capture the governed actor's command object, rather than resolving a
  # script-scoped function name from that nested closure.
  $menuSampleCommand = Get-Command -Name Invoke-MIRDirectLibraryResponsiveMenuSample -CommandType Function -ErrorAction Stop
  $invoke = {
    param($Archive)
    & $menuSampleCommand -RepoRoot $Inputs.repo -FactorioBin $Inputs.factorio.path -LibraryDirectory $Inputs.library -EngineDataDirectory $Inputs.engine_data -BaseRows $Inputs.base_rows -RunRoot $runRoot -WriteDataRoot $WriteDataRoot -Label ([string]$PlanRow.label) -Resources $Context -MirArchive $Archive -TimeoutSeconds $Inputs.timeout_seconds -OrdinaryPlayerConfig $OrdinaryPlayerConfig -OrdinaryMenuPreparation $OrdinaryMenuPreparation
  }.GetNewClosure()
  if($PlanRow.arm -ceq 'without-mir') {
    return [pscustomobject][ordered]@{sample=(& $invoke $null); swap=$null; swap_record=$null}
  }
  if($PlanRow.arm -ceq 'published-4.7') {
    $archive = [pscustomobject]@{version=$Inputs.published.version}
    return [pscustomobject][ordered]@{sample=(& $invoke $archive); swap=$null; swap_record=$null}
  }
  if($PlanRow.arm -ceq 'replay') {
    $archive = [pscustomobject]@{version=$Inputs.replay.version}
    $action = { & $invoke $archive }.GetNewClosure()
    return Invoke-MIR5MenuReplaySwap -LibraryDirectory $Inputs.library -Published $Inputs.published -Replay $Inputs.replay -WaitMilliseconds $Inputs.library_idle_wait_milliseconds -Action $action -RecordRoot $RecordRoot
  }
  throw '[mir5-menu-plan-arm]'
}

$resources = $null
$samples = [Collections.Generic.List[object]]::new()
$current = $null
$ordinaryMenuPreparation = $null
$inputRecord = $null
$developmentHealth = $null
try {
  $healthScript = Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1'
  Assert-MIR5MenuComparison (Test-Path -LiteralPath $healthScript -PathType Leaf) 'development-health-script'
  $health = & $healthScript -RepoRoot $repo -Mode Report -AsJson -MaxScanSeconds 1 -MaxEntriesPerRoot 100 | ConvertFrom-Json -Depth 32
  Assert-MIR5MenuComparison ($null -ne $health -and $null -ne $health.disk) 'development-health'
  Assert-MIR5MenuComparison ([int]$health.disk.free_mib -ge [int]$health.disk.minimum_free_mib) 'development-health-free-space'
  Assert-MIR5MenuComparison ([string]$health.disk.build_budget_observation -notmatch '^over-budget') 'development-health-build-space'
  Assert-MIR5MenuComparison ([string]$health.disk.dist_budget_observation -notmatch '^over-budget') 'development-health-dist-space'
  $developmentHealth = [ordered]@{
    status=[string]$health.status
    free_mib=[int]$health.disk.free_mib
    minimum_free_mib=[int]$health.disk.minimum_free_mib
    build_budget_observation=[string]$health.disk.build_budget_observation
    dist_budget_observation=[string]$health.disk.dist_budget_observation
  }

  $library = (Resolve-Path -LiteralPath $ArchiveLibrary).Path
  Assert-MIRLibraryPath $library
  $profile = (Resolve-Path -LiteralPath $ProfilePath).Path
  $null = Assert-MIR5MenuSha256 -Path $profile -Expected $ExpectedProfileSha256 -Code 'profile-sha256'
  $profileRaw = (Get-Content -LiteralPath $profile -Raw).TrimStart([char]0xFEFF) | ConvertFrom-Json -AsHashtable
  Assert-MIR5MenuComparison ($profileRaw.mods -is [array] -and @($profileRaw.mods | Where-Object {$_.name -ceq 'more-infinite-research'}).Count -eq 0) 'profile-mir-row'

  $engineRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Resolve-Path -LiteralPath $FactorioBin).Path))
  $engineData = Join-Path $engineRoot 'data'
  Assert-MIR5MenuComparison (Test-Path -LiteralPath $engineData -PathType Container) 'engine-data'
  $engine = Get-MIRDirectLibraryStartupEngineIdentity -FactorioBin $FactorioBin -EngineDataDirectory $engineData
  Assert-MIR5MenuComparison ($engine.sha256 -ceq $ExpectedFactorioSha256.ToUpperInvariant()) 'factorio-sha256'
  Assert-MIR5MenuComparison ($engine.base_version -ceq $ExpectedEngineVersion) 'engine-version'

  $published = Read-MIR5MenuArchive -Path $PublishedArchive -ExpectedSha256 $ExpectedPublishedSha256 -Code 'published'
  $replay = Read-MIR5MenuArchive -Path $ReplayArchive -ExpectedSha256 $ExpectedReplaySha256 -Code 'replay'
  Assert-MIR5MenuComparison ([IO.Path]::GetDirectoryName($published.path) -ceq $library) 'published-library-location'
  Assert-MIR5MenuComparison ([IO.Path]::GetDirectoryName($replay.path) -cne $library) 'replay-source-location'
  Assert-MIR5MenuComparison ($published.name -ceq $replay.name -and $published.version -ceq $replay.version -and $published.root -ceq $replay.root) 'same-metadata-required'
  Assert-MIR5MenuComparison ($published.factorio_version -ceq '2.1' -and $replay.factorio_version -ceq '2.1') 'archive-factorio-line'

  $ordinaryPlayerConfig = Get-MIRDirectLibraryOrdinaryPlayerConfigInput -Path $OrdinaryPlayerConfigPath
  Assert-MIR5MenuComparison ($ordinaryPlayerConfig.sha256 -ceq $ExpectedOrdinaryPlayerConfigSha256.ToUpperInvariant()) 'ordinary-config-sha256'
  $playerData = Get-MIRDirectLibraryOrdinaryMenuPlayerDataInput -Path $PlayerDataPath -ExpectedEngineVersion $ExpectedEngineVersion
  Assert-MIR5MenuComparison ($playerData.sha256 -ceq $ExpectedPlayerDataSha256.ToUpperInvariant()) 'player-data-sha256'
  $baseRows = Read-MIRDirectLibraryStartupProfile -Path $profile

  $resources = New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB -UseExactOutputRoot
  [IO.Directory]::CreateDirectory($resources.root) | Out-Null
  $planRecord = New-MIR5MenuComparisonPlanRecord
  $planPath = Join-Path $resources.root 'plan.json'
  [IO.File]::WriteAllText($planPath, ($planRecord | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
  $planSha = Get-MIRImmutableInputSha256 -Path $planPath
  $writeDataRoot = Join-Path $resources.root 'write-data/ordinary-menu-shared'
  $ordinaryMenuPreparation = Initialize-MIRDirectLibraryOrdinaryMenuSharedWriteData -WriteDataRoot $writeDataRoot -PlayerData $playerData
  $inputRecord = [ordered]@{
    development_health=$developmentHealth
    factorio=$engine
    archive_library=$library
    profile=[ordered]@{path=$profile;sha256=$ExpectedProfileSha256.ToUpperInvariant()}
    published=$published
    replay=$replay
    ordinary_player_config=[ordered]@{path=$ordinaryPlayerConfig.path;sha256=$ordinaryPlayerConfig.sha256;bytes=$ordinaryPlayerConfig.bytes}
    player_data=[ordered]@{path=$playerData.path;sha256=$playerData.sha256;bytes=$playerData.bytes;engine_version=$playerData.engine_version;kind=$playerData.kind}
  }
  $inputs = [pscustomobject]@{
    repo=$repo; factorio=$engine; library=$library; engine_data=$engineData; base_rows=$baseRows; published=$published; replay=$replay
    timeout_seconds=$TimeoutSeconds; library_idle_wait_milliseconds=$LibraryIdleWaitMilliseconds
  }
  foreach($planRow in @($planRecord.samples)) {
    $current = $planRow
    $admission = Wait-MIRDirectLibraryStartupAdmission -Policy $resources.policy -WorkRoot $resources.root -EstimatedPeakBytes (Get-MIRNativeProbeRemainingOutputBytes -Context $resources) -ExpectedPeakMemoryBytes $resources.peak_memory_bytes -AdmissionWaitSeconds $AdmissionWaitSeconds -Phase ('menu-comparison:' + [string]$planRow.label)
    $sample = Invoke-MIR5MenuComparisonSample -PlanRow $planRow -Context $resources -Inputs $inputs -OrdinaryPlayerConfig $ordinaryPlayerConfig -OrdinaryMenuPreparation $ordinaryMenuPreparation -WriteDataRoot $writeDataRoot -RecordRoot $resources.root
    $samples.Add([ordered]@{plan=$planRow;prelaunch_admission_wait=$admission;observation=$sample.sample;archive_swap=$sample.swap;archive_swap_record=$sample.swap_record})
  }
  $result = [pscustomobject][ordered]@{
    schema=1;kind='MIR5ResponsiveMenuComparisonObservationV1';status='completed-observation-only';endpoint_class='ordinary-responsive-menu'
    plan=[ordered]@{path='plan.json';sha256=$planSha;fixed_before_execution=$true;samples=@($planRecord.samples)}
    inputs=$inputRecord;ordinary_menu_preparation=$ordinaryMenuPreparation;samples=@($samples)
    library_controls_restored=(-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json')))
    claims=[ordered]@{native_execution=$true;performance_measurement=$false;performance_comparison=$false;release_qualification=$false}
    limitations=@('Raw owned-window menu observations only; no performance gate, score, or acceptance analysis is computed.','This private plan compares an exact published archive and same-metadata replay bytes only after a root-owned native run.','Full MIR5 package parity, gameplay, save continuity, Library fidelity, and release qualification remain outside this wrapper.')
  }
  Write-MIRNativeProbeResult -Context $resources -Record $result
  $result
} catch {
  if($null -ne $resources) {
    $failure = [pscustomobject][ordered]@{
      schema=1;kind='MIR5ResponsiveMenuComparisonObservationV1';status='failed-observation-retained';endpoint_class='ordinary-responsive-menu'
      current_plan_row=$current;development_health=$developmentHealth;inputs=$inputRecord;ordinary_menu_preparation=$ordinaryMenuPreparation;samples_so_far=@($samples);error=$_.Exception.Message
      library_controls_restored=$(if([string]::IsNullOrWhiteSpace($ArchiveLibrary)){$false}else{-not(Test-Path -LiteralPath (Join-Path $ArchiveLibrary '.mir-active-profile.json'))})
      claims=[ordered]@{native_execution=$false;performance_measurement=$false;performance_comparison=$false;release_qualification=$false}
    }
    try { Write-MIRNativeProbeResult -Context $resources -Record $failure } catch { Write-Warning "[mir5-menu-failure-receipt] $($_.Exception.Message)" }
  }
  throw
}
