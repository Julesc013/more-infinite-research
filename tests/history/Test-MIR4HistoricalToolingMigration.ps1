param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/history/HistoricalToolingMigration.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

function Assert-MIR4HistoricalToolingMigrationV1([bool]$Condition,[string]$Code,[string]$Detail=''){if(-not$Condition){throw "[$Code] $Detail"}}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$packageHashes=[ordered]@{};foreach($path in @(Get-MIRPackageSourceFiles -RepoRoot $repo)){$packageHashes[[string]$path]=(Get-FileHash -LiteralPath (Join-Path $repo ([string]$path)) -Algorithm SHA256).Hash}
Assert-MIR4HistoricalToolingMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4HistoricalToolingPredecessorReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4HistoricalToolingPredecessorReceiptSha256) 'mir4-historical-tooling-migration-predecessor-immutable'
Assert-MIR4HistoricalToolingMigrationV1 ((Get-Item -LiteralPath (Join-Path $repo $script:MIR4HistoricalToolingPredecessorReceiptPath)).Length-eq53137) 'mir4-historical-tooling-migration-predecessor-bytes'
try{Invoke-MIR4AssuranceOfflineCustodyMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-historical-tooling-migration-predecessor-write-enabled]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-assurance-offline-custody-migration-receipt-immutable]')){throw}}

$authority=Get-MIR4HistoricalToolingMigrationAuthorityV1 -RepoRoot $repo
$proof=Get-MIR4HistoricalToolingMigrationProofPolicyV1 -RepoRoot $repo
$receipt=Invoke-MIR4HistoricalToolingMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4HistoricalToolingMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4HistoricalToolingMigrationReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4HistoricalToolingMigrationReceiptSha256) 'mir4-historical-tooling-migration-immutable-successor-receipt'
Assert-MIR4HistoricalToolingMigrationV1 ((Get-Item -LiteralPath (Join-Path $repo $script:MIR4HistoricalToolingMigrationReceiptPath)).Length-eq$script:MIR4HistoricalToolingMigrationReceiptBytes) 'mir4-historical-tooling-migration-immutable-successor-bytes'
try{Invoke-MIR4HistoricalToolingMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-historical-tooling-migration-write-enabled]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-historical-tooling-migration-receipt-immutable]')){throw}}
$inventory=Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4HistoricalToolingMigrationV1 ([int]$inventory.summary.unknown-eq0-and-not[bool]$inventory.deletion_authorized) 'mir4-historical-tooling-migration-inventory'
Assert-MIR4HistoricalToolingMigrationV1 (@($authority.writers).Count-eq1-and@($authority.compatibility_entrypoints).Count-eq3) 'mir4-historical-tooling-migration-authority'
Assert-MIR4HistoricalToolingMigrationV1 ([string]$proof.test_id-ceq'static.mir4-historical-tooling-migration-v1'-and@($proof.required_checks).Count-eq30-and[string]$proof.pre_cutover_archive_content_sha256-ceq$script:MIR4HistoricalToolingArchiveContentSha256V1) 'mir4-historical-tooling-migration-proof'
Assert-MIR4HistoricalToolingMigrationV1 (Test-MIR4HistoricalToolingForwardersV1 -RepoRoot $repo) 'mir4-historical-tooling-migration-forwarders'
Assert-MIR4HistoricalToolingMigrationV1 (Test-MIR4HistoricalToolingDeclaredConsumersV1 -RepoRoot $repo) 'mir4-historical-tooling-migration-consumers'
Assert-MIR4HistoricalToolingMigrationV1 ([string](Test-MIR4HistoricalToolingFunctionalParityV1 -RepoRoot $repo).digest-ceq$script:MIR4HistoricalToolingParityDigestV1) 'mir4-historical-tooling-migration-functional-parity'

