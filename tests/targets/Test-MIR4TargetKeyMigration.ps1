param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/diagnostics/DiagnosticsMigration.ps1')
. (Join-Path $repo 'tools/mir/application/targets/TargetKeyMigration.ps1')

function Assert-MIR4TargetKeyMigrationV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if (-not $Condition) {
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " $Detail" }
    throw "[$Code]$suffix"
  }
}

$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$predecessor = Invoke-MIR4DiagnosticsMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4TargetKeyMigrationV1 ([string]$predecessor.migration_id -ceq 'MIR4-DIAGNOSTICS-TOOLING-V1') 'mir4-target-key-migration-predecessor-id'
Assert-MIR4TargetKeyMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4TargetKeyPredecessorReceiptPath) -Algorithm SHA256).Hash -ceq $script:MIR4TargetKeyPredecessorReceiptSha256) 'mir4-target-key-migration-predecessor-immutable'
try { Invoke-MIR4DiagnosticsMigrationProjectionV1 -RepoRoot $repo | Out-Null; throw '[mir4-target-key-migration-predecessor-write-enabled]' }
catch { if (-not $_.Exception.Message.StartsWith('[mir4-diagnostics-migration-receipt-immutable]')) { throw } }

$authority = Get-MIR4TargetKeyMigrationAuthorityV1 -RepoRoot $repo
$proof = Get-MIR4TargetKeyMigrationProofPolicyV1 -RepoRoot $repo
$receipt = Invoke-MIR4TargetKeyMigrationProjectionV1 -RepoRoot $repo -Check
$inventory = Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4TargetKeyMigrationV1 ([int]$inventory.summary.unknown -eq 0) 'mir4-target-key-migration-inventory-unknown'
Assert-MIR4TargetKeyMigrationV1 (-not [bool]$inventory.deletion_authorized) 'mir4-target-key-migration-deletion-authority'
Assert-MIR4TargetKeyMigrationV1 (@($authority.writers).Count -eq 1) 'mir4-target-key-migration-writer-count'
Assert-MIR4TargetKeyMigrationV1 ([string]$proof.test_id -ceq 'static.mir4-target-key-migration-v1') 'mir4-target-key-migration-proof-test-id'
Assert-MIR4TargetKeyMigrationV1 (Test-MIR4TargetKeyCompatibilityForwarderV1 -RepoRoot $repo) 'mir4-target-key-migration-forwarder'
Assert-MIR4TargetKeyMigrationV1 (Test-MIR4TargetKeyDeclaredConsumersV1 -RepoRoot $repo) 'mir4-target-key-migration-consumers'
$parity = Test-MIR4TargetKeyFunctionalParityV1 -RepoRoot $repo
Assert-MIR4TargetKeyMigrationV1 ([string]$parity.digest -ceq $script:MIR4TargetKeyParityDigestV1) 'mir4-target-key-migration-functional-parity'

