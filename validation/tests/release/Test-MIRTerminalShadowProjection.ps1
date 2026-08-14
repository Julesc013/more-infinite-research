param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$profilesPath = Join-Path $RepoRoot ".mir/releases/terminal/MIR3-Terminal-Shadow-ProjectionProfilesV1.json"
$sourcePublicationPath = Join-Path $RepoRoot ".mir/releases/terminal/MIR3-Terminal-Shadow-Source-PublicationV1.json"
$productReconciliationPath = Join-Path $RepoRoot ".mir/releases/terminal/MIR3TerminalProductImplementationReconciliationV1.json"
$branchReceiptPath = Join-Path $RepoRoot ".mir/releases/terminal/MIR3-Terminal-Shadow-Kernel-Branch-ReceiptV1.json"
$matrixPath = Join-Path $RepoRoot ".mir/releases/terminal/MIR3-Terminal-Target-MatrixV1.json"
$admissionPath = Join-Path $RepoRoot ".mir/releases/terminal/MIR3TerminalProductAdmissionBundleV1.json"
$commandPath = Join-Path $RepoRoot "tools/commands/targets/Set-MIRTerminalShadowProjection.ps1"
$approvedDeltaFixturePath = Join-Path $RepoRoot "fixtures/export-approved-delta/data-final-fixes.lua"
$materializerText = Get-Content -Raw -LiteralPath $commandPath

function Test-MIRTerminalDetachedHeadEquivalent {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$ActualText,
    [Parameter(Mandatory)][string]$ExpectedText
  )
  if ($RelativePath -eq "scripts/Test-MIRAssurance.ps1") {
    $reconstructed = $ActualText
    foreach ($pair in @(
      @(
        '& (Join-Path $RepoRoot "scripts\Invoke-MIRAssurance.ps1") self-test',
        'if ($LASTEXITCODE -ne 0) { throw "MIR assurance self-test failed." }'
      ),
      @(
        '& (Join-Path $RepoRoot "scripts\Test-MIRVerificationSchemas.ps1") -RepoRoot $RepoRoot',
        'if ($LASTEXITCODE -ne 0) { throw "MIR verification schema validation failed." }'
      )
    )) {
      if ($ExpectedText.Contains([string]$pair[1]) -and -not $reconstructed.Contains([string]$pair[1])) {
        $reconstructed = $reconstructed.Replace([string]$pair[0], [string]$pair[0] + "`n" + [string]$pair[1])
      }
    }
    $safeInventoryGate = 'if (-not $inventoryText.Contains(''"schema": 2'')) {'
    $unsafeInventoryGate = 'if ($LASTEXITCODE -ne 0 -or -not $inventoryText.Contains(''"schema": 2'')) {'
    if ($ExpectedText.Contains($unsafeInventoryGate) -and $reconstructed.Contains($safeInventoryGate)) {
      $reconstructed = $reconstructed.Replace($safeInventoryGate, $unsafeInventoryGate)
    }
    return $reconstructed -ceq $ExpectedText
  }
  $replacement = switch ($RelativePath) {
    "scripts/Invoke-MIRAssurance.ps1" {
      @{safe='      branch=(@(& git -C $repo branch --show-current) -join "").Trim()'; unsafe='      branch=(& git -C $repo branch --show-current).Trim()'}
      break
    }
    { $_ -in @("scripts/MIRAssurance/Release.ps1", "tools/lib/assurance/Release.ps1") } {
      @{safe='  $branch = (@(& git -C $repo branch --show-current) -join "").Trim()'; unsafe='  $branch = (& git -C $repo branch --show-current).Trim()'}
      break
    }
    default { return $false }
  }
  return $ActualText.Contains([string]$replacement.safe) -and
    $ActualText.Replace([string]$replacement.safe, [string]$replacement.unsafe) -ceq $ExpectedText
}

function Write-MIRTerminalProjectionTestText {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Text
  )

  $encoding = [Text.UTF8Encoding]::new($false)
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path))
  for ($attempt = 1; $attempt -le 20; $attempt++) {
    try {
      [IO.File]::WriteAllText($Path, $Text, $encoding)
      return
    } catch [IO.IOException] {
      if ($attempt -ge 20) { throw }
      Start-Sleep -Milliseconds ([Math]::Min(50 * $attempt, 500))
    }
  }
}

function Remove-MIRTerminalProjectionTestRoot {
  param([Parameter(Mandatory)][string]$Path)

  for ($attempt = 1; $attempt -le 20; $attempt++) {
    try {
      Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
      return
    } catch {
      if ($attempt -ge 20) { throw }
      Start-Sleep -Milliseconds ([Math]::Min(50 * $attempt, 500))
    }
  }
}

foreach ($requiredIdempotencePolicy in @(
  'for ($attempt = 1; $attempt -le 20; $attempt++) {',
  'catch [IO.IOException] {',
  '$finalOverlayBlob = [string]$orderedOverlayOutputs[-1].blob',
  '} elseif ([string]$file.blob -eq $finalOverlayBlob) {',
  'hash-object --no-filters -- $destination',
  'if ($existingBlob -ne $finalOverlayBlob) {'
)) {
  if (-not $materializerText.Contains($requiredIdempotencePolicy)) {
    throw "Terminal projection materializer does not preserve idempotent final-overlay writes: $requiredIdempotencePolicy"
  }
}

