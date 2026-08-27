param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/canonicalization/CanonicalizationMigration.ps1')
. (Join-Path $repo 'tools/mir/application/diagnostics/DiagnosticsMigration.ps1')

function Assert-MIR4DiagnosticsMigrationV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if (-not $Condition) {
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " $Detail" }
    throw "[$Code]$suffix"
  }
}

$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$predecessor = Invoke-MIR4CanonicalizationMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4DiagnosticsMigrationV1 ([string]$predecessor.migration_id -ceq 'MIR4-CANONICALIZATION-TOOLING-V1') 'mir4-diagnostics-migration-predecessor-id'
Assert-MIR4DiagnosticsMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4DiagnosticsPredecessorReceiptPath) -Algorithm SHA256).Hash -ceq $script:MIR4DiagnosticsPredecessorReceiptSha256) 'mir4-diagnostics-migration-predecessor-immutable'
try { Invoke-MIR4CanonicalizationMigrationProjectionV1 -RepoRoot $repo | Out-Null; throw '[mir4-diagnostics-migration-predecessor-write-enabled]' }
catch { if (-not $_.Exception.Message.StartsWith('[mir4-canonicalization-migration-receipt-immutable]')) { throw } }

$authority = Get-MIR4DiagnosticsMigrationAuthorityV1 -RepoRoot $repo
$proof = Get-MIR4DiagnosticsMigrationProofPolicyV1 -RepoRoot $repo
$receipt = Invoke-MIR4DiagnosticsMigrationProjectionV1 -RepoRoot $repo -Check
$inventory = Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4DiagnosticsMigrationV1 ([int]$inventory.summary.unknown -eq 0) 'mir4-diagnostics-migration-inventory-unknown'
Assert-MIR4DiagnosticsMigrationV1 (-not [bool]$inventory.deletion_authorized) 'mir4-diagnostics-migration-deletion-authority'
Assert-MIR4DiagnosticsMigrationV1 (@($authority.writers).Count -eq 1) 'mir4-diagnostics-migration-writer-count'
Assert-MIR4DiagnosticsMigrationV1 ([string]$proof.test_id -ceq 'static.mir4-diagnostics-migration-v1') 'mir4-diagnostics-migration-proof-test-id'
Assert-MIR4DiagnosticsMigrationV1 (Test-MIR4DiagnosticsCompatibilityForwarderV1 -RepoRoot $repo) 'mir4-diagnostics-migration-forwarder'
Assert-MIR4DiagnosticsMigrationV1 (Test-MIR4DiagnosticsDeclaredConsumersV1 -RepoRoot $repo) 'mir4-diagnostics-migration-consumers'
$parity = Test-MIR4DiagnosticsFunctionalParityV1 -RepoRoot $repo
Assert-MIR4DiagnosticsMigrationV1 ([string]$parity.digest -ceq $script:MIR4DiagnosticsParityDigestV1) 'mir4-diagnostics-migration-functional-parity'

