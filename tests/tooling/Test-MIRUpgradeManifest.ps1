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
  $zip=Join-Path (Split-Path $manifestPath -Parent) $row.filename
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
# This metadata-only ZIP is controlled test input, never a release package.
[pscustomobject]@{status='passed';assertions=$assertions;historical_transition_assertions=$historicalAssertions;selected_targets=9;actual_hotfix_archives=[bool]$SelectedManifestPath;future_patch_metadata_fixture=$true;native_engine_launched=$false}|ConvertTo-Json
