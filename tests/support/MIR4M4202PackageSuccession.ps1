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
    # V3--V5 are frozen package-presentation evidence. Current development is
    # validated by the non-receipt package contract so ordinary source changes
    # do not require an artificial V6 historical receipt.
    $historicalPresentation = Get-MIR4CurrentPackagePresentationV5Historical -RepoRoot $RepoRoot
    $currentContract = Assert-MIR4CurrentPackageContract -RepoRoot $RepoRoot -RequiredPackageSourceSha256 $CurrentSha256
    if ((@($currentContract.roots) -join '|') -cne 'source|targets' -or [bool]$currentContract.release_authority) { return $false }
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
    $presentation=$historicalPresentation
    $enabledTransitionGates=@($presentation.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}|ForEach-Object{[string]$_.Name})
    $targetSemantics = @{}
    foreach ($target in @($presentation.target_content_identities)) {
      $targetSemantics[[string]$target.target] = "$($target.relation)|$($target.capability_state)|$($target.exact_engine_qualification_required)"
    }
    return (
      [string]$presentation.kind -ceq 'MIR4CurrentPackagePresentationV5' -and
      [string]$currentContract.package_source_sha256-ceq$CurrentSha256-and
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

function Get-MIR4M4202GitBlobCanonicalText {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Object
  )

  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = 'git'
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  foreach ($argument in @('-C', $RepoRoot, 'cat-file', 'blob', $Object)) {
    [void]$startInfo.ArgumentList.Add($argument)
  }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw '[mir4-m42-02-historical-blob-start]' }
  $bytes = [IO.MemoryStream]::new()
  try {
    $process.StandardOutput.BaseStream.CopyTo($bytes)
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw '[mir4-m42-02-historical-blob-read] ' + $stderr.Trim() }
    return [Text.UTF8Encoding]::new($false).GetString($bytes.ToArray()).Replace("`r`n", "`n").Replace("`r", "`n")
  } finally {
    $bytes.Dispose()
    $process.Dispose()
  }
}

function Find-MIR4M4202HistoricalTextByCanonicalSha256 {
  [CmdletBinding()]
  [OutputType([object])]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$EpochCommit,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Sha256,
    [string]$ReceiptPath = 'releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
  )

  if ($EpochCommit -cnotmatch '^[0-9a-f]{40}$' -or
      $Sha256 -cnotmatch '^[A-F0-9]{64}$' -or
      [string]::IsNullOrWhiteSpace($Path) -or
      [IO.Path]::IsPathRooted($Path) -or
      $Path.Replace('\', '/') -match '(^|/)\.\.(/|$)') {
    throw '[mir4-m42-02-historical-blob-input]'
  }
  $text = Get-MIR4M4202GitBlobCanonicalText -RepoRoot $RepoRoot -Object "$EpochCommit`:$Path"
  if ((Get-MIR4Sha256String -Value $text) -ceq $Sha256) {
    return [pscustomobject]@{ commit = $EpochCommit; text = $text }
  }

  # The characterization receipt itself was introduced immediately after its
  # stated starting_dev.  PreFreezeRelease is the only tracked file whose
  # recorded shape belongs to that receipt-introducing commit; pin this narrow
  # exception to the exact receipt addition and its exact parent rather than
  # searching arbitrary descendant or ancestor history.
  if ($Path -cne 'tools/lib/mir4/PreFreezeRelease.ps1' -or
      $ReceiptPath -cne 'releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json') {
    throw "[mir4-m42-02-historical-blob-unavailable] $Path"
  }
  $introducingCommits = @(& git -C $RepoRoot log --format=%H --diff-filter=A HEAD -- $ReceiptPath)
  if ($LASTEXITCODE -ne 0 -or $introducingCommits.Count -ne 1 -or
      [string]$introducingCommits[0] -cnotmatch '^[0-9a-f]{40}$') {
    throw '[mir4-m42-02-historical-receipt-provenance]'
  }
  $introducingCommit = [string]$introducingCommits[0]
  $parents = @(((& git -C $RepoRoot show -s --format=%P $introducingCommit).Trim()) -split '\s+' | Where-Object { $_ -match '^[0-9a-f]{40}$' })
  if ($LASTEXITCODE -ne 0 -or $parents.Count -lt 1 -or [string]$parents[0] -cne $EpochCommit) {
    throw '[mir4-m42-02-historical-receipt-parent]'
  }
  $text = Get-MIR4M4202GitBlobCanonicalText -RepoRoot $RepoRoot -Object "$introducingCommit`:$Path"
  if ((Get-MIR4Sha256String -Value $text) -ceq $Sha256) {
    return [pscustomobject]@{ commit = $introducingCommit; text = $text }
  }
  throw "[mir4-m42-02-historical-blob-unavailable] $Path"
}

