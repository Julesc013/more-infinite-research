# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [Parameter(Mandatory)][string]$PlanPath,
  [Parameter(Mandatory)][string]$SummaryPath,
  [Parameter(Mandatory)][string]$RuntimeResultPath,
  [Parameter(Mandatory)][string]$FactorioBin,
  [string]$ConfigurationSourceRoot = 'build/synthesis-20260906/k2-engine-candidate/runs/u-ad28370088e7/mods',
  [string]$OutputPath = 'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-execution-proof.json'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/mir/application/assurance/EnvironmentEvidence.ps1')

function Assert-A03Proof { param([bool]$Condition,[string]$Code) if (-not $Condition) { throw "[$Code]" } }
function Get-A03ProofSha256 { param([string]$Path) (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }
function Get-A03ProofTextSha256 {
  param([AllowEmptyString()][string]$Value)
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Value)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
}
function Get-A03ProofAssuranceJsonHash { param($Value) Get-A03ProofTextSha256 (($Value | ConvertTo-Json -Depth 40 -Compress)) }
function Test-A03ProofRuntimeMarkerBinding {
  param([string]$MarkerPath,[string]$MarkerRecordSha256,[string]$ExpectedRuntimePath,$RuntimeRecord)
  try {
    $markerFull = [IO.Path]::GetFullPath($MarkerPath)
    return $markerFull.Equals($ExpectedRuntimePath,[StringComparison]::OrdinalIgnoreCase) -and
      $MarkerRecordSha256 -cmatch '^[A-F0-9]{64}$' -and
      $MarkerRecordSha256 -ceq [string]$RuntimeRecord.record_sha256 -and
      (Test-MIR4BootstrapRecordHash $RuntimeRecord)
  } catch { return $false }
}
function ConvertTo-A03ProofAssuranceTimestamp {
  param($Value)
  ([DateTimeOffset]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)
}
function Get-A03ProofCapsuleDigest {
  param($Capsule)
  $material = [ordered]@{
    schema=[int]$Capsule.schema;test_id=[string]$Capsule.test_id;conclusion=[string]$Capsule.conclusion
    input_key=[string]$Capsule.input_key;fingerprint_sha256=[string]$Capsule.fingerprint_sha256;definition_sha256=[string]$Capsule.definition_sha256
    target=[string]$Capsule.target;command=[string]$Capsule.command;resolved_command=[string]$Capsule.resolved_command;inputs=$Capsule.inputs;producer=$Capsule.producer
    assertions=$Capsule.assertions;exit_code=[int]$Capsule.exit_code;result=$Capsule.result;artifacts=$Capsule.artifacts
    stdout_sha256=[string]$Capsule.stdout_sha256;stderr_sha256=[string]$Capsule.stderr_sha256;log_digest=[string]$Capsule.log_digest
    started_at=(ConvertTo-A03ProofAssuranceTimestamp $Capsule.started_at);completed_at=(ConvertTo-A03ProofAssuranceTimestamp $Capsule.completed_at);duration_seconds=[double]$Capsule.duration_seconds;message=[string]$Capsule.message
  }
  Get-A03ProofAssuranceJsonHash $material
}
function Resolve-A03ProofPath {
  param([string]$Path)
  $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repo $Path)) }
  $prefix = $repo.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  Assert-A03Proof ($full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) 'mir4-a03-proof-path-boundary'
  Assert-A03Proof (Test-Path -LiteralPath $full -PathType Leaf) 'mir4-a03-proof-input-missing'
  $full
}
function Get-A03ProofRelativePath {
  param([string]$Path)
  $full = Resolve-A03ProofPath $Path
  [IO.Path]::GetRelativePath($repo,$full).Replace('\','/')
}
function Get-A03ProofArtifact {
  param([string]$Path)
  $full = Resolve-A03ProofPath $Path
  [pscustomobject][ordered]@{path=(Get-A03ProofRelativePath $full);sha256=(Get-A03ProofSha256 $full);bytes=[long](Get-Item -LiteralPath $full).Length}
}
function Read-A03ProofJson { param([string]$Path) Get-Content -Raw -LiteralPath (Resolve-A03ProofPath $Path) | ConvertFrom-Json -Depth 100 -DateKind String }

$a00Relative = 'spec/programmes/evidence/synthesis-2026-09-10/a00-current-authority-observation.json'
$lockRelative = 'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-current.lock.json'
$a00Path = Resolve-A03ProofPath $a00Relative
$lockPath = Resolve-A03ProofPath $lockRelative
$a00 = Read-A03ProofJson $a00Path
$lock = Read-A03ProofJson $lockPath
Assert-A03Proof ((Get-Content -Raw -LiteralPath $a00Path) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-a00-current-authority-observation-v1.schema.json')) 'mir4-a03-proof-a00-schema'
Assert-A03Proof ((Get-Content -Raw -LiteralPath $lockPath) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/preview/mir4-environment-lock-v1.schema.json')) 'mir4-a03-proof-lock-schema'
Assert-A03Proof (Test-MIR4BootstrapRecordHash $a00) 'mir4-a03-proof-a00-hash'
Assert-A03Proof (Test-MIR4EnvironmentLockV1 $lock) 'mir4-a03-proof-lock'

$planFull = Resolve-A03ProofPath $PlanPath
$summaryFull = Resolve-A03ProofPath $SummaryPath
$runtimeFull = Resolve-A03ProofPath $RuntimeResultPath
$plan = Read-A03ProofJson $planFull
$summary = Read-A03ProofJson $summaryFull
$runtime = Read-A03ProofJson $runtimeFull
Assert-A03Proof ((Get-Content -Raw -LiteralPath $planFull) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/plan.schema.json')) 'mir4-a03-proof-plan-schema'
Assert-A03Proof ([string]$plan.digest_policy_ids.text -ceq 'utf8-nfc-lf-final-newline-v1' -and [string]$plan.digest_policy_ids.json -ceq 'json-sorted-properties-utf8-nfc-lf-final-newline-v1' -and @($plan.digest_policy_ids.PSObject.Properties).Count -eq 2) 'mir4-a03-proof-plan-digest-policy'
Assert-A03Proof (Test-MIR4BootstrapRecordHash $runtime) 'mir4-a03-proof-runtime-record'
$runtimeRoot = Split-Path -Parent $runtimeFull
$modsRoot = Join-Path $runtimeRoot 'mods'

$tests = @($plan.tests | Where-Object { [string]$_.id -ceq 'runtime.k2-k2so-f210-intake' })
Assert-A03Proof ($tests.Count -eq 1 -and [string]$tests[0].disposition -ceq 'RUN' -and [bool]$tests[0].force_fresh) 'mir4-a03-proof-plan-row'
$inputKey = [string]$tests[0].fingerprint.input_key
Assert-A03Proof ($inputKey -cmatch '^[A-F0-9]{64}$' -and [string]$tests[0].fingerprint.fingerprint_sha256 -ceq $inputKey) 'mir4-a03-proof-input-key'
Assert-A03Proof ([int]$plan.counts.total -eq 1 -and [int]$plan.counts.run -eq 1 -and [int]$plan.counts.reuse -eq 0 -and [int]$plan.counts.wait -eq 0 -and [int]$plan.counts.invalid -eq 0) 'mir4-a03-proof-plan-counts'
Assert-A03Proof ([string]$summary.status -ceq 'passed' -and [int]$summary.counts.total -eq 1 -and [int]$summary.counts.executed -eq 1 -and [int]$summary.counts.reused -eq 0 -and [int]$summary.counts.failed -eq 0 -and [int]$summary.counts.incomplete -eq 0 -and [int]$summary.counts.unexpected -eq 0) 'mir4-a03-proof-summary-counts'
Assert-A03Proof ([string]$summary.evidence.input_key -ceq $inputKey -and [string]$summary.evidence.fingerprint_sha256 -ceq $inputKey -and [string]$summary.evidence.status -ceq 'passed' -and [string]$summary.evidence.disposition -ceq 'RUN') 'mir4-a03-proof-summary-binding'

$attemptFull = Resolve-A03ProofPath ([string]$summary.evidence.attempt_path)
$attempt = Read-A03ProofJson $attemptFull
Assert-A03Proof ((($summary.evidence | ConvertTo-Json -Depth 100)) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/capsule.schema.json')) 'mir4-a03-proof-summary-capsule-schema'
Assert-A03Proof ((Get-Content -Raw -LiteralPath $attemptFull) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/capsule.schema.json')) 'mir4-a03-proof-attempt-capsule-schema'
Assert-A03Proof ((ConvertTo-MIR4BootstrapCanonicalJson $summary.evidence) -ceq (ConvertTo-MIR4BootstrapCanonicalJson $attempt)) 'mir4-a03-proof-summary-attempt-equality'
Assert-A03Proof ([string]$attempt.test_id -ceq 'runtime.k2-k2so-f210-intake' -and [string]$attempt.status -ceq 'passed' -and [int]$attempt.exit_code -eq 0 -and [string]$attempt.input_key -ceq $inputKey -and [string]$attempt.fingerprint_sha256 -ceq $inputKey) 'mir4-a03-proof-attempt-binding'
Assert-A03Proof ([string]$attempt.producer.campaign_plan_material_sha256 -ceq [string]$plan.plan_material_sha256) 'mir4-a03-proof-campaign-binding'
Assert-A03Proof ([string]$attempt.definition_sha256 -ceq [string]$tests[0].fingerprint.definition_sha256 -and (Get-A03ProofAssuranceJsonHash $attempt.inputs) -ceq (Get-A03ProofAssuranceJsonHash $tests[0].fingerprint.inputs)) 'mir4-a03-proof-fingerprint-binding'

$structuredResultFull = Resolve-A03ProofPath ([string]$attempt.result.path)
$structuredResultArtifact = Get-A03ProofArtifact $structuredResultFull
$structuredResult = Read-A03ProofJson $structuredResultFull
Assert-A03Proof ((Get-Content -Raw -LiteralPath $structuredResultFull) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/result.schema.json')) 'mir4-a03-proof-structured-result-schema'
Assert-A03Proof ($structuredResultArtifact.sha256 -ceq [string]$attempt.result.sha256 -and $structuredResultArtifact.bytes -eq [long]$attempt.result.bytes -and [string]$attempt.result.schema -ceq 'mir-test-result-v1' -and [string]$attempt.result.status -ceq 'passed') 'mir4-a03-proof-structured-result-descriptor'
Assert-A03Proof ([string]$structuredResult.test_id -ceq [string]$attempt.test_id -and [string]$structuredResult.status -ceq 'passed' -and [int]$structuredResult.exit_code -eq 0 -and @($structuredResult.assertions | Where-Object status -cne 'passed').Count -eq 0) 'mir4-a03-proof-structured-result-content'
Assert-A03Proof ((Get-A03ProofAssuranceJsonHash @($structuredResult.assertions)) -ceq (Get-A03ProofAssuranceJsonHash @($attempt.assertions)) -and (Get-A03ProofAssuranceJsonHash @($structuredResult.artifacts)) -ceq (Get-A03ProofAssuranceJsonHash @($attempt.artifacts))) 'mir4-a03-proof-structured-result-equality'
$executorRoot = Split-Path -Parent $structuredResultFull
$executorStdout = Get-A03ProofArtifact (Join-Path $executorRoot 'stdout.txt')
$executorStderr = Get-A03ProofArtifact (Join-Path $executorRoot 'stderr.txt')
Assert-A03Proof ($executorStdout.sha256 -ceq [string]$attempt.stdout_sha256 -and $executorStderr.sha256 -ceq [string]$attempt.stderr_sha256) 'mir4-a03-proof-executor-log-hashes'
$executorStdoutText = [IO.File]::ReadAllText((Resolve-A03ProofPath $executorStdout.path))
$runtimeMarkers = [regex]::Matches($executorStdoutText, '(?m)^\[MIR4_A03_RUNTIME_RESULT\] path=(?<path>.+) sha256=(?<sha>[A-F0-9]{64})\r?$')
Assert-A03Proof ($runtimeMarkers.Count -eq 1) 'mir4-a03-proof-runtime-marker-count'
$runtimeMarker = $runtimeMarkers[0]
Assert-A03Proof (Test-A03ProofRuntimeMarkerBinding -MarkerPath $runtimeMarker.Groups['path'].Value -MarkerRecordSha256 $runtimeMarker.Groups['sha'].Value -ExpectedRuntimePath $runtimeFull -RuntimeRecord $runtime) 'mir4-a03-proof-runtime-marker-binding'
$swappedRuntime = $runtime | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$swappedRuntime.recorded_at = '2026-09-10T00:00:01Z'
$swappedRuntime.record_sha256 = Get-MIR4BootstrapRecordSha256 $swappedRuntime
Assert-A03Proof (Test-MIR4BootstrapRecordHash $swappedRuntime) 'mir4-a03-proof-runtime-swap-control'
Assert-A03Proof (-not (Test-A03ProofRuntimeMarkerBinding -MarkerPath $runtimeMarker.Groups['path'].Value -MarkerRecordSha256 $runtimeMarker.Groups['sha'].Value -ExpectedRuntimePath $runtimeFull -RuntimeRecord $swappedRuntime)) 'mir4-a03-proof-runtime-swap-rejected'
$executorLogDigest = Get-A03ProofTextSha256 ((Get-Content -Raw -LiteralPath (Resolve-A03ProofPath $executorStdout.path)) + "`n" + (Get-Content -Raw -LiteralPath (Resolve-A03ProofPath $executorStderr.path)))
Assert-A03Proof ($executorLogDigest -ceq [string]$attempt.log_digest -and (Get-A03ProofCapsuleDigest $attempt) -ceq [string]$attempt.result_digest) 'mir4-a03-proof-capsule-digests'

$candidateFull = Resolve-A03ProofPath ([string]$runtime.candidate.path)
$candidateArtifact = Get-A03ProofArtifact $candidateFull
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($candidateFull)
try { $candidateEntries = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count } finally { $archive.Dispose() }
$candidateContent = Get-MIRZipContentFingerprint $candidateFull
Assert-A03Proof ($candidateArtifact.sha256 -ceq [string]$runtime.candidate.sha256 -and $candidateArtifact.sha256 -ceq ([string]$lock.mir.package_sha256).Substring(7).ToUpperInvariant()) 'mir4-a03-proof-candidate-hash'
Assert-A03Proof ([string]$runtime.factorio.executable_sha256 -ceq ([string]$lock.engine.executable_sha256).Substring(7).ToUpperInvariant() -and [string]$runtime.factorio.version -ceq [string]$lock.engine.version) 'mir4-a03-proof-engine'
Assert-A03Proof ([string]$runtime.target -ceq [string]$lock.target -and [string]$a00.engine.target -ceq [string]$lock.target -and [string]$a00.engine.version -ceq [string]$lock.engine.version -and [string]$a00.engine.sha256 -ceq [string]$runtime.factorio.executable_sha256) 'mir4-a03-proof-a00-engine-binding'
Assert-A03Proof ([string]$a00.current_candidate.sha256 -ceq $candidateArtifact.sha256 -and [long]$a00.current_candidate.bytes -eq $candidateArtifact.bytes -and [string]$a00.base.origin_dev -ceq [string]$lock.mir.source_commit -and [string]$a00.base.tree -ceq [string]$lock.mir.source_tree) 'mir4-a03-proof-a00-candidate-binding'
Assert-A03Proof ([string]$plan.source_commit -ceq [string]$lock.mir.source_commit -and [string]$plan.source_tree -ceq [string]$lock.mir.source_tree -and [string]$plan.candidate_descriptor.sha256 -ceq $candidateArtifact.sha256 -and [string]$plan.candidate_descriptor_sha256 -ceq [string]$plan.candidate_descriptor.descriptor_sha256) 'mir4-a03-proof-plan-source-binding'
$factorioFull = (Resolve-Path -LiteralPath $FactorioBin).Path
Assert-A03Proof ((Get-A03ProofSha256 $factorioFull) -ceq [string]$runtime.factorio.executable_sha256) 'mir4-a03-proof-factorio-binary'
try {
  & (Join-Path $repo 'scripts/Invoke-MIRAssurance.ps1') explain --target ([string]$plan.target) --profile ([string]$plan.profile) --candidate $candidateFull --factorio $factorioFull --plan $planFull --no-reuse | Out-Null
} catch { throw '[mir4-a03-proof-plan-integrity]' }

$sourceRoot = [IO.Path]::GetFullPath((Join-Path $repo $ConfigurationSourceRoot))
$sourceModList = Get-A03ProofArtifact (Join-Path $sourceRoot 'mod-list.json')
$sourceModSettings = Get-A03ProofArtifact (Join-Path $sourceRoot 'mod-settings.dat')
$launchModList = Get-A03ProofArtifact (Join-Path $modsRoot 'mod-list.json')
$postEngineModSettings = Get-A03ProofArtifact (Join-Path $modsRoot 'mod-settings.dat')
Assert-A03Proof ($sourceModList.sha256 -ceq 'FC7D944550AE7C4DEABAC91EF20CD2CC8E1ABFEDA0F96953284CDBFAB608FCAD' -and $sourceModSettings.sha256 -ceq '6AF4D7F55D19D9F105BCD540FFCA61267613843BC7AFEB457241BFB3703977A4') 'mir4-a03-proof-source-configuration'
Assert-A03Proof ($launchModList.sha256 -ceq [string]$runtime.closure_archives.'mod-list.json' -and $postEngineModSettings.sha256 -ceq [string]$runtime.closure_archives.'mod-settings.dat') 'mir4-a03-proof-final-configuration'

$enabledMods = @((Get-Content -Raw -LiteralPath (Resolve-A03ProofPath $launchModList.path) | ConvertFrom-Json -Depth 20).mods | Where-Object { [bool]$_.enabled } | ForEach-Object { [string]$_.name })
$expectedEnabledMods = @('base','elevated-rails','quality','recycler','space-age','flib','k2so-assets','Krastorio2','Krastorio2-spaced-out','Krastorio2Assets','Krastorio2MenuSimulations','mir-validation-settings-overrides','more-infinite-research','xy-k2so-enhancements-nulls-fork','mir4-a03-k2-intake-observer')
$enabledModSet = @($enabledMods | Sort-Object -CaseSensitive -Unique)
$expectedEnabledModSet = @($expectedEnabledMods | Sort-Object -CaseSensitive)
Assert-A03Proof ($enabledMods.Count -eq $expectedEnabledMods.Count -and $enabledModSet.Count -eq $expectedEnabledMods.Count -and ($enabledModSet -join '|') -ceq ($expectedEnabledModSet -join '|')) 'mir4-a03-proof-enabled-mods'

$closureRows = @($runtime.closure_archives.PSObject.Properties | Sort-Object Name -CaseSensitive | ForEach-Object {
  $file = Resolve-A03ProofPath (Join-Path $modsRoot $_.Name)
  Assert-A03Proof ((Get-A03ProofSha256 $file) -ceq [string]$_.Value) 'mir4-a03-proof-closure-archive-hash'
  [pscustomobject][ordered]@{name=[string]$_.Name;sha256=[string]$_.Value}
})
Assert-A03Proof ($closureRows.Count -eq 12) 'mir4-a03-proof-closure-count'
$expectedClosureNames = @('Krastorio2-spaced-out_2.0.13.zip','Krastorio2Assets_2.1.0.zip','Krastorio2MenuSimulations_2.1.0.zip','Krastorio2_2.1.2.zip','flib_0.17.2.zip','k2so-assets_1.0.7.zip','mir-validation-settings-overrides_0.1.0.zip','mir4-a03-k2-intake-observer_0.1.0.zip','mod-list.json','mod-settings.dat','more-infinite-research_4.2.21000.zip','xy-k2so-enhancements-nulls-fork_0.8.3.zip') | Sort-Object -CaseSensitive
Assert-A03Proof ((@($closureRows.name) -join '|') -ceq ($expectedClosureNames -join '|')) 'mir4-a03-proof-closure-names'
Assert-A03Proof ([string](@($closureRows | Where-Object name -CEQ 'more-infinite-research_4.2.21000.zip'))[0].sha256 -ceq $candidateArtifact.sha256) 'mir4-a03-proof-closure-candidate'
foreach ($mod in @($lock.mods)) {
  $name = ([string]$mod.name + '_' + [string]$mod.version + '.zip')
  $row = @($closureRows | Where-Object { [string]$_.name -ceq $name })
  Assert-A03Proof ($row.Count -eq 1 -and [string]$row[0].sha256 -ceq ([string]$mod.sha256).Substring(7).ToUpperInvariant()) 'mir4-a03-proof-lock-archive'
}

$helperArchive = @($closureRows | Where-Object name -CEQ 'mir-validation-settings-overrides_0.1.0.zip')
$observerArchive = @($closureRows | Where-Object name -CEQ 'mir4-a03-k2-intake-observer_0.1.0.zip')
Assert-A03Proof ($helperArchive.Count -eq 1 -and $observerArchive.Count -eq 1 -and [string]$observerArchive[0].sha256 -ceq [string]$runtime.governed_run_observer.archive_sha256) 'mir4-a03-proof-governed-archives'
$helperSourceRoot = Join-Path $repo 'fixtures/assert-k2-k2so-f210-intake/settings-helper'
$helperInfoSha = Get-A03ProofSha256 (Resolve-A03ProofPath (Join-Path $helperSourceRoot 'info.json'))
$helperSettingsSha = Get-A03ProofSha256 (Resolve-A03ProofPath (Join-Path $helperSourceRoot 'settings-updates.lua'))
$observerSourceRoot = Join-Path $repo 'fixtures/assert-k2-k2so-f210-intake/governed-observer-source'
$observerInfoSha = Get-A03ProofSha256 (Resolve-A03ProofPath (Join-Path $observerSourceRoot 'info.json'))
$observerDataFinalFixesSha = Get-A03ProofSha256 (Resolve-A03ProofPath (Join-Path $observerSourceRoot 'data-final-fixes.lua'))
Assert-A03Proof ($observerInfoSha -ceq [string]$runtime.governed_run_observer.source_sha256.info -and $observerDataFinalFixesSha -ceq [string]$runtime.governed_run_observer.source_sha256.data_final_fixes) 'mir4-a03-proof-governed-observer-source'

$stdout = Get-A03ProofArtifact (Join-Path $runtimeRoot 'a03-k2-k2so-f210-intake.stdout.log')
$stderr = Get-A03ProofArtifact (Join-Path $runtimeRoot 'a03-k2-k2so-f210-intake.stderr.log')
$factorioLog = Get-A03ProofArtifact (Join-Path $runtimeRoot 'factorio-current.log')
$save = Get-A03ProofArtifact (Join-Path $runtimeRoot 'saves/a03-k2-k2so-f210-intake.zip')
Assert-A03Proof ($stdout.sha256 -ceq [string]$runtime.stdout_sha256 -and $stderr.sha256 -ceq [string]$runtime.stderr_sha256 -and $factorioLog.sha256 -ceq [string]$runtime.factorio_log_sha256 -and $save.sha256 -ceq [string]$runtime.save_sha256) 'mir4-a03-proof-runtime-artifacts'
Assert-A03Proof ([string]$runtime.result -ceq 'passed' -and [int]$runtime.observer_marker_count -eq 1 -and [bool]$runtime.observation.post_finalizer_observation -and [bool]$runtime.observation.effective_startup_settings.'mir-debug-generation-report' -and -not [bool]$runtime.observation.mutation_authorized -and -not [bool]$runtime.observation.package_visible) 'mir4-a03-proof-observation'
$expectedObservation = Read-A03ProofJson 'fixtures/assert-k2-k2so-f210-intake/expected-observation.json'
Assert-A03Proof ((ConvertTo-MIR4BootstrapCanonicalJson $runtime.observation) -ceq (ConvertTo-MIR4BootstrapCanonicalJson $expectedObservation)) 'mir4-a03-proof-exact-observation'
$observationSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson $runtime.observation)

$proof = [pscustomobject][ordered]@{
  schema=1;kind='MIR4A03K2K2SOExecutionProofV1';recorded_at=[string]$runtime.recorded_at;task='A03';status='passed'
  authority_observation=[ordered]@{path=$a00Relative;record_sha256=[string]$a00.record_sha256}
  environment_lock=[ordered]@{path=$lockRelative;raw_sha256=(Get-A03ProofSha256 $lockPath);digest=[string]$lock.digest}
  candidate=[ordered]@{archive_sha256=$candidateArtifact.sha256;content_sha256=$candidateContent;bytes=$candidateArtifact.bytes;entries=$candidateEntries;source_commit=[string]$lock.mir.source_commit;source_tree=[string]$lock.mir.source_tree}
  engine=[ordered]@{version=[string]$runtime.factorio.version;executable_sha256=[string]$runtime.factorio.executable_sha256}
  configuration=[ordered]@{source_mod_list=$sourceModList;launch_mod_list=$launchModList;source_mod_settings=$sourceModSettings;post_engine_mod_settings=$postEngineModSettings;settings_helper=[ordered]@{archive_sha256=[string]$helperArchive[0].sha256;source_sha256=[ordered]@{info=$helperInfoSha;settings_updates=$helperSettingsSha}};governed_observer=[ordered]@{archive_sha256=[string]$observerArchive[0].sha256;source_sha256=[ordered]@{data_final_fixes=$observerDataFinalFixesSha;info=$observerInfoSha}};enabled_mods=$enabledMods}
  closure_files=$closureRows
  execution=[ordered]@{
    plan=[ordered]@{path=(Get-A03ProofRelativePath $planFull);raw_sha256=(Get-A03ProofSha256 $planFull);plan_material_sha256=[string]$plan.plan_material_sha256;candidate_descriptor_sha256=[string]$plan.candidate_descriptor_sha256;input_key=$inputKey;digest_policy_ids=[ordered]@{text=[string]$plan.digest_policy_ids.text;json=[string]$plan.digest_policy_ids.json};counts=[ordered]@{total=1;run=1;reuse=0;wait=0;invalid=0}}
    summary=[ordered]@{path=(Get-A03ProofRelativePath $summaryFull);raw_sha256=(Get-A03ProofSha256 $summaryFull);status='passed';input_key=$inputKey;counts=[ordered]@{total=1;executed=1;reused=0;failed=0;incomplete=0;unexpected=0}}
    attempt=[ordered]@{path=(Get-A03ProofRelativePath $attemptFull);raw_sha256=(Get-A03ProofSha256 $attemptFull);test_id='runtime.k2-k2so-f210-intake';status='passed';input_key=$inputKey;fingerprint_sha256=[string]$attempt.fingerprint_sha256;definition_sha256=[string]$attempt.definition_sha256;exit_code=0;structured_result=$structuredResultArtifact;executor_stdout=$executorStdout;executor_stderr=$executorStderr;stdout_sha256=[string]$attempt.stdout_sha256;stderr_sha256=[string]$attempt.stderr_sha256;log_digest=[string]$attempt.log_digest;result_digest=[string]$attempt.result_digest}
    runtime=[ordered]@{result_file=(Get-A03ProofArtifact $runtimeFull);record_sha256=[string]$runtime.record_sha256;result='passed';duration_seconds=[double]$runtime.duration_seconds;stdout=$stdout;stderr=$stderr;factorio_log=$factorioLog;save=$save;observer_marker_count=1}
  }
  observation=[ordered]@{canonical_sha256=$observationSha;value=$runtime.observation}
  invariants=[ordered]@{fresh_no_reuse_run=$true;single_executed_attempt_in_final_plan=$true;post_finalizer_read_only=$true;configuration_hash_bound=$true;lock_mod_archives_match=$true;observation_matches_runtime=$true;player_mutation_authorized=$false;prototype_write_authorized=$false;public_support_authorized=$false;release_authority=$false}
  record_sha256=''
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('mir4-a03-proof-' + [guid]::NewGuid().ToString('N') + '.json')
try {
  Write-MIR4BootstrapRecord -Record $proof -Path $scratch | Out-Null
  $projection = Get-Content -Raw -LiteralPath $scratch
  Assert-A03Proof ($projection -notmatch '(?i)(?:[A-Z]:[\\/]|\\\\)') 'mir4-a03-proof-private-path'
  Assert-A03Proof ($projection | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-a03-k2-k2so-execution-proof-v1.schema.json')) 'mir4-a03-proof-schema'
  & (Join-Path $repo 'tools/commands/mir4/Write-MIR4A00A03Evidence.ps1') -Kind A03ExecutionProof -InputPath $scratch -OutputPath (Join-Path $repo $OutputPath) -RecordedAt ([string]$runtime.recorded_at) -RequireLocalEvidence
} finally { if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Force } }
