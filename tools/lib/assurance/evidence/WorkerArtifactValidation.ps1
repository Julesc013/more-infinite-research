function Test-MIRAssuranceCapsule {
  param(
    [Parameter(Mandatory)]$Capsule,
    [Parameter(Mandatory)]$Fingerprint,
    [Parameter(Mandatory)]$Context
  )
  if ([int]$Capsule.schema -ne $evidenceSchema) { return [ordered]@{valid=$false; reason="schema-mismatch"} }
  if ([string]$Capsule.conclusion -ne "passed" -or [string]$Capsule.status -ne "passed") { return [ordered]@{valid=$false; reason="not-passing"} }
  if ([string]$Capsule.test_id -ne [string]$Fingerprint.test_id) { return [ordered]@{valid=$false; reason="test-id-mismatch"} }
  if ([string]$Capsule.target -ne [string]$Fingerprint.target) { return [ordered]@{valid=$false; reason="target-mismatch"} }
  if ([string]$Capsule.input_key -ne [string]$Fingerprint.input_key) { return [ordered]@{valid=$false; reason="input-key-mismatch"} }
  if ([string]$Capsule.fingerprint_sha256 -ne [string]$Fingerprint.fingerprint_sha256) { return [ordered]@{valid=$false; reason="fingerprint-mismatch"} }
  if ([string]$Capsule.definition_sha256 -ne [string]$Fingerprint.definition_sha256) { return [ordered]@{valid=$false; reason="definition-mismatch"} }
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $Capsule.producer -Context $Context)) { return [ordered]@{valid=$false; reason="untrusted-producer"} }
  if ([int]$Capsule.exit_code -ne 0) { return [ordered]@{valid=$false; reason="nonzero-exit"} }
  if ($null -eq $Capsule.result -or [string]$Capsule.result.schema -ne "mir-test-result-v1" -or
      [string]$Capsule.result.status -ne "passed") {
    return [ordered]@{valid=$false; reason="missing-or-invalid-structured-result"}
  }
  $resultPath = Resolve-MIRAssurancePath -Path ([string]$Capsule.result.path)
  if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { return [ordered]@{valid=$false; reason="structured-result-missing"} }
  if ((Get-MIRAssuranceSha256 -Path $resultPath) -ne [string]$Capsule.result.sha256) {
    return [ordered]@{valid=$false; reason="structured-result-digest-mismatch"}
  }
  try { $structuredResult = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json }
  catch { return [ordered]@{valid=$false; reason="structured-result-invalid-json"} }
  if ([string]$structuredResult.schema -ne "mir-test-result-v1" -or
      [string]$structuredResult.test_id -ne [string]$Capsule.test_id -or
      [string]$structuredResult.status -ne "passed" -or
      [int]$structuredResult.exit_code -ne 0) {
    return [ordered]@{valid=$false; reason="structured-result-content-mismatch"}
  }
  if (@($Capsule.assertions).Count -eq 0 -or
      @($Capsule.assertions | Where-Object { [string]$_.status -ne "passed" }).Count -gt 0) {
    return [ordered]@{valid=$false; reason="assertion-outcomes-not-passing"}
  }
  if ((Get-MIRAssuranceJsonHash -Value @($Capsule.assertions)) -ne
      (Get-MIRAssuranceJsonHash -Value @($structuredResult.assertions))) {
    return [ordered]@{valid=$false; reason="structured-result-assertion-mismatch"}
  }
  if ((Get-MIRAssuranceJsonHash -Value @($Capsule.artifacts)) -ne
      (Get-MIRAssuranceJsonHash -Value @($structuredResult.artifacts))) {
    return [ordered]@{valid=$false; reason="structured-result-artifact-mismatch"}
  }
  foreach ($artifact in @($Capsule.artifacts)) {
    $artifactPath = Resolve-MIRAssurancePath -Path ([string]$artifact.path)
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { return [ordered]@{valid=$false; reason="artifact-missing"} }
    $item = Get-Item -LiteralPath $artifactPath
    if ($item.Length -ne [long]$artifact.bytes -or (Get-MIRAssuranceSha256 -Path $artifactPath) -ne [string]$artifact.sha256) {
      return [ordered]@{valid=$false; reason="artifact-digest-mismatch"}
    }
  }
  $expectedDigest = Get-MIRAssuranceCapsuleDigest -Capsule $Capsule
  if ([string]$Capsule.result_digest -ne $expectedDigest) { return [ordered]@{valid=$false; reason="result-digest-mismatch"} }
  return [ordered]@{valid=$true; reason="exact-trusted-pass"}
}

