function Get-MIR4PlaytestFileDescriptor {
  param([Parameter(Mandatory)][string]$Path)
  $item = Get-Item -LiteralPath $Path
  return [ordered]@{path=$item.FullName;bytes=$item.Length;sha256=(Get-MIR4PreFreezeFileSha256 $item.FullName)}
}

function Write-MIR4PlaytestJson {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
  [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 100)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}

function Assert-MIR4PlaytestEvidenceV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Record)
  $schema = Join-Path (Get-MIR4PreFreezeRepoRoot $RepoRoot) 'spec/schemas/mir4-playtest-evidence-v1.schema.json'
  if (-not (Test-Path -LiteralPath $schema -PathType Leaf)) { throw '[mir4-playtest-evidence-schema-missing]' }
  $json = $Record | ConvertTo-Json -Depth 100
  if (-not ($json | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) {
    throw "[mir4-playtest-evidence-schema] $($Record.kind)"
  }
  return $true
}

function Get-MIR4PlaytestScenarioContract {
  param([Parameter(Mandatory)][ValidateSet('F210','F200')][string]$Target)
  $rows = if ($Target -ceq 'F210') {
    @(
      @{id='fresh-load';expected='A new default-settings game loads with the exact F210 development package.'},
      @{id='direct-upgrade-3.2.11';expected='A representative 3.2.11 save upgrades directly to the exact F210 development package.'},
      @{id='reload-1';expected='The upgraded F210 save reloads once without identity, state, or graph drift.'},
      @{id='reload-2';expected='The same F210 save reloads a second time without identity, state, or graph drift.'},
      @{id='maximum-level-states';expected='Maximum-level and continuation states match the F210 target contract.'},
      @{id='research-progress-and-queue';expected='Current research, fractional progress, and queued research survive upgrade and reload.'},
      @{id='production-route-policy';expected='Production-route selection matches the admitted F210 policy.'},
      @{id='cubium-canary';expected='The bounded Cubium compatibility canary matches its exact expected state.'},
      @{id='corrundum-canary';expected='The bounded Corrundum compatibility canary matches its exact expected state.'},
      @{id='recycler-canary';expected='The bounded Recycler compatibility canary matches its exact expected state.'},
      @{id='bounded-k2';expected='The exact bounded F210 Krastorio 2 scenario matches its target-bound claim.'},
      @{id='bounded-k2so';expected='The exact bounded F210 K2SO scenario matches its target-bound claim.'},
      @{id='settings-runtime-presentation-diagnostics';expected='Settings, runtime behavior, UI presentation, locales, and diagnostics match the F210 handoff.'}
    )
  } else {
    @(
      @{id='fresh-load';expected='A new default-settings game loads with the exact F200 development package.'},
      @{id='direct-upgrade-2.5.11';expected='A representative 2.5.11 save upgrades directly to the exact F200 development package.'},
      @{id='reload-1';expected='The upgraded F200 save reloads once without identity, state, or graph drift.'},
      @{id='reload-2';expected='The same F200 save reloads a second time without identity, state, or graph drift.'},
      @{id='target-appropriate-maximum-level';expected='Maximum-level behavior matches the F200 target contract and its finite omissions.'},
      @{id='research-progress-and-queue';expected='Current research, fractional progress, and queued research survive upgrade and reload.'},
      @{id='route-policy';expected='Production-route selection matches the admitted F200 policy.'},
      @{id='bounded-f200-k2';expected='The exact bounded F200 Krastorio 2 scenario matches its target-bound claim.'},
      @{id='bounded-f200-k2so';expected='The exact bounded F200 K2SO scenario matches its target-bound claim.'},
      @{id='explicit-target-omissions';expected='F210-only capabilities remain absent exactly where the F200 profile requires omission.'},
      @{id='settings-runtime-presentation-diagnostics';expected='Settings, runtime behavior, UI presentation, locales, and diagnostics match the F200 handoff.'}
    )
  }
  return @($rows | ForEach-Object { [pscustomobject][ordered]@{id=[string]$_.id;expected=[string]$_.expected} })
}

