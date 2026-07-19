param(
  [string]$Baseline = "dist\more-infinite-research_2.4.5.zip",
  [string]$Candidate = "dist\more-infinite-research_2.4.9.zip",
  [string]$OutputPath = "approved-delta\2.4.5-to-2.4.9.json",
  [Parameter(Mandatory)][string]$ExpectedSourceCommit
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Resolve-MIRDeltaPath([string]$Path) {
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  return [IO.Path]::GetFullPath((Join-Path $repo $Path))
}

function Get-MIRDeltaEntries([string]$Path) {
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $rows = [ordered]@{}
    foreach ($entry in @($archive.Entries | Where-Object { -not $_.FullName.EndsWith("/") } | Sort-Object FullName)) {
      $separator = $entry.FullName.IndexOf("/")
      if ($separator -lt 0) { throw "Package entry has no versioned root: $($entry.FullName)" }
      $relative = $entry.FullName.Substring($separator + 1)
      $stream = $entry.Open()
      $sha = [Security.Cryptography.SHA256]::Create()
      try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "") }
      finally { $sha.Dispose(); $stream.Dispose() }
      $rows[$relative] = [ordered]@{ bytes=[int64]$entry.Length; sha256=$hash }
    }
    return $rows
  } finally { $archive.Dispose() }
}

function Get-MIRDeltaInfo([string]$Path) {
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entry = @($archive.Entries | Where-Object { $_.FullName.EndsWith("/info.json") })[0]
    if ($null -eq $entry) { throw "Package lacks info.json: $Path" }
    $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8, $true)
    try { return ($reader.ReadToEnd() | ConvertFrom-Json) }
    finally { $reader.Dispose() }
  } finally { $archive.Dispose() }
}

$baselinePath = Resolve-MIRDeltaPath $Baseline
$candidatePath = Resolve-MIRDeltaPath $Candidate
foreach ($path in @($baselinePath, $candidatePath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Approved-delta package is absent: $path" }
}
$head = (& git -C $repo rev-parse HEAD).Trim()
if ($head -ne $ExpectedSourceCommit -or (Test-MIRPackageSourceGitDirty -RepoRoot $repo)) {
  throw "Approved-delta export requires the clean candidate package source at ExpectedSourceCommit."
}
$lock = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\backport-source-lock.json") | ConvertFrom-Json
$baselineInfo = Get-MIRDeltaInfo $baselinePath
$candidateInfo = Get-MIRDeltaInfo $candidatePath
if ([string]$baselineInfo.version -ne [string]$lock.baseline_version -or
    [string]$candidateInfo.version -ne [string]$lock.mir_version) {
  throw "Approved-delta package versions disagree with the backport source lock."
}
$baselineSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $baselinePath).Hash
if ($baselineSha -ne "7649824B72247AA38F05661422DFDEE7C729B21CC73A0A35D2455443B45D39F8") {
  throw "Approved-delta baseline is not the published MIR 2.4.5 archive."
}
$candidateContent = Get-MIRZipContentFingerprint -Path $candidatePath
if ($candidateContent -ne (Get-MIRPackageSourceFingerprint -RepoRoot $repo)) {
  throw "Approved-delta candidate content differs from the package source authority."
}
$before = Get-MIRDeltaEntries $baselinePath
$after = Get-MIRDeltaEntries $candidatePath
$allPaths = @(@($before.Keys) + @($after.Keys) | Sort-Object -Unique)
$differences = @()
foreach ($relative in $allPaths) {
  $old = $before[$relative]
  $new = $after[$relative]
  if ($null -ne $old -and $null -ne $new -and [string]$old.sha256 -eq [string]$new.sha256) { continue }
  $reasonProperty = $lock.adapted_package_paths.PSObject.Properties[$relative]
  $reason = if ($null -ne $reasonProperty) { [string]$reasonProperty.Value } else { "" }
  $differences += [ordered]@{
    path=$relative
    change=if ($null -eq $old) { "added" } elseif ($null -eq $new) { "removed" } else { "changed" }
    before_sha256=if ($null -eq $old) { $null } else { [string]$old.sha256 }
    after_sha256=if ($null -eq $new) { $null } else { [string]$new.sha256 }
    reason=$reason
    intentional=(-not [string]::IsNullOrWhiteSpace($reason))
    migration_impact="No generated ID, setting ID, migration, or runtime namespace change is authorized by this package-path delta."
    required_evidence=@("exact archive hashes", "2.4.5-to-2.4.9 upgrade proof", "Factorio 2.0 full qualification")
  }
}
$declared = @($lock.adapted_package_paths.PSObject.Properties.Name | Sort-Object)
$actual = @($differences.path | Sort-Object)
if ((Compare-Object $declared $actual).Count -ne 0) {
  throw "Exact archive differences do not equal the declared 2.4.9 package boundary."
}
$unapproved = @($differences | Where-Object intentional -ne $true)
$output = [ordered]@{
  schema=2
  kind="mir-approved-package-delta"
  baseline=[ordered]@{
    version=[string]$baselineInfo.version
    archive_sha256=$baselineSha
    package_content_sha256=(Get-MIRZipContentFingerprint -Path $baselinePath)
    source_commit=[string]$lock.baseline_package_source_commit
  }
  current=[ordered]@{
    version=[string]$candidateInfo.version
    archive_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $candidatePath).Hash
    package_content_sha256=$candidateContent
    source_commit=$ExpectedSourceCommit
  }
  invariants=[ordered]@{
    settings_paths_unchanged=(@($differences.path | Where-Object { $_ -like "settings*" -or $_ -like "prototypes/mir/settings/*" }).Count -eq 0)
    migration_paths_unchanged=(@($differences.path | Where-Object { $_ -like "migrations/*" }).Count -eq 0)
    stream_paths_unchanged=(@($differences.path | Where-Object { $_ -like "prototypes/streams/*" }).Count -eq 0)
  }
  differences=$differences
  summary=[ordered]@{
    difference_count=$differences.Count
    intentional_count=@($differences | Where-Object intentional -eq $true).Count
    unapproved_count=$unapproved.Count
    status=if ($unapproved.Count -eq 0) { "approved" } else { "review-required" }
  }
  exporter=[ordered]@{
    generated_at=(Get-Date).ToUniversalTime().ToString("o")
    producer_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash
  }
}
$resolvedOutput = Resolve-MIRDeltaPath $OutputPath
$parent = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
[IO.File]::WriteAllText($resolvedOutput, (($output | ConvertTo-Json -Depth 40) + "`n"), [Text.UTF8Encoding]::new($false))
Write-Host "[ok] Exported exact MIR 2.4.5-to-2.4.9 approved package delta: $resolvedOutput"
