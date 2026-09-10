# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$CandidateZip='',
  [string]$OutputRoot='build/mir4/a05-k2-materials/k2-materials-runtime'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$generatedAt=(Get-Date).ToUniversalTime().ToString('o')
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
function Assert-A05K2([bool]$value,[string]$code){if(-not $value){throw "[mir4-a05-k2-materials] $code"}}
function Get-A05K2Sha([string]$path){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()}
function Get-A05K2Relative([string]$path){$full=[IO.Path]::GetFullPath($path);$prefix=$repo.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar;Assert-A05K2 $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) 'artifact-outside-repository';$full.Substring($prefix.Length).Replace('\','/')}
function Get-A05K2Artifact([string]$path){$item=Get-Item -LiteralPath $path;[pscustomobject][ordered]@{path=Get-A05K2Relative $item.FullName;bytes=[int64]$item.Length;raw_sha256=Get-A05K2Sha $item.FullName}}
Assert-A05K2 ((Get-A05K2Sha $engine) -ceq '710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8') 'engine-sha256'
Assert-A05K2 ((Get-Item -LiteralPath $engine).VersionInfo.ProductVersion -ceq '2.1.17') 'engine-version'
if([string]::IsNullOrWhiteSpace($CandidateZip)){
  . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
  $candidate=New-MIR4TargetPackage -RepoRoot $repo -Target f210 -CandidateId ('A05-K2-MATERIALS-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()) -SourceVersion '4.2.0' -DistributionVersion '4.2.21000' -OutputRoot 'build/mir4/a05-k2-materials/candidate'
  $CandidateZip=[string]$candidate.archive_path
}
$candidate=(Resolve-Path -LiteralPath $CandidateZip).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot));$outputPrefix=$output.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
Assert-A05K2 $output.StartsWith((Join-Path $repo 'build')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) 'output-outside-build'
$lockedSource=Join-Path $repo 'build/synthesis-20260906/k2-engine-candidate/runs/u-ad28370088e7/mods'
$currentSource=Join-Path $repo 'build/compat-mod-cache'
$common=@(
  [pscustomobject]@{name='flib_0.17.2.zip';sha256='0A48C15DC0FC6C13BB3FE8293BA6CB35A07F3B0F37D37ACB50AB30E32E8E019D'},
  [pscustomobject]@{name='k2so-assets_1.0.7.zip';sha256='C3E11214407B08120B2EE717405D3B0398F533647695AB2E6EF6DF9267D62017'},
  [pscustomobject]@{name='Krastorio2_2.1.2.zip';sha256='89989E60784EA3E94345289E063C64ABFCE5F35693DB7B9A69D656A163620F43'},
  [pscustomobject]@{name='Krastorio2Assets_2.1.0.zip';sha256='39EF950EC8B21A40357DD0240EF8389501EE75CCA82717F2773B98554DA46E29'},
  [pscustomobject]@{name='Krastorio2MenuSimulations_2.1.0.zip';sha256='3A485B449B356DC4B3EB4233DE4E803B3A001259FBC251BDC9F9D9120B3C53A7'},
  [pscustomobject]@{name='mir-validation-settings-overrides_0.1.0.zip';sha256='0A6AAA9E8D89DDCC9E421F8AB065124554531588C4E4F91EC5E4D52EC0E10E26'}
)
$progressMarkers=@(
  '[MIR4_A05_K2_MATERIAL_PROGRESS] force=mir-a05-k2-material-1;technology=recipe-prod-research_material_rare_metals-1;progress=0.42',
  '[MIR4_A05_K2_MATERIAL_PROGRESS] force=mir-a05-k2-material-2;technology=recipe-prod-research_material_silicon-1;progress=0.42',
  '[MIR4_A05_K2_MATERIAL_PROGRESS] force=mir-a05-k2-material-3;technology=recipe-prod-research_material_glass-1;progress=0.42'
)
$technologyMarkers=@(
  '[MIR4_A05_K2_MATERIAL_TECH] name=recipe-prod-research_material_rare_metals-1;effects=kr-rare-metals-from-enriched-rare-metals=0.02,kr-rare-metals=0.02;science=automation-science-pack,chemical-science-pack,logistic-science-pack;labs=biolab,kr-advanced-lab,kr-singularity-lab,lab',
  '[MIR4_A05_K2_MATERIAL_TECH] name=recipe-prod-research_material_silicon-1;effects=kr-silicon=0.02;science=automation-science-pack,logistic-science-pack;labs=biolab,kr-advanced-lab,kr-singularity-lab,lab',
  '[MIR4_A05_K2_MATERIAL_TECH] name=recipe-prod-research_material_glass-1;effects=kr-glass=0.02;science=automation-science-pack,chemical-science-pack,logistic-science-pack;labs=biolab,kr-advanced-lab,kr-singularity-lab,lab'
)
function Assert-A05K2Observation([string]$log,[string]$case){
  $text=[IO.File]::ReadAllText($log)
  foreach($marker in $technologyMarkers){Assert-A05K2 ($text.Contains($marker)) "$case-tech-owner-science:$marker"}
  Assert-A05K2 ($text.Contains('[MIR4_A05_K2_MATERIAL_ROUTE] rare=ore:2>rare:1;enriched:1>rare:1;silicon=quartz:18>silicon:9;glass=sand:16>glass:8;casting=dirty-water:ignored_by_productivity:5;black_paving=withheld-final-denial;white_paving=withheld-final-denial')) "$case-final-route-matrix"
  foreach($recipe in @('kr-rare-metals','kr-rare-metals-from-enriched-rare-metals','kr-silicon','kr-glass')){Assert-A05K2 ($text.Contains("Material route admitted recipe=$recipe reason=reviewed-forward-route:")) "$case-admission:$recipe"}
  Assert-A05K2 ($text.Contains('Material route omitted recipe=kr-casting-rare-metals reason=potential-return-path:water')) "$case-casting-graph-guard"
  foreach($stream in @('research_material_black_paving','research_material_white_paving')){Assert-A05K2 ($text.Contains("Skipping stream $stream because no_matching_recipes.")) "$case-paving-withheld:$stream"}
  $pavingMatches=@([regex]::Matches($text,'(?m)^.*\[MIR4_A05_K2_MATERIAL_PAVING_ROUTES\] (.+)$'))
  Assert-A05K2 ($pavingMatches.Count-eq1) "$case-paving-route-matrix-count"
  $pavingRoutes=@($pavingMatches[0].Groups[1].Value.Split(',')|Where-Object{$_})
  Assert-A05K2 ($pavingRoutes.Count-gt0 -and @($pavingRoutes|Where-Object{$_-notmatch'^[^|]+\|class=(?:manufacturing|recolor-return|recycling|crushing)\|permission=(?:nil|false)\|owner=\|in=[^|]*\|out=[^|]*$'}).Count-eq0) "$case-paving-route-matrix-shape"
  return $pavingRoutes
}
function Invoke-A05K2Case([string]$Id,[string]$K2SO,[string]$K2SOHash,[bool]$IncludeXy){
  $root=[IO.Path]::GetFullPath((Join-Path $output $Id));Assert-A05K2 $root.StartsWith($outputPrefix,[StringComparison]::OrdinalIgnoreCase) "$Id-output-containment";if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force};New-Item -ItemType Directory -Force -Path (Join-Path $root 'mods'),(Join-Path $root 'saves')|Out-Null
  $mods=Join-Path $root 'mods';$archives=@()
  foreach($entry in $common){$source=Join-Path $lockedSource $entry.name;Assert-A05K2 ((Get-A05K2Sha $source)-ceq $entry.sha256) "$Id-common:$($entry.name)";$destination=Join-Path $mods $entry.name;Copy-Item -LiteralPath $source -Destination $destination;$archives+=Get-A05K2Artifact $destination}
  Assert-A05K2 ((Get-A05K2Sha $K2SO)-ceq $K2SOHash) "$Id-k2so";$k2soDestination=Join-Path $mods (Split-Path -Leaf $K2SO);Copy-Item -LiteralPath $K2SO -Destination $k2soDestination;$archives+=Get-A05K2Artifact $k2soDestination
  if($IncludeXy){$xy=Join-Path $lockedSource 'xy-k2so-enhancements-nulls-fork_0.8.3.zip';Assert-A05K2 ((Get-A05K2Sha $xy)-ceq '930F43B96B04012FEF090C40D8B16A6B3F259D1713C86CF59DFF3E9A5A97E2BE') "$Id-xy";$xyDestination=Join-Path $mods (Split-Path -Leaf $xy);Copy-Item -LiteralPath $xy -Destination $xyDestination;$archives+=Get-A05K2Artifact $xyDestination}
  $candidateDestination=Join-Path $mods 'more-infinite-research_4.2.21000.zip';Copy-Item -LiteralPath $candidate -Destination $candidateDestination
  $fixture=Publish-MIRModDirectoryArchive -Source (Join-Path $repo 'fixtures/assert-k2-materials') -Name 'mir-fixture-assert-k2-materials' -Version '0.1.0' -ModsDir $mods
  $enabled=@('base','elevated-rails','quality','recycler','space-age','flib','k2so-assets','Krastorio2','Krastorio2-spaced-out','Krastorio2Assets','Krastorio2MenuSimulations','mir-validation-settings-overrides','more-infinite-research');if($IncludeXy){$enabled+='xy-k2so-enhancements-nulls-fork'};$enabled+='mir-fixture-assert-k2-materials';$list=[ordered]@{mods=@($enabled|ForEach-Object{[ordered]@{name=$_;enabled=$true}})};[IO.File]::WriteAllText((Join-Path $mods 'mod-list.json'),(($list|ConvertTo-Json -Depth 10)+"`n"),[Text.UTF8Encoding]::new($false));$settings=Join-Path $lockedSource 'mod-settings.dat';Copy-Item -LiteralPath $settings -Destination (Join-Path $mods 'mod-settings.dat')
  $load=Invoke-MIRFactorioLoadCheck -FactorioBin $engine -UserDataDir $root -ScenarioName $Id -ScenarioTimeoutSeconds 300;Assert-A05K2 ($load.passed -and -not $load.timed_out -and $load.exit_code -eq 0) "$Id-load";Assert-A05K2 ($load.stderr_sha256-ceq 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855') "$Id-stderr";$pavingRoutes=Assert-A05K2Observation $load.factorio_log $Id
  $reload=Invoke-MIRFactorioReloadContract -FactorioBin $engine -UserDataDir $root -ScenarioName $Id -SavePath $load.save -RequiredReloadCount 2 -MaxReloadDurationSeconds 300 -RequiredLogFragments $progressMarkers;Assert-A05K2 ([bool]$reload.passed) "$Id-reloads"
  [pscustomobject][ordered]@{id=$Id;k2so=[ordered]@{archive_sha256=$K2SOHash;version=if($K2SO-match '_([0-9]+[.][0-9]+[.][0-9]+)[.]zip$'){$matches[1]}else{''}};xy_enabled=$IncludeXy;fresh_load=[ordered]@{passed=$true;save=Get-A05K2Artifact $load.save;stdout=Get-A05K2Artifact $load.stdout;stderr=Get-A05K2Artifact $load.stderr;factorio_log=Get-A05K2Artifact $load.factorio_log};reloads=$reload;mod_archives=@($archives|Sort-Object path);fixture=Get-A05K2Artifact $fixture;candidate=Get-A05K2Artifact $candidateDestination;mod_list=Get-A05K2Artifact (Join-Path $mods 'mod-list.json');mod_settings=Get-A05K2Artifact (Join-Path $mods 'mod-settings.dat');paving_routes=@($pavingRoutes)}
}
$locked=Invoke-A05K2Case -Id 'locked-2.0.13' -K2SO (Join-Path $lockedSource 'Krastorio2-spaced-out_2.0.13.zip') -K2SOHash 'A2EEB2E5A6119C4117BD3653979D40D305D17539E184BFA6F4ED53EF12A5F242' -IncludeXy $true
$current=Invoke-A05K2Case -Id 'current-2.0.17' -K2SO (Join-Path $currentSource 'Krastorio2-spaced-out_2.0.17.zip') -K2SOHash '0D48E22858FB4D1259413B65FFA7E5A0C5B5C2439A4918D58BDACC9411FA9284' -IncludeXy $false
$fixtureArtifacts=@(
  Get-A05K2Artifact (Join-Path $repo 'fixtures/assert-k2-materials/info.json')
  Get-A05K2Artifact (Join-Path $repo 'fixtures/assert-k2-materials/data-final-fixes.lua')
  Get-A05K2Artifact (Join-Path $repo 'fixtures/assert-k2-materials/control.lua')
)
$result=[ordered]@{schema=1;kind='MIR4A05K2MaterialsRuntimeResultV1';generated_at=$generatedAt;engine=[ordered]@{version='2.1.17';executable_sha256=Get-A05K2Sha $engine};candidate=Get-A05K2Artifact $candidate;fixture=$fixtureArtifacts;locked=$locked;current=$current;non_claims=@('Casting remains withheld because its final dirty-water result has ignored_by_productivity=5.','Black and white paving remain withheld by final productivity denial.','This finite three-tier evidence does not establish an infinite continuation or authorize release.')}
$resultPath=Join-Path $output 'result.json';[IO.File]::WriteAllText($resultPath,(ConvertTo-Json $result -Depth 100 -Compress),[Text.UTF8Encoding]::new($false));Write-Host "[MIR4_A05_K2_MATERIALS_RUNTIME] $(Get-A05K2Relative $resultPath)"