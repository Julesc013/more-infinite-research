param(
  [Parameter(Mandatory)][ValidateSet("3.2.11", "3.2.10", "3.2.9", "2.5.9")][string]$Release,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$CandidateSha,
  [ValidatePattern('^[0-9a-f]{40}$')][string]$ControllerSha = "",
  [ValidateSet("promotion", "post-publication-sync")][string]$Operation = "promotion",
  [string]$CandidateRef = "",
  [ValidateSet("main", "legacy")][string]$PromotionBranch = "main",
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path,
  [string]$OutputPath = "",
  [switch]$SkipRemote
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$controllerRepo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
. (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")

function Invoke-MIRPromotionGit {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  $output = @(& git -C $repo @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)" }
  return $output
}

$resolvedControllerSha = @(& git -C $controllerRepo rev-parse "HEAD^{commit}" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "The dispatched terminal controller commit could not be resolved." }
$resolvedControllerSha = ([string]($resolvedControllerSha | Select-Object -First 1)).Trim()
if (-not [string]::IsNullOrWhiteSpace($ControllerSha) -and $resolvedControllerSha -ne $ControllerSha) {
  throw "The executed terminal controller differs from the exact dispatched controller commit."
}
if (-not [string]::IsNullOrWhiteSpace($ControllerSha)) {
  & git -C $controllerRepo diff --quiet --exit-code HEAD --
  $controllerWorktreeDirty = $LASTEXITCODE -ne 0
  & git -C $controllerRepo diff --cached --quiet --exit-code HEAD --
  $controllerIndexDirty = $LASTEXITCODE -ne 0
  if ($controllerWorktreeDirty -or $controllerIndexDirty) {
    throw "The dispatched terminal controller checkout contains tracked changes outside its exact commit."
  }
}

if ($Release -eq "3.2.11") {
  if (($Operation -eq "promotion" -and $PromotionBranch -ne "main") -or
      ($Operation -eq "post-publication-sync" -and $PromotionBranch -ne "legacy")) {
    throw "The sealed 3.2.11 controller authorizes initial promotion only to main and post-publication alias synchronization only to legacy."
  }

  $head = (Invoke-MIRPromotionGit rev-parse "HEAD^{commit}" | Select-Object -First 1).Trim()
  $resolvedCommit = (Invoke-MIRPromotionGit rev-parse "$CandidateSha`^{commit}" | Select-Object -First 1).Trim()
  $resolvedTree = (Invoke-MIRPromotionGit rev-parse "$CandidateSha`^{tree}" | Select-Object -First 1).Trim()
  $resolvedParents = @(((Invoke-MIRPromotionGit show -s --format=%P $CandidateSha | Select-Object -First 1).Trim() -split '\s+') | Where-Object { $_ })
  if ($head -ne $CandidateSha -or $resolvedCommit -ne $CandidateSha) {
    throw "The 3.2.11 promotion workflow must check out the exact requested sealed head."
  }

  $authorityRepo = if ($Operation -eq "post-publication-sync") { $controllerRepo } else { $repo }
  $releaseRecordPath = Join-Path $authorityRepo ".mir/releases/records/3.2.11.json"
  $overridePath = Join-Path $authorityRepo ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixMaintainerReleaseOverrideV2.json"
  $reconstructionPath = Join-Path $authorityRepo ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixCandidateReconstructionV2.json"
  $qualificationPath = Join-Path $authorityRepo ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixLocalQualificationV2.json"
  $releaseRecord = Get-Content -Raw -LiteralPath $releaseRecordPath | ConvertFrom-Json -Depth 100
  $override = Get-Content -Raw -LiteralPath $overridePath | ConvertFrom-Json -Depth 100
  $reconstruction = Get-Content -Raw -LiteralPath $reconstructionPath | ConvertFrom-Json -Depth 100
  $qualification = Get-Content -Raw -LiteralPath $qualificationPath | ConvertFrom-Json -Depth 100

  $packageSourceCommit = [string]$releaseRecord.package.source_commit
  $packageSourceTree = (Invoke-MIRPromotionGit rev-parse "$packageSourceCommit`^{tree}" | Select-Object -First 1).Trim()
  Invoke-MIRPromotionGit merge-base --is-ancestor $packageSourceCommit $CandidateSha | Out-Null
  $packageRoots = @(Get-MIRPackageSourceRoots)
  $changedPackagePaths = @(Invoke-MIRPromotionGit diff --name-only $packageSourceCommit $CandidateSha -- @packageRoots)
  if ($packageSourceTree -ne [string]$releaseRecord.package.source_tree -or $changedPackagePaths.Count -ne 0) {
    throw "Package-visible source changed after the accepted C35 package-source commit."
  }

  $zipRelative = [string]$releaseRecord.package.archive
  $zip = Join-Path $repo $zipRelative
  if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) { throw "Accepted C35 ZIP is missing: $zipRelative" }
  $archiveSha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
  $contentSha = Get-MIRZipContentFingerprint -Path $zip
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($zip)
  try { $entries = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count }
  finally { $archive.Dispose() }
  $bytes = (Get-Item -LiteralPath $zip).Length
  $expectedReleaseState = if ($Operation -eq "post-publication-sync") { "publicly-verified" } else { "sealed" }

  if ($archiveSha -ne [string]$releaseRecord.package.archive_sha256 -or
      $contentSha -ne [string]$releaseRecord.package.content_sha256 -or
      $bytes -ne [long]$releaseRecord.package.bytes -or $entries -ne [int]$releaseRecord.package.entries -or
      [string]$releaseRecord.state -ne $expectedReleaseState -or [string]$releaseRecord.candidate_id -ne "C35" -or
      @($releaseRecord.assurance_exceptions).Count -ne 0 -or
      [string]$releaseRecord.source_release.tag -ne "3.2.10" -or
      [string]$releaseRecord.source_release.tag_commit -ne "4cbea531a1043e0cacb9ac5c496731c8d77bbdb6" -or
      [string]$override.status -ne "accepted-for-immediate-promotion" -or
      [string]$override.release -ne "3.2.11" -or [string]$override.candidate_id -ne "C35" -or
      [string]$override.candidate.archive_sha256 -ne $archiveSha -or
      [string]$override.candidate.content_sha256 -ne $contentSha -or
      [string]$override.maintainer_decision.accepted_factorio.version -ne "2.1.14" -or
      [string]$override.maintainer_decision.accepted_factorio.file_version -ne "2.1.14.87180" -or
      [string]$reconstruction.status -ne "passed" -or [string]$reconstruction.release -ne "3.2.11" -or
      [string]$reconstruction.candidate_id -ne "C35" -or [string]$reconstruction.archive.sha256 -ne $archiveSha -or
      @($reconstruction.builds).Count -ne 3 -or @($reconstruction.builds.sha256 | Select-Object -Unique).Count -ne 1 -or
      [string]$qualification.status -ne "exact-engine-and-governed-upgrades-passed" -or
      [string]$qualification.release -ne "3.2.11" -or [string]$qualification.candidate_id -ne "C35" -or
      [string]$qualification.candidate.archive_sha256 -ne $archiveSha -or
      [string]$qualification.candidate.content_sha256 -ne $contentSha -or
      [string]$qualification.engine.version -ne "2.1.14" -or
      [string]$qualification.engine.file_version -ne "2.1.14.87180" -or
      [string]$qualification.engine.binary_sha256 -ne "E396BD25C068DD4C5EF45E93E6A87DBA0E12EEA964B6A5B73163041CC4A6143F" -or
      [int]$qualification.governed_upgrades.passed -ne 15 -or [int]$qualification.governed_upgrades.required -ne 15 -or
      [string]$qualification.static_validation.status -ne "passed") {
    throw "The C35 seal, acceptance, deterministic reconstruction, exact-engine qualification, or archive identity is not exact."
  }

  foreach ($historical in @(
    [pscustomobject]@{tag="3.2.10";commit="4cbea531a1043e0cacb9ac5c496731c8d77bbdb6"},
    [pscustomobject]@{tag="2.5.10";commit="6bb483de9042a7ec4c93674933e7f6c1670d79aa"}
  )) {
    $historicalCommit = (Invoke-MIRPromotionGit rev-parse "$($historical.tag)^{commit}" | Select-Object -First 1).Trim()
    if ($historicalCommit -ne [string]$historical.commit) { throw "Historical tag $($historical.tag) moved." }
  }

  if ($Operation -eq "post-publication-sync") {
    if ($CandidateRef -notmatch '^refs/heads/[A-Za-z0-9._/-]+$' -or $CandidateRef.Contains('..')) {
      throw "Post-publication synchronization requires an exact safe refs/heads candidate ref."
    }

    $receiptPath = Join-Path $authorityRepo ".mir/evidence/terminal-publication/2026-08-18/github/3.2.11.json"
    $closurePath = Join-Path $authorityRepo ".mir/releases/terminal/closures/3.2.11.json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $closurePath -PathType Leaf)) {
      throw "The append-only 3.2.11 publication receipt or release closure is missing."
    }
    $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100
    $closure = Get-Content -Raw -LiteralPath $closurePath | ConvertFrom-Json -Depth 100
    $releaseCommit = [string]$releaseRecord.proofs.tag.commit
    $tagObject = (Invoke-MIRPromotionGit rev-parse refs/tags/3.2.11 | Select-Object -First 1).Trim()
    $tagCommit = (Invoke-MIRPromotionGit rev-parse 'refs/tags/3.2.11^{commit}' | Select-Object -First 1).Trim()
    $releasePackageChanges = @(Invoke-MIRPromotionGit diff --name-only $releaseCommit $CandidateSha -- @packageRoots)

    if ([string]$releaseRecord.state -ne "publicly-verified" -or
        $releaseCommit -ne "e3d787deb35ff30157bb2013fa1cc745a445e629" -or
        $tagObject -ne [string]$releaseRecord.proofs.tag.tag_object -or $tagCommit -ne $releaseCommit -or
        [string]$receipt.kind -ne "Mir3PostTerminalEmergencyPublicationReceiptV1" -or
        [string]$receipt.status -ne "published-and-verified" -or
        [string]$receipt.candidate_commit -ne $releaseCommit -or
        [string]$receipt.tag.object_sha -ne $tagObject -or
        [string]$receipt.tag.peeled_commit -ne $releaseCommit -or -not [bool]$receipt.tag.immutable -or
        [string]$receipt.archive_sha256 -ne $archiveSha -or [string]$receipt.download_sha256 -ne $archiveSha -or
        [string]$receipt.content_sha256 -ne $contentSha -or
        [long]$receipt.bytes -ne $bytes -or [int]$receipt.entries -ne $entries -or
        [long]$receipt.github_release.id -ne 371825678 -or
        [bool]$receipt.github_release.draft -or [bool]$receipt.github_release.prerelease -or
        [long]$receipt.asset.id -ne 518275792 -or
        [string]$closure.kind -ne "Mir3TerminalReleaseClosureV1" -or
        [string]$closure.status -ne "github-closed-mod-portal-pending" -or
        [string]$closure.tag.peeled_commit -ne $releaseCommit -or
        [string]$closure.github.download_sha256 -ne $archiveSha -or
        $releasePackageChanges.Count -ne 0) {
      throw "Published 3.2.11 authority, immutable tag, public receipt, closure, or package identity is not exact."
    }

    $candidateRemote = "not-checked"
    $mainRemote = "not-checked"
    $legacyRemote = "not-checked"
    $expectedLegacyCommit = "20210a90d97c52426ea6abc7c94a89bb8ec7671b"
    $publishedMainTree = (Invoke-MIRPromotionGit rev-parse "$releaseCommit`^{tree}" | Select-Object -First 1).Trim()
    if ($resolvedParents.Count -ne 2 -or $resolvedParents[0] -ne $expectedLegacyCommit -or
        $resolvedParents[1] -ne $releaseCommit -or $resolvedTree -ne $publishedMainTree) {
      throw "The 3.2.11 legacy alias candidate must be a two-parent commit whose tree is exactly protected main."
    }
    Invoke-MIRPromotionGit merge-base --is-ancestor $expectedLegacyCommit $CandidateSha | Out-Null
    Invoke-MIRPromotionGit merge-base --is-ancestor $releaseCommit $CandidateSha | Out-Null
    if (-not $SkipRemote) {
      $candidateRemoteLine = @(Invoke-MIRPromotionGit ls-remote --heads origin $CandidateRef)
      $candidateRemote = if ($candidateRemoteLine.Count -eq 1) { ([string]$candidateRemoteLine[0] -split '\s+')[0] } else { "" }
      $mainRemoteLine = @(Invoke-MIRPromotionGit ls-remote --heads origin refs/heads/main)
      $mainRemote = if ($mainRemoteLine.Count -eq 1) { ([string]$mainRemoteLine[0] -split '\s+')[0] } else { "" }
      $legacyRemoteLine = @(Invoke-MIRPromotionGit ls-remote --heads origin refs/heads/legacy)
      $legacyRemote = if ($legacyRemoteLine.Count -eq 1) { ([string]$legacyRemoteLine[0] -split '\s+')[0] } else { "" }
      if ($candidateRemote -ne $CandidateSha -or $mainRemote -ne $releaseCommit -or
          $legacyRemote -ne $expectedLegacyCommit -or
          $resolvedParents.Count -ne 2 -or $resolvedParents[0] -ne $legacyRemote -or
          $resolvedParents[1] -ne $mainRemote) {
        throw "The 3.2.11 legacy alias candidate must preserve the exact published alias as first parent and protected main as second parent."
      }
      $mainTree = (Invoke-MIRPromotionGit rev-parse "$mainRemote`^{tree}" | Select-Object -First 1).Trim()
      if ($resolvedTree -ne $mainTree) {
        throw "The 3.2.11 legacy alias promotion tree must be exactly identical to protected main."
      }
    }

    $result = [ordered]@{
      schema = 1
      status = "passed"
      operation = "post-publication-authority-sync-verification"
      release = $Release
      controller_commit = $resolvedControllerSha
      authority_source_commit = $resolvedControllerSha
      candidate_commit = $CandidateSha
      candidate_tree = $resolvedTree
      parents = $resolvedParents
      candidate_ref = $CandidateRef
      candidate_remote = $candidateRemote
      release_commit = $releaseCommit
      tag_object = $tagObject
      package_source_commit = $packageSourceCommit
      package_visible_changes_after_release = @($releasePackageChanges)
      promotion_branch = "legacy"
      promotion_branch_remote = $legacyRemote
      protected_main_commit = $mainRemote
      archive = [ordered]@{path=$zipRelative;sha256=$archiveSha;content_sha256=$contentSha;bytes=$bytes;entries=$entries}
      publication_receipt = ".mir/evidence/terminal-publication/2026-08-18/github/3.2.11.json"
      release_closure = ".mir/releases/terminal/closures/3.2.11.json"
      authorization = "legacy-alias-post-publication-sync-only"
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
      $resolvedOutput = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repo $OutputPath }
      $parent = Split-Path -Parent $resolvedOutput
      if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
      [IO.File]::WriteAllText($resolvedOutput, (($result | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
    }
    $result | ConvertTo-Json -Depth 20
    exit 0
  }

  $candidateRef = "refs/heads/agent/mir3-2.5.11-cap-display-fix"
  $candidateRemote = "not-checked"
  $mainRemote = "not-checked"
  if (-not $SkipRemote) {
    $candidateRemoteLine = @(Invoke-MIRPromotionGit ls-remote --heads origin $candidateRef)
    $candidateRemote = if ($candidateRemoteLine.Count -eq 1) { ([string]$candidateRemoteLine[0] -split '\s+')[0] } else { "" }
    $mainRemoteLine = @(Invoke-MIRPromotionGit ls-remote --heads origin refs/heads/main)
    $mainRemote = if ($mainRemoteLine.Count -eq 1) { ([string]$mainRemoteLine[0] -split '\s+')[0] } else { "" }
    if ($candidateRemote -ne $CandidateSha -or $mainRemote -ne "4ff688c58c07b695be6ae6ebe021c5c7e5e1fa95") {
      throw "Remote C35 head or protected main predecessor changed before 3.2.11 promotion."
    }
    Invoke-MIRPromotionGit merge-base --is-ancestor $mainRemote $CandidateSha | Out-Null
  }

  $result = [ordered]@{
    schema = 1
    status = "passed"
    operation = "post-terminal-emergency-candidate-promotion-verification"
    release = $Release
    controller_commit = $resolvedControllerSha
    candidate_commit = $CandidateSha
    candidate_tree = $resolvedTree
    parents = $resolvedParents
    candidate_ref = $candidateRef
    candidate_remote = $candidateRemote
    package_source_commit = $packageSourceCommit
    package_visible_changes_after_freeze = @($changedPackagePaths)
    promotion_branch = "main"
    promotion_from = $mainRemote
    promotion_to = $CandidateSha
    archive = [ordered]@{path=$zipRelative;sha256=$archiveSha;content_sha256=$contentSha;bytes=$bytes;entries=$entries}
    acceptance = $overridePath.Substring($repo.Length + 1).Replace('\', '/')
    reconstruction = $reconstructionPath.Substring($repo.Length + 1).Replace('\', '/')
    qualification = $qualificationPath.Substring($repo.Length + 1).Replace('\', '/')
    authorization = "github-publication-only"
  }

  if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repo $OutputPath }
    $parent = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
    [IO.File]::WriteAllText($resolvedOutput, (($result | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
  }
  $result | ConvertTo-Json -Depth 20
  exit 0
}

if ($Release -eq "3.2.10") {
  $head = (Invoke-MIRPromotionGit rev-parse "HEAD^{commit}" | Select-Object -First 1).Trim()
  $resolvedCommit = (Invoke-MIRPromotionGit rev-parse "$CandidateSha`^{commit}" | Select-Object -First 1).Trim()
  $resolvedTree = (Invoke-MIRPromotionGit rev-parse "$CandidateSha`^{tree}" | Select-Object -First 1).Trim()
  $resolvedParents = @(((Invoke-MIRPromotionGit show -s --format=%P $CandidateSha | Select-Object -First 1).Trim() -split '\s+') | Where-Object { $_ })
  if ($head -ne $CandidateSha -or $resolvedCommit -ne $CandidateSha) {
    throw "The emergency promotion workflow must check out the exact requested candidate head."
  }

  $releaseRecordPath = Join-Path $repo ".mir/releases/records/3.2.10.json"
  $overridePath = Join-Path $repo ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixMaintainerReleaseOverrideV1.json"
  $deltaPath = Join-Path $repo ".mir/releases/deltas/3.2.9-to-3.2.10.json"
  $releaseRecord = Get-Content -Raw -LiteralPath $releaseRecordPath | ConvertFrom-Json -Depth 100
  $override = Get-Content -Raw -LiteralPath $overridePath | ConvertFrom-Json -Depth 100
  $delta = Get-Content -Raw -LiteralPath $deltaPath | ConvertFrom-Json -Depth 100

  $packageSourceCommit = [string]$releaseRecord.package.source_commit
  $packageSourceTree = (Invoke-MIRPromotionGit rev-parse "$packageSourceCommit`^{tree}" | Select-Object -First 1).Trim()
  Invoke-MIRPromotionGit merge-base --is-ancestor $packageSourceCommit $CandidateSha | Out-Null
  $packageRoots = @(Get-MIRPackageSourceRoots)
  $changedPackagePaths = @(Invoke-MIRPromotionGit diff --name-only $packageSourceCommit $CandidateSha -- @packageRoots)
  if ($packageSourceTree -ne [string]$releaseRecord.package.source_tree -or $changedPackagePaths.Count -ne 0) {
    throw "Package-visible source changed after the accepted C34 package-source commit."
  }

  $zipRelative = [string]$releaseRecord.package.archive
  $zip = Join-Path $repo $zipRelative
  if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) { throw "Accepted C34 ZIP is missing: $zipRelative" }
  $archiveSha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
  $contentSha = Get-MIRZipContentFingerprint -Path $zip
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($zip)
  try { $entries = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count }
  finally { $archive.Dispose() }
  $bytes = (Get-Item -LiteralPath $zip).Length
  if ($archiveSha -ne [string]$releaseRecord.package.archive_sha256 -or
      $contentSha -ne [string]$releaseRecord.package.content_sha256 -or
      $bytes -ne [long]$releaseRecord.package.bytes -or $entries -ne [int]$releaseRecord.package.entries) {
    throw "Accepted C34 ZIP identity differs from the ReleaseRecord."
  }

  if ($Operation -eq "promotion" -and
      ([string]$releaseRecord.state -ne "manually-accepted" -or [string]$releaseRecord.candidate_id -ne "C34" -or
      [string]$override.status -ne "accepted-for-immediate-promotion" -or
      [string]$override.release -ne "3.2.10" -or [string]$override.candidate_id -ne "C34" -or
      [string]$override.candidate.archive_sha256 -ne $archiveSha -or
      [string]$override.maintainer_decision.accepted_factorio.version -ne "2.1.14" -or
      [string]$override.maintainer_decision.factorio_2_1_13_gate -ne "waived and superseded for 3.2.10 only" -or
      [string]$delta.status -ne "approved-under-release-specific-maintainer-override" -or
      [string]$delta.candidate.archive_sha256 -ne $archiveSha -or
      [string]$delta.transition.from_version -ne "3.2.9" -or [string]$delta.transition.to_version -ne "3.2.10")) {
    throw "Emergency acceptance, approved delta, or release identity does not authorize C34 promotion."
  }

  foreach ($historical in @(
    [pscustomobject]@{tag="3.2.9";commit="a60230a0695d2dd8fd1e727744614e746cda0bd8"},
    [pscustomobject]@{tag="2.5.9";commit="89719eb8ea5c938b6a0e9d816e6324d4d59b87bb"}
  )) {
    $historicalCommit = (Invoke-MIRPromotionGit rev-parse "$($historical.tag)^{commit}" | Select-Object -First 1).Trim()
    if ($historicalCommit -ne [string]$historical.commit) { throw "Historical tag $($historical.tag) moved." }
  }

  if ($Operation -eq "post-publication-sync") {
    if ($CandidateRef -notmatch '^refs/heads/[A-Za-z0-9._/-]+$' -or $CandidateRef.Contains('..')) {
      throw "Post-publication synchronization requires an exact safe refs/heads candidate ref."
    }

    $receiptPath = Join-Path $repo ".mir/evidence/terminal-publication/2026-08-16/github/3.2.10.json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
      throw "The append-only 3.2.10 GitHub publication receipt is missing."
    }
    $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100
    $releaseCommit = [string]$releaseRecord.proofs.tag.commit
    $tagObject = (Invoke-MIRPromotionGit rev-parse refs/tags/3.2.10 | Select-Object -First 1).Trim()
    $tagCommit = (Invoke-MIRPromotionGit rev-parse 'refs/tags/3.2.10^{commit}' | Select-Object -First 1).Trim()
    Invoke-MIRPromotionGit merge-base --is-ancestor $releaseCommit $CandidateSha | Out-Null

    if ([string]$releaseRecord.state -ne "publicly-verified" -or
        [string]$releaseRecord.candidate_id -ne "C34" -or
        $releaseCommit -ne "4cbea531a1043e0cacb9ac5c496731c8d77bbdb6" -or
        $tagObject -ne [string]$releaseRecord.proofs.tag.tag_object -or
        $tagCommit -ne $releaseCommit -or
        [string]$receipt.kind -ne "Mir3PostTerminalEmergencyPublicationReceiptV1" -or
        [string]$receipt.status -ne "published-and-verified" -or
        [string]$receipt.candidate_commit -ne $releaseCommit -or
        [string]$receipt.tag.object_sha -ne $tagObject -or
        [string]$receipt.tag.peeled_commit -ne $releaseCommit -or
        -not [bool]$receipt.tag.immutable -or
        [string]$receipt.archive_sha256 -ne $archiveSha -or
        [string]$receipt.download_sha256 -ne $archiveSha -or
        [string]$receipt.content_sha256 -ne $contentSha -or
        [long]$receipt.bytes -ne $bytes -or [int]$receipt.entries -ne $entries -or
        [long]$receipt.github_release.id -ne 371323367 -or
        [bool]$receipt.github_release.draft -or [bool]$receipt.github_release.prerelease -or
        -not [bool]$receipt.github_release.latest -or
        [long]$receipt.asset.id -ne 516809271 -or
        [string]$receipt.post_publication_validation.finding -ne ".mir/releases/emergency/findings/MIR3-TERM-0033.json" -or
        [string]$receipt.post_publication_validation.disposition -ne "deferred-to-mir4-under-maintainer-direction" -or
        [string]$override.status -ne "accepted-for-immediate-promotion" -or
        [string]$delta.status -ne "approved-under-release-specific-maintainer-override") {
      throw "Published 3.2.10 authority, immutable tag, public receipt, or package identity is not exact."
    }

    $releasePackageChanges = @(Invoke-MIRPromotionGit diff --name-only $releaseCommit $CandidateSha -- @packageRoots)
    if ($releasePackageChanges.Count -ne 0) {
      throw "Package-visible source changed after the immutable 3.2.10 release commit."
    }

    $candidateRemote = "not-checked"
    $mainRemote = "not-checked"
    $legacyRemote = "not-checked"
    if (-not $SkipRemote) {
      $candidateRemoteLine = @(Invoke-MIRPromotionGit ls-remote --heads origin $CandidateRef)
      $candidateRemote = if ($candidateRemoteLine.Count -eq 1) { ([string]$candidateRemoteLine[0] -split '\s+')[0] } else { "" }
      $mainRemoteLine = @(Invoke-MIRPromotionGit ls-remote --heads origin refs/heads/main)
      $mainRemote = if ($mainRemoteLine.Count -eq 1) { ([string]$mainRemoteLine[0] -split '\s+')[0] } else { "" }
      if ($candidateRemote -ne $CandidateSha) {
        throw "Remote candidate head is not the exact requested post-publication commit."
      }

      if ($PromotionBranch -eq "main") {
        Invoke-MIRPromotionGit merge-base --is-ancestor $releaseCommit $mainRemote | Out-Null
        Invoke-MIRPromotionGit merge-base --is-ancestor $mainRemote $CandidateSha | Out-Null
      }
      else {
        $legacyRemoteLine = @(Invoke-MIRPromotionGit ls-remote --heads origin refs/heads/legacy)
        $legacyRemote = if ($legacyRemoteLine.Count -eq 1) { ([string]$legacyRemoteLine[0] -split '\s+')[0] } else { "" }
        if ($legacyRemote -ne "89719eb8ea5c938b6a0e9d816e6324d4d59b87bb" -or
            $resolvedParents.Count -ne 2 -or $resolvedParents[0] -ne $legacyRemote -or
            $resolvedParents[1] -ne $mainRemote) {
          throw "Legacy alias promotion must preserve exact 2.5.9 as first parent and protected main as second parent."
        }
        $mainTree = (Invoke-MIRPromotionGit rev-parse "$mainRemote`^{tree}" | Select-Object -First 1).Trim()
        Invoke-MIRPromotionGit merge-base --is-ancestor $releaseCommit $mainRemote | Out-Null
        Invoke-MIRPromotionGit merge-base --is-ancestor $mainRemote $CandidateSha | Out-Null
        if ($resolvedTree -ne $mainTree) {
          throw "Legacy alias promotion tree must be exactly identical to protected main."
        }
      }
    }

    $result = [ordered]@{
      schema = 1
      status = "passed"
      operation = "post-publication-authority-sync-verification"
      release = $Release
      candidate_commit = $CandidateSha
      candidate_tree = $resolvedTree
      parents = $resolvedParents
      candidate_ref = $CandidateRef
      candidate_remote = $candidateRemote
      release_commit = $releaseCommit
      tag_object = $tagObject
      package_source_commit = $packageSourceCommit
      package_visible_changes_after_release = @($releasePackageChanges)
      promotion_branch = $PromotionBranch
      promotion_branch_remote = if ($PromotionBranch -eq "legacy") { $legacyRemote } else { $mainRemote }
      protected_main_commit = $mainRemote
      archive = [ordered]@{path=$zipRelative;sha256=$archiveSha;content_sha256=$contentSha;bytes=$bytes;entries=$entries}
      publication_receipt = ".mir/evidence/terminal-publication/2026-08-16/github/3.2.10.json"
      deferred_finding = "MIR3-TERM-0033"
      authorization = "post-publication-authority-sync-only"
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
      $resolvedOutput = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repo $OutputPath }
      $parent = Split-Path -Parent $resolvedOutput
      if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
      [IO.File]::WriteAllText($resolvedOutput, (($result | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
    }
    $result | ConvertTo-Json -Depth 20
    exit 0
  }

  $candidateRef = "refs/heads/hotfix/mir3-native-owner-max-level"
  $candidateRemote = "not-checked"
  $mainRemote = "not-checked"
  if (-not $SkipRemote) {
    $candidateRemoteLine = @(Invoke-MIRPromotionGit ls-remote --heads origin $candidateRef)
    $candidateRemote = if ($candidateRemoteLine.Count -eq 1) { ([string]$candidateRemoteLine[0] -split '\s+')[0] } else { "" }
    $mainRemoteLine = @(Invoke-MIRPromotionGit ls-remote --heads origin refs/heads/main)
    $mainRemote = if ($mainRemoteLine.Count -eq 1) { ([string]$mainRemoteLine[0] -split '\s+')[0] } else { "" }
    if ($candidateRemote -ne $CandidateSha -or $mainRemote -ne [string]$releaseRecord.source_release.tag_commit) {
      throw "Remote hotfix head or main predecessor changed before 3.2.10 promotion."
    }
  }

  $result = [ordered]@{
    schema = 1
    status = "passed"
    operation = "post-terminal-emergency-candidate-promotion-verification"
    release = $Release
    candidate_commit = $CandidateSha
    candidate_tree = $resolvedTree
    parents = $resolvedParents
    candidate_ref = $candidateRef
    candidate_remote = $candidateRemote
    package_source_commit = $packageSourceCommit
    promotion_branch = "main"
    promotion_from = [string]$releaseRecord.source_release.tag_commit
    promotion_to = $CandidateSha
    promotion_branch_remote = $mainRemote
    archive = [ordered]@{path=$zipRelative;sha256=$archiveSha;content_sha256=$contentSha;bytes=$bytes;entries=$entries}
    acceptance = [ordered]@{path=".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixMaintainerReleaseOverrideV1.json";factorio="2.1.14"}
    approved_delta = ".mir/releases/deltas/3.2.9-to-3.2.10.json"
    authorization = "github-publication-only"
  }

  if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repo $OutputPath }
    $parent = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
    [IO.File]::WriteAllText($resolvedOutput, (($result | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
  }
  $result | ConvertTo-Json -Depth 20
  exit 0
}

& (Join-Path $repo "tools/commands/release/New-MIR3TerminalReleaseCeremony.ps1") -RepoRoot $repo -Check
if ($LASTEXITCODE -ne 0) { throw "The terminal release ceremony is not internally valid." }

$allocation = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir/releases/terminal/MIR3-Terminal-Candidate-AllocationV1.json") | ConvertFrom-Json -Depth 100
$rows = @($allocation.allocations | Where-Object { [string]$_.release -eq $Release })
if ($rows.Count -ne 1) { throw "Candidate allocation must contain exactly one $Release row." }
$row = $rows[0]
if ([string]$row.candidate_commit -ne $CandidateSha -or -not [bool]$row.remote_exact) {
  throw "Requested candidate does not match the immutable $Release allocation."
}

$resolvedCommit = (Invoke-MIRPromotionGit rev-parse "$CandidateSha`^{commit}" | Select-Object -First 1).Trim()
$resolvedTree = (Invoke-MIRPromotionGit rev-parse "$CandidateSha`^{tree}" | Select-Object -First 1).Trim()
$resolvedParents = @(((Invoke-MIRPromotionGit show -s --format=%P $CandidateSha | Select-Object -First 1).Trim() -split '\s+') | Where-Object { $_ })
if ($resolvedCommit -ne $CandidateSha -or $resolvedTree -ne [string]$row.candidate_tree -or
    ($resolvedParents -join "|") -ne (@($row.parents) -join "|")) {
  throw "Candidate commit, tree, or parent authority differs from the allocation."
}

$zipRelative = "dist/more-infinite-research_$Release.zip"
$zip = Join-Path $repo $zipRelative
$archiveSha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
$contentSha = Get-MIRZipContentFingerprint -Path $zip
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try { $entries = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count }
finally { $archive.Dispose() }
$bytes = (Get-Item -LiteralPath $zip).Length
if ($archiveSha -ne [string]$row.archive_sha256 -or $contentSha -ne [string]$row.content_sha256 -or
    $bytes -ne [long]$row.bytes -or $entries -ne [int]$row.entries) {
  throw "Candidate ZIP identity differs from the immutable allocation."
}

$sealPath = Join-Path $repo ".mir/releases/terminal/seals/$Release.json"
$seal = Get-Content -Raw -LiteralPath $sealPath | ConvertFrom-Json -Depth 100
$family = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir/releases/terminal/MIR3TerminalFamilyReadinessV1.json") | ConvertFrom-Json -Depth 100
$acceptance = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir/releases/terminal/MIR3TerminalMaintainerAcceptanceV1.json") | ConvertFrom-Json -Depth 100
$familySeal = @($family.target_seals | Where-Object { [string]$_.release -eq $Release })
$acceptedCandidate = @($acceptance.candidates | Where-Object { [string]$_.release -eq $Release })
if ([string]$seal.status -ne "sealed" -or [string]$seal.candidate_commit -ne $CandidateSha -or
    [string]$seal.source_tree -ne [string]$row.candidate_tree -or
    [string]$seal.archive_sha256 -ne $archiveSha -or [string]$seal.content_sha256 -ne $contentSha -or
    [string]$seal.tag_authority.name -ne $Release -or [string]$seal.tag_authority.target_commit -ne $CandidateSha -or
    -not [bool]$seal.tag_authority.immutable -or [bool]$seal.tag_authority.update_or_delete -or
    [string]$family.status -ne "ready-for-local-tagging" -or -not [bool]$family.authorization.github_publication -or
    [bool]$family.authorization.mod_portal_upload -or $familySeal.Count -ne 1 -or $acceptedCandidate.Count -ne 1 -or
    [string]$acceptedCandidate[0].candidate_commit -ne $CandidateSha -or
    [string]$acceptedCandidate[0].archive_sha256 -ne $archiveSha) {
  throw "Maintainer acceptance, target seal, tag authority, or family readiness does not authorize this candidate."
}

$promotionBranch = if ($Release -eq "3.2.9") { "main" } else { "legacy" }
$promotion = $family.branch_promotion_preflight.PSObject.Properties[$promotionBranch].Value
if ([string]$promotion.status -ne "ready" -or [string]$promotion.mode -ne "governed-fast-forward" -or
    [string]$promotion.to -ne $CandidateSha) {
  throw "Branch-promotion preflight does not authorize this candidate."
}
Invoke-MIRPromotionGit merge-base --is-ancestor ([string]$promotion.from) $CandidateSha | Out-Null

$candidateRemote = "not-checked"
$branchRemote = "not-checked"
if (-not $SkipRemote) {
  $candidateRef = [string]$row.candidate_ref
  $candidateRemoteLine = @(Invoke-MIRPromotionGit ls-remote --heads origin $candidateRef)
  $candidateRemote = if ($candidateRemoteLine.Count -eq 1) { ([string]$candidateRemoteLine[0] -split '\s+')[0] } else { "" }
  $branchName = $promotionBranch
  $branchRemoteLine = @(Invoke-MIRPromotionGit ls-remote --heads origin "refs/heads/$branchName")
  $branchRemote = if ($branchRemoteLine.Count -eq 1) { ([string]$branchRemoteLine[0] -split '\s+')[0] } else { "" }
  if ($candidateRemote -ne $CandidateSha -or $branchRemote -ne [string]$promotion.from) {
    throw "Remote candidate or promotion-branch authority changed before promotion."
  }
}

$result = [ordered]@{
  schema = 1
  status = "passed"
  operation = "terminal-candidate-promotion-verification"
  release = $Release
  candidate_commit = $CandidateSha
  candidate_tree = $resolvedTree
  parents = $resolvedParents
  candidate_ref = [string]$row.candidate_ref
  candidate_remote = $candidateRemote
  promotion_branch = $promotionBranch
  promotion_from = [string]$promotion.from
  promotion_to = [string]$promotion.to
  promotion_branch_remote = $branchRemote
  archive = [ordered]@{path=$zipRelative;sha256=$archiveSha;content_sha256=$contentSha;bytes=$bytes;entries=$entries}
  target_seal = [ordered]@{path=".mir/releases/terminal/seals/$Release.json";record_sha256=[string]$seal.record_sha256}
  family_readiness = [ordered]@{path=".mir/releases/terminal/MIR3TerminalFamilyReadinessV1.json";record_sha256=[string]$family.record_sha256}
  authorization = "github-publication-only"
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $resolvedOutput = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repo $OutputPath }
  $parent = Split-Path -Parent $resolvedOutput
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
  [IO.File]::WriteAllText($resolvedOutput, (($result | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
}

$result | ConvertTo-Json -Depth 20
