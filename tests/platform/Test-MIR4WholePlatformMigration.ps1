param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/targets/TargetKeyMigration.ps1')
. (Join-Path $repo 'tools/mir/application/platform/WholePlatformMigration.ps1')

function Assert-MIR4WholePlatformMigrationV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if (-not $Condition) {
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " $Detail" }
    throw "[$Code]$suffix"
  }
}

$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$predecessor = Invoke-MIR4TargetKeyMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4WholePlatformMigrationV1 ([string]$predecessor.migration_id -ceq 'MIR4-TARGET-KEY-TOOLING-V1') 'mir4-whole-platform-migration-predecessor-id'
Assert-MIR4WholePlatformMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4WholePlatformPredecessorReceiptPath) -Algorithm SHA256).Hash -ceq $script:MIR4WholePlatformPredecessorReceiptSha256) 'mir4-whole-platform-migration-predecessor-immutable'
try { Invoke-MIR4TargetKeyMigrationProjectionV1 -RepoRoot $repo | Out-Null; throw '[mir4-whole-platform-migration-predecessor-write-enabled]' }
catch { if (-not $_.Exception.Message.StartsWith('[mir4-target-key-migration-receipt-immutable]')) { throw } }

$authority = Get-MIR4WholePlatformMigrationAuthorityV1 -RepoRoot $repo
$proof = Get-MIR4WholePlatformMigrationProofPolicyV1 -RepoRoot $repo
$receipt = Invoke-MIR4WholePlatformMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4WholePlatformMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4WholePlatformMigrationReceiptPath) -Algorithm SHA256).Hash -ceq $script:MIR4WholePlatformMigrationReceiptSha256) 'mir4-whole-platform-migration-receipt-immutable'
try { Invoke-MIR4WholePlatformMigrationProjectionV1 -RepoRoot $repo | Out-Null; throw '[mir4-whole-platform-migration-write-enabled]' }
catch { if (-not $_.Exception.Message.StartsWith('[mir4-whole-platform-migration-receipt-immutable]')) { throw } }
$inventory = Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4WholePlatformMigrationV1 ([int]$inventory.summary.unknown -eq 0) 'mir4-whole-platform-migration-inventory-unknown'
Assert-MIR4WholePlatformMigrationV1 (-not [bool]$inventory.deletion_authorized) 'mir4-whole-platform-migration-deletion-authority'
Assert-MIR4WholePlatformMigrationV1 (@($authority.writers).Count -eq 1) 'mir4-whole-platform-migration-writer-count'
Assert-MIR4WholePlatformMigrationV1 ([string]$proof.test_id -ceq 'static.mir4-whole-platform-migration-v1') 'mir4-whole-platform-migration-proof-test-id'
Assert-MIR4WholePlatformMigrationV1 (Test-MIR4WholePlatformCompatibilityForwardersV1 -RepoRoot $repo) 'mir4-whole-platform-migration-forwarders'
Assert-MIR4WholePlatformMigrationV1 (Test-MIR4WholePlatformDeclaredConsumersV1 -RepoRoot $repo) 'mir4-whole-platform-migration-consumers'