function Get-MIR4PlaytestLauncherText {
  return @'
param(
  [ValidateSet('Candidate','Predecessor')][string]$Package = 'Candidate',
  [string]$SavePath = '',
  [string]$CaptureLabel = ''
)

$ErrorActionPreference = 'Stop'
$sessionPath = Join-Path $PSScriptRoot 'session.json'
$session = Get-Content -Raw -LiteralPath $sessionPath | ConvertFrom-Json -Depth 100
function Get-LauncherSha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
$enginePath = [string]$session.engine.path
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf) -or (Get-LauncherSha256 $enginePath) -cne [string]$session.engine.sha256) {
  throw '[mir4-playtest-launcher-engine-hash]'
}
$selected = if ($Package -ceq 'Candidate') { $session.candidate } else { $session.predecessor }
if (-not (Test-Path -LiteralPath ([string]$selected.path) -PathType Leaf) -or (Get-LauncherSha256 ([string]$selected.path)) -cne [string]$selected.sha256) {
  throw '[mir4-playtest-launcher-package-hash]'
}
$mods = [string]$session.profile.mods
$stagedName = [IO.Path]::GetFileName([string]$selected.path)
foreach ($item in @(Get-ChildItem -LiteralPath $mods -Filter 'more-infinite-research_*.zip' -File -ErrorAction SilentlyContinue)) {
  Remove-Item -LiteralPath $item.FullName -Force
}
Copy-Item -LiteralPath ([string]$selected.path) -Destination (Join-Path $mods $stagedName)
$arguments = @('--config',[string]$session.profile.config,'--no-log-rotation','--mod-directory',$mods)
if (-not [string]::IsNullOrWhiteSpace($SavePath)) {
  $resolvedSave = (Resolve-Path -LiteralPath $SavePath -ErrorAction Stop).Path
  $arguments += @('--load-game',$resolvedSave)
}
& $enginePath @arguments
$exitCode = $LASTEXITCODE
$logPath = Join-Path ([string]$session.profile.userdata) 'factorio-current.log'
if (Test-Path -LiteralPath $logPath -PathType Leaf) {
  if ([string]::IsNullOrWhiteSpace($CaptureLabel)) { $CaptureLabel = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') }
  if ($CaptureLabel -notmatch '^[A-Za-z0-9._-]+$') { throw '[mir4-playtest-launcher-capture-label]' }
  $captureLog = Join-Path ([string]$session.profile.capture_queue) ('logs/' + $CaptureLabel + '-factorio-current.log')
  New-Item -ItemType Directory -Path (Split-Path -Parent $captureLog) -Force | Out-Null
  if (Test-Path -LiteralPath $captureLog) { throw '[mir4-playtest-launcher-capture-exists]' }
  Copy-Item -LiteralPath $logPath -Destination $captureLog
}
if ($exitCode -ne 0) { throw "[mir4-playtest-launcher-exit] $exitCode" }
'@
}

function Get-MIR4PlaytestCaptureKind {
  param([Parameter(Mandatory)][string]$Path,[string]$ObservationsPath='')
  $full = [IO.Path]::GetFullPath($Path)
  if (-not [string]::IsNullOrWhiteSpace($ObservationsPath) -and $full -ceq [IO.Path]::GetFullPath($ObservationsPath)) { return 'observations' }
  $extension = [IO.Path]::GetExtension($full).ToLowerInvariant()
  if ($extension -eq '.log') { return 'factorio-log' }
  if ($extension -eq '.zip') { return 'save' }
  if ($extension -in @('.png','.jpg','.jpeg','.webp')) { return 'screenshot' }
  if ($extension -in @('.md','.txt')) { return 'note' }
  return 'attachment'
}