$profiles = Get-Content -Raw -LiteralPath $profilesPath | ConvertFrom-Json -Depth 100
$sourcePublication = Get-Content -Raw -LiteralPath $sourcePublicationPath | ConvertFrom-Json -Depth 100
$productReconciliation = Get-Content -Raw -LiteralPath $productReconciliationPath | ConvertFrom-Json -Depth 100
$branchReceipt = Get-Content -Raw -LiteralPath $branchReceiptPath | ConvertFrom-Json -Depth 100
$matrix = Get-Content -Raw -LiteralPath $matrixPath | ConvertFrom-Json -Depth 100
$admission = Get-Content -Raw -LiteralPath $admissionPath | ConvertFrom-Json -Depth 100
$family = @("3.2.9", "2.5.9", "1.9.9", "1.8.9", "1.7.9", "1.6.9", "1.5.9", "1.4.9", "1.3.9")

if ([int]$profiles.schema -ne 1 -or [string]$profiles.kind -ne "MIR3TerminalShadowProjectionProfilesV1" -or
    (@($profiles.targets.release) -join "|") -ne ($family -join "|")) {
  throw "Terminal shadow projection profile family is incomplete or unordered."
}
if ([string]$profiles.portable_source.release -ne "3.2.9" -or
    (& git -C $RepoRoot rev-parse "$([string]$profiles.portable_source.authority_commit)^{commit}").Trim() -ne [string]$profiles.portable_source.authority_commit -or
    (& git -C $RepoRoot rev-parse "$([string]$profiles.portable_source.authority_commit)^{tree}").Trim() -ne [string]$profiles.portable_source.authority_tree) {
  throw "Terminal shadow portable source is not an immutable repository authority."
}
if ([int]$sourcePublication.schema -ne 1 -or
    [string]$sourcePublication.kind -ne "MIR3TerminalShadowSourcePublicationV1" -or
    [string]$sourcePublication.status -ne "published-shadow-source-history" -or
    [string]$sourcePublication.repository -ne "Julesc013/more-infinite-research" -or
    [bool]$sourcePublication.source_frozen -or $null -ne $sourcePublication.candidate_id -or
    [string]$sourcePublication.transport -ne "full-git-history-v1" -or
    @($sourcePublication.refs).Count -ne 3) {
  throw "Terminal shadow source publication authority is incomplete or overclaims freeze/candidate state."
}

$publishedOverlayIds = @()
foreach ($sourceRef in @($sourcePublication.refs)) {
  $headCommit = [string]$sourceRef.head_commit
  $headTree = [string]$sourceRef.head_tree
  if ((& git -C $RepoRoot rev-parse "$headCommit^{commit}" 2>$null).Trim() -ne $headCommit -or
      (& git -C $RepoRoot rev-parse "$headCommit^{tree}" 2>$null).Trim() -ne $headTree) {
    throw "Terminal shadow source publication head is unavailable or changed: $($sourceRef.id)"
  }
  $branchName = ([string]$sourceRef.ref).Substring("refs/heads/".Length)
  $publishedTips = @(
    [string]$sourceRef.ref,
    "refs/remotes/origin/$branchName"
  ) | ForEach-Object {
    $resolved = @(& git -C $RepoRoot rev-parse --verify "$_^{commit}" 2>$null)
    if ($LASTEXITCODE -eq 0 -and $resolved.Count -eq 1) { [string]$resolved[0].Trim() }
  } | Select-Object -Unique
  $reachableTip = @($publishedTips | Where-Object {
    & git -C $RepoRoot merge-base --is-ancestor $headCommit $_ 2>$null
    $LASTEXITCODE -eq 0
  } | Select-Object -First 1)
  if ($reachableTip.Count -ne 1) {
    throw "Terminal shadow source ref no longer contains its recorded immutable head: $($sourceRef.ref)"
  }
  $publishedOverlayIds += @($sourceRef.overlay_ids | ForEach-Object { [string]$_ })
}
if (@($publishedOverlayIds | Select-Object -Unique).Count -ne $publishedOverlayIds.Count) {
  throw "Terminal shadow source publication assigns an assurance overlay more than once."
}
if ([int]$productReconciliation.schema -ne 1 -or
    [string]$productReconciliation.status -ne "late-p0-fixed-point-accepted-ready-for-source-freeze" -or
    [string]$productReconciliation.prior_receipt.raw_sha256 -ne (Get-FileHash -LiteralPath (Join-Path $RepoRoot ([string]$productReconciliation.prior_receipt.path)) -Algorithm SHA256).Hash -or
    [string]$productReconciliation.current_3_2_9_shadow.package.archive_sha256 -ne "0E833FCDDA3017641CA99D0EBD2FA226938A1CEE91D2EBB4007E94B29787AE20" -or
    [string]$productReconciliation.current_2_5_9_shadow.package.archive_sha256 -ne "B5EF300A12F1DE7F130ADAE8A2D368CD879D56FE7141879A807698F9B0EBBF35" -or
    [string]$productReconciliation.current_3_2_9_shadow.convergence.independent_confirmation.status -ne "passed" -or
    [int]$productReconciliation.current_3_2_9_shadow.convergence.independent_confirmation.executed -ne 127 -or
    [string]$productReconciliation.current_2_5_9_shadow.independent_confirmation.status -ne "passed" -or
    [int]$productReconciliation.current_2_5_9_shadow.independent_confirmation.executed -ne 90 -or
    (@($productReconciliation.finding_dispositions.id) -join "|") -ne "MIR3-TERM-0027|MIR3-TERM-0028|MIR3-TERM-0031" -or
    (@($productReconciliation.late_p0_amendment.development_packages.archive_sha256) -join "|") -ne "0E833FCDDA3017641CA99D0EBD2FA226938A1CEE91D2EBB4007E94B29787AE20|B5EF300A12F1DE7F130ADAE8A2D368CD879D56FE7141879A807698F9B0EBBF35" -or
    (@($productReconciliation.late_p0_amendment.supersedes_current_shadow_identity_for) -join "|") -ne "3.2.9|2.5.9" -or
    [bool]$productReconciliation.immutable_boundaries.dot5_package_bytes_changed -or
    [bool]$productReconciliation.immutable_boundaries.source_frozen -or
    [bool]$productReconciliation.immutable_boundaries.candidate_assigned -or
    -not [bool]$productReconciliation.immutable_boundaries.all_nine_fixed_point_accepted -or
    [bool]$productReconciliation.immutable_boundaries.tagging_or_publication_permitted) {
  throw "Terminal product implementation reconciliation is stale, lacks accepted proof, or crosses the source-freeze boundary."
}
if ([int]$branchReceipt.schema -ne 1 -or
    [string]$branchReceipt.status -ne "kernel-ready-for-pr-all-nine-convergence-evidence-present-confirmation-pending" -or
    [string]$branchReceipt.source_snapshot.commit -ne "3bc84321394d6e7d817ca885d1d63df925eee902" -or
    (& git -C $RepoRoot rev-parse "$([string]$branchReceipt.source_snapshot.commit)^{tree}").Trim() -ne [string]$branchReceipt.source_snapshot.tree -or
    [int]$branchReceipt.source_snapshot.commits_behind -ne 0 -or @($branchReceipt.targets).Count -ne 9 -or
    (@($branchReceipt.targets.release) -join "|") -ne ($family -join "|") -or
    @($branchReceipt.targets | Where-Object { [string]$_.convergence.status -ne "passed" -or [string]$_.confirmation -ne "pending" }).Count -ne 0 -or
    [bool]$branchReceipt.kernel.source_frozen -or [bool]$branchReceipt.kernel.candidate_ids_assigned) {
  throw "Terminal shadow kernel branch receipt is stale, incomplete, or overclaims confirmation/freeze state."
}
$approvedDeltaFixture = Get-Content -Raw -LiteralPath $approvedDeltaFixturePath
if ($approvedDeltaFixture -notmatch 'mods\["more-infinite-research"\]\s*==\s*"2\.5\.9"' -or
    $approvedDeltaFixture -notmatch 'terminal 2\.5\.9 route-policy projection') {
  throw "The approved-delta observer does not recognize the target-native 2.5.9 compiler-artifact boundary."
}

