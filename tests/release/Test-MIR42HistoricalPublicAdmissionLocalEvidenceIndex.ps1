param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$IndexPath='.mir/releases/governance/mir4/MIR42-Historical-Local-Evidence-IndexV1.json',
  [string]$EvidenceRoot='',
  [string]$PackageRoot='',
  [string]$PredecessorRoot=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Assert-HistoricalEvidenceIndex([bool]$Condition,[string]$Code,[string]$Detail='') {
  if (-not $Condition) { throw "[$Code] $Detail" }
}

function Resolve-HistoricalLocalCustodyPath([string]$Value,[string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw "[historical-local-evidence-index-custody-unavailable] Provide -$Name from the named local private custody. This index does not establish independently reviewable public evidence."
  }
  if (-not (Test-Path -LiteralPath $Value -PathType Container)) {
    throw "[historical-local-evidence-index-custody-unavailable] -$Name does not exist: $Value. This index does not establish independently reviewable public evidence."
  }
  return (Resolve-Path -LiteralPath $Value).Path
}

function Get-HistoricalPinnedJson([string]$Repository,[string]$Commit,[string]$Path,[string]$Code) {
  $spec=$Commit + ':' + $Path
  $lines=@(& git -C $Repository show $spec 2>$null)
  if ($LASTEXITCODE -ne 0) { throw "[$Code] $spec" }
  return (($lines -join "`n") | ConvertFrom-Json -Depth 100)
}

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
if (-not [IO.Path]::IsPathRooted($IndexPath)) { $IndexPath=Join-Path $repo $IndexPath }
$IndexPath=(Resolve-Path -LiteralPath $IndexPath).Path
. (Join-Path $repo 'tools/lib/mir4/bootstrap-materialization/DigestsAndRecords.ps1')
$index=Get-Content -Raw -LiteralPath $IndexPath | ConvertFrom-Json -Depth 100
Assert-HistoricalEvidenceIndex ([string]$index.kind -ceq 'MIR42HistoricalPublicAdmissionLocalEvidenceIndexV1') 'historical-local-evidence-index-kind'
Assert-HistoricalEvidenceIndex ([string]$index.status -ceq 'local-private-evidence-index-not-public-admission') 'historical-local-evidence-index-status'
Assert-HistoricalEvidenceIndex ([string]$index.evidence_availability -ceq 'local-private-handoff-only-not-durable') 'historical-local-evidence-index-availability'
Assert-HistoricalEvidenceIndex ([string]$index.independent_review_status -ceq 'blocked-until-content-addressed-governed-evidence-capsule') 'historical-local-evidence-index-review-status'
Assert-HistoricalEvidenceIndex (Test-MIR4BootstrapRecordHash $index) 'historical-local-evidence-index-self-hash'
foreach($flag in @('public_admission','source_freeze','production_signing','technical_seal','promotion_to_main','tagging','github_publication','mod_portal_publication')) {
  Assert-HistoricalEvidenceIndex (-not [bool]$index.transition_gate.$flag) 'historical-local-evidence-index-gate-firewall' $flag
}
Assert-HistoricalEvidenceIndex (-not [bool]$index.channel_disposition.channel_operation_authorized) 'historical-local-evidence-index-channel-firewall'
Assert-HistoricalEvidenceIndex ([string]$index.hard_boundary -match 'not a durable governed evidence capsule') 'historical-local-evidence-index-boundary'