$enginePath = 'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1'
$engineText = [IO.File]::ReadAllText((Join-Path $repo $enginePath))
Assert-MIR4DiagnosticsMigrationV1 ($engineText -match 'function Test-MIR4ImmutableMigrationReceiptV1' -and $engineText -match 'function New-MIR4AppendOnlyAuthorityMigrationReceiptV1') 'mir4-diagnostics-migration-shared-engine'
$canonicalAppText = [IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/canonicalization/CanonicalizationMigration.ps1')).Replace('\','/')
Assert-MIR4DiagnosticsMigrationV1 ($canonicalAppText -match [regex]::Escape('application/canonicalization/../migration/AppendOnlyAuthorityMigration.ps1') -or $canonicalAppText -match [regex]::Escape('../migration/AppendOnlyAuthorityMigration.ps1')) 'mir4-diagnostics-migration-canonical-engine-reuse'

$assuranceConfig = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$migrationClass = @($assuranceConfig.classes | Where-Object { [string]$_.id -ceq 'repository-migration' })
Assert-MIR4DiagnosticsMigrationV1 ($migrationClass.Count -eq 1) 'mir4-diagnostics-migration-assurance-class'
$migrationPaths = @($authority.path_map | ForEach-Object { [string]$_.final_path }) + @($authority.compatibility_entrypoints | ForEach-Object { [string]$_.path })
foreach ($path in @($migrationPaths | Sort-Object -Unique)) {
  $matches = @($migrationClass[0].patterns | Where-Object { $path -match [string]$_ })
  Assert-MIR4DiagnosticsMigrationV1 ($matches.Count -gt 0) 'mir4-diagnostics-migration-assurance-path' $path
}
Assert-MIR4DiagnosticsMigrationV1 (@($migrationClass[0].tests) -contains [string]$proof.test_id) 'mir4-diagnostics-migration-assurance-test'

$catalog = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
$functionalRows = @($catalog.tests | Where-Object { [string]$_.id -ceq 'static.mir4-diagnostics-v1' })
$migrationRows = @($catalog.tests | Where-Object { [string]$_.id -ceq [string]$proof.test_id })
Assert-MIR4DiagnosticsMigrationV1 ($functionalRows.Count -eq 1 -and [string]$functionalRows[0].command -ceq './tests/diagnostics/Test-MIR4DiagnosticsV1.ps1') 'mir4-diagnostics-migration-functional-test-registration'
Assert-MIR4DiagnosticsMigrationV1 ($migrationRows.Count -eq 1 -and [string]$migrationRows[0].command -ceq './tests/diagnostics/Test-MIR4DiagnosticsMigration.ps1') 'mir4-diagnostics-migration-test-registration'

$packageFiles = @(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach ($path in @($migrationPaths | Sort-Object -Unique)) {
  Assert-MIR4DiagnosticsMigrationV1 ($path -notin $packageFiles) 'mir4-diagnostics-migration-package-visible' $path
}
Assert-MIR4DiagnosticsMigrationV1 ($packageBefore -ceq [string]$authority.package_source_sha256) 'mir4-diagnostics-migration-package-fingerprint-authority'
Assert-MIR4DiagnosticsMigrationV1 ([string]$receipt.package_source_sha256 -ceq $packageBefore) 'mir4-diagnostics-migration-package-fingerprint-receipt'
Assert-MIR4DiagnosticsMigrationV1 (@($receipt.package_visible_delta).Count -eq 0) 'mir4-diagnostics-migration-package-delta'

$prior = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration
Assert-MIR4DiagnosticsMigrationV1 ([string]$receipt.predecessor_receipt.path -ceq [string]$prior.prior_receipt_path) 'mir4-diagnostics-migration-predecessor-path'
Assert-MIR4DiagnosticsMigrationV1 ([string]$receipt.predecessor_receipt.sha256 -ceq [string]$prior.prior_receipt_sha256) 'mir4-diagnostics-migration-predecessor-sha256'
foreach ($binding in @($receipt.evolved_bindings)) {
  $path = [string]$binding.path
  Assert-MIR4DiagnosticsMigrationV1 ($prior.authority_hashes.ContainsKey($path)) 'mir4-diagnostics-migration-evolved-prior-missing' $path
  Assert-MIR4DiagnosticsMigrationV1 ([string]$binding.previous_sha256 -ceq [string]$prior.authority_hashes[$path]) 'mir4-diagnostics-migration-evolved-prior-sha256' $path
  $actual = Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $path) -Mode ([string]$binding.hash_mode)
  Assert-MIR4DiagnosticsMigrationV1 ([string]$binding.current_sha256 -ceq $actual) 'mir4-diagnostics-migration-evolved-current-sha256' $path
  Assert-MIR4DiagnosticsMigrationV1 (-not [bool]$binding.package_visible -and -not [bool]$binding.release_authority) 'mir4-diagnostics-migration-evolved-firewall' $path
}
foreach ($binding in @($receipt.current_authorities)) {
  $actual = Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$binding.path)) -Mode ([string]$binding.hash_mode)
  Assert-MIR4DiagnosticsMigrationV1 ([string]$binding.sha256 -ceq $actual) 'mir4-diagnostics-migration-current-authority' ([string]$binding.path)
}
foreach ($component in @($receipt.components)) {
  Assert-MIR4DiagnosticsMigrationV1 ([string]$component.hash_mode -ceq 'canonical-text-v1') 'mir4-diagnostics-migration-component-mode' ([string]$component.path)
  $actual = Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$component.path)) -Mode 'canonical-text-v1'
  Assert-MIR4DiagnosticsMigrationV1 ([string]$component.sha256 -ceq $actual) 'mir4-diagnostics-migration-component-sha256' ([string]$component.path)
}
$digest = Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:diagnostics-migration-receipt:1' -OmitTopLevelDigest
Assert-MIR4DiagnosticsMigrationV1 ([string]$receipt.digest -ceq $digest) 'mir4-diagnostics-migration-receipt-digest'
foreach ($field in @('transition_gate','release_transition_authority')) {
  Assert-MIR4DiagnosticsMigrationV1 (@($receipt.$field.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-diagnostics-migration-release-firewall' $field
}
Assert-MIR4DiagnosticsMigrationV1 ([string]$receipt.sunset.state -ceq 'deferred-compatibility-readers-retained') 'mir4-diagnostics-migration-sunset'

Test-MIR4PreFreezeAuthorities -RepoRoot $repo | Out-Null
$latest = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration
Assert-MIR4DiagnosticsMigrationV1 ([string]$latest.prior_receipt_path -ceq $script:MIR4DiagnosticsMigrationReceiptPath) 'mir4-diagnostics-migration-prefreeze-chain'

function Invoke-MIR4DiagnosticsMigrationCommandProbeV1 {
  param([Parameter(Mandatory)][ValidateSet('check','show')][string]$Command)
  $output = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4DiagnosticsMigration.ps1') -Command $Command -RepoRoot $repo 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) { throw "[mir4-diagnostics-migration-cli] $Command $output" }
  return $output | ConvertFrom-Json -Depth 100
}
$checkResult = Invoke-MIR4DiagnosticsMigrationCommandProbeV1 -Command check
$showResult = Invoke-MIR4DiagnosticsMigrationCommandProbeV1 -Command show
Assert-MIR4DiagnosticsMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 -Value $checkResult) -ceq (ConvertTo-MIR4CanonicalJsonV1 -Value $showResult)) 'mir4-diagnostics-migration-cli-parity'
$facadeOutput = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 diagnostics-migration check 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "[mir4-diagnostics-migration-facade] $facadeOutput" }
$facadeResult = $facadeOutput | ConvertFrom-Json -Depth 100
Assert-MIR4DiagnosticsMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 -Value $checkResult) -ceq (ConvertTo-MIR4CanonicalJsonV1 -Value $facadeResult)) 'mir4-diagnostics-migration-facade-parity'
Assert-MIR4DiagnosticsMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-diagnostics-migration-package-source-mutation'

[pscustomobject][ordered]@{
  status='passed'
  migration_id=[string]$receipt.migration_id
  canonical_implementation='tools/mir/domain/diagnostics/DiagnosticsV1.ps1'
  compatibility_entrypoints=@($authority.compatibility_entrypoints | ForEach-Object { [string]$_.path })
  predecessor_receipt_sha256=$script:MIR4DiagnosticsPredecessorReceiptSha256
  parity_digest=[string]$parity.digest
  receipt_digest=[string]$receipt.digest
  package_source_sha256=[string]$receipt.package_source_sha256
  package_visible_delta=@($receipt.package_visible_delta)
  release_transition_authority=$false
}
