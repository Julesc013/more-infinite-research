param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path,
  [switch]$SharedInputsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')

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
function Assert-MIR42EngineSharedInputs {
  . (Join-Path $RepoRoot 'tools/lib/validation/NativeProbeResources.ps1')
  . (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
  # Controlled capacity applies only to tiny inputs and one PowerShell child.
  # The historical fresh-load actor is a stub; no Factorio process runs here.
  function Get-MIR441ResourceSnapshot {
    param([string]$WorkRoot)
    [pscustomobject]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');memory=[pscustomobject]@{total_bytes=16GB;free_bytes=12GB;committed_bytes=4GB;commit_limit_bytes=20GB};system_volume=[pscustomobject]@{free_bytes=100GB};work_volume=[pscustomobject]@{free_bytes=100GB}}
  }
  function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw "Engine shared inputs: $Message"};$script:engineSharedAssertions++}
  function Refuses([scriptblock]$Action,[string]$Expected){$failure='';try{& $Action|Out-Null}catch{$failure=$_.Exception.Message};Check ($failure.Contains($Expected)) "expected $Expected; got $failure"}
  $script:engineSharedAssertions=0
  $scratch=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $RepoRoot ('build/tmp/engine-link-controls-'+[guid]::NewGuid().ToString('N')))
  $inputLeases=[Collections.Generic.List[object]]::new()
  foreach($name in @('Get-MIR42EngineRunSha','Invoke-MIR42BoundedUpgrade','Invoke-MIR42HistoricalFreshLoad','New-MIR42EngineArchiveStage')){
    Import-MIR42EngineRunnerFunction -Path $runnerPath -Name $name
  }
  try {
    $null=New-Item -ItemType Directory -Path $scratch
    $exactRoot=Join-Path $scratch 'campaign'
    Refuses {New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot $exactRoot -UseExactOutputRoot} 'peak-budget-required'
    Check (-not (Test-Path -LiteralPath $exactRoot)) 'missing peak allocated output.'
    $resources=New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot $exactRoot -ExpectedPeakMemoryMiB 256 -MaxNewOutputMiB 4 -UseExactOutputRoot
    Check ($resources.root -ceq $exactRoot -and -not (Test-Path -LiteralPath $exactRoot)) 'exact-root admission allocated or changed the output path.'
    $null=New-Item -ItemType Directory -Path $exactRoot
    $empty=New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot $exactRoot -ExpectedPeakMemoryMiB 256 -MaxNewOutputMiB 4 -UseExactOutputRoot
    Check ($empty.root -ceq $exactRoot) 'empty exact root rejected or changed.'
    $sentinel=Join-Path $exactRoot 'retained.txt';[IO.File]::WriteAllText($sentinel,'retained')
    Refuses {New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot $exactRoot -ExpectedPeakMemoryMiB 256 -UseExactOutputRoot} 'exact-output-not-empty'
    Refuses {New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot $sentinel -ExpectedPeakMemoryMiB 256 -UseExactOutputRoot} 'exact-output-not-empty'
    Check ((Get-Content -Raw -LiteralPath $sentinel) -ceq 'retained') 'occupied-root refusal changed existing state.'
    $default=New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot $scratch -ExpectedPeakMemoryMiB 256 -MaxNewOutputMiB 4
    Check ($default.root -cne $scratch -and (Test-MIR441PathContained -Root $scratch -Path $default.root)) 'default isolated-root contract changed.'

    $sourceRoot=Join-Path $scratch 'inputs';$null=New-Item -ItemType Directory -Path $sourceRoot
    $rows=[ordered]@{};$originals=[ordered]@{}
    foreach($target in @('f210','f200','f110','f100','f017','f016','f015','f014','f013')){
      $to='4.2.'+$target.Substring(1)+'01';$from='4.2.'+$target.Substring(1)+'00'
      $candidate=Join-Path $sourceRoot "more-infinite-research_$to.zip";$predecessor=Join-Path $sourceRoot "more-infinite-research_$from.zip"
      [IO.File]::WriteAllText($candidate,"tiny candidate $target");[IO.File]::WriteAllText($predecessor,"tiny predecessor $target")
      $row=[ordered]@{candidate=$candidate;candidate_sha256=Get-MIRImmutableInputSha256 $candidate;predecessor=$predecessor;predecessor_sha256=Get-MIRImmutableInputSha256 $predecessor;to=$to;from=$from}
      $rows[$target]=$row;$originals[$target]=$candidate
      New-MIR42EngineArchiveStage -Target $target -Row $row -OutputRoot $exactRoot -SourceVersion '4.2.1' -SourceCommit ('A'*40) -Context $resources -Leases $inputLeases
      $lease=$inputLeases[$inputLeases.Count-1]
      Check ($lease.record.require_hard_links -and $lease.record.inputs.Count -eq 2) "$target did not lease both inputs."
      foreach($input in $lease.record.inputs){Check ($input.staging_mode -ceq 'hardlink' -and (Get-MIRImmutableInputFileIdentity $input.source_path) -ceq (Get-MIRImmutableInputFileIdentity $input.stage_path)) "$target copied $($input.role)."}
      Check ($row.candidate -cne $candidate -and $row.predecessor -ceq $predecessor) "$target changed predecessor authority or failed to select the candidate alias."
      Refuses {[IO.File]::WriteAllText($candidate,'attempted mutation')} 'used by another process'
    }
    Check ($resources.aliases.Count -eq 18 -and $resources.shared_alias_bytes -eq [int64](($inputLeases|ForEach-Object {$_.record.inputs}|ForEach-Object {(Get-Item -LiteralPath $_.stage_path).Length}|Measure-Object -Sum).Sum)) 'archive alias accounting differs.'
    Check ((Get-MIRNativeProbeRemainingOutputBytes -Context $resources) -gt 0) 'tiny aliases exhausted the output budget.'

    $script:engineArchiveCopies=0
    function New-Item {[CmdletBinding()]param([string]$ItemType,[string[]]$Path,[string]$Target,[switch]$Force);if($ItemType -ceq 'HardLink'){throw 'controlled link failure'};Microsoft.PowerShell.Management\New-Item @PSBoundParameters}
    function Copy-Item {$script:engineArchiveCopies++;throw 'copy attempted'}
    try {
      $blocked=[ordered]@{};foreach($key in $rows.f210.Keys){$blocked[$key]=$rows.f210[$key]}
      Refuses {New-MIR42EngineArchiveStage -Target blocked -Row $blocked -OutputRoot $exactRoot -SourceVersion '4.2.1' -SourceCommit ('A'*40) -Context $resources -Leases $inputLeases} 'requires a verified hard link'
      Check ($script:engineArchiveCopies -eq 0) 'unavailable link invoked archive copying.'
    } finally {Remove-Item Function:\New-Item;Remove-Item Function:\Copy-Item}

    # Real governed child proves capture relocation and the shared inventory.
    $stdout=Join-Path $exactRoot 'row.stdout.txt';$stderr=Join-Path $exactRoot 'row.stderr.txt'
    $code=Invoke-MIR42BoundedUpgrade -PowerShell (Get-Command pwsh).Source -Arguments @('-NoProfile','-Command','[Console]::WriteLine("tiny actor"); [Console]::Error.WriteLine("tiny stderr")') -StdoutPath $stdout -StderrPath $stderr -DeadlineSeconds 15 -NativeActor
    Check ($code -eq 0 -and (Get-Content -Raw $stdout).Contains('tiny actor') -and (Get-Content -Raw $stderr).Contains('tiny stderr')) 'governed worker lost captured output.'
    Check ($resources.runs.Count -eq 1 -and $resources.runs[0].stdout -ceq $stdout -and $resources.runs[0].stderr -ceq $stderr -and $resources.runs[0].status -ceq 'passed') 'relocated captures were not reflected in the process inventory.'
    Refuses {Invoke-MIR42BoundedUpgrade -PowerShell (Get-Command pwsh).Source -Arguments @('-NoProfile','-Command','exit 0') -StdoutPath (Join-Path $scratch 'outside.txt') -StderrPath $stderr -DeadlineSeconds 15 -NativeActor} 'must remain below'
    Check ($resources.runs.Count -eq 1) 'outside capture launched another actor.'
    Refuses {Invoke-MIR42BoundedUpgrade -PowerShell (Get-Command pwsh).Source -Arguments @('-NoProfile','-Command','exit 7') -StdoutPath (Join-Path $exactRoot 'failed.stdout.txt') -StderrPath (Join-Path $exactRoot 'failed.stderr.txt') -DeadlineSeconds 15 -NativeActor} 'mir441-process-exit'
    Check ($resources.runs.Count -eq 2 -and $resources.runs[1].status -ceq 'interrupted' -and (Test-Path $resources.runs[1].ledger)) 'failed worker lost its interruption record.'
    $legacyStdout=Join-Path $exactRoot 'upgrade-worker.stdout.txt';$legacyStderr=Join-Path $exactRoot 'upgrade-worker.stderr.txt'
    $code=Invoke-MIR42BoundedUpgrade -PowerShell (Get-Command pwsh).Source -Arguments @('-NoProfile','-Command','[Console]::WriteLine("tiny governed-worker transport")') -StdoutPath $legacyStdout -StderrPath $legacyStderr -DeadlineSeconds 15
    Check ($code -eq 0 -and $resources.runs.Count -eq 2 -and (Get-Content -Raw $legacyStdout).Contains('tiny governed-worker transport')) 'upgrade transport took a second governor or lost its output.'
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($runnerPath,[ref]$tokens,[ref]$errors)
    $argumentNode=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Extent.Text.StartsWith('$args = @(')},$true))
    Check ($argumentNode.Count -eq 1) 'upgrade argument construction is ambiguous.'
    $harness='controlled harness';$repo=$RepoRoot;$rowRoot=Join-Path $exactRoot 'row';$row=$rows.f210;$row.engine='controlled';$row.fixture='controlled';$receiptPath=Join-Path $rowRoot 'upgrade.json';$ExpectedPeakMemoryMiB=256
    . ([scriptblock]::Create($argumentNode[0].Extent.Text+"`n"+'$builtArguments=$args'))
    Check ($builtArguments[[Array]::IndexOf($builtArguments,'-ExpectedPeakMemoryMiB')+1] -ceq '256' -and [int]$builtArguments[[Array]::IndexOf($builtArguments,'-MaxNewOutputMiB')+1] -gt 0 -and [int]$builtArguments[[Array]::IndexOf($builtArguments,'-MaxNewOutputMiB')+1] -lt 4) 'upgrade worker lost the declared peak or remaining output allowance.'

    # The following actor synthesizes outputs, solely to exercise retained
    # fresh-load oracles and version admission. It proves no native gameplay.
    function Invoke-MIR42BoundedUpgrade {
      param($PowerShell,$Arguments,$StdoutPath,$StderrPath,$DeadlineSeconds,[switch]$NativeActor)
      $config=$Arguments[[Array]::IndexOf($Arguments,'--config')+1]
      $mods=$Arguments[[Array]::IndexOf($Arguments,'--mod-directory')+1]
      $save=$Arguments[[Array]::IndexOf($Arguments,'--create')+1]
      Check ($NativeActor -and $DeadlineSeconds -eq 60 -and $Arguments -contains '--no-log-rotation') 'fresh actor changed arguments or deadline.'
      Check (($Arguments -contains '--disable-audio') -eq ($freshLine -notin @('0.13','0.14'))) 'historical audio capability changed.'
      $modList=Get-Content -Raw -LiteralPath (Join-Path $mods 'mod-list.json')|ConvertFrom-Json
      Check (($modList.mods.name -join '|') -ceq 'base|more-infinite-research' -and (Get-Content -Raw $config).Contains('[path]')) 'fresh load lost private configuration.'
      $display=(($freshVersion -split '\.')|ForEach-Object {[int]$_})-join '.'
      $log=Join-Path (Split-Path -Parent $mods) 'factorio-current.log'
      if($freshFailure -cne 'missing'){[IO.File]::WriteAllText($save,'tiny save')}
      [IO.File]::WriteAllText($log,"Loading mod more-infinite-research $display`nFactorio initialised`nCreating new map`nMap version controlled`n$freshFailure")
      [IO.File]::WriteAllText($StdoutPath,'tiny controlled output');[IO.File]::WriteAllText($StderrPath,'')
      return 0
    }
    $engineRoot=Join-Path $scratch 'controlled-engine';$engine=Join-Path $engineRoot 'bin/x64/factorio.exe'
    $null=New-Item -ItemType Directory -Path (Split-Path -Parent $engine),(Join-Path $engineRoot 'data/base')
    [IO.File]::WriteAllText($engine,'tiny engine identity never executed');$engineHash=Get-MIRImmutableInputSha256 $engine
    $freshFailure='';$freshRoots=[Collections.Generic.List[string]]::new()
    foreach($target in @('f017','f016','f015','f014','f013')){foreach($patch in @(0,1)){
      $freshLine='0.'+$target.Substring(2);$freshVersion='4.2.'+$target.Substring(1)+('0'+$patch)
      $candidate=Join-Path $sourceRoot "more-infinite-research_$freshVersion.zip"
      $root=Join-Path $exactRoot "fresh-$target-$patch";$freshRoots.Add($root)
      $freshParams=@{Target=$target;FactorioLine=$freshLine;Engine=$engine;EngineSha256=$engineHash;Candidate=$candidate;CandidateSha256=Get-MIRImmutableInputSha256 $candidate;Version=$freshVersion;SourceVersion="4.2.$patch";FreshRoot=$root;SourceCommit=('A'*40);DeadlineSeconds=60}
      $result=Invoke-MIR42HistoricalFreshLoad @freshParams
      $receipt=Get-Content -Raw -LiteralPath $result.receipt.path|ConvertFrom-Json -Depth 100
      Check ($receipt.candidate.version -ceq $freshVersion -and (Test-MIR4BootstrapRecordHash $receipt) -and $inputLeases[$inputLeases.Count-1].closed) "$target/$patch did not preserve the fresh receipt or close custody."
      Check ((Get-MIRImmutableInputFileIdentity $candidate) -ceq (Get-MIRImmutableInputFileIdentity (Join-Path $root "work/user/mods/$([IO.Path]::GetFileName($candidate))"))) "$target/$patch copied the fresh input."
    }}
    Check (@($freshRoots|ForEach-Object {Get-MIRImmutableInputFileIdentity (Join-Path $_ 'work/user/mods/mod-list.json')}|Sort-Object -Unique).Count -eq 10) 'fresh writable controls share identities.'
    foreach($badVersion in @('4.2.01300','4.2.01302','4.2.01401')){
      $freshParams.Version=$badVersion;$freshParams.FreshRoot=Join-Path $exactRoot ('rejected-'+$badVersion)
      Refuses {Invoke-MIR42HistoricalFreshLoad @freshParams} 'historical-fresh-target-binding'
      Check (-not (Test-Path $freshParams.FreshRoot)) 'bad maintenance identity allocated staging.'
    }
    $freshParams.Version='4.2.01301';$freshParams.FactorioLine='0.14'
    Refuses {Invoke-MIR42HistoricalFreshLoad @freshParams} 'historical-fresh-target-binding'
    $freshParams.FactorioLine='0.13'
    $freshParams.CandidateSha256='0'*64;$freshParams.FreshRoot=Join-Path $exactRoot 'hash-drift'
    Refuses {Invoke-MIR42HistoricalFreshLoad @freshParams} 'historical-fresh-input-drift'
    Check (-not (Test-Path (Join-Path $freshParams.FreshRoot 'summary.json'))) 'input drift produced an accepted receipt.'
    $freshParams.CandidateSha256=Get-MIRImmutableInputSha256 $freshParams.Candidate
    foreach($failure in @('missing','Error controlled opposing log')){
      $freshFailure=$failure;$freshParams.FreshRoot=Join-Path $exactRoot ('failed-'+[guid]::NewGuid().ToString('N'))
      $expected=if($failure -ceq 'missing'){'historical-fresh-output-missing'}else{'historical-fresh-log-content'}
      Refuses {Invoke-MIR42HistoricalFreshLoad @freshParams} $expected
      Check (-not (Test-Path (Join-Path $freshParams.FreshRoot 'summary.json'))) 'failed fresh oracle produced an accepted receipt.'
      $null=Complete-MIRImmutableInputLease -Lease $inputLeases[$inputLeases.Count-1] -Outcome failed
    }
    foreach($lease in $inputLeases){if(-not $lease.closed){$terminal=Complete-MIRImmutableInputLease -Lease $lease -Outcome passed;$null=Assert-MIRImmutableInputTerminalReceipt -Receipt $terminal}}
    foreach($lease in $inputLeases){
      $root=[string]$lease.record.run_root
      if($lease.record.state -ceq 'failed'){
        Refuses {Assert-MIRImmutableInputLeaseReclaimable -RunRoot $root -Context 'failed tiny engine stage'} 'retains immutable-input custody'
        continue
      }
      $null=Assert-MIRImmutableInputLeaseReclaimable -RunRoot $root -Context 'completed tiny engine stage'
      $null=Assert-MIRImmutableInputPathWithin -Path $root -Root $exactRoot -Context 'owned tiny stage retirement'
      Remove-Item -LiteralPath $root -Recurse
    }
    foreach($target in $originals.Keys){Check ((Test-Path -LiteralPath $originals[$target] -PathType Leaf) -and (Get-MIRImmutableInputSha256 $originals[$target]) -ceq $rows[$target].candidate_sha256) 'stage retirement lost or changed a shared source input.'}
    Write-Output "MIR42-ENGINE-SHARED-INPUTS-PASSED assertions=$script:engineSharedAssertions archives=18 fresh_version_controls=10 factorio_processes=0"
  } finally {
    foreach($lease in $inputLeases){if(-not $lease.closed){$null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed}}
    foreach($name in @('Invoke-MIR42BoundedUpgrade','Invoke-MIR42HistoricalFreshLoad','New-MIR42EngineArchiveStage')){Remove-Item -LiteralPath "function:script:$name" -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $scratch){$null=Assert-MIRImmutableInputPathWithin -Path $scratch -Root (Join-Path $RepoRoot 'build/tmp') -Context 'owned tiny engine controls';Remove-Item -LiteralPath $scratch -Recurse -Force}
  }
}
Assert-MIR42EngineSharedInputs
if($SharedInputsOnly){return}
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
    $patchDescriptor=Get-MIR42HistoricalEngineDescriptor -RepoRoot $RepoRoot -Target $target -SourceVersion '4.2.1'
    $patchIdentity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $target.Substring(1) -SourceMinor 2 -SourcePatch 1
    if([string]$patchDescriptor.to-cne[string]$patchIdentity.distribution_version-or
       [string]$patchDescriptor.from-cne[string]$descriptor.from-or
       [string]$patchDescriptor.historical.predecessor.sha256-cne[string]$descriptor.historical.predecessor.sha256-or
       [string]$patchDescriptor.historical.engine.sha256-cne[string]$descriptor.historical.engine.sha256-or
       [string]$patchDescriptor.historical.target_record.record_sha256-cne[string]$descriptor.historical.target_record.record_sha256){throw "patch-descriptor-binding $target"}

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
if (-not $harness.Contains("`$serverReload = `$isHistoricalTerminalFixture -and `$historicalLine -in @('0.15','0.16')") -or
    -not $harness.Contains('$reloadExitCode = if ($serverReload)') -or
    -not $harness.Contains('$secondReloadExitCode = if ($serverReload)')) {
  throw 'historical-015-016-reloads-must-use-server-path'
}
$historicalFreshCall = $runner.IndexOf('$freshLoads = @(Invoke-MIR42HistoricalFreshLoad -Target $target',[StringComparison]::Ordinal)
$historicalFreshBranch = if ($historicalFreshCall -ge 0) { $runner.LastIndexOf('if ($isHistoricalTarget) {',$historicalFreshCall,[StringComparison]::Ordinal) } else { -1 }
$modernFreshCall = $runner.IndexOf("`$freshArgs = @('-NoProfile'",[StringComparison]::Ordinal)
$modernFreshElse = if ($historicalFreshCall -ge 0) { $runner.IndexOf('} else {',$historicalFreshCall,[StringComparison]::Ordinal) } else { -1 }
if ($historicalFreshBranch -lt 0 -or $historicalFreshCall -le $historicalFreshBranch -or
    $modernFreshElse -le $historicalFreshCall -or $modernFreshCall -le $modernFreshElse -or
    -not $runner.Contains("[mir42-`$Target-historical-fresh-log-content]")) {
  throw 'historical-fresh-load-must-bypass-modern-scenario-worker'
}
foreach ($needle in @('$isHistoricalTerminalFixture = $FixtureName -eq ''assert-upgrade-historical-terminal-to-mir42''','$isLegacyFactorio = $isHistoricalTerminalFixture -or','MIR historical upgrade specialization requires an exact terminal predecessor','historical-terminal-source-state-retained','historical-terminal-infinite-bonus-retained-where-supported','$historicalHarness = Assert-MIR42HistoricalUpgradeHarness -RepoRoot $repo','$historical = Get-MIR42HistoricalEngineDescriptor -RepoRoot $repo -Target $target','kind=$runKind','status=$runStatus')) {
  if (-not ($runner.Contains($needle) -or $harness.Contains($needle))) { throw "historical-runtime-contract $needle" }
}
$tokens=$null;$errors=$null
$runnerAst=[Management.Automation.Language.Parser]::ParseFile($runnerPath,[ref]$tokens,[ref]$errors)
if(@($errors).Count-ne0){throw 'historical-record-selector-parse'}
$recordSelectors=@(foreach($prefix in @('$runKind = ','$runStatus = ')){
  $nodes=@($runnerAst.EndBlock.Statements|Where-Object {$_.Extent.Text.StartsWith($prefix)})
  if($nodes.Count-ne1){throw 'historical-record-selector-definition'}
  $nodes[0].Extent.Text
})
$recordSelector=[scriptblock]::Create(($recordSelectors-join"`n"))
foreach($case in @(
  @{nine=$false;maintenance=$null;kind='MIR42FourTargetEngineRunV1';status='four-target-base-default-real-engine-probes-passed-private-unqualified'},
  @{nine=$true;maintenance=$null;kind='MIR42NineTargetEngineRunV1';status='nine-target-base-default-real-engine-probes-passed-private-unqualified'},
  @{nine=$true;maintenance=[pscustomobject]@{fixture=$true};kind='MIR42NineTargetMaintenanceEngineRunV1';status='nine-target-maintenance-base-default-real-engine-probes-passed-private-unqualified'}
)){
  $isNineTargetCandidate=$case.nine;$maintenanceInputs=$case.maintenance
  . $recordSelector
  if($runKind-cne$case.kind-or$runStatus-cne$case.status){throw 'historical-record-selector-contract'}
}
$logClear = '[IO.File]::WriteAllText($log, '''', [Text.UTF8Encoding]::new($false))'
$firstClear = $harness.IndexOf($logClear,[StringComparison]::Ordinal)
$firstReload = $harness.IndexOf('$reloadExitCode = ',[StringComparison]::Ordinal)
$secondClear = $harness.IndexOf($logClear,$firstReload,[StringComparison]::Ordinal)
$secondReload = $harness.IndexOf('$secondReloadExitCode = ',[StringComparison]::Ordinal)
if ($firstClear -lt 0 -or $firstReload -lt 0 -or $secondClear -le $firstReload -or $secondReload -le $secondClear -or
    $runner.Contains('$targetRow.engine.path') -or $runner.Contains('kind=(if ($isNineTargetCandidate)') -or $runner.Contains('status=(if ($isNineTargetCandidate)')) { throw 'historical-runner-shape-or-reload-log-scope' }

Write-Output 'MIR42-NINE-TARGET-HISTORICAL-ENGINE-RUN-PRECHECK-PASSED targets=5 source_versions=2 record_selectors=3 engines=0'
