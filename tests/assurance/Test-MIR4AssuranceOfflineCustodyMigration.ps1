param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/assurance/AssuranceOfflineCustodyMigration.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

function Assert-MIR4AssuranceOfflineCustodyMigrationV1([bool]$Condition,[string]$Code,[string]$Detail=''){if(-not$Condition){throw "[$Code] $Detail"}}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$compatibilityBefore=(Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash
$packageHashes=[ordered]@{};foreach($path in @(Get-MIRPackageSourceFiles -RepoRoot $repo)){$packageHashes[[string]$path]=(Get-FileHash -LiteralPath (Join-Path $repo ([string]$path)) -Algorithm SHA256).Hash}
$historicalHashes=[ordered]@{
  '.mir/releases/waves/mir4-r0/MIR4-T10-Authority-Evolution-ReceiptV1.json'=$script:MIR4AssuranceOfflineCustodyT10ReceiptSha256
  '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json'=$script:MIR4AssuranceOfflineCustodyT15ReceiptSha256
  '.mir/releases/waves/mir4-r0/MIR4-T15-Independent-Machine-AcceptanceV1.json'=$script:MIR4AssuranceOfflineCustodyT15AcceptanceSha256
}

$predecessor=Invoke-MIR4InspectorCompatibilityMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ([string]$predecessor.migration_id-ceq'MIR4-INSPECTOR-COMPATIBILITY-TOOLING-V1') 'mir4-assurance-offline-custody-migration-predecessor-id'
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4AssuranceOfflineCustodyPredecessorReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4AssuranceOfflineCustodyPredecessorReceiptSha256) 'mir4-assurance-offline-custody-migration-predecessor-immutable'
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ((Get-Item -LiteralPath (Join-Path $repo $script:MIR4AssuranceOfflineCustodyPredecessorReceiptPath)).Length-eq56839) 'mir4-assurance-offline-custody-migration-predecessor-bytes'
try{Invoke-MIR4InspectorCompatibilityMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-assurance-offline-custody-migration-predecessor-write-enabled]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-inspector-compatibility-migration-receipt-immutable]')){throw}}

$authority=Get-MIR4AssuranceOfflineCustodyMigrationAuthorityV1 -RepoRoot $repo
$proof=Get-MIR4AssuranceOfflineCustodyMigrationProofPolicyV1 -RepoRoot $repo
$receipt=Invoke-MIR4AssuranceOfflineCustodyMigrationProjectionV1 -RepoRoot $repo -Check
$platformLock=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'mir.lock'
Assert-MIR4AssuranceOfflineCustodyMigrationV1 (@($platformLock.inputs|Where-Object{[string]$_.path-ceq'spec/schemas/mir4-assurance-scale-programme-v1.schema.json'}).Count-eq1) 'mir4-assurance-offline-custody-migration-platform-input-schema'
$inventory=Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ([int]$inventory.summary.unknown-eq0) 'mir4-assurance-offline-custody-migration-inventory-unknown'
Assert-MIR4AssuranceOfflineCustodyMigrationV1 (-not[bool]$inventory.deletion_authorized-and@($authority.writers).Count-eq1-and@($authority.compatibility_entrypoints).Count-eq7) 'mir4-assurance-offline-custody-migration-authority'
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ([string]$proof.test_id-ceq'static.mir4-assurance-offline-custody-migration-v1'-and@($proof.required_checks).Count-eq32-and[string]$proof.pre_cutover_functional_digest-ceq$script:MIR4AssuranceOfflineCustodyPreCutoverDigestV1) 'mir4-assurance-offline-custody-migration-proof'
Assert-MIR4AssuranceOfflineCustodyMigrationV1 (Test-MIR4AssuranceOfflineCustodyForwardersV1 -RepoRoot $repo) 'mir4-assurance-offline-custody-migration-forwarders'
Assert-MIR4AssuranceOfflineCustodyMigrationV1 (Test-MIR4AssuranceOfflineCustodyDeclaredConsumersV1 -RepoRoot $repo) 'mir4-assurance-offline-custody-migration-consumers'
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ([string](Test-MIR4AssuranceOfflineCustodyFunctionalParityV1 -RepoRoot $repo).digest-ceq$script:MIR4AssuranceOfflineCustodyParityDigestV1) 'mir4-assurance-offline-custody-migration-functional-parity'

