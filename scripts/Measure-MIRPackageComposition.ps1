param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$ArchivePath,
  [string]$BaselinePath,
  [string]$OutputPath,
  [int]$TopEntryCount = 20,
  [double]$GrowthReviewPercent = 20.0,
  [double]$RootGrowthReviewPercent = 30.0,
  [string]$Explanation,
  [switch]$RequireReviewedExplanation
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
  $ArchivePath = Join-Path $repo "dist\$($info.name)_$($info.version).zip"
} elseif (-not [System.IO.Path]::IsPathRooted($ArchivePath)) {
  $ArchivePath = Join-Path $repo $ArchivePath
}
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
  $BaselinePath = Join-Path $repo "dist\$($info.name)_3.1.9.zip"
} elseif (-not [System.IO.Path]::IsPathRooted($BaselinePath)) {
  $BaselinePath = Join-Path $repo $BaselinePath
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $repo ".mir\evidence\$($info.version)-package-composition.json"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath = Join-Path $repo $OutputPath
}

$ArchivePath = (Resolve-Path -LiteralPath $ArchivePath).Path
if (-not [string]::IsNullOrWhiteSpace($BaselinePath) -and (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
  $BaselinePath = (Resolve-Path -LiteralPath $BaselinePath).Path
} else {
  $BaselinePath = $null
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-MIRSha256Hex {
  param([Parameter(Mandatory = $true)][System.IO.Stream]$Stream)

  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($algorithm.ComputeHash($Stream))).Replace("-", "")
  } finally {
    $algorithm.Dispose()
  }
}

function Get-MIRPackageCategory {
  param([Parameter(Mandatory = $true)][string]$RelativePath)

  $path = $RelativePath.Replace("\", "/")
  if ($path.StartsWith("locale/", [StringComparison]::OrdinalIgnoreCase)) { return "locale" }
  if ($path -eq "control.lua" -or $path.StartsWith("prototypes/mir/runtime/", [StringComparison]::OrdinalIgnoreCase)) { return "runtime" }
  if ($path.StartsWith("migrations/", [StringComparison]::OrdinalIgnoreCase)) { return "migrations" }
  if ($path -eq "thumbnail.png" -or $path.StartsWith("graphics/", [StringComparison]::OrdinalIgnoreCase)) { return "assets" }
  if (@("README.md", "LICENSE", "changelog.txt", "info.json") -contains $path) { return "shell-documentation" }
  if ($path.StartsWith("prototypes/", [StringComparison]::OrdinalIgnoreCase) -or
      $path -match '^(data|settings)(-updates|-final-fixes)?\.lua$') { return "prototypes/compiler" }
  return "unclassified"
}

function Get-MIRZipInventory {
  param([Parameter(Mandatory = $true)][string]$Path)

  $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $fileEntries = @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })
    $firstSegments = @($fileEntries | ForEach-Object {
      $normalized = $_.FullName.Replace("\", "/")
      $separator = $normalized.IndexOf("/")
      if ($separator -ge 0) { $normalized.Substring(0, $separator) } else { "" }
    } | Sort-Object -Unique)
    $commonRoot = if ($firstSegments.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($firstSegments[0])) { $firstSegments[0] + "/" } else { "" }

    $entries = @($fileEntries | ForEach-Object {
      $fullName = $_.FullName.Replace("\", "/")
      $relative = if ($commonRoot -and $fullName.StartsWith($commonRoot, [StringComparison]::Ordinal)) {
        $fullName.Substring($commonRoot.Length)
      } else {
        $fullName
      }
      $stream = $_.Open()
      try {
        $entrySha256 = Get-MIRSha256Hex -Stream $stream
      } finally {
        $stream.Dispose()
      }
      [pscustomobject][ordered]@{
        path = $relative
        category = Get-MIRPackageCategory -RelativePath $relative
        uncompressed_bytes = [long]$_.Length
        compressed_bytes = [long]$_.CompressedLength
        sha256 = $entrySha256
      }
    } | Sort-Object path)
  } finally {
    $zip.Dispose()
  }

  $archiveFile = Get-Item -LiteralPath $Path
  [pscustomobject][ordered]@{
    path = $archiveFile.FullName
    bytes = [long]$archiveFile.Length
    sha256 = (Get-FileHash -LiteralPath $archiveFile.FullName -Algorithm SHA256).Hash
    entry_count = $entries.Count
    entries = $entries
  }
}

function Get-MIRRootSummary {
  param([Parameter(Mandatory = $true)][object[]]$Entries)

  return @($Entries | Group-Object category | Sort-Object Name | ForEach-Object {
    [pscustomobject][ordered]@{
      root = $_.Name
      entry_count = $_.Count
      uncompressed_bytes = [long](($_.Group | Measure-Object uncompressed_bytes -Sum).Sum)
      compressed_bytes = [long](($_.Group | Measure-Object compressed_bytes -Sum).Sum)
    }
  })
}

$current = Get-MIRZipInventory -Path $ArchivePath
$baseline = if ($BaselinePath) { Get-MIRZipInventory -Path $BaselinePath } else { $null }
$roots = @(Get-MIRRootSummary -Entries $current.entries)
$baselineRoots = if ($baseline) { @(Get-MIRRootSummary -Entries $baseline.entries) } else { @() }

