# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot 'tools/lib/validation/ResearchAllPerformance.ps1')
$checks=0
function Assert-Observation([bool]$Value,[string]$Message){if(-not$Value){throw $Message};$script:checks++}
$json='{"schema":1,"status":"observed","engine":"2.0.77","mir_version":"4.2.20001","connected_players":0,"observations":[{"phase":"first","completion_events":250,"technologies":250},{"phase":"repeat","completion_events":63,"technologies":250}]}'
# Native Factorio 2.0.77 profiler representation captured in the paired baseline run.
$log="5.906 Script: [mir-research-all] first=Duration: 8.677500ms`n5.908 Script: [mir-research-all] repeat=Duration: 1.018600ms"
$arguments=@{Observation=($json|ConvertFrom-Json);LogText=$log;MirVersion='4.2.20001';EngineVersion='2.0.77'}
$result=@(Read-MIRResearchAllObservation @arguments)
Assert-Observation ($result.Count-eq2-and$result[0].milliseconds-eq8.6775-and$result[1].milliseconds-eq1.0186) 'Native timer values must retain their phase and unit.'
Assert-Observation ($result[0].completion_events-eq250-and$result[1].completion_events-eq63) 'Event counts distinguish work performed.'
foreach($case in @('missing-timer','duplicate-timer','negative-time','wrong-unit','nonfinite-time','missing-repeat','wrong-engine','wrong-package','players','zero-events','wrong-order')){
  $argsCopy=@{};foreach($key in $arguments.Keys){$argsCopy[$key]=$arguments[$key]};$argsCopy.Observation=$json|ConvertFrom-Json
  switch($case){
    'missing-timer' {$argsCopy.LogText='no profiler marker'}
    'duplicate-timer' {$argsCopy.LogText=$log+"`n"+$log}
    'negative-time' {$argsCopy.LogText=$log.Replace('8.677500','-1')}
    'wrong-unit' {$argsCopy.LogText=$log.Replace('ms','s')}
    'nonfinite-time' {$argsCopy.LogText=$log.Replace('8.677500','NaN')}
    'missing-repeat' {$argsCopy.Observation.observations=@($argsCopy.Observation.observations[0])}
    'wrong-engine' {$argsCopy.Observation.engine='2.1.21'}
    'wrong-package' {$argsCopy.Observation.mir_version='4.2.20000'}
    'players' {$argsCopy.Observation.connected_players=1}
    'zero-events' {$argsCopy.Observation.observations[0].completion_events=0}
    'wrong-order' {$argsCopy.Observation.observations[0].phase='repeat'}
  }
  $errorText='';try{Read-MIRResearchAllObservation @argsCopy|Out-Null}catch{$errorText=$_.Exception.Message}
  Assert-Observation ($errorText.StartsWith('[mir-research-all-observation-')) ('Unsafe observation accepted: '+$case)
}
foreach($relative in @('scripts/Measure-MIRPerformanceRegression.ps1','tools/lib/validation/ResearchAllPerformance.ps1')){
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot $relative),[ref]$tokens,[ref]$errors)
  Assert-Observation ($errors.Count-eq0) ('PowerShell parse failure: '+$relative)
}
$refusal=''
$fixtureRoot=Join-Path $RepoRoot ('build/tmp/research-all-fixture-'+[guid]::NewGuid().ToString('N'))
foreach($target in @('f200','f210')){
  $profile=Get-Content -LiteralPath (Join-Path $RepoRoot ('fixtures/run-profiles/research-all-'+$target+'.json')) -Raw|ConvertFrom-Json
  $fixture=New-MIRResearchAllFixtureSource -Root (Join-Path $fixtureRoot $target) -Profile $profile -ControlPath (Join-Path $RepoRoot 'fixtures/performance-regression-probe/research-all.lua')
  $info=Get-Content -LiteralPath (Join-Path $fixture 'info.json') -Raw|ConvertFrom-Json
  Assert-Observation ($info.dependencies.Count-eq2-and$info.dependencies[0]-ceq('base = '+$profile.engine_version)-and$info.dependencies[1]-ceq'more-infinite-research') ('Independent fixture dependencies: '+$target)
  $members=(Get-ChildItem -LiteralPath $fixture -File|Sort-Object Name|ForEach-Object Name)-join','
  Assert-Observation ($members-ceq'control.lua,data.lua,info.json') ('Fixture has runtime and versioned data-stage load entries: '+$target)
  Assert-Observation ((Get-FileHash -LiteralPath (Join-Path $fixture 'control.lua')).Hash-ceq(Get-FileHash -LiteralPath (Join-Path $RepoRoot 'fixtures/performance-regression-probe/research-all.lua')).Hash) ('Prepared fixture runs the canonical observation: '+$target)
}
try{& (Join-Path $RepoRoot 'scripts/Measure-MIRPerformanceRegression.ps1') -RepoRoot $RepoRoot -ExpectedSourceCommit ('1'*40) -ObserveResearchAll}catch{$refusal=$_.Exception.Message}
Assert-Observation ($refusal.StartsWith('[mir-research-all-direct-inputs]')) 'Direct observation must reject missing bindings before output or native work.'
$repo=$RepoRoot
$imports=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.InvocationOperator-eq[Management.Automation.Language.TokenKind]::Dot},$true))
foreach($node in $imports){. ([scriptblock]::Create($node.Extent.Text))}
foreach($target in @('f200','f210')){
  $identity=Resolve-MIR4CanonicalPackageIdentity -RepoRoot $RepoRoot -Target $target -SourceVersion '4.2.1'
  Assert-Observation ($identity.distribution_version-ceq('4.2.'+$target.Substring(1)+'01')) ('Consumer imports its actual candidate identity resolver: '+$target)
}
Write-Output "[ok] Research-all observation: $checks checks; no native process or dependency staging."
