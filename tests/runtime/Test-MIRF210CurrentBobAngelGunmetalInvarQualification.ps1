# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$ExactStageRoot='C:\Projects\Factorio\more-infinite-research\build\tests\wed-material-f210\current-ba-20260930',
  [string]$OutputRoot='build/tests/ba-gi',
  [switch]$PrepareOnly,
  [string]$RecoverRun=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Assert-GI([bool]$Condition,[string]$Message) {
  if (-not $Condition) { throw "[mir-f210-current-ba-gunmetal-invar] $Message" }
}
function Get-GISha([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$stage=(Resolve-Path -LiteralPath $ExactStageRoot).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$outputPrefix=$output.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
$buildPrefix=[IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
Assert-GI ($output.StartsWith($buildPrefix,[StringComparison]::OrdinalIgnoreCase)) 'output root must be inside build'
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/ImmutableInputStaging.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')

function Get-GIRelative([string]$Path) {
  $full=[IO.Path]::GetFullPath($Path)
  $prefix=$repo.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  Assert-GI ($full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) "artifact is outside repository: $full"
  $full.Substring($prefix.Length).Replace('\','/')
}
function Get-GIArtifact([string]$Path) {
  $item=Get-Item -LiteralPath $Path -ErrorAction Stop
  [pscustomobject][ordered]@{path=Get-GIRelative $item.FullName;bytes=[int64]$item.Length;raw_sha256=Get-GISha $item.FullName}
}
function New-GIInput([string]$Path,[string]$Role,[object]$Identity,[object]$Provenance) {
  $resolved=(Resolve-Path -LiteralPath $Path).Path
  [ordered]@{
    source_path=$resolved
    file_name=(Split-Path -Leaf $resolved)
    expected_sha256=Get-GISha $resolved
    role=$Role
    identity=$Identity
    provenance=$Provenance
    immutable=$true
  }
}
function Assert-GIPath([string]$Path,[string]$Context) {
  Assert-MIRFactorioPathBudget -Path $Path -Context $Context -MaximumLength 240
}
function Copy-GIPreparedRecord($Record) {
  $copy=[ordered]@{}
  foreach($entry in $Record.GetEnumerator()) { $copy[$entry.Key]=$entry.Value }
  return $copy
}

& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') | Out-Host
$changes=@(& git -C $repo status --porcelain --untracked-files=all)
Assert-GI ($changes.Count -eq 0) "qualification requires a clean worktree: $($changes -join '; ')"

$fixtureRoot=Join-Path $repo 'fixtures/assert-f210-current-bob-angel-gunmetal-invar-qualification'
$fixtureName='mir-fixture-assert-f210-current-bob-angel-gunmetal-invar-qualification'
$fixtureVersion='0.1.0'
foreach($fixtureFile in @('info.json','data-final-fixes.lua','control.lua')) {
  Assert-GI (Test-Path -LiteralPath (Join-Path $fixtureRoot $fixtureFile) -PathType Leaf) "fixture is incomplete: $fixtureFile"
}

$receiptPath=Join-Path $stage 'result.json'
Assert-GI (Test-Path -LiteralPath $receiptPath -PathType Leaf) 'exact F210 Bob/Angel stage receipt is absent'
$stageReceipt=Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -ErrorAction Stop
$expectedEngineSha='E4B1FDBDCC77F4C3449318CE1398493EA7A8E77A19D68BD1AC3A858D0F373B92'
Assert-GI ([string]$stageReceipt.engine_sha256 -ceq $expectedEngineSha) 'exact stage engine identity differs'
$expectedArchives=[ordered]@{
  'boblibrary_3.0.1.zip'='3DD83A195E120BAECC51A43B0B3EB965C0D419A09883F9DAA018B3921C12D51B'
  'bobores_3.0.0.zip'='7F8E33E35F59BB3F2CD72E3AB2FED30D1C2AE9C117E3731324AC307D9965082B'
  'bobplates_3.0.2.zip'='0C9A4910E2DCAA8DCABBE5BFFA67333F214EAB2EFD8C798D5EF84D90B691862D'
  'bobelectronics_3.0.1.zip'='50C2718E38D507CF4D4ACA2DBFE3240997172309413397C9C70083BBAE6927BE'
  'bobtech_3.0.0.zip'='397D979976316C3CE082D2AD29A046CCBAA147E412A0AEB727230BDECF665E5B'
  'angelsrefining_2.1.2.zip'='AF5E79E35E591F68D52F13EDA082950E10AC98A4B7722B3F568D0211E3FEB813'
  'angelsrefininggraphics_2.1.0.zip'='79F373BC628F619EDE3B1875827172390D2C3F5EAB56310F6F1572C4553CB6EF'
  'angelspetrochem_2.1.3.zip'='95FA8F1740A180E5CF5617EFDA7C409A7974E29B236F9F5AB28D789193AC44B4'
  'angelspetrochemgraphics_2.1.0.zip'='DECDC2FCD5BBBDEF70784943C142C30FAA7294B98E814296C5D44D09A9DE4790'
  'angelssmelting_2.1.1.zip'='1DFCDD77D075FD545CFEE74BD8A6443E7E90B133D3832FDD47649C84892243A9'
  'angelssmeltinggraphics_2.1.1.zip'='71E89ABF7CC372FADE39B11FB4FE83A1B5E629226AF123BFE8DDA08C7C228DD3'
}
$receiptArchives=@{}
foreach($row in @($stageReceipt.mods)) { $receiptArchives[[string]$row.archive]=[string]$row.sha256 }
Assert-GI ($receiptArchives.Count -eq $expectedArchives.Count) 'exact stage archive count differs'
$stageMods=Join-Path $stage 'mods'
foreach($entry in $expectedArchives.GetEnumerator()) {
  $archive=Join-Path $stageMods $entry.Key
  Assert-GI ($receiptArchives.ContainsKey($entry.Key) -and $receiptArchives[$entry.Key] -ceq $entry.Value) "stage receipt archive differs: $($entry.Key)"
  Assert-GI (Test-Path -LiteralPath $archive -PathType Leaf) "stage archive absent: $($entry.Key)"
  Assert-GI ((Get-GISha $archive) -ceq $entry.Value) "stage archive bytes differ: $($entry.Key)"
}
$stageSettings=Join-Path $stageMods 'mod-settings.dat'
$expectedSettingsSha='2D258A213E7A4230563651ABD1B7D8268318A2DED5E23F3B20AFB6F1D56ECA6A'
Assert-GI (Test-Path -LiteralPath $stageSettings -PathType Leaf) 'exact stage settings are absent'
Assert-GI ((Get-GISha $stageSettings) -ceq $expectedSettingsSha) 'exact stage settings identity differs'

$candidateResult=New-MIR4TargetPackage -RepoRoot $repo -Target f210 -CandidateId ('F210-BA-GI-'+[guid]::NewGuid().ToString('N').Substring(0,10).ToUpperInvariant()) -SourceVersion '4.2.0' -DistributionVersion '4.2.21000' -OutputRoot 'build/tests/ba-gi/pkg'
$candidate=(Resolve-Path -LiteralPath ([string]$candidateResult.archive_path)).Path
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim()
$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
Assert-GI ($sourceCommit -match '^[0-9a-f]{40}$' -and $sourceTree -match '^[0-9a-f]{40}$') 'source Git identity is invalid'
$prepared=[ordered]@{
  schema=1
  kind='MIRF210CurrentBobAngelGunmetalInvarQualificationV1'
  status='prepared'
  scope='Exact Factorio 2.1.20, Space Age and current 11-archive Bob/Angel closure: Gunmetal and Invar early technology effects, unique ownership, one create and one reload.'
  source=[ordered]@{commit=$sourceCommit;tree=$sourceTree;package_source_sha256=Get-GISha (Join-Path $repo 'source/package-source.json')}
  exact_stage=[ordered]@{path=$stage;engine_sha256=$expectedEngineSha;settings_sha256=$expectedSettingsSha;archives=$expectedArchives}
  candidate=Get-GIArtifact $candidate
  fixture=@('info.json','data-final-fixes.lua','control.lua' | ForEach-Object { Get-GIArtifact (Join-Path $fixtureRoot $_) })
  harness=Get-GIArtifact $PSCommandPath
  non_claims=@('No late-stage or infinite-continuation claim is made.','No other Bob/Angel final route is admitted.','This is an exact configured current tuple, not a general Bob/Angel compatibility claim.')
}
if($PrepareOnly) { $prepared | ConvertTo-Json -Depth 20; return }

if(-not [string]::IsNullOrWhiteSpace($RecoverRun)) {
  $recoveryRun=(Resolve-Path -LiteralPath $RecoverRun).Path
  Assert-GI ($recoveryRun.StartsWith($outputPrefix,[StringComparison]::OrdinalIgnoreCase)) 'recovery run escapes output root'
  $leasePath=Join-Path $recoveryRun 'mir-immutable-input-lease.json'
  $lease=Get-Content -Raw -LiteralPath $leasePath | ConvertFrom-Json -ErrorAction Stop
  Assert-GI ([string]$lease.state -ceq 'completed' -and [string]$lease.outcome -ceq 'passed' -and [bool]$lease.inputs_sha256_match) 'recovery run immutable input lease is not terminal and clean'
  $recoveryCandidate=@($lease.inputs | Where-Object { $_.role -ceq 'candidate' })
  Assert-GI ($recoveryCandidate.Count -eq 1) 'recovery run candidate cardinality differs'
  Assert-GI ((Get-GISha [string]$recoveryCandidate[0].stage_path) -ceq [string]$recoveryCandidate[0].expected_sha256) 'recovery run candidate bytes differ'
  $recoveryCommit=[string]$recoveryCandidate[0].provenance.source_commit
  $recoveryTree=[string]$recoveryCandidate[0].provenance.source_tree
  Assert-GI ($recoveryCommit -match '^[0-9a-f]{40}$' -and $recoveryTree -match '^[0-9a-f]{40}$') 'recovery run source identity is invalid'
  $recoveryPackageBlob=(& git -C $repo rev-parse ($recoveryCommit+':source/package-source.json')).Trim()
  $currentPackageBlob=(& git -C $repo rev-parse 'HEAD:source/package-source.json').Trim()
  Assert-GI ($recoveryPackageBlob -ceq $currentPackageBlob -and (Get-GISha $candidate) -ceq [string]$recoveryCandidate[0].expected_sha256) 'recovery run package source or fresh materialization differs'
  $freshLogPath=Join-Path $recoveryRun 'f210-ba-gunmetal-invar.factorio.log'
  $reloadLogPath=Join-Path $recoveryRun 'f210-ba-gunmetal-invar.reload-01.factorio.log'
  $freshLog=[IO.File]::ReadAllText($freshLogPath)
  $reloadLog=[IO.File]::ReadAllText($reloadLogPath)
  $dataMarker='[mir-f210-current-ba-gunmetal-invar] DATA PASS gunmetal=recipe-prod-research_material_gunmetal-1:angels-plate-gunmetal:0.02 invar=recipe-prod-research_material_invar-1:angels-plate-invar:0.02 unique-owners=true'
  $runtimeMarker='[mir-f210-current-ba-gunmetal-invar] RUNTIME PASS stage=create technologies=researched'
  $reloadMarker='[mir-f210-current-ba-gunmetal-invar] RELOAD PASS technologies=researched save-state=preserved'
  Assert-GI ($freshLog.Contains($dataMarker,[StringComparison]::Ordinal) -and $freshLog.Contains($runtimeMarker,[StringComparison]::Ordinal)) 'recovery run fresh markers differ'
  Assert-GI ($reloadLog.Contains($dataMarker,[StringComparison]::Ordinal) -and $reloadLog.Contains($reloadMarker,[StringComparison]::Ordinal)) 'recovery run reload markers differ'
  foreach($log in @($freshLog,$reloadLog)) { Assert-GI (-not $log.Contains('Error while running event',[StringComparison]::Ordinal) -and $log.Contains('Goodbye',[StringComparison]::Ordinal)) 'recovery run Factorio lifecycle differs' }
  $result=Copy-GIPreparedRecord $prepared
  $result.status='passed-recovered'
  $result.recovery=[ordered]@{
    reason='The original runner reached result construction only after both helper assertions passed, then failed because OrderedDictionary has no Clone method.'
    source_run=Get-GIRelative $recoveryRun
    source_commit=$recoveryCommit
    source_tree=$recoveryTree
    terminal_input_lease_sha256=[string]$lease.terminal_record_sha256
    input_hashes_match=[bool]$lease.inputs_sha256_match
  }
  $result.fresh_create=[ordered]@{passed=$true;save=Get-GIArtifact (Join-Path $recoveryRun 'saves/f210-ba-gunmetal-invar.zip');stdout=Get-GIArtifact (Join-Path $recoveryRun 'f210-ba-gunmetal-invar.stdout.log');stderr=Get-GIArtifact (Join-Path $recoveryRun 'f210-ba-gunmetal-invar.stderr.log');factorio_log=Get-GIArtifact $freshLogPath}
  $result.reloads=@([ordered]@{ordinal=1;passed=$true;reload_log_contract_passed=$true;required_log_assertions=@([ordered]@{fragment=$reloadMarker;passed=$true});stdout=Get-GIArtifact (Join-Path $recoveryRun 'f210-ba-gunmetal-invar.reload-01.stdout.log');stderr=Get-GIArtifact (Join-Path $recoveryRun 'f210-ba-gunmetal-invar.reload-01.stderr.log');factorio_log=Get-GIArtifact $reloadLogPath})
  $result.mod_closure=[ordered]@{candidate=Get-GIArtifact ([string]$recoveryCandidate[0].stage_path);fixture=Get-GIArtifact (Join-Path $recoveryRun 'mods' ($fixtureName+'_'+$fixtureVersion+'.zip'));mod_list=Get-GIArtifact (Join-Path $recoveryRun 'mods/mod-list.json');input_staging=$lease}
  $resultPath=Join-Path $recoveryRun 'result.json'
  [IO.File]::WriteAllText($resultPath,(ConvertTo-Json $result -Depth 100),[Text.UTF8Encoding]::new($false))
  Write-Output "[MIR-F210-BA-GUNMETAL-INVAR-RECOVERED] $(Get-GIRelative $resultPath)"
  return
}

$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
Assert-GI ((Get-GISha $engine) -ceq $expectedEngineSha) 'Factorio executable differs from the exact stage'
$version=(& $engine --version | Out-String)
Assert-GI ($LASTEXITCODE -eq 0 -and $version -match 'Version:\s+2[.]1[.]20') 'requires Factorio 2.1.20'

$runName='g-'+[guid]::NewGuid().ToString('N').Substring(0,12)
$run=Join-Path $output $runName
$runPrefix=$outputPrefix
Assert-GI ($run.StartsWith($runPrefix,[StringComparison]::OrdinalIgnoreCase)) 'run root escapes output root'
Assert-GIPath $run 'F210 Gunmetal/Invar run root'
$inputLease=$null
try {
  New-Item -ItemType Directory -Force -Path (Join-Path $run 'mods'),(Join-Path $run 'saves') | Out-Null
  $mods=Join-Path $run 'mods'
  $inputs=@()
  foreach($entry in $expectedArchives.GetEnumerator()) {
    $archive=Join-Path $stageMods $entry.Key
    $inputs += New-GIInput -Path $archive -Role 'dependency-mod' -Identity ([ordered]@{archive=$entry.Key;sha256=$entry.Value}) -Provenance ([ordered]@{kind='retained-exact-f210-ba-stage';stage=$stage})
  }
  $inputs += New-GIInput -Path $candidate -Role 'candidate' -Identity ([ordered]@{target='f210';sha256=(Get-GISha $candidate)}) -Provenance ([ordered]@{kind='fresh-f210-target-materialization';source_commit=$sourceCommit;source_tree=$sourceTree})
  $inputLease=New-MIRImmutableInputLease -RunRoot $run -StageDirectory $mods -Inputs $inputs
  $fixtureArchive=Publish-MIRModDirectoryArchive -Source $fixtureRoot -Name $fixtureName -Version $fixtureVersion -ModsDir $mods
  Assert-GIPath $fixtureArchive 'F210 Gunmetal/Invar fixture archive'
  $enabled=@('base','elevated-rails','quality','recycler','space-age')
  $enabled += @($expectedArchives.Keys | ForEach-Object { [regex]::Replace($_,'_[0-9]+(?:[.][0-9]+)*[.]zip$','') })
  $enabled += @('more-infinite-research',$fixtureName)
  $modList=[ordered]@{mods=@($enabled | ForEach-Object { [ordered]@{name=$_;enabled=$true} })}
  [IO.File]::WriteAllText((Join-Path $mods 'mod-list.json'),(($modList | ConvertTo-Json -Depth 10)+"`n"),[Text.UTF8Encoding]::new($false))
  # Factorio updates mod-settings.dat on startup.  It remains hash-bound to
  # the retained source before launch, but must not be held by the immutable
  # archive lease while the engine atomically rewrites it.
  $stagedSettings=Join-Path $mods 'mod-settings.dat'
  Copy-Item -LiteralPath $stageSettings -Destination $stagedSettings -Force
  Assert-GI ((Get-GISha $stagedSettings) -ceq $expectedSettingsSha) 'copied exact stage settings differ before create'
  $initialSettingsArtifact=Get-GIArtifact $stagedSettings
  Assert-GIPath (Join-Path $mods 'mod-list.json') 'F210 Gunmetal/Invar mod list'

  $load=Invoke-MIRFactorioLoadCheck -FactorioBin $engine -UserDataDir $run -ScenarioName 'f210-ba-gunmetal-invar' -ScenarioTimeoutSeconds 300
  Assert-GI ([bool]$load.passed -and -not [bool]$load.timed_out -and [int]$load.exit_code -eq 0) 'fresh create failed'
  $freshLog=[IO.File]::ReadAllText([string]$load.factorio_log)
  $dataMarker='[mir-f210-current-ba-gunmetal-invar] DATA PASS gunmetal=recipe-prod-research_material_gunmetal-1:angels-plate-gunmetal:0.02 invar=recipe-prod-research_material_invar-1:angels-plate-invar:0.02 unique-owners=true'
  $runtimeMarker='[mir-f210-current-ba-gunmetal-invar] RUNTIME PASS stage=create technologies=researched'
  Assert-GI ($freshLog.Contains($dataMarker,[StringComparison]::Ordinal)) 'fresh data effect/owner marker is absent'
  Assert-GI ($freshLog.Contains($runtimeMarker,[StringComparison]::Ordinal)) 'fresh runtime effect marker is absent'

  $reloadMarker='[mir-f210-current-ba-gunmetal-invar] RELOAD PASS technologies=researched save-state=preserved'
  $reload=Invoke-MIRFactorioReloadContract -FactorioBin $engine -UserDataDir $run -ScenarioName 'f210-ba-gunmetal-invar' -SavePath $load.save -RequiredReloadCount 1 -MaxReloadDurationSeconds 300 -RequiredLogFragments @($reloadMarker)
  Assert-GI ([bool]$reload.passed) 'single reload or saved runtime-state contract failed'

  $staging=Complete-MIRImmutableInputLease -Lease $inputLease
  $inputLease=$null
  $archiveArtifacts=@($staging.inputs | Where-Object { $_.role -ceq 'dependency-mod' } | ForEach-Object { ConvertTo-MIRImmutableInputArtifact -Receipt $staging -Input $_ -Locator (Get-GIRelative ([string]$_.stage_path)) } | Sort-Object path)
  $candidateInput=@($staging.inputs | Where-Object { $_.role -ceq 'candidate' })
  Assert-GI ($candidateInput.Count -eq 1) 'terminal staged candidate cardinality differs'
  $reloadArtifacts=@($reload.reloads | ForEach-Object {
    [ordered]@{
      ordinal=$_.ordinal;passed=$_.passed;duration_seconds=$_.duration_seconds;maximum_duration_seconds=$_.maximum_duration_seconds
      input_save_sha256=$_.input_save_sha256;save_sha256=$_.save_sha256;save_byte_identical=$_.save_byte_identical
      reload_log_contract_passed=$_.reload_log_contract_passed;required_log_assertions=$_.required_log_assertions
      stdout=Get-GIArtifact $_.stdout;stderr=Get-GIArtifact $_.stderr;factorio_log=Get-GIArtifact $_.factorio_log
    }
  })
  $result=Copy-GIPreparedRecord $prepared
  $result.status='passed'
  $result.engine=[ordered]@{version=([regex]::Match($version,'Version:\s+[^\r\n]+').Value).Trim();executable_sha256=Get-GISha $engine}
  $result.run_root=Get-GIRelative $run
  $result.fresh_create=[ordered]@{passed=$load.passed;duration_seconds=$load.duration_seconds;save=Get-GIArtifact $load.save;stdout=Get-GIArtifact $load.stdout;stderr=Get-GIArtifact $load.stderr;factorio_log=Get-GIArtifact $load.factorio_log}
  $result.reloads=$reloadArtifacts
  $result.mod_closure=[ordered]@{
    enabled_mods=$enabled
    archives=$archiveArtifacts
    candidate=ConvertTo-MIRImmutableInputArtifact -Receipt $staging -Input $candidateInput[0] -Locator (Get-GIRelative ([string]$candidateInput[0].stage_path))
    settings=[ordered]@{source_sha256=$expectedSettingsSha;initial=$initialSettingsArtifact;after_engine=Get-GIArtifact $stagedSettings}
    fixture=Get-GIArtifact $fixtureArchive
    mod_list=Get-GIArtifact (Join-Path $mods 'mod-list.json')
    input_staging=$staging
  }
  $resultPath=Join-Path $run 'result.json'
  [IO.File]::WriteAllText($resultPath,(ConvertTo-Json $result -Depth 100),[Text.UTF8Encoding]::new($false))
  Write-Output "[MIR-F210-BA-GUNMETAL-INVAR] $(Get-GIRelative $resultPath)"
} catch {
  $failure=$_
  if($null -ne $inputLease -and -not $inputLease.closed) {
    try { Complete-MIRImmutableInputLease -Lease $inputLease -Outcome failed | Out-Null } catch {}
  }
  throw $failure
}
