# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
$path=Join-Path $RepoRoot 'spec/programmes/mir4-4x-operating-programme-v1.json'
$raw=Get-Content -Raw -LiteralPath $path
if(-not($raw | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-4x-operating-programme-v1.schema.json'))) { throw '[synthesis-programme-schema]' }
$p=$raw | ConvertFrom-Json -Depth 100 -DateKind String
$root=Join-Path $RepoRoot 'spec/programmes/inputs/synthesis-2026-09-05'
$m=Get-Content -Raw -LiteralPath (Join-Path $root 'manifest.json') | ConvertFrom-Json
foreach($f in $m.files) {
 $full=[IO.Path]::GetFullPath((Join-Path $root $f.path))
 if(-not $full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[synthesis-input-path]' }
 if((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ine $f.sha256 -or (Get-Item -LiteralPath $full).Length -ne $f.bytes) { throw "[synthesis-input-identity] $($f.path)" }
}
$requests=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $p.synthesis.request_ledger) | ConvertFrom-Json -Depth 100
$originalExpected=@(1..7 | ForEach-Object { 'K2-{0:D2}' -f $_ })+@(1..16 | ForEach-Object { 'BA-{0:D2}' -f $_ })
$integrationExpected=@(1..6 | ForEach-Object { 'OAB-{0:D2}' -f $_ })+@(1..8 | ForEach-Object { 'RIC-{0:D2}' -f $_ })
$platformExpected=@('PLAT-UI-01')
$expected=@($requests.requests.id)
if($requests.request_count -ne 81 -or $expected.Count -ne 81 -or @($expected | Sort-Object -Unique).Count -ne 81) { throw '[community-exact-81-requests]' }
if(@($originalExpected | Where-Object { $_ -notin $expected }).Count -ne 0) { throw '[community-original-requests-lost]' }
if(@($integrationExpected+$platformExpected | Where-Object { $_ -notin $expected }).Count -ne 0) { throw '[community-expanded-requests-lost]' }
foreach($request in @($requests.requests | Where-Object id -in $originalExpected)) {
  if($request.original_request.id -cne $request.id) { throw '[community-original-attribution-lost]' }
}
$scienceRequest=@($requests.requests | Where-Object id -eq 'K2-01')[0]
if($scienceRequest.requested_outcome -notmatch '^Retire early science' -or $scienceRequest.original_complaint -notmatch 'retained') { throw '[community-request-direction]' }
$components=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $p.synthesis.component_destinations) | ConvertFrom-Json
$platform=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/platform/mir4-preview-v0/platform.json') | ConvertFrom-Json
if(@(Compare-Object @($platform.components.id | Sort-Object) @($components.components.id | Sort-Object)).Count -ne 0) { throw '[synthesis-component-coverage]' }
$tasks=@($p.synthesis.tasks)
$ids=@($tasks.id)
if(@($ids | Sort-Object -Unique).Count -ne $tasks.Count) { throw '[synthesis-duplicate-task]' }
$a01=@($tasks | Where-Object id -eq 'A01')
if($a01.Count-ne1-or[string]$a01[0].state-cne'complete') { throw '[mir4-a01-completion-state]' }
$a01Evidence=@($a01[0].evidence)
$a01RequiredEvidence=@('spec/programmes/evidence/synthesis-2026-09-06/four-target-packages.json','spec/distribution/mir4-current-package-presentation-v2.json','spec/distribution/mir4-current-package-presentation-v2-evolution-receipt.json','.mir/releases/waves/mir4-r0/MIR4-Exact-ProcessIR-T12V1.json','sdk/preview/mir4/reference/t12/MIR4_T12_RECEIPT.json','.mir/releases/waves/mir4-r0/MIR4-Release-Compatibility-Canaries-T13V1.json','sdk/preview/mir4/reference/t13/MIR4_T13_RECEIPT.json')
if($a01Evidence.Count-ne$a01RequiredEvidence.Count-or@($a01RequiredEvidence|Where-Object{$_-notin$a01Evidence}).Count-ne0) { throw '[mir4-a01-evidence-bindings]' }
$t12Authority=Get-Content -Raw (Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Exact-ProcessIR-T12V1.json')|ConvertFrom-Json -Depth 100
$t12Receipt=Get-Content -Raw (Join-Path $RepoRoot 'sdk/preview/mir4/reference/t12/MIR4_T12_RECEIPT.json')|ConvertFrom-Json -Depth 100
$t13Authority=Get-Content -Raw (Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Release-Compatibility-Canaries-T13V1.json')|ConvertFrom-Json -Depth 100
$t13Receipt=Get-Content -Raw (Join-Path $RepoRoot 'sdk/preview/mir4/reference/t13/MIR4_T13_RECEIPT.json')|ConvertFrom-Json -Depth 100
if([string]$t12Authority.work_package-cne'T12'-or-not$t12Authority.terminal_fact_authority_preserved-or[string]$t12Receipt.status-cne'completed-machine-work-with-custody-blocker'-or[int]$t12Receipt.capture_count-ne10-or[int]$t12Receipt.required_capture_count-ne11-or-not$t12Receipt.package_source_unchanged){throw '[mir4-a01-t12-historical-object]'}
if([string]$t13Authority.exact_processir_authority-cne'.mir/releases/waves/mir4-r0/MIR4-Exact-ProcessIR-T12V1.json'-or[int]$t13Authority.required_capture_count-ne11-or[string]$t13Receipt.status-cne'completed-machine-work'-or[int]$t13Receipt.capture_count-ne11-or-not$t13Receipt.f200_k2so_archive_custody_complete-or-not$t13Receipt.t12_historical_blocker_superseded-or-not$t13Receipt.package_source_unchanged){throw '[mir4-a01-t13-current-supersession]'}
foreach($record in @($t12Authority,$t13Authority)){foreach($flag in @('semantic_authority','player_mutation_authorized','prototype_write_authorized','automatic_synthesis_authorized','public_support_authorized','source_freeze_authorized','signing_or_sealing_authorized','promotion_authorized','publication_authorized','package_visible')){if($null-ne$record.PSObject.Properties[$flag]-and[bool]$record.$flag){throw "[mir4-a01-authority-gate] $flag"}}}
$presentation=Get-Content -Raw (Join-Path $RepoRoot 'spec/distribution/mir4-current-package-presentation-v2.json')|ConvertFrom-Json -Depth 100
$presentationReceipt=Get-Content -Raw (Join-Path $RepoRoot 'spec/distribution/mir4-current-package-presentation-v2-evolution-receipt.json')|ConvertFrom-Json -Depth 100
if([string]$presentation.kind-cne'MIR4CurrentPackagePresentationV2'-or-not$presentation.presentation.repository_readme_package_excluded-or-not$presentation.authority_invariants.one_emitter_preserved-or@($presentation.authority_invariants.PSObject.Properties|Where-Object{$_.Name-ne'one_emitter_preserved'-and[bool]$_.Value}).Count-ne0-or[string]$presentationReceipt.authority.record_sha256-cne[string]$presentation.record_sha256-or@($presentation.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0-or@($presentationReceipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-a01-package-presentation-authority]'}
$done=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
while($done.Count -lt $tasks.Count) {
 $before=$done.Count
 foreach($t in $tasks) {
  if(@($t.depends_on | Where-Object { $_ -notin $ids }).Count -ne 0) { throw '[synthesis-unknown-dependency]' }
  if(@($t.requests | Where-Object { $_ -notin $expected }).Count -ne 0) { throw '[synthesis-unknown-request]' }
  if(@($t.programme_mapping | Where-Object { $_ -notin $p.work_packages.id -and $_ -ne 'maintenance' }).Count -ne 0) { throw '[synthesis-unknown-programme]' }
  if($t.state -eq 'complete' -and @($t.evidence).Count -eq 0) { throw '[synthesis-false-completion]' }
  if(@($t.depends_on | Where-Object { -not $done.Contains($_) }).Count -eq 0) { [void]$done.Add($t.id) }
 }
 if($done.Count -eq $before) { throw '[synthesis-dependency-cycle]' }
}
if(@(Compare-Object ($expected | Sort-Object) @($tasks.requests | Sort-Object -Unique)).Count -ne 0) { throw '[synthesis-unowned-request]' }
if($p.synthesis.objectives_measured -or $p.synthesis.heavy_engine_concurrency -ne 1) { throw '[synthesis-unmeasured-capacity]' }
if($p.synthesis.release_baseline.source -cne '3562377b520cccb071b97b3968946eae7024c950' -or $p.synthesis.release_baseline.human_acceptance.f210 -cne 'release-specific-direct-playtest-waiver') { throw '[synthesis-release-history]' }
if(@($p.work_packages | Where-Object { $_.id -eq 'M41-08' -and $_.state -eq 'complete' }).Count -ne 1 -or @($p.work_packages | Where-Object { $_.id -eq 'M43-00' -and $_.state -eq 'active' }).Count -ne 1) { throw '[synthesis-current-state]' }
$m44=@($p.work_packages | Where-Object id -eq 'M44-00')
$m42Train=@($p.outcome_trains | Where-Object candidate -eq '4.2.0')
$m43Train=@($p.outcome_trains | Where-Object candidate -eq '4.3.0')
if($m44.Count-ne1-or[string]$m44[0].state-cne'active'-or[string]$m44[0].completion_boundary-cne'4.3.0'-or
   'M43-00'-in@($m44[0].depends_on)-or@('M41-08','M42-01','M42-02'|Where-Object{$_-notin@($m44[0].depends_on)}).Count-ne0-or
   $m42Train.Count-ne1-or[string]$m42Train[0].outcome-notmatch'consumed M44.*exact-fingerprint evidence reuse.*support-export.*release-recovery'-or
   $m43Train.Count-ne1-or[string]$m43Train[0].outcome-notmatch'remaining generalized M44') { throw '[synthesis-m44-consumed-pullforward]' }
$m44Allocation=$p.synthesis.m44_42_allocation
$m44Expected=[ordered]@{
  'impact-selected-verification'=[ordered]@{task='A13';acceptance='Select only the propositions affected by the declared semantic impact; every omission names its unaffected proposition.';static_test='tests/tooling/Test-MIRAssurance.ps1';candidate_receipt='spec/programmes/evidence/mir42/a13-impact-selection.json'}
  'exact-fingerprint-evidence-reuse'=[ordered]@{task='A13';acceptance='Reuse evidence only when target, candidate source, environment, command, evaluator, and input fingerprints exactly match; a contradiction quarantines reuse.';static_test='tests/tooling/Test-MIRAssurance.ps1';candidate_receipt='spec/programmes/evidence/mir42/a13-exact-fingerprint-reuse.json'}
  'redacted-support-export'=[ordered]@{task='A14';acceptance='Produce a minimal redacted support export bound to the exact candidate and environment, reconcile it with the qualified support matrix, and exclude credentials, personal data, and unsupported claims.';static_test='tests/mir4/Test-MIR42SupportExportA14.ps1';candidate_receipt='spec/programmes/evidence/mir42/a14-support-export.json'}
  'candidate-bound-release-recovery'=[ordered]@{task='A07';acceptance='Rehearse interruption and recovery from persisted intent bound to candidate identity, effects, recovery decision, and local delivery record without publication.';static_test='tests/mir4/Test-MIR4ReleaseOperatorRecoveryA07.ps1';candidate_receipt='spec/programmes/evidence/mir42/a07-release-recovery.json'}
}
if([string]$m44Allocation.work_package-cne'M44-00'-or@($m44Allocation.consumed_by_4_2).Count-ne$m44Expected.Count-or@($m44Allocation.consumed_by_4_2.id|Sort-Object -Unique).Count-ne$m44Expected.Count){throw '[synthesis-m44-allocation-shape]'}
$m44Tasks=@{}
foreach($task in $tasks){$m44Tasks[[string]$task.id]=$task}
$a14=@($tasks|Where-Object id -eq 'A14')
if($a14.Count-ne1-or'A13'-notin@($a14[0].depends_on)){throw '[synthesis-m44-support-export-dependency]'}
$validationRegistry=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'validation/tests.yml')|ConvertFrom-Json -Depth 100
foreach($capability in @($m44Allocation.consumed_by_4_2)){
  $expectedCapability=$m44Expected[[string]$capability.id]
  if($null-eq$expectedCapability-or[string]$capability.task-cne$expectedCapability.task-or[string]$capability.acceptance-cne$expectedCapability.acceptance-or
     [string]$capability.evidence.static_test-cne$expectedCapability.static_test-or[string]$capability.evidence.candidate_receipt-cne$expectedCapability.candidate_receipt){throw "[synthesis-m44-consumed-binding] $($capability.id)"}
  $task=$m44Tasks[[string]$capability.task]
  if($null-eq$task-or'M44-00'-notin@($task.programme_mapping)-or[string]$task.state-ceq'complete'-or
     [string]$capability.acceptance-notin@($task.acceptance)){throw "[synthesis-m44-task-binding] $($capability.id)"}
  if([string]$capability.evidence.static_test-cnotmatch'^tests/[A-Za-z0-9._/-]+\.ps1$'-or
     [string]$capability.evidence.candidate_receipt-cnotmatch'^spec/programmes/evidence/mir42/[A-Za-z0-9._/-]+\.json$'){throw "[synthesis-m44-evidence-binding] $($capability.id)"}
  $staticTest=[string]$capability.evidence.static_test
  if(-not(Test-Path -LiteralPath (Join-Path $RepoRoot ($staticTest.Replace('/','\'))) -PathType Leaf)){throw "[synthesis-m44-static-test-missing] $($capability.id)"}
  $registered=@($validationRegistry.tests|Where-Object{$_.PSObject.Properties['command']-and[string]$_.command-ceq('./'+$staticTest)})
  if($registered.Count-ne1-or[string]$registered[0].kind-cne'static'-or[bool]$registered[0].requires_factorio){throw "[synthesis-m44-static-test-unregistered] $($capability.id)"}
}
$m44Reserved=@('generalized-selection-and-reuse-policy','evidence-revocation-and-lifecycle','cross-task-partial-run-recovery','nondeterminism-classification','offline-operation-and-preservation','measured-release-lane-calibration')
if(@($m44Allocation.reserved_for_4_3).Count-ne$m44Reserved.Count-or@(Compare-Object ($m44Reserved|Sort-Object) @($m44Allocation.reserved_for_4_3.id|Sort-Object)).Count-ne0-or
   @($m44Allocation.reserved_for_4_3|Where-Object{[string]$_.delivery_boundary-cne'4.3.0'-or[string]$_.outcome.Length-lt20}).Count-ne0){throw '[synthesis-m44-reserved-allocation]'}
Write-Output 'Synthesis input integrity, complete 81-request/component coverage, dependency graph, and truthful completion boundaries passed.'

# The controlled proof is reusable only for these exact current module bytes.
$scienceEvidence=Join-Path $RepoRoot 'spec/programmes/evidence/synthesis-2026-09-06/science-modules.json'
$science=Get-Content -Raw $scienceEvidence | ConvertFrom-Json
if($science.status -cne 'passed' -or $science.assertions -ne 33 -or $science.scope -cne 'controlled-modules-not-real-k2-qualification') { throw '[synthesis-science-proof-scope]' }
foreach($module in $science.modules) {
  $currentModule=Resolve-MIR4CanonicalPackageSourcePath -RepoRoot $RepoRoot -RelativePath ([string]$module.path)
  if((Get-FileHash -LiteralPath (Join-Path $RepoRoot $currentModule)).Hash -cne $module.sha256) { throw "[synthesis-science-proof-stale] $($module.path)" }
}
if((Get-FileHash -LiteralPath (Join-Path $RepoRoot 'tests/compiler/science_planning.lua')).Hash -cne $science.test_sha256) { throw '[synthesis-science-test-stale]' }

# Preserve the authored calendar date across AEST and UTC runners.
. (Join-Path $RepoRoot 'tools/lib/control/Core.ps1')
. (Join-Path $RepoRoot 'tools/lib/control/Views.ps1')
$authored=Read-MIRCPJson -Path 'spec/programmes/mir4-4x-operating-programme-v1.json' -RepoRoot $RepoRoot -PreserveTimestamps
if($authored.recorded_at -isnot [string] -or $authored.recorded_at -cne $p.recorded_at) { throw '[synthesis-authored-timestamp]' }
$date=Get-MIRCPAuthoredDate -Timestamp $authored.recorded_at
if($date -cne $p.recorded_at.Substring(0,10)) { throw '[synthesis-authored-date]' }
if((Get-MIRCPAuthoredDate -Timestamp '2026-09-06T00:00:00+10:00') -cne '2026-09-06' -or
   (Get-MIRCPAuthoredDate -Timestamp '2026-09-05T14:00:00Z') -cne '2026-09-05') { throw '[synthesis-timezone-regression]' }
if(@(Get-Content -LiteralPath (Join-Path $RepoRoot 'TODO.md') | Where-Object { $_ -ceq "Generated: $date" }).Count -ne 1) { throw '[synthesis-queue-date]' }

# Development outcomes are exact historical source/receipt bindings, never support authority.
function Assert-MIR4CommunitySafeRelativePath([string]$RelativePath) {
 if([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath) -or
    $RelativePath -cnotmatch '^[A-Za-z0-9._/-]+$' -or $RelativePath -cmatch '(^|/)\.\.?($|/)') {
  throw "[community-evidence-unsafe-path] $RelativePath"
 }
 return $RelativePath
}
function Resolve-MIR4CommunityRepositoryPath([string]$RelativePath) {
 $safeRelativePath=Assert-MIR4CommunitySafeRelativePath $RelativePath
 $repositoryPath=[IO.Path]::GetFullPath($RepoRoot)
 $fullPath=[IO.Path]::GetFullPath((Join-Path $repositoryPath ($safeRelativePath.Replace('/',[IO.Path]::DirectorySeparatorChar))))
 if(-not $fullPath.StartsWith($repositoryPath+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
  throw "[community-evidence-unsafe-path] $RelativePath"
 }
 return $fullPath
}
function Get-MIR4CommunityGitBlob([string]$Commit,[string]$RelativePath) {
 $safeRelativePath=Assert-MIR4CommunitySafeRelativePath $RelativePath
 $objectIdRows=@(& git -C $RepoRoot rev-parse --verify "$Commit`:$safeRelativePath" 2>$null)
 if($LASTEXITCODE -ne 0 -or $objectIdRows.Count -ne 1) { throw "[community-evidence-snapshot-blob] $safeRelativePath" }
 $objectId=([string]$objectIdRows[0]).Trim()
 if($objectId -cnotmatch '^[0-9a-f]{40}([0-9a-f]{24})?$') { throw "[community-evidence-snapshot-object] $safeRelativePath" }
 $startInfo=[Diagnostics.ProcessStartInfo]::new()
 $startInfo.FileName='git'
 $startInfo.WorkingDirectory=$RepoRoot
 $startInfo.UseShellExecute=$false
 $startInfo.RedirectStandardOutput=$true
 $startInfo.RedirectStandardError=$true
 foreach($argument in @('cat-file','blob',$objectId)) { [void]$startInfo.ArgumentList.Add($argument) }
 $process=[Diagnostics.Process]::new()
 $process.StartInfo=$startInfo
 if(-not $process.Start()) { throw "[community-evidence-snapshot-blob] $safeRelativePath" }
 $standardErrorTask=$process.StandardError.ReadToEndAsync()
 $memory=[IO.MemoryStream]::new()
 try {
  $process.StandardOutput.BaseStream.CopyTo($memory)
  $process.WaitForExit()
  $standardError=$standardErrorTask.GetAwaiter().GetResult()
  if($process.ExitCode -ne 0) { throw "[community-evidence-snapshot-blob] $safeRelativePath $standardError" }
  return [pscustomobject]@{ object_id=$objectId; bytes=$memory.ToArray() }
 } finally {
  $memory.Dispose()
  $process.Dispose()
 }
}
function Test-MIR4CommunityByteIdentity([byte[]]$Expected,[byte[]]$Actual) {
 if($Expected.Length -ne $Actual.Length) { return $false }
 for($index=0;$index -lt $Expected.Length;$index++) {
  if($Expected[$index] -ne $Actual[$index]) { return $false }
 }
 return $true
}
function Get-MIR4CommunityByteSha256([byte[]]$Bytes) {
 $algorithm=[Security.Cryptography.SHA256]::Create()
 try { return (($algorithm.ComputeHash($Bytes) | ForEach-Object { $_.ToString('X2') }) -join '') }
 finally { $algorithm.Dispose() }
}
$communityRelativePath='spec/programmes/evidence/community-2026-09-06/outcomes.json'
$communityPath=Resolve-MIR4CommunityRepositoryPath $communityRelativePath
if(-not (Test-Path -LiteralPath $communityPath -PathType Leaf)) { throw '[community-evidence-snapshot-record]' }
$snapshotCommitRows=@(& git -C $RepoRoot log -1 --format=%H -- $communityRelativePath 2>$null)
if($LASTEXITCODE -ne 0 -or $snapshotCommitRows.Count -ne 1) { throw '[community-evidence-snapshot-commit]' }
$snapshotCommit=([string]$snapshotCommitRows[0]).Trim()
if($snapshotCommit -cnotmatch '^[0-9a-f]{40}([0-9a-f]{24})?$') { throw '[community-evidence-snapshot-commit]' }
& git -C $RepoRoot merge-base --is-ancestor $snapshotCommit HEAD 2>$null
if($LASTEXITCODE -ne 0) { throw '[community-evidence-snapshot-not-ancestor]' }
$snapshotOutcomes=Get-MIR4CommunityGitBlob $snapshotCommit $communityRelativePath
$currentOutcomesBytes=[IO.File]::ReadAllBytes($communityPath)
if(-not (Test-MIR4CommunityByteIdentity $snapshotOutcomes.bytes $currentOutcomesBytes)) { throw '[community-evidence-snapshot-record-bytes]' }
$community=[Text.Encoding]::UTF8.GetString($snapshotOutcomes.bytes) | ConvertFrom-Json -Depth 100
if($community.release_candidate_ready -or $community.release_authority -or $community.campaigns.Count -ne 3) { throw '[community-evidence-scope]' }
foreach($binding in @($community.material_source_bindings)+@($community.browser_source_bindings)+@($community.runtime_receipts)) {
 if($null -eq $binding -or $null -eq $binding.PSObject.Properties['path'] -or $null -eq $binding.PSObject.Properties['sha256']) { throw '[community-evidence-binding-shape]' }
 $bindingPath=Assert-MIR4CommunitySafeRelativePath ([string]$binding.path)
 $expectedSha256=[string]$binding.sha256
 if($expectedSha256 -cnotmatch '^[A-F0-9]{64}$') { throw "[community-evidence-binding-sha256] $bindingPath" }
 $snapshotBinding=Get-MIR4CommunityGitBlob $snapshotCommit $bindingPath
 if((Get-MIR4CommunityByteSha256 $snapshotBinding.bytes) -cne $expectedSha256) { throw "[community-evidence-binding] $bindingPath" }
}
$manifest=Get-Content -Raw (Join-Path $RepoRoot 'source/prototypes/mir/streams/generated_stream_manifest.json') | ConvertFrom-Json -Depth 100
$declarations=@($requests.requests | Where-Object { $null -ne $_.PSObject.Properties['material_route_declaration'] })
if($declarations.Count -ne 22) { throw '[community-material-accounting]' }
foreach($request in $declarations) {
 $identity='recipe-prod-'+$request.material_route_declaration.stream+'-1'
 if(($manifest | ConvertTo-Json -Depth 100) -notmatch [regex]::Escape($identity)) { throw "[community-material-identity] $identity" }
 if($request.material_route_declaration.infinite_continuation -cne 'not-implemented' -or $request.qualification.Count -eq 0) { throw '[community-material-false-completion]' }
}
$source=Get-Content -Raw (Join-Path $RepoRoot 'source/package-source.json') | ConvertFrom-Json -Depth 100
if(@($source.bindings | Where-Object source_path -Like 'tests/*').Count -ne 0) { throw '[community-experiment-package-leak]' }
Write-Output 'Community source bindings, exact receipts, 22 stable material declarations and prototype package exclusion passed.'
