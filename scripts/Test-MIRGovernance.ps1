param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$docsRoot = Join-Path $repo "docs"
$mirRoot = Join-Path $repo ".mir"

$allowedStatuses = @("current", "draft", "deprecated", "archived")
$allowedDocTypes = @("tutorial", "how-to", "reference", "explanation", "adr", "release-plan", "archive")
$allowedAudiences = @("player", "modpack-author", "maintainer", "developer", "release-manager")
$forbiddenDocNames = @("notes.md", "misc.md", "old.md", "new.md", "ideas.md", "dump.md")

function Get-MIRRelativePath {
  param([Parameter(Mandatory)][string]$Path)
  return [System.IO.Path]::GetRelativePath($repo, (Resolve-Path -LiteralPath $Path).Path).Replace("\", "/")
}

function Test-MIRRepoPath {
  param([Parameter(Mandatory)][string]$RelativePath)
  return Test-Path -LiteralPath (Join-Path $repo $RelativePath)
}

function Read-MIRText {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path = Join-Path $repo $RelativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required governance file: $RelativePath"
  }
  return Get-Content -Raw -LiteralPath $path
}

function Get-MIRFrontmatter {
  param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$RelativePath)
  $match = [regex]::Match($Text, "\A---\r?\n(?<body>.*?)(\r?\n)---\r?\n", [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if (-not $match.Success) {
    throw "$RelativePath is missing frontmatter."
  }

  $fields = @{}
  foreach ($line in $match.Groups["body"].Value -split "\r?\n") {
    if ($line -match "^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$") {
      $fields[$matches[1]] = $matches[2].Trim()
    }
  }
  return $fields
}

function Get-MIRFrontmatterString {
  param($Fields, [string]$Name, [string]$RelativePath)
  if (-not $Fields.ContainsKey($Name)) {
    throw "$RelativePath frontmatter missing required field: $Name"
  }
  return ([string]$Fields[$Name]).Trim().Trim('"')
}

function Get-MIRManifestDocPaths {
  param([string]$Text)
  return @(
    foreach ($match in [regex]::Matches($Text, "(?m)^\s+- path:\s+(docs/.+?\.md)\s*$")) {
      $match.Groups[1].Value
    }
  )
}

function Get-MIRManifestSourceTruths {
  param([string]$Text)
  return @(
    foreach ($match in [regex]::Matches($Text, "(?m)^\s{6}-\s+([A-Za-z0-9._-]+)\s*$")) {
      $match.Groups[1].Value
    }
  )
}

function ConvertTo-MIRClaimPageSlug {
  param([Parameter(Mandatory)][string]$Name)
  $value = $Name -replace "_", "-"
  $value = [regex]::Replace($value, "([a-z0-9])([A-Z])", '$1-$2')
  $value = $value.ToLowerInvariant()
  $value = [regex]::Replace($value, "[^a-z0-9-]+", "-")
  $value = [regex]::Replace($value, "-+", "-").Trim("-")
  return $value
}

function Assert-MIRFileHasSchemaOne {
  param([Parameter(Mandatory)][string]$RelativePath)
  $text = Read-MIRText -RelativePath $RelativePath
  if ($text -notmatch "(?m)^schema:\s+1\s*$") {
    throw "$RelativePath must declare schema: 1."
  }
}

function Assert-MIRRelativeMarkdownLinks {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Text
  )

  $sourceDir = Split-Path -Parent (Join-Path $repo $RelativePath)
  $matches = [regex]::Matches($Text, "(?<!\!)\[[^\]]+\]\((?<target>[^)]+)\)")
  foreach ($match in $matches) {
    $target = $match.Groups["target"].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($target)) { continue }
    if ($target.StartsWith("<") -and $target.EndsWith(">")) {
      $target = $target.Substring(1, $target.Length - 2)
    }
    if ($target -match "^(https?|mailto):") { continue }
    if ($target.StartsWith("#")) { continue }

    $targetPath = ($target -split "#", 2)[0]
    if ([string]::IsNullOrWhiteSpace($targetPath)) { continue }

    $resolved = Join-Path $sourceDir $targetPath
    if (-not (Test-Path -LiteralPath $resolved)) {
      throw "$RelativePath has broken relative link: $target"
    }
  }
}

foreach ($manifest in @(
  ".mir/docs.yml",
  ".mir/modules.yml",
  ".mir/capabilities.yml",
  ".mir/settings.yml",
  ".mir/compatibility.yml",
  ".mir/streams.yml",
  ".mir/fixtures.yml",
  ".mir/branches.yml",
  ".mir/convergence.yml",
  ".mir/agents.yml"
)) {
  Assert-MIRFileHasSchemaOne -RelativePath $manifest
}

