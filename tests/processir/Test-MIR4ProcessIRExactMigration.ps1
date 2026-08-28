param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/extensions/ModuleSdkMepMigration.ps1')
. (Join-Path $repo 'tools/mir/application/processir/ProcessIRExactMigration.ps1')

function Assert-MIR4ProcessIRExactMigrationV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$compatibilityBefore=(Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash
$packageHashes=[ordered]@{};foreach($path in @(Get-MIRPackageSourceFiles -RepoRoot $repo)){$packageHashes[[string]$path]=(Get-FileHash -LiteralPath (Join-Path $repo ([string]$path)) -Algorithm SHA256).Hash}
$t12Hashes=[ordered]@{'sdk/preview/mir4/reference/t12/MIR4_T12_RECEIPT.json'='3ED97AD8417F0FFFCDD01FE496AEAD70E4F64F29F80A703BC2842F36113C2441';'sdk/preview/mir4/reference/t12/MIR4_T12_EXACT_PROCESSIR_MANIFEST.json'='AE2A8CFBCE866C2543E4FDE24E1CE976344509929D4971BE6789E55C5735510D'}

$predecessor=Invoke-MIR4ModuleSdkMepMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4ProcessIRExactMigrationV1 ([string]$predecessor.migration_id-ceq'MIR4-MODULE-SDK-MEP-TOOLING-V1') 'mir4-processir-exact-migration-predecessor-id'
Assert-MIR4ProcessIRExactMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4ProcessIRExactPredecessorReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4ProcessIRExactPredecessorReceiptSha256) 'mir4-processir-exact-migration-predecessor-immutable'
try{Invoke-MIR4ModuleSdkMepMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-processir-exact-migration-predecessor-write-enabled]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-module-sdk-mep-migration-receipt-immutable]')){throw}}

$authority=Get-MIR4ProcessIRExactMigrationAuthorityV1 -RepoRoot $repo;$proof=Get-MIR4ProcessIRExactMigrationProofPolicyV1 -RepoRoot $repo;$receipt=Invoke-MIR4ProcessIRExactMigrationProjectionV1 -RepoRoot $repo -Check
$inventory=Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4ProcessIRExactMigrationV1 ([int]$inventory.summary.unknown-eq0) 'mir4-processir-exact-migration-inventory-unknown'
Assert-MIR4ProcessIRExactMigrationV1 (-not[bool]$inventory.deletion_authorized-and@($authority.writers).Count-eq1) 'mir4-processir-exact-migration-authority'
Assert-MIR4ProcessIRExactMigrationV1 ([string]$proof.test_id-ceq'static.mir4-processir-exact-migration-v1'-and[string]$proof.pre_cutover_functional_digest-ceq$script:MIR4ProcessIRExactPreCutoverDigestV1) 'mir4-processir-exact-migration-proof'
Assert-MIR4ProcessIRExactMigrationV1 (Test-MIR4ProcessIRExactCompatibilityForwardersV1 -RepoRoot $repo) 'mir4-processir-exact-migration-forwarders'
Assert-MIR4ProcessIRExactMigrationV1 (Test-MIR4ProcessIRExactDeclaredConsumersV1 -RepoRoot $repo) 'mir4-processir-exact-migration-consumers'
Assert-MIR4ProcessIRExactMigrationV1 ([string](Test-MIR4ProcessIRExactFunctionalParityV1 -RepoRoot $repo).digest-ceq$script:MIR4ProcessIRExactParityDigestV1) 'mir4-processir-exact-migration-functional-parity'

