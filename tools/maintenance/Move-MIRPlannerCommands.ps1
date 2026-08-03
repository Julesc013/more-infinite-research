param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$marker = "MIR-L5-LEGACY-COMMAND-WRAPPER"
$commands = [ordered]@{
  "scripts/Compare-MIRPlannerReports.ps1" = "tools/commands/planner/Compare-MIRPlannerReports.ps1"
  "scripts/Compare-MIRPlannerSnapshots.ps1" = "tools/commands/planner/Compare-MIRPlannerSnapshots.ps1"
  "scripts/Export-MIRPlannerSnapshot.ps1" = "tools/commands/planner/Export-MIRPlannerSnapshot.ps1"
  "scripts/Minimize-MIRPlannerSnapshot.ps1" = "tools/commands/planner/Minimize-MIRPlannerSnapshot.ps1"
  "scripts/New-MIRCompatibilityPack.ps1" = "tools/commands/compatibility/New-MIRCompatibilityPack.ps1"
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
      throw "Refusing duplicate planner-command implementations: $legacyRelative and $canonicalRelative"
    }
    $moveCount++
    $moved += $canonicalRelative
    if ($Apply) {
      $null = New-Item -ItemType Directory -Path (Split-Path -Parent $canonicalPath) -Force
      $canonicalText = $legacyText
      if ($legacyRelative -eq "scripts/Export-MIRPlannerSnapshot.ps1") {
        $canonicalText = $canonicalText.Replace(
          'Join-Path $PSScriptRoot "MIRCompatAudit\DiagnosticsParser.ps1"',
          'Join-Path $PSScriptRoot "../../lib/compatibility/DiagnosticsParser.ps1"'
        )
        if ($canonicalText -ceq $legacyText) {
          throw "Planner snapshot dependency bootstrap was not rewritten."
        }
      }
      [IO.File]::WriteAllText($canonicalPath, $canonicalText, $utf8NoBom)

      $bodyIndex = $legacyText.IndexOf('$ErrorActionPreference')
      if ($bodyIndex -lt 1) { throw "Planner command has no stable parameter/body boundary: $legacyRelative" }
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
    throw "Legacy planner-command wrapper has no canonical implementation: $legacyRelative"
  }
}

[ordered]@{
  schema = 1
  migration = "mir-planner-commands-v1"
  mode = if ($Apply) { "apply" } else { "preview" }
  commands = $commands.Count
  implementations = $moveCount
  changed = $moveCount
  moved = @($moved)
} | ConvertTo-Json -Depth 5
