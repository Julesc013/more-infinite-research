param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')

function Assert-MIR4RepositoryMigrationV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if (-not $Condition) {
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " $Detail" }
    throw "[$Code]$suffix"
  }
}

$authority = Get-MIR4RepositoryFixedPointAuthority -RepoRoot $repo
$migration = Get-MIR4RepositoryMigrationAuthorityV1 -RepoRoot $repo
$proof = Get-MIR4RepositoryMigrationProofPolicyV1 -RepoRoot $repo
Invoke-MIR4RepositoryRootProjection -RepoRoot $repo -Check
$receipt = Invoke-MIR4RepositoryMigrationProjectionV1 -RepoRoot $repo -Check
$inventory = Get-MIR4RepositoryInventory -RepoRoot $repo

if ([int]$inventory.summary.unknown -ne 0) {
  $unknown = @($inventory.tracked + $inventory.untracked + $inventory.ignored | Where-Object class -eq 'unknown' | ForEach-Object path)
  throw "[mir4-repository-migration-unknown-path] $($unknown -join ', ')"
}
Assert-MIR4RepositoryMigrationV1 (-not [bool]$inventory.deletion_authorized) 'mir4-repository-migration-deletion-authority'
Assert-MIR4RepositoryMigrationV1 (@($migration.writers).Count -eq 1) 'mir4-repository-migration-writer-count'
Assert-MIR4RepositoryMigrationV1 (@($receipt.parity.duplicate_writers).Count -eq 0) 'mir4-repository-migration-duplicate-writer'
Assert-MIR4RepositoryMigrationV1 (Test-MIR4RepositoryCompatibilityForwardersV1 -RepoRoot $repo) 'mir4-repository-migration-forwarders'
Assert-MIR4RepositoryMigrationV1 ([string]$proof.test_id -ceq 'static.mir4-repository-fixed-point-v2') 'mir4-repository-migration-proof-test-id'

$expectedActive = @('governance','contracts','assurance','tests','tools-mir','releases','changes')
$actualActive = @($authority.visible_roots | Where-Object { [string]$_.mode -like 'active-*' } | ForEach-Object { [string]$_.id } | Sort-Object)
Assert-MIR4RepositoryMigrationV1 ((@($actualActive) -join '|') -ceq (@($expectedActive | Sort-Object) -join '|')) 'mir4-repository-migration-active-roots'
Assert-MIR4RepositoryMigrationV1 (@($authority.visible_roots | Where-Object { [string]$_.mode -like 'shadow*' }).Count -ge 4) 'mir4-repository-migration-remaining-shadow-boundary'
Assert-MIR4RepositoryMigrationV1 (@($authority.move_gate).Count -eq 6) 'mir4-repository-migration-move-gate'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.remaining_move.classification -ceq 'bounded-authority-migration-and-package-cutover-debt') 'mir4-repository-migration-debt-class'
Assert-MIR4RepositoryMigrationV1 (@($authority.migration_sequence).Count -eq 17) 'mir4-repository-migration-sequence-count'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[0].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[1].migration_id -ceq 'MIR4-CANONICALIZATION-TOOLING-V1' -and [string]$authority.migration_sequence[1].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-canonicalization-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[2].migration_id -ceq 'MIR4-DIAGNOSTICS-TOOLING-V1' -and [string]$authority.migration_sequence[2].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-diagnostics-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[3].migration_id -ceq 'MIR4-TARGET-KEY-TOOLING-V1' -and [string]$authority.migration_sequence[3].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-target-key-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[4].migration_id -ceq 'MIR4-WHOLE-PLATFORM-TOOLING-V1' -and [string]$authority.migration_sequence[4].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-whole-platform-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[5].migration_id -ceq 'MIR4-TECHNOLOGY-ACCEPTANCE-TOOLING-V1' -and [string]$authority.migration_sequence[5].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-technology-acceptance-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[6].migration_id -ceq 'MIR4-TARGET-COMPILER-TOOLING-V1' -and [string]$authority.migration_sequence[6].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-target-compiler-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[7].migration_id -ceq 'MIR4-SEMANTIC-COMPILER-POLICY-TOOLING-V1' -and [string]$authority.migration_sequence[7].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-semantic-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[8].migration_id -ceq 'MIR4-RUNTIME-CONTINUITY-TOOLING-V1' -and [string]$authority.migration_sequence[8].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-runtime-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[9].migration_id -ceq 'MIR4-MODULE-SDK-MEP-TOOLING-V1' -and [string]$authority.migration_sequence[9].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-module-sdk-mep-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[10].migration_id -ceq 'MIR4-PROCESSIR-EXACT-TOOLING-V1' -and [string]$authority.migration_sequence[10].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-processir-exact-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[11].migration_id -ceq 'MIR4-INSPECTOR-COMPATIBILITY-TOOLING-V1' -and [string]$authority.migration_sequence[11].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-inspector-compatibility-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[12].migration_id -ceq 'MIR4-ASSURANCE-OFFLINE-CUSTODY-TOOLING-V1' -and [string]$authority.migration_sequence[12].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-assurance-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[13].migration_id -ceq 'MIR4-HISTORICAL-TOOLING-V1' -and [string]$authority.migration_sequence[13].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-historical-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[14].migration_id -ceq 'MIR4-RELEASE-TOOLING-V1' -and [string]$authority.migration_sequence[14].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-release-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[15].migration_id -ceq 'M41-03-CHANGE-AND-RELEASE-AUTHORITY-V1' -and [string]$authority.migration_sequence[15].state -ceq 'accepted-immutable-predecessor') 'mir4-repository-migration-sequence-m41-03-predecessor'
Assert-MIR4RepositoryMigrationV1 ([string]$authority.migration_sequence[16].migration_id -ceq 'M41-05A-M42-00A-REPOSITORY-CHARACTERIZATION-V1' -and [string]$authority.migration_sequence[16].state -ceq 'current-append-only-successor') 'mir4-repository-migration-sequence-characterization-successor'
foreach ($root in @($authority.visible_roots)) {
  $marker = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path (([string]$root.path) + '/.mir-root.json')
  $expectedWritable = [string]$root.id -ceq 'changes'
  Assert-MIR4RepositoryMigrationV1 ([bool]$marker.writable_authority -eq $expectedWritable) 'mir4-repository-migration-marker-compatibility-authority' ([string]$root.path)
  Assert-MIR4RepositoryMigrationV1 (-not [bool]$marker.marker_is_writable_authority) 'mir4-repository-migration-marker-projection-authority' ([string]$root.path)
}

