param(
  [Parameter(Mandatory)][string]$CandidateZip,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ModsDir,
  [Parameter(Mandatory)]
  [ValidateSet(
    "startup-failure",
    "missing-technology",
    "unexpected-technology",
    "wrong-recipe-membership",
    "duplicate-owner",
    "wrong-prerequisite",
    "wrong-science",
    "unreachable-technology",
    "technology-too-early",
    "technology-too-late",
    "effect-too-large",
    "effect-too-small",
    "cost-too-large",
    "cost-too-small",
    "icon-or-locale",
    "settings-ux",
    "save-or-upgrade",
    "performance",
    "sanitation-review-required"
  )]
  [string]$Category,
  [Parameter(Mandatory)][string]$Expected,
  [Parameter(Mandatory)][string]$Actual,
  [ValidateSet("release-blocker", "compatibility", "balance", "cosmetic", "information")]
  [string]$Severity = "balance",
  [string]$Technology = "",
  [string]$Recipe = "",
  [string]$SourceCommit = "",
  [string]$ModListPath = "",
  [string]$StartupSettingsPath = "",
  [string]$SavePath = "",
  [switch]$IncludeSave,
  [string]$FactorioLogPath = "",
  [string[]]$ScreenshotPath = @(),
  [string[]]$CompilerArtifactPath = @(),
  [string]$GenerationPlanFingerprint = "",
  [string]$CompilerEvidenceFingerprint = "",
  [string]$CoverageFingerprint = "",
  [string]$CompilerSummaryPath = "",
  [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")

function Resolve-MIRInputFile {
  param([Parameter(Mandatory)][string]$Path)

  $candidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
}

function Resolve-MIRInputDirectory {
  param([Parameter(Mandatory)][string]$Path)

  $candidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  $resolved = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
    throw "Expected a directory: $Path"
  }
  return $resolved
}

function Get-MIRDirectoryContentFingerprint {
  param([Parameter(Mandatory)][string]$Path)

  $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName)
  $rows = foreach ($file in $files) {
    $relative = [System.IO.Path]::GetRelativePath($Path, $file.FullName).Replace("\", "/")
    "{0}`t{1}`t{2}" -f $relative, $file.Length, (Get-MIRFileSha256 -Path $file.FullName)
  }
  return [pscustomobject]@{
    file_count = $files.Count
    sha256 = Get-MIRStringSha256 -Value ($rows -join "`n")
  }
}

function Assert-MIRSha256OrEmpty {
  param(
    [Parameter(Mandatory)][string]$Name,
    [AllowEmptyString()][string]$Value
  )

  if (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -notmatch '^[0-9a-fA-F]{64}$') {
    throw "$Name must be empty or a SHA-256 value."
  }
}

function Protect-MIRShareableText {
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
    [switch]$SelectRelevantLogLines
  )

  $value = $Text.Replace($repo, "<REPO>")
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $value = $value.Replace($env:USERPROFILE, "<USER_PROFILE>")
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
    $value = $value.Replace($env:USERNAME, "<USER>")
  }
  $value = [regex]::Replace($value, '(?i)\b[A-Z]:\\Users\\[^\\\s"'']+', '<USER_PROFILE>')

  if ($SelectRelevantLogLines) {
    $lines = @($value -split "\r?\n")
    $value = (@($lines | Where-Object {
      $_ -match '(?i)(more-infinite-research|\bMIR\b|error|warning|failed|loading mod|checksum)'
    }) -join "`n")
  }
  return $value
}

function Write-MIRUtf8NoBom {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text
  )

  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

foreach ($entry in @(
  @{ Name = "GenerationPlanFingerprint"; Value = $GenerationPlanFingerprint },
  @{ Name = "CompilerEvidenceFingerprint"; Value = $CompilerEvidenceFingerprint },
  @{ Name = "CoverageFingerprint"; Value = $CoverageFingerprint }
)) {
  Assert-MIRSha256OrEmpty -Name $entry.Name -Value $entry.Value
}

$candidatePath = Resolve-MIRInputFile -Path $CandidateZip
$factorioPath = Resolve-MIRInputFile -Path $FactorioBin
$modsPath = Resolve-MIRInputDirectory -Path $ModsDir
if ([string]::IsNullOrWhiteSpace($ModListPath)) {
  $ModListPath = Join-Path $modsPath "mod-list.json"
}
$modList = Resolve-MIRInputFile -Path $ModListPath

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
if (Test-MIRPackageSourceGitDirty -RepoRoot $repo) {
  throw "Package-visible working-tree changes must be committed before capturing a playtest bundle."
}