$evidenceRoot=Resolve-HistoricalLocalCustodyPath -Value $EvidenceRoot -Name 'EvidenceRoot'
$packageRoot=Resolve-HistoricalLocalCustodyPath -Value $PackageRoot -Name 'PackageRoot'
$predecessorRoot=Resolve-HistoricalLocalCustodyPath -Value $PredecessorRoot -Name 'PredecessorRoot'
$relativePackageRoot=([string]$index.local_private_custody.package_root).Replace('/','\')
Assert-HistoricalEvidenceIndex ($packageRoot.EndsWith($relativePackageRoot,[StringComparison]::OrdinalIgnoreCase)) 'historical-local-evidence-index-package-root' $packageRoot
$primaryRoot=$packageRoot.Substring(0,$packageRoot.Length-$relativePackageRoot.Length).TrimEnd('\','/')

$custodyPath=Join-Path $evidenceRoot 'CUSTODY-VERIFICATION.json'
Assert-HistoricalEvidenceIndex (Test-Path -LiteralPath $custodyPath -PathType Leaf) 'historical-local-evidence-index-custody-manifest'
$custody=Get-Content -Raw -LiteralPath $custodyPath | ConvertFrom-Json -Depth 100
Assert-HistoricalEvidenceIndex ([string]$custody.kind -ceq 'MIR42HistoricalPrivateEvidenceCustodyV1' -and [string]$custody.status -ceq 'preserved-local-private-handoff' -and -not [bool]$custody.public_output_authorized -and -not [bool]$custody.publication_authorized -and (Test-MIR4BootstrapRecordHash $custody) -and [string]$custody.record_sha256 -ceq [string]$index.local_private_custody.evidence_manifest.record_sha256) 'historical-local-evidence-index-custody-manifest-binding'
foreach($entry in @($custody.files)) {
  $path=Join-Path $primaryRoot (([string]$entry.path).Replace('/','\'))
  Assert-HistoricalEvidenceIndex ((Test-Path -LiteralPath $path -PathType Leaf) -and [int64](Get-Item -LiteralPath $path).Length -eq [int64]$entry.bytes -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ceq [string]$entry.sha256) 'historical-local-evidence-index-custody-file' ([string]$entry.path)
}
$copyPath=Join-Path $primaryRoot (([string]$index.local_private_custody.copy_verification.path).Replace('/','\'))
Assert-HistoricalEvidenceIndex ((Test-Path -LiteralPath $copyPath -PathType Leaf) -and (Get-FileHash -LiteralPath $copyPath -Algorithm SHA256).Hash -ceq [string]$index.local_private_custody.copy_verification.sha256) 'historical-local-evidence-index-copy-verification'
$copyRows=Get-Content -Raw -LiteralPath $copyPath | ConvertFrom-Json -Depth 100

$privatePath=Join-Path $repo ([string]$index.private_predecessor_authority.path)
$private=Get-Content -Raw -LiteralPath $privatePath | ConvertFrom-Json -Depth 100
Assert-HistoricalEvidenceIndex ([string]$private.record_sha256 -ceq [string]$index.private_predecessor_authority.record_sha256) 'historical-local-evidence-index-private-authority-binding'
foreach($flag in @('public_output_authorized','signing_or_sealing_authorized','publication_authorized')) {
  Assert-HistoricalEvidenceIndex (-not [bool]$private.$flag) 'historical-local-evidence-index-private-authority-still-closed' $flag
}
$sourceCommit=[string]$index.source.candidate_materialization_commit
$sourceTree=[string]$index.source.candidate_materialization_tree
$resolvedCommit=(& git -C $repo rev-parse "$sourceCommit^{commit}" 2>$null).Trim(); Assert-HistoricalEvidenceIndex ($LASTEXITCODE -eq 0 -and $resolvedCommit -ceq $sourceCommit) 'historical-local-evidence-index-source-commit'
$resolvedTree=(& git -C $repo rev-parse "$sourceCommit^{tree}" 2>$null).Trim(); Assert-HistoricalEvidenceIndex ($LASTEXITCODE -eq 0 -and $resolvedTree -ceq $sourceTree) 'historical-local-evidence-index-source-tree'
$packageAuthority=Get-HistoricalPinnedJson -Repository $repo -Commit $sourceCommit -Path ([string]$index.source.package_authority.path) -Code 'historical-local-evidence-index-pinned-package-authority'
$sourceManifest=Get-HistoricalPinnedJson -Repository $repo -Commit $sourceCommit -Path ([string]$index.source.source_manifest.path) -Code 'historical-local-evidence-index-pinned-source-manifest'
Assert-HistoricalEvidenceIndex ((Test-MIR4BootstrapRecordHash $packageAuthority) -and [string]$packageAuthority.record_sha256 -ceq [string]$index.source.package_authority.record_sha256 -and (Test-MIR4BootstrapRecordHash $sourceManifest) -and [string]$sourceManifest.record_sha256 -ceq [string]$index.source.source_manifest.record_sha256) 'historical-local-evidence-index-pinned-source-authority-binding'

$registry=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json') | ConvertFrom-Json -Depth 100
$expected=@('f017','f016','f015','f014','f013')
Assert-HistoricalEvidenceIndex ((@($index.targets | ForEach-Object {[string]$_.target_key}) -join ',') -ceq ($expected -join ',')) 'historical-local-evidence-index-target-order'
foreach($row in @($index.targets)) {
  $target=[string]$row.target_key
  $identity=@($registry.identities | Where-Object {[string]$_.target -ceq $target})
  Assert-HistoricalEvidenceIndex ($identity.Count -eq 1 -and [string]$identity[0].factorio_line -ceq [string]$row.factorio_line -and [string]$identity[0].mir3_predecessor -ceq [string]$row.predecessor.version) 'historical-local-evidence-index-registry-binding' $target
  $targetRecord=Get-HistoricalPinnedJson -Repository $repo -Commit $sourceCommit -Path ([string]$row.target_record.path) -Code 'historical-local-evidence-index-pinned-target-record'
  Assert-HistoricalEvidenceIndex ((Test-MIR4BootstrapRecordHash $targetRecord) -and [string]$targetRecord.record_sha256 -ceq [string]$row.target_record.record_sha256 -and [string]$targetRecord.target -ceq $target -and [string]$targetRecord.factorio_line -ceq [string]$row.factorio_line -and [string]$targetRecord.distribution_version -ceq [string]$row.candidate.distribution_version -and [string]$targetRecord.engine.sha256 -ceq [string]$row.engine.sha256 -and [string]$targetRecord.engine.version -ceq [string]$row.engine.version -and [string]$targetRecord.predecessor.sha256 -ceq [string]$row.predecessor.archive_sha256 -and [string]$targetRecord.predecessor.version -ceq [string]$row.predecessor.version -and -not [bool]$targetRecord.public_output_authorized -and -not [bool]$targetRecord.publication_authorized) 'historical-local-evidence-index-pinned-target-record-binding' $target
  Assert-HistoricalEvidenceIndex ([bool]$row.candidate.identical_builds -and [int]$row.candidate.repeated_builds -eq 2 -and [int]$row.candidate.entry_count -gt 0 -and [string]$row.candidate.archive_sha256 -match '^[A-F0-9]{64}$' -and [string]$row.candidate.content_sha256 -match '^[A-F0-9]{64}$' -and [string]$row.candidate.handoff_file -ceq "more-infinite-research_$([string]$row.candidate.distribution_version).zip") 'historical-local-evidence-index-candidate-shape' $target
  $manifestPath=Join-Path $evidenceRoot "manifests/$target.json"
  $manifest=Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
  Assert-HistoricalEvidenceIndex ((Test-MIR4BootstrapRecordHash $manifest) -and [string]$manifest.kind -ceq 'MIR42HistoricalPlaytestCandidateManifestV1' -and [string]$manifest.status -ceq 'built-private-historical-unqualified' -and [string]$manifest.target -ceq $target -and [string]$manifest.factorio_line -ceq [string]$row.factorio_line -and [string]$manifest.distribution_version -ceq [string]$row.candidate.distribution_version -and [string]$manifest.source.commit -ceq $sourceCommit -and [string]$manifest.source.tree -ceq $sourceTree -and [string]$manifest.target_record.sha256 -ceq [string]$row.target_record.record_sha256 -and [string]$manifest.engine.sha256 -ceq [string]$row.engine.sha256 -and [string]$manifest.engine.version -ceq [string]$row.engine.version -and [string]$manifest.predecessor.sha256 -ceq [string]$row.predecessor.archive_sha256 -and [string]$manifest.predecessor.version -ceq [string]$row.predecessor.version -and -not [bool]$manifest.public_output_authorized -and -not [bool]$manifest.publication_authorized) 'historical-local-evidence-index-manifest-binding' $target
  Assert-HistoricalEvidenceIndex (@($manifest.builds).Count -eq 2 -and @($manifest.builds | Where-Object {[string]$_.archive_sha256 -cne [string]$row.candidate.archive_sha256 -or [string]$_.content_sha256 -cne [string]$row.candidate.content_sha256 -or [int]$_.entry_count -ne [int]$row.candidate.entry_count}).Count -eq 0 -and [string]$manifest.distribution.sha256 -ceq [string]$row.candidate.archive_sha256 -and [string]$manifest.distribution.content_sha256 -ceq [string]$row.candidate.content_sha256 -and [int]$manifest.distribution.entry_count -eq [int]$row.candidate.entry_count) 'historical-local-evidence-index-repeated-build-binding' $target
  $candidateArchive=Join-Path $packageRoot ([string]$row.candidate.handoff_file)
  $copyRow=@($copyRows | Where-Object {[string]$_.target -ceq $target})
  Assert-HistoricalEvidenceIndex ($copyRow.Count -eq 1 -and [string]$copyRow[0].version -ceq [string]$row.candidate.distribution_version -and [string]$copyRow[0].sha256 -ceq [string]$row.candidate.archive_sha256 -and [string]$copyRow[0].file -ceq [string]$row.candidate.handoff_file -and (Get-FileHash -LiteralPath $candidateArchive -Algorithm SHA256).Hash -ceq [string]$row.candidate.archive_sha256) 'historical-local-evidence-index-candidate-custody' $target
  $predecessorArchive=Join-Path $predecessorRoot ([IO.Path]::GetFileName([string]$row.predecessor.archive))
  Assert-HistoricalEvidenceIndex ((Test-Path -LiteralPath $predecessorArchive -PathType Leaf) -and (Get-FileHash -LiteralPath $predecessorArchive -Algorithm SHA256).Hash -ceq [string]$row.predecessor.archive_sha256) 'historical-local-evidence-index-predecessor-archive' $target
  $privateTarget=@($private.targets | Where-Object {[string]$_.target_key -ceq $target})
  Assert-HistoricalEvidenceIndex ($privateTarget.Count -eq 1 -and [string]$privateTarget[0].engine.sha256 -ceq [string]$row.engine.sha256 -and [string]$privateTarget[0].predecessor_archive_sha256 -ceq [string]$row.predecessor.archive_sha256) 'historical-local-evidence-index-private-binding' $target
  $runtimePath=Join-Path $evidenceRoot ([string]$row.engine.fresh_load.custody_path)
  $runtime=Get-Content -Raw -LiteralPath $runtimePath | ConvertFrom-Json -Depth 100
  $runtimeLog=Join-Path $evidenceRoot ([string]$row.engine.fresh_load.log_custody_path)
  Assert-HistoricalEvidenceIndex ((Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash -ceq [string]$row.engine.fresh_load.receipt_sha256 -and [string]$runtime.status -ceq 'passed-private-unqualified' -and [string]$runtime.target -ceq $target -and [string]$runtime.candidate.sha256 -ceq [string]$row.candidate.archive_sha256 -and [string]$runtime.engine.sha256 -ceq [string]$row.engine.sha256 -and [string]$runtime.engine.version -ceq [string]$row.engine.version -and [string]$runtime.log_sha256 -ceq [string]$row.engine.fresh_load.log_sha256 -and (Get-FileHash -LiteralPath $runtimeLog -Algorithm SHA256).Hash -ceq [string]$row.engine.fresh_load.log_sha256 -and -not [bool]$runtime.public_output_authorized -and -not [bool]$runtime.publication_authorized) 'historical-local-evidence-index-fresh-load-binding' $target
  $continuityPath=Join-Path $evidenceRoot ([string]$row.direct_continuity.custody_path)
  $continuity=Get-Content -Raw -LiteralPath $continuityPath | ConvertFrom-Json -Depth 100
  $continuityRequired=@('published-mir3-predecessor-created','migrates-into-current-mir42','first-current-reload-passes','second-current-reload-passes')
  $missingContinuityAssertions=@()
  foreach($assertionId in $continuityRequired) {
    if (@($continuity.assertions | Where-Object {[string]$_.id -ceq $assertionId -and [string]$_.status -ceq 'passed'}).Count -ne 1) { $missingContinuityAssertions += $assertionId }
  }
  Assert-HistoricalEvidenceIndex ((Get-FileHash -LiteralPath $continuityPath -Algorithm SHA256).Hash -ceq [string]$row.direct_continuity.receipt_sha256 -and [string]$continuity.status -ceq 'passed-private-historical-continuity' -and [string]$continuity.target -ceq $target -and [string]$continuity.engine.sha256 -ceq [string]$row.engine.sha256 -and [string]$continuity.predecessor.sha256 -ceq [string]$row.predecessor.archive_sha256 -and [string]$continuity.predecessor.version -ceq [string]$row.predecessor.version -and [string]$continuity.candidate.sha256 -ceq [string]$row.candidate.archive_sha256 -and [string]$continuity.candidate.version -ceq [string]$row.candidate.distribution_version -and @($continuity.assertions | Where-Object {[string]$_.status -cne 'passed'}).Count -eq 0 -and $missingContinuityAssertions.Count -eq 0) 'historical-local-evidence-index-continuity-binding' $target
}
[pscustomobject][ordered]@{status='passed-local-private-historical-evidence-index';targets=$expected;record_sha256=[string]$index.record_sha256;independently_reviewable=$false;public_admission_authorized=$false}
