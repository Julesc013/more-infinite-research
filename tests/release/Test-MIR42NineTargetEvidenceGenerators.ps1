# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$evidence = Join-Path $repo 'tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1'
$independent = Join-Path $repo 'tools/mir/application/release/readiness/MIR42IndependentEvidenceRehash.ps1'
foreach ($path in @($evidence,$independent)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir42-nine-generator-stage-missing] $path" } }
. $evidence
. $independent

function Assert-MIR42NineGeneratorTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir42-nine-generator-test-$Code]" }
}

function Get-MIR42NineGeneratorFunctionParameters {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name,[string]$SourceText)
  $errors = $null
  $ast = if ($SourceText) { [System.Management.Automation.Language.Parser]::ParseInput($SourceText,[ref]$null,[ref]$errors) } else { [System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$null,[ref]$errors) }
  if ($errors) { throw "[mir42-nine-generator-test-parser] $Path" }
  $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name }, $true))
  if ($functions.Count -ne 1) { throw "[mir42-nine-generator-test-function] $Name" }
  return @($functions[0].Body.ParamBlock.Parameters | ForEach-Object { [string]$_.Name.VariablePath.UserPath })
}

$modernRows = @($script:MIR42QualificationTargets | ForEach-Object { [pscustomobject][ordered]@{target=$_} })
$nineRows = @($script:MIR42QualificationNineTargets | ForEach-Object { [pscustomobject][ordered]@{target=$_} })
$modernScope = Get-MIR42QualificationTargetScope -Rows $modernRows -Code 'mir42-nine-generator-modern'
$nineScope = Get-MIR42QualificationTargetScope -Rows $nineRows -Code 'mir42-nine-generator-nine'
$modernContract = Get-MIR42QualificationScopeContract -Scope $modernScope
$nineContract = Get-MIR42QualificationScopeContract -Scope $nineScope
$nineIndependentContract = Get-MIR42IndependentScopeContract -Scope (Get-MIR42IndependentTargetScope -Rows $nineRows -Code 'mir42-nine-generator-independent')
Assert-MIR42NineGeneratorTest -Condition ([string]$modernContract.kind -ceq 'MIR42FourTargetEvidenceReconciliationV1' -and [string]$modernContract.target_requirement -ceq 'all_four_targets_required') -Code 'modern-contract'
Assert-MIR42NineGeneratorTest -Condition ([string]$nineContract.kind -ceq 'MIR42NineTargetEvidenceReconciliationV1' -and [string]$nineContract.target_requirement -ceq 'all_nine_targets_required') -Code 'nine-reconciliation-contract'
Assert-MIR42NineGeneratorTest -Condition ([string]$nineIndependentContract.rehash_kind -ceq 'MIR42NineTargetIndependentEvidenceRehashV1' -and [string]$nineIndependentContract.target_requirement -ceq 'all_nine_targets_required') -Code 'nine-independent-contract'

$rejected = $false
try { $null = Get-MIR42QualificationTargetScope -Rows @($modernRows + [pscustomobject][ordered]@{target='f017'}) -Code 'mir42-nine-generator-opposing' } catch { $rejected = $_.Exception.Message -match '^\[mir42-nine-generator-opposing-target-set\]' }
Assert-MIR42NineGeneratorTest -Condition $rejected -Code 'mixed-scope-rejected'

foreach ($target in $script:MIR42QualificationHistoricalTargets) {
  $authority = Get-MIR42QualificationHistoricalAuthority -RepoRoot $repo -Target $target
  Assert-MIR42NineGeneratorTest -Condition ([string]$authority.identity.target -ceq $target -and [string]$authority.record.target -ceq $target) -Code "identity-$target"
  Assert-MIR42NineGeneratorTest -Condition ([string]$authority.seal.release -ceq [string]$authority.record.predecessor.version -and [string]$authority.inventory.archive_sha256 -ceq [string]$authority.record.predecessor.sha256) -Code "terminal-$target"
  Assert-MIR42NineGeneratorTest -Condition (-not [bool]$authority.record.public_output_authorized -and -not [bool]$authority.record.publication_authorized) -Code "private-$target"
  $engine = Get-MIR42IndependentEngine -RepoRoot $repo -Target $target -Qualified ([pscustomobject][ordered]@{environment=[pscustomobject][ordered]@{binary_sha256=[string]$authority.record.engine.sha256;version=[string]$authority.record.engine.version}})
  Assert-MIR42NineGeneratorTest -Condition ([string]$engine.version -ceq [string]$authority.record.engine.version -and [string]$engine.binary_sha256 -ceq [string]$authority.record.engine.sha256) -Code "engine-$target"
}

$fourCommand = Get-Command Invoke-MIR42FourTargetEvidenceReconciliation -CommandType Function
$nineCommand = Get-Command Invoke-MIR42NineTargetEvidenceReconciliation -CommandType Function
$fourRehash = Get-Command Invoke-MIR42FourTargetIndependentEvidenceRehash -CommandType Function
$nineRehash = Get-Command Invoke-MIR42NineTargetIndependentEvidenceRehash -CommandType Function
Assert-MIR42NineGeneratorTest -Condition ($fourCommand.Parameters.Keys -contains 'F210PredecessorZip' -and $fourCommand.Parameters.Keys -contains 'F100UpgradeReceipt' -and $fourRehash.Parameters.Keys -contains 'F210PredecessorZip') -Code 'four-positional-contract-preserved'
Assert-MIR42NineGeneratorTest -Condition ($nineCommand.Parameters.Keys -contains 'PredecessorZips' -and $nineCommand.Parameters.Keys -contains 'UpgradeReceipts' -and $nineRehash.Parameters.Keys -contains 'PredecessorZips' -and $nineRehash.Parameters.Keys -contains 'UpgradeReceipts' -and $nineCommand.Parameters.Keys -notcontains 'F210PredecessorZip') -Code 'nine-keyed-input-contract'
$baseEvidence = (@(& git -C $repo show '8835c01b82c26cfb7634e1727e33903c9c6a39d7:tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1') -join "`n")
if ($LASTEXITCODE -ne 0) { throw '[mir42-nine-generator-baseline-evidence]' }
$baseIndependent = (@(& git -C $repo show '8835c01b82c26cfb7634e1727e33903c9c6a39d7:tools/mir/application/release/readiness/MIR42IndependentEvidenceRehash.ps1') -join "`n")
if ($LASTEXITCODE -ne 0) { throw '[mir42-nine-generator-baseline-independent]' }
Assert-MIR42NineGeneratorTest -Condition ((@(Get-MIR42NineGeneratorFunctionParameters -Path $evidence -SourceText $baseEvidence -Name 'Invoke-MIR42FourTargetEvidenceReconciliation') -join '|') -ceq (@(Get-MIR42NineGeneratorFunctionParameters -Path $evidence -Name 'Invoke-MIR42FourTargetEvidenceReconciliation') -join '|')) -Code 'four-evidence-parameter-parity'
Assert-MIR42NineGeneratorTest -Condition ((@(Get-MIR42NineGeneratorFunctionParameters -Path $independent -SourceText $baseIndependent -Name 'Invoke-MIR42FourTargetIndependentEvidenceRehash') -join '|') -ceq (@(Get-MIR42NineGeneratorFunctionParameters -Path $independent -Name 'Invoke-MIR42FourTargetIndependentEvidenceRehash') -join '|')) -Code 'four-independent-parameter-parity'

Write-Output 'MIR42-NINE-TARGET-EVIDENCE-GENERATOR-PASSED scopes=4,9 historical=5 engines=0'
