[CmdletBinding()]
param([switch]$IdentityContractsOnly,[switch]$MaterializerReceiptContractsOnly,[switch]$HistoricalIdentityProjectionOnly,[switch]$HistoricalAuthenticationOnly,
  [ValidateSet('4.4.2','4.5.2','4.6.0','4.7.0')][string[]]$HistoricalAuthenticationSourceVersions=@())

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
$script:mir42CandidateRealMaterializer = (Get-Item Function:New-MIR4TargetPackage).ScriptBlock
$engineRunnerPath = Join-Path $repo 'tools/commands/release/Invoke-MIR42FourTargetEngineRun.ps1'
$engineTokens=$null;$engineErrors=$null
$engineAst=[Management.Automation.Language.Parser]::ParseFile($engineRunnerPath,[ref]$engineTokens,[ref]$engineErrors)
if(@($engineErrors).Count-ne0){throw '[mir42-candidate-engine-reader-parse]'}
foreach($name in @('Assert-MIR42EngineRunFile','Get-MIR42EngineCandidateVersionContract','Get-MIR42EngineMaintenanceSelection')){
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
$script:mir42CandidateReceiptAssertions = 0
$script:mir422ConstructionAssertions = 0

function Assert-MIR42CandidateBuildTest {
  param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
  if (-not $Condition) { throw "[mir42-candidate-build-test] $Message" }
  if ($Message.StartsWith('422-',[StringComparison]::Ordinal)) { $script:mir422ConstructionAssertions++ }
}

function Test-MIR42CandidateSchema {
  param([Parameter(Mandatory)][string]$Json, [Parameter(Mandatory)][string]$SchemaPath)
  # Test-Json releases differ in whether a schema rejection returns False or
  # reports InvalidJsonAgainstSchema. Only that rejection is a Boolean result;
  # broken schema files, JSON syntax, IO and binding failures must still fail.
  try {
    $valid = Test-Json -Json $Json -SchemaFile $SchemaPath -ErrorAction Stop
  } catch {
    if ($_.FullyQualifiedErrorId -cin @(
      'InvalidJsonAgainstSchema,Microsoft.PowerShell.Commands.TestJsonCommand',
      'InvalidJsonAgainstSchemaDetailed,Microsoft.PowerShell.Commands.TestJsonCommand'
    )) { return $false }
    throw
  }
  if ($valid -isnot [bool]) { throw '[mir42-candidate-schema-result-not-boolean]' }
  return $valid
}

function Test-MIR460ManifestIdentityOpponents {
  param([Parameter(Mandatory)]$Manifest, [Parameter(Mandatory)][string]$SchemaPath)
  foreach ($field in @('distribution_version', 'asset.path')) {
    $changed = $Manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    if ($field -ceq 'distribution_version') {
      $changed.targets[0].distribution_version = '4.5.21002'
    } else {
      $changed.targets[0].asset.path = 'assets/f210/more-infinite-research_4.6.21001.zip'
    }
    $accepted = Test-MIR42CandidateSchema -Json ($changed | ConvertTo-Json -Depth 100) -SchemaPath $SchemaPath
    Assert-MIR42CandidateBuildTest (-not $accepted) "460-schema-rejects-wrong-$field"
  }
}

function Test-MIR43HistoricalBaselineProjection {
  param([string]$OutputRoot)
  $checks = 0
  $utf8 = [Text.UTF8Encoding]::new($false)
  foreach ($target in @('f017','f016','f015','f014','f013')) {
    $record = Get-Content -Raw -LiteralPath (Join-Path $repo "targets/historical/$target/target.json") | ConvertFrom-Json -Depth 100 -DateKind String
    foreach ($sourceVersion in @('4.2.2','4.3.0','4.3.1','4.4.0','4.4.1','4.4.2','4.5.0','4.5.1','4.5.2','4.6.0','4.7.0')) {
      $tree = Join-Path $OutputRoot "$target/$sourceVersion"
      [IO.Directory]::CreateDirectory($tree) | Out-Null
      $template = Join-Path $repo "source/presentation/historical/$target/info.json.template"
      [IO.File]::WriteAllBytes((Join-Path $tree 'info.json'), [IO.File]::ReadAllBytes($template))
      $history = "---------------------------------------------------------------------------------------------------`nVersion: $($record.distribution_version)`n  Changes:`n    - Retained authored entry.`n"
      [IO.File]::WriteAllText((Join-Path $tree 'changelog.txt'), $history, $utf8)
      $minor = [int]$sourceVersion.Split('.')[1]
      $patch = [int]$sourceVersion.Split('.')[2]
      $version = (New-MIR4DistributionIdentityProjection -DistributionTargetCode $target.Substring(1) -SourceMinor $minor -SourcePatch $patch).distribution_version
      Set-MIR42HistoricalBaselinePackageIdentity -Tree $tree -Record $record -BaselineSourceVersion "4.$minor.0"
      Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion $version -SourceVersion $sourceVersion
      $info = Get-Content -Raw -LiteralPath (Join-Path $tree 'info.json') | ConvertFrom-Json -Depth 20
      Assert-MIR42CandidateBuildTest ([string]$info.version -ceq $version -and [string]$info.factorio_version -ceq [string]$record.factorio_line -and [string]$info.title -ceq 'More Infinite Research') "$sourceVersion-historical-real-adapter-identity-$target"
      Assert-MIR42CandidateBuildTest ([IO.File]::ReadAllText((Join-Path $tree 'changelog.txt')).EndsWith($history,[StringComparison]::Ordinal)) "$sourceVersion-historical-preserves-authored-history-$target"
      $checks += 2
    }
  }
  $record = Get-Content -Raw -LiteralPath (Join-Path $repo 'targets/historical/f017/target.json') | ConvertFrom-Json -Depth 100 -DateKind String
  foreach ($bad in @('version','factorio_version','name','record-line')) {
    $tree = Join-Path $OutputRoot "negative-$bad"
    [IO.Directory]::CreateDirectory($tree) | Out-Null
    $info = Get-Content -Raw -LiteralPath (Join-Path $repo 'source/presentation/historical/f017/info.json.template') | ConvertFrom-Json -Depth 20
    $testRecord = $record | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    switch ($bad) {
      'version' {$info.version='4.2.01701'}
      'factorio_version' {$info.factorio_version='0.13'}
      'name' {$info.name='another-mod'}
      'record-line' {$info.factorio_version='0.13';$testRecord.factorio_line='0.13'}
    }
    $path = Join-Path $tree 'info.json'
    [IO.File]::WriteAllText($path, ($info | ConvertTo-Json -Depth 20), $utf8)
    $before = Get-MIR4Sha256File -Path $path
    $rejected = $false
    try { Set-MIR42HistoricalBaselinePackageIdentity -Tree $tree -Record $testRecord -BaselineSourceVersion '4.3.0' }
    catch { $rejected = $_.Exception.Message -ceq '[mir42-historical-baseline-input-identity]' }
    Assert-MIR42CandidateBuildTest ($rejected -and (Get-MIR4Sha256File -Path $path) -ceq $before) "historical-baseline-refuses-$bad-without-write"
    $checks++
  }
  return $checks
}

function Test-MIR43HistoricalCandidateAuthentication {
  param([Parameter(Mandatory)][string]$OutputRoot,[string[]]$SelectedSourceVersions=@())

  . (Join-Path $repo 'tests/support/MIR43HistoricalCandidateAuthentication.ps1')
  $projectionChecks = 0
  foreach ($sourceVersion in @('4.3.0','4.3.1','4.4.0','4.4.1','4.4.2','4.5.0','4.5.2')) {
    foreach ($target in @('f017','f016','f015','f014','f013')) {
      $projection = Get-MIR43HistoricalCandidateAuthenticationProjection -Repository $repo -Target $target -SourceVersion $sourceVersion
      Assert-MIR42CandidateBuildTest (
        [string]$projection.target -ceq $target -and
        [string]$projection.source_version -ceq $sourceVersion -and
        [string]$projection.canonical_base.target -ceq 'f100' -and
        [string]$projection.source.commit -ceq ((& git -C $repo rev-parse HEAD).Trim()) -and
        [string]$projection.source.tree -ceq ((& git -C $repo rev-parse 'HEAD^{tree}').Trim()) -and
        @($projection.members).Count -gt 0 -and
        [string]$projection.member_projection_sha256 -match '^[0-9A-F]{64}$'
      ) "historical-authentication-projection-current-authorities-$sourceVersion-$target"
      $projectionChecks++
    }
  }
  $unsupported450Patch = $false
  try {
    Get-MIR43HistoricalCandidateAuthenticationProjection -Repository $repo -Target f017 -SourceVersion '4.5.1' | Out-Null
  } catch [System.Management.Automation.ParameterBindingException] {
    $unsupported450Patch = $true
  }
  Assert-MIR42CandidateBuildTest $unsupported450Patch 'historical-authentication-keeps-emergency-4-5-1-out-of-normal-evidence-route'
  $projectionChecks++
  $unsupportedFuturePatch = $false
  try {
    Get-MIR43HistoricalCandidateAuthenticationProjection -Repository $repo -Target f017 -SourceVersion '4.5.3' | Out-Null
  } catch [System.Management.Automation.ParameterBindingException] {
    $unsupportedFuturePatch = $true
  }
  Assert-MIR42CandidateBuildTest $unsupportedFuturePatch 'historical-authentication-refuses-future-4-5-3-normal-evidence-route'
  $projectionChecks++

  $writer = Join-Path $repo 'tools/commands/release/New-MIR42HistoricalPlaytestCandidate.ps1'
  $auth442Root = Join-Path $OutputRoot 'authentication-442'
  $auth452Root = Join-Path $OutputRoot 'authentication-452'
  Assert-MIR42CandidateBuildTest (
    [System.IO.Path]::GetFullPath($auth442Root) -cne [System.IO.Path]::GetFullPath($auth452Root)
  ) 'historical-authentication-fixture-output-roots-are-distinct'
  $authenticationCases = @(
    [pscustomobject][ordered]@{ label = '442'; source_version = '4.4.2'; candidate_id = 'AUTHENTICATION-CONTROL-442'; output_root = $auth442Root },
    [pscustomobject][ordered]@{ label = '452'; source_version = '4.5.2'; candidate_id = 'AUTHENTICATION-CONTROL-452'; output_root = $auth452Root },
    [pscustomobject][ordered]@{ label = '460'; source_version = '4.6.0'; candidate_id = 'AUTHENTICATION-CONTROL-460'; output_root = (Join-Path $OutputRoot 'authentication-460') },
    [pscustomobject][ordered]@{ label = '470'; source_version = '4.7.0'; candidate_id = 'AUTHENTICATION-CONTROL-470'; output_root = (Join-Path $OutputRoot 'authentication-470') }
  )
  if($SelectedSourceVersions.Count){$authenticationCases=@($authenticationCases|Where-Object {$_.source_version -cin $SelectedSourceVersions})}
  $authenticationAssertions = 0
  $authorityInputAssertions = 0
  $receiptCustodyAssertions = 0
  $authenticCandidateZipBuilds = 0
  foreach ($case in $authenticationCases) {
    $manifestRows = @(& $writer -RepoRoot $repo -Target f017 -SourceVersion ([string]$case.source_version) -CandidateId ([string]$case.candidate_id) -OutputRoot ([string]$case.output_root) -Repetitions 2 -Check)
    Assert-MIR42CandidateBuildTest ($manifestRows.Count -eq 1) "historical-authentication-fixture-manifest-count-$($case.label)"
    $manifest = $manifestRows[0]
    $manifestPath = Join-Path ([string]$case.output_root) 'manifests/f017.json'
    $archive = Join-Path $repo ([string]$manifest.distribution.path)
    Assert-MIR42CandidateBuildTest (
      (Test-Path -LiteralPath $manifestPath -PathType Leaf) -and
      (Test-Path -LiteralPath $archive -PathType Leaf) -and
      [string]$manifest.target -ceq 'f017' -and
      [string]$manifest.candidate_row.source_version -ceq [string]$case.source_version
    ) "historical-authentication-fixture-identity-$($case.label)"
    $opposingRoot = Join-Path ([string]$case.output_root) 'opposing'
    $controls = Invoke-MIR43HistoricalCurrentCandidateAuthenticationControls -Repository $repo -Archive $archive -ManifestPath $manifestPath `
      -Target f017 -SourceVersion ([string]$case.source_version) -WorkRoot $opposingRoot
    Assert-MIR42CandidateBuildTest (
      [string]$controls.status -ceq 'passed' -and
      [int]$controls.assertions -eq 4 -and
      [int]$controls.authority_input_assertions -eq 5 -and
      [int]$controls.receipt_custody_assertions -eq 6 -and
      [int]$controls.tooling_equivalence_assertions -eq $(if([string]$case.source_version -cin @('4.6.0','4.7.0')){4}else{0}) -and
      -not [bool]$controls.native_factorio -and
      -not [bool]$controls.package_materialization -and
      -not (Test-Path -LiteralPath $opposingRoot)
    ) "historical-authentication-opposing-controls-$($case.label)"
    $authenticationAssertions += [int]$controls.assertions
    $authorityInputAssertions += [int]$controls.authority_input_assertions
    $receiptCustodyAssertions += [int]$controls.receipt_custody_assertions
    $authenticCandidateZipBuilds += 2
    if ([string]$case.source_version -ceq '4.6.0') {
      $currentHistory = Read-MIR4ArchiveText -Path $archive -RelativePath 'changelog.txt'
      $currentVersion = [string]$manifest.distribution_version
      Assert-MIR42CandidateBuildTest (
        $currentHistory.StartsWith("---------------------------------------------------------------------------------------------------`nVersion: $currentVersion`n", [StringComparison]::Ordinal) -and
        $currentHistory.Contains('Restore the published 4.3, 4.4 and 4.5 changelog entries alongside the retained earlier history.') -and
        $currentHistory.Contains('Retain the research, settings, cap and save-continuity repairs included in source 4.5.2.')
      ) 'historical-authentication-accepts-current-460-enriched-history'
      $authenticationAssertions++

      # A self-consistent manifest cannot authenticate stale or changed
      # changelog bytes: the independent member projection remains binding.
      $historyOpponent = Join-Path ([string]$case.output_root) 'history-opponent'
      try {
        New-Item -ItemType Directory -Force -Path $historyOpponent | Out-Null
        $forgedArchive = Join-Path $historyOpponent ([IO.Path]::GetFileName($archive))
        $forgedManifestPath = Join-Path $historyOpponent 'forged-history.json'
        Copy-Item -LiteralPath $archive -Destination $forgedArchive
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::Open($forgedArchive, [IO.Compression.ZipArchiveMode]::Update)
        try {
          $entryPath = ([string]$manifest.authentication_projection.distribution_root) + '/changelog.txt'
          $entry = $zip.GetEntry($entryPath)
          if ($null -eq $entry) { throw '[mir42-candidate-build-test] historical-authentication-opponent-changelog-missing' }
          $entry.Delete()
          $replacement = $zip.CreateEntry($entryPath)
          $entryWriter = [IO.StreamWriter]::new($replacement.Open(), [Text.UTF8Encoding]::new($false))
          try { $entryWriter.Write("---------------------------------------------------------------------------------------------------`nVersion: 4.5.01702`n  Info:`n    - Stale historical changelog entry.`n") } finally { $entryWriter.Dispose() }
        } finally { $zip.Dispose() }
        $forgedManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100 -DateKind String
        $forgedInventory = Get-MIR4ArchiveInventory -Path $forgedArchive
        $forgedManifest.distribution.sha256 = [string]$forgedInventory.archive_sha256
        $forgedManifest.distribution.content_sha256 = [string]$forgedInventory.content_sha256
        $forgedManifest.distribution.entry_count = [int]$forgedInventory.entry_count
        $forgedManifest.candidate_row.asset.bytes = [int64](Get-Item -LiteralPath $forgedArchive).Length
        $forgedManifest.candidate_row.asset.sha256 = [string]$forgedInventory.archive_sha256
        $forgedManifest.candidate_row.content_sha256 = [string]$forgedInventory.content_sha256
        $forgedManifest.candidate_row.entry_count = [int]$forgedInventory.entry_count
        $forgedManifest.candidate_row.build_a_sha256 = [string]$forgedInventory.archive_sha256
        $forgedManifest.candidate_row.build_b_sha256 = [string]$forgedInventory.archive_sha256
        $forgedManifest.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $forgedManifest
        [IO.File]::WriteAllText($forgedManifestPath, (($forgedManifest | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
        $rejected = $false
        try {
          Read-MIR43HistoricalCurrentCandidate -Repository $repo -Archive $forgedArchive -ManifestPath $forgedManifestPath -Target f017 -SourceVersion '4.6.0' | Out-Null
        } catch {
          $rejected = $_.Exception.Message.Contains('candidate member differs: changelog.txt', [StringComparison]::Ordinal)
        }
        Assert-MIR42CandidateBuildTest $rejected 'historical-authentication-rejects-stale-460-history'
        $authenticationAssertions++
      } finally {
        if (Test-Path -LiteralPath $historyOpponent) {
          $resolvedOpponent = (Resolve-Path -LiteralPath $historyOpponent).Path
          $null = Assert-MIR4DescendantPath -Root (Join-Path $repo 'build') -Path $resolvedOpponent
          $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $resolvedOpponent
          Remove-Item -LiteralPath $resolvedOpponent -Recurse -Force
        }
      }
    }
  }
  return [pscustomobject][ordered]@{
    archive_source_versions = @($authenticationCases.source_version)
    authority_projection_checks = $projectionChecks
    authentication_assertions = $authenticationAssertions
    authority_input_assertions = $authorityInputAssertions
    receipt_custody_assertions = $receiptCustodyAssertions
    authentic_candidate_zip_builds = $authenticCandidateZipBuilds
    factorio_processes = 0
  }
}

function New-MIR4TargetPackage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$CandidateId,
    [string]$SourceVersion,
    [string]$DistributionVersion,
    [string]$OutputRoot,
    [string]$ArchiveRelativePath=''
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
  if (-not [string]::IsNullOrWhiteSpace($ArchiveRelativePath)) {
    $archive = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath $ArchiveRelativePath
  }
  Write-MIR4DeterministicRawTreeArchive -SourceRoot $tree -EntryRoot ([string]$identity.distribution_root) -OutputPath $archive -ContainmentRoot $OutputRoot
  $inventory = Get-MIR4ArchiveInventory -Path $archive
  $result = [pscustomobject][ordered]@{
    target = $Target
    candidate_id = $CandidateId
    source_version = $SourceVersion
    distribution_version = $DistributionVersion
    tree_path = $tree
    archive_path = $archive
    archive_sha256 = [string]$inventory.archive_sha256
    content_sha256 = [string]$inventory.content_sha256
    entry_count = [int]$inventory.entry_count
    record_sha256 = ''
  }
  $result.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $result
  return $result
}

. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42CandidateBuild.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42IndependentEvidenceRehash.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')

function Test-MIR42RetainedMaterializerReceipts {
  param([Parameter(Mandatory)][string]$OutputRoot)
  . (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
  foreach ($target in @('f210','f200')) {
    $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target $target -SourceVersion '4.2.1'
    $candidateId = 'RECEIPT'
    $stageRoot = Join-Path $OutputRoot "$target/$candidateId"
    New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
    $marker = Join-Path $stageRoot 'preserve-until-admitted.txt'
    [IO.File]::WriteAllText($marker, 'unique controlled staging state')
    $assetRelative = "assets/$target/$($identity.package_name)"
    $assetPath = Join-Path $OutputRoot $assetRelative
    foreach ($badPath in @(('../'+$identity.package_name), $assetPath, 'assets/wrong.zip', "$target/$candidateId/$($identity.package_name)")) {
      $rejected = $false
      try {
        & $script:mir42CandidateRealMaterializer -RepoRoot $repo -Target $target -CandidateId $candidateId -SourceVersion '4.2.1' -OutputRoot $OutputRoot -ArchiveRelativePath $badPath | Out-Null
      } catch {
        $rejected = $_.Exception.Message -match 'Unsafe MIR 4 artifact-relative path|mir4-target-materializer-archive-filename|mir4-target-materializer-retained-archive-in-staging'
      }
      Assert-MIR42CandidateBuildTest ($rejected -and (Test-Path -LiteralPath $marker) -and -not (Test-Path -LiteralPath $assetPath)) "retained-materializer-refuses-unsafe-destination-before-staging-$target-$badPath"
      $script:mir42CandidateReceiptAssertions++
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $assetPath) | Out-Null
    foreach ($collision in @($assetPath, "$assetPath.new")) {
      [IO.File]::WriteAllText($collision, 'unique controlled asset state')
      $collisionHash = Get-MIR4Sha256File -Path $collision
      $rejected = $false
      try {
        & $script:mir42CandidateRealMaterializer -RepoRoot $repo -Target $target -CandidateId $candidateId -SourceVersion '4.2.1' -OutputRoot $OutputRoot -ArchiveRelativePath $assetRelative | Out-Null
      } catch { $rejected = $_.Exception.Message -ceq '[mir4-target-materializer-retained-archive-collision]' }
      Assert-MIR42CandidateBuildTest ($rejected -and (Test-Path -LiteralPath $marker) -and (Get-MIR4Sha256File -Path $collision) -ceq $collisionHash) "retained-materializer-preserves-collision-before-staging-$target"
      $script:mir42CandidateReceiptAssertions++
      Remove-Item -LiteralPath $collision
    }
    $result = & $script:mir42CandidateRealMaterializer -RepoRoot $repo -Target $target -CandidateId $candidateId -SourceVersion '4.2.1' -OutputRoot $OutputRoot -ArchiveRelativePath $assetRelative
    Assert-MIR42CandidateBuildTest ($result.archive_path -ceq [IO.Path]::GetFullPath($assetPath) -and (Test-MIR4BootstrapRecordHash -Record $result)) "retained-materializer-original-receipt-$target"
    $script:mir42CandidateReceiptAssertions++
    $originalHash = [string]$result.record_sha256
    $receiptPath = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath "materializations/$target.json"
    Write-MIR4BootstrapRecord -Record $result -Path $receiptPath | Out-Null
    Remove-MIR4BuildTree -OutputRoot $OutputRoot -Path (Split-Path -Parent $result.tree_path)
    $consumed = Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $assetPath -ReceiptPath $receiptPath -Target $target
    Assert-MIR42CandidateBuildTest ($consumed.receipt.record_sha256 -ceq $originalHash -and $consumed.receipt.archive_sha256 -ceq (Get-MIR4Sha256File -Path $assetPath) -and -not (Test-Path -LiteralPath $stageRoot) -and @(Get-ChildItem -LiteralPath $OutputRoot -Recurse -File -Filter $identity.package_name).Count -eq 1) "retained-materializer-native-reader-after-staging-retirement-$target"
    $script:mir42CandidateReceiptAssertions++
  }
}

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
$admittedCandidateSources = @('4.2.0','4.2.1','4.2.2','4.2.3','4.3.0','4.3.1','4.4.0','4.4.1','4.4.2','4.5.0','4.5.1','4.5.2','4.6.0','4.7.0')
foreach ($entryPoint in @(
  'tools/commands/release/New-MIR42FourTargetCandidate.ps1',
  'tools/commands/release/New-MIR42HistoricalPlaytestCandidate.ps1'
)) {
  $entryTokens = $null
  $entryErrors = $null
  $entryAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $entryPoint), [ref]$entryTokens, [ref]$entryErrors)
  $sourceParameter = @($entryAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -ceq 'SourceVersion' })
  $sourceValues = if ($sourceParameter.Count -eq 1) {
    @(
      $sourceParameter[0].Attributes |
        Where-Object { $_.TypeName.FullName -ceq 'ValidateSet' } |
        ForEach-Object { $_.PositionalArguments | ForEach-Object { [string]$_.Value } }
    )
  } else { @() }
  Assert-MIR42CandidateBuildTest (
    @($entryErrors).Count -eq 0 -and $sourceParameter.Count -eq 1 -and
    ($sourceValues -join '|') -ceq ($admittedCandidateSources -join '|')
  ) "candidate-entrypoint-current-source-admission-$([IO.Path]::GetFileNameWithoutExtension($entryPoint))"
  if ($entryPoint.EndsWith('New-MIR42HistoricalPlaytestCandidate.ps1', [StringComparison]::Ordinal)) {
    $identityHelpers = @($entryAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Set-MIR42HistoricalBaselinePackageIdentity'}, $true))
    Assert-MIR42CandidateBuildTest ($identityHelpers.Count -eq 1) 'historical-baseline-projection-helper'
    . ([scriptblock]::Create($identityHelpers[0].Extent.Text))
    $baseMaterializers = @($entryAst.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'New-MIR4TargetPackage' }, $true))
    Assert-MIR42CandidateBuildTest (
      $baseMaterializers.Count -eq 1 -and $baseMaterializers[0].Extent.Text -match '-SourceVersion\s+\$baselineSourceVersion'
    ) 'historical-current-source-builds-from-its-minor-baseline'
  }
}
$current440 = Resolve-MIR4CurrentPackageMetadataSourceVersion -SourceVersion '4.4.0'
Assert-MIR42CandidateBuildTest (
  [string]$current440.source_version -ceq '4.4.0' -and [int]$current440.source_minor -eq 4 -and [int]$current440.source_patch -eq 0
) 'current-package-metadata-admits-4-4-identity'
$current441 = Resolve-MIR4CurrentPackageMetadataSourceVersion -SourceVersion '4.4.1'
Assert-MIR42CandidateBuildTest (
  [string]$current441.source_version -ceq '4.4.1' -and [int]$current441.source_minor -eq 4 -and [int]$current441.source_patch -eq 1
) 'current-package-metadata-admits-4-4-1-identity'
$current442 = Resolve-MIR4CurrentPackageMetadataSourceVersion -SourceVersion '4.4.2'
Assert-MIR42CandidateBuildTest (
  [string]$current442.source_version -ceq '4.4.2' -and [int]$current442.source_minor -eq 4 -and [int]$current442.source_patch -eq 2
) 'current-package-metadata-admits-4-4-2-identity'
$current450 = Resolve-MIR4CurrentPackageMetadataSourceVersion -SourceVersion '4.5.0'
Assert-MIR42CandidateBuildTest (
  [string]$current450.source_version -ceq '4.5.0' -and [int]$current450.source_minor -eq 5 -and [int]$current450.source_patch -eq 0
) 'current-package-metadata-admits-4-5-identity'
$current443Rejected = $false
try { Resolve-MIR4CurrentPackageMetadataSourceVersion -SourceVersion '4.4.3' | Out-Null }
catch { $current443Rejected = $_.Exception.Message -ceq '[mir4-current-package-metadata-source-version]' }
Assert-MIR42CandidateBuildTest $current443Rejected 'current-package-metadata-refuses-unapproved-4-4-patch'
$current451 = Resolve-MIR4CurrentPackageMetadataSourceVersion -SourceVersion '4.5.1'
Assert-MIR42CandidateBuildTest (
  [string]$current451.source_version -ceq '4.5.1' -and [int]$current451.source_minor -eq 5 -and [int]$current451.source_patch -eq 1
) 'current-package-metadata-admits-4-5-1-identity'
$current452 = Resolve-MIR4CurrentPackageMetadataSourceVersion -SourceVersion '4.5.2'
Assert-MIR42CandidateBuildTest (
  [string]$current452.source_version -ceq '4.5.2' -and [int]$current452.source_minor -eq 5 -and [int]$current452.source_patch -eq 2
) 'current-package-metadata-admits-4-5-2-identity'
$current460 = Resolve-MIR4CurrentPackageMetadataSourceVersion -SourceVersion '4.6.0'
Assert-MIR42CandidateBuildTest (
  [string]$current460.source_version -ceq '4.6.0' -and [int]$current460.source_minor -eq 6 -and [int]$current460.source_patch -eq 0
) 'current-package-metadata-admits-4-6-identity'
$current470 = Resolve-MIR4CurrentPackageMetadataSourceVersion -SourceVersion '4.7.0'
Assert-MIR42CandidateBuildTest (
  [string]$current470.source_version -ceq '4.7.0' -and [int]$current470.source_minor -eq 7 -and [int]$current470.source_patch -eq 0
) 'current-package-metadata-admits-4-7-development-identity'
$current453Rejected = $false
try { Resolve-MIR4CurrentPackageMetadataSourceVersion -SourceVersion '4.5.3' | Out-Null }
catch { $current453Rejected = $_.Exception.Message -ceq '[mir4-current-package-metadata-source-version]' }
Assert-MIR42CandidateBuildTest $current453Rejected 'current-package-metadata-refuses-unapproved-4-5-3-patch'

$root = Join-Path $repo ('build/test-results/mir42-four-target-candidate-' + [guid]::NewGuid().ToString('N'))
$partialRoot = $root + '-partial'
$historicalRoot = $root + '-historical'
$nineRoot = $root + '-nine'
$identityRoot = $root + '-identity'
$patchRoot = $root + '-patch'
$receiptRoot = $root + '-receipts'
$historicalAuthenticationRoot = $root + '-historical-authentication'
$historicalRecordHashes = @{}
foreach ($target in @('f017','f016','f015','f014','f013')) {
  $historicalRecordHashes[$target] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo "targets/historical/$target/target.json")).Hash
}
try {
  $historicalIdentityChecks = Test-MIR43HistoricalBaselineProjection -OutputRoot (Join-Path $identityRoot 'historical-baseline')
  if ($HistoricalIdentityProjectionOnly) {
    [pscustomobject]@{status='MIR-4.3-HISTORICAL-IDENTITY-PROJECTION-CONTROLS-PASSED';checks=$historicalIdentityChecks;targets=5;source_versions=@('4.2.2','4.3.0','4.3.1','4.4.0','4.4.1','4.4.2','4.5.0','4.5.1','4.5.2','4.6.0','4.7.0');engine_runs=0;actual_candidate_zip_builds=0}
    return
  }
  if ($HistoricalAuthenticationOnly) {
    $historicalAuthentication = Test-MIR43HistoricalCandidateAuthentication -OutputRoot $historicalAuthenticationRoot -SelectedSourceVersions $HistoricalAuthenticationSourceVersions
    [pscustomobject][ordered]@{
      status = 'MIR-4.3-HISTORICAL-CANDIDATE-AUTHENTICATION-CONTROLS-PASSED'
      targets = 5
      source_versions = @($historicalAuthentication.archive_source_versions)
      authority_projection_checks = [int]$historicalAuthentication.authority_projection_checks
      authentication_assertions = [int]$historicalAuthentication.authentication_assertions
      authority_input_assertions = [int]$historicalAuthentication.authority_input_assertions
      receipt_custody_assertions = [int]$historicalAuthentication.receipt_custody_assertions
      authentic_candidate_zip_builds = [int]$historicalAuthentication.authentic_candidate_zip_builds
      factorio_processes = [int]$historicalAuthentication.factorio_processes
      qualification = 'not-performed'
    }
    return
  }
  if ($MaterializerReceiptContractsOnly) {
    Test-MIR42RetainedMaterializerReceipts -OutputRoot $receiptRoot
    [pscustomobject]@{status='MIR-4.2.1-RETAINED-MATERIALIZER-RECEIPTS-PASSED';receipt_assertions=$script:mir42CandidateReceiptAssertions;canonical_packages=2;native_candidate_readers=2;factorio_processes=0;qualification='not-performed'}
    return
  }
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
  $performanceDescriptors=@(Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SourceVersion '4.2.3')
  $performanceVersions=@('4.2.21003','4.2.20003','4.2.11003','4.2.10003','4.2.01703','4.2.01603','4.2.01503','4.2.01403','4.2.01303')
  Assert-MIR42CandidateBuildTest (($performanceDescriptors.target-join'|')-ceq($patchDescriptors.target-join'|')-and($performanceDescriptors.distribution_version-join'|')-ceq($performanceVersions-join'|')-and@($performanceDescriptors|Where-Object{[string]$_.source_version-cne'4.2.3'-or[bool]$_.public_output_authorized-or[bool]$_.publication_authorized}).Count-eq0) '423-default-selects-nine-private-exact-identities'
  $performanceFourRejected=$false
  try{Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SourceVersion '4.2.3' -SelectedTargets @('f210','f200','f110','f100')|Out-Null}catch{$performanceFourRejected=$_.Exception.Message-match'mir42-candidate-target-selection-unsupported'}
  Assert-MIR42CandidateBuildTest $performanceFourRejected '423-rejects-four-target-selection'
  $mir43Contracts = @(
    [pscustomobject][ordered]@{ source_version='4.3.0'; schema=5; source_patch='00' },
    [pscustomobject][ordered]@{ source_version='4.3.1'; schema=6; source_patch='01' },
    [pscustomobject][ordered]@{ source_version='4.4.0'; schema=7; source_patch='00' },
    [pscustomobject][ordered]@{ source_version='4.4.1'; schema=8; source_patch='01' },
    [pscustomobject][ordered]@{ source_version='4.4.2'; schema=9; source_patch='02' },
    [pscustomobject][ordered]@{ source_version='4.5.0'; schema=10; source_patch='00' },
    [pscustomobject][ordered]@{ source_version='4.5.1'; schema=11; source_patch='01' },
    [pscustomobject][ordered]@{ source_version='4.5.2'; schema=12; source_patch='02' },
    [pscustomobject][ordered]@{ source_version='4.6.0'; schema=13; source_patch='00' },
    [pscustomobject][ordered]@{ source_version='4.7.0'; schema=14; source_patch='00' }
  )
  $mir43DescriptorSets = [ordered]@{}
  $targetCodes = @('210','200','110','100','017','016','015','014','013')
  foreach ($mir43Contract in $mir43Contracts) {
    $sourceVersion = [string]$mir43Contract.source_version
    $descriptors = @(Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SourceVersion $sourceVersion)
    $sourceIdentity=[version]$sourceVersion
    $expectedVersions = @($targetCodes | ForEach-Object { "4.$($sourceIdentity.Minor).$($_)$($mir43Contract.source_patch)" })
    $mir43DescriptorSets[$sourceVersion] = $descriptors
    Assert-MIR42CandidateBuildTest (
      ($descriptors.target -join '|') -ceq ($patchDescriptors.target -join '|') -and
      ($descriptors.distribution_version -join '|') -ceq ($expectedVersions -join '|') -and
      @($descriptors | Where-Object {
        [string]$_.source_version -cne $sourceVersion -or [bool]$_.public_output_authorized -or [bool]$_.publication_authorized
      }).Count -eq 0
    ) "$sourceVersion-default-selects-nine-private-exact-identities"
    $fourRejected = $false
    try { Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SourceVersion $sourceVersion -SelectedTargets @('f210','f200','f110','f100') | Out-Null } catch { $fourRejected = $_.Exception.Message -match 'mir42-candidate-target-selection-unsupported' }
    Assert-MIR42CandidateBuildTest $fourRejected "$sourceVersion-rejects-four-target-selection"
    for ($i = 0; $i -lt $expectedVersions.Count; $i++) {
      $identity = Get-MIR42ReleaseTargetIdentity -RepoRoot $repo -Target ([string]$descriptors[$i].target) -SourceVersion $sourceVersion
      Assert-MIR42CandidateBuildTest (
        [string]$identity.source_version -ceq $sourceVersion -and
        [string]$identity.distribution_version -ceq $expectedVersions[$i] -and
        [string]$identity.distribution_root -ceq "more-infinite-research_$($expectedVersions[$i])" -and
        [string]$identity.package_name -ceq "more-infinite-research_$($expectedVersions[$i]).zip"
      ) "$sourceVersion-release-target-identity-$i"
    }
  }
  foreach ($schemaVersion in @(1,2,3,4,5,6,7,8,9,10,11,12,13,14)) {
    $versionContract = Get-MIR42CandidateConstructionVersionContract -RepoRoot $repo -Manifest ([pscustomobject]@{schema=$schemaVersion;kind="MIR42FourTargetDeterministicCandidateManifestV$schemaVersion"})
    $expectedSource = @('4.2.0','4.2.1','4.2.2','4.2.3','4.3.0','4.3.1','4.4.0','4.4.1','4.4.2','4.5.0','4.5.1','4.5.2','4.6.0','4.7.0')[$schemaVersion-1]
    Assert-MIR42CandidateBuildTest ($versionContract.source_version -ceq $expectedSource -and $versionContract.requires_nine_targets -eq ($schemaVersion -ge 2) -and (Test-Path -LiteralPath $versionContract.schema_path -PathType Leaf)) "construction-version-contract-$schemaVersion"
  }
  $v13Predecessor = Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion '4.6.0'
  Assert-MIR42CandidateBuildTest ($v13Predecessor.source_version -ceq '4.5.2' -and $v13Predecessor.source_tag -ceq 'v4.5.2' -and $v13Predecessor.release_id -eq 416333929 -and $v13Predecessor.commit -ceq '8e4de4be0f24a3da514ad39179d5ce254459788d' -and $v13Predecessor.tree -ceq '46e1787363671e1209b819dcc0b5360fc9433fc1' -and $v13Predecessor.manifest_sha256 -ceq 'BD8AE26FE457334C6856591BB09D286F32A7D1D7DB6C596CB6CB7D463F1A8493') 'v13-construction-binds-published-452-predecessor'
  $v13Selection = Get-MIR42EngineMaintenanceSelection -CandidateSourceVersion '4.6.0' -RequestedPredecessorSourceVersion '4.5.2'
  Assert-MIR42CandidateBuildTest ($v13Selection.source_version -ceq '4.5.2' -and $v13Selection.reader_version -ceq '4.6.0') 'v13-engine-selection-binds-published-452-predecessor'
  $v14Predecessor = Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion '4.7.0'
  Assert-MIR42CandidateBuildTest (
    $v14Predecessor.source_version -ceq '4.6.0' -and $v14Predecessor.source_patch -eq 0 -and
    $v14Predecessor.release_id -eq 418350860 -and $v14Predecessor.asset_count -eq 11 -and
    $v14Predecessor.commit -ceq '9d6a9de1d77ca526da78428f8de52d5c61f9f55b' -and
    $v14Predecessor.tree -ceq 'da6bafdd17c6246c90edad3fef7a6ba6166ac920' -and
    $v14Predecessor.tag_object -ceq 'cd67ea9b93415819444c2bdf7f25873a0b906c6c' -and
    $v14Predecessor.manifest_sha256 -ceq '543F8D525248F984B14E181AA251C4D3288A6E2FE5FB7158A6F46D1B06B198D2'
  ) 'v14-predecessor-is-consolidated-460-publication'
  $v14Selection = Get-MIR42EngineMaintenanceSelection -CandidateSourceVersion '4.7.0'
  Assert-MIR42CandidateBuildTest ($v14Selection.source_version -ceq '4.6.0' -and $v14Selection.reader_version -ceq '4.7.0') 'v14-engine-selection-deduplicates-immediate-and-prior-minor-predecessor'
  foreach ($wrongPredecessor in @('4.4.2','4.5.2','4.6.1','4.7.0')) {
    $rejected = $false
    try { Get-MIR42EngineMaintenanceSelection -CandidateSourceVersion '4.7.0' -RequestedPredecessorSourceVersion $wrongPredecessor | Out-Null } catch { $rejected = $_.Exception.Message -ceq '[mir42-engine-maintenance-predecessor-selection]' }
    Assert-MIR42CandidateBuildTest $rejected ('v14-engine-selection-rejects-unselected-predecessor-'+$wrongPredecessor)
  }
  $v14Pinned = Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath (Join-Path $repo 'fixtures/release-inputs/mir470-published-460-consolidated-construction.json') -CandidateSourceVersion '4.7.0'
  Assert-MIR42CandidateBuildTest (
    $v14Pinned.bytes -eq 5014 -and (Test-MIR4BootstrapRecordHash -Record $v14Pinned.manifest) -and
    $v14Pinned.manifest.source.commit -ceq $v14Predecessor.commit -and
    $v14Pinned.manifest.source.tree -ceq $v14Predecessor.tree -and
    $v14Pinned.manifest.qualification -ceq 'not-performed' -and
    $v14Pinned.manifest.signing -ceq 'not-performed' -and -not $v14Pinned.manifest.publication_authorized
  ) 'v14-pinned-construction-retains-original-honest-boundaries'
  # Synthetic API rows exercise the actual production custody reader. They do
  # not replace the retained public-download readback or make an engine pass.
  $v14AssetId = 1
  $v14Assets = @($v14Predecessor.public_auxiliaries | ForEach-Object { [pscustomobject]@{id=$v14AssetId++;name=$_.name;state='uploaded';size=$_.bytes;digest=('sha256:'+$_.sha256).ToLowerInvariant()} })
  foreach ($row in $v14Pinned.manifest.targets) {
    $v14Assets += [pscustomobject]@{id=$v14AssetId++;name=('more-infinite-research_'+$row.distribution_version+'.zip');state='uploaded';size=$row.asset.bytes;digest=('sha256:'+$row.asset.sha256).ToLowerInvariant()}
  }
  $v14Release = [pscustomobject]@{id=$v14Predecessor.release_id;tag_name='v4.6.0';target_commitish=$v14Predecessor.commit;draft=$false;prerelease=$false;immutable=$false;assets=$v14Assets}
  $v14Rows = @(Assert-MIR42PublishedMaintenancePredecessorMetadata -PinnedManifest $v14Pinned -ReleaseMetadata $v14Release -CandidateSourceVersion '4.7.0')
  Assert-MIR42CandidateBuildTest ($v14Rows.Count -eq 9 -and ($v14Rows.target -join '|') -ceq ($patchDescriptors.target -join '|')) 'v14-custody-reader-accepts-all-nine-consolidated-assets'
  foreach ($tamper in @('withdrawn-release','superseded-metadata-release','changed-commit','changed-archive','changed-checksums','changed-signature','surplus-manifest')) {
    $badRelease = $v14Release | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    switch ($tamper) {
      'withdrawn-release' { $badRelease.id=416765779 }
      'superseded-metadata-release' { $badRelease.id=417286963 }
      'changed-commit' { $badRelease.target_commitish=('0'*40) }
      'changed-archive' { $badRelease.assets[2].digest=('sha256:'+('0'*64)) }
      'changed-checksums' { $badRelease.assets[0].digest=('sha256:'+('0'*64)) }
      'changed-signature' { $badRelease.assets[1].digest=('sha256:'+('0'*64)) }
      'surplus-manifest' { $badRelease.assets += [pscustomobject]@{id=999;name=$v14Predecessor.manifest_name;state='uploaded';size=$v14Pinned.bytes;digest=('sha256:'+$v14Pinned.sha256).ToLowerInvariant()} }
    }
    $rejected=$false
    try { Assert-MIR42PublishedMaintenancePredecessorMetadata -PinnedManifest $v14Pinned -ReleaseMetadata $badRelease -CandidateSourceVersion '4.7.0' | Out-Null } catch { $rejected=$_.Exception.Message -match '^\[mir42-maintenance-predecessor-' }
    Assert-MIR42CandidateBuildTest $rejected ('v14-custody-reader-refuses-'+$tamper)
  }
  $v14ChangedPath = Join-Path $identityRoot 'changed-460-construction.json'
  $v14ChangedBytes = [IO.File]::ReadAllBytes($v14Pinned.path)
  $v14ChangedBytes[0] = [byte][char]'['
  [IO.File]::WriteAllBytes($v14ChangedPath,$v14ChangedBytes)
  $rejected=$false
  try { Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath $v14ChangedPath -CandidateSourceVersion '4.7.0' | Out-Null } catch { $rejected=$_.Exception.Message -ceq '[mir42-maintenance-predecessor-frozen-manifest]' }
  Assert-MIR42CandidateBuildTest $rejected 'v14-predecessor-refuses-changed-raw-bytes-before-parsing'
  foreach ($wrongPredecessor in @('4.4.2','4.5.0','4.5.1','4.5.3','4.6.0')) {
    $rejected = $false
    try { Get-MIR42EngineMaintenanceSelection -CandidateSourceVersion '4.6.0' -RequestedPredecessorSourceVersion $wrongPredecessor | Out-Null } catch { $rejected = $_.Exception.Message -ceq '[mir42-engine-maintenance-predecessor-selection]' }
    Assert-MIR42CandidateBuildTest $rejected ('v13-engine-selection-rejects-non-immediate-predecessor-'+$wrongPredecessor)
  }

  foreach ($badContract in @(
    [pscustomobject]@{schema=15;kind='MIR42FourTargetDeterministicCandidateManifestV15'},
    [pscustomobject]@{schema=10;kind='MIR42FourTargetDeterministicCandidateManifestV9'},
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
    Assert-MIR42CandidateBuildTest ($writtenReadme -ceq "MIR $($patchVersions[$i]), source 4.2.1.`n`n$readme") "patch-readme-identity-and-preserved-prose-$i"
    $firstHashes = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion $patchVersions[$i]
    $secondHashes = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
    Assert-MIR42CandidateBuildTest (($firstHashes -join '|') -ceq ($secondHashes -join '|')) "patch-metadata-idempotence-$i"
    # A historical-source construction prepends its own identity without
    # rewriting the authored entry for the later source patch.
    $target = [string]$patchDescriptors[$i].target
    $presentation = if ($i -lt 4) { "source/presentation/$target" } else { "source/presentation/historical/$target" }
    $authoredHistory = [IO.File]::ReadAllText((Join-Path $repo "$presentation/changelog.txt.template")).Replace("`r`n", "`n")
    $authoredVersion = [regex]::Match($authoredHistory, '(?m)^Version:\s*(\S+)')
    [IO.File]::WriteAllText((Join-Path $tree 'changelog.txt'), $authoredHistory, $utf8)
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion $patchVersions[$i]
    $writtenAuthoredHistory = [IO.File]::ReadAllText((Join-Path $tree 'changelog.txt'))
    Assert-MIR42CandidateBuildTest ($authoredVersion.Success -and
      $writtenAuthoredHistory.StartsWith("---------------------------------------------------------------------------------------------------`nVersion: $($patchVersions[$i])`n", [StringComparison]::Ordinal) -and
      $writtenAuthoredHistory.EndsWith($authoredHistory, [StringComparison]::Ordinal)) "patch-authored-prior-changelog-preserved-$i"
  }
  foreach ($mir43Contract in $mir43Contracts) {
    $sourceVersion = [string]$mir43Contract.source_version
    $sourceIdentity = [version]$sourceVersion
    $distributionVersion = [string](New-MIR4DistributionIdentityProjection -DistributionTargetCode '210' -SourceMinor $sourceIdentity.Minor -SourcePatch $sourceIdentity.Build).distribution_version
    $baselineVersion = [string](New-MIR4DistributionIdentityProjection -DistributionTargetCode '210' -SourceMinor $sourceIdentity.Minor -SourcePatch 0).distribution_version
    # Each source identity starts from its own baseline package. Reusing an
    # earlier source's rewritten info/readme would turn an invalid input into
    # an apparent later-source maintenance patch.
    $mir43IdentityTree = Join-Path $identityRoot ("mir43-private-identity-" + $sourceVersion.Replace('.', '-'))
    New-Item -ItemType Directory -Force -Path $mir43IdentityTree | Out-Null
    # Current metadata writers require an explicit exact engine floor. Keep
    # this synthetic identity fixture subject to the same input contract.
    $identityBase = if ($sourceVersion -ceq '4.7.0') { 'base >= 2.1.23' } elseif ($sourceVersion -ceq '4.6.0') { 'base >= 2.1.21' } else { 'base' }
    $mir43Info = [ordered]@{ name='more-infinite-research'; version=$baselineVersion; factorio_version='2.1'; dependencies=@($identityBase); title='Preserved authored title' }
    [IO.File]::WriteAllText((Join-Path $mir43IdentityTree 'info.json'), ($mir43Info | ConvertTo-Json -Depth 20), $utf8)
    [IO.File]::WriteAllText((Join-Path $mir43IdentityTree 'changelog.txt'), "---------------------------------------------------------------------------------------------------`nVersion: $baselineVersion`n  Changes:`n    - Preserved historical entry.`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $mir43IdentityTree 'README.md'), "# Preserved authored README`n", $utf8)
    Write-MIR4PrivatePatchPackageIdentity -Tree $mir43IdentityTree -DistributionVersion $distributionVersion -SourceVersion $sourceVersion
    $mir43InfoAfter = Get-Content -Raw -LiteralPath (Join-Path $mir43IdentityTree 'info.json') | ConvertFrom-Json -Depth 20
    $mir43Readme = [IO.File]::ReadAllText((Join-Path $mir43IdentityTree 'README.md'))
    Assert-MIR42CandidateBuildTest (
      [string]$mir43InfoAfter.version -ceq $distributionVersion -and
      $mir43Readme.StartsWith("MIR $distributionVersion, source $sourceVersion.`n`n", [StringComparison]::Ordinal)
    ) "$sourceVersion-private-package-identity-is-explicit"
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
  # Exercise the existing writer and consumed envelope readers for the next
  # maintenance cut. These metadata rows are not built or qualified packages.
  $currentDescriptors=@(Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SourceVersion '4.2.2')
  $currentVersions=@('4.2.21002','4.2.20002','4.2.11002','4.2.10002','4.2.01702','4.2.01602','4.2.01502','4.2.01402','4.2.01302')
  Assert-MIR42CandidateBuildTest (($currentDescriptors.target-join'|')-ceq($patchDescriptors.target-join'|')-and($currentDescriptors.distribution_version-join'|')-ceq($currentVersions-join'|')) '422-default-selects-nine-exact-identities'
  for($i=0;$i-lt$currentVersions.Count;$i++){
    $currentIdentity=Get-MIR42ReleaseTargetIdentity -RepoRoot $repo -Target $currentDescriptors[$i].target -SourceVersion '4.2.2'
    Assert-MIR42CandidateBuildTest ($currentIdentity.source_version-ceq'4.2.2'-and$currentIdentity.distribution_version-ceq$currentVersions[$i]-and$currentIdentity.package_name-ceq("more-infinite-research_"+$currentVersions[$i]+'.zip')) "422-release-identity-$i"
    $target = [string]$currentDescriptors[$i].target
    $presentation = if ($i -lt 4) { "source/presentation/$target" } else { "source/presentation/historical/$target" }
    $authoredHistory = [IO.File]::ReadAllText((Join-Path $repo "$presentation/changelog.txt.template")).Replace("`r`n", "`n")
    $authoredVersion = [regex]::Match($authoredHistory, '(?m)^Version:\s*(\S+)')
    # The V3 fixture remains bound to 4.2.2.  Every retained template also
    # preserves its exact authored published head; constructed 4.2.2 metadata is
    # separately bound above.
    $admittedAuthoredVersions = @(
      [string]$currentIdentity.distribution_version,
      [string](Get-MIR42ReleaseTargetIdentity -RepoRoot $repo -Target $target -SourceVersion '4.5.2').distribution_version,
      [string](Get-MIR42ReleaseTargetIdentity -RepoRoot $repo -Target $target -SourceVersion '4.6.0').distribution_version
    )
    Assert-MIR42CandidateBuildTest ($authoredVersion.Success -and ($admittedAuthoredVersions -ccontains [string]$authoredVersion.Groups[1].Value)) "422-authored-current-changelog-version-$i"
  }
  $rejected=$false
  try{Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SourceVersion '4.2.2' -SelectedTargets @('f210','f200','f110','f100')|Out-Null}catch{$rejected=$_.Exception.Message-match'mir42-candidate-target-selection-unsupported'}
  Assert-MIR42CandidateBuildTest $rejected '422-rejects-four-target-selection'
  $currentPreflight=$schemaPreflight|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $currentPreflight.target_authority=@($currentDescriptors|Select-Object target,target_id,source_version,distribution_version)
  $currentRows=@(foreach($d in $currentDescriptors){[pscustomobject]@{target=$d.target;distribution_version=$d.distribution_version;asset=@{path="assets/$($d.target)/more-infinite-research_$($d.distribution_version).zip";bytes=1;sha256=('A'*64)};content_sha256=('B'*64);entry_count=1}})
  $currentRoot=Join-Path $identityRoot 'schema-422';New-Item -ItemType Directory -Path $currentRoot|Out-Null
  $currentManifest=Write-MIR42FourTargetManifest -OutputRoot $currentRoot -Preflight $currentPreflight -Rows $currentRows -Failures @()
  $performancePreflight=$schemaPreflight|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $performancePreflight.target_authority=@($performanceDescriptors|Select-Object target,target_id,source_version,distribution_version)
  $performanceRows=@(foreach($d in $performanceDescriptors){[pscustomobject]@{target=$d.target;distribution_version=$d.distribution_version;asset=@{path="assets/$($d.target)/more-infinite-research_$($d.distribution_version).zip";bytes=1;sha256=('A'*64)};content_sha256=('B'*64);entry_count=1}})
  $performanceRoot=Join-Path $identityRoot 'schema-423';New-Item -ItemType Directory -Path $performanceRoot|Out-Null
  $performanceManifest=Write-MIR42FourTargetManifest -OutputRoot $performanceRoot -Preflight $performancePreflight -Rows $performanceRows -Failures @()
  Assert-MIR42CandidateBuildTest ($performanceManifest.schema-eq4-and$performanceManifest.kind-ceq'MIR42FourTargetDeterministicCandidateManifestV4'-and$performanceManifest.status-ceq'private-deterministic-nine-target-candidate-built-unqualified'-and(Test-MIR4BootstrapRecordHash -Record $performanceManifest)) '423-writer-selects-v4-nine-target-private-boundary'
  foreach ($mir43Contract in $mir43Contracts) {
    $sourceVersion = [string]$mir43Contract.source_version
    $sourceIdentity = [version]$sourceVersion
    $descriptors = @($mir43DescriptorSets[$sourceVersion])
    $mir43Preflight = $schemaPreflight | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    $mir43Preflight.target_authority = @($descriptors | Select-Object target,target_id,source_version,distribution_version)
    $mir43Rows = @(
      foreach ($descriptor in $descriptors) {
        [pscustomobject]@{
          target = [string]$descriptor.target
          distribution_version = [string]$descriptor.distribution_version
          asset = [ordered]@{ path="assets/$($descriptor.target)/more-infinite-research_$($descriptor.distribution_version).zip"; bytes=1; sha256=('A'*64) }
          content_sha256=('B'*64)
          entry_count=1
        }
      }
    )
    $mir43Root = Join-Path $identityRoot ("schema-" + $sourceVersion.Replace('.',''))
    New-Item -ItemType Directory -Force -Path $mir43Root | Out-Null
    $mir43Manifest = Write-MIR42FourTargetManifest -OutputRoot $mir43Root -Preflight $mir43Preflight -Rows $mir43Rows -Failures @()
    $mir43VersionContract = Get-MIR42CandidateConstructionVersionContract -RepoRoot $repo -Manifest $mir43Manifest
    Assert-MIR42CandidateBuildTest (
      [int]$mir43Manifest.schema -eq [int]$mir43Contract.schema -and
      [string]$mir43Manifest.kind -ceq "MIR42FourTargetDeterministicCandidateManifestV$($mir43Contract.schema)" -and
      [string]$mir43VersionContract.source_version -ceq $sourceVersion -and
      $mir43VersionContract.requires_nine_targets -and
      (Test-MIR4BootstrapRecordHash -Record $mir43Manifest) -and
      (Test-MIR42CandidateSchema -Json (Get-Content -Raw -LiteralPath (Join-Path $mir43Root 'candidate-manifest.json')) -SchemaPath $mir43VersionContract.schema_path)
    ) "$sourceVersion-writer-selects-current-nine-target-schema"
    if ($sourceVersion -ceq '4.6.0') {
      Test-MIR460ManifestIdentityOpponents -Manifest $mir43Manifest -SchemaPath $mir43VersionContract.schema_path
    }
    # 4.5.1 and 4.5.2 retain their established construction-only boundary;
    # 4.6/4.7 construction admission does not imply downstream qualification.
    if ($sourceVersion -cnotin @('4.5.1','4.5.2','4.6.0','4.7.0')) {
      # Exercise the production historical and independent readers as well as
      # the schema. Their old 4.2-only parameter sets blocked real 4.5 receipts.
      foreach ($historicalTarget in @('f017','f016','f015','f014','f013')) {
        $historical = Get-MIR42QualificationHistoricalAuthority -RepoRoot $repo -Target $historicalTarget -SourceVersion $sourceVersion -PredecessorIdentityOnly
        Assert-MIR42CandidateBuildTest ($historical.identity.source_version -ceq $sourceVersion -and $historical.record.distribution_version -ceq ('4.2.'+$historicalTarget.Substring(1)+'00')) "$sourceVersion-historical-reader-keeps-pinned-baseline-$historicalTarget"
      }
      $independent = Get-MIR42IndependentScopeContract -Scope 'nine-target' -PublishedMaintenance -SourceVersion $sourceVersion
      Assert-MIR42CandidateBuildTest ($independent.reconciliation_status -ceq "MIR-$sourceVersion-NINE-TARGET-MAINTENANCE-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED" -and $independent.rehash_status -ceq "MIR-$sourceVersion-NINE-TARGET-MAINTENANCE-INDEPENDENT-EVIDENCE-REHASH-PASSED-PRIVATE-UNQUALIFIED") "$sourceVersion-independent-reader-keeps-current-version"
      $wrongScope = ''
      try { Get-MIR42IndependentScopeContract -Scope 'four-target' -PublishedMaintenance -SourceVersion $sourceVersion | Out-Null } catch { $wrongScope = $_.Exception.Message }
      Assert-MIR42CandidateBuildTest ($wrongScope -ceq '[mir42-independent-maintenance-candidate-scope]') "$sourceVersion-independent-reader-refuses-four-target-maintenance"
    }
    $crossVersion = $mir43Manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    $crossVersion.target_authority[0].source_version = '4.2.3'
    $crossVersion.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $crossVersion
    $crossVersionValid = Test-MIR42CandidateSchema -Json ($crossVersion | ConvertTo-Json -Depth 100) -SchemaPath $mir43VersionContract.schema_path
    Assert-MIR42CandidateBuildTest (-not $crossVersionValid) "$sourceVersion-schema-refuses-cross-source-authority"
    # Exercise the complete writer output, including historical leading-zero
    # codes. A schema accepting a mismatched source patch in any identity
    # field must fail.
    if ($sourceVersion -cin @('4.4.1','4.4.2','4.5.0','4.5.1','4.5.2','4.7.0')) {
      for ($i = 0; $i -lt $descriptors.Count; $i++) {
        foreach ($field in @('authority-version','target-version','asset-path')) {
          $wrongPatch = $mir43Manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
          $wrongSourcePatch = if ([int]$sourceIdentity.Build -eq 0) { 1 } else { 0 }
          $oldVersion = "4.$($sourceIdentity.Minor).$($targetCodes[$i])$($wrongSourcePatch.ToString('D2'))"
          switch ($field) {
            'authority-version' { $wrongPatch.target_authority[$i].distribution_version = $oldVersion }
            'target-version' { $wrongPatch.targets[$i].distribution_version = $oldVersion }
            'asset-path' { $wrongPatch.targets[$i].asset.path = "assets/$($descriptors[$i].target)/more-infinite-research_$oldVersion.zip" }
          }
          $wrongPatch.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $wrongPatch
          $wrongPatchValid = Test-MIR42CandidateSchema -Json ($wrongPatch | ConvertTo-Json -Depth 100) -SchemaPath $mir43VersionContract.schema_path
          Assert-MIR42CandidateBuildTest (-not $wrongPatchValid) "$($sourceVersion.Replace('.',''))-schema-refuses-mismatched-source-patch-$($descriptors[$i].target)-$field"
        }
      }
    }
  }
  $performanceContract=Get-MIR42SealCandidateConstructionVersionContract -RepoRoot $repo -Manifest $performanceManifest
  $futureHistoricalRefused = $false
  try { Get-MIR42QualificationHistoricalAuthority -RepoRoot $repo -Target f017 -SourceVersion '4.6.0' -PredecessorIdentityOnly | Out-Null } catch { $futureHistoricalRefused = $_.FullyQualifiedErrorId -match 'ParameterArgumentValidationError' }
  Assert-MIR42CandidateBuildTest $futureHistoricalRefused 'historical-reader-refuses-unadmitted-source-version'
  $futureIndependentRefused = $false
  try { Get-MIR42IndependentScopeContract -Scope 'nine-target' -PublishedMaintenance -SourceVersion '4.6.0' | Out-Null } catch { $futureIndependentRefused = $_.FullyQualifiedErrorId -match 'ParameterArgumentValidationError' }
  Assert-MIR42CandidateBuildTest $futureIndependentRefused 'independent-reader-refuses-unadmitted-source-version'
  $performanceEnvelope=Get-MIR42EngineCandidateVersionContract -RepoRoot $repo -ManifestPath (Join-Path $performanceRoot 'candidate-manifest.json')
  Assert-MIR42CandidateBuildTest ($performanceContract.source_version-ceq'4.2.3'-and$performanceEnvelope.source_version-ceq'4.2.3'-and$performanceEnvelope.nine_targets-and-not$performanceManifest.publication_authorized-and$performanceManifest.qualification-ceq'not-performed') '423-writer-and-consumed-readers-preserve-private-boundary'
  $performanceEvidenceCandidate=[pscustomobject]@{scope='nine-target';targets=$performanceManifest.targets;identity=[pscustomobject]@{record=$performanceManifest}}
  $performanceEvidence=Get-MIR42EngineEvidenceBindingContract -Candidate $performanceEvidenceCandidate -PublishedMaintenance
  $performanceCampaign=Get-MIR42JoinedCampaignInputContract -Candidate $performanceEvidenceCandidate -PublishedMaintenance
  $performanceSeal=Get-MIR42TechnicalSealInputContract -Candidate $performanceEvidenceCandidate -PublishedMaintenance
  $performanceIndependent=Get-MIR42IndependentScopeContract -Scope 'nine-target' -PublishedMaintenance -SourceVersion '4.2.3'
  foreach($field in @('evidence_status','binder_status','campaign_status','independent_status','seal_status')){
    Assert-MIR42CandidateBuildTest ($performanceSeal.$field.StartsWith('MIR-4.2.3-NINE-TARGET-MAINTENANCE-')) ('423-maintenance-reader-selects-'+$field)
  }
  Assert-MIR42CandidateBuildTest ($performanceIndependent.reconciliation_status-ceq$performanceEvidence.evidence_status-and$performanceIndependent.rehash_status-ceq$performanceSeal.independent_status-and$performanceCampaign.maintenance_source_version-ceq'4.2.3') '423-evidence-campaign-seal-readers-agree-on-version'
  foreach($criterion in @('fresh-exact-loads','target-omissions')){
    $criterionContract=Get-MIR42CriterionObservationContract -Criterion $criterion -PublishedMaintenance -SourceVersion '4.2.3'
    $expectedStatus=if($criterion-ceq'fresh-exact-loads'){$performanceEvidence.binder_status}else{$performanceEvidence.evidence_status}
    Assert-MIR42CandidateBuildTest ($criterionContract.status-ceq$expectedStatus) ('423-criterion-consumes-'+$criterion)
  }
  $currentContract=Get-MIR42SealCandidateConstructionVersionContract -RepoRoot $repo -Manifest $currentManifest
  $currentEnvelope=Get-MIR42EngineCandidateVersionContract -RepoRoot $repo -ManifestPath (Join-Path $currentRoot 'candidate-manifest.json')
  Assert-MIR42CandidateBuildTest ($currentManifest.schema-eq3-and$currentContract.source_version-ceq'4.2.2'-and$currentEnvelope.source_version-ceq'4.2.2'-and$currentEnvelope.nine_targets-and-not$currentManifest.publication_authorized-and$currentManifest.qualification-ceq'not-performed') '422-writer-and-consumed-readers-preserve-private-boundary'
  $currentEvidenceCandidate=[pscustomobject]@{scope='nine-target';targets=$currentManifest.targets;identity=[pscustomobject]@{record=$currentManifest}}
  $currentEvidence=Get-MIR42EngineEvidenceBindingContract -Candidate $currentEvidenceCandidate -PublishedMaintenance
  $currentCampaign=Get-MIR42JoinedCampaignInputContract -Candidate $currentEvidenceCandidate -PublishedMaintenance
  $currentSeal=Get-MIR42TechnicalSealInputContract -Candidate $currentEvidenceCandidate -PublishedMaintenance
  $currentIndependent=Get-MIR42IndependentScopeContract -Scope 'nine-target' -PublishedMaintenance -SourceVersion '4.2.2'
  foreach($field in @('evidence_status','binder_status','campaign_status','independent_status','seal_status')){
    Assert-MIR42CandidateBuildTest ($currentSeal.$field.StartsWith('MIR-4.2.2-NINE-TARGET-MAINTENANCE-')) ('422-maintenance-reader-selects-'+$field)
  }
  Assert-MIR42CandidateBuildTest ($currentIndependent.reconciliation_status-ceq$currentEvidence.evidence_status-and$currentIndependent.rehash_status-ceq$currentSeal.independent_status-and$currentCampaign.maintenance_source_version-ceq'4.2.2') '422-evidence-campaign-seal-readers-agree-on-version'
  foreach($criterion in @('fresh-exact-loads','target-omissions')){
    $criterionContract=Get-MIR42CriterionObservationContract -Criterion $criterion -PublishedMaintenance -SourceVersion '4.2.2'
    $expectedStatus=if($criterion-ceq'fresh-exact-loads'){$currentEvidence.binder_status}else{$currentEvidence.evidence_status}
    Assert-MIR42CandidateBuildTest ($criterionContract.status-ceq$expectedStatus) ('422-criterion-consumes-'+$criterion)
    Assert-MIR42CandidateBuildTest ((Get-MIR42CriterionObservationContract -Criterion $criterion -PublishedMaintenance).status-cne$criterionContract.status) ('422-criterion-does-not-relabel-421-'+$criterion)
  }
  foreach($target in @('f017','f016','f015','f014','f013')){
    $historicalIdentity=Get-MIR42QualificationHistoricalAuthority -RepoRoot $repo -Target $target -SourceVersion '4.2.2' -PredecessorIdentityOnly
    Assert-MIR42CandidateBuildTest ($null-eq$historicalIdentity.inventory-and$historicalIdentity.identity.source_version-ceq'4.2.2'-and$historicalIdentity.record.target-ceq$target) ('422-historical-provenance-does-not-require-terminal-archive-'+$target)
  }
  foreach($mutate in @(
    {param($m)$m.target_authority[0].source_version='4.2.1'},
    {param($m)$m.targets[0].distribution_version='4.2.21001'},
    {param($m)$m.targets[0].asset.path='assets/f210/more-infinite-research_4.2.21001.zip'},
    {param($m)$m.targets[0].target='f200'},
    {param($m)$m.targets=@($m.targets[0])},
    {param($m)$m.publication_authorized=$true},
    {param($m)$m.qualification='passed'}
  )){
    $invalid=$currentManifest|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    & $mutate $invalid
    $invalid.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $invalid
    $rejected=$false
    try{Get-MIR42SealCandidateConstructionVersionContract -RepoRoot $repo -Manifest $invalid|Out-Null}catch{$rejected=$_.Exception.Message-match'mir42-seal-candidate-manifest-schema'}
    Assert-MIR42CandidateBuildTest $rejected '422-rejects-mixed-version-target-or-authority'
  }
  $currentPartial=Write-MIR42FourTargetManifest -OutputRoot $currentRoot -Preflight $currentPreflight -Rows @($currentRows[0]) -Failures @(@{target='f200';message='controlled incomplete construction'})
  Assert-MIR42CandidateBuildTest (-not$currentPartial.build_complete-and$currentPartial.schema-eq3) '422-partial-state-retained'
  $rejected=$false
  try{Get-MIR42EngineCandidateVersionContract -RepoRoot $repo -ManifestPath (Join-Path $currentRoot 'candidate-manifest.json')|Out-Null}catch{$rejected=$_.Exception.Message-match'mir42-engine-candidate-manifest-invalid'}
  Assert-MIR42CandidateBuildTest $rejected '422-partial-construction-not-engine-acceptance'
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
    $valid = Test-MIR42CandidateSchema -Json ($invalid | ConvertTo-Json -Depth 100) -SchemaPath $schemaPath
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
  $valid = Test-MIR42CandidateSchema -Json ($invalidPartial | ConvertTo-Json -Depth 100) -SchemaPath $schemaPath
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
  # Exact 4.2.1 publication, selected explicitly for 4.2.2. The release's
  # disclosed gaps remain in the receipt; synthetic API metadata is not a
  # remote readback or native qualification.
  $published421Path=Join-Path $repo 'fixtures/release-inputs/mir422-published-421-manifest.json'
  $published421=Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath $published421Path -CandidateSourceVersion '4.2.2'
  $assets421=@(for($i=0;$i-lt9;$i++){
    $row=$published421.manifest.targets[$i]
    [pscustomobject]@{id=$i+1;name=$row.filename;size=$row.bytes;digest=('sha256:'+[string]$row.sha256).ToLowerInvariant();state='uploaded'}
  })
  $assets421+=,[pscustomobject]@{id=10;name='mir-4.2.1.release.json';size=$published421.bytes;digest=('sha256:'+$published421.sha256).ToLowerInvariant();state='uploaded'}
  $assets421+=@(for($i=11;$i-le16;$i++){[pscustomobject]@{id=$i;name="controlled-supporting-asset-$i";size=1;digest=('sha256:'+('a'*64));state='uploaded'}})
  $metadata421=[pscustomobject]@{id=407909462;tag_name='v4.2.1';draft=$false;prerelease=$false;immutable=$false;assets=$assets421}
  $rows421=@(Assert-MIR42PublishedMaintenancePredecessorMetadata -PinnedManifest $published421 -ReleaseMetadata $metadata421 -CandidateSourceVersion '4.2.2')
  Assert-MIR42CandidateBuildTest ($rows421.Count-eq9-and-not$published421.manifest.signed-and-not$published421.manifest.acceptance.full_technical_seal-and-not$published421.manifest.acceptance.independent_review-and-not$published421.manifest.acceptance.protected_signing_and_restore) '422-predecessor-retains-disclosed-acceptance-gaps'
  foreach($row in $rows421){
    Assert-MIR42CandidateBuildTest ($row.version-ceq('4.2.'+$row.target.Substring(1)+'01')) ('422-predecessor-exact-CCC01-'+$row.target)
    $tinyRoot=Join-Path $identityRoot ('published-421-archive-input/'+$row.target)
    $tinyTree=Join-Path $tinyRoot ('more-infinite-research_'+$row.version)
    New-Item -ItemType Directory -Path $tinyTree -Force|Out-Null
    $tinyInfo=[ordered]@{name='more-infinite-research';version=$row.version;factorio_version=$script:MIR42FourTargetLines[$row.target]}
    [IO.File]::WriteAllText((Join-Path $tinyTree 'info.json'),($tinyInfo|ConvertTo-Json -Compress),$utf8)
    $tinyArchive=Join-Path $tinyRoot $row.filename
    Write-MIR4DeterministicRawTreeArchive -SourceRoot $tinyTree -EntryRoot (Split-Path -Leaf $tinyTree) -OutputPath $tinyArchive -ContainmentRoot $identityRoot
    $archiveInput=Get-MIR42FourTargetArchiveInput -RepoRoot $repo -Target $row.target -Path $tinyArchive -SourceVersion '4.2.1'
    Assert-MIR42CandidateBuildTest ($archiveInput.distribution_version-ceq$row.version-and$archiveInput.qualification-ceq'not-run') ('422-predecessor-archive-reader-explicit-version-'+$row.target)
    $rejected=$false
    try{Get-MIR42FourTargetArchiveInput -RepoRoot $repo -Target $row.target -Path $tinyArchive|Out-Null}catch{$rejected=$_.Exception.Message-ceq('[mir42-preflight-package-root] '+$row.target)}
    Assert-MIR42CandidateBuildTest $rejected ('422-predecessor-archive-reader-keeps-420-default-'+$row.target)
  }
  foreach($case in $metadataMutations.GetEnumerator()){
    $invalid=$metadata421|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    & $case.Value $invalid
    $rejected=$false
    try{Assert-MIR42PublishedMaintenancePredecessorMetadata -PinnedManifest $published421 -ReleaseMetadata $invalid -CandidateSourceVersion '4.2.2'|Out-Null}catch{$rejected=$_.Exception.Message.StartsWith('[mir42-maintenance-predecessor-')}
    Assert-MIR42CandidateBuildTest $rejected ('422-predecessor-refuses-'+$case.Key)
  }
  foreach($case in @(
    @{path=$published421Path;version='4.2.1'},
    @{path=$publishedPin.path;version='4.2.2'}
  )){
    $rejected=$false
    try{Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath $case.path -CandidateSourceVersion $case.version|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-maintenance-predecessor-frozen-manifest]'}
    Assert-MIR42CandidateBuildTest $rejected ('422-predecessor-refuses-cross-release-'+$case.version)
  }
  $changed421=Join-Path $identityRoot 'changed-421-published-manifest.json'
  $bytes421=[IO.File]::ReadAllBytes($published421.path);$bytes421[100]=$bytes421[100]-bxor1
  [IO.File]::WriteAllBytes($changed421,$bytes421)
  $rejected=$false
  try{Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath $changed421 -CandidateSourceVersion '4.2.2'|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-maintenance-predecessor-frozen-manifest]'}
  Assert-MIR42CandidateBuildTest $rejected '422-predecessor-refuses-same-size-changed-manifest'
  $rejected=$false
  try{Assert-MIR42PublishedMaintenancePredecessorMetadata -PinnedManifest $published421 -ReleaseMetadata $metadata421|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-maintenance-predecessor-release-metadata]'}
  Assert-MIR42CandidateBuildTest $rejected '422-predecessor-metadata-default-remains-420'
  # Exact 4.2.2 publication, selected explicitly for a 4.2.3 candidate.
  # This portable pinned input has the same recorded bytes as the local dist
  # custody copy, but host validation must not depend on ignored dist output.
  $published422Path=Join-Path $repo 'fixtures/release-inputs/mir423-published-422-manifest.json'
  $published422=Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath $published422Path -CandidateSourceVersion '4.2.3'
  Assert-MIR42CandidateBuildTest ($published422.sha256 -ceq '157E001794BA7D0D0303C35085DEADC7BAA70606FA98CCCFD102E0D4FFAB3DDB' -and $published422.bytes -eq 7311 -and [string]$published422.manifest.source_tag -ceq 'v4.2.2') '423-predecessor-portable-published-manifest'
  $changed422=Join-Path $identityRoot 'changed-422-published-manifest.json'
  $bytes422=[IO.File]::ReadAllBytes($published422.path);$bytes422[100]=$bytes422[100]-bxor1
  [IO.File]::WriteAllBytes($changed422,$bytes422)
  $rejected=$false
  try{Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath $changed422 -CandidateSourceVersion '4.2.3'|Out-Null}catch{$rejected=$_.Exception.Message-ceq'[mir42-maintenance-predecessor-frozen-manifest]'}
  Assert-MIR42CandidateBuildTest $rejected '423-predecessor-portable-manifest-refuses-same-size-changed-bytes'
  $scopeCandidates=@($patchDescriptors|ForEach-Object {[pscustomobject]@{identity=$_}})
  Assert-MIR42MaintenanceReconciliationScope -Scope 'nine-target' -Candidates $scopeCandidates
  $maintenanceEvidenceAssertions++
  $currentScopeCandidates=@($currentDescriptors|ForEach-Object {[pscustomobject]@{identity=$_}})
  Assert-MIR42MaintenanceReconciliationScope -Scope 'nine-target' -Candidates $currentScopeCandidates
  $mir430ScopeCandidates=@($mir43DescriptorSets['4.3.0']|ForEach-Object {[pscustomobject]@{identity=$_}})
  Assert-MIR42MaintenanceReconciliationScope -Scope 'nine-target' -Candidates $mir430ScopeCandidates
  $maintenanceEvidenceAssertions++
  $mir431ScopeCandidates=@($mir43DescriptorSets['4.3.1']|ForEach-Object {[pscustomobject]@{identity=$_}})
  Assert-MIR42MaintenanceReconciliationScope -Scope 'nine-target' -Candidates $mir431ScopeCandidates
  $maintenanceEvidenceAssertions++
  $mir440ScopeCandidates=@($mir43DescriptorSets['4.4.0']|ForEach-Object {[pscustomobject]@{identity=$_}})
  Assert-MIR42MaintenanceReconciliationScope -Scope 'nine-target' -Candidates $mir440ScopeCandidates
  $maintenanceEvidenceAssertions++
  Assert-MIR42IndependentMaintenanceScope -Scope 'nine-target' -SourceVersion '4.2.2'
  $mixedScope=@($scopeCandidates[0])+@($currentScopeCandidates|Select-Object -Skip 1)
  $mixed431Scope=@($scopeCandidates[0])+@($mir431ScopeCandidates|Select-Object -Skip 1)
  $mixed440Scope=@($scopeCandidates[0])+@($mir440ScopeCandidates|Select-Object -Skip 1)
  foreach($case in @(
    @{name='four-target';scope='four-target';rows=@($scopeCandidates|Select-Object -First 4)},
    @{name='unsupported-420';scope='nine-target';rows=@($nineDescriptors|ForEach-Object {[pscustomobject]@{identity=$_}})},
    @{name='short';scope='nine-target';rows=@($scopeCandidates|Select-Object -First 8)},
    @{name='legacy-mixed';scope='nine-target';rows=$mixedScope},
    @{name='431-mixed';scope='nine-target';rows=$mixed431Scope},
    @{name='440-mixed';scope='nine-target';rows=$mixed440Scope}
  )){
    $rejected=$false
    try{Assert-MIR42MaintenanceReconciliationScope -Scope $case.scope -Candidates $case.rows}catch{$rejected=$_.Exception.Message-ceq'[mir42-reconciliation-maintenance-candidate-scope]'}
    Assert-MIR42CandidateBuildTest $rejected ('maintenance-reconciliation-refuses-'+$case.name)
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
  # The source-specific contract is selected after reading the candidate.
  # Test the CLI's real named-argument forwarding with a controlled boundary;
  # the preceding controls separately enforce the 4.2 maintenance restriction.
  $criterionCliRepo=Join-Path $identityRoot 'criterion-cli-binding-repo'
  $criterionCliLibrary=Join-Path $criterionCliRepo 'tools/mir/application/release/readiness'
  New-Item -ItemType Directory -Force -Path $criterionCliLibrary|Out-Null
  [IO.File]::WriteAllText((Join-Path $criterionCliLibrary 'MIR42EvidenceReconciliation.ps1'),@'
function New-MIR42NineTargetCriterionEvidence {
  param($RepoRoot,$CandidateManifestPath,$Criterion,$ObservationPaths,$ObservedTargets,$NotApplicableTargetReasons,$Claim,$KnownLimitations,$OutputPath,$PublishedMaintenancePredecessorManifestPath,$PublishedMaintenanceArchiveBindings)
  if($PublishedMaintenancePredecessorManifestPath-cne'not-read.json'-or$Criterion-cne'performance-telemetry'){
    throw '[controlled-criterion-cli-missing-maintenance-binding]'
  }
  throw '[mir42-maintenance-criterion-input-scope]'
}
'@,[Text.UTF8Encoding]::new($false))
  $rejected=$false
  try{
    & (Join-Path $repo 'tools/commands/release/Invoke-MIR42NineTargetEvidenceReconciliation.ps1') -Mode Criterion -RepoRoot $criterionCliRepo `
      -CandidateManifestPath (Join-Path $identityRoot 'not-read.json') -Criterion 'performance-telemetry' -ObservationPaths @('not-read.json') `
      -ObservedTargets @('f210') -Claim 'source flag-forwarding control' -KnownLimitations 'not native' `
      -OutputPath (Join-Path $identityRoot 'must-not-create.json') -PublishedMaintenancePredecessorManifestPath 'not-read.json'|Out-Null
  }catch{$rejected=$_.Exception.Message-ceq'[mir42-maintenance-criterion-input-scope]'}
  Assert-MIR42CandidateBuildTest ($rejected-and-not(Test-Path -LiteralPath (Join-Path $identityRoot 'must-not-create.json'))) 'maintenance-criterion-cli-forwards-and-refuses-out-of-scope-option'
  $maintenanceCriterionAssertions++
  foreach($criterion in $script:MIR42ReleaseAcceptanceCriteria){
    $current=Get-MIR42CriterionObservationContract -Criterion $criterion -PublishedMaintenance -SourceVersion '4.3.0'
    $dedicated=$criterion-cin@('fresh-exact-loads','target-omissions')
    Assert-MIR42CandidateBuildTest ($(if($dedicated){$null-ne$current-and-not[string]::IsNullOrWhiteSpace([string]$current.kind)}else{$null-eq$current})) ('mir430-criterion-contract-admitted-'+$criterion)
    $maintenanceCriterionAssertions++
    $normal440=Get-MIR42CriterionObservationContract -Criterion $criterion -PublishedMaintenance -SourceVersion '4.4.0'
    Assert-MIR42CandidateBuildTest ($(if($dedicated){$null-ne$normal440-and-not[string]::IsNullOrWhiteSpace([string]$normal440.kind)}else{$null-eq$normal440})) ('mir440-normal-criterion-contract-admitted-'+$criterion)
    $maintenanceCriterionAssertions++
  }
  if ($IdentityContractsOnly) {
    [pscustomobject][ordered]@{ status='MIR-4.3-CANDIDATE-IDENTITY-CONTRACTS-PASSED'; source_versions=$admittedCandidateSources; current_maintenance_contract_assertions=$script:mir422ConstructionAssertions; target_identities=9; mir43_source_versions=@($mir43Contracts.source_version); mir43_target_identities=9*$mir43Contracts.Count; mir43_manifest_contracts=$mir43Contracts.Count; metadata_idempotence_checks=9; invalid_version_refusals=2; invalid_manifest_refusals=16; patch00_opposing_checks=27; engine_envelope_assertions=$engineEnvelopeAssertions; engine_destination_assertions=$engineDestinationAssertions; maintenance_custody_assertions=$maintenanceCustodyAssertions; maintenance_evidence_assertions=$maintenanceEvidenceAssertions; maintenance_independent_assertions=$maintenanceIndependentAssertions; seal_candidate_contract_assertions=$sealCandidateContractAssertions; maintenance_binder_assertions=$maintenanceBinderAssertions; maintenance_criterion_assertions=$maintenanceCriterionAssertions; maintenance_campaign_assertions=$maintenanceCampaignAssertions; maintenance_readiness_assertions=$maintenanceReadinessAssertions; maintenance_seal_assertions=$maintenanceSealAssertions; controlled_predecessor_archives=9; engine_runs=0; actual_candidate_zip_builds=0 }
    return
  }

  Test-MIR42RetainedMaterializerReceipts -OutputRoot $receiptRoot

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
    $retained = Get-Content -Raw -LiteralPath (Join-Path $root "materializations/$target.json") | ConvertFrom-Json -Depth 100
    Assert-MIR42CandidateBuildTest ((Test-MIR4BootstrapRecordHash -Record $retained) -and $retained.record_sha256 -ceq $row.materializer_record_b_sha256 -and $retained.archive_path -ceq $asset -and -not (Test-Path -LiteralPath $retained.tree_path)) "row-retains-original-materializer-receipt-$target"
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
    $retainedManifestPath = Join-Path $nineRoot "materializations/$target.json"
    $retainedManifestIdentity = if (Test-Path -LiteralPath $retainedManifestPath -PathType Leaf) {
      Get-MIR4RawFileIdentity -Path $retainedManifestPath
    } else { $null }
    $retainedManifest = if (Test-Path -LiteralPath $retainedManifestPath -PathType Leaf) {
      Get-Content -Raw -LiteralPath $retainedManifestPath | ConvertFrom-Json -Depth 100 -DateKind String
    } else { $null }
    Assert-MIR42CandidateBuildTest (
      $null -ne $retainedManifest -and
      $null -ne $retainedManifestIdentity -and
      $null -ne $row.historical_materializer_manifest -and
      [string]$row.historical_materializer_manifest.path -ceq "materializations/$target.json" -and
      [int64]$row.historical_materializer_manifest.bytes -eq [int64]$retainedManifestIdentity.bytes -and
      [string]$row.historical_materializer_manifest.sha256 -ceq [string]$retainedManifestIdentity.sha256 -and
      [string]$row.historical_materializer_manifest.record_sha256 -ceq [string]$row.historical_materializer_manifest_sha256 -and
      (Test-MIR4BootstrapRecordHash -Record $retainedManifest) -and
      [string]$retainedManifest.record_sha256 -ceq [string]$row.historical_materializer_manifest_sha256
    ) "nine-historical-row-retains-self-hashed-construction-manifest-$target"
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
    $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $patchRoot ([string]$row.asset.path)))
    try {
      $version = [string]$row.distribution_version
      $entry = $archive.GetEntry("more-infinite-research_$version/README.md")
      $reader = [IO.StreamReader]::new($entry.Open())
      try { $readme = $reader.ReadToEnd() } finally { $reader.Dispose() }
      Assert-MIR42CandidateBuildTest ($readme.Contains("# More Infinite Research $version") -and $readme.Contains("More Infinite Research $version is") -and $readme.Contains("more-infinite-research_$version.zip") -and $readme -notmatch '4\.2\.100[0-9]{2}') "patch-historical-readme-package-identity-$target"
      Assert-MIR42CandidateBuildTest ($readme.Contains("Earlier fresh-load evidence used $($frozenRecord.engine.version);") -and $readme.Contains("The exact published $($frozenRecord.predecessor.version) archive remains a historical predecessor record.") -and $readme.Contains('Consult the matching release record for native qualification of this exact package.')) "patch-historical-readme-evidence-boundary-$target"
    } finally { $archive.Dispose() }
  }

  # This registered construction suite owns the published-predecessor reader's
  # executable control.  The child test uses bounded synthetic archive/API
  # inputs only; it does not perform native qualification or publication.
  & (Join-Path $repo 'tests/release/Test-MIR42FourTargetReleasePreflight.ps1') -RepoRoot $repo
  Assert-MIR42CandidateBuildTest $true 'published-maintenance-predecessor-controls-composed'

  [pscustomobject][ordered]@{
    status = 'MIR-4.2-NINE-TARGET-CONSTRUCTION-ADAPTER-STATIC-PASSED'
    materializer_calls_complete = 8
    retained_receipt_assertions = $script:mir42CandidateReceiptAssertions
    partial_successful_targets = @($partial.targets).Count
    historical_target_rows = 5
    patch_target_rows = 9
    predecessor_inventory_control = 'terminal-seal-fixture-only'
    independent_input_controls = 'v1-v2-first-row-and-required-predecessor-refusals-engine-lookup-fixture-only'
    engine_runs = 0
  }
} catch {
  # The assurance caller retains the thrown message. Include the location so a
  # hosted-only failure can be diagnosed without rerunning unchanged controls.
  throw ("[mir42-candidate-build-failure] {0}`n{1}`n{2}" -f $_.FullyQualifiedErrorId, $_.Exception.Message, $_.ScriptStackTrace)
} finally {
  foreach ($path in @($root, $partialRoot, $historicalRoot, $nineRoot, $identityRoot, $patchRoot, $receiptRoot, $historicalAuthenticationRoot)) {
    if (Test-Path -LiteralPath $path) {
      $resolvedPath = (Resolve-Path -LiteralPath $path).Path
      $null = Assert-MIR4DescendantPath -Root (Join-Path $repo 'build') -Path $resolvedPath
      $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $resolvedPath
      Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    }
  }
}
