# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$path=Join-Path $repo 'tests/runtime/Test-MIRModernLaunchReturn.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message-join'; ')}
foreach($name in @('Assert-Launch','Read-LaunchObservation','Assert-LaunchProduction')){
  $functions=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
  if($functions.Count-ne1){throw "Missing consumed function $name"}
  . ([scriptblock]::Create($functions[0].Extent.Text))
}
$checks=0
function Reject-Launch([scriptblock]$Action){
  $rejected=$false
  try{& $Action}catch{$rejected=$true}
  if(-not$rejected){throw 'Corrupt launch observation accepted'}
  $script:checks++
}
$scenario=Get-Content -LiteralPath (Join-Path $repo 'fixtures/assert-modern-launch-return/scenario.json') -Raw|ConvertFrom-Json
Assert-Launch ($scenario.source_version-ceq'4.2.2'-and$scenario.settings_mode-ceq'Defaults'-and$scenario.required_reload_count-eq1) 'scenario scope differs'
foreach($target in @('f200','f210')){
  $binding=$scenario.targets.$target
  $mir='4.2.'+$target.Substring(1)+'02'
  $row=[ordered]@{stage='production';base=$binding.engine_version;mir=$mir;phase='complete';crafts=100;rockets_launched=1;return_count=1000;launch_ordered=$true;lab_transfer=1;pad_count=999;technology='research-speed-7';progress=0.001;saved_progress=0.001;feed_remaining=@{'processing-unit'=0;'low-density-structure'=0;'rocket-fuel'=0};consumed=@{'processing-unit'=1000;'low-density-structure'=1000;'rocket-fuel'=1000}}
  $log='0.1 Script @fixture/control.lua: [mir-a04-launch] RESULT '+($row|ConvertTo-Json -Depth 5 -Compress)
  $parsed=Read-LaunchObservation $log production
  Assert-LaunchProduction $parsed production $binding.engine_version $mir
  $checks++
  Reject-Launch {Read-LaunchObservation ($log+"`n"+$log) production}
  Reject-Launch {Read-LaunchObservation $log reload}
  foreach($property in @('crafts','rockets_launched','return_count','pad_count','lab_transfer','progress','saved_progress','launch_ordered','technology','base','mir')){
    $changed=$row|ConvertTo-Json -Depth 5|ConvertFrom-Json
    $changed.$property=if($property-eq'launch_ordered'){$false}elseif($property-in@('technology','base','mir')){'wrong'}else{0}
    Reject-Launch {Assert-LaunchProduction $changed production $binding.engine_version $mir}
  }
  foreach($name in @('processing-unit','low-density-structure','rocket-fuel')){
    $changed=$row|ConvertTo-Json -Depth 5|ConvertFrom-Json
    $changed.consumed.$name=999
    Reject-Launch {Assert-LaunchProduction $changed production $binding.engine_version $mir}
    $changed.consumed.$name=1000;$changed.feed_remaining.$name=1
    Reject-Launch {Assert-LaunchProduction $changed production $binding.engine_version $mir}
  }
}
Write-Output "MIR-MODERN-LAUNCH-OBSERVATION-CONTROLS-PASS $checks (host only; native and Lua fixture execution are separate)"