function Write-MIRAssuranceAtomicJson {
  param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
  [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 40) + "`n"), [Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Move-MIRAssuranceCorruptEvidence {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Reason)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  $quarantine = Join-Path (Split-Path -Parent $Path) "quarantine"
  New-Item -ItemType Directory -Force -Path $quarantine | Out-Null
  $name = "$(Get-Date -Format 'yyyyMMddTHHmmssfffffffZ')-$Reason-$([guid]::NewGuid().ToString('N')).json"
  Move-Item -LiteralPath $Path -Destination (Join-Path $quarantine $name)
}

function Read-MIRAssuranceEvidencePointer {
  param([Parameter(Mandatory)][string]$Path)
  try { $pointer = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json }
  catch {
    Move-MIRAssuranceCorruptEvidence -Path $Path -Reason "invalid-json"
    return $null
  }
  if ([int]$pointer.schema -ne 1 -or [string]::IsNullOrWhiteSpace([string]$pointer.capsule_path) -or
      [string]::IsNullOrWhiteSpace([string]$pointer.capsule_sha256)) {
    Move-MIRAssuranceCorruptEvidence -Path $Path -Reason "invalid-pointer"
    return $null
  }
  $capsulePath = Resolve-MIRAssurancePath -Path ([string]$pointer.capsule_path)
  if (-not (Test-Path -LiteralPath $capsulePath -PathType Leaf) -or
      (Get-MIRAssuranceSha256 -Path $capsulePath) -ne [string]$pointer.capsule_sha256) {
    Move-MIRAssuranceCorruptEvidence -Path $Path -Reason "broken-pointer"
    return $null
  }
  try { return Get-Content -Raw -LiteralPath $capsulePath | ConvertFrom-Json }
  catch {
    Move-MIRAssuranceCorruptEvidence -Path $Path -Reason "invalid-capsule"
    return $null
  }
}

function Get-MIRAssuranceWorkerCanonicalPath {
  param([Parameter(Mandatory)][string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path) -or $Path.IndexOf([char]0) -ge 0 -or
      [IO.Path]::IsPathRooted($Path) -or $Path -match '^[A-Za-z]:' -or $Path.StartsWith("\\")) {
    throw "Worker evidence path must be repository-relative: $Path"
  }
  $normalized = $Path.Replace("\", "/").Normalize([Text.NormalizationForm]::FormC)
  if ($normalized.StartsWith("/") -or $normalized -match '[<>:"|?*\x00-\x1F]') {
    throw "Worker evidence path contains unsafe Windows path syntax: $Path"
  }
  $segments = @($normalized.Split("/"))
  if ($segments.Count -eq 0 -or @($segments | Where-Object {
      $_ -in @("", ".", "..") -or $_.EndsWith(" ") -or $_.EndsWith(".") -or
      $_ -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$'
    }).Count -gt 0) {
    throw "Worker evidence path is not canonically representable on Windows: $Path"
  }
  return [pscustomobject][ordered]@{
    path=$normalized
    key=$normalized.ToUpperInvariant()
  }
}

function Get-MIRAssuranceWindowsAlternateDataStreams {
  param([Parameter(Mandatory)][string]$Path)

  if ($env:OS -ne "Windows_NT") { return @() }
  if (-not ("MIR.NativeStreams" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MIR {
  public static class NativeStreams {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct StreamData {
      public long StreamSize;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 296)] public string StreamName;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr FindFirstStreamW(string fileName, int infoLevel, out StreamData data, int flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] public static extern bool FindNextStreamW(IntPtr handle, out StreamData data);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] public static extern bool FindClose(IntPtr handle);
  }
}
'@
  }
  $fullPath = [IO.Path]::GetFullPath($Path)
  $nativePath = if ($fullPath.StartsWith("\\", [StringComparison]::Ordinal)) {
    "\\?\UNC\" + $fullPath.Substring(2)
  } else {
    "\\?\" + $fullPath
  }
  $data = New-Object MIR.NativeStreams+StreamData
  $handle = [MIR.NativeStreams]::FindFirstStreamW($nativePath, 0, [ref]$data, 0)
  $invalidHandle = [IntPtr](-1)
  if ($handle -eq $invalidHandle) {
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw [ComponentModel.Win32Exception]::new($errorCode, "Unable to enumerate alternate data streams for '$fullPath'.")
  }
  $streams = [Collections.Generic.List[string]]::new()
  try {
    do {
      if ([string]$data.StreamName -ne '::$DATA') { $streams.Add([string]$data.StreamName) }
      $hasNext = [MIR.NativeStreams]::FindNextStreamW($handle, [ref]$data)
    } while ($hasNext)
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($errorCode -notin @(18, 38)) {
      throw [ComponentModel.Win32Exception]::new($errorCode, "Unable to complete alternate data stream enumeration for '$fullPath'.")
    }
  } finally {
    [void][MIR.NativeStreams]::FindClose($handle)
  }
  return @($streams)
}

