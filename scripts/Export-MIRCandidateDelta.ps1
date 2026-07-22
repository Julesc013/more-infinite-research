param(
  [Parameter(Mandatory)][string]$BaselineZip,
  [Parameter(Mandatory)][string]$CandidateZip,
  [Parameter(Mandatory)][string]$OutputPath,
  [string]$BaselineCandidateId = "C5",
  [string]$CandidateId = "C6",
  [string[]]$AllowedChangeRoots = @("prototypes/mir/")
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")

function Get-MIRCandidateZipIndex {
  param([Parameter(Mandatory)][string]$Path)

  $resolved = (Resolve-Path -LiteralPath $Path).Path
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead($resolved)
  try {
    $rows = [ordered]@{}
    foreach ($entry in @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | Sort-Object FullName)) {
      $slash = $entry.FullName.IndexOf("/")
      $relative = if ($slash -ge 0) { $entry.FullName.Substring($slash + 1) } else { $entry.FullName }
      if ([string]::IsNullOrWhiteSpace($relative)) { continue }
      if ($rows.Contains($relative)) { throw "Duplicate normalized ZIP entry: $relative" }
      $identity = Get-MIRZipEntryContentIdentity -Entry $entry -RelativePath $relative
      $rows[$relative] = [ordered]@{
        path = $relative
        bytes = [long]$identity.Length
        content_sha256 = [string]$identity.Sha256
      }
    }
    return $rows
  } finally {
    $zip.Dispose()
  }
}

function Test-MIRAllowedDeltaPath {
  param([Parameter(Mandatory)][string]$Path)

  foreach ($root in $AllowedChangeRoots) {
    $normalized = ([string]$root).Replace("\", "/").TrimStart("/")
    if (-not $normalized.EndsWith("/")) { $normalized += "/" }
    if ($Path.StartsWith($normalized, [System.StringComparison]::Ordinal)) { return $true }
  }
  return $false
}

$baselinePath = (Resolve-Path -LiteralPath $BaselineZip).Path
$candidatePath = (Resolve-Path -LiteralPath $CandidateZip).Path
$baseline = Get-MIRCandidateZipIndex -Path $baselinePath
$candidate = Get-MIRCandidateZipIndex -Path $candidatePath
$paths = @($baseline.Keys + $candidate.Keys | Sort-Object -Unique)
$changes = @()
$unchanged = 0
$unexpected = @()
foreach ($path in $paths) {
  $before = if ($baseline.Contains($path)) { $baseline[$path] } else { $null }
  $after = if ($candidate.Contains($path)) { $candidate[$path] } else { $null }
  $kind = if ($null -eq $before) {
    "added"
  } elseif ($null -eq $after) {
    "removed"
  } elseif ([string]$before.content_sha256 -ne [string]$after.content_sha256 -or [long]$before.bytes -ne [long]$after.bytes) {
    "changed"
  } else {
    "unchanged"
  }
  if ($kind -eq "unchanged") {
    $unchanged++
    continue
  }
  $allowed = $kind -ne "removed" -and (Test-MIRAllowedDeltaPath -Path $path)
  $row = [ordered]@{ path=$path; change=$kind; allowed=$allowed; baseline=$before; candidate=$after }
  $changes += $row
  if (-not $allowed) { $unexpected += $row }
}

$baselineItem = Get-Item -LiteralPath $baselinePath
$candidateItem = Get-Item -LiteralPath $candidatePath
$result = [ordered]@{
  schema = 1
  record_type = "MIRCandidateArchiveDelta"
  status = if ($unexpected.Count -eq 0) { "PASS" } else { "REVIEW_REQUIRED" }
  baseline = [ordered]@{
    candidate_id = $BaselineCandidateId
    archive_bytes = [long]$baselineItem.Length
    archive_entries = [int]$baseline.Count
    archive_sha256 = Get-MIRFileSha256 -Path $baselinePath
    candidate_content_sha256 = Get-MIRZipContentFingerprint -Path $baselinePath
  }
  candidate = [ordered]@{
    candidate_id = $CandidateId
    archive_bytes = [long]$candidateItem.Length
    archive_entries = [int]$candidate.Count
    archive_sha256 = Get-MIRFileSha256 -Path $candidatePath
    candidate_content_sha256 = Get-MIRZipContentFingerprint -Path $candidatePath
  }
  policy = [ordered]@{
    allowed_change_roots = @($AllowedChangeRoots | ForEach-Object { ([string]$_).Replace("\", "/") })
    removals_allowed = $false
    unchanged_entries_omitted = $true
  }
  summary = [ordered]@{
    added = [int]@($changes | Where-Object change -eq "added").Count
    changed = [int]@($changes | Where-Object change -eq "changed").Count
    removed = [int]@($changes | Where-Object change -eq "removed").Count
    unchanged = [int]$unchanged
    unexpected = [int]$unexpected.Count
  }
  changes = @($changes)
}

$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host "[ok] wrote $($result.status) $BaselineCandidateId-to-$CandidateId archive delta $OutputPath changes=$($changes.Count) unexpected=$($unexpected.Count)"
if ($unexpected.Count -gt 0) {
  throw "Candidate delta contains removed or out-of-scope entries: $(@($unexpected.path) -join ', ')"
}
