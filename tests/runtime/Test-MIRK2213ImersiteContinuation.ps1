# MIR4-CANONICAL-EXECUTABLE-TEST
<#!
.SYNOPSIS
Runs one fresh, exact F210/Krastorio2/K2SO Imersite-continuation create and
single reload. Supply a portable exact input profile or the historical V5
observation lock. Neither input contract grants gameplay acceptance.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$CandidateZip,
  [Parameter(Mandatory)][string]$SourceMaterializationPath,
  [string]$V5ObservationResultPath = '',
  [string]$InputProfilePath = '',
  [string]$RepoRoot = '',
  [string]$OutputRoot = 'build/p/k2-213-imersite-continuation',
  [string[]]$LocalModLibraryDirs = @(),
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB = 0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB = 120,
  [switch]$PreflightOnly,
  [ValidateRange(1,180)][int]$CreateTimeoutSeconds = 90,
  [ValidateRange(1,180)][int]$ReloadTimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/ImmutableInputStaging.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/NativeProbeResources.ps1')

function Fail-K2213 { param([string]$Code) throw "[mir42-k2-213-imersite] $Code" }
function Assert-K2213 { param([bool]$Condition,[string]$Code) if (-not $Condition) { Fail-K2213 $Code } }
function Get-K2213Sha256 { param([Parameter(Mandatory)][string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Get-K2213Property { param($Object,[string]$Name,$Default=$null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}
function Read-K2213CurrentCandidate([string]$Archive,[string]$ReceiptPath) {
  Read-MIRNativeProbeF210CurrentCandidate -Repository $RepoRoot -Archive $Archive -ReceiptPath $ReceiptPath
}
function Read-K2213DependencyInputs($Observation,[Collections.IDictionary]$ExpectedDependencies,[string[]]$Libraries,[string]$ObservationPath) {
  $lockEntries=@($Observation.staged_inputs)
  Assert-K2213 ($lockEntries.Count -ge $ExpectedDependencies.Count) 'v5-staged-input-count'
  $expectedHashes=[ordered]@{};$lockedPaths=[ordered]@{}
  foreach($fileName in $ExpectedDependencies.Keys) {
    $matches=@($lockEntries|Where-Object {[IO.Path]::GetFileName([string]$_.source_path) -ceq $fileName})
    Assert-K2213 ($matches.Count -eq 1) "v5-dependency-lock:$fileName"
    $entry=$matches[0]
    Assert-K2213 ([bool]$entry.source_match -and [bool]$entry.stage_match -and ([string]$entry.sha256 -cmatch '^[0-9A-F]{64}$')) "v5-dependency-lock-integrity:$fileName"
    $expectedHashes[$fileName]=[string]$entry.sha256
    $lockedPaths[$fileName]=[string]$entry.source_path
  }
  # Historical paths remain custody text. Resolve only the explicit flat
  # libraries; never restore or walk the retired V5 profile directories.
  $resolved=Resolve-MIRNativeProbeDependencyInputs -ExpectedArchives $expectedHashes -LocalModLibraryDirs $Libraries
  $inputs=@()
  foreach($fileName in $ExpectedDependencies.Keys) {
    $source=[string]$resolved[$fileName].source_path
    Assert-K2213ArchiveIdentity -Path $source -ExpectedName $ExpectedDependencies[$fileName][0] -ExpectedVersion $ExpectedDependencies[$fileName][1] -ExpectedSha256 $expectedHashes[$fileName]
    $inputs += [ordered]@{source_path=$source;file_name=$fileName;expected_sha256=$expectedHashes[$fileName];role='dependency-mod';identity=[ordered]@{name=$ExpectedDependencies[$fileName][0];version=$ExpectedDependencies[$fileName][1];archive=$fileName};provenance=[ordered]@{kind='verified-local-library-with-v5-dependency-lock';v5_result_sha256=Get-K2213Sha256 $ObservationPath;historical_source_path=$lockedPaths[$fileName]};immutable=$true}
  }
  return $inputs
}
function Read-K2213ProfileInputs {
  param([string]$Path,[Collections.IDictionary]$ExpectedDependencies,[string[]]$Libraries)
  $profile=Read-K2213Json -Path $Path -Code 'input-profile'
  Assert-K2213 ($profile.schema -eq 1 -and $profile.target -ceq 'f210' -and $profile.factorio_line -ceq '2.1') 'input-profile-schema-target'
  Assert-K2213 ($profile.engine_version -cin @('2.1.20','2.1.21')) 'input-profile-engine-version'
  foreach($field in @('engine_sha256','runtime_api_sha256')){Assert-K2213 ([string]$profile.$field -cmatch '^[0-9A-F]{64}$') "input-profile-hash:$field"}
  Assert-K2213 ($profile.settings_mode -ceq 'Defaults') 'input-profile-settings'
  $expected=[ordered]@{}
  foreach($name in @('base','elevated-rails','quality','recycler','space-age')){$expected[$name]=[string]$profile.engine_version}
  foreach($fileName in $ExpectedDependencies.Keys){$expected[$ExpectedDependencies[$fileName][0]]=$ExpectedDependencies[$fileName][1]}
  $expected['more-infinite-research']='4.2.21001'
  $expected['mir-fixture-assert-k2-213-imersite-continuation']='0.1.1'
  Assert-K2213 (@($profile.mods).Count -eq $expected.Count) 'input-profile-selection-count'
  foreach($name in $expected.Keys){
    $rows=@($profile.mods|Where-Object {$_.name -ceq $name})
    Assert-K2213 ($rows.Count -eq 1 -and $rows[0].enabled -is [bool] -and $rows[0].enabled -and $rows[0].version -ceq $expected[$name]) "input-profile-selection:$name"
  }
  $hashes=[ordered]@{}
  Assert-K2213 (@($profile.archive_sha256.PSObject.Properties).Count -eq $ExpectedDependencies.Count) 'input-profile-archive-count'
  foreach($fileName in $ExpectedDependencies.Keys){
    $hash=[string](Get-K2213Property $profile.archive_sha256 $fileName '')
    Assert-K2213 ($hash -cmatch '^[0-9A-F]{64}$') "input-profile-archive-hash:$fileName"
    $hashes[$fileName]=$hash
  }
  $resolved=Resolve-MIRNativeProbeDependencyInputs -ExpectedArchives $hashes -LocalModLibraryDirs $Libraries
  $inputs=@(foreach($fileName in $ExpectedDependencies.Keys){
    $source=[string]$resolved[$fileName].source_path
    Assert-K2213ArchiveIdentity -Path $source -ExpectedName $ExpectedDependencies[$fileName][0] -ExpectedVersion $ExpectedDependencies[$fileName][1] -ExpectedSha256 $hashes[$fileName]
    [ordered]@{source_path=$source;file_name=$fileName;expected_sha256=$hashes[$fileName];role='dependency-mod';identity=@{name=$ExpectedDependencies[$fileName][0];version=$ExpectedDependencies[$fileName][1]};provenance=@{kind='portable-exact-input-profile';profile_sha256=Get-K2213Sha256 $Path};immutable=$true}
  })
  return [pscustomobject]@{profile=$profile;inputs=$inputs}
}
function Invoke-MIRCompatFactorioProcess {
  param([string]$FactorioBin,[object[]]$ArgumentList,[string]$StdoutPath,[string]$StderrPath,[int]$TimeoutSeconds,$LibraryActivation)
  # Preserve the existing create/reload collector and its exact oracles,
  # while charging their native actors to one owned row over the active library.
  Assert-MIRLibraryLaunch -Activation $LibraryActivation -FactorioBin $FactorioBin -Arguments ([string[]]$ArgumentList)
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $FactorioBin -Arguments ([string[]]$ArgumentList) -TimeoutSeconds $TimeoutSeconds
  Copy-Item -LiteralPath $actor.stdout -Destination $StdoutPath
  Copy-Item -LiteralPath $actor.stderr -Destination $StderrPath
  $null=Get-MIRNativeProbeRemainingOutputBytes -Context $resources
  return $actor.result
}
function Get-K2213PathIdentity {
  param([Parameter(Mandatory)][string]$Path,[switch]$AllowExternalInput)
  $full = [IO.Path]::GetFullPath($Path)
  $root = $RepoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if ($full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) {
    return [pscustomobject][ordered]@{path=$full.Substring($root.Length).Replace('\','/');path_kind='repository-relative'}
  }
  Assert-K2213 ([bool]$AllowExternalInput) "artifact-outside-repository:$full"
  return [pscustomobject][ordered]@{path=$full;path_kind='external-input-file'}
}
function Get-K2213Relative { param([Parameter(Mandatory)][string]$Path)
  return (Get-K2213PathIdentity -Path $Path).path
}
function Get-K2213Artifact { param([Parameter(Mandatory)][string]$Path,[switch]$AllowExternalInput)
  $item = Get-Item -LiteralPath $Path -Force
  Assert-K2213 (-not (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) "artifact-reparse:$Path"
  $identity = Get-K2213PathIdentity -Path $item.FullName -AllowExternalInput:$AllowExternalInput
  [pscustomobject][ordered]@{path=$identity.path;path_kind=$identity.path_kind;bytes=[long]$item.Length;raw_sha256=Get-K2213Sha256 $item.FullName}
}
function Read-K2213Json { param([Parameter(Mandatory)][string]$Path,[string]$Code)
  Assert-K2213 (Test-Path -LiteralPath $Path -PathType Leaf) "$Code-missing"
  try { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100) } catch { Fail-K2213 "$Code-invalid-json" }
}
function Get-K2213ZipInfo { param([Parameter(Mandatory)][string]$Path)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entries = @($archive.Entries | Where-Object { $_.FullName -match '^[^/]+/info[.]json$' })
    Assert-K2213 ($entries.Count -eq 1) "archive-info-json-count:$([IO.Path]::GetFileName($Path))"
    $reader = [IO.StreamReader]::new($entries[0].Open())
    try { $json = $reader.ReadToEnd() } finally { $reader.Dispose() }
    try { return ($json | ConvertFrom-Json -Depth 20) } catch { Fail-K2213 "archive-info-json-invalid:$([IO.Path]::GetFileName($Path))" }
  } finally { $archive.Dispose() }
}
function Assert-K2213ArchiveIdentity {
  param([string]$Path,[string]$ExpectedName,[string]$ExpectedVersion,[string]$ExpectedSha256)
  Assert-K2213 (Test-Path -LiteralPath $Path -PathType Leaf) "archive-missing:$ExpectedName"
  Assert-K2213 ((Get-K2213Sha256 $Path) -ceq $ExpectedSha256) "archive-sha256:$ExpectedName"
  $info = Get-K2213ZipInfo $Path
  Assert-K2213 ([string]$info.name -ceq $ExpectedName) "archive-name:$ExpectedName"
  Assert-K2213 ([string]$info.version -ceq $ExpectedVersion) "archive-version:$ExpectedName"
}
function Read-K2213DirectLibraryInputs {
  param([string]$Library,[object[]]$Inputs,[string]$FixtureRoot,[ValidateSet('2.1.20','2.1.21')][string]$EngineVersion='2.1.20')
  Assert-MIRLibraryPath $Library
  $hashes=[ordered]@{}
  $rows=@(foreach($name in @('base','elevated-rails','quality','recycler','space-age')){[ordered]@{name=$name;version=$EngineVersion;enabled=$true}})
  foreach($inputRow in $Inputs){
    $archive=Join-Path $Library ([string]$inputRow.file_name)
    # Acquisition is separate. Missing library members do not trigger a copy,
    # a link, a download or recovery of an obsolete populated profile.
    Assert-K2213ArchiveIdentity -Path $archive -ExpectedName $inputRow.identity.name -ExpectedVersion $inputRow.identity.version -ExpectedSha256 $inputRow.expected_sha256
    $hashes[$inputRow.file_name]=[string]$inputRow.expected_sha256
    $rows+=[ordered]@{name=$inputRow.identity.name;version=$inputRow.identity.version;enabled=$true}
  }
  $info=Get-Content -LiteralPath (Join-Path $FixtureRoot 'info.json') -Raw|ConvertFrom-Json
  $name=$info.name+'_'+$info.version+'.zip'
  $fixtureArchive=Join-Path $Library $name
  Assert-K2213 (Test-Path -LiteralPath $fixtureArchive -PathType Leaf) 'install-current-fixture-once-in-library'
  Assert-MIRLibraryPath $fixtureArchive
  $sourceFiles=@(Get-ChildItem -LiteralPath $FixtureRoot -Recurse -File)
  $zip=[IO.Compression.ZipFile]::OpenRead($fixtureArchive)
  try{
    Assert-K2213 ($zip.Entries.Count -eq $sourceFiles.Count) 'library-fixture-membership'
    foreach($file in $sourceFiles){
      $relative=[IO.Path]::GetRelativePath($FixtureRoot,$file.FullName).Replace('\','/')
      $entry=$zip.GetEntry($info.name+'_'+$info.version+'/'+$relative)
      Assert-K2213 ($null -ne $entry -and $entry.Length -eq $file.Length) "library-fixture-member:$relative"
      $stream=$entry.Open()
      try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
      Assert-K2213 ($hash -ceq (Get-K2213Sha256 $file.FullName)) "library-fixture-source:$relative"
    }
  }finally{$zip.Dispose()}
  $hashes[$name]=Get-K2213Sha256 $fixtureArchive
  $rows+=[ordered]@{name=$info.name;version=$info.version;enabled=$true}
  return [pscustomobject]@{mod_list=[ordered]@{mods=$rows};archive_hashes=$hashes;fixture_archive=$fixtureArchive}
}
function Get-K2213FixtureEnvelope {
  param([Parameter(Mandatory)][string]$Path)
  $text = Get-Content -Raw -LiteralPath $Path
  $fixtureId = 'k2-213-imersite-continuation'
  $match = [regex]::Match($text,"(?ms)^  $fixtureId`:\s*\r?\n(?<body>.*?)(?=^  [A-Za-z0-9][A-Za-z0-9_-]*:\s*\r?\n|\z)")
  Assert-K2213 $match.Success 'registered-fixture-absent'
  $body = $match.Groups['body'].Value
  $required = @(
    'path: fixtures/assert-k2-213-imersite-continuation',
    'qualification_status: unqualified',
    'base: "2.1.21"',
    'Krastorio2: "2.1.3"',
    'Krastorio2-spaced-out: "2.0.13"',
    'more-infinite-research: "4.2.21001"'
  )
  foreach ($line in $required) { Assert-K2213 ($body.Contains($line,[StringComparison]::Ordinal)) "registered-fixture-field:$line" }
  return [pscustomobject][ordered]@{id=$fixtureId;path='fixtures/assert-k2-213-imersite-continuation';raw_sha256=Get-K2213Sha256 $Path}
}
function New-K2213FailureResult {
  param([string]$RunRoot,[string]$Message,$Activation,$Resources)
  if ([string]::IsNullOrWhiteSpace($RunRoot) -or -not (Test-Path -LiteralPath $RunRoot -PathType Container)) { return }
  $terminal = $null
  if ($null -ne $Activation -and -not [bool]$Activation.closed) {
    try { $terminal = Complete-MIRLibraryActivation -Activation $Activation } catch { $terminal=@{status='recovery-required';library=$Activation.library;error=$_.Exception.Message} }
  }
  $record = [ordered]@{
    schema=2;kind='MIR42K2213ImersiteContinuationRuntimeResultV2';status='failed';
    generated_at=(Get-Date).ToUniversalTime().ToString('o');failure=[string]$Message;
    scope='exact-current-f210-k2-k2so-imersite-powder-continuation-create-and-single-reload';
    qualification=$false;support_claim=$false;release_authority=$false;publication=$false;
    input_binding=$inputBinding;
    library_activation=$terminal
    resource_runs=if($Resources){$Resources.runs.ToArray()}else{@()}
  }
  if($Resources){Write-MIRNativeProbeResult -Context $Resources -Record $record}
}

$runRoot = ''
$activation = $null
$resources = $null
$inputBinding = $null
try {
  $engine = (Resolve-Path -LiteralPath $FactorioBin).Path
  $candidate = (Resolve-Path -LiteralPath $CandidateZip).Path
  $materializationPath = (Resolve-Path -LiteralPath $SourceMaterializationPath).Path
  Assert-K2213 (([bool]$V5ObservationResultPath) -xor ([bool]$InputProfilePath)) 'supply-one-input-profile-or-historical-observation'
  $v5Path = if($V5ObservationResultPath){(Resolve-Path -LiteralPath $V5ObservationResultPath).Path}else{''}
  $profilePath = if($InputProfilePath){(Resolve-Path -LiteralPath $InputProfilePath).Path}else{''}
  $outputRootFull = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputRoot))
  $buildRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build')).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  Assert-K2213 ($outputRootFull.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)) 'output-root-outside-build'

  $fixtureRegistry = Get-K2213FixtureEnvelope -Path (Join-Path $RepoRoot '.mir/fixtures.yml')
  $fixtureRoot = Join-Path $RepoRoot $fixtureRegistry.path
  $fixtureInfoPath = Join-Path $fixtureRoot 'info.json'
  $fixtureDataPath = Join-Path $fixtureRoot 'data-final-fixes.lua'
  $fixtureControlPath = Join-Path $fixtureRoot 'control.lua'
  foreach ($fixturePath in @($fixtureInfoPath,$fixtureDataPath,$fixtureControlPath)) { Assert-K2213 (Test-Path -LiteralPath $fixturePath -PathType Leaf) "fixture-missing:$fixturePath" }
  $fixtureInfo = Read-K2213Json -Path $fixtureInfoPath -Code 'fixture-info'
  Assert-K2213 ([string]$fixtureInfo.name -ceq 'mir-fixture-assert-k2-213-imersite-continuation') 'fixture-name'
  Assert-K2213 ([string]$fixtureInfo.version -ceq '0.1.1') 'fixture-version'
  Assert-K2213 ([string]$fixtureInfo.factorio_version -ceq '2.1') 'fixture-factorio-version'
  $fixtureDependencies = @($fixtureInfo.dependencies | ForEach-Object {[string]$_})
  foreach ($dependency in @('base >= 2.1.20','Krastorio2 = 2.1.3','Krastorio2-spaced-out = 2.0.13','more-infinite-research = 4.2.21001')) {
    Assert-K2213 ($fixtureDependencies -contains $dependency) "fixture-dependency:$dependency"
  }
  Assert-K2213 ($LocalModLibraryDirs.Count -eq 1) 'one-active-flat-library-required'
  $library=(Resolve-Path -LiteralPath $LocalModLibraryDirs[0]).Path
  $plannedFixtureArchive = Join-Path $library ([string]$fixtureInfo.name + '_' + [string]$fixtureInfo.version + '.zip')
  Assert-MIRFactorioPathBudget -Path $plannedFixtureArchive -Context 'K2 continuation fixture archive path'

  $currentCandidate=Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $materializationPath
  $materialization=$currentCandidate.receipt

  $engineHash = Get-K2213Sha256 $engine
  $engineRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $engine))
  $runtimeApi = Join-Path $engineRoot 'doc-html/runtime-api.json'
  $expectedDependencies = [ordered]@{
    'flib_0.17.2.zip'=@('flib','0.17.2')
    'k2so-assets_1.0.7.zip'=@('k2so-assets','1.0.7')
    'Krastorio2_2.1.3.zip'=@('Krastorio2','2.1.3')
    'Krastorio2-spaced-out_2.0.13.zip'=@('Krastorio2-spaced-out','2.0.13')
    'Krastorio2Assets_2.1.0.zip'=@('Krastorio2Assets','2.1.0')
    'Krastorio2MenuSimulations_2.1.0.zip'=@('Krastorio2MenuSimulations','2.1.0')
    'xy-k2so-enhancements-nulls-fork_0.8.3.zip'=@('xy-k2so-enhancements-nulls-fork','0.8.3')
  }
  $predecessorLock=$null
  $inputProfile=$null
  if($profilePath){
    $bound=Read-K2213ProfileInputs -Path $profilePath -ExpectedDependencies $expectedDependencies -Libraries $LocalModLibraryDirs
    $expectedEngineVersion=[string]$bound.profile.engine_version
    Assert-K2213 ($engineHash -ceq $bound.profile.engine_sha256) 'engine-sha256'
    Assert-K2213 ((Get-K2213Sha256 $runtimeApi) -ceq $bound.profile.runtime_api_sha256) 'engine-runtime-api'
    $inputs=@($bound.inputs)
    $inputProfile=Get-K2213Artifact $profilePath -AllowExternalInput
  }else{
    $v5 = Read-K2213Json -Path $v5Path -Code 'v5-observation'
    Assert-K2213 ([int]$v5.schema -eq 1 -and [string]$v5.kind -ceq 'MIR42ExactK2213ForwardPathObservationResultV3' -and [string]$v5.status -ceq 'passed') 'v5-schema-status'
    foreach ($forbiddenClaim in @('qualification','support_claim','release_authority','publication')) { Assert-K2213 (-not [bool](Get-K2213Property $v5 $forbiddenClaim $true)) "v5-must-remain-non-authorizing:$forbiddenClaim" }
    $v5Mods = Get-K2213Property $v5 'exact_mods'
    foreach ($pair in @(@('base','2.1.20'),@('Krastorio2','2.1.3'),@('Krastorio2-spaced-out','2.0.13'),@('more-infinite-research','4.2.21000'))) {
      Assert-K2213 ([string](Get-K2213Property $v5Mods $pair[0] '') -ceq $pair[1]) "v5-exact-mod:$($pair[0])"
    }
    Assert-K2213 ($engineHash -ceq [string]$v5.engine.sha256) 'engine-sha256'
    Assert-K2213 ([string]$v5.engine.product_version -ceq '2.1.20') 'v5-engine-version'
    Assert-K2213 ((Get-K2213Sha256 $runtimeApi) -ceq [string]$v5.engine.bundled_runtime_api_sha256) 'engine-runtime-api'
    $expectedEngineVersion='2.1.20'
    $expectedDependencies['mir-validation-settings-overrides_0.1.0.zip']=@('mir-validation-settings-overrides','0.1.0')
    $inputs = @(Read-K2213DependencyInputs -Observation $v5 -ExpectedDependencies $expectedDependencies -Libraries $LocalModLibraryDirs -ObservationPath $v5Path)
    $predecessorLock=[ordered]@{result=Get-K2213Artifact $v5Path -AllowExternalInput;kind=[string]$v5.kind;status=[string]$v5.status;role='exact-engine-and-dependency-archive-lock-only';old_candidate_sha256=[string]$v5.candidate.sha256}
  }
  Assert-K2213 ((Get-Item -LiteralPath $engine).VersionInfo.ProductVersion -ceq $expectedEngineVersion) 'engine-product-version'
  $inputs += [ordered]@{source_path=$candidate;file_name=([IO.Path]::GetFileName($candidate));expected_sha256=([string]$materialization.archive_sha256);role='candidate';identity=[ordered]@{name='more-infinite-research';version='4.2.21001';materialization_record_sha256=[string]$materialization.record_sha256};provenance=[ordered]@{kind='current-candidate-materialization';raw_materialization_sha256=Get-K2213Sha256 $materializationPath};immutable=$true}
  $directInputs=Read-K2213DirectLibraryInputs -Library $library -Inputs $inputs -FixtureRoot $fixtureRoot -EngineVersion $expectedEngineVersion
  $inputBinding=[ordered]@{
    source_commit=(& git -C $RepoRoot rev-parse HEAD).Trim();harness=Get-K2213Artifact $PSCommandPath
    candidate_sha256=[string]$materialization.archive_sha256;materialization_sha256=Get-K2213Sha256 $materializationPath
    engine_version=$expectedEngineVersion;engine_sha256=$engineHash;runtime_api_sha256=Get-K2213Sha256 $runtimeApi
    input_profile=$inputProfile;predecessor_observation_lock=$predecessorLock;archive_hashes=$directInputs.archive_hashes
  }

  if ($PreflightOnly) {
    [pscustomobject][ordered]@{
      status='passed-preflight-only'
      scope='exact-current-f210-k2-k2so-imersite-continuation-input-and-envelope-validation'
      candidate_sha256=[string]$materialization.archive_sha256
      materialization_sha256=Get-K2213Sha256 $materializationPath
      predecessor_observation_lock=$predecessorLock
      input_profile=$inputProfile
      engine_version=$expectedEngineVersion
      engine_sha256=$engineHash
      runtime_api_sha256=Get-K2213Sha256 $runtimeApi
      fixture_registry_sha256=$fixtureRegistry.raw_sha256
      dependency_count=$expectedDependencies.Count
      library=$library
      fixture_archive_sha256=$directInputs.archive_hashes[[IO.Path]::GetFileName($directInputs.fixture_archive)]
      execution_started=$false
    } | ConvertTo-Json -Depth 20
    return
  }

  & (Join-Path $RepoRoot 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -RepoRoot $RepoRoot -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
  $resources=New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
  $runRoot=$resources.root
  [IO.Directory]::CreateDirectory($runRoot) | Out-Null
  [IO.Directory]::CreateDirectory((Join-Path $runRoot 'saves')) | Out-Null
  $versionRun=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments @('--version') -TimeoutSeconds 30
  $engineVersion=(Get-Content -LiteralPath $versionRun.stdout -Raw).Trim()
  Assert-K2213 ($engineVersion -match ('(?m)^Version:\s*'+[regex]::Escape($expectedEngineVersion)+'(?:\s|$)')) 'engine-version'
  $fixtureArchive=$directInputs.fixture_archive
  $enabled = @('base','elevated-rails','quality','recycler','space-age','more-infinite-research',[string]$fixtureInfo.name)+@(foreach($key in $expectedDependencies.Keys){$expectedDependencies[$key][0]})
  $profilePath=Join-Path $runRoot 'selection.json'
  [IO.File]::WriteAllText($profilePath,($directInputs.mod_list|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory (Join-Path $engineRoot 'data') -ProfilePath $profilePath -ArchiveHashes $directInputs.archive_hashes -SettingsMode Defaults
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  $modListPath = Join-Path $runRoot 'active-mod-list.json'
  [IO.File]::WriteAllBytes($modListPath,$activation.mod_list_bytes)
  $modList = Read-K2213Json -Path $modListPath -Code 'mod-list'
  $enabledRows = @($modList.mods | Where-Object {[bool]$_.enabled} | ForEach-Object {[string]$_.name} | Sort-Object)
  Assert-K2213 ((@($enabledRows) -join '|') -ceq (@($enabled | Sort-Object) -join '|')) 'mod-list-exact-enabled-closure'
  foreach ($dlc in @('elevated-rails','quality','recycler','space-age')) {
    $row = @($modList.mods | Where-Object {[string]$_.name -ceq $dlc})
    Assert-K2213 ($row.Count -eq 1 -and [bool]$row[0].enabled) "mod-list-observed-dlc:$dlc"
  }
  # The continuation fixture proves the current declaration's default zero
  # configuration, with the fixture's explicit diagnostic-report default.
  # It never inherits an unbound settings file from a previous test.
  Assert-K2213 (-not (Test-Path -LiteralPath (Join-Path $library 'mod-settings.dat') -PathType Leaf)) 'unexpected-unbound-mod-settings'

  $load = Invoke-MIRFactorioLoadCheck -FactorioBin $engine -UserDataDir $runRoot -ScenarioName 'k2-213-imersite-continuation' -ScenarioTimeoutSeconds $CreateTimeoutSeconds -LibraryActivation $activation
  Assert-K2213 ([bool]$load.passed -and -not [bool]$load.timed_out -and [int]$load.exit_code -eq 0) 'create'
  Assert-K2213 ([string]$load.stderr_sha256 -ceq 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855') 'create-stderr'
  $loadLog = [IO.File]::ReadAllText([string]$load.factorio_log)
  Assert-K2213 ($loadLog.Contains('[MIR42_K2_213_IMERSITE_CONTINUATION_DATA]',[StringComparison]::Ordinal)) 'create-data-marker'
  Assert-K2213 ($loadLog.Contains('[MIR42_K2_213_IMERSITE_CONTINUATION] stage=initial;completed_level=4;next_level=5;bonus=0.08;progress=0.42',[StringComparison]::Ordinal)) 'create-initial-marker'
  $reload = Invoke-MIRFactorioReloadContract -FactorioBin $engine -UserDataDir $runRoot -ScenarioName 'k2-213-imersite-continuation' -SavePath $load.save -RequiredReloadCount 1 -MaxReloadDurationSeconds $ReloadTimeoutSeconds -RequiredLogFragments '[MIR42_K2_213_IMERSITE_CONTINUATION] stage=reload;completed_level=4;next_level=5;bonus=0.08;progress=0.42' -LibraryActivation $activation
  Assert-K2213 ([bool]$reload.passed) 'single-reload'
  # Capture locators while the archive read handles are still held; a later
  # activation may select different MIR bytes under the same numeric version.
  $dependencyArtifacts = @($inputs | Where-Object {[string]$_.role -ceq 'dependency-mod'} | ForEach-Object { Get-K2213Artifact (Join-Path $library $_.file_name) -AllowExternalInput })
  $candidateArtifact = Get-K2213Artifact (Join-Path $library ([IO.Path]::GetFileName($candidate))) -AllowExternalInput
  $fixtureArtifact = Get-K2213Artifact $fixtureArchive -AllowExternalInput
  $terminal = Complete-MIRLibraryActivation -Activation $activation
  $activation = $null
  $result = [ordered]@{
    schema=2;kind='MIR42K2213ImersiteContinuationRuntimeResultV2';status='passed';generated_at=(Get-Date).ToUniversalTime().ToString('o');
    scope='exact-current-f210-k2-k2so-imersite-powder-continuation-create-and-single-reload';
    qualification=$false;support_claim=$false;release_authority=$false;publication=$false;
    candidate=[ordered]@{archive=$candidateArtifact;materialization=Get-K2213Artifact $materializationPath;materialization_record_sha256=[string]$materialization.record_sha256;package_source_sha256=[string]$materialization.package_source_sha256};
    source=[ordered]@{commit=(& git -C $RepoRoot rev-parse HEAD).Trim();tree=(& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim();source_version='4.2.1';distribution_version='4.2.21001';harness=Get-K2213Artifact $PSCommandPath};
    predecessor_observation_lock=$predecessorLock;input_profile=$inputProfile;
    engine=[ordered]@{path=Get-K2213PathIdentity $engine -AllowExternalInput;product_version=$expectedEngineVersion;executable_sha256=$engineHash;bundled_runtime_api_sha256=Get-K2213Sha256 $runtimeApi};
    fixture=[ordered]@{registration=$fixtureRegistry;files=@(Get-K2213Artifact $fixtureInfoPath;Get-K2213Artifact $fixtureDataPath;Get-K2213Artifact $fixtureControlPath);archive=$fixtureArtifact};
    library_activation=$terminal;dependency_archives=@($dependencyArtifacts | Sort-Object path);mod_list=Get-K2213Artifact $modListPath;startup_settings='candidate-defaults-no-unbound-mod-settings';
    create=[ordered]@{duration_seconds=$load.duration_seconds;save=Get-K2213Artifact $load.save;stdout=Get-K2213Artifact $load.stdout;stderr=Get-K2213Artifact $load.stderr;factorio_log=Get-K2213Artifact $load.factorio_log};
    reload=$reload;
    resource_runs=$resources.runs.ToArray();
    non_claims=@('The supplied V5 observation remains non-authorizing and is not rebound.','Only generated MIR Imersite powder continuation is exercised. Native Imersite crystal ownership and witnessed withheld K2 routes remain outside this receipt.','No player delivery, broad K2 admission, support, release, signing, or publication claim.')
  }
  $resultPath = Join-Path $runRoot 'result.json'
  Write-MIRNativeProbeResult -Context $resources -Record $result
  Write-Host "[MIR42_K2_213_IMERSITE_CONTINUATION_RUNTIME] $(Get-K2213Relative $resultPath)"
} catch {
  $failure = $_.Exception.Message
  try{New-K2213FailureResult -RunRoot $runRoot -Message $failure -Activation $activation -Resources $resources}catch{Write-Warning 'Failed K2 result exceeded its output budget; owned ledgers remain preserved.'}
  throw
}