function Compare-MIR4PlaytestObservations {
  param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)]$Observations)
  if ([string]$Observations.kind -cne 'MIR4PlaytestObservationsV1' -or
      [string]$Observations.target -cne [string]$Session.target -or
      [string]$Observations.candidate_sha256 -cne [string]$Session.candidate.sha256 -or
      [string]$Observations.engine_sha256 -cne [string]$Session.engine.sha256) {
    throw '[mir4-playtest-observations-binding]'
  }
  $expectedIds = @($Session.expected_scenarios | ForEach-Object { [string]$_.id })
  $actualIds = @($Observations.scenarios | ForEach-Object { [string]$_.id })
  if (@($actualIds | Sort-Object -Unique).Count -ne $actualIds.Count -or
      (($expectedIds | Sort-Object) -join '|') -cne (($actualIds | Sort-Object) -join '|')) {
    throw '[mir4-playtest-observations-scenario-set]'
  }
  $allowed = @('PASSED','FAILED','BLOCKED','PENDING')
  foreach ($row in @($Observations.scenarios)) {
    if ([string]$row.status -notin $allowed) { throw "[mir4-playtest-observations-status] $($row.id)" }
  }
  $passed = @($Observations.scenarios | Where-Object { [string]$_.status -ceq 'PASSED' }).Count
  $failed = @($Observations.scenarios | Where-Object { [string]$_.status -ceq 'FAILED' }).Count
  $blocked = @($Observations.scenarios | Where-Object { [string]$_.status -ceq 'BLOCKED' }).Count
  $pending = @($Observations.scenarios | Where-Object { [string]$_.status -ceq 'PENDING' }).Count
  $status = if ($failed -gt 0) { 'MISMATCH' } elseif ($blocked -gt 0 -or $pending -gt 0) { 'INCOMPLETE' } else { 'MATCHED' }
  return [pscustomobject][ordered]@{status=$status;total=$actualIds.Count;passed=$passed;failed=$failed;blocked=$blocked;pending=$pending}
}

