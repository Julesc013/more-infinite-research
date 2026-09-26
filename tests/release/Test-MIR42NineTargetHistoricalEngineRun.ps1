param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')

$expected = [ordered]@{
  f017 = [ordered]@{line='0.17';version='1.7.9';candidate='4.2.01700';archive='B6BDCD54C5952F986155ED4D78D92E109E90AD38D2CA9EC609034A848152CA2C';engine='E699D376D100A428B95243507FDBB39C372921577C6D7593203EDF07CAA12D06';infinite='mining-productivity-4'}
  f016 = [ordered]@{line='0.16';version='1.6.9';candidate='4.2.01600';archive='928916C96C500AD1441455563F0559EF330A4814DD6C9630ADA9E9B698248B84';engine='ACBA4D8B766C8CB61CBB564E0D5041439DF32D93C86127DCC3887EB329630966';infinite='mining-productivity-16'}
  f015 = [ordered]@{line='0.15';version='1.5.9';candidate='4.2.01500';archive='85255CB5E8F8B482387454C92A16660276009E0A5D301FBDE38BF8944F72E24E';engine='A1C87043244BEAE8E5903FB7D4A96E7920189C6339F00E3A2398988B9C8E7DD6';infinite='mining-productivity-16'}
  f014 = [ordered]@{line='0.14';version='1.4.9';candidate='4.2.01400';archive='1E3651E59656CE5258EC4F5FEFEA05883D577151E0BC8465342547D92CBAC872';engine='A2B7DC0FBC1D6D68CF4D71EB71D42952FBB3B0CF35EEC6BF8B4BA16B9F79715F';infinite=''}
  f013 = [ordered]@{line='0.13';version='1.3.9';candidate='4.2.01300';archive='CF540E5ED6902BC0B97F0AC98D17875001B286183647C604CB065A8078B1AD5A';engine='F12C0DF5A5EF0D72F50A24BD76E077DFC9CBEAB4B31EE9EF0951A4A9C086B856';infinite=''}
}

function Import-MIR42EngineRunnerFunction {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name)
  $tokens = $null
  $errors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
  if (@($errors).Count -ne 0) { throw "runner-parse $Name" }
  $definitions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name },$true))
  if ($definitions.Count -ne 1) { throw "runner-function $Name" }
  . ([scriptblock]::Create($definitions[0].Extent.Text))
  $implementation = (Get-Item -LiteralPath ("function:$Name")).ScriptBlock
  Set-Item -LiteralPath ("function:script:$Name") -Value $implementation
}

$runnerPath = Join-Path $RepoRoot 'tools/commands/release/Invoke-MIR42FourTargetEngineRun.ps1'
$runner = Get-Content -Raw -LiteralPath $runnerPath
$script:MIR42HistoricalTerminalInputs = [ordered]@{
  f017 = [ordered]@{ line='0.17'; predecessor='1.7.9'; target_record='targets/historical/f017/target.json'; terminal_seal='.mir/releases/terminal/seals/1.7.9.json' }
  f016 = [ordered]@{ line='0.16'; predecessor='1.6.9'; target_record='targets/historical/f016/target.json'; terminal_seal='.mir/releases/terminal/seals/1.6.9.json' }
  f015 = [ordered]@{ line='0.15'; predecessor='1.5.9'; target_record='targets/historical/f015/target.json'; terminal_seal='.mir/releases/terminal/seals/1.5.9.json' }
  f014 = [ordered]@{ line='0.14'; predecessor='1.4.9'; target_record='targets/historical/f014/target.json'; terminal_seal='.mir/releases/terminal/seals/1.4.9.json' }
  f013 = [ordered]@{ line='0.13'; predecessor='1.3.9'; target_record='targets/historical/f013/target.json'; terminal_seal='.mir/releases/terminal/seals/1.3.9.json' }
}
foreach ($name in @('Assert-MIR42EngineRunFile','Get-MIR42EngineRunSha','Get-MIR42HistoricalEngineDescriptor','Assert-MIR42HistoricalUpgradeHarness')) {
  Import-MIR42EngineRunnerFunction -Path $runnerPath -Name $name
}

