param([string]$RepoRoot = "")

# Synthetic ignored contract probes only: never qualification, review, completion, or release evidence.
$ErrorActionPreference = "Stop"
$RepoRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
} else { (Resolve-Path -LiteralPath $RepoRoot).Path }
. (Join-Path $RepoRoot "tools/mir/application/custody/OfflineCandidateCustody.ps1")

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Action, [string]$Message) {
  $threw = $false; try { & $Action } catch { $threw = $true }; if (-not $threw) { throw $Message }
}
function Get-OpenSshKeygenPath {
  $candidates = @()
  if (-not [string]::IsNullOrWhiteSpace($env:WINDIR)) { $candidates += Join-Path $env:WINDIR "System32/OpenSSH/ssh-keygen.exe" }
  $candidates += "C:\Program Files\Git\usr\bin\ssh-keygen.exe"
  $command = Get-Command ssh-keygen -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $command) { $candidates += [string]$command.Source }
  $found = @($candidates | Where-Object { [IO.Path]::IsPathRooted($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique)
  if ($found.Count -eq 0) { throw "The MIR 4 custody test requires an explicit OpenSSH ssh-keygen executable." }
  return (Resolve-Path -LiteralPath $found[0]).Path
}

$currentPlanPath = (Resolve-Path (Join-Path $RepoRoot ".mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV3.json")).Path
$currentPlan = Assert-MIR4GovernedBootstrapRecordFileV1 -Path $currentPlanPath -SchemaPath (Join-Path $RepoRoot "spec/schemas/mir4-bootstrap-local-candidate-plan-v3.schema.json")
$currentF210 = @($currentPlan.targets | Where-Object { [string]$_.target_key -ceq "f210" })[0]
$currentBaseline = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$currentF210.predecessor.baseline_manifest)) | ConvertFrom-Json -Depth 100
Assert-True ([string]$currentBaseline.record_sha256 -ceq [string]$currentF210.predecessor.baseline_record_sha256) "The hash-bound MIR 4 candidate plan V3 has a stale f210 terminal baseline."

