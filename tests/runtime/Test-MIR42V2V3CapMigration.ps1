# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='',
  [string]$SteamManifest='',
  [string]$LibraryDirectory='',
  [switch]$PrepareInputsOnly,
  [string]$OutputRoot='build/tmp/m42mig',
  [string]$CandidateZip='',
  [string]$SourceMaterializationPath='',
  [string]$PredecessorCandidateZip='',
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120
)

$ErrorActionPreference='Stop'
$activeStage=$null
if(-not $PrepareInputsOnly -and (-not $FactorioBin -or -not $LibraryDirectory)){
  throw '[mir42-v2-v3-direct-inputs-required] Supply an explicit engine and flat archive library. No populated profile is created.'
}
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$buildRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
if(-not $output.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){
  throw 'V2-to-V3 cap migration evidence outputs must be under build.'
}

$predecessorCommit='f7f9bab7bb1d1a63c98b5e21178fbaed418a3f6e'
. (Join-Path $repo 'tools/mir/application/release/F210QualificationPolicy.ps1')

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
function Get-Artifact([string]$Path,[switch]$AllowExternal){
  $resolved=(Resolve-Path -LiteralPath $Path).Path
  Assert-MIRLibraryPath $resolved
  $inside=$resolved.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
  Assert-Migration ($inside -or $AllowExternal) "artifact is outside the repository: $resolved"
  [ordered]@{path=$(if($inside){$resolved.Substring($repo.Length+1).Replace('\','/')}else{$resolved});path_kind=$(if($inside){'repository-relative'}else{'machine-local-input'});bytes=(Get-Item -LiteralPath $resolved).Length;raw_sha256=Get-MigrationSha $resolved}
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

Assert-Exact 'Pinned predecessor commit' ((& git -C $repo rev-parse $predecessorCommit).Trim()) $predecessorCommit

$currentCommit=(& git -C $repo rev-parse HEAD).Trim()
$currentTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$candidateClosure=@('source','targets','tools/mir/application/package','tools/mir/application/release','tools/mir/domain/canonicalization','tools/lib/mir4/BootstrapMaterialization.ps1','tools/lib/mir4/bootstrap-materialization','tools/lib/validation/PackageIdentity.ps1','tools/lib/validation/MIR4DistributionIdentity.ps1','spec/schemas/mir4-canonical-package-authority-v2.schema.json','spec/schemas/mir4-package-composition-result-v1.schema.json','contracts/release','releases/governance','changes','.mir/releases/waves/mir4-r0')
$closureChanges=@(& git -C $repo status --porcelain --untracked-files=all -- @candidateClosure)
Assert-Migration ($closureChanges.Count -eq 0) "Requires a clean current-candidate materialization closure: $($closureChanges -join '; ')"

. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
$fixture=(Join-Path $repo 'fixtures/assert-mir42-v2-v3-cap-migration')
Assert-Migration (Test-Path -LiteralPath $fixture -PathType Container) 'Migration assertion fixture is absent.'

. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/mir/application/package/HistoricalSourceAuthority.ps1')
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxBranches 32 | Out-Host
$running=@(Get-Process -Name factorio -ErrorAction SilentlyContinue)
Assert-Migration ($running.Count -eq 0) 'requires one Factorio process tree; an engine is already running.'
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $output -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
$predecessorInput=Read-MIR421PinnedV2Candidate -RepoRoot $repo -Archive $PredecessorCandidateZip
$currentInput=Read-MIRNativeProbeF210CurrentCandidate -Repository $repo -Archive $CandidateZip -ReceiptPath $SourceMaterializationPath
$predecessorCandidate=[string]$predecessorInput.path
$predecessorCommitTree=[string]$predecessorInput.source_tree
$currentCandidate=[string]$currentInput.path
Assert-CandidateExclusions $currentCandidate
Assert-Migration ((Get-ZipEntryText $currentCandidate 'prototypes/mir/emit/mod_data.lua') -match 'maximum-level-policy-v3') 'Current package does not contain V3 transport.'
$currentMaximumLevelControl=Get-ZipEntryText $currentCandidate 'prototypes/mir/runtime/maximum_level_control.lua'
Assert-Migration ($currentMaximumLevelControl -match 'local POLICY_VERSION = 3') 'Current package does not contain the V3 controller.'
Assert-Migration ($currentMaximumLevelControl -match 'unowned_disabled_by_cap' -and $currentMaximumLevelControl -match 'migrated_unowned_disable' -and $currentMaximumLevelControl -match 'restore_unowned_disable_continuity') 'Current package does not contain the V2 unowned-disable continuity repair.'
trap {
  $failure=$_
  if($null -ne $activeStage -and $null -ne $activeStage.activation -and -not $activeStage.activation.closed){
    try{$activeStage.terminals.Add((Complete-MIRLibraryActivation $activeStage.activation))}catch{Write-Warning $_.Exception.Message}
  }
  if($null -ne $resources -and (Test-Path -LiteralPath $resources.root)){
    try{Write-MIRNativeProbeResult -Context $resources -Record @{status='failed';error=$failure.Exception.Message;source=$currentCommit;resource_runs=$resources.runs.ToArray()}}catch{Write-Warning $_.Exception.Message}
  }
  throw $failure
}
$run=$resources.root
New-Item -ItemType Directory -Path $run|Out-Null
function New-MigrationFixtureSource([string]$FixtureDirectory,[string]$Version){
  # This is generated assertion-fixture metadata. Player inputs are consumed
  # separately through the pinned predecessor and current materializer readers.
  Copy-Item -LiteralPath $fixture -Destination $FixtureDirectory -Recurse
  $infoPath=Join-Path $FixtureDirectory 'info.json';$info=Get-Content -LiteralPath $infoPath -Raw|ConvertFrom-Json
  $info.version=$Version
  [IO.File]::WriteAllText($infoPath,(($info|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  [pscustomobject]@{source=$FixtureDirectory;version=$Version;file=($fixtureName+'_'+$Version+'.zip')}
}
function New-MigrationSettingsSource([string]$SettingsDirectory,[int]$Cap){
  Assert-Migration ($Cap -in @(0,3)) 'unsupported settings cap'
  Initialize-MIRSettingsOverrideMod -ModsDir $SettingsDirectory -FactorioVersion '2.1'
  Set-CopiedStartupSettingDefaults -ModsDir $SettingsDirectory -Overrides @{'ips-enable-research_copper'=$true;'ips-max-level-research_copper'=$Cap}
  $source=Join-Path $SettingsDirectory 'mir-validation-settings-overrides';$infoPath=Join-Path $source 'info.json'
  $info=Get-Content -LiteralPath $infoPath -Raw|ConvertFrom-Json
  $info=[ordered]@{name=$info.name;version=$(if($Cap -eq 0){'0.1.310'}else{'0.1.313'});title=$info.title;author=$info.author;factorio_version=$info.factorio_version;dependencies=@($info.dependencies)}
  [IO.File]::WriteAllText($infoPath,($info|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  [pscustomobject]@{source=$source;version=$info.version;file=('mir-validation-settings-overrides_'+$info.version+'.zip')}
}
$preparedFixtures=@{};$preparedSettings=@{}
foreach($version in @('0.1.0','0.1.1','0.1.2','0.1.3')){$preparedFixtures[$version]=New-MigrationFixtureSource (Join-Path $run ('input-definitions/fixture-'+$version)) $version}
foreach($cap in @(0,3)){$preparedSettings[$cap]=New-MigrationSettingsSource (Join-Path $run ('input-definitions/cap-'+$cap)) $cap}
if($PrepareInputsOnly){
  $assets=Join-Path $run 'owned-inputs';[IO.Directory]::CreateDirectory($assets)|Out-Null
  $archives=@(foreach($version in @('0.1.0','0.1.1','0.1.2','0.1.3')){Publish-MIRModDirectoryArchive -Source $preparedFixtures[$version].source -Name $fixtureName -Version $version -ModsDir $assets})
  foreach($cap in @(0,3)){$input=$preparedSettings[$cap];$archives+=Publish-MIRModDirectoryArchive -Source $input.source -Name 'mir-validation-settings-overrides' -Version $input.version -ModsDir $assets}
  Write-MIRNativeProbeResult -Context $resources -Record @{status='prepared-owned-inputs-only';source=$currentCommit;archives=@($archives|ForEach-Object{Get-Artifact $_});native_factorio=$false;predecessor_input=$predecessorInput;candidate_materialization=$currentInput.receipt}
  Write-Output "Prepared inputs: $run";return
}
Assert-MIR441CleanTrackedSource -RepoRoot $repo
$library=(Resolve-Path -LiteralPath $LibraryDirectory).Path;Assert-MIRLibraryPath $library
function Get-MigrationGovernedEngineResolution {
  # Keep the complete existing admission oracle, including its version query,
  # inside one owned monitored tree. No policy facts are reconstructed here.
  $driver=Join-Path $resources.root 'resolve-engine.ps1'
  $receipt=Join-Path $resources.root 'engine-resolution.json'
  $driverText=@'
param([string]$Repository,[string]$Engine,[string]$Manifest,[string]$Receipt)
$ErrorActionPreference='Stop'
$env:SteamAppId='427520';$env:SteamGameId='427520'
. (Join-Path $Repository 'tools/mir/application/release/F210QualificationPolicy.ps1')
$record=Resolve-MIR4F210CurrentEngineCapHarnessAdmissionV3 -RepoRoot $Repository -HarnessId 'runtime.maximum-level-v2-v3-migration-f210' -FactorioBin $Engine -SteamManifest $Manifest
[IO.File]::WriteAllText($Receipt,(($record|ConvertTo-Json -Depth 50)+"`n"),[Text.UTF8Encoding]::new($false))
'@
  [IO.File]::WriteAllText($driver,$driverText,[Text.UTF8Encoding]::new($false))
  $null=Invoke-MIRNativeProbeProcess -Context $resources -FilePath (Get-Command pwsh).Source -TimeoutSeconds 30 -Arguments @('-NoProfile','-File',$driver,'-Repository',$repo,'-Engine',$FactorioBin,'-Manifest',$SteamManifest,'-Receipt',$receipt)
  Assert-Migration (Test-Path -LiteralPath $receipt -PathType Leaf) 'governed engine resolution receipt is absent.'
  Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json -Depth 50 -DateKind String
}
$engineResolution=Get-MigrationGovernedEngineResolution
$engine=[string]$engineResolution.engine.path
Assert-Exact 'Factorio executable SHA-256' (Get-MigrationSha $engine) ([string]$engineResolution.engine.sha256)
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent)-Parent)-Parent
function New-Stage([string]$Name,[string]$Candidate,[string]$FixtureVersion,[int]$Cap){
  $root=Join-Path $run $Name
  $userdata=Join-Path $root 'userdata'
  New-Item -ItemType Directory -Force -Path $userdata,(Join-Path $userdata 'saves')|Out-Null
  $isPredecessor=$Candidate -ceq $predecessorCandidate
  $hash=if($isPredecessor){$predecessorInput.archive_sha256}else{$currentInput.receipt.archive_sha256}
  $version=if($isPredecessor){'4.2.21000'}else{'4.2.21001'}
  $candidateName=[IO.Path]::GetFileName($Candidate);$installed=Join-Path $library $candidateName
  Assert-MIRLibraryPath $installed
  Assert-Exact 'installed candidate hash' (Get-MigrationSha $installed) ([string]$hash)
  $fixtureInput=$preparedFixtures[$FixtureVersion];$settingsInput=$preparedSettings[$Cap]
  $fixtureArchive=Join-Path $library $fixtureInput.file;$settingsArchive=Join-Path $library $settingsInput.file
  Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $fixtureInput.source
  Assert-MIRLibraryFixtureArchive -Archive $settingsArchive -SourceDirectory $settingsInput.source
  $hashes=@{$candidateName=[string]$hash;$fixtureInput.file=(Get-MigrationSha $fixtureArchive);$settingsInput.file=(Get-MigrationSha $settingsArchive)}
  $baseVersion=[string](Get-Content -LiteralPath (Join-Path $engineRoot 'data/base/info.json') -Raw|ConvertFrom-Json).version
  $modList=[ordered]@{mods=@(
    @('base','elevated-rails','quality','recycler','space-age')|ForEach-Object{[ordered]@{name=$_;version=$baseVersion;enabled=$true}}
    [ordered]@{name='more-infinite-research';version=$version;enabled=$true}
    [ordered]@{name=$fixtureName;version=$FixtureVersion;enabled=$true}
    [ordered]@{name='mir-validation-settings-overrides';version=$settingsInput.version;enabled=$true}
  )}
  $modListPath=Join-Path $root 'selection.json'
  [IO.File]::WriteAllText($modListPath,(($modList|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  $config=Join-Path $root 'config.ini'
  [IO.File]::WriteAllText($config,"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($userdata.Replace('\','/'))`n[other]`nenable-new-mods=false`ncheck-updates=false`ndisable-blueprint-storage=true`n",[Text.UTF8Encoding]::new($false))
  $server=Join-Path $root 'server-settings.json'
  $serverData=[ordered]@{name='MIR V2 to V3 migration';description='';tags=@();max_players=1;visibility=[ordered]@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false}
  [IO.File]::WriteAllText($server,(($serverData|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  [pscustomobject]@{name=$Name;root=$root;mods=$library;userdata=$userdata;config=$config;server=$server;fixture_archive=$fixtureArchive;settings_archive=$settingsArchive;mod_list=$modListPath;cap=$Cap;fixture_version=$FixtureVersion;archive_hashes=$hashes;activation=$null;terminals=[Collections.Generic.List[object]]::new()}
}
function Start-MigrationStage($Stage){
  $Stage.activation=Start-MIRLibraryActivation -LibraryDirectory $Stage.mods -EngineDataDirectory (Join-Path $engineRoot 'data') -ProfilePath $Stage.mod_list -ArchiveHashes $Stage.archive_hashes -SettingsMode Defaults
  $script:activeStage=$Stage
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $Stage.activation
  [IO.File]::WriteAllBytes((Join-Path $Stage.root 'active-mod-list.json'),$Stage.activation.mod_list_bytes)
}
function Complete-MigrationStage($Stage,[string]$Log){
  $null=Assert-MIRLibraryLoadedSelection -Activation $Stage.activation -LogPath $Log -LatestInvocation
  $Stage.terminals.Add((Complete-MIRLibraryActivation $Stage.activation))
  $script:activeStage=$null
}
function Invoke-Engine([object]$Stage,[string]$Name,[string[]]$Arguments){
  Start-MigrationStage $Stage
  $factorioLog=Join-Path $Stage.userdata 'factorio-current.log'
  if(Test-Path -LiteralPath $factorioLog){Remove-Item -LiteralPath $factorioLog -Force}
  $nativeArguments=@('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods)+$Arguments
  Assert-MIRLibraryLaunch -Activation $Stage.activation -FactorioBin $engine -Arguments $nativeArguments
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -TimeoutSeconds 120 -Arguments $nativeArguments
  $text=(Get-Content -Raw -LiteralPath $actor.stdout)+(Get-Content -Raw -LiteralPath $actor.stderr)
  Assert-Migration ([Text.Encoding]::UTF8.GetByteCount($text) -lt (Get-MIRNativeProbeRemainingOutputBytes -Context $resources)) 'engine capture exceeds remaining output allowance.'
  [IO.File]::WriteAllText((Join-Path $Stage.root "engine-$Name.log"),$text,[Text.UTF8Encoding]::new($false))
  Assert-Migration (Test-Path -LiteralPath $factorioLog -PathType Leaf) "Factorio log is absent after $Name."
  $copy=Join-Path $Stage.root "factorio-$Name.log";Copy-Item -LiteralPath $factorioLog -Destination $copy;Complete-MigrationStage $Stage $copy;$copy
}
function Invoke-ServerSave([object]$Stage,[string]$Name,[string]$InputSave,[string]$ExpectedSave,[string]$ExpectedStage){
  Start-MigrationStage $Stage
  $factorioLog=Join-Path $Stage.userdata 'factorio-current.log'
  if(Test-Path -LiteralPath $factorioLog){Remove-Item -LiteralPath $factorioLog -Force}
  $needle="[mir42-v2-v3-cap-migration] STATE JSON {`"stage`":`"$ExpectedStage`""
  $completion={
    if(-not (Test-Path -LiteralPath $factorioLog -PathType Leaf) -or -not (Test-Path -LiteralPath $ExpectedSave -PathType Leaf)){return $false}
    try{$text=Get-Content -Raw -LiteralPath $factorioLog -ErrorAction Stop}catch [IO.IOException]{return $false}
    return $null -ne $text -and $text.Contains($needle) -and $text.Contains('Saving finished')
  }.GetNewClosure()
  $nativeArguments=@('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods,'--server-settings',$Stage.server,'--start-server',$InputSave)
  Assert-MIRLibraryLaunch -Activation $Stage.activation -FactorioBin $engine -Arguments $nativeArguments
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -TimeoutSeconds 60 -CompletionPredicate $completion -Arguments $nativeArguments
  Assert-Migration ([bool]$actor.result.completion_predicate_observed) "Factorio server did not create $Name successor."
  $copy=Join-Path $Stage.root "factorio-$Name.log";Copy-Item -LiteralPath $factorioLog -Destination $copy;Complete-MigrationStage $Stage $copy;$copy
}

$v2UnboundedStage=New-Stage -Name v2-unbounded -Candidate $predecessorCandidate -FixtureVersion '0.1.0' -Cap 0
$v2CappedStage=New-Stage -Name v2-capped -Candidate $predecessorCandidate -FixtureVersion '0.1.1' -Cap 3
$v3Stage=New-Stage -Name v3-capped -Candidate $currentCandidate -FixtureVersion '0.1.2' -Cap 3
$relaxedStage=New-Stage -Name v3-relaxed -Candidate $currentCandidate -FixtureVersion '0.1.3' -Cap 0
$v2UnboundedSave=Join-Path $v2UnboundedStage.root 'predecessor-v2-unbounded.zip'
$v2UnboundedLog=Invoke-Engine $v2UnboundedStage 'v2-unbounded' @('--create',$v2UnboundedSave)
Assert-Migration (Test-Path -LiteralPath $v2UnboundedSave -PathType Leaf) 'V2 cap=0 seed save is absent.'
$v2UnboundedState=Read-State (Get-Content -Raw -LiteralPath $v2UnboundedLog) 'v2-unbounded'

$v2CappedSave=Join-Path $v2CappedStage.userdata 'saves/mir42-v2-v3-cap-migration-v2-capped.zip'
$v2CappedLog=Invoke-ServerSave $v2CappedStage 'v2-capped' $v2UnboundedSave $v2CappedSave 'v2-capped'
$v2CappedState=Read-State (Get-Content -Raw -LiteralPath $v2CappedLog) 'v2-capped'

$v3Save=Join-Path $v3Stage.userdata 'saves/mir42-v2-v3-cap-migration-v3-capped.zip'
$v3Log=Invoke-ServerSave $v3Stage 'v3-capped' $v2CappedSave $v3Save 'v3-capped'
$v3Text=Get-Content -Raw -LiteralPath $v3Log
$v3State=Read-State $v3Text 'v3-capped'
$ownedMigration=[regex]::Matches($v3Text,'\[more-infinite-research\] Migrated maximum-level V2 ownership force=v2-owned technology=recipe-prod-research_copper-1 enablement-owned=true visibility-owned=true policy-version=3[.]')
$foreignMigration=[regex]::Matches($v3Text,'\[more-infinite-research\] Migrated maximum-level V2 ownership force=v2-foreign-disabled technology=recipe-prod-research_copper-1 enablement-owned=false visibility-owned=true policy-version=3[.]')
$unownedDisableContinuity=[regex]::Matches($v3Text,'\[more-infinite-research\] Captured maximum-level V2 unowned-disable continuity force=v2-foreign-disabled technology=recipe-prod-research_copper-1 original-enabled=false policy-version=3[.]')
Assert-Migration ($ownedMigration.Count -eq 1) "Expected exactly one admitted V2 owned migration diagnostic; observed $($ownedMigration.Count)."
Assert-Migration ($foreignMigration.Count -eq 1) "Expected exactly one admitted V2 foreign visibility-only migration diagnostic; observed $($foreignMigration.Count)."
Assert-Migration ($unownedDisableContinuity.Count -eq 1) "Expected exactly one V2 unowned-disable continuity diagnostic; observed $($unownedDisableContinuity.Count)."

$relaxedSave=Join-Path $relaxedStage.userdata 'saves/mir42-v2-v3-cap-migration-v3-relaxed.zip'
$relaxedLog=Invoke-ServerSave $relaxedStage 'v3-relaxed' $v3Save $relaxedSave 'v3-relaxed'
$relaxedState=Read-State (Get-Content -Raw -LiteralPath $relaxedLog) 'v3-relaxed'
$terminalLog=Invoke-Engine $relaxedStage 'terminal' @('--benchmark',$relaxedSave,'--benchmark-ticks','10','--benchmark-runs','1','--benchmark-sanitize')
$terminalState=Read-State (Get-Content -Raw -LiteralPath $terminalLog) 'terminal'

$v2UnboundedForces=@(@{name='v2-owned';level=4;enabled=$true;visible_when_disabled=$false},@{name='v2-foreign-disabled';level=4;enabled=$false;visible_when_disabled=$false})
$v2CappedForces=@(@{name='v2-owned';level=4;enabled=$false;visible_when_disabled=$true},@{name='v2-foreign-disabled';level=4;enabled=$false;visible_when_disabled=$true})
$v2Forces=$v2CappedForces
$v3Forces=@($v2Forces+@(@{name='v3-owned';level=4;enabled=$false;visible_when_disabled=$true}))
$relaxedForces=@(@{name='v2-owned';level=4;enabled=$true;visible_when_disabled=$false},@{name='v2-foreign-disabled';level=4;enabled=$false;visible_when_disabled=$false},@{name='v3-owned';level=4;enabled=$true;visible_when_disabled=$false})
Assert-State $v2UnboundedState 'v2-unbounded' 2 0 $false $false $v2UnboundedForces
Assert-State $v2CappedState 'v2-capped' 2 3 $false $false $v2CappedForces
Assert-State $v3State 'v3-capped' 3 3 $true $false $v3Forces
Assert-State $relaxedState 'v3-relaxed' 3 0 $true $true $relaxedForces
Assert-State $terminalState 'terminal' 3 0 $true $true $relaxedForces

$lineage=@(
  [ordered]@{stage='predecessor-v2-unbounded';save=Get-Artifact $v2UnboundedSave;predecessor_sha256=$null},
  [ordered]@{stage='predecessor-v2-capped';save=Get-Artifact $v2CappedSave;predecessor_sha256=Get-MigrationSha $v2UnboundedSave},
  [ordered]@{stage='v3-capped';save=Get-Artifact $v3Save;predecessor_sha256=Get-MigrationSha $v2CappedSave},
  [ordered]@{stage='v3-relaxed';save=Get-Artifact $relaxedSave;predecessor_sha256=Get-MigrationSha $v3Save}
)
for($index=1;$index -lt $lineage.Count;$index++){
  Assert-Exact "save lineage $($lineage[$index].stage)" $lineage[$index].predecessor_sha256 $lineage[$index-1].save.raw_sha256
}
function Get-StageManifest([object]$Stage,[string]$Candidate){
  [ordered]@{name=$Stage.name;cap=$Stage.cap;fixture_version=$Stage.fixture_version;artifacts=[ordered]@{candidate=Get-Artifact (Join-Path $Stage.mods (Split-Path -Leaf $Candidate)) -AllowExternal;fixture=Get-Artifact $Stage.fixture_archive -AllowExternal;settings=Get-Artifact $Stage.settings_archive -AllowExternal;mod_list=Get-Artifact $Stage.mod_list;config=Get-Artifact $Stage.config}}
}
$result=[ordered]@{
  schema=1
  kind='MIR42F210V2ToV3MaximumLevelMigrationQualificationV1'
  status='passed-current-f210-v2-to-v3-cap-migration-only'
  scope='Pinned origin/dev F210 V2 package verified against the exact f7f9bab binding set, seeded at V2 cap=0, changed to V2 cap=3 to distinguish owned from pre-disabled state, then upgraded into a supplied current 4.2.21001 F210 V3 candidate; authentic V2 runtime ownership, V3 migration/enforcement, cap=0 owner-only restoration, and research continuity.'
  target=[ordered]@{
    factorio_line='2.1'
    factorio_version=[string]$engineResolution.engine.version
    engine_build=[int]$engineResolution.engine.build
    engine_file_version=[string]$engineResolution.engine.file_version
    engine_sha256=[string]$engineResolution.engine.sha256
    engine_resolution_record_sha256=[string]$engineResolution.record_sha256
    steam_app_id=[string]$engineResolution.steam.app_id
    steam_branch=[string]$engineResolution.steam.branch
    steam_build_id=[string]$engineResolution.steam.build_id
    steam_manifest_sha256=[string]$engineResolution.steam.app_manifest_sha256
  }
  predecessor=[ordered]@{commit=$predecessorCommit;tree=$predecessorCommitTree;candidate=Get-Artifact (Join-Path $v2UnboundedStage.mods (Split-Path -Leaf $predecessorCandidate)) -AllowExternal;transport='maximum-level-policy-v2';runtime_controller_policy_version=1}
  source=[ordered]@{commit=$currentCommit;tree=$currentTree;package_source_sha256=$currentInput.receipt.package_source_sha256;candidate_materialization_closure=$candidateClosure;candidate_materialization_closure_clean=$true}
  current_candidate=Get-Artifact (Join-Path $v3Stage.mods (Split-Path -Leaf $currentCandidate)) -AllowExternal
  candidate_package_excludes_fixture_test_docs_governance_build_dist=$true
  fixture_source_hashes=[ordered]@{info=Get-MigrationSha (Join-Path $fixture 'info.json');data_final_fixes=Get-MigrationSha (Join-Path $fixture 'data-final-fixes.lua');control=Get-MigrationSha (Join-Path $fixture 'control.lua')}
  harness_sha256=Get-MigrationSha $PSCommandPath
  stages=@((Get-StageManifest $v2UnboundedStage $predecessorCandidate),(Get-StageManifest $v2CappedStage $predecessorCandidate),(Get-StageManifest $v3Stage $currentCandidate),(Get-StageManifest $relaxedStage $currentCandidate))
  migration_diagnostics=[ordered]@{owned_enablement_and_visibility_count=$ownedMigration.Count;foreign_visibility_only_count=$foreignMigration.Count;unowned_disable_continuity_count=$unownedDisableContinuity.Count;policy_version=3}
  state_receipts=[ordered]@{predecessor_v2_unbounded=$v2UnboundedState;predecessor_v2_capped=$v2CappedState;v3_capped=$v3State;v3_relaxed=$relaxedState;terminal=$terminalState}
  save_lineage=$lineage
  f200_disposition=[ordered]@{status='settings-derived-V3-transition-qualified-no-transported-V2-migration';factorio_version='2.0.77';target_profile='source/adapters/f200/prototypes/mir/platform/factorio/target_profiles.lua';separate_qualification='tests/runtime/Test-MIR42F200SettingsCapTransition.ps1';reason='The F200 profile declares prototype_shapes.mod_data=false. Current settings-derived V3 records capture current MIR ownership and have a separately exact-engine-qualified finite-to-zero transition; authentic V2 transport remains read-only and is not migrated on F200.';reconsider_when='An F200-specific accepted V3 binding transport plus an authentic persisted V2 predecessor case is implemented and qualified on the exact F200 engine.'}
  explicit_non_claims=$nonClaims
  logs=[ordered]@{predecessor_v2_unbounded=Get-Artifact $v2UnboundedLog;predecessor_v2_capped=Get-Artifact $v2CappedLog;v3_capped=Get-Artifact $v3Log;v3_relaxed=Get-Artifact $relaxedLog;terminal=Get-Artifact $terminalLog}
}
$resultPath=Join-Path $run 'result.json'
$result['library_activations']=@($v2UnboundedStage,$v2CappedStage,$v3Stage,$relaxedStage|ForEach-Object {$_.terminals.ToArray()})
$result['dependency_payload_bytes_copied']=0
$result['archive_links_created']=0
$result['predecessor_input']=$predecessorInput
$result['candidate_materialization']=$currentInput.receipt
$result['resource_context']=[ordered]@{expected_peak_memory_bytes=$resources.peak_memory_bytes;max_new_output_bytes=$resources.max_new_output_bytes;shared_alias_bytes=$resources.shared_alias_bytes;memory_enforcement='sampled-watchdog-not-hard-cap'}
$result['process_inventory']=@($resources.runs)
Assert-MIR441CleanTrackedSource -RepoRoot $repo
Assert-Exact 'source after execution' ((& git -C $repo rev-parse HEAD).Trim()) $currentCommit
Assert-Exact 'engine after execution' (Get-MigrationSha $engine) ([string]$engineResolution.engine.sha256)
foreach($stage in @($v2UnboundedStage,$v2CappedStage,$v3Stage,$relaxedStage)){foreach($entry in $stage.archive_hashes.GetEnumerator()){Assert-Exact ('library input after '+$stage.name+': '+$entry.Key) (Get-MigrationSha (Join-Path $library $entry.Key)) ([string]$entry.Value)}}
Write-MIRNativeProbeResult -Context $resources -Record $result
$result|ConvertTo-Json -Depth 40
Write-Output "Evidence: $run"