foreach ($row in @($profiles.targets)) {
  $matrixRow = @($matrix.targets | Where-Object release -eq ([string]$row.release))
  $admissionRow = @($admission.all_nine_dispositions | Where-Object release -eq ([string]$row.release))
  $record = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir/releases/records/$([string]$row.release).json") | ConvertFrom-Json -Depth 100
  if ($matrixRow.Count -ne 1 -or $admissionRow.Count -ne 1 -or
      [string]$matrixRow[0].immutable_dot5_predecessor -ne [string]$row.baseline.release -or
      [string]$matrixRow[0].pre_dot5_public_predecessor -ne [string]$row.pre_dot5.release -or
      (@($matrixRow[0].upgrade_rows) -join "|") -ne (@($row.upgrade_rows) -join "|") -or
      [string]$record.release -ne [string]$row.release -or [string]$record.target -ne [string]$row.factorio_line -or
      [string]$record.source_release.release -ne [string]$row.baseline.release -or
      [string]$record.state -ne "source-frozen" -or [string]$record.candidate_id -ne [string]$record.candidate_allocation.assigned_id) {
    throw "Terminal target, admission, release record, and projection profile disagree for $($row.release)."
  }
  if ((@($admissionRow[0].findings) -join "|") -ne (@($row.product_findings) -join "|")) {
    throw "Terminal product finding disposition disagrees for $($row.release)."
  }
  foreach ($input in @($row.baseline, $row.pre_dot5)) {
    if ((& git -C $RepoRoot rev-parse "$([string]$input.tag)^{commit}").Trim() -ne [string]$input.commit) {
      throw "Terminal projection input tag moved: $($input.tag)"
    }
  }
  if ([string]$row.support_tier -in @("maintained", "lts", "historical", "finite") -and
      [string]$row.exact_engine_sha256 -notmatch '^[0-9A-F]{64}$') {
    throw "Maintained or lower terminal projection lacks an exact engine SHA-256 for $($row.release)."
  }
  foreach ($overlay in @($row.assurance_overlays)) {
    if ((& git -C $RepoRoot rev-parse "$([string]$overlay.commit)^{commit}").Trim() -ne [string]$overlay.commit) {
      throw "Terminal assurance overlay commit is unavailable for $($row.release): $($overlay.id)"
    }
    foreach ($file in @($overlay.files)) {
      if ((& git -C $RepoRoot rev-parse "$([string]$overlay.commit):$([string]$file.path)").Trim() -ne [string]$file.blob) {
        throw "Terminal assurance overlay blob is unavailable for $($row.release): $($file.path)"
      }
    }
    if ([string]$row.release -eq "2.5.9") {
      $publicationRef = @($sourcePublication.refs | Where-Object { @($_.overlay_ids) -contains [string]$overlay.id })
      if ($publicationRef.Count -ne 1) {
        throw "Terminal assurance overlay lacks one published source ref: $($overlay.id)"
      }
      & git -C $RepoRoot merge-base --is-ancestor ([string]$overlay.commit) ([string]$publicationRef[0].head_commit)
      if ($LASTEXITCODE -ne 0) {
        throw "Published terminal source ref does not contain assurance overlay $($overlay.id)."
      }
    }
  }
}

$maintainedOverlayIds = @(
  @($profiles.targets | Where-Object release -eq "2.5.9")[0].assurance_overlays |
    ForEach-Object { [string]$_.id }
)
if ((@($publishedOverlayIds | Sort-Object) -join "|") -ne (@($maintainedOverlayIds | Sort-Object) -join "|")) {
  throw "Terminal shadow source publication does not cover the exact maintained overlay set."
}

