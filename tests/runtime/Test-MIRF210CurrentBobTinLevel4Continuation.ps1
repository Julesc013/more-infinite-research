# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [Parameter(Mandatory)][string]$FactorioBin,
  [string]$ExactStageRoot = '',
  [string[]]$LocalModLibraryDirs = @(),
  [string]$SettingsPath = '',
  [string]$CandidateZip = '',
  [string]$SourceMaterializationPath = '',
  [string]$OutputRoot = 'build/p/f210-tin-level4',
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB = 0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB = 120,
  [switch]$PrepareOnly,
  [string]$RecoverRun = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Tin([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "[mir-f210-current-bob-tin-level4] $Message" }
}
function Get-TinSha([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function Get-TinRelative([string]$Repo, [string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  $prefix = $Repo.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  Assert-Tin ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) "artifact is outside repository: $full"
  $full.Substring($prefix.Length).Replace('\', '/')
}
function Get-TinArtifact([string]$Repo, [string]$Path, [switch]$AllowExternalInput) {
  $item = Get-Item -LiteralPath $Path -ErrorAction Stop
  Assert-MIRLibraryPath $item.FullName
  [ordered]@{
    path = if ($AllowExternalInput) { $item.FullName } else { Get-TinRelative $Repo $item.FullName }
    path_kind = if ($AllowExternalInput) { 'machine-local-input' } else { 'repository-relative' }
    bytes = [int64]$item.Length
    raw_sha256 = Get-TinSha $item.FullName
  }
}
function Assert-TinPath([string]$Path, [string]$Context) {
  Assert-MIRFactorioPathBudget -Path $Path -Context $Context -MaximumLength 240
}
function Assert-TinRuntimeApiSurface([string]$FixtureControl, [string]$EngineRoot) {
  $docsRoot = Join-Path $EngineRoot 'doc-html/classes'
  $members = @(
    [ordered]@{ file = 'LuaForce.html'; member = 'add_research' },
    [ordered]@{ file = 'LuaForce.html'; member = 'cancel_current_research' },
    [ordered]@{ file = 'LuaForce.html'; member = 'current_research' },
    [ordered]@{ file = 'LuaForce.html'; member = 'research_queue' },
    [ordered]@{ file = 'LuaForce.html'; member = 'recipes' },
    [ordered]@{ file = 'LuaTechnology.html'; member = 'level' },
    [ordered]@{ file = 'LuaTechnology.html'; member = 'researched' },
    [ordered]@{ file = 'LuaTechnology.html'; member = 'research_recursive' },
    [ordered]@{ file = 'LuaRecipe.html'; member = 'productivity_bonus' }
  )
  foreach ($item in $members) {
    $path = Join-Path $docsRoot ([string]$item.file)
    Assert-Tin (Test-Path -LiteralPath $path -PathType Leaf) "installed runtime API page is absent: $($item.file)"
    $html = [IO.File]::ReadAllText($path)
    Assert-Tin ($html.Contains(('id="' + [string]$item.member + '"'), [StringComparison]::Ordinal)) "installed runtime API member is absent: $($item.file)#$($item.member)"
  }
  $control = [IO.File]::ReadAllText($FixtureControl)
  Assert-Tin (-not $control.Contains('get_recipe_productivity_bonus', [StringComparison]::Ordinal)) 'fixture still calls unsupported LuaForce productivity accessor'
  Assert-Tin ($control.Contains('force.recipes[recipe_name]', [StringComparison]::Ordinal) -and $control.Contains('recipe.productivity_bonus', [StringComparison]::Ordinal)) 'fixture does not use the documented force recipe productivity bonus'
}
function Read-TinCurrentCandidate([string]$Repository, [string]$Archive, [string]$ReceiptPath) {
  Read-MIRNativeProbeF210CurrentCandidate -Repository $Repository -Archive $Archive -ReceiptPath $ReceiptPath
}
function Read-TinDirectLibraryInputs {
  param([string]$Library,[Collections.IDictionary]$ExpectedArchives,$Candidate,[string]$FixtureRoot,[string]$EngineVersion,[string[]]$OfficialMods)
  Assert-MIRLibraryPath $Library
  $hashes=[ordered]@{}
  $rows=@(foreach($name in $OfficialMods){[ordered]@{name=$name;version=$EngineVersion;enabled=$true}})
  foreach($entry in $ExpectedArchives.GetEnumerator()){
    Assert-Tin ($entry.Key -ceq ($entry.Value.name+'_'+$entry.Value.version+'.zip')) 'dependency filename differs from its identity'
    $hashes[$entry.Key]=[string]$entry.Value.sha256
    $rows+=[ordered]@{name=$entry.Value.name;version=$entry.Value.version;enabled=$true}
  }
  # The existing resolver takes filename -> SHA-256, not full identity objects.
  $null=Resolve-MIRNativeProbeDependencyInputs -ExpectedArchives $hashes -LocalModLibraryDirs @($Library)
  $candidateName=[IO.Path]::GetFileName([string]$Candidate.path)
  $candidatePath=Join-Path $Library $candidateName
  Assert-Tin (Test-Path -LiteralPath $candidatePath -PathType Leaf) 'install-selected-candidate-once-in-library'
  Assert-MIRLibraryPath $candidatePath
  $candidateSha=Get-TinSha $Candidate.path
  Assert-Tin ((Get-TinSha $candidatePath) -ceq $candidateSha) 'library candidate bytes differ'
  $hashes[$candidateName]=$candidateSha
  $rows+=[ordered]@{name='more-infinite-research';version=$Candidate.receipt.distribution_version;enabled=$true}
  $fixtureInfo=Get-Content -LiteralPath (Join-Path $FixtureRoot 'info.json') -Raw|ConvertFrom-Json
  $fixtureName=$fixtureInfo.name+'_'+$fixtureInfo.version+'.zip'
  $fixtureArchive=Join-Path $Library $fixtureName
  Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $FixtureRoot
  $hashes[$fixtureName]=Get-TinSha $fixtureArchive
  $rows+=[ordered]@{name=$fixtureInfo.name;version=$fixtureInfo.version;enabled=$true}
  return [pscustomobject]@{mod_list=[ordered]@{mods=$rows};archive_hashes=$hashes;candidate=$candidatePath;fixture_archive=$fixtureArchive}
}
function Invoke-TinGovernedEngine([string]$Scenario, [string[]]$Arguments, [int]$TimeoutSeconds) {
  $safe = Get-MIRSafeScenarioFileName -Name $Scenario
  Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $Arguments
  $actor = Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
  $stdout = Join-Path $run ($safe+'.stdout.log'); $stderr = Join-Path $run ($safe+'.stderr.log')
  Copy-Item -LiteralPath $actor.stdout -Destination $stdout
  Copy-Item -LiteralPath $actor.stderr -Destination $stderr
  $factorioLog = Join-Path $run ($safe+'.factorio.log')
  $captured = Copy-MIRCompatFactorioCurrentLog -UserDataDir $run -Destination $factorioLog
  $null = Get-MIRNativeProbeRemainingOutputBytes -Context $resources
  Assert-Tin (-not [string]::IsNullOrWhiteSpace($captured)) 'native Factorio log is absent'
  $null=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $captured
  return [pscustomobject]@{passed=$true;exit_code=0;timed_out=$false;duration_seconds=$actor.result.duration_seconds;stdout=$stdout;stderr=$stderr;factorio_log=$captured}
}
function Invoke-TinBoundedReload {
  param(
    [string]$Factorio,
    [string]$RunRoot,
    [string]$Scenario,
    [string]$SavePath,
    [int]$Ticks,
    [int]$TimeoutSeconds
  )
  $safe = Get-MIRSafeScenarioFileName -Name $Scenario
  $save = (Resolve-Path -LiteralPath $SavePath).Path
  $inputSha = Get-TinSha $save
  $stdout = Join-Path $RunRoot ($safe + '.reload.stdout.log')
  $stderr = Join-Path $RunRoot ($safe + '.reload.stderr.log')
  $factorioLog = Join-Path $RunRoot ($safe + '.reload.factorio.log')
  $currentLog = Join-Path $RunRoot 'factorio-current.log'
  if (Test-Path -LiteralPath $currentLog) { Remove-Item -LiteralPath $currentLog -Force }
  $arguments = @(
    '--config', (Join-Path $RunRoot 'mir-compat-config.ini'),
    '--no-log-rotation',
    '--disable-audio',
    '--mod-directory', $activation.library,
    '--benchmark', $save,
    '--benchmark-ticks', [string]$Ticks,
    '--benchmark-runs', '1',
    '--benchmark-sanitize'
  )
  $process = Invoke-TinGovernedEngine -Scenario ($safe+'.reload') -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
  $captured = $process.factorio_log
  $saveSha = Get-TinSha $save
  [pscustomobject]@{
    passed = [bool]($process.passed -and $process.duration_seconds -le $TimeoutSeconds -and $inputSha -ceq $saveSha -and -not [string]::IsNullOrWhiteSpace($captured))
    exit_code = $process.exit_code
    timed_out = $process.timed_out
    duration_seconds = $process.duration_seconds
    maximum_duration_seconds = $TimeoutSeconds
    benchmark_ticks = $Ticks
    input_save_sha256 = $inputSha
    save_sha256 = $saveSha
    save_byte_identical = [bool]($inputSha -ceq $saveSha)
    stdout = $stdout
    stderr = $stderr
    factorio_log = $captured
  }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
if ($ExactStageRoot -or $RecoverRun) {
  throw '[mir-tin-obsolete-runner-mode] Populated-stage recovery is retired. Preserve its original receipt and pinned source; use an explicit library for a fresh run.'
}
$output = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($OutputRoot)) {$OutputRoot} else {Join-Path $repo $OutputRoot}))
$buildPrefix = [IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
Assert-Tin ($output.StartsWith($buildPrefix, [StringComparison]::OrdinalIgnoreCase)) 'output root must be inside build'
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')

& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
$resources = New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB

$fixtureRoot = Join-Path $repo 'fixtures/assert-f210-current-bob-tin-level4-continuation'
$dossierPath = Join-Path $fixtureRoot 'continuation-dossier.json'
foreach ($name in @('info.json', 'continuation-dossier.json', 'data-final-fixes.lua', 'control.lua')) {
  Assert-Tin (Test-Path -LiteralPath (Join-Path $fixtureRoot $name) -PathType Leaf) "fixture is incomplete: $name"
}
$dossier = Get-Content -Raw -LiteralPath $dossierPath | ConvertFrom-Json -ErrorAction Stop
Assert-Tin ([string]$dossier.kind -ceq 'MIR4F210CurrentBobTinLevelFourContinuationV1') 'fixture dossier identity differs'
Assert-Tin ([string]$dossier.technology.legacy -ceq 'recipe-prod-research_material_tin-1') 'fixture dossier legacy technology differs'
Assert-Tin ([string]$dossier.technology.continuation -ceq 'recipe-prod-research_material_tin-4') 'fixture dossier continuation technology differs'
Assert-Tin ([int]$dossier.technology.legacy_completed_levels -eq 3 -and [int]$dossier.technology.continuation_first_level -eq 4) 'fixture dossier level boundary differs'
Assert-Tin ([double]$dossier.technology.bonus_after_level_four -eq 0.08 -and [int]$dossier.manufacturing_witness.expected_output_after_level_four -eq 108) 'fixture dossier quantitative witness differs'

$expectedEngineSha = [string]$dossier.target.engine_sha256
$expectedSettingsSha = [string]$dossier.target.stage_settings_sha256
$expectedArchives = [ordered]@{}
foreach ($archive in @($dossier.target.archives)) {
  $expectedArchives[[string]$archive.file] = [ordered]@{ name = [string]$archive.name; version = [string]$archive.version; sha256 = [string]$archive.sha256 }
}
Assert-Tin ($expectedArchives.Count -eq 5) 'fixture dossier archive closure differs'
$changes = @(& git -C $repo status --porcelain --untracked-files=all)
Assert-Tin ($changes.Count -eq 0) "qualification requires a clean worktree: $($changes -join '; ')"
$engine = (Resolve-Path -LiteralPath $FactorioBin).Path
Assert-MIRLibraryPath $engine
$engineRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $engine))
Assert-Tin ((Get-TinSha $engine) -ceq $expectedEngineSha) 'engine differs from the retained 2.1.20 proof; this input needs a fresh engine-specific observation'
Assert-TinRuntimeApiSurface (Join-Path $fixtureRoot 'control.lua') $engineRoot
Assert-Tin ($LocalModLibraryDirs.Count -eq 1) 'supply exactly one explicit flat archive library'
$library=(Resolve-Path -LiteralPath $LocalModLibraryDirs[0]).Path
$candidateInput = Read-TinCurrentCandidate -Repository $repo -Archive $CandidateZip -ReceiptPath $SourceMaterializationPath
$candidate = $candidateInput.path
$direct=Read-TinDirectLibraryInputs -Library $library -ExpectedArchives $expectedArchives -Candidate $candidateInput -FixtureRoot $fixtureRoot -EngineVersion $dossier.target.factorio_version -OfficialMods $dossier.target.official_mods
Assert-Tin (-not [string]::IsNullOrWhiteSpace($SettingsPath)) 'supply the small retained settings file separately from immutable archives'
$stageSettings = (Resolve-Path -LiteralPath $SettingsPath).Path
Assert-Tin ((Get-TinSha $stageSettings) -ceq $expectedSettingsSha) 'selected Bob settings bytes differ'
$sourceCommit = (& git -C $repo rev-parse HEAD).Trim()
$sourceTree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
Assert-Tin ($sourceCommit -match '^[0-9a-f]{40}$' -and $sourceTree -match '^[0-9a-f]{40}$') 'source Git identity is invalid'
$prepared = [ordered]@{
  schema = 2
  kind = 'MIR4F210CurrentBobTinLevelFourContinuationV2'
  status = 'prepared'
  scope = [string]$dossier.scope
  source = [ordered]@{ commit = $sourceCommit; tree = $sourceTree; package_source_sha256 = Get-TinSha (Join-Path $repo 'source/package-source.json') }
  exact_stage = [ordered]@{ path = $null; engine_sha256 = $expectedEngineSha; settings_sha256 = $expectedSettingsSha; archives = $expectedArchives; input_mode='direct-library'; library=$library }
  materialization = Get-TinArtifact $repo (Resolve-Path -LiteralPath $SourceMaterializationPath).Path
  candidate = Get-TinArtifact $repo $candidate -AllowExternalInput
  fixture = @('info.json', 'continuation-dossier.json', 'data-final-fixes.lua', 'control.lua' | ForEach-Object { Get-TinArtifact $repo (Join-Path $fixtureRoot $_) })
  harness = Get-TinArtifact $repo $PSCommandPath
  non_claims = @($dossier.explicit_non_claims)
}
if ($PrepareOnly) {
  $prepared | ConvertTo-Json -Depth 30
  return
}

