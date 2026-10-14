# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$tokens=$null;$errors=$null
$runner=Join-Path $repo 'tests/runtime/Test-MIRSecretasFiniteContinuation.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message-join'; ')}
foreach($name in @('Assert-Secretas','Assert-SecretasMarker','New-SecretasSelectedFixture')){
  $definitions=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$true))
  if($definitions.Count-ne1){throw "Missing consumed function $name"}
  . ([scriptblock]::Create($definitions[0].Extent.Text))
}
$scratch=Join-Path $repo ('build/tmp/secretas-selected-fixture-'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $repo 'fixtures/assert-secretas-finite-continuation-hotfix'
$fixtureCases=@(
  [ordered]@{target='f210';source='4.2.2';mir='4.2.21002';fixture='0.1.2';factorio='2.1';retained=$true;deps='base = 2.1.21|space-age = 2.1.21|secretas = 1.0.37|pretty-frozeta = 1.0.1|more-infinite-research = 4.2.21002'},
  [ordered]@{target='f200';source='4.2.2';mir='4.2.20002';fixture='0.1.3';factorio='2.0';retained=$false;deps='base = 2.0.77|space-age = 2.0.77|secretas = 1.0.33|pretty-frozeta = 0.1.0|more-infinite-research = 4.2.20002'},
  [ordered]@{target='f210';source='4.4.0';mir='4.4.21000';fixture='0.1.4';factorio='2.1';retained=$false;deps='base = 2.1.21|space-age = 2.1.21|secretas = 1.0.37|pretty-frozeta = 1.0.1|more-infinite-research = 4.4.21000'},
  [ordered]@{target='f200';source='4.4.0';mir='4.4.20000';fixture='0.1.5';factorio='2.0';retained=$false;deps='base = 2.0.77|space-age = 2.0.77|secretas = 1.0.33|pretty-frozeta = 0.1.0|more-infinite-research = 4.4.20000'}
)
$fixtureChecks=0
foreach($case in $fixtureCases){
  $selected=New-SecretasSelectedFixture -Source $source -Run (Join-Path $scratch ($case.target+'-'+$case.source)) -SelectedTarget $case.target -SelectedSourceVersion $case.source -SelectedMIRVersion $case.mir
  Assert-Secretas (($selected-ceq$source)-eq[bool]$case.retained) ('retained fixture selection '+$case.target+'/'+$case.source)
  $info=Get-Content -LiteralPath (Join-Path $selected 'info.json') -Raw|ConvertFrom-Json
  Assert-Secretas ($info.version-ceq$case.fixture-and$info.factorio_version-ceq$case.factorio-and($info.dependencies-join'|')-ceq$case.deps) ('selected fixture identity '+$case.target+'/'+$case.source)
  $control=Get-Content -LiteralPath (Join-Path $selected 'control.lua') -Raw
  Assert-Secretas ($control.Contains('local MIR_VERSION = "'+$case.mir+'"')) ('selected fixture control identity '+$case.target+'/'+$case.source)
  $fixtureChecks+=3
}
foreach($wrong in @(
  @{target='f210';source='4.4.0';mir='4.4.20000'},
  @{target='f200';source='4.4.0';mir='4.4.21000'}
)){
  $refused=$false
  try{New-SecretasSelectedFixture -Source $source -Run $scratch -SelectedTarget $wrong.target -SelectedSourceVersion $wrong.source -SelectedMIRVersion $wrong.mir|Out-Null}catch{$refused=$_.Exception.Message-ceq'[mir422-secretas] selected fixture candidate version differs'}
  if(-not$refused){throw 'Cross-target current fixture candidate was accepted'}
  $fixtureChecks++
}
Write-Output "MIR-SECRETAS-SELECTED-FIXTURE-CONTROLS-PASS $fixtureChecks (host only)"
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
