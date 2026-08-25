param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/PreFreezeRelease.ps1')

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$corpusPath=Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Release-Fault-CorpusV1.json'
$corpusJson=Get-Content -Raw -LiteralPath $corpusPath
if(-not($corpusJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-release-fault-corpus-v1.schema.json'))){throw '[mir4-t06-fault-corpus-schema]'}
$corpus=$corpusJson|ConvertFrom-Json -Depth 100
$expectedPhases=@('source-freeze','target-build','target-qualification','preview-assets','independent-verification','release-seal','promotion','target-publication','public-readback','restore-drill')
if((@($corpus.phases.phase|Sort-Object)-join'|')-cne(@($expectedPhases|Sort-Object)-join'|')-or
   @($corpus.phases.phase|Group-Object|Where-Object Count -ne 1).Count-ne0-or
   @($corpus.phases.fault.id|Group-Object|Where-Object Count -ne 1).Count-ne0){throw '[mir4-t06-fault-corpus-closure]'}
foreach($row in @($corpus.phases)){
  foreach($relative in @([string]$row.happy_path.path,[string]$row.fault.assertion_path)){
    $source=Get-Content -Raw -LiteralPath (Join-Path $repo $relative)
    if($source-notmatch[regex]::Escape([string]$row.phase)-or$source-notmatch[regex]::Escape([string]$row.fault.expected_error_prefix)){throw "[mir4-t06-fault-binding] $($row.phase)"}
  }
}

$catalog=Get-Content -Raw -LiteralPath (Join-Path $repo 'validation/tests.yml')|ConvertFrom-Json -Depth 100
$assurance=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/assurance.json')|ConvertFrom-Json -Depth 100
$catalogIds=@($catalog.tests.id)
$profileIds=@($assurance.profiles.'mir4-bootstrap')
foreach($testId in @($corpus.aggregate.required_test_ids)){
  if($testId-notin$catalogIds-or$testId-notin$profileIds){throw "[mir4-t06-required-test-not-planned] $testId"}
}

$maturity=@(Get-MIR4ReleaseWorkflowMaturity -RepoRoot $repo)
if($maturity.Count-ne10-or@($maturity|Where-Object{-not$_.workflow_registered-or-not$_.workflow_fail_closed-or-not$_.workflow_executor_implemented-or-not$_.workflow_dry_run_passed-or-not$_.workflow_production_rehearsal_passed-or$_.workflow_production_authorized}).Count-ne0){throw '[mir4-t06-workflow-maturity]'}
$doctor=Get-MIR4ReleaseDoctor -RepoRoot $repo -Explain
$executorCheck=@($doctor.checks|Where-Object id -eq 'workflow-executor-maturity')
$signingCheck=@($doctor.checks|Where-Object id -eq 'protected-signing-secret')
if($executorCheck.Count-ne1-or[string]$executorCheck[0].status-cne'passed'-or$signingCheck.Count-ne1-or[string]$signingCheck[0].status-cne'blocked'-or
   [bool]$doctor.source_freeze_authorized-or[bool]$doctor.candidate_allocation_authorized-or[bool]$doctor.publication_authorized-or
   [string]$doctor.release_status-cne'blocked'){throw '[mir4-t06-doctor-overclaim]'}

$workflow=Get-Content -Raw -LiteralPath (Join-Path $repo '.github/workflows/validate.yml')
foreach($branch in @('main','dev','legacy')){if($workflow-notmatch("(?m)^\s{6}- "+[regex]::Escape($branch)+"\s*$")){throw "[mir4-t06-ci-integration-branch] $branch"}}
if($workflow-notmatch'(?m)^\s{2}pull_request:\s*$'-or$workflow-match'(?m)^\s{6}- (?:codex|feature|fix)/'){throw '[mir4-t06-ci-duplicate-topic-push]'}

if((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-cne$packageBefore){throw '[mir4-t06-package-mutation]'}
Write-Host '[ok] MIR 4 T06 ten-phase rehearsal, typed fault corpus, truthful doctor maturity, production denial, and single-matrix topic CI passed.'
