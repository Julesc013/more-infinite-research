param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/technology/TechnologyAcceptanceMigration.ps1')
. (Join-Path $repo 'tools/mir/application/targets/TargetCompilerMigration.ps1')

function Assert-MIR4TargetCompilerMigrationV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$predecessor=Invoke-MIR4TechnologyAcceptanceMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4TargetCompilerMigrationV1 ([string]$predecessor.migration_id-ceq'MIR4-TECHNOLOGY-ACCEPTANCE-TOOLING-V1') 'mir4-target-compiler-migration-predecessor-id'
Assert-MIR4TargetCompilerMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4TargetCompilerPredecessorReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4TargetCompilerPredecessorReceiptSha256) 'mir4-target-compiler-migration-predecessor-immutable'
try{Invoke-MIR4TechnologyAcceptanceMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-target-compiler-migration-predecessor-write-enabled]'}
catch{if(-not$_.Exception.Message.StartsWith('[mir4-technology-acceptance-migration-receipt-immutable]')){throw}}

$authority=Get-MIR4TargetCompilerMigrationAuthorityV1 -RepoRoot $repo
$proof=Get-MIR4TargetCompilerMigrationProofPolicyV1 -RepoRoot $repo
$receipt=Invoke-MIR4TargetCompilerMigrationProjectionV1 -RepoRoot $repo -Check
$inventory=Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4TargetCompilerMigrationV1 ([int]$inventory.summary.unknown-eq0) 'mir4-target-compiler-migration-inventory-unknown'
Assert-MIR4TargetCompilerMigrationV1 (-not[bool]$inventory.deletion_authorized) 'mir4-target-compiler-migration-deletion-authority'
Assert-MIR4TargetCompilerMigrationV1 (@($authority.writers).Count-eq1) 'mir4-target-compiler-migration-writer-count'
Assert-MIR4TargetCompilerMigrationV1 ([string]$proof.test_id-ceq'static.mir4-target-compiler-migration-v1') 'mir4-target-compiler-migration-proof-test-id'
Assert-MIR4TargetCompilerMigrationV1 (Test-MIR4TargetCompilerCompatibilityForwarderV1 -RepoRoot $repo) 'mir4-target-compiler-migration-forwarder'
Assert-MIR4TargetCompilerMigrationV1 (Test-MIR4TargetCompilerDeclaredConsumersV1 -RepoRoot $repo) 'mir4-target-compiler-migration-consumers'
Assert-MIR4TargetCompilerMigrationV1 ([string](Test-MIR4TargetCompilerFunctionalParityV1 -RepoRoot $repo).digest-ceq$script:MIR4TargetCompilerParityDigestV1) 'mir4-target-compiler-migration-functional-parity'

$engineText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1'))
Assert-MIR4TargetCompilerMigrationV1 ($engineText-match'function Test-MIR4ImmutableMigrationReceiptV1'-and$engineText-match'function New-MIR4AppendOnlyAuthorityMigrationReceiptV1') 'mir4-target-compiler-migration-shared-engine'
$assurance=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$migrationClass=@($assurance.classes|Where-Object{[string]$_.id-ceq'repository-migration'})
Assert-MIR4TargetCompilerMigrationV1 ($migrationClass.Count-eq1-and@($migrationClass[0].tests)-contains[string]$proof.test_id) 'mir4-target-compiler-migration-assurance-registration'
$catalog=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
Assert-MIR4TargetCompilerMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq'static.mir4-target-compiler-v1'-and[string]$_.command-ceq'./tests/targets/Test-MIR4TargetCompiler.ps1'}).Count-eq1) 'mir4-target-compiler-migration-functional-registration'
Assert-MIR4TargetCompilerMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq[string]$proof.test_id-and[string]$_.command-ceq'./tests/targets/Test-MIR4TargetCompilerMigration.ps1'}).Count-eq1) 'mir4-target-compiler-migration-test-registration'

$migrationPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path})+@($authority.compatibility_entrypoints|ForEach-Object{[string]$_.path})
$packageFiles=@(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach($item in @($migrationPaths|Sort-Object -Unique)){
  Assert-MIR4TargetCompilerMigrationV1 (@($migrationClass[0].patterns|Where-Object{$item-match[string]$_}).Count-gt0) 'mir4-target-compiler-migration-assurance-path' $item
  Assert-MIR4TargetCompilerMigrationV1 ($item-notin$packageFiles) 'mir4-target-compiler-migration-package-visible' $item
}
Assert-MIR4TargetCompilerMigrationV1 ($packageBefore-ceq[string]$authority.package_source_sha256-and[string]$receipt.package_source_sha256-ceq$packageBefore-and@($receipt.package_visible_delta).Count-eq0) 'mir4-target-compiler-migration-package-firewall'

$prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration
Assert-MIR4TargetCompilerMigrationV1 ([string]$receipt.predecessor_receipt.path-ceq[string]$prior.prior_receipt_path-and[string]$receipt.predecessor_receipt.sha256-ceq[string]$prior.prior_receipt_sha256) 'mir4-target-compiler-migration-predecessor-chain'
foreach($binding in @($receipt.evolved_bindings)){
  $item=[string]$binding.path
  Assert-MIR4TargetCompilerMigrationV1 ($prior.authority_hashes.ContainsKey($item)) 'mir4-target-compiler-migration-evolved-prior-missing' $item
  Assert-MIR4TargetCompilerMigrationV1 ([string]$binding.previous_sha256-ceq[string]$prior.authority_hashes[$item]) 'mir4-target-compiler-migration-evolved-prior-sha256' $item
  Assert-MIR4TargetCompilerMigrationV1 ([string]$binding.current_sha256-ceq(Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $item) -Mode ([string]$binding.hash_mode))) 'mir4-target-compiler-migration-evolved-current-sha256' $item
  Assert-MIR4TargetCompilerMigrationV1 (-not[bool]$binding.package_visible-and-not[bool]$binding.release_authority) 'mir4-target-compiler-migration-evolved-firewall' $item
}
Assert-MIR4TargetCompilerMigrationV1 (@($receipt.current_authorities.path|Sort-Object -Unique).Count-eq@($receipt.current_authorities).Count) 'mir4-target-compiler-migration-current-authority-duplicate'
foreach($binding in @($receipt.current_authorities)){
  $actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$binding.path)) -Mode ([string]$binding.hash_mode)
  Assert-MIR4TargetCompilerMigrationV1 ([string]$binding.sha256-ceq$actual) 'mir4-target-compiler-migration-current-authority' ([string]$binding.path)
}
foreach($component in @($receipt.components)){
  Assert-MIR4TargetCompilerMigrationV1 ([string]$component.hash_mode-ceq'canonical-text-v1') 'mir4-target-compiler-migration-component-mode' ([string]$component.path)
  $actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$component.path)) -Mode 'canonical-text-v1'
  Assert-MIR4TargetCompilerMigrationV1 ([string]$component.sha256-ceq$actual) 'mir4-target-compiler-migration-component-sha256' ([string]$component.path)
}
$digest=Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:target-compiler-migration-receipt:1' -OmitTopLevelDigest
Assert-MIR4TargetCompilerMigrationV1 ([string]$receipt.digest-ceq$digest) 'mir4-target-compiler-migration-receipt-digest'
foreach($field in @('transition_gate','release_transition_authority')){Assert-MIR4TargetCompilerMigrationV1 (@($receipt.$field.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-target-compiler-migration-release-firewall' $field}
Assert-MIR4TargetCompilerMigrationV1 ([string]$receipt.sunset.state-ceq'deferred-compatibility-readers-retained') 'mir4-target-compiler-migration-sunset'

Test-MIR4PreFreezeAuthorities -RepoRoot $repo|Out-Null
$latest=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration
Assert-MIR4TargetCompilerMigrationV1 ([string]$latest.prior_receipt_path-ceq$script:MIR4TargetCompilerMigrationReceiptPath) 'mir4-target-compiler-migration-prefreeze-chain'
$releaseHistoryOutput=(& pwsh -NoProfile -File (Join-Path $repo 'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1') 2>&1|Out-String).Trim()
Assert-MIR4TargetCompilerMigrationV1 ($LASTEXITCODE-eq0-and$releaseHistoryOutput-match'append-only-t14-t17') 'mir4-target-compiler-migration-release-history-successor' $releaseHistoryOutput

function Invoke-MIR4TargetCompilerMigrationCommandProbeV1 {
  param([Parameter(Mandatory)][ValidateSet('generate','check','show')][string]$Command)
  $output=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4TargetCompilerMigration.ps1') -Command $Command -RepoRoot $repo 2>&1|Out-String).Trim()
  if($LASTEXITCODE-ne0){throw "[mir4-target-compiler-migration-cli] $Command $output"}
  return $output|ConvertFrom-Json -Depth 100
}
$generateResult=Invoke-MIR4TargetCompilerMigrationCommandProbeV1 generate
$checkResult=Invoke-MIR4TargetCompilerMigrationCommandProbeV1 check
$showResult=Invoke-MIR4TargetCompilerMigrationCommandProbeV1 show
Assert-MIR4TargetCompilerMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $generateResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-and(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $showResult)) 'mir4-target-compiler-migration-cli-parity'
$facadeOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 target-compiler-migration check 2>&1|Out-String).Trim()
if($LASTEXITCODE-ne0){throw "[mir4-target-compiler-migration-facade] $facadeOutput"}
Assert-MIR4TargetCompilerMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 ($facadeOutput|ConvertFrom-Json -Depth 100))) 'mir4-target-compiler-migration-facade-parity'
Assert-MIR4TargetCompilerMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-target-compiler-migration-package-source-mutation'
Assert-MIR4TargetCompilerMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4TargetCompilerPredecessorReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4TargetCompilerPredecessorReceiptSha256) 'mir4-target-compiler-migration-predecessor-mutated'

[pscustomobject][ordered]@{status='accepted';migration_id=[string]$receipt.migration_id;canonical_application='tools/mir/application/targets/TargetCompiler.ps1';canonical_test='tests/targets/Test-MIR4TargetCompiler.ps1';compatibility_entrypoints=@($authority.compatibility_entrypoints|ForEach-Object{[string]$_.path});predecessor_receipt_sha256=$script:MIR4TargetCompilerPredecessorReceiptSha256;receipt_digest=[string]$receipt.digest;package_source_sha256=[string]$receipt.package_source_sha256;package_visible_delta=@();release_transition_authority=$false}