$currentByPath = @{}
foreach ($entry in $current.entries) { $currentByPath[$entry.path] = $entry }
$baselineByPath = @{}
if ($baseline) {
  foreach ($entry in $baseline.entries) { $baselineByPath[$entry.path] = $entry }
}

$added = @($current.entries | Where-Object { -not $baselineByPath.ContainsKey($_.path) } | ForEach-Object { $_.path })
$removed = if ($baseline) { @($baseline.entries | Where-Object { -not $currentByPath.ContainsKey($_.path) } | ForEach-Object { $_.path }) } else { @() }
$changed = if ($baseline) {
  @($current.entries | Where-Object {
    $baselineByPath.ContainsKey($_.path) -and $baselineByPath[$_.path].sha256 -ne $_.sha256
  } | ForEach-Object {
    $prior = $baselineByPath[$_.path]
    [pscustomobject][ordered]@{
      path = $_.path
      uncompressed_byte_delta = [long]($_.uncompressed_bytes - $prior.uncompressed_bytes)
      compressed_byte_delta = [long]($_.compressed_bytes - $prior.compressed_bytes)
    }
  })
} else { @() }

$triggers = [System.Collections.Generic.List[object]]::new()
if ($baseline -and $baseline.bytes -gt 0) {
  $growthPercent = (($current.bytes - $baseline.bytes) / [double]$baseline.bytes) * 100.0
  if ($growthPercent -gt $GrowthReviewPercent) {
    $triggers.Add([pscustomobject][ordered]@{
      kind = "total-growth"
      actual_percent = [math]::Round($growthPercent, 3)
      threshold_percent = $GrowthReviewPercent
    })
  }

  $baselineRootsByName = @{}
  foreach ($root in $baselineRoots) { $baselineRootsByName[$root.root] = $root }
  foreach ($root in $roots) {
    if ($baselineRootsByName.ContainsKey($root.root) -and $baselineRootsByName[$root.root].compressed_bytes -gt 0) {
      $rootGrowth = (($root.compressed_bytes - $baselineRootsByName[$root.root].compressed_bytes) / [double]$baselineRootsByName[$root.root].compressed_bytes) * 100.0
      if ($rootGrowth -gt $RootGrowthReviewPercent) {
        $triggers.Add([pscustomobject][ordered]@{
          kind = "root-growth"
          root = $root.root
          actual_percent = [math]::Round($rootGrowth, 3)
          threshold_percent = $RootGrowthReviewPercent
        })
      }
    } elseif ($root.compressed_bytes -gt 0) {
      $triggers.Add([pscustomobject][ordered]@{ kind = "new-root"; root = $root.root })
    }
  }
}

$unclassified = @($current.entries | Where-Object { $_.category -eq "unclassified" } | ForEach-Object { $_.path })
if ($unclassified.Count -gt 0) {
  $triggers.Add([pscustomobject][ordered]@{ kind = "unclassified-path"; paths = $unclassified })
}
$forbiddenNames = @(".mir", ".codex", ".github", "docs", "fixtures", "scripts", "tests", "tools", "build", "dist")
$forbidden = @($current.entries | Where-Object {
  $first = ($_.path.Replace("\", "/") -split "/", 2)[0]
  $forbiddenNames -contains $first -or @("AGENTS.md", "CONTRIBUTING.md", "todo.md") -contains $_.path
} | ForEach-Object { $_.path })
if ($forbidden.Count -gt 0) {
  $triggers.Add([pscustomobject][ordered]@{ kind = "repository-only-path"; paths = $forbidden })
}

$hasExplanation = -not [string]::IsNullOrWhiteSpace($Explanation)
$reviewRequired = $triggers.Count -gt 0 -and -not $hasExplanation
if ($RequireReviewedExplanation -and $reviewRequired) {
  throw "Package composition review requires an explanation for: $(@($triggers | ForEach-Object { $_.kind }) -join ', ')."
}

$topEntries = @($current.entries | Sort-Object @{ Expression = "compressed_bytes"; Descending = $true }, path | Select-Object -First $TopEntryCount | ForEach-Object {
  [pscustomobject][ordered]@{
    path = $_.path
    category = $_.category
    uncompressed_bytes = $_.uncompressed_bytes
    compressed_bytes = $_.compressed_bytes
  }
})

$report = [pscustomobject][ordered]@{
  schema = 1
  generated_at_utc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  archive = [pscustomobject][ordered]@{
    path = $current.path
    bytes = $current.bytes
    sha256 = $current.sha256
    entry_count = $current.entry_count
  }
  roots = $roots
  top_entries = $topEntries
  delta = [pscustomobject][ordered]@{
    baseline = if ($baseline) {
      [pscustomobject][ordered]@{
        path = $baseline.path
        bytes = $baseline.bytes
        sha256 = $baseline.sha256
        entry_count = $baseline.entry_count
      }
    } else { $null }
    added = $added
    removed = $removed
    changed = $changed
    compressed_byte_delta = if ($baseline) { [long]($current.bytes - $baseline.bytes) } else { $null }
  }
  review = [pscustomobject][ordered]@{
    required = $reviewRequired
    reviewed = ($triggers.Count -eq 0 -or $hasExplanation)
    explanation = if ($hasExplanation) { $Explanation } else { $null }
    triggers = @($triggers)
  }
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
  New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}
$json = $report | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($OutputPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))

$report
