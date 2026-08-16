param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$marker = "MIR-L5-LEGACY-COMMAND-WRAPPER"
$commands = [ordered]@{
  "scripts/Convert-MIRCompatAuditResults.ps1" = "tools/commands/compatibility/Convert-MIRCompatAuditResults.ps1"
  "scripts/Invoke-MIRCompatAudit.ps1" = "tools/commands/compatibility/Invoke-MIRCompatAudit.ps1"
  "scripts/New-MIRCompatProfileStub.ps1" = "tools/commands/compatibility/New-MIRCompatProfileStub.ps1"
  "scripts/New-MIRFactorioLineTestAdapter.ps1" = "tools/commands/compatibility/New-MIRFactorioLineTestAdapter.ps1"
  "scripts/New-MIRModInteractionGraph.ps1" = "tools/commands/compatibility/New-MIRModInteractionGraph.ps1"
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
      throw "Refusing duplicate compatibility-command implementations: $legacyRelative and $canonicalRelative"
    }
    $moveCount++
    $moved += $canonicalRelative
    if ($Apply) {
      $null = New-Item -ItemType Directory -Path (Split-Path -Parent $canonicalPath) -Force
      $canonicalText = $legacyText
      if ($legacyRelative -eq "scripts/Convert-MIRCompatAuditResults.ps1") {
        $canonicalText = $canonicalText.Replace(
          'Join-Path $PSScriptRoot "..\validation\',
          'Join-Path $PSScriptRoot "..\..\..\validation\'
        )
      }
      if ($legacyRelative -eq "scripts/Invoke-MIRCompatAudit.ps1") {
        $canonicalText = $canonicalText.Replace(
          'Join-Path $PSScriptRoot "..\',
          'Join-Path $PSScriptRoot "..\..\..\'
        ).Replace(
          'Resolve-Path (Join-Path $PSScriptRoot "..")',
          'Resolve-Path (Join-Path $PSScriptRoot "../../..")'
        ).Replace(
          '$moduleRoot = Join-Path $PSScriptRoot "MIRCompatAudit"',
          '$moduleRoot = Join-Path $repo "tools\lib\compatibility"'
        ).Replace(
          '. (Join-Path $PSScriptRoot "validation\SettingsOverrides.ps1")',
          '. (Join-Path $repo "tools\lib\validation\SettingsOverrides.ps1")'
        )
      }
      if ($legacyRelative -eq "scripts/New-MIRModInteractionGraph.ps1") {
        $canonicalText = $canonicalText.Replace(
          'Join-Path $PSScriptRoot ".."',
          'Join-Path $PSScriptRoot "../../.."'
        )
      }
      if ($canonicalText -ceq $legacyText -and $legacyRelative -in @(
        "scripts/Convert-MIRCompatAuditResults.ps1",
        "scripts/Invoke-MIRCompatAudit.ps1",
        "scripts/New-MIRModInteractionGraph.ps1"
      )) {
        throw "Compatibility command root bootstrap was not rewritten: $legacyRelative"
      }
      [IO.File]::WriteAllText($canonicalPath, $canonicalText, $utf8NoBom)

      $bodyIndex = $legacyText.IndexOf('$ErrorActionPreference')
      if ($bodyIndex -lt 1) { throw "Compatibility command has no stable parameter/body boundary: $legacyRelative" }
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
    throw "Legacy compatibility-command wrapper has no canonical implementation: $legacyRelative"
  }
}

[ordered]@{
  schema = 1
  migration = "mir-compatibility-commands-v1"
  mode = if ($Apply) { "apply" } else { "preview" }
  commands = $commands.Count
  implementations = $moveCount
  changed = $moveCount
  moved = @($moved)
} | ConvertTo-Json -Depth 5
