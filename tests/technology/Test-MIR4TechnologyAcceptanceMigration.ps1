param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/platform/WholePlatformMigration.ps1')
. (Join-Path $repo 'tools/mir/application/technology/TechnologyAcceptanceMigration.ps1')

function Assert-MIR4TechnologyAcceptanceMigrationV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$predecessor=Invoke-MIR4WholePlatformMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$predecessor.migration_id-ceq'MIR4-WHOLE-PLATFORM-TOOLING-V1') 'mir4-technology-acceptance-migration-predecessor-id'
Assert-MIR4TechnologyAcceptanceMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4TechnologyAcceptancePredecessorReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4TechnologyAcceptancePredecessorReceiptSha256) 'mir4-technology-acceptance-migration-predecessor-immutable'
try{Invoke-MIR4WholePlatformMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-technology-acceptance-migration-predecessor-write-enabled]'}
catch{if(-not$_.Exception.Message.StartsWith('[mir4-whole-platform-migration-receipt-immutable]')){throw}}

$authority=Get-MIR4TechnologyAcceptanceMigrationAuthorityV1 -RepoRoot $repo
$proof=Get-MIR4TechnologyAcceptanceMigrationProofPolicyV1 -RepoRoot $repo
$receipt=Invoke-MIR4TechnologyAcceptanceMigrationProjectionV1 -RepoRoot $repo -Check
$inventory=Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4TechnologyAcceptanceMigrationV1 ([int]$inventory.summary.unknown-eq0) 'mir4-technology-acceptance-migration-inventory-unknown'
Assert-MIR4TechnologyAcceptanceMigrationV1 (-not[bool]$inventory.deletion_authorized) 'mir4-technology-acceptance-migration-deletion-authority'
Assert-MIR4TechnologyAcceptanceMigrationV1 (@($authority.writers).Count-eq1) 'mir4-technology-acceptance-migration-writer-count'
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$proof.test_id-ceq'static.mir4-technology-acceptance-migration-v1') 'mir4-technology-acceptance-migration-proof-test-id'
Assert-MIR4TechnologyAcceptanceMigrationV1 (Test-MIR4TechnologyAcceptanceCompatibilityForwarderV1 -RepoRoot $repo) 'mir4-technology-acceptance-migration-forwarder'
Assert-MIR4TechnologyAcceptanceMigrationV1 (Test-MIR4TechnologyAcceptanceDeclaredConsumersV1 -RepoRoot $repo) 'mir4-technology-acceptance-migration-consumers'
Assert-MIR4TechnologyAcceptanceMigrationV1 (Test-MIR4TargetKeyDeclaredConsumersV1 -RepoRoot $repo) 'mir4-technology-acceptance-migration-target-key-successor-consumer'
$parity=Test-MIR4TechnologyAcceptanceFunctionalParityV1 -RepoRoot $repo
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$parity.digest-ceq$script:MIR4TechnologyAcceptanceParityDigestV1) 'mir4-technology-acceptance-migration-functional-parity'

$engineText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1'))
Assert-MIR4TechnologyAcceptanceMigrationV1 ($engineText-match'function Test-MIR4ImmutableMigrationReceiptV1'-and$engineText-match'function New-MIR4AppendOnlyAuthorityMigrationReceiptV1') 'mir4-technology-acceptance-migration-shared-engine'

$assuranceConfig=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$migrationClass=@($assuranceConfig.classes|Where-Object{[string]$_.id-ceq'repository-migration'})
Assert-MIR4TechnologyAcceptanceMigrationV1 ($migrationClass.Count-eq1) 'mir4-technology-acceptance-migration-assurance-class'
$migrationPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path})+@($authority.compatibility_entrypoints|ForEach-Object{[string]$_.path})
foreach($path in @($migrationPaths|Sort-Object -Unique)){
  $matches=@($migrationClass[0].patterns|Where-Object{$path-match[string]$_})
  Assert-MIR4TechnologyAcceptanceMigrationV1 ($matches.Count-gt0) 'mir4-technology-acceptance-migration-assurance-path' $path
}
Assert-MIR4TechnologyAcceptanceMigrationV1 (@($migrationClass[0].tests)-contains[string]$proof.test_id) 'mir4-technology-acceptance-migration-assurance-test'

$catalog=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
$functionalRows=@($catalog.tests|Where-Object{[string]$_.id-ceq'static.mir4-technology-acceptance-v1'})
$migrationRows=@($catalog.tests|Where-Object{[string]$_.id-ceq[string]$proof.test_id})
Assert-MIR4TechnologyAcceptanceMigrationV1 ($functionalRows.Count-eq1-and[string]$functionalRows[0].command-ceq'./tests/technology/Test-MIR4TechnologyAcceptance.ps1') 'mir4-technology-acceptance-migration-functional-test-registration'
Assert-MIR4TechnologyAcceptanceMigrationV1 ($migrationRows.Count-eq1-and[string]$migrationRows[0].command-ceq'./tests/technology/Test-MIR4TechnologyAcceptanceMigration.ps1') 'mir4-technology-acceptance-migration-test-registration'

$packageFiles=@(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach($path in @($migrationPaths|Sort-Object -Unique)){Assert-MIR4TechnologyAcceptanceMigrationV1 ($path-notin$packageFiles) 'mir4-technology-acceptance-migration-package-visible' $path}
Assert-MIR4TechnologyAcceptanceMigrationV1 ($packageBefore-ceq[string]$authority.package_source_sha256) 'mir4-technology-acceptance-migration-package-fingerprint-authority'
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$receipt.package_source_sha256-ceq$packageBefore) 'mir4-technology-acceptance-migration-package-fingerprint-receipt'
Assert-MIR4TechnologyAcceptanceMigrationV1 (@($receipt.package_visible_delta).Count-eq0) 'mir4-technology-acceptance-migration-package-delta'

$prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$receipt.predecessor_receipt.path-ceq[string]$prior.prior_receipt_path) 'mir4-technology-acceptance-migration-predecessor-path'
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$receipt.predecessor_receipt.sha256-ceq[string]$prior.prior_receipt_sha256) 'mir4-technology-acceptance-migration-predecessor-sha256'
foreach($binding in @($receipt.evolved_bindings)){
  $path=[string]$binding.path
  Assert-MIR4TechnologyAcceptanceMigrationV1 ($prior.authority_hashes.ContainsKey($path)) 'mir4-technology-acceptance-migration-evolved-prior-missing' $path
  Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$binding.previous_sha256-ceq[string]$prior.authority_hashes[$path]) 'mir4-technology-acceptance-migration-evolved-prior-sha256' $path
  $actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $path) -Mode ([string]$binding.hash_mode)
  Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$binding.current_sha256-ceq$actual) 'mir4-technology-acceptance-migration-evolved-current-sha256' $path
  Assert-MIR4TechnologyAcceptanceMigrationV1 (-not[bool]$binding.package_visible-and-not[bool]$binding.release_authority) 'mir4-technology-acceptance-migration-evolved-firewall' $path
}
foreach($binding in @($receipt.current_authorities)){
  $actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$binding.path)) -Mode ([string]$binding.hash_mode)
  Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$binding.sha256-ceq$actual) 'mir4-technology-acceptance-migration-current-authority' ([string]$binding.path)
}
foreach($component in @($receipt.components)){
  Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$component.hash_mode-ceq'canonical-text-v1') 'mir4-technology-acceptance-migration-component-mode' ([string]$component.path)
  $actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$component.path)) -Mode 'canonical-text-v1'
  Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$component.sha256-ceq$actual) 'mir4-technology-acceptance-migration-component-sha256' ([string]$component.path)
}
$digest=Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:technology-acceptance-migration-receipt:1' -OmitTopLevelDigest
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$receipt.digest-ceq$digest) 'mir4-technology-acceptance-migration-receipt-digest'
foreach($field in @('transition_gate','release_transition_authority')){Assert-MIR4TechnologyAcceptanceMigrationV1 (@($receipt.$field.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-technology-acceptance-migration-release-firewall' $field}
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$receipt.sunset.state-ceq'deferred-compatibility-readers-retained') 'mir4-technology-acceptance-migration-sunset'

Test-MIR4PreFreezeAuthorities -RepoRoot $repo|Out-Null
$latest=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$latest.prior_receipt_path-ceq$script:MIR4TechnologyAcceptanceMigrationReceiptPath) 'mir4-technology-acceptance-migration-prefreeze-chain'

$releaseHistoryOutput=(& pwsh -NoProfile -File (Join-Path $repo 'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1') -Index 2>&1|Out-String).Trim()
Assert-MIR4TechnologyAcceptanceMigrationV1 ($LASTEXITCODE-eq0-and$releaseHistoryOutput-match'append-only-t14-t17') 'mir4-technology-acceptance-migration-release-history-successor'

function Invoke-MIR4TechnologyAcceptanceMigrationCommandProbeV1 {
  param([Parameter(Mandatory)][ValidateSet('generate','check','show')][string]$Command)
  $output=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4TechnologyAcceptanceMigration.ps1') -Command $Command -RepoRoot $repo 2>&1|Out-String).Trim()
  if($LASTEXITCODE-ne0){throw "[mir4-technology-acceptance-migration-cli] $Command $output"}
  return $output|ConvertFrom-Json -Depth 100
}
$generateResult=Invoke-MIR4TechnologyAcceptanceMigrationCommandProbeV1 generate
$checkResult=Invoke-MIR4TechnologyAcceptanceMigrationCommandProbeV1 check
$showResult=Invoke-MIR4TechnologyAcceptanceMigrationCommandProbeV1 show
Assert-MIR4TechnologyAcceptanceMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $generateResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $checkResult)) 'mir4-technology-acceptance-migration-cli-generate-check-parity'
Assert-MIR4TechnologyAcceptanceMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $showResult)) 'mir4-technology-acceptance-migration-cli-check-show-parity'
$facadeOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 technology-acceptance-migration check 2>&1|Out-String).Trim()
if($LASTEXITCODE-ne0){throw "[mir4-technology-acceptance-migration-facade] $facadeOutput"}
$facadeResult=$facadeOutput|ConvertFrom-Json -Depth 100
Assert-MIR4TechnologyAcceptanceMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $facadeResult)) 'mir4-technology-acceptance-migration-facade-parity'
Assert-MIR4TechnologyAcceptanceMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-technology-acceptance-migration-package-source-mutation'

[pscustomobject][ordered]@{
  status='passed';migration_id=[string]$receipt.migration_id;canonical_application='tools/mir/application/technology/TechnologyAcceptance.ps1'
  canonical_test='tests/technology/Test-MIR4TechnologyAcceptance.ps1';compatibility_entrypoints=@($authority.compatibility_entrypoints|ForEach-Object{[string]$_.path})
  predecessor_receipt_sha256=$script:MIR4TechnologyAcceptancePredecessorReceiptSha256;parity_digest=[string]$parity.digest;receipt_digest=[string]$receipt.digest
  package_source_sha256=[string]$receipt.package_source_sha256;package_visible_delta=@($receipt.package_visible_delta);release_transition_authority=$false
}
