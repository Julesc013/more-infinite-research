[CmdletBinding()]
param([switch]$IdentityContractsOnly)

Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
$engineRunnerPath = Join-Path $repo 'tools/commands/release/Invoke-MIR42FourTargetEngineRun.ps1'
$engineTokens=$null;$engineErrors=$null
$engineAst=[Management.Automation.Language.Parser]::ParseFile($engineRunnerPath,[ref]$engineTokens,[ref]$engineErrors)
if(@($engineErrors).Count-ne0){throw '[mir42-candidate-engine-reader-parse]'}
foreach($name in @('Assert-MIR42EngineRunFile','Get-MIR42EngineCandidateVersionContract')){
  $definitions=@($engineAst.FindAll({param($node) $node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$true))
  if($definitions.Count-ne1){throw ('[mir42-candidate-engine-reader-definition] '+$name)}
  . ([scriptblock]::Create($definitions[0].Extent.Text))
}
$script:MIR42ModernEngineTargets=@('f210','f200','f110','f100')
$script:MIR42NineTargetEngineTargets=@($script:MIR42ModernEngineTargets+@('f017','f016','f015','f014','f013'))
$engineEnvelopeAssertions=0
$engineDestinationAssertions=0
$maintenanceCustodyAssertions=0
$maintenanceEvidenceAssertions=0
$maintenanceIndependentAssertions=0
$sealCandidateContractAssertions=0
$maintenanceBinderAssertions=0
$maintenanceCriterionAssertions=0
$maintenanceCampaignAssertions=0
$maintenanceReadinessAssertions=0
$maintenanceSealAssertions=0
$script:mir42CandidateStubCalls = [Collections.Generic.List[string]]::new()
$script:mir42CandidateStubFailureTarget = ''

function Assert-MIR42CandidateBuildTest {
  param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
  if (-not $Condition) { throw "[mir42-candidate-build-test] $Message" }
}

function New-MIR4TargetPackage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$CandidateId,
    [string]$SourceVersion,
    [string]$DistributionVersion,
    [string]$OutputRoot
  )

  $script:mir42CandidateStubCalls.Add("$Target/$CandidateId")
  if ($script:mir42CandidateStubFailureTarget -ceq $Target -and $CandidateId.EndsWith('-B', [StringComparison]::Ordinal)) {
    throw "[mir42-candidate-stub-later-failure] $Target"
  }
  $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $RepoRoot -Target $Target -SourceVersion $SourceVersion -DistributionVersion $DistributionVersion
  $candidateRoot = Join-Path $OutputRoot "$Target/$CandidateId"
  $tree = Join-Path $candidateRoot ([string]$identity.distribution_root)
  New-Item -ItemType Directory -Force -Path $tree | Out-Null
  $stubInfo = [ordered]@{name='more-infinite-research';version=[string]$identity.distribution_version;factorio_version=([string]$identity.target_id).Substring('factorio-'.Length)}
  [IO.File]::WriteAllText((Join-Path $tree 'info.json'), (($stubInfo | ConvertTo-Json -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $tree 'data.lua'), ('return {}' + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
  $archive = Join-Path $candidateRoot ([string]$identity.package_name)
  Write-MIR4DeterministicRawTreeArchive -SourceRoot $tree -EntryRoot ([string]$identity.distribution_root) -OutputPath $archive -ContainmentRoot $OutputRoot
  $inventory = Get-MIR4ArchiveInventory -Path $archive
  return [pscustomobject][ordered]@{
    target = $Target
    candidate_id = $CandidateId
    source_version = $SourceVersion
    distribution_version = $DistributionVersion
    tree_path = $tree
    archive_path = $archive
    archive_sha256 = [string]$inventory.archive_sha256
    content_sha256 = [string]$inventory.content_sha256
    entry_count = [int]$inventory.entry_count
    record_sha256 = ('A' * 64)
  }
}

. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42CandidateBuild.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42IndependentEvidenceRehash.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')

function Test-MIR42IndependentConstructionInput {
  param([Parameter(Mandatory)][string]$CandidateRoot,[Parameter(Mandatory)][object[]]$Inputs)
  # Exercise real construction rows and archives, but stop at an intentionally
  # mismatched predecessor. The engine lookup is a counted fixture, never native.
  $manifestPath = Join-Path $CandidateRoot 'candidate-manifest.json'
  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
  $reference = $Inputs[0].candidate_manifest
  $qualification = [pscustomobject][ordered]@{
    schema=1;kind='MIR42NineTargetEvidenceReconciliationV1';status='MIR-4.2-NINE-TARGET-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED'
    source=$manifest.source;candidate_manifest=$reference;all_nine_targets_required=$true;cross_target_substitution=$false
    factorio_processes=0;release_qualification='not-performed';independent_verification='not-performed';publication_authorized=$false
    targets=@(foreach($inputRow in $Inputs){[pscustomobject][ordered]@{
      target=$inputRow.target;distribution_version=$inputRow.identity.distribution_version;status='reconciled';qualification='not-performed'
      candidate=$inputRow.archive;candidate_manifest=$reference;candidate_target_row=$inputRow.target_row
      predecessor=[pscustomobject]@{archive=[pscustomobject]@{sha256=('0' * 64)}}
    }})
    record_sha256=''
  }
  $qualificationPath=Join-Path $CandidateRoot 'independent-input-fixture.json'
  Write-MIR4BootstrapRecord -Record $qualification -Path $qualificationPath | Out-Null
  $maps=@{}
  foreach($inputRow in $Inputs){$maps[$inputRow.target]=Join-Path $CandidateRoot $inputRow.archive.path}
  $output=Join-Path $CandidateRoot 'independent-refusal'
  $arguments=@{RepoRoot=$repo;CandidateManifestPath=$manifestPath;QualificationPath=$qualificationPath;PredecessorZips=$maps;UpgradeReceipts=$maps;OutputRoot=$output}
  $originalEngine=(Get-Item Function:Get-MIR42IndependentEngine).ScriptBlock
  $script:mir42IndependentEngineFixtureCalls=0
  $rowPath=Join-Path $CandidateRoot $Inputs[0].target_row.path
  $originalRow=[IO.File]::ReadAllBytes($rowPath)
  $originalQualification=[IO.File]::ReadAllBytes($qualificationPath)
  try {
    Set-Item Function:Get-MIR42IndependentEngine -Value {
      param($RepoRoot,$Target,$Qualified)
      $script:mir42IndependentEngineFixtureCalls++
      return [pscustomobject]@{path='fixture-only';version='fixture-only';binary_sha256=('A' * 64)}
    }
    $rejected=$false
    try { Invoke-MIR42NineTargetIndependentEvidenceRehash @arguments | Out-Null } catch {$rejected=$_.Exception.Message -ceq '[mir42-independent-predecessor] f210'}
    Assert-MIR42CandidateBuildTest ($rejected -and $script:mir42IndependentEngineFixtureCalls -eq 1 -and -not (Test-Path -LiteralPath $output)) 'independent-version-input-reaches-required-predecessor-refusal-without-output'
    foreach($tamper in @('source-version','row-schema','row-kind')){
      $badRow=[Text.UTF8Encoding]::new($false).GetString($originalRow) | ConvertFrom-Json -Depth 100
      switch($tamper){
        'source-version' {$badRow.source_version=if($Inputs[0].identity.source_version -ceq '4.2.1'){'4.2.0'}else{'4.2.1'}}
        'row-schema' {$badRow.schema=2}
        'row-kind' {$badRow.kind='MIR42FourTargetCandidateRowV2'}
      }
      Write-MIR4BootstrapRecord -Record $badRow -Path $rowPath | Out-Null
      # Rebind the supplied upstream row hash, so a raw-hash mismatch cannot
      # substitute for the independent row identity check under test.
      $qualification.targets[0].candidate_target_row.sha256=Get-MIR4Sha256File -Path $rowPath
      Write-MIR4BootstrapRecord -Record $qualification -Path $qualificationPath | Out-Null
      $script:mir42IndependentEngineFixtureCalls=0;$rejected=$false
      try { Invoke-MIR42NineTargetIndependentEvidenceRehash @arguments | Out-Null } catch {$rejected=$_.Exception.Message -ceq '[mir42-independent-candidate-binding] f210'}
      Assert-MIR42CandidateBuildTest ($rejected -and $script:mir42IndependentEngineFixtureCalls -eq 0 -and -not (Test-Path -LiteralPath $output)) "independent-refuses-rebound-$tamper-before-engine-lookup"
      [IO.File]::WriteAllBytes($rowPath,$originalRow)
    }
  } finally {
    [IO.File]::WriteAllBytes($rowPath,$originalRow)
    [IO.File]::WriteAllBytes($qualificationPath,$originalQualification)
    Set-Item Function:Get-MIR42IndependentEngine -Value $originalEngine
  }
}

$commit = (& git -C $repo rev-parse HEAD).Trim()
$root = Join-Path $repo ('build/test-results/mir42-four-target-candidate-' + [guid]::NewGuid().ToString('N'))
$partialRoot = $root + '-partial'
$historicalRoot = $root + '-historical'
$nineRoot = $root + '-nine'
$identityRoot = $root + '-identity'
$patchRoot = $root + '-patch'
$historicalRecordHashes = @{}
foreach ($target in @('f017','f016','f015','f014','f013')) {
  $historicalRecordHashes[$target] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo "targets/historical/$target/target.json")).Hash
}
try {
  $nineDescriptors = @(Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SelectedTargets @('f210', 'f200', 'f110', 'f100', 'f017', 'f016', 'f015', 'f014', 'f013'))
  Assert-MIR42CandidateBuildTest (($nineDescriptors | ForEach-Object { [string]$_.target }) -join '|' -ceq 'f210|f200|f110|f100|f017|f016|f015|f014|f013') 'nine-target-descriptor-order'
  Assert-MIR42CandidateBuildTest (@($nineDescriptors | Where-Object { [string]$_.materializer -ceq 'canonical-package-source' }).Count -eq 4) 'nine-target-canonical-descriptor-count'
  Assert-MIR42CandidateBuildTest (@($nineDescriptors | Where-Object { [string]$_.materializer -ceq 'historical-playtest-target' }).Count -eq 5) 'nine-target-historical-descriptor-count'
  Assert-MIR42CandidateBuildTest (@($nineDescriptors | Where-Object { [bool]$_.public_output_authorized -or [bool]$_.publication_authorized }).Count -eq 0) 'nine-target-descriptor-private-boundary'
  $patchDescriptors=@(Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SelectedTargets @('f210','f200','f110','f100','f017','f016','f015','f014','f013') -SourceVersion '4.2.1')
  $patchVersions=@('4.2.21001','4.2.20001','4.2.11001','4.2.10001','4.2.01701','4.2.01601','4.2.01501','4.2.01401','4.2.01301')
  Assert-MIR42CandidateBuildTest (($patchDescriptors.distribution_version-join'|')-ceq($patchVersions-join'|')) 'nine-target-requested-source-patch'
  for ($i = 0; $i -lt $patchVersions.Count; $i++) {
    $patchIdentity = Get-MIR42ReleaseTargetIdentity -RepoRoot $repo -Target ([string]$patchDescriptors[$i].target) -SourceVersion '4.2.1'
    $baselineIdentity = Get-MIR42ReleaseTargetIdentity -RepoRoot $repo -Target ([string]$patchDescriptors[$i].target)
    Assert-MIR42CandidateBuildTest ([string]$patchIdentity.source_version -ceq '4.2.1' -and [string]$patchIdentity.distribution_version -ceq $patchVersions[$i] -and [string]$patchIdentity.distribution_root -ceq "more-infinite-research_$($patchVersions[$i])" -and [string]$patchIdentity.package_name -ceq "more-infinite-research_$($patchVersions[$i]).zip" -and [string]$baselineIdentity.distribution_version -ceq [string]$nineDescriptors[$i].distribution_version) "patch-release-target-reader-and-historical-default-$i"
  }
  $patchDefaults = @(Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SourceVersion '4.2.1')
  Assert-MIR42CandidateBuildTest (($patchDefaults.target -join '|') -ceq ($patchDescriptors.target -join '|')) 'patch-default-selects-all-nine'
  $patchFourRejected = $false
  try { Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SourceVersion '4.2.1' -SelectedTargets @('f210','f200','f110','f100') | Out-Null } catch { $patchFourRejected = $_.Exception.Message -match 'mir42-candidate-target-selection-unsupported' }
  Assert-MIR42CandidateBuildTest $patchFourRejected 'patch-rejects-explicit-four-target-selection'
  Assert-MIR42CandidateBuildTest (@($patchDescriptors|Where-Object{[string]$_.source_version-cne'4.2.1'-or[bool]$_.public_output_authorized-or[bool]$_.publication_authorized}).Count-eq0) 'nine-target-requested-source-private-boundary'
  Assert-MIR42CandidateBuildTest (@($nineDescriptors|Where-Object{[string]$_.source_version-cne'4.2.0'}).Count-eq0) 'historical-default-source-preserved'
  $unsupportedSourceRejected=$false
  try{Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SourceVersion '4.2.2'|Out-Null}catch{$unsupportedSourceRejected=$true}
  Assert-MIR42CandidateBuildTest $unsupportedSourceRejected 'unsupported-source-version-rejected'
  foreach ($schemaVersion in @(1,2)) {
    $versionContract = Get-MIR42CandidateConstructionVersionContract -RepoRoot $repo -Manifest ([pscustomobject]@{schema=$schemaVersion;kind="MIR42FourTargetDeterministicCandidateManifestV$schemaVersion"})
    $expectedSource = if ($schemaVersion -eq 1) { '4.2.0' } else { '4.2.1' }
    Assert-MIR42CandidateBuildTest ($versionContract.source_version -ceq $expectedSource -and $versionContract.requires_nine_targets -eq ($schemaVersion -eq 2) -and (Test-Path -LiteralPath $versionContract.schema_path -PathType Leaf)) "construction-version-contract-$schemaVersion"
  }
  foreach ($badContract in @(
    [pscustomobject]@{schema=3;kind='MIR42FourTargetDeterministicCandidateManifestV3'},
    [pscustomobject]@{schema=2;kind='MIR42FourTargetDeterministicCandidateManifestV1'}
  )) {
    $rejected = $false
    try { Get-MIR42CandidateConstructionVersionContract -RepoRoot $repo -Manifest $badContract | Out-Null } catch { $rejected=$_.Exception.Message -match 'mir42-candidate-construction-version-contract' }
    Assert-MIR42CandidateBuildTest $rejected 'construction-version-contract-refuses-unsupported-or-mixed-kind'
  }
  $duplicateRejected = $false
  try { Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SelectedTargets @('f210', 'f200', 'f110', 'f100', 'f017', 'f017', 'f016', 'f015', 'f014', 'f013') | Out-Null } catch { $duplicateRejected = $_.Exception.Message -match 'mir42-candidate-target-selection-duplicate' }
  Assert-MIR42CandidateBuildTest $duplicateRejected 'nine-target-descriptor-duplicate-rejected'
  $unknownRejected = $false
  try { Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SelectedTargets @('f210', 'f200', 'f110', 'f100', 'f017', 'f016', 'f015', 'f014', 'f999') | Out-Null } catch { $unknownRejected = $_.Exception.Message -match 'mir42-candidate-target-selection-unsupported' }
  Assert-MIR42CandidateBuildTest $unknownRejected 'nine-target-descriptor-unknown-rejected'
  $mismatchedHistoricalRecord = Get-Content -Raw -LiteralPath (Join-Path $repo 'targets/historical/f017/target.json') | ConvertFrom-Json -Depth 100 -DateKind String
  $mismatchedHistoricalRecord.factorio_line = '0.13'
  $mismatchedHistoricalRecord.distribution_version = '4.2.01300'
  $mismatchedHistoricalRecord.record_sha256 = ''
  $mismatchedHistoricalRecord.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $mismatchedHistoricalRecord
  $mismatchedHistoricalRejected = $false
  try { Assert-MIR42HistoricalCandidateTargetRecord -Target f017 -Record $mismatchedHistoricalRecord } catch { $mismatchedHistoricalRejected = $_.Exception.Message -match 'mir42-candidate-historical-target-record-invalid' }
  Assert-MIR42CandidateBuildTest $mismatchedHistoricalRejected 'nine-target-descriptor-mismatched-self-hashed-record-rejected'

  $utf8 = [Text.UTF8Encoding]::new($false)
  $lines = @('2.1','2.0','1.1','1.0','0.17','0.16','0.15','0.14','0.13')
  for ($i = 0; $i -lt $patchVersions.Count; $i++) {
    $tree = Join-Path $identityRoot ([string]$patchDescriptors[$i].target)
    New-Item -ItemType Directory -Force -Path $tree | Out-Null
    $baseline = [string]$nineDescriptors[$i].distribution_version
    $inputInfo = [ordered]@{ name='more-infinite-research'; version=$baseline; factorio_version=$lines[$i]; dependencies=@('base'); title='Preserved authored title' }
    $history = "---------------------------------------------------------------------------------------------------`nVersion: $baseline`n  Changes:`n    - Preserved historical entry.`n"
    $readme = "# Preserved authored README`n`nSettings, research catalogue, examples and troubleshooting remain here.`n"
    [IO.File]::WriteAllText((Join-Path $tree 'info.json'), ($inputInfo | ConvertTo-Json -Depth 20), $utf8)
    [IO.File]::WriteAllText((Join-Path $tree 'changelog.txt'), $history, $utf8)
    [IO.File]::WriteAllText((Join-Path $tree 'README.md'), $readme, $utf8)
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion $patchVersions[$i]
    $info = Get-Content -Raw -LiteralPath (Join-Path $tree 'info.json') | ConvertFrom-Json -Depth 20
    Assert-MIR42CandidateBuildTest ([string]$info.version -ceq $patchVersions[$i] -and [string]$info.factorio_version -ceq $lines[$i] -and [string]$info.title -ceq $inputInfo.title -and @($info.dependencies).Count -eq 1) "patch-metadata-identity-and-preserved-fields-$i"
    $writtenHistory = [IO.File]::ReadAllText((Join-Path $tree 'changelog.txt'))
    Assert-MIR42CandidateBuildTest ($writtenHistory.StartsWith("---------------------------------------------------------------------------------------------------`nVersion: $($patchVersions[$i])`n", [StringComparison]::Ordinal) -and $writtenHistory.EndsWith($history, [StringComparison]::Ordinal)) "patch-current-changelog-and-preserved-history-$i"
    $writtenReadme = [IO.File]::ReadAllText((Join-Path $tree 'README.md'))
    Assert-MIR42CandidateBuildTest ($writtenReadme.StartsWith("MIR $($patchVersions[$i]), source 4.2.1.", [StringComparison]::Ordinal) -and $writtenReadme.EndsWith($readme, [StringComparison]::Ordinal)) "patch-readme-identity-and-preserved-prose-$i"
    $firstHashes = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion $patchVersions[$i]
    $secondHashes = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
    Assert-MIR42CandidateBuildTest (($firstHashes -join '|') -ceq ($secondHashes -join '|')) "patch-metadata-idempotence-$i"
  }
  $negativeTree = Join-Path $identityRoot 'f210'
  foreach ($badVersion in @('4.2.21002','4.2.20001','4.2.99901')) {
    $before = @(Get-ChildItem -LiteralPath $negativeTree -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
    $rejected = $false
    try { Write-MIR4PrivatePatchPackageIdentity -Tree $negativeTree -DistributionVersion $badVersion } catch { $rejected = $true }
    $after = @(Get-ChildItem -LiteralPath $negativeTree -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
    Assert-MIR42CandidateBuildTest ($rejected -and ($before -join '|') -ceq ($after -join '|')) "patch-invalid-version-no-writes-$badVersion"
  }
  $schemaPath = Join-Path $repo 'spec/schemas/mir42-four-target-deterministic-candidate-manifest-v2.schema.json'
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $schemaPreflight = [pscustomobject]@{
    source=[ordered]@{commit=$commit;tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()}
    package_authority_sha256=[string]$authority.record_sha256
    package_source_sha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
    target_authority=@($patchDescriptors | Select-Object target,target_id,source_version,distribution_version)
    resource_admission=[ordered]@{admitted=$true;minimum_free_memory_bytes=1;minimum_free_work_bytes=1}
  }
  # These rows are schema fixtures, not package construction or qualification.
  $schemaRows = @(foreach ($descriptor in $patchDescriptors) {
    [pscustomobject]@{
      target=[string]$descriptor.target;distribution_version=[string]$descriptor.distribution_version
      asset=[ordered]@{path="assets/$($descriptor.target)/more-infinite-research_$($descriptor.distribution_version).zip";bytes=1;sha256=('A'*64)}
      content_sha256=('B'*64);entry_count=1
    }
  })
  $schemaRoot = Join-Path $identityRoot 'schema'
  New-Item -ItemType Directory -Force -Path $schemaRoot | Out-Null
  $schemaComplete = Write-MIR42FourTargetManifest -OutputRoot $schemaRoot -Preflight $schemaPreflight -Rows $schemaRows -Failures @()
  Assert-MIR42CandidateBuildTest ($schemaComplete.schema -eq 2 -and $schemaComplete.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV2' -and (Test-MIR4BootstrapRecordHash -Record $schemaComplete)) 'patch-v2-manifest-writer-and-record-hash'
  $sealVersion=Get-MIR42SealCandidateConstructionVersionContract -RepoRoot $repo -Manifest $schemaComplete
  Assert-MIR42CandidateBuildTest ($sealVersion.source_version-ceq'4.2.1'-and$sealVersion.requires_nine_targets) 'seal-reader-selects-v2-nine-target-contract-without-qualification'
  $sealCandidateContractAssertions++
  $binderCandidate=[pscustomobject]@{scope='nine-target';targets=$schemaComplete.targets;identity=[pscustomobject]@{record=$schemaComplete}}
  $binderContract=Get-MIR42EngineEvidenceBindingContract -Candidate $binderCandidate -PublishedMaintenance
  Assert-MIR42CandidateBuildTest ($binderContract.binder_kind-ceq'MIR42NineTargetMaintenanceRealEngineEvidenceBinderV1'-and
    $binderContract.evidence_kind-ceq'MIR42NineTargetMaintenanceEvidenceReconciliationV1'-and$binderContract.engine_run_kind-ceq'MIR42NineTargetMaintenanceEngineRunV1') 'maintenance-binder-selects-only-current-binding-identities'
  $maintenanceBinderAssertions++
  $unchangedSealContract=Get-MIR42SealScopeContract -Scope 'nine-target'
  Assert-MIR42CandidateBuildTest ($unchangedSealContract.binder_kind-ceq'MIR42NineTargetRealEngineEvidenceBinderV1'-and$unchangedSealContract.campaign_kind-ceq'MIR42NineTargetRealEngineCandidateCampaignV1') 'maintenance-binder-does-not-change-global-campaign-or-seal-contract'
  $maintenanceBinderAssertions++
  $campaignContract=Get-MIR42JoinedCampaignInputContract -Candidate $binderCandidate -PublishedMaintenance
  Assert-MIR42CandidateBuildTest ($campaignContract.campaign_kind-ceq'MIR42NineTargetMaintenanceRealEngineCandidateCampaignV1'-and$campaignContract.binder_kind-ceq'MIR42NineTargetMaintenanceRealEngineEvidenceBinderV1') 'maintenance-campaign-selects-current-input-contract'
  $maintenanceCampaignAssertions++
  $defaultCampaignContract=Get-MIR42JoinedCampaignInputContract -Candidate $binderCandidate
  Assert-MIR42CandidateBuildTest ($defaultCampaignContract.campaign_kind-ceq$unchangedSealContract.campaign_kind-and$binderContract.campaign_kind-ceq$unchangedSealContract.campaign_kind) 'maintenance-campaign-keeps-default-and-binder-contracts-independent'
  $maintenanceCampaignAssertions++
  $independentSealContract=Get-MIR42SealIndependentInputContract -Candidate $binderCandidate -PublishedMaintenance
  $independentWriterContract=Get-MIR42IndependentScopeContract -Scope 'nine-target' -PublishedMaintenance
  Assert-MIR42CandidateBuildTest ($independentSealContract.independent_kind-ceq$independentWriterContract.rehash_kind-and$independentSealContract.independent_status-ceq$independentWriterContract.rehash_status) 'maintenance-readiness-consumes-the-independent-writer-contract'
  $maintenanceReadinessAssertions++
  $defaultIndependentContract=Get-MIR42SealIndependentInputContract -Candidate $binderCandidate
  Assert-MIR42CandidateBuildTest ($defaultIndependentContract.independent_kind-ceq$unchangedSealContract.independent_kind) 'maintenance-readiness-keeps-default-independent-contract'
  $maintenanceReadinessAssertions++
  $fourBinderCandidate=[pscustomobject]@{scope='four-target';targets=@($schemaComplete.targets|Select-Object -First 4);identity=[pscustomobject]@{record=$schemaComplete}}
  $maintenanceSealContract=Get-MIR42TechnicalSealInputContract -Candidate $binderCandidate -PublishedMaintenance
  Assert-MIR42CandidateBuildTest ($maintenanceSealContract.seal_kind-ceq'MIR42NineTargetMaintenanceTechnicalSealV1'-and$maintenanceSealContract.seal_status-ceq'MIR-4.2.1-NINE-TARGET-MAINTENANCE-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR'-and$maintenanceSealContract.independent_kind-ceq$independentWriterContract.rehash_kind) 'maintenance-seal-selects-current-seal-and-input-contracts'
  $maintenanceSealAssertions++
  foreach($scopeCandidate in @($binderCandidate,$fourBinderCandidate)){
    $defaultSealContract=Get-MIR42TechnicalSealInputContract -Candidate $scopeCandidate
    $scopeContract=Get-MIR42SealScopeContract -Scope $scopeCandidate.scope
    Assert-MIR42CandidateBuildTest ((ConvertTo-MIR4BootstrapCanonicalJson -Value $defaultSealContract)-ceq(ConvertTo-MIR4BootstrapCanonicalJson -Value $scopeContract)) 'maintenance-seal-preserves-default-scope-contract'
    $maintenanceSealAssertions++
  }
  $failure='';try{Get-MIR42TechnicalSealInputContract -Candidate $fourBinderCandidate -PublishedMaintenance|Out-Null}catch{$failure=$_.Exception.Message}
  Assert-MIR42CandidateBuildTest ($failure-ceq'[mir42-engine-evidence-maintenance-candidate-scope]') 'maintenance-seal-refuses-four-target-contract'
  $maintenanceSealAssertions++
  $rejected=$false
  try{Get-MIR42EngineEvidenceBindingContract -Candidate $fourBinderCandidate -PublishedMaintenance|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-engine-evidence-maintenance-candidate-scope]'}
  Assert-MIR42CandidateBuildTest $rejected 'maintenance-binder-refuses-four-target-scope'
  $maintenanceBinderAssertions++
  $engineFixturePath=Join-Path $schemaRoot 'candidate-manifest.json'
  $engineVersion=Get-MIR42EngineCandidateVersionContract -RepoRoot $repo -ManifestPath $engineFixturePath
  Assert-MIR42CandidateBuildTest ($engineVersion.source_version-ceq'4.2.1'-and$engineVersion.nine_targets-and-not$engineVersion.four_targets-and@($engineVersion.targets).Count-eq9) 'native-runner-reads-v2-nine-target-envelope-without-execution'
  $engineEnvelopeAssertions++
  $badHash=$schemaComplete|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $badHash.record_sha256='0'*64
  [IO.File]::WriteAllText($engineFixturePath,($badHash|ConvertTo-Json -Depth 100),$utf8)
  $rejected=$false
  try{Get-MIR42EngineCandidateVersionContract -RepoRoot $repo -ManifestPath $engineFixturePath|Out-Null}catch{$rejected=$_.Exception.Message-eq'[mir42-engine-candidate-manifest-invalid]'}
  Assert-MIR42CandidateBuildTest $rejected 'native-runner-refuses-valid-schema-with-invalid-record-hash'
  $engineEnvelopeAssertions++
  $rejected=$false
  try{Get-MIR42SealCandidateConstructionVersionContract -RepoRoot $repo -Manifest $badHash|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-seal-candidate-record-hash]'}
  Assert-MIR42CandidateBuildTest $rejected 'seal-reader-refuses-invalid-construction-record-hash'
  $sealCandidateContractAssertions++
  $schemaPartial = Write-MIR42FourTargetManifest -OutputRoot $schemaRoot -Preflight $schemaPreflight -Rows @($schemaRows[0]) -Failures @([ordered]@{target='f200';message='schema-fixture-only'})
  Assert-MIR42CandidateBuildTest (-not $schemaPartial.build_complete -and $schemaPartial.status -ceq 'private-deterministic-nine-target-candidate-partial') 'patch-partial-manifest-preserves-complete-authority'
  $rejected=$false
  try{Get-MIR42EngineCandidateVersionContract -RepoRoot $repo -ManifestPath $engineFixturePath|Out-Null}catch{$rejected=$_.Exception.Message-eq'[mir42-engine-candidate-manifest-invalid]'}
  Assert-MIR42CandidateBuildTest $rejected 'native-runner-refuses-schema-valid-partial-envelope'
  $engineEnvelopeAssertions++
  $schemaMutations = [ordered]@{
    'authority-source-zero' = { param($m) $m.target_authority[0].source_version='4.2.0' }
    'authority-wrong-target-version' = { param($m) $m.target_authority[0].distribution_version='4.2.20001' }
    'authority-wrong-engine-line' = { param($m) $m.target_authority[0].target_id='factorio-2.0' }
    'authority-missing-target' = { param($m) $m.target_authority=@($m.target_authority | Select-Object -Skip 1) }
    'authority-duplicate-target' = { param($m) $m.target_authority[8]=$m.target_authority[0] }
    'row-wrong-target-version' = { param($m) $m.targets[0].distribution_version='4.2.20001' }
    'row-patch-two' = { param($m) $m.targets[0].distribution_version='4.2.21002' }
    'row-wrong-target-path' = { param($m) $m.targets[0].target_row_path='target-rows/f200.json' }
    'row-wrong-asset-path' = { param($m) $m.targets[0].asset.path='assets/f200/more-infinite-research_4.2.20001.zip' }
    'complete-missing-target' = { param($m) $m.targets=@($m.targets | Select-Object -Skip 1) }
    'complete-duplicate-target' = { param($m) $m.targets[8]=$m.targets[0] }
    'complete-has-failure' = { param($m) $m.failures=@([ordered]@{target='f200'}) }
    'complete-partial-status' = { param($m) $m.status='private-deterministic-nine-target-candidate-partial' }
    'qualification-claim' = { param($m) $m.qualification='passed' }
    'publication-claim' = { param($m) $m.publication_authorized=$true }
  }
  foreach ($case in $schemaMutations.GetEnumerator()) {
    $invalid = $schemaComplete | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    & $case.Value $invalid
    $valid = $invalid | ConvertTo-Json -Depth 100 | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue
    Assert-MIR42CandidateBuildTest (-not $valid) "patch-schema-refuses-$($case.Key)"
    $invalid.record_sha256=''
    $invalid.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $invalid
    [IO.File]::WriteAllText($engineFixturePath,($invalid|ConvertTo-Json -Depth 100),$utf8)
    $rejected=$false
    try{Get-MIR42EngineCandidateVersionContract -RepoRoot $repo -ManifestPath $engineFixturePath|Out-Null}catch{$rejected=$_.Exception.Message-eq'[mir42-engine-candidate-manifest-schema]'}
    Assert-MIR42CandidateBuildTest $rejected "native-runner-refuses-self-hashed-$($case.Key)"
    $engineEnvelopeAssertions++
    $rejected=$false
    try{Get-MIR42SealCandidateConstructionVersionContract -RepoRoot $repo -Manifest $invalid|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-seal-candidate-manifest-schema]'}
    Assert-MIR42CandidateBuildTest $rejected "seal-reader-refuses-self-hashed-$($case.Key)"
    $sealCandidateContractAssertions++
  }
  foreach($entry in @(@{mode='Seal';code='[mir42-seal-output-path-required]'},@{mode='PromotionPlan';code='[mir42-promotion-technical-seal-required]'},@{mode='MainReadback';code='[mir42-main-readback-primary-required]'})){
    $rejected=$false
    try{& (Join-Path $repo 'tools/commands/release/Invoke-MIR42NineTargetSealPromotion.ps1') -RepoRoot $repo -Mode $entry.mode -CandidateManifestPath 'unused-control.json' -PublishedMaintenancePredecessorManifestPath 'unread-control-manifest.json'|Out-Null}catch{$rejected=$_.Exception.Message-ceq$entry.code}
    Assert-MIR42CandidateBuildTest $rejected ('maintenance-seal-command-retains-required-input-'+$entry.mode)
    $maintenanceSealAssertions++
  }
  $sealedOutput=Join-Path $identityRoot 'must-not-seal.json'
  $failure='';try{& (Join-Path $repo 'tools/commands/release/Invoke-MIR42NineTargetSealPromotion.ps1') -RepoRoot $repo -Mode Seal -CandidateManifestPath 'unused-control.json' -PublishedMaintenancePredecessorManifestPath 'unread-control-manifest.json' -OutputPath $sealedOutput|Out-Null}catch{$failure=$_.Exception.Message}
  Assert-MIR42CandidateBuildTest ($failure.StartsWith('[mir42-seal-not-authorized]')-and-not(Test-Path -LiteralPath $sealedOutput)) 'maintenance-seal-command-refuses-missing-evidence-before-output'
  $maintenanceSealAssertions++
  $failure='';try{New-MIR42TechnicalSealForScope -RequiredScope four-target -RepoRoot $repo -CandidateManifestPath 'unused-control.json' -PublishedMaintenancePredecessorManifestPath 'unread-control-manifest.json' -OutputPath $sealedOutput|Out-Null}catch{$failure=$_.Exception.Message}
  Assert-MIR42CandidateBuildTest ($failure-ceq'[mir42-maintenance-readiness-candidate-scope]'-and-not(Test-Path -LiteralPath $sealedOutput)) 'maintenance-seal-writer-refuses-four-target-scope-before-read-or-write'
  $maintenanceSealAssertions++
  $rejected=$false
  try{& (Join-Path $repo 'tools/commands/release/Invoke-MIR42NineTargetSealPromotion.ps1') -RepoRoot $repo -Mode JoinedCampaign -CandidateManifestPath 'unused-control.json' -PublishedMaintenancePredecessorManifestPath 'unread-control-manifest.json'|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-joined-campaign-inputs-required]'}
  Assert-MIR42CandidateBuildTest $rejected 'maintenance-campaign-command-reaches-required-input-guard-without-output'
  $maintenanceCampaignAssertions++
  $diagnostic=& (Join-Path $repo 'tools/commands/release/Invoke-MIR42NineTargetSealPromotion.ps1') -RepoRoot $repo -Mode Readiness -CandidateManifestPath 'unused-control.json' -PublishedMaintenancePredecessorManifestPath 'unread-control-manifest.json'|ConvertFrom-Json -Depth 100
  Assert-MIR42CandidateBuildTest (-not$diagnostic.technical_seal_authorized-and-not$diagnostic.publication_authorized-and-not$diagnostic.checks.candidate-and-not$diagnostic.checks.maintenance_predecessor-and$diagnostic.blockers-cnotcontains'[mir42-maintenance-seal-consumer-pending]') 'maintenance-readiness-command-stays-blocked-without-candidate-or-evidence'
  $maintenanceReadinessAssertions++
  $failure='';try{Get-MIR42TechnicalSealReadinessForScope -RequiredScope four-target -RepoRoot $repo -CandidateManifestPath 'unused-control.json' -PublishedMaintenancePredecessorManifestPath 'unread-control-manifest.json'|Out-Null}catch{$failure=$_.Exception.Message}
  Assert-MIR42CandidateBuildTest ($failure-ceq'[mir42-maintenance-readiness-candidate-scope]') 'maintenance-readiness-refuses-four-target-scope-before-input-read'
  $maintenanceReadinessAssertions++
  $invalidPartial = $schemaPartial | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
  $duplicatePartialRow = $invalidPartial.targets[0] | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
  $duplicatePartialRow.asset.sha256='C'*64
  $invalidPartial.targets=@($invalidPartial.targets[0],$duplicatePartialRow)
  $valid = $invalidPartial | ConvertTo-Json -Depth 100 | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue
  Assert-MIR42CandidateBuildTest (-not $valid) 'patch-schema-refuses-partial-same-target-different-row'
  foreach($legacyCount in @(4,9)){
    $legacyDescriptors=@($nineDescriptors|Select-Object -First $legacyCount)
    $legacyPreflight=$schemaPreflight|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $legacyPreflight.target_authority=@($legacyDescriptors|Select-Object target,target_id,source_version,distribution_version)
    $legacyRows=@(foreach($descriptor in $legacyDescriptors){
      [pscustomobject]@{target=[string]$descriptor.target;distribution_version=[string]$descriptor.distribution_version
        asset=[ordered]@{path="assets/$($descriptor.target)/more-infinite-research_$($descriptor.distribution_version).zip";bytes=1;sha256=('A'*64)}
        content_sha256=('B'*64);entry_count=1}
    })
    $legacyFixture=Write-MIR42FourTargetManifest -OutputRoot $schemaRoot -Preflight $legacyPreflight -Rows $legacyRows -Failures @()
    $legacyEngine=Get-MIR42EngineCandidateVersionContract -RepoRoot $repo -ManifestPath $engineFixturePath
    Assert-MIR42CandidateBuildTest ($legacyFixture.schema-eq1-and$legacyEngine.source_version-ceq'4.2.0'-and
      $legacyEngine.four_targets-eq($legacyCount-eq4)-and$legacyEngine.nine_targets-eq($legacyCount-eq9)) "native-runner-preserves-v1-$legacyCount-target-envelope"
    $engineEnvelopeAssertions++
    $legacySealVersion=Get-MIR42SealCandidateConstructionVersionContract -RepoRoot $repo -Manifest $legacyFixture
    Assert-MIR42CandidateBuildTest ($legacySealVersion.source_version-ceq'4.2.0'-and-not$legacySealVersion.requires_nine_targets) "seal-reader-preserves-v1-$legacyCount-target-schema"
    $sealCandidateContractAssertions++
  }
  $oldBinderCandidate=[pscustomobject]@{scope='nine-target';targets=$legacyFixture.targets;identity=[pscustomobject]@{record=$legacyFixture}}
  $rejected=$false
  try{Get-MIR42EngineEvidenceBindingContract -Candidate $oldBinderCandidate -PublishedMaintenance|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-engine-evidence-maintenance-candidate-scope]'}
  Assert-MIR42CandidateBuildTest $rejected 'maintenance-binder-refuses-source-zero'
  $maintenanceBinderAssertions++
  $failure='';try{Get-MIR42TechnicalSealInputContract -Candidate $oldBinderCandidate -PublishedMaintenance|Out-Null}catch{$failure=$_.Exception.Message}
  Assert-MIR42CandidateBuildTest ($failure-ceq'[mir42-engine-evidence-maintenance-candidate-scope]') 'maintenance-seal-refuses-source-zero'
  $maintenanceSealAssertions++
  # Exercise the runner's actual selection statements without its native CLI.
  $engineStatements=@($engineAst.EndBlock.Statements)
  $selectionIndex=[array]::FindIndex($engineStatements,[Predicate[object]]{param($node) $node.Extent.Text.StartsWith('$selected = ')})
  Assert-MIR42CandidateBuildTest ($selectionIndex-ge0-and$engineStatements[$selectionIndex+1]-is[Management.Automation.Language.ForEachStatementAst]) 'native-runner-selection-region'
  $selectionBlock=[scriptblock]::Create(($engineStatements[$selectionIndex..($selectionIndex+1)].Extent.Text-join"`n"))
  foreach($sourceVersion in @('4.2.0','4.2.1')){
    foreach($prefix in @('F210','F200','F110','F100')){
      Set-Variable -Name ($prefix+'Engine') -Value 'selection-fixture-no-engine'
      Set-Variable -Name ($prefix+'Predecessor') -Value 'selection-fixture-no-archive'
    }
    . $selectionBlock
    $descriptors=if($sourceVersion-ceq'4.2.0'){$nineDescriptors}else{$patchDescriptors}
    foreach($descriptor in @($descriptors|Select-Object -First 4)){
      $target=[string]$descriptor.target
      Assert-MIR42CandidateBuildTest ($selected[$target].to-ceq[string]$descriptor.distribution_version-and
        $selected[$target].from-ceq('4.1.'+$target.Substring(1)+'00')-and
        $selected[$target].engine-ceq'selection-fixture-no-engine'-and$selected[$target].predecessor-ceq'selection-fixture-no-archive') "native-runner-modern-destination-$sourceVersion-$target"
      $engineDestinationAssertions++
    }
  }
  # Exact published receipt fixture; metadata mutations are controls only.
  # No delivered ZIP, signature, engine or new-candidate acceptance is implied.
  $publishedPin=Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath (Join-Path $repo 'fixtures/release-inputs/mir421-published-420-manifest.json')
  $metadataAssets=@(for($i=0;$i-lt9;$i++){
    $row=$publishedPin.manifest.targets[$i]
    [pscustomobject]@{id=$i+1;name=$row.filename;size=$row.bytes;digest=('sha256:'+[string]$row.sha256).ToLowerInvariant();state='uploaded'}
  })
  $metadataAssets+=@(
    [pscustomobject]@{id=10;name='mir-4.2.0.release.json';size=$publishedPin.bytes;digest=('sha256:'+$publishedPin.sha256).ToLowerInvariant();state='uploaded'},
    [pscustomobject]@{id=11;name='SHA256SUMS.txt';size=1;digest=('sha256:'+('a'*64));state='uploaded'},
    [pscustomobject]@{id=12;name='release-notes.md';size=1;digest=('sha256:'+('b'*64));state='uploaded'}
  )
  $metadataFixture=[pscustomobject]@{id=402577876;tag_name='v4.2.0-stable';draft=$false;prerelease=$false;immutable=$false;assets=$metadataAssets}
  $publishedRows=@(Assert-MIR42PublishedMaintenancePredecessorMetadata -PinnedManifest $publishedPin -ReleaseMetadata $metadataFixture)
  Assert-MIR42CandidateBuildTest ($publishedRows.Count-eq9-and-not$publishedPin.manifest.signed-and
    $publishedPin.manifest.qualification.native_final_package-ceq'NOT RUN'-and$publishedPin.manifest.qualification.save_upgrade-ceq'NOT RUN') 'published-unsigned-predecessor-custody-does-not-upgrade-qualification'
  $maintenanceCustodyAssertions++
  $metadataMutations=[ordered]@{
    'release-id'={param($m) $m.id=402577877}
    'canonical-reserved-tag'={param($m) $m.tag_name='v4.2.0'}
    'draft'={param($m) $m.draft=$true}
    'prerelease'={param($m) $m.prerelease=$true}
    'immutable'={param($m) $m.immutable=$true}
    'missing-target'={param($m) $m.assets=@($m.assets|Select-Object -Skip 1)}
    'duplicate-name'={param($m) $m.assets[1].name=$m.assets[0].name}
    'duplicate-asset-id'={param($m) $m.assets[1].id=$m.assets[0].id}
    'missing-manifest'={param($m) $m.assets[9].name='another-manifest.json'}
    'manifest-digest'={param($m) $m.assets[9].digest='sha256:'+('0'*64)}
    'manifest-size'={param($m) $m.assets[9].size++}
    'target-digest'={param($m) $m.assets[0].digest='sha256:'+('0'*64)}
    'target-size'={param($m) $m.assets[0].size++}
    'target-state'={param($m) $m.assets[0].state='new'}
    'target-id'={param($m) $m.assets[0].id=0}
  }
  foreach($case in $metadataMutations.GetEnumerator()){
    $invalid=$metadataFixture|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    & $case.Value $invalid
    $rejected=$false
    try{Assert-MIR42PublishedMaintenancePredecessorMetadata -PinnedManifest $publishedPin -ReleaseMetadata $invalid|Out-Null}catch{$rejected=$_.Exception.Message.StartsWith('[mir42-maintenance-predecessor-')}
    Assert-MIR42CandidateBuildTest $rejected ('published-predecessor-refuses-'+$case.Key)
    $maintenanceCustodyAssertions++
  }
  $invalidPinPath=Join-Path $identityRoot 'changed-published-manifest.json'
  $pinBytes=[IO.File]::ReadAllBytes($publishedPin.path)
  $pinBytes[100]=$pinBytes[100]-bxor1
  [IO.File]::WriteAllBytes($invalidPinPath,$pinBytes)
  $rejected=$false
  try{Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath $invalidPinPath|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-maintenance-predecessor-frozen-manifest]'}
  Assert-MIR42CandidateBuildTest $rejected 'published-predecessor-refuses-same-size-changed-manifest-by-raw-hash'
  $maintenanceCustodyAssertions++
  $scopeCandidates=@($patchDescriptors|ForEach-Object {[pscustomobject]@{identity=$_}})
  Assert-MIR42MaintenanceReconciliationScope -Scope 'nine-target' -Candidates $scopeCandidates
  $maintenanceEvidenceAssertions++
  foreach($case in @(
    @{scope='four-target';rows=@($scopeCandidates|Select-Object -First 4)},
    @{scope='nine-target';rows=@($nineDescriptors|ForEach-Object {[pscustomobject]@{identity=$_}})},
    @{scope='nine-target';rows=@($scopeCandidates|Select-Object -First 8)}
  )){
    $rejected=$false
    try{Assert-MIR42MaintenanceReconciliationScope -Scope $case.scope -Candidates $case.rows}catch{$rejected=$_.Exception.Message-ceq'[mir42-reconciliation-maintenance-candidate-scope]'}
    Assert-MIR42CandidateBuildTest $rejected 'maintenance-reconciliation-refuses-wrong-scope-version-or-count'
    $maintenanceEvidenceAssertions++
  }
  Assert-MIR42IndependentMaintenanceScope -Scope 'nine-target' -SourceVersion '4.2.1'
  $maintenanceIndependentAssertions++
  foreach($case in @(@{scope='four-target';source='4.2.1'},@{scope='nine-target';source='4.2.0'})){
    $rejected=$false
    try{Assert-MIR42IndependentMaintenanceScope -Scope $case.scope -SourceVersion $case.source}catch{$rejected=$_.Exception.Message-ceq'[mir42-independent-maintenance-candidate-scope]'}
    Assert-MIR42CandidateBuildTest $rejected 'independent-maintenance-refuses-other-source-or-scope'
    $maintenanceIndependentAssertions++
  }
  $maintenanceContract=Get-MIR42IndependentScopeContract -Scope 'nine-target' -PublishedMaintenance
  Assert-MIR42CandidateBuildTest ($maintenanceContract.reconciliation_kind-ceq'MIR42NineTargetMaintenanceEvidenceReconciliationV1'-and$maintenanceContract.rehash_kind-ceq'MIR42NineTargetMaintenanceIndependentEvidenceRehashV1'-and$maintenanceContract.target_requirement-ceq'all_nine_targets_required') 'independent-maintenance-selects-distinct-nine-target-contract'
  $maintenanceIndependentAssertions++
  $rejected=$false
  try{Get-MIR42IndependentScopeContract -Scope 'four-target' -PublishedMaintenance|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-independent-maintenance-candidate-scope]'}
  Assert-MIR42CandidateBuildTest $rejected 'independent-maintenance-contract-refuses-four-target'
  $maintenanceIndependentAssertions++
  # Untrusted custody fields in memory only, not an authenticated input receipt.
  $custodyFields=[pscustomobject]@{metadata_fixture_only=$true;source=$publishedPin.manifest.source;manifest_sha256=$publishedPin.sha256}
  $recordedFields=$custodyFields|ConvertTo-Json -Depth 40|ConvertFrom-Json -Depth 40 -DateKind String
  Assert-MIR42IndependentMaintenanceCustody -Recorded $recordedFields -Current $custodyFields
  $maintenanceIndependentAssertions++
  foreach($field in @('source','manifest')){
    $invalid=$custodyFields|ConvertTo-Json -Depth 40|ConvertFrom-Json -Depth 40 -DateKind String
    if($field-ceq'source'){$invalid.source.commit='f'*40}else{$invalid.manifest_sha256='0'*64}
    $rejected=$false
    try{Assert-MIR42IndependentMaintenanceCustody -Recorded $invalid -Current $custodyFields}catch{$rejected=$_.Exception.Message-ceq'[mir42-independent-maintenance-custody-binding]'}
    Assert-MIR42CandidateBuildTest $rejected ('independent-maintenance-refuses-changed-custody-'+$field)
    $maintenanceIndependentAssertions++
  }
  # Tiny archive/receipt-field controls only; no authenticated public custody
  # or upgrade receipt is fabricated by these fixtures.
  $criterionBindings=[Collections.Generic.List[object]]::new()
  for($i=0;$i-lt9;$i++){
    $descriptor=$nineDescriptors[$i];$target=[string]$descriptor.target
    $fixtureRoot=Join-Path $identityRoot ('predecessor-binding/'+$target)
    $fixtureTree=Join-Path $fixtureRoot ('more-infinite-research_'+$descriptor.distribution_version)
    New-Item -ItemType Directory -Force -Path $fixtureTree|Out-Null
    $info=[ordered]@{name='more-infinite-research';version=[string]$descriptor.distribution_version;factorio_version=$lines[$i]}
    [IO.File]::WriteAllText((Join-Path $fixtureTree 'info.json'),($info|ConvertTo-Json -Compress),$utf8)
    $fixtureArchive=Join-Path $fixtureRoot ('more-infinite-research_'+$descriptor.distribution_version+'.zip')
    Write-MIR4DeterministicRawTreeArchive -SourceRoot $fixtureTree -EntryRoot (Split-Path -Leaf $fixtureTree) -OutputPath $fixtureArchive -ContainmentRoot $identityRoot
    $inventory=Get-MIR4ArchiveInventory -Path $fixtureArchive
    $binding=[pscustomobject]@{target=$target;path=$fixtureArchive;version=[string]$descriptor.distribution_version;
      sha256=$inventory.archive_sha256;bytes=$inventory.bytes;content_sha256=$inventory.content_sha256;entry_count=$inventory.entry_count}
    $receiptFields=[pscustomobject]@{from=[pscustomobject]@{version=$binding.version;sha256=$binding.sha256}}
    $legacy=Get-MIR42QualificationPredecessor -Target $target -Path $fixtureArchive -Receipt $receiptFields
    $maintenance=Get-MIR42QualificationPredecessor -Target $target -Path $fixtureArchive -Receipt $receiptFields -PublishedMaintenanceInput $binding
    Assert-MIR42CandidateBuildTest (($legacy|ConvertTo-Json -Depth 20 -Compress)-ceq($maintenance|ConvertTo-Json -Depth 20 -Compress)) ('maintenance-binding-preserves-return-contract-'+$target)
    $maintenanceEvidenceAssertions++
    foreach($field in @('target','path','version','sha256','bytes','content_sha256','entry_count')){
      $invalid=$binding|ConvertTo-Json -Depth 20|ConvertFrom-Json -Depth 20
      if($field-in@('bytes','entry_count')){$invalid.$field++}else{$invalid.$field='wrong-binding'}
      $rejected=$false
      try{Get-MIR42QualificationPredecessor -Target $target -Path $fixtureArchive -Receipt $receiptFields -PublishedMaintenanceInput $invalid|Out-Null}catch{$rejected=$_.Exception.Message-ceq('[mir42-qualification-published-maintenance-predecessor-binding] '+$target)}
      Assert-MIR42CandidateBuildTest $rejected ('maintenance-binding-refuses-'+$field+'-'+$target)
      $maintenanceEvidenceAssertions++
    }
    $independentBinding=$binding|ConvertTo-Json -Depth 20|ConvertFrom-Json -Depth 20
    $independentBinding|Add-Member -NotePropertyName github_asset_id -NotePropertyValue 1
    $independentFields=[pscustomobject]@{predecessor=$maintenance;published_maintenance_predecessor=$independentBinding}
    Assert-MIR42IndependentMaintenancePredecessor -Target $target -Path $fixtureArchive -Inventory $inventory -Qualified $independentFields -PublishedInput $independentBinding
    $maintenanceIndependentAssertions++
    foreach($case in @('path','inventory-hash','version','content','asset-id','missing-custody')){
      $invalid=$independentFields|ConvertTo-Json -Depth 20|ConvertFrom-Json -Depth 20
      $observed=$inventory|ConvertTo-Json -Depth 20|ConvertFrom-Json -Depth 20
      $observedPath=$fixtureArchive
      switch($case){
        'path'{$observedPath=$fixtureArchive+'.wrong'}
        'inventory-hash'{$observed.archive_sha256='0'*64}
        'version'{$invalid.predecessor.version='4.2.'+$target.Substring(1)+'01'}
        'content'{$invalid.predecessor.archive.content_sha256='0'*64}
        'asset-id'{$invalid.published_maintenance_predecessor.github_asset_id=2}
        'missing-custody'{$invalid.PSObject.Properties.Remove('published_maintenance_predecessor')}
      }
      $rejected=$false
      try{Assert-MIR42IndependentMaintenancePredecessor -Target $target -Path $observedPath -Inventory $observed -Qualified $invalid -PublishedInput $independentBinding}catch{$rejected=$_.Exception.Message-ceq('[mir42-independent-maintenance-predecessor-binding] '+$target)}
      Assert-MIR42CandidateBuildTest $rejected ('independent-maintenance-refuses-'+$case+'-'+$target)
      $maintenanceIndependentAssertions++
    }
    # Predecessor fields only: no passed engine execution or native log fixture.
    $executionFields=[pscustomobject]@{predecessor=[pscustomobject]@{path=$fixtureArchive;version=$binding.version;sha256=$binding.sha256};published_maintenance_predecessor=$independentBinding}
    $criterionBindings.Add([pscustomobject]@{input=$independentBinding;predecessor=$maintenance;execution=$executionFields})
    Assert-MIR42EngineEvidenceMaintenanceExecution -Target $target -Execution $executionFields -PublishedInput $independentBinding
    $maintenanceBinderAssertions++
    foreach($case in @('path','version','hash','missing-custody','asset-id','target')){
      $invalid=$executionFields|ConvertTo-Json -Depth 20|ConvertFrom-Json -Depth 20
      $expected=$independentBinding|ConvertTo-Json -Depth 20|ConvertFrom-Json -Depth 20
      $expectedCode='[mir42-engine-evidence-maintenance-predecessor-binding] '+$target
      switch($case){
        'path'{$invalid.predecessor.path=$fixtureArchive+'.wrong'}
        'version'{$invalid.predecessor.version='4.2.'+$target.Substring(1)+'01'}
        'hash'{$invalid.predecessor.sha256='0'*64}
        'missing-custody'{$invalid.PSObject.Properties.Remove('published_maintenance_predecessor')}
        'asset-id'{$invalid.published_maintenance_predecessor.github_asset_id=2;$expectedCode='[mir42-engine-evidence-maintenance-custody-binding-'+$target+']'}
        'target'{$expected.target='f999'}
      }
      $rejected=$false
      try{Assert-MIR42EngineEvidenceMaintenanceExecution -Target $target -Execution $invalid -PublishedInput $expected}catch{$rejected=$_.Exception.Message-ceq$expectedCode}
      Assert-MIR42CandidateBuildTest $rejected ('maintenance-binder-refuses-'+$case+'-'+$target)
      $maintenanceBinderAssertions++
    }
  }
  # Pure custody/predecessor field subsets only. No native status, engine-run,
  # binder, reconciliation or successful criterion evidence is fabricated.
  $criterionInputs=[pscustomobject]@{metadata_fixture_only=$true;targets=@($criterionBindings|ForEach-Object {$_.input})}
  $independentSealFields=[pscustomobject]@{published_maintenance_predecessor=$criterionInputs;targets=@($criterionBindings|ForEach-Object {[pscustomobject]@{target=$_.input.target;predecessor_sha256=$_.input.sha256;published_maintenance_predecessor=$_.input}})}
  Assert-MIR42SealIndependentMaintenanceCustody -Record $independentSealFields -PublishedInputs $criterionInputs
  $maintenanceReadinessAssertions++
  foreach($case in @('missing-target','duplicate-target','reordered-targets','top-custody')){
    $invalid=$independentSealFields|ConvertTo-Json -Depth 40|ConvertFrom-Json -Depth 40
    $expectedCode='[mir42-seal-independent-maintenance-target-set]'
    switch($case){
      'missing-target'{$invalid.targets=@($invalid.targets|Select-Object -Skip 1)}
      'duplicate-target'{$invalid.targets[8]=$invalid.targets[0]}
      'reordered-targets'{$first=$invalid.targets[0];$invalid.targets[0]=$invalid.targets[1];$invalid.targets[1]=$first}
      'top-custody'{$invalid.published_maintenance_predecessor.metadata_fixture_only=$false;$expectedCode='[mir42-seal-independent-maintenance-custody-binding]'}
    }
    $failure='';try{Assert-MIR42SealIndependentMaintenanceCustody -Record $invalid -PublishedInputs $criterionInputs}catch{$failure=$_.Exception.Message}
    Assert-MIR42CandidateBuildTest ($failure-ceq$expectedCode) ('maintenance-readiness-independent-refuses-'+$case)
    $maintenanceReadinessAssertions++
  }
  for($index=0;$index-lt9;$index++){
    foreach($case in @('hash','asset-id')){
      $invalid=$independentSealFields|ConvertTo-Json -Depth 40|ConvertFrom-Json -Depth 40
      $expectedCode='[mir42-seal-independent-maintenance-predecessor-binding]'
      if($case-ceq'hash'){$invalid.targets[$index].predecessor_sha256='0'*64}else{$invalid.targets[$index].published_maintenance_predecessor.github_asset_id=2;$expectedCode='[mir42-seal-independent-maintenance-row-custody-binding-'+$invalid.targets[$index].target+']'}
      $failure='';try{Assert-MIR42SealIndependentMaintenanceCustody -Record $invalid -PublishedInputs $criterionInputs}catch{$failure=$_.Exception.Message}
      Assert-MIR42CandidateBuildTest ($failure-ceq$expectedCode) ('maintenance-readiness-independent-refuses-'+$case+'-'+$invalid.targets[$index].target)
      $maintenanceReadinessAssertions++
    }
  }
  # Field subsets have no campaign kind/status or successful engine flags.
  $campaignFields=[pscustomobject]@{published_maintenance_predecessor=$criterionInputs;factorio_processes=0;targets=@($criterionBindings|ForEach-Object {[pscustomobject]@{target=$_.input.target;engine_execution=$_.execution}})}
  Assert-MIR42MaintenanceCampaignCustody -Record $campaignFields -PublishedInputs $criterionInputs
  $maintenanceCampaignAssertions++
  foreach($case in @('missing-target','duplicate-target','reordered-targets','top-custody')){
    $invalid=$campaignFields|ConvertTo-Json -Depth 40|ConvertFrom-Json -Depth 40
    $expectedCode='[mir42-maintenance-campaign-target-set]'
    switch($case){
      'missing-target'{$invalid.targets=@($invalid.targets|Select-Object -Skip 1)}
      'duplicate-target'{$invalid.targets[8]=$invalid.targets[0]}
      'reordered-targets'{$first=$invalid.targets[0];$invalid.targets[0]=$invalid.targets[1];$invalid.targets[1]=$first}
      'top-custody'{$invalid.published_maintenance_predecessor.metadata_fixture_only=$false;$expectedCode='[mir42-maintenance-campaign-custody-binding]'}
    }
    $failure='';try{Assert-MIR42MaintenanceCampaignCustody -Record $invalid -PublishedInputs $criterionInputs}catch{$failure=$_.Exception.Message}
    Assert-MIR42CandidateBuildTest ($failure-ceq$expectedCode) ('maintenance-campaign-refuses-'+$case)
    $maintenanceCampaignAssertions++
  }
  for($index=0;$index-lt9;$index++){
    foreach($case in @('path','version','hash','asset-id')){
      $invalid=$campaignFields|ConvertTo-Json -Depth 40|ConvertFrom-Json -Depth 40
      $execution=$invalid.targets[$index].engine_execution
      $expectedCode='[mir42-engine-evidence-maintenance-predecessor-binding] '+$invalid.targets[$index].target
      switch($case){
        'path'{$execution.predecessor.path+='-other'}
        'version'{$execution.predecessor.version=$execution.predecessor.version.Substring(0,$execution.predecessor.version.Length-2)+'02'}
        'hash'{$execution.predecessor.sha256='0'*64}
        'asset-id'{$execution.published_maintenance_predecessor.github_asset_id=2;$expectedCode='[mir42-engine-evidence-maintenance-custody-binding-'+$invalid.targets[$index].target+']'}
      }
      $failure='';try{Assert-MIR42MaintenanceCampaignCustody -Record $invalid -PublishedInputs $criterionInputs}catch{$failure=$_.Exception.Message}
      Assert-MIR42CandidateBuildTest ($failure-ceq$expectedCode) ('maintenance-campaign-refuses-'+$case+'-'+$invalid.targets[$index].target)
      $maintenanceCampaignAssertions++
    }
  }
  $unexecutedRun=[pscustomobject]@{record=[pscustomobject]@{factorio_processes=0;targets=$campaignFields.targets}}
  $provisional=[pscustomobject]@{record=$campaignFields}
  $failure='';try{Assert-MIR42RealEngineCampaignExecution -RepoRoot $repo -Campaign $provisional -Candidate $binderCandidate -EngineRun $unexecutedRun -PublishedMaintenanceInputs $criterionInputs}catch{$failure=$_.Exception.Message}
  Assert-MIR42CandidateBuildTest ($failure-ceq'[mir42-seal-real-engine-target-shape]') 'maintenance-campaign-prewrite-guard-refuses-unexecuted-field-subset'
  $maintenanceCampaignAssertions++
  $unexecutedRun.record.factorio_processes=1
  $failure='';try{Assert-MIR42RealEngineCampaignExecution -RepoRoot $repo -Campaign $provisional -Candidate $binderCandidate -EngineRun $unexecutedRun -PublishedMaintenanceInputs $criterionInputs}catch{$failure=$_.Exception.Message}
  Assert-MIR42CandidateBuildTest ($failure-ceq'[mir42-seal-real-engine-process-count-binding]') 'maintenance-campaign-refuses-process-count-rebinding'
  $maintenanceCampaignAssertions++
  foreach($criterion in @('fresh-exact-loads','target-omissions')){
    $contract=Get-MIR42CriterionObservationContract -Criterion $criterion -PublishedMaintenance
    $expectedKind=if($criterion-ceq'fresh-exact-loads'){'MIR42NineTargetMaintenanceRealEngineEvidenceBinderV1'}else{'MIR42NineTargetMaintenanceEvidenceReconciliationV1'}
    Assert-MIR42CandidateBuildTest ($contract.kind-ceq$expectedKind) ('maintenance-criterion-contract-'+$criterion)
    $maintenanceCriterionAssertions++
    $fieldRows=@(foreach($bindingFields in $criterionBindings){
      if($criterion-ceq'fresh-exact-loads'){
        [pscustomobject]@{target=$bindingFields.input.target;engine_execution=$bindingFields.execution}
      }else{
        [pscustomobject]@{target=$bindingFields.input.target;predecessor=$bindingFields.predecessor;published_maintenance_predecessor=$bindingFields.input}
      }
    })
    $fields=[pscustomobject]@{published_maintenance_predecessor=$criterionInputs;targets=$fieldRows}
    Assert-MIR42MaintenanceCriterionObservation -Record $fields -Criterion $criterion -PublishedInputs $criterionInputs
    $maintenanceCriterionAssertions++
    foreach($case in @('missing-top-custody','changed-top-custody','reordered-targets','partial-targets')){
      $invalid=$fields|ConvertTo-Json -Depth 40|ConvertFrom-Json -Depth 40
      switch($case){
        'missing-top-custody'{$invalid.PSObject.Properties.Remove('published_maintenance_predecessor')}
        'changed-top-custody'{$invalid.published_maintenance_predecessor.metadata_fixture_only=$false}
        'reordered-targets'{$invalid.targets=@($invalid.targets[1],$invalid.targets[0])+@($invalid.targets|Select-Object -Skip 2)}
        'partial-targets'{$invalid.targets=@($invalid.targets|Select-Object -First 8)}
      }
      $rejected=$false
      try{Assert-MIR42MaintenanceCriterionObservation -Record $invalid -Criterion $criterion -PublishedInputs $criterionInputs}catch{$rejected=$_.Exception.Message-ceq'[mir42-maintenance-criterion-custody-binding]'}
      Assert-MIR42CandidateBuildTest $rejected ('maintenance-criterion-refuses-'+$case+'-'+$criterion)
      $maintenanceCriterionAssertions++
    }
    for($i=0;$i-lt9;$i++){
      foreach($case in @('asset-id','hash','version','path','missing-custody')){
        $invalid=$fields|ConvertTo-Json -Depth 40|ConvertFrom-Json -Depth 40
        $row=$invalid.targets[$i];$target=[string]$row.target
        $expectedCode='[mir42-maintenance-criterion-predecessor-binding] '+$target
        if($criterion-ceq'fresh-exact-loads'){
          switch($case){
            'asset-id'{$row.engine_execution.published_maintenance_predecessor.github_asset_id++}
            'hash'{$row.engine_execution.predecessor.sha256='0'*64}
            'version'{$row.engine_execution.predecessor.version='4.2.21001'}
            'path'{$row.engine_execution.predecessor.path+='-changed'}
            'missing-custody'{$row.engine_execution.PSObject.Properties.Remove('published_maintenance_predecessor')}
          }
        }else{
          switch($case){
            'asset-id'{$row.published_maintenance_predecessor.github_asset_id++;$expectedCode='[mir42-maintenance-criterion-row-custody-binding] '+$target}
            'hash'{$row.predecessor.archive.sha256='0'*64}
            'version'{$row.predecessor.version='4.2.21001'}
            'path'{$row.predecessor.archive.path+='-changed'}
            'missing-custody'{$row.PSObject.Properties.Remove('published_maintenance_predecessor');$expectedCode='[mir42-maintenance-criterion-row-custody-binding] '+$target}
          }
        }
        $rejected=$false
        try{Assert-MIR42MaintenanceCriterionObservation -Record $invalid -Criterion $criterion -PublishedInputs $criterionInputs}catch{$rejected=$_.Exception.Message-ceq$expectedCode}
        Assert-MIR42CandidateBuildTest $rejected ('maintenance-criterion-refuses-'+$case+'-'+$criterion+'-'+$target)
        $maintenanceCriterionAssertions++
      }
    }
  }
  foreach($criterion in @($script:MIR42ReleaseAcceptanceCriteria|Where-Object {$_-cnotin@('fresh-exact-loads','target-omissions')})){
    $rejected=$false
    try{Get-MIR42CriterionObservationContract -Criterion $criterion -PublishedMaintenance|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-maintenance-criterion-input-scope]'}
    Assert-MIR42CandidateBuildTest $rejected ('maintenance-criterion-refuses-unrelated-option-'+$criterion)
    $maintenanceCriterionAssertions++
  }
  $legacyCriterion=Get-MIR42CriterionObservationContract -Criterion 'fresh-exact-loads'
  Assert-MIR42CandidateBuildTest ($legacyCriterion.kind-ceq'MIR42NineTargetRealEngineEvidenceBinderV1') 'maintenance-criterion-preserves-default-contract'
  $maintenanceCriterionAssertions++
  $rejected=$false
  try{
    & (Join-Path $repo 'tools/commands/release/Invoke-MIR42NineTargetEvidenceReconciliation.ps1') -Mode Criterion -RepoRoot $repo `
      -CandidateManifestPath (Join-Path $identityRoot 'not-read.json') -Criterion 'performance-telemetry' -ObservationPaths @('not-read.json') `
      -ObservedTargets @('f210') -Claim 'source flag-forwarding control' -KnownLimitations 'not native' `
      -OutputPath (Join-Path $identityRoot 'must-not-create.json') -PublishedMaintenancePredecessorManifestPath 'not-read.json'|Out-Null
  }catch{$rejected=$_.Exception.Message-ceq'[mir42-maintenance-criterion-input-scope]'}
  Assert-MIR42CandidateBuildTest ($rejected-and-not(Test-Path -LiteralPath (Join-Path $identityRoot 'must-not-create.json'))) 'maintenance-criterion-cli-forwards-and-refuses-out-of-scope-option'
  $maintenanceCriterionAssertions++
  if ($IdentityContractsOnly) {
    [pscustomobject][ordered]@{ status='MIR-4.2.1-CANDIDATE-IDENTITY-CONTRACTS-PASSED'; target_identities=9; metadata_idempotence_checks=9; invalid_version_refusals=3; invalid_manifest_refusals=16; engine_envelope_assertions=$engineEnvelopeAssertions; engine_destination_assertions=$engineDestinationAssertions; maintenance_custody_assertions=$maintenanceCustodyAssertions; maintenance_evidence_assertions=$maintenanceEvidenceAssertions; maintenance_independent_assertions=$maintenanceIndependentAssertions; seal_candidate_contract_assertions=$sealCandidateContractAssertions; maintenance_binder_assertions=$maintenanceBinderAssertions; maintenance_criterion_assertions=$maintenanceCriterionAssertions; maintenance_campaign_assertions=$maintenanceCampaignAssertions; maintenance_readiness_assertions=$maintenanceReadinessAssertions; maintenance_seal_assertions=$maintenanceSealAssertions; controlled_predecessor_archives=9; engine_runs=0; actual_candidate_zip_builds=0 }
    return
  }

  $complete = New-MIR42FourTargetCandidate -RepoRoot $repo -FinalSourceCommit $commit -BuildId 'STATIC' -OutputRoot $root -MinimumFreeMemoryBytes 1 -MinimumFreeWorkBytes 1
  Assert-MIR42CandidateBuildTest ([bool]$complete.build_complete) 'complete-build-status'
  Assert-MIR42CandidateBuildTest ($complete.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV1') 'complete-build-manifest-kind'
  Assert-MIR42CandidateBuildTest ($complete.status -ceq 'private-deterministic-four-target-candidate-built-unqualified') 'complete-build-private-status'
  Assert-MIR42CandidateBuildTest (@($complete.targets).Count -eq 4) 'complete-build-target-count'
  Assert-MIR42CandidateBuildTest ($script:mir42CandidateStubCalls.Count -eq 8) 'complete-build-serial-two-per-target'
  Assert-MIR42CandidateBuildTest (Test-MIR4BootstrapRecordHash -Record $complete) 'complete-build-manifest-hash'
  Assert-MIR42CandidateBuildTest (-not (($complete | ConvertTo-Json -Depth 100) -match '"engine"')) 'manifest-engine-neutral'

  foreach ($target in @('f210', 'f200', 'f110', 'f100')) {
    $rowPath = Join-Path $root "target-rows/$target.json"
    $row = Get-Content -Raw -LiteralPath $rowPath | ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR42CandidateBuildTest (Test-MIR4BootstrapRecordHash -Record $row) "row-hash-$target"
    Assert-MIR42CandidateBuildTest ([bool]$row.deterministic_archive_bytes -and [bool]$row.package_excluded_surface) "row-determinism-surface-$target"
    $asset = Join-Path $root ([string]$row.asset.path)
    Assert-MIR42CandidateBuildTest ((Get-MIR4Sha256File -Path $asset) -ceq [string]$row.asset.sha256) "row-custody-$target"
  }

  $script:mir42CandidateStubCalls.Clear()
  $script:mir42CandidateStubFailureTarget = 'f200'
  $partial = New-MIR42FourTargetCandidate -RepoRoot $repo -FinalSourceCommit $commit -BuildId 'PARTIAL' -OutputRoot $partialRoot -MinimumFreeMemoryBytes 1 -MinimumFreeWorkBytes 1
  Assert-MIR42CandidateBuildTest (-not [bool]$partial.build_complete) 'partial-build-status'
  Assert-MIR42CandidateBuildTest ($partial.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV1') 'partial-build-manifest-kind'
  Assert-MIR42CandidateBuildTest (@($partial.targets).Count -eq 1 -and [string]$partial.targets[0].target -ceq 'f210') 'partial-build-keeps-prior-target-row'
  Assert-MIR42CandidateBuildTest (@($partial.failures).Count -eq 1 -and [string]$partial.failures[0].target -ceq 'f200') 'partial-build-records-later-failure'
  Assert-MIR42CandidateBuildTest (Test-Path -LiteralPath (Join-Path $partialRoot 'target-rows/f210.json') -PathType Leaf) 'partial-build-persists-prior-row'
  Assert-MIR42CandidateBuildTest (Test-MIR4BootstrapRecordHash -Record $partial) 'partial-build-manifest-hash'

  $historicalScript = Join-Path $repo 'tools/commands/release/New-MIR42HistoricalPlaytestCandidate.ps1'
  $historicalManifest = & $historicalScript -RepoRoot $repo -Target f017 -CandidateId 'STATIC' -Repetitions 2 -OutputRoot $historicalRoot -Check
  $historicalDescriptor = @($nineDescriptors | Where-Object { [string]$_.target -ceq 'f017' })
  Assert-MIR42CandidateBuildTest ($historicalDescriptor.Count -eq 1) 'historical-descriptor-f017'
  $historicalRow = Read-MIR42HistoricalCandidateConstructionRow -RepoRoot $repo -Descriptor $historicalDescriptor[0] -ManifestPath (Join-Path $historicalRoot 'manifests/f017.json')
  Assert-MIR42CandidateBuildTest ([string]$historicalManifest.candidate_row.kind -ceq 'MIR42HistoricalCandidateRowV1') 'historical-manifest-row-kind'
  Assert-MIR42CandidateBuildTest ([string]$historicalRow.target -ceq 'f017' -and [bool]$historicalRow.deterministic_archive_bytes -and [bool]$historicalRow.package_excluded_surface) 'historical-row-construction-shape'
  Assert-MIR42CandidateBuildTest (-not [bool]$historicalRow.public_output_authorized -and -not [bool]$historicalRow.publication_authorized) 'historical-row-private-boundary'

  $script:mir42CandidateStubCalls.Clear()
  $script:mir42CandidateStubFailureTarget = ''
  $nine = New-MIR42FourTargetCandidate -RepoRoot $repo -FinalSourceCommit $commit -BuildId 'NINE' -SelectedTargets @('f210', 'f200', 'f110', 'f100', 'f017', 'f016', 'f015', 'f014', 'f013') -OutputRoot $nineRoot -MinimumFreeMemoryBytes 1 -MinimumFreeWorkBytes 1
  Assert-MIR42CandidateBuildTest ([bool]$nine.build_complete) 'nine-build-status'
  Assert-MIR42CandidateBuildTest ($nine.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV1') 'nine-build-manifest-kind'
  Assert-MIR42CandidateBuildTest ($nine.status -ceq 'private-deterministic-nine-target-candidate-built-unqualified') 'nine-build-private-status'
  Assert-MIR42CandidateBuildTest ((@($nine.targets | ForEach-Object { [string]$_.target }) -join '|') -ceq 'f210|f200|f110|f100|f017|f016|f015|f014|f013') 'nine-build-target-order'
  # The historical command imports its own materializer in its script scope.
  # This stub observes only the four modern targets; historical A/B equality
  # is checked through their construction rows below.
  Assert-MIR42CandidateBuildTest ($script:mir42CandidateStubCalls.Count -eq 8) 'nine-build-two-modern-materializations-per-target'
  foreach ($target in @('f017', 'f016', 'f015', 'f014', 'f013')) {
    $rowPath = Join-Path $nineRoot "target-rows/$target.json"
    $row = Get-Content -Raw -LiteralPath $rowPath | ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR42CandidateBuildTest (Test-MIR4BootstrapRecordHash -Record $row) "nine-historical-row-hash-$target"
    Assert-MIR42CandidateBuildTest ([string]$row.materializer -ceq 'historical-playtest-target') "nine-historical-row-materializer-$target"
    Assert-MIR42CandidateBuildTest ([string]$row.target_record.path -ceq "targets/historical/$target/target.json" -and -not [bool]$row.public_output_authorized -and -not [bool]$row.publication_authorized) "nine-historical-row-binding-$target"
    Assert-MIR42CandidateBuildTest ([string]$row.engine.sha256 -match '^[A-Fa-f0-9]{64}$' -and [string]$row.predecessor.sha256 -match '^[A-Fa-f0-9]{64}$') "nine-historical-row-engine-predecessor-$target"
    Assert-MIR42CandidateBuildTest ([string]$row.historical_materializer_manifest_sha256 -match '^[A-Fa-f0-9]{64}$') "nine-historical-row-manifest-receipt-$target"
    $asset = Join-Path $nineRoot ([string]$row.asset.path)
    Assert-MIR42CandidateBuildTest ((Get-MIR4Sha256File -Path $asset) -ceq [string]$row.asset.sha256) "nine-historical-row-custody-$target"
  }

  $script:mir42CandidateStubCalls.Clear()
  $patch = New-MIR42FourTargetCandidate -RepoRoot $repo -FinalSourceCommit $commit -BuildId 'PATCH' -SourceVersion '4.2.1' -OutputRoot $patchRoot -MinimumFreeMemoryBytes 1 -MinimumFreeWorkBytes 1
  Assert-MIR42CandidateBuildTest ([bool]$patch.build_complete -and $patch.schema -eq 2 -and $patch.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV2') 'patch-nine-build-v2-complete'
  Assert-MIR42CandidateBuildTest (($patch.targets.distribution_version -join '|') -ceq ($patchVersions -join '|')) 'patch-nine-build-actual-row-identities'
  Assert-MIR42CandidateBuildTest ($script:mir42CandidateStubCalls.Count -eq 8) 'patch-nine-build-two-modern-materializations-per-target'
  Assert-MIR42CandidateBuildTest (Test-MIR4BootstrapRecordHash -Record $patch) 'patch-nine-build-manifest-hash'
  # Portable input-contract control. CI has no delivered terminal ZIPs. Only
  # their inventory lookup uses seal fixtures; all candidate ZIPs are rehashed.
  # This does not execute predecessor custody, upgrades or native qualification.
  $originalArchiveInventory = (Get-Item Function:Get-MIR4ArchiveInventory).ScriptBlock
  $terminalInventoryFixtures = @{}
  foreach ($target in @('f017','f016','f015','f014','f013')) {
    $record = Get-Content -Raw -LiteralPath (Join-Path $repo "targets/historical/$target/target.json") | ConvertFrom-Json -Depth 100
    $seal = Get-Content -Raw -LiteralPath (Join-Path $repo ('.mir/releases/terminal/seals/' + $record.predecessor.version + '.json')) | ConvertFrom-Json -Depth 100
    $terminalInventoryFixtures[[IO.Path]::GetFullPath((Join-Path $repo $record.predecessor.archive))] = [pscustomobject]@{
      archive_sha256=$seal.archive_sha256;bytes=$seal.bytes;content_sha256=$seal.content_sha256;entry_count=$seal.entries
    }
  }
  try {
    Set-Item Function:Get-MIR4ArchiveInventory -Value {
      param([Parameter(Mandatory)][string]$Path)
      $fullPath = [IO.Path]::GetFullPath($Path)
      if ($terminalInventoryFixtures.ContainsKey($fullPath)) { return $terminalInventoryFixtures[$fullPath] }
      return & $originalArchiveInventory -Path $Path
    }
    $patchInputs = @(Get-MIR42QualificationCandidateRows -RepoRoot $repo -CandidateManifestPath (Join-Path $patchRoot 'candidate-manifest.json'))
    $legacyInputs = @(Get-MIR42QualificationCandidateRows -RepoRoot $repo -CandidateManifestPath (Join-Path $nineRoot 'candidate-manifest.json'))
    $patchSealInputs=Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath (Join-Path $patchRoot 'candidate-manifest.json')
    $legacySealInputs=Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath (Join-Path $nineRoot 'candidate-manifest.json')
    Assert-MIR42CandidateBuildTest ($patchSealInputs.targets.Count-eq9-and$legacySealInputs.targets.Count-eq9-and
      ($patchSealInputs.targets.distribution_version-join'|')-ceq($patchVersions-join'|')) 'seal-input-reader-binds-nine-constructed-v1-and-v2-archives-without-sealing'
    Assert-MIR42CandidateBuildTest ($patchInputs.Count -eq 9 -and @($patchInputs | Where-Object { $_.identity.source_version -cne '4.2.1' }).Count -eq 0) 'patch-nine-input-reader-uses-current-source-version'
    Assert-MIR42CandidateBuildTest ($legacyInputs.Count -eq 9 -and @($legacyInputs | Where-Object { $_.identity.source_version -cne '4.2.0' }).Count -eq 0) 'legacy-nine-input-reader-default-preserved'
    $tamperedRowPath = Join-Path $patchRoot 'target-rows/f210.json'
    $originalRowBytes = [IO.File]::ReadAllBytes($tamperedRowPath)
    foreach ($tamper in @('source-version','row-schema')) {
      $badRow = [Text.UTF8Encoding]::new($false).GetString($originalRowBytes) | ConvertFrom-Json -Depth 100
      if ($tamper -ceq 'source-version') { $badRow.source_version='4.2.0' } else { $badRow.schema=2 }
      Write-MIR4BootstrapRecord -Record $badRow -Path $tamperedRowPath | Out-Null
      $rejected = $false
      try { Get-MIR42QualificationCandidateRows -RepoRoot $repo -CandidateManifestPath (Join-Path $patchRoot 'candidate-manifest.json') | Out-Null } catch { $rejected=$_.Exception.Message -match 'mir42-qualification-target-row-binding' }
      Assert-MIR42CandidateBuildTest $rejected "patch-input-reader-refuses-self-hashed-$tamper"
      $rejected=$false
      $expectedSealRefusal=if($tamper-ceq'source-version'){'[mir42-seal-candidate-target-row-drift] f210'}else{'[mir42-seal-candidate-target-row-schema] f210'}
      try{Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath (Join-Path $patchRoot 'candidate-manifest.json')|Out-Null}catch{$rejected=$_.Exception.Message-ceq$expectedSealRefusal}
      Assert-MIR42CandidateBuildTest $rejected "seal-input-reader-refuses-self-hashed-$tamper"
      [IO.File]::WriteAllBytes($tamperedRowPath, $originalRowBytes)
    }
  } finally {
    Set-Item Function:Get-MIR4ArchiveInventory -Value $originalArchiveInventory
  }
  Test-MIR42IndependentConstructionInput -CandidateRoot $nineRoot -Inputs $legacyInputs
  Test-MIR42IndependentConstructionInput -CandidateRoot $patchRoot -Inputs $patchInputs
  foreach ($target in @('f017','f016','f015','f014','f013')) {
    $row = Get-Content -Raw -LiteralPath (Join-Path $patchRoot "target-rows/$target.json") | ConvertFrom-Json -Depth 100
    Assert-MIR42CandidateBuildTest ([string]$row.distribution_version -ceq "4.2.$($target.Substring(1))01" -and [bool]$row.deterministic_archive_bytes -and -not [bool]$row.publication_authorized) "patch-historical-row-identity-and-private-boundary-$target"
    $recordPath = Join-Path $repo ([string]$row.target_record.path)
    $frozenRecord = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json -Depth 100
    Assert-MIR42CandidateBuildTest ((Test-MIR4BootstrapRecordHash -Record $frozenRecord) -and [string]$frozenRecord.record_sha256 -ceq [string]$row.target_record.sha256 -and (Get-FileHash -Algorithm SHA256 -LiteralPath $recordPath).Hash -ceq $historicalRecordHashes[$target]) "patch-historical-baseline-record-preserved-$target"
  }

  [pscustomobject][ordered]@{
    status = 'MIR-4.2-NINE-TARGET-CONSTRUCTION-ADAPTER-STATIC-PASSED'
    materializer_calls_complete = 8
    partial_successful_targets = @($partial.targets).Count
    historical_target_rows = 5
    patch_target_rows = 9
    predecessor_inventory_control = 'terminal-seal-fixture-only'
    independent_input_controls = 'v1-v2-first-row-and-required-predecessor-refusals-engine-lookup-fixture-only'
    engine_runs = 0
  }
} finally {
  foreach ($path in @($root, $partialRoot, $historicalRoot, $nineRoot, $identityRoot, $patchRoot)) {
    if (Test-Path -LiteralPath $path) {
      $resolvedPath = (Resolve-Path -LiteralPath $path).Path
      $null = Assert-MIR4DescendantPath -Root (Join-Path $repo 'build') -Path $resolvedPath
      $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $resolvedPath
      Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    }
  }
}