$docsManifestText = Read-MIRText -RelativePath ".mir/docs.yml"
$manifestDocPaths = @(Get-MIRManifestDocPaths -Text $docsManifestText)
if ($manifestDocPaths.Count -eq 0) {
  throw ".mir/docs.yml must register docs."
}

$manifestDuplicates = @($manifestDocPaths | Group-Object | Where-Object { $_.Count -gt 1 })
if ($manifestDuplicates.Count -gt 0) {
  throw ".mir/docs.yml has duplicate paths: $($manifestDuplicates.Name -join ', ')"
}

$docFiles = @(
  Get-ChildItem -LiteralPath $docsRoot -Recurse -File -Filter "*.md" |
    Sort-Object FullName |
    ForEach-Object { Get-MIRRelativePath -Path $_.FullName }
)

$missingFromManifest = @($docFiles | Where-Object { $_ -notin $manifestDocPaths })
if ($missingFromManifest.Count -gt 0) {
  throw ".mir/docs.yml is missing docs: $($missingFromManifest -join ', ')"
}

$missingFromDisk = @($manifestDocPaths | Where-Object { $_ -notin $docFiles })
if ($missingFromDisk.Count -gt 0) {
  throw ".mir/docs.yml references missing docs: $($missingFromDisk -join ', ')"
}

$sourceTruths = @(Get-MIRManifestSourceTruths -Text $docsManifestText)
$duplicateTruths = @($sourceTruths | Group-Object | Where-Object { $_.Count -gt 1 })
if ($duplicateTruths.Count -gt 0) {
  throw ".mir/docs.yml has duplicate source_of_truth_for values: $($duplicateTruths.Name -join ', ')"
}

foreach ($docPath in $docFiles) {
  $fullPath = Join-Path $repo $docPath
  $text = Get-Content -Raw -LiteralPath $fullPath
  $frontmatter = Get-MIRFrontmatter -Text $text -RelativePath $docPath
  foreach ($field in @("title", "status", "applies_to", "audience", "doc_type", "owner", "last_reviewed", "supersedes", "superseded_by")) {
    $null = Get-MIRFrontmatterString -Fields $frontmatter -Name $field -RelativePath $docPath
  }

  $status = Get-MIRFrontmatterString -Fields $frontmatter -Name "status" -RelativePath $docPath
  $docType = Get-MIRFrontmatterString -Fields $frontmatter -Name "doc_type" -RelativePath $docPath
  $audience = Get-MIRFrontmatterString -Fields $frontmatter -Name "audience" -RelativePath $docPath

  if ($status -notin $allowedStatuses) { throw "$docPath has invalid status: $status" }
  if ($docType -notin $allowedDocTypes) { throw "$docPath has invalid doc_type: $docType" }
  if ($audience -notin $allowedAudiences) { throw "$docPath has invalid audience: $audience" }

  if ($docPath.StartsWith("docs/archive/") -and $docPath -ne "docs/archive/README.md" -and $status -ne "archived") {
    throw "$docPath is under docs/archive but status is $status."
  }
  if ($status -eq "archived") {
    $supersededBy = Get-MIRFrontmatterString -Fields $frontmatter -Name "superseded_by" -RelativePath $docPath
    if ($supersededBy -eq "[]") {
      throw "$docPath is archived but superseded_by is empty."
    }
  }

  $name = [System.IO.Path]::GetFileName($docPath)
  if ($name -in $forbiddenDocNames) {
    throw "$docPath uses a forbidden dumping-ground filename."
  }
  if ($name -ne "README.md" -and $name -notmatch "^(\d{4}-)?[a-z0-9][a-z0-9.-]*(-[a-z0-9][a-z0-9.-]*)*\.md$") {
    throw "$docPath is not lower-kebab-case markdown."
  }

  if (-not $docPath.StartsWith("docs/archive/")) {
    if (($text -match "\]\((\.\./)?archive/") -and ($text -notmatch "(?i)historical")) {
      throw "$docPath links to archive content without marking it as historical context."
    }
  }

  Assert-MIRRelativeMarkdownLinks -RelativePath $docPath -Text $text
}

$docDirectories = @(
  Get-ChildItem -LiteralPath $docsRoot -Recurse -Directory |
    Where-Object {
      @(Get-ChildItem -LiteralPath $_.FullName -File -Filter "*.md" -ErrorAction SilentlyContinue).Count -gt 0
    }
)
foreach ($dir in $docDirectories) {
  $readmePath = Join-Path $dir.FullName "README.md"
  if (-not (Test-Path -LiteralPath $readmePath)) {
    throw "Documentation folder missing README.md: $(Get-MIRRelativePath -Path $dir.FullName)"
  }
}

