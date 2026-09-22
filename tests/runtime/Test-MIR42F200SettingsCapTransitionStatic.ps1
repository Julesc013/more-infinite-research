# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$harnessPath=Join-Path $repo 'tests/runtime/Test-MIR42F200SettingsCapTransition.ps1'
$fixturesPath=Join-Path $repo '.mir/fixtures.yml'
$expectedExpansions=@('elevated-rails','quality','space-age')

function Assert-MIR42F200Static([bool]$Condition,[string]$Message){if(-not$Condition){throw "[mir42-f200-settings-cap-transition-static] $Message"}}
function Get-MIR42F200StaticFunctionText($Ast,[string]$Name){$matches=@($Ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name},$true));Assert-MIR42F200Static ($matches.Count-eq1) "expected exactly one $Name function, observed $($matches.Count).";$matches[0].Extent.Text}
function Assert-MIR42F200BaseOnlyHarnessContract([string]$Text){
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
  Assert-MIR42F200Static (@($errors).Count-eq0) "harness parser errors: $(@($errors|ForEach-Object Message)-join'; ')"
  $assignments=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -ceq 'officialExpansionMods'},$true))
  Assert-MIR42F200Static ($assignments.Count-eq1) 'official expansion list must have one explicit assignment.'
  $declared=@([regex]::Matches($assignments[0].Right.Extent.Text,"'(?<name>[^']+)'")|ForEach-Object{$_.Groups['name'].Value})
  Assert-MIR42F200Static (($declared-join"`n")-ceq($expectedExpansions-join"`n")) 'official expansion list differs from elevated-rails, quality, and space-age.'
  $baseOnlyList=Get-MIR42F200StaticFunctionText $ast 'New-MIR42F200BaseOnlyModList'
  Assert-MIR42F200Static ($baseOnlyList-match'foreach\s*\(\s*\$name\s+in\s+\$officialExpansionMods\s*\)') 'base-only mod-list builder does not enumerate the explicit official expansion list.'
  Assert-MIR42F200Static ($baseOnlyList-match'\[ordered\]@\{name=\[string\]\$name;enabled=\$false\}') 'base-only mod-list builder does not explicitly disable every official expansion.'
  $newStage=Get-MIR42F200StaticFunctionText $ast 'New-Stage'
  Assert-MIR42F200Static ($newStage-match'\$modList\s*=\s*New-MIR42F200BaseOnlyModList') 'every stage must use the shared explicit base-only mod-list builder.'
  $stageAssertion=Get-MIR42F200StaticFunctionText $ast 'Assert-MIR42F200BaseOnlyStageModList'
  Assert-MIR42F200Static ($stageAssertion-match'\$officialExpansionMods' -and $stageAssertion-match'\.enabled') 'stage mod-list assertion does not verify disabled expansions.'
  Assert-MIR42F200Static ($Text-match'\$stages\s*=\s*@\(\$seed,\$capped,\$relaxed\).*?foreach\s*\(\$stage\s+in\s+\$stages\).*?Assert-MIR42F200BaseOnlyStageModList' ) 'seed, capped, and relaxed stages are not all checked against the base-only mod-list contract.'
  $engineClosure=Get-MIR42F200StaticFunctionText $ast 'Get-MIR42F200EffectiveEngineLoadedClosure'
  Assert-MIR42F200Static ($engineClosure.Contains('Loading mod (?!settings ') -and $engineClosure.Contains('Loading mod settings ') -and $engineClosure-match'\$expectedEngineLoadedModNames' -and $engineClosure-match'\$officialExpansionMods' -and $engineClosure-match'loaded_mods') 'engine-loaded closure assertion is incomplete.'
  Assert-MIR42F200Static ($Text-match'Get-MIR42F200EffectiveEngineLoadedClosure\s+\$seedText\s+seed' -and $Text-match'Get-MIR42F200EffectiveEngineLoadedClosure\s+\$cappedText\s+capped' -and $Text-match'Get-MIR42F200EffectiveEngineLoadedClosure\s+\$relaxedText\s+relaxed') 'engine-loaded closure is not asserted for every stage.'
  Assert-MIR42F200Static ($Text-match'declared_base_only_mod_closure\s*=\s*\[ordered\]@\{' -and $Text-match'effective_engine_loaded_closure\s*=\s*\$effectiveEngineLoadedClosure' -and $Text-match'mod_list_contract\s*=\s*\$stageModListContracts') 'result.json does not retain declared and effective base-only closure evidence.'
}

Assert-MIR42F200Static (Test-Path -LiteralPath $harnessPath -PathType Leaf) 'runtime harness is absent.'
$harnessText=Get-Content -Raw -LiteralPath $harnessPath
Assert-MIR42F200BaseOnlyHarnessContract $harnessText
$disabledExpansionRemoved=$harnessText.Replace('enabled=$false','enabled=$true')
Assert-MIR42F200Static ($disabledExpansionRemoved-cne$harnessText) 'static negative control could not remove the disabled-expansion guard.'
$rejected=$false;try{Assert-MIR42F200BaseOnlyHarnessContract $disabledExpansionRemoved}catch{$rejected=$true}
Assert-MIR42F200Static $rejected 'static contract accepted a harness with expansions enabled.'
$closureReceiptRemoved=$harnessText.Replace('effective_engine_loaded_closure=$effectiveEngineLoadedClosure','effective_engine_loaded_closure_removed=$effectiveEngineLoadedClosure')
Assert-MIR42F200Static ($closureReceiptRemoved-cne$harnessText) 'static negative control could not remove the effective closure receipt.'
$rejected=$false;try{Assert-MIR42F200BaseOnlyHarnessContract $closureReceiptRemoved}catch{$rejected=$true}
Assert-MIR42F200Static $rejected 'static contract accepted a harness without the effective closure receipt.'
Assert-MIR42F200Static (Test-Path -LiteralPath $fixturesPath -PathType Leaf) 'fixture manifest is absent.'
$fixturesText=Get-Content -Raw -LiteralPath $fixturesPath
Assert-MIR42F200Static ($fixturesText-match'mod_lock:\s+exact-engine-2[.]0[.]77-base-only-explicit-elevated-rails-quality-space-age-disabled') 'fixture manifest does not document the explicit base-only expansion lock.'
Write-Host '[ok] MIR42 F200 settings-cap-transition static base-only closure contract passed.'
