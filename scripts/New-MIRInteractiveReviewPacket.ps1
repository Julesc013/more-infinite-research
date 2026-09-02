param(
  [Parameter(Mandatory)][string]$CandidateZip,
  [string]$SourceCommit = "",
  [string]$FactorioBin = "",
  [string]$ExpectedFactorioVersion = "2.1.11",
  [string]$OutputDir = "build\results\interactive-review-current",
  [switch]$HistoricalMaintainerStatement,
  [string]$Reviewer = "",
  [string]$MaintainerStatement = "",
  [string]$HistoricalAttestationPath = "",
  [string]$HistoricalCustodyPath = ""
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "tools\lib\validation\PackageIdentity.ps1")
. (Join-Path $repo "tools\lib\validation\ReleaseAttestations.ps1")

function Write-MIRReviewJson {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Value
  )

  [System.IO.File]::WriteAllText(
    $Path,
    ($Value | ConvertTo-Json -Depth 30),
    [System.Text.UTF8Encoding]::new($false)
  )
}

$info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
$candidatePath = if ([System.IO.Path]::IsPathRooted($CandidateZip)) {
  (Resolve-Path -LiteralPath $CandidateZip).Path
} else {
  (Resolve-Path -LiteralPath (Join-Path $repo $CandidateZip)).Path
}
$candidatePackageInfo = Get-MIRReleasePackageInfo -Path $candidatePath
if ([string]::IsNullOrWhiteSpace($SourceCommit)) {
  if ($HistoricalMaintainerStatement) {
    $historicalReleaseRecordPath = Join-Path $repo ".mir\releases\records\$($candidatePackageInfo.version).json"
    if (-not (Test-Path -LiteralPath $historicalReleaseRecordPath -PathType Leaf)) {
      throw "Historical maintainer attestation requires an existing release record: $historicalReleaseRecordPath"
    }
    $SourceCommit = [string](Get-Content -Raw -LiteralPath $historicalReleaseRecordPath | ConvertFrom-Json).package.source_commit
  } else {
    $SourceCommit = Get-MIRGitCommit -RepoRoot $repo
  }
}
if ($SourceCommit -notmatch '^[0-9a-f]{40}$') {
  throw "SourceCommit must be a full lowercase Git commit ID."
}
& git -C $repo cat-file -e "$SourceCommit^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
  throw "Source commit is not available locally: $SourceCommit"
}

$candidateContentSha256 = Get-MIRZipContentFingerprint -Path $candidatePath
$packageSourceSha256 = ""
if (-not $HistoricalMaintainerStatement) {
  $changedPackagePaths = @(& git -C $repo diff --name-only $SourceCommit HEAD -- @(Get-MIRPackageSourceRoots))
  if ($LASTEXITCODE -ne 0 -or $changedPackagePaths.Count -gt 0) {
    throw "Package-visible source differs from the requested source commit: $($changedPackagePaths -join ', ')"
  }
  if (Test-MIRRepositoryGitDirty -RepoRoot $repo) {
    throw "The repository must be clean before creating an identity-bound interactive review packet."
  }
  $packageSourceSha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  if ($candidateContentSha256 -ne $packageSourceSha256) {
    throw "Candidate content does not match the clean package-visible source."
  }
}

$factorio = [ordered]@{
  expected_version = $ExpectedFactorioVersion
  version = $null
  binary_sha256 = $null
}
if (-not [string]::IsNullOrWhiteSpace($FactorioBin)) {
  $factorioPath = if ([System.IO.Path]::IsPathRooted($FactorioBin)) {
    (Resolve-Path -LiteralPath $FactorioBin).Path
  } else {
    (Resolve-Path -LiteralPath (Join-Path $repo $FactorioBin)).Path
  }
  $factorio.version = Get-MIRFactorioBinaryVersion -Path $factorioPath
  $factorio.binary_sha256 = Get-MIRFileSha256 -Path $factorioPath
}

