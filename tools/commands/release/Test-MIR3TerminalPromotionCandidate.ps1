param(
  [Parameter(Mandatory)][ValidateSet("3.2.9", "2.5.9")][string]$Release,
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