$catalog=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
Assert-MIR4HistoricalToolingMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq'static.mir4-historical-tooling-v1'-and[string]$_.command-ceq'./tests/history/Test-MIR4HistoricalTooling.ps1'}).Count-eq1) 'mir4-historical-tooling-migration-functional-registration'
Assert-MIR4HistoricalToolingMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq[string]$proof.test_id-and[string]$_.command-ceq'./tests/history/Test-MIR4HistoricalToolingMigration.ps1'}).Count-eq1) 'mir4-historical-tooling-migration-test-registration'
$assurance=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$migrationClass=@($assurance.classes|Where-Object{[string]$_.id-ceq'historical-tooling-migration'})
Assert-MIR4HistoricalToolingMigrationV1 ($migrationClass.Count-eq1-and@($migrationClass[0].tests)-contains[string]$proof.test_id) 'mir4-historical-tooling-migration-assurance-registration'
foreach($testId in @('static.mir4-historical-tooling-v1','static.mir4-historical-tooling-migration-v1')){Assert-MIR4HistoricalToolingMigrationV1 ($testId-in@($assurance.profiles.'mir4-bootstrap')) 'mir4-historical-tooling-migration-bootstrap-profile' $testId}
foreach($path in @('tools/mir/application/history/HistoricalToolingMigration.ps1','tools/mir/cli/Invoke-MIR4HistoricalToolingMigration.ps1')){Assert-MIR4HistoricalToolingMigrationV1 (@($receipt.components|Where-Object{[string]$_.path-ceq$path}).Count-eq1-and@($receipt.current_authorities|Where-Object{[string]$_.path-ceq$path}).Count-eq1) 'mir4-historical-tooling-migration-receipt-writer-binding' $path}
Assert-MIR4HistoricalToolingMigrationV1 ($packageBefore-ceq[string]$authority.package_source_sha256-and[string]$receipt.package_source_sha256-ceq$packageBefore-and@($receipt.package_visible_delta).Count-eq0) 'mir4-historical-tooling-migration-package-firewall'
Assert-MIR4HistoricalToolingMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-ceq$script:MIR4HistoricalToolingCompatibilityPolicySha256) 'mir4-historical-tooling-migration-compatibility-policy'
Assert-MIR4HistoricalToolingMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json') -Algorithm SHA256).Hash-ceq$script:MIR4HistoricalToolingT14ReceiptSha256) 'mir4-historical-tooling-migration-t14'
Assert-MIR4HistoricalToolingMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo 'tools/mir/application/release/ReleaseDag.ps1') -Algorithm SHA256).Hash-ceq$script:MIR4HistoricalToolingReleaseDagSha256) 'mir4-historical-tooling-migration-release-dag'

$prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration
Assert-MIR4HistoricalToolingMigrationV1 ([string]$receipt.predecessor_receipt.path-ceq[string]$prior.prior_receipt_path-and[string]$receipt.predecessor_receipt.sha256-ceq[string]$prior.prior_receipt_sha256) 'mir4-historical-tooling-migration-predecessor-chain'
foreach($binding in @($receipt.evolved_bindings)){$item=[string]$binding.path;Assert-MIR4HistoricalToolingMigrationV1 ($prior.authority_hashes.ContainsKey($item)-and[string]$binding.previous_sha256-ceq[string]$prior.authority_hashes[$item]) 'mir4-historical-tooling-migration-evolved-prior' $item}
Assert-MIR4HistoricalToolingMigrationV1 ([string]$receipt.digest-ceq(Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:historical-tooling-migration-receipt:1' -OmitTopLevelDigest)) 'mir4-historical-tooling-migration-receipt-digest'
foreach($field in @('transition_gate','release_transition_authority')){Assert-MIR4HistoricalToolingMigrationV1 (@($receipt.$field.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-historical-tooling-migration-release-firewall' $field}
foreach($field in @('transition_gate','release_transition_authority')){$tampered=$receipt|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$tampered.$field.publication=$true;Assert-MIR4HistoricalToolingMigrationV1 (-not(($tampered|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $repo $script:MIR4HistoricalToolingMigrationReceiptSchemaPath) -ErrorAction SilentlyContinue)) 'mir4-historical-tooling-migration-release-firewall-schema' $field}
Test-MIR4PreFreezeAuthorities -RepoRoot $repo|Out-Null
$latest=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration -IncludeHistoricalToolingMigration
Assert-MIR4HistoricalToolingMigrationV1 ([string]$latest.prior_receipt_path-ceq$script:MIR4HistoricalToolingMigrationReceiptPath) 'mir4-historical-tooling-migration-prefreeze-chain'
$releaseHistoryOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tests/release/Test-MIRPublishedSnapshotIntegrity.ps1') 2>&1|Out-String).Trim()
Assert-MIR4HistoricalToolingMigrationV1 ($LASTEXITCODE-eq0-and$releaseHistoryOutput-match'append-only-release-tooling-successor') 'mir4-historical-tooling-migration-release-history-successor' $releaseHistoryOutput

function Invoke-MIR4HistoricalToolingMigrationCommandProbeV1([string]$Command){$output=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4HistoricalToolingMigration.ps1') -Command $Command -RepoRoot $repo 2>&1|Out-String).Trim();if($LASTEXITCODE-ne0){throw "[mir4-historical-tooling-migration-cli] $Command $output"};return $output|ConvertFrom-Json -Depth 100}
$checkResult=Invoke-MIR4HistoricalToolingMigrationCommandProbeV1 check;$showResult=Invoke-MIR4HistoricalToolingMigrationCommandProbeV1 show
Assert-MIR4HistoricalToolingMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $showResult)) 'mir4-historical-tooling-migration-cli-parity'
$facadeOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 historical-tooling-migration check 2>&1|Out-String).Trim()
Assert-MIR4HistoricalToolingMigrationV1 ($LASTEXITCODE-eq0-and(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 ($facadeOutput|ConvertFrom-Json -Depth 100))) 'mir4-historical-tooling-migration-facade-parity'
$predecessorGenerateOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 assurance-offline-custody-migration generate 2>&1|Out-String).Trim()
Assert-MIR4HistoricalToolingMigrationV1 ($LASTEXITCODE-ne0-and$predecessorGenerateOutput-match'Unknown mir4 assurance-offline-custody-migration command: generate') 'mir4-historical-tooling-migration-predecessor-facade-write-enabled'

$exportRoot='build/mir4/test-historical-tooling-parity'
$canonicalExportOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Export-MIR4HistoricalSuccessionRecords.ps1') -RepoRoot $repo -OutputRoot $exportRoot 2>&1|Out-String).Trim()
Assert-MIR4HistoricalToolingMigrationV1 ($LASTEXITCODE-eq0) 'mir4-historical-tooling-migration-canonical-export' $canonicalExportOutput
$canonicalHashes=[ordered]@{};foreach($file in Get-ChildItem -LiteralPath (Join-Path $repo $exportRoot) -Recurse -File){$canonicalHashes[[IO.Path]::GetRelativePath((Join-Path $repo $exportRoot),$file.FullName).Replace('\','/')]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
$compatibilityExportOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/commands/mir4/Export-MIR4HistoricalSuccessionRecords.ps1') -RepoRoot $repo -OutputRoot $exportRoot 2>&1|Out-String).Trim()
Assert-MIR4HistoricalToolingMigrationV1 ($LASTEXITCODE-eq0) 'mir4-historical-tooling-migration-compatibility-export' $compatibilityExportOutput
$compatibilityHashes=[ordered]@{};foreach($file in Get-ChildItem -LiteralPath (Join-Path $repo $exportRoot) -Recurse -File){$compatibilityHashes[[IO.Path]::GetRelativePath((Join-Path $repo $exportRoot),$file.FullName).Replace('\','/')]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
Assert-MIR4HistoricalToolingMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $canonicalHashes)-ceq(ConvertTo-MIR4CanonicalJsonV1 $compatibilityHashes)) 'mir4-historical-tooling-migration-export-parity'
foreach($path in $packageHashes.Keys){Assert-MIR4HistoricalToolingMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $path) -Algorithm SHA256).Hash-ceq[string]$packageHashes[$path]) 'mir4-historical-tooling-migration-player-authority-mutation' $path}
Assert-MIR4HistoricalToolingMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-historical-tooling-migration-package-source-mutation'
[pscustomobject][ordered]@{status='accepted';migration_id=[string]$receipt.migration_id;canonical_applications=@('tools/mir/application/history/HistoricalSuccession.ps1','tools/mir/application/history/SuccessorHost.ps1');compatibility_entrypoints=@($authority.compatibility_entrypoints.path);predecessor_receipt_sha256=$script:MIR4HistoricalToolingPredecessorReceiptSha256;receipt_digest=[string]$receipt.digest;package_source_sha256=[string]$receipt.package_source_sha256;package_visible_delta=@();release_transition_authority=$false}
