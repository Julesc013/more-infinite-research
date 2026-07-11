param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$formatter = Join-Path $RepoRoot "scripts\Format-MIRMarkdown.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mir-markdown-format-" + [Guid]::NewGuid().ToString("N"))

try {
  $docs = Join-Path $testRoot "docs"
  New-Item -ItemType Directory -Path $docs -Force | Out-Null
  & git -C $testRoot init --quiet
  if ($LASTEXITCODE -ne 0) { throw "Unable to initialize Markdown formatter test repository." }

  $samplePath = Join-Path $docs "sample.md"
  $source = @'
---
title: "Sample"
---

This paragraph is
manually wrapped.

- This list item is
  manually wrapped.
  - Nested item remains separate.

> Quoted lines remain structural.
> They are not joined by the prose formatter.

| Column | Value |
| --- | --- |
| One | Two |

```text
code stays
on its lines
```

This line has an explicit break.  
This is a new line.
'@
  [System.IO.File]::WriteAllText($samplePath, $source + "`n", [System.Text.UTF8Encoding]::new($false))
  & git -C $testRoot add docs/sample.md
  if ($LASTEXITCODE -ne 0) { throw "Unable to stage Markdown formatter test fixture." }

  $failedAsExpected = $false
  try {
    & $formatter -RepoRoot $testRoot -Check
  } catch {
    $failedAsExpected = $_.Exception.Message -match "manually hard-wrapped"
  }
  if (-not $failedAsExpected) { throw "Markdown check accepted manually wrapped prose." }

  & $formatter -RepoRoot $testRoot
  & $formatter -RepoRoot $testRoot -Check
  $formatted = [System.IO.File]::ReadAllText($samplePath).Replace("`r`n", "`n")
  foreach ($required in @(
    "This paragraph is manually wrapped.",
    "- This list item is manually wrapped.",
    "  - Nested item remains separate.",
    "> Quoted lines remain structural.`n> They are not joined by the prose formatter.",
    "| Column | Value |`n| --- | --- |`n| One | Two |",
    ('```text' + "`ncode stays`non its lines`n" + '```'),
    "This line has an explicit break.  `nThis is a new line."
  )) {
    if (-not $formatted.Contains($required)) {
      throw "Markdown formatter did not preserve expected structure: $required"
    }
  }
} finally {
  if (Test-Path -LiteralPath $testRoot) {
    $resolved = [System.IO.Path]::GetFullPath($testRoot)
    $temp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($temp, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove unexpected Markdown test path: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}

Write-Host "[ok] MIR Markdown formatter regression tests passed."