$engineText = [IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1'))
Assert-MIR4WholePlatformMigrationV1 ($engineText -match 'function Test-MIR4ImmutableMigrationReceiptV1' -and $engineText -match 'function New-MIR4AppendOnlyAuthorityMigrationReceiptV1') 'mir4-whole-platform-migration-shared-engine'

$assuranceConfig = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$migrationClass = @($assuranceConfig.classes | Where-Object { [string]$_.id -ceq 'repository-migration' })
Assert-MIR4WholePlatformMigrationV1 ($migrationClass.Count -eq 1) 'mir4-whole-platform-migration-assurance-class'
$migrationPaths = @($authority.path_map | ForEach-Object { [string]$_.final_path }) + @($authority.compatibility_entrypoints | ForEach-Object { [string]$_.path })
foreach ($path in @($migrationPaths | Sort-Object -Unique)) {
  $matches = @($migrationClass[0].patterns | Where-Object { $path -match [string]$_ })
  Assert-MIR4WholePlatformMigrationV1 ($matches.Count -gt 0) 'mir4-whole-platform-migration-assurance-path' $path
}
Assert-MIR4WholePlatformMigrationV1 (@($migrationClass[0].tests) -contains [string]$proof.test_id) 'mir4-whole-platform-migration-assurance-test'

$catalog = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
$functionalRows = @($catalog.tests | Where-Object { [string]$_.id -ceq 'static.mir4-whole-platform' })
$migrationRows = @($catalog.tests | Where-Object { [string]$_.id -ceq [string]$proof.test_id })
Assert-MIR4WholePlatformMigrationV1 ($functionalRows.Count -eq 1 -and [string]$functionalRows[0].command -ceq './tests/platform/Test-MIR4WholePlatform.ps1') 'mir4-whole-platform-migration-functional-test-registration'
Assert-MIR4WholePlatformMigrationV1 ($migrationRows.Count -eq 1 -and [string]$migrationRows[0].command -ceq './tests/platform/Test-MIR4WholePlatformMigration.ps1') 'mir4-whole-platform-migration-test-registration'

$packageFiles = @(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach ($path in @($migrationPaths | Sort-Object -Unique)) {
  Assert-MIR4WholePlatformMigrationV1 ($path -notin $packageFiles) 'mir4-whole-platform-migration-package-visible' $path
}
Assert-MIR4WholePlatformMigrationV1 ($packageBefore -ceq [string]$authority.package_source_sha256) 'mir4-whole-platform-migration-package-fingerprint-authority'
Assert-MIR4WholePlatformMigrationV1 ([string]$receipt.package_source_sha256 -ceq $packageBefore) 'mir4-whole-platform-migration-package-fingerprint-receipt'
Assert-MIR4WholePlatformMigrationV1 (@($receipt.package_visible_delta).Count -eq 0) 'mir4-whole-platform-migration-package-delta'

$prior = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration
Assert-MIR4WholePlatformMigrationV1 ([string]$receipt.predecessor_receipt.path -ceq [string]$prior.prior_receipt_path) 'mir4-whole-platform-migration-predecessor-path'
Assert-MIR4WholePlatformMigrationV1 ([string]$receipt.predecessor_receipt.sha256 -ceq [string]$prior.prior_receipt_sha256) 'mir4-whole-platform-migration-predecessor-sha256'
foreach ($binding in @($receipt.evolved_bindings)) {
  $path = [string]$binding.path
  Assert-MIR4WholePlatformMigrationV1 ($prior.authority_hashes.ContainsKey($path)) 'mir4-whole-platform-migration-evolved-prior-missing' $path
  Assert-MIR4WholePlatformMigrationV1 ([string]$binding.previous_sha256 -ceq [string]$prior.authority_hashes[$path]) 'mir4-whole-platform-migration-evolved-prior-sha256' $path
  Assert-MIR4WholePlatformMigrationV1 (-not [bool]$binding.package_visible -and -not [bool]$binding.release_authority) 'mir4-whole-platform-migration-evolved-firewall' $path
}
Assert-MIR4WholePlatformMigrationV1 (@($receipt.current_authorities.path | Sort-Object -Unique).Count -eq @($receipt.current_authorities).Count) 'mir4-whole-platform-migration-current-authority-duplicate'
foreach ($binding in @($receipt.current_authorities)) {
  Assert-MIR4WholePlatformMigrationV1 ([string]$binding.sha256 -cmatch '^[A-F0-9]{64}$') 'mir4-whole-platform-migration-current-authority-shape' ([string]$binding.path)
}
foreach ($component in @($receipt.components)) {
  Assert-MIR4WholePlatformMigrationV1 ([string]$component.hash_mode -ceq 'canonical-text-v1') 'mir4-whole-platform-migration-component-mode' ([string]$component.path)
  Assert-MIR4WholePlatformMigrationV1 ([string]$component.sha256 -cmatch '^[A-F0-9]{64}$') 'mir4-whole-platform-migration-component-shape' ([string]$component.path)
}
$digest = Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:whole-platform-migration-receipt:1' -OmitTopLevelDigest
Assert-MIR4WholePlatformMigrationV1 ([string]$receipt.digest -ceq $digest) 'mir4-whole-platform-migration-receipt-digest'
foreach ($field in @('transition_gate','release_transition_authority')) {
  Assert-MIR4WholePlatformMigrationV1 (@($receipt.$field.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-whole-platform-migration-release-firewall' $field
}
Assert-MIR4WholePlatformMigrationV1 ([string]$receipt.sunset.state -ceq 'deferred-compatibility-readers-retained') 'mir4-whole-platform-migration-sunset'

Test-MIR4PreFreezeAuthorities -RepoRoot $repo | Out-Null
$latest = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration
Assert-MIR4WholePlatformMigrationV1 ([string]$latest.prior_receipt_path -ceq 'releases/migrations/MIR4-Target-Compiler-Tooling-MigrationV1.json') 'mir4-whole-platform-migration-prefreeze-chain'

function Invoke-MIR4WholePlatformMigrationCommandProbeV1 {
  param([Parameter(Mandatory)][ValidateSet('check','show')][string]$Command)
  $output = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4WholePlatformMigration.ps1') -Command $Command -RepoRoot $repo 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) { throw "[mir4-whole-platform-migration-cli] $Command $output" }
  return $output | ConvertFrom-Json -Depth 100
}
$checkResult = Invoke-MIR4WholePlatformMigrationCommandProbeV1 -Command check
$showResult = Invoke-MIR4WholePlatformMigrationCommandProbeV1 -Command show
Assert-MIR4WholePlatformMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 -Value $checkResult) -ceq (ConvertTo-MIR4CanonicalJsonV1 -Value $showResult)) 'mir4-whole-platform-migration-cli-check-show-parity'
$generateOutput = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4WholePlatformMigration.ps1') -Command generate -RepoRoot $repo 2>&1 | Out-String).Trim()
Assert-MIR4WholePlatformMigrationV1 ($LASTEXITCODE -ne 0 -and $generateOutput -match 'Cannot validate argument on parameter') 'mir4-whole-platform-migration-cli-generate-disabled'
$facadeOutput = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 whole-platform-migration check 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "[mir4-whole-platform-migration-facade] $facadeOutput" }
$facadeResult = $facadeOutput | ConvertFrom-Json -Depth 100
Assert-MIR4WholePlatformMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 -Value $checkResult) -ceq (ConvertTo-MIR4CanonicalJsonV1 -Value $facadeResult)) 'mir4-whole-platform-migration-facade-parity'
Assert-MIR4WholePlatformMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-whole-platform-migration-package-source-mutation'

[pscustomobject][ordered]@{
  status='accepted-immutable-predecessor'
  migration_id=[string]$receipt.migration_id
  canonical_application='tools/mir/application/platform/WholePlatform.ps1'
  canonical_test='tests/platform/Test-MIR4WholePlatform.ps1'
  compatibility_entrypoints=@($authority.compatibility_entrypoints | ForEach-Object { [string]$_.path })
  predecessor_receipt_sha256=$script:MIR4WholePlatformPredecessorReceiptSha256
  receipt_sha256=$script:MIR4WholePlatformMigrationReceiptSha256
  receipt_digest=[string]$receipt.digest
  package_source_sha256=[string]$receipt.package_source_sha256
  package_visible_delta=@($receipt.package_visible_delta)
  release_transition_authority=$false
}