$sshKeygen = Get-OpenSshKeygenPath
$buildTests = Join-Path $RepoRoot "build/tests"
$testRoot = Join-Path $buildTests ("mir4-offline-custody-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$createdCandidate = $false
$governedRoot = $null

try {
  $schemas = Join-Path $RepoRoot "spec/schemas"
  $planPath = (Resolve-Path (Join-Path $RepoRoot ".mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV3.json")).Path
  $plan = Assert-MIR4GovernedBootstrapRecordFileV1 -Path $planPath -SchemaPath (Join-Path $schemas "mir4-bootstrap-local-candidate-plan-v3.schema.json")
  $target = @($plan.targets | Where-Object { [string]$_.target_key -ceq "f210" })[0]

  # Consume only the governed materializer output; admission re-runs its complete -Check path.
  $governedRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ([string]$plan.package_policy.output_root)))
  $expectedCandidate = Join-Path $governedRoot "distributions/more-infinite-research_4.0.21000.zip"
  $expectedManifest = Join-Path $governedRoot "manifests/f210.json"
  if (-not (Test-Path -LiteralPath $expectedCandidate -PathType Leaf) -or
      -not (Test-Path -LiteralPath $expectedManifest -PathType Leaf)) {
    if (Test-Path -LiteralPath $governedRoot) {
      throw "Refusing to replace a pre-existing incomplete governed MIR 4 bootstrap output root: $governedRoot"
    }
    $createdCandidate = $true
    & (Join-Path $RepoRoot "tools/commands/release/New-MIR4BootstrapLocalCandidate.ps1") `
      -RepoRoot $RepoRoot -PlanPath $planPath -Target f210 -OutputRoot $governedRoot
  }
  $candidatePath = (Resolve-Path $expectedCandidate).Path
  $manifestPath = (Resolve-Path $expectedManifest).Path
  $inventory = Get-MIR4ArchiveInventory -Path $candidatePath
  $manifest = Assert-MIR4BootstrapRecordFileV1 -Path $manifestPath -SchemaPath (Join-Path $schemas "mir4-bootstrap-local-candidate-manifest.schema.json")
  $manifestBinding = New-MIR4CustodyRecordBindingV1 -Role "candidate-manifest" -Record $manifest -Path $manifestPath
  $planBinding = New-MIR4CustodyRecordBindingV1 -Role "candidate-plan" -Record $plan -Path $planPath

  $candidate = [pscustomobject][ordered]@{candidate_id="synthetic-mir4-custody-probe";target_id="factorio-2.1";distribution_version="4.0.21000";archive_name=[IO.Path]::GetFileName($candidatePath);archive_sha256=$inventory.archive_sha256;bytes=$inventory.bytes}
  $identity="mir4-r0-offline-proof";$evidenceIdentity="synthetic-exact-engine-probe"
  $privateKey=Join-Path $testRoot "keys/proof-only-ed25519";$publicKey="$privateKey.pub"
  $evidencePrivateKey=Join-Path $testRoot "keys/synthetic-evidence-ed25519";$evidencePublicKey="$evidencePrivateKey.pub"
  $wrongPrivateKey=Join-Path $testRoot "keys/wrong-ed25519";$wrongPublicKey="$wrongPrivateKey.pub"
  $null=New-MIR4ProofOnlyEd25519KeyPairV1 -RepoRoot $RepoRoot -SshKeygenPath $sshKeygen -PrivateKeyPath $privateKey -PublicKeyPath $publicKey -Identity $identity
  $null=New-MIR4ProofOnlyEd25519KeyPairV1 -RepoRoot $RepoRoot -SshKeygenPath $sshKeygen -PrivateKeyPath $evidencePrivateKey -PublicKeyPath $evidencePublicKey -Identity $evidenceIdentity
  $null=New-MIR4ProofOnlyEd25519KeyPairV1 -RepoRoot $RepoRoot -SshKeygenPath $sshKeygen -PrivateKeyPath $wrongPrivateKey -PublicKeyPath $wrongPublicKey -Identity "$identity-wrong"

  # This signed bundle is intentionally synthetic. It is schema-complete and exercises
  # fail-closed custody, but its dummy executable cannot satisfy the exact engine lock.
  $artifactRoot=Join-Path $testRoot "artifacts";New-Item -ItemType Directory -Force -Path $artifactRoot|Out-Null
  $observations=@()
  foreach($observationId in $script:MIR4ExactEngineObservationIdsV1){
    $artifactPath=Join-Path $artifactRoot "$observationId.json"
    [IO.File]::WriteAllText($artifactPath,"{`"synthetic`":true,`"observation`":`"$observationId`"}`n",[Text.UTF8Encoding]::new($false))
    $observations += [pscustomobject][ordered]@{id=$observationId;status="passed";result_artifact=[pscustomobject][ordered]@{relative_path="artifacts/$observationId.json";sha256=Get-MIR4Sha256File $artifactPath;bytes=[long](Get-Item $artifactPath).Length}}
  }
  $syntheticEnginePath=Join-Path $testRoot "synthetic-factorio-engine.exe"
  [IO.File]::WriteAllText($syntheticEnginePath,"synthetic engine; not Factorio 2.1.14",[Text.UTF8Encoding]::new($false))
  $evidencePayload=[pscustomobject][ordered]@{
    schema=1;kind="MIR4ExactEngineQualificationEvidencePayloadV1";canonicalization="MIR4BootstrapCanonicalJsonV1"
    evidence_class="exact-engine-observation-bundle";qualification_scope="local-offline-f210-exact-engine";publication_authority=$false
    candidate_manifest=$manifestBinding;candidate_plan=$planBinding;candidate=$candidate
    engine=[pscustomobject][ordered]@{version=[string]$target.engine_lock.version;executable_sha256=[string]$target.engine_lock.executable_sha256;network_denied=$true}
    observations=$observations
    producer=[pscustomobject][ordered]@{kind="MIR4ExactEngineEvidenceProducerV1";trust_scope="explicit-key-local-offline-exact-engine";identity=$evidenceIdentity;algorithm="ssh-ed25519";signature_format="sshsig";namespace="mir4-exact-engine-qualification-v1";public_key=Get-MIR4OpenSshPublicKeyLineV1 $evidencePublicKey;public_key_fingerprint=Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $sshKeygen -PublicKeyPath $evidencePublicKey;private_key_committed=$false}
  }
  $evidencePayloadPath=Join-Path $testRoot "synthetic-evidence-payload.json"
  $evidencePayload=Write-MIR4CustodyRecordV1 -Record $evidencePayload -Path $evidencePayloadPath
  $signResult=Invoke-MIR4OpenSshProcessV1 -SshKeygenPath $sshKeygen -Arguments @("-Y","sign","-f",$evidencePrivateKey,"-n","mir4-exact-engine-qualification-v1",$evidencePayloadPath)
  $evidenceSignaturePath="$evidencePayloadPath.sig"
  Assert-True ($signResult.exit_code -eq 0 -and (Test-Path $evidenceSignaturePath -PathType Leaf)) "Synthetic evidence probe was not signed."
  Assert-True (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $sshKeygen -PublicKeyPath $evidencePublicKey -Identity $evidenceIdentity -Namespace "mir4-exact-engine-qualification-v1" -PayloadPath $evidencePayloadPath -SignaturePath $evidenceSignaturePath -ScratchRoot (Join-Path $testRoot "scratch/evidence-signature")) "Synthetic evidence signature did not verify with its explicit producer key."
  Assert-True (-not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $sshKeygen -PublicKeyPath $wrongPublicKey -Identity $evidenceIdentity -Namespace "mir4-exact-engine-qualification-v1" -PayloadPath $evidencePayloadPath -SignaturePath $evidenceSignaturePath -ScratchRoot (Join-Path $testRoot "scratch/evidence-wrong-key"))) "Synthetic evidence signature verified with the wrong producer key."
  $tamperedEvidencePayloadPath=Join-Path $testRoot "synthetic-evidence-payload-tampered.json";$tamperedEvidencePayload=Get-Content -Raw $evidencePayloadPath|ConvertFrom-Json -Depth 100 -DateKind String;$tamperedEvidencePayload.candidate.candidate_id="tampered-synthetic-probe";$null=Write-MIR4CustodyRecordV1 -Record $tamperedEvidencePayload -Path $tamperedEvidencePayloadPath
  Assert-True (-not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $sshKeygen -PublicKeyPath $evidencePublicKey -Identity $evidenceIdentity -Namespace "mir4-exact-engine-qualification-v1" -PayloadPath $tamperedEvidencePayloadPath -SignaturePath $evidenceSignaturePath -ScratchRoot (Join-Path $testRoot "scratch/evidence-tamper"))) "Tampered synthetic evidence payload verified against the original signature."
  $signatureBytes=[IO.File]::ReadAllBytes($evidenceSignaturePath)
  $evidence=[pscustomobject][ordered]@{schema=1;kind="MIR4ExactEngineQualificationEvidenceBundleV1";canonicalization="MIR4BootstrapCanonicalJsonV1";status="passed-exact-engine-qualification";publication_authority=$false;payload=$evidencePayload;signature=[pscustomobject][ordered]@{algorithm="ssh-ed25519";format="sshsig";identity=$evidenceIdentity;namespace="mir4-exact-engine-qualification-v1";payload_record_sha256=[string]$evidencePayload.record_sha256;signature_sha256=Get-MIR4Sha256Bytes $signatureBytes;signature_base64=[Convert]::ToBase64String($signatureBytes)}}
  $evidencePath=Join-Path $testRoot "synthetic-exact-engine-evidence.json"
  $evidence=Write-MIR4CustodyRecordV1 -Record $evidence -Path $evidencePath
  $evidenceBinding=New-MIR4CustodyRecordBindingV1 -Role "exact-engine-evidence" -Record $evidence -Path $evidencePath

  $qualification=[pscustomobject][ordered]@{schema=1;kind="MIR4OfflineQualificationRecordV1";canonicalization="MIR4BootstrapCanonicalJsonV1";qualification_scope="local-offline-proof-only";publication_authority=$false;candidate_manifest=$manifestBinding;candidate_plan=$planBinding;exact_engine_evidence=$evidenceBinding;candidate=$candidate;engine=$evidencePayload.engine;proof_root_sha256=[string]$evidence.record_sha256;status="passed"}
  $qualificationPath=Join-Path $testRoot "synthetic-qualification-passed.json";$qualification=Write-MIR4CustodyRecordV1 -Record $qualification -Path $qualificationPath
  $qualification=Assert-MIR4BootstrapRecordFileV1 -Path $qualificationPath -SchemaPath (Join-Path $schemas "mir4-offline-qualification-record.schema.json")
  $qualificationBinding=New-MIR4CustodyRecordBindingV1 -Role "qualification" -Record $qualification -Path $qualificationPath
  $review=[pscustomobject][ordered]@{schema=1;kind="MIR4OfflineReviewRecordV1";canonicalization="MIR4BootstrapCanonicalJsonV1";review_scope="local-offline-proof-only";publication_authority=$false;candidate_manifest=$manifestBinding;candidate_plan=$planBinding;qualification=$qualificationBinding;review_class="human-manual";reviewer="synthetic-contract-probe";decision="accepted-local-proof-only";status="passed"}
  $reviewPath=Join-Path $testRoot "synthetic-review-passed.json";$review=Write-MIR4CustodyRecordV1 -Record $review -Path $reviewPath
  $null=Assert-MIR4BootstrapRecordFileV1 -Path $reviewPath -SchemaPath (Join-Path $schemas "mir4-offline-review-record.schema.json")

  $admission=Get-MIR4CustodyAdmissionV1 -RepoRoot $RepoRoot -CandidateManifestPath $manifestPath -CandidatePlanPath $planPath -CandidatePath $candidatePath -SchemaRoot $schemas
  Assert-Throws {Assert-MIR4ExactEngineQualificationEvidenceBundleV1 -RepoRoot $RepoRoot -EvidenceBundlePath $evidencePath -CandidateManifestPath $manifestPath -CandidatePlanPath $planPath -Admission $admission -ExactEngineExecutablePath $syntheticEnginePath -SshKeygenPath $sshKeygen -TrustedPublicKeyPath $evidencePublicKey -ScratchRoot (Join-Path $testRoot "scratch/evidence") -SchemaRoot $schemas} "Synthetic evidence with a non-exact engine executable satisfied production qualification."
  $sealArgs=@{RepoRoot=$RepoRoot;CandidatePath=$candidatePath;CandidateManifestPath=$manifestPath;CandidatePlanPath=$planPath;ExactEngineEvidenceBundlePath=$evidencePath;ExactEngineExecutablePath=$syntheticEnginePath;ExactEngineTrustedPublicKeyPath=$evidencePublicKey;QualificationRecordPath=$qualificationPath;ReviewRecordPath=$reviewPath;SshKeygenPath=$sshKeygen;PrivateKeyPath=$privateKey;PublicKeyPath=$publicKey;Identity=$identity;ScratchRoot=(Join-Path $testRoot "scratch/seal")}
  $sealPath=Join-Path $testRoot "offline-seal-must-not-exist.json"
  Assert-Throws {New-MIR4OfflineSealV1 @sealArgs -OutputPath $sealPath} "Synthetic exact-engine evidence minted a production custody seal."
  Assert-True (-not (Test-Path $sealPath)) "Rejected synthetic evidence left a seal artifact."
  foreach($mode in @("apply","tag","upload","public")){Assert-Throws {New-MIR4OfflineSealV1 @sealArgs -Mode $mode -OutputPath (Join-Path $testRoot "$mode.json")} "Forbidden $mode mode admitted."}

  # The dual dry-run identity primitive remains independently testable without minting a seal.
  $pairSealPath=Join-Path $testRoot "synthetic-pair-seal-marker";[IO.File]::WriteAllText($pairSealPath,"not-a-production-seal",[Text.UTF8Encoding]::new($false))
  $pairSeal=[pscustomobject][ordered]@{kind="MIR4OfflineSealV1";record_sha256=("A"*64);payload=[pscustomobject][ordered]@{candidate=$candidate;source_identity=[pscustomobject][ordered]@{version="4.0.0";proposed_tag="v4.0.0"};distribution_identity=[pscustomobject][ordered]@{target_id="factorio-2.1";version="4.0.21000";proposed_tag="dist/f210/v4.0.21000"}}}
  $dryRun=[pscustomobject][ordered]@{schema=1;kind="MIR4PublicationDryRunBundleV1";canonicalization="MIR4BootstrapCanonicalJsonV1";mode="dry-run";mutating=$false;network_required=$false;apply_allowed=$false;publication_authority=$false;seal=[pscustomobject][ordered]@{kind="MIR4OfflineSealV1";record_sha256=("A"*64);file_sha256=Get-MIR4Sha256File $pairSealPath};source_identity=$pairSeal.payload.source_identity;distribution_identity=$pairSeal.payload.distribution_identity;identity_authorities=$admission.identity_authorities;candidate=$candidate;release=[pscustomobject][ordered]@{title="Synthetic pair contract probe";asset_name=$candidate.archive_name;asset_sha256=$candidate.archive_sha256};channel_requests=@([pscustomobject][ordered]@{channel="github";operation="describe-request-only";asset_name=$candidate.archive_name;expected_sha256=$candidate.archive_sha256;mutation_allowed=$false},[pscustomobject][ordered]@{channel="mod-portal";operation="describe-request-only";asset_name=$candidate.archive_name;expected_sha256=$candidate.archive_sha256;mutation_allowed=$false});rollback=[pscustomobject][ordered]@{partial_publication_policy="not-applicable-no-mutation";mutation_count=0};readback_verification=@([pscustomobject][ordered]@{id="candidate-sha256";operation="sha256";subject=$candidate.archive_name;expected=$candidate.archive_sha256},[pscustomobject][ordered]@{id="candidate-byte-count";operation="byte-count";subject=$candidate.archive_name;expected=[long]$candidate.bytes})}
  $dryA=Join-Path $testRoot "synthetic-dry-a.json";$dryB=Join-Path $testRoot "synthetic-dry-b.json"
  $null=Write-MIR4CustodyRecordV1 -Record $dryRun -Path $dryA;$null=Write-MIR4CustodyRecordV1 -Record $dryRun -Path $dryB
  $pair=Assert-MIR4PublicationDryRunPairV1 -RepoRoot $RepoRoot -SealPath $pairSealPath -PublicationDryRunBundlePathA $dryA -PublicationDryRunBundlePathB $dryB -Seal $pairSeal -Admission $admission -SchemaRoot $schemas
  Assert-True ((@($pair.bindings.run_id)-join "|") -ceq "A|B") "Dual dry-run pair did not bind distinct A/B runs."
  Assert-Throws {Assert-MIR4PublicationDryRunPairV1 -RepoRoot $RepoRoot -SealPath $pairSealPath -PublicationDryRunBundlePathA $dryA -PublicationDryRunBundlePathB $dryA -Seal $pairSeal -Admission $admission -SchemaRoot $schemas} "Dual dry-run pair accepted one aliased path."
  $differentDry=Join-Path $testRoot "synthetic-dry-different.json";$different=Get-Content -Raw $dryA|ConvertFrom-Json -Depth 100 -DateKind String;$different.release.title="Divergent synthetic pair probe";$null=Write-MIR4CustodyRecordV1 -Record $different -Path $differentDry
  Assert-Throws {Assert-MIR4PublicationDryRunPairV1 -RepoRoot $RepoRoot -SealPath $pairSealPath -PublicationDryRunBundlePathA $dryA -PublicationDryRunBundlePathB $differentDry -Seal $pairSeal -Admission $admission -SchemaRoot $schemas} "Dual dry-run pair accepted divergent records."

  $completionArgs=@{RepoRoot=$RepoRoot;SealPath=$sealPath;CandidatePath=$candidatePath;CandidateManifestPath=$manifestPath;CandidatePlanPath=$planPath;ExactEngineEvidenceBundlePath=$evidencePath;ExactEngineExecutablePath=$syntheticEnginePath;ExactEngineTrustedPublicKeyPath=$evidencePublicKey;QualificationRecordPath=$qualificationPath;ReviewRecordPath=$reviewPath;PublicationDryRunBundlePathA=$dryA;PublicationDryRunBundlePathB=$dryB;RestorationReceiptPath=(Join-Path $testRoot "missing-restoration.json");SshKeygenPath=$sshKeygen;TrustedPublicKeyPath=$publicKey;ScratchRoot=(Join-Path $testRoot "scratch/completion")}
  Assert-Throws {New-MIR4EmergencyLaneCompletionRecordV1 @completionArgs -OutputPath (Join-Path $testRoot "completion-must-not-exist.json")} "Synthetic evidence minted an emergency-lane completion record."
} finally {
  if (Test-Path $testRoot) { Remove-MIR4BuildTree -OutputRoot $buildTests -Path $testRoot }
  if ($createdCandidate -and $null -ne $governedRoot -and (Test-Path -LiteralPath $governedRoot)) {
    Remove-MIR4BuildTree -OutputRoot (Join-Path $RepoRoot "build/mir4") -Path $governedRoot
  }
}
Write-Host "[ok] MIR 4 custody rejects synthetic engine evidence and enforces dual dry-run identity without minting a seal"