$info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
$packageSourceSha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$candidateContentSha256 = Get-MIRZipContentFingerprint -Path $candidatePath
if ($candidateContentSha256 -ne $packageSourceSha256) {
  throw "Candidate content does not match the current package-visible source."
}

$factorioVersion = Get-MIRFactorioBinaryVersion -Path $factorioPath
$factorioRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $factorioPath))
$officialDataRoot = Join-Path $factorioRoot "data"
if (-not (Test-Path -LiteralPath $officialDataRoot -PathType Container)) {
  throw "Unable to find the Factorio data directory beside the supplied executable: $officialDataRoot"
}

$officialMods = @(
  foreach ($directory in @(Get-ChildItem -LiteralPath $officialDataRoot -Directory | Sort-Object Name)) {
    $officialInfoPath = Join-Path $directory.FullName "info.json"
    if (-not (Test-Path -LiteralPath $officialInfoPath -PathType Leaf)) {
      continue
    }
    $officialInfo = Get-Content -Raw -LiteralPath $officialInfoPath | ConvertFrom-Json
    $identity = Get-MIRDirectoryContentFingerprint -Path $directory.FullName
    $officialVersion = [string]$officialInfo.version
    if ([string]::IsNullOrWhiteSpace($officialVersion)) {
      $officialVersion = $factorioVersion
    }
    [ordered]@{
      name = [string]$officialInfo.name
      version = $officialVersion
      file_count = [int]$identity.file_count
      content_sha256 = [string]$identity.sha256
    }
  }
)

$modArchives = @(
  foreach ($archive in @(Get-ChildItem -LiteralPath $modsPath -Filter "*.zip" -File | Sort-Object Name)) {
    [ordered]@{
      file = $archive.Name
      bytes = [long]$archive.Length
      sha256 = Get-MIRFileSha256 -Path $archive.FullName
    }
  }
)
$modListSha256 = Get-MIRFileSha256 -Path $modList
$closureRows = @("mod-list`t$modListSha256")
$closureRows += @($officialMods | ForEach-Object {
  "official`t$($_.name)`t$($_.version)`t$($_.file_count)`t$($_.content_sha256)"
})
$closureRows += @($modArchives | ForEach-Object {
  "archive`t$($_.file)`t$($_.bytes)`t$($_.sha256)"
})
$modClosureSha256 = Get-MIRStringSha256 -Value (@($closureRows | Sort-Object) -join "`n")

$startupSettingsSha256 = $null
$startupSettingsResolved = $null
if (-not [string]::IsNullOrWhiteSpace($StartupSettingsPath)) {
  $startupSettingsResolved = Resolve-MIRInputFile -Path $StartupSettingsPath
  $startupSettingsSha256 = Get-MIRFileSha256 -Path $startupSettingsResolved
}
$saveSha256 = $null
$saveResolved = $null
if (-not [string]::IsNullOrWhiteSpace($SavePath)) {
  $saveResolved = Resolve-MIRInputFile -Path $SavePath
  $saveSha256 = Get-MIRFileSha256 -Path $saveResolved
}
if ($IncludeSave -and $null -eq $saveResolved) {
  throw "-IncludeSave requires -SavePath."
}

$compilerSummary = $null
if (-not [string]::IsNullOrWhiteSpace($CompilerSummaryPath)) {
  $compilerSummaryResolved = Resolve-MIRInputFile -Path $CompilerSummaryPath
  $compilerSummary = Get-Content -Raw -LiteralPath $compilerSummaryResolved | ConvertFrom-Json
}
$sanitationSummary = if ($null -ne $compilerSummary -and $null -ne $compilerSummary.sanitation_summary) {
  $compilerSummary.sanitation_summary
} else {
  [pscustomobject]@{}
}
$telemetrySummary = if ($null -ne $compilerSummary -and $null -ne $compilerSummary.telemetry_summary) {
  $compilerSummary.telemetry_summary
} else {
  [pscustomobject]@{}
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $stamp = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss")
  $OutputDir = Join-Path $repo "artifacts\playtest\$stamp-$Category"
}
$outputRoot = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repo $OutputDir }
if ((Test-Path -LiteralPath $outputRoot) -and @(Get-ChildItem -LiteralPath $outputRoot -Force).Count -gt 0) {
  throw "OutputDir already contains files: $outputRoot"
}
$attachmentRoot = Join-Path $outputRoot "attachments"
New-Item -ItemType Directory -Force -Path $attachmentRoot | Out-Null
$attachments = [System.Collections.Generic.List[object]]::new()

