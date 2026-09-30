# MIR4-CANONICAL-EXECUTABLE-TEST
<#!
.SYNOPSIS
Runs one fresh, exact F210/Krastorio2/K2SO Imersite-continuation create and
single reload.  V5 is a dependency/engine observation lock only: this command
never treats its candidate, result, or private plan as an admission authority.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$CandidateZip,
  [Parameter(Mandatory)][string]$SourceMaterializationPath,
  [Parameter(Mandatory)][string]$V5ObservationResultPath,
  [string]$RepoRoot = '',
  [string]$OutputRoot = 'build/tests/k2-213-imersite-continuation',
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

function Fail-K2213 { param([string]$Code) throw "[mir42-k2-213-imersite] $Code" }
function Assert-K2213 { param([bool]$Condition,[string]$Code) if (-not $Condition) { Fail-K2213 $Code } }
function Get-K2213Sha256 { param([Parameter(Mandatory)][string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Get-K2213Property { param($Object,[string]$Name,$Default=$null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
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
    'base: "2.1.20"',
    'Krastorio2: "2.1.3"',
    'Krastorio2-spaced-out: "2.0.13"',
    'more-infinite-research: "4.2.21000"'
  )
  foreach ($line in $required) { Assert-K2213 ($body.Contains($line,[StringComparison]::Ordinal)) "registered-fixture-field:$line" }
  return [pscustomobject][ordered]@{id=$fixtureId;path='fixtures/assert-k2-213-imersite-continuation';raw_sha256=Get-K2213Sha256 $Path}
}
function New-K2213FailureResult {
  param([string]$RunRoot,[string]$Message,$Lease)
  if ([string]::IsNullOrWhiteSpace($RunRoot) -or -not (Test-Path -LiteralPath $RunRoot -PathType Container)) { return }
  $terminal = $null
  if ($null -ne $Lease -and -not [bool]$Lease.closed) {
    try { $terminal = Complete-MIRImmutableInputLease -Lease $Lease -Outcome failed } catch {}
  }
  $record = [ordered]@{
    schema=1;kind='MIR42K2213ImersiteContinuationRuntimeResultV1';status='failed';
    generated_at=(Get-Date).ToUniversalTime().ToString('o');failure=[string]$Message;
    scope='exact-current-f210-k2-k2so-imersite-powder-continuation-create-and-single-reload';
    qualification=$false;support_claim=$false;release_authority=$false;publication=$false;
    immutable_input_staging=$terminal
  }
  [IO.File]::WriteAllText((Join-Path $RunRoot 'result.json'),(($record | ConvertTo-Json -Depth 100 -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
}

$runRoot = ''
$lease = $null
try {
  $engine = (Resolve-Path -LiteralPath $FactorioBin).Path
  $candidate = (Resolve-Path -LiteralPath $CandidateZip).Path
  $materializationPath = (Resolve-Path -LiteralPath $SourceMaterializationPath).Path
  $v5Path = (Resolve-Path -LiteralPath $V5ObservationResultPath).Path
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
  Assert-K2213 ([string]$fixtureInfo.version -ceq '0.1.0') 'fixture-version'
  Assert-K2213 ([string]$fixtureInfo.factorio_version -ceq '2.1') 'fixture-factorio-version'
  $fixtureDependencies = @($fixtureInfo.dependencies | ForEach-Object {[string]$_})
  foreach ($dependency in @('base >= 2.1.20','Krastorio2 = 2.1.3','Krastorio2-spaced-out = 2.0.13','more-infinite-research = 4.2.21000')) {
    Assert-K2213 ($fixtureDependencies -contains $dependency) "fixture-dependency:$dependency"
  }

  $materialization = Read-K2213Json -Path $materializationPath -Code 'materialization'
  Assert-K2213 ([int]$materialization.schema -eq 1 -and [string]$materialization.kind -ceq 'MIR4PackageCompositionResultV1') 'materialization-schema'
  Assert-K2213 ([string]$materialization.status -ceq 'passed-canonical-package-authority-materialization') 'materialization-status'
  Assert-K2213 (Test-MIR4BootstrapRecordHash -Record $materialization) 'materialization-record-integrity'
  Assert-K2213 ([string]$materialization.target -ceq 'f210') 'materialization-target'
  Assert-K2213 ([string]$materialization.source_version -ceq '4.2.0' -and [string]$materialization.distribution_version -ceq '4.2.21000') 'materialization-version'
  Assert-K2213 ([bool]$materialization.invariants.canonical_package_authority) 'materialization-canonical'
  Assert-K2213 ((Resolve-Path -LiteralPath ([string]$materialization.archive_path)).Path -ceq $candidate) 'materialization-candidate-path'
  Assert-K2213 ((Get-K2213Sha256 $candidate) -ceq [string]$materialization.archive_sha256) 'materialization-candidate-sha256'
  Assert-K2213 ([string]$materialization.record_sha256 -match '^[0-9A-F]{64}$') 'materialization-record-sha256'
  Assert-K2213ArchiveIdentity -Path $candidate -ExpectedName 'more-infinite-research' -ExpectedVersion '4.2.21000' -ExpectedSha256 ([string]$materialization.archive_sha256)

  $v5 = Read-K2213Json -Path $v5Path -Code 'v5-observation'
  Assert-K2213 ([int]$v5.schema -eq 1 -and [string]$v5.kind -ceq 'MIR42ExactK2213ForwardPathObservationResultV3' -and [string]$v5.status -ceq 'passed') 'v5-schema-status'
  foreach ($forbiddenClaim in @('qualification','support_claim','release_authority','publication')) { Assert-K2213 (-not [bool](Get-K2213Property $v5 $forbiddenClaim $true)) "v5-must-remain-non-authorizing:$forbiddenClaim" }
  $v5Mods = Get-K2213Property $v5 'exact_mods'
  foreach ($pair in @(@('base','2.1.20'),@('Krastorio2','2.1.3'),@('Krastorio2-spaced-out','2.0.13'),@('more-infinite-research','4.2.21000'))) {
    Assert-K2213 ([string](Get-K2213Property $v5Mods $pair[0] '') -ceq $pair[1]) "v5-exact-mod:$($pair[0])"
  }
  $engineHash = Get-K2213Sha256 $engine
  Assert-K2213 ($engineHash -ceq [string]$v5.engine.sha256) 'engine-sha256'
  $engineVersion = (& $engine --version | Out-String).Trim()
  Assert-K2213 ($LASTEXITCODE -eq 0 -and $engineVersion -match '(?m)^Version:\s*2[.]1[.]20(?:\s|$)') 'engine-version'
  Assert-K2213 ([string]$v5.engine.product_version -ceq '2.1.20') 'v5-engine-version'
  $engineRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $engine))
  $runtimeApi = Join-Path $engineRoot 'doc-html/runtime-api.json'
  Assert-K2213 ((Get-K2213Sha256 $runtimeApi) -ceq [string]$v5.engine.bundled_runtime_api_sha256) 'engine-runtime-api'

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
  $lockEntries = @($v5.staged_inputs)
  Assert-K2213 ($lockEntries.Count -ge $expectedDependencies.Count) 'v5-staged-input-count'
  $inputs = @()
  foreach ($fileName in $expectedDependencies.Keys) {
    $matches = @($lockEntries | Where-Object { [IO.Path]::GetFileName([string]$_.source_path) -ceq $fileName })
    Assert-K2213 ($matches.Count -eq 1) "v5-dependency-lock:$fileName"
    $entry = $matches[0]
    Assert-K2213 ([bool]$entry.source_match -and [bool]$entry.stage_match -and ([string]$entry.sha256 -match '^[0-9A-F]{64}$')) "v5-dependency-lock-integrity:$fileName"
    $source = (Resolve-Path -LiteralPath ([string]$entry.source_path)).Path
    Assert-K2213ArchiveIdentity -Path $source -ExpectedName $expectedDependencies[$fileName][0] -ExpectedVersion $expectedDependencies[$fileName][1] -ExpectedSha256 ([string]$entry.sha256)
    $inputs += [ordered]@{source_path=$source;file_name=$fileName;expected_sha256=[string]$entry.sha256;role='dependency-mod';identity=[ordered]@{name=$expectedDependencies[$fileName][0];version=$expectedDependencies[$fileName][1];archive=$fileName};provenance=[ordered]@{kind='v5-observation-dependency-lock';v5_result_sha256=Get-K2213Sha256 $v5Path};immutable=$true}
  }
  $inputs += [ordered]@{source_path=$candidate;file_name=([IO.Path]::GetFileName($candidate));expected_sha256=([string]$materialization.archive_sha256);role='candidate';identity=[ordered]@{name='more-infinite-research';version='4.2.21000';materialization_record_sha256=[string]$materialization.record_sha256};provenance=[ordered]@{kind='current-candidate-materialization';raw_materialization_sha256=Get-K2213Sha256 $materializationPath};immutable=$true}

  if ($PreflightOnly) {
    [pscustomobject][ordered]@{
      status='passed-preflight-only'
      scope='exact-current-f210-k2-k2so-imersite-continuation-input-and-envelope-validation'
      candidate_sha256=[string]$materialization.archive_sha256
      materialization_sha256=Get-K2213Sha256 $materializationPath
      v5_observation_sha256=Get-K2213Sha256 $v5Path
      engine_sha256=$engineHash
      runtime_api_sha256=Get-K2213Sha256 $runtimeApi
      fixture_registry_sha256=$fixtureRegistry.raw_sha256
      dependency_count=$expectedDependencies.Count
      execution_started=$false
    } | ConvertTo-Json -Depth 20
    return
  }

  [IO.Directory]::CreateDirectory($outputRootFull) | Out-Null
  $runRoot = Join-Path $outputRootFull ('run-' + [guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($runRoot) | Out-Null
  $mods = Join-Path $runRoot 'mods'
  [IO.Directory]::CreateDirectory($mods) | Out-Null
  [IO.Directory]::CreateDirectory((Join-Path $runRoot 'saves')) | Out-Null
  $lease = New-MIRImmutableInputLease -RunRoot $runRoot -StageDirectory $mods -Inputs $inputs
  $fixtureArchive = Publish-MIRModDirectoryArchive -Source $fixtureRoot -Name ([string]$fixtureInfo.name) -Version ([string]$fixtureInfo.version) -ModsDir $mods
  Assert-K2213ArchiveIdentity -Path $fixtureArchive -ExpectedName ([string]$fixtureInfo.name) -ExpectedVersion ([string]$fixtureInfo.version) -ExpectedSha256 (Get-K2213Sha256 $fixtureArchive)
  # V5's exact current K2SO lock includes the four bundled Space Age modules.
  # They are part of the observed profile, rather than an inferred DLC choice.
  $enabled = @('base','elevated-rails','quality','recycler','space-age','flib','k2so-assets','Krastorio2','Krastorio2-spaced-out','Krastorio2Assets','Krastorio2MenuSimulations','xy-k2so-enhancements-nulls-fork','mir-validation-settings-overrides','more-infinite-research',[string]$fixtureInfo.name)
  Write-MIRModList -ModsDir $mods -EnabledMods $enabled
  $modListPath = Join-Path $mods 'mod-list.json'
  $modList = Read-K2213Json -Path $modListPath -Code 'mod-list'
  $enabledRows = @($modList.mods | Where-Object {[bool]$_.enabled} | ForEach-Object {[string]$_.name} | Sort-Object)
  Assert-K2213 ((@($enabledRows) -join '|') -ceq (@($enabled | Sort-Object) -join '|')) 'mod-list-exact-enabled-closure'
  foreach ($dlc in @('elevated-rails','quality','recycler','space-age')) {
    $row = @($modList.mods | Where-Object {[string]$_.name -ceq $dlc})
    Assert-K2213 ($row.Count -eq 1 -and [bool]$row[0].enabled) "mod-list-observed-dlc:$dlc"
  }
  # The continuation fixture proves the current declaration's default zero
  # configuration.  It never inherits a settings file that V5 did not hash.
  Assert-K2213 (-not (Test-Path -LiteralPath (Join-Path $mods 'mod-settings.dat') -PathType Leaf)) 'unexpected-unbound-mod-settings'

  $load = Invoke-MIRFactorioLoadCheck -FactorioBin $engine -UserDataDir $runRoot -ScenarioName 'k2-213-imersite-continuation' -ScenarioTimeoutSeconds $CreateTimeoutSeconds
  Assert-K2213 ([bool]$load.passed -and -not [bool]$load.timed_out -and [int]$load.exit_code -eq 0) 'create'
  Assert-K2213 ([string]$load.stderr_sha256 -ceq 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855') 'create-stderr'
  $loadLog = [IO.File]::ReadAllText([string]$load.factorio_log)
  Assert-K2213 ($loadLog.Contains('[MIR42_K2_213_IMERSITE_CONTINUATION_DATA]',[StringComparison]::Ordinal)) 'create-data-marker'
  Assert-K2213 ($loadLog.Contains('[MIR42_K2_213_IMERSITE_CONTINUATION] stage=initial;completed_level=4;next_level=5;bonus=0.08;progress=0.42',[StringComparison]::Ordinal)) 'create-initial-marker'
  $reload = Invoke-MIRFactorioReloadContract -FactorioBin $engine -UserDataDir $runRoot -ScenarioName 'k2-213-imersite-continuation' -SavePath $load.save -RequiredReloadCount 1 -MaxReloadDurationSeconds $ReloadTimeoutSeconds -RequiredLogFragments '[MIR42_K2_213_IMERSITE_CONTINUATION] stage=reload;completed_level=4;next_level=5;bonus=0.08;progress=0.42'
  Assert-K2213 ([bool]$reload.passed) 'single-reload'
  $terminal = Complete-MIRImmutableInputLease -Lease $lease
  $lease = $null
  $null = Assert-MIRImmutableInputTerminalReceipt -Receipt $terminal -Context 'K2 2.1.3 Imersite continuation input staging'
  $dependencyArtifacts = @($terminal.inputs | Where-Object {[string]$_.role -ceq 'dependency-mod'} | ForEach-Object { ConvertTo-MIRImmutableInputArtifact -Receipt $terminal -InputRecord $_ -Locator (Get-K2213Relative ([string]$_.stage_path)) })
  $candidateInput = @($terminal.inputs | Where-Object {[string]$_.role -ceq 'candidate'})
  Assert-K2213 ($candidateInput.Count -eq 1) 'terminal-candidate-input'
  $candidateArtifact = ConvertTo-MIRImmutableInputArtifact -Receipt $terminal -InputRecord $candidateInput[0] -Locator (Get-K2213Relative ([string]$candidateInput[0].stage_path))
  $result = [ordered]@{
    schema=1;kind='MIR42K2213ImersiteContinuationRuntimeResultV1';status='passed';generated_at=(Get-Date).ToUniversalTime().ToString('o');
    scope='exact-current-f210-k2-k2so-imersite-powder-continuation-create-and-single-reload';
    qualification=$false;support_claim=$false;release_authority=$false;publication=$false;
    candidate=[ordered]@{archive=$candidateArtifact;materialization=Get-K2213Artifact $materializationPath;materialization_record_sha256=[string]$materialization.record_sha256;package_source_sha256=[string]$materialization.package_source_sha256};
    predecessor_observation_lock=[ordered]@{result=Get-K2213Artifact $v5Path -AllowExternalInput;kind=[string]$v5.kind;status=[string]$v5.status;role='exact-engine-and-dependency-archive-lock-only';old_candidate_sha256=[string]$v5.candidate.sha256};
    engine=[ordered]@{path=Get-K2213PathIdentity $engine -AllowExternalInput;product_version='2.1.20';executable_sha256=$engineHash;bundled_runtime_api_sha256=Get-K2213Sha256 $runtimeApi};
    fixture=[ordered]@{registration=$fixtureRegistry;files=@(Get-K2213Artifact $fixtureInfoPath;Get-K2213Artifact $fixtureDataPath;Get-K2213Artifact $fixtureControlPath);archive=Get-K2213Artifact $fixtureArchive};
    input_staging=$terminal;dependency_archives=@($dependencyArtifacts | Sort-Object path);mod_list=Get-K2213Artifact $modListPath;startup_settings='candidate-defaults-no-unbound-mod-settings';
    create=[ordered]@{duration_seconds=$load.duration_seconds;save=Get-K2213Artifact $load.save;stdout=Get-K2213Artifact $load.stdout;stderr=Get-K2213Artifact $load.stderr;factorio_log=Get-K2213Artifact $load.factorio_log};
    reload=$reload;
    non_claims=@('The supplied V5 observation remains non-authorizing and is not rebound.','Only generated MIR Imersite powder continuation is exercised. Native Imersite crystal ownership and witnessed withheld K2 routes remain outside this receipt.','No player delivery, broad K2 admission, support, release, signing, or publication claim.')
  }
  $resultPath = Join-Path $runRoot 'result.json'
  [IO.File]::WriteAllText($resultPath,(($result | ConvertTo-Json -Depth 100 -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
  Write-Host "[MIR42_K2_213_IMERSITE_CONTINUATION_RUNTIME] $(Get-K2213Relative $resultPath)"
} catch {
  $failure = $_.Exception.Message
  New-K2213FailureResult -RunRoot $runRoot -Message $failure -Lease $lease
  throw
}