$run = $resources.root
Assert-TinPath $run 'F210 Bob Tin level-four run root'
$activation = $null
try {
  New-Item -ItemType Directory -Force -Path (Join-Path $run 'saves') | Out-Null
  $profilePath=Join-Path $run 'selection.json'
  [IO.File]::WriteAllText($profilePath,($direct.mod_list|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory (Join-Path $engineRoot 'data') -ProfilePath $profilePath -ArchiveHashes $direct.archive_hashes -SettingsMode File -SettingsPath $stageSettings -SettingsSha256 $expectedSettingsSha
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  $modListPath=Join-Path $run 'active-mod-list.json'
  [IO.File]::WriteAllBytes($modListPath,$activation.mod_list_bytes)
  $enabled=@($activation.selected.name)
  $fixtureArchive=$direct.fixture_archive
  $initialSettingsPath=Join-Path $run 'initial-mod-settings.dat'
  Copy-Item -LiteralPath (Join-Path $library 'mod-settings.dat') -Destination $initialSettingsPath
  $initialSettings=Get-TinArtifact $repo $initialSettingsPath
  Assert-Tin ($initialSettings.raw_sha256 -ceq $expectedSettingsSha) 'activated Bob settings differ before create'
  $config = Join-Path $run 'mir-compat-config.ini'
  [IO.File]::WriteAllText($config,"[path]`nread-data=$(Join-Path $engineRoot 'data')`nwrite-data=$run`n`n[general]`nlocale=auto`n`n[other]`nenable-new-mods=false`nenable-steam-networking=false`ndisable-blueprint-storage=true`n",[Text.UTF8Encoding]::new($false))
  $versionActor = Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments @('--version') -TimeoutSeconds 10
  $version = Get-Content -LiteralPath $versionActor.stdout -Raw
  Assert-Tin ($version -match 'Version:\s+2[.]1[.]20(?:\s|$)') 'requires Factorio 2.1.20'
  $save = Join-Path $run 'saves/f210-current-bob-tin-level4.zip'
  $load = Invoke-TinGovernedEngine -Scenario 'f210-current-bob-tin-level4' -Arguments @('--config',$config,'--no-log-rotation','--create',$save,'--mod-directory',$library,'--disable-audio') -TimeoutSeconds 240
  $load | Add-Member -NotePropertyName save -NotePropertyValue $save
  Assert-Tin (Test-Path -LiteralPath $save -PathType Leaf) 'fresh create save is absent'
  Assert-Tin ([bool]$load.passed -and -not [bool]$load.timed_out -and [int]$load.exit_code -eq 0) 'fresh create failed'
  $freshLog = [IO.File]::ReadAllText([string]$load.factorio_log)
  $dataMarker = '[mir-f210-current-bob-tin-level4] DATA PASS early=recipe-prod-research_material_tin-1:1:3 continuation=recipe-prod-research_material_tin-4:4:infinite prerequisite=true'
  $createMarker = '[mir-f210-current-bob-tin-level4] CREATE PASS legacy-levels=3 continuation-start=4 continuation-next=5 bonus-before=0.06 bonus-after=0.08 research-action=add_research-to-level-and-finite-researched science-lab=accepted'
  Assert-Tin ($freshLog.Contains($dataMarker, [StringComparison]::Ordinal)) 'fresh data continuation marker is absent'
  Assert-Tin ($freshLog.Contains($createMarker, [StringComparison]::Ordinal)) 'fresh level-four quantitative research marker is absent'
  $reload = Invoke-TinBoundedReload -Factorio $engine -RunRoot $run -Scenario 'f210-current-bob-tin-level4' -SavePath $load.save -Ticks 30000 -TimeoutSeconds 240
  Assert-Tin ([bool]$reload.passed) 'bounded reload failed'
  $reloadLog = [IO.File]::ReadAllText([string]$reload.factorio_log)
  $reloadMarker = '[mir-f210-current-bob-tin-level4] RELOAD PASS continuation-next=5 output=108 bonus=0.08 continuity=true'
  Assert-Tin ($reloadLog.Contains($dataMarker, [StringComparison]::Ordinal)) 'reload data continuation marker is absent'
  Assert-Tin ($reloadLog.Contains($reloadMarker, [StringComparison]::Ordinal)) 'reload quantitative production marker is absent'

  Assert-Tin ((Get-TinSha $engine) -ceq $expectedEngineSha -and (& git -C $repo rev-parse HEAD).Trim() -ceq $sourceCommit -and @(& git -C $repo status --porcelain --untracked-files=all).Count -eq 0) 'engine or source changed during the run'
  $candidateArtifact=Get-TinArtifact $repo $direct.candidate -AllowExternalInput
  $fixtureArtifact=Get-TinArtifact $repo $fixtureArchive -AllowExternalInput
  $finalSettingsPath=Join-Path $run 'final-mod-settings.dat'
  Copy-Item -LiteralPath (Join-Path $library 'mod-settings.dat') -Destination $finalSettingsPath
  $terminal=Complete-MIRLibraryActivation -Activation $activation
  $activation=$null
  $result = $prepared
  $result.status = 'passed'
  $result.engine = [ordered]@{ version = ([regex]::Match($version, 'Version:\s+[^\r\n]+').Value).Trim(); executable_sha256 = Get-TinSha $engine }
  $result.run_root = Get-TinRelative $repo $run
  $result.fresh_create = [ordered]@{ passed = $load.passed; duration_seconds = $load.duration_seconds; save = Get-TinArtifact $repo $load.save; stdout = Get-TinArtifact $repo $load.stdout; stderr = Get-TinArtifact $repo $load.stderr; factorio_log = Get-TinArtifact $repo $load.factorio_log }
  $result.reload = [ordered]@{ passed = $reload.passed; duration_seconds = $reload.duration_seconds; maximum_duration_seconds = $reload.maximum_duration_seconds; benchmark_ticks = $reload.benchmark_ticks; input_save_sha256 = $reload.input_save_sha256; save_sha256 = $reload.save_sha256; save_byte_identical = $reload.save_byte_identical; stdout = Get-TinArtifact $repo $reload.stdout; stderr = Get-TinArtifact $repo $reload.stderr; factorio_log = Get-TinArtifact $repo $reload.factorio_log }
  $result.mod_closure = [ordered]@{
    enabled_mods = $enabled
    candidate = $candidateArtifact
    settings = [ordered]@{ source_sha256 = $expectedSettingsSha; initial = $initialSettings; after_engine = Get-TinArtifact $repo $finalSettingsPath }
    fixture = $fixtureArtifact
    mod_list = Get-TinArtifact $repo $modListPath
    library_activation = $terminal
  }
  $resultPath = Join-Path $run 'result.json'
  $result['resource_runs'] = $resources.runs.ToArray()
  Write-MIRNativeProbeResult -Context $resources -Record $result
  Write-Output "[MIR-F210-CURRENT-BOB-TIN-LEVEL4] $(Get-TinRelative $repo $resultPath)"
} catch {
  $failure = $_
  $cleanup=$null
  if ($null -ne $activation -and -not $activation.closed) {
    try {$cleanup=Complete-MIRLibraryActivation -Activation $activation; $activation=$null}
    catch {$cleanup=@{status='recovery-required';library=$activation.library;error=$_.Exception.Message}}
  }
  try { Write-MIRNativeProbeResult -Context $resources -Record ([ordered]@{schema=2;status='failed';scope=$dossier.scope;failure=$failure.Exception.Message;library_activation=$cleanup;resource_runs=$resources.runs.ToArray();qualification=$false;publication=$false}) }
  catch {Write-Warning "Tin failure receipt exceeded its remaining budget; retained ledgers are in $run."}
  throw $failure
}