function Assert-MIRAssuranceWorkerArtifactTree {
  param(
    [Parameter(Mandatory)][string]$ArtifactRoot,
    [Parameter(Mandatory)]$Context
  )

  $limits = $Context.config.worker_import
  foreach ($field in @("max_entries_per_artifact", "max_expanded_bytes_per_artifact", "max_file_bytes")) {
    if ([long]$limits.$field -le 0) { throw "Worker-import limit '$field' must be positive." }
  }
  $resolvedRoot = [IO.Path]::GetFullPath($ArtifactRoot)
  $rootItem = Get-Item -LiteralPath $resolvedRoot -Force
  if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Worker artifact root is a symlink or reparse point: $resolvedRoot"
  }
  $directories = [Collections.Generic.Stack[string]]::new()
  $directories.Push($resolvedRoot)
  $canonicalPaths = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
  $entryCount = 0
  [long]$expandedBytes = 0
  while ($directories.Count -gt 0) {
    $directory = $directories.Pop()
    foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
      $entryCount++
      if ($entryCount -gt [int]$limits.max_entries_per_artifact) {
        throw "Worker artifact exceeds the entry-count limit: $resolvedRoot"
      }
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Worker artifact contains a symlink or reparse point: $($item.FullName)"
      }
      $relative = [IO.Path]::GetRelativePath($resolvedRoot, $item.FullName).Replace("\", "/")
      $canonical = Get-MIRAssuranceWorkerCanonicalPath -Path $relative
      if ($canonicalPaths.ContainsKey([string]$canonical.key)) {
        throw "Worker artifact contains a case-fold or Unicode-normalization path collision: $relative"
      }
      $canonicalPaths[[string]$canonical.key] = $relative
      if ($item.PSIsContainer) {
        $directories.Push($item.FullName)
      } elseif ($item -is [IO.FileInfo]) {
        if ($env:OS -eq "Windows_NT") {
          $alternateStreams = @(Get-MIRAssuranceWindowsAlternateDataStreams -Path $item.FullName)
          if ($alternateStreams.Count -gt 0) {
            throw "Worker artifact contains an NTFS alternate data stream: $relative"
          }
        }
        if ([long]$item.Length -gt [long]$limits.max_file_bytes) {
          throw "Worker artifact contains an oversized file: $relative"
        }
        $expandedBytes += [long]$item.Length
        if ($expandedBytes -gt [long]$limits.max_expanded_bytes_per_artifact) {
          throw "Worker artifact exceeds the expanded-byte limit: $resolvedRoot"
        }
      } else {
        throw "Worker artifact contains an unsupported filesystem entry: $relative"
      }
    }
  }
  return [pscustomobject][ordered]@{entries=$entryCount;expanded_bytes=$expandedBytes}
}

function Resolve-MIRAssuranceWorkerObjectPath {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$DestinationRoot,
    [Parameter(Mandatory)][string]$RepoRelativePath
  )

  $canonicalPath = Get-MIRAssuranceWorkerCanonicalPath -Path $RepoRelativePath
  $canonicalDestination = Get-MIRAssuranceWorkerCanonicalPath -Path ((Get-MIRAssuranceRepoRelativePath -Path $DestinationRoot).Replace("\", "/").TrimEnd("/"))
  $normalizedPath = [string]$canonicalPath.path
  $normalizedDestination = [string]$canonicalDestination.path + "/"
  if (-not $normalizedPath.StartsWith($normalizedDestination, [StringComparison]::Ordinal)) {
    throw "Worker evidence path escapes its planned fingerprint subtree: $RepoRelativePath"
  }
  $suffix = $normalizedPath.Substring($normalizedDestination.Length)
  if ([string]::IsNullOrWhiteSpace($suffix)) {
    throw "Worker evidence path is not a safe file path: $RepoRelativePath"
  }

  $resolvedSourceRoot = [IO.Path]::GetFullPath($SourceRoot).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
  $resolved = [IO.Path]::GetFullPath((Join-Path $SourceRoot ($suffix.Replace("/", [IO.Path]::DirectorySeparatorChar))))
  if (-not $resolved.StartsWith($resolvedSourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Worker evidence source path escapes its artifact directory: $RepoRelativePath"
  }
  $sourceItem = Get-Item -LiteralPath $resolved -Force -ErrorAction SilentlyContinue
  if ($null -ne $sourceItem -and ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Worker evidence source is a symlink or reparse point: $RepoRelativePath"
  }
  return $resolved
}