if ($HistoricalMaintainerStatement) {
  if ([string]::IsNullOrWhiteSpace($Reviewer) -or [string]::IsNullOrWhiteSpace($MaintainerStatement)) {
    throw "Historical maintainer attestation requires -Reviewer and -MaintainerStatement."
  }
  if ([string]::IsNullOrWhiteSpace([string]$factorio.version) -or [string]::IsNullOrWhiteSpace([string]$factorio.binary_sha256)) {
    throw "Historical maintainer attestation requires an exact -FactorioBin."
  }
  if (-not ([string]$factorio.version).StartsWith($ExpectedFactorioVersion)) {
    throw "Historical maintainer attestation Factorio binary does not match $ExpectedFactorioVersion."
  }
  $releaseRecordPath = Join-Path $repo ".mir\releases\records\$($candidatePackageInfo.version).json"
  if (-not (Test-Path -LiteralPath $releaseRecordPath -PathType Leaf)) {
    throw "Historical maintainer attestation requires a release record for $($candidatePackageInfo.version)."
  }
  $releaseRecord = Get-Content -Raw -LiteralPath $releaseRecordPath | ConvertFrom-Json
  $archiveSha256 = Get-MIRReleaseSha256 -Path $candidatePath
  if ([string]$releaseRecord.state -ne "publicly-verified" -or
      [string]$releaseRecord.release -ne [string]$candidatePackageInfo.version -or
      [string]$releaseRecord.package.archive_sha256 -ne $archiveSha256 -or
      [string]$releaseRecord.package.content_sha256 -ne $candidateContentSha256 -or
      [string]$releaseRecord.package.source_commit -ne $SourceCommit -or
      [long]$releaseRecord.package.bytes -ne (Get-Item -LiteralPath $candidatePath).Length) {
    throw "Historical maintainer attestation may only bind the exact immutable public release identity."
  }
  $artifactPaths = @(
    "docs/releases/archive/MIR-3.5-WAVE-INDEX.json",
    ".mir/evidence/MIR-3.5-wave-publication.json",
    ".mir/releases/waves/MIR-3.5-Local-Qualification-Inventory.json"
  )
  $supportingArtifacts = @(
    foreach ($relativePath in $artifactPaths) {
      $artifactPath = Join-Path $repo $relativePath
      if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        throw "Historical maintainer attestation supporting authority is absent: $relativePath"
      }
      [ordered]@{
        path=$relativePath.Replace("\", "/")
        sha256=(Get-MIRReleasePortableArtifactSha256 -Path $artifactPath)
      }
    }
  )
  $attestationPath = if ([string]::IsNullOrWhiteSpace($HistoricalAttestationPath)) {
    Join-Path $repo ".mir\evidence\$($candidatePackageInfo.version)-manual-review-attestation.json"
  } elseif ([IO.Path]::IsPathRooted($HistoricalAttestationPath)) {
    [IO.Path]::GetFullPath($HistoricalAttestationPath)
  } else {
    [IO.Path]::GetFullPath((Join-Path $repo $HistoricalAttestationPath))
  }
  $custodyPath = if ([string]::IsNullOrWhiteSpace($HistoricalCustodyPath)) {
    Join-Path $repo ".mir\evidence\$($candidatePackageInfo.version)-manual-review-custody.json"
  } elseif ([IO.Path]::IsPathRooted($HistoricalCustodyPath)) {
    [IO.Path]::GetFullPath($HistoricalCustodyPath)
  } else {
    [IO.Path]::GetFullPath((Join-Path $repo $HistoricalCustodyPath))
  }
  $attestationRelative = [IO.Path]::GetRelativePath($repo, $attestationPath).Replace("\", "/")
  $custodyRelative = [IO.Path]::GetRelativePath($repo, $custodyPath).Replace("\", "/")
  if ($attestationRelative.StartsWith("../") -or $custodyRelative.StartsWith("../")) {
    throw "Historical attestation and custody paths must remain under the repository evidence authority."
  }
  if ((Test-Path -LiteralPath $attestationPath -PathType Leaf) -or (Test-Path -LiteralPath $custodyPath -PathType Leaf)) {
    throw "Historical attestation or custody destination already exists; never overwrite evidence."
  }
  $attestation = [ordered]@{
    schema = 2
    kind = "mir-manual-release-review"
    candidate_sha256 = $archiveSha256
    candidate_content_sha256 = $candidateContentSha256
    source_commit = $SourceCommit
    checklist_version = "mir-manual-release-review-historical-statement-v1"
    factorio_version = [string]$factorio.version
    factorio_binary_sha256 = [string]$factorio.binary_sha256
    reviewer = $Reviewer.Trim()
    attestation_recorded_at = (Get-Date).ToUniversalTime().ToString("o")
    review_performed_before_publication = $true
    review_exact_time_known = $false
    attestation_recorded_after_publication = $true
    reviewed_release = [string]$candidatePackageInfo.version
    statement = $MaintainerStatement.Trim()
    supporting_artifacts = $supportingArtifacts
    custody_manifest_path = $custodyRelative
    status = "passed"
    attestation_sha256 = $null
  }
  $attestationMaterial = ConvertTo-MIRReleaseOrderedMap -Object ([pscustomobject]$attestation)
  $attestationMaterial.Remove("attestation_sha256")
  $attestation.attestation_sha256 = Get-MIRReleaseTextSha256 -Text ($attestationMaterial | ConvertTo-Json -Depth 40 -Compress)
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $attestationPath))
  Write-MIRReviewJson -Path $attestationPath -Value $attestation

  $attestationFileSha256 = Get-MIRReleaseSha256 -Path $attestationPath
  $objectRelative = ".mir/evidence/objects/sha256/$($attestationFileSha256.Substring(0, 2))/$attestationFileSha256.json"
  $objectPath = Join-Path $repo $objectRelative
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $objectPath))
  if (Test-Path -LiteralPath $objectPath -PathType Leaf) {
    if (-not (Test-MIRReleaseByteIdentity -Expected ([IO.File]::ReadAllBytes($attestationPath)) -Actual ([IO.File]::ReadAllBytes($objectPath)))) {
      throw "Historical manual attestation content address is occupied by different bytes."
    }
  } else {
    Copy-Item -LiteralPath $attestationPath -Destination $objectPath
  }
  $custodyObjectMatches = Test-MIRReleaseByteIdentity -Expected ([IO.File]::ReadAllBytes($attestationPath)) -Actual ([IO.File]::ReadAllBytes($objectPath))
  if ((Get-MIRReleaseSha256 -Path $objectPath) -ne $attestationFileSha256 -or -not $custodyObjectMatches) {
    throw "Historical manual attestation content-addressed custody copy is not byte-identical."
  }
  $custody = [ordered]@{
    schema = 1
    kind = "MIR3HistoricalManualReviewCustodyV1"
    recorded_at = (Get-Date).ToUniversalTime().ToString("o")
    retention = "repository-governed-content-addressed-evidence-v1"
    package = [ordered]@{
      release=[string]$candidatePackageInfo.version
      archive_sha256=$archiveSha256
      content_sha256=$candidateContentSha256
      source_commit=$SourceCommit
    }
    attestation = [ordered]@{
      path=$attestationRelative
      sha256=$attestationFileSha256
      canonical_self_sha256=[string]$attestation.attestation_sha256
    }
    object = [ordered]@{
      path=$objectRelative
      sha256=$attestationFileSha256
    }
  }
  Write-MIRReviewJson -Path $custodyPath -Value $custody
  Write-Host "[ok] created historical manual review attestation $attestationRelative"
  Write-Host "[ok] imported byte-identical custody object $objectRelative"
  return
}

