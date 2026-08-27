param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/targets/TargetCompilerMigration.ps1')
. (Join-Path $repo 'tools/mir/application/compiler/SemanticCompilerPolicyMigration.ps1')

function Assert-MIR4SemanticCompilerMigrationV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$compatibilityBefore=(Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash
$predecessor=Invoke-MIR4TargetCompilerMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4SemanticCompilerMigrationV1 ([string]$predecessor.migration_id-ceq'MIR4-TARGET-COMPILER-TOOLING-V1') 'mir4-semantic-compiler-policy-migration-predecessor-id'
Assert-MIR4SemanticCompilerMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4SemanticCompilerPolicyPredecessorReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4SemanticCompilerPolicyPredecessorReceiptSha256) 'mir4-semantic-compiler-policy-migration-predecessor-immutable'
try{Invoke-MIR4TargetCompilerMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-semantic-compiler-policy-migration-predecessor-write-enabled]'}
catch{if(-not$_.Exception.Message.StartsWith('[mir4-target-compiler-migration-receipt-immutable]')){throw}}

$authority=Get-MIR4SemanticCompilerPolicyMigrationAuthorityV1 -RepoRoot $repo
$proof=Get-MIR4SemanticCompilerPolicyMigrationProofPolicyV1 -RepoRoot $repo
$receipt=Invoke-MIR4SemanticCompilerPolicyMigrationProjectionV1 -RepoRoot $repo -Check
$inventory=Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4SemanticCompilerMigrationV1 ([int]$inventory.summary.unknown-eq0) 'mir4-semantic-compiler-policy-migration-inventory-unknown'
Assert-MIR4SemanticCompilerMigrationV1 (-not[bool]$inventory.deletion_authorized) 'mir4-semantic-compiler-policy-migration-deletion-authority'
Assert-MIR4SemanticCompilerMigrationV1 (@($authority.writers).Count-eq1) 'mir4-semantic-compiler-policy-migration-writer-count'
Assert-MIR4SemanticCompilerMigrationV1 ([string]$proof.test_id-ceq'static.mir4-semantic-compiler-policy-migration-v1') 'mir4-semantic-compiler-policy-migration-proof-test-id'
Assert-MIR4SemanticCompilerMigrationV1 (Test-MIR4SemanticCompilerPolicyCompatibilityForwardersV1 -RepoRoot $repo) 'mir4-semantic-compiler-policy-migration-forwarders'
Assert-MIR4SemanticCompilerMigrationV1 (Test-MIR4SemanticCompilerPolicyDeclaredConsumersV1 -RepoRoot $repo) 'mir4-semantic-compiler-policy-migration-consumers'
Assert-MIR4SemanticCompilerMigrationV1 ([string](Test-MIR4SemanticCompilerPolicyFunctionalParityV1 -RepoRoot $repo).digest-ceq$script:MIR4SemanticCompilerPolicyParityDigestV1) 'mir4-semantic-compiler-policy-migration-functional-parity'

$engineText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1'))
Assert-MIR4SemanticCompilerMigrationV1 ($engineText-match'function Test-MIR4ImmutableMigrationReceiptV1'-and$engineText-match'function New-MIR4AppendOnlyAuthorityMigrationReceiptV1') 'mir4-semantic-compiler-policy-migration-shared-engine'
$assurance=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$migrationClass=@($assurance.classes|Where-Object{[string]$_.id-ceq'repository-migration'})
Assert-MIR4SemanticCompilerMigrationV1 ($migrationClass.Count-eq1-and@($migrationClass[0].tests)-contains[string]$proof.test_id) 'mir4-semantic-compiler-policy-migration-assurance-registration'
$catalog=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
Assert-MIR4SemanticCompilerMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq'static.mir4-semantic-compiler-v1'-and[string]$_.command-ceq'./tests/compiler/Test-MIR4SemanticCompiler.ps1'}).Count-eq1) 'mir4-semantic-compiler-policy-migration-functional-registration'
Assert-MIR4SemanticCompilerMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq[string]$proof.test_id-and[string]$_.command-ceq'./tests/compiler/Test-MIR4SemanticCompilerMigration.ps1'}).Count-eq1) 'mir4-semantic-compiler-policy-migration-test-registration'

$migrationPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path})+@($authority.compatibility_entrypoints|ForEach-Object{[string]$_.path})
$packageFiles=@(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach($item in @($migrationPaths|Sort-Object -Unique)){
  Assert-MIR4SemanticCompilerMigrationV1 (@($migrationClass[0].patterns|Where-Object{$item-match[string]$_}).Count-gt0) 'mir4-semantic-compiler-policy-migration-assurance-path' $item
  Assert-MIR4SemanticCompilerMigrationV1 ($item-notin$packageFiles) 'mir4-semantic-compiler-policy-migration-package-visible' $item
}
Assert-MIR4SemanticCompilerMigrationV1 ($packageBefore-ceq[string]$authority.package_source_sha256-and[string]$receipt.package_source_sha256-ceq$packageBefore-and@($receipt.package_visible_delta).Count-eq0) 'mir4-semantic-compiler-policy-migration-package-firewall'
Assert-MIR4SemanticCompilerMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-ceq$compatibilityBefore) 'mir4-semantic-compiler-policy-migration-compatibility-policy'

$prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration
Assert-MIR4SemanticCompilerMigrationV1 ([string]$receipt.predecessor_receipt.path-ceq[string]$prior.prior_receipt_path-and[string]$receipt.predecessor_receipt.sha256-ceq[string]$prior.prior_receipt_sha256) 'mir4-semantic-compiler-policy-migration-predecessor-chain'
foreach($binding in @($receipt.evolved_bindings)){
  $item=[string]$binding.path
  Assert-MIR4SemanticCompilerMigrationV1 ($prior.authority_hashes.ContainsKey($item)) 'mir4-semantic-compiler-policy-migration-evolved-prior-missing' $item
  Assert-MIR4SemanticCompilerMigrationV1 ([string]$binding.previous_sha256-ceq[string]$prior.authority_hashes[$item]) 'mir4-semantic-compiler-policy-migration-evolved-prior-sha256' $item
  Assert-MIR4SemanticCompilerMigrationV1 ([string]$binding.current_sha256-ceq(Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $item) -Mode ([string]$binding.hash_mode))) 'mir4-semantic-compiler-policy-migration-evolved-current-sha256' $item
  Assert-MIR4SemanticCompilerMigrationV1 (-not[bool]$binding.package_visible-and-not[bool]$binding.release_authority) 'mir4-semantic-compiler-policy-migration-evolved-firewall' $item
}
Assert-MIR4SemanticCompilerMigrationV1 (@($receipt.current_authorities.path|Sort-Object -Unique).Count-eq@($receipt.current_authorities).Count) 'mir4-semantic-compiler-policy-migration-current-authority-duplicate'
foreach($binding in @($receipt.current_authorities)){
  $actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$binding.path)) -Mode ([string]$binding.hash_mode)
  Assert-MIR4SemanticCompilerMigrationV1 ([string]$binding.sha256-ceq$actual) 'mir4-semantic-compiler-policy-migration-current-authority' ([string]$binding.path)
}
foreach($component in @($receipt.components)){
  Assert-MIR4SemanticCompilerMigrationV1 ([string]$component.hash_mode-ceq'canonical-text-v1') 'mir4-semantic-compiler-policy-migration-component-mode' ([string]$component.path)
  $actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$component.path)) -Mode 'canonical-text-v1'
  Assert-MIR4SemanticCompilerMigrationV1 ([string]$component.sha256-ceq$actual) 'mir4-semantic-compiler-policy-migration-component-sha256' ([string]$component.path)
}
$digest=Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:semantic-compiler-policy-migration-receipt:1' -OmitTopLevelDigest
Assert-MIR4SemanticCompilerMigrationV1 ([string]$receipt.digest-ceq$digest) 'mir4-semantic-compiler-policy-migration-receipt-digest'
foreach($field in @('transition_gate','release_transition_authority')){Assert-MIR4SemanticCompilerMigrationV1 (@($receipt.$field.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-semantic-compiler-policy-migration-release-firewall' $field}
Assert-MIR4SemanticCompilerMigrationV1 ([string]$receipt.sunset.state-ceq'deferred-compatibility-readers-retained'-and@($receipt.sunset.compatibility_paths).Count-eq5) 'mir4-semantic-compiler-policy-migration-sunset'

Test-MIR4PreFreezeAuthorities -RepoRoot $repo|Out-Null
$latest=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration
Assert-MIR4SemanticCompilerMigrationV1 ([string]$latest.prior_receipt_path-ceq$script:MIR4SemanticCompilerPolicyMigrationReceiptPath) 'mir4-semantic-compiler-policy-migration-prefreeze-chain'
$releaseHistoryOutput=(& pwsh -NoProfile -File (Join-Path $repo 'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1') 2>&1|Out-String).Trim()
Assert-MIR4SemanticCompilerMigrationV1 ($LASTEXITCODE-eq0-and$releaseHistoryOutput-match'append-only-semantic-compiler-policy-successor') 'mir4-semantic-compiler-policy-migration-release-history-successor' $releaseHistoryOutput

function Invoke-MIR4SemanticCompilerPolicyMigrationCommandProbeV1 {
  param([Parameter(Mandatory)][ValidateSet('generate','check','show')][string]$Command)
  $output=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4SemanticCompilerPolicyMigration.ps1') -Command $Command -RepoRoot $repo 2>&1|Out-String).Trim()
  if($LASTEXITCODE-ne0){throw "[mir4-semantic-compiler-policy-migration-cli] $Command $output"}
  return $output|ConvertFrom-Json -Depth 100
}
$generateResult=Invoke-MIR4SemanticCompilerPolicyMigrationCommandProbeV1 generate
$checkResult=Invoke-MIR4SemanticCompilerPolicyMigrationCommandProbeV1 check
$showResult=Invoke-MIR4SemanticCompilerPolicyMigrationCommandProbeV1 show
Assert-MIR4SemanticCompilerMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $generateResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-and(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $showResult)) 'mir4-semantic-compiler-policy-migration-cli-parity'
$facadeOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 semantic-compiler-policy-migration check 2>&1|Out-String).Trim()
if($LASTEXITCODE-ne0){throw "[mir4-semantic-compiler-policy-migration-facade] $facadeOutput"}
Assert-MIR4SemanticCompilerMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 ($facadeOutput|ConvertFrom-Json -Depth 100))) 'mir4-semantic-compiler-policy-migration-facade-parity'
Assert-MIR4SemanticCompilerMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-semantic-compiler-policy-migration-package-source-mutation'
Assert-MIR4SemanticCompilerMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4SemanticCompilerPolicyPredecessorReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4SemanticCompilerPolicyPredecessorReceiptSha256) 'mir4-semantic-compiler-policy-migration-predecessor-mutated'

[pscustomobject][ordered]@{status='accepted';migration_id=[string]$receipt.migration_id;canonical_application='tools/mir/application/compiler/CompilationRun.ps1';canonical_test='tests/compiler/Test-MIR4SemanticCompiler.ps1';compatibility_entrypoints=@($authority.compatibility_entrypoints|ForEach-Object{[string]$_.path});predecessor_receipt_sha256=$script:MIR4SemanticCompilerPolicyPredecessorReceiptSha256;receipt_digest=[string]$receipt.digest;package_source_sha256=[string]$receipt.package_source_sha256;package_visible_delta=@();release_transition_authority=$false}
