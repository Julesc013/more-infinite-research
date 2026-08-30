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
$firstReceipt = Invoke-MIR4RepositoryMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4CanonicalizationMigrationV1 ([string]$firstReceipt.migration_id -ceq 'MIR4-REPOSITORY-FIXED-POINT-TOOLING-V1') 'mir4-canonicalization-migration-first-predecessor-kind'
try { Invoke-MIR4RepositoryMigrationProjectionV1 -RepoRoot $repo | Out-Null; throw '[mir4-canonicalization-migration-first-predecessor-write-enabled]' }
catch { if (-not $_.Exception.Message.StartsWith('[mir4-repository-migration-receipt-immutable]')) { throw } }

$authority = Get-MIR4CanonicalizationMigrationAuthorityV1 -RepoRoot $repo
$proof = Get-MIR4CanonicalizationMigrationProofPolicyV1 -RepoRoot $repo
$receipt = Invoke-MIR4CanonicalizationMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4CanonicalizationMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4CanonicalizationMigrationReceiptPath) -Algorithm SHA256).Hash -ceq $script:MIR4CanonicalizationMigrationReceiptSha256) 'mir4-canonicalization-migration-immutable-bytes'
Assert-MIR4CanonicalizationMigrationV1 ([string]$receipt.migration_id -ceq 'MIR4-CANONICALIZATION-TOOLING-V1') 'mir4-canonicalization-migration-id'
Assert-MIR4CanonicalizationMigrationV1 ([string]$receipt.predecessor_receipt.path -ceq $script:MIR4CanonicalizationPredecessorReceiptPath) 'mir4-canonicalization-migration-predecessor-path'
Assert-MIR4CanonicalizationMigrationV1 ([string]$receipt.predecessor_receipt.sha256 -ceq $script:MIR4CanonicalizationPredecessorReceiptSha256) 'mir4-canonicalization-migration-predecessor-sha256'
Assert-MIR4CanonicalizationMigrationV1 (@($authority.writers).Count -eq 1) 'mir4-canonicalization-migration-writer-count'
Assert-MIR4CanonicalizationMigrationV1 ([string]$proof.test_id -ceq 'static.mir4-canonicalization-migration-v1') 'mir4-canonicalization-migration-proof-test-id'
Assert-MIR4CanonicalizationMigrationV1 (Test-MIR4CanonicalizationCompatibilityForwardersV1 -RepoRoot $repo) 'mir4-canonicalization-migration-forwarders'

foreach ($field in @('transition_gate','release_transition_authority')) {
  Assert-MIR4CanonicalizationMigrationV1 (@($receipt.$field.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-canonicalization-migration-release-firewall' $field
}
Assert-MIR4CanonicalizationMigrationV1 ([string]$receipt.package_source_sha256 -ceq $packageBefore) 'mir4-canonicalization-migration-package-fingerprint'
Assert-MIR4CanonicalizationMigrationV1 (@($receipt.package_visible_delta).Count -eq 0) 'mir4-canonicalization-migration-package-delta'
foreach ($path in @($authority.path_map.final_path) + @($authority.compatibility_entrypoints.path)) {
  Assert-MIR4CanonicalizationMigrationV1 ($path -notin @(Get-MIRPackageSourceFiles -RepoRoot $repo)) 'mir4-canonicalization-migration-package-visible' ([string]$path)
}

$assuranceConfig = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$migrationClass = @($assuranceConfig.classes | Where-Object { [string]$_.id -ceq 'repository-migration' })
Assert-MIR4CanonicalizationMigrationV1 ($migrationClass.Count -eq 1 -and @($migrationClass[0].tests) -contains [string]$proof.test_id) 'mir4-canonicalization-migration-assurance-registration'
$catalog = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
$rows = @($catalog.tests | Where-Object { [string]$_.id -ceq [string]$proof.test_id })
Assert-MIR4CanonicalizationMigrationV1 ($rows.Count -eq 1 -and [string]$rows[0].command -ceq './tests/canonicalization/Test-MIR4CanonicalizationMigration.ps1') 'mir4-canonicalization-migration-test-registration'

$prior = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration
Assert-MIR4CanonicalizationMigrationV1 ([string]$receipt.predecessor_receipt.path -ceq [string]$prior.prior_receipt_path) 'mir4-canonicalization-migration-chain-path'
Assert-MIR4CanonicalizationMigrationV1 ([string]$receipt.predecessor_receipt.sha256 -ceq [string]$prior.prior_receipt_sha256) 'mir4-canonicalization-migration-chain-sha256'
$latest = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration
Assert-MIR4CanonicalizationMigrationV1 ([string]$latest.prior_receipt_path -ceq $script:MIR4CanonicalizationMigrationReceiptPath) 'mir4-canonicalization-migration-prefreeze-chain'
Test-MIR4PreFreezeAuthorities -RepoRoot $repo | Out-Null

function Invoke-MIR4CanonicalizationMigrationCommandProbeV1 {
  param([Parameter(Mandatory)][ValidateSet('check','show')][string]$Command)
  $output = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4CanonicalizationMigration.ps1') -Command $Command -RepoRoot $repo 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) { throw "[mir4-canonicalization-migration-cli] $Command $output" }
  return $output | ConvertFrom-Json -Depth 100
}
$checkResult = Invoke-MIR4CanonicalizationMigrationCommandProbeV1 -Command check
$showResult = Invoke-MIR4CanonicalizationMigrationCommandProbeV1 -Command show
Assert-MIR4CanonicalizationMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 -Value $checkResult) -ceq (ConvertTo-MIR4CanonicalJsonV1 -Value $showResult)) 'mir4-canonicalization-migration-cli-parity'
$generateOutput = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4CanonicalizationMigration.ps1') -Command generate -RepoRoot $repo 2>&1 | Out-String).Trim()
Assert-MIR4CanonicalizationMigrationV1 ($LASTEXITCODE -ne 0 -and $generateOutput -match 'mir4-canonicalization-migration-receipt-immutable') 'mir4-canonicalization-migration-generate-disabled'
$facadeOutput = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 canonicalization-migration check 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "[mir4-canonicalization-migration-facade] $facadeOutput" }
$facadeResult = $facadeOutput | ConvertFrom-Json -Depth 100
Assert-MIR4CanonicalizationMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 -Value $checkResult) -ceq (ConvertTo-MIR4CanonicalJsonV1 -Value $facadeResult)) 'mir4-canonicalization-migration-facade-parity'
Assert-MIR4CanonicalizationMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-canonicalization-migration-package-source-mutation'

[pscustomobject][ordered]@{
  status='passed'
  migration_id=[string]$receipt.migration_id
  state='accepted-immutable-predecessor'
  receipt_sha256=$script:MIR4CanonicalizationMigrationReceiptSha256
  receipt_digest=[string]$receipt.digest
  package_source_sha256=$packageBefore
  release_transition_authority=$false
}