foreach ($target in $expected.Keys) {
  $row = $expected[$target]
  $record = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "targets/historical/$target/target.json") | ConvertFrom-Json -Depth 100 -DateKind String
  $seal = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ('.mir/releases/terminal/seals/' + $row.version + '.json')) | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $record) -or -not (Test-MIR4BootstrapRecordHash -Record $seal) -or
      [string]$record.target -cne $target -or [string]$record.factorio_line -cne [string]$row.line -or [string]$record.distribution_version -cne [string]$row.candidate -or
      [string]$record.predecessor.version -cne [string]$row.version -or [string]$record.predecessor.sha256 -cne [string]$row.archive -or [string]$record.engine.sha256 -cne [string]$row.engine -or
      [bool]$record.public_output_authorized -or [bool]$record.publication_authorized -or [string]$seal.release -cne [string]$row.version -or [string]$seal.target -cne [string]$row.line -or
      [string]$seal.archive_sha256 -cne [string]$row.archive -or [string]$seal.engine.binary_sha256 -cne [string]$row.engine) { throw "historical-binding $target" }
  $archive = Join-Path $RepoRoot ([string]$record.predecessor.archive)
  if (-not (Test-Path -LiteralPath $archive -PathType Leaf) -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$row.archive) { throw "historical-predecessor $target" }
}

$descriptorParent = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build/tmp/mir42-historical-descriptor'))
$descriptorRoot = Join-Path $descriptorParent ([guid]::NewGuid().ToString('N'))
try {
  foreach ($target in $expected.Keys) {
    $descriptor = Get-MIR42HistoricalEngineDescriptor -RepoRoot $RepoRoot -Target $target
    $row = $expected[$target]
    if ([string]$descriptor.from -cne [string]$row.version -or [string]$descriptor.to -cne [string]$row.candidate -or
        -not ([string]$descriptor.engine).EndsWith(('Factorio\' + $row.line + '\bin\x64\factorio.exe'),[StringComparison]::OrdinalIgnoreCase) -or
        [string]$descriptor.historical.target_record.path -cne "targets/historical/$target/target.json" -or
        [string]$descriptor.historical.predecessor.sha256 -cne [string]$row.archive -or
        [string]$descriptor.historical.engine.sha256 -cne [string]$row.engine) { throw "descriptor-binding $target" }

    $recordRelative = "targets/historical/$target/target.json"
    $sealRelative = '.mir/releases/terminal/seals/' + $row.version + '.json'
    $recordDestination = Join-Path $descriptorRoot $recordRelative
    $sealDestination = Join-Path $descriptorRoot $sealRelative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $recordDestination),(Split-Path -Parent $sealDestination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot $recordRelative) -Destination $recordDestination
    Copy-Item -LiteralPath (Join-Path $RepoRoot $sealRelative) -Destination $sealDestination
    $tamperedRecord = Get-Content -Raw -LiteralPath $recordDestination | ConvertFrom-Json -Depth 100 -DateKind String
    $tamperedRecord.predecessor.sha256 = '0' * 64
    $tamperedRecord.record_sha256 = ''
    $tamperedRecord.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $tamperedRecord
    $tamperedRecord | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $recordDestination -Encoding UTF8
    try {
      $null = Get-MIR42HistoricalEngineDescriptor -RepoRoot $descriptorRoot -Target $target
      throw "descriptor-opposing-case-not-rejected $target"
    } catch {
      if ($_.Exception.Message -eq "descriptor-opposing-case-not-rejected $target") { throw }
      if ($_.Exception.Message -notmatch ('^\[mir42-' + [regex]::Escape($target) + '-terminal-seal-binding\]$')) { throw }
    }
  }
} finally {
  if (Test-Path -LiteralPath $descriptorRoot) {
    $resolvedDescriptorRoot = (Resolve-Path -LiteralPath $descriptorRoot).Path
    $descriptorPrefix = $descriptorParent.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedDescriptorRoot.StartsWith($descriptorPrefix,[StringComparison]::OrdinalIgnoreCase)) {
      throw 'Historical descriptor cleanup escapes its repository scratch parent.'
    }
    Remove-Item -LiteralPath $resolvedDescriptorRoot -Recurse -Force
  }
}

$harnessDescriptor = Assert-MIR42HistoricalUpgradeHarness -RepoRoot $RepoRoot
if ([string]::IsNullOrWhiteSpace([string]$harnessDescriptor.fixture_sha256) -or
    [string]::IsNullOrWhiteSpace([string]$harnessDescriptor.control_sha256) -or
    [string]::IsNullOrWhiteSpace([string]$harnessDescriptor.upgrade_harness_sha256)) { throw 'historical-harness-descriptor' }