function Add-MIRAttachment {
  param(
    [Parameter(Mandatory)][string]$Kind,
    [Parameter(Mandatory)][string]$Source,
    [switch]$RedactText,
    [switch]$RelevantLogOnly
  )

  $resolved = Resolve-MIRInputFile -Path $Source
  $ordinal = $attachments.Count + 1
  $leaf = Split-Path -Leaf $resolved
  $destination = Join-Path $attachmentRoot ("{0:D2}-{1}" -f $ordinal, $leaf)
  if ($RedactText) {
    $text = [System.IO.File]::ReadAllText($resolved)
    $protected = Protect-MIRShareableText -Text $text -SelectRelevantLogLines:$RelevantLogOnly
    Write-MIRUtf8NoBom -Path $destination -Text $protected
  } else {
    Copy-Item -LiteralPath $resolved -Destination $destination
  }
  $attachments.Add([ordered]@{
    kind = $Kind
    path = [System.IO.Path]::GetRelativePath($outputRoot, $destination).Replace("\", "/")
    sha256 = Get-MIRFileSha256 -Path $destination
  })
}

Add-MIRAttachment -Kind "environment" -Source $modList
if ($null -ne $startupSettingsResolved) {
  Add-MIRAttachment -Kind "environment" -Source $startupSettingsResolved
}
if (-not [string]::IsNullOrWhiteSpace($FactorioLogPath)) {
  Add-MIRAttachment -Kind "log" -Source $FactorioLogPath -RedactText -RelevantLogOnly
}
foreach ($path in @($ScreenshotPath)) {
  if (-not [string]::IsNullOrWhiteSpace($path)) {
    Add-MIRAttachment -Kind "screenshot" -Source $path
  }
}
foreach ($path in @($CompilerArtifactPath)) {
  if (-not [string]::IsNullOrWhiteSpace($path)) {
    Add-MIRAttachment -Kind "compiler-artifact" -Source $path -RedactText
  }
}
if ($IncludeSave) {
  Add-MIRAttachment -Kind "save" -Source $saveResolved
}

$nullableTechnology = if ([string]::IsNullOrWhiteSpace($Technology)) { $null } else { $Technology }
$nullableRecipe = if ([string]::IsNullOrWhiteSpace($Recipe)) { $null } else { $Recipe }
$nullableGenerationPlanFingerprint = if ([string]::IsNullOrWhiteSpace($GenerationPlanFingerprint)) { $null } else { $GenerationPlanFingerprint.ToUpperInvariant() }
$nullableCompilerEvidenceFingerprint = if ([string]::IsNullOrWhiteSpace($CompilerEvidenceFingerprint)) { $null } else { $CompilerEvidenceFingerprint.ToUpperInvariant() }
$nullableCoverageFingerprint = if ([string]::IsNullOrWhiteSpace($CoverageFingerprint)) { $null } else { $CoverageFingerprint.ToUpperInvariant() }

$report = [ordered]@{
  schema = 1
  kind = "mir-playtest-report"
  created_at = [DateTime]::UtcNow.ToString("o")
  candidate = [ordered]@{
    version = [string]$info.version
    archive_sha256 = Get-MIRFileSha256 -Path $candidatePath
    content_sha256 = $candidateContentSha256
    source_commit = $SourceCommit
    package_source_sha256 = $packageSourceSha256
  }
  factorio = [ordered]@{
    version = $factorioVersion
    binary_sha256 = Get-MIRFileSha256 -Path $factorioPath
  }
  environment = [ordered]@{
    mod_list_sha256 = $modListSha256
    mod_archives = $modArchives
    official_mods = $officialMods
    mod_closure_sha256 = $modClosureSha256
    startup_settings_sha256 = $startupSettingsSha256
    save_sha256 = $saveSha256
  }
  observation = [ordered]@{
    category = $Category
    technology = $nullableTechnology
    recipe = $nullableRecipe
    expected = $Expected
    actual = $Actual
    severity = $Severity
  }
  compiler = [ordered]@{
    generation_plan_fingerprint = $nullableGenerationPlanFingerprint
    compiler_evidence_fingerprint = $nullableCompilerEvidenceFingerprint
    coverage_fingerprint = $nullableCoverageFingerprint
    sanitation_summary = $sanitationSummary
    telemetry_summary = $telemetrySummary
  }
  attachments = @($attachments)
}

$reportPath = Join-Path $outputRoot "report.json"
Write-MIRUtf8NoBom -Path $reportPath -Text ($report | ConvertTo-Json -Depth 30)
Write-Host "[ok] captured identity-bound playtest bundle $reportPath"