$catalog=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
Assert-MIR4AssuranceOfflineCustodyMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq'static.mir4-assurance-offline-custody-v1'-and[string]$_.command-ceq'./tests/assurance/Test-MIR4AssuranceOfflineCustody.ps1'}).Count-eq1) 'mir4-assurance-offline-custody-migration-functional-registration'
Assert-MIR4AssuranceOfflineCustodyMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq[string]$proof.test_id-and[string]$_.command-ceq'./tests/assurance/Test-MIR4AssuranceOfflineCustodyMigration.ps1'}).Count-eq1) 'mir4-assurance-offline-custody-migration-test-registration'
$migrationClass=@((Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json').classes|Where-Object{[string]$_.id-ceq'assurance-offline-custody-migration'})
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($migrationClass.Count-eq1-and@($migrationClass[0].tests)-contains[string]$proof.test_id) 'mir4-assurance-offline-custody-migration-assurance-registration'
foreach($item in @(@($authority.path_map.final_path)+@($authority.compatibility_entrypoints.path)|Sort-Object -Unique)){Assert-MIR4AssuranceOfflineCustodyMigrationV1 (@($migrationClass[0].patterns|Where-Object{$item-match[string]$_}).Count-gt0) 'mir4-assurance-offline-custody-migration-assurance-path' $item;Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($item-notin@(Get-MIRPackageSourceFiles -RepoRoot $repo)) 'mir4-assurance-offline-custody-migration-package-visible' $item}
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($packageBefore-ceq[string]$authority.package_source_sha256-and[string]$receipt.package_source_sha256-ceq$packageBefore-and@($receipt.package_visible_delta).Count-eq0) 'mir4-assurance-offline-custody-migration-package-firewall'
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($compatibilityBefore-ceq$script:MIR4AssuranceOfflineCustodyCompatibilityPolicySha256-and(Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-ceq$compatibilityBefore) 'mir4-assurance-offline-custody-migration-compatibility-policy'
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ((Get-MIR4AssuranceV4PreservationDigestV1 -RepoRoot $repo)-ceq$script:MIR4AssuranceV4PreservationDigestV1) 'mir4-assurance-offline-custody-migration-assurance-v4'
foreach($item in $historicalHashes.Keys){Assert-MIR4AssuranceOfflineCustodyMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $item) -Algorithm SHA256).Hash-ceq[string]$historicalHashes[$item]) 'mir4-assurance-offline-custody-migration-historical-evidence' $item}

$prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ([string]$receipt.predecessor_receipt.path-ceq[string]$prior.prior_receipt_path-and[string]$receipt.predecessor_receipt.sha256-ceq[string]$prior.prior_receipt_sha256) 'mir4-assurance-offline-custody-migration-predecessor-chain'
foreach($binding in @($receipt.evolved_bindings)){$item=[string]$binding.path;Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($prior.authority_hashes.ContainsKey($item)-and[string]$binding.previous_sha256-ceq[string]$prior.authority_hashes[$item]) 'mir4-assurance-offline-custody-migration-evolved-prior' $item;Assert-MIR4AssuranceOfflineCustodyMigrationV1 ([string]$binding.current_sha256-ceq(Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $item) -Mode ([string]$binding.hash_mode))) 'mir4-assurance-offline-custody-migration-evolved-current' $item}
foreach($binding in @($receipt.current_authorities)){$actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$binding.path)) -Mode ([string]$binding.hash_mode);Assert-MIR4AssuranceOfflineCustodyMigrationV1 ([string]$binding.sha256-ceq$actual) 'mir4-assurance-offline-custody-migration-current-authority' ([string]$binding.path)}
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ([string]$receipt.digest-ceq(Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:assurance-offline-custody-migration-receipt:1' -OmitTopLevelDigest)) 'mir4-assurance-offline-custody-migration-receipt-digest'
foreach($field in @('transition_gate','release_transition_authority')){Assert-MIR4AssuranceOfflineCustodyMigrationV1 (@($receipt.$field.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-assurance-offline-custody-migration-release-firewall' $field}
Test-MIR4PreFreezeAuthorities -RepoRoot $repo|Out-Null
$latest=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ([string]$latest.prior_receipt_path-ceq$script:MIR4AssuranceOfflineCustodyMigrationReceiptPath) 'mir4-assurance-offline-custody-migration-prefreeze-chain'
$releaseHistoryOutput=(& pwsh -NoProfile -File (Join-Path $repo 'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1') 2>&1|Out-String).Trim()
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($LASTEXITCODE-eq0-and$releaseHistoryOutput-match'append-only-assurance-offline-custody-successor') 'mir4-assurance-offline-custody-migration-release-history-successor' $releaseHistoryOutput

function Invoke-MIR4AssuranceOfflineCustodyMigrationCommandProbeV1([string]$Command){$output=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4AssuranceOfflineCustodyMigration.ps1') -Command $Command -RepoRoot $repo 2>&1|Out-String).Trim();if($LASTEXITCODE-ne0){throw "[mir4-assurance-offline-custody-migration-cli] $Command $output"};return $output|ConvertFrom-Json -Depth 100}
$generateResult=Invoke-MIR4AssuranceOfflineCustodyMigrationCommandProbeV1 generate;$checkResult=Invoke-MIR4AssuranceOfflineCustodyMigrationCommandProbeV1 check;$showResult=Invoke-MIR4AssuranceOfflineCustodyMigrationCommandProbeV1 show
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $generateResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-and(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $showResult)) 'mir4-assurance-offline-custody-migration-cli-parity'
$facadeOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 assurance-offline-custody-migration check 2>&1|Out-String).Trim()
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($LASTEXITCODE-eq0-and(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 ($facadeOutput|ConvertFrom-Json -Depth 100))) 'mir4-assurance-offline-custody-migration-facade-parity'
$predecessorGenerateOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 inspector-compatibility-migration generate 2>&1|Out-String).Trim()
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($LASTEXITCODE-ne0-and$predecessorGenerateOutput-match'Unknown mir4 inspector-compatibility-migration command: generate') 'mir4-assurance-offline-custody-migration-predecessor-facade-write-enabled'

$environmentCanonical=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4EnvironmentEvidence.ps1') reference -RepoRoot $repo 2>&1|Out-String).Trim()
$environmentCompatibility=(& pwsh -NoProfile -File (Join-Path $repo 'tools/commands/mir4/Invoke-MIR4EnvironmentEvidence.ps1') reference -RepoRoot $repo 2>&1|Out-String).Trim()
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($LASTEXITCODE-eq0-and$environmentCanonical-ceq$environmentCompatibility) 'mir4-assurance-offline-custody-migration-environment-command-parity'
$environmentFacade=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 environment-evidence reference 2>&1|Out-String).Trim()
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($LASTEXITCODE-eq0-and$environmentCanonical-ceq$environmentFacade) 'mir4-assurance-offline-custody-migration-environment-facade-parity'
$exportRoot='build/mir4/test-assurance-offline-custody-parity'
$canonicalExportOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Export-MIR4AssuranceScaleRecords.ps1') -RepoRoot $repo -OutputRoot $exportRoot 2>&1|Out-String).Trim()
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($LASTEXITCODE-eq0) 'mir4-assurance-offline-custody-migration-canonical-export' $canonicalExportOutput
$canonicalHashes=[ordered]@{};foreach($file in Get-ChildItem -LiteralPath (Join-Path $repo $exportRoot) -Recurse -File){$canonicalHashes[[IO.Path]::GetRelativePath((Join-Path $repo $exportRoot),$file.FullName).Replace('\','/')]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
$compatibilityExportOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/commands/mir4/Export-MIR4AssuranceScaleRecords.ps1') -RepoRoot $repo -OutputRoot $exportRoot 2>&1|Out-String).Trim()
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($LASTEXITCODE-eq0) 'mir4-assurance-offline-custody-migration-compatibility-export' $compatibilityExportOutput
$compatibilityHashes=[ordered]@{};foreach($file in Get-ChildItem -LiteralPath (Join-Path $repo $exportRoot) -Recurse -File){$compatibilityHashes[[IO.Path]::GetRelativePath((Join-Path $repo $exportRoot),$file.FullName).Replace('\','/')]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $canonicalHashes)-ceq(ConvertTo-MIR4CanonicalJsonV1 $compatibilityHashes)) 'mir4-assurance-offline-custody-migration-assurance-export-parity'
& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 assurance-scale check --output $exportRoot|Out-Null
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ($LASTEXITCODE-eq0) 'mir4-assurance-offline-custody-migration-assurance-facade-parity'
foreach($path in $packageHashes.Keys){Assert-MIR4AssuranceOfflineCustodyMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $path) -Algorithm SHA256).Hash-ceq[string]$packageHashes[$path]) 'mir4-assurance-offline-custody-migration-player-authority-mutation' $path}
Assert-MIR4AssuranceOfflineCustodyMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-assurance-offline-custody-migration-package-source-mutation'
[pscustomobject][ordered]@{status='accepted';migration_id=[string]$receipt.migration_id;canonical_applications=@('tools/mir/application/assurance/AssuranceScale.ps1','tools/mir/application/assurance/ReleaseBudget.ps1','tools/mir/application/assurance/OfflineDrill.ps1','tools/mir/application/assurance/EnvironmentEvidence.ps1','tools/mir/application/custody/OfflineCandidateCustody.ps1');compatibility_entrypoints=@($authority.compatibility_entrypoints.path);predecessor_receipt_sha256=$script:MIR4AssuranceOfflineCustodyPredecessorReceiptSha256;receipt_digest=[string]$receipt.digest;package_source_sha256=[string]$receipt.package_source_sha256;package_visible_delta=@();release_transition_authority=$false}
