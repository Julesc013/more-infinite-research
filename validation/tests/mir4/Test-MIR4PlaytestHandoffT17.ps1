param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/PreFreezeRelease.ps1')

function Write-TestJson([string]$Path,$Value){
  $parent=Split-Path -Parent $Path
  if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 100)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}

$testBase=Join-Path $repo 'build/mir4/test-t17-playtest-handoff'
$fixture=Join-Path $testBase ([guid]::NewGuid().ToString('N'))
$allowed=[IO.Path]::GetFullPath($testBase).TrimEnd('\')+'\'
$resolvedFixture=[IO.Path]::GetFullPath($fixture)
if(-not($resolvedFixture+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw '[mir4-t17-test-boundary]'}

try{
  New-Item -ItemType Directory -Path $fixture -Force|Out-Null
  $fixtureSchema=Join-Path $fixture 'spec/schemas/mir4-playtest-evidence-v1.schema.json'
  New-Item -ItemType Directory -Path (Split-Path -Parent $fixtureSchema) -Force|Out-Null
  Copy-Item -LiteralPath (Join-Path $repo 'spec/schemas/mir4-playtest-evidence-v1.schema.json') -Destination $fixtureSchema
  $candidate=Join-Path $fixture 'inputs/more-infinite-research_4.0.20000.zip'
  $predecessor=Join-Path $fixture 'inputs/more-infinite-research_2.5.11.zip'
  $engine=Join-Path $fixture 'inputs/factorio.exe'
  New-Item -ItemType Directory -Path (Split-Path -Parent $candidate) -Force|Out-Null
  [IO.File]::WriteAllBytes($candidate,[Text.Encoding]::UTF8.GetBytes('candidate-fixture'))
  [IO.File]::WriteAllBytes($predecessor,[Text.Encoding]::UTF8.GetBytes('predecessor-fixture'))
  [IO.File]::WriteAllBytes($engine,[Text.Encoding]::UTF8.GetBytes('engine-fixture'))
  $candidateSha=Get-MIR4PreFreezeFileSha256 $candidate
  $predecessorSha=Get-MIR4PreFreezeFileSha256 $predecessor
  $engineSha=Get-MIR4PreFreezeFileSha256 $engine
  $packageSourceSha=Get-MIRPackageSourceFingerprint -RepoRoot $fixture

  $planPath=Join-Path $fixture '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json'
  $t15Path=Join-Path $fixture '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json'
  $handoffPath=Join-Path $fixture 'docs/maintainer/mir4-w09-manual-playtest.md'
  Write-TestJson $planPath ([ordered]@{
    schema=1;kind='MIR4PreFreezeDevelopmentPlanV1'
    source_baseline=[ordered]@{branch='dev';commit=('a'*40);tree=('b'*40);package_source_sha256=('c'*64)}
    targets=@([ordered]@{
      target='F200';release_role='mandatory';distribution_version='4.0.20000'
      development_package=[ordered]@{sha256=$candidateSha;content_sha256=('d'*64);bytes=(Get-Item $candidate).Length;entry_count=1;release_identity=$false}
      engine=[ordered]@{version='2.0.test';path=$engine;sha256=$engineSha}
      predecessor=[ordered]@{release='2.5.11';path=$predecessor;sha256=$predecessorSha;content_sha256=('e'*64)}
    })
    verification_plan=[ordered]@{profile='fixture';plan_sha256=('f'*64);plan_material_sha256=('1'*64);required_test_set_sha256=('2'*64);bundle_sha256=('3'*64);total=1;passed=1;failed=0;invalid=0}
  })
  Write-TestJson $t15Path ([ordered]@{schema=1;kind='MIR4T15AuthorityEvolutionReceiptV1';player_package_source_sha256=$packageSourceSha})
  New-Item -ItemType Directory -Path (Split-Path -Parent $handoffPath) -Force|Out-Null
  [IO.File]::WriteAllText($handoffPath,"---`ntitle: fixture`n---`n",[Text.UTF8Encoding]::new($false))

  $session=New-MIR4PlaytestSession -RepoRoot $fixture -Target F200 -CandidatePath $candidate -PredecessorPath $predecessor -FactorioBin $engine -OutputRoot 'build/mir4/playtests/f200/fixture'
  $sessionRoot=[string]$session.session_root
  foreach($path in @(
    (Join-Path $sessionRoot 'session.json'),
    (Join-Path $sessionRoot 'review-checklist.md'),
    (Join-Path $sessionRoot 'Invoke-MIR4PlaytestEngine.ps1'),
    (Join-Path $sessionRoot 'profile/config.ini'),
    (Join-Path $sessionRoot 'profile/mods/mod-list.json'),
    (Join-Path $sessionRoot 'observations.json'),
    (Join-Path $sessionRoot 'manual-decision.template.json')
  )){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-t17-prepared-file] $path"}}
  if([string]$session.status-cne'prepared'-or@($session.expected_scenarios).Count-ne11-or
     [bool]$session.decision_inferred-or[bool]$session.production_release_authorized-or
     (Get-MIR4PreFreezeFileSha256 ([string]$session.engine_command.launcher))-cne[string]$session.engine_command.launcher_sha256){
    throw '[mir4-t17-session-contract]'
  }
  $template=Get-Content -Raw -LiteralPath (Join-Path $sessionRoot 'manual-decision.template.json')|ConvertFrom-Json
  if([bool]$template.valid_evidence-or$null-ne$template.decision-or[bool]$template.production_release_authorized){throw '[mir4-t17-decision-template-boundary]'}

  $queue=[string]$session.profile.capture_queue
  [IO.File]::WriteAllText((Join-Path $queue 'logs/factorio-current.log'),'fixture log',[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllBytes((Join-Path $queue 'saves/upgrade.zip'),[Text.Encoding]::UTF8.GetBytes('save-fixture'))
  [IO.File]::WriteAllText((Join-Path $queue 'notes/reviewer.md'),'fixture note',[Text.UTF8Encoding]::new($false))
  $pending=Capture-MIR4PlaytestSession -RepoRoot $fixture -SessionRoot $sessionRoot -DryRun
  if([string]$pending.comparison.status-cne'INCOMPLETE'-or[int]$pending.comparison.pending-ne11){throw '[mir4-t17-pending-comparison]'}

  $observationsPath=Join-Path $sessionRoot 'observations.json'
  $observations=Get-Content -Raw -LiteralPath $observationsPath|ConvertFrom-Json -Depth 100
  foreach($row in @($observations.scenarios)){$row.status='PASSED';$row.notes='fixture-only explicit observation'}
  $observations.status='review-complete'
  Write-TestJson $observationsPath $observations
  $capture=Capture-MIR4PlaytestSession -RepoRoot $fixture -SessionRoot $sessionRoot
  if([string]$capture.status-cne'ready-for-maintainer-decision'-or[string]$capture.comparison.status-cne'MATCHED'-or
     @($capture.missing_capture_requirements).Count-ne0-or@($capture.files).Count-ne4){throw '[mir4-t17-capture-contract]'}
  $summary=Get-Content -Raw -LiteralPath (Join-Path $sessionRoot 'result-summary.json')|ConvertFrom-Json -Depth 100
  if([string]$summary.status-cne'ready-for-maintainer-decision'-or[bool]$summary.decision_inferred-or[bool]$summary.production_release_authorized){throw '[mir4-t17-summary-contract]'}

  $plannedDecision=Complete-MIR4PlaytestSession -RepoRoot $fixture -SessionRoot $sessionRoot -Decision ACCEPTED -Reviewer 'fixture-explicit-reviewer' -DryRun
  if([string]$plannedDecision.status-cne'planned'-or[bool]$plannedDecision.decision_inferred-or[bool]$plannedDecision.source_freeze_authorized-or[bool]$plannedDecision.production_release_authorized){throw '[mir4-t17-planned-decision-boundary]'}
  $decision=Complete-MIR4PlaytestSession -RepoRoot $fixture -SessionRoot $sessionRoot -Decision CHANGES-REQUESTED -Reviewer 'fixture-explicit-reviewer' -Notes 'fixture only'
  if([string]$decision.decision-cne'CHANGES-REQUESTED'-or[bool]$decision.decision_inferred-or[bool]$decision.source_freeze_authorized-or[bool]$decision.production_release_authorized){throw '[mir4-t17-explicit-decision-boundary]'}
  if(-not(Test-Path -LiteralPath (Join-Path $sessionRoot 'manual-decision.json') -PathType Leaf)){throw '[mir4-t17-decision-write]'}
  $schema=Join-Path $repo 'spec/schemas/mir4-playtest-evidence-v1.schema.json'
  foreach($evidencePath in @('session.json','observations.json','capture.json','result-summary.json','manual-decision.json')){
    $json=Get-Content -Raw -LiteralPath (Join-Path $sessionRoot $evidencePath)
    if(-not($json|Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)){throw "[mir4-t17-evidence-schema] $evidencePath"}
  }
  $templateJson=Get-Content -Raw -LiteralPath (Join-Path $sessionRoot 'manual-decision.template.json')
  if($templateJson|Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue){throw '[mir4-t17-template-accepted-as-evidence]'}

  $f210=@(Get-MIR4PlaytestScenarioContract -Target F210)
  if($f210.Count-ne13-or'cubium-canary'-notin@($f210.id)-or'bounded-k2so'-notin@($f210.id)){throw '[mir4-t17-f210-scenario-contract]'}
  Write-Host '[ok] MIR 4 T17 playtest handoff prepares exact isolated sessions, compares complete evidence, and requires an explicit non-release human decision.'
}finally{
  if(Test-Path -LiteralPath $fixture){
    $resolved=[IO.Path]::GetFullPath($fixture)
    if(-not($resolved+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw '[mir4-t17-test-cleanup-boundary]'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
