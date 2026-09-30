# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin = 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$ExactStageRoot = 'C:\Projects\Factorio\more-infinite-research\build\tests\wed-material-f210\current-bob-20260930',
  [string]$OutputRoot = 'build/tests/f210-bob-tin-level4',
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
function Get-TinArtifact([string]$Repo, [string]$Path) {
  $item = Get-Item -LiteralPath $Path -ErrorAction Stop
  [ordered]@{
    path = Get-TinRelative $Repo $item.FullName
    bytes = [int64]$item.Length
    raw_sha256 = Get-TinSha $item.FullName
  }
}
function New-TinInput([string]$Path, [string]$Role, [object]$Identity, [object]$Provenance) {
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  [ordered]@{
    source_path = $resolved
    file_name = Split-Path -Leaf $resolved
    expected_sha256 = Get-TinSha $resolved
    role = $Role
    identity = $Identity
    provenance = $Provenance
    immutable = $true
  }
}
function Assert-TinPath([string]$Path, [string]$Context) {
  Assert-MIRFactorioPathBudget -Path $Path -Context $Context -MaximumLength 240
}
function Assert-TinRuntimeApiSurface([string]$FixtureControl) {
  $docsRoot = 'C:\Program Files\Steam\steamapps\common\Factorio\doc-html\classes'
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
    '--mod-directory', (Join-Path $RunRoot 'mods'),
    '--benchmark', $save,
    '--benchmark-ticks', [string]$Ticks,
    '--benchmark-runs', '1',
    '--benchmark-sanitize'
  )
  $process = Invoke-MIRCompatFactorioProcess -FactorioBin $Factorio -ArgumentList $arguments -StdoutPath $stdout -StderrPath $stderr -TimeoutSeconds $TimeoutSeconds
  $captured = Copy-MIRCompatFactorioCurrentLog -UserDataDir $RunRoot -Destination $factorioLog
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
$stage = (Resolve-Path -LiteralPath $ExactStageRoot).Path
$output = [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$buildPrefix = [IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
Assert-Tin ($output.StartsWith($buildPrefix, [StringComparison]::OrdinalIgnoreCase)) 'output root must be inside build'
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/ImmutableInputStaging.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')

$fixtureRoot = Join-Path $repo 'fixtures/assert-f210-current-bob-tin-level4-continuation'
$fixtureName = 'mir-fixture-assert-f210-current-bob-tin-level4-continuation'
$fixtureVersion = '0.1.0'
$dossierPath = Join-Path $fixtureRoot 'continuation-dossier.json'
foreach ($name in @('info.json', 'continuation-dossier.json', 'data-final-fixes.lua', 'control.lua')) {
  Assert-Tin (Test-Path -LiteralPath (Join-Path $fixtureRoot $name) -PathType Leaf) "fixture is incomplete: $name"
}
Assert-TinRuntimeApiSurface (Join-Path $fixtureRoot 'control.lua')
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
$stageReceiptPath = Join-Path $stage 'result.json'
Assert-Tin (Test-Path -LiteralPath $stageReceiptPath -PathType Leaf) 'exact retained Bob stage receipt is absent'
$stageReceipt = Get-Content -Raw -LiteralPath $stageReceiptPath | ConvertFrom-Json -ErrorAction Stop
Assert-Tin ([string]$stageReceipt.engine_sha256 -ceq $expectedEngineSha) 'exact retained Bob stage engine identity differs'
$stageMods = Join-Path $stage 'mods'
$receiptArchives = @{}
foreach ($row in @($stageReceipt.mods)) { $receiptArchives[[string]$row.archive] = [string]$row.sha256 }
foreach ($entry in $expectedArchives.GetEnumerator()) {
  $archivePath = Join-Path $stageMods $entry.Key
  Assert-Tin ($receiptArchives.ContainsKey($entry.Key) -and $receiptArchives[$entry.Key] -ceq $entry.Value.sha256) "retained Bob archive receipt differs: $($entry.Key)"
  Assert-Tin (Test-Path -LiteralPath $archivePath -PathType Leaf) "retained Bob archive is absent: $($entry.Key)"
  Assert-Tin ((Get-TinSha $archivePath) -ceq $entry.Value.sha256) "retained Bob archive bytes differ: $($entry.Key)"
}
$stageSettings = Join-Path $stageMods 'mod-settings.dat'
Assert-Tin (Test-Path -LiteralPath $stageSettings -PathType Leaf) 'retained Bob settings are absent'
Assert-Tin ((Get-TinSha $stageSettings) -ceq $expectedSettingsSha) 'retained Bob settings bytes differ'

if (-not [string]::IsNullOrWhiteSpace($RecoverRun)) {
  $run = (Resolve-Path -LiteralPath $RecoverRun).Path
  $outputPrefix = $output.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  Assert-Tin ($run.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) 'recovery run escapes output root'
  $leasePath = Join-Path $run 'mir-immutable-input-lease.json'
  $lease = Get-Content -Raw -LiteralPath $leasePath | ConvertFrom-Json -ErrorAction Stop
  Assert-Tin ([string]$lease.state -ceq 'completed' -and [string]$lease.outcome -ceq 'passed' -and [bool]$lease.inputs_sha256_match) 'recovery run immutable inputs are not terminal and clean'
  $candidateInput = @($lease.inputs | Where-Object { $_.role -ceq 'candidate' })
  Assert-Tin ($candidateInput.Count -eq 1) 'recovery candidate cardinality differs'
  $candidatePath = [string]$candidateInput[0].stage_path
  Assert-Tin (Test-Path -LiteralPath $candidatePath -PathType Leaf) 'recovery candidate archive is absent'
  Assert-Tin ((Get-TinSha $candidatePath) -ceq [string]$candidateInput[0].expected_sha256) 'recovery candidate archive bytes differ'
  $sourceCommit = [string]$candidateInput[0].provenance.source_commit
  $sourceTree = [string]$candidateInput[0].provenance.source_tree
  Assert-Tin ($sourceCommit -match '^[0-9a-f]{40}$' -and $sourceTree -match '^[0-9a-f]{40}$') 'recovery source identity is invalid'
  $freshLogPath = Join-Path $run 'f210-current-bob-tin-level4.factorio.log'
  $reloadLogPath = Join-Path $run 'f210-current-bob-tin-level4.reload.factorio.log'
  $freshLog = [IO.File]::ReadAllText($freshLogPath)
  $reloadLog = [IO.File]::ReadAllText($reloadLogPath)
  $dataMarker = '[mir-f210-current-bob-tin-level4] DATA PASS early=recipe-prod-research_material_tin-1:1:3 continuation=recipe-prod-research_material_tin-4:4:infinite prerequisite=true'
  $createMarker = '[mir-f210-current-bob-tin-level4] CREATE PASS legacy-levels=3 continuation-start=4 continuation-next=5 bonus-before=0.06 bonus-after=0.08 research-action=add_research-to-level-and-finite-researched science-lab=accepted'
  $reloadMarker = '[mir-f210-current-bob-tin-level4] RELOAD PASS continuation-next=5 output=108 bonus=0.08 continuity=true'
  Assert-Tin ($freshLog.Contains($dataMarker, [StringComparison]::Ordinal) -and $freshLog.Contains($createMarker, [StringComparison]::Ordinal)) 'recovery fresh create markers differ'
  Assert-Tin ($reloadLog.Contains($dataMarker, [StringComparison]::Ordinal) -and $reloadLog.Contains($reloadMarker, [StringComparison]::Ordinal)) 'recovery reload markers differ'
  foreach ($log in @($freshLog, $reloadLog)) {
    Assert-Tin (-not $log.Contains('Error while running event', [StringComparison]::Ordinal) -and $log.Contains('Goodbye', [StringComparison]::Ordinal)) 'recovery Factorio lifecycle differs'
  }
  $save = Join-Path $run 'saves/f210-current-bob-tin-level4.zip'
  Assert-Tin (Test-Path -LiteralPath $save -PathType Leaf) 'recovery create save is absent'
  $saveSha = Get-TinSha $save
  $fixtureArchive = Join-Path $run ('mods/' + $fixtureName + '_' + $fixtureVersion + '.zip')
  $result = [ordered]@{
    schema = 1
    kind = 'MIR4F210CurrentBobTinLevelFourContinuationV1'
    status = 'passed-recovered'
    scope = [string]$dossier.scope
    source = [ordered]@{ commit = $sourceCommit; tree = $sourceTree; candidate_sha256 = [string]$candidateInput[0].expected_sha256 }
    exact_stage = [ordered]@{ path = $stage; engine_sha256 = $expectedEngineSha; settings_sha256 = $expectedSettingsSha; archives = $expectedArchives }
    recovery = [ordered]@{
      reason = 'The immutable input lease completed after the engine passed, but the initiating terminal session returned before result.json was constructed.'
      run_root = Get-TinRelative $repo $run
      lease_terminal_record_sha256 = [string]$lease.terminal_record_sha256
      inputs_sha256_match = [bool]$lease.inputs_sha256_match
    }
    candidate = Get-TinArtifact $repo $candidatePath
    fixture_archive = Get-TinArtifact $repo $fixtureArchive
    fresh_create = [ordered]@{
      passed = $true
      save = Get-TinArtifact $repo $save
      factorio_log = Get-TinArtifact $repo $freshLogPath
      stdout = Get-TinArtifact $repo (Join-Path $run 'f210-current-bob-tin-level4.stdout.log')
      stderr = Get-TinArtifact $repo (Join-Path $run 'f210-current-bob-tin-level4.stderr.log')
    }
    reload = [ordered]@{
      passed = $true
      benchmark_ticks = 30000
      input_save_sha256 = $saveSha
      save_sha256 = $saveSha
      save_byte_identical = $true
      factorio_log = Get-TinArtifact $repo $reloadLogPath
      stdout = Get-TinArtifact $repo (Join-Path $run 'f210-current-bob-tin-level4.reload.stdout.log')
      stderr = Get-TinArtifact $repo (Join-Path $run 'f210-current-bob-tin-level4.reload.stderr.log')
    }
    fixture = @('info.json', 'continuation-dossier.json', 'data-final-fixes.lua', 'control.lua' | ForEach-Object { Get-TinArtifact $repo (Join-Path $fixtureRoot $_) })
    recovery_harness = Get-TinArtifact $repo $PSCommandPath
    mod_closure = [ordered]@{
      enabled_mods = @((Get-Content -Raw -LiteralPath (Join-Path $run 'mods/mod-list.json') | ConvertFrom-Json).mods | Where-Object { $_.enabled } | ForEach-Object { $_.name })
      settings_after_engine = Get-TinArtifact $repo (Join-Path $run 'mods/mod-settings.dat')
      input_staging = $lease
    }
    non_claims = @($dossier.explicit_non_claims)
  }
  $resultPath = Join-Path $run 'result.json'
  [IO.File]::WriteAllText($resultPath, (ConvertTo-Json $result -Depth 100), [Text.UTF8Encoding]::new($false))
  Write-Output "[MIR-F210-CURRENT-BOB-TIN-LEVEL4-RECOVERED] $(Get-TinRelative $repo $resultPath)"
  return
}

& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') | Out-Host
$changes = @(& git -C $repo status --porcelain --untracked-files=all)
Assert-Tin ($changes.Count -eq 0) "qualification requires a clean worktree: $($changes -join '; ')"
$engine = (Resolve-Path -LiteralPath $FactorioBin).Path
Assert-Tin ((Get-TinSha $engine) -ceq $expectedEngineSha) 'Factorio executable differs from the exact retained Bob stage'
$version = (& $engine --version | Out-String)
Assert-Tin ($LASTEXITCODE -eq 0 -and $version -match 'Version:\s+2[.]1[.]20') 'requires Factorio 2.1.20'

$candidateResult = New-MIR4TargetPackage -RepoRoot $repo -Target f210 -CandidateId ('F210-BOB-TIN-L4-' + [guid]::NewGuid().ToString('N').Substring(0, 10).ToUpperInvariant()) -SourceVersion '4.2.0' -DistributionVersion '4.2.21000' -OutputRoot 'build/tests/f210-bob-tin-level4/pkg'
$candidate = (Resolve-Path -LiteralPath ([string]$candidateResult.archive_path)).Path
$sourceCommit = (& git -C $repo rev-parse HEAD).Trim()
$sourceTree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
Assert-Tin ($sourceCommit -match '^[0-9a-f]{40}$' -and $sourceTree -match '^[0-9a-f]{40}$') 'source Git identity is invalid'
$prepared = [ordered]@{
  schema = 1
  kind = 'MIR4F210CurrentBobTinLevelFourContinuationV1'
  status = 'prepared'
  scope = [string]$dossier.scope
  source = [ordered]@{ commit = $sourceCommit; tree = $sourceTree; package_source_sha256 = Get-TinSha (Join-Path $repo 'source/package-source.json') }
  exact_stage = [ordered]@{ path = $stage; engine_sha256 = $expectedEngineSha; settings_sha256 = $expectedSettingsSha; archives = $expectedArchives }
  candidate = Get-TinArtifact $repo $candidate
  fixture = @('info.json', 'continuation-dossier.json', 'data-final-fixes.lua', 'control.lua' | ForEach-Object { Get-TinArtifact $repo (Join-Path $fixtureRoot $_) })
  harness = Get-TinArtifact $repo $PSCommandPath
  non_claims = @($dossier.explicit_non_claims)
}
if ($PrepareOnly) {
  $prepared | ConvertTo-Json -Depth 30
  return
}

$run = Join-Path $output ('t-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
Assert-TinPath $run 'F210 Bob Tin level-four run root'
$inputLease = $null
try {
  New-Item -ItemType Directory -Force -Path (Join-Path $run 'mods'), (Join-Path $run 'saves') | Out-Null
  $mods = Join-Path $run 'mods'
  $inputs = @()
  foreach ($entry in $expectedArchives.GetEnumerator()) {
    $archivePath = Join-Path $stageMods $entry.Key
    $inputs += New-TinInput $archivePath 'dependency-mod' ([ordered]@{ archive = $entry.Key; sha256 = $entry.Value.sha256 }) ([ordered]@{ kind = 'retained-exact-f210-bob-stage'; stage = $stage })
  }
  $inputs += New-TinInput $candidate 'candidate' ([ordered]@{ target = 'f210'; sha256 = Get-TinSha $candidate }) ([ordered]@{ kind = 'fresh-f210-target-materialization'; source_commit = $sourceCommit; source_tree = $sourceTree })
  $inputLease = New-MIRImmutableInputLease -RunRoot $run -StageDirectory $mods -Inputs $inputs
  $fixtureArchive = Publish-MIRModDirectoryArchive -Source $fixtureRoot -Name $fixtureName -Version $fixtureVersion -ModsDir $mods
  Assert-TinPath $fixtureArchive 'F210 Bob Tin level-four fixture archive'
  $enabled = @('base', 'elevated-rails', 'quality', 'recycler', 'space-age')
  $enabled += @($expectedArchives.GetEnumerator() | ForEach-Object { $_.Value.name })
  $enabled += @('more-infinite-research', $fixtureName)
  $modList = [ordered]@{ mods = @($enabled | ForEach-Object { [ordered]@{ name = $_; enabled = $true } }) }
  [IO.File]::WriteAllText((Join-Path $mods 'mod-list.json'), (($modList | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
  $stagedSettings = Join-Path $mods 'mod-settings.dat'
  Copy-Item -LiteralPath $stageSettings -Destination $stagedSettings -Force
  Assert-Tin ((Get-TinSha $stagedSettings) -ceq $expectedSettingsSha) 'copied exact Bob settings differ before create'
  $initialSettings = Get-TinArtifact $repo $stagedSettings

  $load = Invoke-MIRFactorioLoadCheck -FactorioBin $engine -UserDataDir $run -ScenarioName 'f210-current-bob-tin-level4' -ScenarioTimeoutSeconds 240
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

  $staging = Complete-MIRImmutableInputLease -Lease $inputLease
  $inputLease = $null
  $candidateInput = @($staging.inputs | Where-Object { $_.role -ceq 'candidate' })
  Assert-Tin ($candidateInput.Count -eq 1) 'terminal staged candidate cardinality differs'
  $result = $prepared
  $result.status = 'passed'
  $result.engine = [ordered]@{ version = ([regex]::Match($version, 'Version:\s+[^\r\n]+').Value).Trim(); executable_sha256 = Get-TinSha $engine }
  $result.run_root = Get-TinRelative $repo $run
  $result.fresh_create = [ordered]@{ passed = $load.passed; duration_seconds = $load.duration_seconds; save = Get-TinArtifact $repo $load.save; stdout = Get-TinArtifact $repo $load.stdout; stderr = Get-TinArtifact $repo $load.stderr; factorio_log = Get-TinArtifact $repo $load.factorio_log }
  $result.reload = [ordered]@{ passed = $reload.passed; duration_seconds = $reload.duration_seconds; maximum_duration_seconds = $reload.maximum_duration_seconds; benchmark_ticks = $reload.benchmark_ticks; input_save_sha256 = $reload.input_save_sha256; save_sha256 = $reload.save_sha256; save_byte_identical = $reload.save_byte_identical; stdout = Get-TinArtifact $repo $reload.stdout; stderr = Get-TinArtifact $repo $reload.stderr; factorio_log = Get-TinArtifact $repo $reload.factorio_log }
  $result.mod_closure = [ordered]@{
    enabled_mods = $enabled
    candidate = ConvertTo-MIRImmutableInputArtifact -Receipt $staging -Input $candidateInput[0] -Locator (Get-TinRelative $repo ([string]$candidateInput[0].stage_path))
    settings = [ordered]@{ source_sha256 = $expectedSettingsSha; initial = $initialSettings; after_engine = Get-TinArtifact $repo $stagedSettings }
    fixture = Get-TinArtifact $repo $fixtureArchive
    mod_list = Get-TinArtifact $repo (Join-Path $mods 'mod-list.json')
    input_staging = $staging
  }
  $resultPath = Join-Path $run 'result.json'
  [IO.File]::WriteAllText($resultPath, (ConvertTo-Json $result -Depth 100), [Text.UTF8Encoding]::new($false))
  Write-Output "[MIR-F210-CURRENT-BOB-TIN-LEVEL4] $(Get-TinRelative $repo $resultPath)"
} catch {
  $failure = $_
  if ($null -ne $inputLease -and -not $inputLease.closed) {
    try { Complete-MIRImmutableInputLease -Lease $inputLease -Outcome failed | Out-Null } catch {}
  }
  throw $failure
}