function Test-MIR4M4202HistoricalAssuranceEvidencePublicContract {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][object]$Receipt
  )

  try {
    $commit = [string]$Receipt.starting_dev.commit
    if ($commit -cnotmatch '^[0-9a-f]{40}$') { return $false }
    & git -C $RepoRoot cat-file -e "$commit`^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0 -or
        [string]((& git -C $RepoRoot rev-parse "$commit`^{tree}").Trim()) -cne [string]$Receipt.starting_dev.tree) { return $false }
    $source = Get-MIR4M4202GitBlobCanonicalText -RepoRoot $RepoRoot -Object "$commit`:tools/lib/assurance/Evidence.ps1"
    if (-not $source.EndsWith("`n", [StringComparison]::Ordinal) -or
        (Get-MIR4Sha256String -Value $source) -cne [string]$Receipt.characterization.sha256) { return $false }
    $sourceLines = $source -split "`n"
    $functionNames = [Collections.Generic.List[string]]::new()
    foreach ($module in @($Receipt.decomposition.modules)) {
      $start = [int]$module.source_lines.start
      $end = [int]$module.source_lines.end
      if ($start -lt 1 -or $end -lt $start -or $end -ge $sourceLines.Count) { return $false }
      $segment = (@($sourceLines[($start - 1)..($end - 1)]) -join "`n") + "`n"
      $tokens = $null
      $parseErrors = $null
      $ast = [Management.Automation.Language.Parser]::ParseInput($segment, [ref]$tokens, [ref]$parseErrors)
      $functions = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true))
      if ((Get-MIR4Sha256String -Value $segment) -cne [string]$module.sha256 -or
          [regex]::Matches($segment, "`n").Count -ne [int]$module.lines -or
          @($parseErrors).Count -ne [int]$module.parse_errors -or
          $functions.Count -ne [int]$module.function_count) { return $false }
      foreach ($function in $functions) { [void]$functionNames.Add($function.Name) }
    }
    $projectionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $functionNames.ToArray())
    return ($functionNames.Count -eq [int]$Receipt.public_contract.function_count -and
            $projectionSha -ceq [string]$Receipt.public_contract.previous_sha256 -and
            $projectionSha -ceq [string]$Receipt.public_contract.current_sha256 -and
            [bool]$Receipt.public_contract.unchanged)
  } catch { return $false }
}

function Test-MIR4M4202HistoricalPowerShellCharacterization {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][object]$Receipt
  )

  try {
    $commit = [string]$Receipt.starting_dev.commit
    if ($commit -cnotmatch '^[0-9a-f]{40}$') { return $false }
    & git -C $RepoRoot cat-file -e "$commit`^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0 -or
        [string]((& git -C $RepoRoot rev-parse "$commit`^{tree}").Trim()) -cne [string]$Receipt.starting_dev.tree) { return $false }
    foreach ($row in @($Receipt.tracked_files)) {
      $path = [string]$row.path
      $historical = Find-MIR4M4202HistoricalTextByCanonicalSha256 -RepoRoot $RepoRoot -EpochCommit $commit -Path $path -Sha256 ([string]$row.sha256)
      $text = [string]$historical.text
      $tokens = $null
      $parseErrors = $null
      $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
      if (-not $text.EndsWith("`n", [StringComparison]::Ordinal) -or
          [string]$row.hash_mode -cne 'canonical-text-v1' -or
          (Get-MIR4Sha256String -Value $text) -cne [string]$row.sha256 -or
          @($text -split "`n").Count -ne [int]$row.lines -or
          @($parseErrors).Count -ne [int]$row.parse_errors -or
          @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count -ne [int]$row.function_count) { return $false }
    }
    return (@($Receipt.tracked_files).Count -eq [int]$Receipt.inventory.reviewed_file_count -and
            [string]$Receipt.inventory.path -ceq 'governance/automation/mir4-command-inventory-v1.json' -and
            [string]$Receipt.inventory.sha256 -cmatch '^[A-F0-9]{64}$' -and
            [string]$Receipt.inventory.digest -cmatch '^sha256:[a-f0-9]{64}$' -and
            [int]$Receipt.inventory.canonical_internal -gt 0 -and
            [int]$Receipt.inventory.unknown -eq 0)
  } catch { return $false }
}

