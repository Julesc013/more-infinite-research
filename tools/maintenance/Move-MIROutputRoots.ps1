[CmdletBinding()]
param(
  [string]$RepoRoot = "",
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
}
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

$files = [Collections.Generic.List[string]]::new()
foreach ($root in @("scripts", ".github/workflows")) {
  Get-ChildItem -LiteralPath (Join-Path $repo $root) -Recurse -File |
    Where-Object Extension -in @(".ps1", ".psm1", ".yml", ".yaml") |
    ForEach-Object { $files.Add($_.FullName) }
}
foreach ($relative in @(
  ".mir/assurance.json",
  ".mir/control-plane/control-plane.json",
  ".mir/fixtures.yml",
  "validation/tests.yml",
  "validation/domains.yml",
  "validation/trust.json"
)) {
  $path = Join-Path $repo $relative
  if (Test-Path -LiteralPath $path -PathType Leaf) { $files.Add($path) }
}
Get-ChildItem -LiteralPath (Join-Path $repo ".mir/tasks") -Filter *.json -File |
  ForEach-Object { $files.Add($_.FullName) }

$excluded = @(
  (Join-Path $repo "validation/tests/package/Test-MIRArtifactCleanup.ps1"),
  (Join-Path $repo "validation/tests/tooling/Test-MIRPowerShellQuality.ps1"),
  (Join-Path $repo "scripts/Update-MIRShadowBaselines.ps1"),
  (Join-Path $repo "tools/commands/control/Update-MIRShadowBaselines.ps1")
)
$replacements = @(
  [pscustomobject]@{ Pattern = [regex]::Escape("./scripts/mir.ps1"); Replacement = "./tools/mir.ps1" },
  [pscustomobject]@{ Pattern = [regex]::Escape(".\scripts\mir.ps1"); Replacement = ".\tools\mir.ps1" },
  [pscustomobject]@{ Pattern = [regex]::Escape("dist/playtest/"); Replacement = ".work/playtest/" },
  [pscustomobject]@{ Pattern = [regex]::Escape("dist\playtest\"); Replacement = ".work\playtest\" },
  [pscustomobject]@{ Pattern = "(?<!\.work/)artifacts/"; Replacement = ".work/artifacts/" },
  [pscustomobject]@{ Pattern = "(?<!\.work\\)artifacts\\"; Replacement = ".work\artifacts\" },
  [pscustomobject]@{ Pattern = "(?<!\.work/)build/"; Replacement = ".work/build/" },
  [pscustomobject]@{ Pattern = "(?<!\.work\\)build\\"; Replacement = ".work\build\" },
  [pscustomobject]@{ Pattern = [regex]::Escape('Join-Path $repo "build"'); Replacement = 'Join-Path $repo ".work\build"' },
  [pscustomobject]@{ Pattern = "out/"; Replacement = ".work/output/" },
  [pscustomobject]@{ Pattern = "out\\"; Replacement = ".work\output\" },
  [pscustomobject]@{ Pattern = [regex]::Escape('Join-Path $repo "out"'); Replacement = 'Join-Path $repo ".work\output"' },
  [pscustomobject]@{ Pattern = "(?m)^(?<indent>\s*)path:\s*out\s*$"; Replacement = '${indent}path: .work/output' }
)

function Add-MIRHiddenArtifactUploadOptIn {
  param([Parameter(Mandatory)][string]$Text)

  $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
  $hadTrailingNewline = $Text.EndsWith("`n")
  $lines = [Collections.Generic.List[string]]::new()
  foreach ($line in @($Text -split "`r?`n")) { $lines.Add($line) }
  if ($hadTrailingNewline -and $lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") {
    $lines.RemoveAt($lines.Count - 1)
  }

  $insertions = [Collections.Generic.List[object]]::new()
  for ($index = 0; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -notmatch "uses:\s*actions/upload-artifact@") { continue }

    $usesIndent = ([regex]::Match($lines[$index], "^\s*").Value).Length
    $stepStart = $index
    if ($lines[$index] -notmatch "^\s*-\s+uses:") {
      for ($candidate = $index - 1; $candidate -ge 0; $candidate--) {
        $match = [regex]::Match($lines[$candidate], "^(?<indent>\s*)-\s+")
        if ($match.Success -and $match.Groups["indent"].Value.Length -lt $usesIndent) {
          $stepStart = $candidate
          break
        }
      }
    }
    $stepIndent = ([regex]::Match($lines[$stepStart], "^\s*").Value).Length
    $stepEnd = $lines.Count
    for ($candidate = $stepStart + 1; $candidate -lt $lines.Count; $candidate++) {
      $match = [regex]::Match($lines[$candidate], "^(?<indent>\s*)-\s+")
      if ($match.Success -and $match.Groups["indent"].Value.Length -eq $stepIndent) {
        $stepEnd = $candidate
        break
      }
    }

    $block = ($lines.GetRange($stepStart, $stepEnd - $stepStart) -join "`n")
    if ($block -notmatch "\.work/" -or
        $block -match "(?m)^\s+include-hidden-files:\s*true\s*$") {
      continue
    }

    for ($candidate = $index + 1; $candidate -lt $stepEnd; $candidate++) {
      $match = [regex]::Match($lines[$candidate], "^(?<indent>\s*)with:\s*$")
      if (-not $match.Success) { continue }
      $insertions.Add([pscustomobject]@{
        Index = $candidate + 1
        Text = "$($match.Groups["indent"].Value)  include-hidden-files: true"
      })
      break
    }
  }

  foreach ($insertion in @($insertions | Sort-Object Index -Descending)) {
    $lines.Insert($insertion.Index, $insertion.Text)
  }
  $result = $lines -join $newline
  if ($hadTrailingNewline) { $result += $newline }
  return $result
}

$changed = [Collections.Generic.List[string]]::new()
foreach ($path in @($files | Sort-Object -Unique)) {
  if ($path -in $excluded) { continue }
  $before = [IO.File]::ReadAllText($path)
  $after = $before
  foreach ($replacement in $replacements) {
    $after = [regex]::Replace($after, $replacement.Pattern, $replacement.Replacement)
  }
  if ($path.StartsWith((Join-Path $repo ".github/workflows"), [StringComparison]::OrdinalIgnoreCase)) {
    $after = Add-MIRHiddenArtifactUploadOptIn -Text $after
  }
  if ($after -ceq $before) { continue }
  $changed.Add($path.Substring($repo.Length + 1).Replace("\", "/"))
  if ($Apply) {
    [IO.File]::WriteAllText($path, $after, [Text.UTF8Encoding]::new($false))
  }
}

[pscustomobject][ordered]@{
  schema = 1
  mode = if ($Apply) { "applied" } else { "preview" }
  changed = $changed.Count
  files = @($changed)
} | ConvertTo-Json -Depth 4
