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
    # V3 is frozen layout evidence and V4 is frozen Factorio-1 convergence
    # evidence. V5 is the current progression successor.
    $currentPresentation = Get-MIR4CurrentPackagePresentationV5 -RepoRoot $RepoRoot
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

    # V2/V3/V4 are frozen predecessor evidence. V5 is the current successor
    # and validates the progression composition plus the explicit F1 nonclaim.
    $presentation=$currentPresentation
    $enabledTransitionGates=@($presentation.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}|ForEach-Object{[string]$_.Name})
    $targetSemantics = @{}
    foreach ($target in @($presentation.target_content_identities)) {
      $targetSemantics[[string]$target.target] = "$($target.relation)|$($target.capability_state)|$($target.exact_engine_qualification_required)"
    }
    return (
      [string]$presentation.kind -ceq 'MIR4CurrentPackagePresentationV5' -and
      [string]$presentation.package_source.fingerprint_sha256-ceq$CurrentSha256-and
      [string]$presentation.package_source.materializer_abi-ceq'mir4-target-materializer/1'-and
      [string]$presentation.package_source.sole_writer-ceq'tools/mir/application/package/TargetMaterializer.ps1'-and
       (@($presentation.package_source.roots)-join'|')-ceq'source|targets'-and
       [bool]$presentation.authority_invariants.v4_receipt_immutable-and
       [bool]$presentation.authority_invariants.factorio_one_convergence_historical-and
       [bool]$presentation.authority_invariants.historical_protected_prefix_semantics_accounted-and
       [bool]$presentation.authority_invariants.promotion_custody_revalidation_required-and
       [bool]$presentation.authority_invariants.f210_f200_progression_capability_applied-and
      [bool]$presentation.authority_invariants.f110_f100_progression_capability_omitted_nonclaim-and
      [bool]$presentation.authority_invariants.exact_engine_qualification_required-and
      -not[bool]$presentation.authority_invariants.candidate_allocation_authorized-and
      -not[bool]$presentation.authority_invariants.signing_or_sealing_authorized-and
      -not[bool]$presentation.authority_invariants.promotion_authorized-and
      -not[bool]$presentation.authority_invariants.publication_authorized-and
       -not[bool]$presentation.authority_invariants.public_support_authorized-and
       [string]$presentation.historical_custody.historical_protected_prefix.revision-ceq'a38735d22257aa7ab46237a111dc94c961fd04c0'-and
       [string]$presentation.historical_custody.historical_protected_prefix.record_sha256-ceq'DF6B284C201062589497481E7491A742A48314FC42E8EBF8F4FC79565322ACD9'-and
       [string]$presentation.historical_custody.historical_protected_prefix.mode-ceq'protected-remote-prefix-v1'-and
       [string]$presentation.historical_custody.reviewed_successor.mode-ceq'immutable-v4-predecessor-v5-self-hash-current-binding-v1'-and
       -not[bool]$presentation.historical_custody.reviewed_successor.historical_prefix_runtime_enforcement-and
       [bool]$presentation.historical_custody.reviewed_successor.promotion_custody_revalidation_required-and
       -not[bool]$presentation.historical_custody.reviewed_successor.release_authority_granted-and
       $targetSemantics.Count-eq4-and
      [string]$targetSemantics['f210']-ceq'progression-semantic-content-changed-exact-engine-qualification-required|applied|True'-and
      [string]$targetSemantics['f200']-ceq'progression-semantic-content-changed-exact-engine-qualification-required|applied|True'-and
      [string]$targetSemantics['f110']-ceq'progression-capability-omitted-nonclaim-exact-engine-qualification-required|omitted-nonclaim|True'-and
      [string]$targetSemantics['f100']-ceq'progression-capability-omitted-nonclaim-exact-engine-qualification-required|omitted-nonclaim|True'-and
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
    # This receipt is frozen 4.1 documentation lineage.  Later 4.2 package
    # source changes are admitted only through the current V2 successor, so
    # validate the documented record against its historical base instead of
    # incorrectly requiring its former current-package fingerprint.
    $documentation=Get-MIR4PostReleaseDocumentation -RepoRoot $RepoRoot -Historical
    if($null -ne $documentation){
      foreach($binding in @($documentation.bindings)){
        $path=[string]$binding.path
        if(-not $ExpectedBindingSha.ContainsKey($path)){continue}
        if([string]$binding.previous_sha256 -cne [string]$ExpectedBindingSha[$path]){return $false}
        $ExpectedBindingSha[$path]=[string]$binding.current_sha256
      }
    }
    # V3 is frozen progression evidence and V4 is the current proof-input
    # successor. Only their authenticated evolved paths may advance a frozen
    # M42-02 module expectation; neither grants release operation authority.
    . (Join-Path $RepoRoot 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')
    foreach ($successor in @(
      Get-MIR4M41ToM42ComposableSourceSuccessionV3 -RepoRoot $RepoRoot
      Get-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $RepoRoot
    )) {
      $inventoryPath = [string]$successor.current.tooling_inventory.path
      if ($ExpectedBindingSha.ContainsKey($inventoryPath)) {
        if ([string]$successor.current.tooling_inventory_predecessor_sha256 -cne [string]$ExpectedBindingSha[$inventoryPath] -or
            [string]$successor.current.tooling_inventory.sha256 -notmatch '^[A-F0-9]{64}$') { return $false }
        $ExpectedBindingSha[$inventoryPath] = [string]$successor.current.tooling_inventory.sha256
      }
      foreach($binding in @($successor.evolved_bindings)){
        $path=[string]$binding.path
        if(-not $ExpectedBindingSha.ContainsKey($path)){continue}
        if([string]$binding.previous_sha256 -cne [string]$ExpectedBindingSha[$path] -or
           [string]$binding.hash_mode -cne 'canonical-text-v1' -or
           [bool]$binding.package_visible -or
           [bool]$binding.release_authority){return $false}
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
    # See the matching historical-lineage validation above.  The V2 successor
    # below owns the post-cutover current inventory binding.
    $documentation=Get-MIR4PostReleaseDocumentation -RepoRoot $RepoRoot -Historical
    if($null -ne $documentation){
      $documentationBinding=@($documentation.bindings|Where-Object{[string]$_.path -ceq $inventoryRelativePath})
      if($documentationBinding.Count -ne 1 -or [string]$documentationBinding[0].previous_sha256 -cne $expectedInventorySha){return $null}
      $expectedInventorySha=[string]$documentationBinding[0].current_sha256
    }
    # The bridge/readiness/documentation records authenticate the historical
    # inventory succession through their final evolved binding.  The one-source
    # cutover deliberately changes that inventory, so do not substitute the
    # live file for the successor. V2 is the immutable Factorio-1 predecessor;
    # V3 is immutable progression evidence and V4 records the live inventory
    # alongside the proof-input/control-plane successor. We return its digest
    # only after historical custody and current live binding both agree.
    . (Join-Path $RepoRoot 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')
    $historicalSuccessor = Get-MIR4M41ToM42ComposableSourceSuccessionV2Historical -RepoRoot $RepoRoot
    $factorioAuthorityPath = Join-Path $RepoRoot ([string]$historicalSuccessor.factorio_one_successor.authority.path)
    if ([string]$historicalSuccessor.factorio_one_successor.authority.path -cne 'governance/repository/factorio-one-source-convergence-v1.json' -or
        -not (Test-Path -LiteralPath $factorioAuthorityPath -PathType Leaf) -or
        (Get-MIR4BootstrapTextSha256 -Path $factorioAuthorityPath) -cne [string]$historicalSuccessor.factorio_one_successor.authority.sha256) { return $null }
    . (Join-Path $RepoRoot 'tools/mir/application/package/FactorioOneSourceConvergenceAuthority.ps1')
    $factorioReceipt = Read-MIR4FactorioOneSourceConvergenceReceipt -RepoRoot $RepoRoot
    if ([string]$historicalSuccessor.factorio_one_successor.receipt.path -cne 'assurance/repository/factorio-one-source-convergence-v1.json' -or
        [string]$historicalSuccessor.factorio_one_successor.receipt.kind -cne [string]$factorioReceipt.kind -or
        [string]$historicalSuccessor.factorio_one_successor.receipt.record_sha256 -cne [string]$factorioReceipt.record_sha256) { return $null }
    $successorInventory = (Get-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $RepoRoot).current.tooling_inventory
    if ([string]$successorInventory.path -cne $inventoryRelativePath -or
        [string]$successorInventory.hash_mode -cne 'canonical-text-v1' -or
        [int]$successorInventory.command_count -ne 85 -or
        [int]$successorInventory.unknown -ne 0 -or
        [int]$successorInventory.duplicate_command_keys -ne 0) { return $null }
    $inventoryPath = Join-Path $RepoRoot ([string]$successorInventory.path)
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf) -or
        (Get-MIR4BootstrapTextSha256 -Path $inventoryPath) -cne [string]$successorInventory.sha256) { return $null }
    $inventory = Get-Content -Raw -LiteralPath $inventoryPath | ConvertFrom-Json -Depth 100 -DateKind String
    if ([string]$inventory.digest -cne [string]$successorInventory.digest -or
        [int]$inventory.command_count -ne [int]$successorInventory.command_count -or
        [int]$inventory.summary.unknown -ne [int]$successorInventory.unknown -or
        [int]$inventory.summary.duplicate_command_keys -ne [int]$successorInventory.duplicate_command_keys) { return $null }
    return [string]$successorInventory.digest
  }catch{return $null}
}
