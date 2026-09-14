# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$CandidateZip='',
  [string]$OutputRoot='build/tests/mir42-cap-ownership-multiforce'
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$buildRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
if(-not $output.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){
  throw 'MIR42 cap ownership/multiforce evidence outputs must be under build.'
}

$engineSha='710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8'
$fixtureName='mir-fixture-assert-mir42-cap-ownership-multiforce'
$blockerName='late-mir42-cap-binding-blocker'
$technologyName='recipe-prod-research_copper-1'
$settingName='ips-max-level-research_copper'
$nonClaims=@(
  'release-readiness-or-publication-authorization',
  'historical-package-upgrade-or-general-save-migration',
  'multiplayer-gameplay-or-human-playtest',
  'unbounded-multiforce-coverage-beyond-named-forces',
  'browser-or-profile-user-interface-qualification',
  'all-stream-or-all-ecosystem-cap-qualification',
  'external-late-mutator-compatibility-or-endorsement',
  'performance-or-memory-envelope-qualification'
)

function Assert-MIR42([bool]$Condition,[string]$Message){
  if(-not $Condition){throw "[mir42-cap-ownership-multiforce] $Message"}
}
function Get-MIR42Sha([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Assert-Exact([string]$Name,$Actual,$Expected){
  if($null -eq $Actual -and $null -eq $Expected){return}
  if($null -eq $Actual -or $null -eq $Expected -or $Actual -cne $Expected){
    throw "[mir42-cap-ownership-multiforce] $Name differs: expected '$Expected', actual '$Actual'."
  }
}
function Assert-Properties([string]$Name,$Value,[string[]]$Expected){
  Assert-MIR42 ($null -ne $Value) "$Name is absent."
  $actual=@($Value.PSObject.Properties.Name|Sort-Object)
  $wanted=@($Expected|Sort-Object)
  Assert-Exact "$Name properties" ($actual -join "`n") ($wanted -join "`n")
}
function Get-MIR42Artifact([string]$Path){
  $resolved=(Resolve-Path -LiteralPath $Path).Path
  Assert-MIR42 ($resolved.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) "artifact is outside the repository: $resolved"
  return [ordered]@{
    path=$resolved.Substring($repo.Length+1).Replace('\','/')
    bytes=(Get-Item -LiteralPath $resolved).Length
    raw_sha256=Get-MIR42Sha $resolved
  }
}
function Read-MIR42State([string]$Text,[string]$Stage){
  $matches=@([regex]::Matches($Text,'\[mir42-cap-ownership-multiforce\] STATE JSON (?<json>\{[^\r\n]+\})')|ForEach-Object{
    try{$value=$_.Groups['json'].Value|ConvertFrom-Json -ErrorAction Stop}catch{throw "invalid state JSON: $($_.Exception.Message)"}
    if([string]$value.stage -ceq $Stage){$value}
  })
  Assert-MIR42 ($matches.Count -eq 1) "expected exactly one $Stage state receipt; observed $($matches.Count)."
  return $matches[0]
}
function Read-MIR42Data([string]$Text){
  $matches=[regex]::Matches($Text,'\[mir42-cap-ownership-multiforce\] DATA policy=v3 technology=(?<technology>[^\s]+) cap=(?<cap>[^\s]+) finalizer=(?<finalizer>[^\s]+) prototype=(?<prototype>[^\s]+)')
  Assert-MIR42 ($matches.Count -eq 1) "expected exactly one V3 data receipt; observed $($matches.Count)."
  return [pscustomobject]@{
    technology=$matches[0].Groups['technology'].Value
    cap=$matches[0].Groups['cap'].Value
    finalizer=$matches[0].Groups['finalizer'].Value
    prototype=$matches[0].Groups['prototype'].Value
  }
}
function Assert-MIR42Data($Data,[string]$ExpectedCap){
  Assert-Properties 'V3 data receipt' $Data @('technology','cap','finalizer','prototype')
  Assert-Exact 'V3 data technology' $Data.technology $technologyName
  Assert-Exact 'V3 data cap' $Data.cap $ExpectedCap
  Assert-Exact 'V3 finalizer' $Data.finalizer 'accepted'
  Assert-Exact 'V3 prototype strategy observation' $Data.prototype 'infinite'
}
function Assert-MIR42State($State,[string]$ExpectedStage,[int]$ExpectedCap,[bool]$ExpectedBlocker,[int]$ExpectedConfigurationChanges,[object[]]$ExpectedForces){
  Assert-Properties "state.$ExpectedStage" $State @('stage','cap','blocker','configuration_changed_events','forces')
  Assert-Exact "$ExpectedStage.stage" $State.stage $ExpectedStage
  Assert-Exact "$ExpectedStage.cap" ([int]$State.cap) $ExpectedCap
  Assert-Exact "$ExpectedStage.blocker" ([bool]$State.blocker) $ExpectedBlocker
  Assert-Exact "$ExpectedStage.configuration_changed_events" ([int]$State.configuration_changed_events) $ExpectedConfigurationChanges
  $actual=@($State.forces)
  Assert-MIR42 ($actual.Count -eq $ExpectedForces.Count) "$ExpectedStage force receipt count differs."
  $seen=@{}
  $seenIndexes=@{}
  foreach($row in $actual){
    Assert-Properties "$ExpectedStage.force" $row @('name','index','level','enabled','visible_when_disabled')
    $name=[string]$row.name
    Assert-MIR42 (-not $seen.ContainsKey($name)) "$ExpectedStage duplicates force $name."
    $seen[$name]=$row
    $forceIndex=[int]$row.index
    Assert-MIR42 ($forceIndex -gt 0) "$ExpectedStage force $name has no positive Factorio force index."
    Assert-MIR42 (-not $seenIndexes.ContainsKey($forceIndex)) "$ExpectedStage reuses force index $forceIndex for $name and $($seenIndexes[$forceIndex])."
    $seenIndexes[$forceIndex]=$name
  }
  foreach($expected in $ExpectedForces){
    $name=[string]$expected.name
    Assert-MIR42 ($seen.ContainsKey($name)) "$ExpectedStage misses force $name."
    $actualRow=$seen[$name]
    Assert-Exact "$ExpectedStage.$name.level" ([int]$actualRow.level) ([int]$expected.level)
    Assert-Exact "$ExpectedStage.$name.enabled" ([bool]$actualRow.enabled) ([bool]$expected.enabled)
    Assert-Exact "$ExpectedStage.$name.visible_when_disabled" ([bool]$actualRow.visible_when_disabled) ([bool]$expected.visible_when_disabled)
  }
}
function Assert-MIR42StableForceIndices($Reference,$Current,[string]$Name){
  $referenceByName=@{}
  foreach($row in @($Reference.forces)){$referenceByName[[string]$row.name]=[int]$row.index}
  foreach($row in @($Current.forces)){
    $forceName=[string]$row.name
    if($referenceByName.ContainsKey($forceName)){
      Assert-Exact "$Name force index for $forceName" ([int]$row.index) $referenceByName[$forceName]
    }
  }
}
function Get-MIR42SemanticStateJson($State){
  $forces=@($State.forces|Sort-Object name|ForEach-Object{
    [ordered]@{
      name=[string]$_.name
      index=[int]$_.index
      level=[int]$_.level
      enabled=[bool]$_.enabled
      visible_when_disabled=[bool]$_.visible_when_disabled
    }
  })
  return ([ordered]@{
    cap=[int]$State.cap
    blocker=[bool]$State.blocker
    configuration_changed_events=[int]$State.configuration_changed_events
    forces=$forces
  }|ConvertTo-Json -Depth 8 -Compress)
}

Assert-Exact 'Factorio executable SHA-256' (Get-MIR42Sha $engine) $engineSha
$engineVersion=(& $engine --version|Out-String)
Assert-MIR42 ($LASTEXITCODE -eq 0 -and $engineVersion -match 'Version: 2[.]1[.]17') 'requires exact Steam Factorio 2.1.17.'
$engineVersion=([regex]::Match($engineVersion,'Version:\s+2[.]1[.]17[^\r\n]*').Value).Trim()

$sourceCommit=(& git -C $repo rev-parse HEAD).Trim()
$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
Assert-MIR42 ($sourceCommit -match '^[0-9a-f]{40}$' -and $sourceTree -match '^[0-9a-f]{40}$') 'requires source commit/tree identities.'
$packageSourceChanges=@(& git -C $repo status --porcelain --untracked-files=all -- src/mod)
Assert-MIR42 ($packageSourceChanges.Count -eq 0) "requires a clean src/mod root: $($packageSourceChanges -join '; ')"

. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')

$freshCandidate=New-MIR4TargetPackage -RepoRoot $repo -Target f210 -CandidateId ('MIR42-CAP-OWNERSHIP-MULTIFORCE-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()) -SourceVersion '4.2.0' -DistributionVersion '4.2.21000' -OutputRoot 'build/mir42-cap-ownership-multiforce/packages'
$freshCandidateZip=(Resolve-Path -LiteralPath ([string]$freshCandidate.archive_path)).Path
if([string]::IsNullOrWhiteSpace($CandidateZip)){
  $candidateZip=$freshCandidateZip
} else {
  $candidateZip=(Resolve-Path -LiteralPath $CandidateZip).Path
  Assert-Exact 'supplied candidate SHA-256' (Get-MIR42Sha $candidateZip) (Get-MIR42Sha $freshCandidateZip)
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$candidateArchive=[IO.Compression.ZipFile]::OpenRead($candidateZip)
try{
  $forbidden=@($candidateArchive.Entries|Where-Object{
    $_.FullName -match '(^|/)(fixtures|tests|docs|scripts|[.]mir|[.]codex|[.]github|build|dist)(/|$)' -or
    $_.FullName -match '(^|/)(AGENTS|CONTRIBUTING|GOVERNANCE|SECURITY|PROJECT-CONTINUITY|FORKING|MAINTAINER-HANDOFF|EXTENSION-PROTOCOL|RELEASE-RUNBOOK|SUPPORT)[.]md$' -or
    $_.FullName -match '(^|/)(todo[.]md|CHANGELOG[.]md|[.]gitattributes|[.]gitignore)$'
  })
  if($forbidden.Count -ne 0){
    throw "[mir42-cap-ownership-multiforce] candidate contains package-excluded path $($forbidden[0].FullName)"
  }
} finally {
  $candidateArchive.Dispose()
}

$fixture=Join-Path $repo 'fixtures/assert-mir42-cap-ownership-multiforce'
$blockerFixture=Join-Path $repo 'fixtures/late-mir42-cap-binding-blocker'
foreach($path in @($fixture,$blockerFixture)){
  Assert-MIR42 (Test-Path -LiteralPath $path -PathType Container) "fixture directory is absent: $path"
}

$run=Join-Path $output ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $run|Out-Null
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent)-Parent)-Parent

function New-MIR42Stage([string]$Name,[int]$Cap,[bool]$UseBlocker){
  $stageRoot=Join-Path $run $Name
  $mods=Join-Path $stageRoot 'mods'
  $userdata=Join-Path $stageRoot 'userdata'
  New-Item -ItemType Directory -Force -Path $mods,$userdata,(Join-Path $userdata 'saves')|Out-Null
  Copy-Item -LiteralPath $candidateZip -Destination $mods
  $fixtureArchive=Publish-MIRModDirectoryArchive -Source $fixture -Name $fixtureName -Version '0.1.0' -ModsDir $mods
  $blockerArchive=$null
  if($UseBlocker){
    $blockerArchive=Publish-MIRModDirectoryArchive -Source $blockerFixture -Name $blockerName -Version '0.1.0' -ModsDir $mods
  }
  Initialize-MIRSettingsOverrideMod -ModsDir $mods -FactorioVersion '2.1'
  Set-CopiedStartupSettingDefaults -ModsDir $mods -Overrides @{
    'ips-enable-research_copper'=$true
    'ips-max-level-research_copper'=$Cap
  }
  Complete-MIRSettingsOverrideMod -ModsDir $mods
  $modNames=@('base','elevated-rails','quality','recycler','space-age','more-infinite-research',$fixtureName,'mir-validation-settings-overrides')
  if($UseBlocker){$modNames+=,$blockerName}
  $modList=[ordered]@{mods=@($modNames|ForEach-Object{[ordered]@{name=$_;enabled=$true}})}
  $modListPath=Join-Path $mods 'mod-list.json'
  [IO.File]::WriteAllText($modListPath,(($modList|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  $configPath=Join-Path $stageRoot 'config.ini'
  [IO.File]::WriteAllText($configPath,"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($userdata.Replace('\','/'))`n",[Text.UTF8Encoding]::new($false))
  $serverSettings=Join-Path $stageRoot 'server-settings.json'
  $server=[ordered]@{name='MIR42 cap ownership/multiforce';description='';tags=@();max_players=1;visibility=[ordered]@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false}
  [IO.File]::WriteAllText($serverSettings,(($server|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  return [pscustomobject]@{
    name=$Name
    cap=$Cap
    blocker=$UseBlocker
    root=$stageRoot
    mods=$mods
    userdata=$userdata
    config=$configPath
    server_settings=$serverSettings
    fixture_archive=$fixtureArchive
    blocker_archive=$blockerArchive
    settings_archive=(Join-Path $mods 'mir-validation-settings-overrides_0.1.0.zip')
    mod_list=$modListPath
  }
}

function Invoke-MIR42Engine($Stage,[string]$Name,[string[]]$Arguments){
  $factorioLog=Join-Path $Stage.userdata 'factorio-current.log'
  if(Test-Path -LiteralPath $factorioLog){Remove-Item -LiteralPath $factorioLog -Force}
  $start=[Diagnostics.ProcessStartInfo]::new($engine)
  $start.UseShellExecute=$false
  $start.CreateNoWindow=$true
  $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
  $start.RedirectStandardOutput=$true
  $start.RedirectStandardError=$true
  $start.Environment['SteamAppId']='427520'
  $start.Environment['SteamGameId']='427520'
  foreach($argument in @('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods)+$Arguments){
    [void]$start.ArgumentList.Add($argument)
  }
  $process=[Diagnostics.Process]::Start($start)
  try{
    $stdout=$process.StandardOutput.ReadToEndAsync()
    $stderr=$process.StandardError.ReadToEndAsync()
    if(-not $process.WaitForExit(120000)){
      $process.Kill($true)
      throw "Factorio timed out during $Name."
    }
    $text=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $Stage.root "engine-$Name.log"),$text,[Text.UTF8Encoding]::new($false))
    if($process.ExitCode -ne 0){
      throw "Factorio failed during ${Name}: $($text.Substring([Math]::Max(0,$text.Length-2500)))"
    }
  } finally {
    $process.Dispose()
  }
  Assert-MIR42 (Test-Path -LiteralPath $factorioLog -PathType Leaf) "Factorio log is absent after $Name."
  $copy=Join-Path $Stage.root "factorio-$Name.log"
  Copy-Item -LiteralPath $factorioLog -Destination $copy
  return $copy
}

function Invoke-MIR42ServerSave($Stage,[string]$Name,[string]$InputSave,[string]$ExpectedSave,[string]$ExpectedStage){
  $factorioLog=Join-Path $Stage.userdata 'factorio-current.log'
  if(Test-Path -LiteralPath $factorioLog){Remove-Item -LiteralPath $factorioLog -Force}
  $start=[Diagnostics.ProcessStartInfo]::new($engine)
  $start.UseShellExecute=$false
  $start.CreateNoWindow=$true
  $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
  $start.Environment['SteamAppId']='427520'
  $start.Environment['SteamGameId']='427520'
  foreach($argument in @('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods,'--server-settings',$Stage.server_settings,'--start-server',$InputSave)){
    [void]$start.ArgumentList.Add($argument)
  }
  $process=[Diagnostics.Process]::Start($start)
  $ready=$false
  try{
    $deadline=[DateTime]::UtcNow.AddSeconds(60)
    $needle="[mir42-cap-ownership-multiforce] STATE JSON {`"stage`":`"$ExpectedStage`""
    while([DateTime]::UtcNow -lt $deadline){
      if($process.HasExited){throw "Factorio server exited before $Name successor with code $($process.ExitCode)."}
      if((Test-Path -LiteralPath $factorioLog -PathType Leaf) -and (Test-Path -LiteralPath $ExpectedSave -PathType Leaf)){
        $text=Get-Content -Raw -LiteralPath $factorioLog
        if($text.Contains($needle) -and $text.Contains('Saving finished')){$ready=$true;break}
      }
      Start-Sleep -Milliseconds 200
    }
    if(-not $ready){throw "Factorio server did not create $Name successor."}
  } finally {
    if(-not $process.HasExited){try{$process.Kill($true)}catch{$process.Kill()}}
    $process.WaitForExit()
    $process.Dispose()
  }
  Assert-MIR42 (Test-Path -LiteralPath $factorioLog -PathType Leaf) "Factorio log is absent after $Name."
  $copy=Join-Path $Stage.root "factorio-$Name.log"
  Copy-Item -LiteralPath $factorioLog -Destination $copy
  return $copy
}

$seedStage=New-MIR42Stage -Name 'seed' -Cap 0 -UseBlocker:$false
$cappedStage=New-MIR42Stage -Name 'capped' -Cap 3 -UseBlocker:$false
$blockedStage=New-MIR42Stage -Name 'blocked' -Cap 3 -UseBlocker:$true
$removalStage=New-MIR42Stage -Name 'removal' -Cap 0 -UseBlocker:$false

$seedSave=Join-Path $seedStage.root 'seed.zip'
$seedLog=Invoke-MIR42Engine $seedStage 'seed' @('--create',$seedSave)
Assert-MIR42 (Test-Path -LiteralPath $seedSave -PathType Leaf) 'Seed current-candidate save is absent.'
$seedText=Get-Content -Raw -LiteralPath $seedLog
$seedData=Read-MIR42Data $seedText
Assert-MIR42Data $seedData 'infinite'
$seedState=Read-MIR42State $seedText 'seed'

$cappedSave=Join-Path $cappedStage.userdata 'saves/mir42-cap-ownership-multiforce-capped.zip'
$cappedLog=Invoke-MIR42ServerSave $cappedStage 'capped' $seedSave $cappedSave 'event-probe'
$cappedText=Get-Content -Raw -LiteralPath $cappedLog
$cappedData=Read-MIR42Data $cappedText
Assert-MIR42Data $cappedData '3'
$cappedState=Read-MIR42State $cappedText 'capped'
$eventProbeState=Read-MIR42State $cappedText 'event-probe'

$blockedSave=Join-Path $blockedStage.userdata 'saves/mir42-cap-ownership-multiforce-blocked.zip'
$blockedLog=Invoke-MIR42ServerSave $blockedStage 'blocked' $cappedSave $blockedSave 'blocked'
$blockedText=Get-Content -Raw -LiteralPath $blockedLog
$blockedData=Read-MIR42Data $blockedText
Assert-MIR42Data $blockedData '3'
$blockedState=Read-MIR42State $blockedText 'blocked'
$blockerRecords=[regex]::Matches($blockedText,'\[late-mir42-cap-binding-blocker\] DATA technology=recipe-prod-research_copper-1 pre=infinite post=5 policy=v3')
Assert-MIR42 ($blockerRecords.Count -eq 1) "expected exactly one late blocker data receipt; observed $($blockerRecords.Count)."
$lateConflicts=[regex]::Matches($blockedText,'\[more-infinite-research\] Maximum-level conflict technology=recipe-prod-research_copper-1 selected=3 final-observed=5 binding-operation=emit source=generated-stream reason=maximum_level_late_prototype_mutation setting=ips-max-level-research_copper; runtime queue normalization was refused[.]')
Assert-MIR42 ($lateConflicts.Count -eq 1) "expected exactly one Copper late-conflict refusal; observed $($lateConflicts.Count)."

$removalSave=Join-Path $removalStage.userdata 'saves/mir42-cap-ownership-multiforce-removal.zip'
$removalLog=Invoke-MIR42ServerSave $removalStage 'removal' $blockedSave $removalSave 'removal'
$removalText=Get-Content -Raw -LiteralPath $removalLog
$removalData=Read-MIR42Data $removalText
Assert-MIR42Data $removalData 'infinite'
$removalState=Read-MIR42State $removalText 'removal'

$terminalLog=Invoke-MIR42Engine $removalStage 'terminal' @('--benchmark',$removalSave,'--benchmark-ticks','10','--benchmark-runs','1','--benchmark-sanitize')
$terminalText=Get-Content -Raw -LiteralPath $terminalLog
$terminalData=Read-MIR42Data $terminalText
Assert-MIR42Data $terminalData 'infinite'
$terminalState=Read-MIR42State $terminalText 'terminal'

$seedForces=@(
  [pscustomobject]@{name='owned';level=4;enabled=$true;visible_when_disabled=$false},
  [pscustomobject]@{name='foreign-disabled';level=4;enabled=$false;visible_when_disabled=$false},
  [pscustomobject]@{name='below-cap';level=2;enabled=$true;visible_when_disabled=$false},
  [pscustomobject]@{name='event-probe';level=4;enabled=$true;visible_when_disabled=$false}
)
$cappedForces=@(
  [pscustomobject]@{name='owned';level=4;enabled=$false;visible_when_disabled=$true},
  [pscustomobject]@{name='foreign-disabled';level=4;enabled=$false;visible_when_disabled=$true},
  [pscustomobject]@{name='below-cap';level=2;enabled=$true;visible_when_disabled=$false},
  [pscustomobject]@{name='event-probe';level=4;enabled=$false;visible_when_disabled=$true}
)
$eventForces=@($cappedForces + [pscustomobject]@{name='new-force';level=4;enabled=$true;visible_when_disabled=$false})
$removedForces=@(
  [pscustomobject]@{name='owned';level=4;enabled=$true;visible_when_disabled=$false},
  [pscustomobject]@{name='foreign-disabled';level=4;enabled=$false;visible_when_disabled=$false},
  [pscustomobject]@{name='below-cap';level=2;enabled=$true;visible_when_disabled=$false},
  [pscustomobject]@{name='event-probe';level=4;enabled=$true;visible_when_disabled=$false},
  [pscustomobject]@{name='new-force';level=4;enabled=$true;visible_when_disabled=$true}
)
Assert-MIR42State $seedState 'seed' 0 $false 0 $seedForces
Assert-MIR42State $cappedState 'capped' 3 $false 1 $cappedForces
Assert-MIR42State $eventProbeState 'event-probe' 3 $false 1 $eventForces
Assert-MIR42State $blockedState 'blocked' 3 $true 2 $eventForces
Assert-MIR42State $removalState 'removal' 0 $false 3 $removedForces
Assert-MIR42State $terminalState 'terminal' 0 $false 3 $removedForces
Assert-MIR42StableForceIndices $seedState $cappedState 'seed-to-capped'
Assert-MIR42StableForceIndices $seedState $eventProbeState 'seed-to-event-probe'
Assert-MIR42StableForceIndices $eventProbeState $blockedState 'event-probe-to-blocked'
Assert-MIR42StableForceIndices $eventProbeState $removalState 'event-probe-to-removal'
Assert-MIR42StableForceIndices $removalState $terminalState 'removal-to-terminal'
Assert-Exact 'terminal semantic state after serialized reload' (Get-MIR42SemanticStateJson $terminalState) (Get-MIR42SemanticStateJson $removalState)

$lineage=@(
  [ordered]@{stage='seed';save=Get-MIR42Artifact $seedSave;predecessor_sha256=$null},
  [ordered]@{stage='capped';save=Get-MIR42Artifact $cappedSave;predecessor_sha256=Get-MIR42Sha $seedSave},
  [ordered]@{stage='blocked';save=Get-MIR42Artifact $blockedSave;predecessor_sha256=Get-MIR42Sha $cappedSave},
  [ordered]@{stage='removal';save=Get-MIR42Artifact $removalSave;predecessor_sha256=Get-MIR42Sha $blockedSave}
)
for($index=1;$index -lt $lineage.Count;$index++){
  Assert-Exact "save lineage $($lineage[$index].stage)" $lineage[$index].predecessor_sha256 $lineage[$index-1].save.raw_sha256
}

function Get-MIR42StageManifest($Stage){
  $entries=[ordered]@{
    candidate=Get-MIR42Artifact (Join-Path $Stage.mods (Split-Path -Leaf $candidateZip))
    fixture=Get-MIR42Artifact $Stage.fixture_archive
    settings=Get-MIR42Artifact $Stage.settings_archive
    mod_list=Get-MIR42Artifact $Stage.mod_list
    config=Get-MIR42Artifact $Stage.config
  }
  if($Stage.blocker){$entries.blocker=Get-MIR42Artifact $Stage.blocker_archive}
  return [ordered]@{name=$Stage.name;cap=$Stage.cap;blocker=$Stage.blocker;artifacts=$entries}
}

$result=[ordered]@{
  schema=1
  kind='MIR42F210CapOwnershipMultiforceQualificationV1'
  status='passed-current-f210-candidate-cap-ownership-multiforce-only'
  scope='Freshly materialized F210 candidate: V3 copper absolute cap ownership, named-force isolation, late finalizer refusal, cap removal, and terminal serialized reload; package-excluded fixture evidence.'
  target=[ordered]@{factorio_line='2.1';factorio_version='2.1.17';engine_sha256=$engineSha}
  source=[ordered]@{
    commit=$sourceCommit
    tree=$sourceTree
    package_source_sha256=Get-MIR42Sha (Join-Path $repo 'src/mod/package-source.json')
    package_source_roots_clean=$true
  }
  candidate=Get-MIR42Artifact $candidateZip
  freshly_materialized_candidate=Get-MIR42Artifact $freshCandidateZip
  candidate_package_excludes_fixture_test_docs_governance_build_dist=$true
  fixture_hashes=[ordered]@{
    main_info=Get-MIR42Sha (Join-Path $fixture 'info.json')
    main_data_final_fixes=Get-MIR42Sha (Join-Path $fixture 'data-final-fixes.lua')
    main_control=Get-MIR42Sha (Join-Path $fixture 'control.lua')
    blocker_info=Get-MIR42Sha (Join-Path $blockerFixture 'info.json')
    blocker_data_final_fixes=Get-MIR42Sha (Join-Path $blockerFixture 'data-final-fixes.lua')
  }
  harness_sha256=Get-MIR42Sha $PSCommandPath
  stages=@(
    (Get-MIR42StageManifest $seedStage)
    (Get-MIR42StageManifest $cappedStage)
    (Get-MIR42StageManifest $blockedStage)
    (Get-MIR42StageManifest $removalStage)
  )
  v3_observations=[ordered]@{seed=$seedData;capped=$cappedData;blocked=$blockedData;removal=$removalData;terminal=$terminalData}
  named_force_state_receipts=[ordered]@{seed=$seedState;capped=$cappedState;event_probe=$eventProbeState;blocked=$blockedState;removal=$removalState;terminal=$terminalState}
  late_conflict=[ordered]@{technology=$technologyName;selected_cap=3;late_observed_prototype_max_level=5;reason='maximum_level_late_prototype_mutation';count=$lateConflicts.Count}
  save_lineage=$lineage
  logs=[ordered]@{
    seed=Get-MIR42Artifact $seedLog
    capped=Get-MIR42Artifact $cappedLog
    blocked=Get-MIR42Artifact $blockedLog
    removal=Get-MIR42Artifact $removalLog
    terminal=Get-MIR42Artifact $terminalLog
  }
  explicit_non_claims=$nonClaims
}
$resultPath=Join-Path $run 'result.json'
[IO.File]::WriteAllText($resultPath,(($result|ConvertTo-Json -Depth 40)+"`n"),[Text.UTF8Encoding]::new($false))
$result|ConvertTo-Json -Depth 40
Write-Output "Evidence: $run"
