function Test-MIR4M4202PackageSourceSuccession {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$PredecessorSha256,
    [Parameter(Mandatory)][string]$CurrentSha256
  )

  if($PredecessorSha256-ceq$CurrentSha256){return $true}

  try{
    $receiptPath=Join-Path $RepoRoot 'releases/migrations/MIR4-M41-Current-Product-Bridge-RetirementV1.json'
    $schemaPath=Join-Path $RepoRoot 'contracts/repository/mir4-m41-current-product-bridge-retirement-v1.schema.json'
    if(-not(Test-Path -LiteralPath $receiptPath -PathType Leaf)-or-not(Test-Path -LiteralPath $schemaPath -PathType Leaf)){return $false}
    $raw=Get-Content -Raw -LiteralPath $receiptPath
    if(-not($raw|Test-Json -SchemaFile $schemaPath)){return $false}
    $receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
    if(-not(Test-MIR4BootstrapRecordHash -Record $receipt)){return $false}
    $enabledGates=@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}|ForEach-Object{[string]$_.Name})
    return (
      [string]$receipt.package_source.predecessor_sha256-ceq$PredecessorSha256-and
      [string]$receipt.package_source.current_sha256-ceq$CurrentSha256-and
      @($receipt.package_visible_delta).Count-eq0-and
      $enabledGates.Count-eq1-and
      $enabledGates[0]-ceq'bridge_retirement'
    )
  }catch{return $false}
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