$catalog=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
Assert-MIR4ProcessIRExactMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq'static.mir4-processir-exact-v1'-and[string]$_.command-ceq'./tests/processir/Test-MIR4ProcessIRExact.ps1'}).Count-eq1) 'mir4-processir-exact-migration-functional-registration'
Assert-MIR4ProcessIRExactMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq[string]$proof.test_id-and[string]$_.command-ceq'./tests/processir/Test-MIR4ProcessIRExactMigration.ps1'}).Count-eq1) 'mir4-processir-exact-migration-test-registration'
$migrationClass=@((Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json').classes|Where-Object{[string]$_.id-ceq'repository-migration'})
Assert-MIR4ProcessIRExactMigrationV1 ($migrationClass.Count-eq1-and@($migrationClass[0].tests)-contains[string]$proof.test_id) 'mir4-processir-exact-migration-assurance-registration'
foreach($item in @(@($authority.path_map.final_path)+@($authority.compatibility_entrypoints.path)|Sort-Object -Unique)){Assert-MIR4ProcessIRExactMigrationV1 (@($migrationClass[0].patterns|Where-Object{$item-match[string]$_}).Count-gt0) 'mir4-processir-exact-migration-assurance-path' $item;Assert-MIR4ProcessIRExactMigrationV1 ($item-notin@(Get-MIRPackageSourceFiles -RepoRoot $repo)) 'mir4-processir-exact-migration-package-visible' $item}
Assert-MIR4ProcessIRExactMigrationV1 ($packageBefore-ceq[string]$authority.package_source_sha256-and[string]$receipt.package_source_sha256-ceq$packageBefore-and@($receipt.package_visible_delta).Count-eq0) 'mir4-processir-exact-migration-package-firewall'
Assert-MIR4ProcessIRExactMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-ceq$compatibilityBefore) 'mir4-processir-exact-migration-compatibility-policy'
foreach($item in $t12Hashes.Keys){Assert-MIR4ProcessIRExactMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $item) -Algorithm SHA256).Hash-ceq[string]$t12Hashes[$item]) 'mir4-processir-exact-migration-historical-t12' $item}

$prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration
Assert-MIR4ProcessIRExactMigrationV1 ([string]$receipt.predecessor_receipt.path-ceq[string]$prior.prior_receipt_path-and[string]$receipt.predecessor_receipt.sha256-ceq[string]$prior.prior_receipt_sha256) 'mir4-processir-exact-migration-predecessor-chain'
foreach($binding in @($receipt.evolved_bindings)){$item=[string]$binding.path;Assert-MIR4ProcessIRExactMigrationV1 ($prior.authority_hashes.ContainsKey($item)-and[string]$binding.previous_sha256-ceq[string]$prior.authority_hashes[$item]) 'mir4-processir-exact-migration-evolved-prior' $item;Assert-MIR4ProcessIRExactMigrationV1 ([string]$binding.current_sha256-ceq(Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $item) -Mode ([string]$binding.hash_mode))) 'mir4-processir-exact-migration-evolved-current' $item}
foreach($binding in @($receipt.current_authorities)){$actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$binding.path)) -Mode ([string]$binding.hash_mode);Assert-MIR4ProcessIRExactMigrationV1 ([string]$binding.sha256-ceq$actual) 'mir4-processir-exact-migration-current-authority' ([string]$binding.path)}
Assert-MIR4ProcessIRExactMigrationV1 ([string]$receipt.digest-ceq(Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:processir-exact-migration-receipt:1' -OmitTopLevelDigest)) 'mir4-processir-exact-migration-receipt-digest'
foreach($field in @('transition_gate','release_transition_authority')){Assert-MIR4ProcessIRExactMigrationV1 (@($receipt.$field.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-processir-exact-migration-release-firewall' $field}
Test-MIR4PreFreezeAuthorities -RepoRoot $repo|Out-Null
$latest=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration
Assert-MIR4ProcessIRExactMigrationV1 ([string]$latest.prior_receipt_path-ceq$script:MIR4ProcessIRExactMigrationReceiptPath) 'mir4-processir-exact-migration-prefreeze-chain'
$releaseHistoryOutput=(& pwsh -NoProfile -File (Join-Path $repo 'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1') 2>&1|Out-String).Trim()
Assert-MIR4ProcessIRExactMigrationV1 ($LASTEXITCODE-eq0-and$releaseHistoryOutput-match'append-only-processir-exact-successor') 'mir4-processir-exact-migration-release-history-successor' $releaseHistoryOutput

function Invoke-MIR4ProcessIRExactMigrationCommandProbeV1([string]$Command){$output=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4ProcessIRExactMigration.ps1') -Command $Command -RepoRoot $repo 2>&1|Out-String).Trim();if($LASTEXITCODE-ne0){throw "[mir4-processir-exact-migration-cli] $Command $output"};return $output|ConvertFrom-Json -Depth 100}
$generateResult=Invoke-MIR4ProcessIRExactMigrationCommandProbeV1 generate;$checkResult=Invoke-MIR4ProcessIRExactMigrationCommandProbeV1 check;$showResult=Invoke-MIR4ProcessIRExactMigrationCommandProbeV1 show
Assert-MIR4ProcessIRExactMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $generateResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-and(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $showResult)) 'mir4-processir-exact-migration-cli-parity'
$facadeOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 processir-exact-migration check 2>&1|Out-String).Trim()
Assert-MIR4ProcessIRExactMigrationV1 ($LASTEXITCODE-eq0-and(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 ($facadeOutput|ConvertFrom-Json -Depth 100))) 'mir4-processir-exact-migration-facade-parity'

$canonicalOutput='build/mir4/test-processir-exact-canonical';$compatibilityOutput='build/mir4/test-processir-exact-compatibility'
& (Join-Path $repo 'tools/mir/cli/Export-MIR4ProcessIRSynthesisRecords.ps1') -RepoRoot $repo -OutputRoot $canonicalOutput|Out-Null
& (Join-Path $repo 'tools/commands/mir4/Export-MIR4ProcessIRSynthesisRecords.ps1') -RepoRoot $repo -OutputRoot $compatibilityOutput|Out-Null
foreach($name in @('MIR4_PROCESSIR_PARITY_RESULT.json','MIR4_EFFECT_CHANNEL_REGISTRY.json','MIR4_SYNTHESIS_MATURITY_MATRIX.json')){$canonicalBytes=[IO.File]::ReadAllBytes((Join-Path $repo "$canonicalOutput/$name"));$compatibilityBytes=[IO.File]::ReadAllBytes((Join-Path $repo "$compatibilityOutput/$name"));Assert-MIR4ProcessIRExactMigrationV1 ([Linq.Enumerable]::SequenceEqual([byte[]]$canonicalBytes,[byte[]]$compatibilityBytes)) 'mir4-processir-exact-migration-export-parity' $name}
$canonicalExact=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Export-MIR4ExactProcessIRRecords.ps1') -RepoRoot $repo -ReferenceRoot 'sdk/preview/mir4/reference/t12' -Check 2>&1|Out-String).Trim()
$compatibilityExact=(& pwsh -NoProfile -File (Join-Path $repo 'tools/commands/mir4/Export-MIR4ExactProcessIRRecords.ps1') -RepoRoot $repo -ReferenceRoot 'sdk/preview/mir4/reference/t12' -Check 2>&1|Out-String).Trim()
Assert-MIR4ProcessIRExactMigrationV1 ($LASTEXITCODE-eq0-and$canonicalExact-ceq$compatibilityExact) 'mir4-processir-exact-migration-exact-check-parity'
foreach($path in $packageHashes.Keys){Assert-MIR4ProcessIRExactMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $path) -Algorithm SHA256).Hash-ceq[string]$packageHashes[$path]) 'mir4-processir-exact-migration-player-authority-mutation' $path}
Assert-MIR4ProcessIRExactMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-processir-exact-migration-package-source-mutation'
[pscustomobject][ordered]@{status='accepted';migration_id=[string]$receipt.migration_id;canonical_applications=@('tools/mir/application/processir/ProcessIR.ps1','tools/mir/application/processir/ExactProcessIR.ps1');compatibility_entrypoints=@($authority.compatibility_entrypoints.path);predecessor_receipt_sha256=$script:MIR4ProcessIRExactPredecessorReceiptSha256;receipt_digest=[string]$receipt.digest;package_source_sha256=[string]$receipt.package_source_sha256;package_visible_delta=@();custody_blocker='BLOCKED-EXACT-ARCHIVE-CUSTODY-F200-K2SO';release_transition_authority=$false}
