# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/PreFreezeRelease.ps1')

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$canonicalProbeRoot=Join-Path $repo ('build/mir4/release-phase-engine/tests/t06-canonical-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $canonicalProbeRoot -Force|Out-Null
$lfProbe=Join-Path $canonicalProbeRoot 'lf.txt';$crlfProbe=Join-Path $canonicalProbeRoot 'crlf.txt'
[IO.File]::WriteAllText($lfProbe,"alpha`nbeta`n",[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($crlfProbe,"alpha`r`nbeta`r`n",[Text.UTF8Encoding]::new($false))
if((Get-MIR4PreFreezeFileSha256 -Path $lfProbe -Mode canonical-text-v1)-cne(Get-MIR4PreFreezeFileSha256 -Path $crlfProbe -Mode canonical-text-v1)-or
   (Get-MIR4PreFreezeFileSha256 -Path $lfProbe -Mode raw-bytes)-ceq(Get-MIR4PreFreezeFileSha256 -Path $crlfProbe -Mode raw-bytes)){throw '[mir4-t06-canonical-text-hash]'}
$corpusPath=Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Release-Fault-CorpusV1.json'
$corpusJson=Get-Content -Raw -LiteralPath $corpusPath
if(-not($corpusJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-release-fault-corpus-v1.schema.json'))){throw '[mir4-t06-fault-corpus-schema]'}
$corpus=$corpusJson|ConvertFrom-Json -Depth 100
$expectedPhases=@('source-freeze','target-build','target-qualification','preview-assets','independent-verification','release-seal','promotion','target-publication','public-readback','restore-drill')
if((@($corpus.phases.phase|Sort-Object)-join'|')-cne(@($expectedPhases|Sort-Object)-join'|')-or
   @($corpus.phases.phase|Group-Object|Where-Object Count -ne 1).Count-ne0-or
   @($corpus.phases.fault.id|Group-Object|Where-Object Count -ne 1).Count-ne0){throw '[mir4-t06-fault-corpus-closure]'}

# T06 is a historical release-fault corpus.  Its original proof locators are
# deliberately byte-preserved, while M42-01B is the sole authority that moved
# canonical executable tests from validation/tests to tests.  Do not silently
# rewrite the corpus or use a broad path substitution: each missing locator
# must have exactly one authenticated M42-01B relocation to a canonical test.
$workflowConvergencePath=Join-Path $repo 'releases/migrations/MIR4-M42-01B-Test-Workflow-ConvergenceV1.json'
if(-not(Test-Path -LiteralPath $workflowConvergencePath -PathType Leaf)){throw '[mir4-t06-fault-binding-relocation-authority]'}
$workflowConvergence=Get-Content -Raw -LiteralPath $workflowConvergencePath|ConvertFrom-Json -Depth 100
if([string]$workflowConvergence.kind-cne'MIR4M4201BTestWorkflowConvergenceV1'-or
   -not(Test-MIR4BootstrapRecordHash -Record $workflowConvergence)){throw '[mir4-t06-fault-binding-relocation-authority]'}
$relocations=@($workflowConvergence.relocated_bindings)
$expectedCanonicalProofSha256=@{
  'tests/mir4/Test-MIR4ReleaseAdaptersT03.ps1'='319060667FF7DB328106A14CC12EB1CBABDE605635479F8E3CF5103F8E166C17'
  'tests/mir4/Test-MIR4ReleaseAdaptersT04.ps1'='7BEF2BEF656D64F588CAF18DFC04E5FE8B14A676F6BE0D61D96881E322BA62C4'
  'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'='8ECA00F8BD5B3D98806B3E260478C77D0D21CD90D2543DE633C88D8F1FEA6747'
}
# M42-01B's current_sha256 values describe the relocation instant.  Later
# append-only authority records may evolve a canonical test, so T06 pins the
# current proof bytes separately and requires an intentional update here.

function Resolve-MIR4T06HistoricalProofPath([string]$RelativePath,[object[]]$RelocationBindings,[hashtable]$ExpectedCanonicalSha256){
  $directPath=Join-Path $repo $RelativePath
  if(Test-Path -LiteralPath $directPath -PathType Leaf){
    if($RelativePath-match'^validation/tests/'){throw "[mir4-t06-fault-binding-relocation-direct] $RelativePath"}
    return [pscustomobject]@{relative_path=$RelativePath;full_path=$directPath;relocated=$false}
  }
  $matches=@($RelocationBindings|Where-Object{[string]$_.from_path-ceq$RelativePath})
  if($matches.Count-ne1){throw "[mir4-t06-fault-binding-relocation-cardinality] $RelativePath"}
  $binding=$matches[0]
  $targetRelative=[string]$binding.to_path
  if([string]$binding.from_path-cne$RelativePath-or$targetRelative-notmatch'^tests/mir4/Test-MIR4Release(?:AdaptersT0[345]|DoctorT06)\.ps1$' -or
     [string]$binding.previous_git_blob-notmatch'^[0-9a-f]{40}$' -or
     [string]$binding.previous_sha256-notmatch'^[A-F0-9]{64}$' -or
     [string]$binding.current_sha256-notmatch'^[A-F0-9]{64}$' -or
     [string]$binding.hash_mode-cne'canonical-text-v1'){
    throw "[mir4-t06-fault-binding-relocation-hash] $RelativePath"
  }
  $targetPath=Join-Path $repo $targetRelative
  if(-not(Test-Path -LiteralPath $targetPath -PathType Leaf)){throw "[mir4-t06-fault-binding-relocation-target] $targetRelative"}
  if(-not$ExpectedCanonicalSha256.ContainsKey($targetRelative)-or
     (Get-MIR4PreFreezeFileSha256 -Path $targetPath -Mode canonical-text-v1)-cne[string]$ExpectedCanonicalSha256[$targetRelative]){
    throw "[mir4-t06-fault-binding-relocation-hash] $targetRelative"
  }
  return [pscustomobject]@{relative_path=$targetRelative;full_path=$targetPath;relocated=$true}
}

# Counterexamples prove that an absent, ambiguous, or hash-inconsistent
# relocation cannot be treated as a current proof target.
$referenceRelocation=@($relocations|Where-Object{[string]$_.from_path-ceq'validation/tests/mir4/Test-MIR4ReleaseAdaptersT03.ps1'})
if($referenceRelocation.Count-ne1){throw '[mir4-t06-fault-binding-relocation-reference]'}
foreach($counterexample in @(
  @{bindings=@();code='[mir4-t06-fault-binding-relocation-cardinality]'},
  @{bindings=@($referenceRelocation[0],$referenceRelocation[0]);code='[mir4-t06-fault-binding-relocation-cardinality]'},
  @{bindings=@($referenceRelocation[0]);expected=@{'tests/mir4/Test-MIR4ReleaseAdaptersT03.ps1'=('0'*64)};code='[mir4-t06-fault-binding-relocation-hash]'}
)){
  $counterexampleExpected=if($counterexample.ContainsKey('expected')){$counterexample.expected}else{$expectedCanonicalProofSha256}
  try{[void](Resolve-MIR4T06HistoricalProofPath -RelativePath 'validation/tests/mir4/Test-MIR4ReleaseAdaptersT03.ps1' -RelocationBindings $counterexample.bindings -ExpectedCanonicalSha256 $counterexampleExpected);throw '[mir4-t06-fault-binding-relocation-counterexample-accepted]'}
  catch{
    if(-not$_.Exception.Message.StartsWith([string]$counterexample.code,[StringComparison]::Ordinal)){throw}
  }
}
foreach($row in @($corpus.phases)){
  foreach($relative in @([string]$row.happy_path.path,[string]$row.fault.assertion_path)){
    $proof=Resolve-MIR4T06HistoricalProofPath -RelativePath $relative -RelocationBindings $relocations -ExpectedCanonicalSha256 $expectedCanonicalProofSha256
    $source=Get-Content -Raw -LiteralPath $proof.full_path
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
$t06Receipt=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T06-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if(@($t06Receipt.current_authorities|Where-Object hash_mode -eq 'canonical-text-v1').Count-ne4-or
   @($t06Receipt.current_authorities|Where-Object hash_mode -eq 'raw-bytes').Count-ne6){throw '[mir4-t06-authority-hash-modes]'}
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
