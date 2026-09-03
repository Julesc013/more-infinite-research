function Get-MIRGitStatusPaths {
  $lines = @(& git -C $repo status --porcelain)
  if ($LASTEXITCODE -ne 0) { throw "git status failed." }

  $paths = @()
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $pathText = $line.Substring(3)
    if ($pathText -match " -> ") {
      $paths += @($pathText -split " -> ")
    } else {
      $paths += $pathText
    }
  }

  return @($paths | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique)
}

function Test-MIRDocsOnlyReleasePath {
  param([Parameter(Mandatory)][string]$Path)

  $normalized = $Path.Replace("\", "/")
  return (
    $normalized -match "^docs/" -or
    $normalized -match "^dist/[^/]+\.zip$" -or
    $normalized -in @(
      "README.md",
      "changelog.txt",
      "CONTRIBUTING.md",
      "LICENSE",
      "todo.md"
    )
  )
}

function Assert-MIRDocsOnlyReleaseStatus {
  param([Parameter(Mandatory)][string]$Stage)

  $paths = @(Get-MIRGitStatusPaths)
  $bad = @($paths | Where-Object { -not (Test-MIRDocsOnlyReleasePath -Path $_) })
  if ($bad.Count -gt 0) {
    throw "Docs-only release check found non-doc/package changes during ${Stage}: $($bad -join ', '). Run the full release gate instead."
  }

  if ($paths.Count -eq 0) {
    Write-MIRInfo "$Stage git status: clean"
  } else {
    Write-MIRInfo "$Stage allowed changes: $($paths -join ', ')"
  }
}

function Invoke-MIRDocsOnlyReleaseCheck {
  Assert-MIRDocsOnlyReleaseStatus -Stage "before docs-only validation"

  Write-MIRStep "building release package"
  & (Join-Path $repo "tools/commands/package/Build-MIRPackage.ps1")
  if ($LASTEXITCODE -ne 0) { throw "Build-MIRPackage.ps1 failed." }

  Write-MIRStep "running static/package validation"
  & (Join-Path $scriptRoot "Invoke-MIRValidation.ps1") -StaticOnly
  if ($LASTEXITCODE -ne 0) { throw "Invoke-MIRValidation.ps1 -StaticOnly failed." }

  Write-MIRStep "checking whitespace"
  & git -C $repo diff --check
  if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }

  Assert-MIRDocsOnlyReleaseStatus -Stage "after docs-only validation"
  Write-MIRSuccess "docs-only release validation passed"
}
