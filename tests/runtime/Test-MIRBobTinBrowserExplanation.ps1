# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$CandidateZip='',
  [string]$BobModsDir='C:\Projects\Factorio\testmods\2.1',
  [string]$OutputRoot='build/p/tin-browser-explanation',
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120,
  [switch]$Graphics
)
$ErrorActionPreference='Stop'
# Native execution is retired; the preserved oracle is not current acceptance.
throw '[mir-native-obsolete-runner] This native runner still materializes a mod directory. Use a migrated direct-library consumer; retain this scenario and its historical evidence until conversion. No engine or staging was started.'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tests/support/MIRMaterialAuditInputs.ps1')
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
# Admit the complete row before resolving an engine, generating a package or
# allocating any stage. This retained exact-engine fixture is not a current
# Steam-engine qualification merely because its inputs are shared.
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
Assert-MIR441CleanTrackedSource -RepoRoot $repo
function Resolve-TinBrowserEnginePath([string]$Requested) {
  if(-not [IO.Path]::GetFullPath($Requested).Equals('C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',[StringComparison]::OrdinalIgnoreCase)) { throw '[mir-tin-browser-engine-location] Select the authorized current 2.1 engine; do not retarget Steam for this historical lock.' }
  return $Requested
}
$engine=(Resolve-Path -LiteralPath (Resolve-TinBrowserEnginePath -Requested $FactorioBin)).Path
$bobMods=(Resolve-Path -LiteralPath $BobModsDir).Path
function Test-TinBrowserCandidate([string]$Candidate,[string]$Line,$Identity,[string]$Repository) {
$candidate=$Candidate;$Target=$Line;$expectedIdentity=$Identity;$repo=$Repository
$archive=[IO.Compression.ZipFile]::OpenRead($candidate)
try {
 $infoEntries=@($archive.Entries | Where-Object FullName -Like '*/info.json')
 if($infoEntries.Count -ne 1) { throw 'Browser candidate requires one mod identity.' }
 if($infoEntries[0].Length -gt 64KB){throw '[mir-browser-candidate-info-budget]'}
 $infoReader=[IO.StreamReader]::new($infoEntries[0].Open())
 try { $info=$infoReader.ReadToEnd() | ConvertFrom-Json } finally { $infoReader.Dispose() }
 if([string]$info.name -cne 'more-infinite-research' -or [string]$info.factorio_version -cne $Target) {
  throw "Browser candidate target mismatch: requested $Target, archive declares $($info.factorio_version)."
 }
 $packageRoot='more-infinite-research_'+$expectedIdentity.distribution_version
 if([string]$info.version -cne $expectedIdentity.distribution_version -or
    [IO.Path]::GetFileName($candidate) -cne $expectedIdentity.package_name -or
    $infoEntries[0].FullName -cne ($packageRoot+'/info.json') -or
    @($archive.Entries | Where-Object {
      -not $_.FullName.StartsWith($packageRoot+'/',[StringComparison]::Ordinal) -or
      $_.FullName -cmatch '[\\\x00]' -or
      @($_.FullName.TrimEnd('/').Split('/') | Where-Object {$_ -in @('','.','..')}).Count -gt 0
    }).Count -ne 0) {
  throw '[mir-browser-candidate-identity] Candidate filename, root and metadata must encode source 4.2.1 for the selected target.'
 }
 foreach($name in @('research_browser.lua','research_browser_core.lua','research_browser_factorio_catalogue.lua','research_browser_mir_provider.lua','research_browser_actions.lua')) {
  $entry=@($archive.Entries | Where-Object FullName -CEQ "$packageRoot/prototypes/mir/runtime/$name")
  if($entry.Count -ne 1) { throw "Candidate must contain exactly one $name." }
  if($entry[0].Length -ne (Get-Item -LiteralPath (Join-Path $repo "source/prototypes/mir/runtime/$name")).Length){throw "Candidate $name differs from the controlled source under test."}
  $stream=$entry[0].Open()
  try { $moduleHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) } finally { $stream.Dispose() }
  if($moduleHash -cne (Get-FileHash (Join-Path $repo "source/prototypes/mir/runtime/$name")).Hash) { throw "Candidate $name differs from the controlled source under test." }
 }
 if(@($archive.Entries | Where-Object FullName -match '/(?:fixtures|tests|docs|[.]mir|build|dist)/').Count){throw '[mir-tin-browser-candidate-exclusions] Player candidate includes a forbidden repository path.'}
 return [pscustomobject]@{info=$info;sha256=(Get-FileHash -LiteralPath $candidate).Hash}
} finally { $archive.Dispose() }
}
$run=$resources.root
$lease=$null
try {
New-Item -ItemType Directory -Path $run | Out-Null
$expectedEngine='710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8'
if((Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash -cne $expectedEngine) { throw "Browser evidence requires F210 engine SHA-256 $expectedEngine." }
$versionActor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments @('--version') -TimeoutSeconds 10
$engineVersion=Get-Content -LiteralPath $versionActor.stdout -Raw
if($engineVersion -notmatch 'Version: 2[.]1[.]17(?:\s|$)') { throw 'Browser evidence requires Factorio 2.1.17.' }
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim();$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
if($sourceCommit -notmatch '^[0-9a-f]{40}$' -or $sourceTree -notmatch '^[0-9a-f]{40}$') { throw 'Browser evidence could not bind source commit/tree.' }
$fixture=Join-Path $repo 'fixtures/assert-bob-tin-browser-explanation'
$dossierPath=Join-Path $fixture 'browser-explanation-dossier.json'
try{$dossier=Get-Content -Raw -LiteralPath $dossierPath|ConvertFrom-Json -ErrorAction Stop}catch{throw "Browser explanation dossier is invalid JSON: $($_.Exception.Message)"}
function Assert-Eq([string]$Name,$Actual,$Expected){if($Actual -cne $Expected){throw "$Name differs: expected '$Expected', actual '$Actual'."}}
function Assert-Props([string]$Name,$Value,[string[]]$Expected){if($null -eq $Value){throw "$Name is absent."};$actual=@($Value.PSObject.Properties.Name|Sort-Object);$wanted=@($Expected|Sort-Object);if($actual.Count -ne $wanted.Count -or (@(Compare-Object -CaseSensitive $actual $wanted)).Count){throw "$Name properties differ."}}
function Assert-Array([string]$Name,$Actual,[string[]]$Expected){$actual=@($Actual|ForEach-Object{[string]$_});if($actual.Count -ne $Expected.Count -or (@(Compare-Object -CaseSensitive $actual $Expected)).Count){throw "$Name differs."}}
Assert-Props root $dossier @('schema','scope','target','public_row','final_science','settings','runtime_levels','locked_route_universe','explicit_non_claims')
Assert-Eq schema $dossier.schema 1;Assert-Eq scope $dossier.scope 'F210 exact locked Bob-only Tin browser explanation; package-excluded evidence'
Assert-Props target $dossier.target @('factorio_line','factorio_version','engine_sha256','boblibrary_version','boblibrary_sha256','bobores_version','bobores_sha256','bobplates_version','bobplates_sha256')
Assert-Eq target.line $dossier.target.factorio_line '2.1';Assert-Eq target.version $dossier.target.factorio_version '2.1.17';Assert-Eq target.engine $dossier.target.engine_sha256 $expectedEngine
$expectedArchives=[ordered]@{boblibrary='49EAE2D4D8E58EBD28BAFDB7E71D5307CBCE2077E0642440ED7EC527D466FFC4';bobores='7F8E33E35F59BB3F2CD72E3AB2FED30D1C2AE9C117E3731324AC307D9965082B';bobplates='503D7BF6E88DA1F99463AC00CEC959C2003B2701D80DC4A564CF2EC3920AC8AF'}
foreach($name in $expectedArchives.Keys){Assert-Eq "target.$name" $dossier.target."$($name)_sha256" $expectedArchives[$name]}
Assert-Props public_row $dossier.public_row @('technology','stream','action','reason','affected_recipe_ids','disposition');Assert-Eq public.tech $dossier.public_row.technology 'recipe-prod-research_material_tin-1';Assert-Eq public.stream $dossier.public_row.stream 'research_material_tin';Assert-Eq public.action $dossier.public_row.action 'emit';Assert-Eq public.reason $dossier.public_row.reason 'recipe_productivity';Assert-Array public.recipes $dossier.public_row.affected_recipe_ids @('bob-tin-plate')
Assert-Props disposition $dossier.public_row.disposition @('inclusion','route_exclusions');Assert-Eq disposition.inclusion $dossier.public_row.disposition.inclusion 'included';Assert-Props exclusions $dossier.public_row.disposition.route_exclusions @('state','recipe_ids');Assert-Eq exclusions.state $dossier.public_row.disposition.route_exclusions.state 'no-additional-route-exclusions-published-for-current-row';Assert-Array exclusions.ids $dossier.public_row.disposition.route_exclusions.recipe_ids @()
Assert-Props science $dossier.final_science @('rationale','ingredients');Assert-Eq science.rationale $dossier.final_science.rationale 'final-technology-prototype-cross-bound-to-public-generation-plan-row';if(@($dossier.final_science.ingredients).Count -ne 1){throw 'Final science ingredients differ.'};Assert-Eq science.name $dossier.final_science.ingredients[0].name 'automation-science-pack';Assert-Eq science.amount $dossier.final_science.ingredients[0].amount 1
Assert-Props settings.root $dossier.settings @('maximum_level','enabled');foreach($entry in @($dossier.settings.maximum_level,$dossier.settings.enabled)){Assert-Props setting $entry @('name','default','raw_direct','effective','source','changed','changed_from_default','restart_required');Assert-Eq setting.source $entry.source 'mirset1';Assert-Eq setting.restart $entry.restart_required $true}
Assert-Eq max.name $dossier.settings.maximum_level.name 'ips-max-level-research_material_tin';Assert-Eq max.default $dossier.settings.maximum_level.default 2;Assert-Eq max.raw $dossier.settings.maximum_level.raw_direct 2;Assert-Eq max.effective $dossier.settings.maximum_level.effective 3;Assert-Eq max.changed $dossier.settings.maximum_level.changed $true;Assert-Eq max.changed_from_default $dossier.settings.maximum_level.changed_from_default $true
Assert-Eq enabled.name $dossier.settings.enabled.name 'ips-enable-research_material_tin';Assert-Eq enabled.default $dossier.settings.enabled.default $true;Assert-Eq enabled.raw $dossier.settings.enabled.raw_direct $true;Assert-Eq enabled.effective $dossier.settings.enabled.effective $true;Assert-Eq enabled.changed $dossier.settings.enabled.changed $false;Assert-Eq enabled.changed_from_default $dossier.settings.enabled.changed_from_default $false
Assert-Props levels $dossier.runtime_levels @('level_three_current_has_effective_benefit','post_cap_level_four_has_effective_benefit','cap_saturated_recipe_has_effective_benefit','recipe_benefit_rule');Assert-Eq levels.three $dossier.runtime_levels.level_three_current_has_effective_benefit $true;Assert-Eq levels.four $dossier.runtime_levels.post_cap_level_four_has_effective_benefit $false;Assert-Eq levels.saturated $dossier.runtime_levels.cap_saturated_recipe_has_effective_benefit $false
Assert-Array non_claims $dossier.explicit_non_claims @('F200','Angel-or-combined-Bob-Angel-route-coverage','two-genuine-client-or-multiplayer-isolation','vanilla-technology-tree-button-injection','startup-hot-mutation','full-A16-BA-07-or-PROG-01','release-readiness')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1');. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1');. (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')
$mods=Join-Path $run 'mods';New-Item -ItemType Directory -Force -Path $mods,(Join-Path $run 'userdata')|Out-Null
if([string]::IsNullOrWhiteSpace($CandidateZip)){$candidate=New-MIRNativeProbeTargetPackage -Context $resources -RepoRoot $repo -Target f210 -CandidatePrefix BROWSER;$candidateZip=[string]$candidate.archive_path}else{$candidateZip=(Resolve-Path -LiteralPath $CandidateZip).Path}
$identity=New-MIR4DistributionIdentityProjection -DistributionTargetCode '210' -SourceMinor 2 -SourcePatch 1
$validatedCandidate=Test-TinBrowserCandidate -Candidate $candidateZip -Line '2.1' -Identity $identity -Repository $repo

$archiveNames=[ordered]@{boblibrary='boblibrary_3.0.0.zip';bobores='bobores_3.0.0.zip';bobplates='bobplates_3.0.1.zip'};$archiveHashes=[ordered]@{}
$lockedFiles=[ordered]@{}
foreach($item in $archiveNames.GetEnumerator()){$lockedFiles[$item.Value]=$expectedArchives[$item.Key]}
$lease=New-MIRMaterialAuditInputLease -RunRoot $run -ModsDirectory $mods -CandidateArchive $candidateZip -DependencyDirectory $bobMods -ExpectedArchives $lockedFiles
Add-MIRNativeProbeImmutableLease -Context $resources -Lease $lease
foreach($item in $archiveNames.GetEnumerator()){$archiveHashes[$item.Key]=Get-MIRImmutableInputSha256 (Join-Path $bobMods $item.Value)}
foreach($name in $expectedArchives.Keys){Assert-Eq "archive.$name" $archiveHashes[$name] $expectedArchives[$name]}
Publish-MIRModDirectoryArchive -Source $fixture -Name 'mir-fixture-assert-bob-tin-browser-explanation' -Version '0.1.0' -ModsDir $mods|Out-Null
Initialize-MIRSettingsOverrideMod -ModsDir $mods -FactorioVersion '2.1';Set-CopiedStartupSettingDefaults -ModsDir $mods -Overrides @{'ips-enable-research_material_tin'=$true;'ips-max-level-research_material_tin'=2};Set-CopiedMIRSettingsProfileDefault -ModsDir $mods -Settings @{'ips-enable-research_material_tin'=$true;'ips-max-level-research_material_tin'=3};Complete-MIRSettingsOverrideMod -ModsDir $mods
@{mods=@(@{name='base';enabled=$true},@{name='space-age';enabled=$false},@{name='elevated-rails';enabled=$false},@{name='quality';enabled=$false},@{name='recycler';enabled=$false},@{name='more-infinite-research';enabled=$true},@{name='boblibrary';enabled=$true},@{name='bobores';enabled=$true},@{name='bobplates';enabled=$true},@{name='mir-fixture-assert-bob-tin-browser-explanation';enabled=$true},@{name='mir-validation-settings-overrides';enabled=$true})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $mods 'mod-list.json') -Encoding utf8
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent;Set-Content -LiteralPath (Join-Path $run 'config.ini') -Value "[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n`n[graphics]`ngraphics-quality=normal`nvideo-memory-usage=medium`ntexture-streaming=true`nmax-texture-size=8192`ntexture-compression-level=low-quality`nfull-screen=false`n" -Encoding utf8
function Invoke-Engine([string]$Stage,[string[]]$Arguments) {
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments (@('--config',(Join-Path $run 'config.ini'),'--mod-directory',$mods)+$Arguments) -TimeoutSeconds 120
  $text=(Get-Content -LiteralPath $actor.stdout -Raw)+(Get-Content -LiteralPath $actor.stderr -Raw)
  Set-Content -LiteralPath (Join-Path $run "engine-$Stage.log") -Value $text -Encoding utf8
  $factorioLog=Join-Path $run 'userdata/factorio-current.log'
  if(-not(Test-Path -LiteralPath $factorioLog)){throw "Factorio log missing at $Stage."}
  $copy=Join-Path $run "factorio-$Stage.log"
  Copy-Item -LiteralPath $factorioLog -Destination $copy
  $null=Get-MIRNativeProbeRemainingOutputBytes -Context $resources
  return $copy
}
$save=Join-Path $run 'bob-tin-browser-explanation.zip';$createLog=Invoke-Engine create @('--create',$save);if(-not(Test-Path -LiteralPath $save)){throw 'Browser fixture did not create a save.'};$dataLine='[mir-bob-tin-browser-explanation] DATA PASS public-row=emit affected=bob-tin-plate science=automation-science-pack:1';if((Get-Content -Raw -LiteralPath $createLog) -notmatch [regex]::Escape($dataLine)){throw "Browser data-stage assertion is absent: $createLog"};$runtimeLog=Invoke-Engine runtime @('--benchmark',$save,'--benchmark-ticks','3','--benchmark-runs','1','--disable-audio')
$resultPath=Join-Path $run 'userdata/script-output/bob-tin-browser-explanation.json';if(-not(Test-Path -LiteralPath $resultPath)){throw "Browser DTO result is absent: $run"};$result=Get-Content -Raw -LiteralPath $resultPath|ConvertFrom-Json;Assert-Eq result.status $result.status 'passed';Assert-Eq result.scope $result.scope 'F210-exact-locked-Bob-only-browser-explanation';Assert-Eq result.execution_surface $result.execution_surface 'headless-dto';Assert-Eq result.native_players ([int]$result.native_players) 0;Assert-Eq result.owner $result.detail.enrichment.owner.technology_id $dossier.public_row.technology;Assert-Eq result.cap $result.detail.enrichment.effective_cap 3;Assert-Eq result.benefit $result.detail.enrichment.next_level_has_effective_benefit $true;Assert-Eq result.recipe $result.detail.enrichment.recipe_benefits[0].recipe_id 'bob-tin-plate';Assert-Eq result.max.changed_from_default $result.detail.enrichment.settings.maximum_level.changed_from_default $dossier.settings.maximum_level.changed_from_default;Assert-Eq result.enabled.changed_from_default $result.detail.enrichment.settings.enabled.changed_from_default $dossier.settings.enabled.changed_from_default;if($result.detail.enrichment.recipe_benefits[0].current_productivity_bonus -ge $result.detail.enrichment.recipe_benefits[0].maximum_productivity){throw 'Browser receipt accepts a saturated Tin recipe as beneficial.'}
$graphicsLog=$null;if($Graphics){$graphicsLog=Invoke-Engine graphics @('--benchmark-graphics',$save,'--benchmark-ticks','120','--disable-audio','--window-size','1024x768');$result=Get-Content -Raw -LiteralPath $resultPath|ConvertFrom-Json;Assert-Eq graphics.status $result.status 'passed';Assert-Eq graphics.scope $result.scope 'F210-exact-locked-Bob-only-browser-explanation';Assert-Eq graphics.execution_surface $result.execution_surface 'native-player-gui';Assert-Eq graphics.native_players ([int]$result.native_players) 1;Assert-Eq ui.cost-key $result.ui_facts.research_cost[0] 'mir-browser.research-cost';Assert-Eq ui.increment-key $result.ui_facts.productivity_increment[0] 'mir-browser.productivity-increment';Assert-Eq ui.cap-key $result.ui_facts.productivity_current_cap[0] 'mir-browser.productivity-current-cap';Assert-Eq ui.profile-key $result.ui_facts.profile_import.key 'mir-browser.profile-active';Assert-Eq ui.profile-recognized ([int]$result.ui_facts.profile_import.recognized) 2;Assert-Eq ui.profile-invalid ([int]$result.ui_facts.profile_import.invalid) 0}
$receipt=[ordered]@{schema=1;status='passed';scope='F210 exact locked Bob-only Tin browser explanation';target='F210';execution_surface=[string]$result.execution_surface;graphics_requested=[bool]$Graphics;native_players=[int]$result.native_players;engine_version=$engineVersion.Trim();engine_sha256=$expectedEngine;source=[ordered]@{commit=$sourceCommit;tree=$sourceTree;package_source_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'source/package-source.json')).Hash};package_sha256=(Get-FileHash -LiteralPath $candidateZip).Hash;bob_archive_sha256=$archiveHashes;dossier_sha256=(Get-FileHash -LiteralPath $dossierPath).Hash;fixture_hashes=[ordered]@{info=(Get-FileHash -LiteralPath (Join-Path $fixture 'info.json')).Hash;data_final_fixes=(Get-FileHash -LiteralPath (Join-Path $fixture 'data-final-fixes.lua')).Hash;control=(Get-FileHash -LiteralPath (Join-Path $fixture 'control.lua')).Hash};browser_module_hashes=[ordered]@{core=(Get-FileHash -LiteralPath (Join-Path $repo 'source/prototypes/mir/runtime/research_browser_core.lua')).Hash;provider=(Get-FileHash -LiteralPath (Join-Path $repo 'source/prototypes/mir/runtime/research_browser_mir_provider.lua')).Hash;host=(Get-FileHash -LiteralPath (Join-Path $repo 'source/prototypes/mir/runtime/research_browser.lua')).Hash};harness_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;result_sha256=(Get-FileHash -LiteralPath $resultPath).Hash;save_sha256=(Get-FileHash -LiteralPath $save).Hash;logs=[ordered]@{create=(Get-FileHash -LiteralPath $createLog).Hash;runtime=(Get-FileHash -LiteralPath $runtimeLog).Hash;graphics=if($graphicsLog){(Get-FileHash -LiteralPath $graphicsLog).Hash}else{$null}};detail=$result.detail;ui_facts=$result.ui_facts;non_claims=$dossier.explicit_non_claims}
$receipt['input_lease']=Complete-MIRImmutableInputLease -Lease $lease -Outcome passed
$lease=$null
$receipt['resource_runs']=$resources.runs.ToArray()
Write-MIRNativeProbeResult -Context $resources -Record $receipt
$receipt|ConvertTo-Json -Depth 30
Write-Output "Evidence: $run"
} finally {
  if($null -ne $lease -and -not $lease.closed){$null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed}
}