$testRoot = Join-Path $RepoRoot ("build/tests/terminal-shadow-projection/" + [guid]::NewGuid().ToString("N"))
$materializerSourceRoot = Join-Path $testRoot "frozen-source"
$sourceFreeze = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir/releases/terminal/MIR3TerminalSourceFreezeV1.json") | ConvertFrom-Json -Depth 100
& git -C $RepoRoot worktree add --detach $materializerSourceRoot ([string]$sourceFreeze.common_source.commit)
if ($LASTEXITCODE -ne 0) { throw "Unable to materialize the frozen pre-allocation source for projection regression tests." }
try {
  foreach ($row in @($profiles.targets)) {
    $targetRoot = Join-Path $testRoot ([string]$row.release)
    [void](New-Item -ItemType Directory -Force -Path $targetRoot)
    $infoText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):info.json") -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($infoText)) { throw "Unable to read exact predecessor metadata for $($row.release)." }
    Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot "info.json") -Text ($infoText + "`n")

    $changelogText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):changelog.txt" 2>$null) -join "`n"
    Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot "changelog.txt") -Text ($changelogText + "`n")

    [void](New-Item -ItemType Directory -Force -Path (Join-Path $targetRoot ".mir"))
    $assuranceText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):.mir/assurance.json") -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($assuranceText)) { throw "Unable to read exact predecessor assurance profile for $($row.release)." }
    Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot ".mir/assurance.json") -Text ($assuranceText + "`n")
    $fixturesText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):.mir/fixtures.yml") -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($fixturesText)) { throw "Unable to read exact predecessor fixture registry for $($row.release)." }
    Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot ".mir/fixtures.yml") -Text ($fixturesText + "`n")
    $docsText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):.mir/docs.yml") -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($docsText)) { throw "Unable to read exact predecessor documentation registry for $($row.release)." }
    Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot ".mir/docs.yml") -Text ($docsText + "`n")
    [void](New-Item -ItemType Directory -Force -Path (Join-Path $targetRoot "scripts"))
    $assuranceEntryPointText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):scripts/Invoke-MIRAssurance.ps1") -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($assuranceEntryPointText)) { throw "Unable to read exact predecessor assurance entry point for $($row.release)." }
    Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot "scripts/Invoke-MIRAssurance.ps1") -Text ($assuranceEntryPointText + "`n")
    $assuranceSelfTestText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):scripts/Test-MIRAssurance.ps1") -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($assuranceSelfTestText)) { throw "Unable to read exact predecessor assurance self-test wrapper for $($row.release)." }
    Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot "scripts/Test-MIRAssurance.ps1") -Text ($assuranceSelfTestText + "`n")
    if ([string]$row.support_tier -ne "current") {
      $validateWorkflowText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):.github/workflows/validate.yml") -join "`n"
      if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($validateWorkflowText)) { throw "Unable to read exact predecessor hosted validation workflow for $($row.release)." }
      Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot ".github/workflows/validate.yml") -Text ($validateWorkflowText + "`n")
    }
    & git -C $RepoRoot cat-file -e "$([string]$row.baseline.tag):.github/workflows/assurance-fast.yml" 2>$null
    if ($LASTEXITCODE -eq 0) {
      $assuranceFastWorkflowText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):.github/workflows/assurance-fast.yml") -join "`n"
      Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot ".github/workflows/assurance-fast.yml") -Text ($assuranceFastWorkflowText + "`n")
    }
    foreach ($releaseLibraryPath in @("scripts/MIRAssurance/Release.ps1", "tools/lib/assurance/Release.ps1")) {
      & git -C $RepoRoot cat-file -e "$([string]$row.baseline.tag):$releaseLibraryPath" 2>$null
      if ($LASTEXITCODE -ne 0) { continue }
      $releaseLibraryText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):$releaseLibraryPath") -join "`n"
      if ([string]::IsNullOrWhiteSpace($releaseLibraryText)) { throw "Unable to read exact predecessor assurance release library for $($row.release): $releaseLibraryPath" }
      $releaseLibraryDestination = Join-Path $targetRoot $releaseLibraryPath
      [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $releaseLibraryDestination))
      Write-MIRTerminalProjectionTestText -Path $releaseLibraryDestination -Text ($releaseLibraryText + "`n")
    }
    if ([string]$row.support_tier -in @("lts", "historical", "finite")) {
      $validationEntryPointText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):scripts/Invoke-MIRValidation.ps1") -join "`n"
      if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($validationEntryPointText)) { throw "Unable to read exact predecessor validation entry point for $($row.release)." }
      Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot "scripts/Invoke-MIRValidation.ps1") -Text ($validationEntryPointText + "`n")
      $upgradeHarnessText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):scripts/Test-MIRUpgrade.ps1") -join "`n"
      if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($upgradeHarnessText)) { throw "Unable to read exact predecessor upgrade harness for $($row.release)." }
      Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot "scripts/Test-MIRUpgrade.ps1") -Text ($upgradeHarnessText + "`n")
      $backportLockText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):.mir/backport-source-lock.json") -join "`n"
      if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($backportLockText)) { throw "Unable to read exact predecessor backport source lock for $($row.release)." }
      Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot ".mir/backport-source-lock.json") -Text ($backportLockText + "`n")
      $backportLock = $backportLockText | ConvertFrom-Json -Depth 100
      $featureText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):$([string]$backportLock.feature_classification)") -join "`n"
      if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($featureText)) { throw "Unable to read exact predecessor feature classification for $($row.release)." }
      $featureDestination = Join-Path $targetRoot ([string]$backportLock.feature_classification)
      [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $featureDestination))
      Write-MIRTerminalProjectionTestText -Path $featureDestination -Text ($featureText + "`n")
    }

    if ([string]$row.release -eq "2.5.9") {
      $convergenceText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):.mir/convergence.yml") -join "`n"
      Write-MIRTerminalProjectionTestText -Path (Join-Path $targetRoot ".mir/convergence.yml") -Text ($convergenceText + "`n")
    }

    & $commandPath -Release ([string]$row.release) -TargetRoot $targetRoot -SourceRepoRoot $materializerSourceRoot
    if ($LASTEXITCODE -ne 0) { throw "Terminal projection materialization failed for $($row.release)." }
    $convergencePath = Join-Path $targetRoot ".mir/convergence.yml"
    $firstConvergenceText = [IO.File]::ReadAllText($convergencePath)
    if ($firstConvergenceText.Contains("`r")) {
      throw "Terminal projection materialization did not write canonical LF authority for $($row.release)."
    }
    $firstConvergenceHash = (Get-FileHash -LiteralPath $convergencePath -Algorithm SHA256).Hash
    $firstProjectionState = @(
      Get-ChildItem -LiteralPath $targetRoot -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
          $relativePath = $_.FullName.Substring($targetRoot.Length).TrimStart([char[]]@("\", "/")).Replace("\", "/")
          "$relativePath|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
        }
    ) -join "`n"
    & $commandPath -Release ([string]$row.release) -TargetRoot $targetRoot -SourceRepoRoot $materializerSourceRoot
    $secondProjectionState = @(
      Get-ChildItem -LiteralPath $targetRoot -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
          $relativePath = $_.FullName.Substring($targetRoot.Length).TrimStart([char[]]@("\", "/")).Replace("\", "/")
          "$relativePath|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
        }
    ) -join "`n"
    if ($LASTEXITCODE -ne 0 -or
        (Get-FileHash -LiteralPath $convergencePath -Algorithm SHA256).Hash -ne $firstConvergenceHash -or
        $secondProjectionState -cne $firstProjectionState) {
      throw "Terminal projection materialization is not idempotent for $($row.release)."
    }
    & $commandPath -Release ([string]$row.release) -TargetRoot $targetRoot -SourceRepoRoot $materializerSourceRoot -Check
    if ($LASTEXITCODE -ne 0) { throw "Terminal projection check failed for $($row.release)." }

    $info = Get-Content -Raw -LiteralPath (Join-Path $targetRoot "info.json") | ConvertFrom-Json
    $record = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/releases/records/$([string]$row.release).json") | ConvertFrom-Json -Depth 100
    $package = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/releases/terminal/shadows/$([string]$row.release)/package-manifest.json") | ConvertFrom-Json -Depth 100
    $qualification = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/releases/terminal/shadows/$([string]$row.release)/qualification-context.json") | ConvertFrom-Json -Depth 100
    $transition = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/releases/terminal/shadows/$([string]$row.release)/transition-plan.json") | ConvertFrom-Json -Depth 100
    $convergence = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/convergence.yml")
    $assurance = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/assurance.json") | ConvertFrom-Json -Depth 100
    $assuranceSelfTest = Get-Content -Raw -LiteralPath (Join-Path $targetRoot "scripts/Test-MIRAssurance.ps1")
    $hostedValidation = if ([string]$row.support_tier -ne "current") {
      Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".github/workflows/validate.yml")
    } else { "" }
    $hostedTargetPattern = '--target\s+[''"]?' + [regex]::Escape([string]$row.factorio_line) + '[''"]?(?:\s|$)'
    $shadowProfile = @($assurance.profiles.'terminal-shadow-convergence' | ForEach-Object { [string]$_ })
    $releaseGovernance = @($assurance.classes | Where-Object { [string]$_.id -eq "release-governance" })
    $docsRegistry = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/docs.yml")
    if ([string]$row.support_tier -eq "maintained" -and
        (-not $hostedValidation.Contains("Download isolated worker evidence") -or
         -not $hostedValidation.Contains("Import exact worker evidence deterministically") -or
         -not $hostedValidation.Contains("artifacts/assurance/worker-evidence") -or
         -not $hostedValidation.Contains('foreach ($row in @($plan.work))') -or
         -not $hostedValidation.Contains("Exact worker evidence is missing") -or
         $hostedValidation.Contains("merge-multiple: true"))) {
      throw "Maintained terminal projection does not replace stale cached terminal markers with exact planned worker evidence."
    }
    foreach ($releaseLibraryPath in @("scripts/MIRAssurance/Release.ps1", "tools/lib/assurance/Release.ps1")) {
      $releaseLibraryFullPath = Join-Path $targetRoot $releaseLibraryPath
      if (-not (Test-Path -LiteralPath $releaseLibraryFullPath -PathType Leaf)) { continue }
      $releaseLibrarySource = Get-Content -Raw -LiteralPath $releaseLibraryFullPath
      if ($releaseLibrarySource.Contains('branch --show-current') -and
          (-not $releaseLibrarySource.Contains('(@(& git -C $repo branch --show-current) -join "").Trim()') -or
           $releaseLibrarySource.Contains('([string](& git -C $repo branch --show-current)).Trim()') -or
           $releaseLibrarySource.Contains('(& git -C $repo branch --show-current).Trim()'))) {
        throw "Terminal projection left a detached-HEAD-unsafe release authority for $($row.release): $releaseLibraryPath"
      }
    }
    $releaseNoteRegistryCount = [regex]::Matches(
      $docsRegistry,
      ('(?m)^\s*- path: ' + [regex]::Escape("docs/releases/notes/release-notes-$([string]$row.release).md") + '$')
    ).Count
    if ([string]$info.version -ne [string]$row.release -or [string]$info.factorio_version -ne [string]$row.factorio_line -or
        [string]$record.release -ne [string]$row.release -or [string]$package.release -ne [string]$row.release -or
        [string]$qualification.release -ne [string]$row.release -or [string]$transition.release -ne [string]$row.release -or
        $convergence -notmatch '(?m)^schema: 1$' -or
        $convergence -notmatch ('(?m)^  version: "' + [regex]::Escape([string]$row.release) + '"$') -or
        $convergence -notmatch ('(?m)^  baseline_commit: ' + [regex]::Escape([string]$row.baseline.commit) + '$') -or
        ([string]$row.support_tier -ne "current" -and
          ($assuranceSelfTest.Contains('throw "MIR assurance self-test failed."') -or
           $hostedValidation -notmatch $hostedTargetPattern -or
           -not $hostedValidation.Contains("more-infinite-research_$([string]$row.release).zip") -or
           -not $hostedValidation.Contains('.\scripts\Build-MIRPackage.ps1 -OutputDir dist') -or
           @($transition.generated_authorities | Where-Object { [string]$_ -eq "scripts/Test-MIRAssurance.ps1" }).Count -ne 1 -or
           @($transition.generated_authorities | Where-Object { [string]$_ -eq ".github/workflows/validate.yml" }).Count -ne 1)) -or
        ($shadowProfile -join '|') -ne 'tooling.self-test|static.balance|static.museum|runtime.full|runtime.exact-zip' -or
        $shadowProfile -contains 'runtime.upgrade' -or $shadowProfile -contains 'runtime.ecosystem' -or
        $releaseGovernance.Count -ne 1 -or
        @($releaseGovernance[0].patterns | Where-Object { [string]$_ -eq '^\.mir/releases/(records/|terminal/shadows/)' }).Count -ne 1 -or
        $releaseNoteRegistryCount -ne 1) {
      throw "Terminal projection did not align every release-local authority for $($row.release)."
    }
    foreach ($overlay in @($row.assurance_overlays)) {
      foreach ($file in @($overlay.files)) {
        $materializedBlob = (& git hash-object --no-filters -- (Join-Path $targetRoot ([string]$file.path))).Trim()
        $transitionOutput = @($row.performance_transition.output_blobs | Where-Object { [string]$_.path -eq [string]$file.path })
        $orderedOverlayOutputs = @(
          foreach ($orderedOverlay in @($row.assurance_overlays)) {
            foreach ($orderedFile in @($orderedOverlay.files)) {
              if ([string]$orderedFile.path -eq [string]$file.path) { $orderedFile }
            }
          }
        )
        $expectedBlob = if ($transitionOutput.Count -eq 1) {
          [string]$transitionOutput[0].blob
        } elseif ($orderedOverlayOutputs.Count -gt 0) {
          [string]$orderedOverlayOutputs[-1].blob
        } else {
          [string]$file.blob
        }
        if ($materializedBlob -ne $expectedBlob) {
          $materializedPath = Join-Path $targetRoot ([string]$file.path)
          $materializedText = (Get-Content -Raw -LiteralPath $materializedPath).Replace("`r`n", "`n").Replace("`r", "`n")
          $expectedText = ((@(& git -C $RepoRoot cat-file blob $expectedBlob) -join "`n").TrimEnd() + "`n")
          if (-not (Test-MIRTerminalDetachedHeadEquivalent -RelativePath ([string]$file.path) -ActualText $materializedText -ExpectedText $expectedText)) {
            throw "Terminal projection did not materialize exact assurance overlay $($overlay.id): $($file.path)"
          }
        }
      }
    }
    if ([string]$row.support_tier -in @("lts", "historical", "finite")) {
      $upgradeManifestPath = Join-Path $targetRoot ".mir/releases/terminal/shadows/$([string]$row.release)/upgrade-fixtures.json"
      $upgradeManifest = Get-Content -Raw -LiteralPath $upgradeManifestPath | ConvertFrom-Json -Depth 100
      $fixtureRegistry = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/fixtures.yml")
      $assuranceEntryPoint = Get-Content -Raw -LiteralPath (Join-Path $targetRoot "scripts/Invoke-MIRAssurance.ps1")
      $assuranceFastWorkflow = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".github/workflows/assurance-fast.yml")
      $assuranceReleaseLibrary = Get-Content -Raw -LiteralPath (Join-Path $targetRoot "scripts/MIRAssurance/Release.ps1")
      $validationEntryPoint = Get-Content -Raw -LiteralPath (Join-Path $targetRoot "scripts/Invoke-MIRValidation.ps1")
      $upgradeHarness = Get-Content -Raw -LiteralPath (Join-Path $targetRoot "scripts/Test-MIRUpgrade.ps1")
      $backportLock = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/backport-source-lock.json") | ConvertFrom-Json -Depth 100
      $featureClassification = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ([string]$backportLock.feature_classification)) | ConvertFrom-Json -Depth 100
      if ([string]$upgradeManifest.release -ne [string]$row.release -or
          (@($upgradeManifest.rows.id) -join '|') -ne (@($row.upgrade_rows) -join '|') -or
          [string]$qualification.upgrade_fixture_manifest -ne ".mir/releases/terminal/shadows/$([string]$row.release)/upgrade-fixtures.json" -or
          [string]$qualification.exact_engine_sha256 -ne [string]$row.exact_engine_sha256 -or
          -not $assuranceEntryPoint.Contains('function Get-MIRAssuranceFactorioVersion {') -or
          -not $assuranceEntryPoint.Contains('[void]$start.ArgumentList.Add("--version")') -or
          -not $assuranceEntryPoint.Contains('branch=(@(& git -C $repo branch --show-current) -join "").Trim()') -or
          $assuranceEntryPoint.Contains('branch=([string](& git -C $repo branch --show-current)).Trim()') -or
          -not $assuranceFastWorkflow.Contains('workflow_dispatch:') -or
          $assuranceFastWorkflow.Contains("`n  push:") -or
          -not $assuranceFastWorkflow.Contains("--target '$([string]$row.factorio_line)'") -or
          @($transition.generated_authorities | Where-Object { [string]$_ -eq ".github/workflows/assurance-fast.yml" }).Count -ne 1 -or
          -not $assuranceReleaseLibrary.Contains('$branch = (@(& git -C $repo branch --show-current) -join "").Trim()') -or
          $assuranceReleaseLibrary.Contains('$branch = ([string](& git -C $repo branch --show-current)).Trim()') -or
          $assuranceReleaseLibrary.Contains('$branch = (& git -C $repo branch --show-current).Trim()') -or
          -not $validationEntryPoint.Contains('$generatedUserDataRoot = Join-Path $repo "build\validation-userdata"') -or
          -not $validationEntryPoint.Contains('function Remove-MIRGeneratedValidationUserData {') -or
          $validationEntryPoint.Contains('[System.IO.Path]::GetTempPath()') -or
          ([string]$row.release -eq "1.6.9" -and
            (-not $upgradeHarness.Contains("# MIR3-TERMINAL-0.16-HEADLESS-UPGRADE-LOAD") -or
             -not $upgradeHarness.Contains('"--start-server", $save, "--until-tick", "1"') -or
             $upgradeHarness.Contains('"--benchmark", $save'))) -or
          [string]$backportLock.mir_version -ne [string]$row.release -or
          [string]$backportLock.release_notes -ne "docs/releases/notes/release-notes-$([string]$row.release).md" -or
          [string]$featureClassification.mir_version -ne [string]$row.release -or
          [string]$featureClassification.canonical_dev_anchor -ne [string]$backportLock.canonical_dev_anchor -or
          -not (Get-Content -Raw -LiteralPath (Join-Path $targetRoot "docs/releases/notes/release-notes-$([string]$row.release).md")).Contains([string]$backportLock.canonical_dev_anchor)) {
        throw "Terminal projection did not bind both target-native upgrade rows for $($row.release)."
      }
      foreach ($upgradeRow in @($upgradeManifest.rows)) {
        $fixturePath = Join-Path $targetRoot ([string]$upgradeRow.generated_fixture)
        $fixtureInfo = Get-Content -Raw -LiteralPath (Join-Path $fixturePath "info.json") | ConvertFrom-Json
        $fixtureControl = Get-Content -Raw -LiteralPath (Join-Path $fixturePath "control.lua")
        $fixtureSettingsPath = Join-Path $fixturePath "settings-updates.lua"
        $fixtureSettings = if (Test-Path -LiteralPath $fixtureSettingsPath -PathType Leaf) {
          Get-Content -Raw -LiteralPath $fixtureSettingsPath
        } else {
          ""
        }
        $fromVersion = [string]$upgradeRow.from.release
        if ([string]$fixtureInfo.name -notmatch ([regex]::Escape($fromVersion.Replace('.', '-')) + '-to-' + [regex]::Escape(([string]$row.release).Replace('.', '-'))) -or
            @($fixtureInfo.dependencies | Where-Object { [string]$_ -eq "more-infinite-research >= $fromVersion" }).Count -ne 1 -or
            -not $fixtureControl.Contains("local from_version = `"$fromVersion`"") -or
            -not $fixtureControl.Contains("local to_version = `"$([string]$row.release)`"") -or
            ($fixtureSettings -and -not $fixtureSettings.Contains($fromVersion)) -or
            -not $fixtureRegistry.Contains("assertion_path: $([string]$upgradeRow.generated_fixture)")) {
          throw "Terminal upgrade fixture is stale or unregistered: $($upgradeRow.id)"
        }
      }
    }
    if ([string]$row.support_tier -eq "current") {
      $upgradeManifestPath = Join-Path $targetRoot ".mir/releases/terminal/shadows/$([string]$row.release)/upgrade-fixtures.json"
      $upgradeManifest = Get-Content -Raw -LiteralPath $upgradeManifestPath | ConvertFrom-Json -Depth 100
      $fixtureRegistry = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/fixtures.yml")
      if ((@($upgradeManifest.rows.id) -join '|') -cne (@($row.upgrade_rows) -join '|') -or
          [string]$qualification.upgrade_fixture_manifest -ne ".mir/releases/terminal/shadows/$([string]$row.release)/upgrade-fixtures.json") {
        throw "Current-tier projection did not bind both upgrade rows for $($row.release)."
      }
      $preDot5Row = @($upgradeManifest.rows | Where-Object { [string]$_.from.release -eq [string]$row.pre_dot5.release })
      if ($preDot5Row.Count -ne 1 -or
          [string]$preDot5Row[0].source_fixture.commit -ne [string]$row.baseline.commit -or
          [string]$preDot5Row[0].source_fixture.path -ne "fixtures/assert-upgrade-3-2-3-to-3-2-5") {
        throw "Current-tier direct pre-.5 fixture does not retain immutable predecessor custody."
      }
      $fixtureRoot = Join-Path $targetRoot ([string]$preDot5Row[0].generated_fixture)
      foreach ($requiredFixtureFile in @("info.json", "control.lua", "data.lua", "data-final-fixes.lua", "settings.lua", "settings-updates.lua")) {
        if (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot $requiredFixtureFile) -PathType Leaf)) {
          throw "Current-tier direct pre-.5 fixture is incomplete: $requiredFixtureFile"
        }
      }
      $fixtureInfo = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot "info.json") | ConvertFrom-Json
      $fixtureControl = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot "control.lua")
      $fixtureData = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot "data.lua")
      $preDot5Version = [string]$row.pre_dot5.release
      $generatedFixtureName = Split-Path -Leaf ([string]$preDot5Row[0].generated_fixture)
      $sourceFixtureName = Split-Path -Leaf ([string]$preDot5Row[0].source_fixture.path)
      if (@($fixtureInfo.dependencies | Where-Object { [string]$_ -eq "more-infinite-research >= $preDot5Version" }).Count -ne 1 -or
          -not $fixtureControl.Contains("script.active_mods[`"more-infinite-research`"] ~= `"$preDot5Version`"") -or
          -not $fixtureControl.Contains("script.active_mods[`"more-infinite-research`"] ~= `"$([string]$row.release)`"") -or
          -not $fixtureControl.Contains("[mir-fixture] $preDot5Version to $([string]$row.release) upgrade proof complete") -or
          -not $fixtureControl.Contains("game.server_save(`"mir-$(([string]$row.release).Replace('.', ''))-upgraded`")") -or
          -not $fixtureData.Contains($generatedFixtureName) -or $fixtureData.Contains($sourceFixtureName) -or
          -not $fixtureRegistry.Contains("assertion_path: $([string]$preDot5Row[0].generated_fixture)")) {
        throw "Current-tier direct pre-.5 upgrade fixture is stale or unregistered."
      }
    }
    if ($null -ne $row.performance_transition) {
      foreach ($output in @($row.performance_transition.output_blobs)) {
        $materializedBlob = (& git hash-object --no-filters -- (Join-Path $targetRoot ([string]$output.path))).Trim()
        if ($materializedBlob -ne [string]$output.blob) { throw "Terminal projection did not materialize exact performance transition output $($row.performance_transition.id): $($output.path)" }
      }
    }
    if ([string]$row.release -eq "2.5.9") {
      $expectedDevelopment = $row.performance_transition.development_package
      $developmentAuthorities = @(
        $package.source.performance_transition.development_package,
        $qualification.performance_transition.development_package,
        $transition.immutable_inputs.performance_transition.development_package
      )
      foreach ($developmentAuthority in $developmentAuthorities) {
        if ([string]$developmentAuthority.version -ne [string]$expectedDevelopment.version -or
            [string]$developmentAuthority.package_source_commit -ne [string]$expectedDevelopment.package_source_commit -or
            [string]$developmentAuthority.package_source_sha256 -ne [string]$expectedDevelopment.package_source_sha256 -or
            [long]$developmentAuthority.archive_bytes -ne [long]$expectedDevelopment.archive_bytes -or
            [int]$developmentAuthority.archive_entries -ne [int]$expectedDevelopment.archive_entries -or
            [string]$developmentAuthority.archive_sha256 -ne [string]$expectedDevelopment.archive_sha256 -or
            [string]$developmentAuthority.package_content_sha256 -ne [string]$expectedDevelopment.package_content_sha256) {
          throw "The 2.5.9 generated shadow authorities do not bind exact development bytes and entries."
        }
      }
      $targetCatalog = Get-Content -Raw -LiteralPath (Join-Path $targetRoot "validation/tests.yml") | ConvertFrom-Json -Depth 100
      $ecosystemTest = @($targetCatalog.tests | Where-Object { [string]$_.id -eq "runtime.ecosystem" })
      if ($ecosystemTest.Count -ne 1 -or
          [string]$ecosystemTest[0].command -notmatch '^\./scripts/mir\.ps1\s' -or
          [string]$ecosystemTest[0].command -notmatch '--mods\s+<mods>' -or
          @($ecosystemTest[0].inputs) -notcontains "mod-lock") {
        throw "The 2.5.9 assurance projection must forward the exact planned mod closure into its target-native ecosystem gate."
      }
      $performanceTest = @($targetCatalog.tests | Where-Object { [string]$_.id -eq "runtime.performance-regression" })
      if ($performanceTest.Count -ne 1 -or
          [string]$performanceTest[0].command -notmatch '-OutputPath\s+<test-output>(?:\s|$)' -or
          [string]$performanceTest[0].command -match '-OutputPath\s+\.mir/evidence/' -or
          @($performanceTest[0].inputs) -notcontains "mod-closure") {
        throw "The 2.5.9 assurance projection must keep performance evidence content-addressed and bind the exact mod closure."
      }
      $validationFacade = Get-Content -Raw -LiteralPath (Join-Path $targetRoot "scripts/Invoke-MIRValidation.ps1")
      foreach ($requiredPolicy in @(
        '$generatedUserDataRoot = Join-Path $repo "build\validation-userdata"',
        '$resolvedValidationRoot.StartsWith($resolvedGeneratedRoot, [System.StringComparison]::OrdinalIgnoreCase)',
        'function Remove-MIRGeneratedValidationUserData {'
      )) {
        if (-not $validationFacade.Contains($requiredPolicy)) {
          throw "The 2.5.9 assurance projection does not preserve bounded repository-local validation userdata: $requiredPolicy"
        }
      }
    }
  }

  $tamperedRoot = Join-Path $testRoot "2.5.9"
  $tamperedPath = Join-Path $tamperedRoot ".mir/convergence.yml"
  $tampered = (Get-Content -Raw -LiteralPath $tamperedPath).Replace('  version: "2.5.9"', '  version: "2.5.5"')
  Write-MIRTerminalProjectionTestText -Path $tamperedPath -Text $tampered
  $rejected = $false
  try { & $commandPath -Release "2.5.9" -TargetRoot $tamperedRoot -SourceRepoRoot $materializerSourceRoot -Check } catch { $rejected = $true }
  if (-not $rejected) { throw "Terminal projection check accepted stale 2.5.5 convergence identity in a 2.5.9 shadow." }
} finally {
  & git -C $RepoRoot worktree remove --force $materializerSourceRoot 2>$null
  if (Test-Path -LiteralPath $testRoot -PathType Container) { Remove-MIRTerminalProjectionTestRoot -Path $testRoot }
}

Write-Host "[ok] exact predecessor inputs and the portable terminal source produce consistent release authority for all nine shadows."
