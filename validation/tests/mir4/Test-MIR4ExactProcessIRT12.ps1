param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/processir/ExactProcessIR.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/inspection/Inspector.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')

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
  if($packageBefore-cne$t14Package){throw '[mir4-t12-package-source-unknown-evolution]'}
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
  & (Join-Path $RepoRoot 'validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1') -RepoRoot $RepoRoot|Out-Null
}
Write-Host '[ok] MIR 4 T12 exact F210/F200 ProcessIR, deterministic captures, custody blocker, bounded comparisons, and offline Inspector passed.'