function New-MIR4PlaytestSession {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('F210','F200')][string]$Target,
    [string]$CandidatePath = '',
    [string]$PredecessorPath = '',
    [string]$FactorioBin = '',
    [string]$SettingsPath = '',
    [string]$SavePath = '',
    [string]$OutputRoot = '',
    [switch]$DryRun
  )
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  if (-not (Get-Command Get-MIRPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
  }
  $plan = Get-MIR4FinalMilePlaytestCandidateAuthorityV1 -RepoRoot $repo
  $t15Path = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json'
  $t15 = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json' -Kind 'MIR4T15AuthorityEvolutionReceiptV1'
  $f210Resolution = $null
  $f210PolicyPath = Join-Path $repo $script:MIR4F210PolicyRelativePath
  $targetRow = @($plan.targets | Where-Object { [string]$_.target -ceq $Target })
  if ($targetRow.Count -ne 1) { throw "[mir4-playtest-target] $Target" }
  $row = $targetRow[0]
  $packageSourceSha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  if ($packageSourceSha256 -cne [string]$t15.player_package_source_sha256) { throw '[mir4-playtest-package-source-superseded]' }
  if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
    $CandidatePath = Join-Path $repo ("build/results/mir4-sol/sol08/target-candidates/distributions/more-infinite-research_{0}.zip" -f [string]$row.distribution_version)
  }
  if ([string]::IsNullOrWhiteSpace($PredecessorPath)) { $PredecessorPath = Join-Path $repo ([string]$row.predecessor.path) }
  if ($Target -ceq 'F210') {
    $f210Resolution = Get-MIR4F210EngineResolutionV1 -RepoRoot $repo -FactorioBin $FactorioBin
    $FactorioBin = [string]$f210Resolution.engine.path
  } elseif ([string]::IsNullOrWhiteSpace($FactorioBin)) { $FactorioBin = [string]$row.engine.path }
  foreach ($required in @($CandidatePath,$PredecessorPath,$FactorioBin)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "[mir4-playtest-input] $required" }
  }
  $candidate = Get-MIR4PlaytestFileDescriptor $CandidatePath
  $predecessor = Get-MIR4PlaytestFileDescriptor $PredecessorPath
  $engine = Get-MIR4PlaytestFileDescriptor $FactorioBin
  if ([string]$candidate.sha256 -cne [string]$row.development_package.sha256) { throw '[mir4-playtest-candidate-hash]' }
  if ([string]$predecessor.sha256 -cne [string]$row.predecessor.sha256) { throw '[mir4-playtest-predecessor-hash]' }
  $expectedEngineSha256 = if ($Target -ceq 'F210') { [string]$f210Resolution.engine.sha256 } else { [string]$row.engine.sha256 }
  if ([string]$engine.sha256 -cne $expectedEngineSha256) { throw '[mir4-playtest-engine-hash]' }
  foreach ($optional in @($SettingsPath,$SavePath)) {
    if (-not [string]::IsNullOrWhiteSpace($optional) -and -not (Test-Path -LiteralPath $optional -PathType Leaf)) {
      throw "[mir4-playtest-optional-input] $optional"
    }
  }
  if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repo ("build/mir4/playtests/{0}/session-{1}" -f $Target.ToLowerInvariant(),[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
  }
  $output = [IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($OutputRoot)){$OutputRoot}else{Join-Path $repo $OutputRoot}))
  $allowed = [IO.Path]::GetFullPath((Join-Path $repo 'build/mir4/playtests')).TrimEnd('\') + '\'
  if (-not ($output + '\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw "[mir4-playtest-output-boundary] $output" }
  $profile = Join-Path $output 'profile'
  $mods = Join-Path $profile 'mods'
  $userdata = Join-Path $profile 'userdata'
  $packages = Join-Path $output 'packages'
  $captureQueue = Join-Path $output 'capture-queue'
  $config = Join-Path $profile 'config.ini'
  $launcher = Join-Path $output 'Invoke-MIR4PlaytestEngine.ps1'
  $observationsPath = Join-Path $output 'observations.json'
  $decisionTemplatePath = Join-Path $output 'manual-decision.template.json'
  $planPath = Join-Path $repo $script:MIR4FinalMilePlaytestCandidateAuthorityRelativePath
  $handoffPath = Join-Path $repo 'docs/maintainer/mir4-w09-manual-playtest.md'
  $scenarioContract = @(Get-MIR4PlaytestScenarioContract -Target $Target)
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4PlaytestSessionV1';status=$(if($DryRun){'planned'}else{'prepared'})
    target=$Target;distribution_version=[string]$row.distribution_version;candidate_state='development-pre-freeze-not-release-identity'
    created_at=[DateTime]::UtcNow.ToString('o');session_root=$output
    engine=$engine;candidate=$candidate;predecessor=$predecessor
    authority=[ordered]@{
      development_plan=(Get-MIR4PlaytestFileDescriptor $planPath)
      current_package_authority=(Get-MIR4PlaytestFileDescriptor $t15Path)
      f210_engine_policy=$(if($Target -ceq 'F210'){Get-MIR4PlaytestFileDescriptor $f210PolicyPath}else{$null})
      f210_engine_resolution=$f210Resolution
      manual_handoff=(Get-MIR4PlaytestFileDescriptor $handoffPath)
      source_baseline=$plan.source_baseline
      verification_plan=[ordered]@{profile='mir4-final-mile';assurance=$row.assurance}
      package_source_sha256=$packageSourceSha256
    }
    settings=$(if([string]::IsNullOrWhiteSpace($SettingsPath)){$null}else{Get-MIR4PlaytestFileDescriptor $SettingsPath})
    save_fixture=$(if([string]::IsNullOrWhiteSpace($SavePath)){$null}else{Get-MIR4PlaytestFileDescriptor $SavePath})
    profile=[ordered]@{root=$profile;config=$config;mods=$mods;userdata=$userdata;capture_queue=$captureQueue;default_package='Candidate'}
    engine_command=[ordered]@{launcher=$launcher;base_arguments=@('--config',$config,'--no-log-rotation','--mod-directory',$mods);save_argument='--load-game'}
    expected_scenarios=$scenarioContract
    capture_requirements=@('factorio-log','save','observations','screenshot-or-note')
    observations_template=$observationsPath
    decision_template=$decisionTemplatePath
    decision=$null;decision_inferred=$false;package_visible=$false;production_release_authorized=$false
  }
  if ($DryRun) { Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $record | Out-Null; return $record }
  if (Test-Path -LiteralPath $output) { throw "[mir4-playtest-session-exists] $output" }
  New-Item -ItemType Directory -Path $mods,$userdata,$packages,$captureQueue,(Join-Path $captureQueue 'logs'),(Join-Path $captureQueue 'saves'),(Join-Path $captureQueue 'screenshots'),(Join-Path $captureQueue 'notes') -Force | Out-Null
  $candidateStored = Join-Path $packages ([IO.Path]::GetFileName($CandidatePath))
  $predecessorStored = Join-Path $packages ([IO.Path]::GetFileName($PredecessorPath))
  Copy-Item -LiteralPath $CandidatePath -Destination $candidateStored
  Copy-Item -LiteralPath $PredecessorPath -Destination $predecessorStored
  Copy-Item -LiteralPath $candidateStored -Destination (Join-Path $mods ([IO.Path]::GetFileName($candidateStored)))
  if (-not [string]::IsNullOrWhiteSpace($SettingsPath)) {
    Copy-Item -LiteralPath $SettingsPath -Destination (Join-Path $output ('profile/' + [IO.Path]::GetFileName($SettingsPath)))
  }
  if (-not [string]::IsNullOrWhiteSpace($SavePath)) {
    New-Item -ItemType Directory -Path (Join-Path $output 'profile/saves') -Force | Out-Null
    Copy-Item -LiteralPath $SavePath -Destination (Join-Path $output ('profile/saves/' + [IO.Path]::GetFileName($SavePath)))
  }
  $record.candidate.path = $candidateStored
  $record.predecessor.path = $predecessorStored
  $newline = [Environment]::NewLine
  $configText = @(
    '; Generated by MIR 4 T17 playtest preparation.',$newline,
    '[path]',
    'read-data=__PATH__executable__/../../data',
    ('write-data=' + $userdata.Replace('\','/')),
    '[other]',
    'check-updates=false'
  ) -join $newline
  [IO.File]::WriteAllText($config,$configText+$newline,[Text.UTF8Encoding]::new($false))
  $modList = [ordered]@{mods=@([ordered]@{name='base';enabled=$true},[ordered]@{name='more-infinite-research';enabled=$true})}
  Write-MIR4PlaytestJson -Path (Join-Path $mods 'mod-list.json') -Value $modList
  [IO.File]::WriteAllText($launcher,(Get-MIR4PlaytestLauncherText)+$newline,[Text.UTF8Encoding]::new($false))
  $record.engine_command.launcher_sha256 = Get-MIR4PreFreezeFileSha256 $launcher
  $observations = [ordered]@{
    schema=1;kind='MIR4PlaytestObservationsV1';status='in-progress';target=$Target
    candidate_sha256=[string]$record.candidate.sha256;engine_sha256=[string]$record.engine.sha256
    scenarios=@($scenarioContract | ForEach-Object { [ordered]@{id=[string]$_.id;status='PENDING';notes=''} })
    decision=$null;decision_inferred=$false;production_release_authorized=$false
  }
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $observations | Out-Null
  Write-MIR4PlaytestJson -Path $observationsPath -Value $observations
  $decisionTemplate = [ordered]@{
    schema=1;kind='MIR4ManualPlaytestDecisionTemplateV1';valid_evidence=$false;target=$Target
    candidate_sha256=[string]$record.candidate.sha256;engine_sha256=[string]$record.engine.sha256
    allowed_decisions=@('ACCEPTED','CHANGES-REQUESTED','REJECTED')
    instruction='Do not edit this template into evidence. After capture, the maintainer runs tools/mir.ps1 playtest finalize with an explicit decision and reviewer.'
    decision=$null;reviewer=$null;source_freeze_authorized=$false;production_release_authorized=$false
  }
  Write-MIR4PlaytestJson -Path $decisionTemplatePath -Value $decisionTemplate
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $record | Out-Null
  Write-MIR4PlaytestJson -Path (Join-Path $output 'session.json') -Value $record
  $checklist = "# MIR 4 $Target manual playtest" + $newline + $newline +
    "Candidate, predecessor, engine, plan, package-source, and handoff identities are locked in session.json. Record observations; do not infer acceptance." + $newline + $newline +
    "Launch the isolated engine with .\Invoke-MIR4PlaytestEngine.ps1 -Package Candidate. Use -Package Predecessor to create or inspect the direct-upgrade source save, then switch back to Candidate and pass -SavePath <save>." + $newline + $newline +
    ((@($scenarioContract) | ForEach-Object { "- [ ] $($_.id): $($_.expected)" }) -join $newline) + $newline + $newline +
    "Place logs, saves, screenshots, and notes below capture-queue, set every observations.json scenario to PASSED, FAILED, or BLOCKED, then run playtest capture. Only the maintainer may run playtest finalize." + $newline
  [IO.File]::WriteAllText((Join-Path $output 'review-checklist.md'),$checklist,[Text.UTF8Encoding]::new($false))
  return $record
}

function Capture-MIR4PlaytestSession {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SessionRoot,
    [string[]]$CapturePath = @(),
    [string]$ObservationsPath = '',
    [switch]$DryRun
  )
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $sessionRootFull = [IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($SessionRoot)){$SessionRoot}else{Join-Path $repo $SessionRoot}))
  $sessionPath = Join-Path $sessionRootFull 'session.json'
  $session = Get-Content -Raw -LiteralPath $sessionPath | ConvertFrom-Json -Depth 100
  if ([string]$session.kind -cne 'MIR4PlaytestSessionV1') { throw '[mir4-playtest-session-kind]' }
  foreach ($locked in @($session.candidate,$session.predecessor,$session.engine,$session.authority.development_plan,$session.authority.current_package_authority,$session.authority.manual_handoff)) {
    if (-not (Test-Path -LiteralPath ([string]$locked.path) -PathType Leaf) -or
        (Get-MIR4PreFreezeFileSha256 ([string]$locked.path)) -cne [string]$locked.sha256) {
      throw "[mir4-playtest-locked-input] $($locked.path)"
    }
  }
  if (-not (Test-Path -LiteralPath ([string]$session.engine_command.launcher) -PathType Leaf) -or
      (Get-MIR4PreFreezeFileSha256 ([string]$session.engine_command.launcher)) -cne [string]$session.engine_command.launcher_sha256) {
    throw '[mir4-playtest-launcher-current]'
  }
  if ([string]::IsNullOrWhiteSpace($ObservationsPath)) { $ObservationsPath = [string]$session.observations_template }
  if (-not (Test-Path -LiteralPath $ObservationsPath -PathType Leaf)) { throw '[mir4-playtest-observations-required]' }
  $observations = Get-Content -Raw -LiteralPath $ObservationsPath | ConvertFrom-Json -Depth 100
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $observations | Out-Null
  $comparison = Compare-MIR4PlaytestObservations -Session $session -Observations $observations
  $paths = [Collections.Generic.List[string]]::new()
  foreach ($path in @($CapturePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    $paths.Add([IO.Path]::GetFullPath($path))
  }
  $queueRoot = [string]$session.profile.capture_queue
  if (Test-Path -LiteralPath $queueRoot -PathType Container) {
    foreach ($item in @(Get-ChildItem -LiteralPath $queueRoot -Recurse -File -ErrorAction Stop | Sort-Object FullName)) { $paths.Add($item.FullName) }
  }
  $paths.Add([IO.Path]::GetFullPath($ObservationsPath))
  $paths = @($paths | Sort-Object -Unique)
  foreach ($path in $paths) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-playtest-capture-input] $path" } }
  $sourceRows = @($paths | ForEach-Object {
    $descriptor = Get-MIR4PlaytestFileDescriptor $_
    $descriptor['kind'] = Get-MIR4PlaytestCaptureKind -Path $_ -ObservationsPath $ObservationsPath
    [pscustomobject]$descriptor
  })
  $kinds = @($sourceRows | ForEach-Object { [string]$_.kind })
  $missingRequirements = [Collections.Generic.List[string]]::new()
  foreach ($required in @('factorio-log','save','observations')) { if ($required -notin $kinds) { $missingRequirements.Add($required) } }
  if ('screenshot' -notin $kinds -and 'note' -notin $kinds) { $missingRequirements.Add('screenshot-or-note') }
  $ready = $comparison.status -ceq 'MATCHED' -and $missingRequirements.Count -eq 0
  $receipt = [pscustomobject][ordered]@{
    schema=1;kind='MIR4PlaytestCaptureV1';status=$(if($DryRun){'planned'}elseif($ready){'ready-for-maintainer-decision'}else{'captured-incomplete'})
    target=[string]$session.target;captured_at=[DateTime]::UtcNow.ToString('o')
    candidate_sha256=[string]$session.candidate.sha256;engine_sha256=[string]$session.engine.sha256
    session_sha256=(Get-MIR4PreFreezeFileSha256 $sessionPath)
    files=$sourceRows;observations_supplied=$true;comparison=$comparison
    missing_capture_requirements=@($missingRequirements);result_summary=$null
    decision=$null;decision_inferred=$false;package_visible=$false;production_release_authorized=$false
  }
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $receipt | Out-Null
  if ($DryRun) { return $receipt }
  $captureRoot = Join-Path $sessionRootFull 'capture'
  if (Test-Path -LiteralPath (Join-Path $sessionRootFull 'capture.json')) { throw '[mir4-playtest-capture-exists]' }
  New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
  $usedNames = @{}
  $capturedRows = [Collections.Generic.List[object]]::new()
  foreach ($source in $sourceRows) {
    $name = [IO.Path]::GetFileName([string]$source.path)
    if ($usedNames.ContainsKey($name)) { throw "[mir4-playtest-capture-name-collision] $name" }
    $usedNames[$name] = $true
    $destination = Join-Path $captureRoot $name
    Copy-Item -LiteralPath ([string]$source.path) -Destination $destination
    $descriptor = Get-MIR4PlaytestFileDescriptor $destination
    $descriptor['kind'] = [string]$source.kind
    $capturedRows.Add([pscustomobject]$descriptor)
  }
  $receipt.files = @($capturedRows)
  $summary = [ordered]@{
    schema=1;kind='MIR4PlaytestResultSummaryV1';status=$(if($ready){'ready-for-maintainer-decision'}else{'changes-required-or-incomplete'})
    target=[string]$session.target;candidate_sha256=[string]$session.candidate.sha256;engine_sha256=[string]$session.engine.sha256
    comparison=$comparison;capture_file_count=$capturedRows.Count;capture_kinds=@($capturedRows.kind | Sort-Object -Unique)
    missing_capture_requirements=@($missingRequirements)
    next_action=$(if($ready){'Maintainer reviews the retained evidence and supplies an explicit decision.'}else{'Complete or correct the named scenarios and capture requirements; do not infer acceptance.'})
    decision=$null;decision_inferred=$false;source_freeze_authorized=$false;production_release_authorized=$false
  }
  $summaryPath = Join-Path $sessionRootFull 'result-summary.json'
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $summary | Out-Null
  Write-MIR4PlaytestJson -Path $summaryPath -Value $summary
  $receipt.result_summary = Get-MIR4PlaytestFileDescriptor $summaryPath
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $receipt | Out-Null
  Write-MIR4PlaytestJson -Path (Join-Path $sessionRootFull 'capture.json') -Value $receipt
  return $receipt
}

