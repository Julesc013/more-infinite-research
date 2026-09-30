<#
.SYNOPSIS
Seeds an exact K2 2.1.3/K2SO 2.0.13 save under the pinned pre-continuation F210
package, upgrades it to the pinned PR #411 package, and checks state continuity.
.DESCRIPTION
Preflight verifies immutable package/dependency identities and Factorio path budget.
The full mode runs predecessor create, current-package upgrade/save, and one reload.
It is a narrow migration observation, not broad K2 qualification or release authority.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$OldCandidateZip,
  [Parameter(Mandatory)][string]$NewCandidateZip,
  [Parameter(Mandatory)][string]$V5ObservationResultPath,
  [string]$RepoRoot = '',
  [string]$OutputRoot = 'build/m',
  [switch]$PreflightOnly,
  [ValidateRange(1,180)][int]$CreateTimeoutSeconds = 90,
  [ValidateRange(1,180)][int]$UpgradeTimeoutSeconds = 90,
  [ValidateRange(1,180)][int]$ReloadTimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/ImmutableInputStaging.ps1')

$oldCandidateSha = '3992DE66E873184709559CCEEB1E87E2A7E4909CECEB8FCDF537DB32C9CE8A79'
$newCandidateSha = '68415741C2F789B4D0E80A93D60238284FC3EB9069B84FA13887DFEF64758AD4'
$v5ResultSha = 'E5A8FFD18674DFC4DD7C3E52AC009B116FE3846D932776FDF54A1CF12757B324'
$v5SaveSha = 'B628AF5A7CACA5E44A5DD1D717C15030D07695AAA3D4E8F702C1C4EF60E5E4A2'
$engineSha = 'E4B1FDBDCC77F4C3449318CE1398493EA7A8E77A19D68BD1AC3A858D0F373B92'
$runtimeApiSha = '1FF275CC085347FAFDDC01B5BA53DF10259319339E78CD6E5B4E0D067E1DAEB6'
$expectedDependencies = [ordered]@{
  'flib_0.17.2.zip'=@('flib','0.17.2')
  'k2so-assets_1.0.7.zip'=@('k2so-assets','1.0.7')
  'Krastorio2_2.1.3.zip'=@('Krastorio2','2.1.3')
  'Krastorio2-spaced-out_2.0.13.zip'=@('Krastorio2-spaced-out','2.0.13')
  'Krastorio2Assets_2.1.0.zip'=@('Krastorio2Assets','2.1.0')
  'Krastorio2MenuSimulations_2.1.0.zip'=@('Krastorio2MenuSimulations','2.1.0')
  'xy-k2so-enhancements-nulls-fork_0.8.3.zip'=@('xy-k2so-enhancements-nulls-fork','0.8.3')
  'mir-validation-settings-overrides_0.1.0.zip'=@('mir-validation-settings-overrides','0.1.0')
}
$fixtureName = 'mir-fixture-assert-k2-213-imersite-continuation-migration'
$fixtureRelative = 'fixtures/assert-k2-213-imersite-continuation-migration'
$repoPrefix = $RepoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$outputRootFull = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputRoot))
$buildPrefix = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build')).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $outputRootFull.StartsWith($buildPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'K2 migration output must remain under build.' }

