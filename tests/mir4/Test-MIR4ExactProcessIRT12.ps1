# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,[switch]$CaptureConsumerOnly)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/processir/ExactProcessIR.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/inspection/Inspector.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PackagePresentation.ps1')

if(-not$CaptureConsumerOnly){
$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
$authority=Get-MIR4T12Authority -RepoRoot $RepoRoot
if(@($authority.captures).Count-ne 11-or[int]$authority.required_repetitions-ne 2-or[int]$authority.maximum_processes_per_capture-ne 128){throw '[mir4-t12-authority-matrix]'}
foreach($flag in @('semantic_authority','player_mutation_authorized','prototype_write_authorized','planner_or_emitter_admission_authorized','automatic_synthesis_authorized','public_support_authorized','release_admission_authorized','signing_or_sealing_authorized','publication_authorized')){if([bool]$authority.$flag){throw "[mir4-t12-authority-boundary] $flag"}}

$reference=Join-Path $RepoRoot 'sdk/preview/mir4/reference/t12'
& (Join-Path $RepoRoot 'tools/mir/cli/Export-MIR4ExactProcessIRRecords.ps1') -RepoRoot $RepoRoot -ReferenceRoot 'sdk/preview/mir4/reference/t12' -Check|Out-Null
$manifest=Get-Content -Raw -LiteralPath (Join-Path $reference 'MIR4_T12_EXACT_PROCESSIR_MANIFEST.json')|ConvertFrom-Json -Depth 100
$receipt=Get-Content -Raw -LiteralPath (Join-Path $reference 'MIR4_T12_RECEIPT.json')|ConvertFrom-Json -Depth 100
if(-not$manifest.complete-or[int]$manifest.capture_count-ne 10-or[int]$manifest.blocker_count-ne 1-or[int]$manifest.comparison_count-ne 8-or[int]$manifest.inspector_bundle_count-ne 8){throw '[mir4-t12-manifest-counts]'}
if([string]$receipt.status-cne'completed-machine-work-with-custody-blocker'-or[int]$receipt.capture_count-ne 10-or[int]$receipt.required_capture_count-ne 11-or[int]$receipt.blocker_count-ne 1-or[int]$receipt.repetitions-ne 2-or-not$receipt.all_deterministic-or[int]$receipt.comparison_count-ne 8-or[int]$receipt.inspector_bundle_count-ne 8-or[string]$receipt.exact_target_processir_status-cne'CAPTURED-EXACT-F210-F200-PROCESSIR-PREVIEW-WITH-DECLARED-CUSTODY-BLOCKER'){throw '[mir4-t12-receipt]'}
if(-not(($receipt|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-t12-receipt-v1.schema.json'))){throw '[mir4-t12-receipt-schema]'}
if([string]$receipt.digest-cne(Get-MIR4T12RecordDigest -Value $receipt -Domain 'mir4:t12-receipt:1')-or-not$receipt.package_source_unchanged-or$receipt.package_visible-or$receipt.player_mutation_authorized-or$receipt.prototype_write_authorized-or$receipt.planner_or_emitter_admission_authorized-or$receipt.public_support_authorized-or$receipt.release_admission_authorized){throw '[mir4-t12-receipt-boundary]'}

$blockers=@(Get-ChildItem -LiteralPath (Join-Path $reference 'blockers') -File -Filter '*.json')
if($blockers.Count-ne 1-or$blockers[0].BaseName-cne'f200-k2so'){throw '[mir4-t12-custody-blocker-count]'}
$blocker=Get-Content -Raw -LiteralPath $blockers[0].FullName|ConvertFrom-Json -Depth 100
if([string]$blocker.status-cne'blocked-exact-archive-custody'-or$blocker.fabricated_substitute-or-not([string]$blocker.reason).StartsWith('[mir4-t12-exact-archive-missing]')){throw '[mir4-t12-custody-blocker-truth]'}

$snapshots=@(Get-ChildItem -LiteralPath (Join-Path $reference 'snapshots') -File -Filter '*.json')
if($snapshots.Count-ne 10-or@('f210-base','f210-official','f200-base','f200-official'|Where-Object{"$_.json"-notin@($snapshots.Name)}).Count){throw '[mir4-t12-mandatory-snapshots]'}
foreach($file in $snapshots){
  $snapshot=Get-Content -Raw -LiteralPath $file.FullName|ConvertFrom-Json -Depth 100
  if(-not(($snapshot|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-exact-process-ir-snapshot-v1.schema.json'))-or[string]$snapshot.digest-cne(Get-MIR4T12RecordDigest $snapshot)){throw "[mir4-t12-snapshot-schema] $($file.Name)"}
  if([int]$snapshot.observer.repetitions-ne 2-or-not$snapshot.observer.deterministic-or@($snapshot.process_ir.processes).Count-lt 1-or-not$snapshot.explicit_unavailable_not_zero-or-not$snapshot.terminal_fact_authority_preserved-or$snapshot.authoritative-or$snapshot.package_visible-or$snapshot.public_release_proof-or$snapshot.player_mutation_authorized-or$snapshot.prototype_write_authorized-or$snapshot.planner_or_emitter_admission_authorized-or$snapshot.public_support_authorized){throw "[mir4-t12-snapshot-boundary] $($file.Name)"}
  if(@($snapshot.process_ir.processes|Where-Object{[string]$_.source_mod.status-cne'unavailable'}).Count){throw "[mir4-t12-source-mod-unavailable] $($file.Name)"}
  if(@($snapshot.transport_omissions|Where-Object{[string]$_.status-cne'unavailable'-or[string]::IsNullOrWhiteSpace([string]$_.reason)}).Count){throw "[mir4-t12-explicit-unavailable] $($file.Name)"}
}
foreach($file in Get-ChildItem -LiteralPath (Join-Path $reference 'locks') -File -Filter '*.json'){$lock=Get-Content -Raw -LiteralPath $file.FullName|ConvertFrom-Json -Depth 100;Test-MIR4EnvironmentLockV1 -Lock $lock|Out-Null}

$comparisons=@(Get-ChildItem -LiteralPath (Join-Path $reference 'comparisons') -File -Filter '*.json')
$bundles=@(Get-ChildItem -LiteralPath (Join-Path $reference 'inspector') -File -Filter '*.json')
if($comparisons.Count-ne 8-or$bundles.Count-ne 8){throw '[mir4-t12-comparison-bundle-count]'}
foreach($file in $comparisons){$comparison=Get-Content -Raw -LiteralPath $file.FullName|ConvertFrom-Json -Depth 100;if(-not(($comparison|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-process-ir-comparison-v1.schema.json'))-or[string]$comparison.digest-cne(Get-MIR4T12RecordDigest -Value $comparison -Domain 'mir4:processir-comparison:1')-or-not$comparison.offline-or$comparison.network_or_upload_authorized-or$comparison.mutation_authorized-or$comparison.public_support_claim-or$comparison.package_visible-or@($comparison.process_changes).Count-gt 100){throw "[mir4-t12-comparison] $($file.Name)"}}
foreach($file in $bundles){$bundle=Get-Content -Raw -LiteralPath $file.FullName|ConvertFrom-Json -Depth 100;Test-MIR4InspectionBundleV1 -Bundle $bundle -RepoRoot $RepoRoot|Out-Null;$codes=@(@($bundle.sections|Where-Object id -eq diagnostics)[0].items.code);if('mir4-t12-exact-comparison-captured'-notin$codes-or'BLOCKED-EXACT-TARGET-PROCESSIR-SNAPSHOT'-in$codes-or-not$bundle.local_file_api_only-or$bundle.network_or_upload_authorized-or$bundle.package_visible){throw "[mir4-t12-inspector] $($file.Name)"}}

$rows=@([pscustomobject]@{name='a';version='1.0.0'},[pscustomobject]@{name='B';version='1.0.0'})
if((@(ConvertTo-MIR4EnvironmentRows -Rows $rows -IdField name -Diagnostic test).name-join'|')-cne'B|a'){throw '[mir4-t12-ordinal-environment-rows]'}
$nodes=@(0..19|ForEach-Object{'dense-{0:d2}'-f$_});$adjacency=@{};foreach($node in $nodes){$adjacency[$node]=@($nodes)}
$elapsed=Measure-Command{$witness=@(Get-MIR4MinimalCycleWitness -Adjacency $adjacency -Nodes $nodes)}
if(($witness-join'|')-cne'dense-00|dense-00'-or$elapsed.TotalSeconds-gt 5){throw '[mir4-t12-bounded-cycle-witness]'}

$observerText=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-processir-exact-observer/data-final-fixes.lua')
if($observerText-match'(?m)\bdata\.raw\b'-or$observerText-match'prototypes/mir/(?:planner|emit|runtime)'){throw '[mir4-t12-observer-write-surface]'}
$observerInfo=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-processir-exact-observer/info.json')|ConvertFrom-Json
if([string]$observerInfo.name-cne'mir-fixture-mir4-processir-exact-observer'-or[string]$observerInfo.version-cne'0.1.0'-or[string]$observerInfo.factorio_version-cne'2.1'-or@($observerInfo.dependencies).Count-ne 2){throw '[mir4-t12-observer-fixture-metadata]'}
$packageAfter=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
if($packageAfter-cne$packageBefore){throw '[mir4-t12-package-source-mutation]'}
$preT14Package='9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FA95FCE67A24C'
$t14Package='F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'
if($packageBefore-cne$preT14Package){
  if($packageBefore-ceq$t14Package){
    $t14=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Documentation-Continuity-T14V1.json')|ConvertFrom-Json -Depth 100
    if([string]$t14.kind-cne'MIR4DocumentationContinuityT14V1'){throw '[mir4-t12-t14-presentation-authority-kind]'}
    $beforeMatches = [string]::Equals([string]$t14.package_source_fingerprint_before,'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C',[StringComparison]::Ordinal)
    $afterMatches = [string]::Equals([string]$t14.package_source_fingerprint_after,'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E',[StringComparison]::Ordinal)
    $deltaMatches = (@($t14.package_visible_delta) -join '|') -ceq 'README.md'
    $presentationValid = $beforeMatches -and $afterMatches -and $deltaMatches -and
      ([bool]$t14.player_executable_sources_unchanged) -and ([bool]$t14.one_emitter_preserved) -and
      (-not [bool]$t14.source_freeze_authorized) -and (-not [bool]$t14.signing_or_sealing_authorized) -and
      (-not [bool]$t14.promotion_authorized) -and (-not [bool]$t14.publication_authorized)
    if(-not $presentationValid){
      throw "[mir4-t12-t14-presentation-evolution] before=$beforeMatches after=$afterMatches delta=$deltaMatches executable=$([bool]$t14.player_executable_sources_unchanged) emitter=$([bool]$t14.one_emitter_preserved) freeze=$([bool]$t14.source_freeze_authorized) signing=$([bool]$t14.signing_or_sealing_authorized) promotion=$([bool]$t14.promotion_authorized) publication=$([bool]$t14.publication_authorized)"
    }
    & (Join-Path $RepoRoot 'tests/mir4/Test-MIR4PreFreezeHardening.ps1') -RepoRoot $RepoRoot|Out-Null
  }else{
    try{Assert-MIR4CurrentPackagePresentationV3 -RepoRoot $RepoRoot -PackageSourceSha256 $packageBefore|Out-Null}catch{throw '[mir4-t12-package-source-unknown-evolution]'}
  }
}
}
& {
  # Exercise the real capture consumer with tiny immutable inputs. Only the
  # engine actor and unrelated snapshot semantics are stubbed; no game runs.
  . (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
  . (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
  . (Join-Path $RepoRoot 'tools/mir/application/processir/ExactProcessIR.ps1')
  $root=Join-Path $RepoRoot ('build/tmp/mir421-processir-input-controls/'+[guid]::NewGuid().ToString('N'))
  $library=Join-Path $root 'library';$engineRoot=Join-Path $root 'engine'
  New-Item -ItemType Directory -Path $library,(Join-Path $engineRoot 'bin/x64'),(Join-Path $engineRoot 'data') -Force|Out-Null
  $candidate=Join-Path $library 'more-infinite-research_4.2.21001.zip'
  $dependency=Join-Path $library 'synthetic-dependency_1.0.0.zip'
  $engine=Join-Path $engineRoot 'bin/x64/factorio.exe'
  [IO.File]::WriteAllText($candidate,'synthetic candidate, never loaded')
  [IO.File]::WriteAllText($dependency,'synthetic dependency, never loaded')
  [IO.File]::WriteAllText($engine,'synthetic engine, never executed')
  $candidateHash=Get-MIR4T12FileSha256 $candidate;$dependencyHash=Get-MIR4T12FileSha256 $dependency
  $testAuthority=[pscustomobject]@{targets=[pscustomobject]@{f210=[pscustomobject]@{factorio_line='2.1';engine_version='2.1.0';engine_sha256=Get-MIR4T12FileSha256 $engine;candidate=$candidate;candidate_version='4.2.21001';candidate_sha256=$candidateHash;available_official_mods=@()}};maximum_processes_per_capture=1;required_repetitions=2}
  $capture=[pscustomobject]@{id='synthetic';target='f210';scenario_id='synthetic';selectors=@('synthetic')}
  function Get-MIR4T12ScenarioEvidence {
    param($RepoRoot,$Capture)
    [pscustomobject]@{scenario=[pscustomobject]@{dependency_closure=@([pscustomobject]@{name='synthetic-dependency';version='1.0.0';sha256=$dependencyHash});official_mods=@()};lock=[pscustomobject]@{mods=@([pscustomobject]@{name='synthetic-dependency';version='1.0.0';sha256=$dependencyHash;file_name=[IO.Path]::GetFileName($dependency)})}}
  }
  function New-MIR4T12EnvironmentLock {param($Authority,$Target,$Scenario,$ClosureRows) [pscustomobject]@{digest='synthetic-not-native'}}
  function New-MIR4T12ExactSnapshot {param($RepoRoot,$Capture,$EnvironmentLock,$Observed,$SourceIdentity,$Evidence,$Repetitions,$Deterministic) [pscustomobject]@{kind='SyntheticCaptureConsumerControl';public_release_proof=$false}}
  $calls=[Collections.Generic.List[object]]::new();$mode='passed'
  function Invoke-MIRNativeProbeFactorioProcess {
    param($Context,$FilePath,$Arguments,$TimeoutSeconds)
    $calls.Add([pscustomobject]@{context=$Context;path=$FilePath;arguments=$Arguments;timeout=$TimeoutSeconds})
    $save=$Arguments[([array]::IndexOf($Arguments,'--create')+1)];$run=Split-Path -Parent (Split-Path -Parent $save)
    if($mode-ne'missing-save'){[IO.File]::WriteAllText($save,'synthetic save')}
    if($mode-ne'missing-log'){[IO.File]::WriteAllText((Join-Path $run 'factorio-current.log'),'synthetic current log')}
    $stdout=Join-Path $run 'synthetic.stdout.txt';$stderr=Join-Path $run 'synthetic.stderr.txt'
    [IO.File]::WriteAllText($stdout,"[MIR4_PROCESSIR_HEADER] {`"selected_processes`":0}`n[MIR4_PROCESSIR_FOOTER] {`"emitted_rows`":0,`"complete`":true}`n")
    [IO.File]::WriteAllText($stderr,'')
    [pscustomobject]@{stdout=$stdout;stderr=$stderr;result=[pscustomobject]@{passed=($mode-ne'failed-exit');exit_code=$(if($mode-eq'failed-exit'){1}else{0})}}
  }
  function New-ControlContext([string]$Name){
    [pscustomobject]@{root=Join-Path $root $Name;max_new_output_bytes=1MB;result_reserve_bytes=64KB;shared_alias_bytes=0L;alias_paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);aliases=[Collections.Generic.List[object]]::new()}
  }
  $context=New-ControlContext 'passed'
  $arguments=@{RepoRoot=$RepoRoot;Authority=$testAuthority;Capture=$capture;EnginePath=$engine;OutputRoot=$context.root;ArchiveSearchRoots=@($library);SourceIdentity=@{synthetic=$true};ResourceContext=$context;Repetitions=2}
  $set=Invoke-MIR4T12ExactCapture @arguments
  if($calls.Count-ne 2-or-not$set.deterministic-or@($set.immutable_input_receipts).Count-ne 2){throw '[mir421-t12-consumer-repetitions]'}
  foreach($receipt in $set.immutable_input_receipts){
    if($receipt.state-cne'completed'-or-not$receipt.require_hard_links-or-not$receipt.inputs_sha256_match-or@($receipt.inputs).Count-ne 2-or@($receipt.inputs|Where-Object staging_mode -ne hardlink).Count){throw '[mir421-t12-consumer-strict-lease]'}
    foreach($entry in $receipt.inputs){if((Get-MIRImmutableInputFileIdentity $entry.source_path)-cne(Get-MIRImmutableInputFileIdentity $entry.stage_path)){throw '[mir421-t12-consumer-file-id]'}}
  }
  if($context.shared_alias_bytes-ne(2*((Get-Item $candidate).Length+(Get-Item $dependency).Length))-or(Get-MIRNativeProbeRemainingOutputBytes $context)-le 0){throw '[mir421-t12-consumer-alias-accounting]'}
  if((Get-MIR4T12FileSha256 $candidate)-cne$candidateHash-or(Get-MIR4T12FileSha256 $dependency)-cne$dependencyHash){throw '[mir421-t12-consumer-library-mutation]'}
  foreach($failureMode in @('missing-save','missing-log','failed-exit')){
    $mode=$failureMode;$context=New-ControlContext $mode;$arguments.ResourceContext=$context;$arguments.OutputRoot=$context.root;$arguments.Repetitions=1
    $caught=$false;try{$null=Invoke-MIR4T12ExactCapture @arguments}catch{if(-not$_.Exception.Message.StartsWith('[mir4-t12-factorio]')){throw};$caught=$true}
    $record=Get-Content -Raw (Join-Path $context.root 'runtime/synthetic/run-1/mir-immutable-input-lease.json')|ConvertFrom-Json -Depth 30
    if(-not$caught-or$record.state-cne'failed'-or$null-ne$record.owner_pid){throw '[mir421-t12-consumer-failed-receipt]'}
  }
  $before=$calls.Count;$arguments.OutputRoot=Join-Path $root 'wrong'
  try{$null=Invoke-MIR4T12ExactCapture @arguments;throw '[control-not-rejected]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-t12-resource-root-binding]')){throw}}
  if($calls.Count-ne$before){throw '[mir421-t12-root-binding-before-actor]'}
  foreach($field in @('engine_sha256','candidate_sha256')){
    $context=New-ControlContext $field;$arguments.ResourceContext=$context;$arguments.OutputRoot=$context.root
    $original=$testAuthority.targets.f210.$field;$testAuthority.targets.f210.$field='0'*64
    try{
      try{$null=Invoke-MIR4T12ExactCapture @arguments;throw '[control-not-rejected]'}catch{if($_.Exception.Message-notmatch'^\[mir4-t12-(engine|candidate)-identity\]'){throw}}
      if($calls.Count-ne$before-or(Test-Path -LiteralPath $context.root)){throw '[mir421-t12-identity-before-staging]'}
    }finally{$testAuthority.targets.f210.$field=$original}
  }
  $context=New-ControlContext 'missing-exact-dependency';$arguments.ResourceContext=$context;$arguments.OutputRoot=$context.root
  [IO.File]::WriteAllText($dependency,'changed synthetic input')
  try{$null=Invoke-MIR4T12ExactCapture @arguments;throw '[control-not-rejected]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-t12-exact-archive-missing]')){throw}}
  if($calls.Count-ne$before-or(Test-Path -LiteralPath $context.root)){throw '[mir421-t12-dependency-before-staging]'}
  [IO.File]::WriteAllText($dependency,'synthetic dependency, never loaded')
  $nested=Join-Path $library 'old-profile';New-Item -ItemType Directory -Path $nested|Out-Null
  Move-Item -LiteralPath $dependency -Destination (Join-Path $nested ([IO.Path]::GetFileName($dependency)))
  try{$null=Invoke-MIR4T12ExactCapture @arguments;throw '[control-not-rejected]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-t12-exact-archive-missing]')){throw}}
  if($calls.Count-ne$before-or(Test-Path -LiteralPath $context.root)){throw '[mir421-t12-no-recursive-profile-search]'}
  $existing=Join-Path $root 'preserved';New-Item -ItemType Directory -Path $existing|Out-Null
  [IO.File]::WriteAllText((Join-Path $existing 'unique.txt'),'keep')
  try{$null=Reset-MIR4T12RunDirectory -Root $root -Path $existing;throw '[control-not-rejected]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-t12-existing-run-preserved]')){throw}}
  if((Get-Content -Raw (Join-Path $existing 'unique.txt'))-cne'keep'){throw '[mir421-t12-existing-run-changed]'}
  foreach($case in @(@{CaptureId=@()},@{CaptureId=@('f210-base');PublishReference=$true})){
    $caught=$false;try{& (Join-Path $RepoRoot 'tools/mir/cli/Export-MIR4ExactProcessIRRecords.ps1') -RepoRoot $RepoRoot @case|Out-Null}catch{if($_.Exception.Message-notmatch'^\[mir4-t12-(explicit-capture-selection-required|existing-reference-preserved)\]'){throw};$caught=$true}
    if(-not$caught){throw '[mir421-t12-cli-early-refusal]'}
  }
  Write-Host '[ok] ProcessIR consumer: two strict shared-input repetitions; wrong hashes, missing save/log, engine failure, root mismatch and destructive reference reuse rejected. Synthetic actor only; no Factorio.'
}
if(-not$CaptureConsumerOnly){Write-Host '[ok] MIR 4 T12 exact F210/F200 ProcessIR, deterministic captures, custody blocker, bounded comparisons, and offline Inspector passed.'}
