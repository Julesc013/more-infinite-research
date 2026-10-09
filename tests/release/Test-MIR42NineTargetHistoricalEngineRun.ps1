param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path,
  [switch]$SharedInputsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/DistributionCustody.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/ImmutableInputStaging.ps1')

function Assert-MIR42HistoricalPredecessorCustody {
  param([Parameter(Mandatory)][string]$Version,[Parameter(Mandatory)][string]$ExpectedSha256,
    [Parameter(Mandatory)][string]$LocalPath)
  $distribution=Get-MIR4DistributionCustodyEntry -RepoRoot $RepoRoot -Version $Version
  if([string]$distribution.sha256 -cne $ExpectedSha256 -or
      [string]$distribution.path -cne ('dist/more-infinite-research_'+$Version+'.zip')){throw "historical-predecessor-authority $Version"}
  # Stream the pinned blob into the existing verifier, without restoring ZIPs.
  $null=Test-MIR4DistributionHistoricalCustody -RepoRoot $RepoRoot -Distribution $distribution
  if((Test-Path -LiteralPath $LocalPath) -and -not (Test-MIR4DistributionCustodyFile -Path $LocalPath -Distribution $distribution)){
    throw "historical-predecessor-local-drift $Version"
  }
}

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
  . (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
  function Write-TinyEngineArchive($Path,$Version,$Line){
    $zip=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create)
    try{
      $writer=[IO.StreamWriter]::new($zip.CreateEntry("more-infinite-research_$Version/info.json").Open())
      try{$writer.Write((@{name='more-infinite-research';version=$Version;factorio_version=$Line;dependencies=@('base')}|ConvertTo-Json -Compress))}finally{$writer.Dispose()}
    }finally{$zip.Dispose()}
  }
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
  foreach($name in @('Assert-MIR42EngineRunFile','Get-MIR42HistoricalEngineDescriptor','Get-MIR42EngineRunSha','Get-MIR42EngineLibraryBindings','Invoke-MIR42BoundedUpgrade','Invoke-MIR42HistoricalFreshLoad','New-MIR42EngineArchiveStage')){
    Import-MIR42EngineRunnerFunction -Path $runnerPath -Name $name
  }
  try {
    $null=New-Item -ItemType Directory -Path $scratch
    # A fresh PowerShell scope must preserve failures before lease allocation.
    # Running in this test scope would accidentally supply its own $inputLeases
    # and conceal the StrictMode regression in the runner's script-wide trap.
    $earlyFailure=Join-Path $scratch 'early-failure.ps1'
    [IO.File]::WriteAllText($earlyFailure,@'
param([string]$Repository,[string]$Scratch)
$ErrorActionPreference='Stop'
$arguments=@{RepoRoot=$Repository;CandidateManifestPath=(Join-Path $Scratch 'absent.json');OutputRoot=(Join-Path $Scratch 'never-created')}
foreach($target in @('F210','F200','F110','F100')){$arguments[$target+'Engine']='not-executed';$arguments[$target+'Predecessor']='not-read'}
try{& (Join-Path $Repository 'tools/commands/release/Invoke-MIR42FourTargetEngineRun.ps1') @arguments;throw 'Unexpected runner success'}catch{[Console]::Out.WriteLine($_.Exception.Message)}
'@)
    $start=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    foreach($arg in @('-NoProfile','-File',$earlyFailure,'-Repository',$RepoRoot,'-Scratch',$scratch)){[void]$start.ArgumentList.Add($arg)}
    $child=[Diagnostics.Process]::Start($start)
    try{
      $stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync()
      if(-not$child.WaitForExit(20000)){$child.Kill($true);$child.WaitForExit();throw 'Early-failure control exceeded its deadline'}
      Check ($child.ExitCode-eq0 -and $stdout.Result.Contains('[mir42-candidate-manifest-missing]') -and [string]::IsNullOrWhiteSpace($stderr.Result)) ('early runner failure was masked: '+$stdout.Result+$stderr.Result)
      Check (-not(Test-Path -LiteralPath (Join-Path $scratch 'never-created'))) 'early runner refusal allocated output'
    }finally{$child.Dispose()}
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
    $bindingsPath=Join-Path $scratch 'bindings.json'
    Refuses {Get-MIR42EngineLibraryBindings -Path $bindingsPath -Targets @('f210')} 'library-bindings-required'
    [IO.File]::WriteAllText($bindingsPath,(@{f210=$sourceRoot}|ConvertTo-Json))
    Check ((Get-MIR42EngineLibraryBindings -Path $bindingsPath -Targets @('f210')).f210 -ceq $sourceRoot) 'explicit library binding changed.'
    Refuses {Get-MIR42EngineLibraryBindings -Path $bindingsPath -Targets @('f210','f200')} 'library-bindings-targets'
    Refuses {Get-MIR42EngineLibraryBindings -Path $bindingsPath -Targets @('f200')} 'library-missing'
    $rows=[ordered]@{};$originals=[ordered]@{}
    foreach($target in @('f210','f200','f110','f100','f017','f016','f015','f014','f013')){
      $to='4.2.'+$target.Substring(1)+'01';$from='4.2.'+$target.Substring(1)+'00'
      $candidate=Join-Path $sourceRoot "more-infinite-research_$to.zip";$predecessor=Join-Path $sourceRoot "more-infinite-research_$from.zip"
      $line=switch($target){f210{'2.1'};f200{'2.0'};f110{'1.1'};f100{'1.0'};default{'0.'+$target.Substring(2)}}
      Write-TinyEngineArchive $candidate $to $line;Write-TinyEngineArchive $predecessor $from $line
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
    $target='f210';$libraryBindings=@{f210=$sourceRoot};$sourceVersion='4.2.2'
    . ([scriptblock]::Create($argumentNode[0].Extent.Text+"`n"+'$builtArguments=$args'))
    Check ($builtArguments[[Array]::IndexOf($builtArguments,'-ExpectedPeakMemoryMiB')+1] -ceq '256' -and [int]$builtArguments[[Array]::IndexOf($builtArguments,'-MaxNewOutputMiB')+1] -gt 0 -and [int]$builtArguments[[Array]::IndexOf($builtArguments,'-MaxNewOutputMiB')+1] -lt 4) 'upgrade worker lost the declared peak or remaining output allowance.'
    Check ($builtArguments[[Array]::IndexOf($builtArguments,'-LocalModLibraryDirs')+1] -ceq $sourceRoot) 'upgrade worker lost the selected direct library.'
    Check ($builtArguments[[Array]::IndexOf($builtArguments,'-SourceVersion')+1] -ceq '4.2.2') 'upgrade worker lost its maintenance source version.'
    $sourceVersion='4.2.0'
    . ([scriptblock]::Create($argumentNode[0].Extent.Text+"`n"+'$builtArguments=$args'))
    Check ($builtArguments[[Array]::IndexOf($builtArguments,'-SourceVersion')+1] -ceq '4.2.1') 'original base-upgrade invocation lost the harness historical default.'
    $authorityNode=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$script:MIR42HistoricalTerminalInputs'},$true))
    Check ($authorityNode.Count-eq1) 'historical engine authority assignment is ambiguous.'
    . ([scriptblock]::Create($authorityNode[0].Extent.Text))
    foreach($historicalTarget in @('f017','f016','f015','f014','f013')){
      $boundEngine=Join-Path $scratch "relocated/$historicalTarget/factorio.exe"
      $baseline=Get-MIR42HistoricalEngineDescriptor -RepoRoot $RepoRoot -Target $historicalTarget
      foreach($patch in @(1,2)){
        $descriptor=Get-MIR42HistoricalEngineDescriptor -RepoRoot $RepoRoot -Target $historicalTarget -SourceVersion "4.2.$patch" -EnginePath $boundEngine
        Check ($descriptor.to-ceq('4.2.'+$historicalTarget.Substring(1)+'0'+$patch)-and$descriptor.engine-ceq$boundEngine-and$descriptor.historical.engine.sha256-ceq$baseline.historical.engine.sha256-and$descriptor.historical.predecessor.sha256-ceq$baseline.historical.predecessor.sha256) "$historicalTarget maintenance $patch changed its retained authority or target identity."
        foreach($badPath in @('','relative/factorio.exe')){
          Refuses {Get-MIR42HistoricalEngineDescriptor -RepoRoot $RepoRoot -Target $historicalTarget -SourceVersion "4.2.$patch" -EnginePath $badPath} "mir421-$historicalTarget-local-engine-binding-required"
        }
      }
    }
    # Exercise the actual joined-runner call site. Published byte custody is
    # tested separately by the real predecessor reader; no network runs here.
    $maintenanceNode=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith('if (-not [string]::IsNullOrWhiteSpace($PublishedMaintenancePredecessorManifestPath))')},$true))
    Check ($maintenanceNode.Count-eq1) 'maintenance input call site is ambiguous.'
    function gh {param($Verb,$Route);$script:observedReleaseRoute=$Route;$global:LASTEXITCODE=0;return '{}'}
    function Get-MIR42PublishedMaintenancePredecessorInputs {
      param($RepoRoot,$ManifestPath,$ReleaseMetadata,$CandidateSourceVersion)
      $script:observedCustodySource=$CandidateSourceVersion
      Check ($ManifestPath-ceq'controlled-published.json') 'joined runner dropped the supplied manifest.'
      return [pscustomobject]@{targets=@($selected.Keys|ForEach-Object {[pscustomobject]@{target=$_;path=$selected[$_].predecessor;version=('4.2.'+$_.Substring(1)+'0'+(([version]$CandidateSourceVersion).Build-1))}})}
    }
    try{
      $PublishedMaintenancePredecessorManifestPath='controlled-published.json';$isNineTargetCandidate=$true
      $script:MIR42ModernEngineTargets=@('f210','f200','f110','f100')
      foreach($sourceVersion in @('4.2.1','4.2.2')){
        $selected=[ordered]@{}
        foreach($id in $rows.Keys){$selected[$id]=[ordered]@{predecessor=$rows[$id].predecessor;from='unselected'}}
        . ([scriptblock]::Create($maintenanceNode[0].Extent.Text))
        $tag=if($sourceVersion-ceq'4.2.2'){'v4.2.1'}else{'v4.2.0-stable'}
        Check ($script:observedReleaseRoute-ceq('repos/Julesc013/more-infinite-research/releases/tags/'+$tag)-and$script:observedCustodySource-ceq$sourceVersion) 'joined runner selected the wrong publication or custody contract.'
        foreach($id in $selected.Keys){Check ($selected[$id].from-ceq('4.2.'+$id.Substring(1)+'0'+(([version]$sourceVersion).Build-1))-and$selected[$id].maintenance_predecessor.target-ceq$id) "$id lost selected published predecessor identity."}
      }
      $sourceVersion='4.2.0'
      Refuses {. ([scriptblock]::Create($maintenanceNode[0].Extent.Text))} 'maintenance-predecessor-candidate-scope'
      $sourceVersion='4.2.2';$isNineTargetCandidate=$false
      Refuses {. ([scriptblock]::Create($maintenanceNode[0].Extent.Text))} 'maintenance-predecessor-candidate-scope'
    }finally{Remove-Item Function:\gh;Remove-Item Function:\Get-MIR42PublishedMaintenancePredecessorInputs}

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
      Check (($modList.mods.name -join '|') -ceq 'base|more-infinite-research' -and (Get-Content -Raw $config).Contains('[path]') -and $mods -ceq $sourceRoot) 'fresh load lost direct library or private configuration.'
      Check (-not(Test-Path -LiteralPath (Join-Path $mods 'mod-settings.dat'))) 'fresh load inherited settings.'
      $display=(($freshVersion -split '\.')|ForEach-Object {[int]$_})-join '.'
      $userPath=[regex]::Match((Get-Content -Raw $config),'(?m)^write-data=(.+)$').Groups[1].Value.Trim()
      $log=Join-Path $userPath 'factorio-current.log'
      if($freshFailure -cne 'missing'){[IO.File]::WriteAllText($save,'tiny save')}
      [IO.File]::WriteAllText($log,"Loading mod base $freshLine.1 (data.lua)`nLoading mod more-infinite-research $display (data.lua)`nFactorio initialised`nCreating new map`nMap version controlled`n$freshFailure")
      [IO.File]::WriteAllText($StdoutPath,'tiny controlled output');[IO.File]::WriteAllText($StderrPath,'')
      return 0
    }
    $engineRoot=Join-Path $scratch 'controlled-engine';$engine=Join-Path $engineRoot 'bin/x64/factorio.exe'
    $null=New-Item -ItemType Directory -Path (Split-Path -Parent $engine),(Join-Path $engineRoot 'data/base')
    [IO.File]::WriteAllText($engine,'tiny engine identity never executed');$engineHash=Get-MIRImmutableInputSha256 $engine
    $oldList='{"mods":[{"name":"base","enabled":true}]}';$oldSettings=[byte[]](5,4,3,2,1)
    [IO.File]::WriteAllText((Join-Path $sourceRoot 'mod-list.json'),$oldList)
    [IO.File]::WriteAllBytes((Join-Path $sourceRoot 'mod-settings.dat'),$oldSettings)
    $freshFailure='';$freshRoots=[Collections.Generic.List[string]]::new()
    foreach($target in @('f017','f016','f015','f014','f013')){foreach($patch in @(0,1,2)){
      $freshLine='0.'+$target.Substring(2);$freshVersion='4.2.'+$target.Substring(1)+('0'+$patch)
      [IO.File]::WriteAllText((Join-Path $engineRoot 'data/base/info.json'),(@{name='base';version="$freshLine.1";dependencies=@()}|ConvertTo-Json))
      $candidate=Join-Path $sourceRoot "more-infinite-research_$freshVersion.zip"
      if($patch-eq2){Write-TinyEngineArchive $candidate $freshVersion $freshLine}
      $root=Join-Path $exactRoot "fresh-$target-$patch";$freshRoots.Add($root)
      $freshParams=@{Target=$target;FactorioLine=$freshLine;Engine=$engine;EngineSha256=$engineHash;Candidate=$candidate;CandidateSha256=Get-MIRImmutableInputSha256 $candidate;Version=$freshVersion;SourceVersion="4.2.$patch";FreshRoot=$root;SourceCommit=('A'*40);DeadlineSeconds=60;LibraryDirectory=$sourceRoot}
      $result=Invoke-MIR42HistoricalFreshLoad @freshParams
      $receipt=Get-Content -Raw -LiteralPath $result.receipt.path|ConvertFrom-Json -Depth 100
      Check ($receipt.candidate.version -ceq $freshVersion -and (Test-MIR4BootstrapRecordHash $receipt) -and $receipt.library_input_receipt.status -ceq 'restored-direct-library-controls') "$target/$patch did not preserve the fresh receipt or restore controls."
      Check (-not(Test-Path -LiteralPath (Join-Path $root 'work/user/mods')) -and $receipt.library_input_receipt.archive_links_created -eq 0 -and $receipt.library_input_receipt.dependency_payload_bytes_copied -eq 0) "$target/$patch materialized fresh inputs."
      Check ((Get-Content -Raw -LiteralPath (Join-Path $sourceRoot 'mod-list.json')) -ceq $oldList -and [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $sourceRoot 'mod-settings.dat'))) -ceq [Convert]::ToBase64String($oldSettings)) 'fresh actor failed to restore controls.'
    }}
    Check (@($freshRoots|ForEach-Object {Get-MIRImmutableInputFileIdentity (Join-Path $_ 'selection.json')}|Sort-Object -Unique).Count -eq 15) 'fresh definitions share identities.'
    $freshVersion='4.2.01301';$freshParams.SourceVersion='4.2.1'
    $freshParams.Candidate=Join-Path $sourceRoot 'more-infinite-research_4.2.01301.zip'
    $freshParams.CandidateSha256=Get-MIRImmutableInputSha256 $freshParams.Candidate
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
      Check ((Get-Content -Raw -LiteralPath (Join-Path $sourceRoot 'mod-list.json')) -ceq $oldList -and -not(Test-Path -LiteralPath (Join-Path $sourceRoot '.mir-active-profile.json'))) 'failed fresh actor did not restore controls.'
    }
    # Invoke the real modern package-smoke consumer with the real activation
    # adapter. Only the process and summary collector are substituted.
    Import-MIR42EngineRunnerFunction -Path (Join-Path $RepoRoot 'tools/lib/validation/runner/PackageSmoke.ps1') -Name Invoke-PackageZipSmokeScenario
    function Test-MIRScenarioSelected {return $true}
    function Resolve-MIRScenarioDeclaration {return @{group='controlled';timeout_seconds=60;assertions=@('saved','healthy')}}
    function Start-MIRValidationScenario {return @{status='running'}}
    function Complete-MIRValidationScenario {param($Record,$Status,$AssertionsExecuted,$ErrorMessage);$Record.status=$Status;$script:smokeStatus=$Status}
    function Clear-FactorioLog {if(Test-Path -LiteralPath $FactorioLog){[IO.File]::Delete($FactorioLog)}}
    function Get-MIRFileSha256 {param($Path);Get-MIRImmutableInputSha256 $Path}
    function Assert-RuntimeLogHealthy {if((Get-Content -Raw $FactorioLog).Contains('Error controlled')){throw 'controlled-unhealthy'}}
    function Invoke-FactorioProcess {
      param($FilePath,$Arguments,$TimeoutMs)
      $mods=$Arguments[[Array]::IndexOf($Arguments,'--mod-directory')+1]
      $save=$Arguments[[Array]::IndexOf($Arguments,'--create')+1]
      Check ($mods -ceq $sourceRoot -and $TimeoutMs -eq 60000) 'modern smoke lost direct library or deadline.'
      Check (-not(Test-Path -LiteralPath (Join-Path $mods 'mod-settings.dat'))) 'modern smoke inherited settings.'
      $selected=@((Get-Content -Raw (Join-Path $mods 'mod-list.json')|ConvertFrom-Json).mods|Where-Object enabled)
      Check ($selected.Count -eq $(if($smokeDlc){6}else{2})) 'modern smoke enabled an unrelated installed mod.'
      [IO.File]::WriteAllLines($FactorioLog,@($selected|ForEach-Object {"Loading mod $($_.name) $($_.version) (data.lua)"})+@('Factorio initialised','Creating new map'))
      if($smokeFailure -eq 'extra'){[IO.File]::AppendAllText($FactorioLog,"Loading mod surprise 1.0.0 (data.lua)`n")}
      if($smokeFailure -eq 'log'){[IO.File]::AppendAllText($FactorioLog,'Error controlled')}
      if($smokeFailure -ne 'save'){[IO.File]::WriteAllText($save,'tiny save')}
      if($smokeFailure -eq 'exit'){return 3};return 0
    }
    $scenarioRegistry=@{};$LibraryDirectory=$sourceRoot;$FactorioBin=$engine;$factorioReadData=Join-Path $engineRoot 'data'
    foreach($name in @('quality','elevated-rails','space-age','recycler')){
      $null=New-Item -ItemType Directory -Path (Join-Path $factorioReadData $name)
      [IO.File]::WriteAllText((Join-Path $factorioReadData "$name/info.json"),(@{name=$name;version='2.1.1';dependencies=@('base')}|ConvertTo-Json))
    }
    foreach($target in @('f210','f200','f110','f100')){
      $line=switch($target){f210{'2.1'};f200{'2.0'};f110{'1.1'};f100{'1.0'}}
      [IO.File]::WriteAllText((Join-Path $factorioReadData 'base/info.json'),(@{name='base';version="$line.1";dependencies=@()}|ConvertTo-Json))
      $repoInfo=@{version=$rows[$target].to};$script:ValidationPackageZipPath=$originals[$target]
      foreach($case in @('base','dlc','save','exit','extra','log')){
        if($case -eq 'dlc' -and $target -ne 'f210'){continue}
        $smokeDlc=$case -eq 'dlc';$smokeFailure=$case
        $validationRoot=Join-Path $exactRoot "smoke-$target-$case";$null=New-Item -ItemType Directory -Path $validationRoot
        $validationRootWithSeparator=$validationRoot+'\';$FactorioLog=Join-Path $validationRoot 'factorio-current.log';$factorioConfigPath=Join-Path $validationRoot 'config.ini'
        [IO.File]::WriteAllLines($factorioConfigPath,@('[path]',"read-data=$factorioReadData","write-data=$validationRoot",'[other]','enable-new-mods=false'))
        $script:smokeStatus=''
        if($case -in @('base','dlc')){Invoke-PackageZipSmokeScenario -ScenarioName 'package-zip-base' -EnableSpaceAge:$smokeDlc;Check ($script:smokeStatus -ceq 'passed') 'modern smoke did not finish.'}
        else{
          $errorText=switch($case){save{'did not create'};exit{'code 3'};extra{'loaded-selection'};log{'controlled-unhealthy'}}
          Refuses {Invoke-PackageZipSmokeScenario -ScenarioName 'package-zip-base'} $errorText
          Check ($script:smokeStatus -ceq 'failed') 'modern smoke accepted a failed actor.'
        }
        Check ((Get-Content -Raw (Join-Path $sourceRoot 'mod-list.json')) -ceq $oldList -and -not(Test-Path (Join-Path $sourceRoot '.mir-active-profile.json'))) 'modern smoke failed to restore controls.'
        Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $sourceRoot 'mod-settings.dat'))) -ceq [Convert]::ToBase64String($oldSettings)) 'modern smoke failed to restore settings.'
        Check (@(Get-ChildItem -LiteralPath $validationRoot -Directory -Recurse|Where-Object Name -EQ 'mods').Count -eq 0) 'modern smoke recreated a mods stage.'
      }
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
    Write-Output "MIR42-ENGINE-SHARED-INPUTS-PASSED assertions=$script:engineSharedAssertions archives=18 fresh_version_controls=15 factorio_processes=0"
  } finally {
    foreach($lease in $inputLeases){if(-not $lease.closed){$null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed}}
    foreach($name in @('Invoke-MIR42BoundedUpgrade','Invoke-MIR42HistoricalFreshLoad','New-MIR42EngineArchiveStage','Invoke-PackageZipSmokeScenario','Get-MIR42EngineLibraryBindings')){Remove-Item -LiteralPath "function:script:$name" -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $scratch){$null=Assert-MIRImmutableInputPathWithin -Path $scratch -Root (Join-Path $RepoRoot 'build/tmp') -Context 'owned tiny engine controls';Remove-Item -LiteralPath $scratch -Recurse -Force}
  }
}
Assert-MIR42EngineSharedInputs
function Test-MIR421MaintenanceEngineInputs {
  $script:engineInputChecks=0
  $scratch=''
  function Check([bool]$Condition,[string]$Message){if(-not$Condition){throw "[maintenance-engine-test] $Message"};$script:engineInputChecks++}
  function Refuses([scriptblock]$Action,[string]$Expected){$message='';try{&$Action|Out-Null}catch{$message=$_.Exception.Message};Check ($message.Contains($Expected)) "expected $Expected; got $message"}
  $source=Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1'
  foreach($name in @('Assert-MIR42ExactEngineAuthority','Assert-MIR42GovernedPredecessor','Assert-MIR42EngineEvidenceMaintenanceExecution','Assert-MIR42EngineEvidenceMaintenanceCustody')){Import-MIR42EngineRunnerFunction -Path $source -Name $name}
  $oldPath=Join-Path $RepoRoot '.mir/releases/governance/mir4/MIR42-Direct-Predecessor-InputsV1.json'
  $oldSha=(Get-FileHash -LiteralPath $oldPath).Hash
  $legacy=Get-Content -LiteralPath $oldPath -Raw|ConvertFrom-Json
  $captured=Get-Content -LiteralPath (Join-Path $RepoRoot 'spec/engines/mir421-native-engine-inputs-v1.json') -Raw|ConvertFrom-Json
  $fakeEngine=Join-Path $RepoRoot 'build/tmp/controlled-engine-not-executed.exe'
  # Substitute binary metadata/bytes only. Both actual release consumers and
  # the shared tracked-input reader execute; no engine or qualification record.
  function Get-Item {param($LiteralPath);if($LiteralPath-ceq$fakeEngine){return [pscustomobject]@{FullName=$fakeEngine;VersionInfo=[pscustomobject]@{ProductVersion=$observed.product_version;FileVersion=$observed.file_version}}};Microsoft.PowerShell.Management\Get-Item @PSBoundParameters}
  function Get-FileHash {param($LiteralPath,$Algorithm);if($LiteralPath-ceq$fakeEngine){return @{Hash=$observed.sha256}};Microsoft.PowerShell.Utility\Get-FileHash @PSBoundParameters}
  function Get-MIR42DirectPredecessorAuthority {throw 'legacy-predecessor-reader-requested'}
  function Get-MIR4F210CurrentEngineCapHarnessAdmissionV3 {return @{engine=@{binary=@{sha256=$legacy.targets[0].engine.sha256};file_version=$legacy.targets[0].engine.file_version}}}
  try{
    foreach($key in @('f210','f200','f110','f100')){
      $expected=Get-MIR421NativeEngineInput -RepoRoot $RepoRoot -Target $key
      $observed=[pscustomobject]@{product_version=$expected.product_version;file_version=$expected.file_version;sha256=$expected.sha256}
      $target=[pscustomobject]@{target=$key}
      $publishedInput=[pscustomobject]@{target=$key;path=Join-Path $RepoRoot "build/tmp/more-infinite-research_4.2.$($key.Substring(1))00.zip";version="4.2.$($key.Substring(1))00";sha256=('A'*64)}
      $execution=[pscustomobject]@{executable_path=$fakeEngine;executable_sha256=$expected.sha256;version=$expected.file_version;predecessor=[pscustomobject]@{path=$publishedInput.path;version=$publishedInput.version;sha256=$publishedInput.sha256};published_maintenance_predecessor=$publishedInput}
      Assert-MIR42ExactEngineAuthority -RepoRoot $RepoRoot -Target $target -Execution $execution -PublishedMaintenance
      Assert-MIR42GovernedPredecessor -RepoRoot $RepoRoot -Target $target -Execution $execution -AuthorityReference @{} -RunAsset @{} -PublishedMaintenanceInput $publishedInput
      Check ($true) "$key consumes declared maintenance engine without old predecessor archives"
      foreach($field in @('product_version','file_version','sha256')){
        $saved=$observed.$field;$observed.$field=if($field-eq'sha256'){'0'*64}elseif($field-eq'file_version'){'2.1.99.99999'}else{'2.1.99'}
        Refuses {Assert-MIR421NativeEngineIdentity -RepoRoot $RepoRoot -Target $key -Observed $observed} 'mir421-engine-input-binding'
        $observed.$field=$saved
      }
      $execution.executable_sha256='0'*64
      Refuses {Assert-MIR42ExactEngineAuthority -RepoRoot $RepoRoot -Target $target -Execution $execution -PublishedMaintenance} 'engine-local-identity-drift'
      $execution.executable_sha256=$expected.sha256
      $execution.predecessor.sha256='0'*64
      Refuses {Assert-MIR42GovernedPredecessor -RepoRoot $RepoRoot -Target $target -Execution $execution -AuthorityReference @{} -RunAsset @{} -PublishedMaintenanceInput $publishedInput} 'maintenance-predecessor-binding'
      $execution.predecessor.sha256=$publishedInput.sha256
      Refuses {Assert-MIR42GovernedPredecessor -RepoRoot $RepoRoot -Target $target -Execution $execution -AuthorityReference @{} -RunAsset @{}} 'legacy-predecessor-reader-requested'
      if($key-ceq'f210'){
        Refuses {Assert-MIR42ExactEngineAuthority -RepoRoot $RepoRoot -Target $target -Execution $execution} 'f210-engine-authority-drift'
        # Consume the actual orchestration branch, including its legacy path.
        $ast=[Management.Automation.Language.Parser]::ParseFile($runnerPath,[ref]$null,[ref]$null)
        $nodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith('if ($isHistoricalTarget)') -and $n.Extent.Text.Contains('$row.engine_product_version.StartsWith')},$true))
        Check ($nodes.Count-eq1) 'modern orchestration admission branch missing'
        $repo=$RepoRoot;$target=$key;$isHistoricalTarget=$false;$maintenanceInputs=@{selected=$true};$lock=$legacy.targets[0]
        $row=@{engine_product_version=$expected.product_version;engine_file_version=$expected.file_version;engine_sha256=$expected.sha256;engine_major='2.1';engine_version=''}
        . ([scriptblock]::Create($nodes[0].Extent.Text))
        Check ($row.engine_version-ceq$expected.file_version) 'orchestrator did not select the maintenance engine'
        $maintenanceInputs=$null
        Refuses {. ([scriptblock]::Create($nodes[0].Extent.Text))} 'mir42-f210-engine-version'
      }
    }
    Check ((Get-FileHash -LiteralPath $oldPath).Hash-ceq$oldSha) 'frozen predecessor authority changed'
    Check (-not$captured.qualification_authorized -and -not$captured.publication_authorized) 'input lock grants qualification/publication'
    $scratch=Join-Path $RepoRoot ('build/tmp/maintenance-engine-inputs-'+[guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path (Join-Path $scratch 'spec/engines'),(Join-Path $scratch 'spec/schemas')
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'spec/schemas/mir421-native-engine-inputs-v1.schema.json') -Destination (Join-Path $scratch 'spec/schemas/mir421-native-engine-inputs-v1.schema.json')
    foreach($case in @('hash','qualification','order','line')){
      $record=$captured|ConvertTo-Json -Depth 15|ConvertFrom-Json
      switch($case){hash{$record.targets[0].sha256='0'*64};qualification{$record.qualification_authorized=$true};order{$record.targets=@($record.targets[1],$record.targets[0],$record.targets[2],$record.targets[3])};line{$record.targets[0].product_version='2.0.77';$record.targets[0].file_version='2.0.77.84539'}}
      if($case-ne'hash'){$record.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $record}
      $record|ConvertTo-Json -Depth 15|Set-Content -LiteralPath (Join-Path $scratch 'spec/engines/mir421-native-engine-inputs-v1.json')
      $errorCode=switch($case){hash{'engine-input-record'};qualification{'engine-input-schema'};order{'engine-input-record'};line{'engine-input-version'}}
      Refuses {Get-MIR421NativeEngineInput -RepoRoot $scratch -Target f210} $errorCode
    }
    Write-Output "MIR421-MAINTENANCE-ENGINE-INPUTS-PASSED assertions=$script:engineInputChecks engines=0"
  }finally{
    if($scratch-and(Test-Path -LiteralPath $scratch)){$null=Assert-MIRImmutableInputPathWithin -Path $scratch -Root (Join-Path $RepoRoot 'build/tmp') -Context 'owned engine-input test';Remove-Item -LiteralPath $scratch -Recurse -Force}
    foreach($name in @('Assert-MIR42ExactEngineAuthority','Assert-MIR42GovernedPredecessor','Assert-MIR42EngineEvidenceMaintenanceExecution','Assert-MIR42EngineEvidenceMaintenanceCustody')){Remove-Item -LiteralPath "function:script:$name" -ErrorAction SilentlyContinue}
  }
}
Test-MIR421MaintenanceEngineInputs
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
  Assert-MIR42HistoricalPredecessorCustody -Version $row.version -ExpectedSha256 $row.archive -LocalPath $archive
}

