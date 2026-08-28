param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/processir/ProcessIRExactMigration.ps1')
. (Join-Path $repo 'tools/mir/application/inspection/InspectorCompatibilityMigration.ps1')

function Assert-MIR4InspectorCompatibilityMigrationV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$compatibilityBefore=(Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash
$claimsBefore=(Get-FileHash -LiteralPath (Join-Path $repo 'spec/compatibility/claims.json') -Algorithm SHA256).Hash
$packageHashes=[ordered]@{};foreach($path in @(Get-MIRPackageSourceFiles -RepoRoot $repo)){$packageHashes[[string]$path]=(Get-FileHash -LiteralPath (Join-Path $repo ([string]$path)) -Algorithm SHA256).Hash}
$t13Hashes=[ordered]@{'sdk/preview/mir4/reference/t13/MIR4_T13_RECEIPT.json'=$script:MIR4InspectorCompatibilityT13ReceiptSha256;'sdk/preview/mir4/reference/t13/MIR4_T13_MANIFEST.json'=$script:MIR4InspectorCompatibilityT13ManifestSha256}

$predecessor=Invoke-MIR4ProcessIRExactMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4InspectorCompatibilityMigrationV1 ([string]$predecessor.migration_id-ceq'MIR4-PROCESSIR-EXACT-TOOLING-V1') 'mir4-inspector-compatibility-migration-predecessor-id'
Assert-MIR4InspectorCompatibilityMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4InspectorCompatibilityPredecessorReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4InspectorCompatibilityPredecessorReceiptSha256) 'mir4-inspector-compatibility-migration-predecessor-immutable'
try{Invoke-MIR4ProcessIRExactMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-inspector-compatibility-migration-predecessor-write-enabled]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-processir-exact-migration-receipt-immutable]')){throw}}

$authority=Get-MIR4InspectorCompatibilityMigrationAuthorityV1 -RepoRoot $repo;$proof=Get-MIR4InspectorCompatibilityMigrationProofPolicyV1 -RepoRoot $repo;$receipt=Invoke-MIR4InspectorCompatibilityMigrationProjectionV1 -RepoRoot $repo -Check
$platformLock=Get-Content -Raw -LiteralPath (Join-Path $repo 'mir.lock')|ConvertFrom-Json -Depth 100
Assert-MIR4InspectorCompatibilityMigrationV1 (@($platformLock.inputs|Where-Object{[string]$_.path-ceq'spec/schemas/mir4-inspector-compatibility-programme-v1.schema.json'}).Count-eq1) 'mir4-inspector-compatibility-migration-platform-input-schema'
$inventory=Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4InspectorCompatibilityMigrationV1 ([int]$inventory.summary.unknown-eq0) 'mir4-inspector-compatibility-migration-inventory-unknown'
Assert-MIR4InspectorCompatibilityMigrationV1 (-not[bool]$inventory.deletion_authorized-and@($authority.writers).Count-eq1) 'mir4-inspector-compatibility-migration-authority'
Assert-MIR4InspectorCompatibilityMigrationV1 ([string]$proof.test_id-ceq'static.mir4-inspector-compatibility-migration-v1'-and[string]$proof.pre_cutover_functional_digest-ceq$script:MIR4InspectorCompatibilityPreCutoverDigestV1-and[string]$proof.terminal_claims_sha256-ceq$script:MIR4InspectorCompatibilityTerminalClaimsSha256) 'mir4-inspector-compatibility-migration-proof'
Assert-MIR4InspectorCompatibilityMigrationV1 (Test-MIR4InspectorCompatibilityForwardersV1 -RepoRoot $repo) 'mir4-inspector-compatibility-migration-forwarders'
Assert-MIR4InspectorCompatibilityMigrationV1 (Test-MIR4InspectorCompatibilityDeclaredConsumersV1 -RepoRoot $repo) 'mir4-inspector-compatibility-migration-consumers'
Assert-MIR4InspectorCompatibilityMigrationV1 ([string](Test-MIR4InspectorCompatibilityFunctionalParityV1 -RepoRoot $repo).digest-ceq$script:MIR4InspectorCompatibilityParityDigestV1) 'mir4-inspector-compatibility-migration-functional-parity'

