# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/package/DistributionCustody.ps1')
. (Join-Path $repo 'tools/mir/cli/router/MIR4BootstrapCommands.ps1')
. (Join-Path $repo 'tools/mir/cli/router/ArgumentParsing.ps1')
. (Join-Path $repo 'tools/mir/domain/targets/TargetKey.ps1')
$assertions=0
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw "Custody routes: $Message"};$script:assertions++}
function Refuses([scriptblock]$Action,[string]$Message){$failure='';try{& $Action|Out-Null}catch{$failure=$_.Exception.Message};Check ($failure.Contains($Message)) "expected $Message; got $failure"}
$scratch=Join-Path $repo ('build/tmp/custody-route-controls-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $scratch
try {
  Check (-not (Test-MIR4DistributionCustodyAliasOwnership reused)) 'pre-existing alias acquired cleanup ownership.'
  Check (Test-MIR4DistributionCustodyAliasOwnership materialized-from-verified-cache) 'owned alias lost cleanup ownership.'
  Refuses {Test-MIR4DistributionCustodyAliasOwnership unknown} '[mir4-distribution-custody-output-state]'
  # Only the library metadata/restoration boundary is controlled. The actual
  # route helper and byte verifier execute against tiny generated files.
  $script:restoreCount=0;$script:restoreState='materialized-from-verified-cache'
  function Get-MIR4DistributionCustodyEntry {
    param($RepoRoot,$Version)
    $bytes=[Text.Encoding]::UTF8.GetBytes('tiny custody coupon '+$Version)
    [pscustomobject]@{path=('dist/more-infinite-research_'+$Version+'.zip');bytes=$bytes.Length;sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
  }
  function Restore-MIR4DistributionArchive {
    param($RepoRoot,$Version,$OutputRoot)
    $script:restoreCount++
    $entry=Get-MIR4DistributionCustodyEntry -RepoRoot $RepoRoot -Version $Version
    $path=Join-Path $RepoRoot $entry.path;$null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)
    [IO.File]::WriteAllText($path,('tiny custody coupon '+$Version),[Text.UTF8Encoding]::new($false))
    [pscustomobject]@{output_path=[IO.Path]::GetFullPath($path);output_state=$script:restoreState}
  }
  $libraryRoot=Join-Path $scratch 'tools/mir/application/package';$null=New-Item -ItemType Directory -Path $libraryRoot
  $controlledLibrary=". '"+(Join-Path $repo 'tools/mir/application/package/DistributionCustody.ps1').Replace("'","''")+"'`n"
  foreach($name in @('Get-MIR4DistributionCustodyEntry','Restore-MIR4DistributionArchive')){
    $controlledLibrary+="function $name {`n"+(Get-Command $name).ScriptBlock.ToString()+"`n}`n"
  }
  [IO.File]::WriteAllText((Join-Path $libraryRoot 'DistributionCustody.ps1'),$controlledLibrary)
  $authority=Join-Path $scratch '.mir/releases/waves/mir4-r0';$null=New-Item -ItemType Directory -Path $authority
  [IO.File]::WriteAllText((Join-Path $authority 'MIR4-Historical-Private-Candidate-AuthorizationV1.json'),[IO.File]::ReadAllText((Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Historical-Private-Candidate-AuthorizationV1.json')))
  $distribution=Get-MIR4DistributionCustodyEntry $scratch '3.2.9';$alias=Join-Path $scratch $distribution.path
  $null=New-Item -ItemType Directory -Path (Split-Path -Parent $alias)
  [IO.File]::WriteAllText($alias,'tiny custody coupon 3.2.9',[Text.UTF8Encoding]::new($false))
  $null=Invoke-MIR4WithDistributionCustodyAliases -RepoRoot $scratch -Version @('3.2.9') -Action {Check (Test-MIR4DistributionCustodyFile $alias $distribution) 'existing alias not verified.'}
  Check ((Test-Path $alias) -and $script:restoreCount -eq 0) 'existing exact bytes were restored or removed.'
  Remove-Item -LiteralPath $alias
  $null=Invoke-MIR4WithDistributionCustodyAliases -RepoRoot $scratch -Version @('3.2.9','3.2.9') -Action {Check (Test-MIR4DistributionCustodyFile $alias $distribution) 'owned alias not visible to consumer.'}
  Check (-not (Test-Path $alias) -and $script:restoreCount -eq 1) 'owned alias leaked or duplicate version restored twice.'
  Refuses {Invoke-MIR4WithDistributionCustodyAliases -RepoRoot $scratch -Version @('3.2.9') -Action {throw 'controlled consumer failure'}} 'controlled consumer failure'
  Check (-not (Test-Path $alias)) 'consumer failure leaked owned alias.'
  $script:restoreState='reused'
  $null=Invoke-MIR4WithDistributionCustodyAliases -RepoRoot $scratch -Version @('3.2.9') -Action {}
  Check (Test-MIR4DistributionCustodyFile $alias $distribution) 'concurrent reused alias was removed.'
  [IO.File]::WriteAllText($alias,'different pre-existing bytes')
  $before=$script:restoreCount
  Refuses {Invoke-MIR4WithDistributionCustodyAliases -RepoRoot $scratch -Version @('3.2.9') -Action {throw 'unexpected action'}} '[mir4-distribution-custody-existing-alias-mismatch]'
  Check ($script:restoreCount -eq $before -and (Get-Content -Raw $alias) -ceq 'different pre-existing bytes') 'differing pre-existing bytes were replaced.'
  Remove-Item -LiteralPath $alias;$script:restoreState='materialized-from-verified-cache'
  Refuses {Invoke-MIR4WithDistributionCustodyAliases -RepoRoot $scratch -Version @('3.2.9') -Action {[IO.File]::WriteAllText($alias,'consumer changed bytes')}} '[mir4-distribution-custody-cleanup-mismatch]'
  Check ((Get-Content -Raw $alias) -ceq 'consumer changed bytes') 'changed alias was silently removed.'
  Remove-Item -LiteralPath $alias

  # Exercise the real public CLI switch with small writable receivers. These
  # controls test command transport and custody, not package generation.
  $commands=Join-Path $scratch 'tools/commands/release';$null=New-Item -ItemType Directory -Path $commands
  $receiver=@'
param([string]$RepoRoot,[string]$Target,[int]$Repetitions,[switch]$Check,[switch]$BuildBundles,[string]$OutputPath)
$archives=@(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'dist') -Filter '*.zip' -File)
if($archives.Count -lt 1){throw 'Receiver did not receive custody aliases'}
[IO.File]::WriteAllText((Join-Path $RepoRoot 'received-command.json'),(($PSBoundParameters|ConvertTo-Json -Depth 8)+"`n"))
'@
  foreach($file in @('New-MIR3Dot9TerminalBaselines.ps1','Import-MIR3TerminalBaselines.ps1','New-MIR4HistoricalPrivateCandidate.ps1')){[IO.File]::WriteAllText((Join-Path $commands $file),$receiver)}
  foreach($verb in @('capture-terminal-baselines','import-terminal-baselines','build-historical-private','check-historical-private')){
    $null=Invoke-MIR4BootstrapCommandGroup -RepoRoot (Resolve-Path $scratch) -ScriptRoot (Join-Path $repo 'tools') -Verb $verb -CommandArguments @('--target','F013','--check')
    $received=Get-Content -Raw (Join-Path $scratch 'received-command.json')|ConvertFrom-Json
    Check ($received.RepoRoot -ceq $scratch) "$verb lost its selected repository."
    if($verb -match 'historical-private'){Check ($received.Target -ceq 'f013' -and $received.Repetitions -eq 3) "$verb lost its original target/repetition contract."}
    Check (@(Get-ChildItem -LiteralPath (Join-Path $scratch 'dist') -Filter '*.zip' -File).Count -eq 0) "$verb leaked owned aliases."
  }

  $runtime=Join-Path $scratch 'tests/runtime';$null=New-Item -ItemType Directory -Path $runtime
  $nativeReceiver=@'
param([string]$RepoRoot,[string]$Target,[string]$FactorioBin,[string]$CandidateZip,[string]$PredecessorZip,[string]$EvidenceRoot,[int]$ExpectedPeakMemoryMiB,[int]$MaxNewOutputMiB)
[IO.File]::WriteAllText((Join-Path $RepoRoot 'received-native-command.json'),(($PSBoundParameters|ConvertTo-Json -Depth 8)+"`n"))
'@
  [IO.File]::WriteAllText((Join-Path $runtime 'Test-MIR4HistoricalPrivateRuntime.ps1'),$nativeReceiver)
  function Invoke-MIR4WithDistributionCustodyAliases {throw 'Native command attempted distribution restoration'}
  $before=$script:restoreCount
  foreach($target in @('F017','F016','F015','F014','F013')){
    $null=Invoke-MIR4BootstrapCommandGroup -RepoRoot (Resolve-Path $scratch) -ScriptRoot (Join-Path $repo 'tools') -Verb runtime-historical-private -CommandArguments @('--target',$target,'--factorio-bin','selected engine with spaces','--candidate','selected candidate with spaces','--prior','selected predecessor with spaces','--evidence','selected private output','--expected-peak-memory-mib','256','--max-new-output-mib','16')
    $received=Get-Content -Raw (Join-Path $scratch 'received-native-command.json')|ConvertFrom-Json
    Check ($received.Target -ceq $target.ToLowerInvariant() -and $received.FactorioBin -ceq 'selected engine with spaces' -and $received.CandidateZip -ceq 'selected candidate with spaces' -and $received.PredecessorZip -ceq 'selected predecessor with spaces') "$target lost its supplied input transport."
    Check ($received.ExpectedPeakMemoryMiB -eq 256 -and $received.MaxNewOutputMiB -eq 16 -and $received.EvidenceRoot -ceq 'selected private output') "$target lost its budget or private output."
  }
  Check ($script:restoreCount -eq $before) 'native command restored an archive.'
  Refuses {Invoke-MIR4BootstrapCommandGroup -RepoRoot (Resolve-Path $scratch) -ScriptRoot (Join-Path $repo 'tools') -Verb runtime-historical-private -CommandArguments @('--target','F018')} 'F018 requires an explicitly admitted exact engine'
  [pscustomobject]@{status='passed';assertions=$assertions;worktrees_created=0;factorio_processes=0;native_archive_restore_calls=0;scope='Actual custody helper/byte checker and public CLI transport with tiny controlled receivers; no native or package qualification'}
} finally {
  if(Test-Path $scratch){$resolved=(Resolve-Path -LiteralPath $scratch).Path;$parent=(Resolve-Path -LiteralPath (Join-Path $repo 'build/tmp')).Path.TrimEnd('\')+'\';if(-not $resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase)){throw 'Controlled custody cleanup escaped owned root'};Remove-Item -LiteralPath $resolved -Recurse -Force}
}