function Complete-MIR4PlaytestSession {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SessionRoot,
    [Parameter(Mandatory)][ValidateSet('ACCEPTED','CHANGES-REQUESTED','REJECTED')][string]$Decision,
    [Parameter(Mandatory)][string]$Reviewer,
    [string]$Notes = '',
    [switch]$DryRun
  )
  if ([string]::IsNullOrWhiteSpace($Reviewer)) { throw '[mir4-playtest-reviewer-required]' }
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  if (-not (Get-Command Get-MIRPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
  }
  $root = [IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($SessionRoot)){$SessionRoot}else{Join-Path $repo $SessionRoot}))
  $sessionPath = Join-Path $root 'session.json'
  $session = Get-Content -Raw -LiteralPath $sessionPath | ConvertFrom-Json -Depth 100
  if ([string]$session.kind -cne 'MIR4PlaytestSessionV1' -or [bool]$session.decision_inferred -or [bool]$session.production_release_authorized) {
    throw '[mir4-playtest-finalize-session]'
  }
  $planPath = [string]$session.authority.development_plan.path
  if ((Get-MIR4PreFreezeFileSha256 $planPath) -cne [string]$session.authority.development_plan.sha256) { throw '[mir4-playtest-finalize-plan-superseded]' }
  if (-not (Test-Path -LiteralPath ([string]$session.authority.current_package_authority.path) -PathType Leaf) -or
      (Get-MIR4PreFreezeFileSha256 ([string]$session.authority.current_package_authority.path)) -cne [string]$session.authority.current_package_authority.sha256 -or
      (Get-MIRPackageSourceFingerprint -RepoRoot $repo) -cne [string]$session.authority.package_source_sha256) {
    throw '[mir4-playtest-finalize-package-source-superseded]'
  }
  $plan = Get-MIR4FinalMilePlaytestCandidateAuthorityV1 -RepoRoot $repo
  if ([IO.Path]::GetFullPath($planPath) -cne [IO.Path]::GetFullPath((Join-Path $repo $script:MIR4FinalMilePlaytestCandidateAuthorityRelativePath))) {
    throw '[mir4-playtest-finalize-plan-path]'
  }
  $targetRow = @($plan.targets | Where-Object { [string]$_.target -ceq [string]$session.target })
  $expectedEngineSha256 = if ([string]$session.target -ceq 'F210') {
    $resolution = Get-MIR4F210EngineResolutionV1 -RepoRoot $repo -FactorioBin ([string]$session.engine.path)
    if ($null -eq $session.authority.f210_engine_policy -or
        (Get-MIR4PreFreezeFileSha256 ([string]$session.authority.f210_engine_policy.path)) -cne [string]$session.authority.f210_engine_policy.sha256 -or
        [string]$resolution.record_sha256 -cne [string]$session.authority.f210_engine_resolution.record_sha256) {
      throw '[mir4-playtest-finalize-f210-policy-or-engine-drift]'
    }
    [string]$resolution.engine.sha256
  } else { [string]$targetRow[0].engine.sha256 }
  if ($targetRow.Count -ne 1 -or [string]$targetRow[0].development_package.sha256 -cne [string]$session.candidate.sha256 -or
      [string]$targetRow[0].predecessor.sha256 -cne [string]$session.predecessor.sha256 -or
      $expectedEngineSha256 -cne [string]$session.engine.sha256) {
    throw '[mir4-playtest-finalize-current-bindings]'
  }
  $capturePath = Join-Path $root 'capture.json'
  if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) { throw '[mir4-playtest-finalize-without-capture]' }
  $capture = Get-Content -Raw -LiteralPath $capturePath | ConvertFrom-Json -Depth 100
  if ([string]$capture.candidate_sha256 -cne [string]$session.candidate.sha256 -or
      [string]$capture.engine_sha256 -cne [string]$session.engine.sha256 -or
      [string]$capture.session_sha256 -cne (Get-MIR4PreFreezeFileSha256 $sessionPath) -or
      [bool]$capture.decision_inferred -or [bool]$capture.production_release_authorized) {
    throw '[mir4-playtest-finalize-capture-binding]'
  }
  foreach ($evidence in @($capture.files)) {
    if (-not (Test-Path -LiteralPath ([string]$evidence.path) -PathType Leaf) -or
        (Get-MIR4PreFreezeFileSha256 ([string]$evidence.path)) -cne [string]$evidence.sha256) {
      throw "[mir4-playtest-finalize-evidence] $($evidence.path)"
    }
  }
  $summaryPath = Join-Path $root 'result-summary.json'
  if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf) -or
      (Get-MIR4PreFreezeFileSha256 $summaryPath) -cne [string]$capture.result_summary.sha256) {
    throw '[mir4-playtest-finalize-summary-binding]'
  }
  $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json -Depth 100
  if ($Decision -ceq 'ACCEPTED' -and ([string]$capture.status -cne 'ready-for-maintainer-decision' -or
      [string]$capture.comparison.status -cne 'MATCHED' -or @($capture.missing_capture_requirements).Count -ne 0 -or
      [string]$summary.status -cne 'ready-for-maintainer-decision')) {
    throw '[mir4-playtest-acceptance-evidence-incomplete]'
  }
  $receipt = [pscustomobject][ordered]@{
    schema=1;kind='MIR4ManualPlaytestDecisionV1';status=$(if($DryRun){'planned'}else{'final'})
    target=[string]$session.target;candidate_sha256=[string]$session.candidate.sha256
    engine_sha256=[string]$session.engine.sha256;capture_sha256=(Get-MIR4PreFreezeFileSha256 $capturePath)
    session_sha256=(Get-MIR4PreFreezeFileSha256 $sessionPath);result_summary_sha256=(Get-MIR4PreFreezeFileSha256 $summaryPath)
    reviewer=$Reviewer;decision=$Decision;notes=$Notes;decided_at=[DateTime]::UtcNow.ToString('o')
    decision_inferred=$false;source_freeze_authorized=$false;production_release_authorized=$false
  }
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $receipt | Out-Null
  if ($DryRun) { return $receipt }
  $output = Join-Path $root 'manual-decision.json'
  if (Test-Path -LiteralPath $output) { throw '[mir4-playtest-decision-exists]' }
  Write-MIR4PlaytestJson -Path $output -Value $receipt
  return $receipt
}
