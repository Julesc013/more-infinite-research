param(
  [Parameter(Mandatory)][ValidateSet("3.2.10", "3.2.9", "2.5.9")][string]$Release,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$CandidateSha,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path,
  [string]$OutputPath = "",
  [switch]$SkipRemote
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")

function Invoke-MIRPromotionGit {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  $output = @(& git -C $repo @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)" }
  return $output
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

  if ([string]$releaseRecord.state -ne "manually-accepted" -or [string]$releaseRecord.candidate_id -ne "C34" -or
      [string]$override.status -ne "accepted-for-immediate-promotion" -or
      [string]$override.release -ne "3.2.10" -or [string]$override.candidate_id -ne "C34" -or
      [string]$override.candidate.archive_sha256 -ne $archiveSha -or
      [string]$override.maintainer_decision.accepted_factorio.version -ne "2.1.14" -or
      [string]$override.maintainer_decision.factorio_2_1_13_gate -ne "waived and superseded for 3.2.10 only" -or
      [string]$delta.status -ne "approved-under-release-specific-maintainer-override" -or
      [string]$delta.candidate.archive_sha256 -ne $archiveSha -or
      [string]$delta.transition.from_version -ne "3.2.9" -or [string]$delta.transition.to_version -ne "3.2.10") {
    throw "Emergency acceptance, approved delta, or release identity does not authorize C34 promotion."
  }

  foreach ($historical in @(
    [pscustomobject]@{tag="3.2.9";commit="a60230a0695d2dd8fd1e727744614e746cda0bd8"},
    [pscustomobject]@{tag="2.5.9";commit="89719eb8ea5c938b6a0e9d816e6324d4d59b87bb"}
  )) {
    $historicalCommit = (Invoke-MIRPromotionGit rev-parse "$($historical.tag)^{commit}" | Select-Object -First 1).Trim()
    if ($historicalCommit -ne [string]$historical.commit) { throw "Historical tag $($historical.tag) moved." }
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
