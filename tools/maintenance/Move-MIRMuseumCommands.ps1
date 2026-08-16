param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$marker = "MIR-L5-LEGACY-COMMAND-WRAPPER"
$commands = [ordered]@{
  "scripts/Build-MIRMuseumTarget.ps1" = "tools/commands/museum/Build-MIRMuseumTarget.ps1"
  "scripts/New-MIRMuseumQualification.ps1" = "tools/commands/museum/New-MIRMuseumQualification.ps1"
  "scripts/New-MIRMuseumSeal.ps1" = "tools/commands/museum/New-MIRMuseumSeal.ps1"
}

$moveCount = 0
$moved = @()
foreach ($legacyRelative in $commands.Keys) {
  $canonicalRelative = $commands[$legacyRelative]
  $legacyPath = Join-Path $RepoRoot $legacyRelative
  $canonicalPath = Join-Path $RepoRoot $canonicalRelative
  $legacyText = Get-Content -Raw -LiteralPath $legacyPath
  if (-not $legacyText.Contains($marker)) {
    if (Test-Path -LiteralPath $canonicalPath -PathType Leaf) {
      throw "Refusing duplicate museum-command implementations: $legacyRelative and $canonicalRelative"
    }
    $moveCount++
    $moved += $canonicalRelative
    if ($Apply) {
      $null = New-Item -ItemType Directory -Path (Split-Path -Parent $canonicalPath) -Force
      $canonicalText = $legacyText.Replace(
        'Resolve-Path (Join-Path $PSScriptRoot "..")',
        'Resolve-Path (Join-Path $PSScriptRoot "../../..")'
      ).Replace(
        'Import-Module (Join-Path $PSScriptRoot "Museum\MuseumCompiler.psm1") -Force',
        'Import-Module (Join-Path $repo "tools\lib\museum\MuseumCompiler.psm1") -Force'
      )
      if ($legacyRelative -eq "scripts/New-MIRMuseumSeal.ps1") {
        $canonicalText = $canonicalText.Replace(
          '"scripts\Build-MIRMuseumTarget.ps1"',
          '"tools\commands\museum\Build-MIRMuseumTarget.ps1"'
        ).Replace(
          '"scripts\New-MIRMuseumQualification.ps1"',
          '"tools\commands\museum\New-MIRMuseumQualification.ps1"'
        ).Replace(
          '"scripts\New-MIRMuseumSeal.ps1"',
          '"tools\commands\museum\New-MIRMuseumSeal.ps1"'
        )
      }
      if ($canonicalText -ceq $legacyText) { throw "Museum command bootstrap was not rewritten: $legacyRelative" }
      [IO.File]::WriteAllText($canonicalPath, $canonicalText.TrimEnd("`r", "`n") + "`n", $utf8NoBom)

      $bodyIndex = $legacyText.IndexOf('$ErrorActionPreference')
      if ($bodyIndex -lt 1) { throw "Museum command has no stable parameter/body boundary: $legacyRelative" }
      $parameterBlock = $legacyText.Substring(0, $bodyIndex).TrimEnd()
      $relativeTarget = "../" + $canonicalRelative
      $wrapper = @"
$parameterBlock

# ${marker}: retained for historical command compatibility only.
`$canonicalCommand = Join-Path `$PSScriptRoot "$relativeTarget"
& `$canonicalCommand @PSBoundParameters
exit `$LASTEXITCODE
"@
      [IO.File]::WriteAllText($legacyPath, $wrapper, $utf8NoBom)
    }
  } elseif (-not (Test-Path -LiteralPath $canonicalPath -PathType Leaf)) {
    throw "Legacy museum-command wrapper has no canonical implementation: $legacyRelative"
  }
}

[ordered]@{
  schema = 1
  migration = "mir-museum-commands-v1"
  mode = if ($Apply) { "apply" } else { "preview" }
  commands = $commands.Count
  implementations = $moveCount
  changed = $moveCount
  moved = @($moved)
} | ConvertTo-Json -Depth 5