$outputRoot = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repo $OutputDir }
if ((Test-Path -LiteralPath $outputRoot) -and @(Get-ChildItem -LiteralPath $outputRoot -Force).Count -gt 0) {
  throw "OutputDir already contains files: $outputRoot"
}

$profileRows = @(
  [ordered]@{
    id = "base"
    official_mods = @("base")
  },
  [ordered]@{
    id = "space-age"
    official_mods = @("base", "quality", "elevated-rails", "space-age")
  }
)
foreach ($profile in $profileRows) {
  $profileRoot = Join-Path $outputRoot $profile.id
  $modsDir = Join-Path $profileRoot "mods"
  New-Item -ItemType Directory -Force -Path $modsDir | Out-Null
  Copy-Item -LiteralPath $candidatePath -Destination (Join-Path $modsDir (Split-Path -Leaf $candidatePath))

  $modRows = [System.Collections.Generic.List[object]]::new()
  foreach ($officialName in @("base", "quality", "elevated-rails", "space-age")) {
    $modRows.Add([ordered]@{
      name = $officialName
      enabled = $profile.official_mods -contains $officialName
    })
  }
  $modRows.Add([ordered]@{
    name = [string]$info.name
    enabled = $true
  })
  Write-MIRReviewJson -Path (Join-Path $modsDir "mod-list.json") -Value ([ordered]@{ mods = @($modRows) })
  foreach ($leaf in @("saves", "screenshots")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $profileRoot $leaf) | Out-Null
  }
}

$requiredChecks = @(
  [ordered]@{
    id = "technology-tree-visual"
    status = "pending"
    criteria = "Inspect placement, arrows, infinite display, continuations, native-owner duplication, and disabled-stream gaps in base and Space Age."
  },
  [ordered]@{
    id = "icon-visual"
    status = "pending"
    criteria = "Inspect base fallbacks, DLC assets, overlays, contrast, UI scale, and missing-asset placeholders."
  },
  [ordered]@{
    id = "locale-fit-and-truncation"
    status = "pending"
    criteria = "Inspect technology, setting, and help text at ordinary UI widths in the reviewed locales."
  },
  [ordered]@{
    id = "settings-ux"
    status = "pending"
    criteria = "Inspect conservative defaults, automatic-compiler controls, native-owner notes, dropdown fit, and translated labels."
  },
  [ordered]@{
    id = "save-ui"
    status = "pending"
    criteria = "Inspect existing levels, selected research, fractional progress, native-owner values, mod removal/re-addition, and startup-setting save/reload."
  },
  [ordered]@{
    id = "human-balance"
    status = "pending"
    criteria = "Complete the representative balance worksheet and record a reasoned verdict for every sample."
  },
  [ordered]@{
    id = "configuration-change-give-item-safety"
    status = "pending"
    criteria = "With a connected player, prove an external give-item effect and unrelated force state are unchanged by the MIR adoption-signature change."
  }
)

