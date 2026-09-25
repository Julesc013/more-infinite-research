[CmdletBinding()]
param()

Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42ExactCandidateQualification.ps1')

function Assert-MIR42QualificationTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir42-qualification-test] $Code" }
}

function New-MIR42QualificationTestZip {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$Version
  )

  $line = @{ f210 = '2.1'; f200 = '2.0'; f110 = '1.1'; f100 = '1.0' }[$Target]
  $tree = Join-Path $Root "tree/more-infinite-research_$Version"
  New-Item -ItemType Directory -Force -Path $tree | Out-Null
  $info = [ordered]@{ name = 'more-infinite-research'; version = $Version; factorio_version = $line } | ConvertTo-Json -Compress
  [IO.File]::WriteAllText((Join-Path $tree 'info.json'), ($info + [string][char]10), [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $tree 'data.lua'), ('return {}' + [string][char]10), [Text.UTF8Encoding]::new($false))
  $archive = Join-Path $Root "more-infinite-research_$Version.zip"
  Write-MIR4DeterministicRawTreeArchive -SourceRoot $tree -EntryRoot "more-infinite-research_$Version" -OutputPath $archive -ContainmentRoot $Root
  return Get-MIR4ArchiveInventory -Path $archive
}

function New-MIR42QualificationTestReceipt {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$SourceCommit,
    [Parameter(Mandatory)]$Predecessor,
    [Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)]$Environment
  )

  $root = Split-Path -Parent $Path
  $logs = [ordered]@{}
  foreach ($name in @('create_log','load_log','reload_log','second_reload_log')) {
    $file = "$name.txt"
    [IO.File]::WriteAllText((Join-Path $root $file), ($Target + '-' + $name + [string][char]10), [Text.UTF8Encoding]::new($false))
    $logs[$name] = $file
    $logs[$name + '_sha256'] = Get-MIR4Sha256File -Path (Join-Path $root $file)
  }
  $receipt = [ordered]@{
    schema = 2
    status = 'passed'
    generated_at = '2026-09-25T00:00:00Z'
    git_commit = $SourceCommit
    archetype = 'base-default'
    factorio_binary_version = [string]$Environment.version
    factorio_binary_sha256 = [string]$Environment.binary_sha256
    from = [ordered]@{ version = [string]$Predecessor.version; path = 'predecessor.zip'; sha256 = [string]$Predecessor.archive_sha256 }
    to = [ordered]@{ version = [string]$Candidate.version; path = 'candidate.zip'; sha256 = [string]$Candidate.archive_sha256 }
    assertions = @('exact-candidate-normal-mod-directory-load','upgraded-save-reload-passed','upgraded-save-second-reload-passed')
  }
  foreach ($property in $logs.Keys) { $receipt[$property] = $logs[$property] }
  [IO.File]::WriteAllText($Path, (($receipt | ConvertTo-Json -Depth 20) + [string][char]10), [Text.UTF8Encoding]::new($false))
  return $receipt
}

