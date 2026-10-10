# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIRSecretasFiniteContinuation.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message-join'; ')}
foreach($name in @('Assert-Secretas','Assert-SecretasMarker')){
  $definitions=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$true))
  if($definitions.Count-ne1){throw "Missing consumed function $name"}
  . ([scriptblock]::Create($definitions[0].Extent.Text))
}
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