$assuranceConfig = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$repositoryMigrationClass = @($assuranceConfig.classes | Where-Object { [string]$_.id -ceq 'repository-migration' })
Assert-MIR4RepositoryMigrationV1 ($repositoryMigrationClass.Count -eq 1) 'mir4-repository-migration-assurance-class'
$assurancePaths = @($migration.path_map | ForEach-Object { [string]$_.final_path }) + @($authority.visible_roots | ForEach-Object { ([string]$_.path) + '/.mir-root.json' })
foreach ($path in @($assurancePaths | Sort-Object -Unique)) {
  $matches = @($repositoryMigrationClass[0].patterns | Where-Object { $path -match [string]$_ })
  Assert-MIR4RepositoryMigrationV1 ($matches.Count -gt 0) 'mir4-repository-migration-assurance-path' $path
}
Assert-MIR4RepositoryMigrationV1 (@($repositoryMigrationClass[0].tests) -contains 'static.mir4-repository-fixed-point-v2') 'mir4-repository-migration-assurance-test'

$packageFiles = @(Get-MIRPackageOutputPaths -RepoRoot $repo)
$migrationPaths = @($migration.path_map | ForEach-Object { [string]$_.final_path }) + @($migration.compatibility_entrypoints | ForEach-Object { [string]$_.path })
foreach ($path in @($migrationPaths + @($authority.visible_roots | ForEach-Object { ([string]$_.path) + '/.mir-root.json' }) | Sort-Object -Unique)) {
  Assert-MIR4RepositoryMigrationV1 ($path -notin $packageFiles) 'mir4-repository-migration-package-visible' $path
}
$currentPackageSourceSha256 = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
Assert-MIR4RepositoryMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $currentPackageSourceSha256) 'mir4-repository-migration-package-fingerprint'
$f2eReceipt = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'releases/migrations/MIR4-M41-F2E-Package-Authority-CutoverV1.json'
$f2ePackageSourceSha256=[string]$f2eReceipt.verification.package_source_sha256
if($currentPackageSourceSha256-cne$f2ePackageSourceSha256){
  $m4202Path='releases/migrations/MIR4-M42-02-Compilation-Plan-DecompositionV1.json'
  $m4202SchemaPath='contracts/repository/mir4-m42-02-compilation-plan-decomposition-v1.schema.json'
  $m4202Raw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202Path)
  Assert-MIR4RepositoryMigrationV1 ($m4202Raw|Test-Json -SchemaFile (Join-Path $repo $m4202SchemaPath)) 'mir4-repository-migration-m42-02-successor-schema'
  $m4202=$m4202Raw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202) 'mir4-repository-migration-m42-02-successor-record'
  Assert-MIR4RepositoryMigrationV1 ([string]$m4202.predecessor.package_source_sha256-ceq$f2ePackageSourceSha256) 'mir4-repository-migration-m42-02-successor-predecessor-fingerprint'
  Assert-MIR4RepositoryMigrationV1 ([string]$m4202.status-ceq'M42-02-L1-COMPILATION-PLAN-DECOMPOSED'-and[string]$m4202.responsibility-ceq'compilation-plan') 'mir4-repository-migration-m42-02-successor-scope'
  Assert-MIR4RepositoryMigrationV1 (@($m4202.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-release-firewall'
  $m4202L2Path='releases/migrations/MIR4-M42-02-Base-Continuations-DecompositionV1.json'
  if(Test-Path -LiteralPath (Join-Path $repo $m4202L2Path) -PathType Leaf){
    $m4202L2SchemaPath='contracts/repository/mir4-m42-02-base-continuations-decomposition-v1.schema.json'
    $m4202L2Raw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202L2Path)
    Assert-MIR4RepositoryMigrationV1 ($m4202L2Raw|Test-Json -SchemaFile (Join-Path $repo $m4202L2SchemaPath)) 'mir4-repository-migration-m42-02-l2-successor-schema'
    $m4202L2=$m4202L2Raw|ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202L2) 'mir4-repository-migration-m42-02-l2-successor-record'
    Assert-MIR4RepositoryMigrationV1 ([string]$m4202L2.predecessor.package_source_sha256-ceq[string]$m4202.package_authority.package_source_sha256-and[string]$m4202L2.package_authority.package_source_sha256-ceq$currentPackageSourceSha256) 'mir4-repository-migration-m42-02-l2-successor-fingerprint'
    Assert-MIR4RepositoryMigrationV1 ([string]$m4202L2.status-ceq'M42-02-L2-BASE-CONTINUATIONS-DECOMPOSED'-and[string]$m4202L2.responsibility-ceq'base-continuations') 'mir4-repository-migration-m42-02-l2-successor-scope'
    Assert-MIR4RepositoryMigrationV1 (@($m4202L2.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-l2-release-firewall'
  }else{
    Assert-MIR4RepositoryMigrationV1 ([string]$m4202.package_authority.package_source_sha256-ceq$currentPackageSourceSha256) 'mir4-repository-migration-m42-02-current-successor'
  }
}
Assert-MIR4RepositoryMigrationV1 ([string]$receipt.package_source_sha256 -ceq 'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E') 'mir4-repository-migration-historical-package-fingerprint'

$receiptDigest = Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:repository-migration-receipt:1' -OmitTopLevelDigest
Assert-MIR4RepositoryMigrationV1 ([string]$receipt.digest -ceq $receiptDigest) 'mir4-repository-migration-receipt-digest'
Assert-MIR4RepositoryMigrationV1 ((Get-MIR4RepositoryFileSha256V1 -Path (Join-Path $repo $script:MIR4RepositoryMigrationReceiptPath)) -ceq $script:MIR4RepositoryMigrationReceiptSha256) 'mir4-repository-migration-receipt-immutable-bytes'
Assert-MIR4RepositoryMigrationV1 (@($receipt.release_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-repository-migration-release-firewall'
Assert-MIR4RepositoryMigrationV1 ([string]$receipt.sunset.state -ceq 'deferred-compatibility-readers-retained') 'mir4-repository-migration-sunset-boundary'
foreach ($component in @($receipt.components)) {
  Assert-MIR4RepositoryMigrationV1 ([string]$component.hash_mode -ceq 'canonical-text-v1') 'mir4-repository-migration-component-hash-mode' ([string]$component.path)
}
Test-MIR4PreFreezeAuthorities -RepoRoot $repo | Out-Null
$latestAuthorityState = Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration
Assert-MIR4RepositoryMigrationV1 ([string]$latestAuthorityState.prior_receipt_path -ceq 'releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json') 'mir4-repository-migration-prefreeze-chain'

function Invoke-MIR4RepositoryCommandProbeV1 {
  param([Parameter(Mandatory)][string]$Path)
  $output = (& pwsh -NoProfile -File (Join-Path $repo $Path) -Command inventory -RepoRoot $repo 2>&1 | Out-String).Trim()
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) { throw "[mir4-repository-migration-command-probe] $Path $output" }
  return $output | ConvertFrom-Json -Depth 100
}

$canonicalResult = Invoke-MIR4RepositoryCommandProbeV1 -Path 'tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1'
$compatibilityResult = Invoke-MIR4RepositoryCommandProbeV1 -Path 'tools/commands/mir4/Invoke-MIR4RepositoryFixedPoint.ps1'
$canonicalResultJson = ConvertTo-MIR4CanonicalJsonV1 -Value $canonicalResult
$compatibilityResultJson = ConvertTo-MIR4CanonicalJsonV1 -Value $compatibilityResult
Assert-MIR4RepositoryMigrationV1 ($canonicalResultJson -ceq $compatibilityResultJson) 'mir4-repository-migration-command-parity'

$facadeOutput = (& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 repository inventory 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "[mir4-repository-migration-facade-probe] $facadeOutput" }
$facadeResultJson = ConvertTo-MIR4CanonicalJsonV1 -Value ($facadeOutput | ConvertFrom-Json -Depth 100)
Assert-MIR4RepositoryMigrationV1 ($canonicalResultJson -ceq $facadeResultJson) 'mir4-repository-migration-facade-parity'

[pscustomobject][ordered]@{
  status='passed'
  migration_id=[string]$migration.migration_id
  canonical_writer=[string]$migration.writers[0].path
  active_roots=$actualActive
  compatibility_entrypoints=@($migration.compatibility_entrypoints | ForEach-Object { [string]$_.path })
  receipt_digest=[string]$receipt.digest
  package_source_sha256=[string]$receipt.package_source_sha256
  current_package_source_sha256=$currentPackageSourceSha256
  package_visible_delta=@($receipt.package_visible_delta)
  release_transition_authority=$false
}
