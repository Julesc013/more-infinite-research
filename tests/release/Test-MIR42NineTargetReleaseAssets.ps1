# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [ValidateSet('4.2.0','4.2.1','4.2.2')][string]$SourceVersion = '4.2.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$module = Join-Path $repo 'tools/mir/application/release/readiness/MIR42ReleaseAssets.ps1'
if (-not (Test-Path -LiteralPath $module -PathType Leaf)) { throw "[mir42-release-assets-test-module-missing] $module" }
. $module
. (Join-Path $repo 'tests/support/MIR42StartupCollectorControls.ps1')
. (Join-Path $repo 'tests/support/MIR421ReleaseAssetControls.ps1')
. (Join-Path $repo 'tests/support/MIR422ReleaseUpgradeControls.ps1')
$maintenance=$SourceVersion -cin @('4.2.1','4.2.2')
$releaseTag='v' + $SourceVersion
$patchSuffix=([version]$SourceVersion).Build.ToString('D2')
$script:mir42ReleaseAssetControlAssertions=0

function Assert-MIR42ReleaseAssetsTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir42-release-assets-test-$Code]" }
  $script:mir42ReleaseAssetControlAssertions++
}

$publicReadback = Get-Command Get-MIR42NineTargetPublicDownloadedReleaseReadback -CommandType Function -ErrorAction Stop
Assert-MIR42ReleaseAssetsTest -Condition ($publicReadback.Parameters.ContainsKey('PublicReleaseObserver') -eq $false) -Code 'public-readback-observer-not-caller-injectable'
$wrapper = Join-Path $repo 'tools/commands/release/Invoke-MIR42NineTargetReleaseAssets.ps1'
if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) { throw "[mir42-release-assets-test-wrapper-missing] $wrapper" }
$wrapperText = Get-Content -Raw -LiteralPath $wrapper
Assert-MIR42ReleaseAssetsTest -Condition ($wrapperText -match 'Get-MIR42NineTargetProtectedMainPromotionPlan' -and $wrapperText -match '-PromotionPlan \$promotion' -and $wrapperText -notmatch '\$PublicReleaseObserver') -Code 'wrapper-reconstructs-promotion-and-hides-observer'

function New-MIR42ReleaseAssetsFixtureZip {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Version,[Parameter(Mandatory)][string]$Line)

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($row in @(
      [pscustomobject]@{path="$Root/info.json";text=((@{name='more-infinite-research';version=$Version;factorio_version=$Line}|ConvertTo-Json -Compress) + "`n")},
      [pscustomobject]@{path="$Root/data.lua";text=("-- structural fixture for " + $Version + "`n")}
    )) {
      $entry = $archive.CreateEntry([string]$row.path)
      $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
      try { $writer.Write([string]$row.text) } finally { $writer.Dispose() }
    }
  } finally { $archive.Dispose() }
}

function Copy-MIR42ReleaseAssetsFixtureTree {
  param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force)) {
    Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
  }
}

