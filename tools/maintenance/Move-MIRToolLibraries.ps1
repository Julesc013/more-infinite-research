param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$roots = [ordered]@{
  "scripts/MIRAssurance" = "tools/lib/assurance"
  "scripts/MIRCli" = "tools/lib/cli"
  "scripts/MIRCompatAudit" = "tools/lib/compatibility"
  "scripts/MIRControlPlane" = "tools/lib/control"
  "scripts/localization" = "tools/lib/localization"
  "scripts/Museum" = "tools/lib/museum"
  "scripts/validation" = "tools/lib/validation"
}

function Get-MIRActiveToolFiles {
  $activeRoots = @(".github", ".mir", "docs", "scripts", "validation", "tools", "spec", "fixtures")
  $files = @()
  foreach ($root in $activeRoots) {
    $absolute = Join-Path $RepoRoot $root
    if (Test-Path -LiteralPath $absolute) { $files += Get-ChildItem -LiteralPath $absolute -Recurse -File }
  }
  foreach ($name in @("AGENTS.md", "CONTRIBUTING.md")) {
    $absolute = Join-Path $RepoRoot $name
    if (Test-Path -LiteralPath $absolute -PathType Leaf) { $files += Get-Item -LiteralPath $absolute }
  }
  return @($files | Where-Object {
    $relative = [IO.Path]::GetRelativePath($RepoRoot, $_.FullName).Replace("\", "/")
    $_.Extension -in @(".json", ".md", ".ps1", ".psm1", ".yml", ".yaml") -and
    $relative -notlike ".mir/evidence/*" -and
    $relative -notlike ".mir/target-lines/*" -and
    $relative -notlike ".mir/releases/*" -and
    $relative -notlike ".mir/candidate-closures/*" -and
    $relative -notlike ".mir/release-transitions/*" -and
    $relative -notlike ".mir/backports/*" -and
    $relative -notlike ".mir/backport-*.json" -and
    $relative -ne ".mir/performance-campaign.json" -and
    $relative -notlike ".mir/performance-campaigns/*" -and
    $relative -notlike "docs/archive/*" -and
    $relative -notlike "docs/releases/*" -and
    $relative -ne "README.md" -and
    $relative -ne "tools/maintenance/Move-MIRToolLibraries.ps1" -and
    $relative -ne ".mir/control/aliases.yml"
  } | Sort-Object FullName -Unique)
}

$files = [ordered]@{}
foreach ($fromRoot in $roots.Keys) {
  $sourceRoot = Join-Path $RepoRoot $fromRoot
  $targetRoot = Join-Path $RepoRoot $roots[$fromRoot]
  $legacyFiles = @(Get-ChildItem -LiteralPath $sourceRoot -File)
  foreach ($legacyFile in $legacyFiles) {
    $relative = "$fromRoot/$($legacyFile.Name)"
    $targetRelative = "$($roots[$fromRoot])/$($legacyFile.Name)"
    $files[$relative] = $targetRelative
  }
  if ($legacyFiles.Count -eq 0 -and -not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    throw "Tool library root is absent from legacy and canonical locations: $fromRoot"
  }
}

$moveCount = 0
$moved = @()
foreach ($from in $files.Keys) {
  $source = Join-Path $RepoRoot $from
  $targetRelative = $files[$from]
  $target = Join-Path $RepoRoot $targetRelative
  $sourceText = Get-Content -Raw -LiteralPath $source
  $isWrapper = $sourceText.Contains("MIR-L5-LEGACY-LIBRARY-WRAPPER")
  if (-not $isWrapper) {
    if (Test-Path -LiteralPath $target -PathType Leaf) {
      throw "Refusing duplicate tool library implementations: $from and $targetRelative"
    }
    $moveCount++
    $moved += $targetRelative
    if ($Apply) {
      $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
      $canonicalText = $sourceText
      if ($from -eq "scripts/MIRAssurance/Core.ps1") {
        $canonicalText = $canonicalText.Replace(
          '$scriptsRoot = Split-Path -Parent $PSScriptRoot' + [Environment]::NewLine + '  $repositoryRoot = Split-Path -Parent $scriptsRoot',
          '$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path'
        )
      }
      if ($from -eq "scripts/MIRControlPlane/Core.ps1") {
        $canonicalText = $canonicalText.Replace('Join-Path $PSScriptRoot "..\.."', 'Join-Path $PSScriptRoot "../../.."')
      }
      [IO.File]::WriteAllText($target, $canonicalText, $utf8NoBom)
      $relativeFromLegacy = "../../" + $targetRelative
      $forwardCommand = if ([IO.Path]::GetExtension($from) -eq ".psm1") { "Import-Module" } else { "." }
      $forwardOptions = if ([IO.Path]::GetExtension($from) -eq ".psm1") { " -Force -Global" } else { "" }
      $wrapper = @"
# MIR-L5-LEGACY-LIBRARY-WRAPPER: retained for historical imports only.
$forwardCommand (Join-Path $([char]36)PSScriptRoot "$relativeFromLegacy")$forwardOptions
"@
      [IO.File]::WriteAllText($source, $wrapper, $utf8NoBom)
    }
  } elseif (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    throw "Legacy library wrapper has no canonical implementation: $from"
  }
}

$referenceFiles = @()
foreach ($file in Get-MIRActiveToolFiles) {
  $text = Get-Content -Raw -LiteralPath $file.FullName
  $updated = $text
  $updated = $updated.Replace(
    '(Join-Path $PSScriptRoot "MIRCli\',
    '(Join-Path $repo "tools\lib\cli\'
  )
  $updated = $updated.Replace(
    '(Join-Path $scriptRoot "MIRCli\',
    '(Join-Path $repo "tools\lib\cli\'
  )
  foreach ($fromRoot in $roots.Keys) {
    $toRoot = $roots[$fromRoot]
    $updated = $updated.Replace($fromRoot, $toRoot)
    $updated = $updated.Replace($fromRoot.Replace("/", "\"), $toRoot.Replace("/", "\"))
  }
  if ($updated -ne $text) {
    $referenceFiles += [IO.Path]::GetRelativePath($RepoRoot, $file.FullName).Replace("\", "/")
    if ($Apply) { [IO.File]::WriteAllText($file.FullName, $updated, $utf8NoBom) }
  }
}

[ordered]@{
  schema = 1
  migration = "mir-tool-libraries-v1"
  mode = if ($Apply) { "apply" } else { "preview" }
  libraries = $roots.Count
  implementations = $moveCount
  reference_files = $referenceFiles.Count
  changed = $moveCount + $referenceFiles.Count
  moved = @($moved)
  rewritten = @($referenceFiles)
} | ConvertTo-Json -Depth 6
