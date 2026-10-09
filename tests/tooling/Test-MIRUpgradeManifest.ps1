# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path,[string]$SelectedManifestPath='')
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot 'tests/runtime/Test-MIRUpgrade.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count -ne 0){throw 'Upgrade harness syntax error'}
$functions=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Resolve-MIRUpgradeManifestVersion'},$true))
if($functions.Count -ne 1){throw 'Manifest resolver missing or ambiguous'}
. ([scriptblock]::Create($functions[0].Extent.Text))
$historicalFunctions=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Resolve-MIRHistoricalUpgradeTransition'},$true))
if($historicalFunctions.Count -ne 1){throw 'Historical transition resolver missing or ambiguous'}
. ([scriptblock]::Create($historicalFunctions[0].Extent.Text))
$currentFunctions=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-MIR421CurrentUpgradeInputMode'},$true))
if($currentFunctions.Count -ne 1){throw 'Current-package input mode validator missing or ambiguous'}
. ([scriptblock]::Create($currentFunctions[0].Extent.Text))
$testRoot=Join-Path $RepoRoot ('build/handoff/mir421-upgrade-manifest/'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $testRoot|Out-Null
$manifestPath=$SelectedManifestPath
if(-not $manifestPath){
  $manifestPath=Join-Path $testRoot 'controlled-nine-target-manifest.json'
  $rows=@();$lines=@{'210'='2.1';'200'='2.0';'110'='1.1';'100'='1.0';'017'='0.17';'016'='0.16';'015'='0.15';'014'='0.14';'013'='0.13'}
  foreach($code in @('210','200','110','100','017','016','015','014','013')){
    $version="4.2.${code}00";$zipPath=Join-Path $testRoot "more-infinite-research_$version.zip"
    $archive=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
    try{
      $entry=$archive.CreateEntry("more-infinite-research_$version/info.json")
      $writer=[IO.StreamWriter]::new($entry.Open())
      try{$writer.Write((@{name='more-infinite-research';version=$version;factorio_version=$lines[$code]}|ConvertTo-Json -Compress))}finally{$writer.Dispose()}
    }finally{$archive.Dispose()}
    $rows+=@{target="f$code";filename=(Split-Path $zipPath -Leaf);distribution_version=$version;sha256=(Get-FileHash $zipPath).Hash}
  }
  @{kind='MIR42FinalReleaseManifestV1';source_tag='v4.2.0';targets=$rows}|ConvertTo-Json -Depth 12|Set-Content $manifestPath -Encoding utf8
}
$manifest=Get-Content -Raw $manifestPath|ConvertFrom-Json -Depth 100
$assertions=0
foreach($row in $manifest.targets){
  $construction=$manifest.kind -cin @('MIR42FourTargetDeterministicCandidateManifestV1','MIR42FourTargetDeterministicCandidateManifestV2')
  $relative=if($construction){$row.asset.path}else{$row.filename}
  $zip=Join-Path (Split-Path $manifestPath -Parent) $relative
  $version=Resolve-MIRUpgradeManifestVersion -ManifestPath $manifestPath -CandidatePath $zip -Target $row.target
  if($version -cne $row.distribution_version){throw 'Actual manifest-selected package version differs'}
  $assertions++
}
$testManifest=Join-Path $testRoot 'test-manifest.json'
$futureZip=Join-Path $testRoot 'more-infinite-research_4.2.21001.zip'
if(Test-Path -LiteralPath $futureZip){throw 'Refusing to overwrite a prior test archive'}
$archive=[IO.Compression.ZipFile]::Open($futureZip,[IO.Compression.ZipArchiveMode]::Create)
try{
  $entry=$archive.CreateEntry('more-infinite-research_4.2.21001/info.json')
  $writer=[IO.StreamWriter]::new($entry.Open())
  try{$writer.Write('{"name":"more-infinite-research","version":"4.2.21001","factorio_version":"2.1"}')}finally{$writer.Dispose()}
}finally{$archive.Dispose()}
$fixture=[ordered]@{kind='MIR42FinalReleaseManifestV1';source_tag='v4.2.1';targets=@([ordered]@{target='f210';filename=(Split-Path $futureZip -Leaf);distribution_version='4.2.21001';sha256=(Get-FileHash -LiteralPath $futureZip).Hash})}
function Write-UpgradeManifestFixture { $fixture|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $testManifest -Encoding utf8 }
function Assert-UpgradeManifestRejected([string]$Code,[string]$Target='f210'){
  $rejected=$false
  try{Resolve-MIRUpgradeManifestVersion -ManifestPath $testManifest -CandidatePath $futureZip -Target $Target|Out-Null}catch{$rejected=$_.Exception.Message.StartsWith($Code)}
  if(-not $rejected){throw "Meaningful rejection missing: $Code"}
  $script:assertions++
}
Write-UpgradeManifestFixture
if((Resolve-MIRUpgradeManifestVersion -ManifestPath $testManifest -CandidatePath $futureZip -Target f210) -cne '4.2.21001'){throw 'Future patch did not come from the selected manifest'}
$assertions++
Assert-UpgradeManifestRejected '[mir-upgrade-manifest-target]' f200
$fixture.source_tag='v4.2.0';Write-UpgradeManifestFixture
Assert-UpgradeManifestRejected '[mir4-distribution-source-patch]'
$fixture.source_tag='v4.2.1';$fixture.targets[0].sha256='0'*64;Write-UpgradeManifestFixture
Assert-UpgradeManifestRejected '[mir-upgrade-manifest-package-hash]'
$fixture.targets[0].sha256=(Get-FileHash -LiteralPath $futureZip).Hash
$fixture.targets+=@($fixture.targets[0]);Write-UpgradeManifestFixture
Assert-UpgradeManifestRejected '[mir-upgrade-manifest-target]'
$historicalAssertions=0
$historicalCases=@(
  @{code='017';line='0.17';terminal='1.7.9';infinite='mining-productivity-4'},
  @{code='016';line='0.16';terminal='1.6.9';infinite='mining-productivity-16'},
  @{code='015';line='0.15';terminal='1.5.9';infinite='mining-productivity-16'},
  @{code='014';line='0.14';terminal='1.4.9';infinite=''},
  @{code='013';line='0.13';terminal='1.3.9';infinite=''}
)
foreach($case in $historicalCases){
  $baseline='4.2.'+$case.code+'00';$maintenance='4.2.'+$case.code+'01'
  foreach($transition in @(
    @{from=$case.terminal;to=$baseline;kind='historical-terminal'},
    @{from=$case.terminal;to=$maintenance;kind='historical-terminal'},
    @{from=$baseline;to=$maintenance;kind='same-target-maintenance'}
  )){
    $resolved=Resolve-MIRHistoricalUpgradeTransition -RepoRoot $RepoRoot -FromVersion $transition.from -ToVersion $transition.to
    if($resolved.line -cne $case.line -or $resolved.target -cne $transition.to -or $resolved.infinite_technology -cne $case.infinite -or $resolved.predecessor_kind -cne $transition.kind){throw 'Historical transition binding differs'}
    $historicalAssertions++
  }
  $other=@($historicalCases | Where-Object code -cne $case.code)[0]
  foreach($transition in @(
    @{from=$baseline;to=$baseline},
    @{from=$maintenance;to=$baseline},
    @{from=$maintenance;to=$maintenance},
    @{from=('4.2.'+$other.code+'00');to=$maintenance},
    @{from=$other.terminal;to=$maintenance},
    @{from=$baseline;to=('4.2.'+$other.code+'01')},
    @{from=$case.terminal;to=('4.2.'+$case.code+'1')},
    @{from=('4.2.'+$case.code+'0');to=$maintenance},
    @{from=$baseline;to='4.2.21001'},
    @{from=$baseline;to=('4.1.'+$case.code+'01')}
  )){
    $rejected=$false
    try{$null=Resolve-MIRHistoricalUpgradeTransition -RepoRoot $RepoRoot -FromVersion $transition.from -ToVersion $transition.to}catch{$rejected=$_.Exception.Message.StartsWith('MIR historical upgrade specialization requires an exact terminal predecessor')}
    if(-not $rejected){throw "Historical invalid transition accepted: $($transition.from) -> $($transition.to)"}
    $historicalAssertions++
  }
}
. (Join-Path $RepoRoot 'tests/support/MIR421K2Upgrade.ps1')
$k2Assertions=0
$profilePath=Join-Path $RepoRoot 'fixtures/run-profiles/k2-213-imersite-f210.json'
$bound=Read-MIR421K2UpgradeProfile -Path $profilePath
if($bound.inputs.Count-ne7-or@($bound.inputs|Where-Object {$_.identity.name-like'mir-fixture-*'-or$_.identity.name-ceq'more-infinite-research'}).Count){throw 'K2 upgrade must consume only the seven exact dependencies'}
$k2Assertions++
$mutatedPath=Join-Path $testRoot 'k2-input-profile.json'
foreach($case in @('engine','extra-mod','missing-mod','wrong-version','disabled','missing-hash','bad-hash','extra-hash','settings')){
  $mutated=Get-Content -LiteralPath $profilePath -Raw|ConvertFrom-Json -Depth 20
  $code=switch($case){
    'engine' {$mutated.engine_version='2.1.20';'[mir421-k2-upgrade-profile]'}
    'extra-mod' {$mutated.mods+=@{name='unrequested';version='1.0.0';enabled=$true};'[mir421-k2-upgrade-selection]'}
    'missing-mod' {$mutated.mods=@($mutated.mods|Where-Object name -CNE 'flib');'[mir421-k2-upgrade-selection]'}
    'wrong-version' {@($mutated.mods|Where-Object name -CEQ 'Krastorio2')[0].version='2.1.2';'[mir421-k2-upgrade-selection]'}
    'disabled' {@($mutated.mods|Where-Object name -CEQ 'Krastorio2')[0].enabled=$false;'[mir421-k2-upgrade-selection]'}
    'missing-hash' {$mutated.archive_sha256.PSObject.Properties.Remove('flib_0.17.2.zip');'[mir421-k2-upgrade-archive-count]'}
    'bad-hash' {$mutated.archive_sha256.'flib_0.17.2.zip'='not-a-hash';'[mir421-k2-upgrade-archive-hash]'}
    'extra-hash' {$mutated.archive_sha256|Add-Member NoteProperty 'extra_1.0.0.zip' ('0'*64);'[mir421-k2-upgrade-archive-count]'}
    'settings' {$mutated.settings_mode='File';'[mir421-k2-upgrade-profile]'}
  }
  $mutated|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $mutatedPath
  $rejected=$false
  try{$null=Read-MIR421K2UpgradeProfile -Path $mutatedPath}catch{$rejected=$_.Exception.Message.StartsWith($code)}
  if(-not$rejected){throw "K2 profile rejection missing: $case"};$k2Assertions++
}
$transition=@{Target='f210';FromVersion='4.2.21000';ToVersion='4.2.21001';FixtureName='assert-upgrade-k2-imersite-4-2-21000-to-4-2-21001';Archetype='';SpaceIsFake=$false;SourceOnlyFixtureNames=@()}
Assert-MIR421K2UpgradeTransition @transition;$k2Assertions++
foreach($case in @('Target','FromVersion','ToVersion','FixtureName','Archetype','SpaceIsFake','SourceOnlyFixtureNames')){
  $mutated=$transition.Clone();$mutated[$case]=switch($case){'SpaceIsFake'{$true};'SourceOnlyFixtureNames'{@('unrequested')};default{'wrong'}}
  $rejected=$false
  try{Assert-MIR421K2UpgradeTransition @mutated}catch{$rejected=$_.Exception.Message.StartsWith('[mir421-k2-upgrade-transition]')}
  if(-not$rejected){throw "K2 transition rejection missing: $case"};$k2Assertions++
}
foreach($stage in @('source','upgrade','reload')){foreach($cap in @(0,3)){
  Assert-MIR421K2UpgradeMarker -Text "native log [mir-fixture] K2-421 maintenance state verified stage=$stage;cap=$cap" -Stage $stage -Cap $cap
  $rejected=$false
  try{Assert-MIR421K2UpgradeMarker -Text "[mir-fixture] K2-421 maintenance state verified stage=$stage;cap=$([int](3-$cap))" -Stage $stage -Cap $cap}catch{$rejected=$_.Exception.Message.StartsWith("[mir421-k2-upgrade-$stage-marker]")}
  if(-not$rejected){throw "K2 stage marker missing: $stage"};$k2Assertions+=2
}}
. (Join-Path $RepoRoot 'tools/lib/validation/SettingsOverrides.ps1')
$defaultRoot=Join-Path $testRoot 'k2-default'
if((New-MIR421K2CapOverride -Root $defaultRoot -Cap 3)-or(Test-Path -LiteralPath $defaultRoot)){throw 'Default cap scenario must not create settings overrides'}
$override=New-MIR421K2CapOverride -Root (Join-Path $testRoot 'k2-zero') -Cap 0
$overrideInfo=Get-Content -LiteralPath (Join-Path $override 'info.json') -Raw|ConvertFrom-Json
$overrideText=Get-Content -LiteralPath (Join-Path $override 'settings-updates.lua') -Raw
if($overrideInfo.version-cne'0.1.210'-or$overrideInfo.factorio_version-cne'2.1'-or$overrideText-notmatch 'override\("ips-max-level-research_material_imersite", 0\)' -or ([regex]::Matches($overrideText,'(?m)^override\(')).Count-ne1){throw 'Explicit zero-cap override identity or selected settings differ'}
$k2Assertions+=2
# These controlled inputs prove readers and rejection paths, never native saves.
. (Join-Path $RepoRoot 'tests/support/MIR421SpaceFakeUpgrade.ps1')
$currentAssertions=0
foreach($target in @('f210','f200')){
  $code=$target.Substring(1)
  $mode=@{Target=$target;FromVersion="4.2.${code}00";ToVersion="4.2.${code}01";FixtureName="assert-upgrade-4-0-${code}00-to-4-1-${code}00";Archetype='base-default';SpaceIsFake=$false;SourceOnlyFixtureNames=@();SelectedReleaseManifest='';PublishedPredecessorManifest='published.json';Retention='Always';K2ImersiteInputProfile=''}
  Assert-MIR421CurrentUpgradeInputMode @mode;$currentAssertions++
  $sif=$mode.Clone();$sif.SpaceIsFake=$true;$sif.Archetype=if($target-ceq'f210'){'base-continuations'}else{'base-default'}
  Assert-MIR421CurrentUpgradeInputMode @sif;$currentAssertions++
  foreach($case in @('Target','FromVersion','ToVersion','FixtureName','Archetype','SourceOnlyFixtureNames','SelectedReleaseManifest','PublishedPredecessorManifest','Retention','K2ImersiteInputProfile')){
    $mutated=$mode.Clone()
    $mutated[$case]=switch($case){
      'Target' {'f110'}
      'FromVersion' {"4.1.${code}00"}
      'ToVersion' {"4.2.${code}02"}
      'SourceOnlyFixtureNames' {@('unrequested')}
      'SelectedReleaseManifest' {'candidate.json'}
      'PublishedPredecessorManifest' {''}
      'Retention' {'Never'}
      default {'wrong'}
    }
    $rejected=$false
    try{Assert-MIR421CurrentUpgradeInputMode @mutated}catch{$rejected=$_.Exception.Message.StartsWith('[mir421-')}
    if(-not$rejected){throw "Current-package invalid mode accepted: $target $case"};$currentAssertions++
  }
  $mutated=$sif.Clone();$mutated.Archetype='space-age-native-owner'
  $rejected=$false
  try{Assert-MIR421CurrentUpgradeInputMode @mutated}catch{$rejected=$_.Exception.Message.StartsWith('[mir421-sif-transition]')}
  if(-not$rejected){throw "Current-package SIF archetype accepted: $target"};$currentAssertions++
}
$currentK2=@{Target='f210';FromVersion='4.2.21000';ToVersion='4.2.21001';FixtureName='assert-upgrade-k2-imersite-4-2-21000-to-4-2-21001';Archetype='';SpaceIsFake=$false;SourceOnlyFixtureNames=@();SelectedReleaseManifest='';PublishedPredecessorManifest='published.json';Retention='Always';K2ImersiteInputProfile=$profilePath}
Assert-MIR421CurrentUpgradeInputMode @currentK2;$currentAssertions++
$currentK2.K2ImersiteInputProfile=''
$rejected=$false
try{Assert-MIR421CurrentUpgradeInputMode @currentK2}catch{$rejected=$_.Exception.Message.StartsWith('[mir421-k2-upgrade-inputs-required]')}
if(-not$rejected){throw 'Current-package K2 mode accepted without its locked profile'};$currentAssertions++
[pscustomobject]@{status='passed';assertions=$assertions;historical_transition_assertions=$historicalAssertions;k2_profile_transition_assertions=$k2Assertions;current_package_input_mode_assertions=$currentAssertions;selected_targets=$manifest.targets.Count;actual_hotfix_archives=([bool]$SelectedManifestPath -and $manifest.kind -ceq 'MIR42FinalReleaseManifestV1');actual_private_candidate_archives=([bool]$SelectedManifestPath -and $construction);future_patch_metadata_fixture=$true;native_engine_launched=$false}|ConvertTo-Json
