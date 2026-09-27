# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$module = Join-Path $repo 'tools/mir/application/release/readiness/MIR42ReleaseAssets.ps1'
if (-not (Test-Path -LiteralPath $module -PathType Leaf)) { throw "[mir42-release-assets-test-module-missing] $module" }
. $module

function Assert-MIR42ReleaseAssetsTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir42-release-assets-test-$Code]" }
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

$root = Join-Path $repo ('build/test-results/mir42-release-assets-' + [guid]::NewGuid().ToString('N'))
$candidateReader = (Get-Item Function:Get-MIR42ExactFourTargetCandidate).ScriptBlock
try {
  $candidateRoot = Join-Path $root 'candidate'
  $assetRoot = Join-Path $root 'release-assets'
  New-Item -ItemType Directory -Force -Path $candidateRoot,$assetRoot | Out-Null
  $source = [pscustomobject][ordered]@{commit=('a' * 40);tree=('b' * 40);package_source_sha256=('C' * 64)}
  $targets = [Collections.Generic.List[object]]::new()
  $lineByTarget = [ordered]@{f210='2.1';f200='2.0';f110='1.1';f100='1.0';f017='0.17';f016='0.16';f015='0.15';f014='0.14';f013='0.13'}
  foreach ($target in $script:MIR42ReleaseAssetTargets) {
    $version = '4.2.' + $target.Substring(1) + '00'
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
  foreach ($target in $script:MIR42ReleaseAssetTargets) {
    $path = Join-Path $assetRoot ('upload-text/' + $target + '.md')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path, ("Structural upload copy for " + $target + "`n"), [Text.UTF8Encoding]::new($false))
  }

  $script:mir42ReleaseAssetsFixtureCandidate = [pscustomobject][ordered]@{
    identity=[pscustomobject][ordered]@{sha256=('D' * 64);record=[pscustomobject][ordered]@{record_sha256=('E' * 64)}}
    source=$source;scope='nine-target';targets=@($targets)
  }
  $sealRecord = [pscustomobject][ordered]@{
    schema=1;kind='MIR42NineTargetTechnicalSealV1';status='MIR-4.2-NINE-TARGET-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR'
    source=$source;candidate_manifest=[ordered]@{sha256=('D' * 64);record_sha256=('E' * 64)};targets=@($targets)
    protected_main_promotion_authorized=$false;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''
  }
  $sealPath = Join-Path $root 'technical-seal.json'
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
  $fixtureTargetRows = @($fixturePackages | ForEach-Object { [ordered]@{target=[string]$_.target;distribution_version=[string]$_.distribution_version;archive_sha256=[string]$_.sha256;content_sha256=[string]$_.content_sha256;entry_count=[int]$_.entry_count} })
  $fixtureCandidateBinding = [ordered]@{sha256=('D' * 64);record_sha256=('E' * 64)}
  $fixtureFlags = [ordered]@{human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false}
  $releaseBinding = [ordered]@{source_version='4.2.0';tag='v4.2.0'}
  $qualificationRecord = [pscustomobject][ordered]@{schema=1;kind='MIR42NineTargetReleaseQualificationSummaryV1';status='MIR-4.2-NINE-TARGET-TECHNICALLY-QUALIFIED-NONPUBLIC';release=$releaseBinding;source=$source;candidate_manifest=$fixtureCandidateBinding;targets=$fixtureTargetRows;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''}
  $provenanceRecord = [pscustomobject][ordered]@{schema=1;kind='MIR42NineTargetReleaseProvenanceV1';status='MIR-4.2-NINE-TARGET-PROVENANCE-FROZEN-NONPUBLIC';release=$releaseBinding;source=$source;candidate_manifest=$fixtureCandidateBinding;package_source_sha256=[string]$source.package_source_sha256;outputs=$fixtureTargetRows;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''}
  $componentsRecord = [pscustomobject][ordered]@{schema=1;kind='MIR42NineTargetComponentInventoryV1';status='MIR-4.2-NINE-TARGET-COMPONENTS-FROZEN-NONPUBLIC';release=$releaseBinding;source=$source;candidate_manifest=$fixtureCandidateBinding;player_assets=$fixtureTargetRows;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''}
  $qualificationPath = Join-Path $assetRoot 'mir-4.2.0.qualification.json'
  $provenancePath = Join-Path $assetRoot 'mir-4.2.0.provenance.json'
  $componentsPath = Join-Path $assetRoot 'mir-4.2.0.components.json'
  Write-MIR4BootstrapRecord -Record $qualificationRecord -Path $qualificationPath | Out-Null
  Write-MIR4BootstrapRecord -Record $provenanceRecord -Path $provenancePath | Out-Null
  Write-MIR4BootstrapRecord -Record $componentsRecord -Path $componentsPath | Out-Null
  $fixtureGithub = [Collections.Generic.List[object]]::new()
  foreach ($package in $fixturePackages) { $fixtureGithub.Add([pscustomobject][ordered]@{name=[string]$package.public_name;role='package';target=[string]$package.target;sha256=[string]$package.sha256;bytes=[int64]$package.bytes}) }
  foreach ($support in @(
    [pscustomobject][ordered]@{name='SHA256SUMS.txt';role='checksum';target='';sha256=(Get-FileHash -LiteralPath (Join-Path $assetRoot 'SHA256SUMS.txt') -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64](Get-Item -LiteralPath (Join-Path $assetRoot 'SHA256SUMS.txt')).Length},
    [pscustomobject][ordered]@{name='SHA256SUMS.txt.sig';role='signature';target='';sha256=(Get-FileHash -LiteralPath (Join-Path $assetRoot 'SHA256SUMS.txt.sig') -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64](Get-Item -LiteralPath (Join-Path $assetRoot 'SHA256SUMS.txt.sig')).Length},
    [pscustomobject][ordered]@{name='mir-4.2.0.qualification.json';role='qualification';target='';sha256=(Get-FileHash -LiteralPath $qualificationPath -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64](Get-Item -LiteralPath $qualificationPath).Length},
    [pscustomobject][ordered]@{name='mir-4.2.0.provenance.json';role='provenance';target='';sha256=(Get-FileHash -LiteralPath $provenancePath -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64](Get-Item -LiteralPath $provenancePath).Length},
    [pscustomobject][ordered]@{name='mir-4.2.0.components.json';role='components';target='';sha256=(Get-FileHash -LiteralPath $componentsPath -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64](Get-Item -LiteralPath $componentsPath).Length}
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
    technical_seal=[ordered]@{sha256=[string]$sealIdentity.sha256;record_sha256=[string]$sealIdentity.record.record_sha256};github_assets=@($fixtureGithub);manifest_asset=[ordered]@{name='mir-4.2.0.release.json'}
    release_body=[ordered]@{path='release-notes.md';sha256=(Get-FileHash -LiteralPath $notesItem.FullName -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64]$notesItem.Length};mod_portal_upload_texts=$fixtureUploads;signature_verified=$false
    human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''
  }
  Write-MIR4BootstrapRecord -Record $releaseManifestRecord -Path (Join-Path $assetRoot 'mir-4.2.0.release.json') | Out-Null
  Set-Item Function:Get-MIR42ExactFourTargetCandidate -Value { param($RepoRoot,$CandidateManifestPath) return $script:mir42ReleaseAssetsFixtureCandidate }

  $inventoryPath = Join-Path $root 'frozen-inventory.json'
  $inventory = Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion '4.2.0' -ReleaseTag 'v4.2.0' -AssetRoot $assetRoot -OutputPath $inventoryPath
  Assert-MIR42ReleaseAssetsTest -Condition ([string]$inventory.record.kind -ceq 'MIR42NineTargetReleaseAssetInventoryV1' -and @($inventory.record.package_assets).Count -eq 9 -and @($inventory.record.github_assets).Count -eq 15 -and @($inventory.record.mod_portal_upload_texts).Count -eq 9 -and -not [bool]$inventory.record.signature.signature_verified -and -not [bool]$inventory.record.publication_authorized) -Code 'nine-asset-inventory-frozen-nonpublic'
  $readInventory = Read-MIR42NineTargetReleaseAssetInventory -Path $inventoryPath
  Assert-MIR42ReleaseAssetsTest -Condition ([string]$readInventory.sha256 -ceq [string]$inventory.sha256) -Code 'frozen-inventory-self-hash-reader'

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
    kind='MIR42PublicReleaseObserverV1';transport='github-cli-api';synthetic=$true;repository='Julesc013/more-infinite-research';tag='v4.2.0';release_id=1;url='https://github.com/Julesc013/more-infinite-research/releases/tag/v4.2.0';draft=$false;network_calls=0
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
    kind='MIR42PublicReleaseObserverV1';transport='github-cli-api';synthetic=$false;repository='Julesc013/more-infinite-research';tag='v4.2.0';release_id=1;url='https://github.com/Julesc013/more-infinite-research/releases/tag/v4.2.0';draft=$false;network_calls=1;assets=@($reorderedLiveAssets)
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
  try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion '4.2.0' -ReleaseTag 'v4.2.0' -AssetRoot $missingRoot -OutputPath (Join-Path $root 'missing.json') | Out-Null }
  catch { $missingRejected = $_.Exception.Message -match '^\[mir42-release-assets-package-missing\].*f013' }
  Assert-MIR42ReleaseAssetsTest -Condition $missingRejected -Code 'missing-ninth-package-rejected'

  $substitutedRoot = Join-Path $root 'substituted-ninth'
  Copy-MIR42ReleaseAssetsFixtureTree -Source $assetRoot -Destination $substitutedRoot
  Copy-Item -LiteralPath (Join-Path $substitutedRoot ('assets/f014/' + [IO.Path]::GetFileName([string]$targets[7].archive_path))) -Destination (Join-Path $substitutedRoot ('assets/f013/' + [IO.Path]::GetFileName([string]$targets[8].archive_path))) -Force
  $substitutedRejected = $false
  try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion '4.2.0' -ReleaseTag 'v4.2.0' -AssetRoot $substitutedRoot -OutputPath (Join-Path $root 'substituted.json') | Out-Null }
  catch { $substitutedRejected = $_.Exception.Message -match '^\[mir42-release-assets-package-identity\].*f013' }
  Assert-MIR42ReleaseAssetsTest -Condition $substitutedRejected -Code 'substituted-ninth-package-rejected'

  $extraRoot = Join-Path $root 'extra-asset'
  Copy-MIR42ReleaseAssetsFixtureTree -Source $assetRoot -Destination $extraRoot
  [IO.File]::WriteAllText((Join-Path $extraRoot 'unbound-release-byte.txt'), 'unbound', [Text.UTF8Encoding]::new($false))
  $extraRejected = $false
  try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion '4.2.0' -ReleaseTag 'v4.2.0' -AssetRoot $extraRoot -OutputPath (Join-Path $root 'extra.json') | Out-Null }
  catch { $extraRejected = $_.Exception.Message -match '^\[mir42-release-assets-count\]' }
  Assert-MIR42ReleaseAssetsTest -Condition $extraRejected -Code 'extra-public-or-upload-asset-rejected'

  $qualificationDriftRoot = Join-Path $root 'qualification-drift'
  Copy-MIR42ReleaseAssetsFixtureTree -Source $assetRoot -Destination $qualificationDriftRoot
  $qualificationDriftPath = Join-Path $qualificationDriftRoot 'mir-4.2.0.qualification.json'
  $qualificationDrift = Get-Content -Raw -LiteralPath $qualificationDriftPath | ConvertFrom-Json -Depth 100 -DateKind String
  $qualificationDrift.targets[8].archive_sha256 = ('0' * 64)
  Write-MIR4BootstrapRecord -Record $qualificationDrift -Path $qualificationDriftPath | Out-Null
  $qualificationDriftRejected = $false
  try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $promotionPlan -SourceVersion '4.2.0' -ReleaseTag 'v4.2.0' -AssetRoot $qualificationDriftRoot -OutputPath (Join-Path $root 'qualification-drift.json') | Out-Null }
  catch { $qualificationDriftRejected = $_.Exception.Message -match '^\[mir42-release-assets-qualification-target\].*f013/archive_sha256' }
  Assert-MIR42ReleaseAssetsTest -Condition $qualificationDriftRejected -Code 'qualification-ninth-package-binding-rejected'

  $sourceDriftPlan = $promotionPlan | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $sourceDriftPlan.source.package_source_sha256 = ('F' * 64)
  $sourceDriftRejected = $false
  try { Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $repo -CandidateManifestPath 'synthetic-candidate.json' -TechnicalSealPath $sealPath -PromotionPlan $sourceDriftPlan -SourceVersion '4.2.0' -ReleaseTag 'v4.2.0' -AssetRoot $assetRoot -OutputPath (Join-Path $root 'source-drift.json') | Out-Null }
  catch { $sourceDriftRejected = $_.Exception.Message -match '^\[mir42-release-assets-promotion-source\].*package_source_sha256' }
  Assert-MIR42ReleaseAssetsTest -Condition $sourceDriftRejected -Code 'release-source-package-drift-rejected'

  [IO.File]::WriteAllText((Join-Path $downloadRoot 'mir-4.2.0.components.json'), 'tampered downloaded release bytes', [Text.UTF8Encoding]::new($false))
  $downloadDriftRejected = $false
  try { Assert-MIR42NineTargetDownloadedReleaseBytes -FrozenInventoryPath $inventoryPath -DownloadedAssetRoot $downloadRoot | Out-Null }
  catch { $downloadDriftRejected = $_.Exception.Message -match '^\[mir42-release-assets-downloaded-byte\].*mir-4\.2\.0\.components\.json' }
  Assert-MIR42ReleaseAssetsTest -Condition $downloadDriftRejected -Code 'downloaded-byte-drift-rejected'
} finally {
  Set-Item Function:Get-MIR42ExactFourTargetCandidate -Value $candidateReader
  $buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  if (-not $root.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-release-assets-test-fixture-containment]' }
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

Write-Output 'MIR42-NINE-TARGET-RELEASE-ASSETS-PASSED assets=15 uploads=9 targets=9 processes=0 network=0 public-claims=0'
