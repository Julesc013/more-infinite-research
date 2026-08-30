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
Assert-MIR4TechnologyAcceptanceMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4TechnologyAcceptanceMigrationReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4TechnologyAcceptanceMigrationReceiptSha256) 'mir4-technology-acceptance-migration-receipt-immutable'
try{Invoke-MIR4TechnologyAcceptanceMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-technology-acceptance-migration-write-enabled]'}
catch{if(-not$_.Exception.Message.StartsWith('[mir4-technology-acceptance-migration-receipt-immutable]')){throw}}

$inventory=Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4TechnologyAcceptanceMigrationV1 ([int]$inventory.summary.unknown-eq0) 'mir4-technology-acceptance-migration-inventory-unknown'
Assert-MIR4TechnologyAcceptanceMigrationV1 (-not[bool]$inventory.deletion_authorized) 'mir4-technology-acceptance-migration-deletion-authority'
Assert-MIR4TechnologyAcceptanceMigrationV1 (@($authority.writers).Count-eq1) 'mir4-technology-acceptance-migration-writer-count'
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$proof.test_id-ceq'static.mir4-technology-acceptance-migration-v1') 'mir4-technology-acceptance-migration-proof-test-id'
Assert-MIR4TechnologyAcceptanceMigrationV1 (Test-MIR4TechnologyAcceptanceCompatibilityForwarderV1 -RepoRoot $repo) 'mir4-technology-acceptance-migration-forwarder'
Assert-MIR4TechnologyAcceptanceMigrationV1 (Test-MIR4TechnologyAcceptanceDeclaredConsumersV1 -RepoRoot $repo) 'mir4-technology-acceptance-migration-consumers'
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string](Test-MIR4TechnologyAcceptanceFunctionalParityV1 -RepoRoot $repo).digest-ceq$script:MIR4TechnologyAcceptanceParityDigestV1) 'mir4-technology-acceptance-migration-functional-parity'

$assurance=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$migrationClass=@($assurance.classes|Where-Object{[string]$_.id-ceq'repository-migration'})
Assert-MIR4TechnologyAcceptanceMigrationV1 ($migrationClass.Count-eq1-and@($migrationClass[0].tests)-contains[string]$proof.test_id) 'mir4-technology-acceptance-migration-assurance-registration'
$catalog=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
Assert-MIR4TechnologyAcceptanceMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq[string]$proof.test_id-and[string]$_.command-ceq'./tests/technology/Test-MIR4TechnologyAcceptanceMigration.ps1'}).Count-eq1) 'mir4-technology-acceptance-migration-test-registration'

$packageFiles=@(Get-MIRPackageSourceFiles -RepoRoot $repo)
$migrationPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path})+@($authority.compatibility_entrypoints|ForEach-Object{[string]$_.path})
foreach($item in @($migrationPaths|Sort-Object -Unique)){Assert-MIR4TechnologyAcceptanceMigrationV1 ($item-notin$packageFiles) 'mir4-technology-acceptance-migration-package-visible' $item}
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$receipt.package_source_sha256-ceq$packageBefore-and@($receipt.package_visible_delta).Count-eq0) 'mir4-technology-acceptance-migration-package-firewall'

$prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$receipt.predecessor_receipt.path-ceq[string]$prior.prior_receipt_path-and[string]$receipt.predecessor_receipt.sha256-ceq[string]$prior.prior_receipt_sha256) 'mir4-technology-acceptance-migration-predecessor-chain'
foreach($binding in @($receipt.evolved_bindings)){
  Assert-MIR4TechnologyAcceptanceMigrationV1 ($prior.authority_hashes.ContainsKey([string]$binding.path)) 'mir4-technology-acceptance-migration-evolved-prior-missing' ([string]$binding.path)
  Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$binding.previous_sha256-ceq[string]$prior.authority_hashes[[string]$binding.path]) 'mir4-technology-acceptance-migration-evolved-prior-sha256' ([string]$binding.path)
  Assert-MIR4TechnologyAcceptanceMigrationV1 (-not[bool]$binding.package_visible-and-not[bool]$binding.release_authority) 'mir4-technology-acceptance-migration-evolved-firewall' ([string]$binding.path)
}
foreach($binding in @($receipt.current_authorities)){Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$binding.sha256-cmatch'^[A-F0-9]{64}$') 'mir4-technology-acceptance-migration-current-authority-shape' ([string]$binding.path)}
foreach($component in @($receipt.components)){Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$component.hash_mode-ceq'canonical-text-v1'-and[string]$component.sha256-cmatch'^[A-F0-9]{64}$') 'mir4-technology-acceptance-migration-component-shape' ([string]$component.path)}
$digest=Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:technology-acceptance-migration-receipt:1' -OmitTopLevelDigest
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$receipt.digest-ceq$digest) 'mir4-technology-acceptance-migration-receipt-digest'
foreach($field in @('transition_gate','release_transition_authority')){Assert-MIR4TechnologyAcceptanceMigrationV1 (@($receipt.$field.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-technology-acceptance-migration-release-firewall' $field}

Test-MIR4PreFreezeAuthorities -RepoRoot $repo|Out-Null
$latest=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration
Assert-MIR4TechnologyAcceptanceMigrationV1 ([string]$latest.prior_receipt_path-ceq'releases/migrations/MIR4-Target-Compiler-Tooling-MigrationV1.json') 'mir4-technology-acceptance-migration-prefreeze-chain'

function Invoke-MIR4TechnologyAcceptanceMigrationCommandProbeV1 {
  param([Parameter(Mandatory)][ValidateSet('check','show')][string]$Command)
  $output=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4TechnologyAcceptanceMigration.ps1') -Command $Command -RepoRoot $repo 2>&1|Out-String).Trim()
  if($LASTEXITCODE-ne0){throw "[mir4-technology-acceptance-migration-cli] $Command $output"}
  return $output|ConvertFrom-Json -Depth 100
}
$checkResult=Invoke-MIR4TechnologyAcceptanceMigrationCommandProbeV1 check
$showResult=Invoke-MIR4TechnologyAcceptanceMigrationCommandProbeV1 show
Assert-MIR4TechnologyAcceptanceMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $showResult)) 'mir4-technology-acceptance-migration-cli-check-show-parity'
$generateOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4TechnologyAcceptanceMigration.ps1') -Command generate -RepoRoot $repo 2>&1|Out-String).Trim()
Assert-MIR4TechnologyAcceptanceMigrationV1 ($LASTEXITCODE-ne0-and$generateOutput-match'Cannot validate argument on parameter') 'mir4-technology-acceptance-migration-cli-generate-disabled'
$facadeOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 technology-acceptance-migration check 2>&1|Out-String).Trim()
if($LASTEXITCODE-ne0){throw "[mir4-technology-acceptance-migration-facade] $facadeOutput"}
Assert-MIR4TechnologyAcceptanceMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 ($facadeOutput|ConvertFrom-Json -Depth 100))) 'mir4-technology-acceptance-migration-facade-parity'
Assert-MIR4TechnologyAcceptanceMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-technology-acceptance-migration-package-source-mutation'

[pscustomobject][ordered]@{status='accepted-immutable-predecessor';migration_id=[string]$receipt.migration_id;canonical_application='tools/mir/application/technology/TechnologyAcceptance.ps1';canonical_test='tests/technology/Test-MIR4TechnologyAcceptance.ps1';receipt_sha256=$script:MIR4TechnologyAcceptanceMigrationReceiptSha256;receipt_digest=[string]$receipt.digest;package_source_sha256=[string]$receipt.package_source_sha256;package_visible_delta=@();release_transition_authority=$false}
