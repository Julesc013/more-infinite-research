# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

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
  $authoritySchema=Join-Path $fixture 'spec/schemas/mir4-final-mile-playtest-candidate-authority-v1.schema.json'
  $authorizationSchema=Join-Path $fixture 'spec/schemas/mir4-maintainer-final-github-release-authorization-v1.schema.json'
  New-Item -ItemType Directory -Path (Split-Path -Parent $fixtureSchema) -Force|Out-Null
  Copy-Item -LiteralPath (Join-Path $repo 'spec/schemas/mir4-playtest-evidence-v1.schema.json') -Destination $fixtureSchema
  Copy-Item -LiteralPath (Join-Path $repo 'spec/schemas/mir4-final-mile-playtest-candidate-authority-v1.schema.json') -Destination $authoritySchema
  Copy-Item -LiteralPath (Join-Path $repo 'spec/schemas/mir4-maintainer-final-github-release-authorization-v1.schema.json') -Destination $authorizationSchema
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

  $planPath=Join-Path $fixture '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Playtest-Candidate-AuthorityV1.json'
  $authorizationPath=Join-Path $fixture '.mir/releases/waves/mir4-r0/MIR4-Maintainer-Final-GitHub-Release-AuthorizationV1.json'
  $candidateManifestPath=Join-Path $fixture 'build/mir4/fixture/candidate-manifest.json'
  $f210AssurancePath=Join-Path $fixture 'build/results/assurance/fixture/f210-assurance.json'
  $f200AssurancePath=Join-Path $fixture 'build/results/assurance/fixture/f200-assurance.json'
  $t15Path=Join-Path $fixture '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json'
  $handoffPath=Join-Path $fixture 'docs/maintainer/mir4-w09-manual-playtest.md'
  Write-TestJson $authorizationPath ([ordered]@{
    schema=1;kind='MIR4MaintainerChatReleaseAuthorizationV1';status='maintainer-instruction-to-be-materialized-through-governed-local-receipts'
    recorded_from_user_turn_date='2026-08-30';timezone='fixture';maintainer=[ordered]@{display_name='fixture';github_login='fixture'}
    repository='Julesc013/more-infinite-research'
    starting_source=[ordered]@{branch='dev';commit=('a'*40);tree=('b'*40);package_source_sha256=$packageSourceSha}
    playtest_decisions=@(
      [ordered]@{target='F210';distribution='4.0.21000';decision='ACCEPTED';candidate_zip_sha256=$candidateSha;content_root=('D'*64);engine=[ordered]@{version='2.1.test';build='1';executable_sha256=$engineSha}},
      [ordered]@{target='F200';distribution='4.0.20000';decision='ACCEPTED';candidate_zip_sha256=$candidateSha;content_root=('D'*64);engine=[ordered]@{version='2.0.test';build='1';executable_sha256=$engineSha}}
    )
    additional_github_targets=@(
      [ordered]@{target='F110';distribution='4.0.11000';publish_if_exact_proof_remains_green=$true;candidate_zip_sha256=('1'*64);content_root=('2'*64);engine_version='1.1.test';engine_executable_sha256=('3'*64)},
      [ordered]@{target='F100';distribution='4.0.10000';publish_if_exact_proof_remains_green=$true;candidate_zip_sha256=('4'*64);content_root=('5'*64);engine_version='1.0.test';engine_executable_sha256=('6'*64)}
    )
    release_authorization=[ordered]@{
      source_version='4.0.0';candidate='M4RC1';source_freeze='AUTHORIZED-CONDITIONALLY';production_signing='AUTHORIZED-AFTER-T16-AND-FROZEN-PROOF-CLOSURE'
      seal='AUTHORIZED-AFTER-EXACT-HASH-MATCH';main_promotion='AUTHORIZED-AFTER-SEAL-AND-OFFLINE-RESTORE';tagging='AUTHORIZED-AFTER-PROMOTION-GATE'
      github_publication='AUTHORIZED';mod_portal_publication='DEFERRED-TO-MAINTAINER'
      github_assets=[ordered]@{player_targets=@('F210','F200','F110','F100');developer_preview_assets=@('mir4-api-sdk-v1-preview.zip','mir4-mep-v1-preview.zip','mir4-reference-extension-v1-preview.zip','mir4-inspector-v1-preview.zip')}
    }
    conditions=@('fixture-1','fixture-2','fixture-3','fixture-4','fixture-5','fixture-6','fixture-7','fixture-8')
    secret_values_present=$false;warning='fixture only'
  })
  Write-TestJson $candidateManifestPath ([ordered]@{
    local_distribution=[ordered]@{archive_sha256=$candidateSha;content_sha256=('D'*64);bytes=(Get-Item $candidate).Length;entry_count=1}
  })
  Write-TestJson $f210AssurancePath ([ordered]@{
    status='passed';counts=[ordered]@{expected=1;failed=0;incomplete=0}
    plan=[ordered]@{target='2.1';package_source_sha256=$packageSourceSha;domain_manifest=[ordered]@{artifact=[ordered]@{sha256=$candidateSha;content_sha256=('D'*64)}}}
  })
  Write-TestJson $f200AssurancePath ([ordered]@{
    status='passed';counts=[ordered]@{expected=1;failed=0;incomplete=0}
    plan=[ordered]@{target='2.0';package_source_sha256=$packageSourceSha;domain_manifest=[ordered]@{artifact=[ordered]@{sha256=$candidateSha;content_sha256=('D'*64)}}}
  })
  $authorizationItem=Get-Item -LiteralPath $authorizationPath
  $candidateManifestItem=Get-Item -LiteralPath $candidateManifestPath
  $f210AssuranceItem=Get-Item -LiteralPath $f210AssurancePath
  $f200AssuranceItem=Get-Item -LiteralPath $f200AssurancePath
  Write-TestJson $planPath ([ordered]@{
    schema=1;kind='MIR4FinalMilePlaytestCandidateAuthorityV1';recorded_at=[DateTime]::UtcNow.ToString('o')
    programme_id='M4C10-WHOLE-4X-IN-4.0';status='EXACT-F210-F200-CANDIDATES-ADMITTED-FOR-PLAYTEST-RECEIPT-MATERIALIZATION'
    source_baseline=[ordered]@{branch='dev';commit=('a'*40);tree=('b'*40);package_source_sha256=$packageSourceSha}
    authorization=[ordered]@{path='.mir/releases/waves/mir4-r0/MIR4-Maintainer-Final-GitHub-Release-AuthorizationV1.json';bytes=$authorizationItem.Length;sha256=(Get-MIR4PreFreezeFileSha256 $authorizationItem.FullName)}
    targets=@([ordered]@{
      target='F210';distribution_version='4.0.21000'
      development_package=[ordered]@{sha256=$candidateSha;content_sha256=('D'*64);bytes=(Get-Item $candidate).Length;entry_count=1;release_identity=$false}
      engine=[ordered]@{version='2.1.test';build=1;path=$engine;sha256=$engineSha;steam_build=$null}
      predecessor=[ordered]@{release='3.2.11';path=$predecessor;sha256=$predecessorSha;content_sha256=('E'*64)}
      candidate_manifest=[ordered]@{path='build/mir4/fixture/candidate-manifest.json';bytes=$candidateManifestItem.Length;sha256=(Get-MIR4PreFreezeFileSha256 $candidateManifestItem.FullName)}
      assurance=[ordered]@{path='build/results/assurance/fixture/f210-assurance.json';bytes=$f210AssuranceItem.Length;sha256=(Get-MIR4PreFreezeFileSha256 $f210AssuranceItem.FullName);status='passed';expected=1;failed=0;incomplete=0}
    },[ordered]@{
      target='F200';distribution_version='4.0.20000'
      development_package=[ordered]@{sha256=$candidateSha;content_sha256=('D'*64);bytes=(Get-Item $candidate).Length;entry_count=1;release_identity=$false}
      engine=[ordered]@{version='2.0.test';build=1;path=$engine;sha256=$engineSha;steam_build=$null}
      predecessor=[ordered]@{release='2.5.11';path=$predecessor;sha256=$predecessorSha;content_sha256=('E'*64)}
      candidate_manifest=[ordered]@{path='build/mir4/fixture/candidate-manifest.json';bytes=$candidateManifestItem.Length;sha256=(Get-MIR4PreFreezeFileSha256 $candidateManifestItem.FullName)}
      assurance=[ordered]@{path='build/results/assurance/fixture/f200-assurance.json';bytes=$f200AssuranceItem.Length;sha256=(Get-MIR4PreFreezeFileSha256 $f200AssuranceItem.FullName);status='passed';expected=1;failed=0;incomplete=0}
    })
    transition_gate=[ordered]@{source_freeze=$false;candidate_allocation=$false;production_signing=$false;production_seal=$false;promotion_to_main=$false;tagging=$false;publication=$false}
    secret_values_present=$false
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
