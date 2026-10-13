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
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')
$completeCatalogueAssignments=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.AssignmentStatementAst]-and$node.Left.Extent.Text-ceq'$requiresCompleteCatalogue'},$true))
if($completeCatalogueAssignments.Count-ne1){throw 'Complete-catalogue applicability assignment missing or ambiguous'}
$classicPolicyAssignments=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.AssignmentStatementAst]-and$node.Left.Extent.Text-ceq'$classicReducedPolicy'},$true))
if($classicPolicyAssignments.Count-ne1){throw 'Classic reduced-policy applicability assignment missing or ambiguous'}
$completeCatalogueMarkerCalls=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.CommandAst]-and$node.GetCommandName()-ceq'Assert-MIR42CompleteCatalogueUpgradeMarker'},$true))
if($completeCatalogueMarkerCalls.Count-ne3){throw 'Complete-catalogue marker must be enforced for upgrade and both reloads'}
$classicMarkerCalls=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.CommandAst]-and$node.GetCommandName()-ceq'Assert-MIR430ClassicUpgradeMarker'},$true))
if($classicMarkerCalls.Count-ne4){throw 'Classic reduced-policy marker must be enforced for source, upgrade, and both reloads'}
$snapshotRetainerFunctions=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Copy-MIRCompleteCatalogueSnapshotEvidence'},$true))
if($snapshotRetainerFunctions.Count-ne1){throw 'Complete-catalogue snapshot retainer missing or ambiguous'}
$classicHelper=Join-Path $RepoRoot 'tests/support/MIR430ClassicUpgrade.ps1'
if(-not(Test-Path -LiteralPath $classicHelper -PathType Leaf)){throw 'Classic reduced-policy upgrade helper missing'}
. $classicHelper
$classicTemplate=Get-MIR430ClassicUpgradeFixtureControl -FromVersion '4.2.10002' -ToVersion '4.3.10000'
foreach($needle in @('local state_root = storage or global','game.write_file','game.table_to_json','state_root.mir430_classic_upgrade','recipe-prod-research_character_crafting_speed-1','recipe-prod-research_iron-1')){
  if(-not$classicTemplate.Contains($needle)){throw "Classic upgrade fixture lost target-local compatibility support: $needle"}
}
$completeCatalogueEvaluator=[scriptblock]::Create($completeCatalogueAssignments[0].Right.Extent.Text)
$classicReducedPolicy=$false
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
  $construction=$manifest.kind -cin @('MIR42FourTargetDeterministicCandidateManifestV1','MIR42FourTargetDeterministicCandidateManifestV2','MIR42FourTargetDeterministicCandidateManifestV3','MIR42FourTargetDeterministicCandidateManifestV4')
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
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/ResourceGovernor.ps1')
. (Join-Path $RepoRoot 'tools/lib/compatibility/LibraryActivation.ps1')
. (Join-Path $RepoRoot 'tools/lib/workspace/RepoPaths.ps1')
$currentAssertions=0
$f200BobAngelAssertions=0
$f210OracleRoot=Join-Path $RepoRoot ('build/tmp/mir423-f210-oracle-control-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $f210OracleRoot|Out-Null
$f210OracleControl=Join-Path $f210OracleRoot 'control.lua'
$f210OldDelta='if (from_version ~= "4.2.21001" and not persisted_damage_probe) or to_version ~= "4.2.21002" then return false end'
$f210NewDelta='if from_version ~= "4.2.21001" or to_version ~= "4.2.21003" then return false end'
[IO.File]::WriteAllText($f210OracleControl,('function restored_promethium_frontier()'+"`n"+$f210OldDelta+"`n"+'end'),[Text.UTF8Encoding]::new($false))
Set-MIR423F210InheritedPromethiumDefinitionDelta -FixtureDirectory $f210OracleRoot -FromVersion '4.2.21001' -ToVersion '4.2.21003'
if((Get-Content -LiteralPath $f210OracleControl -Raw).Contains($f210OldDelta)-or-not(Get-Content -LiteralPath $f210OracleControl -Raw).Contains($f210NewDelta)){throw '4.2.3 F210 oracle did not bind the inherited reviewed definition delta'}
$currentAssertions++
foreach($invalid in @(@{from='4.2.21000';to='4.2.21003';code='[mir423-f210-oracle-predecessor]'},@{from='4.2.21002';to='4.2.21003';code='[mir423-f210-oracle-predecessor]'},@{from='4.2.21001';to='4.2.21002';code='[mir423-f210-oracle-version]'})){
  $refused=$false;try{Set-MIR423F210InheritedPromethiumDefinitionDelta -FixtureDirectory $f210OracleRoot -FromVersion $invalid.from -ToVersion $invalid.to}catch{$refused=$_.Exception.Message-ceq$invalid.code}
  if(-not$refused){throw "4.2.3 F210 oracle accepted invalid $($invalid.from) to $($invalid.to) binding"};$currentAssertions++
}
[IO.File]::WriteAllText($f210OracleControl,('function restored_promethium_frontier()'+"`n"+'if from_version ~= "4.2.21000" or to_version ~= "4.2.21003" then return false end'+"`n"+'end'),[Text.UTF8Encoding]::new($false))
$refused=$false;try{Set-MIR423F210InheritedPromethiumDefinitionDelta -FixtureDirectory $f210OracleRoot -FromVersion '4.2.21001' -ToVersion '4.2.21003'}catch{$refused=$_.Exception.Message-ceq'[mir423-f210-oracle-anchor]'}
if(-not$refused){throw '4.2.3 F210 oracle accepted a mismatched inherited definition delta'};$currentAssertions++
$f210SettingsOracleRoot=Join-Path $RepoRoot ('build/tmp/mir423-f210-settings-oracle-control-'+[Guid]::NewGuid().ToString('N'))
$f210SharedControlPath=Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-21000-to-4-1-21000/control.lua'
$f210SharedControl=Get-Content -LiteralPath $f210SharedControlPath -Raw
$f210SharedControlSha256=(Get-FileHash -LiteralPath $f210SharedControlPath -Algorithm SHA256).Hash
Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-21000-to-4-1-21000') -Destination $f210SettingsOracleRoot -Recurse
Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $f210SettingsOracleRoot -Target f210 -SourceVersion '4.2.3' -FromVersion '4.2.21000' -SpaceAge -HistoricalSettingsOracle
Set-MIR423F210HistoricalSettingDefaultOracle -FixtureDirectory $f210SettingsOracleRoot -FromVersion '4.2.21000' -ToVersion '4.2.21003'
$f210SettingsControl=Get-Content -LiteralPath (Join-Path $f210SettingsOracleRoot 'control.lua') -Raw
$f210SettingsInfo=Get-Content -LiteralPath (Join-Path $f210SettingsOracleRoot 'info.json') -Raw|ConvertFrom-Json
$f210HistoricalSettingsFamilies=@('glycerol','hydrochloric_acid','hydrofluoric_acid','nitric_acid','py_acid_gas','py_earth_flower_sample','py_earth_generic_sample','py_earth_jute_sample','py_earth_palmtree_sample','py_earth_potato_sample','py_earth_shroom_sample','py_earth_sunflower_sample','py_earth_tropical_tree_sample','py_earth_venus_fly_sample','py_glycerol','py_log','py_treated_wood','py_wood')
$f210HistoricalSettingsDefaults=[ordered]@{'enable'=$true;'effect-per-level'=2;'max-level'=0;'research-time'=30;'cost-base'=200;'cost-growth'=2;'cost-linear-increment'=0}
$f210HistoricalSettingsGuard='if from_version == "4.2.21000" and to_version == "4.2.21003" then'
$f210OriginalSettingsGuard='if to_version == "4.2.21002" then'
$f210ExpectedSettingsControl=$f210SharedControl.Replace($f210OriginalSettingsGuard,$f210HistoricalSettingsGuard)
if($f210SettingsInfo.version-cne'0.1.33'-or($f210HistoricalSettingsFamilies.Count*$f210HistoricalSettingsDefaults.Count)-ne126-or
   $f210SettingsControl-cne$f210ExpectedSettingsControl-or
   [regex]::Matches($f210SettingsControl,[regex]::Escape($f210HistoricalSettingsGuard)).Count-ne1-or
   $f210SettingsControl.Contains($f210OriginalSettingsGuard)){
  throw '4.2.3 F210 historical settings oracle did not retain its exact reviewed allowance'}
$currentAssertions++
foreach($invalid in @(@{from='4.2.21001';to='4.2.21003';code='[mir423-f210-settings-oracle-predecessor]'},@{from='4.2.21000';to='4.2.21001';code='[mir423-f210-settings-oracle-version]'},@{from='4.2.21000';to='4.2.21002';code='[mir423-f210-settings-oracle-version]'})){
  $refused=$false;try{Set-MIR423F210HistoricalSettingDefaultOracle -FixtureDirectory $f210SettingsOracleRoot -FromVersion $invalid.from -ToVersion $invalid.to}catch{$refused=$_.Exception.Message-ceq$invalid.code}
  if(-not$refused){throw "4.2.3 F210 historical settings oracle accepted invalid $($invalid.from) to $($invalid.to) binding"};$currentAssertions++
}
foreach($invalidIdentity in @(@{from='4.2.21001';space=$true},@{from='4.2.21000';space=$false})){
  $refused=$false;try{Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $f210SettingsOracleRoot -Target f210 -SourceVersion '4.2.3' -FromVersion $invalidIdentity.from -SpaceAge:$invalidIdentity.space -HistoricalSettingsOracle}catch{$refused=$_.Exception.Message-ceq'[mir423-f210-settings-oracle-transition]'}
  if(-not$refused){throw '4.2.3 F210 historical settings fixture identity accepted a non-exact scope'};$currentAssertions++
}
$f210SettingsAnchorRoot=Join-Path $RepoRoot ('build/tmp/mir423-f210-settings-oracle-anchor-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $f210SettingsAnchorRoot|Out-Null
[IO.File]::WriteAllText((Join-Path $f210SettingsAnchorRoot 'control.lua'),$f210SettingsControl.Replace('local added_422_setting_defaults = {}','local wrong_setting_defaults = {}'),[Text.UTF8Encoding]::new($false))
$refused=$false;try{Set-MIR423F210HistoricalSettingDefaultOracle -FixtureDirectory $f210SettingsAnchorRoot -FromVersion '4.2.21000' -ToVersion '4.2.21003'}catch{$refused=$_.Exception.Message-ceq'[mir423-f210-settings-oracle-anchor]'}
if(-not$refused){throw '4.2.3 F210 historical settings oracle accepted an altered complete-state guard'};$currentAssertions++
if((Get-FileHash -LiteralPath $f210SharedControlPath -Algorithm SHA256).Hash-cne$f210SharedControlSha256){throw '4.2.3 F210 settings specialization mutated the shared fixture'}
$currentAssertions++
$f200OracleRoot=Join-Path $RepoRoot ('build/tmp/mir423-f200-oracle-control-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $f200OracleRoot|Out-Null
$f200ReviewedGuard='if from_version ~= "4.2.20000" or to_version ~= "4.2.20003" then return false end'
foreach($from in @('4.2.20000','4.2.20001','4.2.20002')){
  Set-MIR422F200CompleteStateUpgradeOracle -RepoRoot $RepoRoot -FixtureDirectory $f200OracleRoot -FromVersion $from -ToVersion '4.2.20003'
  $f200Control=Get-Content -LiteralPath (Join-Path $f200OracleRoot 'control.lua') -Raw
  if(-not$f200Control.Contains($f200ReviewedGuard)){throw "F200 reviewed delta did not reject the $from predecessor"}
  if($f200Control.Contains('new technology added in performance-only upgrade')){throw "F200 reviewed delta unexpectedly applied Bob/Angel performance-only strictness to the $from predecessor"}
  $currentAssertions++
}
$bobAngelProfilePath=Join-Path $RepoRoot 'fixtures/run-profiles/f200-bob-angel-upgrade-422.json'
$bobAngelInputs=Read-MIR423F200BobAngelUpgradeProfile -Path $bobAngelProfilePath
if($bobAngelInputs.inputs.Count-ne14-or@($bobAngelInputs.inputs|Where-Object role -CEQ 'acquired-bob-angel-upstream').Count-ne13-or
   @($bobAngelInputs.inputs|Where-Object {$_.identity.name-ceq'mir423-startup-observer'-and$_.role-ceq'honest-active-mods-observer'}).Count-ne1-or
   @($bobAngelInputs.inputs|Where-Object {$_.identity.name-like '*graphics'}).Count-ne4){throw 'Bob/Angel profile did not retain its exact upstream closure and graphics inputs'}
$f200BobAngelAssertions++
$bobAngelMutation=Join-Path $testRoot 'f200-bob-angel-upgrade-profile.json'
foreach($case in @('engine','status','source-lock-status','missing-upstream','wrong-hash','extra-upstream','observer','mir-injection')){
  $mutated=Get-Content -LiteralPath $bobAngelProfilePath -Raw|ConvertFrom-Json -Depth 20
  $code=switch($case){
    'engine' {$mutated.engine_version='2.0.76';'[mir423-f200-bob-angel-profile]'}
    'status' {$mutated.status='qualified';'[mir423-f200-bob-angel-profile]'}
    'source-lock-status' {$mutated.source_lock.status='qualified';'[mir423-f200-bob-angel-custody]'}
    'missing-upstream' {$mutated.upstream_mods=@($mutated.upstream_mods|Where-Object name -CNE 'angelssmeltinggraphics');'[mir423-f200-bob-angel-selection]'}
    'wrong-hash' {$mutated.archive_sha256.'bobplates_2.1.1.zip'='0'*64;'[mir423-f200-bob-angel-archive-hash]'}
    'extra-upstream' {$mutated.upstream_mods+=@{name='unrequested';version='1.0.0';enabled=$true};'[mir423-f200-bob-angel-selection]'}
    'observer' {$mutated.observer.script='control.lua';'[mir423-f200-bob-angel-observer]'}
    'mir-injection' {$mutated.upstream_mods[0].name='more-infinite-research';'[mir423-f200-bob-angel-selection]'}
  }
  $mutated|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $bobAngelMutation
  $rejected=$false
  try{Read-MIR423F200BobAngelUpgradeProfile -Path $bobAngelMutation|Out-Null}catch{$rejected=$_.Exception.Message.StartsWith($code)}
  if(-not$rejected){throw "Bob/Angel profile rejection missing: $case"};$f200BobAngelAssertions++
}
$bobAngelFixture=Join-Path $RepoRoot ('build/tmp/mir423-f200-bob-angel-fixture-'+[Guid]::NewGuid().ToString('N'))
$bobAngelFixtureSucceeded=$false
try {
  Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-20000-to-4-1-20000') -Destination $bobAngelFixture -Recurse
  Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $bobAngelFixture -Target f200 -SourceVersion '4.2.3' -FromVersion '4.2.20002'
  Set-MIR422F200CompleteStateUpgradeOracle -RepoRoot $RepoRoot -FixtureDirectory $bobAngelFixture -FromVersion '4.2.20002' -ToVersion '4.2.20003'
  Set-MIR423F200BobAngelCompleteStateUpgradeOracle -FixtureDirectory $bobAngelFixture -FromVersion '4.2.20002' -ToVersion '4.2.20003'
  $bobAngelInfo=Get-Content -LiteralPath (Join-Path $bobAngelFixture 'info.json') -Raw|ConvertFrom-Json
  $bobAngelControl=Get-Content -LiteralPath (Join-Path $bobAngelFixture 'control.lua') -Raw
  $bobAngelSettings=Get-Content -LiteralPath (Join-Path $bobAngelFixture 'settings.lua') -Raw
  if($bobAngelInfo.version-cne'0.1.33'-or-not$bobAngelControl.Contains('["f200-bob-angel"]={technology="mining-productivity-4",level=5}')-or
     $bobAngelSettings-notmatch 'default_value="f200-bob-angel",allowed_values=\{"base-default","f200-bob-angel"\}'-or
     -not$bobAngelControl.Contains('new technology added in performance-only upgrade: " .. name')-or
     $bobAngelControl.Contains('not expected.technologies[name] and after.researched then fail("new research was awarded without earning it: " .. name)')){
    throw 'Bob/Angel full-state fixture did not receive its unique staged identity and selected oracle'}
  $f200BobAngelAssertions++
  # The host oracle states the policy independently of the staged Lua text so
  # the opposing row demonstrates that a new *unresearched* technology fails.
  $assertExactTechnologySet={
    param([hashtable]$Expected,[hashtable]$Observed)
    foreach($name in $Expected.Keys){if(-not$Observed.ContainsKey($name)){throw "missing technology: $name"}}
    foreach($name in $Observed.Keys){if(-not$Expected.ContainsKey($name)){throw "unexpected technology: $name"}}
  }
  $expectedTechnologies=@{established=[pscustomobject]@{researched=$true}}
  & $assertExactTechnologySet $expectedTechnologies @{established=[pscustomobject]@{researched=$true}}
  $f200BobAngelAssertions++
  $rejected=$false
  try{& $assertExactTechnologySet $expectedTechnologies @{established=[pscustomobject]@{researched=$true};unearned=[pscustomobject]@{researched=$false}}}catch{$rejected=$_.Exception.Message-ceq'unexpected technology: unearned'}
  if(-not$rejected){throw 'Bob/Angel performance-only technology-set control accepted an unresearched addition'}
  $f200BobAngelAssertions++
  $bobAngelSelection=@([pscustomobject]@{name='base';version='2.0.77'},[pscustomobject]@{name='angelsbioprocessinggraphics';version='2.0.0'},[pscustomobject]@{name='mir423-startup-observer';version='1.0.0'},[pscustomobject]@{name='more-infinite-research';version='4.2.20003'})
  $bobAngelSnapshot=[pscustomobject]@{active_mods=[pscustomobject]@{base='2.0.77';angelsbioprocessinggraphics='2.0.0';'mir423-startup-observer'='1.0.0';'more-infinite-research'='4.2.20003'}}
  $bobAngelReceipt=Assert-MIR423F200BobAngelFullStateActiveMods -Snapshot $bobAngelSnapshot -ExpectedSelection $bobAngelSelection -Stage upgrade
  if($bobAngelReceipt.active_mods.Count-ne4-or@($bobAngelReceipt.active_mods|Where-Object name -CEQ 'angelsbioprocessinggraphics').Count-ne1){throw 'Bob/Angel full-state active-mod receipt omitted asset-only graphics'}
  $f200BobAngelAssertions++
  $bobAngelSnapshot.active_mods.angelsbioprocessinggraphics='2.0.1'
  $rejected=$false;try{Assert-MIR423F200BobAngelFullStateActiveMods -Snapshot $bobAngelSnapshot -ExpectedSelection $bobAngelSelection -Stage upgrade|Out-Null}catch{$rejected=$_.Exception.Message.StartsWith('[mir423-f200-bob-angel-active-mods]')}
  if(-not$rejected){throw 'Bob/Angel full-state active-mod comparison accepted a graphics version mismatch'};$f200BobAngelAssertions++
  $bobAngelFixtureSucceeded=$true
} catch {
  if(-not(Test-Path -LiteralPath $bobAngelFixture -PathType Container)){New-Item -ItemType Directory -Force -Path $bobAngelFixture|Out-Null}
  [IO.File]::WriteAllText((Join-Path $bobAngelFixture 'TEST-FAILURE-RETAINED.txt'),("Bob/Angel staged-fixture host control failed and was retained for inspection.`n" + $_.Exception.Message + "`n"),[Text.UTF8Encoding]::new($false))
  throw
} finally {
  if($bobAngelFixtureSucceeded){Remove-Item -LiteralPath $bobAngelFixture -Recurse -Force}
}
if(Test-Path -LiteralPath $bobAngelFixture){throw 'Bob/Angel staged fixture was not cleaned after a successful host control'}
$f200BobAngelAssertions++
& {
  param([string]$FunctionText,[string]$Root)
  . ([scriptblock]::Create($FunctionText))
  $userdata=Join-Path $Root 'full-state-userdata'
  $output=Join-Path $Root 'full-state-output'
  $live=Join-Path $userdata 'script-output/mir-upgrade-full-state-reload.json'
  [IO.Directory]::CreateDirectory((Split-Path -Parent $live))|Out-Null
  [IO.Directory]::CreateDirectory($output)|Out-Null
  @{from_version='4.2.20002';to_version='4.2.20003';stage='reload';state='first'}|ConvertTo-Json -Compress|Set-Content -LiteralPath $live -Encoding utf8
  $first=Copy-MIRCompleteCatalogueSnapshotEvidence -SnapshotStage reload -EvidenceStage reload-1 -UserdataRoot $userdata -OutputParent $output -ToVersion '4.2.20003' -ArtifactSlug 'f200-bob-angel' -FromVersion '4.2.20002'
  @{from_version='4.2.20002';to_version='4.2.20003';stage='reload';state='second'}|ConvertTo-Json -Compress|Set-Content -LiteralPath $live -Encoding utf8
  $second=Copy-MIRCompleteCatalogueSnapshotEvidence -SnapshotStage reload -EvidenceStage reload-2 -UserdataRoot $userdata -OutputParent $output -ToVersion '4.2.20003' -ArtifactSlug 'f200-bob-angel' -FromVersion '4.2.20002'
  if($first.stage-cne'reload-1'-or$second.stage-cne'reload-2'-or$first.snapshot_stage-cne'reload'-or$second.snapshot_stage-cne'reload'-or
     $first.sha256-ceq$second.sha256-or-not(Test-Path -LiteralPath $first.path)-or-not(Test-Path -LiteralPath $second.path)){throw 'Complete-catalogue reload snapshots were not retained independently'}
  $firstState=Get-Content -LiteralPath $first.path -Raw|ConvertFrom-Json
  $secondState=Get-Content -LiteralPath $second.path -Raw|ConvertFrom-Json
  if($firstState.state-cne'first'-or$secondState.state-cne'second'){throw 'First reload snapshot was overwritten by the second reload'}
  @{from_version='4.2.20002';to_version='4.2.20003';stage='upgrade'}|ConvertTo-Json -Compress|Set-Content -LiteralPath $live -Encoding utf8
  $rejected=$false;try{Copy-MIRCompleteCatalogueSnapshotEvidence -SnapshotStage reload -EvidenceStage reload-2 -UserdataRoot $userdata -OutputParent $output -ToVersion '4.2.20003' -ArtifactSlug 'f200-bob-angel' -FromVersion '4.2.20002'|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir422-full-state-snapshot-identity]'}
  if(-not$rejected){throw 'Complete-catalogue snapshot retainer accepted the wrong live stage'}
} $snapshotRetainerFunctions[0].Extent.Text $testRoot
$f200BobAngelAssertions+=3
& {
  param([string]$Root)
  $userdata=Join-Path $Root 'classic-state-userdata'
  $output=Join-Path $Root 'classic-state-output'
  $live=Join-Path $userdata 'script-output/mir-upgrade-classic-state-reload.json'
  [IO.Directory]::CreateDirectory((Split-Path -Parent $live))|Out-Null
  [IO.Directory]::CreateDirectory($output)|Out-Null
  @{schema=1;kind='MIR430ClassicUpgradeSnapshotV1';stage='reload';from_version='4.2.20002';to_version='4.3.20000';sequence='first'}|ConvertTo-Json -Compress|Set-Content -LiteralPath $live -Encoding utf8
  $first=Copy-MIR430ClassicUpgradeSnapshotEvidence -SnapshotStage reload -EvidenceStage reload-1 -UserdataRoot $userdata -OutputParent $output -ToVersion '4.3.20000' -ArtifactSlug 'f200-classic' -FromVersion '4.2.20002'
  @{schema=1;kind='MIR430ClassicUpgradeSnapshotV1';stage='reload';from_version='4.2.20002';to_version='4.3.20000';sequence='second'}|ConvertTo-Json -Compress|Set-Content -LiteralPath $live -Encoding utf8
  $second=Copy-MIR430ClassicUpgradeSnapshotEvidence -SnapshotStage reload -EvidenceStage reload-2 -UserdataRoot $userdata -OutputParent $output -ToVersion '4.3.20000' -ArtifactSlug 'f200-classic' -FromVersion '4.2.20002'
  if($first.stage-cne'reload-1'-or$second.stage-cne'reload-2'-or$first.sha256-ceq$second.sha256-or-not(Test-Path -LiteralPath $first.path)-or-not(Test-Path -LiteralPath $second.path)){throw 'Classic reload snapshots were not retained independently'}
  @{schema=1;kind='MIR430ClassicUpgradeSnapshotV1';stage='upgrade';from_version='4.2.20002';to_version='4.3.20000'}|ConvertTo-Json -Compress|Set-Content -LiteralPath $live -Encoding utf8
  $rejected=$false;try{Copy-MIR430ClassicUpgradeSnapshotEvidence -SnapshotStage reload -EvidenceStage reload-2 -UserdataRoot $userdata -OutputParent $output -ToVersion '4.3.20000' -ArtifactSlug 'f200-classic' -FromVersion '4.2.20002'|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir430-classic-upgrade-snapshot-identity]'}
  if(-not$rejected){throw 'Classic snapshot retainer accepted the wrong live stage'}
} $testRoot
$mir43ClassicSnapshotAssertions=3
# These controls are deliberately synthetic host-only records. They prove the
# Classic receipt validator rejects corrupted candidate-bound snapshot content;
# they do not claim a Factorio upgrade or an exhaustive saved-catalogue pass.
$classicDispositionAssertions=& {
  function Copy-MIR430ClassicSyntheticValue($Value){
    return ($Value|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable -Depth 100)
  }
  $directIds=@(
    'recipe-prod-research_inventory_capacity-1',
    'recipe-prod-research_character_crafting_speed-1',
    'recipe-prod-research_character_mining_speed-1',
    'recipe-prod-research_character_reach-1',
    'recipe-prod-research_character_walking_speed-1'
  )
  $directEffects=@{
    'recipe-prod-research_inventory_capacity-1'=@(@{type='character-inventory-slots-bonus';modifier=1},@{type='character-logistic-trash-slots';modifier=1})
    'recipe-prod-research_character_crafting_speed-1'=@(@{type='character-crafting-speed';modifier=0.05})
    'recipe-prod-research_character_mining_speed-1'=@(@{type='character-mining-speed';modifier=0.05})
    'recipe-prod-research_character_reach-1'=@(@{type='character-reach-distance';modifier=10},@{type='character-build-distance';modifier=10},@{type='character-resource-reach-distance';modifier=10},@{type='character-item-drop-distance';modifier=10})
    'recipe-prod-research_character_walking_speed-1'=@(@{type='character-running-speed';modifier=0.05})
  }
  $rows=@(foreach($id in $directIds){
    [ordered]@{name=$id;level=3;researched=$false;enabled=$true;unit_count=8000;unit_energy=60;
      unit_ingredients=@(@{name='utility-science-pack';amount=1});prerequisites=@('utility-science-pack');
      effects=$directEffects[$id];hidden=$false;max_level='infinite'}
  })
  function New-MIR430ClassicSyntheticSnapshot([string]$Stage){
    return [ordered]@{
      schema=1;kind='MIR430ClassicUpgradeSnapshotV1';stage=$Stage
      mir_prefix_technologies=$rows;declared_direct_ids=$directIds
      declared_direct_technologies=(Copy-MIR430ClassicSyntheticValue $rows)
      base=@{name='mining-productivity-4';level=4;researched=$true;enabled=$true}
      base_force_effects=@{mining_drill_productivity_bonus=0.4}
      native_technologies=@(@{name='braking-force-1';level=1;researched=$true;enabled=$true})
      native_force_effects=@{train_braking_force_bonus=0.1;laboratory_speed_modifier=0.1;worker_robots_storage_bonus=1;inserter_stack_size_bonus=1}
      native_gun_speed_modifiers=@{bullet=0.1;laser=0.2}
      declared_direct_force_effects=@{character_inventory_slots_bonus=1;character_trash_slot_count=1;manual_crafting_speed_modifier=0.05;manual_mining_speed_modifier=0.05;character_reach_distance_bonus=10;character_build_distance_bonus=10;character_resource_reach_distance_bonus=10;character_item_drop_distance_bonus=10;character_running_speed_modifier=0.05}
      current_research='recipe-prod-research_character_crafting_speed-1';research_progress=0.42;research_queue=$directIds
    }
  }
  function Assert-MIR430ClassicSyntheticReject($Action,[string]$Expected){
    $rejected=$false
    try{& $Action}catch{$rejected=$_.Exception.Message.StartsWith($Expected)}
    if(-not$rejected){throw "Classic synthetic snapshot corruption did not reject $Expected"}
  }
  $source=New-MIR430ClassicSyntheticSnapshot source
  $candidate=Copy-MIR430ClassicSyntheticValue $source
  $candidate.stage='reload'
  $positive=Get-MIR430ClassicCatalogDisposition -Source $source -Candidate $candidate
  if($positive.source_mir_prefix_count-ne5-or$positive.candidate_mir_prefix_count-ne5-or$positive.dispositions.Count-ne5){throw 'Classic synthetic snapshot did not retain five declared rows'}
  $assertions=1
  Assert-MIR430ClassicSyntheticReject {
    $bad=Copy-MIR430ClassicSyntheticValue $candidate;$bad.research_queue=@($directIds[0])
    Get-MIR430ClassicCatalogDisposition -Source $source -Candidate $bad|Out-Null
  } '[mir430-classic-upgrade-current-queue-state]';$assertions++
  Assert-MIR430ClassicSyntheticReject {
    $bad=Copy-MIR430ClassicSyntheticValue $candidate;$bad.research_progress=0.41
    Get-MIR430ClassicCatalogDisposition -Source $source -Candidate $bad|Out-Null
  } '[mir430-classic-upgrade-current-work-state]';$assertions++
  Assert-MIR430ClassicSyntheticReject {
    $bad=Copy-MIR430ClassicSyntheticValue $candidate;$bad.native_gun_speed_modifiers.bullet=0.3
    Get-MIR430ClassicCatalogDisposition -Source $source -Candidate $bad|Out-Null
  } '[mir430-classic-upgrade-base-native-state]';$assertions++
  Assert-MIR430ClassicSyntheticReject {
    $bad=Copy-MIR430ClassicSyntheticValue $candidate
    $bad.mir_prefix_technologies+=,[ordered]@{name='recipe-prod-research_unexpected-1';level=1;researched=$false;enabled=$true;unit_count=1;unit_energy=1;unit_ingredients=@();prerequisites=@();effects=@();hidden=$false;max_level='infinite'}
    Get-MIR430ClassicCatalogDisposition -Source $source -Candidate $bad|Out-Null
  } '[mir430-classic-upgrade-undeclared-candidate-prefix]';$assertions++
  Assert-MIR430ClassicSyntheticReject {
    $bad=Copy-MIR430ClassicSyntheticValue $candidate
    $bad.declared_direct_technologies=@($bad.declared_direct_technologies|Select-Object -First 4)
    Get-MIR430ClassicCatalogDisposition -Source $source -Candidate $bad|Out-Null
  } '[mir430-classic-upgrade-declared-direct-catalog]';$assertions++
  $assertions
}
$mir43ClassicSnapshotAssertions+=[int]$classicDispositionAssertions
foreach($target in @('f210','f200','f110','f100','f017','f016','f015','f014','f013')){
  $isHistorical=$target-cin@('f017','f016','f015','f014','f013')
  foreach($patch in @(0,1,2)){
    $SourceVersion='4.2.3';$SpaceIsFake=$false;$k2Scenario=$false;$classicReducedPolicy=$false
    $mir42UpgradeSpecialized=-not$isHistorical;$isHistoricalTerminalFixture=$isHistorical
    $Archetype=if($target-ceq'f210'){'space-age-native-owner'}elseif(-not$isHistorical){'base-default'}else{''}
    $requiresCompleteCatalogue=& $completeCatalogueEvaluator
    if(-not$requiresCompleteCatalogue){throw "4.2.3 complete-catalogue gate is absent for $target predecessor $patch"}
    $currentAssertions++
  }
}
foreach($excluded in @('SpaceIsFake','k2Scenario','Archetype','SourceVersion')){
  $SourceVersion='4.2.3';$SpaceIsFake=$false;$k2Scenario=$false;$classicReducedPolicy=$false;$mir42UpgradeSpecialized=$true;$isHistoricalTerminalFixture=$false;$Archetype='base-default'
  switch($excluded){'SpaceIsFake'{$SpaceIsFake=$true};'k2Scenario'{$k2Scenario=$true};'Archetype'{$Archetype='unsupported'};'SourceVersion'{$SourceVersion='4.2.1'}}
  if(& $completeCatalogueEvaluator){throw "Complete-catalogue gate accepted excluded $excluded scenario"}
  $currentAssertions++
}
$SourceVersion='4.2.3';$SpaceIsFake=$false;$k2Scenario=$false;$classicReducedPolicy=$false;$mir42UpgradeSpecialized=$true;$isHistoricalTerminalFixture=$false;$Archetype='f200-bob-angel'
if(-not(& $completeCatalogueEvaluator)){throw 'Bob/Angel complete-catalogue gate is absent'}
$f200BobAngelAssertions++
foreach($target in @('f110','f100')){
  $code=$target.Substring(1)
  foreach($patch in @(0,1)){
    Assert-MIR421CurrentUpgradeInputMode -Target $target -FromVersion ("4.2.${code}0"+$patch) -ToVersion "4.2.${code}02" -FixtureName "assert-upgrade-4-0-${code}00-to-4-1-${code}00" -Archetype base-default -SpaceIsFake $false -PublishedPredecessorManifest 'published.json' -Retention Always -SourceVersion 4.2.2
    $currentAssertions++
  }
}
foreach($target in @('f210','f200','f110','f100','f017','f016','f015','f014','f013')){
  $code=$target.Substring(1)
  foreach($oldPatch in @(0,1)){
    $readerVersion=Resolve-MIR42UpgradePredecessorReaderVersion -Target $target -FromVersion ("4.2.${code}0"+$oldPatch) -SourceVersion 4.2.2
    if($readerVersion-cne('4.2.'+($oldPatch+1))){throw 'Wrong published custody contract selected for direct path'}
    $currentAssertions++
  }
  foreach($oldPatch in @(0,1,2)){
    $readerVersion=Resolve-MIR42UpgradePredecessorReaderVersion -Target $target -FromVersion ("4.2.${code}0"+$oldPatch) -SourceVersion 4.2.3
    if($readerVersion-cne('4.2.'+($oldPatch+1))){throw '423 selected the wrong published custody contract for a retained predecessor'}
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
  foreach($oldPatch in @(0,1,2)){
    $mode423=$mode422.Clone();$mode423.SourceVersion='4.2.3';$mode423.FromVersion="4.2.${code}0$oldPatch";$mode423.ToVersion="4.2.${code}03"
    Assert-MIR421CurrentUpgradeInputMode @mode423;$currentAssertions++
  }
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
$currentSpaceAge423=$currentSpaceAge.Clone();$currentSpaceAge423.SourceVersion='4.2.3';$currentSpaceAge423.FromVersion='4.2.21002';$currentSpaceAge423.ToVersion='4.2.21003'
Assert-MIR421CurrentUpgradeInputMode @currentSpaceAge423;$currentAssertions++
foreach($from in @('4.2.21000','4.2.21001')){
  $directSpaceAge423=$currentSpaceAge423.Clone();$directSpaceAge423.FromVersion=$from
  Assert-MIR421CurrentUpgradeInputMode @directSpaceAge423;$currentAssertions++
}
# The current 4.3 Full Space Age path remains bound to the same published
# 4.2.2 predecessor and complete-state fixture. It is not a generic DLC bypass.
$currentSpaceAge430=$currentSpaceAge.Clone();$currentSpaceAge430.SourceVersion='4.3.0';$currentSpaceAge430.FromVersion='4.2.21002';$currentSpaceAge430.ToVersion='4.3.21000'
Assert-MIR421CurrentUpgradeInputMode @currentSpaceAge430;$currentAssertions++
# 4.3.1 retains both exact Full Space Age paths: direct published 4.2.2 and
# immediate published 4.3.0.  A neighbouring 4.2 patch cannot enter either.
$currentSpaceAge431Direct=$currentSpaceAge430.Clone();$currentSpaceAge431Direct.SourceVersion='4.3.1';$currentSpaceAge431Direct.ToVersion='4.3.21001'
Assert-MIR421CurrentUpgradeInputMode @currentSpaceAge431Direct;$currentAssertions++
$currentSpaceAge431Immediate=$currentSpaceAge431Direct.Clone();$currentSpaceAge431Immediate.FromVersion='4.3.21000'
Assert-MIR421CurrentUpgradeInputMode @currentSpaceAge431Immediate;$currentAssertions++
$bad=$currentSpaceAge431Direct.Clone();$bad.FromVersion='4.2.21001'
$rejected=$false;try{Assert-MIR421CurrentUpgradeInputMode @bad}catch{$rejected=$_.Exception.Message-ceq'[mir421-current-upgrade-transition]'}
if(-not$rejected){throw '4.3.1 Full Space Age mode admitted an unpublished 4.2 predecessor'};$currentAssertions++
foreach($field in @('Target','FromVersion','ToVersion','FixtureName','SourceVersion','SpaceIsFake')){
  $bad=$currentSpaceAge430.Clone();$bad[$field]=switch($field){
    'Target'{'f200'};'FromVersion'{'4.2.21001'};'ToVersion'{'4.3.21001'};'FixtureName'{'wrong'};'SourceVersion'{'4.3.1'};'SpaceIsFake'{$true}
  }
  $rejected=$false;try{Assert-MIR421CurrentUpgradeInputMode @bad}catch{$rejected=$_.Exception.Message.StartsWith('[mir421-')}
  if(-not$rejected){throw "4.3 Full Space Age mode accepted invalid $field"};$currentAssertions++
}
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
$currentBobAngel=@{Target='f200';FromVersion='4.2.20002';ToVersion='4.2.20003';FixtureName='assert-upgrade-4-0-20000-to-4-1-20000';Archetype='f200-bob-angel';SpaceIsFake=$false;SourceOnlyFixtureNames=@();SelectedReleaseManifest='';PublishedPredecessorManifest='published.json';Retention='Always';K2ImersiteInputProfile='';F200BobAngelInputProfile=$bobAngelProfilePath;SourceVersion='4.2.3'}
Assert-MIR421CurrentUpgradeInputMode @currentBobAngel;$f200BobAngelAssertions++
# The exact locked F200 profile also has one Full 4.3 preservation lane.
$currentBobAngel430=$currentBobAngel.Clone();$currentBobAngel430.SourceVersion='4.3.0';$currentBobAngel430.ToVersion='4.3.20000'
Assert-MIR421CurrentUpgradeInputMode @currentBobAngel430;$f200BobAngelAssertions++
# The locked Bob/Angel profile has the same two exact Full 4.3.1 lanes.
$currentBobAngel431Direct=$currentBobAngel430.Clone();$currentBobAngel431Direct.SourceVersion='4.3.1';$currentBobAngel431Direct.ToVersion='4.3.20001'
Assert-MIR421CurrentUpgradeInputMode @currentBobAngel431Direct;$f200BobAngelAssertions++
$currentBobAngel431Immediate=$currentBobAngel431Direct.Clone();$currentBobAngel431Immediate.FromVersion='4.3.20000'
Assert-MIR421CurrentUpgradeInputMode @currentBobAngel431Immediate;$f200BobAngelAssertions++
$bad=$currentBobAngel431Direct.Clone();$bad.FromVersion='4.2.20001'
$rejected=$false;try{Assert-MIR421CurrentUpgradeInputMode @bad}catch{$rejected=$_.Exception.Message-ceq'[mir421-current-upgrade-transition]'}
if(-not$rejected){throw '4.3.1 Full Bob/Angel mode admitted an unpublished 4.2 predecessor'};$f200BobAngelAssertions++
foreach($field in @('Target','FromVersion','ToVersion','FixtureName','Archetype','SpaceIsFake','SourceOnlyFixtureNames','K2ImersiteInputProfile','F200BobAngelInputProfile','SourceVersion')){
  $bad=$currentBobAngel.Clone();$bad[$field]=switch($field){'SpaceIsFake'{$true};'SourceOnlyFixtureNames'{@('extra')};'K2ImersiteInputProfile'{'k2.json'};'F200BobAngelInputProfile'{''};'SourceVersion'{'4.2.2'};default{'wrong'}}
  $rejected=$false;try{Assert-MIR421CurrentUpgradeInputMode @bad}catch{$rejected=$_.Exception.Message -match '^\[mir42(?:1|3)-'}
  if(-not$rejected){throw "Bob/Angel current-package mode accepted invalid $field"};$f200BobAngelAssertions++
}
foreach($field in @('Target','FromVersion','ToVersion','FixtureName','Archetype','SpaceIsFake','SourceOnlyFixtureNames','K2ImersiteInputProfile','F200BobAngelInputProfile','SourceVersion')){
  $bad=$currentBobAngel430.Clone();$bad[$field]=switch($field){'SpaceIsFake'{$true};'SourceOnlyFixtureNames'{@('extra')};'K2ImersiteInputProfile'{'k2.json'};'F200BobAngelInputProfile'{''};'SourceVersion'{'4.3.1'};default{'wrong'}}
  $rejected=$false;try{Assert-MIR421CurrentUpgradeInputMode @bad}catch{$rejected=$_.Exception.Message -match '^\[mir42(?:1|3)-'}
  if(-not$rejected){throw "4.3 Full Bob/Angel mode accepted invalid $field"};$f200BobAngelAssertions++
}
# Execute the actual caller statements with a recording reader, so adding a
# validator parameter without forwarding it cannot pass these controls.
$predecessorSelectCalls=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$predecessorReaderVersion'},$true))
$publishedInputCalls=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$publishedInputs'-and$n.Right.Extent.Text.StartsWith('Get-MIR42PublishedMaintenancePredecessorInputs ')},$true))
if($predecessorSelectCalls.Count-ne1-or$publishedInputCalls.Count-ne1){throw 'Published input call missing or ambiguous'}
function Get-MIR42PublishedMaintenancePredecessorInputs {param($RepoRoot,$ManifestPath,$ReleaseMetadata,$CandidateSourceVersion,$SelectedTarget,$SelectedArchivePath) return [pscustomobject]@{reader=$CandidateSourceVersion;target=$SelectedTarget;archive=$SelectedArchivePath}}
foreach($SelectedTarget in @('f210','f200')){foreach($sourcePatch in @(2,3)){foreach($oldPatch in 0..($sourcePatch-1)){
  $code=$SelectedTarget.Substring(1);$SourceVersion="4.2.$sourcePatch";$FromVersion="4.2.${code}0$oldPatch"
  $from='explicit-selected-published.zip';$PublishedMaintenancePredecessorManifestPath='explicit-frozen-manifest.json';$metadataText='{}'
  . ([scriptblock]::Create($predecessorSelectCalls[0].Extent.Text))
  . ([scriptblock]::Create($publishedInputCalls[0].Extent.Text))
  if($publishedInputs.reader-cne('4.2.'+($oldPatch+1))-or$publishedInputs.target-cne$SelectedTarget-or$publishedInputs.archive-cne$from-or$SourceVersion-cne("4.2.$sourcePatch")){throw 'Published caller lost predecessor/archive/candidate identity'}
  $currentAssertions++
}}}
# Exercise the real reader-selection and published-input caller for both 4.3.1
# lanes.  The direct lane must retain the 4.2.3 reader; the immediate lane must
# use only the 4.3.1 reader.
foreach($SelectedTarget in @('f210','f200')){
  $code=$SelectedTarget.Substring(1)
  foreach($binding in @(
    [pscustomobject]@{from=('4.2.'+$code+'02');reader='4.2.3'},
    [pscustomobject]@{from=('4.3.'+$code+'00');reader='4.3.1'}
  )){
    $SourceVersion='4.3.1';$FromVersion=$binding.from
    $from='explicit-selected-published.zip';$PublishedMaintenancePredecessorManifestPath='explicit-frozen-manifest.json';$metadataText='{}'
    . ([scriptblock]::Create($predecessorSelectCalls[0].Extent.Text))
    . ([scriptblock]::Create($publishedInputCalls[0].Extent.Text))
    if($publishedInputs.reader-cne$binding.reader-or$publishedInputs.target-cne$SelectedTarget-or$publishedInputs.archive-cne$from){
      throw "4.3.1 published caller lost exact predecessor reader: $SelectedTarget/$($binding.from)"
    }
    $currentAssertions++
  }
}
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
  $currentModes=@(
    [pscustomobject]@{source='4.2.1';from='4.2.21000';to='4.2.21001'},
    [pscustomobject]@{source='4.2.2';from='4.2.21001';to='4.2.21002'},
    [pscustomobject]@{source='4.2.3';from='4.2.21002';to='4.2.21003'},
    [pscustomobject]@{source='4.3.1';from='4.2.21002';to='4.3.21001'},
    [pscustomobject]@{source='4.3.1';from='4.3.21000';to='4.3.21001'}
  )
  foreach($currentMode in $currentModes){
    $SourceVersion=$currentMode.source
    $SelectedTarget='f210';$to='selected.zip';$SourceMaterializationPath='selected-receipt.json'
    $FromVersion=$currentMode.from;$ToVersion=$currentMode.to
    $FixtureName='assert-upgrade-4-0-21000-to-4-1-21000';$Archetype='base-default';$SpaceIsFake=$false
    $SourceOnlyFixtureNames=@();$SelectedReleaseManifest='';$PublishedMaintenancePredecessorManifestPath='published.json';$Retention='Always';$K2ImersiteInputProfile='';$F200BobAngelInputProfile=''
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
$fixtureRootAuthority=Resolve-MIRRepoPath -RepoRoot $RepoRoot -Id 'fixtures.root'
if($fixtureRootAuthority.id-cne'fixtures.root'-or$fixtureRootAuthority.relative_path-cne'fixtures'-or$fixtureRootAuthority.alias-or$fixtureRootAuthority.mode-cne'canonical'){
  throw 'K2 upgrade fixture root authority is not canonical'}
$fixtureRoot=Join-Path $RepoRoot ([string]$fixtureRootAuthority.relative_path)
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
  # The exact transition validator owns FixtureName; fixture bytes are read
  # through the canonical fixture-root authority, never a package-root path.
  $fixtureInfoPath=Join-Path (Join-Path $fixtureRoot $FixtureName) 'info.json'
  $info=Get-Content -LiteralPath $fixtureInfoPath -Raw|ConvertFrom-Json
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
# 4.3.0 destinations retain the full current-package contract while binding
# each row to an exact published 4.2 predecessor.  4.3.1 retains two required
# Full lanes for every target: direct published 4.2.2 and immediate published
# 4.3.0.  They use different exact custody readers.  These host-only controls
# build no package and never launch an engine.
$mir43Assertions=0
$allUpgradeTargets=@('f210','f200','f110','f100','f017','f016','f015','f014','f013')
foreach($target in $allUpgradeTargets){
  $code=$target.Substring(1)
  $fixtureName=if($target-cin@('f017','f016','f015','f014','f013')){'assert-upgrade-historical-terminal-to-mir42'}else{"assert-upgrade-4-0-${code}00-to-4-1-${code}00"}
  $combinedCustody=if($target-cin@('f017','f016','f015','f014','f013')){'candidate.json'}else{''}
  foreach($oldPatch in 0..2){
    $from="4.2.${code}0$oldPatch"
    $mode=@{Target=$target;FromVersion=$from;ToVersion=('4.3.'+$code+'00');FixtureName=$fixtureName;Archetype='base-default';SpaceIsFake=$false;SourceOnlyFixtureNames=@();SelectedReleaseManifest=$combinedCustody;PublishedPredecessorManifest='published.json';Retention='Always';K2ImersiteInputProfile='';F200BobAngelInputProfile='';SourceVersion='4.3.0'}
    Assert-MIR421CurrentUpgradeInputMode @mode
    $readerVersion=Resolve-MIR42UpgradePredecessorReaderVersion -Target $target -FromVersion $from -SourceVersion '4.3.0'
    if($readerVersion-cne('4.2.'+($oldPatch+1))){throw "4.3.0 selected incorrect published predecessor custody: $target/$oldPatch"}
    $mir43Assertions+=2
  }
  $custodyMode=$mode.Clone()
  $custodyMode.SelectedReleaseManifest=if($combinedCustody){''}else{'candidate.json'}
  $rejected=$false
  try{Assert-MIR421CurrentUpgradeInputMode @custodyMode}catch{$rejected=$_.Exception.Message-ceq'[mir421-current-upgrade-input-mode]'}
  if(-not$rejected){throw "4.3.0 current mode accepted the wrong custody shape: $target"}
  $mir43Assertions++

  $published422Direct=@{Target=$target;FromVersion=('4.2.'+$code+'02');ToVersion=('4.3.'+$code+'01');FixtureName=$fixtureName;Archetype='base-default';SpaceIsFake=$false;SourceOnlyFixtureNames=@();SelectedReleaseManifest=$combinedCustody;PublishedPredecessorManifest='published-422.json';Retention='Always';K2ImersiteInputProfile='';F200BobAngelInputProfile='';SourceVersion='4.3.1'}
  Assert-MIR421CurrentUpgradeInputMode @published422Direct
  $readerVersion=Resolve-MIR42UpgradePredecessorReaderVersion -Target $target -FromVersion $published422Direct.FromVersion -SourceVersion $published422Direct.SourceVersion
  if($readerVersion-cne'4.2.3'){throw "4.3.1 selected incorrect direct 4.2.2 predecessor custody: $target"}
  $mir43Assertions+=2

  $published430=@{Target=$target;FromVersion=('4.3.'+$code+'00');ToVersion=('4.3.'+$code+'01');FixtureName=$fixtureName;Archetype='base-default';SpaceIsFake=$false;SourceOnlyFixtureNames=@();SelectedReleaseManifest=$combinedCustody;PublishedPredecessorManifest='published-430.json';Retention='Always';K2ImersiteInputProfile='';F200BobAngelInputProfile='';SourceVersion='4.3.1'}
  Assert-MIR421CurrentUpgradeInputMode @published430
  $readerVersion=Resolve-MIR42UpgradePredecessorReaderVersion -Target $target -FromVersion $published430.FromVersion -SourceVersion $published430.SourceVersion
  if($readerVersion-cne'4.3.1'){throw "4.3.1 selected incorrect immediate 4.3.0 predecessor custody: $target"}
  $mir43Assertions+=2
  foreach($releaseMode in @($published422Direct,$published430)){
    $custodyMode=$releaseMode.Clone()
    $custodyMode.SelectedReleaseManifest=if($combinedCustody){''}else{'candidate.json'}
    $rejected=$false
    try{Assert-MIR421CurrentUpgradeInputMode @custodyMode}catch{$rejected=$_.Exception.Message-ceq'[mir421-current-upgrade-input-mode]'}
    if(-not$rejected){throw "4.3.1 current mode accepted the wrong custody shape: $target/$($releaseMode.FromVersion)"}
    $mir43Assertions++
  }
  foreach($invalid in @(
    @{from="4.2.${code}01";to=('4.3.'+$code+'01');kind='unpublished-prior-minor-predecessor'},
    @{from=('4.3.'+$code+'01');to=('4.3.'+$code+'01');kind='current-version-predecessor'},
    @{from=('4.2.'+$code+'02');to=('4.3.'+$code+'00');kind='wrong-destination'}
  )){
    $bad=$published430.Clone();$bad.FromVersion=$invalid.from;$bad.ToVersion=$invalid.to
    $rejected=$false;try{Assert-MIR421CurrentUpgradeInputMode @bad}catch{$rejected=$_.Exception.Message.StartsWith('[mir421-current-upgrade-')}
    if(-not$rejected){throw "4.3.1 current mode accepted $($invalid.kind): $target"}
    $mir43Assertions++
  }
  foreach($badFrom in @("4.2.${code}01",("4.3.${code}01"))){
    $rejected=$false;try{Resolve-MIR42UpgradePredecessorReaderVersion -Target $target -FromVersion $badFrom -SourceVersion '4.3.1'|Out-Null}catch{$rejected=$_.Exception.Message.StartsWith('[mir42-upgrade-predecessor-version]')}
    if(-not$rejected){throw "4.3.1 predecessor reader accepted an unpinned predecessor: $target/$badFrom"}
    $mir43Assertions++
  }
}
$rejected=$false;try{Resolve-MIR42UpgradePredecessorReaderVersion -Target 'f999' -FromVersion '4.3.99900' -SourceVersion '4.3.1'|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-upgrade-predecessor-target]'}
if(-not$rejected){throw '4.3.1 predecessor reader accepted an unselected target'}
$mir43Assertions++

# The 4.3.1 reader consumes only the published 4.3.0 release receipt.  The
# raw manifest hash, release metadata and target assets are independently
# bound; its disclosed signing and qualification state never becomes a grant
# for the successor.
$published430Path=Join-Path $RepoRoot 'fixtures/release-inputs/mir431-published-430-manifest.json'
$published430=Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath $published430Path -CandidateSourceVersion '4.3.1'
$published430Contract=Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion '4.3.1'
if($published430Contract.source_version-cne'4.3.0'-or$published430Contract.source_tag-cne'v4.3.0'-or
   $published430Contract.release_id-ne411700807-or$published430Contract.asset_count-ne15-or
   $published430.sha256-cne$published430Contract.manifest_sha256-or$published430.bytes-ne$published430Contract.manifest_bytes-or
   [string]$published430.manifest.status-cne'emergency-accepted-with-disclosed-qualification-gaps'){
  throw '4.3.1 published 4.3.0 predecessor contract differs'
}
$published430Assets=@(for($i=0;$i-lt@($published430.manifest.targets).Count;$i++){
  $row=$published430.manifest.targets[$i]
  [pscustomobject]@{id=($i+1);name=[string]$row.filename;size=[int64]$row.bytes;digest=('sha256:'+[string]$row.sha256).ToLowerInvariant();state='uploaded'}
})
$published430Assets+=,[pscustomobject]@{id=637109443;name='mir-4.3.0.manifest.json';size=[int64]$published430.bytes;digest=('sha256:'+[string]$published430.sha256).ToLowerInvariant();state='uploaded'}
foreach($i in 11..15){$published430Assets+=,[pscustomobject]@{id=$i;name=('controlled-430-supporting-asset-'+$i);size=1;digest=('sha256:'+('a'*64));state='uploaded'}}
$published430Metadata=[pscustomobject]@{id=411700807;tag_name='v4.3.0';target_commitish='main';draft=$false;prerelease=$false;immutable=$false;assets=$published430Assets}
$published430Rows=@(Assert-MIR42PublishedMaintenancePredecessorMetadata -PinnedManifest $published430 -ReleaseMetadata $published430Metadata -CandidateSourceVersion '4.3.1')
if($published430Rows.Count-ne9-or(@($published430Rows.target)-join'|')-cne'f210|f200|f110|f100|f017|f016|f015|f014|f013' -or
   @($published430Rows|Where-Object {$_.version-cne('4.3.'+$_.target.Substring(1)+'00')}).Count){
  throw '4.3.1 published 4.3.0 predecessor target binding differs'
}
$mir43Assertions+=2
foreach($mutation in @(
  @{name='target-commitish';apply={param($m)$m.target_commitish='other'};code='[mir42-maintenance-predecessor-release-metadata]'},
  @{name='manifest-digest';apply={param($m)($m.assets|Where-Object name -ceq 'mir-4.3.0.manifest.json')[0].digest='sha256:'+('0'*64)};code='[mir42-maintenance-predecessor-published-manifest]'},
  @{name='selected-target-digest';apply={param($m)($m.assets|Where-Object name -ceq 'more-infinite-research_4.3.21000.zip')[0].digest='sha256:'+('0'*64)};code='[mir42-maintenance-predecessor-published-asset]'}
)){
  $invalid=$published430Metadata|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  & $mutation.apply $invalid
  $rejected=$false;try{Assert-MIR42PublishedMaintenancePredecessorMetadata -PinnedManifest $published430 -ReleaseMetadata $invalid -CandidateSourceVersion '4.3.1'|Out-Null}catch{$rejected=$_.Exception.Message.StartsWith($mutation.code)}
  if(-not$rejected){throw "4.3.1 published reader accepted invalid $($mutation.name)"}
  $mir43Assertions++
}
$changed430=Join-Path $testRoot 'changed-published-430-manifest.json'
$changed430Bytes=[IO.File]::ReadAllBytes($published430Path);$changed430Bytes[100]=$changed430Bytes[100]-bxor1
[IO.File]::WriteAllBytes($changed430,$changed430Bytes)
$rejected=$false;try{Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath $changed430 -CandidateSourceVersion '4.3.1'|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-maintenance-predecessor-frozen-manifest]'}
if(-not$rejected){throw '4.3.1 published reader accepted changed 4.3.0 manifest bytes'}
$rejected=$false;try{Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath (Join-Path $RepoRoot 'fixtures/release-inputs/mir423-published-422-manifest.json') -CandidateSourceVersion '4.3.1'|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-maintenance-predecessor-frozen-manifest]'}
if(-not$rejected){throw '4.3.1 published reader accepted a prior-minor manifest'}
$mir43Assertions+=2
# The direct 4.2.2 lane selects the retained 4.2.3 reader rather than trying
# to parse a 4.2 receipt through the 4.3.1 reader.  This binds its own exact
# pin and rejects the immediate-predecessor manifest under that reader.
$published422Path=Join-Path $RepoRoot 'fixtures/release-inputs/mir423-published-422-manifest.json'
$published422=Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath $published422Path -CandidateSourceVersion '4.2.3'
$published422Contract=Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion '4.2.3'
if($published422Contract.source_version-cne'4.2.2'-or$published422Contract.source_tag-cne'v4.2.2'-or
   $published422.sha256-cne$published422Contract.manifest_sha256-or$published422.bytes-ne$published422Contract.manifest_bytes){
  throw '4.3.1 direct 4.2.2 predecessor contract differs'
}
$rejected=$false;try{Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath $published430Path -CandidateSourceVersion '4.2.3'|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-maintenance-predecessor-frozen-manifest]'}
if(-not$rejected){throw '4.3.1 direct 4.2.2 reader accepted the immediate 4.3.0 manifest'}
$mir43Assertions+=2
foreach($target in @('f017','f016','f015','f014','f013')){
  $code=$target.Substring(1)
  $wrong=@{Target=$target;FromVersion="4.2.${code}02";ToVersion="4.3.${code}00";FixtureName="assert-upgrade-4-0-${code}00-to-4-1-${code}00";Archetype='base-default';SpaceIsFake=$false;SourceOnlyFixtureNames=@();SelectedReleaseManifest=$(if($target-cin@('f017','f016','f015','f014','f013')){'candidate.json'}else{''});PublishedPredecessorManifest='published.json';Retention='Always';K2ImersiteInputProfile='';F200BobAngelInputProfile='';SourceVersion='4.3.0'}
  $rejected=$false;try{Assert-MIR421CurrentUpgradeInputMode @wrong}catch{$rejected=$_.Exception.Message-ceq'[mir421-current-upgrade-scenario]'}
  if(-not$rejected){throw "4.3 historical target accepted a modern fixture: $target"}
  $mir43Assertions++
}
# A single published 4.1 reader exists for the directly acquired F200 archive.
# It is deliberately outside the retained 4.2 predecessor reader and cannot
# admit another target, destination, policy, or a synthetic 4.2 manifest.
$published410Mode=@{Target='f200';FromVersion='4.1.20000';ToVersion='4.3.20000';FixtureName='assert-upgrade-4-0-20000-to-4-1-20000';Archetype='base-default';SpaceIsFake=$false;SourceOnlyFixtureNames=@();SelectedReleaseManifest='';PublishedPredecessorManifest='';Retention='Always';K2ImersiteInputProfile='';F200BobAngelInputProfile='';SourceVersion='4.3.0'}
Assert-MIR421CurrentUpgradeInputMode @published410Mode
Assert-MIR430Published410F200FullUpgradeTransition -Target $published410Mode.Target -SourceVersion $published410Mode.SourceVersion -FromVersion $published410Mode.FromVersion -ToVersion $published410Mode.ToVersion -FixtureName $published410Mode.FixtureName -Archetype $published410Mode.Archetype -SpaceIsFake $published410Mode.SpaceIsFake -UpgradePolicy Full
$mir43Assertions+=2
foreach($invalid in @(
  @{field='Target';value='f210';code='[mir421-current-upgrade-input-mode]'},
  @{field='ToVersion';value='4.3.20001';code='[mir421-current-upgrade-input-mode]'},
  @{field='SourceVersion';value='4.3.1';code='[mir421-current-upgrade-input-mode]'},
  @{field='PublishedPredecessorManifest';value='published-4.2.json';code='[mir421-current-upgrade-transition]'}
)){
  $bad=$published410Mode.Clone();$bad[$invalid.field]=$invalid.value
  $rejected=$false;try{Assert-MIR421CurrentUpgradeInputMode @bad}catch{$rejected=$_.Exception.Message-ceq$invalid.code}
  if(-not$rejected){throw "Published 4.1 F200 mode admitted invalid $($invalid.field)"}
  $mir43Assertions++
}
$rejected=$false;try{Assert-MIR430Published410F200FullUpgradeTransition -Target f200 -SourceVersion '4.3.0' -FromVersion '4.1.20000' -ToVersion '4.3.20000' -FixtureName 'assert-upgrade-4-0-20000-to-4-1-20000' -Archetype base-default -SpaceIsFake:$false -UpgradePolicy Classic}catch{$rejected=$_.Exception.Message-ceq'[mir430-published410-upgrade-profile]'}
if(-not$rejected){throw 'Published 4.1 F200 transition admitted the destructive Classic policy'}
$rejected=$false;try{Assert-MIR430Published410F200FullUpgradeTransition -Target f200 -SourceVersion '4.3.0' -FromVersion '4.1.20001' -ToVersion '4.3.20000' -FixtureName 'assert-upgrade-4-0-20000-to-4-1-20000' -Archetype base-default -SpaceIsFake:$false -UpgradePolicy Full}catch{$rejected=$_.Exception.Message-ceq'[mir430-published410-upgrade-transition]'}
if(-not$rejected){throw 'Published 4.1 F200 transition inferred a non-published archive'}
$wrong410Archive=Join-Path $testRoot 'not-the-published-410.zip';[IO.File]::WriteAllText($wrong410Archive,'not a published archive',[Text.UTF8Encoding]::new($false))
$rejected=$false;try{Read-MIR430Published410F200ReleaseInput -ReleaseMetadata ([pscustomobject]@{}) -ReleaseManifestPath $wrong410Archive -ArchivePath $wrong410Archive|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir430-published410-archive]'}
if(-not$rejected){throw 'Published 4.1 reader admitted an unrelated archive'}
$mir43Assertions+=3
foreach($case in $historicalCases){
  foreach($sourceVersion in @('4.3.0','4.3.1')){
    $to='4.3.'+$case.code+([version]$sourceVersion).Build.ToString('00')
    $fromVersions=if($sourceVersion-ceq'4.3.1'){@(('4.2.'+$case.code+'02'),('4.3.'+$case.code+'00'))}else{@('4.2.'+$case.code+'02')}
    foreach($from in $fromVersions){
      $resolved=Resolve-MIRHistoricalUpgradeTransition -RepoRoot $RepoRoot -FromVersion $from -ToVersion $to
      if($resolved.target-cne$to-or$resolved.predecessor_kind-cne'same-target-maintenance'){
        throw "4.3 historical cross-minor transition binding differs: $($case.code)/$sourceVersion/$from"
      }
      $mir43Assertions++
    }
  }
}
foreach($sourceVersion in @('4.3.0','4.3.1')){
  foreach($target in $allUpgradeTargets){
    $isHistorical=$target-cin@('f017','f016','f015','f014','f013')
    $SourceVersion=$sourceVersion;$SpaceIsFake=$false;$k2Scenario=$false
    $mir42UpgradeSpecialized=-not$isHistorical;$isHistoricalTerminalFixture=$isHistorical;$Archetype='base-default'
    if(-not(& $completeCatalogueEvaluator)){throw "4.3 complete-catalogue gate is absent for $target/$sourceVersion"}
    $mir43Assertions++
  }
}
# Fixture versions must distinguish every 4.2 predecessor and destination
# patch, without modifying the checked-in templates.
# Classic deliberately records a bounded retained-core/omission proof instead
# of claiming complete 4.2 catalogue preservation.  The Full opt-in retains
# the existing complete catalogue gate under otherwise identical inputs.
foreach($target in @('f210','f200','f110','f100')){
  $code=$target.Substring(1)
  foreach($patch in @(0,1,2)){
    $SourceVersion='4.3.0';$SpaceIsFake=$false;$k2Scenario=$false;$classicReducedPolicy=$true
    $mir42UpgradeSpecialized=$true;$isHistoricalTerminalFixture=$false;$Archetype='base-default'
    if(& $completeCatalogueEvaluator){throw "Classic 4.3.0 incorrectly requires complete-catalogue proof for $target predecessor $patch"}
    Assert-MIR430ClassicUpgradeMode -Target $target -SourceVersion $SourceVersion -FromVersion ('4.2.'+$code+$patch.ToString('00')) -ToVersion ('4.3.'+$code+'00') -FixtureName ('assert-upgrade-4-0-'+$code+'00-to-4-1-'+$code+'00') -Archetype $Archetype
    $mir43Assertions+=2
  }
}
$SourceVersion='4.3.0';$SpaceIsFake=$false;$k2Scenario=$false;$classicReducedPolicy=$false;$mir42UpgradeSpecialized=$true;$isHistoricalTerminalFixture=$false;$Archetype='base-default'
if(-not(& $completeCatalogueEvaluator)){throw 'Full 4.3.0 opt-in lost complete-catalogue gate'}
$mir43Assertions++
$mir43FixtureRoot=Join-Path $RepoRoot ('build/tmp/mir43-upgrade-fixture-identities-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $mir43FixtureRoot|Out-Null
foreach($sourceVersion in @('4.3.0','4.3.1')){
  foreach($target in @('f210','f200','f110','f100')){
    $code=$target.Substring(1)
    $predecessors=if($sourceVersion-ceq'4.3.1'){@(
      [pscustomobject]@{label='direct-422';from=('4.2.'+$code+'02');identity_patch=2},
      [pscustomobject]@{label='immediate-430';from=('4.3.'+$code+'00');identity_patch=0}
    )}else{@(0..2|ForEach-Object {[pscustomobject]@{label=('published-42-'+$_);from=('4.2.'+$code+$_.ToString('00'));identity_patch=$_}})}
    foreach($predecessor in $predecessors){
      $fixtureRoot=Join-Path $mir43FixtureRoot ('mir43-modern-'+$target+'-'+$sourceVersion.Replace('.','-')+'-'+$predecessor.label)
      $fixtureName='assert-upgrade-4-0-'+$code+'00-to-4-1-'+$code+'00'
      Copy-Item -LiteralPath (Join-Path $RepoRoot ('fixtures/'+$fixtureName)) -Destination $fixtureRoot -Recurse
      Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $fixtureRoot -Target $target -SourceVersion $sourceVersion -FromVersion $predecessor.from
      $info=Get-Content -LiteralPath (Join-Path $fixtureRoot 'info.json') -Raw|ConvertFrom-Json
      $expected='0.1.'+(40+3*([version]$sourceVersion).Build+$predecessor.identity_patch)
      if($info.version-cne$expected){throw "4.3 modern fixture identity collision: $target/$sourceVersion/$($predecessor.label)"}
      $mir43Assertions++
    }
  }
  foreach($target in @('f017','f016','f015','f014','f013')){
    $code=$target.Substring(1)
    $predecessors=if($sourceVersion-ceq'4.3.1'){@(
      [pscustomobject]@{label='direct-422';from=('4.2.'+$code+'02');identity_patch=2},
      [pscustomobject]@{label='immediate-430';from=('4.3.'+$code+'00');identity_patch=0}
    )}else{@(0..2|ForEach-Object {[pscustomobject]@{label=('published-42-'+$_);from=('4.2.'+$code+$_.ToString('00'));identity_patch=$_}})}
    foreach($predecessor in $predecessors){
      $fixtureRoot=Join-Path $mir43FixtureRoot ('mir43-historical-'+$target+'-'+$sourceVersion.Replace('.','-')+'-'+$predecessor.label)
      Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-upgrade-historical-terminal-to-mir42') -Destination $fixtureRoot -Recurse
      $infoPath=Join-Path $fixtureRoot 'info.json'
      $infoText=Get-Content -LiteralPath $infoPath -Raw
      [IO.File]::WriteAllText($infoPath,$infoText.Replace('@@FACTORIO_LINE@@',('0.'+[int]$code)).Replace('@@MIR_UPGRADE_FROM_VERSION@@',$predecessor.from),[Text.UTF8Encoding]::new($false))
      Set-MIR42HistoricalMaintenanceUpgradeFixtureIdentity -FixtureDirectory $fixtureRoot -Target $target -SourceVersion $sourceVersion -FromVersion $predecessor.from
      $info=Get-Content -LiteralPath (Join-Path $fixtureRoot 'info.json') -Raw|ConvertFrom-Json
      $expected='1.0.'+(20+3*([version]$sourceVersion).Build+$predecessor.identity_patch)
      if($info.version-cne$expected){throw "4.3 historical fixture identity collision: $target/$sourceVersion/$($predecessor.label)"}
      $mir43Assertions++
    }
  }
}
$f200Mir43Oracle=Join-Path $mir43FixtureRoot 'mir43-f200-full-state-oracle'
New-Item -ItemType Directory -Force -Path $f200Mir43Oracle|Out-Null
Set-MIR422F200CompleteStateUpgradeOracle -RepoRoot $RepoRoot -FixtureDirectory $f200Mir43Oracle -FromVersion '4.2.20002' -ToVersion '4.3.20000'
$f200Mir43Control=Get-Content -LiteralPath (Join-Path $f200Mir43Oracle 'control.lua') -Raw
if($f200Mir43Control.Contains('reviewed_420_frontier')){throw '4.3 F200 full-state oracle retained a 4.2-only definition-delta allowance'}
$mir43Assertions++
$f200Mir431Oracle=Join-Path $mir43FixtureRoot 'mir431-f200-full-state-oracle'
New-Item -ItemType Directory -Force -Path $f200Mir431Oracle|Out-Null
Set-MIR422F200CompleteStateUpgradeOracle -RepoRoot $RepoRoot -FixtureDirectory $f200Mir431Oracle -FromVersion '4.3.20000' -ToVersion '4.3.20001'
$f200Mir431Control=Get-Content -LiteralPath (Join-Path $f200Mir431Oracle 'control.lua') -Raw
if($f200Mir431Control.Contains('reviewed_420_frontier')-or-not$f200Mir431Control.Contains('"4.3.20000"')-or-not$f200Mir431Control.Contains('"4.3.20001"')){throw '4.3.1 F200 full-state oracle differs'}
$mir43Assertions++
$f200Published410Fixture=Join-Path $mir43FixtureRoot 'mir43-f200-published-410-full-state-oracle'
Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-20000-to-4-1-20000') -Destination $f200Published410Fixture -Recurse
Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $f200Published410Fixture -Target f200 -SourceVersion '4.3.0' -FromVersion '4.1.20000'
Set-MIR422F200CompleteStateUpgradeOracle -RepoRoot $RepoRoot -FixtureDirectory $f200Published410Fixture -FromVersion '4.1.20000' -ToVersion '4.3.20000'
$f200Published410Info=Get-Content -LiteralPath (Join-Path $f200Published410Fixture 'info.json') -Raw|ConvertFrom-Json
$f200Published410Control=Get-Content -LiteralPath (Join-Path $f200Published410Fixture 'control.lua') -Raw
if($f200Published410Info.version-cne'0.1.49'-or-not$f200Published410Control.Contains('"4.1.20000"')-or-not$f200Published410Control.Contains('"4.3.20000"')){
  throw 'Published 4.1 F200 fixture identity or complete-state oracle differs'
}
$mir43Assertions++
$f210FullSettingFixture=Join-Path $mir43FixtureRoot 'mir43-f210-full-setting-allowance'
Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-21000-to-4-1-21000') -Destination $f210FullSettingFixture -Recurse
Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $f210FullSettingFixture -Target f210 -SourceVersion '4.3.0' -FromVersion '4.2.21002' -SpaceAge
Set-MIR430FullCompilerProfileUpgradeAllowance -Target f210 -FixtureDirectory $f210FullSettingFixture -FromVersion '4.2.21002' -ToVersion '4.3.21000'
$f210FullControl=Get-Content -LiteralPath (Join-Path $f210FullSettingFixture 'control.lua') -Raw
foreach($needle in @(
  'local added_422_setting_defaults = {["mir-compiler-profile"] = "full"}',
  'to_version == "4.3.21000"',
  'export_state("source")',
  'export_state("upgrade")',
  'export_state("reload")',
  'for _, name in ipairs({"recipe-prod-research_cargo_bay_unloading_distance-1", "recipe-prod-research_ice-1", "recipe-prod-research_science_pack_productivity-1"}) do'
)){
  if(-not$f210FullControl.Contains($needle)){throw "F210 Full fixture lost complete-state hook: $needle"}
}
$mir43Assertions++
$f210MissingSourceFixture=Join-Path $mir43FixtureRoot 'mir43-f210-full-missing-source-hook'
Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-21000-to-4-1-21000') -Destination $f210MissingSourceFixture -Recurse
Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $f210MissingSourceFixture -Target f210 -SourceVersion '4.3.0' -FromVersion '4.2.21002' -SpaceAge
$f210MissingSourceControl=Join-Path $f210MissingSourceFixture 'control.lua'
$missingSourceText=Get-Content -LiteralPath $f210MissingSourceControl -Raw
if(-not$missingSourceText.Contains('    export_state("source")')){throw 'F210 source-hook opposing fixture anchor changed'}
[IO.File]::WriteAllText($f210MissingSourceControl,$missingSourceText.Replace('    export_state("source")','    -- source export removed'),[Text.UTF8Encoding]::new($false))
$rejected=$false;try{Set-MIR430FullCompilerProfileUpgradeAllowance -Target f210 -FixtureDirectory $f210MissingSourceFixture -FromVersion '4.2.21002' -ToVersion '4.3.21000'}catch{$rejected=$_.Exception.Message-ceq'[mir430-full-upgrade-complete-state-anchor]'}
if(-not$rejected){throw 'F210 Full fixture admitted a missing source complete-state hook'}
$mir43Assertions++
$f210BaseFullFixture=Join-Path $mir43FixtureRoot 'mir43-f210-base-full-setting-allowance'
Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-21000-to-4-1-21000') -Destination $f210BaseFullFixture -Recurse
Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $f210BaseFullFixture -Target f210 -SourceVersion '4.3.0' -FromVersion '4.2.21002'
Set-MIR430FullCompilerProfileUpgradeAllowance -Target f210 -FixtureDirectory $f210BaseFullFixture -FromVersion '4.2.21002' -ToVersion '4.3.21000' -BaseDefaultCompleteState
$f210BaseFullControl=Get-Content -LiteralPath (Join-Path $f210BaseFullFixture 'control.lua') -Raw
foreach($needle in @(
  '(archetype == "space-age-native-owner" or archetype == "base-default")',
  'to_version == "4.3.21000"',
  'export_state("source")',
  'export_state("upgrade")',
  'export_state("reload")',
  'for _, name in ipairs({}) do'
)){
  if(-not$f210BaseFullControl.Contains($needle)){throw "F210 Base Full fixture lost complete-state hook: $needle"}
}
$mir43Assertions++
$f210WrongBaseBindingFixture=Join-Path $mir43FixtureRoot 'mir43-f210-base-wrong-snapshot-binding'
Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-21000-to-4-1-21000') -Destination $f210WrongBaseBindingFixture -Recurse
Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $f210WrongBaseBindingFixture -Target f210 -SourceVersion '4.3.0' -FromVersion '4.2.21001'
$rejected=$false;try{Set-MIR430FullCompilerProfileUpgradeAllowance -Target f210 -FixtureDirectory $f210WrongBaseBindingFixture -FromVersion '4.2.21001' -ToVersion '4.3.21000' -BaseDefaultCompleteState}catch{$rejected=$_.Exception.Message-ceq'[mir430-full-upgrade-base-snapshot-transition]'}
if(-not$rejected){throw 'F210 Base complete-state snapshots admitted an unbound predecessor'}
$mir43Assertions++
$rejected=$false;try{Set-MIR430FullCompilerProfileUpgradeAllowance -Target f110 -FixtureDirectory $f210WrongBaseBindingFixture -FromVersion '4.2.11002' -ToVersion '4.3.11000' -BaseDefaultCompleteState}catch{$rejected=$_.Exception.Message-ceq'[mir430-full-upgrade-base-snapshot-transition]'}
if(-not$rejected){throw 'F110 accepted the F210 Base complete-state switch'}
$mir43Assertions++
foreach($target in @('f110','f100')){
  $code=$target.Substring(1)
  $fixturePath=Join-Path $mir43FixtureRoot ('mir43-'+$target+'-full-setting-allowance')
  Copy-Item -LiteralPath (Join-Path $RepoRoot ('fixtures/assert-upgrade-4-0-'+$code+'00-to-4-1-'+$code+'00')) -Destination $fixturePath -Recurse
  Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $fixturePath -Target $target -SourceVersion '4.3.0' -FromVersion ('4.2.'+$code+'02')
  Set-MIR422HistoricalCompleteStateUpgradeOracle -RepoRoot $RepoRoot -FixtureDirectory $fixturePath -Target $target -FromVersion ('4.2.'+$code+'02') -ToVersion ('4.3.'+$code+'00')
  Set-MIR430FullCompilerProfileUpgradeAllowance -Target $target -FixtureDirectory $fixturePath -FromVersion ('4.2.'+$code+'02') -ToVersion ('4.3.'+$code+'00')
  $allowance=Get-Content -LiteralPath (Join-Path $fixturePath 'mir422_complete_state.lua') -Raw
  if(-not$allowance.Contains('before[field]["mir-compiler-profile"] == nil')-or-not$allowance.Contains('expected_settings["mir-compiler-profile"] = "full"')){
    throw "$target Full selector allowance was not bound to the complete-state oracle"
  }
  $mir43Assertions++
}
Remove-Item -LiteralPath $mir43FixtureRoot -Recurse -Force
# The matrix has a single current-destination route with exact argument
# propagation and demands both reload receipts for it.
$matrixTokens=$null;$matrixErrors=$null
$matrixAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot 'tests/runtime/Test-MIRUpgradeMatrix.ps1'),[ref]$matrixTokens,[ref]$matrixErrors)
if($matrixErrors.Count){throw 'Upgrade matrix syntax error'}
$matrixText=$matrixAst.Extent.Text
foreach($needle in @('$LocalModLibraryDirs','$SourceMaterializationPath','$SelectedReleaseManifest','$SelectedTarget','$SourceVersion','$UpgradePolicy','$PublishedMaintenancePredecessorManifestPath','LocalModLibraryDirs = @($LocalModLibraryDirs)','$arguments.SourceMaterializationPath=$SourceMaterializationPath','$arguments.SelectedReleaseManifest=$SelectedReleaseManifest','$arguments.SelectedTarget=$SelectedTarget','$arguments.SourceVersion=$SourceVersion','$arguments.UpgradePolicy=$UpgradePolicy','$arguments.PublishedMaintenancePredecessorManifestPath=$PublishedMaintenancePredecessorManifestPath','($currentDestination -or $FixtureName')){
  if(-not$matrixText.Contains($needle)){throw "4.3 upgrade matrix lost current destination control: $needle"}
  $mir43Assertions++
}

# The public UpgradePolicy parameter is a validated caller contract.  The
# native resource governor needs a different object, so it must never reuse
# that variable name (PowerShell variable names are case-insensitive).  Parse
# assignments and command arguments instead of accepting a text-only check.
$upgradeTokens=$null;$upgradeErrors=$null
$upgradeAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot 'tests/runtime/Test-MIRUpgrade.ps1'),[ref]$upgradeTokens,[ref]$upgradeErrors)
if($upgradeErrors.Count){throw 'Upgrade runner syntax error'}
$upgradeParameters=@($upgradeAst.ParamBlock.Parameters|Where-Object {$_.Name.VariablePath.UserPath-ieq'UpgradePolicy'})
if($upgradeParameters.Count-ne1){throw 'Upgrade runner lost its validated UpgradePolicy parameter'}
function Get-MIRUpgradePolicyAssignments {
  param([Parameter(Mandatory)][Management.Automation.Language.Ast]$Ast)
  @($Ast.FindAll({param($node)
    $node-is[Management.Automation.Language.AssignmentStatementAst]-and
    $node.Left-is[Management.Automation.Language.VariableExpressionAst]-and
    $node.Left.VariablePath.UserPath-ieq'UpgradePolicy'
  },$true))
}
$upgradePolicyAssignments=@(Get-MIRUpgradePolicyAssignments -Ast $upgradeAst)
if($upgradePolicyAssignments.Count){throw 'Upgrade runner overwrites the validated UpgradePolicy parameter'}
$collisionTokens=$null;$collisionErrors=$null
$lowercaseCollisionAst=[Management.Automation.Language.Parser]::ParseInput('$upgradePolicy=[pscustomobject]@{minimum_free_ram_gib=4}',[ref]$collisionTokens,[ref]$collisionErrors)
if($collisionErrors.Count-or-not @(Get-MIRUpgradePolicyAssignments -Ast $lowercaseCollisionAst).Count){throw 'Upgrade runner collision guard would admit the original lowercase resource-policy assignment'}
$resourcePolicyAssignments=@($upgradeAst.FindAll({param($node)
  $node-is[Management.Automation.Language.AssignmentStatementAst]-and
  $node.Left-is[Management.Automation.Language.VariableExpressionAst]-and
  $node.Left.VariablePath.UserPath-ieq'upgradeResourcePolicy'
},$true))
if($resourcePolicyAssignments.Count-ne1){throw 'Upgrade runner lacks one distinct resource-policy object'}
$policyConsumers=@($upgradeAst.FindAll({param($node)
  if($node-isnot[Management.Automation.Language.CommandAst]){return $false}
  $elements=@($node.CommandElements)
  $name=if($elements.Count){[string]$elements[0].Extent.Text}else{''}
  $name-cin@('Assert-MIR441ResourceAdmission','Invoke-MIR441MonitoredProcess')
},$true))
if($policyConsumers.Count-ne2){throw 'Upgrade runner has an ambiguous resource-policy consumer set'}
foreach($consumer in $policyConsumers){
  $elements=@($consumer.CommandElements);$policyIndex=-1
  for($index=1;$index-lt$elements.Count;$index++){
    if([string]$elements[$index].Extent.Text-ceq'-Policy'){$policyIndex=$index;break}
  }
  if($policyIndex-lt0-or$policyIndex-ge($elements.Count-1)-or
     $elements[$policyIndex+1]-isnot[Management.Automation.Language.VariableExpressionAst]-or
     $elements[$policyIndex+1].VariablePath.UserPath-ine'upgradeResourcePolicy'){
    throw 'Upgrade runner does not pass its distinct resource policy to the governed invocation'
  }
}
$mir43Assertions+=5

# Exercise the wrapper's real named-argument call shape with a controlled
# callee. No engine or mod archive is launched: the fake runner records what
# the matrix passes and emits only the minimum schema/cleanup receipts which
# the matrix itself requires.
$matrixBindingRoot=Join-Path $testRoot 'matrix-direct-library-binding'
$matrixBindingRepo=Join-Path $matrixBindingRoot 'repo'
$matrixBindingLibrary=Join-Path $matrixBindingRoot 'flat-library'
$matrixBindingWork=Join-Path $matrixBindingRoot 'work'
$matrixBindingOutput=Join-Path $matrixBindingRoot 'matrix.json'
$resolvedTestRoot=[IO.Path]::GetFullPath($testRoot)
$resolvedMatrixBindingRoot=[IO.Path]::GetFullPath($matrixBindingRoot)
$matrixBindingRelative=[IO.Path]::GetRelativePath($resolvedTestRoot,$resolvedMatrixBindingRoot)
if([IO.Path]::IsPathRooted($matrixBindingRelative)-or$matrixBindingRelative-ceq'..'-or$matrixBindingRelative.StartsWith('..'+[IO.Path]::DirectorySeparatorChar)){
  throw 'Upgrade matrix controlled cleanup root escapes the owned test root'
}
New-Item -ItemType Directory -Force -Path (Join-Path $matrixBindingRepo 'tests/runtime'),(Join-Path $matrixBindingRepo 'tools/mir/application/release/readiness'),$matrixBindingLibrary,$matrixBindingWork|Out-Null
Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests/runtime/Test-MIRUpgradeMatrix.ps1') -Destination (Join-Path $matrixBindingRepo 'tests/runtime/Test-MIRUpgradeMatrix.ps1') -Force
[IO.File]::WriteAllText((Join-Path $matrixBindingRepo 'tools/mir/application/release/readiness/ResourceGovernor.ps1'),@'
function Resolve-MIR441RecoveryScratchPath { param([string]$Path) return $Path }
function Assert-MIR441ResourceAdmission { if($env:MIR_MATRIX_ALLOW_RESOURCE -ceq '1'){return $null}; throw '[matrix-test-resource-admission-called]' }
'@,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $matrixBindingRepo 'tests/runtime/Test-MIRUpgrade.ps1'),@'
param(
  [string]$RepoRoot,[string]$FactorioBin,[string]$FromZip,[string]$ToZip,[string]$FromVersion,[string]$ToVersion,
  [string[]]$LocalModLibraryDirs,[string]$FixtureName,[string]$Archetype,[string[]]$SourceOnlyFixtureNames,
  [string]$OutputPath,[string]$WorkRoot,[int]$ExpectedPeakMemoryMiB,[int]$MaxNewOutputMiB,[string]$Retention,
  [Parameter(ValueFromRemainingArguments=$true)]$Ignored
)
$bindingPath=Join-Path $WorkRoot ('binding-'+$Archetype+'.json')
[IO.File]::WriteAllText($bindingPath,([ordered]@{local_mod_library_dirs=@($LocalModLibraryDirs);archetype=$Archetype}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
$result=[ordered]@{schema=2;status='passed';archetype=$Archetype;assertions=@('upgraded-save-reload-passed','upgraded-save-second-reload-passed');second_reload_log='controlled-second.log';second_reload_log_sha256=('A'*64)}
[IO.File]::WriteAllText($OutputPath,($result|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
$cleanup=Join-Path (Split-Path -Parent $OutputPath) ($ToVersion+'-upgrade-'+$Archetype+'-cleanup.json')
[IO.File]::WriteAllText($cleanup,([ordered]@{status='retained';run_status='passed';contained=$true;bytes=0}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
$global:LASTEXITCODE=0
'@,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $matrixBindingRoot 'factorio.exe'),'controlled-factorio',[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $matrixBindingRoot 'from.zip'),'controlled-from',[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $matrixBindingRoot 'to.zip'),'controlled-to',[Text.UTF8Encoding]::new($false))
$matrixPath=Join-Path $matrixBindingRepo 'tests/runtime/Test-MIRUpgradeMatrix.ps1'
$matrixBaseArgs=@{RepoRoot=$matrixBindingRepo;FactorioBin=(Join-Path $matrixBindingRoot 'factorio.exe');FromZip=(Join-Path $matrixBindingRoot 'from.zip');ToZip=(Join-Path $matrixBindingRoot 'to.zip');FromVersion='4.2.20002';ToVersion='4.3.20000';OutputPath=$matrixBindingOutput;WorkRoot=$matrixBindingWork;ExpectedPeakMemoryMiB=1;MaxNewOutputMiB=1;Retention='Always'}
$hadMatrixAllowResource=Test-Path Env:MIR_MATRIX_ALLOW_RESOURCE
$savedMatrixAllowResource=if($hadMatrixAllowResource){[string]$env:MIR_MATRIX_ALLOW_RESOURCE}else{''}
try {
  $missingLibraryRejected=$false
  try { & $matrixPath @matrixBaseArgs | Out-Null } catch { $missingLibraryRejected=$_.Exception.Message-ceq'[mir-upgrade-matrix-library-required] Supply exactly one flat archive library; retired profile staging is unsupported.' }
  if(-not$missingLibraryRejected){throw 'Upgrade matrix admitted a missing direct-library input or reached resource admission first'}
  $env:MIR_MATRIX_ALLOW_RESOURCE='1'
  $matrixArgs=$matrixBaseArgs.Clone();$matrixArgs.LocalModLibraryDirs=@($matrixBindingLibrary)
  & $matrixPath @matrixArgs | Out-Null
  $bindings=@(Get-ChildItem -LiteralPath $matrixBindingWork -Filter 'binding-*.json' -File)
  if($bindings.Count-ne5){throw 'Upgrade matrix did not execute every controlled direct-library row'}
  foreach($bindingPath in $bindings){
    $binding=Get-Content -Raw -LiteralPath $bindingPath.FullName|ConvertFrom-Json -Depth 10
    if(@($binding.local_mod_library_dirs).Count-ne1-or[IO.Path]::GetFullPath([string]$binding.local_mod_library_dirs[0])-cne[IO.Path]::GetFullPath($matrixBindingLibrary)){throw 'Upgrade matrix did not forward the exact one-library direct input'}
  }
  $mir43Assertions+=2
} finally {
  if($hadMatrixAllowResource){$env:MIR_MATRIX_ALLOW_RESOURCE=$savedMatrixAllowResource}else{Remove-Item Env:MIR_MATRIX_ALLOW_RESOURCE -ErrorAction SilentlyContinue}
  if(Test-Path -LiteralPath $matrixBindingRoot){Remove-Item -LiteralPath $matrixBindingRoot -Recurse -Force}
}

[pscustomobject]@{status='passed';assertions=$assertions;maintenance422_manifest_assertions=$maintenance422Assertions;historical_transition_assertions=$historicalAssertions;k2_profile_transition_assertions=$k2Assertions;f200_bob_angel_upgrade_assertions=$f200BobAngelAssertions;current_package_input_mode_assertions=$currentAssertions;mir43_upgrade_assertions=$mir43Assertions;mir43_classic_snapshot_assertions=$mir43ClassicSnapshotAssertions;mir43_classic_snapshot_control_kind='synthetic-host-only-classic-disposition-controls-v1';mir43_classic_snapshot_native_engine_launched=$false;selected_targets=$manifest.targets.Count;actual_hotfix_archives=([bool]$SelectedManifestPath -and $manifest.kind -ceq 'MIR42FinalReleaseManifestV1');actual_private_candidate_archives=([bool]$SelectedManifestPath -and $construction);future_patch_metadata_fixture=$true;native_engine_launched=$false}|ConvertTo-Json
