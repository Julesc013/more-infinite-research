param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryFixedPoint.ps1')
. (Join-Path $repo 'tools/mir/application/compiler/SemanticCompilerPolicyMigration.ps1')
. (Join-Path $repo 'tools/mir/application/runtime/RuntimeContinuityMigration.ps1')

function Assert-MIR4RuntimeContinuityMigrationV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$compatibilityBefore=(Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash
$runtimeAuthority=Get-MIR4RuntimeContinuityAuthority -RepoRoot $repo
$playerHashes=[ordered]@{}
foreach($path in @($runtimeAuthority.terminal_player_authority)){$playerHashes[[string]$path]=(Get-FileHash -LiteralPath (Join-Path $repo ([string]$path)) -Algorithm SHA256).Hash}

$predecessor=Invoke-MIR4SemanticCompilerPolicyMigrationProjectionV1 -RepoRoot $repo -Check
Assert-MIR4RuntimeContinuityMigrationV1 ([string]$predecessor.migration_id-ceq'MIR4-SEMANTIC-COMPILER-POLICY-TOOLING-V1') 'mir4-runtime-continuity-migration-predecessor-id'
Assert-MIR4RuntimeContinuityMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4RuntimeContinuityPredecessorReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4RuntimeContinuityPredecessorReceiptSha256) 'mir4-runtime-continuity-migration-predecessor-immutable'
try{Invoke-MIR4SemanticCompilerPolicyMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-runtime-continuity-migration-predecessor-write-enabled]'}
catch{if(-not$_.Exception.Message.StartsWith('[mir4-semantic-compiler-policy-migration-receipt-immutable]')){throw}}

$authority=Get-MIR4RuntimeContinuityMigrationAuthorityV1 -RepoRoot $repo
$proof=Get-MIR4RuntimeContinuityMigrationProofPolicyV1 -RepoRoot $repo
$receipt=Invoke-MIR4RuntimeContinuityMigrationProjectionV1 -RepoRoot $repo -Check
$inventory=Get-MIR4RepositoryInventory -RepoRoot $repo
Assert-MIR4RuntimeContinuityMigrationV1 ([int]$inventory.summary.unknown-eq0) 'mir4-runtime-continuity-migration-inventory-unknown'
Assert-MIR4RuntimeContinuityMigrationV1 (-not[bool]$inventory.deletion_authorized) 'mir4-runtime-continuity-migration-deletion-authority'
Assert-MIR4RuntimeContinuityMigrationV1 (@($authority.writers).Count-eq1) 'mir4-runtime-continuity-migration-writer-count'
Assert-MIR4RuntimeContinuityMigrationV1 ([string]$proof.test_id-ceq'static.mir4-runtime-continuity-migration-v1') 'mir4-runtime-continuity-migration-proof-test-id'
Assert-MIR4RuntimeContinuityMigrationV1 (Test-MIR4RuntimeContinuityCompatibilityForwardersV1 -RepoRoot $repo) 'mir4-runtime-continuity-migration-forwarders'
Assert-MIR4RuntimeContinuityMigrationV1 (Test-MIR4RuntimeContinuityDeclaredConsumersV1 -RepoRoot $repo) 'mir4-runtime-continuity-migration-consumers'
Assert-MIR4RuntimeContinuityMigrationV1 ([string](Test-MIR4RuntimeContinuityFunctionalParityV1 -RepoRoot $repo).digest-ceq$script:MIR4RuntimeContinuityParityDigestV1) 'mir4-runtime-continuity-migration-functional-parity'

$engineText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1'))
Assert-MIR4RuntimeContinuityMigrationV1 ($engineText-match'function Test-MIR4ImmutableMigrationReceiptV1'-and$engineText-match'function New-MIR4AppendOnlyAuthorityMigrationReceiptV1') 'mir4-runtime-continuity-migration-shared-engine'
$assurance=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json'
$migrationClass=@($assurance.classes|Where-Object{[string]$_.id-ceq'repository-migration'})
Assert-MIR4RuntimeContinuityMigrationV1 ($migrationClass.Count-eq1-and@($migrationClass[0].tests)-contains[string]$proof.test_id) 'mir4-runtime-continuity-migration-assurance-registration'
$catalog=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'validation/tests.yml'
Assert-MIR4RuntimeContinuityMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq'static.mir4-runtime-continuity-v1'-and[string]$_.command-ceq'./tests/runtime/Test-MIR4RuntimeContinuity.ps1'}).Count-eq1) 'mir4-runtime-continuity-migration-functional-registration'
Assert-MIR4RuntimeContinuityMigrationV1 (@($catalog.tests|Where-Object{[string]$_.id-ceq[string]$proof.test_id-and[string]$_.command-ceq'./tests/runtime/Test-MIR4RuntimeContinuityMigration.ps1'}).Count-eq1) 'mir4-runtime-continuity-migration-test-registration'

$migrationPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path})+@($authority.compatibility_entrypoints|ForEach-Object{[string]$_.path})
$packageFiles=@(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach($item in @($migrationPaths|Sort-Object -Unique)){
  Assert-MIR4RuntimeContinuityMigrationV1 (@($migrationClass[0].patterns|Where-Object{$item-match[string]$_}).Count-gt0) 'mir4-runtime-continuity-migration-assurance-path' $item
  Assert-MIR4RuntimeContinuityMigrationV1 ($item-notin$packageFiles) 'mir4-runtime-continuity-migration-package-visible' $item
}
Assert-MIR4RuntimeContinuityMigrationV1 ($packageBefore-ceq[string]$authority.package_source_sha256-and[string]$receipt.package_source_sha256-ceq$packageBefore-and@($receipt.package_visible_delta).Count-eq0) 'mir4-runtime-continuity-migration-package-firewall'
Assert-MIR4RuntimeContinuityMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-ceq$compatibilityBefore) 'mir4-runtime-continuity-migration-compatibility-policy'

$prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration
Assert-MIR4RuntimeContinuityMigrationV1 ([string]$receipt.predecessor_receipt.path-ceq[string]$prior.prior_receipt_path-and[string]$receipt.predecessor_receipt.sha256-ceq[string]$prior.prior_receipt_sha256) 'mir4-runtime-continuity-migration-predecessor-chain'
foreach($binding in @($receipt.evolved_bindings)){
  $item=[string]$binding.path
  Assert-MIR4RuntimeContinuityMigrationV1 ($prior.authority_hashes.ContainsKey($item)) 'mir4-runtime-continuity-migration-evolved-prior-missing' $item
  Assert-MIR4RuntimeContinuityMigrationV1 ([string]$binding.previous_sha256-ceq[string]$prior.authority_hashes[$item]) 'mir4-runtime-continuity-migration-evolved-prior-sha256' $item
  Assert-MIR4RuntimeContinuityMigrationV1 ([string]$binding.current_sha256-ceq(Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo $item) -Mode ([string]$binding.hash_mode))) 'mir4-runtime-continuity-migration-evolved-current-sha256' $item
  Assert-MIR4RuntimeContinuityMigrationV1 (-not[bool]$binding.package_visible-and-not[bool]$binding.release_authority) 'mir4-runtime-continuity-migration-evolved-firewall' $item
}
Assert-MIR4RuntimeContinuityMigrationV1 (@($receipt.current_authorities.path|Sort-Object -Unique).Count-eq@($receipt.current_authorities).Count) 'mir4-runtime-continuity-migration-current-authority-duplicate'
foreach($binding in @($receipt.current_authorities)){
  $actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$binding.path)) -Mode ([string]$binding.hash_mode)
  Assert-MIR4RuntimeContinuityMigrationV1 ([string]$binding.sha256-ceq$actual) 'mir4-runtime-continuity-migration-current-authority' ([string]$binding.path)
}
foreach($component in @($receipt.components)){
  Assert-MIR4RuntimeContinuityMigrationV1 ([string]$component.hash_mode-ceq'canonical-text-v1') 'mir4-runtime-continuity-migration-component-mode' ([string]$component.path)
  $actual=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $repo ([string]$component.path)) -Mode 'canonical-text-v1'
  Assert-MIR4RuntimeContinuityMigrationV1 ([string]$component.sha256-ceq$actual) 'mir4-runtime-continuity-migration-component-sha256' ([string]$component.path)
}
$digest=Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:runtime-continuity-migration-receipt:1' -OmitTopLevelDigest
Assert-MIR4RuntimeContinuityMigrationV1 ([string]$receipt.digest-ceq$digest) 'mir4-runtime-continuity-migration-receipt-digest'
foreach($field in @('transition_gate','release_transition_authority')){Assert-MIR4RuntimeContinuityMigrationV1 (@($receipt.$field.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-runtime-continuity-migration-release-firewall' $field}
Assert-MIR4RuntimeContinuityMigrationV1 ([string]$receipt.sunset.state-ceq'deferred-compatibility-readers-retained'-and@($receipt.sunset.compatibility_paths).Count-eq2) 'mir4-runtime-continuity-migration-sunset'

Test-MIR4PreFreezeAuthorities -RepoRoot $repo|Out-Null
$latest=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration
Assert-MIR4RuntimeContinuityMigrationV1 ([string]$latest.prior_receipt_path-ceq$script:MIR4RuntimeContinuityMigrationReceiptPath) 'mir4-runtime-continuity-migration-prefreeze-chain'
$releaseHistoryOutput=(& pwsh -NoProfile -File (Join-Path $repo 'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1') 2>&1|Out-String).Trim()
Assert-MIR4RuntimeContinuityMigrationV1 ($LASTEXITCODE-eq0-and$releaseHistoryOutput-match'append-only-runtime-continuity-successor') 'mir4-runtime-continuity-migration-release-history-successor' $releaseHistoryOutput

function Invoke-MIR4RuntimeContinuityMigrationCommandProbeV1 {
  param([Parameter(Mandatory)][ValidateSet('generate','check','show')][string]$Command)
  $output=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4RuntimeContinuityMigration.ps1') -Command $Command -RepoRoot $repo 2>&1|Out-String).Trim()
  if($LASTEXITCODE-ne0){throw "[mir4-runtime-continuity-migration-cli] $Command $output"}
  return $output|ConvertFrom-Json -Depth 100
}
$generateResult=Invoke-MIR4RuntimeContinuityMigrationCommandProbeV1 generate
$checkResult=Invoke-MIR4RuntimeContinuityMigrationCommandProbeV1 check
$showResult=Invoke-MIR4RuntimeContinuityMigrationCommandProbeV1 show
Assert-MIR4RuntimeContinuityMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $generateResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-and(ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 $showResult)) 'mir4-runtime-continuity-migration-cli-parity'
$facadeOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 runtime-continuity-migration check 2>&1|Out-String).Trim()
if($LASTEXITCODE-ne0){throw "[mir4-runtime-continuity-migration-facade] $facadeOutput"}
Assert-MIR4RuntimeContinuityMigrationV1 ((ConvertTo-MIR4CanonicalJsonV1 $checkResult)-ceq(ConvertTo-MIR4CanonicalJsonV1 ($facadeOutput|ConvertFrom-Json -Depth 100))) 'mir4-runtime-continuity-migration-facade-parity'

$canonicalOutput='build/mir4/test-runtime-continuity-canonical'
$compatibilityOutput='build/mir4/test-runtime-continuity-compatibility'
& (Join-Path $repo 'tools/mir/cli/Export-MIR4RuntimeContinuityRecords.ps1') -RepoRoot $repo -OutputRoot $canonicalOutput -CandidateZip ''|Out-Null
& (Join-Path $repo 'tools/commands/mir4/Export-MIR4RuntimeContinuityRecords.ps1') -RepoRoot $repo -OutputRoot $compatibilityOutput -CandidateZip ''|Out-Null
foreach($name in @('MIR4_RUNTIME_STATE_MATRIX.json','MIR4_MIGRATION_GRAPH_MATRIX.json','MIR4_CONTINUITY_BUNDLE.json')){
  $canonicalBytes=[IO.File]::ReadAllBytes((Join-Path $repo "$canonicalOutput/$name"));$compatibilityBytes=[IO.File]::ReadAllBytes((Join-Path $repo "$compatibilityOutput/$name"))
  Assert-MIR4RuntimeContinuityMigrationV1 ([Linq.Enumerable]::SequenceEqual([byte[]]$canonicalBytes,[byte[]]$compatibilityBytes)) 'mir4-runtime-continuity-migration-export-parity' $name
}

foreach($path in $playerHashes.Keys){Assert-MIR4RuntimeContinuityMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $path) -Algorithm SHA256).Hash-ceq[string]$playerHashes[$path]) 'mir4-runtime-continuity-migration-player-authority-mutation' $path}
Assert-MIR4RuntimeContinuityMigrationV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-runtime-continuity-migration-package-source-mutation'
Assert-MIR4RuntimeContinuityMigrationV1 ((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4RuntimeContinuityPredecessorReceiptPath) -Algorithm SHA256).Hash-ceq$script:MIR4RuntimeContinuityPredecessorReceiptSha256) 'mir4-runtime-continuity-migration-predecessor-mutated'

[pscustomobject][ordered]@{status='accepted';migration_id=[string]$receipt.migration_id;canonical_application='tools/mir/application/runtime/RuntimeStateModel.ps1';canonical_test='tests/runtime/Test-MIR4RuntimeContinuity.ps1';compatibility_entrypoints=@($authority.compatibility_entrypoints|ForEach-Object{[string]$_.path});predecessor_receipt_sha256=$script:MIR4RuntimeContinuityPredecessorReceiptSha256;receipt_digest=[string]$receipt.digest;package_source_sha256=[string]$receipt.package_source_sha256;package_visible_delta=@();release_transition_authority=$false}
