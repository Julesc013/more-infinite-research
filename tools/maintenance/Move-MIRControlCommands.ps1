param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$marker = "MIR-L5-LEGACY-COMMAND-WRAPPER"
$commands = [ordered]@{
  "scripts/Invoke-MIRControlPlane.ps1" = "tools/commands/control/Invoke-MIRControlPlane.ps1"
  "scripts/Invoke-MIRControlPlaneWork.ps1" = "tools/commands/control/Invoke-MIRControlPlaneWork.ps1"
  "scripts/New-MIRVerificationContext.ps1" = "tools/commands/control/New-MIRVerificationContext.ps1"
  "scripts/Update-MIRExecutionRegistry.ps1" = "tools/commands/control/Update-MIRExecutionRegistry.ps1"
  "scripts/Update-MIRObservationReplay.ps1" = "tools/commands/control/Update-MIRObservationReplay.ps1"
  "scripts/Update-MIRShadowAnalysis.ps1" = "tools/commands/control/Update-MIRShadowAnalysis.ps1"
  "scripts/Update-MIRShadowBaselines.ps1" = "tools/commands/control/Update-MIRShadowBaselines.ps1"
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
      throw "Refusing duplicate control-command implementations: $legacyRelative and $canonicalRelative"
    }
    $moveCount++
    $moved += $canonicalRelative
    if ($Apply) {
      $null = New-Item -ItemType Directory -Path (Split-Path -Parent $canonicalPath) -Force
      $canonicalText = $legacyText.Replace(
        'Join-Path $PSScriptRoot ".."',
        'Join-Path $PSScriptRoot "../../.."'
      )
      if ($canonicalText -ceq $legacyText) {
        throw "Control command repository-root bootstrap was not rewritten: $legacyRelative"
      }
      if ($legacyRelative -eq "scripts/Invoke-MIRControlPlane.ps1") {
        $beforeImport = '. (Join-Path $PSScriptRoot "MIRControlPlane/$module.ps1")'
        $canonicalText = $canonicalText.Replace(
          $beforeImport,
          '. (Join-Path $repo "tools/lib/control/$module.ps1")'
        )
        if ($canonicalText.Contains($beforeImport)) {
          throw "Control-plane facade retained a legacy library import."
        }
      }
      [IO.File]::WriteAllText($canonicalPath, $canonicalText, $utf8NoBom)

      $bodyIndex = $legacyText.IndexOf('$ErrorActionPreference')
      if ($bodyIndex -lt 1) { throw "Control command has no stable parameter/body boundary: $legacyRelative" }
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
    throw "Legacy control-command wrapper has no canonical implementation: $legacyRelative"
  }
}

[ordered]@{
  schema = 1
  migration = "mir-control-commands-v1"
  mode = if ($Apply) { "apply" } else { "preview" }
  commands = $commands.Count
  implementations = $moveCount
  changed = $moveCount
  moved = @($moved)
} | ConvertTo-Json -Depth 5
