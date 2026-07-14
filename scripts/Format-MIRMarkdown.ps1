param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string[]]$Paths = @(),
  [switch]$Check
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

function Test-MIRMarkdownStructuralLine {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Line)

  if ([string]::IsNullOrWhiteSpace($Line)) { return $true }
  if ($Line -match '^\s{0,3}(#{1,6}\s|```|~~~)') { return $true }
  if ($Line -match '^\s*(?:[-+*]|\d+[.)])\s+') { return $true }
  if ($Line -match '^\s*>') { return $true }
  if ($Line -match '^\s*\|') { return $true }
  if ($Line -match '\s\|\s') { return $true }
  if ($Line -match '^\s*\[[^\]]+\]:\s*\S') { return $true }
  if ($Line -match '^\s*!\[') { return $true }
  if ($Line -match '^\s*</?[A-Za-z][^>]*>\s*$') { return $true }
  if ($Line -match '^\s{4,}\S') { return $true }
  if ($Line -match '^\s*(?:=+|-+)\s*$') { return $true }
  if ($Line -match '^\s{0,3}(?:\*\s*){3,}$') { return $true }
  if ($Line -match '(?:\\|  )$') { return $true }
  return $false
}

function ConvertTo-MIRUnwrappedMarkdown {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

  $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
  $hadFinalNewline = $normalized.EndsWith("`n")
  $lines = [regex]::Split($normalized, "`n")
  if ($hadFinalNewline -and $lines.Count -gt 0 -and $lines[-1] -eq "") {
    $lines = @($lines[0..($lines.Count - 2)])
  }

  $output = [System.Collections.Generic.List[string]]::new()
  $inFrontmatter = $lines.Count -gt 0 -and $lines[0] -eq "---"
  $frontmatterClosed = -not $inFrontmatter
  $inFence = $false
  $fenceCharacter = ""
  $inHtmlComment = $false
  $index = 0

  while ($index -lt $lines.Count) {
    $line = $lines[$index]

    if (-not $frontmatterClosed) {
      $output.Add($line)
      if ($index -gt 0 -and $line -eq "---") { $frontmatterClosed = $true }
      $index++
      continue
    }

    if ($inHtmlComment) {
      $output.Add($line)
      if ($line -match '-->') { $inHtmlComment = $false }
      $index++
      continue
    }
    if ($line -match '^\s*<!--') {
      $output.Add($line)
      if ($line -notmatch '-->') { $inHtmlComment = $true }
      $index++
      continue
    }

    if ($line -match '^\s*(?<fence>```+|~~~+)') {
      $character = $matches.fence.Substring(0, 1)
      if (-not $inFence) {
        $inFence = $true
        $fenceCharacter = $character
      } elseif ($character -eq $fenceCharacter) {
        $inFence = $false
        $fenceCharacter = ""
      }
      $output.Add($line)
      $index++
      continue
    }
    if ($inFence) {
      $output.Add($line)
      $index++
      continue
    }

    if ([string]::IsNullOrWhiteSpace($line)) {
      $output.Add("")
      $index++
      continue
    }

    if ($line -match '^(?<prefix>\s*(?:[-+*]|\d+[.)])\s+)(?<body>.*)$') {
      $combined = $matches.prefix + $matches.body.TrimEnd()
      $next = $index + 1
      while ($next -lt $lines.Count) {
        $continuation = $lines[$next]
        if (Test-MIRMarkdownStructuralLine -Line $continuation) { break }
        $combined += " " + $continuation.Trim()
        $next++
      }
      $output.Add($combined)
      $index = $next
      continue
    }

    if (Test-MIRMarkdownStructuralLine -Line $line) {
      $output.Add($line)
      $index++
      continue
    }

    $indentMatch = [regex]::Match($line, '^\s*')
    $indent = $indentMatch.Value
    $combinedParagraph = $indent + $line.Trim()
    $next = $index + 1
    while ($next -lt $lines.Count) {
      $continuation = $lines[$next]
      if (Test-MIRMarkdownStructuralLine -Line $continuation) { break }
      $combinedParagraph += " " + $continuation.Trim()
      $next++
    }
    $output.Add($combinedParagraph)
    $index = $next
  }

  $result = $output -join "`n"
  if ($hadFinalNewline) { $result += "`n" }
  return $result
}

if ($Paths.Count -eq 0) {
  $trackedMarkdown = @(& git -C $repo ls-files -- "*.md")
  if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate tracked Markdown files." }
  $docsMarkdown = @(
    Get-ChildItem -LiteralPath (Join-Path $repo "docs") -Recurse -File -Filter "*.md" |
      ForEach-Object { [System.IO.Path]::GetRelativePath($repo, $_.FullName).Replace("\", "/") }
  )
  $Paths = @($trackedMarkdown + $docsMarkdown | Sort-Object -Unique)
}

$changed = [System.Collections.Generic.List[string]]::new()
foreach ($relative in @($Paths | Sort-Object -Unique)) {
  if ([System.IO.Path]::GetExtension($relative) -ne ".md") { continue }
  $fullPath = Join-Path $repo $relative
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "Markdown formatting target does not exist: $relative"
  }

  $source = [System.IO.File]::ReadAllText($fullPath)
  $formatted = ConvertTo-MIRUnwrappedMarkdown -Text $source
  $sourceNormalized = $source.Replace("`r`n", "`n").Replace("`r", "`n")
  if ($sourceNormalized -eq $formatted) { continue }

  $changed.Add($relative)
  if (-not $Check) {
    [System.IO.File]::WriteAllText($fullPath, $formatted, [System.Text.UTF8Encoding]::new($false))
  }
}

if ($Check -and $changed.Count -gt 0) {
  throw "Markdown prose is manually hard-wrapped. Run scripts/Format-MIRMarkdown.ps1. Files: $($changed -join ', ')"
}

if ($Check) {
  Write-Host "[ok] MIR Markdown prose uses renderer-managed word wrapping."
} else {
  Write-Host "[ok] MIR Markdown formatting updated $($changed.Count) file(s)."
}
