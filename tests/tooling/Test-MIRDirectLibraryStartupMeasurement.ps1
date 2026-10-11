# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
$root=Join-Path $repo ('build/tmp/direct-library-startup-controls-'+[guid]::NewGuid().ToString('N'))
$assertions=0
function Assert-DirectStartup([bool]$Condition,[string]$Message){if(-not $Condition){throw "Direct-library startup controls: $Message"};$script:assertions++}
function Write-TestArchive([string]$Library,[string]$Version){
  $archive=Join-Path $Library ('more-infinite-research_'+$Version+'.zip')
  $zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
  try{
    $entry=$zip.CreateEntry('more-infinite-research_'+$Version+'/info.json')
    $writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false))
    try{$writer.Write((@{name='more-infinite-research';version=$Version;factorio_version='2.0';dependencies=@('base')}|ConvertTo-Json -Compress))}finally{$writer.Dispose()}
  }finally{$zip.Dispose()}
  return $archive
}
try{
  $library=Join-Path $root 'library';$data=Join-Path $root 'engine/data';[IO.Directory]::CreateDirectory($library)|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $data 'base'))|Out-Null
  [IO.File]::WriteAllText((Join-Path $data 'base/info.json'),(@{name='base';version='2.0.77';dependencies=@()}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  $published=Write-TestArchive -Library $library -Version '4.2.20002';$candidate=Write-TestArchive -Library $library -Version '4.2.20003'
  $publishedSha=Get-MIRImmutableInputSha256 -Path $published;$manifest=Join-Path $root 'mir-4.2.2.release.json'
  [IO.File]::WriteAllText($manifest,(@{release=@{source_version='4.2.2'};package_assets=@(@{target='f200';distribution_version='4.2.20002';sha256=$publishedSha})}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $template=Join-Path $root 'profile.json';[IO.File]::WriteAllText($template,(@{mods=@(@{name='base';version='2.0.77';enabled=$true},@{name='more-infinite-research';version='4.2.20002';enabled=$true})}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $publishedIdentity=Get-MIRDirectLibraryStartupArchive -Archive $published -LibraryDirectory $library;$candidateIdentity=Get-MIRDirectLibraryStartupArchive -Archive $candidate -LibraryDirectory $library
  Assert-DirectStartup ($publishedIdentity.version-ceq'4.2.20002'-and$candidateIdentity.version-ceq'4.2.20003') 'archive identities were not read from selected library bytes.'
  $publishedManifest=Assert-MIRDirectLibraryPublished422Manifest -ManifestPath $manifest -ExpectedSha256 (Get-MIRImmutableInputSha256 -Path $manifest) -PublishedArchive $publishedIdentity -Target f200
  Assert-DirectStartup ($publishedManifest.source_version-ceq'4.2.2'-and$publishedManifest.archive_sha256-ceq$publishedIdentity.sha256) 'published package was not authenticated against its explicit manifest hash.'
  $base=@(Read-MIRDirectLibraryStartupProfile -Path $template)
  Assert-DirectStartup ($base.Count-eq1-and$base[0].name-ceq'base') 'no-MIR profile did not remove only MIR.'
  $selection=Join-Path $root 'selection.json';Write-MIRDirectLibraryStartupProfile -Path $selection -BaseRows $base -MirArchive $candidateIdentity
  $selected=Get-Content -Raw -LiteralPath $selection|ConvertFrom-Json
  Assert-DirectStartup ((@($selected.mods|Where-Object {$_.enabled}).name-join'|')-ceq'base|more-infinite-research'-and(@($selected.mods|Where-Object name -CEQ 'more-infinite-research')[0].version-ceq'4.2.20003')) 'candidate selection was not explicitly version-pinned.'
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -MirArchive $candidateIdentity
  Assert-DirectStartup ($hashes.Count-eq1-and$hashes.ContainsKey('more-infinite-research_4.2.20003.zip')-and$hashes['more-infinite-research_4.2.20003.zip']-ceq$candidateIdentity.sha256) 'selected archive hash set is incomplete or mutable.'
  $outside=Join-Path $root 'outside.zip';Copy-Item -LiteralPath $candidate -Destination $outside
  $refused=$false;try{Get-MIRDirectLibraryStartupArchive -Archive $outside -LibraryDirectory $library|Out-Null}catch{$refused=$_.Exception.Message-ceq'[mir-direct-startup-archive-not-in-selected-library]'}
  Assert-DirectStartup $refused 'archive outside selected library was accepted.'
  # Startup logs omit Lua loading lines for asset-only packages. The explicit
  # observer is selected from the same hash-bound library transaction and its
  # full table remains exact; an altered observer report must fail closed.
  $observerName='mir423-startup-observer'
  $observerActivation=[pscustomobject]@{selected=@(
    [pscustomobject]@{name='base';version='2.0.77'},
    [pscustomobject]@{name=$observerName;version='1.0.0'}
  )}
  $observerLog=Join-Path $root 'observer.log'
  [IO.File]::WriteAllLines($observerLog,@(
    '0.1 Loading mod base 2.0.77 (data.lua)',
    ('0.2 Script @__'+$observerName+'__/data-final-fixes.lua:1: [MIR_ACTIVE_MODS] base@2.0.77|'+$observerName+'@1.0.0')
  ))
  $observerLoaded=@(Assert-MIRLibraryLoadedSelection -Activation $observerActivation -LogPath $observerLog -ActiveModsObserver $observerName)
  Assert-DirectStartup (($observerLoaded -join '|') -ceq ('base@2.0.77|'+$observerName+'@1.0.0')) 'asset-only observer did not establish the complete selected table.'
  [IO.File]::WriteAllLines($observerLog,@(
    '0.1 Loading mod base 2.0.77 (data.lua)',
    ('0.2 Script @__'+$observerName+'__/data-final-fixes.lua:1: [MIR_ACTIVE_MODS] base@2.0.77|'+$observerName+'@1.0.1')
  ))
  $observerRejected=$false
  try{Assert-MIRLibraryLoadedSelection -Activation $observerActivation -LogPath $observerLog -ActiveModsObserver $observerName|Out-Null}catch{$observerRejected=$_.Exception.Message-ceq'[mir-library-loaded-selection] Actual mod names/versions differ from the profile.'}
  Assert-DirectStartup $observerRejected 'mismatching observer table was accepted.'
  $source=Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
  Assert-DirectStartup ($source.Contains('Invoke-MIRNativeProbeFactorioProcess')-and$source.Contains('Add-MIRNativeProbeLibraryActivation')-and$source.Contains('changed-configuration')-and$source.Contains('same-selection')-and$source.Contains('prior_selection_label')-and$source.Contains('warm-repeat')-and$source.Contains('headless-create-diagnostic')-and$source.Contains('factorio-current.log')-and$source.Contains('ready-initialised')-and$source.Contains('ready-save-map-data')-and$source.Contains('-ActiveModsObserver $ActiveModsObserver')-and$source.Contains('active_mods_observer=$observerIdentity')-and$source.Contains('run_relative_path=[IO.Path]::GetRelativePath($Resources.root,$RunRoot)')-and-not$source.Contains('[Diagnostics.Process]::Start')) 'runner bypasses the governed native process actor, does not snapshot the actual engine log and validate the save endpoint, mislabels balanced cache state, or does not bind the asset-only observer.'
  $entry=Get-Content -Raw -LiteralPath (Join-Path $repo 'scripts/Measure-MIRPerformanceRegression.ps1')
  Assert-DirectStartup ($entry.Contains('Invoke-MIRDirectLibraryStartupMeasurement')-and$entry.Contains('ObserveStartup')-and$entry.Contains('ObserveResearchAll')-and$entry.Contains('ActiveModsObserver')-and$entry.Contains('ExpectedPeakMemoryMiB')-and$entry.Contains('mir-native-obsolete-runner')) 'performance entrypoint does not preserve the research-all and obsolete-campaign branches around direct-library measurement or forward the selected observer.'
  $accepted=@((Get-Command Read-MIRNativeProbeCurrentCandidate).Parameters['SourceVersion'].Attributes|Where-Object {$_ -is [Management.Automation.ValidateSetAttribute]}|ForEach-Object ValidValues)
  Assert-DirectStartup ('4.2.3'-in$accepted) 'native candidate reader rejects the 4.2.3 materialization identity.'
  . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
  $privateReadme=Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes ([Text.UTF8Encoding]::new($false).GetBytes('MIR package')) -DistributionVersion '4.2.20003' -SourceVersion '4.2.3'
  Assert-DirectStartup (([Text.UTF8Encoding]::new($false).GetString($privateReadme)).StartsWith("MIR 4.2.20003, source 4.2.3.`n`n",[StringComparison]::Ordinal)) 'materializer does not support private 4.2.3 package identity presentation.'
  [pscustomobject][ordered]@{status='MIR-DIRECT-LIBRARY-STARTUP-CONTROLS-PASSED';assertions=$assertions;engine_runs=0;archive_copies_created=0;archive_links_created=0;populated_profiles_created=0}
}finally{
  if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