$root = Join-Path $repo ('build/tmp/mir42-release-assets-' + [guid]::NewGuid().ToString('N'))
$candidateReader = (Get-Item Function:Get-MIR42ExactFourTargetCandidate).ScriptBlock
$previousDefaults=$PSDefaultParameterValues.Clone()
try {
  $collectorControls=Invoke-MIR42StartupCollectorControls -RepoRoot $repo -Root (Join-Path $root 'collector-controls')
  $candidateRoot = Join-Path $root 'candidate'
  $assetRoot = Join-Path $root 'release-assets'
  New-Item -ItemType Directory -Force -Path $candidateRoot,$assetRoot | Out-Null
  $sourceCommit = (& git -C $repo rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0) { throw '[mir42-release-assets-test-source-commit]' }
  $source = [pscustomobject][ordered]@{commit=$sourceCommit;tree=('b' * 40);package_source_sha256=('C' * 64)}
  $targets = [Collections.Generic.List[object]]::new()
  $lineByTarget = [ordered]@{f210='2.1';f200='2.0';f110='1.1';f100='1.0';f017='0.17';f016='0.16';f015='0.15';f014='0.14';f013='0.13'}
  foreach ($target in $script:MIR42ReleaseAssetTargets) {
    $version = '4.2.' + $target.Substring(1) + $patchSuffix
    $name = 'more-infinite-research_' + $version + '.zip'
    $candidatePath = Join-Path $candidateRoot (Join-Path $target $name)
    New-MIR42ReleaseAssetsFixtureZip -Path $candidatePath -Root ('more-infinite-research_' + $version) -Version $version -Line $lineByTarget[$target]
    $archive = Get-MIR4ArchiveInventory -Path $candidatePath
    $targets.Add([pscustomobject][ordered]@{
      target=$target;distribution_version=$version;archive_sha256=[string]$archive.archive_sha256;content_sha256=[string]$archive.content_sha256;entry_count=[int]$archive.entry_count;archive_path=$candidatePath
    })
    $releasePackage = Join-Path $assetRoot (Join-Path ('assets/' + $target) $name)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $releasePackage) | Out-Null
    Copy-Item -LiteralPath $candidatePath -Destination $releasePackage
  }
  $expectedChecksums = (@($targets | ForEach-Object { "$([string]$_.archive_sha256)  $([IO.Path]::GetFileName([string]$_.archive_path))" }) -join "`n") + "`n"
  [IO.File]::WriteAllText((Join-Path $assetRoot 'SHA256SUMS.txt'), $expectedChecksums, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllBytes((Join-Path $assetRoot 'SHA256SUMS.txt.sig'), [byte[]](7,42,99,18))
  [IO.File]::WriteAllText((Join-Path $assetRoot 'release-notes.md'), "# Structural nine-target fixture`n", [Text.UTF8Encoding]::new($false))
  $collectorPath = Join-Path $assetRoot $script:MIR42SupportCollectorAssetName
  $collector = New-MIR42SupportCollectorBundle -RepoRoot $repo -SourceCommit $sourceCommit -OutputPath $collectorPath
  $secondCollectorPath = Join-Path $root ('second-bundle/' + $script:MIR42SupportCollectorAssetName)
  $secondCollector = & (Join-Path $repo 'tools/commands/release/New-MIR42SupportCollectorBundle.ps1') -RepoRoot $repo -SourceCommit $sourceCommit -OutputPath $secondCollectorPath | ConvertFrom-Json -Depth 10
  Assert-MIR42ReleaseAssetsTest -Condition ([string]$collector.sha256 -ceq [string]$secondCollector.sha256) -Code 'collector-bundle-deterministic'
  $overwriteRejected = $false
  try { New-MIR42SupportCollectorBundle -RepoRoot $repo -SourceCommit $sourceCommit -OutputPath $collectorPath | Out-Null }
  catch { $overwriteRejected = $_.Exception.Message -match '^\[mir42-support-collector-output-exists\]' }
  Assert-MIR42ReleaseAssetsTest -Condition $overwriteRejected -Code 'collector-bundle-frozen-output'
  $mistypedOutput = Join-Path $root ('mistyped-source/' + $script:MIR42SupportCollectorAssetName)
  $mistypedRejected = $false
  try { New-MIR42SupportCollectorBundle -RepoRoot $repo -SourceCommit ('0' * 40) -OutputPath $mistypedOutput | Out-Null }
  catch { $mistypedRejected = $_.Exception.Message -match '^\[mir42-support-collector-source-blob\]' }
  Assert-MIR42ReleaseAssetsTest -Condition ($mistypedRejected -and -not (Test-Path -LiteralPath $mistypedOutput)) -Code 'collector-bundle-bad-source-leaves-no-output'
  $tamperedCollectorPath = Join-Path $root ('tampered-bundle/' + $script:MIR42SupportCollectorAssetName)
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $tamperedCollectorPath))
  $tamperedStream = [IO.File]::Create($tamperedCollectorPath)
  try {
    $tamperedArchive = [IO.Compression.ZipArchive]::new($tamperedStream, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
      foreach ($name in $script:MIR42SupportCollectorScripts) {
        $bytes = Read-MIR42SupportCollectorSourceBlob -RepoRoot $repo -SourceCommit $sourceCommit -Name $name
        if ($name -ceq 'Collect-MIRPlayerReport.ps1') { $bytes = [byte[]]($bytes + [Text.Encoding]::UTF8.GetBytes("`n# tampered`n")) }
        $entryStream = $tamperedArchive.CreateEntry($name).Open()
        try { $entryStream.Write($bytes, 0, $bytes.Length) } finally { $entryStream.Dispose() }
      }
    } finally { $tamperedArchive.Dispose() }
  } finally { $tamperedStream.Dispose() }
  $tamperedRejected = $false
  try { Assert-MIR42SupportCollectorBundle -RepoRoot $repo -SourceCommit $sourceCommit -Path $tamperedCollectorPath | Out-Null }
  catch { $tamperedRejected = $_.Exception.Message -match '^\[mir42-support-collector-bundle-source-drift\]' }
  Assert-MIR42ReleaseAssetsTest -Condition $tamperedRejected -Code 'collector-bundle-source-drift-rejected'
  foreach ($target in $script:MIR42ReleaseAssetTargets) {
    $path = Join-Path $assetRoot ('upload-text/' + $target + '.md')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path, ("Structural upload copy for " + $target + "`n"), [Text.UTF8Encoding]::new($false))
  }

  $script:mir42ReleaseAssetsFixtureCandidate = [pscustomobject][ordered]@{
    identity=[pscustomobject][ordered]@{sha256=('D' * 64);record=[pscustomobject][ordered]@{record_sha256=('E' * 64)}}
    source=$source;scope='nine-target';targets=@($targets)
  }
  if ($maintenance) {
    . (Join-Path $repo 'tools/mir/application/release/readiness/MIR42CandidateBuild.ps1')
    $preflight=[pscustomobject]@{
      source=[ordered]@{commit=$source.commit;tree=$source.tree};package_authority_sha256=('A' * 64);package_source_sha256=$source.package_source_sha256
      target_authority=@(foreach ($target in $targets) { [ordered]@{target=$target.target;target_id=('factorio-' + $lineByTarget[$target.target]);source_version=$SourceVersion;distribution_version=$target.distribution_version} })
      resource_admission=[ordered]@{admitted=$true;minimum_free_memory_bytes=1;minimum_free_work_bytes=1}
    }
    $rows=@(foreach ($target in $targets) { [pscustomobject]@{target=$target.target;distribution_version=$target.distribution_version;asset=[ordered]@{path=('assets/' + $target.target + '/' + [IO.Path]::GetFileName($target.archive_path));bytes=1;sha256=$target.archive_sha256};content_sha256=$target.content_sha256;entry_count=$target.entry_count} })
    $manifestRoot=Join-Path $root 'schema-manifest'
    New-Item -ItemType Directory -Path $manifestRoot | Out-Null
    $script:mir42ReleaseAssetsFixtureCandidate.identity.record=Write-MIR42FourTargetManifest -OutputRoot $manifestRoot -Preflight $preflight -Rows $rows -Failures @()
    $custody=New-MIR421ReleaseAssetCustodyFixture -RepoRoot $repo -CandidateSourceVersion $SourceVersion
  }
  $sealRecord = [pscustomobject][ordered]@{
    schema=1;kind='MIR42NineTargetTechnicalSealV1';status='MIR-4.2-NINE-TARGET-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR'
    source=$source;candidate_manifest=[ordered]@{sha256=('D' * 64);record_sha256=('E' * 64)};targets=@($targets)
    protected_main_promotion_authorized=$false;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''
  }
  $sealPath = Join-Path $root 'technical-seal.json'
  if ($maintenance) {
    $sealRecord.kind='MIR42NineTargetMaintenanceTechnicalSealV1'
    $sealRecord.status="MIR-$SourceVersion-NINE-TARGET-MAINTENANCE-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR"
    $sealRecord.candidate_manifest.record_sha256=$script:mir42ReleaseAssetsFixtureCandidate.identity.record.record_sha256
    $sealRecord | Add-Member -NotePropertyName published_maintenance_predecessor -NotePropertyValue $custody
  }
  Write-MIR4BootstrapRecord -Record $sealRecord -Path $sealPath | Out-Null
  $sealIdentity = Read-MIR42SealRecord -Path $sealPath -Code 'mir42-release-assets-test-seal'
  $promotionPlan = [pscustomobject][ordered]@{
    schema=1;kind='MIR42NineTargetProtectedMainPromotionPlanV1';status='MIR-4.2-NINE-TARGET-PROTECTED-MAIN-PROMOTION-PLAN-ONLY';scope='nine-target';source=$source
    technical_seal=[ordered]@{sha256=[string]$sealIdentity.sha256;record_sha256=[string]$sealIdentity.record.record_sha256}
    candidate_manifest=[ordered]@{sha256=('D' * 64);record_sha256=('E' * 64)};target_assets=@($targets | ForEach-Object { [ordered]@{target=[string]$_.target;distribution_version=[string]$_.distribution_version;archive_sha256=[string]$_.archive_sha256;content_sha256=[string]$_.content_sha256;entry_count=[int]$_.entry_count} })
    main_before=('f' * 40);remote_mutation_performed=$false;protected_main_promotion_authorized=$false;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false
  }
  $fixturePackages = @(
    foreach ($target in $targets) {
      $path = 'assets/' + [string]$target.target + '/' + [IO.Path]::GetFileName([string]$target.archive_path)
      $item = Get-Item -LiteralPath (Join-Path $assetRoot $path)
      [pscustomobject][ordered]@{target=[string]$target.target;distribution_version=[string]$target.distribution_version;path=$path;public_name=[IO.Path]::GetFileName([string]$target.archive_path);sha256=[string]$target.archive_sha256;bytes=[int64]$item.Length;content_sha256=[string]$target.content_sha256;entry_count=[int]$target.entry_count}
    }
  )
  if ($maintenance) {
    $promotionPlan.candidate_manifest.record_sha256=$script:mir42ReleaseAssetsFixtureCandidate.identity.record.record_sha256
    $promotionPlan | Add-Member -NotePropertyName published_maintenance_predecessor -NotePropertyValue $custody
  }
  $fixtureTargetRows = @($fixturePackages | ForEach-Object { [ordered]@{target=[string]$_.target;distribution_version=[string]$_.distribution_version;archive_sha256=[string]$_.sha256;content_sha256=[string]$_.content_sha256;entry_count=[int]$_.entry_count} })
  $fixtureCandidateBinding = [ordered]@{sha256=('D' * 64);record_sha256=('E' * 64)}
  $fixtureFlags = [ordered]@{human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false}
  $releaseBinding = [ordered]@{source_version=$SourceVersion;tag=$releaseTag}
  $qualificationRecord = [pscustomobject][ordered]@{schema=1;kind='MIR42NineTargetReleaseQualificationSummaryV1';status='MIR-4.2-NINE-TARGET-TECHNICALLY-QUALIFIED-NONPUBLIC';release=$releaseBinding;source=$source;candidate_manifest=$fixtureCandidateBinding;targets=$fixtureTargetRows;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''}
  $provenanceRecord = [pscustomobject][ordered]@{schema=1;kind='MIR42NineTargetReleaseProvenanceV1';status='MIR-4.2-NINE-TARGET-PROVENANCE-FROZEN-NONPUBLIC';release=$releaseBinding;source=$source;candidate_manifest=$fixtureCandidateBinding;package_source_sha256=[string]$source.package_source_sha256;outputs=$fixtureTargetRows;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''}
  $componentsRecord = [pscustomobject][ordered]@{schema=1;kind='MIR42NineTargetComponentInventoryV1';status='MIR-4.2-NINE-TARGET-COMPONENTS-FROZEN-NONPUBLIC';release=$releaseBinding;source=$source;candidate_manifest=$fixtureCandidateBinding;player_assets=$fixtureTargetRows;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''}
  if ($maintenance) {
    $fixtureCandidateBinding.record_sha256=$script:mir42ReleaseAssetsFixtureCandidate.identity.record.record_sha256
    $qualificationRecord.kind='MIR42NineTargetMaintenanceReleaseQualificationSummaryV1';$qualificationRecord.status="MIR-$SourceVersion-NINE-TARGET-MAINTENANCE-TECHNICALLY-QUALIFIED-NONPUBLIC"
    $provenanceRecord.kind='MIR42NineTargetMaintenanceReleaseProvenanceV1';$provenanceRecord.status="MIR-$SourceVersion-NINE-TARGET-MAINTENANCE-PROVENANCE-FROZEN-NONPUBLIC"
    $componentsRecord.kind='MIR42NineTargetMaintenanceComponentInventoryV1';$componentsRecord.status="MIR-$SourceVersion-NINE-TARGET-MAINTENANCE-COMPONENTS-FROZEN-NONPUBLIC"
    foreach ($record in @($qualificationRecord,$provenanceRecord,$componentsRecord)) { $record | Add-Member -NotePropertyName published_maintenance_predecessor -NotePropertyValue $custody }
  }
  $qualificationPath = Join-Path $assetRoot "mir-$SourceVersion.qualification.json"
  $provenancePath = Join-Path $assetRoot "mir-$SourceVersion.provenance.json"
  $componentsPath = Join-Path $assetRoot "mir-$SourceVersion.components.json"
  Write-MIR4BootstrapRecord -Record $qualificationRecord -Path $qualificationPath | Out-Null
  Write-MIR4BootstrapRecord -Record $provenanceRecord -Path $provenancePath | Out-Null
  Write-MIR4BootstrapRecord -Record $componentsRecord -Path $componentsPath | Out-Null
  $fixtureGithub = [Collections.Generic.List[object]]::new()
  foreach ($package in $fixturePackages) { $fixtureGithub.Add([pscustomobject][ordered]@{name=[string]$package.public_name;role='package';target=[string]$package.target;sha256=[string]$package.sha256;bytes=[int64]$package.bytes}) }
  foreach ($support in @(
    [pscustomobject][ordered]@{name='SHA256SUMS.txt';role='checksum';target='';sha256=(Get-FileHash -LiteralPath (Join-Path $assetRoot 'SHA256SUMS.txt') -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64](Get-Item -LiteralPath (Join-Path $assetRoot 'SHA256SUMS.txt')).Length},
    [pscustomobject][ordered]@{name='SHA256SUMS.txt.sig';role='signature';target='';sha256=(Get-FileHash -LiteralPath (Join-Path $assetRoot 'SHA256SUMS.txt.sig') -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64](Get-Item -LiteralPath (Join-Path $assetRoot 'SHA256SUMS.txt.sig')).Length},
    [pscustomobject][ordered]@{name=$script:MIR42SupportCollectorAssetName;role='support-collector';target='';sha256=[string]$collector.sha256;bytes=[int64]$collector.bytes},
    [pscustomobject][ordered]@{name="mir-$SourceVersion.qualification.json";role='qualification';target='';sha256=(Get-FileHash -LiteralPath $qualificationPath -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64](Get-Item -LiteralPath $qualificationPath).Length},
    [pscustomobject][ordered]@{name="mir-$SourceVersion.provenance.json";role='provenance';target='';sha256=(Get-FileHash -LiteralPath $provenancePath -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64](Get-Item -LiteralPath $provenancePath).Length},
    [pscustomobject][ordered]@{name="mir-$SourceVersion.components.json";role='components';target='';sha256=(Get-FileHash -LiteralPath $componentsPath -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64](Get-Item -LiteralPath $componentsPath).Length}
  )) { $fixtureGithub.Add($support) }
  $fixtureUploads = @(
    foreach ($target in $script:MIR42ReleaseAssetTargets) {
      $path = 'upload-text/' + $target + '.md'; $item = Get-Item -LiteralPath (Join-Path $assetRoot $path)
      [pscustomobject][ordered]@{target=$target;path=$path;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64]$item.Length}
    }
  )
  $notesItem = Get-Item -LiteralPath (Join-Path $assetRoot 'release-notes.md')
  $releaseManifestRecord = [pscustomobject][ordered]@{
    schema=1;kind='MIR42NineTargetReleaseManifestV1';status='MIR-4.2-NINE-TARGET-RELEASE-MANIFEST-FROZEN-NONPUBLIC';release=$releaseBinding;source=$source;candidate_manifest=$fixtureCandidateBinding
    technical_seal=[ordered]@{sha256=[string]$sealIdentity.sha256;record_sha256=[string]$sealIdentity.record.record_sha256};github_assets=@($fixtureGithub);manifest_asset=[ordered]@{name="mir-$SourceVersion.release.json"}
    release_body=[ordered]@{path='release-notes.md';sha256=(Get-FileHash -LiteralPath $notesItem.FullName -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64]$notesItem.Length};mod_portal_upload_texts=$fixtureUploads;signature_verified=$false
    human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''
  }
  if ($maintenance) {
    $releaseManifestRecord.kind='MIR42NineTargetMaintenanceReleaseManifestV1'
    $releaseManifestRecord.status="MIR-$SourceVersion-NINE-TARGET-MAINTENANCE-RELEASE-MANIFEST-FROZEN-NONPUBLIC"
    $releaseManifestRecord | Add-Member -NotePropertyName published_maintenance_predecessor -NotePropertyValue $custody
  }
  Write-MIR4BootstrapRecord -Record $releaseManifestRecord -Path (Join-Path $assetRoot "mir-$SourceVersion.release.json") | Out-Null
  Set-Item Function:Get-MIR42ExactFourTargetCandidate -Value { param($RepoRoot,$CandidateManifestPath) return $script:mir42ReleaseAssetsFixtureCandidate }

  if ($SourceVersion -ceq '4.2.2') {
    $upgradeControls=Invoke-MIR422ReleaseUpgradeControls -Root (Join-Path $root 'upgrade-controls') -PackageAssets @($fixturePackages)
    $PSDefaultParameterValues['Get-MIR42NineTargetReleaseAssetInventory:MaintenanceUpgradeEvidencePath']=$upgradeControls.path
    Assert-MIR42ReleaseAssetsTest ($upgradeControls.checks -ge 13 -and $upgradeControls.native_runs -eq 0) 'complete-upgrade-evidence-opposing-controls'
  }
  $inventoryPath = Join-Path $root 'frozen-inventory.json'
  $inventory = Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion $SourceVersion -ReleaseTag $releaseTag -AssetRoot $assetRoot -OutputPath $inventoryPath
  $expectedKind=if ($maintenance) { 'MIR42NineTargetMaintenanceReleaseAssetInventoryV1' } else { 'MIR42NineTargetReleaseAssetInventoryV1' }
  Assert-MIR42ReleaseAssetsTest -Condition ([string]$inventory.record.kind -ceq $expectedKind -and @($inventory.record.package_assets).Count -eq 9 -and @($inventory.record.github_assets).Count -eq 16 -and @($inventory.record.mod_portal_upload_texts).Count -eq 9 -and -not [bool]$inventory.record.signature.signature_verified -and -not [bool]$inventory.record.publication_authorized) -Code 'nine-asset-inventory-frozen-nonpublic'
  $readInventory = Read-MIR42NineTargetReleaseAssetInventory -Path $inventoryPath
  Assert-MIR42ReleaseAssetsTest -Condition ([string]$readInventory.sha256 -ceq [string]$inventory.sha256) -Code 'frozen-inventory-self-hash-reader'
  foreach ($suffix in @('00','01','02')) {
    if ($suffix -ceq $patchSuffix) { continue }
    $wrongPatch=$inventory.record | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    $wrongPatch.package_assets[8].distribution_version='4.2.013' + $suffix
    $wrongPath=Join-Path $root ('wrong-patch-' + $suffix + '.json')
    Write-MIR4BootstrapRecord -Record $wrongPatch -Path $wrongPath | Out-Null
    $rejected=$false
    try { Read-MIR42NineTargetReleaseAssetInventory -Path $wrongPath | Out-Null } catch { $rejected=$_.Exception.Message -ceq '[mir42-release-assets-distribution-identity] f013' }
    Assert-MIR42ReleaseAssetsTest -Condition $rejected -Code ('codec-rejects-ninth-patch-' + $suffix)
  }
  foreach ($wrongTag in @('v4.2.1-stable','v4.2.2-stable','v4.2.0','v4.2.1','v4.2.2')) {
    if ($wrongTag -ceq $releaseTag) { continue }
    $output=Join-Path $root ('wrong-tag-' + $wrongTag + '.json')
    $rejected=$false
    try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion $SourceVersion -ReleaseTag $wrongTag -AssetRoot $assetRoot -OutputPath $output | Out-Null } catch { $rejected=$_.Exception.Message -ceq '[mir42-release-assets-version-contract]' }
    Assert-MIR42ReleaseAssetsTest -Condition ($rejected -and -not (Test-Path -LiteralPath $output)) -Code ('wrong-tag-no-output-' + $wrongTag)
  }
  if ($maintenance) {
    Assert-MIR42ReleaseAssetsTest -Condition ((ConvertTo-MIR4BootstrapCanonicalJson -Value $inventory.record.published_maintenance_predecessor) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $custody)) -Code 'published-predecessor-custody-preserved'
    $missingCustodyPlan=$promotionPlan | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    $missingCustodyPlan.PSObject.Properties.Remove('published_maintenance_predecessor')
    $output=Join-Path $root 'missing-custody.json';$rejected=$false
    try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $missingCustodyPlan -SourceVersion $SourceVersion -ReleaseTag $releaseTag -AssetRoot $assetRoot -OutputPath $output | Out-Null } catch { $rejected=$_.Exception.Message -ceq '[mir42-release-assets-seal-maintenance-custody-required]' }
    Assert-MIR42ReleaseAssetsTest -Condition ($rejected -and -not (Test-Path -LiteralPath $output)) -Code 'missing-maintenance-custody-no-output'
    $drift=$promotionPlan | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    $drift.published_maintenance_predecessor.manifest.path='other-custody-location'
    $output=Join-Path $root 'mismatched-custody.json';$rejected=$false
    try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $drift -SourceVersion $SourceVersion -ReleaseTag $releaseTag -AssetRoot $assetRoot -OutputPath $output | Out-Null } catch { $rejected=$_.Exception.Message -ceq '[mir42-release-assets-seal-maintenance-custody]' }
    Assert-MIR42ReleaseAssetsTest -Condition ($rejected -and -not (Test-Path -LiteralPath $output)) -Code 'mismatched-maintenance-custody-no-output'
    $drift.published_maintenance_predecessor.targets[8].version='4.2.013'+$patchSuffix
    $output=Join-Path $root 'wrong-predecessor-version.json';$rejected=$false
    try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $drift -SourceVersion $SourceVersion -ReleaseTag $releaseTag -AssetRoot $assetRoot -OutputPath $output | Out-Null } catch { $rejected=$_.Exception.Message -ceq '[mir42-release-assets-maintenance-predecessor-target] 8/version' }
    Assert-MIR42ReleaseAssetsTest -Condition ($rejected -and -not (Test-Path -LiteralPath $output)) -Code 'selected-published-predecessor-required'
  }

  foreach ($case in @(
    [pscustomobject]@{field='human_go_required_after_main_readback';value='false'},
    [pscustomobject]@{field='publication_authorized';value=0},
    [pscustomobject]@{field='tagging_authorized';value=$null},
    [pscustomobject]@{field='signature_verified';value=''}
  )) {
    $typedInventory = $inventory.record | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    if ($case.field -ceq 'signature_verified') { $typedInventory.signature.signature_verified = $case.value }
    else { $typedInventory.($case.field) = $case.value }
    $typedPath = Join-Path $root ('untyped-' + $case.field + '.json')
    Write-MIR4BootstrapRecord -Record $typedInventory -Path $typedPath | Out-Null
    $untypedRejected = $false
    try { Read-MIR42NineTargetReleaseAssetInventory -Path $typedPath | Out-Null }
    catch { $untypedRejected = $_.Exception.Message -match '^\[mir42-release-assets-.*-flag-type\]' }
    Assert-MIR42ReleaseAssetsTest -Condition $untypedRejected -Code ('inventory-boolean-type-' + $case.field)
  }

  $downloadRoot = Join-Path $root 'downloaded-public-bytes-fixture'
  New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null
  foreach ($asset in @($inventory.record.github_assets)) {
    $sourcePath = switch ([string]$asset.role) {
      'package' { Join-Path $assetRoot ('assets/' + [string]$asset.target + '/' + [string]$asset.name) }
      default { Join-Path $assetRoot ([string]$asset.name) }
    }
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $downloadRoot ([string]$asset.name))
  }
  $verification = Assert-MIR42NineTargetDownloadedReleaseBytes -FrozenInventoryPath $inventoryPath -DownloadedAssetRoot $downloadRoot
  Assert-MIR42ReleaseAssetsTest -Condition ([bool]$verification.downloaded_bytes_verified -and -not [bool]$verification.public_readback_verified -and -not [bool]$verification.publication_authorized) -Code 'all-public-assets-rehashed-nonauthorizing'

  $script:mir42ReleaseAssetsSyntheticObserver = [pscustomobject][ordered]@{
    kind='MIR42PublicReleaseObserverV1';transport='github-cli-api';synthetic=$true;repository='Julesc013/more-infinite-research';tag=$releaseTag;release_id=1;url=('https://github.com/Julesc013/more-infinite-research/releases/tag/' + $releaseTag);draft=$false;network_calls=0
    assets=@($inventory.record.github_assets | ForEach-Object { [pscustomobject][ordered]@{name=[string]$_.name;sha256=[string]$_.sha256;bytes=[int64]$_.bytes} })
  }
  $syntheticRejected = $false
  $publicObserver = (Get-Item Function:Invoke-MIR42DefaultPublicReleaseObserver).ScriptBlock
  try {
    Set-Item Function:Invoke-MIR42DefaultPublicReleaseObserver -Value { param($Repository,$Tag) return $script:mir42ReleaseAssetsSyntheticObserver }
    try { Get-MIR42NineTargetPublicDownloadedReleaseReadback -FrozenInventoryPath $inventoryPath -DownloadedAssetRoot $downloadRoot | Out-Null }
    catch { $syntheticRejected = $_.Exception.Message -match '^\[mir42-release-assets-public-observer-state\]' }
  } finally { Set-Item Function:Invoke-MIR42DefaultPublicReleaseObserver -Value $publicObserver }
  Assert-MIR42ReleaseAssetsTest -Condition $syntheticRejected -Code 'synthetic-or-private-copy-cannot-count-as-public-readback'

  $reorderedLiveAssets = [Collections.Generic.List[object]]::new()
  for ($index = @($inventory.record.github_assets).Count - 1; $index -ge 0; $index--) {
    $asset = $inventory.record.github_assets[$index]
    $reorderedLiveAssets.Add([pscustomobject][ordered]@{name=[string]$asset.name;sha256=[string]$asset.sha256;bytes=[int64]$asset.bytes})
  }
  $structuralLiveMetadata = [pscustomobject][ordered]@{
    kind='MIR42PublicReleaseObserverV1';transport='github-cli-api';synthetic=$false;repository='Julesc013/more-infinite-research';tag=$releaseTag;release_id=1;url=('https://github.com/Julesc013/more-infinite-research/releases/tag/' + $releaseTag);draft=$false;network_calls=1;assets=@($reorderedLiveAssets)
  }
  Assert-MIR42NineTargetLivePublicReleaseObservation -Observation $structuralLiveMetadata -Inventory $inventory
  Assert-MIR42ReleaseAssetsTest -Condition $true -Code 'reordered-live-metadata-binds-by-asset-name'

  $ninthName = [string]$inventory.record.package_assets[8].public_name
  $ninthDrift = $structuralLiveMetadata | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  @($ninthDrift.assets | Where-Object { [string]$_.name -ceq $ninthName })[0].sha256 = ('0' * 64)
  $ninthDriftRejected = $false
  try { Assert-MIR42NineTargetLivePublicReleaseObservation -Observation $ninthDrift -Inventory $inventory } catch { $ninthDriftRejected = $_.Exception.Message -match ('^\[mir42-release-assets-public-observer-asset\].*' + [regex]::Escape($ninthName) + '$') }
  Assert-MIR42ReleaseAssetsTest -Condition $ninthDriftRejected -Code 'ninth-public-asset-digest-drift-rejected'

  $duplicateLive = $structuralLiveMetadata | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $duplicateLive.assets[1].name = [string]$duplicateLive.assets[0].name
  $duplicateRejected = $false
  try { Assert-MIR42NineTargetLivePublicReleaseObservation -Observation $duplicateLive -Inventory $inventory } catch { $duplicateRejected = $_.Exception.Message -match '^\[mir42-release-assets-public-observer-duplicate\]' }
  Assert-MIR42ReleaseAssetsTest -Condition $duplicateRejected -Code 'duplicate-public-asset-name-rejected'

  $missingRoot = Join-Path $root 'missing-ninth'
  Copy-MIR42ReleaseAssetsFixtureTree -Source $assetRoot -Destination $missingRoot
  Remove-Item -LiteralPath (Join-Path $missingRoot ('assets/f013/' + [IO.Path]::GetFileName([string]$targets[8].archive_path))) -Force
  $missingRejected = $false
  try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion $SourceVersion -ReleaseTag $releaseTag -AssetRoot $missingRoot -OutputPath (Join-Path $root 'missing.json') | Out-Null }
  catch { $missingRejected = $_.Exception.Message -match '^\[mir42-release-assets-package-missing\].*f013' }
  Assert-MIR42ReleaseAssetsTest -Condition $missingRejected -Code 'missing-ninth-package-rejected'

  $substitutedRoot = Join-Path $root 'substituted-ninth'
  Copy-MIR42ReleaseAssetsFixtureTree -Source $assetRoot -Destination $substitutedRoot
  Copy-Item -LiteralPath (Join-Path $substitutedRoot ('assets/f014/' + [IO.Path]::GetFileName([string]$targets[7].archive_path))) -Destination (Join-Path $substitutedRoot ('assets/f013/' + [IO.Path]::GetFileName([string]$targets[8].archive_path))) -Force
  $substitutedRejected = $false
  try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion $SourceVersion -ReleaseTag $releaseTag -AssetRoot $substitutedRoot -OutputPath (Join-Path $root 'substituted.json') | Out-Null }
  catch { $substitutedRejected = $_.Exception.Message -match '^\[mir42-release-assets-package-identity\].*f013' }
  Assert-MIR42ReleaseAssetsTest -Condition $substitutedRejected -Code 'substituted-ninth-package-rejected'

  $extraRoot = Join-Path $root 'extra-asset'
  Copy-MIR42ReleaseAssetsFixtureTree -Source $assetRoot -Destination $extraRoot
  [IO.File]::WriteAllText((Join-Path $extraRoot 'unbound-release-byte.txt'), 'unbound', [Text.UTF8Encoding]::new($false))
  $extraRejected = $false
  try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion $SourceVersion -ReleaseTag $releaseTag -AssetRoot $extraRoot -OutputPath (Join-Path $root 'extra.json') | Out-Null }
  catch { $extraRejected = $_.Exception.Message -match '^\[mir42-release-assets-count\]' }
  Assert-MIR42ReleaseAssetsTest -Condition $extraRejected -Code 'extra-public-or-upload-asset-rejected'

  $qualificationDriftRoot = Join-Path $root 'qualification-drift'
  Copy-MIR42ReleaseAssetsFixtureTree -Source $assetRoot -Destination $qualificationDriftRoot
  $qualificationDriftPath = Join-Path $qualificationDriftRoot "mir-$SourceVersion.qualification.json"
  $qualificationDrift = Get-Content -Raw -LiteralPath $qualificationDriftPath | ConvertFrom-Json -Depth 100 -DateKind String
  $qualificationDrift.targets[8].archive_sha256 = ('0' * 64)
  Write-MIR4BootstrapRecord -Record $qualificationDrift -Path $qualificationDriftPath | Out-Null
  $qualificationDriftRejected = $false
  try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion $SourceVersion -ReleaseTag $releaseTag -AssetRoot $qualificationDriftRoot -OutputPath (Join-Path $root 'qualification-drift.json') | Out-Null }
  catch { $qualificationDriftRejected = $_.Exception.Message -match '^\[mir42-release-assets-qualification-target\].*f013/archive_sha256' }
  Assert-MIR42ReleaseAssetsTest -Condition $qualificationDriftRejected -Code 'qualification-ninth-package-binding-rejected'

  if ($maintenance) {
    $custodyDriftRoot=Join-Path $root 'qualification-custody-drift'
    Copy-MIR42ReleaseAssetsFixtureTree -Source $assetRoot -Destination $custodyDriftRoot
    $path=Join-Path $custodyDriftRoot "mir-$SourceVersion.qualification.json"
    $drift=Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String
    $drift.published_maintenance_predecessor.manifest.path='different-qualification-custody'
    Write-MIR4BootstrapRecord -Record $drift -Path $path | Out-Null
    $output=Join-Path $root 'qualification-custody-drift.json';$rejected=$false
    try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion $SourceVersion -ReleaseTag $releaseTag -AssetRoot $custodyDriftRoot -OutputPath $output | Out-Null } catch { $rejected=$_.Exception.Message -ceq '[mir42-release-assets-qualification-maintenance-custody]' }
    Assert-MIR42ReleaseAssetsTest -Condition ($rejected -and -not (Test-Path -LiteralPath $output)) -Code 'qualification-custody-drift-no-output'
    $drift.published_maintenance_predecessor=$custody
    $drift.kind='MIR42NineTargetReleaseQualificationSummaryV1'
    Write-MIR4BootstrapRecord -Record $drift -Path $path | Out-Null
    $output=Join-Path $root 'legacy-qualification-kind.json';$rejected=$false
    try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion $SourceVersion -ReleaseTag $releaseTag -AssetRoot $custodyDriftRoot -OutputPath $output | Out-Null } catch { $rejected=$_.Exception.Message -ceq '[mir42-release-assets-qualification-state]' }
    Assert-MIR42ReleaseAssetsTest -Condition ($rejected -and -not (Test-Path -LiteralPath $output)) -Code 'old-qualification-kind-cannot-be-relabelled'
  }

  # All upstream hashes deliberately match this controlled ZIP; only its
  # info.json version is wrong. Byte binding alone must not freeze this asset.
  $metadataRoot=Join-Path $root 'matching-hashes-wrong-metadata'
  Copy-MIR42ReleaseAssetsFixtureTree -Source $assetRoot -Destination $metadataRoot
  $ninth=$targets[8];$metadataPath=Join-Path $metadataRoot ('assets/f013/' + [IO.Path]::GetFileName($ninth.archive_path))
  Remove-Item -LiteralPath $metadataPath -Force
  New-MIR42ReleaseAssetsFixtureZip -Path $metadataPath -Root ('more-infinite-research_' + $ninth.distribution_version) -Version '4.2.01303' -Line '0.13'
  $badArchive=Get-MIR4ArchiveInventory -Path $metadataPath
  $savedCandidate=$script:mir42ReleaseAssetsFixtureCandidate
  $script:mir42ReleaseAssetsFixtureCandidate=$savedCandidate | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $badSeal=$sealIdentity.record | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $badPlan=$promotionPlan | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  foreach ($row in @($script:mir42ReleaseAssetsFixtureCandidate.targets[8],$badSeal.targets[8],$badPlan.target_assets[8])) {
    $row.archive_sha256=$badArchive.archive_sha256;$row.content_sha256=$badArchive.content_sha256;$row.entry_count=$badArchive.entry_count
  }
  $badSealPath=Join-Path $root 'wrong-metadata-seal-fixture.json'
  Write-MIR4BootstrapRecord -Record $badSeal -Path $badSealPath | Out-Null
  $badSealIdentity=Read-MIR42SealRecord -Path $badSealPath -Code 'mir42-release-assets-test-metadata-seal'
  $badPlan.technical_seal.sha256=$badSealIdentity.sha256;$badPlan.technical_seal.record_sha256=$badSealIdentity.record.record_sha256
  $output=Join-Path $root 'wrong-metadata-must-not-freeze.json';$rejected=$false
  try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $badSealPath -PromotionPlan $badPlan -SourceVersion $SourceVersion -ReleaseTag $releaseTag -AssetRoot $metadataRoot -OutputPath $output | Out-Null } catch { $rejected=$_.Exception.Message -ceq '[mir42-release-assets-package-metadata] f013' }
  finally { $script:mir42ReleaseAssetsFixtureCandidate=$savedCandidate }
  Assert-MIR42ReleaseAssetsTest -Condition ($rejected -and -not (Test-Path -LiteralPath $output)) -Code 'matching-archive-hashes-do-not-excuse-wrong-package-version'

  $sourceDriftPlan = $promotionPlan | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $sourceDriftPlan.source.package_source_sha256 = ('F' * 64)
  $sourceDriftRejected = $false
  try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $sourceDriftPlan -SourceVersion $SourceVersion -ReleaseTag $releaseTag -AssetRoot $assetRoot -OutputPath (Join-Path $root 'source-drift.json') | Out-Null }
  catch { $sourceDriftRejected = $_.Exception.Message -match '^\[mir42-release-assets-promotion-source\].*package_source_sha256' }
  Assert-MIR42ReleaseAssetsTest -Condition $sourceDriftRejected -Code 'release-source-package-drift-rejected'

  [IO.File]::WriteAllText((Join-Path $downloadRoot "mir-$SourceVersion.components.json"), 'tampered downloaded release bytes', [Text.UTF8Encoding]::new($false))
  $downloadDriftRejected = $false
  try { Assert-MIR42NineTargetDownloadedReleaseBytes -FrozenInventoryPath $inventoryPath -DownloadedAssetRoot $downloadRoot | Out-Null }
  catch { $downloadDriftRejected = $_.Exception.Message -match ('^\[mir42-release-assets-downloaded-byte\].*' + [regex]::Escape("mir-$SourceVersion.components.json")) }
  Assert-MIR42ReleaseAssetsTest -Condition $downloadDriftRejected -Code 'downloaded-byte-drift-rejected'
} finally {
  $PSDefaultParameterValues=$previousDefaults
  Set-Item Function:Get-MIR42ExactFourTargetCandidate -Value $candidateReader
  $buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  if (-not $root.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-release-assets-test-fixture-containment]' }
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

Write-Output "MIR42-NINE-TARGET-RELEASE-ASSETS-PASSED source=$SourceVersion assertions=$script:mir42ReleaseAssetControlAssertions assets=16 uploads=9 targets=9 network=0 public-claims=0 collector-controls=$($collectorControls.assertions) collector-hosts=$($collectorControls.hosts) host-versions=$($collectorControls.host_versions -join ',')"
if (-not $maintenance) {
  # Use a fresh script scope after the legacy fixtures have been retired. The
  # module's dot-source guards must not reuse parent functions without their
  # script-scoped constants. This remains one serial test process tree.
  foreach ($maintenanceVersion in @('4.2.1','4.2.2')) {
    & (Get-Process -Id $PID).Path -NoProfile -File $PSCommandPath -RepoRoot $repo -SourceVersion $maintenanceVersion
    if ($LASTEXITCODE -ne 0) { throw "[mir42-release-assets-maintenance-controls-failed] $maintenanceVersion" }
  }
}
