param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$legacyRelative = "scripts/mir.ps1"
$canonicalRelative = "tools/mir.ps1"
$legacyPath = Join-Path $RepoRoot $legacyRelative
$canonicalPath = Join-Path $RepoRoot $canonicalRelative
$marker = "MIR-L5-LEGACY-CLI-WRAPPER"

function Get-MIRActiveFacadeReferenceFiles {
  $roots = @(".github", ".mir", "docs", "fixtures", "scripts", "spec", "tools", "validation")
  $files = @()
  foreach ($root in $roots) {
    $absolute = Join-Path $RepoRoot $root
    if (Test-Path -LiteralPath $absolute) {
      $files += Get-ChildItem -LiteralPath $absolute -Recurse -File
    }
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
    $relative -ne ".mir/control/aliases.yml" -and
    $relative -notlike "docs/archive/*" -and
    $relative -notlike "docs/releases/*" -and
    $relative -ne "docs/architecture/3.3-2.6-semantic-platform-roadmap.md" -and
    $relative -ne "scripts/Get-MIRLegacyInventory.ps1" -and
    $relative -ne $legacyRelative -and
    $relative -ne $canonicalRelative -and
    $relative -notlike "tools/maintenance/*" -and
    $relative -ne "validation/tests/tooling/Test-MIRLayout.ps1"
  } | Sort-Object FullName -Unique)
}

$legacyText = Get-Content -Raw -LiteralPath $legacyPath
$canonicalText = Get-Content -Raw -LiteralPath $canonicalPath
$implementationMove = 0
if (-not $legacyText.Contains($marker)) {
  if ($canonicalText -notmatch 'scripts[/\\]mir\.ps1' -or $canonicalText.Split([char]10).Count -gt 20) {
    throw "Refusing to overwrite a non-forwarding public CLI: $canonicalRelative"
  }
  $implementationMove = 1
  if ($Apply) {
    $oldCrLf = '$scriptRoot = $PSScriptRoot' + "`r`n" + '$repo = Resolve-Path (Join-Path $scriptRoot "..")'
    $newCrLf = '$repo = Resolve-Path (Join-Path $PSScriptRoot "..")' + "`r`n" + '$scriptRoot = Join-Path $repo "scripts"'
    $oldLf = '$scriptRoot = $PSScriptRoot' + "`n" + '$repo = Resolve-Path (Join-Path $scriptRoot "..")'
    $newLf = '$repo = Resolve-Path (Join-Path $PSScriptRoot "..")' + "`n" + '$scriptRoot = Join-Path $repo "scripts"'
    $movedText = $legacyText.Replace($oldCrLf, $newCrLf).Replace($oldLf, $newLf)
    if ($movedText -ceq $legacyText -or -not $movedText.Contains('$scriptRoot = Join-Path $repo "scripts"')) {
      throw "Could not rewrite the CLI dispatcher bootstrap safely."
    }
    [IO.File]::WriteAllText($canonicalPath, $movedText, $utf8NoBom)
    $wrapper = @"
# ${marker}: retained for historical command compatibility only.
param(
  [Parameter(ValueFromRemainingArguments = `$true)]
  [string[]]`$Args
)

`$ErrorActionPreference = "Stop"
`$repo = (Resolve-Path (Join-Path `$PSScriptRoot "..")).Path
& (Join-Path `$repo "tools/mir.ps1") @Args
exit `$LASTEXITCODE
"@
    [IO.File]::WriteAllText($legacyPath, $wrapper, $utf8NoBom)
  }
} elseif ($canonicalText.Contains($marker) -or $canonicalText -match 'scripts[/\\]mir\.ps1') {
  throw "Legacy/public CLI forwarding direction is invalid."
}

$referenceFiles = @()
foreach ($file in Get-MIRActiveFacadeReferenceFiles) {
  $text = Get-Content -Raw -LiteralPath $file.FullName
  $updated = $text.Replace("scripts/mir.ps1", "tools/mir.ps1").Replace("scripts\mir.ps1", "tools\mir.ps1")
  if ($updated -cne $text) {
    $referenceFiles += [IO.Path]::GetRelativePath($RepoRoot, $file.FullName).Replace("\", "/")
    if ($Apply) { [IO.File]::WriteAllText($file.FullName, $updated, $utf8NoBom) }
  }
}

[ordered]@{
  schema = 1
  migration = "mir-cli-facade-v1"
  mode = if ($Apply) { "apply" } else { "preview" }
  implementation_moves = $implementationMove
  reference_files = $referenceFiles.Count
  changed = $implementationMove + $referenceFiles.Count
  canonical = $canonicalRelative
  legacy = $legacyRelative
  rewritten = @($referenceFiles)
} | ConvertTo-Json -Depth 5
