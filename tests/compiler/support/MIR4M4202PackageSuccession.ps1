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