$catalog=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
Assert-MIR4InspectorCompatibilityMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq'static.mir4-inspector-compatibility-v1'-and[string]$_.command-ceq'./tests/inspection/Test-MIR4InspectorCompatibility.ps1'}).Count-eq1) 'mir4-inspector-compatibility-migration-functional-registration'
Assert-MIR4InspectorCompatibilityMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq[string]$proof.test_id-and[string]$_.command-ceq'./tests/inspection/Test-MIR4InspectorCompatibilityMigration.ps1'}).Count-eq1) 'mir4-inspector-compatibility-migration-test-registration'
$migrationClass=@((Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json').classes|Where-Object{[string]$_.id-ceq'inspector-compatibility-migration'})
Assert-MIR4InspectorCompatibilityMigrationV1 ($migrationClass.Count-eq1-and@($migrationClass[0].tests)-contains[string]$proof.test_id) 'mir4-inspector-compatibility-migration-assurance-registration'
foreach($item in @(@($authority.path_map.final_path)+@($authority.compatibility_entrypoints.path)|Sort-Object -Unique)){Assert-MIR4InspectorCompatibilityMigrationV1 (@($migrationClass[0].patterns|Where-Object{$item-match[string]$_}).Count-gt0) 'mir4-inspector-compatibility-migration-assurance-path' $item;Assert-MIR4InspectorCompatibilityMigrationV1 ($item-notin@(Get-MIRPackageSourceFiles -RepoRoot $repo)) 'mir4-inspector-compatibility-migration-package-visible' $item}
Assert-MIR4InspectorCompatibilityMigrationV1 ($packageBefore-ceq[string]$authority.package_source_sha256-and[string]$receipt.package_source_sha256-ceq$packageBefore-and@($receipt.package_visible_delta).Count-eq0) 'mir4-inspector-compatibility-migration-package-firewall'
Assert-MIR4InspectorCompatibilityMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-ceq$compatibilityBefore-and$compatibilityBefore-ceq$script:MIR4InspectorCompatibilityPolicySha256) 'mir4-inspector-compatibility-migration-compatibility-policy'
Assert-MIR4InspectorCompatibilityMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo 'spec/compatibility/claims.json') -Algorithm SHA256).Hash-ceq$claimsBefore-and$claimsBefore-ceq$script:MIR4InspectorCompatibilityTerminalClaimsSha256) 'mir4-inspector-compatibility-migration-terminal-claims'
foreach($item in $t13Hashes.Keys){Assert-MIR4InspectorCompatibilityMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $item) -Algorithm SHA256).Hash-ceq[string]$t13Hashes[$item]) 'mir4-inspector-compatibility-migration-historical-t13' $item}

$prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration
Assert-MIR4InspectorCompatibilityMigrationV1 ([string]$receipt.predecessor_receipt.path-ceq[string]$prior.prior_receipt_path-and[string]$receipt.predecessor_receipt.sha256-ceq[string]$prior.prior_receipt_sha256) 'mir4-inspector-compatibility-migration-predecessor-chain'
foreach($binding in @($receipt.evolved_bindings)){$item=[string]$binding.path;Assert-MIR4InspectorCompatibilityMigrationV1 ($prior.authority_hashes.ContainsKey($item)-and[string]$binding.previous_sha256-ceq[string]$prior.authority_hashes[$item]) 'mir4-inspector-compatibility-migration-evolved-prior' $item;Assert-MIR4InspectorCompatibilityMigrationV1 ([string]$binding.current_sha256-ceq(Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $item) -Mode ([string]$binding.hash_mode))) 'mir4-inspector-compatibility-migration-evolved-current' $item}
foreach($binding in @($receipt.current_authorities)){$actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$binding.path)) -Mode ([string]$binding.hash_mode);Assert-MIR4InspectorCompatibilityMigrationV1 ([string]$binding.sha256-ceq$actual) 'mir4-inspector-compatibility-migration-current-authority' ([string]$binding.path)}
Assert-MIR4InspectorCompatibilityMigrationV1 ([string]$receipt.digest-ceq(Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:inspector-compatibility-migration-receipt:1' -OmitTopLevelDigest)) 'mir4-inspector-compatibility-migration-receipt-digest'
foreach($field in @('transition_gate','release_transition_authority')){Assert-MIR4InspectorCompatibilityMigrationV1 (@($receipt.$field.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-inspector-compatibility-migration-release-firewall' $field}
Test-MIR4PreFreezeAuthorities -RepoRoot $repo|Out-Null
$latest=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration
Assert-MIR4InspectorCompatibilityMigrationV1 ([string]$latest.prior_receipt_path-ceq$script:MIR4InspectorCompatibilityMigrationReceiptPath) 'mir4-inspector-compatibility-migration-prefreeze-chain'
$releaseHistoryOutput=(& pwsh -NoProfile -File (Join-Path $repo 'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1') 2>&1|Out-String).Trim()
Assert-MIR4InspectorCompatibilityMigrationV1 ($LASTEXITCODE-eq0-and$releaseHistoryOutput-match'append-only-inspector-compatibility-successor') 'mir4-inspector-compatibility-migration-release-history-successor' $releaseHistoryOutput

function Invoke-MIR4InspectorCompatibilityMigrationCommandProbeV1([string]$Command){$output=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4InspectorCompatibilityMigration.ps1') -Command $Command -RepoRoot $repo 2>&1|Out-String).Trim();if($LASTEXITCODE-ne0){throw "[mir4-inspector-compatibility-migration-cli] $Command $output"};return $output|ConvertFrom-Json -Depth 100}
$generateResult=Invoke-MIR4InspectorCompatibilityMigrationCommandProbeV1 generate;$checkResult=Invoke-MIR4InspectorCompatibilityMigrationCommandProbeV1 check;$showResult=Invoke-MIR4InspectorCompatibilityMigrationCommandProbeV1 show
Assert-MIR4InspectorCompatibilityMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $generateResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-and(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $showResult)) 'mir4-inspector-compatibility-migration-cli-parity'
$facadeOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 inspector-compatibility-migration check 2>&1|Out-String).Trim()
Assert-MIR4InspectorCompatibilityMigrationV1 ($LASTEXITCODE-eq0-and(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 ($facadeOutput|ConvertFrom-Json -Depth 100))) 'mir4-inspector-compatibility-migration-facade-parity'
$processIRGenerateOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 processir-exact-migration generate 2>&1|Out-String).Trim()
Assert-MIR4InspectorCompatibilityMigrationV1 ($LASTEXITCODE-ne0-and$processIRGenerateOutput-match'Unknown mir4 processir-exact-migration command: generate') 'mir4-inspector-compatibility-migration-predecessor-facade-write-enabled'

$exportRoot='build/mir4/test-inspector-compatibility-parity'
& (Join-Path $repo 'tools/mir/cli/Export-MIR4InspectorCompatibilityRecords.ps1') -RepoRoot $repo -OutputRoot $exportRoot|Out-Null
$canonicalHashes=[ordered]@{};foreach($file in Get-ChildItem -LiteralPath (Join-Path $repo $exportRoot) -Recurse -File){$canonicalHashes[[IO.Path]::GetRelativePath((Join-Path $repo $exportRoot),$file.FullName).Replace('\','/')]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
& (Join-Path $repo 'tools/commands/mir4/Export-MIR4InspectorCompatibilityRecords.ps1') -RepoRoot $repo -OutputRoot $exportRoot|Out-Null
$compatibilityHashes=[ordered]@{};foreach($file in Get-ChildItem -LiteralPath (Join-Path $repo $exportRoot) -Recurse -File){$compatibilityHashes[[IO.Path]::GetRelativePath((Join-Path $repo $exportRoot),$file.FullName).Replace('\','/')]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
Assert-MIR4InspectorCompatibilityMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $canonicalHashes)-ceq(ConvertTo-MIR4CanonicalJsonV1 $compatibilityHashes)) 'mir4-inspector-compatibility-migration-export-parity'
$canonicalCanary=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Export-MIR4CompatibilityCanaryRecords.ps1') -RepoRoot $repo -Check 2>&1|Out-String).Trim()
$compatibilityCanary=(& pwsh -NoProfile -File (Join-Path $repo 'tools/commands/mir4/Export-MIR4CompatibilityCanaryRecords.ps1') -RepoRoot $repo -Check 2>&1|Out-String).Trim()
Assert-MIR4InspectorCompatibilityMigrationV1 ($LASTEXITCODE-eq0-and$canonicalCanary-ceq$compatibilityCanary) 'mir4-inspector-compatibility-migration-canary-check-parity'
foreach($path in $packageHashes.Keys){Assert-MIR4InspectorCompatibilityMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $path) -Algorithm SHA256).Hash-ceq[string]$packageHashes[$path]) 'mir4-inspector-compatibility-migration-player-authority-mutation' $path}
Assert-MIR4InspectorCompatibilityMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-inspector-compatibility-migration-package-source-mutation'
[pscustomobject][ordered]@{status='accepted';migration_id=[string]$receipt.migration_id;canonical_applications=@('tools/mir/application/inspection/SupportAssessment.ps1','tools/mir/application/inspection/CompatibilityIndex.ps1','tools/mir/application/inspection/CompatibilityFactory.ps1','tools/mir/application/inspection/Inspector.ps1','tools/mir/application/inspection/CompatibilityCanary.ps1');compatibility_entrypoints=@($authority.compatibility_entrypoints.path);predecessor_receipt_sha256=$script:MIR4InspectorCompatibilityPredecessorReceiptSha256;receipt_digest=[string]$receipt.digest;package_source_sha256=[string]$receipt.package_source_sha256;package_visible_delta=@();release_transition_authority=$false}