function Fail-K2Migration([string]$Code) { throw "[mir42-k2-213-imersite-migration] $Code" }
function Assert-K2Migration([bool]$Condition,[string]$Code) { if (-not $Condition) { Fail-K2Migration $Code } }
function Assert-K2HeadroomDiagnostic([string]$LogPath,[string]$StageName) {
  Assert-K2Migration (Test-Path -LiteralPath $LogPath -PathType Leaf) "$StageName-headroom-log-missing"
  $fragment = '[more-infinite-research] Maximum-level state force=player technology=recipe-prod-research_material_imersite-4 selected-cap=150 effective-cap=150 prototype-max=4294967295 current-or-next-level=4 next-level-valid=true enabled=true'
  $matches = @(Select-String -LiteralPath $LogPath -SimpleMatch -Pattern $fragment)
  Assert-K2Migration ($matches.Count -ge 1) "$StageName-finite-recipe-headroom-diagnostic"
}
function Get-K2MigrationSha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Get-K2MigrationIdentity([string]$Path,[switch]$External) {
  $full = [IO.Path]::GetFullPath($Path)
  if ($full.StartsWith($repoPrefix,[StringComparison]::OrdinalIgnoreCase)) {
    return [ordered]@{path=$full.Substring($repoPrefix.Length).Replace('\','/');path_kind='repository-relative'}
  }
  Assert-K2Migration ([bool]$External) "external-path-not-authorized:$full"
  return [ordered]@{path=$full;path_kind='external-input-file'}
}
function Get-K2MigrationArtifact([string]$Path,[switch]$External) {
  $item = Get-Item -LiteralPath $Path -Force
  Assert-K2Migration (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "artifact-reparse:$Path"
  [ordered]@{path=(Get-K2MigrationIdentity $item.FullName -External:$External).path;path_kind=(Get-K2MigrationIdentity $item.FullName -External:$External).path_kind;bytes=[long]$item.Length;raw_sha256=Get-K2MigrationSha $item.FullName}
}
function Read-K2MigrationJson([string]$Path,[string]$Code) {
  Assert-K2Migration (Test-Path -LiteralPath $Path -PathType Leaf) "$Code-missing"
  try { Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100 } catch { Fail-K2Migration "$Code-invalid-json" }
}
function Get-K2MigrationZipInfo([string]$Path) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entries = @($archive.Entries | Where-Object { $_.FullName -match '^[^/]+/info[.]json$' })
    Assert-K2Migration ($entries.Count -eq 1) "archive-info-count:$([IO.Path]::GetFileName($Path))"
    $reader = [IO.StreamReader]::new($entries[0].Open())
    try { return $reader.ReadToEnd() | ConvertFrom-Json -Depth 20 } finally { $reader.Dispose() }
  } finally { $archive.Dispose() }
}
function Assert-K2MigrationArchive([string]$Path,[string]$ExpectedSha) {
  Assert-K2Migration (Test-Path -LiteralPath $Path -PathType Leaf) "candidate-missing:$Path"
  Assert-K2Migration ((Get-K2MigrationSha $Path) -ceq $ExpectedSha) "candidate-sha256:$([IO.Path]::GetFileName($Path))"
  $info = Get-K2MigrationZipInfo $Path
  Assert-K2Migration ([string]$info.name -ceq 'more-infinite-research' -and [string]$info.version -ceq '4.2.21000') 'candidate-identity'
}
function Publish-K2MigrationFixture([string]$Version,[string]$ModsDir,[string]$RunRoot) {
  $source = Join-Path $RunRoot "fixture-$Version"
  Copy-Item -LiteralPath (Join-Path $RepoRoot $fixtureRelative) -Destination $source -Recurse
  $infoPath = Join-Path $source 'info.json'
  $info = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json
  $info.version = $Version
  [IO.File]::WriteAllText($infoPath,(($info | ConvertTo-Json -Depth 10)+"`n"),[Text.UTF8Encoding]::new($false))
  Publish-MIRModDirectoryArchive -Source $source -Name $fixtureName -Version $Version -ModsDir $ModsDir
}
function Get-K2Cap0SettingsMutation([string]$SourcePath,[string]$ExpectedSourceSha,[string]$OutputPath='') {
  Assert-K2Migration ((Get-K2MigrationSha $SourcePath) -ceq $ExpectedSourceSha) 'pinned-settings-source-sha256'
  $bytes = [IO.File]::ReadAllBytes($SourcePath)
  $key = [Text.Encoding]::UTF8.GetBytes('ips-max-level-research_material_imersite')
  $metadata = [byte[]](0x05,0x00,0x01,0x00,0x00,0x00,0x00,0x05,0x76,0x61,0x6C,0x75,0x65,0x06,0x00)
  $positions = @()
  for ($index=0; $index -le $bytes.Length-$key.Length; $index++) {
    $matches = $true
    for ($offset=0; $offset -lt $key.Length; $offset++) {
      if ($bytes[$index+$offset] -ne $key[$offset]) { $matches=$false; break }
    }
    if ($matches) { $positions += $index }
  }
  Assert-K2Migration ($positions.Count -eq 1) 'imersite-cap-key-occurrence-count'
  $keyOffset = [int]$positions[0]
  $metadataOffset = $keyOffset + $key.Length
  for ($offset=0; $offset -lt $metadata.Length; $offset++) {
    Assert-K2Migration ($bytes[$metadataOffset+$offset] -eq $metadata[$offset]) 'imersite-cap-record-layout'
  }
  $valueOffset = $metadataOffset + $metadata.Length
  Assert-K2Migration ([BitConverter]::ToInt64($bytes,$valueOffset) -eq 3) 'imersite-cap-source-value-not-three'
  Assert-K2Migration ($bytes[$valueOffset+8] -eq 0) 'imersite-cap-record-terminator'
  $mutated = [byte[]]$bytes.Clone()
  [Array]::Copy([BitConverter]::GetBytes([long]0),0,$mutated,$valueOffset,8)
  $changed = @()
  for ($index=0; $index -lt $bytes.Length; $index++) { if ($bytes[$index] -ne $mutated[$index]) { $changed += $index } }
  Assert-K2Migration ($changed.Count -eq 1 -and $changed[0] -eq $valueOffset) 'cap-patch-changed-unexpected-bytes'
  Assert-K2Migration ([BitConverter]::ToInt64($mutated,$valueOffset) -eq 0) 'imersite-cap-patch-result-not-zero'
  $newSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($mutated))
  if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    [IO.File]::WriteAllBytes($OutputPath,$mutated)
    Assert-K2Migration ((Get-K2MigrationSha $OutputPath) -ceq $newSha) 'cap-patch-output-sha256'
    Assert-K2Migration ((Get-K2MigrationSha $SourcePath) -ceq $ExpectedSourceSha) 'pinned-settings-source-mutated'
  }
  [pscustomobject][ordered]@{key='ips-max-level-research_material_imersite';byte_offset=$valueOffset;record_key_offset=$keyOffset;before_int64=3;after_int64=0;changed_byte_offsets=$changed;source_sha256=$ExpectedSourceSha;patched_sha256=$newSha;output_path=$OutputPath}
}
function Initialize-K2MigrationStage([string]$Name,[string]$Role,[string]$Version,[int]$ExpectedCap,[string]$SettingsSourcePath,[string]$SettingsExpectedSha,[string]$StageDirectory,[string]$RunRoot) {
  $userdata = Join-Path $StageDirectory 'userdata'
  $mods = Join-Path $userdata 'mods'
  [IO.Directory]::CreateDirectory($mods) | Out-Null
  [IO.Directory]::CreateDirectory((Join-Path $userdata 'saves')) | Out-Null
  $candidateName = 'more-infinite-research_4.2.21000.zip'
  $inputList = @()
  foreach ($fileName in $expectedDependencies.Keys) {
    $dependency = @($dependencyInputs | Where-Object { [string]$_.file_name -ceq $fileName })
    Assert-K2Migration ($dependency.Count -eq 1) "dependency-record:$fileName"
    $entry = $dependency[0]
    $inputList += [ordered]@{source_path=[string]$entry.source_path;file_name=$fileName;expected_sha256=[string]$entry.sha256;role='dependency-mod';identity=[ordered]@{name=$expectedDependencies[$fileName][0];version=$expectedDependencies[$fileName][1]};provenance=[ordered]@{kind='pinned-k2-213-v5-observation-dependency-lock';v5_result_sha256=$v5ResultSha};immutable=$true}
  }
  $candidatePath = if ($Role -ceq 'predecessor') { $oldCandidate } else { $newCandidate }
  $candidateHash = if ($Role -ceq 'predecessor') { $oldCandidateSha } else { $newCandidateSha }
  $inputList += [ordered]@{source_path=$candidatePath;file_name=$candidateName;expected_sha256=$candidateHash;role='candidate';identity=[ordered]@{name='more-infinite-research';version='4.2.21000';role=$Role};provenance=[ordered]@{kind='pinned-K2-Imersite-migration-candidate';sha256=$candidateHash};immutable=$true}
  $lease = New-MIRImmutableInputLease -RunRoot $StageDirectory -StageDirectory $mods -Inputs $inputList
  # Factorio writes mod-settings.dat during load. Copy the pinned initial
  # profile as writable stage state; never hardlink or mark it immutable.
  $stagedSettings = Join-Path $mods 'mod-settings.dat'
  Copy-Item -LiteralPath $SettingsSourcePath -Destination $stagedSettings
  (Get-Item -LiteralPath $stagedSettings).IsReadOnly = $false
  Assert-K2Migration ((Get-K2MigrationSha $stagedSettings) -ceq $SettingsExpectedSha) "staged-mod-settings-sha256:$Name"
  $null = Publish-K2MigrationFixture -Version $Version -ModsDir $mods -RunRoot $RunRoot
  $enabled = @('base','elevated-rails','quality','recycler','space-age','flib','k2so-assets','Krastorio2','Krastorio2-spaced-out','Krastorio2Assets','Krastorio2MenuSimulations','xy-k2so-enhancements-nulls-fork','mir-validation-settings-overrides','more-infinite-research',$fixtureName)
  Write-MIRModList -ModsDir $mods -EnabledMods $enabled
  $config = Join-Path $userdata 'mir-k2-migration-config.ini'
  $engineRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $engine))
  $readData = Join-Path $engineRoot 'data'
  [IO.File]::WriteAllText($config,"[path]`nread-data=$($readData.Replace('\','/'))`nwrite-data=$($userdata.Replace('\','/'))`n",[Text.UTF8Encoding]::new($false))
  $compatConfig = Join-Path $userdata 'mir-compat-config.ini'
  $compatText = @"
