# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$AuditLinePath='',
  [string]$InventoryLogPath=''
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
$inventoryAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelFinalRoutesObserver.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count) { throw 'Final-routes observer has PowerShell parse errors.' }
foreach($name in @('Assert-Observer','Get-ObserverMaterialOutcomeInventory')) {
  $functions=@($inventoryAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false))
  if($functions.Count -ne 1) { throw "Expected one actual final-routes observer function: $name" }
  . ([scriptblock]::Create($functions[0].Extent.Text))
}
$expectedSubjects=@('aluminium/plate','gold/plate','lead/plate','nickel/plate','platinum/plate','silver/plate','tin/plate','titanium/plate','copper-tungsten/alloy','zinc/plate','bronze/alloy','brass/alloy','gunmetal/alloy','invar/alloy','cobalt-steel/alloy','nitinol/alloy','platinum/wire')
$emptyInventory=(@($expectedSubjects|ForEach-Object {"[mir-material-outcome-inventory] SUBJECT id=$_ status=prototype-absent items=0 producers=0"})+@('[mir-material-outcome-inventory] PASS complete=true phase=finalized-raw-prototypes subjects=17 recipes=0 results=0 gaps=0 acquisition=false admission=false')) -join "`n"
$inventory=Get-ObserverMaterialOutcomeInventory $emptyInventory
Assert-Reader ($inventory.subjects.Count -eq 17 -and -not $inventory.acquisition_proved -and -not $inventory.admission_granted) 'independent denominator preserves sixteen outcomes plus separate wire and no admission.'
$wrongShape=$emptyInventory.Replace('id=platinum/plate status=prototype-absent items=0 producers=0','id=platinum/plate status=no-observed-producer items=1 producers=0')+"`n"+'[mir-material-outcome-inventory] ITEM subject=platinum/plate name=angels-wire-platinum hidden=false'
foreach($badInventory in @(
  $emptyInventory.Replace('id=platinum/plate','id=platinum/wire'),
  $emptyInventory.Replace('subjects=17','subjects=16'),
  $emptyInventory.Replace('gaps=0','gaps=1'),
  $emptyInventory.Replace('acquisition=false','acquisition=true'),
  $emptyInventory.Replace('admission=false','admission=true'),
  $emptyInventory.Replace('status=prototype-absent items=0','status=observed items=0'),
  $wrongShape,
  ($emptyInventory+"`n"+$emptyInventory)
)) {
  $rejected=$false
  try {$null=Get-ObserverMaterialOutcomeInventory $badInventory} catch {$rejected=$true}
  Assert-Reader $rejected 'malformed, duplicated, incomplete or admission-bearing inventory was accepted.'
}
if($InventoryLogPath){
  $capturedText=Get-Content -Raw -LiteralPath $InventoryLogPath
  $capture=Get-ObserverMaterialOutcomeInventory $capturedText
  $plate=@($capture.subjects|Where-Object id -CEQ 'platinum/plate')[0]
  $wire=@($capture.subjects|Where-Object id -CEQ 'platinum/wire')[0]
  Assert-Reader ($plate.producers[0].recipe -ceq 'unselected-casting' -and $wire.producers[0].recipe -ceq 'wire-only') 'actual formatter conflated plate and wire.'
  Assert-Reader (@($capture.observation_gaps|Where-Object recipe -CEQ 'unselected-casting').Count -eq 1) 'actual formatter omitted the independent casting gap.'
  Assert-Reader (@(@($capture.subjects|Where-Object id -CEQ 'tin/plate')[0].producers|Where-Object recipe -CEQ 'named route%one').Count -eq 1) 'escaped producer identity did not round-trip.'
  $maskedGap=$capturedText.Replace('[mir-material-outcome-inventory] GAP subject=platinum/plate recipe=unselected-casting','').Replace('gaps=4','gaps=3')
  Assert-Reader ($maskedGap -cne $capturedText) 'casting gap negative control did not change the fixture.'
  $rejected=$false
  try {$null=Get-ObserverMaterialOutcomeInventory $maskedGap} catch {$rejected=$true}
  Assert-Reader $rejected 'a deleted casting gap was hidden by matching the completion count.'
}
Write-Host "[ok] material input/inventory observation readers passed $assertions assertions; no native engine or route admission."