function Update-MIR4M4202ExpectedBindingsThroughComposableSourceSuccession {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][hashtable]$ExpectedBindingSha
  )

  try {
    . (Join-Path $RepoRoot 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')
    $v3 = Get-MIR4M41ToM42ComposableSourceSuccessionV3 -RepoRoot $RepoRoot
    $v4 = Get-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $RepoRoot
    $v3BindingPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($binding in @($v3.evolved_bindings)) {
      [void]$v3BindingPaths.Add([string]$binding.path)
    }
    foreach ($step in @(
      [pscustomobject]@{ successor = $v3; is_v4 = $false }
      [pscustomobject]@{ successor = $v4; is_v4 = $true }
    )) {
      $successor = $step.successor
      $inventoryPath = [string]$successor.current.tooling_inventory.path
      if ($ExpectedBindingSha.ContainsKey($inventoryPath)) {
        if ([string]$successor.current.tooling_inventory_predecessor_sha256 -cne [string]$ExpectedBindingSha[$inventoryPath] -or
            [string]$successor.current.tooling_inventory.sha256 -notmatch '^[A-F0-9]{64}$') { return $false }
        $ExpectedBindingSha[$inventoryPath] = [string]$successor.current.tooling_inventory.sha256
      }
      foreach($binding in @($successor.evolved_bindings)){
        $path=[string]$binding.path
        if(-not $ExpectedBindingSha.ContainsKey($path)){continue}
        if([string]$binding.hash_mode -cne 'canonical-text-v1' -or
           [bool]$binding.package_visible -or
           [bool]$binding.release_authority){return $false}
        $isV4Anchor = [bool]$step.is_v4 -and -not $v3BindingPaths.Contains($path)
        if($isV4Anchor){
          # V4 adds some proof-input bindings that have no V3 counterpart.
          # The V4 reader has already authenticated its immutable V3
          # predecessor, canonical record bytes, fixed record hash, and the
          # binding's fixed predecessor hash.  Do not force such a binding
          # through an unrelated M42 receipt lineage; validate its own
          # predecessor/current hashes and continue from the V4 current hash.
          if([string]$binding.previous_sha256 -cnotmatch '^[A-F0-9]{64}$' -or
             [string]$binding.current_sha256 -cnotmatch '^[A-F0-9]{64}$' -or
             [string]$binding.previous_sha256 -ceq [string]$binding.current_sha256){return $false}
        }elseif([string]$binding.previous_sha256 -cne [string]$ExpectedBindingSha[$path]){
          return $false
        }
        $ExpectedBindingSha[$path]=[string]$binding.current_sha256
      }
    }

    # V3 and V4 remain immutable evidence.  Current package-excluded files
    # are instead admitted by the generated inventory's live fixed point, so
    # later development need not manufacture another historical receipt.
    . (Join-Path $RepoRoot 'tools/mir/application/tooling/CommandInventory.ps1')
    Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot -Check | Out-Null
    foreach ($path in @($ExpectedBindingSha.Keys)) {
      $portable = ([string]$path).Replace('\','/').TrimStart('/')
      if ([string]::IsNullOrWhiteSpace($portable) -or
          [IO.Path]::IsPathRooted([string]$path) -or
          $portable -match '(^|/)\.\.(/|$)' -or
          $portable -ceq 'source' -or $portable.StartsWith('source/',[StringComparison]::Ordinal) -or
          $portable -ceq 'targets' -or $portable.StartsWith('targets/',[StringComparison]::Ordinal)) { return $false }
      $livePath = Join-Path $RepoRoot $portable
      if (-not (Test-Path -LiteralPath $livePath -PathType Leaf)) { return $false }
      $ExpectedBindingSha[$path] = Get-MIR4BootstrapTextSha256 -Path $livePath
    }
    return $true
  }catch{return $false}
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
    return Update-MIR4M4202ExpectedBindingsThroughComposableSourceSuccession -RepoRoot $RepoRoot -ExpectedBindingSha $ExpectedBindingSha
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
    # V3 and V4 are immutable historical evidence. Validate their exact
    # custody, then evaluate the current generated inventory independently so
    # later development does not rewrite those records.
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
    . (Join-Path $RepoRoot 'tools/mir/application/tooling/CommandInventory.ps1')
    $currentInventory = Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot -Check
    # V4 fixes the frozen 85-command inventory. Current development is
    # separately generated and may validly contain later package-excluded
    # commands, so require a non-empty, known, duplicate-free live inventory
    # rather than comparing it to the historical count.
    if ([int]$currentInventory.command_count -le 0 -or
        [int]$currentInventory.summary.unknown -ne 0 -or
        [int]$currentInventory.summary.duplicate_command_keys -ne 0 -or
        [string]$currentInventory.digest -cnotmatch '^sha256:[a-f0-9]{64}$') { return $null }
    return [string]$currentInventory.digest
  }catch{return $null}
}
