param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/canonicalization/CanonicalizationMigration.ps1')

function Assert-MIR4CanonicalizationMigrationV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if (-not $Condition) {
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " $Detail" }
    throw "[$Code]$suffix"
  }
}

$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$predecessorPath = Join-Path $repo $script:MIR4CanonicalizationPredecessorReceiptPath
Assert-MIR4CanonicalizationMigrationV1 ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash -ceq $script:MIR4CanonicalizationPredecessorReceiptSha256) 'mir4-canonicalization-migration-predecessor-immutable'
$historicalReceipt = Invoke-MIR4RepositoryMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4CanonicalizationMigrationV1 ([string]$historicalReceipt.migration_id -ceq 'MIR4-REPOSITORY-FIXED-POINT-TOOLING-V1') 'mir4-canonicalization-migration-predecessor-kind'
try {
  Invoke-MIR4RepositoryMigrationProjectionV1 -RepoRoot $repo | Out-Null
  throw '[mir4-canonicalization-migration-predecessor-write-enabled]'
} catch {
  if (-not $_.Exception.Message.StartsWith('[mir4-repository-migration-receipt-immutable]')) { throw }
}

$authority = Get-MIR4CanonicalizationMigrationAuthorityV1 -RepoRoot $repo
$proof = Get-MIR4CanonicalizationMigrationProofPolicyV1 -RepoRoot $repo
$receipt = Invoke-MIR4CanonicalizationMigrationProjectionV1 -RepoRoot $repo -Check
$inventory = Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4CanonicalizationMigrationV1 ([int]$inventory.summary.unknown -eq 0) 'mir4-canonicalization-migration-inventory-unknown'
Assert-MIR4CanonicalizationMigrationV1 (-not [bool]$inventory.deletion_authorized) 'mir4-canonicalization-migration-deletion-authority'
Assert-MIR4CanonicalizationMigrationV1 (@($authority.writers).Count -eq 1) 'mir4-canonicalization-migration-writer-count'
Assert-MIR4CanonicalizationMigrationV1 ([string]$proof.test_id -ceq 'static.mir4-canonicalization-migration-v1') 'mir4-canonicalization-migration-proof-test-id'
Assert-MIR4CanonicalizationMigrationV1 (Test-MIR4CanonicalizationCompatibilityForwardersV1 -RepoRoot $repo) 'mir4-canonicalization-migration-forwarders'
foreach ($consumerPath in @(
  'tools/lib/mir4/EnvironmentEvidence.ps1',
  'tools/lib/mir4/ModuleEcosystem.ps1',
  'tools/lib/mir4/PlatformPreview.ps1',
  'tools/lib/mir4/ExperimentalApiSdk.ps1',
  'tools/mir/application/repository/RepositoryFixedPoint.ps1'
)) {
  $consumerText = [IO.File]::ReadAllText((Join-Path $repo $consumerPath)).Replace('\','/')
  Assert-MIR4CanonicalizationMigrationV1 ($consumerText -match 'domain/canonicalization/CanonicalJsonV1\.ps1') 'mir4-canonicalization-migration-consumer-cutover' $consumerPath
}

$assuranceConfig = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$migrationClass = @($assuranceConfig.classes | Where-Object { [string]$_.id -ceq 'repository-migration' })
Assert-MIR4CanonicalizationMigrationV1 ($migrationClass.Count -eq 1) 'mir4-canonicalization-migration-assurance-class'
$migrationPaths = @($authority.path_map | ForEach-Object { [string]$_.final_path }) + @($authority.compatibility_entrypoints | ForEach-Object { [string]$_.path })
foreach ($path in @($migrationPaths | Sort-Object -Unique)) {
  $matches = @($migrationClass[0].patterns | Where-Object { $path -match [string]$_ })
  Assert-MIR4CanonicalizationMigrationV1 ($matches.Count -gt 0) 'mir4-canonicalization-migration-assurance-path' $path
}
Assert-MIR4CanonicalizationMigrationV1 (@($migrationClass[0].tests) -contains [string]$proof.test_id) 'mir4-canonicalization-migration-assurance-test'

$catalog = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
$functionalRows = @($catalog.tests | Where-Object { [string]$_.id -ceq 'static.mir4-canonicalization-diagnostics-t07' })
$migrationRows = @($catalog.tests | Where-Object { [string]$_.id -ceq [string]$proof.test_id })
Assert-MIR4CanonicalizationMigrationV1 ($functionalRows.Count -eq 1 -and [string]$functionalRows[0].command -ceq './tests/canonicalization/Test-MIR4CanonicalizationDiagnostics.ps1') 'mir4-canonicalization-migration-functional-test-cutover'
Assert-MIR4CanonicalizationMigrationV1 ($migrationRows.Count -eq 1 -and [string]$migrationRows[0].command -ceq './tests/canonicalization/Test-MIR4CanonicalizationMigration.ps1') 'mir4-canonicalization-migration-test-registration'

$packageFiles = @(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach ($path in @($migrationPaths | Sort-Object -Unique)) {
  Assert-MIR4CanonicalizationMigrationV1 ($path -notin $packageFiles) 'mir4-canonicalization-migration-package-visible' $path
}
Assert-MIR4CanonicalizationMigrationV1 ($packageBefore -ceq [string]$authority.package_source_sha256) 'mir4-canonicalization-migration-package-fingerprint-authority'
Assert-MIR4CanonicalizationMigrationV1 ([string]$receipt.package_source_sha256 -ceq $packageBefore) 'mir4-canonicalization-migration-package-fingerprint-receipt'
Assert-MIR4CanonicalizationMigrationV1 (@($receipt.package_visible_delta).Count -eq 0) 'mir4-canonicalization-migration-package-delta'

$prior = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration
Assert-MIR4CanonicalizationMigrationV1 ([string]$receipt.predecessor_receipt.path -ceq [string]$prior.prior_receipt_path) 'mir4-canonicalization-migration-predecessor-path'
Assert-MIR4CanonicalizationMigrationV1 ([string]$receipt.predecessor_receipt.sha256 -ceq [string]$prior.prior_receipt_sha256) 'mir4-canonicalization-migration-predecessor-sha256'
foreach ($binding in @($receipt.evolved_bindings)) {
  $path = [string]$binding.path
  Assert-MIR4CanonicalizationMigrationV1 ($prior.authority_hashes.ContainsKey($path)) 'mir4-canonicalization-migration-evolved-prior-missing' $path
  Assert-MIR4CanonicalizationMigrationV1 ([string]$binding.previous_sha256 -ceq [string]$prior.authority_hashes[$path]) 'mir4-canonicalization-migration-evolved-prior-sha256' $path
  $actual = Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $path) -Mode ([string]$binding.hash_mode)
  Assert-MIR4CanonicalizationMigrationV1 ([string]$binding.current_sha256 -ceq $actual) 'mir4-canonicalization-migration-evolved-current-sha256' $path
  Assert-MIR4CanonicalizationMigrationV1 (-not [bool]$binding.package_visible -and -not [bool]$binding.release_authority) 'mir4-canonicalization-migration-evolved-firewall' $path
}
foreach ($binding in @($receipt.current_authorities)) {
  $actual = Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$binding.path)) -Mode ([string]$binding.hash_mode)
  Assert-MIR4CanonicalizationMigrationV1 ([string]$binding.sha256 -ceq $actual) 'mir4-canonicalization-migration-current-authority' ([string]$binding.path)
}
foreach ($component in @($receipt.components)) {
  Assert-MIR4CanonicalizationMigrationV1 ([string]$component.hash_mode -ceq 'canonical-text-v1') 'mir4-canonicalization-migration-component-mode' ([string]$component.path)
  $actual = Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$component.path)) -Mode 'canonical-text-v1'
  Assert-MIR4CanonicalizationMigrationV1 ([string]$component.sha256 -ceq $actual) 'mir4-canonicalization-migration-component-sha256' ([string]$component.path)
}
$digest = Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:canonicalization-migration-receipt:1' -OmitTopLevelDigest
Assert-MIR4CanonicalizationMigrationV1 ([string]$receipt.digest -ceq $digest) 'mir4-canonicalization-migration-receipt-digest'
Assert-MIR4CanonicalizationMigrationV1 (@($receipt.release_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-canonicalization-migration-release-firewall'
Assert-MIR4CanonicalizationMigrationV1 ([string]$receipt.sunset.state -ceq 'deferred-compatibility-readers-retained') 'mir4-canonicalization-migration-sunset'

Test-MIR4PreFreezeAuthorities -RepoRoot $repo | Out-Null
$latest = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration
Assert-MIR4CanonicalizationMigrationV1 ([string]$latest.prior_receipt_path -ceq $script:MIR4CanonicalizationMigrationReceiptPath) 'mir4-canonicalization-migration-prefreeze-chain'

function Invoke-MIR4CanonicalizationMigrationCommandProbeV1 {
  param([Parameter(Mandatory)][ValidateSet('check','show')][string]$Command)
  $output = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4CanonicalizationMigration.ps1') -Command $Command -RepoRoot $repo 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) { throw "[mir4-canonicalization-migration-cli] $Command $output" }
  return $output | ConvertFrom-Json -Depth 100
}
$checkResult = Invoke-MIR4CanonicalizationMigrationCommandProbeV1 -Command check
$showResult = Invoke-MIR4CanonicalizationMigrationCommandProbeV1 -Command show
Assert-MIR4CanonicalizationMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 -Value $checkResult) -ceq (ConvertTo-MIR4CanonicalJsonV1 -Value $showResult)) 'mir4-canonicalization-migration-cli-parity'
$facadeOutput = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 canonicalization-migration check 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "[mir4-canonicalization-migration-facade] $facadeOutput" }
$facadeResult = $facadeOutput | ConvertFrom-Json -Depth 100
Assert-MIR4CanonicalizationMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 -Value $checkResult) -ceq (ConvertTo-MIR4CanonicalJsonV1 -Value $facadeResult)) 'mir4-canonicalization-migration-facade-parity'
Assert-MIR4CanonicalizationMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-canonicalization-migration-package-source-mutation'

[pscustomobject][ordered]@{
  status='passed'
  migration_id=[string]$receipt.migration_id
  canonical_implementation='tools/mir/domain/canonicalization/CanonicalJsonV1.ps1'
  canonical_test='tests/canonicalization/Test-MIR4CanonicalizationDiagnostics.ps1'
  compatibility_entrypoints=@($authority.compatibility_entrypoints | ForEach-Object { [string]$_.path })
  predecessor_receipt_sha256=$script:MIR4CanonicalizationPredecessorReceiptSha256
  receipt_digest=[string]$receipt.digest
  package_source_sha256=[string]$receipt.package_source_sha256
  package_visible_delta=@($receipt.package_visible_delta)
  release_transition_authority=$false
}