$archiveSha256 = Get-MIRFileSha256 -Path $candidatePath
$relativeEvidenceRoot = [System.IO.Path]::GetRelativePath($repo, $outputRoot).Replace("\", "/")
$packet = [ordered]@{
  schema = 2
  kind = "mir-interactive-review-preparation"
  status = "pending"
  version = [string]$info.version
  source_commit = $SourceCommit
  archive_path = [System.IO.Path]::GetRelativePath($repo, $candidatePath).Replace("\", "/")
  archive_sha256 = $archiveSha256
  package_content_sha256 = $candidateContentSha256
  package_source_sha256 = $packageSourceSha256
  validation_harness_sha256 = Get-MIRValidationHarnessFingerprint -RepoRoot $repo
  factorio = $factorio
  profiles = $profileRows
  required_checks = $requiredChecks
  notes = @(
    "This pending packet is preparation, not schema-2 evidence that GUI review passed.",
    "Do not reuse screenshots or saves from another candidate or Factorio binary.",
    "Complete the final governed attestation only after Factorio 2.1.11 is identity-bound."
  )
}
$packetPath = Join-Path $outputRoot "interactive-review.json"
Write-MIRReviewJson -Path $packetPath -Value $packet

$attestationTemplate = [ordered]@{
  schema = 2
  kind = "mir-manual-release-review"
  candidate_sha256 = $archiveSha256
  candidate_content_sha256 = $candidateContentSha256
  source_commit = $SourceCommit
  checklist_version = "mir-manual-release-review-v1"
  factorio_version = $factorio.version
  factorio_binary_sha256 = $factorio.binary_sha256
  reviewer = $null
  reviewed_at = $null
  items = @($requiredChecks | ForEach-Object {
    [ordered]@{
      id = $_.id
      status = "pending"
      notes = $_.criteria
      artifacts = @()
    }
  })
  status = "pending"
  attestation_sha256 = $null
  template_notice = "Pending worksheet only. Remove template_notice and satisfy the strict schema after every item passes."
}
Write-MIRReviewJson -Path (Join-Path $outputRoot "manual-release-attestation.template.json") -Value $attestationTemplate

$balanceTemplate = [ordered]@{
  schema = 1
  kind = "mir-human-balance-review-worksheet"
  candidate_sha256 = $archiveSha256
  source_commit = $SourceCommit
  required_sample_kinds = @(
    "early-recipe-productivity",
    "late-recipe-productivity",
    "native-owner-adoption",
    "base-continuation",
    "direct-effect",
    "modded-structural-attachment",
    "intentionally-skipped-candidate",
    "sanitation-or-compatibility-decision"
  )
  rows = @()
  row_fields = @(
    "sample_kind",
    "technology_id",
    "first_generated_level",
    "science_set",
    "prerequisite_milestone",
    "effect_per_level",
    "first_level_cost",
    "growth_factor",
    "research_time",
    "maximum_useful_levels_before_cap",
    "target_recipe_count",
    "ownership",
    "verdict",
    "notes"
  )
}
Write-MIRReviewJson -Path (Join-Path $outputRoot "balance-review.template.json") -Value $balanceTemplate

$readme = @(
  "# MIR $($info.version) Interactive Review",
  "",
  "Candidate source: ``$SourceCommit``",
  "Candidate archive SHA-256: ``$archiveSha256``",
  "Candidate content SHA-256: ``$candidateContentSha256``",
  "",
  "Use the isolated ``$relativeEvidenceRoot/base`` and ``$relativeEvidenceRoot/space-age`` user-data roots. Do not point either run at a normal player mod directory.",
  "",
  "The JSON templates are pending worksheets. After Factorio $ExpectedFactorioVersion is available, bind its exact binary hash, complete every check with portable screenshot/save evidence, convert the worksheet to the strict schema, compute its canonical self-hash, and run ``tests/release/Test-MIRManualReleaseReview.ps1``."
)
[System.IO.File]::WriteAllLines(
  (Join-Path $outputRoot "README.md"),
  $readme,
  [System.Text.UTF8Encoding]::new($false)
)

Write-Host "[ok] prepared identity-bound interactive review packet $packetPath"
