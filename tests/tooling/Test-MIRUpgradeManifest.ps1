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
# This metadata-only ZIP is controlled test input, never a release package.
[pscustomobject]@{status='passed';assertions=$assertions;selected_targets=9;actual_hotfix_archives=[bool]$SelectedManifestPath;future_patch_metadata_fixture=$true;native_engine_launched=$false}|ConvertTo-Json
