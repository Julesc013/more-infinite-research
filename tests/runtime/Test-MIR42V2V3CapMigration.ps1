# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$OutputRoot='build/tests/m42mig'
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$buildRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
if(-not $output.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){
  throw 'V2-to-V3 cap migration evidence outputs must be under build.'
}

$predecessorCommit='f7f9bab7bb1d1a63c98b5e21178fbaed418a3f6e'
$expectedEngineSha='710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8'
$fixtureName='mir-fixture-assert-mir42-v2-v3-cap-migration'
$technologyName='recipe-prod-research_copper-1'
$nonClaims=@(
  'F200-v2-to-v3-ownership-migration-qualification',
  'general-save-migration-or-all-predecessor-coverage',
  'release-readiness-or-publication-authorization',
  'multiplayer-or-human-playtest',
  'non-copper-or-non-F210-cap-migration',
  'browser-or-profile-user-interface-qualification'
)

function Assert-Migration([bool]$Condition,[string]$Message){
  if(-not $Condition){throw "[mir42-v2-v3-cap-migration] $Message"}
}
function Get-MigrationSha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Assert-Exact([string]$Name,$Actual,$Expected){
  if($null -eq $Actual -and $null -eq $Expected){return}
  if($null -eq $Actual -or $null -eq $Expected -or $Actual -cne $Expected){
    throw "[mir42-v2-v3-cap-migration] $Name differs: expected '$Expected', actual '$Actual'."
  }
}
function Assert-Properties([string]$Name,$Value,[string[]]$Expected){
  Assert-Migration ($null -ne $Value) "$Name is absent."
  Assert-Exact "$Name properties" (($Value.PSObject.Properties.Name|Sort-Object)-join "`n") (($Expected|Sort-Object)-join "`n")
}
function Get-Artifact([string]$Path){
  $resolved=(Resolve-Path -LiteralPath $Path).Path
  Assert-Migration ($resolved.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) "artifact is outside the repository: $resolved"
  [ordered]@{path=$resolved.Substring($repo.Length+1).Replace('\','/');bytes=(Get-Item -LiteralPath $resolved).Length;raw_sha256=Get-MigrationSha $resolved}
}
function Read-State([string]$Text,[string]$Stage){
  $matches=@([regex]::Matches($Text,'\[mir42-v2-v3-cap-migration\] STATE JSON (?<json>\{[^\r\n]+\})')|ForEach-Object{
    try{$value=$_.Groups['json'].Value|ConvertFrom-Json -ErrorAction Stop}catch{throw "Invalid migration state JSON: $($_.Exception.Message)"}
    if([string]$value.stage -ceq $Stage){$value}
  })
  Assert-Migration ($matches.Count -eq 1) "Expected exactly one $Stage state receipt; observed $($matches.Count)."
  $matches[0]
}
function Get-ZipEntryText([string]$ArchivePath,[string]$Suffix){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive=[IO.Compression.ZipFile]::OpenRead($ArchivePath)
  try{
    $entries=@($archive.Entries|Where-Object {$_.FullName -like "*$Suffix"})
    Assert-Migration ($entries.Count -eq 1) "Archive entry is ambiguous or absent: $Suffix"
    $reader=[IO.StreamReader]::new($entries[0].Open())
    try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
  }finally{$archive.Dispose()}
}
function Assert-CandidateExclusions([string]$ArchivePath){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive=[IO.Compression.ZipFile]::OpenRead($ArchivePath)
  try{
    $forbidden=@($archive.Entries|Where-Object {$_.FullName -match '(^|/)(fixtures|tests|docs|scripts|[.]mir|[.]codex|[.]github|build|dist)(/|$)'})
    if($forbidden.Count -ne 0){
      throw "[mir42-v2-v3-cap-migration] Candidate contains package-excluded path $($forbidden[0].FullName)"
    }
  }finally{$archive.Dispose()}
}
function Assert-State([object]$State,[string]$Stage,[int]$ExpectedSchema,[int]$ExpectedCap,[bool]$ExpectedMigrationOutcome,[bool]$ExpectedCapZeroRestoration,[object[]]$ExpectedForces){
  Assert-Properties "state.$Stage" $State @('stage','policy_schema','cap','migration_outcome_observed','cap_zero_owner_only_restoration_observed','research_level','current_research','research_queue','fractional_progress','forces')
  Assert-Exact "$Stage.stage" $State.stage $Stage
  Assert-Exact "$Stage.policy_schema" ([int]$State.policy_schema) $ExpectedSchema
  Assert-Exact "$Stage.cap" ([int]$State.cap) $ExpectedCap
  Assert-Exact "$Stage.migration_outcome_observed" ([bool]$State.migration_outcome_observed) $ExpectedMigrationOutcome
  Assert-Exact "$Stage.cap_zero_owner_only_restoration_observed" ([bool]$State.cap_zero_owner_only_restoration_observed) $ExpectedCapZeroRestoration
  Assert-Exact "$Stage.research_level" ([int]$State.research_level) 3
  Assert-Exact "$Stage.current_research" ([string]$State.current_research) $technologyName
  Assert-Exact "$Stage.research_queue" ((@($State.research_queue)-join "`n")) $technologyName
  Assert-Migration ([Math]::Abs(([double]$State.fractional_progress)-0.42) -lt 0.0001) "$Stage fractional progress differs."
  $rows=@{}
  foreach($row in @($State.forces)){
    Assert-Properties "$Stage.force" $row @('name','index','level','enabled','visible_when_disabled')
    Assert-Migration (-not $rows.ContainsKey([string]$row.name)) "$Stage duplicates force $($row.name)."
    $rows[[string]$row.name]=$row
  }
  foreach($expected in $ExpectedForces){
    $name=[string]$expected.name
    Assert-Migration ($rows.ContainsKey($name)) "$Stage misses force $name."
    $actual=$rows[$name]
    Assert-Exact "$Stage.$name.level" ([int]$actual.level) ([int]$expected.level)
    Assert-Exact "$Stage.$name.enabled" ([bool]$actual.enabled) ([bool]$expected.enabled)
    Assert-Exact "$Stage.$name.visible_when_disabled" ([bool]$actual.visible_when_disabled) ([bool]$expected.visible_when_disabled)
  }
}

Assert-Exact 'Factorio executable SHA-256' (Get-MigrationSha $engine) $expectedEngineSha
$engineVersion=(& $engine --version|Out-String)
Assert-Migration ($LASTEXITCODE -eq 0 -and $engineVersion -match 'Version: 2[.]1[.]17') 'Requires exact Steam Factorio 2.1.17.'
$engineVersion=([regex]::Match($engineVersion,'Version:\s+2[.]1[.]17[^\r\n]*').Value).Trim()
Assert-Exact 'Pinned predecessor commit' ((& git -C $repo rev-parse $predecessorCommit).Trim()) $predecessorCommit

$currentCommit=(& git -C $repo rev-parse HEAD).Trim()
$currentTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$candidateClosure=@('src/mod','targets','tools/mir/application/package','tools/mir/application/release','tools/mir/domain/canonicalization','tools/lib/mir4/BootstrapMaterialization.ps1','tools/lib/mir4/bootstrap-materialization','tools/lib/validation/PackageIdentity.ps1','tools/lib/validation/MIR4DistributionIdentity.ps1','spec/schemas/mir4-canonical-package-authority-v1.schema.json','spec/schemas/mir4-package-composition-result-v1.schema.json','contracts/release','releases/governance','changes','.mir/releases/waves/mir4-r0')
$closureChanges=@(& git -C $repo status --porcelain --untracked-files=all -- @candidateClosure)
Assert-Migration ($closureChanges.Count -eq 0) "Requires a clean current-candidate materialization closure: $($closureChanges -join '; ')"

. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')
$fixture=(Join-Path $repo 'fixtures/assert-mir42-v2-v3-cap-migration')
Assert-Migration (Test-Path -LiteralPath $fixture -PathType Container) 'Migration assertion fixture is absent.'

$run=Join-Path $output ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $run|Out-Null
$predecessorWorktree=Join-Path $repo ('build/wt/m42p-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$predecessorCandidate=$null
$predecessorCommitTree=$null
try{
  $worktreeOutput=@(& git -C $repo worktree add --detach $predecessorWorktree $predecessorCommit 2>&1)
  if($LASTEXITCODE -ne 0){throw "Could not materialize pinned predecessor worktree: $($worktreeOutput -join '; ')"}
  $predecessorCommitTree=(& git -C $predecessorWorktree rev-parse 'HEAD^{tree}').Trim()
  . (Join-Path $predecessorWorktree 'tools/mir/application/package/TargetMaterializer.ps1')
  $old=New-MIR4TargetPackage -RepoRoot $predecessorWorktree -Target f210 -CandidateId ('M42-V2-PREDECESSOR-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()) -SourceVersion '4.2.0' -DistributionVersion '4.2.21000' -OutputRoot 'build/m42mig/packages'
  $oldArchive=(Resolve-Path -LiteralPath ([string]$old.archive_path)).Path
  $predecessorCandidate=Join-Path $run (Split-Path -Leaf $oldArchive)
  Copy-Item -LiteralPath $oldArchive -Destination $predecessorCandidate
} finally {
  if(Test-Path -LiteralPath $predecessorWorktree -PathType Container){
    $removalOutput=@(& git -C $repo worktree remove --force $predecessorWorktree 2>&1)
    if($LASTEXITCODE -ne 0){throw "Could not remove the test-owned predecessor worktree: $($removalOutput -join '; ')"}
  }
}
Assert-Exact 'Predecessor worktree tree' $predecessorCommitTree ((& git -C $repo rev-parse "$predecessorCommit^{tree}").Trim())
Assert-Migration (Test-Path -LiteralPath $predecessorCandidate -PathType Leaf) 'Pinned predecessor package was not retained in evidence.'
Assert-Migration ((Get-ZipEntryText $predecessorCandidate 'prototypes/mir/emit/mod_data.lua') -match 'maximum-level-policy-v2') 'Predecessor package does not contain V2 transport.'
Assert-Migration ((Get-ZipEntryText $predecessorCandidate 'prototypes/mir/runtime/maximum_level_control.lua') -match 'local POLICY_VERSION = 1') 'Predecessor package does not contain the authentic V2 controller.'

. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
$current=New-MIR4TargetPackage -RepoRoot $repo -Target f210 -CandidateId ('M42-V3-MIGRATION-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()) -SourceVersion '4.2.0' -DistributionVersion '4.2.21000' -OutputRoot 'build/m42mig/packages'
$currentCandidate=(Resolve-Path -LiteralPath ([string]$current.archive_path)).Path
Assert-CandidateExclusions $currentCandidate
Assert-Migration ((Get-ZipEntryText $currentCandidate 'prototypes/mir/emit/mod_data.lua') -match 'maximum-level-policy-v3') 'Current package does not contain V3 transport.'
Assert-Migration ((Get-ZipEntryText $currentCandidate 'prototypes/mir/runtime/maximum_level_control.lua') -match 'local POLICY_VERSION = 3') 'Current package does not contain the V3 controller.'

$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent)-Parent)-Parent
function New-Stage([string]$Name,[string]$Candidate,[string]$FixtureVersion,[int]$Cap){
  $root=Join-Path $run $Name
  $mods=Join-Path $root 'mods'
  $userdata=Join-Path $root 'userdata'
  New-Item -ItemType Directory -Force -Path $mods,$userdata,(Join-Path $userdata 'saves')|Out-Null
  Copy-Item -LiteralPath $Candidate -Destination $mods
  $fixtureSource=Join-Path $root 'fixture-source'
  Copy-Item -LiteralPath $fixture -Destination $fixtureSource -Recurse
  $infoPath=Join-Path $fixtureSource 'info.json'
  $info=Get-Content -Raw -LiteralPath $infoPath|ConvertFrom-Json
  $info.version=$FixtureVersion
  [IO.File]::WriteAllText($infoPath,(($info|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  $fixtureArchive=Publish-MIRModDirectoryArchive -Source $fixtureSource -Name $fixtureName -Version $FixtureVersion -ModsDir $mods
  Initialize-MIRSettingsOverrideMod -ModsDir $mods -FactorioVersion '2.1'
  Set-CopiedStartupSettingDefaults -ModsDir $mods -Overrides @{'ips-enable-research_copper'=$true;'ips-max-level-research_copper'=$Cap}
  Complete-MIRSettingsOverrideMod -ModsDir $mods
  $names=@('base','elevated-rails','quality','recycler','space-age','more-infinite-research',$fixtureName,'mir-validation-settings-overrides')
  $modList=[ordered]@{mods=@($names|ForEach-Object{[ordered]@{name=$_;enabled=$true}})}
  $modListPath=Join-Path $mods 'mod-list.json'
  [IO.File]::WriteAllText($modListPath,(($modList|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  $config=Join-Path $root 'config.ini'
  [IO.File]::WriteAllText($config,"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($userdata.Replace('\','/'))`n",[Text.UTF8Encoding]::new($false))
  $server=Join-Path $root 'server-settings.json'
  $serverData=[ordered]@{name='MIR V2 to V3 migration';description='';tags=@();max_players=1;visibility=[ordered]@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false}
  [IO.File]::WriteAllText($server,(($serverData|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  [pscustomobject]@{name=$Name;root=$root;mods=$mods;userdata=$userdata;config=$config;server=$server;fixture_archive=$fixtureArchive;settings_archive=(Join-Path $mods 'mir-validation-settings-overrides_0.1.0.zip');mod_list=$modListPath;cap=$Cap;fixture_version=$FixtureVersion}
}
function Invoke-Engine([object]$Stage,[string]$Name,[string[]]$Arguments){
  $factorioLog=Join-Path $Stage.userdata 'factorio-current.log'
  if(Test-Path -LiteralPath $factorioLog){Remove-Item -LiteralPath $factorioLog -Force}
  $start=[Diagnostics.ProcessStartInfo]::new($engine)
  $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  $start.Environment['SteamAppId']='427520';$start.Environment['SteamGameId']='427520'
  foreach($argument in @('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods)+$Arguments){[void]$start.ArgumentList.Add($argument)}
  $process=[Diagnostics.Process]::Start($start)
  try{
    $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
    if(-not $process.WaitForExit(120000)){$process.Kill($true);throw "Factorio timed out during $Name."}
    $text=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $Stage.root "engine-$Name.log"),$text,[Text.UTF8Encoding]::new($false))
    if($process.ExitCode -ne 0){throw "Factorio failed during ${Name}: $($text.Substring([Math]::Max(0,$text.Length-2500)))"}
  }finally{$process.Dispose()}
  Assert-Migration (Test-Path -LiteralPath $factorioLog -PathType Leaf) "Factorio log is absent after $Name."
  $copy=Join-Path $Stage.root "factorio-$Name.log";Copy-Item -LiteralPath $factorioLog -Destination $copy;$copy
}
function Invoke-ServerSave([object]$Stage,[string]$Name,[string]$InputSave,[string]$ExpectedSave,[string]$ExpectedStage){
  $factorioLog=Join-Path $Stage.userdata 'factorio-current.log'
  if(Test-Path -LiteralPath $factorioLog){Remove-Item -LiteralPath $factorioLog -Force}
  $start=[Diagnostics.ProcessStartInfo]::new($engine)
  $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
  $start.Environment['SteamAppId']='427520';$start.Environment['SteamGameId']='427520'
  foreach($argument in @('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods,'--server-settings',$Stage.server,'--start-server',$InputSave)){[void]$start.ArgumentList.Add($argument)}
  $process=[Diagnostics.Process]::Start($start);$ready=$false
  try{
    $deadline=[DateTime]::UtcNow.AddSeconds(60);$needle="[mir42-v2-v3-cap-migration] STATE JSON {`"stage`":`"$ExpectedStage`""
    while([DateTime]::UtcNow -lt $deadline){
      if($process.HasExited){throw "Factorio server exited before $Name successor with code $($process.ExitCode)."}
      if((Test-Path -LiteralPath $factorioLog -PathType Leaf) -and (Test-Path -LiteralPath $ExpectedSave -PathType Leaf)){
        $text=Get-Content -Raw -LiteralPath $factorioLog
        if($text.Contains($needle) -and $text.Contains('Saving finished')){$ready=$true;break}
      }
      Start-Sleep -Milliseconds 200
    }
    if(-not $ready){throw "Factorio server did not create $Name successor."}
  }finally{if(-not $process.HasExited){try{$process.Kill($true)}catch{$process.Kill()}};$process.WaitForExit();$process.Dispose()}
  $copy=Join-Path $Stage.root "factorio-$Name.log";Copy-Item -LiteralPath $factorioLog -Destination $copy;$copy
}

$predecessorStage=New-Stage -Name predecessor -Candidate $predecessorCandidate -FixtureVersion '0.1.0' -Cap 3
$v3Stage=New-Stage -Name v3-capped -Candidate $currentCandidate -FixtureVersion '0.1.1' -Cap 3
$relaxedStage=New-Stage -Name v3-relaxed -Candidate $currentCandidate -FixtureVersion '0.1.2' -Cap 0
$predecessorSave=Join-Path $predecessorStage.root 'predecessor-v2.zip'
$predecessorLog=Invoke-Engine $predecessorStage 'predecessor' @('--create',$predecessorSave)
Assert-Migration (Test-Path -LiteralPath $predecessorSave -PathType Leaf) 'Predecessor save is absent.'
$predecessorState=Read-State (Get-Content -Raw -LiteralPath $predecessorLog) 'v2-seeded'

$v3Save=Join-Path $v3Stage.userdata 'saves/mir42-v2-v3-cap-migration-v3-capped.zip'
$v3Log=Invoke-ServerSave $v3Stage 'v3-capped' $predecessorSave $v3Save 'v3-capped'
$v3Text=Get-Content -Raw -LiteralPath $v3Log
$v3State=Read-State $v3Text 'v3-capped'
$ownedMigration=[regex]::Matches($v3Text,'\[more-infinite-research\] Migrated maximum-level V2 ownership force=v2-owned technology=recipe-prod-research_copper-1 enablement-owned=true visibility-owned=true policy-version=3[.]')
$foreignMigration=[regex]::Matches($v3Text,'\[more-infinite-research\] Migrated maximum-level V2 ownership force=v2-foreign-disabled technology=recipe-prod-research_copper-1 enablement-owned=false visibility-owned=true policy-version=3[.]')
Assert-Migration ($ownedMigration.Count -eq 1) "Expected exactly one admitted V2 owned migration diagnostic; observed $($ownedMigration.Count)."
Assert-Migration ($foreignMigration.Count -eq 1) "Expected exactly one admitted V2 foreign-disabled migration diagnostic; observed $($foreignMigration.Count)."

$relaxedSave=Join-Path $relaxedStage.userdata 'saves/mir42-v2-v3-cap-migration-v3-relaxed.zip'
$relaxedLog=Invoke-ServerSave $relaxedStage 'v3-relaxed' $v3Save $relaxedSave 'v3-relaxed'
$relaxedState=Read-State (Get-Content -Raw -LiteralPath $relaxedLog) 'v3-relaxed'
$terminalLog=Invoke-Engine $relaxedStage 'terminal' @('--benchmark',$relaxedSave,'--benchmark-ticks','10','--benchmark-runs','1','--benchmark-sanitize')
$terminalState=Read-State (Get-Content -Raw -LiteralPath $terminalLog) 'terminal'

$v2Forces=@(@{name='v2-owned';level=4;enabled=$false;visible_when_disabled=$true},@{name='v2-foreign-disabled';level=4;enabled=$false;visible_when_disabled=$true})
$v3Forces=@($v2Forces+@(@{name='v3-owned';level=4;enabled=$false;visible_when_disabled=$true}))
$relaxedForces=@(@{name='v2-owned';level=4;enabled=$true;visible_when_disabled=$false},@{name='v2-foreign-disabled';level=4;enabled=$false;visible_when_disabled=$false},@{name='v3-owned';level=4;enabled=$true;visible_when_disabled=$false})
Assert-State $predecessorState 'v2-seeded' 2 3 $false $false $v2Forces
Assert-State $v3State 'v3-capped' 3 3 $true $false $v3Forces
Assert-State $relaxedState 'v3-relaxed' 3 0 $true $true $relaxedForces
Assert-State $terminalState 'terminal' 3 0 $true $true $relaxedForces

$lineage=@(
  [ordered]@{stage='predecessor-v2';save=Get-Artifact $predecessorSave;predecessor_sha256=$null},
  [ordered]@{stage='v3-capped';save=Get-Artifact $v3Save;predecessor_sha256=Get-MigrationSha $predecessorSave},
  [ordered]@{stage='v3-relaxed';save=Get-Artifact $relaxedSave;predecessor_sha256=Get-MigrationSha $v3Save}
)
for($index=1;$index -lt $lineage.Count;$index++){
  Assert-Exact "save lineage $($lineage[$index].stage)" $lineage[$index].predecessor_sha256 $lineage[$index-1].save.raw_sha256
}
function Get-StageManifest([object]$Stage,[string]$Candidate){
  [ordered]@{name=$Stage.name;cap=$Stage.cap;fixture_version=$Stage.fixture_version;artifacts=[ordered]@{candidate=Get-Artifact (Join-Path $Stage.mods (Split-Path -Leaf $Candidate));fixture=Get-Artifact $Stage.fixture_archive;settings=Get-Artifact $Stage.settings_archive;mod_list=Get-Artifact $Stage.mod_list;config=Get-Artifact $Stage.config}}
}
$result=[ordered]@{
  schema=1
  kind='MIR42F210V2ToV3MaximumLevelMigrationQualificationV1'
  status='passed-current-f210-v2-to-v3-cap-migration-only'
  scope='Pinned origin/dev F210 V2 package reconstructed at f7f9bab, upgraded into a freshly materialized current F210 V3 candidate; authentic V2 runtime ownership, V3 migration/enforcement, cap=0 owner-only restoration, and research continuity.'
  target=[ordered]@{factorio_line='2.1';factorio_version='2.1.17';engine_sha256=$expectedEngineSha}
  predecessor=[ordered]@{commit=$predecessorCommit;tree=$predecessorCommitTree;candidate=Get-Artifact $predecessorCandidate;transport='maximum-level-policy-v2';runtime_controller_policy_version=1}
  source=[ordered]@{commit=$currentCommit;tree=$currentTree;package_source_sha256=Get-MigrationSha (Join-Path $repo 'src/mod/package-source.json');candidate_materialization_closure=$candidateClosure;candidate_materialization_closure_clean=$true}
  current_candidate=Get-Artifact $currentCandidate
  candidate_package_excludes_fixture_test_docs_governance_build_dist=$true
  fixture_source_hashes=[ordered]@{info=Get-MigrationSha (Join-Path $fixture 'info.json');data_final_fixes=Get-MigrationSha (Join-Path $fixture 'data-final-fixes.lua');control=Get-MigrationSha (Join-Path $fixture 'control.lua')}
  harness_sha256=Get-MigrationSha $PSCommandPath
  stages=@((Get-StageManifest $predecessorStage $predecessorCandidate),(Get-StageManifest $v3Stage $currentCandidate),(Get-StageManifest $relaxedStage $currentCandidate))
  migration_diagnostics=[ordered]@{owned_enablement_and_visibility_count=$ownedMigration.Count;foreign_visibility_only_count=$foreignMigration.Count;policy_version=3}
  state_receipts=[ordered]@{predecessor_v2=$predecessorState;v3_capped=$v3State;v3_relaxed=$relaxedState;terminal=$terminalState}
  save_lineage=$lineage
  f200_disposition=[ordered]@{status='excluded-current-target-lacks-v3-mod-data-transport';factorio_version='2.0.77';target_profile='targets/f200/files/prototypes/mir/platform/factorio/target_profiles.lua';reason='The F200 profile declares prototype_shapes.mod_data=false. Current V3 runtime only migrates V2 ownership after an accepted V3 transported binding; its settings fallback is deliberately legacy/read-only and does not migrate V2 ownership.';reconsider_when='An F200-specific accepted V3 binding transport or equivalent persisted ownership proof is implemented and qualified on the exact F200 engine.'}
  explicit_non_claims=$nonClaims
  logs=[ordered]@{predecessor=Get-Artifact $predecessorLog;v3_capped=Get-Artifact $v3Log;v3_relaxed=Get-Artifact $relaxedLog;terminal=Get-Artifact $terminalLog}
}
$resultPath=Join-Path $run 'result.json'
[IO.File]::WriteAllText($resultPath,(($result|ConvertTo-Json -Depth 40)+"`n"),[Text.UTF8Encoding]::new($false))
$result|ConvertTo-Json -Depth 40
Write-Output "Evidence: $run"
