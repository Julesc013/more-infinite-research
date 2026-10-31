[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Prepare','Run')][string]$Mode,
  [Parameter(Mandatory)][string]$ArchiveLibrary,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$MIRArchive,
  [Parameter(Mandatory)][string]$APIBetaArchive,
  [Parameter(Mandatory)][string]$InputRoot,
  [Parameter(Mandatory)][string]$OutputRoot,
  [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedPlanSha256,
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/compatibility/NativeArchiveLease.ps1')

function Assert-Preview([bool]$Condition,[string]$Message) { if(-not $Condition){throw "[mir-library-restoration-preview] $Message"} }
function Get-PreviewGitBytes([string]$Revision,[string]$Path) {
  $start=[Diagnostics.ProcessStartInfo]::new()
  $start.FileName='git';$start.UseShellExecute=$false;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  foreach($argument in @('-C',$repo,'show',($Revision+':'+$Path))){$null=$start.ArgumentList.Add($argument)}
  $process=[Diagnostics.Process]::new();$process.StartInfo=$start
  Assert-Preview ($process.Start()) "git show could not start for $Path"
  $stream=[IO.MemoryStream]::new()
  try {
    $process.StandardOutput.BaseStream.CopyTo($stream)
    $errorText=$process.StandardError.ReadToEnd()
    $process.WaitForExit()
    Assert-Preview ($process.ExitCode-eq0) "committed fixture member is unavailable: $Path $errorText"
    return ,$stream.ToArray()
  } finally { $stream.Dispose();$process.Dispose() }
}
function Get-PreviewArchiveInfo([string]$Path,[string]$Name,[string]$Version,[string]$FactorioLine) {
  $zip=[IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entry=$zip.GetEntry($Name+'_'+$Version+'/info.json')
    Assert-Preview ($null-ne$entry-and$entry.Length-le64KB) "archive metadata is missing or oversized: $([IO.Path]::GetFileName($Path))"
    $reader=[IO.StreamReader]::new($entry.Open())
    try {$info=$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable} finally {$reader.Dispose()}
    Assert-Preview ([string]$info.name-ceq$Name-and[string]$info.version-ceq$Version-and[string]$info.factorio_version-ceq$FactorioLine) "archive identity differs: $([IO.Path]::GetFileName($Path))"
    return $info
  } finally {$zip.Dispose()}
}
function Get-PreviewLibraryState([string]$Library,[string[]]$Names) {
  return @($Names|ForEach-Object {
    $path=Join-Path $Library $_
    if(Test-Path -LiteralPath $path){
      if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir-library-restoration-preview] direct archive is not a flat file: $_"}
      Assert-MIRLibraryPath $path
      [ordered]@{name=$_;exists=$true;bytes=[long](Get-Item -LiteralPath $path).Length;sha256=(Get-MIRImmutableInputSha256 -Path $path);identity=(Get-MIRImmutableInputFileIdentity -Path $path)}
    } else {[ordered]@{name=$_;exists=$false;bytes=0;sha256='';identity=''}}
  })
}
function Get-PreviewControls([string]$Library) {
  return @(@('mod-list.json','mod-settings.dat')|ForEach-Object {
    $path=Join-Path $Library $_
    if(Test-Path -LiteralPath $path){
      if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir-library-restoration-preview] library control is not a file: $_"}
      Assert-MIRLibraryPath $path
      [ordered]@{name=$_;exists=$true;bytes=[long](Get-Item -LiteralPath $path).Length;sha256=(Get-MIRImmutableInputSha256 -Path $path)}
    } else {[ordered]@{name=$_;exists=$false;bytes=0;sha256=''}}
  })
}
function Assert-PreviewBuildPath([string]$Path,[string]$Context) {
  $full=[IO.Path]::GetFullPath($Path)
  $allowedRoots=if($Context-ceq'InputRoot'){@([IO.Path]::GetFullPath((Join-Path $repo 'build/qualification')).TrimEnd('\','/'))}
    elseif($Context-ceq'OutputRoot'){@([IO.Path]::GetFullPath((Join-Path $repo 'build/tmp')).TrimEnd('\','/'),[IO.Path]::GetFullPath((Join-Path $repo 'build/p')).TrimEnd('\','/'))}
    else{throw "Unknown preview path context: $Context"}
  $buildRoot=$null
  foreach($candidateRoot in $allowedRoots){
    if($full.StartsWith($candidateRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){$buildRoot=$candidateRoot;break}
  }
  if(-not$buildRoot){
    $allowedText=if($Context-ceq'InputRoot'){'build/qualification'}else{'build/tmp or build/p'}
    throw "$Context must be a unique path below ${allowedText}: $full"
  }
  $existingTarget=Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
  if($null-ne$existingTarget){
    if(-not$existingTarget.PSIsContainer){throw "$Context must be a directory when it already exists: $full"}
    Assert-MIRLibraryPath $full
  }
  $parent=[IO.Path]::GetDirectoryName($full)
  while($parent -and $parent.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){
    if(Test-Path -LiteralPath $parent -PathType Container){Assert-MIRLibraryPath $parent}
    if($parent -ceq $buildRoot){break}
    $parent=[IO.Path]::GetDirectoryName($parent)
  }
  return $full
}
function Assert-PreviewRootsDisjoint([string]$InputRoot,[string]$OutputRoot) {
  $inputFull=[IO.Path]::GetFullPath($InputRoot).TrimEnd('\','/')
  $outputFull=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\','/')
  $separator=[IO.Path]::DirectorySeparatorChar
  $inputPrefix=$inputFull+$separator
  $outputPrefix=$outputFull+$separator
  if($inputFull-ceq$outputFull -or
     $inputFull.StartsWith($outputPrefix,[StringComparison]::OrdinalIgnoreCase) -or
     $outputFull.StartsWith($inputPrefix,[StringComparison]::OrdinalIgnoreCase)) {
    throw '[mir-library-restoration-preview] prepared input and native output roots must be separate, non-nested directories'
  }
}

$profile=Join-Path $repo 'tests/profiles/library-restoration-cfeac3-space-age-standalone-f210-2123.json'
$profileHash=(Get-MIRImmutableInputSha256 -Path $profile)
$profileDefinition=Get-Content -LiteralPath $profile -Raw -Encoding UTF8|ConvertFrom-Json -AsHashtable
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$library=(Resolve-Path -LiteralPath $ArchiveLibrary).Path
$mir=(Resolve-Path -LiteralPath $MIRArchive).Path
$apiBeta=(Resolve-Path -LiteralPath $APIBetaArchive).Path
$inputRoot=Assert-PreviewBuildPath -Path $InputRoot -Context 'InputRoot'
$outputRoot=Assert-PreviewBuildPath -Path $OutputRoot -Context 'OutputRoot'
Assert-PreviewRootsDisjoint -InputRoot $inputRoot -OutputRoot $outputRoot
$engineSha=(Get-MIRImmutableInputSha256 -Path $engine)
$sourceHeadRows=@(& git -C $repo rev-parse --verify 'HEAD^{commit}')
Assert-Preview ($LASTEXITCODE-eq0-and$sourceHeadRows.Count-eq1-and[string]$sourceHeadRows[0]-cmatch'^[0-9a-f]{40}$') 'source HEAD is not one committed revision'
$sourceHead=[string]$sourceHeadRows[0]
$treeRows=@(& git -C $repo rev-parse --verify 'HEAD^{tree}')
Assert-Preview ($LASTEXITCODE-eq0-and$treeRows.Count-eq1-and[string]$treeRows[0]-cmatch'^[0-9a-f]{40}$') 'source tree identity differs'
$tree=[string]$treeRows[0]
$dirty=@(& git -C $repo status --porcelain --untracked-files=all)
Assert-Preview ($LASTEXITCODE-eq0-and$dirty.Count-eq0) 'source checkout must be clean before input preparation or dispatch'
Assert-Preview ($profileDefinition.kind-ceq'mir5-library-restoration-cfeac3-space-age-standalone-f210-native-selection' -and
  $profileDefinition.target-ceq'f210-standalone' -and $profileDefinition.engine.version-ceq'2.1.23' -and
  $profileDefinition.engine.sha256-ceq'8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38' -and
  $profileDefinition.archive_sha256['more-infinite-research_5.0.21000.zip']-ceq'1EF57E3ACD05BE9B1097AC3744C913933A7784FE6513F12C2771B0096CDB2029' -and
  $profileDefinition.archive_sha256['mir-fixture-mir5-api-beta_0.1.0.zip']-ceq'0E48351A5D515506B133ED16FE265119D72EB781FA2A4473D1771C451C3EB633') 'fixed F210 Space Age profile differs'
Assert-Preview ($engineSha-ceq[string]$profileDefinition.engine.sha256) 'engine SHA-256 differs from the profile'
Assert-Preview ($engine-ceq'D:\Games\Factorio\2.1\bin\x64\factorio.exe') 'only the declared standalone engine is admitted'
Assert-Preview ($library-ceq'D:\Projects\Factorio\testmods\2.1') 'only the declared direct mod library is admitted'
Assert-Preview ((Get-MIRImmutableInputSha256 -Path $mir)-ceq[string]$profileDefinition.archive_sha256['more-infinite-research_5.0.21000.zip']) 'candidate player archive differs from its exact profile pin'
Assert-Preview ((Get-MIRImmutableInputSha256 -Path $apiBeta)-ceq[string]$profileDefinition.archive_sha256['mir-fixture-mir5-api-beta_0.1.0.zip']) 'candidate API beta archive differs from its exact profile pin'
$null=Get-PreviewArchiveInfo -Path $mir -Name 'more-infinite-research' -Version '5.0.21000' -FactorioLine '2.1'
$null=Get-PreviewArchiveInfo -Path $apiBeta -Name 'mir-fixture-mir5-api-beta' -Version '0.1.0' -FactorioLine '2.1'
$runtimeMembers=@('control.lua','settings-updates.lua','info.json')
$fixtureName='mir-fixture-mir5-library-multiplayer';$fixtureVersion='0.3.0'
$expectedTreeMembers=@('README.md','control.lua','info-f210-private-credits.json','info-f210-space-age.json','info-f210.json','info.json','settings-updates.lua')
$gitMembers=@(& git -C $repo ls-tree -r --name-only $sourceHead -- 'tests/fixtures/library-multiplayer')
$fixturePrefix='tests/fixtures/library-multiplayer/'
Assert-Preview ($LASTEXITCODE-eq0-and$gitMembers.Count-eq$expectedTreeMembers.Count-and
  (@($gitMembers|ForEach-Object {Assert-Preview ($_.StartsWith($fixturePrefix,[StringComparison]::Ordinal)) 'committed Library fixture path differs';$_.Substring($fixturePrefix.Length)}|Sort-Object)-join'|')-ceq(@($expectedTreeMembers|Sort-Object)-join'|')) 'committed Library fixture members differ'
$metadataBytes=Get-PreviewGitBytes -Revision $sourceHead -Path 'tests/fixtures/library-multiplayer/info-f210-private-credits.json'
$metadata=[Text.Encoding]::UTF8.GetString($metadataBytes)|ConvertFrom-Json -AsHashtable
Assert-Preview ([string]$metadata.name-ceq$fixtureName-and[string]$metadata.version-ceq$fixtureVersion-and[string]$metadata.factorio_version-ceq'2.1' -and
  ((@($metadata.dependencies)-join'|')-ceq'base >= 2.1.23|? space-age >= 2.1.23|more-infinite-research = 5.0.21000')) 'private-credit fixture metadata differs'
$fixtureInfoBytes=Get-PreviewGitBytes -Revision $sourceHead -Path 'tests/fixtures/library-multiplayer/info-f210-private-credits.json'
$fixtureControlBytes=Get-PreviewGitBytes -Revision $sourceHead -Path 'tests/fixtures/library-multiplayer/control.lua'
$fixtureSettingsBytes=Get-PreviewGitBytes -Revision $sourceHead -Path 'tests/fixtures/library-multiplayer/settings-updates.lua'
$fixtureArchive=Join-Path $inputRoot ($fixtureName+'_'+$fixtureVersion+'.zip')
$sourceRows=@(
  [ordered]@{source='tests/fixtures/library-multiplayer/control.lua';path='control.lua';bytes=$fixtureControlBytes},
  [ordered]@{source='tests/fixtures/library-multiplayer/info-f210-private-credits.json';path='info.json';bytes=$fixtureInfoBytes},
  [ordered]@{source='tests/fixtures/library-multiplayer/settings-updates.lua';path='settings-updates.lua';bytes=$fixtureSettingsBytes}
)

if($Mode-ceq'Prepare'){
  Assert-Preview (-not(Test-Path -LiteralPath $inputRoot) -and -not(Test-Path -LiteralPath $outputRoot)) 'preparation input/output destinations already exist'
  $null=[IO.Directory]::CreateDirectory($inputRoot)
  $stream=[IO.File]::Open($fixtureArchive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{
    $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
    try{
      foreach($row in $sourceRows){
        $entry=$zip.CreateEntry($fixtureName+'_'+$fixtureVersion+'/'+$row.path,[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime=[DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero);$entry.ExternalAttributes=0
        $entryStream=$entry.Open();try{$entryStream.Write($row.bytes,0,$row.bytes.Length)}finally{$entryStream.Dispose()}
      }
    }finally{$zip.Dispose()}
  }finally{$stream.Dispose()}
  $fixtureSha=Get-MIRImmutableInputSha256 -Path $fixtureArchive
  $fixtureZip=[IO.Compression.ZipFile]::OpenRead($fixtureArchive)
  try{
    $entryNames=@($fixtureZip.Entries|ForEach-Object {$_.FullName})
    $expectedNames=@($runtimeMembers|ForEach-Object {$fixtureName+'_'+$fixtureVersion+'/'+$_})
    Assert-Preview ($entryNames.Count-eq$expectedNames.Count-and((@($entryNames|Sort-Object)-join'|')-ceq(@($expectedNames|Sort-Object)-join'|'))) 'generated fixture member set differs'
    foreach($row in $sourceRows){
      $entry=$fixtureZip.GetEntry($fixtureName+'_'+$fixtureVersion+'/'+$row.path)
      $entryStream=$entry.Open();try{$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($entryStream))}finally{$entryStream.Dispose()}
      $expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([byte[]]$row.bytes))
      Assert-Preview ($sha-ceq$expected) "generated fixture member bytes differ: $($row.path)"
    }
  }finally{$fixtureZip.Dispose()}
  $beforeNames=@($profileDefinition.archive_sha256.Keys)+@($fixtureName+'_0.3.0.zip')
  $before=Get-PreviewLibraryState -Library $library -Names $beforeNames
  foreach($fixed in @(
    [ordered]@{name='mir-fixture-mir5-active-mods-observer_0.1.0.zip';sha='A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0'},
    [ordered]@{name='mir-fixture-mir5-api-alpha_0.1.0.zip';sha='DB5ED843FA9D85A1ABDC22595E62D315CA1A2191C846208079F85D4D016CE904'}
  )){
    $row=@($before|Where-Object name -CEQ $fixed.name)
    Assert-Preview ($row.Count-eq1-and$row[0].exists-and$row[0].sha256-ceq$fixed.sha) "direct dependency archive differs: $($fixed.name)"
  }
  $controls=Get-PreviewControls -Library $library
  $leaseSources=@(
    [ordered]@{file_name='more-infinite-research_5.0.21000.zip';source_path=$mir;sha256=[string]$profileDefinition.archive_sha256['more-infinite-research_5.0.21000.zip']},
    [ordered]@{file_name='mir-fixture-mir5-api-beta_0.1.0.zip';source_path=$apiBeta;sha256=[string]$profileDefinition.archive_sha256['mir-fixture-mir5-api-beta_0.1.0.zip']},
    [ordered]@{file_name=$fixtureName+'_0.3.0.zip';source_path=$fixtureArchive;sha256=$fixtureSha}
  )
  $record=[ordered]@{
    schema=1;kind='MIRLibraryRestorationPreviewPreparedV1';status='prepared-no-native-execution'
    source=[ordered]@{commit=$sourceHead;tree=$tree;working_tree_clean=$true}
    engine=[ordered]@{path=$engine;sha256=$engineSha;version=[string]$profileDefinition.engine.version}
    profile=[ordered]@{path='tests/profiles/library-restoration-cfeac3-space-age-standalone-f210-2123.json';sha256=$profileHash}
    package=[ordered]@{path=$mir;sha256=[string]$profileDefinition.archive_sha256['more-infinite-research_5.0.21000.zip']}
    api_beta=[ordered]@{path=$apiBeta;sha256=[string]$profileDefinition.archive_sha256['mir-fixture-mir5-api-beta_0.1.0.zip']}
    library_fixture=[ordered]@{path=$fixtureArchive;sha256=$fixtureSha;source_revision=$sourceHead;members=@($sourceRows|ForEach-Object {[ordered]@{source=$_.source;path=$_.path;sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([byte[]]$_.bytes))}})}
    direct_library=[ordered]@{path=$library;archives=$before;controls=$controls}
    fixture_sources=@('tests/fixtures/library-multiplayer','tests/fixtures/active-mods-observer','tests/fixtures/api-alpha','tests/fixtures/api-beta')
    output_root=$outputRoot;input_root=$inputRoot;endpoint='process start to two-client Library ready witness';launch_count=0
    harness_sha256=[ordered]@{
      caller=(Get-MIRImmutableInputSha256 -Path $PSCommandPath)
      runner=(Get-MIRImmutableInputSha256 -Path (Join-Path $repo 'tools/Invoke-MultiplayerFixture.ps1'))
      lease=(Get-MIRImmutableInputSha256 -Path (Join-Path $repo 'tools/lib/compatibility/NativeArchiveLease.ps1'))
    }
    native_execution=$false;release_qualification=$false;visual_review=$false
  }
  $planPath=Join-Path $inputRoot 'preview-input-plan.json'
  [IO.File]::WriteAllText($planPath,(($record|ConvertTo-Json -Depth 20)+"`n"),[Text.UTF8Encoding]::new($false))
  $planSha=Get-MIRImmutableInputSha256 -Path $planPath
  [pscustomobject]@{kind='MIRLibraryRestorationPreviewPlanIdentityV1';path=$planPath;sha256=$planSha;source_head=$sourceHead;fixture_archive_sha256=$fixtureSha;native_execution=$false;release_qualification=$false}
  return
}

Assert-Preview ($ExpectedPlanSha256-cmatch'^[A-Fa-f0-9]{64}$') 'Run requires the reviewed plan SHA-256'
$planPath=Join-Path $inputRoot 'preview-input-plan.json'
Assert-Preview (Test-Path -LiteralPath $planPath -PathType Leaf) 'prepared input plan is missing'
Assert-Preview ((Get-MIRImmutableInputSha256 -Path $planPath)-ceq$ExpectedPlanSha256.ToUpperInvariant()) 'prepared plan identity differs'
$plan=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8|ConvertFrom-Json -AsHashtable
Assert-Preview ($plan.kind-ceq'MIRLibraryRestorationPreviewPreparedV1'-and$plan.status-ceq'prepared-no-native-execution' -and
  $plan.source.commit-ceq$sourceHead-and$plan.source.tree-ceq$tree-and$plan.native_execution-eq$false-and$plan.release_qualification-eq$false) 'prepared plan source or boundary differs'
Assert-Preview ([IO.Path]::GetFullPath([string]$plan.output_root)-ceq$outputRoot-and[IO.Path]::GetFullPath([string]$plan.input_root)-ceq$inputRoot) 'prepared output roots differ'
Assert-Preview ([string]$plan.profile.sha256-ceq$profileHash-and[IO.Path]::GetFullPath([string]$plan.package.path)-ceq$mir-and
  [IO.Path]::GetFullPath([string]$plan.api_beta.path)-ceq$apiBeta-and[IO.Path]::GetFullPath([string]$plan.library_fixture.path)-ceq$fixtureArchive) 'prepared artifact locators differ'
Assert-Preview (-not(Test-Path -LiteralPath $outputRoot)) 'native output root already exists'
Assert-Preview ((Get-MIRImmutableInputSha256 -Path $mir)-ceq[string]$plan.package.sha256-and(Get-MIRImmutableInputSha256 -Path $apiBeta)-ceq[string]$plan.api_beta.sha256) 'prepared candidate archives changed'
Assert-Preview ((Get-MIRImmutableInputSha256 -Path $fixtureArchive)-ceq[string]$plan.library_fixture.sha256) 'prepared Library fixture archive changed'
$currentBefore=Get-PreviewLibraryState -Library $library -Names @($plan.direct_library.archives|ForEach-Object {[string]$_.name})
$currentArchiveJson=ConvertTo-Json -InputObject @($currentBefore) -Depth 8 -Compress
$plannedArchiveJson=ConvertTo-Json -InputObject @($plan.direct_library.archives) -Depth 8 -Compress
$currentControlJson=ConvertTo-Json -InputObject @(Get-PreviewControls -Library $library) -Depth 8 -Compress
$plannedControlJson=ConvertTo-Json -InputObject @($plan.direct_library.controls) -Depth 8 -Compress
Assert-Preview ($currentArchiveJson-ceq$plannedArchiveJson-and$currentControlJson-ceq$plannedControlJson) 'direct library or controls changed since preparation'

$leaseSources=@(
  [ordered]@{file_name='more-infinite-research_5.0.21000.zip';source_path=$mir;sha256=[string]$plan.package.sha256},
  [ordered]@{file_name='mir-fixture-mir5-api-beta_0.1.0.zip';source_path=$apiBeta;sha256=[string]$plan.api_beta.sha256},
  [ordered]@{file_name=$fixtureName+'_0.3.0.zip';source_path=$fixtureArchive;sha256=[string]$plan.library_fixture.sha256}
)
$result=[ordered]@{schema=1;kind='MIRLibraryRestorationPreviewNativeResultV1';status='started';plan_sha256=$ExpectedPlanSha256.ToUpperInvariant();source_head=$sourceHead;engine=$plan.engine;profile=$plan.profile;runner_invoked=$false;native_execution_succeeded=$false;release_qualification=$false;visual_review=$false;archive_lease=$null;runner_status=$null;failure=$null}
$lease=$null;$failure=$null
try{
  $lease=Start-MIRNativeArchiveLease -LibraryDirectory $library -OutputRoot $inputRoot -ArchiveSources $leaseSources
  $runner=Join-Path $repo 'tools/Invoke-MultiplayerFixture.ps1'
  $fixtureSources=@(
    (Join-Path $repo 'tests/fixtures/library-multiplayer'),
    (Join-Path $repo 'tests/fixtures/active-mods-observer'),
    (Join-Path $repo 'tests/fixtures/api-alpha'),
    (Join-Path $repo 'tests/fixtures/api-beta')
  )
  $result.runner_invoked=$true
  $runnerResult=& $runner -ArchiveLibrary $library -FactorioBin $engine -ProfilePath $profile -FixtureSources $fixtureSources `
    -ExpectedMIRArchiveSha256 ([string]$plan.package.sha256) -OutputRoot $outputRoot -FixtureCase 'library-multiplayer' `
    -SessionExpectedPeakMemoryMiB 8192 -RepoRoot $repo
  $result.runner_status=[string]$runnerResult.status
  Assert-Preview ($result.runner_status-ceq'passed-private-two-client-fixture') 'native wrapper did not report the expected private preview status'
  $result.native_execution_succeeded=$true
  $result.status='completed-private-preview'
}catch{$failure=$_.Exception;$result.failure=$_.Exception.Message;$result.status='failed'}
finally{
  if($null-ne$lease-and-not$lease.closed){
    try{$result.archive_lease=Complete-MIRNativeArchiveLease -Lease $lease}
    catch{$result.status='restoration-failed';if($null-eq$result.failure){$failure=$_.Exception;$result.failure=$_.Exception.Message}}
  }
  if(-not(Test-Path -LiteralPath $outputRoot)){$null=[IO.Directory]::CreateDirectory($outputRoot)}
  $result.completed_utc=[DateTime]::UtcNow.ToString('o')
  $result.direct_library_after=Get-PreviewLibraryState -Library $library -Names @($plan.direct_library.archives|ForEach-Object {[string]$_.name})
  $result.controls_after=Get-PreviewControls -Library $library
  $restoredArchiveJson=ConvertTo-Json -InputObject @($result.direct_library_after) -Depth 8 -Compress
  $restoredControlJson=ConvertTo-Json -InputObject @($result.controls_after) -Depth 8 -Compress
  $result.original_library_bytes_restored=($restoredArchiveJson-ceq$plannedArchiveJson-and$restoredControlJson-ceq$plannedControlJson)
  if(-not$result.original_library_bytes_restored){$result.status='restoration-failed';if($null-eq$failure){$failure=[Exception]::new('Direct library archive/control readback differs from the prepared inputs.');$result.failure=$failure.Message}}
  $receipt=Join-Path $outputRoot 'library-restoration-preview-caller-result.json'
  [IO.File]::WriteAllText($receipt,(($result|ConvertTo-Json -Depth 20)+"`n"),[Text.UTF8Encoding]::new($false))
}
if($failure){throw $failure}
[pscustomobject]$result
