function Test-MIR4M4202PackageSourceSuccession {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$PredecessorSha256,
    [Parameter(Mandatory)][string]$CurrentSha256
  )

  try{
    . (Join-Path $RepoRoot 'tools/lib/mir4/PackagePresentation.ps1')
    $currentPresentation = Get-MIR4CurrentPackagePresentationV3 -RepoRoot $RepoRoot
    if ([string]$currentPresentation.package_source.fingerprint_sha256 -cne $CurrentSha256 -or
        (@($currentPresentation.package_source.roots) -join '|') -cne 'source|targets') { return $false }
    if($PredecessorSha256-ceq$CurrentSha256){return $true}

    $receiptPath=Join-Path $RepoRoot 'releases/migrations/MIR4-M41-Current-Product-Bridge-RetirementV1.json'
    $schemaPath=Join-Path $RepoRoot 'contracts/repository/mir4-m41-current-product-bridge-retirement-v1.schema.json'
    if(-not(Test-Path -LiteralPath $receiptPath -PathType Leaf)-or-not(Test-Path -LiteralPath $schemaPath -PathType Leaf)){return $false}
    $raw=Get-Content -Raw -LiteralPath $receiptPath
    if(-not($raw|Test-Json -SchemaFile $schemaPath)){return $false}
    $receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
    if(-not(Test-MIR4BootstrapRecordHash -Record $receipt)){return $false}
    $enabledGates=@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}|ForEach-Object{[string]$_.Name})
    $bridgeValid=(
      [string]$receipt.package_source.predecessor_sha256-ceq$PredecessorSha256-and
      @($receipt.package_visible_delta).Count-eq0-and
      $enabledGates.Count-eq1-and
      $enabledGates[0]-ceq'bridge_retirement'
    )
    if(-not$bridgeValid){return $false}
    if([string]$receipt.package_source.current_sha256-ceq$CurrentSha256){return $true}

    $sourceLayoutPath=Join-Path $RepoRoot 'assurance/repository/composable-source-layout-receipt-v1.json'
    $sourceLayoutSchemaPath=Join-Path $RepoRoot 'contracts/repository/mir4-composable-source-layout-migration-v1.schema.json'
    if((Test-Path -LiteralPath $sourceLayoutPath -PathType Leaf)-and(Test-Path -LiteralPath $sourceLayoutSchemaPath -PathType Leaf)){
      $sourceLayoutRaw=Get-Content -Raw -LiteralPath $sourceLayoutPath
      if(-not($sourceLayoutRaw|Test-Json -SchemaFile $sourceLayoutSchemaPath)){return $false}
      $sourceLayout=$sourceLayoutRaw|ConvertFrom-Json -Depth 100 -DateKind String
      if(-not(Test-MIR4BootstrapRecordHash -Record $sourceLayout)){return $false}
      . (Join-Path $RepoRoot 'tools/lib/assurance/Hashing.ps1')
      $observedPredecessor=Get-MIRAssuranceCommitPackageSourceHash -Commit ([string]$sourceLayout.predecessor.commit)
      $targetKeys=@($sourceLayout.target_parity|ForEach-Object{[string]$_.target})
      $enabledLayoutGates=@($sourceLayout.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}|ForEach-Object{[string]$_.Name})
      if($observedPredecessor-ceq[string]$sourceLayout.predecessor.package_source_fingerprint_sha256-and
         [string]$sourceLayout.current.package_source_fingerprint_sha256-ceq$CurrentSha256-and
         ($targetKeys-join'|')-ceq'f210|f200|f110|f100'-and
         @($sourceLayout.target_parity|Where-Object{-not[bool]$_.deterministic_archive_bytes}).Count-eq0-and
         [bool]$sourceLayout.invariants.package_bytes_unchanged-and
         $enabledLayoutGates.Count-eq1-and$enabledLayoutGates[0]-ceq'development_merge'){
        return $true
      }
    }

    # V2 is frozen predecessor evidence. Current succession is bound to V3,
    # which validates the source/ and target-composition current authority.
    $presentation=$currentPresentation
    $enabledTransitionGates=@($presentation.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}|ForEach-Object{[string]$_.Name})
    return (
      [string]$presentation.package_source.fingerprint_sha256-ceq$CurrentSha256-and
      [string]$presentation.package_source.materializer_abi-ceq'mir4-target-materializer/1'-and
      [string]$presentation.package_source.sole_writer-ceq'tools/mir/application/package/TargetMaterializer.ps1'-and
      (@($presentation.package_source.roots)-join'|')-ceq'source|targets'-and
      [bool]$presentation.authority_invariants.v2_receipts_immutable-and
      [bool]$presentation.authority_invariants.single_editable_source_root-and
      [bool]$presentation.authority_invariants.single_package_writer-and
      -not[bool]$presentation.transition_gate.main_promotion-and
      -not[bool]$presentation.transition_gate.publication-and
      ($enabledTransitionGates-join'|')-ceq'development_merge'
    )
  }catch{return $false}
}