$custodyScratch=Join-Path $RepoRoot ('build/tmp/historical-custody-controls-'+[guid]::NewGuid().ToString('N'))
try {
  $absent=Join-Path $custodyScratch 'absent.zip'
  Assert-MIR42HistoricalPredecessorCustody -Version $expected.f017.version -ExpectedSha256 $expected.f017.archive -LocalPath $absent
  if(Test-Path -LiteralPath $custodyScratch){throw 'historical-custody-check-materialized-archive'}
  $null=New-Item -ItemType Directory -Path $custodyScratch
  $wrong=Join-Path $custodyScratch 'wrong.zip';[IO.File]::WriteAllText($wrong,'tiny differing local archive')
  foreach($case in @(
    @{sha=('0'*64);path=$absent;error='historical-predecessor-authority'},
    @{sha=$expected.f017.archive;path=$wrong;error='historical-predecessor-local-drift'}
  )){
    $failure='';try{Assert-MIR42HistoricalPredecessorCustody -Version $expected.f017.version -ExpectedSha256 $case.sha -LocalPath $case.path}catch{$failure=$_.Exception.Message}
    if(-not $failure.Contains($case.error)){throw "historical-custody-opposing-case: expected $($case.error), got $failure"}
  }
} finally {
  if(Test-Path -LiteralPath $custodyScratch){
    $null=Assert-MIRImmutableInputPathWithin -Path $custodyScratch -Root (Join-Path $RepoRoot 'build/tmp') -Context 'owned tiny custody controls'
    Remove-Item -LiteralPath $custodyScratch -Recurse -Force
  }
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
    $localEngine=Join-Path $descriptorRoot ($target+'/configured-engine.exe')
    $patchDescriptor=Get-MIR42HistoricalEngineDescriptor -RepoRoot $RepoRoot -Target $target -SourceVersion '4.2.1' -EnginePath $localEngine
    $patchIdentity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $target.Substring(1) -SourceMinor 2 -SourcePatch 1
    if([string]$patchDescriptor.to-cne[string]$patchIdentity.distribution_version-or
       [string]$patchDescriptor.from-cne[string]$descriptor.from-or
       [string]$patchDescriptor.engine-cne$localEngine-or
       [string]$patchDescriptor.historical.engine.path-cne[string]$descriptor.historical.engine.path-or
       [string]$patchDescriptor.historical.predecessor.sha256-cne[string]$descriptor.historical.predecessor.sha256-or
       [string]$patchDescriptor.historical.engine.sha256-cne[string]$descriptor.historical.engine.sha256-or
       [string]$patchDescriptor.historical.target_record.record_sha256-cne[string]$descriptor.historical.target_record.record_sha256){throw "patch-descriptor-binding $target"}
    foreach($badPath in @('','relative/factorio.exe')){
      $failure='';try{$null=Get-MIR42HistoricalEngineDescriptor -RepoRoot $RepoRoot -Target $target -SourceVersion '4.2.1' -EnginePath $badPath}catch{$failure=$_.Exception.Message}
      if($failure-cne"[mir421-$target-local-engine-binding-required]"){throw "patch-descriptor-local-binding $target"}
    }

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

function Test-MIR421HistoricalMaintenancePortability {
  . (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
  $checks=0
  $realContainedResolver=(Get-Command Resolve-MIR42SealContainedArtifactPath).ScriptBlock
  # Emulate an otherwise intact relocated checkout with no old MIR 3 ZIPs.
  # Real tracked target/seal records and the real maintenance consumer execute.
  function Resolve-MIR42SealContainedArtifactPath {
    param($Root,$RelativePath,$Code)
    if($RelativePath.StartsWith('dist/')){throw 'retired-archive-read-requested'}
    & $realContainedResolver @PSBoundParameters
  }
  # File-byte checking is covered by the immutable-file reader and native runs;
  # these controlled paths isolate the caller's identity/location decisions.
  function Resolve-MIR42SealImmutableFile {param($Path,$Sha256,$Code);[IO.Path]::GetFullPath($Path)}
  foreach($key in @('f017','f016','f015','f014','f013')){
    $bound=Get-MIR42HistoricalTerminalAuthority -RepoRoot $RepoRoot -Target $key -PredecessorIdentityOnly
    if($bound.predecessor_path -cne ''){throw 'Historical identity read retained an archive dependency'};$checks++
    $failure='';try{$null=Get-MIR42HistoricalTerminalAuthority -RepoRoot $RepoRoot -Target $key}catch{$failure=$_.Exception.Message}
    if($failure-cne'retired-archive-read-requested'){throw 'Legacy archive check was bypassed'};$checks++
    $descriptor=Get-MIR42HistoricalEngineDescriptor -RepoRoot $RepoRoot -Target $key -SourceVersion '4.2.1' -EnginePath (Join-Path $RepoRoot ('build/tmp/relocated-engines/'+$key+'/factorio.exe'))
    $history=$descriptor.historical|ConvertTo-Json -Depth 12|ConvertFrom-Json -Depth 12
    $publishedInput=[pscustomobject]@{target=$key;path=Join-Path $RepoRoot ('build/tmp/published-'+$key+'.zip');version=('4.2.'+$key.Substring(1)+'00');sha256=('A'*64)}
    $execution=[pscustomobject]@{executable_path=$descriptor.engine;executable_sha256=$descriptor.historical.engine.sha256;version=$descriptor.historical.engine.version;predecessor=[pscustomobject]@{path=$publishedInput.path;sha256=$publishedInput.sha256;version=$publishedInput.version};harness_receipt=@{};harness_exit_code=0;logs=@();fresh_loads=@();fresh_exact_load=$true;predecessor_upgrade=$true;reload_count=2;historical_terminal_authority=$history;published_maintenance_predecessor=$publishedInput}
    $authority=@([pscustomobject]@{target=$key;authority=$history})
    Assert-MIR42HistoricalTerminalExecution -RepoRoot $RepoRoot -Target ([pscustomobject]@{target=$key}) -Execution $execution -HistoricalAuthorities $authority -PublishedMaintenanceInput $publishedInput
    $checks++
    foreach($field in @('executable_sha256','version')){
      $saved=$execution.$field;$execution.$field=if($field-ceq'version'){'0.99.99'}else{'0'*64}
      $failure='';try{Assert-MIR42HistoricalTerminalExecution -RepoRoot $RepoRoot -Target ([pscustomobject]@{target=$key}) -Execution $execution -HistoricalAuthorities $authority -PublishedMaintenanceInput $publishedInput}catch{$failure=$_.Exception.Message}
      if(-not$failure.Contains('historical-execution-binding')){throw "Historical maintenance $field mismatch accepted: $failure"};$checks++;$execution.$field=$saved
    }
    $execution.predecessor.sha256='0'*64
    $failure='';try{Assert-MIR42HistoricalTerminalExecution -RepoRoot $RepoRoot -Target ([pscustomobject]@{target=$key}) -Execution $execution -HistoricalAuthorities $authority -PublishedMaintenanceInput $publishedInput}catch{$failure=$_.Exception.Message}
    if(-not$failure.Contains('maintenance-predecessor-binding')){throw 'Historical maintenance wrong predecessor accepted'};$checks++
  }
  Write-Output "MIR421-HISTORICAL-MAINTENANCE-PORTABILITY-PASSED assertions=$checks engines=0"
}
Test-MIR421HistoricalMaintenancePortability

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
