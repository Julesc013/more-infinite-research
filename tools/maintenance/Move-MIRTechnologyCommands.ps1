param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$marker = "MIR-L5-LEGACY-COMMAND-WRAPPER"
$commands = [ordered]@{
  "scripts/Compare-MIRTechnologyDesigns.ps1" = "tools/commands/technology/Compare-MIRTechnologyDesigns.ps1"
  "scripts/Export-MIRCompilerPreview.ps1" = "tools/commands/technology/Export-MIRCompilerPreview.ps1"
  "scripts/Export-MIRTechnologyCatalog.ps1" = "tools/commands/technology/Export-MIRTechnologyCatalog.ps1"
  "scripts/New-MIRTechnologyLifecycleRecord.ps1" = "tools/commands/technology/New-MIRTechnologyLifecycleRecord.ps1"
  "scripts/New-MIRTechnologyQualityAssessment.ps1" = "tools/commands/technology/New-MIRTechnologyQualityAssessment.ps1"
  "scripts/New-MIRTechnologyReviewDossier.ps1" = "tools/commands/technology/New-MIRTechnologyReviewDossier.ps1"
  "scripts/Update-MIRTechnologyGovernance.ps1" = "tools/commands/technology/Update-MIRTechnologyGovernance.ps1"
  "scripts/Invoke-MIRRuleSynthesis.ps1" = "tools/commands/technology/Invoke-MIRRuleSynthesis.ps1"
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
      throw "Refusing duplicate technology-command implementations: $legacyRelative and $canonicalRelative"
    }
    $moveCount++
    $moved += $canonicalRelative
    if ($Apply) {
      $null = New-Item -ItemType Directory -Path (Split-Path -Parent $canonicalPath) -Force
      $canonicalText = $legacyText
      if ($legacyRelative -eq "scripts/Export-MIRCompilerPreview.ps1") {
        $canonicalText = $canonicalText.Replace(
          'Join-Path $PSScriptRoot ".."',
          'Join-Path $PSScriptRoot "../../.."'
        )
        if ($canonicalText -ceq $legacyText) {
          throw "Compiler preview root bootstrap was not rewritten."
        }
      }
      if ($legacyRelative -eq "scripts/Update-MIRTechnologyGovernance.ps1") {
        $canonicalText = $canonicalText.Replace(
          'Join-Path $PSScriptRoot ".."',
          'Join-Path $PSScriptRoot "../../.."'
        )
        if ($canonicalText -ceq $legacyText) {
          throw "Technology governance root bootstrap was not rewritten."
        }
      }
      if ($legacyRelative -eq "scripts/Invoke-MIRRuleSynthesis.ps1") {
        $canonicalText = $canonicalText.Replace(
          'Join-Path $PSScriptRoot ".."',
          'Join-Path $PSScriptRoot "../../.."'
        )
        if ($canonicalText -ceq $legacyText) {
          throw "Rule synthesis root bootstrap was not rewritten."
        }
      }
      [IO.File]::WriteAllText($canonicalPath, $canonicalText, $utf8NoBom)

      $bodyIndex = $legacyText.IndexOf('$ErrorActionPreference')
      if ($bodyIndex -lt 1) { throw "Technology command has no stable parameter/body boundary: $legacyRelative" }
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
    throw "Legacy technology-command wrapper has no canonical implementation: $legacyRelative"
  }
}

[ordered]@{
  schema = 1
  migration = "mir-technology-commands-v1"
  mode = if ($Apply) { "apply" } else { "preview" }
  commands = $commands.Count
  implementations = $moveCount
  changed = $moveCount
  moved = @($moved)
} | ConvertTo-Json -Depth 5
