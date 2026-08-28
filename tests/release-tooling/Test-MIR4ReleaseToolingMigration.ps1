param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/release/ReleaseToolingMigration.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

function Assert-MIR4ReleaseToolingMigrationV1([bool]$Condition,[string]$Code,[string]$Detail=''){if(-not$Condition){throw "[$Code] $Detail"}}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$packageHashes=[ordered]@{};foreach($path in @(Get-MIRPackageSourceFiles -RepoRoot $repo)){$packageHashes[[string]$path]=(Get-FileHash -LiteralPath (Join-Path $repo ([string]$path)) -Algorithm SHA256).Hash}
Assert-MIR4ReleaseToolingMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4ReleaseToolingPredecessorReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4ReleaseToolingPredecessorReceiptSha256) 'mir4-release-tooling-migration-predecessor-immutable'
Assert-MIR4ReleaseToolingMigrationV1 ((Get-Item -LiteralPath (Join-Path $repo $script:MIR4ReleaseToolingPredecessorReceiptPath)).Length-eq$script:MIR4ReleaseToolingPredecessorReceiptBytes) 'mir4-release-tooling-migration-predecessor-bytes'
try{Invoke-MIR4HistoricalToolingMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-release-tooling-migration-predecessor-write-enabled]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-historical-tooling-migration-receipt-immutable]')){throw}}

$authority=Get-MIR4ReleaseToolingMigrationAuthorityV1 -RepoRoot $repo
$proof=Get-MIR4ReleaseToolingMigrationProofPolicyV1 -RepoRoot $repo
$receipt=Invoke-MIR4ReleaseToolingMigrationProjectionV1 -RepoRoot $repo -Check
$inventory=Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4ReleaseToolingMigrationV1 ([int]$inventory.summary.unknown-eq0-and-not[bool]$inventory.deletion_authorized) 'mir4-release-tooling-migration-inventory'
Assert-MIR4ReleaseToolingMigrationV1 (@($authority.writers).Count-eq1-and@($authority.compatibility_entrypoints).Count-eq1) 'mir4-release-tooling-migration-authority'
Assert-MIR4ReleaseToolingMigrationV1 ([string]$proof.test_id-ceq'static.mir4-release-tooling-migration-v1'-and@($proof.required_checks).Count-eq28-and[string]$proof.functional_parity_digest-ceq$script:MIR4ReleaseToolingFunctionalDigestV1) 'mir4-release-tooling-migration-proof'
Assert-MIR4ReleaseToolingMigrationV1 (Test-MIR4ReleaseToolingForwarderV1 -RepoRoot $repo) 'mir4-release-tooling-migration-forwarder'
Assert-MIR4ReleaseToolingMigrationV1 (Test-MIR4ReleaseToolingDeclaredConsumersV1 -RepoRoot $repo) 'mir4-release-tooling-migration-consumers'
Assert-MIR4ReleaseToolingMigrationV1 ([string](Test-MIR4ReleaseToolingFunctionalParityV1 -RepoRoot $repo).digest-ceq$script:MIR4ReleaseToolingFunctionalDigestV1) 'mir4-release-tooling-migration-functional-parity'

$catalog=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
Assert-MIR4ReleaseToolingMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq'static.mir4-release-tooling-v1'-and[string]$_.command-ceq'./tests/release-tooling/Test-MIR4ReleaseTooling.ps1'}).Count-eq1) 'mir4-release-tooling-migration-functional-registration'
Assert-MIR4ReleaseToolingMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq[string]$proof.test_id-and[string]$_.command-ceq'./tests/release-tooling/Test-MIR4ReleaseToolingMigration.ps1'}).Count-eq1) 'mir4-release-tooling-migration-test-registration'
$assurance=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$migrationClass=@($assurance.classes|Where-Object{[string]$_.id-ceq'release-tooling-migration'})
Assert-MIR4ReleaseToolingMigrationV1 ($migrationClass.Count-eq1-and@($migrationClass[0].tests)-contains[string]$proof.test_id) 'mir4-release-tooling-migration-assurance-registration'
foreach($testId in @('static.mir4-release-tooling-v1','static.mir4-release-tooling-migration-v1')){Assert-MIR4ReleaseToolingMigrationV1 ($testId-in@($assurance.profiles.'mir4-bootstrap')) 'mir4-release-tooling-migration-bootstrap-profile' $testId}
foreach($path in @('tools/mir/application/release/ReleaseToolingMigration.ps1','tools/mir/cli/Invoke-MIR4ReleaseToolingMigration.ps1')){Assert-MIR4ReleaseToolingMigrationV1 (@($receipt.components|Where-Object{[string]$_.path-ceq$path}).Count-eq1-and@($receipt.current_authorities|Where-Object{[string]$_.path-ceq$path}).Count-eq1) 'mir4-release-tooling-migration-receipt-writer-binding' $path}
Assert-MIR4ReleaseToolingMigrationV1 ($packageBefore-ceq[string]$authority.package_source_sha256-and[string]$receipt.package_source_sha256-ceq$packageBefore-and@($receipt.package_visible_delta).Count-eq0) 'mir4-release-tooling-migration-package-firewall'
Assert-MIR4ReleaseToolingMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo 'tools/mir/application/release/ReleaseDag.ps1') -Algorithm SHA256).Hash-ceq$script:MIR4ReleaseToolingImplementationSha256) 'mir4-release-tooling-migration-implementation'
Assert-MIR4ReleaseToolingMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo 'spec/platform/mir4-preview-v0/release-dag.json') -Algorithm SHA256).Hash-ceq$script:MIR4ReleaseToolingDagAuthoritySha256) 'mir4-release-tooling-migration-dag-authority'
Assert-MIR4ReleaseToolingMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-ceq$script:MIR4ReleaseToolingCompatibilityPolicySha256) 'mir4-release-tooling-migration-compatibility-policy'
Assert-MIR4ReleaseToolingMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json') -Algorithm SHA256).Hash-ceq$script:MIR4ReleaseToolingT14ReceiptSha256) 'mir4-release-tooling-migration-t14'

$prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration -IncludeHistoricalToolingMigration
Assert-MIR4ReleaseToolingMigrationV1 ([string]$receipt.predecessor_receipt.path-ceq[string]$prior.prior_receipt_path-and[string]$receipt.predecessor_receipt.sha256-ceq[string]$prior.prior_receipt_sha256) 'mir4-release-tooling-migration-predecessor-chain'
foreach($binding in @($receipt.evolved_bindings)){$item=[string]$binding.path;Assert-MIR4ReleaseToolingMigrationV1 ($prior.authority_hashes.ContainsKey($item)-and[string]$binding.previous_sha256-ceq[string]$prior.authority_hashes[$item]) 'mir4-release-tooling-migration-evolved-prior' $item;Assert-MIR4ReleaseToolingMigrationV1 ([string]$binding.current_sha256-ceq(Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $item) -Mode ([string]$binding.hash_mode))) 'mir4-release-tooling-migration-evolved-current' $item}
foreach($binding in @($receipt.current_authorities)){$actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$binding.path)) -Mode ([string]$binding.hash_mode);Assert-MIR4ReleaseToolingMigrationV1 ([string]$binding.sha256-ceq$actual) 'mir4-release-tooling-migration-current-authority' ([string]$binding.path)}
Assert-MIR4ReleaseToolingMigrationV1 ([string]$receipt.digest-ceq(Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:release-tooling-migration-receipt:1' -OmitTopLevelDigest)) 'mir4-release-tooling-migration-receipt-digest'
foreach($field in @('transition_gate','release_transition_authority')){Assert-MIR4ReleaseToolingMigrationV1 (@($receipt.$field.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-release-tooling-migration-release-firewall' $field}
foreach($field in @('transition_gate','release_transition_authority')){$tampered=$receipt|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$tampered.$field.publication=$true;Assert-MIR4ReleaseToolingMigrationV1 (-not(($tampered|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $repo $script:MIR4ReleaseToolingMigrationReceiptSchemaPath) -ErrorAction SilentlyContinue)) 'mir4-release-tooling-migration-release-firewall-schema' $field}
Test-MIR4PreFreezeAuthorities -RepoRoot $repo|Out-Null
$latest=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration -IncludeHistoricalToolingMigration -IncludeReleaseToolingMigration
Assert-MIR4ReleaseToolingMigrationV1 ([string]$latest.prior_receipt_path-ceq$script:MIR4ReleaseToolingMigrationReceiptPath) 'mir4-release-tooling-migration-prefreeze-chain'
$releaseHistoryOutput=(& pwsh -NoProfile -File (Join-Path $repo 'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1') 2>&1|Out-String).Trim()
Assert-MIR4ReleaseToolingMigrationV1 ($LASTEXITCODE-eq0-and$releaseHistoryOutput-match'append-only-release-tooling-successor') 'mir4-release-tooling-migration-release-history-successor' $releaseHistoryOutput

function Invoke-MIR4ReleaseToolingMigrationCommandProbeV1([string]$Command){$output=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4ReleaseToolingMigration.ps1') -Command $Command -RepoRoot $repo 2>&1|Out-String).Trim();if($LASTEXITCODE-ne0){throw "[mir4-release-tooling-migration-cli] $Command $output"};return $output|ConvertFrom-Json -Depth 100}
$generateResult=Invoke-MIR4ReleaseToolingMigrationCommandProbeV1 generate;$checkResult=Invoke-MIR4ReleaseToolingMigrationCommandProbeV1 check;$showResult=Invoke-MIR4ReleaseToolingMigrationCommandProbeV1 show
Assert-MIR4ReleaseToolingMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $generateResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-and(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $showResult)) 'mir4-release-tooling-migration-cli-parity'
$facadeOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 release-tooling-migration check 2>&1|Out-String).Trim()
Assert-MIR4ReleaseToolingMigrationV1 ($LASTEXITCODE-eq0-and(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 ($facadeOutput|ConvertFrom-Json -Depth 100))) 'mir4-release-tooling-migration-facade-parity'
$predecessorGenerateOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 historical-tooling-migration generate 2>&1|Out-String).Trim()
$predecessorGenerateExitCode=$LASTEXITCODE
Assert-MIR4ReleaseToolingMigrationV1 ($predecessorGenerateExitCode-ne0-and$predecessorGenerateOutput-match'Unknown mir4 historical-tooling-migration command: generate') 'mir4-release-tooling-migration-predecessor-facade-write-enabled'
$global:LASTEXITCODE=0
foreach($path in $packageHashes.Keys){Assert-MIR4ReleaseToolingMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $path) -Algorithm SHA256).Hash-ceq[string]$packageHashes[$path]) 'mir4-release-tooling-migration-player-authority-mutation' $path}
Assert-MIR4ReleaseToolingMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-release-tooling-migration-package-source-mutation'
[pscustomobject][ordered]@{status='accepted';migration_id=[string]$receipt.migration_id;canonical_application='tools/mir/application/release/ReleaseDag.ps1';compatibility_entrypoints=@($authority.compatibility_entrypoints.path);predecessor_receipt_sha256=$script:MIR4ReleaseToolingPredecessorReceiptSha256;receipt_digest=[string]$receipt.digest;package_source_sha256=[string]$receipt.package_source_sha256;package_visible_delta=@();release_transition_authority=$false}
