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
    Assert-MIR4RepositoryMigrationV1 ([string]$m4202L2.predecessor.package_source_sha256-ceq[string]$m4202.package_authority.package_source_sha256) 'mir4-repository-migration-m42-02-l2-successor-predecessor-fingerprint'
    Assert-MIR4RepositoryMigrationV1 ([string]$m4202L2.status-ceq'M42-02-L2-BASE-CONTINUATIONS-DECOMPOSED'-and[string]$m4202L2.responsibility-ceq'base-continuations') 'mir4-repository-migration-m42-02-l2-successor-scope'
    Assert-MIR4RepositoryMigrationV1 (@($m4202L2.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-l2-release-firewall'
    $m4202L3Path='releases/migrations/MIR4-M42-02-Stream-Compiler-DecompositionV1.json'
    if(Test-Path -LiteralPath (Join-Path $repo $m4202L3Path) -PathType Leaf){
      $m4202L3SchemaPath='contracts/repository/mir4-m42-02-stream-compiler-decomposition-v1.schema.json'
      $m4202L3Raw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202L3Path)
      Assert-MIR4RepositoryMigrationV1 ($m4202L3Raw|Test-Json -SchemaFile (Join-Path $repo $m4202L3SchemaPath)) 'mir4-repository-migration-m42-02-l3-successor-schema'
      $m4202L3=$m4202L3Raw|ConvertFrom-Json -Depth 100 -DateKind String
      Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202L3) 'mir4-repository-migration-m42-02-l3-successor-record'
      Assert-MIR4RepositoryMigrationV1 ([string]$m4202L3.predecessor.package_source_sha256-ceq[string]$m4202L2.package_authority.package_source_sha256) 'mir4-repository-migration-m42-02-l3-successor-fingerprint'
      Assert-MIR4RepositoryMigrationV1 ([string]$m4202L3.status-ceq'M42-02-L3-STREAM-COMPILER-DECOMPOSED'-and[string]$m4202L3.responsibility-ceq'stream-compiler') 'mir4-repository-migration-m42-02-l3-successor-scope'
      Assert-MIR4RepositoryMigrationV1 (@($m4202L3.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-l3-release-firewall'
      $m4202L4Path='releases/migrations/MIR4-M42-02-Technology-Catalog-DecompositionV1.json'
      if(Test-Path -LiteralPath (Join-Path $repo $m4202L4Path) -PathType Leaf){
        $m4202L4SchemaPath='contracts/repository/mir4-m42-02-technology-catalog-decomposition-v1.schema.json'
        $m4202L4Raw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202L4Path)
        Assert-MIR4RepositoryMigrationV1 ($m4202L4Raw|Test-Json -SchemaFile (Join-Path $repo $m4202L4SchemaPath)) 'mir4-repository-migration-m42-02-l4-successor-schema'
        $m4202L4=$m4202L4Raw|ConvertFrom-Json -Depth 100 -DateKind String
        Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202L4) 'mir4-repository-migration-m42-02-l4-successor-record'
        $m4202L5Path='releases/migrations/MIR4-M42-02-Effect-Ownership-DecompositionV1.json'
        $m4202L5Exists=Test-Path -LiteralPath (Join-Path $repo $m4202L5Path) -PathType Leaf
        if($m4202L5Exists){
          Assert-MIR4RepositoryMigrationV1 ([string]$m4202L4.predecessor.package_source_sha256-ceq[string]$m4202L3.package_authority.package_source_sha256) 'mir4-repository-migration-m42-02-l4-predecessor-fingerprint'
        }else{
          Assert-MIR4RepositoryMigrationV1 ([string]$m4202L4.predecessor.package_source_sha256-ceq[string]$m4202L3.package_authority.package_source_sha256-and[string]$m4202L4.package_authority.package_source_sha256-ceq$currentPackageSourceSha256) 'mir4-repository-migration-m42-02-l4-successor-fingerprint'
        }
        Assert-MIR4RepositoryMigrationV1 ([string]$m4202L4.status-ceq'M42-02-L4-TECHNOLOGY-CATALOG-DECOMPOSED'-and[string]$m4202L4.responsibility-ceq'technology-catalog') 'mir4-repository-migration-m42-02-l4-successor-scope'
        Assert-MIR4RepositoryMigrationV1 (@($m4202L4.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-l4-release-firewall'
        if($m4202L5Exists){
          $m4202L5SchemaPath='contracts/repository/mir4-m42-02-effect-ownership-decomposition-v1.schema.json'
          $m4202L5Raw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202L5Path)
          Assert-MIR4RepositoryMigrationV1 ($m4202L5Raw|Test-Json -SchemaFile (Join-Path $repo $m4202L5SchemaPath)) 'mir4-repository-migration-m42-02-l5-successor-schema'
          $m4202L5=$m4202L5Raw|ConvertFrom-Json -Depth 100 -DateKind String
          Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202L5) 'mir4-repository-migration-m42-02-l5-successor-record'
          Assert-MIR4RepositoryMigrationV1 ([string]$m4202L5.predecessor.package_source_sha256-ceq[string]$m4202L4.package_authority.package_source_sha256) 'mir4-repository-migration-m42-02-l5-predecessor-fingerprint'
          Assert-MIR4RepositoryMigrationV1 ([string]$m4202L5.status-ceq'M42-02-L5-EFFECT-OWNERSHIP-DECOMPOSED'-and[string]$m4202L5.responsibility-ceq'effect-ownership') 'mir4-repository-migration-m42-02-l5-successor-scope'
          Assert-MIR4RepositoryMigrationV1 (@($m4202L5.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-l5-release-firewall'
          $m4202L6Path='releases/migrations/MIR4-M42-02-Compiler-Orchestrator-DecompositionV1.json'
          if(Test-Path -LiteralPath (Join-Path $repo $m4202L6Path) -PathType Leaf){
            $m4202L6SchemaPath='contracts/repository/mir4-m42-02-compiler-orchestrator-decomposition-v1.schema.json'
            $m4202L6Raw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202L6Path)
            Assert-MIR4RepositoryMigrationV1 ($m4202L6Raw|Test-Json -SchemaFile (Join-Path $repo $m4202L6SchemaPath)) 'mir4-repository-migration-m42-02-l6-successor-schema'
            $m4202L6=$m4202L6Raw|ConvertFrom-Json -Depth 100 -DateKind String
            Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202L6) 'mir4-repository-migration-m42-02-l6-successor-record'
            Assert-MIR4RepositoryMigrationV1 ([string]$m4202L6.predecessor.package_source_sha256-ceq[string]$m4202L5.package_authority.package_source_sha256-and[string]$m4202L6.package_authority.package_source_sha256-ceq$currentPackageSourceSha256) 'mir4-repository-migration-m42-02-l6-successor-fingerprint'
            Assert-MIR4RepositoryMigrationV1 ([string]$m4202L6.status-ceq'M42-02-L6-COMPILER-ORCHESTRATOR-DECOMPOSED'-and[string]$m4202L6.responsibility-ceq'compiler-orchestrator') 'mir4-repository-migration-m42-02-l6-successor-scope'
            Assert-MIR4RepositoryMigrationV1 (@($m4202L6.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-l6-release-firewall'
            $m4202PowerShellPath='releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
            if(Test-Path -LiteralPath (Join-Path $repo $m4202PowerShellPath) -PathType Leaf){
              $m4202PowerShellSchemaPath='contracts/repository/mir4-m42-02-powershell-characterization-v1.schema.json'
              $m4202PowerShellRaw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202PowerShellPath)
              Assert-MIR4RepositoryMigrationV1 ($m4202PowerShellRaw|Test-Json -SchemaFile (Join-Path $repo $m4202PowerShellSchemaPath)) 'mir4-repository-migration-m42-02-powershell-characterization-schema'
              $m4202PowerShell=$m4202PowerShellRaw|ConvertFrom-Json -Depth 100 -DateKind String
              Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202PowerShell) 'mir4-repository-migration-m42-02-powershell-characterization-record'
              Assert-MIR4RepositoryMigrationV1 ((Get-MIR4RepositoryFileSha256V1 -Path (Join-Path $repo $m4202L6Path))-ceq[string]$m4202PowerShell.predecessor.receipt_sha256-and[string]$m4202PowerShell.predecessor.record_sha256-ceq[string]$m4202L6.record_sha256) 'mir4-repository-migration-m42-02-powershell-characterization-predecessor'
              Assert-MIR4RepositoryMigrationV1 ([string]$m4202PowerShell.status-ceq'M42-02-RESIDUAL-POWERSHELL-CHARACTERIZED'-and[string]$m4202PowerShell.next_fixed_point-ceq'M42-02-PS1-COMMAND-ROUTER') 'mir4-repository-migration-m42-02-powershell-characterization-scope'
              Assert-MIR4RepositoryMigrationV1 ([string]$m4202PowerShell.preservation.package_source_sha256-ceq$currentPackageSourceSha256-and@($m4202PowerShell.preservation.package_visible_delta).Count-eq0) 'mir4-repository-migration-m42-02-powershell-characterization-package-firewall'
              Assert-MIR4RepositoryMigrationV1 (@($m4202PowerShell.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-powershell-characterization-release-firewall'
              $m4202CommandRouterPath='releases/migrations/MIR4-M42-02-PowerShell-Command-Router-DecompositionV1.json'
              if(Test-Path -LiteralPath (Join-Path $repo $m4202CommandRouterPath) -PathType Leaf){
                $m4202CommandRouterSchemaPath='contracts/repository/mir4-m42-02-powershell-command-router-decomposition-v1.schema.json'
                $m4202CommandRouterRaw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202CommandRouterPath)
                Assert-MIR4RepositoryMigrationV1 ($m4202CommandRouterRaw|Test-Json -SchemaFile (Join-Path $repo $m4202CommandRouterSchemaPath)) 'mir4-repository-migration-m42-02-command-router-schema'
                $m4202CommandRouter=$m4202CommandRouterRaw|ConvertFrom-Json -Depth 100 -DateKind String
                Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202CommandRouter) 'mir4-repository-migration-m42-02-command-router-record'
                Assert-MIR4RepositoryMigrationV1 ((Get-MIR4RepositoryFileSha256V1 -Path (Join-Path $repo $m4202PowerShellPath))-ceq[string]$m4202CommandRouter.predecessor.receipt_sha256-and[string]$m4202CommandRouter.predecessor.record_sha256-ceq[string]$m4202PowerShell.record_sha256) 'mir4-repository-migration-m42-02-command-router-predecessor'
                Assert-MIR4RepositoryMigrationV1 ([string]$m4202CommandRouter.status-ceq'M42-02-PS1-COMMAND-ROUTER-DECOMPOSED'-and[string]$m4202CommandRouter.decomposition.responsibility-ceq'command-router'-and[string]$m4202CommandRouter.next_fixed_point-ceq'M42-02-PS2-VALIDATION-RUNNER') 'mir4-repository-migration-m42-02-command-router-scope'
                Assert-MIR4RepositoryMigrationV1 ([bool]$m4202CommandRouter.public_contract.unchanged-and[int]$m4202CommandRouter.public_contract.command_count-eq85-and@($m4202CommandRouter.decomposition.modules).Count-eq12) 'mir4-repository-migration-m42-02-command-router-contract'
                Assert-MIR4RepositoryMigrationV1 ([string]$m4202CommandRouter.preservation.package_source_sha256-ceq$currentPackageSourceSha256-and@($m4202CommandRouter.preservation.package_visible_delta).Count-eq0) 'mir4-repository-migration-m42-02-command-router-package-firewall'
                Assert-MIR4RepositoryMigrationV1 (@($m4202CommandRouter.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-command-router-release-firewall'
                $m4202ValidationRunnerPath='releases/migrations/MIR4-M42-02-Validation-Runner-DecompositionV1.json'
                if(Test-Path -LiteralPath (Join-Path $repo $m4202ValidationRunnerPath) -PathType Leaf){
                  $m4202ValidationRunnerRaw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202ValidationRunnerPath)
                  Assert-MIR4RepositoryMigrationV1 ($m4202ValidationRunnerRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-validation-runner-decomposition-v1.schema.json')) 'mir4-repository-migration-m42-02-validation-runner-schema'
                  $m4202ValidationRunner=$m4202ValidationRunnerRaw|ConvertFrom-Json -Depth 100 -DateKind String
                  Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202ValidationRunner) 'mir4-repository-migration-m42-02-validation-runner-record'
                  Assert-MIR4RepositoryMigrationV1 ((Get-MIR4RepositoryFileSha256V1 -Path (Join-Path $repo $m4202CommandRouterPath))-ceq[string]$m4202ValidationRunner.predecessor.receipt_sha256-and[string]$m4202ValidationRunner.predecessor.record_sha256-ceq[string]$m4202CommandRouter.record_sha256) 'mir4-repository-migration-m42-02-validation-runner-predecessor'
                  Assert-MIR4RepositoryMigrationV1 ([string]$m4202ValidationRunner.status-ceq'M42-02-PS2-VALIDATION-RUNNER-DECOMPOSED'-and[string]$m4202ValidationRunner.decomposition.responsibility-ceq'validation-runner'-and[string]$m4202ValidationRunner.next_fixed_point-ceq'M42-02-PS3-ASSURANCE-EVIDENCE') 'mir4-repository-migration-m42-02-validation-runner-scope'
                  Assert-MIR4RepositoryMigrationV1 ([bool]$m4202ValidationRunner.public_contract.unchanged-and@($m4202ValidationRunner.decomposition.modules).Count-eq21-and[bool]$m4202ValidationRunner.semantic_contract.source_segments_exact) 'mir4-repository-migration-m42-02-validation-runner-contract'
                  Assert-MIR4RepositoryMigrationV1 ([string]$m4202ValidationRunner.preservation.package_source_sha256-ceq$currentPackageSourceSha256-and@($m4202ValidationRunner.preservation.package_visible_delta).Count-eq0) 'mir4-repository-migration-m42-02-validation-runner-package-firewall'
                  Assert-MIR4RepositoryMigrationV1 (@($m4202ValidationRunner.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-validation-runner-release-firewall'
                  $m4202AssuranceEvidencePath='releases/migrations/MIR4-M42-02-Assurance-Evidence-DecompositionV1.json'
                  if(Test-Path -LiteralPath (Join-Path $repo $m4202AssuranceEvidencePath) -PathType Leaf){
                    $m4202AssuranceEvidenceRaw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202AssuranceEvidencePath)
                    Assert-MIR4RepositoryMigrationV1 ($m4202AssuranceEvidenceRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-assurance-evidence-decomposition-v1.schema.json')) 'mir4-repository-migration-m42-02-assurance-evidence-schema'
                    $m4202AssuranceEvidence=$m4202AssuranceEvidenceRaw|ConvertFrom-Json -Depth 100 -DateKind String
                    Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202AssuranceEvidence) 'mir4-repository-migration-m42-02-assurance-evidence-record'
                    Assert-MIR4RepositoryMigrationV1 ((Get-MIR4RepositoryFileSha256V1 -Path (Join-Path $repo $m4202ValidationRunnerPath))-ceq[string]$m4202AssuranceEvidence.predecessor.receipt_sha256-and[string]$m4202AssuranceEvidence.predecessor.record_sha256-ceq[string]$m4202ValidationRunner.record_sha256) 'mir4-repository-migration-m42-02-assurance-evidence-predecessor'
                    Assert-MIR4RepositoryMigrationV1 ([string]$m4202AssuranceEvidence.status-ceq'M42-02-PS3-ASSURANCE-EVIDENCE-DECOMPOSED'-and[string]$m4202AssuranceEvidence.decomposition.responsibility-ceq'assurance-evidence'-and[string]$m4202AssuranceEvidence.next_fixed_point-ceq'M42-02-PS4-PRE-FREEZE-RELEASE') 'mir4-repository-migration-m42-02-assurance-evidence-scope'
                    Assert-MIR4RepositoryMigrationV1 ([bool]$m4202AssuranceEvidence.public_contract.unchanged-and[int]$m4202AssuranceEvidence.public_contract.function_count-eq62-and@($m4202AssuranceEvidence.decomposition.modules).Count-eq9-and[bool]$m4202AssuranceEvidence.semantic_contract.source_segments_exact) 'mir4-repository-migration-m42-02-assurance-evidence-contract'
                    Assert-MIR4RepositoryMigrationV1 ([string]$m4202AssuranceEvidence.preservation.package_source_sha256-ceq$currentPackageSourceSha256-and@($m4202AssuranceEvidence.preservation.package_visible_delta).Count-eq0) 'mir4-repository-migration-m42-02-assurance-evidence-package-firewall'
                    Assert-MIR4RepositoryMigrationV1 (@($m4202AssuranceEvidence.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-assurance-evidence-release-firewall'
                    $m4202PreFreezeReleasePath='releases/migrations/MIR4-M42-02-Pre-Freeze-Release-DecompositionV1.json'
                    if(Test-Path -LiteralPath (Join-Path $repo $m4202PreFreezeReleasePath) -PathType Leaf){
                      $m4202PreFreezeReleaseRaw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202PreFreezeReleasePath)
                      Assert-MIR4RepositoryMigrationV1 ($m4202PreFreezeReleaseRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-pre-freeze-release-decomposition-v1.schema.json')) 'mir4-repository-migration-m42-02-pre-freeze-release-schema'
                      $m4202PreFreezeRelease=$m4202PreFreezeReleaseRaw|ConvertFrom-Json -Depth 100 -DateKind String
                      Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202PreFreezeRelease) 'mir4-repository-migration-m42-02-pre-freeze-release-record'
                      Assert-MIR4RepositoryMigrationV1 ((Get-MIR4RepositoryFileSha256V1 -Path (Join-Path $repo $m4202AssuranceEvidencePath))-ceq[string]$m4202PreFreezeRelease.predecessor.receipt_sha256-and[string]$m4202PreFreezeRelease.predecessor.record_sha256-ceq[string]$m4202AssuranceEvidence.record_sha256) 'mir4-repository-migration-m42-02-pre-freeze-release-predecessor'
                      Assert-MIR4RepositoryMigrationV1 ([string]$m4202PreFreezeRelease.status-ceq'M42-02-PS4-PRE-FREEZE-RELEASE-DECOMPOSED'-and[string]$m4202PreFreezeRelease.decomposition.responsibility-ceq'pre-freeze-release'-and[string]$m4202PreFreezeRelease.next_fixed_point-ceq'M42-02-PS5-BOOTSTRAP-MATERIALIZATION') 'mir4-repository-migration-m42-02-pre-freeze-release-scope'
                      Assert-MIR4RepositoryMigrationV1 ([bool]$m4202PreFreezeRelease.public_contract.unchanged-and[int]$m4202PreFreezeRelease.public_contract.function_count-eq25-and@($m4202PreFreezeRelease.decomposition.modules).Count-eq6-and[bool]$m4202PreFreezeRelease.semantic_contract.source_segments_exact_except_declared_self_successor) 'mir4-repository-migration-m42-02-pre-freeze-release-contract'
                      Assert-MIR4RepositoryMigrationV1 ([string]$m4202PreFreezeRelease.preservation.package_source_sha256-ceq$currentPackageSourceSha256-and@($m4202PreFreezeRelease.preservation.package_visible_delta).Count-eq0) 'mir4-repository-migration-m42-02-pre-freeze-release-package-firewall'
                      Assert-MIR4RepositoryMigrationV1 (@($m4202PreFreezeRelease.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-pre-freeze-release-release-firewall'
                      $m4202BootstrapMaterializationPath='releases/migrations/MIR4-M42-02-Bootstrap-Materialization-DecompositionV1.json'
                      if(Test-Path -LiteralPath (Join-Path $repo $m4202BootstrapMaterializationPath) -PathType Leaf){
                        $m4202BootstrapMaterializationRaw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202BootstrapMaterializationPath)
                        Assert-MIR4RepositoryMigrationV1 ($m4202BootstrapMaterializationRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-bootstrap-materialization-decomposition-v1.schema.json')) 'mir4-repository-migration-m42-02-bootstrap-materialization-schema'
                        $m4202BootstrapMaterialization=$m4202BootstrapMaterializationRaw|ConvertFrom-Json -Depth 100 -DateKind String
                        Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202BootstrapMaterialization) 'mir4-repository-migration-m42-02-bootstrap-materialization-record'
                        Assert-MIR4RepositoryMigrationV1 ((Get-MIR4RepositoryFileSha256V1 -Path (Join-Path $repo $m4202PreFreezeReleasePath))-ceq[string]$m4202BootstrapMaterialization.predecessor.receipt_sha256-and[string]$m4202BootstrapMaterialization.predecessor.record_sha256-ceq[string]$m4202PreFreezeRelease.record_sha256) 'mir4-repository-migration-m42-02-bootstrap-materialization-predecessor'
                        Assert-MIR4RepositoryMigrationV1 ([string]$m4202BootstrapMaterialization.status-ceq'M42-02-PS5-BOOTSTRAP-MATERIALIZATION-DECOMPOSED'-and[string]$m4202BootstrapMaterialization.decomposition.responsibility-ceq'bootstrap-materialization'-and[string]$m4202BootstrapMaterialization.next_fixed_point-ceq'M42-02-PS6-ASSURANCE-RELEASE') 'mir4-repository-migration-m42-02-bootstrap-materialization-scope'
                        Assert-MIR4RepositoryMigrationV1 ([bool]$m4202BootstrapMaterialization.public_contract.unchanged-and[int]$m4202BootstrapMaterialization.public_contract.function_count-eq51-and@($m4202BootstrapMaterialization.decomposition.modules).Count-eq6-and[bool]$m4202BootstrapMaterialization.semantic_contract.source_segments_exact) 'mir4-repository-migration-m42-02-bootstrap-materialization-contract'
                        Assert-MIR4RepositoryMigrationV1 ([string]$m4202BootstrapMaterialization.preservation.package_source_sha256-ceq$currentPackageSourceSha256-and@($m4202BootstrapMaterialization.preservation.package_visible_delta).Count-eq0) 'mir4-repository-migration-m42-02-bootstrap-materialization-package-firewall'
                        Assert-MIR4RepositoryMigrationV1 (@($m4202BootstrapMaterialization.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-bootstrap-materialization-release-firewall'
                        $m4202AssuranceReleasePath='releases/migrations/MIR4-M42-02-Assurance-Release-DecompositionV1.json'
                        if(Test-Path -LiteralPath (Join-Path $repo $m4202AssuranceReleasePath) -PathType Leaf){
                          $m4202AssuranceReleaseRaw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202AssuranceReleasePath)
                          Assert-MIR4RepositoryMigrationV1 ($m4202AssuranceReleaseRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-assurance-release-decomposition-v1.schema.json')) 'mir4-repository-migration-m42-02-assurance-release-schema'
                          $m4202AssuranceRelease=$m4202AssuranceReleaseRaw|ConvertFrom-Json -Depth 100 -DateKind String
                          Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202AssuranceRelease) 'mir4-repository-migration-m42-02-assurance-release-record'
                          Assert-MIR4RepositoryMigrationV1 ((Get-MIR4RepositoryFileSha256V1 -Path (Join-Path $repo $m4202BootstrapMaterializationPath))-ceq[string]$m4202AssuranceRelease.predecessor.receipt_sha256-and[string]$m4202AssuranceRelease.predecessor.record_sha256-ceq[string]$m4202BootstrapMaterialization.record_sha256) 'mir4-repository-migration-m42-02-assurance-release-predecessor'
                          Assert-MIR4RepositoryMigrationV1 ([string]$m4202AssuranceRelease.status-ceq'M42-02-PS6-ASSURANCE-RELEASE-DECOMPOSED'-and[string]$m4202AssuranceRelease.decomposition.responsibility-ceq'assurance-release'-and[string]$m4202AssuranceRelease.next_fixed_point-ceq'M42-02-PS7-COMPATIBILITY-AUDIT') 'mir4-repository-migration-m42-02-assurance-release-scope'
                          Assert-MIR4RepositoryMigrationV1 ([bool]$m4202AssuranceRelease.public_contract.unchanged-and[int]$m4202AssuranceRelease.public_contract.function_count-eq11-and@($m4202AssuranceRelease.decomposition.modules).Count-eq4-and[string]$m4202AssuranceRelease.decomposition.self_test.authority-ceq'canonical-executable-test-support'-and[bool]$m4202AssuranceRelease.semantic_contract.embedded_self_test_removed_from_release_authority) 'mir4-repository-migration-m42-02-assurance-release-contract'
                          Assert-MIR4RepositoryMigrationV1 ([string]$m4202AssuranceRelease.preservation.package_source_sha256-ceq$currentPackageSourceSha256-and@($m4202AssuranceRelease.preservation.package_visible_delta).Count-eq0) 'mir4-repository-migration-m42-02-assurance-release-package-firewall'
                          Assert-MIR4RepositoryMigrationV1 (@($m4202AssuranceRelease.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-assurance-release-release-firewall'
                          $m4202CompatibilityAuditPath='releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json'
                          if(Test-Path -LiteralPath (Join-Path $repo $m4202CompatibilityAuditPath) -PathType Leaf){
                            $m4202CompatibilityAuditRaw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202CompatibilityAuditPath)
                            Assert-MIR4RepositoryMigrationV1 ($m4202CompatibilityAuditRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-compatibility-audit-decomposition-v1.schema.json')) 'mir4-repository-migration-m42-02-compatibility-audit-schema'
                            $m4202CompatibilityAudit=$m4202CompatibilityAuditRaw|ConvertFrom-Json -Depth 100 -DateKind String
                            Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202CompatibilityAudit) 'mir4-repository-migration-m42-02-compatibility-audit-record'
                            Assert-MIR4RepositoryMigrationV1 ((Get-MIR4RepositoryFileSha256V1 -Path (Join-Path $repo $m4202AssuranceReleasePath))-ceq[string]$m4202CompatibilityAudit.predecessor.receipt_sha256-and[string]$m4202CompatibilityAudit.predecessor.record_sha256-ceq[string]$m4202AssuranceRelease.record_sha256) 'mir4-repository-migration-m42-02-compatibility-audit-predecessor'
                            Assert-MIR4RepositoryMigrationV1 ([string]$m4202CompatibilityAudit.status-ceq'M42-02-PS7-COMPATIBILITY-AUDIT-DECOMPOSED'-and[string]$m4202CompatibilityAudit.decomposition.responsibility-ceq'compatibility-audit'-and[string]$m4202CompatibilityAudit.next_fixed_point-ceq'M42-02-PS8-OFFLINE-CUSTODY') 'mir4-repository-migration-m42-02-compatibility-audit-scope'
                            Assert-MIR4RepositoryMigrationV1 ([bool]$m4202CompatibilityAudit.public_contract.unchanged-and[int]$m4202CompatibilityAudit.public_contract.function_count-eq35-and@($m4202CompatibilityAudit.decomposition.modules).Count-eq6-and[bool]$m4202CompatibilityAudit.semantic_contract.compatibility_claims_unchanged-and[bool]$m4202CompatibilityAudit.semantic_contract.stream_authority_unchanged) 'mir4-repository-migration-m42-02-compatibility-audit-contract'
                            Assert-MIR4RepositoryMigrationV1 ([string]$m4202CompatibilityAudit.preservation.package_source_sha256-ceq$currentPackageSourceSha256-and@($m4202CompatibilityAudit.preservation.package_visible_delta).Count-eq0) 'mir4-repository-migration-m42-02-compatibility-audit-package-firewall'
                            Assert-MIR4RepositoryMigrationV1 (@($m4202CompatibilityAudit.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-compatibility-audit-release-firewall'
                            $m4202OfflineCustodyPath='releases/migrations/MIR4-M42-02-Offline-Custody-DecompositionV1.json'
                            if(Test-Path -LiteralPath (Join-Path $repo $m4202OfflineCustodyPath) -PathType Leaf){
                              $m4202OfflineCustodyRaw=Get-Content -Raw -LiteralPath (Join-Path $repo $m4202OfflineCustodyPath)
                              Assert-MIR4RepositoryMigrationV1 ($m4202OfflineCustodyRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-offline-custody-decomposition-v1.schema.json')) 'mir4-repository-migration-m42-02-offline-custody-schema'
                              $m4202OfflineCustody=$m4202OfflineCustodyRaw|ConvertFrom-Json -Depth 100 -DateKind String
                              Assert-MIR4RepositoryMigrationV1 (Test-MIR4BootstrapRecordHash -Record $m4202OfflineCustody) 'mir4-repository-migration-m42-02-offline-custody-record'
                              Assert-MIR4RepositoryMigrationV1 ((Get-MIR4RepositoryFileSha256V1 -Path (Join-Path $repo $m4202CompatibilityAuditPath))-ceq[string]$m4202OfflineCustody.predecessor.receipt_sha256-and[string]$m4202OfflineCustody.predecessor.record_sha256-ceq[string]$m4202CompatibilityAudit.record_sha256) 'mir4-repository-migration-m42-02-offline-custody-predecessor'
                              Assert-MIR4RepositoryMigrationV1 ([string]$m4202OfflineCustody.status-ceq'M42-02-PS8-OFFLINE-CUSTODY-DECOMPOSED'-and[string]$m4202OfflineCustody.decomposition.responsibility-ceq'offline-custody'-and[string]$m4202OfflineCustody.next_fixed_point-ceq'M42-02-PS9-RELEASE-CAPSULE') 'mir4-repository-migration-m42-02-offline-custody-scope'
                              Assert-MIR4RepositoryMigrationV1 ([bool]$m4202OfflineCustody.public_contract.unchanged-and[int]$m4202OfflineCustody.public_contract.function_count-eq26-and@($m4202OfflineCustody.decomposition.modules).Count-eq8-and[bool]$m4202OfflineCustody.semantic_contract.ordered_source_slices_preserved_with_declared_substitutions-and[bool]$m4202OfflineCustody.semantic_contract.custody_admission_unchanged-and[bool]$m4202OfflineCustody.semantic_contract.historical_compatibility_check_explicit-and[bool]$m4202OfflineCustody.semantic_contract.signature_verification_unchanged-and[bool]$m4202OfflineCustody.semantic_contract.offline_restore_unchanged) 'mir4-repository-migration-m42-02-offline-custody-contract'
                              Assert-MIR4RepositoryMigrationV1 ([string]$m4202OfflineCustody.preservation.package_source_sha256-ceq$currentPackageSourceSha256-and@($m4202OfflineCustody.preservation.package_visible_delta).Count-eq0) 'mir4-repository-migration-m42-02-offline-custody-package-firewall'
                              Assert-MIR4RepositoryMigrationV1 (@($m4202OfflineCustody.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-repository-migration-m42-02-offline-custody-release-firewall'
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }else{
            Assert-MIR4RepositoryMigrationV1 ([string]$m4202L5.package_authority.package_source_sha256-ceq$currentPackageSourceSha256) 'mir4-repository-migration-m42-02-l5-successor-fingerprint'
          }
        }
      }else{
        Assert-MIR4RepositoryMigrationV1 ([string]$m4202L3.package_authority.package_source_sha256-ceq$currentPackageSourceSha256) 'mir4-repository-migration-m42-02-l3-current-successor'
      }
    }else{
      Assert-MIR4RepositoryMigrationV1 ([string]$m4202L2.package_authority.package_source_sha256-ceq$currentPackageSourceSha256) 'mir4-repository-migration-m42-02-l2-current-successor'
    }
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
