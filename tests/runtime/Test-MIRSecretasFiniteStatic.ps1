# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIRSecretasFiniteContinuation.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message-join'; ')}
foreach($name in @('Assert-Secretas','Assert-SecretasMarker','New-SecretasSelectedFixture')){
  $definitions=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$true))
  if($definitions.Count-ne1){throw "Missing consumed function $name"}
  . ([scriptblock]::Create($definitions[0].Extent.Text))
}
$scratch=Join-Path $repo ('build/tmp/secretas-selected-fixture-'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $repo 'fixtures/assert-secretas-finite-continuation-hotfix'
$selected=New-SecretasSelectedFixture -Source $source -Run $scratch -SelectedTarget f200
$info=Get-Content -LiteralPath (Join-Path $selected 'info.json') -Raw|ConvertFrom-Json
Assert-Secretas ($info.version-ceq'0.1.1'-and$info.factorio_version-ceq'2.0') 'F200 private identity'
Assert-Secretas (($info.dependencies-join'|')-ceq'base = 2.0.77|space-age = 2.0.77|secretas = 1.0.33|pretty-frozeta = 0.1.0|more-infinite-research = 4.2.20002') 'F200 exact dependencies'
$control=Get-Content -LiteralPath (Join-Path $selected 'control.lua') -Raw
Assert-Secretas ($control.Contains('"4.2.20002"')-and$control.Contains('"2.0.77"')-and-not$control.Contains('"2.1.21"')) 'F200 runtime identity'
Assert-Secretas ((New-SecretasSelectedFixture -Source $source -Run $scratch -SelectedTarget f210)-ceq$source) 'F210 source retained'
Write-Output 'MIR-SECRETAS-SELECTED-FIXTURE-CONTROLS-PASS 4 (host only)'
$checks=0
foreach($stage in @('source','reload')){
  Assert-SecretasMarker -Text "[mir-fixture] Secretas finite continuation verified stage=$stage;level=10;bonus=5;" -Stage $stage
  $checks++
  foreach($text in @('',"[mir-fixture] Secretas finite continuation source proof queued level=9", "[mir-fixture] Secretas finite continuation verified stage=$stage;level=9;bonus=5;", '[mir-fixture] complete Space Age state retained technologies=5 recipes=1')){
    $refused=$false
    try{Assert-SecretasMarker -Text $text -Stage $stage}catch{$refused=$_.Exception.Message.StartsWith('[mir422-secretas]')}
    if(-not$refused){throw 'Incomplete or wrong-scenario native marker was accepted'}
    $checks++
  }
}
Write-Output "MIR-SECRETAS-NATIVE-MARKER-CONTROLS-PASS $checks (host only; no Factorio or save evidence)"