foreach ($manifest in @(".mir/compatibility.yml", ".mir/streams.yml")) {
  $text = Read-MIRText -RelativePath $manifest
  foreach ($match in [regex]::Matches($text, "(?m)^canonical_[a-z_]+:\s+(.+?)\s*$")) {
    $relative = $match.Groups[1].Value.Trim()
    if (-not (Test-MIRRepoPath -RelativePath $relative)) {
      throw "$manifest references missing canonical record: $relative"
    }
  }
}

$capabilitiesText = Read-MIRText -RelativePath ".mir/capabilities.yml"
foreach ($match in [regex]::Matches($capabilitiesText, "(?m)^\s+doc:\s+(.+?\.md)\s*$")) {
  $relative = $match.Groups[1].Value.Trim()
  if (-not (Test-MIRRepoPath -RelativePath $relative)) {
    throw ".mir/capabilities.yml references missing doc: $relative"
  }
}
foreach ($match in [regex]::Matches($capabilitiesText, "(?m)^\s+current_path:\s+(.+?)\s*$")) {
  $relative = $match.Groups[1].Value.Trim()
  if (-not (Test-MIRRepoPath -RelativePath $relative)) {
    throw ".mir/capabilities.yml references missing current_path: $relative"
  }
}

$fixturesText = Read-MIRText -RelativePath ".mir/fixtures.yml"
foreach ($match in [regex]::Matches($fixturesText, "(?m)^\s+(path|assertion_path):\s+(.+?)\s*$")) {
  $relative = $match.Groups[2].Value.Trim()
  if (-not (Test-MIRRepoPath -RelativePath $relative)) {
    throw ".mir/fixtures.yml references missing fixture path: $relative"
  }
}

$convergenceText = Read-MIRText -RelativePath ".mir/convergence.yml"
foreach ($needle in @(
  'version: "3.0.5"',
  'objective: behavioral-superset-implementation-subset',
  'baseline_tag: pre-3.0.5-synthesis',
  'BP-002:',
  'BP-013:',
  'target-profile-drift-check',
  'complete-structured-validation-summary'
)) {
  if (-not $convergenceText.Contains($needle)) {
    throw ".mir/convergence.yml is missing required convergence contract text: $needle"
  }
}

$behaviorIds = @(
  [regex]::Matches($convergenceText, '(?m)^\s{2}(BP-\d{3}):\s*$') |
    ForEach-Object { $_.Groups[1].Value }
)
$duplicateBehaviorIds = @($behaviorIds | Group-Object | Where-Object { $_.Count -gt 1 })
if ($duplicateBehaviorIds.Count -gt 0) {
  throw ".mir/convergence.yml has duplicate behavior IDs: $($duplicateBehaviorIds.Name -join ', ')"
}

$claimsManifestText = Read-MIRText -RelativePath ".mir/compatibility.yml"
$claimsPathMatch = [regex]::Match($claimsManifestText, "(?m)^canonical_machine_record:\s+(.+?)\s*$")
if (-not $claimsPathMatch.Success) {
  throw ".mir/compatibility.yml must declare canonical_machine_record."
}
$targetDocsRootMatch = [regex]::Match($claimsManifestText, "(?m)^target_docs_root:\s+(.+?)\s*$")
if (-not $targetDocsRootMatch.Success) {
  throw ".mir/compatibility.yml must declare target_docs_root."
}
$targetDocsRoot = $targetDocsRootMatch.Groups[1].Value.Trim().TrimEnd("/")
$claims = Get-Content -Raw -LiteralPath (Join-Path $repo $claimsPathMatch.Groups[1].Value.Trim()) | ConvertFrom-Json
foreach ($claim in @($claims.claims)) {
  $slug = ConvertTo-MIRClaimPageSlug -Name ([string]$claim.mod)
  $page = "$targetDocsRoot/$slug.md"
  if (-not (Test-MIRRepoPath -RelativePath $page)) {
    throw "Compatibility claim $($claim.mod) has no claim page: $page"
  }
}

$profilesText = Read-MIRText -RelativePath "prototypes/mir/compatibility/profiles.lua"
$profilesCodeLines = @($profilesText -split "\r?\n" | Where-Object { $_ -notmatch "^\s*--" })
if (($profilesCodeLines -join "`n") -match "data:extend|data\.raw") {
  throw "prototypes/mir/compatibility/profiles.lua must stay declarative and must not mutate or inspect data.raw."
}

$capabilityLuaFiles = @(
  Get-ChildItem -LiteralPath (Join-Path $repo "prototypes/mir/capabilities") -Recurse -File -Filter "*.lua" -ErrorAction SilentlyContinue
)
foreach ($file in $capabilityLuaFiles) {
  $text = Get-Content -Raw -LiteralPath $file.FullName
  if ($text -match "data:extend") {
    throw "$(Get-MIRRelativePath -Path $file.FullName) must not call data:extend."
  }
}

Write-Host "[ok] MIR docs and governance lint passed."

