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
$predecessorFunctions=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Resolve-MIR42UpgradePredecessorReaderVersion'},$true))
if($predecessorFunctions.Count -ne 1){throw 'Published predecessor selector missing or ambiguous'}
. ([scriptblock]::Create($predecessorFunctions[0].Extent.Text))
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
  $construction=$manifest.kind -cin @('MIR42FourTargetDeterministicCandidateManifestV1','MIR42FourTargetDeterministicCandidateManifestV2','MIR42FourTargetDeterministicCandidateManifestV3')
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
$maintenance422Assertions=0
$currentManifestPath=Join-Path $testRoot 'current-maintenance-manifest.json'
$currentRows=@()
$lines=@{'210'='2.1';'200'='2.0';'110'='1.1';'100'='1.0';'017'='0.17';'016'='0.16';'015'='0.15';'014'='0.14';'013'='0.13'}
foreach($code in @('210','200','110','100','017','016','015','014','013')){
  $version="4.2.${code}02";$path=Join-Path $testRoot "more-infinite-research_$version.zip"
  $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
  try{
    $entry=$zip.CreateEntry("more-infinite-research_$version/info.json");$writer=[IO.StreamWriter]::new($entry.Open())
    try{$writer.Write((@{name='more-infinite-research';version=$version;factorio_version=$lines[$code]}|ConvertTo-Json -Compress))}finally{$writer.Dispose()}
  }finally{$zip.Dispose()}
  $currentRows+=@{target="f$code";filename=[IO.Path]::GetFileName($path);distribution_version=$version;sha256=(Get-FileHash $path).Hash}
}
$currentManifest=@{kind='MIR42FinalReleaseManifestV1';source_tag='v4.2.2';targets=$currentRows}
$currentManifest|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $currentManifestPath
foreach($row in $currentRows){
  $actual=Resolve-MIRUpgradeManifestVersion -ManifestPath $currentManifestPath -CandidatePath (Join-Path $testRoot $row.filename) -Target $row.target
  if($actual-cne$row.distribution_version){throw 'Current maintenance version differs from selected target'}
  $maintenance422Assertions++
}
$currentManifest.source_tag='v4.2.1'
$currentManifest|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $currentManifestPath
$rejected=$false
try{Resolve-MIRUpgradeManifestVersion -ManifestPath $currentManifestPath -CandidatePath (Join-Path $testRoot $currentRows[0].filename) -Target f210|Out-Null}catch{$rejected=$_.Exception.Message.StartsWith('[mir4-distribution-source-patch]')}
if(-not$rejected){throw 'Current maintenance archive was accepted under a previous release tag'}
$maintenance422Assertions++
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
foreach($fixtureVersion in @('0.1.3','0.1.4','0.1.5')){
  $variant=Get-Content -LiteralPath $profilePath -Raw|ConvertFrom-Json -Depth 20
  @($variant.mods|Where-Object name -CEQ 'mir-fixture-assert-k2-213-imersite-continuation')[0].version=$fixtureVersion
  $variantPath=Join-Path $testRoot ('k2-profile-'+$fixtureVersion+'.json')
  $variant|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $variantPath
  if($fixtureVersion-ceq'0.1.5'){
    $rejected=$false
    try{Read-MIR421K2UpgradeProfile -Path $variantPath|Out-Null}catch{$rejected=$_.Exception.Message.StartsWith('[mir421-k2-upgrade-selection]')}
    if(-not$rejected){throw 'Unreviewed fresh fixture profile was admitted'}
  }else{
    $selected=Read-MIR421K2UpgradeProfile -Path $variantPath
    if(($selected.inputs|ConvertTo-Json -Depth 10 -Compress)-cne($bound.inputs|ConvertTo-Json -Depth 10 -Compress)-or@($selected.inputs|Where-Object file_name -Like '*continuation*').Count){throw 'K2 upgrade profile changed dependencies or retained the replaced fresh fixture'}
  }
  $k2Assertions++
}
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
foreach($target in @('f210','f200','f110','f100','f017','f016','f015','f014','f013')){
  $code=$target.Substring(1)
  foreach($oldPatch in @(0,1)){
    $readerVersion=Resolve-MIR42UpgradePredecessorReaderVersion -Target $target -FromVersion ("4.2.${code}0"+$oldPatch) -SourceVersion 4.2.2
    if($readerVersion-cne('4.2.'+($oldPatch+1))){throw 'Wrong published custody contract selected for direct path'}
    $currentAssertions++
  }
  foreach($badFrom in @("4.1.${code}00","4.2.${code}02","4.2.${code}03",'4.2.99900')){
    $refused=$false;try{Resolve-MIR42UpgradePredecessorReaderVersion -Target $target -FromVersion $badFrom -SourceVersion 4.2.2|Out-Null}catch{$refused=$_.Exception.Message.StartsWith('[mir42-upgrade-predecessor-')}
    if(-not$refused){throw 'Invalid published predecessor accepted'};$currentAssertions++
  }
}
foreach($target in @('f210','f200')){
  $code=$target.Substring(1)
  $mode=@{Target=$target;FromVersion="4.2.${code}00";ToVersion="4.2.${code}01";FixtureName="assert-upgrade-4-0-${code}00-to-4-1-${code}00";Archetype='base-default';SpaceIsFake=$false;SourceOnlyFixtureNames=@();SelectedReleaseManifest='';PublishedPredecessorManifest='published.json';Retention='Always';K2ImersiteInputProfile=''}
  Assert-MIR421CurrentUpgradeInputMode @mode;$currentAssertions++
  $mode422=$mode.Clone();$mode422.SourceVersion='4.2.2';$mode422.FromVersion="4.2.${code}01";$mode422.ToVersion="4.2.${code}02"
  Assert-MIR421CurrentUpgradeInputMode @mode422;$currentAssertions++
  $direct422=$mode422.Clone();$direct422.FromVersion="4.2.${code}00"
  Assert-MIR421CurrentUpgradeInputMode @direct422;$currentAssertions++
  foreach($case in @('SourceVersion','FromVersion','ToVersion','K2ImersiteInputProfile','SourceOnlyFixtureNames','PublishedPredecessorManifest','Retention')){
    $invalid422=$mode422.Clone()
    $invalid422[$case]=switch($case){
      'SourceVersion' {'4.2.1'}
      'FromVersion' {"4.2.${code}02"}
      'ToVersion' {"4.2.${code}01"}
      'K2ImersiteInputProfile' {'old-k2-profile.json'}
      'SourceOnlyFixtureNames' {@('unrequested')}
      'PublishedPredecessorManifest' {''}
      'Retention' {'Never'}
    }
    $rejected=$false
    try{Assert-MIR421CurrentUpgradeInputMode @invalid422}catch{$rejected=$_.Exception.Message.StartsWith('[mir421-')}
    if(-not$rejected){throw "4.2.2 current-package invalid mode accepted: $target $case"};$currentAssertions++
  }
  $sif=$mode.Clone();$sif.SpaceIsFake=$true;$sif.Archetype=if($target-ceq'f210'){'base-continuations'}else{'base-default'}
  Assert-MIR421CurrentUpgradeInputMode @sif;$currentAssertions++
  $sif422=$sif.Clone();$sif422.SourceVersion='4.2.2';$sif422.FromVersion="4.2.${code}01";$sif422.ToVersion="4.2.${code}02"
  Assert-MIR421CurrentUpgradeInputMode @sif422;$currentAssertions++
  $directSif422=$sif422.Clone();$directSif422.FromVersion="4.2.${code}00"
  Assert-MIR421CurrentUpgradeInputMode @directSif422;$currentAssertions++
  $directDescriptor=Get-MIR421SpaceFakeUpgradeDescriptor -Target $target -FromVersion $directSif422.FromVersion -ToVersion $directSif422.ToVersion -FixtureName $directSif422.FixtureName -Archetype $directSif422.Archetype -SourceVersion 4.2.2
  if($directDescriptor.predecessor_source_version-cne'4.2.0'-or$directDescriptor.scenario-cne'SIF-01-published-4.2.0-to-4.2.2'){throw 'Direct SIF predecessor identity was lost'}
  $currentAssertions++
  foreach($field in @('SourceVersion','FromVersion','ToVersion','Archetype')){
    $invalid422=$sif422.Clone();$invalid422[$field]=switch($field){'SourceVersion'{'4.2.1'};'FromVersion'{"4.2.${code}02"};'ToVersion'{"4.2.${code}01"};'Archetype'{'space-age-native-owner'}}
    $rejected=$false;try{Assert-MIR421CurrentUpgradeInputMode @invalid422}catch{$rejected=$_.Exception.Message.StartsWith('[mir421-')}
    if(-not$rejected){throw "4.2.2 SIF invalid mode accepted: $target $field"};$currentAssertions++
  }
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
$currentSpaceAge=@{Target='f210';FromVersion='4.2.21001';ToVersion='4.2.21002';FixtureName='assert-upgrade-4-0-21000-to-4-1-21000';Archetype='space-age-native-owner';SpaceIsFake=$false;SourceOnlyFixtureNames=@();SelectedReleaseManifest='';PublishedPredecessorManifest='published.json';Retention='Always';SourceVersion='4.2.2'}
Assert-MIR421CurrentUpgradeInputMode @currentSpaceAge;$currentAssertions++
$directSpaceAge=$currentSpaceAge.Clone();$directSpaceAge.FromVersion='4.2.21000'
Assert-MIR421CurrentUpgradeInputMode @directSpaceAge;$currentAssertions++
foreach($field in @('Target','FromVersion','ToVersion','FixtureName','SourceVersion','SourceOnlyFixtureNames','PublishedPredecessorManifest','Retention')){
  $bad=$currentSpaceAge.Clone();$bad[$field]=switch($field){
    'Target'{'f200'};'FromVersion'{'4.2.21002'};'ToVersion'{'4.2.21003'};'FixtureName'{'wrong'};'SourceVersion'{'4.2.1'};'SourceOnlyFixtureNames'{@('extra')};'PublishedPredecessorManifest'{''};'Retention'{'Never'}
  }
  $refused=$false;try{Assert-MIR421CurrentUpgradeInputMode @bad}catch{$refused=$_.Exception.Message.StartsWith('[mir421-')}
  if(-not$refused){throw "Current Space Age mode accepted invalid $field"};$currentAssertions++
}
Assert-MIR42CompleteCatalogueUpgradeMarker -Text '[mir-fixture] complete Space Age state retained technologies=5 recipes=1';$currentAssertions++
foreach($text in @('[mir-fixture] ordinary upgrade proof complete','[mir-fixture] complete Space Age state retained technologies=0 recipes=0')){
  $refused=$false;try{Assert-MIR42CompleteCatalogueUpgradeMarker -Text $text}catch{$refused=$_.Exception.Message.StartsWith('[mir42-complete-catalogue-upgrade-marker]')}
  if(-not$refused){throw 'Incomplete full-state marker accepted'};$currentAssertions++
}
Assert-MIR421CurrentUpgradeInputMode @currentK2;$currentAssertions++
$currentK2.K2ImersiteInputProfile=''
$rejected=$false
try{Assert-MIR421CurrentUpgradeInputMode @currentK2}catch{$rejected=$_.Exception.Message.StartsWith('[mir421-k2-upgrade-inputs-required]')}
if(-not$rejected){throw 'Current-package K2 mode accepted without its locked profile'};$currentAssertions++
# Execute the actual caller statements with a recording reader, so adding a
# validator parameter without forwarding it cannot pass these controls.
$predecessorSelectCalls=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$predecessorReaderVersion'},$true))
$publishedInputCalls=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$publishedInputs'-and$n.Right.Extent.Text.StartsWith('Get-MIR42PublishedMaintenancePredecessorInputs ')},$true))
if($predecessorSelectCalls.Count-ne1-or$publishedInputCalls.Count-ne1){throw 'Published input call missing or ambiguous'}
function Get-MIR42PublishedMaintenancePredecessorInputs {param($RepoRoot,$ManifestPath,$ReleaseMetadata,$CandidateSourceVersion,$SelectedTarget,$SelectedArchivePath) return [pscustomobject]@{reader=$CandidateSourceVersion;target=$SelectedTarget;archive=$SelectedArchivePath}}
foreach($SelectedTarget in @('f210','f200')){foreach($oldPatch in @(0,1)){
  $code=$SelectedTarget.Substring(1);$SourceVersion='4.2.2';$FromVersion="4.2.${code}0$oldPatch"
  $from='explicit-selected-published.zip';$PublishedMaintenancePredecessorManifestPath='explicit-frozen-manifest.json';$metadataText='{}'
  . ([scriptblock]::Create($predecessorSelectCalls[0].Extent.Text))
  . ([scriptblock]::Create($publishedInputCalls[0].Extent.Text))
  if($publishedInputs.reader-cne('4.2.'+($oldPatch+1))-or$publishedInputs.target-cne$SelectedTarget-or$publishedInputs.archive-cne$from-or$SourceVersion-cne'4.2.2'){throw 'Published caller lost predecessor/archive/candidate identity'}
  $currentAssertions++
}}
$readerCalls=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.AssignmentStatementAst]-and$node.Left.Extent.Text-ceq'$currentMaterialization'-and$node.Right.Extent.Text.StartsWith('Read-MIRNativeProbeCurrentCandidate ')},$true))
if($readerCalls.Count-ne1){throw 'Current candidate reader assignment missing or ambiguous'}
$modeCalls=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.CommandAst]-and$node.GetCommandName()-ceq'Assert-MIR421CurrentUpgradeInputMode'},$true))
if($modeCalls.Count-ne1){throw 'Current candidate mode call missing or ambiguous'}
$modeBlocks=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.IfStatementAst]-and$node.Extent.Text.StartsWith('if($SourceMaterializationPath){')-and$node.Extent.Text.Contains('Assert-MIR421CurrentUpgradeInputMode ')},$true))
if($modeBlocks.Count-ne1){throw 'Current candidate input block missing or ambiguous'}
$RepoRootOriginal=$RepoRoot
try {
  function Resolve-MIRUpgradePath {param([string]$Path) return $Path}
  function Read-MIRNativeProbeCurrentCandidate {param($Repository,$Archive,$ReceiptPath,$Target,$SourceVersion) [pscustomobject]@{source=$SourceVersion;target=$Target;archive=$Archive;receipt=$ReceiptPath}}
  foreach($SourceVersion in @('4.2.1','4.2.2')){
    $SelectedTarget='f210';$to='selected.zip';$SourceMaterializationPath='selected-receipt.json'
    $FromVersion=if($SourceVersion-ceq'4.2.2'){'4.2.21001'}else{'4.2.21000'}
    $ToVersion=if($SourceVersion-ceq'4.2.2'){'4.2.21002'}else{'4.2.21001'}
    $FixtureName='assert-upgrade-4-0-21000-to-4-1-21000';$Archetype='base-default';$SpaceIsFake=$false
    $SourceOnlyFixtureNames=@();$SelectedReleaseManifest='';$PublishedMaintenancePredecessorManifestPath='published.json';$Retention='Always';$K2ImersiteInputProfile=''
    . ([scriptblock]::Create($modeCalls[0].Extent.Text))
    . ([scriptblock]::Create($readerCalls[0].Extent.Text))
    if($currentMaterialization.source-cne$SourceVersion-or$currentMaterialization.target-cne'f210'-or$currentMaterialization.archive-cne$to-or$currentMaterialization.receipt-cne$SourceMaterializationPath){throw 'Upgrade caller dropped explicit candidate selection'}
    $currentAssertions++
    $Archetype=''
    . ([scriptblock]::Create($modeBlocks[0].Extent.Text))
    if($Archetype-cne'base-default'){throw 'Omitted current base archetype could accidentally enable DLC'}
    $currentAssertions++
  }
} finally { $RepoRoot=$RepoRootOriginal }
# Consume the real outer descriptor and result assignments, not a matching
# string: a missing SourceVersion argument must fail the 4.2.2 case.
$sifCalls=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$sifDescriptor'-and$n.Right.Extent.Text.StartsWith('Get-MIR421SpaceFakeUpgradeDescriptor ')},$true))
$sifResults=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$result.native_scenario'-and$n.Right.Extent.Text-ceq'$sifDescriptor.scenario'},$true))
if($sifCalls.Count-ne1-or$sifResults.Count-ne1){throw 'SIF caller or result is missing or ambiguous'}
foreach($SelectedTarget in @('f210','f200')){foreach($patch in @(1,2)){
  $code=$SelectedTarget.Substring(1);$SourceVersion="4.2.$patch";$FromVersion="4.2.${code}0$($patch-1)";$ToVersion="4.2.${code}0$patch"
  $FixtureName="assert-upgrade-4-0-${code}00-to-4-1-${code}00";$Archetype=if($SelectedTarget-ceq'f210'){'base-continuations'}else{'base-default'}
  . ([scriptblock]::Create($sifCalls[0].Extent.Text))
  $result=[ordered]@{};. ([scriptblock]::Create($sifResults[0].Extent.Text))
  if($sifDescriptor.source_version-cne$SourceVersion-or$result.native_scenario-cne"SIF-01-published-4.2.$($patch-1)-to-4.2.$patch"){throw 'SIF caller lost source or predecessor identity'}
  $currentAssertions++
}}
$profile422=Join-Path $RepoRoot 'fixtures/run-profiles/k2-213-imersite-f210-422.json'
$k2ReaderCalls=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$k2Inputs'-and$n.Right.Extent.Text.StartsWith('Read-MIR421K2UpgradeProfile ')},$true))
$k2Selectors=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$k2Scenario'},$true))
$reloadSelectors=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$requiresReloadProof'},$true))
$k2MarkerCalls=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.CommandAst]-and$n.GetCommandName()-ceq'Assert-MIR421K2UpgradeMarker'},$true))
$k2ResultCalls=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$result.native_scenario'-and$n.Right.Extent.Text.StartsWith("'K2-'" )},$true))
if($k2ReaderCalls.Count-ne1-or$k2Selectors.Count-ne1-or$reloadSelectors.Count-ne1-or$k2MarkerCalls.Count-ne4-or$k2ResultCalls.Count-ne1){throw 'K2 maintenance call sites changed'}
foreach($patch in @(1,2)){
  $SourceVersion="4.2.$patch";$FromVersion="4.2.2100$($patch-1)";$ToVersion="4.2.2100$patch"
  $FixtureName='assert-upgrade-k2-imersite-'+$FromVersion.Replace('.','-')+'-to-'+$ToVersion.Replace('.','-')
  $K2ImersiteInputProfile=if($patch-eq1){$profilePath}else{$profile422}
  . ([scriptblock]::Create($k2ReaderCalls[0].Extent.Text))
  if($k2Inputs.source_version-cne$SourceVersion-or($k2Inputs.inputs|ConvertTo-Json -Depth 10 -Compress)-cne($bound.inputs|ConvertTo-Json -Depth 10 -Compress)){throw 'K2 caller changed the selected source or dependency bytes'}
  $mode=@{Target='f210';FromVersion=$FromVersion;ToVersion=$ToVersion;FixtureName=$FixtureName;Archetype='';SpaceIsFake=$false;SourceOnlyFixtureNames=@();SelectedReleaseManifest='';PublishedPredecessorManifest='published.json';Retention='Always';K2ImersiteInputProfile=$K2ImersiteInputProfile;SourceVersion=$SourceVersion}
  Assert-MIR421CurrentUpgradeInputMode @mode
  . ([scriptblock]::Create($k2Selectors[0].Extent.Text));. ([scriptblock]::Create($reloadSelectors[0].Extent.Text))
  if(-not$k2Scenario-or-not$requiresReloadProof){throw 'Current K2 fixture bypassed its scenario or reload path'}
  $info=Get-Content (Join-Path $RepoRoot ('fixtures/'+$FixtureName+'/info.json')) -Raw|ConvertFrom-Json
  if($info.version-cne"0.1.$patch"-or$info.dependencies-cnotcontains"more-infinite-research >= $FromVersion"){throw 'K2 prepared identity or predecessor differs'}
  $result=[ordered]@{};. ([scriptblock]::Create($k2ResultCalls[0].Extent.Text))
  if($result.native_scenario-cne"K2-42$patch-published-4.2.$($patch-1)-to-$SourceVersion"){throw 'K2 result identity differs'}
  $k2Assertions+=5
  foreach($K2ImersiteCap in @(0,3)){
    $createText="[mir-fixture] K2-42$patch maintenance state verified stage=source;cap=$K2ImersiteCap"
    $loadText="[mir-fixture] K2-42$patch maintenance state verified stage=upgrade;cap=$K2ImersiteCap"
    $reloadText=$secondReloadText="[mir-fixture] K2-42$patch maintenance state verified stage=reload;cap=$K2ImersiteCap"
    foreach($call in $k2MarkerCalls){. ([scriptblock]::Create($call.Extent.Text));$k2Assertions++}
    foreach($stage in @('source','upgrade','reload')){foreach($wrong in @("[mir-fixture] K2-42$(3-$patch) maintenance state verified stage=$stage;cap=$K2ImersiteCap", "[mir-fixture] K2-42$patch maintenance state verified stage=$stage;cap=$K2ImersiteCap-incomplete")){
      $rejected=$false;try{Assert-MIR421K2UpgradeMarker -Text $wrong -Stage $stage -Cap $K2ImersiteCap -SourceVersion $SourceVersion}catch{$rejected=$_.Exception.Message.Contains('marker]')}
      if(-not$rejected){throw 'Wrong-version or incomplete K2 marker accepted'};$k2Assertions++
    }}
  }
  foreach($wrongProfile in @($(if($patch-eq1){$profile422}else{$profilePath}))){
    $rejected=$false;try{Read-MIR421K2UpgradeProfile -Path $wrongProfile -SourceVersion $SourceVersion|Out-Null}catch{$rejected=$_.Exception.Message.StartsWith('[mir421-k2-upgrade-selection]')}
    if(-not$rejected){throw 'K2 opposite source profile accepted'};$k2Assertions++
  }
  foreach($field in @('SourceVersion','FromVersion','ToVersion','FixtureName','K2ImersiteInputProfile')){
    $bad=$mode.Clone();$bad[$field]=switch($field){'SourceVersion'{"4.2.$(3-$patch)"};'K2ImersiteInputProfile'{''};default{'wrong'}}
    $rejected=$false;try{Assert-MIR421CurrentUpgradeInputMode @bad}catch{$rejected=$_.Exception.Message.StartsWith('[mir421-')}
    if(-not$rejected){throw "K2 mixed maintenance mode accepted: $field"};$k2Assertions++
  }
}
[pscustomobject]@{status='passed';assertions=$assertions;maintenance422_manifest_assertions=$maintenance422Assertions;historical_transition_assertions=$historicalAssertions;k2_profile_transition_assertions=$k2Assertions;current_package_input_mode_assertions=$currentAssertions;selected_targets=$manifest.targets.Count;actual_hotfix_archives=([bool]$SelectedManifestPath -and $manifest.kind -ceq 'MIR42FinalReleaseManifestV1');actual_private_candidate_archives=([bool]$SelectedManifestPath -and $construction);future_patch_metadata_fixture=$true;native_engine_launched=$false}|ConvertTo-Json
