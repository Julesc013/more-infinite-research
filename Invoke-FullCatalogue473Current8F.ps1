[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RepoRoot,
  [Parameter(Mandatory)][string]$ArchiveLibrary,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$CandidateArchive,
  [Parameter(Mandatory)][string]$CanonicalObserverArchive,
  [Parameter(Mandatory)][string]$OutputRoot,
  [Parameter(Mandatory)][string]$RecoveryRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sourceCommit = '023396d77f7935d0c217ad6ae4a6a31049273dad'
$sourceTree = '44eadfad017440d384f0e932b0eecbcb991a5e40'
$engineSha = 'FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060'
$publishedSha = 'B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852'
$candidateSha = '8F858F6B7E604757DE84D960E7D7701021B956782C65A13978E3AFD711F7B071'
$restoreCandidateSha = 'C563CB5B96C9E64CB3373BDB60CF5C8B7D3C97E93EADB8F924443C703CDC024D'
$observerSha = 'A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'
$fixtureName = 'mir-fixture-mir5-full-catalogue-upgrade'
$observerName = 'mir-fixture-mir5-active-mods-observer'

function Assert-Full473([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "[full-catalogue-473-current8f] $Message" }
}
function Get-Full473Sha([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function Write-Full473Json([string]$Path, [object]$Value) {
  [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
  [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 32), [Text.UTF8Encoding]::new($false))
}
function Test-Full473Under([string]$Root, [string]$Path) {
  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([char]92, [char]47)
  $pathFull = [IO.Path]::GetFullPath($Path)
  return $pathFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}
function Get-Full473Files([string]$Root) {
  @(Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName | ForEach-Object {
    [ordered]@{
      path = [IO.Path]::GetRelativePath($Root, $_.FullName).Replace([string][char]92, '/')
      bytes = [int64]$_.Length
      sha256 = Get-Full473Sha $_.FullName
    }
  })
}
function Copy-Full473Custody([string]$From, [string]$To) {
  Assert-Full473 (Test-Path -LiteralPath $From -PathType Container) "custody source is absent: $From"
  Assert-Full473 (-not (Test-Path -LiteralPath $To)) "custody destination already exists: $To"
  Copy-Item -LiteralPath $From -Destination $To -Recurse -Force
  $left = Get-Full473Files $From
  $right = Get-Full473Files $To
  Assert-Full473 ($left.Count -eq $right.Count) 'custody member count differs'
  for ($index = 0; $index -lt $left.Count; $index++) {
    Assert-Full473 (($left[$index].path -ceq $right[$index].path) -and ($left[$index].bytes -eq $right[$index].bytes) -and ($left[$index].sha256 -ceq $right[$index].sha256)) "custody member differs at index $index"
  }
  [ordered]@{ source = $From; destination = $To; member_count = $right.Count; members = $right }
}
function Assert-Full473LibraryIdle([string]$Library) {
  Assert-Full473 (@(Get-Process -Name factorio -ErrorAction SilentlyContinue).Count -eq 0) 'Factorio is active'
  Assert-Full473 (-not (Test-Path -LiteralPath (Join-Path $Library '.mir-active-profile.json'))) 'library active-profile marker exists'
  Assert-Full473 (-not (Test-Path -LiteralPath (Join-Path $Library '.mir-recovery-active.json'))) 'library recovery marker exists'
}
function Use-Full473LibraryLock([string]$Library, [scriptblock]$Action) {
  $lockPath = Join-Path $Library '.mir-library.lock'
  $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try { return & $Action } finally { $lock.Dispose() }
}
function Write-Full473GitBlob([string]$Revision, [string]$Source, [string]$Destination) {
  [IO.Directory]::CreateDirectory((Split-Path -Parent $Destination)) | Out-Null
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = 'git'
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($argument in @('-C', $repo, 'show', ($Revision + ':' + $Source))) { [void]$start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $start
  Assert-Full473 ($process.Start()) "cannot read raw Git member: $Source"
  $output = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $process.StandardOutput.BaseStream.CopyTo($output) } finally { $output.Dispose() }
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  $exitCode = $process.ExitCode
  $process.Dispose()
  Assert-Full473 ($exitCode -eq 0) "raw Git member is absent: $Source $stderr"
}
function Assert-Full473Tree([string]$Folder, [string[]]$Expected) {
  $actual = @(& git -C $repo ls-tree -r --name-only $sourceCommit -- $Folder | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object)
  Assert-Full473 (@(Compare-Object -ReferenceObject @($Expected | Sort-Object) -DifferenceObject $actual).Count -eq 0) "raw-Git closure differs: $Folder"
}
function New-Full473Fixture([string]$Id, [string]$StageFolder, [string]$Version) {
  $expected = @(
    "$StageFolder/info.json", "$StageFolder/control.lua", "$StageFolder/data-final-fixes.lua", "$StageFolder/catalogue.lua"
  )
  Assert-Full473Tree $StageFolder $expected
  $members = @(
    [ordered]@{ destination = 'info.json'; source = "$StageFolder/info.json" },
    [ordered]@{ destination = 'control.lua'; source = "$StageFolder/control.lua" },
    [ordered]@{ destination = 'data-final-fixes.lua'; source = "$StageFolder/data-final-fixes.lua" },
    [ordered]@{ destination = 'catalogue.lua'; source = "$StageFolder/catalogue.lua" },
    [ordered]@{ destination = 'fixture_control.lua'; source = 'tests/fixtures/full-catalogue-upgrade/shared/control.lua' },
    [ordered]@{ destination = 'fixture_data_final.lua'; source = 'tests/fixtures/full-catalogue-upgrade/shared/data-final-fixes.lua' },
    [ordered]@{ destination = 'f210_catalogue.lua'; source = 'tests/fixtures/full-catalogue-upgrade/shared/f210-catalogue.lua' }
  )
  $source = Join-Path $fixtureSources $Id
  [IO.Directory]::CreateDirectory($source) | Out-Null
  $rows = @()
  foreach ($member in $members) {
    $destination = Join-Path $source ([string]$member.destination)
    Write-Full473GitBlob $sourceCommit ([string]$member.source) $destination
    $rows += [ordered]@{ source = [string]$member.source; member = [string]$member.destination; sha256 = Get-Full473Sha $destination; bytes = (Get-Item -LiteralPath $destination).Length }
  }
  $info = Get-Content -LiteralPath (Join-Path $source 'info.json') -Raw | ConvertFrom-Json
  Assert-Full473 (([string]$info.name -ceq $fixtureName) -and ([string]$info.version -ceq $Version)) "fixture identity differs: $Id"
  $archive = Join-Path $fixtureArchives ($fixtureName + '_' + $Version + '.zip')
  $zip = [IO.Compression.ZipFile]::Open($archive, [IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($member in $members | Sort-Object destination) {
      $entry = $zip.CreateEntry($fixtureName + '_' + $Version + '/' + [string]$member.destination, [IO.Compression.CompressionLevel]::Optimal)
      $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
      $input = [IO.File]::Open((Join-Path $source ([string]$member.destination)), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
      $output = $entry.Open()
      try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
    }
  } finally { $zip.Dispose() }
  [pscustomobject][ordered]@{ id = $Id; name = $fixtureName; version = $Version; source_directory = $source; archive = $archive; sha256 = Get-Full473Sha $archive; bytes = (Get-Item -LiteralPath $archive).Length; members = $rows }
}
function New-Full473Observer() {
  Assert-Full473Tree 'tests/fixtures/active-mods-observer' @('tests/fixtures/active-mods-observer/data-final-fixes.lua', 'tests/fixtures/active-mods-observer/info-f200.json', 'tests/fixtures/active-mods-observer/info.json')
  $source = Join-Path $fixtureSources 'active-mods-observer'
  [IO.Directory]::CreateDirectory($source) | Out-Null
  Write-Full473GitBlob $sourceCommit 'tests/fixtures/active-mods-observer/info.json' (Join-Path $source 'info.json')
  Write-Full473GitBlob $sourceCommit 'tests/fixtures/active-mods-observer/data-final-fixes.lua' (Join-Path $source 'data-final-fixes.lua')
  $info = Get-Content -LiteralPath (Join-Path $source 'info.json') -Raw | ConvertFrom-Json
  Assert-Full473 (([string]$info.name -ceq $observerName) -and ([string]$info.version -ceq '0.1.0')) 'observer source identity differs'
  $archive = Join-Path $fixtureArchives ($observerName + '_0.1.0.zip')
  [IO.File]::Copy($observerCanonical, $archive, $false)
  Assert-Full473 ((Get-Full473Sha $archive) -ceq $observerSha) 'contained canonical observer archive differs'
  Assert-MIRLibraryFixtureArchive -Archive $archive -SourceDirectory $source
  [pscustomobject][ordered]@{ name = $observerName; version = '0.1.0'; archive = $archive; sha256 = Get-Full473Sha $archive; bytes = (Get-Item -LiteralPath $archive).Length; source_directory = $source; members = Get-Full473Files $source }
}
function Set-Full473TemporaryArchive([string]$Archive, [Collections.Generic.List[object]]$Journal) {
  $destination = Join-Path $library ([IO.Path]::GetFileName($Archive))
  $expected = Get-Full473Sha $Archive
  $state = [ordered]@{ destination = $destination; expected_sha256 = $expected; prior_exists = (Test-Path -LiteralPath $destination -PathType Leaf); prior_sha256 = $null; prior_snapshot = $null; changed = $false }
  if ($state.prior_exists) {
    $state.prior_sha256 = Get-Full473Sha $destination
    $state.prior_snapshot = Join-Path $snapshotRoot (([IO.Path]::GetFileName($destination)) + '.' + $state.prior_sha256 + '.zip')
    if (-not (Test-Path -LiteralPath $state.prior_snapshot)) { [IO.Directory]::CreateDirectory($snapshotRoot) | Out-Null; [IO.File]::Copy($destination, $state.prior_snapshot, $false) }
    Assert-Full473 ((Get-Full473Sha $state.prior_snapshot) -ceq $state.prior_sha256) 'prior owned archive snapshot differs'
  }
  $Journal.Add($state)
  if ((-not $state.prior_exists) -or ($state.prior_sha256 -cne $expected)) { $state.changed = $true; [IO.File]::Copy($Archive, $destination, $true) }
  Assert-Full473 ((Get-Full473Sha $destination) -ceq $expected) 'temporary owned archive differs after staging'
  [pscustomobject]$state
}
function Restore-Full473TemporaryArchive($State) {
  if (-not $State.changed) { return [ordered]@{ destination = $State.destination; action = 'unchanged'; sha256 = Get-Full473Sha $State.destination } }
  if ($State.prior_exists) {
    Assert-Full473 ((Get-Full473Sha $State.prior_snapshot) -ceq $State.prior_sha256) 'prior owned archive snapshot differs before restore'
    [IO.File]::Copy($State.prior_snapshot, $State.destination, $true)
    Assert-Full473 ((Get-Full473Sha $State.destination) -ceq $State.prior_sha256) 'prior owned archive differs after restore'
    return [ordered]@{ destination = $State.destination; action = 'restored-prior'; sha256 = $State.prior_sha256 }
  }
  Assert-Full473 ((Get-Full473Sha $State.destination) -ceq $State.expected_sha256) 'temporary owned archive differs before removal'
  Remove-Item -LiteralPath $State.destination -Force
  Assert-Full473 (-not (Test-Path -LiteralPath $State.destination)) 'temporary owned archive remains after removal'
  [ordered]@{ destination = $State.destination; action = 'removed-temporary'; sha256 = $State.expected_sha256 }
}
function Test-Full473NativeRestoration($Result) {
  if ($null -eq $Result) { return $false }
  $restoration = if ($Result -is [Collections.IDictionary]) { $Result['library_control_restoration'] } else { $Result.library_control_restoration }
  if ($null -eq $restoration) { return $false }
  $status = if ($restoration -is [Collections.IDictionary]) { [string]$restoration['status'] } else { [string]$restoration.status }
  $status -ceq 'restored-direct-library-controls'
}
function Test-Full473Close([object]$Value, [double]$Expected) {
  ($Value -is [double]) -and ([Math]::Abs(([double]$Value) - $Expected) -le 0.000001)
}
function Assert-Full473Profile([hashtable]$Profile, [string]$Stage, [string]$ProfileName) {
  Assert-Full473 (([string]$Profile.engine.version -ceq '2.1.23') -and ([string]$Profile.engine.sha256 -ceq $engineSha)) "profile engine differs: $ProfileName/$Stage"
  $expectedPlayer = if ($Stage -ceq 'published') { $publishedSha } else { $candidateSha }
  $playerName = if ($Stage -ceq 'published') { 'more-infinite-research_4.7.21003.zip' } else { 'more-infinite-research_5.0.21000.zip' }
  Assert-Full473 (([string]$Profile.archive_sha256[$playerName] -ceq $expectedPlayer) -and ([string]$Profile.archive_sha256['mir-fixture-mir5-active-mods-observer_0.1.0.zip'] -ceq $observerSha)) "profile archive binding differs: $ProfileName/$Stage"
  $fixtureVersion = if ($Stage -ceq 'published') { '0.1.0' } else { '0.2.0' }
  $fixtureRows = @($Profile.mods | Where-Object { ([string]$_.name -ceq $fixtureName) -and [bool]$_.enabled })
  Assert-Full473 (($fixtureRows.Count -eq 1) -and ([string]$fixtureRows[0].version -ceq $fixtureVersion)) "profile fixture binding differs: $ProfileName/$Stage"
}
function Assert-Full473Result($Result, [string]$Stage, [string]$ProfileName) {
  Assert-Full473 (($null -ne $Result) -and ([string]$Result.status -ceq 'passed-private-native-fixture') -and ([string]$Result.case -ceq 'full-catalogue-upgrade')) "native status differs: $ProfileName/$Stage"
  Assert-Full473 (([string]$Result.source_head -ceq $sourceCommit) -and ($Result.source_dirty -is [bool]) -and (-not [bool]$Result.source_dirty)) "native source identity differs: $ProfileName/$Stage"
  Assert-Full473 (([string]$Result.engine.sha256 -ceq $engineSha) -and ([string]$Result.engine.base_version -ceq '2.1.23')) "native engine differs: $ProfileName/$Stage"
  $expectedPlayer = if ($Stage -ceq 'published') { $publishedSha } else { $candidateSha }
  Assert-Full473 (([string]$Result.mir_archive.sha256 -ceq $expectedPlayer) -and ([string]$Result.active_mods_observer.sha256 -ceq $observerSha) -and (Test-Full473NativeRestoration $Result)) "native archive, observer, or direct-library restoration differs: $ProfileName/$Stage"
  Assert-Full473 (([string]$Result.initial.stage -ceq 'initial') -and ([string]$Result.initial.status -ceq 'passed') -and ([string]$Result.initial.profile -ceq $ProfileName)) "initial fixture marker differs: $ProfileName/$Stage"
  $witness = $Result.initial.witnesses
  $expectedOwners = if ($ProfileName -ceq 'base') { 0 } else { 5 }
  Assert-Full473 (($null -ne $witness) -and ($witness.public_rows -gt 0) -and ($witness.level_backed_rows -eq $witness.public_rows) -and ($witness.native_owner_rows -eq $expectedOwners) -and (Test-Full473Close $witness.queued_progress .42) -and (Test-Full473Close $witness.paused_progress .27) -and ([string]$witness.save_name -ceq 'mir5-native-complete')) "complete catalogue, native-owner, queue, or detached-force witness differs: $ProfileName/$Stage"
  $expectedSuccessorLabs = if ($Stage -ceq 'published') { 0 } else { 1 }
  Assert-Full473 (($witness.source_gear_lab -eq 1) -and ($witness.successor_gear_lab -eq $expectedSuccessorLabs)) "gear-lab witness differs: $ProfileName/$Stage"
  if ($Stage -ceq 'mir5') { Assert-Full473 ($Result.input_save_byte_identical -eq $true) "successor changed protected published save: $ProfileName" }
  Assert-Full473 (@($Result.reloads).Count -eq 2) "cold reload count differs: $ProfileName/$Stage"
  foreach ($reload in @($Result.reloads)) { Assert-Full473 (($reload.save_byte_identical -eq $true) -and ([string]$reload.result.stage -ceq 'reload') -and ([string]$reload.result.status -ceq 'passed') -and ($reload.result.witnesses.on_load_read_only -eq $true)) "cold reload witness differs: $ProfileName/$Stage" }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$library = (Resolve-Path -LiteralPath $ArchiveLibrary).Path
$engine = (Resolve-Path -LiteralPath $FactorioBin).Path
$candidate = (Resolve-Path -LiteralPath $CandidateArchive).Path
$observerCanonical = (Resolve-Path -LiteralPath $CanonicalObserverArchive).Path
$out = [IO.Path]::GetFullPath($OutputRoot)
$recovery = [IO.Path]::GetFullPath($RecoveryRoot)
$controllerSha = Get-Full473Sha $PSCommandPath
$started = [DateTime]::UtcNow
$deadline = $started.AddMinutes(30)
$archiveStates = [Collections.Generic.List[object]]::new()
$archiveRestoration = @()
$snapshotRoot = Join-Path $recovery 'preexisting-library-archives'
$results = @()
$failure = $null
$failedStage = $null
$custody = $null
function Assert-Full473Budget([int]$MinimumSeconds) {
  $remaining = [int][Math]::Floor(($deadline - [DateTime]::UtcNow).TotalSeconds)
  Assert-Full473 ($remaining -ge $MinimumSeconds) "assignment cannot start the next native stage within the declared 30-minute cap (remaining=$remaining seconds)"
}

$actualHead = ([string](& git -C $repo rev-parse HEAD)).Trim()
$actualSourceTree = ([string](& git -C $repo rev-parse 'HEAD:source')).Trim()
$actualStatus = (@(& git -C $repo status --porcelain=v1) -join "`n").Trim()
Assert-Full473 ($actualHead -ceq $sourceCommit) 'frozen source commit differs'
Assert-Full473 ($actualSourceTree -ceq $sourceTree) 'frozen player source tree differs'
Assert-Full473 ([string]::IsNullOrWhiteSpace($actualStatus)) 'frozen source worktree is dirty'
Assert-Full473 (Test-Full473Under (Join-Path $repo 'build/tmp') $out) 'OutputRoot must remain beneath executing checkout build/tmp'
Assert-Full473 (-not (Test-Path -LiteralPath $out)) 'OutputRoot already exists'
Assert-Full473 (-not (Test-Path -LiteralPath $recovery)) 'RecoveryRoot already exists'
Assert-Full473 ((Get-Full473Sha $engine) -ceq $engineSha) 'F210 executable hash differs'
$baseInfo = Join-Path (Get-Item -LiteralPath $engine).Directory.Parent.Parent.FullName 'data/base/info.json'
Assert-Full473 ([string]((Get-Content -LiteralPath $baseInfo -Raw | ConvertFrom-Json).version) -ceq '2.1.23') 'F210 base version differs'
Assert-Full473 ((Get-Full473Sha $candidate) -ceq $candidateSha) 'external current8F candidate archive differs'
Assert-Full473 ((Get-Full473Sha $observerCanonical) -ceq $observerSha) 'canonical observer container differs'
Assert-Full473 ((Get-Item -LiteralPath $observerCanonical).Length -eq 835) 'canonical observer byte length differs'
Assert-Full473LibraryIdle $library
Use-Full473LibraryLock $library { Assert-Full473LibraryIdle $library; return $null } | Out-Null

$profiles = [ordered]@{
  base = [ordered]@{
    published = [ordered]@{ path = Join-Path $repo 'tests/profiles/full-catalogue-upgrade-published-4.7.3-base-f210-2123.json'; sha256 = '0A2F198FC98E543291FF6A42702C10FA9A77F5A7CC6404CA56F1CBCF5244F4CE' }
    mir5 = [ordered]@{ path = Join-Path $repo 'tests/profiles/full-catalogue-upgrade-mir5-from-4.7.3-base-f210-2123.json'; sha256 = 'A35007741F2A141CF4AC02A0949ED2D01E34FF86DA370325E96B4362CE786228' }
  }
  'space-age' = [ordered]@{
    published = [ordered]@{ path = Join-Path $repo 'tests/profiles/full-catalogue-upgrade-published-4.7.3-space-age-f210-2123.json'; sha256 = 'C0EB75E9A1043CC1F46832986BF21953B7E6C670028B792C2EFAD79F12BA0C1F' }
    mir5 = [ordered]@{ path = Join-Path $repo 'tests/profiles/full-catalogue-upgrade-mir5-from-4.7.3-space-age-f210-2123.json'; sha256 = 'AF87E9036BE75D171F26F64D4826015FA7DE30481DE4C08631D94B857012F33B' }
  }
}
foreach ($profileName in @('base', 'space-age')) {
  foreach ($stageName in @('published', 'mir5')) {
    $entry = $profiles[$profileName][$stageName]
    Assert-Full473 ((Get-Full473Sha $entry.path) -ceq $entry.sha256) "profile hash differs: $profileName/$stageName"
    $entry['data'] = Get-Content -LiteralPath $entry.path -Raw | ConvertFrom-Json -AsHashtable
    Assert-Full473Profile $entry['data'] $stageName $profileName
  }
}
$publishedArchive = Join-Path $library 'more-infinite-research_4.7.21003.zip'
$candidateLibrary = Join-Path $library 'more-infinite-research_5.0.21000.zip'
Assert-Full473 ((Get-Full473Sha $publishedArchive) -ceq $publishedSha) 'direct library published4.7.3 archive differs'
Assert-Full473 ((Get-Full473Sha $candidateLibrary) -ceq $restoreCandidateSha) 'direct library does not retain C563 before current8F adoption'

[IO.Directory]::CreateDirectory($recovery) | Out-Null
$health = & (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -RepoRoot $repo -MaxScanSeconds 2 -MaxEntriesPerRoot 500 -AsJson
Write-Full473Json (Join-Path $recovery 'workspace-health-before.json') ($health | ConvertFrom-Json -AsHashtable)
$fixtureInputRoot = [IO.Path]::GetFullPath($out + '.fixture-inputs')
Assert-Full473 (Test-Full473Under (Join-Path $repo 'build/tmp') $fixtureInputRoot) 'fixture input staging must remain under executing checkout build/tmp'
Assert-Full473 (-not (Test-Path -LiteralPath $fixtureInputRoot)) 'fixture input staging already exists'
[IO.Directory]::CreateDirectory($fixtureInputRoot) | Out-Null
$fixtureSources = Join-Path $fixtureInputRoot 'fixture-sources'
$fixtureArchives = Join-Path $fixtureInputRoot 'fixture-archives'
[IO.Directory]::CreateDirectory($fixtureSources) | Out-Null
[IO.Directory]::CreateDirectory($fixtureArchives) | Out-Null
. (Join-Path $repo 'tools/lib/validation/ImmutableInputStaging.ps1')
. (Join-Path $repo 'tools/lib/compatibility/LibraryActivation.ps1')
Assert-Full473Tree 'tests/fixtures/full-catalogue-upgrade/shared' @('tests/fixtures/full-catalogue-upgrade/shared/control.lua', 'tests/fixtures/full-catalogue-upgrade/shared/data-final-fixes.lua', 'tests/fixtures/full-catalogue-upgrade/shared/f210-catalogue.lua')
$fixtures = [ordered]@{
  published = New-Full473Fixture 'published-4.7.3' 'tests/fixtures/full-catalogue-upgrade/f210/published-4.7.3' '0.1.0'
  mir5 = New-Full473Fixture 'mir5-from-4.7.3' 'tests/fixtures/full-catalogue-upgrade/f210/mir5-from-4.7.3' '0.2.0'
}
$observer = New-Full473Observer
Assert-Full473 (-not (Test-Path -LiteralPath $out)) 'native output was occupied during fixture composition'
$preflight = [ordered]@{
  schema = 1; kind = 'MIR5FullCatalogue473Current8FQualificationV1'; status = 'prepared'; controller_sha256 = $controllerSha; source_head = $sourceCommit; source_tree = $sourceTree; source_clean = $true
  assignment_started_utc = $started.ToString('o'); assignment_deadline_utc = $deadline.ToString('o')
  limits = [ordered]@{ total_seconds = 1800; serial_process_max = 16; per_stage_timeout_seconds = 300; expected_peak_mib = 6144; aggregate_max_output_mib = 4096; admission_wait_seconds = 30 }
  engine = [ordered]@{ path = $engine; sha256 = $engineSha; base_version = '2.1.23' }
  players = [ordered]@{ published = [ordered]@{ path = $publishedArchive; sha256 = $publishedSha }; candidate_external = [ordered]@{ path = $candidate; sha256 = $candidateSha }; candidate_library_before_adoption = [ordered]@{ path = $candidateLibrary; sha256 = Get-Full473Sha $candidateLibrary; restore_sha256 = $restoreCandidateSha } }
  observer = [ordered]@{ canonical_path = $observerCanonical; sha256 = $observerSha; bytes = (Get-Item -LiteralPath $observerCanonical).Length; staged = $observer }
  fixtures = $fixtures; profiles = $profiles; output_root = $out; recovery_root = $recovery
}
$preflight.fixture_input_custody = Copy-Full473Custody $fixtureInputRoot (Join-Path $recovery 'fixture-input-custody')
Write-Full473Json (Join-Path $recovery 'preflight.json') $preflight

try {
  Use-Full473LibraryLock $library {
    Assert-Full473LibraryIdle $library
    Set-Full473TemporaryArchive $candidate $archiveStates | Out-Null
    Set-Full473TemporaryArchive $observer.archive $archiveStates | Out-Null
    Set-Full473TemporaryArchive $fixtures.published.archive $archiveStates | Out-Null
    Set-Full473TemporaryArchive $fixtures.mir5.archive $archiveStates | Out-Null
  } | Out-Null
  $runner = Join-Path $repo 'tools/Invoke-NativeFixture.ps1'
  foreach ($profileName in @('base', 'space-age')) {
    $source = $profiles[$profileName].published
    $failedStage = $profileName + '/published'
    Assert-Full473Budget 300
    $sourceOutput = Join-Path $out ('native/' + $profileName + '/published-4.7.3')
    & $runner -RepoRoot $repo -ArchiveLibrary $library -FactorioBin $engine -ProfilePath $source.path -FixtureSources @($fixtures.published.source_directory, $observer.source_directory) -ExpectedMIRArchiveSha256 $publishedSha -ActiveModsObserver $observerName -CaseName 'full-catalogue-upgrade' -OutputRoot $sourceOutput -ExpectedPeakMemoryMiB 6144 -TimeoutSeconds 300 -AdmissionWaitSeconds 30 | Out-Null
    $sourceResultPath = Join-Path $sourceOutput 'result.json'
    Assert-Full473 (Test-Path -LiteralPath $sourceResultPath -PathType Leaf) "published result is absent: $profileName"
    $sourceResult = Get-Content -LiteralPath $sourceResultPath -Raw | ConvertFrom-Json -AsHashtable
    Assert-Full473Result $sourceResult 'published' $profileName
    $sourceSave = Join-Path $sourceOutput 'write-data/saves/mir5-native-complete.zip'
    Assert-Full473 (Test-Path -LiteralPath $sourceSave -PathType Leaf) "published completed save is absent: $profileName"
    $sourceSaveSha = Get-Full473Sha $sourceSave
    $results += [ordered]@{ profile = $profileName; stage = 'published-4.7.3'; result_path = $sourceResultPath; result_sha256 = Get-Full473Sha $sourceResultPath; save_path = $sourceSave; save_sha256 = $sourceSaveSha }

    $successor = $profiles[$profileName].mir5
    $failedStage = $profileName + '/mir5-from-4.7.3'
    Assert-Full473Budget 300
    $successorOutput = Join-Path $out ('native/' + $profileName + '/mir5-from-4.7.3')
    & $runner -RepoRoot $repo -ArchiveLibrary $library -FactorioBin $engine -ProfilePath $successor.path -FixtureSources @($fixtures.mir5.source_directory, $observer.source_directory) -ExpectedMIRArchiveSha256 $candidateSha -ActiveModsObserver $observerName -CaseName 'full-catalogue-upgrade' -OutputRoot $successorOutput -ExpectedPeakMemoryMiB 6144 -TimeoutSeconds 300 -AdmissionWaitSeconds 30 -InputSavePath $sourceSave -ExpectedInputSaveSha256 $sourceSaveSha | Out-Null
    $successorResultPath = Join-Path $successorOutput 'result.json'
    Assert-Full473 (Test-Path -LiteralPath $successorResultPath -PathType Leaf) "successor result is absent: $profileName"
    $successorResult = Get-Content -LiteralPath $successorResultPath -Raw | ConvertFrom-Json -AsHashtable
    Assert-Full473Result $successorResult 'mir5' $profileName
    $successorSave = Join-Path $successorOutput 'write-data/saves/mir5-native-complete.zip'
    Assert-Full473 (Test-Path -LiteralPath $successorSave -PathType Leaf) "successor completed save is absent: $profileName"
    $successorSaveSha = Get-Full473Sha $successorSave
    Assert-Full473 (@($successorResult.reloads | Where-Object { [string]$_.save_sha256 -ceq $successorSaveSha }).Count -eq 2) "successor reload saves differ: $profileName"
    $results += [ordered]@{ profile = $profileName; stage = 'mir5-from-4.7.3'; result_path = $successorResultPath; result_sha256 = Get-Full473Sha $successorResultPath; input_save_path = $sourceSave; input_save_sha256 = $sourceSaveSha; save_path = $successorSave; save_sha256 = $successorSaveSha }
  }
} catch {
  $failure = $_.Exception.Message
} finally {
  try {
    $archiveRestoration = @(Use-Full473LibraryLock $library {
      Assert-Full473LibraryIdle $library
      foreach ($state in @($archiveStates | Sort-Object destination -Descending)) { Restore-Full473TemporaryArchive $state }
    })
  } catch {
    if ([string]::IsNullOrWhiteSpace($failure)) { $failure = $_.Exception.Message } else { $failure += '; archive restoration: ' + $_.Exception.Message }
  }
}

[int64]$outputBytes = 0
$processCount = 0
if (Test-Path -LiteralPath $out) {
  foreach ($member in @(Get-Full473Files $out)) { $outputBytes += [int64]$member.bytes }
  Assert-Full473 ($outputBytes -le (4096MB)) 'native output exceeds the declared 4096 MiB aggregate cap'
  foreach ($entry in @($results)) {
    $record = Get-Content -LiteralPath $entry.result_path -Raw | ConvertFrom-Json -AsHashtable
    $processCount += @($record.process_runs).Count
  }
  Assert-Full473 ($processCount -le 16) 'native process count exceeds the declared serial maximum'
  $custody = Copy-Full473Custody $out (Join-Path $recovery 'native-output')
}
$withinBudget = ([DateTime]::UtcNow -le $deadline)
$passed = ([string]::IsNullOrWhiteSpace($failure) -and $results.Count -eq 4 -and $withinBudget -and @(Get-Process -Name factorio -ErrorAction SilentlyContinue).Count -eq 0)
$terminal = [ordered]@{
  schema = 1; kind = 'MIR5FullCatalogue473Current8FQualificationV1'; status = if ($passed) { 'passed' } else { 'adverse' }
  controller_sha256 = $controllerSha; source_head = $sourceCommit; source_tree = $sourceTree; source_clean = $true; limits = $preflight.limits
  assignment_started_utc = $started.ToString('o'); assignment_deadline_utc = $deadline.ToString('o'); elapsed_seconds = [Math]::Round(([DateTime]::UtcNow - $started).TotalSeconds, 3); within_assignment_budget = $withinBudget
  failed_stage = $failedStage; failure = $failure; results = $results; native_output_bytes = $outputBytes; native_process_count = $processCount; factorio_processes_after_terminal = @(Get-Process -Name factorio -ErrorAction SilentlyContinue).Count; library_archive_restoration = $archiveRestoration; custody = $custody
}
Write-Full473Json (Join-Path $recovery 'terminal.json') $terminal
[pscustomobject]$terminal
