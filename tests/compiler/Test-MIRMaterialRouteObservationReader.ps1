# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$AuditLinePath=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/compatibility/DiagnosticsParser.ps1')
# Import only the actual reader and its assertion helper; never execute the
# observer's native preparation or process path during a static check.
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelTinRouteObserver.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count) { throw 'Observer has PowerShell parse errors.' }
foreach($name in @('Assert-Observer','Get-ObserverInputContracts')) {
  $functions=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false))
  if($functions.Count -ne 1) { throw "Expected one actual observer function: $name" }
  . ([scriptblock]::Create($functions[0].Extent.Text))
}
$assertions=0
function Assert-Reader([bool]$Condition,[string]$Message) {
  if(-not $Condition) { throw "Material input observation reader: $Message" }
  $script:assertions++
}
function Assert-ReaderReject([object[]]$Rows,[string]$ExpectedError) {
  $failure=''
  try { $null=@(Get-ObserverInputContracts -AuditRows $Rows -ExpectedRecipes @('smelting')) } catch { $failure=$_.Exception.Message }
  Assert-Reader ($failure.Contains($ExpectedError)) "expected rejection $ExpectedError; got $failure"
}
$line=if($AuditLinePath) { Get-Content -LiteralPath $AuditLinePath -Raw } else {
  '[more-infinite-research] audit schema=1 kind=material_route_certificate binding_schema=2 bindings_fingerprint=mir32-01234567 canonical_risk_fingerprint=mir32-89abcdef direct_output_producer_count=1 phase=input reachable_identity_count=2 recipe=smelting relevant_recipe_count=3 return_graph_fingerprint=mir32-abcdef01 status=observed'
}
$row=ConvertFrom-MIRAuditLine -Line $line
$contracts=@(Get-ObserverInputContracts -AuditRows @($row) -ExpectedRecipes @('smelting'))
Assert-Reader ($contracts.Count -eq 1 -and $contracts[0].schema -eq 2 -and $contracts[0].phase -ceq 'input') 'actual reader must preserve explicit input schema.'
Assert-Reader ($contracts[0].bindings_fingerprint -ceq $row.bindings_fingerprint -and $contracts[0].return_graph_fingerprint -ceq $row.return_graph_fingerprint) 'actual reader must preserve exact observed fingerprints.'
Assert-Reader ($contracts[0].relevant_recipe_count -is [int]) 'counts must be typed independently of audit strings.'
Assert-ReaderReject @() 'expected one input contract'
Assert-ReaderReject @($row,$row) 'expected one input contract'
$incomplete=ConvertFrom-MIRAuditLine -Line '[more-infinite-research] audit schema=1 kind=material_route_certificate binding_schema=2 phase=input status=incomplete reason=observation-row-budget'
Assert-ReaderReject @($row,$incomplete) 'input capture is incomplete'
foreach($change in @(
  @('schema','2','wrong input phase'),
  @('binding_schema','1','wrong input phase'),
  @('phase','final','wrong input phase'),
  @('status','unavailable','wrong input phase'),
  @('canonical_risk_fingerprint','not-recorded','invalid input fingerprint'),
  @('bindings_fingerprint','mir32-ABCDEF01','invalid input fingerprint'),
  @('relevant_recipe_count','0','invalid input count'),
  @('reachable_identity_count','2147483648','invalid input count'),
  @('direct_output_producer_count','1.5','invalid input count')
)) {
  $changed=$row | Select-Object *
  $changed.($change[0])=$change[1]
  Assert-ReaderReject @($changed) $change[2]
}
$missing=$row | Select-Object * -ExcludeProperty 'phase'
Assert-ReaderReject @($missing) 'missing input field phase'
Write-Host "[ok] material input observation reader passed $assertions assertions; no native engine or route admission."