$fixtureRoot = Join-Path $RepoRoot 'fixtures/assert-upgrade-historical-terminal-to-mir42'
$infoTemplate = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'info.json')
$controlTemplate = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'control.lua')
foreach ($target in $expected.Keys) {
  $row = $expected[$target]

  $infoText = $infoTemplate.Replace('@@FACTORIO_LINE@@',[string]$row.line).Replace('@@MIR_UPGRADE_FROM_VERSION@@',[string]$row.version)
  $info = $infoText | ConvertFrom-Json -Depth 20
  if ([string]$info.factorio_version -cne [string]$row.line -or 'base' -cnotin @($info.dependencies) -or ('more-infinite-research >= ' + $row.version) -cnotin @($info.dependencies) -or $infoText.Contains('@@')) { throw "historical-info-specialization $target" }
  $saveName = 'mir-' + $row.candidate.Replace('.','') + '-upgraded'
  $control = $controlTemplate.Replace('__MIR_UPGRADE_FROM_VERSION__',[string]$row.version).Replace('__MIR_UPGRADE_TO_VERSION__',[string]$row.candidate).
    Replace('__MIR_FACTORIO_LINE__',[string]$row.line).Replace('__MIR_INFINITE_TECHNOLOGY__',[string]$row.infinite).Replace('__MIR_UPGRADE_SAVE_NAME__',$saveName)
  if ($control.Contains('__MIR_') -or $control.Contains('game.active_mods') -or $control.Contains('event.tick') -or
      -not $control.Contains('script.on_configuration_changed') -or -not $control.Contains('script.on_load') -or -not $control.Contains('loaded_candidate_state') -or
      -not $control.Contains('game.server_save(governed_save_name)') -or -not $control.Contains('force().research_progress = expected_progress') -or
      -not $control.Contains('changed infinite mining productivity bonus') -or -not $control.Contains('completed_prerequisite_levels') -or
      -not $control.Contains('observed_level') -or -not $control.Contains('observed_bonus') -or -not $control.Contains('infinite research did not advance') -or
      -not $control.Contains('"' + $saveName + '"')) { throw "historical-control-specialization $target" }
  if (($row.infinite -eq '') -and $control.Contains('mining-productivity-')) { throw "historical-control-unsupported-infinite $target" }
  if (($row.infinite -ne '') -and -not $control.Contains($row.infinite)) { throw "historical-control-infinite $target" }
  $researchSelection = @'
  if factorio_line == "0.17" then
    force().research_queue_enabled = true
    force().research_queue = { research.name }
  else
    force().current_research = research.name
  end
  local current = force().current_research
  if not current or current.name ~= research.name then
    fail("could not select current finite research on " .. factorio_line)
  end
'@.Trim()
  if (-not $control.Contains($researchSelection) -or $control.Contains('add_research')) { throw "historical-control-current-research-selection $target" }
  $reloadMarker = 'upgraded save reload proof complete archetype=base-default'
  $reloadMarkerIndex = $control.IndexOf($reloadMarker,[StringComparison]::Ordinal)
  $resetIndex = $control.IndexOf('loaded_candidate_state = false',$reloadMarkerIndex,[StringComparison]::Ordinal)
  if ($reloadMarkerIndex -lt 0 -or $resetIndex -le $reloadMarkerIndex -or $control.Contains('if not infinite_technology.researched')) { throw "historical-control-reload-or-infinite-semantics $target" }
}

$harness = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tests/runtime/Test-MIRUpgrade.ps1')
foreach ($needle in @('$isHistoricalTerminalFixture = $FixtureName -eq ''assert-upgrade-historical-terminal-to-mir42''','$isLegacyFactorio = $isHistoricalTerminalFixture -or','MIR historical upgrade specialization requires an exact terminal predecessor','historical-terminal-source-state-retained','historical-terminal-infinite-bonus-retained-where-supported','$historicalHarness = Assert-MIR42HistoricalUpgradeHarness -RepoRoot $repo','$historical = Get-MIR42HistoricalEngineDescriptor -RepoRoot $repo -Target $target','$runKind = if ($isNineTargetCandidate)','kind=$runKind','status=$runStatus')) {
  if (-not ($runner.Contains($needle) -or $harness.Contains($needle))) { throw "historical-runtime-contract $needle" }
}
$logClear = '[IO.File]::WriteAllText($log, '''', [Text.UTF8Encoding]::new($false))'
$firstClear = $harness.IndexOf($logClear,[StringComparison]::Ordinal)
$firstReload = $harness.IndexOf('$reloadExitCode = ',[StringComparison]::Ordinal)
$secondClear = $harness.IndexOf($logClear,$firstReload,[StringComparison]::Ordinal)
$secondReload = $harness.IndexOf('$secondReloadExitCode = ',[StringComparison]::Ordinal)
if ($firstClear -lt 0 -or $firstReload -lt 0 -or $secondClear -le $firstReload -or $secondReload -le $secondClear -or
    $runner.Contains('$targetRow.engine.path') -or $runner.Contains('kind=(if ($isNineTargetCandidate)') -or $runner.Contains('status=(if ($isNineTargetCandidate)')) { throw 'historical-runner-shape-or-reload-log-scope' }

Write-Output 'MIR42-NINE-TARGET-HISTORICAL-ENGINE-RUN-PRECHECK-PASSED targets=5 engines=0'
