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
$completeCatalogueAssignments=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.AssignmentStatementAst]-and$node.Left.Extent.Text-ceq'$requiresCompleteCatalogue'},$true))
if($completeCatalogueAssignments.Count-ne1){throw 'Complete-catalogue applicability assignment missing or ambiguous'}
$completeCatalogueMarkerCalls=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.CommandAst]-and$node.GetCommandName()-ceq'Assert-MIR42CompleteCatalogueUpgradeMarker'},$true))
if($completeCatalogueMarkerCalls.Count-ne3){throw 'Complete-catalogue marker must be enforced for upgrade and both reloads'}
$snapshotRetainerFunctions=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Copy-MIRCompleteCatalogueSnapshotEvidence'},$true))
if($snapshotRetainerFunctions.Count-ne1){throw 'Complete-catalogue snapshot retainer missing or ambiguous'}
$completeCatalogueEvaluator=[scriptblock]::Create($completeCatalogueAssignments[0].Right.Extent.Text)
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
foreach($target in @('f210','f200','f110','f100','f017','f016','f015','f014','f013')){
  $isHistorical=$target-cin@('f017','f016','f015','f014','f013')
  foreach($patch in @(0,1,2)){
    $SourceVersion='4.2.3';$SpaceIsFake=$false;$k2Scenario=$false
    $mir42UpgradeSpecialized=-not$isHistorical;$isHistoricalTerminalFixture=$isHistorical
    $Archetype=if($target-ceq'f210'){'space-age-native-owner'}elseif(-not$isHistorical){'base-default'}else{''}
    $requiresCompleteCatalogue=& $completeCatalogueEvaluator
    if(-not$requiresCompleteCatalogue){throw "4.2.3 complete-catalogue gate is absent for $target predecessor $patch"}
    $currentAssertions++
  }
}
foreach($excluded in @('SpaceIsFake','k2Scenario','Archetype','SourceVersion')){
  $SourceVersion='4.2.3';$SpaceIsFake=$false;$k2Scenario=$false;$mir42UpgradeSpecialized=$true;$isHistoricalTerminalFixture=$false;$Archetype='base-default'
  switch($excluded){'SpaceIsFake'{$SpaceIsFake=$true};'k2Scenario'{$k2Scenario=$true};'Archetype'{$Archetype='unsupported'};'SourceVersion'{$SourceVersion='4.2.1'}}
  if(& $completeCatalogueEvaluator){throw "Complete-catalogue gate accepted excluded $excluded scenario"}
  $currentAssertions++
}
$SourceVersion='4.2.3';$SpaceIsFake=$false;$k2Scenario=$false;$mir42UpgradeSpecialized=$true;$isHistoricalTerminalFixture=$false;$Archetype='f200-bob-angel'
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
foreach($field in @('Target','FromVersion','ToVersion','FixtureName','Archetype','SpaceIsFake','SourceOnlyFixtureNames','K2ImersiteInputProfile','F200BobAngelInputProfile','SourceVersion')){
  $bad=$currentBobAngel.Clone();$bad[$field]=switch($field){'SpaceIsFake'{$true};'SourceOnlyFixtureNames'{@('extra')};'K2ImersiteInputProfile'{'k2.json'};'F200BobAngelInputProfile'{''};'SourceVersion'{'4.2.2'};default{'wrong'}}
  $rejected=$false;try{Assert-MIR421CurrentUpgradeInputMode @bad}catch{$rejected=$_.Exception.Message -match '^\[mir42(?:1|3)-'}
  if(-not$rejected){throw "Bob/Angel current-package mode accepted invalid $field"};$f200BobAngelAssertions++
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
  foreach($SourceVersion in @('4.2.1','4.2.2','4.2.3')){
    $SelectedTarget='f210';$to='selected.zip';$SourceMaterializationPath='selected-receipt.json'
    $FromVersion=if($SourceVersion-ceq'4.2.3'){'4.2.21002'}elseif($SourceVersion-ceq'4.2.2'){'4.2.21001'}else{'4.2.21000'}
    $ToVersion=if($SourceVersion-ceq'4.2.3'){'4.2.21003'}elseif($SourceVersion-ceq'4.2.2'){'4.2.21002'}else{'4.2.21001'}
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
[pscustomobject]@{status='passed';assertions=$assertions;maintenance422_manifest_assertions=$maintenance422Assertions;historical_transition_assertions=$historicalAssertions;k2_profile_transition_assertions=$k2Assertions;f200_bob_angel_upgrade_assertions=$f200BobAngelAssertions;current_package_input_mode_assertions=$currentAssertions;selected_targets=$manifest.targets.Count;actual_hotfix_archives=([bool]$SelectedManifestPath -and $manifest.kind -ceq 'MIR42FinalReleaseManifestV1');actual_private_candidate_archives=([bool]$SelectedManifestPath -and $construction);future_patch_metadata_fixture=$true;native_engine_launched=$false}|ConvertTo-Json