$engineText = [IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1'))
Assert-MIR4TargetKeyMigrationV1 ($engineText -match 'function Test-MIR4ImmutableMigrationReceiptV1' -and $engineText -match 'function New-MIR4AppendOnlyAuthorityMigrationReceiptV1') 'mir4-target-key-migration-shared-engine'

$assuranceConfig = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$migrationClass = @($assuranceConfig.classes | Where-Object { [string]$_.id -ceq 'repository-migration' })
Assert-MIR4TargetKeyMigrationV1 ($migrationClass.Count -eq 1) 'mir4-target-key-migration-assurance-class'
$migrationPaths = @($authority.path_map | ForEach-Object { [string]$_.final_path }) + @($authority.compatibility_entrypoints | ForEach-Object { [string]$_.path })
foreach ($path in @($migrationPaths | Sort-Object -Unique)) {
  $matches = @($migrationClass[0].patterns | Where-Object { $path -match [string]$_ })
  Assert-MIR4TargetKeyMigrationV1 ($matches.Count -gt 0) 'mir4-target-key-migration-assurance-path' $path
}
Assert-MIR4TargetKeyMigrationV1 (@($migrationClass[0].tests) -contains [string]$proof.test_id) 'mir4-target-key-migration-assurance-test'

$catalog = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
$functionalRows = @($catalog.tests | Where-Object { [string]$_.id -ceq 'static.mir4-target-key-v1' })
$migrationRows = @($catalog.tests | Where-Object { [string]$_.id -ceq [string]$proof.test_id })
Assert-MIR4TargetKeyMigrationV1 ($functionalRows.Count -eq 1 -and [string]$functionalRows[0].command -ceq './tests/targets/Test-MIR4TargetKey.ps1') 'mir4-target-key-migration-functional-test-registration'
Assert-MIR4TargetKeyMigrationV1 ($migrationRows.Count -eq 1 -and [string]$migrationRows[0].command -ceq './tests/targets/Test-MIR4TargetKeyMigration.ps1') 'mir4-target-key-migration-test-registration'

$packageFiles = @(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach ($path in @($migrationPaths | Sort-Object -Unique)) {
  Assert-MIR4TargetKeyMigrationV1 ($path -notin $packageFiles) 'mir4-target-key-migration-package-visible' $path
}
Assert-MIR4TargetKeyMigrationV1 ($packageBefore -ceq [string]$authority.package_source_sha256) 'mir4-target-key-migration-package-fingerprint-authority'
Assert-MIR4TargetKeyMigrationV1 ([string]$receipt.package_source_sha256 -ceq $packageBefore) 'mir4-target-key-migration-package-fingerprint-receipt'
Assert-MIR4TargetKeyMigrationV1 (@($receipt.package_visible_delta).Count -eq 0) 'mir4-target-key-migration-package-delta'

$prior = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration
Assert-MIR4TargetKeyMigrationV1 ([string]$receipt.predecessor_receipt.path -ceq [string]$prior.prior_receipt_path) 'mir4-target-key-migration-predecessor-path'
Assert-MIR4TargetKeyMigrationV1 ([string]$receipt.predecessor_receipt.sha256 -ceq [string]$prior.prior_receipt_sha256) 'mir4-target-key-migration-predecessor-sha256'
foreach ($binding in @($receipt.evolved_bindings)) {
  $path = [string]$binding.path
  Assert-MIR4TargetKeyMigrationV1 ($prior.authority_hashes.ContainsKey($path)) 'mir4-target-key-migration-evolved-prior-missing' $path
  Assert-MIR4TargetKeyMigrationV1 ([string]$binding.previous_sha256 -ceq [string]$prior.authority_hashes[$path]) 'mir4-target-key-migration-evolved-prior-sha256' $path
  $actual = Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $path) -Mode ([string]$binding.hash_mode)
  Assert-MIR4TargetKeyMigrationV1 ([string]$binding.current_sha256 -ceq $actual) 'mir4-target-key-migration-evolved-current-sha256' $path
  Assert-MIR4TargetKeyMigrationV1 (-not [bool]$binding.package_visible -and -not [bool]$binding.release_authority) 'mir4-target-key-migration-evolved-firewall' $path
}
foreach ($binding in @($receipt.current_authorities)) {
  $actual = Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$binding.path)) -Mode ([string]$binding.hash_mode)
  Assert-MIR4TargetKeyMigrationV1 ([string]$binding.sha256 -ceq $actual) 'mir4-target-key-migration-current-authority' ([string]$binding.path)
}
foreach ($component in @($receipt.components)) {
  Assert-MIR4TargetKeyMigrationV1 ([string]$component.hash_mode -ceq 'canonical-text-v1') 'mir4-target-key-migration-component-mode' ([string]$component.path)
  $actual = Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$component.path)) -Mode 'canonical-text-v1'
  Assert-MIR4TargetKeyMigrationV1 ([string]$component.sha256 -ceq $actual) 'mir4-target-key-migration-component-sha256' ([string]$component.path)
}
$digest = Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:target-key-migration-receipt:1' -OmitTopLevelDigest
Assert-MIR4TargetKeyMigrationV1 ([string]$receipt.digest -ceq $digest) 'mir4-target-key-migration-receipt-digest'
foreach ($field in @('transition_gate','release_transition_authority')) {
  Assert-MIR4TargetKeyMigrationV1 (@($receipt.$field.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-target-key-migration-release-firewall' $field
}
Assert-MIR4TargetKeyMigrationV1 ([string]$receipt.sunset.state -ceq 'deferred-compatibility-readers-retained') 'mir4-target-key-migration-sunset'

Test-MIR4PreFreezeAuthorities -RepoRoot $repo | Out-Null
$latest = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration
Assert-MIR4TargetKeyMigrationV1 ([string]$latest.prior_receipt_path -ceq $script:MIR4TargetKeyMigrationReceiptPath) 'mir4-target-key-migration-prefreeze-chain'

function Invoke-MIR4TargetKeyMigrationCommandProbeV1 {
  param([Parameter(Mandatory)][ValidateSet('check','show')][string]$Command)
  $output = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4TargetKeyMigration.ps1') -Command $Command -RepoRoot $repo 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) { throw "[mir4-target-key-migration-cli] $Command $output" }
  return $output | ConvertFrom-Json -Depth 100
}
$checkResult = Invoke-MIR4TargetKeyMigrationCommandProbeV1 -Command check
$showResult = Invoke-MIR4TargetKeyMigrationCommandProbeV1 -Command show
Assert-MIR4TargetKeyMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 -Value $checkResult) -ceq (ConvertTo-MIR4CanonicalJsonV1 -Value $showResult)) 'mir4-target-key-migration-cli-parity'
$facadeOutput = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 target-key-migration check 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "[mir4-target-key-migration-facade] $facadeOutput" }
$facadeResult = $facadeOutput | ConvertFrom-Json -Depth 100
Assert-MIR4TargetKeyMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 -Value $checkResult) -ceq (ConvertTo-MIR4CanonicalJsonV1 -Value $facadeResult)) 'mir4-target-key-migration-facade-parity'
Assert-MIR4TargetKeyMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-target-key-migration-package-source-mutation'

[pscustomobject][ordered]@{
  status='passed'
  migration_id=[string]$receipt.migration_id
  canonical_implementation='tools/mir/domain/targets/TargetKey.ps1'
  compatibility_entrypoints=@($authority.compatibility_entrypoints | ForEach-Object { [string]$_.path })
  predecessor_receipt_sha256=$script:MIR4TargetKeyPredecessorReceiptSha256
  parity_digest=[string]$parity.digest
  receipt_digest=[string]$receipt.digest
  package_source_sha256=[string]$receipt.package_source_sha256
  package_visible_delta=@($receipt.package_visible_delta)
  release_transition_authority=$false
}