; Generated by the K2 migration runtime fixture.
[path]
read-data=$readData
write-data=$userdata

[general]
locale=auto

[other]
enable-steam-networking=false
disable-blueprint-storage=true
"@
  [IO.File]::WriteAllText($compatConfig,$compatText,[Text.UTF8Encoding]::new($false))
  $server = Join-Path $StageDirectory 'server-settings.json'
  $serverData = [ordered]@{name='MIR K2 Imersite migration';description='';tags=@();max_players=1;visibility=[ordered]@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false}
  [IO.File]::WriteAllText($server,(($serverData | ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  [pscustomobject]@{name=$Name;role=$Role;version=$Version;configured_cap=$ExpectedCap;settings_path=$stagedSettings;settings_initial_sha256=$SettingsExpectedSha;root=$StageDirectory;mods=$mods;userdata=$userdata;config=$config;server=$server;candidate_name=$candidateName;candidate_path=(Join-Path $mods $candidateName);lease=$lease}
}
function Invoke-K2MigrationServerUpgrade($Stage,[string]$InputSave,[string]$ExpectedSave,[string]$ExpectedMarker) {
  $logPath = Join-Path $Stage.userdata 'factorio-current.log'
  if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
  $start = [Diagnostics.ProcessStartInfo]::new($engine)
  $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
  $start.Environment['SteamAppId']='427520'; $start.Environment['SteamGameId']='427520'
  foreach ($argument in @('--config',$Stage.config,'--no-log-rotation','--disable-audio','--mod-directory',$Stage.mods,'--server-settings',$Stage.server,'--start-server',$InputSave)) { [void]$start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::Start($start)
  $ready = $false
  $lastSaveLength = -1L
  $saveStableSince = $null
  try {
    $deadline = [DateTime]::UtcNow.AddSeconds($UpgradeTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
      if ($process.HasExited) { throw "Factorio server exited before migration save with code $($process.ExitCode)." }
      if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        try {
          $stream = [IO.File]::Open($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
          try { $reader = [IO.StreamReader]::new($stream); try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() } } finally { $stream.Dispose() }
          if ((Test-Path -LiteralPath $ExpectedSave -PathType Leaf) -and (Get-Item -LiteralPath $ExpectedSave).Length -gt 0 -and
              $text.Contains($ExpectedMarker,[StringComparison]::Ordinal) -and $text.Contains('Saving finished',[StringComparison]::Ordinal)) { $ready=$true; break }
        } catch [IO.IOException] {
          # Factorio may hold its active log with sharing that blocks readers.
          # Fall back to a stable save file, then verify the copied log after stop.
        }
      }
      if (Test-Path -LiteralPath $ExpectedSave -PathType Leaf) {
        $saveLength = (Get-Item -LiteralPath $ExpectedSave).Length
        if ($saveLength -gt 0 -and $saveLength -eq $lastSaveLength) {
          if ($null -eq $saveStableSince) { $saveStableSince = [DateTime]::UtcNow }
          elseif (([DateTime]::UtcNow - $saveStableSince).TotalSeconds -ge 2) { $ready=$true; break }
        } else {
          $lastSaveLength = $saveLength
          $saveStableSince = $null
        }
      }
      Start-Sleep -Milliseconds 200
    }
    if (-not $ready) { throw 'Factorio server did not finish the K2 predecessor migration save before timeout.' }
  } finally {
    if (-not $process.HasExited) { try { $process.Kill($true) } catch { $process.Kill() } }
    $process.WaitForExit(); $process.Dispose()
  }
  $copy = Join-Path $Stage.root 'factorio-upgrade.log'
  Copy-Item -LiteralPath $logPath -Destination $copy
  $completedLog = [IO.File]::ReadAllText($copy)
  if (-not $completedLog.Contains($ExpectedMarker,[StringComparison]::Ordinal) -or -not $completedLog.Contains('Saving finished',[StringComparison]::Ordinal)) {
    throw 'Factorio migration save log lacks the required marker or completed-save record.'
  }
  return $copy
}

$runRoot = ''
$activeStages = @()
try {
  $engine = (Resolve-Path -LiteralPath $FactorioBin).Path
  $oldCandidate = (Resolve-Path -LiteralPath $OldCandidateZip).Path
  $newCandidate = (Resolve-Path -LiteralPath $NewCandidateZip).Path
  $v5Path = (Resolve-Path -LiteralPath $V5ObservationResultPath).Path
  Assert-K2Migration ((Get-K2MigrationSha $engine) -ceq $engineSha) 'engine-sha256'
  Assert-K2MigrationArchive $oldCandidate $oldCandidateSha
  Assert-K2MigrationArchive $newCandidate $newCandidateSha
  Assert-K2Migration ((Get-K2MigrationSha $v5Path) -ceq $v5ResultSha) 'v5-result-sha256'
  $v5 = Read-K2MigrationJson $v5Path 'v5-result'
  Assert-K2Migration ([string]$v5.kind -ceq 'MIR42ExactK2213ForwardPathObservationResultV3' -and [string]$v5.status -ceq 'passed') 'v5-kind-status'
  Assert-K2Migration ([string]$v5.candidate.sha256 -ceq $oldCandidateSha -and [string]$v5.candidate.path -ceq $oldCandidate) 'v5-old-candidate-identity'
  Assert-K2Migration ([string]$v5.engine.product_version -ceq '2.1.20' -and [string]$v5.engine.sha256 -ceq $engineSha) 'v5-engine-identity'
  foreach ($pair in @(@('base','2.1.20'),@('Krastorio2','2.1.3'),@('Krastorio2-spaced-out','2.0.13'),@('more-infinite-research','4.2.21000'))) {
    Assert-K2Migration ([string]$v5.exact_mods.($pair[0]) -ceq $pair[1]) "v5-exact-mod:$($pair[0])"
  }
  $engineRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $engine))
  $runtimeApi = Join-Path $engineRoot 'doc-html/runtime-api.json'
  Assert-K2Migration ((Get-K2MigrationSha $runtimeApi) -ceq $runtimeApiSha -and [string]$v5.engine.bundled_runtime_api_sha256 -ceq $runtimeApiSha) 'runtime-api-sha256'
  $v5SavePath = [string]$v5.native.save.path
  Assert-K2Migration (Test-Path -LiteralPath $v5SavePath -PathType Leaf) 'v5-observation-save-missing'
  Assert-K2Migration ((Get-K2MigrationSha $v5SavePath) -ceq $v5SaveSha -and [string]$v5.native.save.sha256 -ceq $v5SaveSha) 'v5-observation-save-sha256'
  $v5SettingsPath = Join-Path (Join-Path (Split-Path -Parent $v5Path) 'mods') 'mod-settings.dat'
  $v5SettingsSha = '12E25E98BD5133CC19CC8E59B0B1FE6A2BDBF097F9468BCD2A9FF290F4C17356'
  Assert-K2Migration (Test-Path -LiteralPath $v5SettingsPath -PathType Leaf) 'v5-mod-settings-missing'
  Assert-K2Migration ((Get-K2MigrationSha $v5SettingsPath) -ceq $v5SettingsSha) 'v5-mod-settings-sha256'
  $cap0SettingsPreview = Get-K2Cap0SettingsMutation -SourcePath $v5SettingsPath -ExpectedSourceSha $v5SettingsSha
  $dependencyInputs = @()
  foreach ($fileName in $expectedDependencies.Keys) {
    $matches = @($v5.staged_inputs | Where-Object { [IO.Path]::GetFileName([string]$_.source_path) -ceq $fileName })
    Assert-K2Migration ($matches.Count -eq 1 -and [bool]$matches[0].source_match -and [bool]$matches[0].stage_match) "v5-dependency-record:$fileName"
    $entry = $matches[0]
    $source = (Resolve-Path -LiteralPath ([string]$entry.source_path)).Path
    Assert-K2Migration ((Get-K2MigrationSha $source) -ceq [string]$entry.sha256) "v5-dependency-sha256:$fileName"
    $info = Get-K2MigrationZipInfo $source
    Assert-K2Migration ([string]$info.name -ceq $expectedDependencies[$fileName][0] -and [string]$info.version -ceq $expectedDependencies[$fileName][1]) "v5-dependency-identity:$fileName"
    $dependencyInputs += [pscustomobject]@{file_name=$fileName;source_path=$source;sha256=[string]$entry.sha256}
  }
  $fixtureRoot = Join-Path $RepoRoot $fixtureRelative
  foreach ($name in @('info.json','control.lua')) { Assert-K2Migration (Test-Path -LiteralPath (Join-Path $fixtureRoot $name) -PathType Leaf) "fixture-file:$name" }
  $fixtureInfo = Read-K2MigrationJson (Join-Path $fixtureRoot 'info.json') 'fixture-info'
  Assert-K2Migration ([string]$fixtureInfo.name -ceq $fixtureName -and [string]$fixtureInfo.version -ceq '0.1.0') 'fixture-identity'
  $plannedRunRoot = Join-Path $outputRootFull ('r-' + ('0' * 20))
  $plannedRuntimePaths = @()
  $plannedCases = @(
    [pscustomobject]@{name='cap3-pinned';old_version='0.1.0';current_version='0.1.1'},
    [pscustomobject]@{name='cap0-headroom';old_version='0.1.0';current_version='0.1.2'}
  )
  foreach ($plannedCase in $plannedCases) {
    $plannedPredecessorUserdata = Join-Path $plannedRunRoot "$($plannedCase.name)/predecessor/userdata"
    $plannedCurrentUserdata = Join-Path $plannedRunRoot "$($plannedCase.name)/current/userdata"
    $plannedRuntimePaths += Join-Path (Join-Path $plannedPredecessorUserdata 'mods') "$fixtureName`_$($plannedCase.old_version).zip"
    $plannedRuntimePaths += Join-Path (Join-Path $plannedCurrentUserdata 'mods') "$fixtureName`_$($plannedCase.current_version).zip"
    $scenario = "k2-213-imersite-migration-$($plannedCase.name)-predecessor"
    $plannedRuntimePaths += Join-Path (Join-Path $plannedPredecessorUserdata 'saves') "$scenario.zip"
    $plannedRuntimePaths += Join-Path (Join-Path $plannedCurrentUserdata 'saves') 'k2-213-imersite-migration-upgraded.zip'
    $plannedRuntimePaths += Join-Path $plannedCurrentUserdata "k2-213-imersite-migration-$($plannedCase.name).reload-01.factorio.log"
  }
  foreach ($plannedPath in $plannedRuntimePaths) {
    Assert-MIRFactorioPathBudget -Path $plannedPath -Context 'K2 migration runtime output path'
  }
  $longestPlannedPath = $plannedRuntimePaths | Sort-Object { $_.Length } -Descending | Select-Object -First 1

  if ($PreflightOnly) {
    [pscustomobject][ordered]@{status='passed-preflight-only';scope='exact-K2-2.1.3-Imersite-powder-predecessor-upgrade-to-PR411-under-cap-three-and-headroom-bounded-cap-zero';old_candidate_sha256=$oldCandidateSha;new_candidate_sha256=$newCandidateSha;v5_result_sha256=$v5ResultSha;v5_observation_save_sha256=$v5SaveSha;v5_settings_sha256=$v5SettingsSha;cap3=$([ordered]@{configured=3;settings_sha256=$v5SettingsSha;source_value=3});cap0=$cap0SettingsPreview;engine_sha256=$engineSha;runtime_api_sha256=$runtimeApiSha;dependency_count=$dependencyInputs.Count;fixture_path=$fixtureRelative;path_budget=[ordered]@{limit_chars=240;maximum_chars=$longestPlannedPath.Length;headroom_chars=(240-$longestPlannedPath.Length);maximum_path=$longestPlannedPath};execution_started=$false} | ConvertTo-Json -Depth 20
    return
  }

  [IO.Directory]::CreateDirectory($outputRootFull) | Out-Null
  do {
    $runRootName = 'r-' + [guid]::NewGuid().ToString('N').Substring(0,20)
    $runRoot = Join-Path $outputRootFull $runRootName
  } while (Test-Path -LiteralPath $runRoot)
  [IO.Directory]::CreateDirectory($runRoot) | Out-Null
  $settingsDirectory = Join-Path $runRoot 'settings-profiles'
  [IO.Directory]::CreateDirectory($settingsDirectory) | Out-Null
  $cap0SettingsPath = Join-Path $settingsDirectory 'mod-settings-cap0.dat'
  $cap0SettingsMutation = Get-K2Cap0SettingsMutation -SourcePath $v5SettingsPath -ExpectedSourceSha $v5SettingsSha -OutputPath $cap0SettingsPath
  $settingsCases = @(
    [pscustomobject]@{name='cap3-pinned';cap=3;settings_path=$v5SettingsPath;settings_sha=$v5SettingsSha;old_version='0.1.0';current_version='0.1.1'},
    [pscustomobject]@{name='cap0-headroom';cap=0;settings_path=$cap0SettingsPath;settings_sha=[string]$cap0SettingsMutation.patched_sha256;old_version='0.1.0';current_version='0.1.2'}
  )
  $caseResults = @()
  foreach ($case in $settingsCases) {
    $caseRoot = Join-Path $runRoot $case.name
    $oldRoot = Join-Path $caseRoot 'predecessor'
    $newRoot = Join-Path $caseRoot 'current'
    [IO.Directory]::CreateDirectory($oldRoot) | Out-Null
    [IO.Directory]::CreateDirectory($newRoot) | Out-Null
    $oldStage = Initialize-K2MigrationStage -Name "$($case.name)-predecessor" -Role 'predecessor' -Version $case.old_version -ExpectedCap $case.cap -SettingsSourcePath $case.settings_path -SettingsExpectedSha $case.settings_sha -StageDirectory $oldRoot -RunRoot $oldRoot
    $newStage = Initialize-K2MigrationStage -Name "$($case.name)-current" -Role 'current' -Version $case.current_version -ExpectedCap $case.cap -SettingsSourcePath $case.settings_path -SettingsExpectedSha $case.settings_sha -StageDirectory $newRoot -RunRoot $newRoot
    $activeStages += @($oldStage,$newStage)
    foreach ($stageFixture in @(@($oldStage,$case.old_version),@($newStage,$case.current_version))) {
      Assert-MIRFactorioPathBudget -Path (Join-Path $stageFixture[0].mods "$fixtureName`_$($stageFixture[1]).zip") -Context "K2 $($case.name) fixture archive path"
    }

    $oldLoad = Invoke-MIRFactorioLoadCheck -FactorioBin $engine -UserDataDir $oldStage.userdata -ScenarioName "k2-213-imersite-migration-$($case.name)-predecessor" -ScenarioTimeoutSeconds $CreateTimeoutSeconds
    if (-not ([bool]$oldLoad.passed -and [int]$oldLoad.exit_code -eq 0 -and -not [bool]$oldLoad.timed_out)) {
      $errorLines = @(Select-String -LiteralPath ([string]$oldLoad.stdout) -Pattern 'validation failed:', 'Error while running event', '^Error:' |
        Select-Object -Last 3 | ForEach-Object { $_.Line.Trim() })
      Fail-K2Migration ("$($case.name)-predecessor-create exit=$($oldLoad.exit_code) timed_out=$($oldLoad.timed_out) stdout=$($oldLoad.stdout) details=$($errorLines -join ' | ')")
    }
    Assert-K2Migration ([string]$oldLoad.stderr_sha256 -ceq 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855') "$($case.name)-predecessor-create-stderr"
    $oldSave = [string]$oldLoad.save
    $oldMarker = "[MIR42_K2_213_IMERSITE_MIGRATION] stage=predecessor;cap=$($case.cap);legacy=1-3;powder=0.06;crystal=0.10;stable=copper-3;progress=0.42"
    $oldLogText = [IO.File]::ReadAllText([string]$oldLoad.factorio_log)
    Assert-K2Migration ($oldLogText.Contains($oldMarker,[StringComparison]::Ordinal)) "$($case.name)-predecessor-marker"
    Assert-K2Migration (Test-Path -LiteralPath $oldSave -PathType Leaf) "$($case.name)-predecessor-save-missing"
    $oldSaveShaBefore = Get-K2MigrationSha $oldSave
    $oldSettingsAfterCreate = Get-K2MigrationSha $oldStage.settings_path

    $newSave = Join-Path $newStage.userdata 'saves/k2-213-imersite-migration-upgraded.zip'
    if ($case.cap -eq 3) {
      $upgradeMarker = '[MIR42_K2_213_IMERSITE_MIGRATION] stage=upgrade-save;cap=3;legacy=1-3;powder=0.06;crystal=0.10;continuation=withheld;stable=copper-3;progress=0.42'
      $reloadMarker = '[MIR42_K2_213_IMERSITE_MIGRATION] stage=reload;cap=3;legacy=1-3;powder=0.06;crystal=0.10;continuation=withheld;stable=copper-3;progress=0.42'
    } else {
      $upgradeMarker = '[MIR42_K2_213_IMERSITE_MIGRATION] stage=upgrade-save;cap=0;legacy=1-3;powder=0.06;crystal=0.10;continuation_level=4;stable=copper-3;progress=0.42'
      $reloadMarker = '[MIR42_K2_213_IMERSITE_MIGRATION] stage=reload;cap=0;legacy=1-3;powder=0.06;crystal=0.10;continuation_level=4;stable=copper-3;progress=0.42'
    }
    $upgradeLog = Invoke-K2MigrationServerUpgrade -Stage $newStage -InputSave $oldSave -ExpectedSave $newSave -ExpectedMarker $upgradeMarker
    if ($case.cap -eq 0) { Assert-K2HeadroomDiagnostic -LogPath $upgradeLog -StageName 'cap0-upgrade' }
    Assert-K2Migration ((Get-K2MigrationSha $oldSave) -ceq $oldSaveShaBefore) "$($case.name)-predecessor-save-mutated"
    $newSettingsAfterUpgrade = Get-K2MigrationSha $newStage.settings_path
    $reload = Invoke-MIRFactorioReloadContract -FactorioBin $engine -UserDataDir $newStage.userdata -ScenarioName "k2-213-imersite-migration-$($case.name)" -SavePath $newSave -RequiredReloadCount 1 -MaxReloadDurationSeconds $ReloadTimeoutSeconds -RequiredLogFragments $reloadMarker
    Assert-K2Migration ([bool]$reload.passed) "$($case.name)-current-package-reload"
    if ($case.cap -eq 0) { Assert-K2HeadroomDiagnostic -LogPath ([string]$reload.reloads[0].factorio_log) -StageName 'cap0-reload' }
    $newSettingsAfterReload = Get-K2MigrationSha $newStage.settings_path
    Assert-K2Migration ((Get-K2MigrationSha $v5SettingsPath) -ceq $v5SettingsSha) 'pinned-v5-settings-source-mutated'
    Assert-K2Migration ((Get-K2MigrationSha $cap0SettingsPath) -ceq [string]$cap0SettingsMutation.patched_sha256) 'cap0-settings-profile-mutated'

    $oldTerminal = Complete-MIRImmutableInputLease -Lease $oldStage.lease
    $oldStage.lease = $null
    $newTerminal = Complete-MIRImmutableInputLease -Lease $newStage.lease
    $newStage.lease = $null
    $null = Assert-MIRImmutableInputTerminalReceipt -Receipt $oldTerminal -Context "$($case.name) predecessor immutable inputs"
    $null = Assert-MIRImmutableInputTerminalReceipt -Receipt $newTerminal -Context "$($case.name) current immutable inputs"
    $oldLogArtifact = Get-K2MigrationArtifact ([string]$oldLoad.factorio_log)
    $reloadLogArtifact = Get-K2MigrationArtifact ([string]$reload.reloads[0].factorio_log)
    $caseResults += [ordered]@{
      name=$case.name;configured_cap=[int]$case.cap
      settings_profile=[ordered]@{source=Get-K2MigrationArtifact ([string]$case.settings_path) -External:$([string]$case.settings_path -ceq $v5SettingsPath);initial_sha256=[string]$case.settings_sha;predecessor_stage=[ordered]@{before_engine=$oldStage.settings_initial_sha256;after_create=$oldSettingsAfterCreate};current_stage=[ordered]@{before_engine=$newStage.settings_initial_sha256;after_upgrade=$newSettingsAfterUpgrade;after_reload=$newSettingsAfterReload}}
      predecessor_candidate=Get-K2MigrationArtifact $oldCandidate -External;current_candidate=Get-K2MigrationArtifact $newCandidate -External
      predecessor_save=[ordered]@{artifact=Get-K2MigrationArtifact $oldSave;sha256_before_upgrade=$oldSaveShaBefore;sha256_after_upgrade=Get-K2MigrationSha $oldSave};upgraded_save=Get-K2MigrationArtifact $newSave
      predecessor_create_log=$oldLogArtifact;upgrade_log=Get-K2MigrationArtifact $upgradeLog;reload_log=$reloadLogArtifact
      predecessor_input_lease=$oldTerminal;current_input_lease=$newTerminal;reload=$reload
      expected_outcome=if($case.cap -eq 3){'continuation-withheld-by-absolute-cap'}else{'level-four-continuation-available-through-recipe-headroom'}
      earned_effects=[ordered]@{legacy_levels='1-3';powder_productivity_bonus=0.06;native_crystal_productivity_bonus=0.10;stable_research='recipe-prod-research_copper-1';stable_level=3;fractional_progress=0.42}
      continuation=[ordered]@{identity='recipe-prod-research_material_imersite-4';available=($case.cap -eq 0);starting_level=if($case.cap -eq 0){4}else{$null}}
    }
    $activeStages = @($activeStages | Where-Object { $null -ne $_.lease })
  }
  Assert-K2Migration ((Get-K2MigrationSha $v5SettingsPath) -ceq $v5SettingsSha) 'pinned-v5-settings-source-mutated-after-campaign'
  Assert-K2Migration ((Get-K2MigrationSha $cap0SettingsPath) -ceq [string]$cap0SettingsMutation.patched_sha256) 'cap0-settings-source-mutated-after-campaign'
  $result = [ordered]@{
    schema=1;kind='MIR42K2213ImersitePredecessorMigrationResultV1';status='passed';generated_at=(Get-Date).ToUniversalTime().ToString('o')
    scope='exact-K2-2.1.3-K2SO-2.0.13-old-F210-package-to-PR411-migration-at-pinned-cap-three-and-controlled-cap-zero'
    qualification=$false;support_claim=$false;release_authority=$false;publication=$false
    candidates=[ordered]@{predecessor=Get-K2MigrationArtifact $oldCandidate -External;current=Get-K2MigrationArtifact $newCandidate -External;predecessor_expected_sha256=$oldCandidateSha;current_expected_sha256=$newCandidateSha}
    v5_observation=[ordered]@{result=Get-K2MigrationArtifact $v5Path -External;result_sha256=$v5ResultSha;old_candidate_sha256=[string]$v5.candidate.sha256;observation_save=Get-K2MigrationArtifact $v5SavePath -External;observation_save_sha256=$v5SaveSha;role='exact-engine-and-dependency-lock-only-not-progressed-save'}
    engine=[ordered]@{path=(Get-K2MigrationIdentity $engine -External).path;path_kind='external-input-file';product_version='2.1.20';sha256=$engineSha;runtime_api_sha256=$runtimeApiSha}
    fixture=[ordered]@{path=$fixtureRelative;info=Get-K2MigrationArtifact (Join-Path $fixtureRoot 'info.json');control=Get-K2MigrationArtifact (Join-Path $fixtureRoot 'control.lua');predecessor_version='0.1.0';current_versions=@('0.1.1','0.1.2')}
    dependency_count=$dependencyInputs.Count
    startup_settings=[ordered]@{pinned_cap_three=[ordered]@{source=Get-K2MigrationArtifact $v5SettingsPath -External;configured_cap=3;initial_sha256=$v5SettingsSha};controlled_cap_zero=$cap0SettingsMutation;pinned_source_unchanged=$true;cap0_profile_source_unchanged=$true}
    cases=$caseResults
    non_claims=@('The V5 forward-path observation save is not used as a progressed predecessor.','Cap zero is configured unbounded only within the material recipe-headroom maximum.','The exact two-setting-case transition is not broad K2 support or ecosystem qualification.','No release, signing, or publication authority.')
  }
  $resultPath = Join-Path $runRoot 'result.json'
  [IO.File]::WriteAllText($resultPath,(($result | ConvertTo-Json -Depth 100 -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
  Write-Host "[MIR42_K2_213_IMERSITE_MIGRATION_RUNTIME] $((Get-K2MigrationIdentity $resultPath).path)"
} catch {
  $failure = $_.Exception.Message
  foreach ($stage in @($activeStages)) {
    if ($null -ne $stage -and $null -ne $stage.lease -and -not [bool]$stage.lease.closed) {
      try { $null = Complete-MIRImmutableInputLease -Lease $stage.lease -Outcome failed } catch {}
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($runRoot) -and (Test-Path -LiteralPath $runRoot -PathType Container)) {
    $failed = [ordered]@{schema=1;kind='MIR42K2213ImersitePredecessorMigrationResultV1';status='failed';generated_at=(Get-Date).ToUniversalTime().ToString('o');failure=$failure;scope='exact-K2-2.1.3-K2SO-2.0.13-old-F210-package-to-PR411-Imersite-powder-continuation-save-migration';qualification=$false;support_claim=$false;release_authority=$false;publication=$false}
    [IO.File]::WriteAllText((Join-Path $runRoot 'result.json'),(($failed | ConvertTo-Json -Depth 30 -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
  }
  throw
}
