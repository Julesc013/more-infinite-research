# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='',
  [string]$SteamManifest='',
  [string]$LibraryDirectory='',
  [switch]$PrepareInputsOnly,
  [string]$CandidateZip='',
  [string]$SourceMaterializationPath='',
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120,
  [string]$OutputRoot='build/p/m421-f210-cap'
)

$ErrorActionPreference='Stop'
$resources=$null;$activeStage=$null
Set-StrictMode -Version Latest
if(-not $PrepareInputsOnly -and (-not $FactorioBin -or -not $LibraryDirectory)){
  throw '[mir42-f210-direct-inputs-required] Supply an explicit engine and flat archive library. No populated profile is created.'
}

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$buildRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
if(-not $output.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){
  throw 'MIR42 cap ownership/multiforce evidence outputs must be under build.'
}

. (Join-Path $repo 'tools/mir/application/release/F210QualificationPolicy.ps1')
$fixtureName='mir-fixture-assert-mir42-cap-ownership-multiforce'
$blockerName='late-mir42-cap-binding-blocker'
$policyBlockerName='late-mir42-policy-binding-blocker'
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
  'external-queue-manager-interoperability-or-second-queue-owner',
  'unobservable-same-value-foreign-write-detection',
  'CAP-FOREIGN-DISABLE',
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
function Get-MIR42Artifact([string]$Path,[switch]$AllowExternal){
  $resolved=(Resolve-Path -LiteralPath $Path).Path
  Assert-MIRLibraryPath $resolved
  $inside=$resolved.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
  Assert-MIR42 ($inside -or $AllowExternal) "artifact is outside the repository: $resolved"
  return [ordered]@{
    path=$(if($inside){$resolved.Substring($repo.Length+1).Replace('\','/')}else{$resolved})
    path_kind=$(if($inside){'repository-relative'}else{'machine-local-input'})
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
function Assert-MIR42State($State,[string]$ExpectedStage,[int]$ExpectedCap,[int]$ExpectedBrowserCap,[bool]$ExpectedBlocker,[bool]$ExpectedPolicyBlocker,[int]$ExpectedConfigurationChanges,[int]$ExpectedForceResetEvents,[string[]]$ExpectedEventProbeQueue,[object[]]$ExpectedForces){
  Assert-Properties "state.$ExpectedStage" $State @('stage','cap','browser_cap','blocker','policy_blocker','configuration_changed_events','force_reset_events','merge_source_index','merge_destination_index','reused_force_index','merge_source_was_capped','source_index_reused','event_probe_queue','forces')
  Assert-Exact "$ExpectedStage.stage" $State.stage $ExpectedStage
  Assert-Exact "$ExpectedStage.cap" ([int]$State.cap) $ExpectedCap
  Assert-Exact "$ExpectedStage.browser_cap" ([int]$State.browser_cap) $ExpectedBrowserCap
  Assert-Exact "$ExpectedStage.blocker" ([bool]$State.blocker) $ExpectedBlocker
  Assert-Exact "$ExpectedStage.policy_blocker" ([bool]$State.policy_blocker) $ExpectedPolicyBlocker
  Assert-Exact "$ExpectedStage.configuration_changed_events" ([int]$State.configuration_changed_events) $ExpectedConfigurationChanges
  Assert-Exact "$ExpectedStage.force_reset_events" ([int]$State.force_reset_events) $ExpectedForceResetEvents
  Assert-Exact "$ExpectedStage.event_probe_queue" ((@($State.event_probe_queue)|ForEach-Object{[string]$_}) -join "`n") ($ExpectedEventProbeQueue -join "`n")
  if($ExpectedStage -in @('seed','capped')){
    Assert-Exact "$ExpectedStage.merge_source_index" ([int]$State.merge_source_index) 0
    Assert-Exact "$ExpectedStage.merge_destination_index" ([int]$State.merge_destination_index) 0
    Assert-Exact "$ExpectedStage.reused_force_index" ([int]$State.reused_force_index) 0
    Assert-Exact "$ExpectedStage.merge_source_was_capped" ([bool]$State.merge_source_was_capped) $false
    Assert-Exact "$ExpectedStage.source_index_reused" ([bool]$State.source_index_reused) $false
  } else {
    Assert-MIR42 ([int]$State.merge_source_index -gt 0) "$ExpectedStage has no removed merge-source index."
    Assert-MIR42 ([int]$State.merge_destination_index -gt 0) "$ExpectedStage has no merge-destination index."
    Assert-Exact "$ExpectedStage.reused_force_index" ([int]$State.reused_force_index) ([int]$State.merge_source_index)
    Assert-MIR42 ([int]$State.merge_destination_index -ne [int]$State.merge_source_index) "$ExpectedStage merge destination reused the source index."
    Assert-Exact "$ExpectedStage.merge_source_was_capped" ([bool]$State.merge_source_was_capped) $true
    Assert-Exact "$ExpectedStage.source_index_reused" ([bool]$State.source_index_reused) $true
  }
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
    browser_cap=[int]$State.browser_cap
    blocker=[bool]$State.blocker
    policy_blocker=[bool]$State.policy_blocker
    configuration_changed_events=[int]$State.configuration_changed_events
    force_reset_events=[int]$State.force_reset_events
    event_probe_queue=@($State.event_probe_queue|ForEach-Object{[string]$_})
    merge_source_index=[int]$State.merge_source_index
    merge_destination_index=[int]$State.merge_destination_index
    reused_force_index=[int]$State.reused_force_index
    merge_source_was_capped=[bool]$State.merge_source_was_capped
    source_index_reused=[bool]$State.source_index_reused
    forces=$forces
  }|ConvertTo-Json -Depth 8 -Compress)
}

$sourceCommit=(& git -C $repo rev-parse HEAD).Trim()
$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
Assert-MIR42 ($sourceCommit -match '^[0-9a-f]{40}$' -and $sourceTree -match '^[0-9a-f]{40}$') 'requires source commit/tree identities.'
$candidateMaterializationClosure=@(
  'source'
  'targets'
  'tools/mir/application/package'
  'tools/mir/application/release'
  'tools/mir/domain/canonicalization'
  'tools/lib/mir4/BootstrapMaterialization.ps1'
  'tools/lib/mir4/bootstrap-materialization'
  'tools/lib/validation/PackageIdentity.ps1'
  'tools/lib/validation/MIR4DistributionIdentity.ps1'
  'spec/schemas/mir4-canonical-package-authority-v1.schema.json'
  'spec/schemas/mir4-package-composition-result-v1.schema.json'
  'contracts/release'
  'releases/governance'
  'changes'
  '.mir/releases/waves/mir4-r0'
)
$candidateInputChanges=@(& git -C $repo status --porcelain --untracked-files=all -- @candidateMaterializationClosure)
Assert-MIR42 ($candidateInputChanges.Count -eq 0) "requires a clean candidate-materialization closure: $($candidateInputChanges -join '; ')"

. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
$running=@(Get-Process -Name factorio -ErrorAction SilentlyContinue)
Assert-MIR42 ($running.Count-eq0) 'requires the one-Factorio-process policy; a Factorio process is already running.'
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $output -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
$candidateInput=Read-MIRNativeProbeF210CurrentCandidate -Repository $repo -Archive $CandidateZip -ReceiptPath $SourceMaterializationPath
$candidateZip=[string]$candidateInput.path
trap {
  $failure=$_
  if($null-ne$activeStage -and $null-ne$activeStage.activation -and -not$activeStage.activation.closed){
    try{$activeStage.terminals.Add((Complete-MIRLibraryActivation $activeStage.activation))}catch{Write-Warning $_.Exception.Message}
  }
  if($null-ne$resources -and (Test-Path -LiteralPath $resources.root)){
    try{Write-MIRNativeProbeResult -Context $resources -Record @{status='failed';error=$failure.Exception.Message;source=$sourceCommit;resource_runs=$resources.runs.ToArray()}}catch{Write-Warning $_.Exception.Message}
  }
  throw $failure
}
New-Item -ItemType Directory -Path $resources.root|Out-Null

function Get-MIR42GovernedEngineResolution {
  # Keep the complete existing admission oracle, including its version query,
  # inside one owned monitored tree. No policy facts are reconstructed here.
  $driver=Join-Path $resources.root 'resolve-engine.ps1'
  $receipt=Join-Path $resources.root 'engine-resolution.json'
  $driverText=@'
param([string]$Repository,[string]$Engine,[string]$Manifest,[string]$Receipt)
$ErrorActionPreference='Stop'
$env:SteamAppId='427520';$env:SteamGameId='427520'
. (Join-Path $Repository 'tools/mir/application/release/F210QualificationPolicy.ps1')
$record=Resolve-MIR4F210CurrentEngineCapHarnessAdmissionV3 -RepoRoot $Repository -HarnessId 'runtime.maximum-level-cap-ownership-multiforce-f210' -FactorioBin $Engine -SteamManifest $Manifest
[IO.File]::WriteAllText($Receipt,(($record|ConvertTo-Json -Depth 50)+"`n"),[Text.UTF8Encoding]::new($false))
'@
  [IO.File]::WriteAllText($driver,$driverText,[Text.UTF8Encoding]::new($false))
  $null=Invoke-MIRNativeProbeProcess -Context $resources -FilePath (Get-Command pwsh).Source -TimeoutSeconds 30 -Arguments @('-NoProfile','-File',$driver,'-Repository',$repo,'-Engine',$FactorioBin,'-Manifest',$SteamManifest,'-Receipt',$receipt)
  Assert-MIR42 (Test-Path -LiteralPath $receipt -PathType Leaf) 'governed engine resolution receipt is absent.'
  Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json -Depth 50 -DateKind String
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
$policyBlockerFixture=Join-Path $repo 'fixtures/late-mir42-policy-binding-blocker'
foreach($path in @($fixture,$blockerFixture,$policyBlockerFixture)){
  Assert-MIR42 (Test-Path -LiteralPath $path -PathType Container) "fixture directory is absent: $path"
}

$run=$resources.root

function New-MIR42CapSettingsSource([string]$Root,[int]$Cap){
  Assert-MIR42 ($Cap-in@(0,3)) 'unsupported cap fixture'
  Initialize-MIRSettingsOverrideMod -ModsDir $Root -FactorioVersion '2.1'
  Set-CopiedStartupSettingDefaults -ModsDir $Root -Overrides @{'ips-enable-research_copper'=$true;'ips-max-level-research_copper'=$Cap}
  $source=Join-Path $Root 'mir-validation-settings-overrides'
  $infoPath=Join-Path $source 'info.json';$info=Get-Content -LiteralPath $infoPath -Raw|ConvertFrom-Json
  $info=[ordered]@{name=$info.name;version=$(if($Cap-eq0){'0.1.200'}else{'0.1.203'});title=$info.title;author=$info.author;factorio_version=$info.factorio_version;dependencies=@($info.dependencies)}
  [IO.File]::WriteAllText($infoPath,($info|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  [pscustomobject]@{source=$source;version=$info.version;file=('mir-validation-settings-overrides_'+$info.version+'.zip')}
}
$preparedSettings=@{}
foreach($cap in @(0,3)){$preparedSettings[$cap]=New-MIR42CapSettingsSource (Join-Path $run ('input-definitions/cap-'+$cap)) $cap}
if($PrepareInputsOnly){
  $assets=Join-Path $run 'owned-inputs';[IO.Directory]::CreateDirectory($assets)|Out-Null
  $archives=@(Publish-MIRModDirectoryArchive -Source $fixture -Name $fixtureName -Version '0.1.0' -ModsDir $assets)
  $archives+=Publish-MIRModDirectoryArchive -Source $blockerFixture -Name $blockerName -Version '0.1.0' -ModsDir $assets
  $archives+=Publish-MIRModDirectoryArchive -Source $policyBlockerFixture -Name $policyBlockerName -Version '0.1.0' -ModsDir $assets
  foreach($cap in @(0,3)){$settingsInput=$preparedSettings[$cap];$archives+=Publish-MIRModDirectoryArchive -Source $settingsInput.source -Name 'mir-validation-settings-overrides' -Version $settingsInput.version -ModsDir $assets}
  Write-MIRNativeProbeResult -Context $resources -Record @{status='prepared-owned-inputs-only';source=$sourceCommit;candidate=Get-MIR42Artifact $candidateZip;archives=@($archives|ForEach-Object{Get-MIR42Artifact $_});native_factorio=$false}
  Write-Output "Prepared inputs: $run";return
}
Assert-MIR441CleanTrackedSource -RepoRoot $repo
$engineResolution=Get-MIR42GovernedEngineResolution
$engine=[string]$engineResolution.engine.path
Assert-Exact 'Factorio executable SHA-256' (Get-MIR42Sha $engine) ([string]$engineResolution.engine.sha256)
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent)-Parent)-Parent
$library=(Resolve-Path -LiteralPath $LibraryDirectory).Path;Assert-MIRLibraryPath $library

function New-MIR42Stage([string]$Name,[int]$Cap,[bool]$UseBlocker,[bool]$UsePolicyBlocker){
  $stageRoot=Join-Path $run $Name
  $mods=$library
  $userdata=Join-Path $stageRoot 'userdata'
  New-Item -ItemType Directory -Force -Path $userdata,(Join-Path $userdata 'saves')|Out-Null
  $candidateName=[IO.Path]::GetFileName($candidateZip);$installed=Join-Path $mods $candidateName
  Assert-MIRLibraryPath $installed
  Assert-Exact 'installed candidate hash' (Get-MIR42Sha $installed) ([string]$candidateInput.receipt.archive_sha256)
  $settings=$preparedSettings[$Cap];$settingsArchive=Join-Path $mods $settings.file
  Assert-MIRLibraryFixtureArchive -Archive $settingsArchive -SourceDirectory $settings.source
  $fixtureArchive=Join-Path $mods ($fixtureName+'_0.1.0.zip')
  Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $fixture
  $hashes=@{$candidateName=[string]$candidateInput.receipt.archive_sha256;$settings.file=(Get-MIR42Sha $settingsArchive);([IO.Path]::GetFileName($fixtureArchive))=(Get-MIR42Sha $fixtureArchive)}
  $blockerArchive=$null
  if($UseBlocker){
    $blockerArchive=Join-Path $mods ($blockerName+'_0.1.0.zip')
    Assert-MIRLibraryFixtureArchive -Archive $blockerArchive -SourceDirectory $blockerFixture
    $hashes[[IO.Path]::GetFileName($blockerArchive)]=Get-MIR42Sha $blockerArchive
  }
  $policyBlockerArchive=$null
  if($UsePolicyBlocker){
    $policyBlockerArchive=Join-Path $mods ($policyBlockerName+'_0.1.0.zip')
    Assert-MIRLibraryFixtureArchive -Archive $policyBlockerArchive -SourceDirectory $policyBlockerFixture
    $hashes[[IO.Path]::GetFileName($policyBlockerArchive)]=Get-MIR42Sha $policyBlockerArchive
  }
  $modList=[ordered]@{mods=@(@('base','elevated-rails','quality','recycler','space-age')|ForEach-Object{[ordered]@{name=$_;version=[string]$engineResolution.engine.version;enabled=$true}})}
  $modList.mods+=@(@{name='more-infinite-research';version='4.2.21001';enabled=$true},@{name=$fixtureName;version='0.1.0';enabled=$true},@{name='mir-validation-settings-overrides';version=$settings.version;enabled=$true})
  if($UseBlocker){$modList.mods+=,@{name=$blockerName;version='0.1.0';enabled=$true}}
  if($UsePolicyBlocker){$modList.mods+=,@{name=$policyBlockerName;version='0.1.0';enabled=$true}}
  $modListPath=Join-Path $stageRoot 'selection.json'
  [IO.File]::WriteAllText($modListPath,(($modList|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  $configPath=Join-Path $stageRoot 'config.ini'
  [IO.File]::WriteAllText($configPath,"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($userdata.Replace('\','/'))`n[other]`nenable-new-mods=false`ncheck-updates=false`ndisable-blueprint-storage=true`n",[Text.UTF8Encoding]::new($false))
  $serverSettings=Join-Path $stageRoot 'server-settings.json'
  $server=[ordered]@{name='MIR42 cap ownership/multiforce';description='';tags=@();max_players=1;visibility=[ordered]@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false}
  [IO.File]::WriteAllText($serverSettings,(($server|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  return [pscustomobject]@{
    name=$Name
    cap=$Cap
    blocker=$UseBlocker
    policy_blocker=$UsePolicyBlocker
    root=$stageRoot
    mods=$mods
    userdata=$userdata
    config=$configPath
    server_settings=$serverSettings
    fixture_archive=$fixtureArchive
    blocker_archive=$blockerArchive
    policy_blocker_archive=$policyBlockerArchive
    settings_archive=$settingsArchive
    mod_list=$modListPath
    archive_hashes=$hashes
    activation=$null
    terminals=[Collections.Generic.List[object]]::new()
  }
}

function Start-MIR42CapStage($Stage){
  $Stage.activation=Start-MIRLibraryActivation -LibraryDirectory $Stage.mods -EngineDataDirectory (Join-Path $engineRoot 'data') -ProfilePath $Stage.mod_list -ArchiveHashes $Stage.archive_hashes -SettingsMode Defaults
  $script:activeStage=$Stage
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $Stage.activation
}
function Complete-MIR42CapStage($Stage,[string]$Log){
  $null=Assert-MIRLibraryLoadedSelection -Activation $Stage.activation -LogPath $Log -LatestInvocation
  $Stage.terminals.Add((Complete-MIRLibraryActivation $Stage.activation))
  $script:activeStage=$null
}

function Invoke-MIR42Engine($Stage,[string]$Name,[string[]]$Arguments){
  Start-MIR42CapStage $Stage
  $factorioLog=Join-Path $Stage.userdata 'factorio-current.log'
  if(Test-Path -LiteralPath $factorioLog){Remove-Item -LiteralPath $factorioLog -Force}
  $nativeArguments=@('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods)+$Arguments
  Assert-MIRLibraryLaunch -Activation $Stage.activation -FactorioBin $engine -Arguments $nativeArguments
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $nativeArguments -TimeoutSeconds 120
  Assert-MIR42 (Test-Path -LiteralPath $factorioLog -PathType Leaf) "Factorio log is absent after $Name."
  $copy=Join-Path $Stage.root "factorio-$Name.log"
  Copy-Item -LiteralPath $factorioLog -Destination $copy
  Complete-MIR42CapStage $Stage $copy
  return $copy
}

function Invoke-MIR42ServerSave($Stage,[string]$Name,[string]$InputSave,[string]$ExpectedSave,[string]$ExpectedStage){
  Start-MIR42CapStage $Stage
  $factorioLog=Join-Path $Stage.userdata 'factorio-current.log'
  if(Test-Path -LiteralPath $factorioLog){Remove-Item -LiteralPath $factorioLog -Force}
  $needle="[mir42-cap-ownership-multiforce] STATE JSON {`"stage`":`"$ExpectedStage`""
  $completion={
    if(-not(Test-Path -LiteralPath $factorioLog -PathType Leaf)-or -not(Test-Path -LiteralPath $ExpectedSave -PathType Leaf)){return $false}
    try {$text=Get-Content -LiteralPath $factorioLog -Raw -ErrorAction Stop} catch [IO.IOException] {return $false}
    return ($null -ne $text -and $text.Contains($needle)-and$text.Contains('Saving finished'))
  }.GetNewClosure()
  $nativeArguments=@('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods,'--server-settings',$Stage.server_settings,'--start-server',$InputSave)
  Assert-MIRLibraryLaunch -Activation $Stage.activation -FactorioBin $engine -Arguments $nativeArguments
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $nativeArguments -TimeoutSeconds 60 -CompletionPredicate $completion
  Assert-MIR42 ([bool]$actor.result.completion_predicate_observed) "Factorio server did not create $Name successor."
  Assert-MIR42 (Test-Path -LiteralPath $factorioLog -PathType Leaf) "Factorio log is absent after $Name."
  $copy=Join-Path $Stage.root "factorio-$Name.log"
  Copy-Item -LiteralPath $factorioLog -Destination $copy
  Complete-MIR42CapStage $Stage $copy
  return $copy
}

$seedStage=New-MIR42Stage -Name 'seed' -Cap 0 -UseBlocker:$false -UsePolicyBlocker:$false
$cappedStage=New-MIR42Stage -Name 'capped' -Cap 3 -UseBlocker:$false -UsePolicyBlocker:$false
$policyBlockedStage=New-MIR42Stage -Name 'policy-blocked' -Cap 3 -UseBlocker:$false -UsePolicyBlocker:$true
$blockedStage=New-MIR42Stage -Name 'blocked' -Cap 3 -UseBlocker:$true -UsePolicyBlocker:$false
$removalStage=New-MIR42Stage -Name 'removal' -Cap 0 -UseBlocker:$false -UsePolicyBlocker:$false

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

$policyBlockedSave=Join-Path $policyBlockedStage.userdata 'saves/mir42-cap-ownership-multiforce-policy-blocked.zip'
$policyBlockedLog=Invoke-MIR42ServerSave $policyBlockedStage 'policy-blocked' $cappedSave $policyBlockedSave 'policy-blocked'
$policyBlockedText=Get-Content -Raw -LiteralPath $policyBlockedLog
$policyBlockedData=Read-MIR42Data $policyBlockedText
Assert-MIR42Data $policyBlockedData '3'
$policyBlockedState=Read-MIR42State $policyBlockedText 'policy-blocked'
$policyBlockerRecords=[regex]::Matches($policyBlockedText,'\[late-mir42-policy-binding-blocker\] DATA technology=recipe-prod-research_copper-1 prototype=infinite cap-pre=3 cap-post=4 artifact-identity=stale')
Assert-MIR42 ($policyBlockerRecords.Count -eq 1) "expected exactly one late policy blocker data receipt; observed $($policyBlockerRecords.Count)."
$policyConflicts=[regex]::Matches($policyBlockedText,'\[more-infinite-research\] Maximum-level conflict technology=recipe-prod-research_copper-1 selected=4 final-observed=4294967295 binding-operation=emit source=generated-stream reason=maximum_level_policy_fingerprint_invalid setting=ips-max-level-research_copper; runtime queue normalization was refused[.]')
Assert-MIR42 ($policyConflicts.Count -eq 1) "expected exactly one Copper invalid-policy refusal; observed $($policyConflicts.Count)."

$blockedSave=Join-Path $blockedStage.userdata 'saves/mir42-cap-ownership-multiforce-blocked.zip'
$blockedLog=Invoke-MIR42ServerSave $blockedStage 'blocked' $policyBlockedSave $blockedSave 'blocked'
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
  [pscustomobject]@{name='event-probe';level=4;enabled=$true;visible_when_disabled=$false},
  [pscustomobject]@{name='reset-probe';level=4;enabled=$true;visible_when_disabled=$false}
)
$cappedForces=@(
  [pscustomobject]@{name='owned';level=4;enabled=$false;visible_when_disabled=$true},
  [pscustomobject]@{name='foreign-disabled';level=4;enabled=$false;visible_when_disabled=$true},
  [pscustomobject]@{name='below-cap';level=2;enabled=$true;visible_when_disabled=$false},
  [pscustomobject]@{name='event-probe';level=4;enabled=$false;visible_when_disabled=$true},
  [pscustomobject]@{name='reset-probe';level=4;enabled=$false;visible_when_disabled=$true}
)
$eventForces=@(
  $cappedForces
  [pscustomobject]@{name='new-force';level=4;enabled=$true;visible_when_disabled=$false}
  [pscustomobject]@{name='merge-destination';level=4;enabled=$false;visible_when_disabled=$true}
  [pscustomobject]@{name='merge-reuse';level=4;enabled=$true;visible_when_disabled=$false}
)
$removedForces=@(
  [pscustomobject]@{name='owned';level=4;enabled=$true;visible_when_disabled=$false},
  [pscustomobject]@{name='foreign-disabled';level=4;enabled=$false;visible_when_disabled=$false},
  [pscustomobject]@{name='below-cap';level=2;enabled=$true;visible_when_disabled=$false},
  [pscustomobject]@{name='event-probe';level=4;enabled=$true;visible_when_disabled=$false},
  [pscustomobject]@{name='reset-probe';level=4;enabled=$true;visible_when_disabled=$true},
  [pscustomobject]@{name='new-force';level=4;enabled=$true;visible_when_disabled=$true},
  [pscustomobject]@{name='merge-destination';level=4;enabled=$true;visible_when_disabled=$false},
  [pscustomobject]@{name='merge-reuse';level=4;enabled=$true;visible_when_disabled=$true}
)
Assert-MIR42State $seedState 'seed' 0 0 $false $false 0 0 @() $seedForces
Assert-MIR42State $cappedState 'capped' 3 3 $false $false 1 0 @() $cappedForces
Assert-MIR42State $eventProbeState 'event-probe' 3 3 $false $false 1 1 @('mir42-cap-native-queue-probe') $eventForces
Assert-MIR42State $policyBlockedState 'policy-blocked' 3 0 $false $true 2 1 @('mir42-cap-native-queue-probe') $eventForces
Assert-MIR42State $blockedState 'blocked' 3 0 $true $false 3 1 @('mir42-cap-native-queue-probe') $eventForces
Assert-MIR42State $removalState 'removal' 0 0 $false $false 4 1 @('mir42-cap-native-queue-probe') $removedForces
Assert-MIR42State $terminalState 'terminal' 0 0 $false $false 4 1 @('mir42-cap-native-queue-probe') $removedForces
Assert-MIR42StableForceIndices $seedState $cappedState 'seed-to-capped'
Assert-MIR42StableForceIndices $seedState $eventProbeState 'seed-to-event-probe'
Assert-MIR42StableForceIndices $eventProbeState $policyBlockedState 'event-probe-to-policy-blocked'
Assert-MIR42StableForceIndices $eventProbeState $blockedState 'event-probe-to-blocked'
Assert-MIR42StableForceIndices $eventProbeState $removalState 'event-probe-to-removal'
Assert-MIR42StableForceIndices $removalState $terminalState 'removal-to-terminal'
Assert-Exact 'terminal semantic state after serialized reload' (Get-MIR42SemanticStateJson $terminalState) (Get-MIR42SemanticStateJson $removalState)

$lineage=@(
  [ordered]@{stage='seed';save=Get-MIR42Artifact $seedSave;predecessor_sha256=$null},
  [ordered]@{stage='capped';save=Get-MIR42Artifact $cappedSave;predecessor_sha256=Get-MIR42Sha $seedSave},
  [ordered]@{stage='policy-blocked';save=Get-MIR42Artifact $policyBlockedSave;predecessor_sha256=Get-MIR42Sha $cappedSave},
  [ordered]@{stage='blocked';save=Get-MIR42Artifact $blockedSave;predecessor_sha256=Get-MIR42Sha $policyBlockedSave},
  [ordered]@{stage='removal';save=Get-MIR42Artifact $removalSave;predecessor_sha256=Get-MIR42Sha $blockedSave}
)
for($index=1;$index -lt $lineage.Count;$index++){
  Assert-Exact "save lineage $($lineage[$index].stage)" $lineage[$index].predecessor_sha256 $lineage[$index-1].save.raw_sha256
}

function Get-MIR42StageManifest($Stage){
  $entries=[ordered]@{
    candidate=Get-MIR42Artifact (Join-Path $Stage.mods (Split-Path -Leaf $candidateZip)) -AllowExternal
    fixture=Get-MIR42Artifact $Stage.fixture_archive -AllowExternal
    settings=Get-MIR42Artifact $Stage.settings_archive -AllowExternal
    mod_list=Get-MIR42Artifact $Stage.mod_list
    config=Get-MIR42Artifact $Stage.config
  }
  if($Stage.blocker){$entries.blocker=Get-MIR42Artifact $Stage.blocker_archive -AllowExternal}
  if($Stage.policy_blocker){$entries.policy_blocker=Get-MIR42Artifact $Stage.policy_blocker_archive -AllowExternal}
  return [ordered]@{name=$Stage.name;cap=$Stage.cap;blocker=$Stage.blocker;policy_blocker=$Stage.policy_blocker;artifacts=$entries}
}

$result=[ordered]@{
  schema=1
  kind='MIR42F210CapOwnershipMultiforceQualificationV1'
  status='passed-current-f210-candidate-cap-ownership-multiforce-only'
  scope='Verified supplied 4.2.21001 F210 candidate: strict V3 policy admission, copper absolute cap ownership, named-force isolation, late policy forgery refusal, force-reset stale-ownership discard, cap removal, and terminal serialized reload; isolated/cooperative package-excluded fixture evidence.'
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
  source=[ordered]@{
    commit=$sourceCommit
    tree=$sourceTree
    package_source_sha256=[string]$candidateInput.receipt.package_source_sha256
    package_source_manifest_sha256=Get-MIR42Sha (Join-Path $repo 'source/package-source.json')
    candidate_materialization_closure=@($candidateMaterializationClosure)
    candidate_materialization_closure_clean=$true
  }
  candidate=Get-MIR42Artifact $candidateZip
  candidate_materialization=Get-MIR42Artifact $SourceMaterializationPath
  candidate_created_by_harness=$false
  candidate_package_excludes_fixture_test_docs_governance_build_dist=$true
  fixture_hashes=[ordered]@{
    main_info=Get-MIR42Sha (Join-Path $fixture 'info.json')
    main_data_final_fixes=Get-MIR42Sha (Join-Path $fixture 'data-final-fixes.lua')
    main_control=Get-MIR42Sha (Join-Path $fixture 'control.lua')
    blocker_info=Get-MIR42Sha (Join-Path $blockerFixture 'info.json')
    blocker_data_final_fixes=Get-MIR42Sha (Join-Path $blockerFixture 'data-final-fixes.lua')
    policy_blocker_info=Get-MIR42Sha (Join-Path $policyBlockerFixture 'info.json')
    policy_blocker_data_final_fixes=Get-MIR42Sha (Join-Path $policyBlockerFixture 'data-final-fixes.lua')
  }
  harness_sha256=Get-MIR42Sha $PSCommandPath
  stages=@(
    (Get-MIR42StageManifest $seedStage)
    (Get-MIR42StageManifest $cappedStage)
    (Get-MIR42StageManifest $policyBlockedStage)
    (Get-MIR42StageManifest $blockedStage)
    (Get-MIR42StageManifest $removalStage)
  )
  v3_observations=[ordered]@{seed=$seedData;capped=$cappedData;policy_blocked=$policyBlockedData;blocked=$blockedData;removal=$removalData;terminal=$terminalData}
  named_force_state_receipts=[ordered]@{seed=$seedState;capped=$cappedState;event_probe=$eventProbeState;policy_blocked=$policyBlockedState;blocked=$blockedState;removal=$removalState;terminal=$terminalState}
  policy_conflict=[ordered]@{technology=$technologyName;configured_cap=3;forged_policy_cap=4;runtime_reported_selected_cap=4;runtime_prototype_max_level=4294967295;reason='maximum_level_policy_fingerprint_invalid';count=$policyConflicts.Count}
  late_conflict=[ordered]@{technology=$technologyName;selected_cap=3;late_observed_prototype_max_level=5;reason='maximum_level_late_prototype_mutation';count=$lateConflicts.Count}
  save_lineage=$lineage
  logs=[ordered]@{
    seed=Get-MIR42Artifact $seedLog
    capped=Get-MIR42Artifact $cappedLog
    policy_blocked=Get-MIR42Artifact $policyBlockedLog
    blocked=Get-MIR42Artifact $blockedLog
    removal=Get-MIR42Artifact $removalLog
    terminal=Get-MIR42Artifact $terminalLog
  }
  explicit_non_claims=$nonClaims
}
Assert-MIR441CleanTrackedSource -RepoRoot $repo
Assert-Exact 'source after execution' ((&git -C $repo rev-parse HEAD).Trim()) $sourceCommit
Assert-Exact 'engine after execution' (Get-MIR42Sha $engine) ([string]$engineResolution.engine.sha256)
$result['library_activations']=@($seedStage,$cappedStage,$policyBlockedStage,$blockedStage,$removalStage|ForEach-Object {$_.terminals.ToArray()})
$result['resource_context']=[ordered]@{expected_peak_memory_bytes=$resources.peak_memory_bytes;max_new_output_bytes=$resources.max_new_output_bytes;shared_alias_bytes=$resources.shared_alias_bytes;memory_enforcement='sampled-watchdog-not-hard-cap'}
$result['process_inventory']=@($resources.runs)
Write-MIRNativeProbeResult -Context $resources -Record $result
$result|ConvertTo-Json -Depth 40
Write-Output "Evidence: $run"