function Get-MIR4M4202CurrentManifestBindingExpectation {
  [CmdletBinding()]
  [OutputType([int])]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][int]$Fallback
  )

  try{
    $receiptPath=Join-Path $RepoRoot 'assurance/repository/composable-source-layout-receipt-v1.json'
    $schemaPath=Join-Path $RepoRoot 'contracts/repository/mir4-composable-source-layout-migration-v1.schema.json'
    if(-not(Test-Path -LiteralPath $receiptPath -PathType Leaf)-or-not(Test-Path -LiteralPath $schemaPath -PathType Leaf)){return $Fallback}
    $raw=Get-Content -Raw -LiteralPath $receiptPath
    if(-not($raw|Test-Json -SchemaFile $schemaPath)){return $Fallback}
    $receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
    if(-not(Test-MIR4BootstrapRecordHash -Record $receipt)-or
       [string]$receipt.current.package_source_fingerprint_sha256-cne(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot)){return $Fallback}
    return [int]$receipt.relocation.binding_count
  }catch{return $Fallback}
}

function Get-MIR4M4202ReadinessSuccessionV1 {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $receiptRelative='releases/migrations/MIR4-M41-Source-Freeze-Authority-EvolutionV1.json'
  $schemaRelative='contracts/repository/mir4-m41-source-freeze-authority-evolution-v1.schema.json'
  $receiptPath=Join-Path $RepoRoot $receiptRelative
  $schemaPath=Join-Path $RepoRoot $schemaRelative
  if(-not(Test-Path -LiteralPath $receiptPath -PathType Leaf)){return $null}
  if(-not(Test-Path -LiteralPath $schemaPath -PathType Leaf)){throw '[mir4-m42-02-readiness-schema-missing]'}
  $raw=Get-Content -Raw -LiteralPath $receiptPath
  if(-not($raw|Test-Json -SchemaFile $schemaPath)){throw '[mir4-m42-02-readiness-schema]'}
  $receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
  if(-not(Test-MIR4BootstrapRecordHash -Record $receipt)){throw '[mir4-m42-02-readiness-record]'}
  $predecessorPath=Join-Path $RepoRoot ([string]$receipt.predecessor.path)
  if(-not(Test-Path -LiteralPath $predecessorPath -PathType Leaf)-or
     (Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash-cne[string]$receipt.predecessor.sha256){throw '[mir4-m42-02-readiness-predecessor-file]'}
  $predecessor=Get-Content -Raw -LiteralPath $predecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
  if([string]$predecessor.record_sha256-cne[string]$receipt.predecessor.record_sha256){throw '[mir4-m42-02-readiness-predecessor-record]'}
  return $receipt
}

function Update-MIR4M4202ExpectedBindingsThroughBridgeRetirement {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][hashtable]$ExpectedBindingSha
  )

  try{
    $receiptPath=Join-Path $RepoRoot 'releases/migrations/MIR4-M41-Current-Product-Bridge-RetirementV1.json'
    $schemaPath=Join-Path $RepoRoot 'contracts/repository/mir4-m41-current-product-bridge-retirement-v1.schema.json'
    if(-not(Test-Path -LiteralPath $receiptPath -PathType Leaf)){return $true}
    if(-not(Test-Path -LiteralPath $schemaPath -PathType Leaf)){return $false}
    $raw=Get-Content -Raw -LiteralPath $receiptPath
    if(-not($raw|Test-Json -SchemaFile $schemaPath)){return $false}
    $receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
    if(-not(Test-MIR4BootstrapRecordHash -Record $receipt)){return $false}
    foreach($binding in @($receipt.evolved_bindings)){
      $path=[string]$binding.path
      if(-not$ExpectedBindingSha.ContainsKey($path)){continue}
      if([string]$binding.previous_sha256-cne[string]$ExpectedBindingSha[$path]){return $false}
      $ExpectedBindingSha[$path]=[string]$binding.current_sha256
    }
    $readiness=Get-MIR4M4202ReadinessSuccessionV1 -RepoRoot $RepoRoot
    if($null-ne$readiness){
      if([string]$readiness.package_source.predecessor_sha256-cne[string]$receipt.package_source.current_sha256){return $false}
      foreach($binding in @($readiness.evolved_bindings)){
        $path=[string]$binding.path
        if(-not$ExpectedBindingSha.ContainsKey($path)){continue}
        if([string]$binding.previous_sha256-cne[string]$ExpectedBindingSha[$path]){return $false}
        $ExpectedBindingSha[$path]=[string]$binding.current_sha256
      }
    }
    . (Join-Path $RepoRoot 'tools/lib/mir4/PostReleaseDocumentation.ps1')
    $documentation=Get-MIR4PostReleaseDocumentation -RepoRoot $RepoRoot
    if($null -ne $documentation){
      foreach($binding in @($documentation.bindings)){
        $path=[string]$binding.path
        if(-not $ExpectedBindingSha.ContainsKey($path)){continue}
        if([string]$binding.previous_sha256 -cne [string]$ExpectedBindingSha[$path]){return $false}
        $ExpectedBindingSha[$path]=[string]$binding.current_sha256
      }
    }
    return $true
  }catch{return $false}
}

