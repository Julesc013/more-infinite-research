param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$marker = "MIR-L5-LEGACY-COMMAND-WRAPPER"
$commands = [ordered]@{
  "scripts/Sync-MIRTargetProfiles.ps1" = "tools/commands/targets/Sync-MIRTargetProfiles.ps1"
  "scripts/Update-MIRCompilerAuthorities.ps1" = "tools/commands/compiler/Update-MIRCompilerAuthorities.ps1"
  "scripts/Update-MIRLocales.ps1" = "tools/commands/localization/Update-MIRLocales.ps1"
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
      throw "Refusing duplicate authority-command implementations: $legacyRelative and $canonicalRelative"
    }
    $moveCount++
    $moved += $canonicalRelative
    if ($Apply) {
      $null = New-Item -ItemType Directory -Path (Split-Path -Parent $canonicalPath) -Force
      $canonicalText = $legacyText
      if ($legacyRelative -in @("scripts/Sync-MIRTargetProfiles.ps1", "scripts/Update-MIRCompilerAuthorities.ps1")) {
        $canonicalText = $canonicalText.Replace(
          'Join-Path $PSScriptRoot ".."',
          'Join-Path $PSScriptRoot "../../.."'
        )
      } else {
        $canonicalText = $canonicalText.Replace(
          '(Split-Path -Parent $PSScriptRoot)',
          '(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path'
        )
      }
      if ($canonicalText -ceq $legacyText) {
        throw "Authority command repository-root bootstrap was not rewritten: $legacyRelative"
      }
      if ($legacyRelative -eq "scripts/Sync-MIRTargetProfiles.ps1") {
        $canonicalText = $canonicalText.Replace(
          "Generated target profile Lua is stale. Run scripts/Sync-MIRTargetProfiles.ps1.",
          "Generated target profile Lua is stale. Run tools/commands/targets/Sync-MIRTargetProfiles.ps1."
        )
      }
      [IO.File]::WriteAllText($canonicalPath, $canonicalText, $utf8NoBom)

      $bodyIndex = $legacyText.IndexOf('$ErrorActionPreference')
      if ($bodyIndex -lt 1) { throw "Authority command has no stable parameter/body boundary: $legacyRelative" }
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
    throw "Legacy authority-command wrapper has no canonical implementation: $legacyRelative"
  }
}

[ordered]@{
  schema = 1
  migration = "mir-authority-commands-v1"
  mode = if ($Apply) { "apply" } else { "preview" }
  commands = $commands.Count
  implementations = $moveCount
  changed = $moveCount
  moved = @($moved)
} | ConvertTo-Json -Depth 5
