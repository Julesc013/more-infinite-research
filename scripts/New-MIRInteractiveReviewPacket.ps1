param(
  [Parameter(Mandatory)][string]$CandidateZip,
  [string]$SourceCommit = "",
  [string]$FactorioBin = "",
  [string]$ExpectedFactorioVersion = "2.1.11",
  [string]$OutputDir = "artifacts\interactive-review-current"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")

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
if ([string]::IsNullOrWhiteSpace($SourceCommit)) {
  $SourceCommit = Get-MIRGitCommit -RepoRoot $repo
}
if ($SourceCommit -notmatch '^[0-9a-f]{40}$') {
  throw "SourceCommit must be a full lowercase Git commit ID."
}
& git -C $repo cat-file -e "$SourceCommit^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
  throw "Source commit is not available locally: $SourceCommit"
}

$changedPackagePaths = @(& git -C $repo diff --name-only $SourceCommit HEAD -- @(Get-MIRPackageSourceRoots))
if ($LASTEXITCODE -ne 0 -or $changedPackagePaths.Count -gt 0) {
  throw "Package-visible source differs from the requested source commit: $($changedPackagePaths -join ', ')"
}
if (Test-MIRRepositoryGitDirty -RepoRoot $repo) {
  throw "The repository must be clean before creating an identity-bound interactive review packet."
}

$packageSourceSha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$candidateContentSha256 = Get-MIRZipContentFingerprint -Path $candidatePath
if ($candidateContentSha256 -ne $packageSourceSha256) {
  throw "Candidate content does not match the clean package-visible source."
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
  "The JSON templates are pending worksheets. After Factorio $ExpectedFactorioVersion is available, bind its exact binary hash, complete every check with portable screenshot/save evidence, convert the worksheet to the strict schema, compute its canonical self-hash, and run ``scripts/Test-MIRManualReleaseReview.ps1``."
)
[System.IO.File]::WriteAllLines(
  (Join-Path $outputRoot "README.md"),
  $readme,
  [System.Text.UTF8Encoding]::new($false)
)

Write-Host "[ok] prepared identity-bound interactive review packet $packetPath"