function Get-MIR4M4202ExpectedInventoryDigestThroughBridgeRetirement {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$PredecessorDigest
  )

  try{
    $receiptPath=Join-Path $RepoRoot 'releases/migrations/MIR4-M41-Current-Product-Bridge-RetirementV1.json'
    $schemaPath=Join-Path $RepoRoot 'contracts/repository/mir4-m41-current-product-bridge-retirement-v1.schema.json'
    if(-not(Test-Path -LiteralPath $receiptPath -PathType Leaf)){return $PredecessorDigest}
    if(-not(Test-Path -LiteralPath $schemaPath -PathType Leaf)){return $null}
    $raw=Get-Content -Raw -LiteralPath $receiptPath
    if(-not($raw|Test-Json -SchemaFile $schemaPath)){return $null}
    $receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
    if(-not(Test-MIR4BootstrapRecordHash -Record $receipt)){return $null}

    $predecessorPath=Join-Path $RepoRoot ([string]$receipt.predecessor.path)
    $predecessor=Get-Content -Raw -LiteralPath $predecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
    if((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash-cne[string]$receipt.predecessor.sha256){return $null}
    if([string]$predecessor.record_sha256-cne[string]$receipt.predecessor.record_sha256){return $null}
    if([string]$predecessor.tooling_inventory.digest-cne$PredecessorDigest){return $null}

    $inventoryRelativePath=[string]$predecessor.tooling_inventory.path
    $binding=@($receipt.evolved_bindings|Where-Object{[string]$_.path-ceq$inventoryRelativePath})
    if($binding.Count-ne1){return $null}
    if([string]$binding[0].previous_sha256-cne[string]$predecessor.tooling_inventory.sha256){return $null}
    $expectedInventorySha=[string]$binding[0].current_sha256
    $readiness=Get-MIR4M4202ReadinessSuccessionV1 -RepoRoot $RepoRoot
    if($null-ne$readiness){
      if([string]$readiness.package_source.predecessor_sha256-cne[string]$receipt.package_source.current_sha256){return $null}
      $readinessBinding=@($readiness.evolved_bindings|Where-Object{[string]$_.path-ceq$inventoryRelativePath})
      if($readinessBinding.Count-ne1-or[string]$readinessBinding[0].previous_sha256-cne$expectedInventorySha){return $null}
      $expectedInventorySha=[string]$readinessBinding[0].current_sha256
    }
    . (Join-Path $RepoRoot 'tools/lib/mir4/PostReleaseDocumentation.ps1')
    $documentation=Get-MIR4PostReleaseDocumentation -RepoRoot $RepoRoot
    if($null -ne $documentation){
      $documentationBinding=@($documentation.bindings|Where-Object{[string]$_.path -ceq $inventoryRelativePath})
      if($documentationBinding.Count -ne 1 -or [string]$documentationBinding[0].previous_sha256 -cne $expectedInventorySha){return $null}
      $expectedInventorySha=[string]$documentationBinding[0].current_sha256
    }
    $inventoryPath=Join-Path $RepoRoot $inventoryRelativePath
    if((Get-MIR4BootstrapTextSha256 -Path $inventoryPath)-cne$expectedInventorySha){return $null}
    return [string](Get-Content -Raw -LiteralPath $inventoryPath|ConvertFrom-Json -Depth 100 -DateKind String).digest
  }catch{return $null}
}