$testRoot = Join-Path $repo ('build/test-results/mir42-qualification-' + [guid]::NewGuid().ToString('N'))
$failureRoot = $testRoot + '-failure'
try {
  $source = Get-MIR42QualificationCurrentSource -RepoRoot $repo
  $candidateRoot = Join-Path $testRoot 'candidate'
  $candidateRows = [Collections.Generic.List[object]]::new()
  $candidateSummaries = [Collections.Generic.List[object]]::new()
  $predecessors = [ordered]@{}
  $receipts = [ordered]@{}

  foreach ($target in @('f210','f200','f110','f100')) {
    $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target $target -SourceVersion '4.2.0'
    $candidateArchiveRoot = Join-Path $candidateRoot "assets/$target"
    $candidateInventory = New-MIR42QualificationTestZip -Root $candidateArchiveRoot -Target $target -Version ([string]$identity.distribution_version)
    $candidatePath = Join-Path $candidateArchiveRoot ([string]$identity.package_name)
    $predecessorVersion = "4.1.$([string]$identity.distribution_target_code)00"
    $predecessorRoot = Join-Path $testRoot "predecessors/$target"
    $predecessorInventory = New-MIR42QualificationTestZip -Root $predecessorRoot -Target $target -Version $predecessorVersion
    $predecessorPath = Join-Path $predecessorRoot "more-infinite-research_$predecessorVersion.zip"
    $predecessors[$target] = $predecessorPath

    $row = [pscustomobject][ordered]@{
      schema = 1
      kind = 'MIR42FourTargetCandidateRowV1'
      status = 'accepted-private-deterministic-unqualified'
      target = $target
      source = $source
      source_version = '4.2.0'
      distribution_version = [string]$identity.distribution_version
      package_authority_sha256 = (Get-MIR4CanonicalPackageAuthority -RepoRoot $repo).record_sha256
      package_source_sha256 = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
      asset = [pscustomobject][ordered]@{ path = "assets/$target/$([string]$identity.package_name)"; bytes = [Int64]$candidateInventory.bytes; sha256 = [string]$candidateInventory.archive_sha256 }
      content_sha256 = [string]$candidateInventory.content_sha256
      entry_count = [int]$candidateInventory.entry_count
      deterministic_archive_bytes = $true
      package_excluded_surface = $true
      record_sha256 = ''
    }
    $rowPath = Join-Path $candidateRoot "target-rows/$target.json"
    Write-MIR4BootstrapRecord -Record $row -Path $rowPath | Out-Null
    $candidateRows.Add($row)
    $candidateSummaries.Add([pscustomobject][ordered]@{
      target = $target
      distribution_version = [string]$identity.distribution_version
      target_row_path = "target-rows/$target.json"
      asset = $row.asset
      content_sha256 = [string]$row.content_sha256
      entry_count = [int]$row.entry_count
    })

    $environment = if ($target -ceq 'f210') {
      $channel = Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/engines/mir4-factorio-2.1-experimental-channel-v1.json') | ConvertFrom-Json -Depth 100 -DateKind String
      [pscustomobject]@{version=[string]$channel.current_review.file_version;binary_sha256=[string]$channel.current_review.binary_sha256}
    } else {
      $lock = Get-MIR4FixedFactorioEngineLock -Target $target -RepoRoot $repo
      [pscustomobject]@{version=[string]$lock.file_version;binary_sha256=[string]$lock.binary_sha256}
    }
    $receiptRoot = Join-Path $testRoot "receipts/$target"
    New-Item -ItemType Directory -Force -Path $receiptRoot | Out-Null
    $receiptPath = Join-Path $receiptRoot 'result.json'
    New-MIR42QualificationTestReceipt -Path $receiptPath -Target $target -SourceCommit ([string]$source.commit) -Predecessor ([pscustomobject]@{version=$predecessorVersion;archive_sha256=$predecessorInventory.archive_sha256}) -Candidate ([pscustomobject]@{version=$identity.distribution_version;archive_sha256=$candidateInventory.archive_sha256}) -Environment $environment | Out-Null
    $receipts[$target] = $receiptPath
  }

  $manifest = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetDeterministicCandidateManifestV1'
    status = 'private-deterministic-four-target-candidate-built-unqualified'
    build_complete = $true
    source = $source
    package_authority_sha256 = (Get-MIR4CanonicalPackageAuthority -RepoRoot $repo).record_sha256
    package_source_sha256 = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
    targets = @($candidateSummaries)
    record_sha256 = ''
  }
  $manifestPath = Join-Path $candidateRoot 'candidate-manifest.json'
  Write-MIR4BootstrapRecord -Record $manifest -Path $manifestPath | Out-Null

  $result = Invoke-MIR42FourTargetExactCandidateQualification -RepoRoot $repo -CandidateManifestPath $manifestPath -F210PredecessorZip $predecessors.f210 -F200PredecessorZip $predecessors.f200 -F110PredecessorZip $predecessors.f110 -F100PredecessorZip $predecessors.f100 -F210UpgradeReceipt $receipts.f210 -F200UpgradeReceipt $receipts.f200 -F110UpgradeReceipt $receipts.f110 -F100UpgradeReceipt $receipts.f100 -OutputRoot (Join-Path $testRoot 'qualification')
  Assert-MIR42QualificationTest ($result.status -ceq 'MIR-4.2-FOUR-TARGET-EXACT-CANDIDATE-QUALIFICATION-PASSED-PRIVATE-UNSEALED') 'result-status'
  Assert-MIR42QualificationTest (Test-MIR4BootstrapRecordHash -Record $result) 'result-self-hash'
  Assert-MIR42QualificationTest ((@($result.targets.target) -join '|') -ceq 'f210|f200|f110|f100') 'target-order'
  Assert-MIR42QualificationTest ([string]$result.source.package_source_sha256 -ceq (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)) 'source-package-fingerprint'
  Assert-MIR42QualificationTest ([string]$result.candidate_manifest.record_sha256 -ceq [string]$manifest.record_sha256) 'candidate-manifest-binding'
  Assert-MIR42QualificationTest (@($result.targets | Where-Object { [string]$_.status -cne 'passed' -or [string]$_.candidate.sha256 -cne [string]$_.archive.sha256 -or [string]$_.candidate.content_sha256 -cne [string]$_.archive.content_sha256 }).Count -eq 0) 'target-contract-binding'
  Assert-MIR42QualificationTest (@($result.targets | Where-Object { @($_.harness.assertions | Where-Object { $_ -eq 'upgraded-save-second-reload-passed' }).Count -ne 1 }).Count -eq 0) 'second-reload-assertions'
  Assert-MIR42QualificationTest (-not [bool]$result.publication_authorized -and [string]$result.technical_seal -ceq 'not-performed') 'release-boundaries'

  $bad = Get-Content -Raw -LiteralPath $receipts.f200 | ConvertFrom-Json -Depth 100 -DateKind String
  $bad.to.sha256 = ('0' * 64)
  $badPath = Join-Path $testRoot 'receipts/f200/bad-result.json'
  [IO.File]::WriteAllText($badPath, (($bad | ConvertTo-Json -Depth 100) + [string][char]10), [Text.UTF8Encoding]::new($false))
  $rejected = $false
  try {
    Invoke-MIR42FourTargetExactCandidateQualification -RepoRoot $repo -CandidateManifestPath $manifestPath -F210PredecessorZip $predecessors.f210 -F200PredecessorZip $predecessors.f200 -F110PredecessorZip $predecessors.f110 -F100PredecessorZip $predecessors.f100 -F210UpgradeReceipt $receipts.f210 -F200UpgradeReceipt $badPath -F110UpgradeReceipt $receipts.f110 -F100UpgradeReceipt $receipts.f100 -OutputRoot $failureRoot | Out-Null
  } catch {
    $rejected = $_.Exception.Message -match 'mir42-qualification-upgrade-receipt-binding] f200'
  }
  Assert-MIR42QualificationTest $rejected 'candidate-mismatch-fails-closed'

  [pscustomobject][ordered]@{
    status = 'MIR-4.2-FOUR-TARGET-EXACT-CANDIDATE-QUALIFICATION-STATIC-PASSED'
    targets = 4
    factorio_processes = 0
  }
} finally {
  foreach ($path in @($testRoot, $failureRoot)) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
  }
}
