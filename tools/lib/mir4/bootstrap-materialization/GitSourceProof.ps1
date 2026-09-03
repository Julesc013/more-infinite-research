function Get-MIR4GitTree {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Commit
  )

  $tree = @(& git -C $RepoRoot rev-parse "$Commit^{tree}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or $tree.Count -ne 1 -or [string]::IsNullOrWhiteSpace($tree[0])) {
    throw "Unable to resolve source tree for $Commit."
  }
  return ([string]$tree[0]).Trim()
}

function Write-MIR4DeterministicRawTreeArchive {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$EntryRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ContainmentRoot
  )

  Add-Type -AssemblyName System.IO.Compression
  $source = (Resolve-Path -LiteralPath $SourceRoot).Path
  Assert-MIR4SourceTreeSafe -SourceRoot $source
  if ($EntryRoot -notmatch '^[a-z0-9][a-z0-9._-]*$') { throw "Unsafe archive entry root: $EntryRoot" }
  $files = [Collections.Generic.List[string]]::new()
  $sourcePathMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($item in @(Get-ChildItem -LiteralPath $source -Recurse -File -Force)) {
    $relative = [IO.Path]::GetRelativePath($source, $item.FullName).Replace('\', '/')
    Add-MIR4PortableArchivePath -PathMap $sourcePathMap -Path $relative -IsDirectory $false
    $files.Add($relative)
  }
  $files.Sort([StringComparer]::Ordinal)
  if ($files.Count -eq 0) { throw "The MIR 4 capsule staging tree is empty." }
  Assert-MIR4PortableArchivePath -Path $EntryRoot

  $output = Assert-MIR4DescendantPath -Root $ContainmentRoot -Path $OutputPath
  $null = Assert-MIR4NoReparseAncestors -Root $ContainmentRoot -Path $output
  $parent = Split-Path -Parent $output
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $temp = "$output.new"
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
  $stream = [IO.File]::Open($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
  $timestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
  try {
    foreach ($relative in $files) {
      $entry = $archive.CreateEntry("$EntryRoot/$relative", [IO.Compression.CompressionLevel]::Optimal)
      $entry.LastWriteTime = $timestamp
      $entry.ExternalAttributes = 0
      $input = [IO.File]::OpenRead((Join-Path $source $relative))
      $destination = $entry.Open()
      try { $input.CopyTo($destination) } finally { $destination.Dispose(); $input.Dispose() }
    }
  } finally {
    $archive.Dispose()
    $stream.Dispose()
  }
  if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
  Move-Item -LiteralPath $temp -Destination $output
}

function Invoke-MIR4GitCatFileToPath {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('blob', 'commit', 'tree')][string]$Type,
    [Parameter(Mandatory)][string]$ObjectId,
    [Parameter(Mandatory)][string]$OutputPath
  )

  $parent = Split-Path -Parent $OutputPath
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $gitCommand = @(Get-Command git -CommandType Application -ErrorAction Stop | Where-Object { Test-Path -LiteralPath $_.Source -PathType Leaf } | Select-Object -First 1)
  if ($gitCommand.Count -ne 1) { throw 'Unable to resolve one executable Git command for capsule object capture.' }
  $processInfo = [Diagnostics.ProcessStartInfo]::new()
  $processInfo.FileName = [string]$gitCommand[0].Source
  $processInfo.UseShellExecute = $false
  $processInfo.CreateNoWindow = $true
  $processInfo.RedirectStandardOutput = $true
  $processInfo.RedirectStandardError = $true
  foreach ($argument in @('-C', $RepoRoot, 'cat-file', $Type, $ObjectId)) { $null = $processInfo.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $processInfo
  if (-not $process.Start()) { throw "Unable to start git cat-file for $ObjectId." }
  $output = [IO.File]::Open($OutputPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $process.StandardOutput.BaseStream.CopyTo($output) } finally { $output.Dispose() }
  $errorText = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  $exitCode = $process.ExitCode
  $process.Dispose()
  if ($exitCode -ne 0) { throw "git cat-file failed for $ObjectId`: $errorText" }
}

function Read-MIR4GitTreeObject {
  param([Parameter(Mandatory)][byte[]]$Bytes)

  $entries = [Collections.Generic.List[object]]::new()
  $offset = 0
  $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
  while ($offset -lt $Bytes.Length) {
    $modeStart = $offset
    while ($offset -lt $Bytes.Length -and $Bytes[$offset] -ne 0x20) { $offset++ }
    if ($offset -ge $Bytes.Length) { throw 'Malformed Git tree object mode.' }
    $mode = [Text.Encoding]::ASCII.GetString($Bytes, $modeStart, $offset - $modeStart)
    $offset++
    $nameStart = $offset
    while ($offset -lt $Bytes.Length -and $Bytes[$offset] -ne 0) { $offset++ }
    if ($offset -ge $Bytes.Length) { throw 'Malformed Git tree object name.' }
    $name = $strictUtf8.GetString($Bytes, $nameStart, $offset - $nameStart)
    $offset++
    if ($offset + 20 -gt $Bytes.Length) { throw 'Malformed Git tree object identity.' }
    $objectBytes = [byte[]]::new(20)
    [Array]::Copy($Bytes, $offset, $objectBytes, 0, 20)
    $offset += 20
    $entries.Add([pscustomobject][ordered]@{
      mode = $mode
      name = $name
      object_id = ([BitConverter]::ToString($objectBytes)).Replace('-', '').ToLowerInvariant()
    })
  }
  return @($entries)
}

function Assert-MIR4GitSourceProof {
  param(
    [Parameter(Mandatory)][string]$CapsuleRoot,
    [Parameter(Mandatory)]$Proof
  )

  if ([string]$Proof.kind -cne 'MIR4BootstrapGitSourceProofV1') { throw 'Unexpected MIR 4 Git source proof kind.' }
  if (-not (Test-MIR4BootstrapRecordHash -Record $Proof)) { throw 'MIR 4 Git source proof self-hash mismatch.' }
  $commitPath = Join-Path $CapsuleRoot ([string]$Proof.commit.payload_path)
  $commitBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $commitPath).Path)
  if ((Get-MIR4GitObjectSha1 -Type commit -Bytes $commitBytes) -cne [string]$Proof.commit.sha1 -or
      (Get-MIR4Sha256Bytes -Bytes $commitBytes) -cne [string]$Proof.commit.sha256) {
    throw 'MIR 4 capsule Git commit object identity mismatch.'
  }
  $commitText = [Text.UTF8Encoding]::new($false, $true).GetString($commitBytes)
  $treeMatches = [Text.RegularExpressions.Regex]::Matches($commitText, '(?m)^tree ([a-f0-9]{40})$')
  if ($treeMatches.Count -ne 1 -or [string]$treeMatches[0].Groups[1].Value -cne [string]$Proof.source_tree) {
    throw 'MIR 4 capsule Git commit does not bind the governed source tree.'
  }

  $treeMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($treeRow in @($Proof.tree_objects)) {
    $treePath = Join-Path $CapsuleRoot ([string]$treeRow.payload_path)
    $treeBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $treePath).Path)
    if ((Get-MIR4GitObjectSha1 -Type tree -Bytes $treeBytes) -cne [string]$treeRow.sha1 -or
        (Get-MIR4Sha256Bytes -Bytes $treeBytes) -cne [string]$treeRow.sha256) {
      throw "MIR 4 capsule Git tree object identity mismatch: $($treeRow.sha1)"
    }
    $treeMap.Add([string]$treeRow.sha1, @(Read-MIR4GitTreeObject -Bytes $treeBytes))
  }
  if (-not $treeMap.ContainsKey([string]$Proof.source_tree)) { throw 'MIR 4 capsule omits its source root tree object.' }

  $observedFileList = [Collections.Generic.List[string]]::new()
  foreach ($relative in @(Get-MIRPackageSourceFiles -RepoRoot $CapsuleRoot)) { $observedFileList.Add([string]$relative) }
  $observedFileList.Sort([StringComparer]::Ordinal)
  $observedFiles = @($observedFileList)
  $expectedFiles = @($Proof.package_files.path)
  if (($observedFiles -join '|') -cne ($expectedFiles -join '|')) { throw 'MIR 4 capsule package-source membership differs from its Git proof.' }
  foreach ($fileRow in @($Proof.package_files)) {
    $relative = [string]$fileRow.path
    $segments = @($relative -split '/')
    $treeId = [string]$Proof.source_tree
    for ($index = 0; $index -lt $segments.Count; $index++) {
      if (-not $treeMap.ContainsKey($treeId)) { throw "MIR 4 capsule is missing a Git tree proof for $relative." }
      $matches = @($treeMap[$treeId] | Where-Object { [string]$_.name -ceq [string]$segments[$index] })
      if ($matches.Count -ne 1) { throw "MIR 4 capsule Git tree does not contain exactly one $relative path segment." }
      $entry = $matches[0]
      if ($index -lt $segments.Count - 1) {
        if ([string]$entry.mode -cne '40000') { throw "MIR 4 capsule Git path is not a tree: $relative" }
        $treeId = [string]$entry.object_id
      } else {
        if ([string]$entry.mode -cne [string]$fileRow.mode -or [string]$entry.object_id -cne [string]$fileRow.blob_sha1) {
          throw "MIR 4 capsule Git blob binding differs for $relative."
        }
      }
    }
    $filePath = Join-Path $CapsuleRoot $relative
    $identity = Get-MIR4RawFileIdentity -Path $filePath
    if ((Get-MIR4GitBlobSha1File -Path $filePath) -cne [string]$fileRow.blob_sha1 -or
        [string]$identity.sha256 -cne [string]$fileRow.sha256 -or [long]$identity.bytes -ne [long]$fileRow.bytes) {
      throw "MIR 4 capsule package source differs from its Git blob proof: $relative"
    }
  }
  return $true
}

function New-MIR4BootstrapToolchainLock {
  param([Parameter(Mandatory)][string]$PwshPath)

  $resolvedPwsh = (Resolve-Path -LiteralPath $PwshPath).Path
  $toolchainRoot = Split-Path -Parent $resolvedPwsh
  if (((Get-Item -LiteralPath $toolchainRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'The bound PowerShell toolchain root cannot be a reparse point.'
  }
  $fileMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  $caseMap = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
  foreach ($item in @(Get-ChildItem -LiteralPath $toolchainRoot -Recurse -Force)) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "The bound PowerShell toolchain contains a reparse point: $($item.FullName)" }
    if ($item.PSIsContainer) { continue }
    $relative = [IO.Path]::GetRelativePath($toolchainRoot, $item.FullName).Replace('\', '/')
    Assert-MIR4PortableArchivePath -Path $relative
    $caseKey = $relative.ToLowerInvariant()
    if ($caseMap.ContainsKey($caseKey)) { throw "Case-colliding bound PowerShell toolchain paths: $($caseMap[$caseKey]) and $relative" }
    $caseMap.Add($caseKey, $relative)
    $fileMap.Add($relative, $item)
  }
  if (-not $fileMap.ContainsKey('pwsh.exe')) { throw 'The bound PowerShell toolchain omits pwsh.exe.' }
  $orderedPaths = [Collections.Generic.List[string]]::new()
  foreach ($relative in $fileMap.Keys) { $orderedPaths.Add($relative) }
  $orderedPaths.Sort([StringComparer]::Ordinal)
  $files = @()
  $contentFields = [ordered]@{}
  [long]$totalBytes = 0
  foreach ($relative in $orderedPaths) {
    $identity = Get-MIR4RawFileIdentity -Path $fileMap[$relative].FullName
    $files += [pscustomobject][ordered]@{ path = $relative; bytes = [long]$identity.bytes; sha256 = [string]$identity.sha256 }
    $contentFields[$relative] = "$([long]$identity.bytes)|$([string]$identity.sha256)"
    $totalBytes += [long]$identity.bytes
  }
  $contentRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.toolchain-content.v1' -Fields $contentFields
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4BootstrapToolchainLockV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    powershell_version = [string]$PSVersionTable.PSVersion
    dotnet_runtime_version = [string][Environment]::Version
    os_platform = [string][Environment]::OSVersion.Platform
    os_version = [string][Environment]::OSVersion.Version
    process_architecture = [string][Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
    executable = 'pwsh.exe'
    execution_culture = 'InvariantCulture'
    file_count = [int]$files.Count
    total_bytes = $totalBytes
    files = $files
    content_root_sha256 = $contentRoot
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function New-MIR4GitSourceProof {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$ExpectedTree,
    [Parameter(Mandatory)][string]$CapsuleRoot
  )

  $gitRoot = Join-Path $CapsuleRoot '.mir/capsule/git'
  New-Item -ItemType Directory -Force -Path (Join-Path $gitRoot 'trees') | Out-Null
  $commitPayload = Join-Path $gitRoot 'commit.raw'
  Invoke-MIR4GitCatFileToPath -RepoRoot $RepoRoot -Type commit -ObjectId $Commit -OutputPath $commitPayload
  $commitBytes = [IO.File]::ReadAllBytes($commitPayload)
  if ((Get-MIR4GitObjectSha1 -Type commit -Bytes $commitBytes) -cne $Commit) { throw 'Captured Git commit payload does not reproduce its object identity.' }

  $roots = @(Get-MIRPackageSourceRoots)
  $treeLines = @(& git -C $RepoRoot ls-tree -r -t $Commit -- @roots 2>$null)
  if ($LASTEXITCODE -ne 0) { throw "Unable to capture package Git tree proof for $Commit." }
  $treeIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $null = $treeIds.Add($ExpectedTree)
  $packageFileMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($line in $treeLines) {
    if ([string]$line -notmatch "^([0-9]{6}) (blob|tree) ([a-f0-9]{40})`t([A-Za-z0-9._/-]+)$") {
      throw "Unsafe or malformed Git tree proof row: $line"
    }
    $mode = [string]$Matches[1]
    $type = [string]$Matches[2]
    $objectId = [string]$Matches[3]
    $relative = [string]$Matches[4]
    if ($type -eq 'tree') {
      $null = $treeIds.Add($objectId)
      continue
    }
    if ($mode -notin @('100644', '100755')) { throw "MIR 4 package source contains a non-regular Git mode: $mode $relative" }
    $path = Join-Path $CapsuleRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Capsule staging omits package source path $relative." }
    $identity = Get-MIR4RawFileIdentity -Path $path
    if ((Get-MIR4GitBlobSha1File -Path $path) -cne $objectId) { throw "Capsule staging differs from Git blob $relative." }
    $packageFileMap.Add($relative, [pscustomobject][ordered]@{
      path = $relative
      mode = $mode
      blob_sha1 = $objectId
      bytes = $identity.bytes
      sha256 = $identity.sha256
    })
  }
  $packagePathList = [Collections.Generic.List[string]]::new()
  foreach ($relative in $packageFileMap.Keys) { $packagePathList.Add($relative) }
  $packagePathList.Sort([StringComparer]::Ordinal)
  $packageFiles = @($packagePathList | ForEach-Object { $packageFileMap[[string]$_] })
  $sourceFileList = [Collections.Generic.List[string]]::new()
  foreach ($relative in @(Get-MIRPackageSourceFiles -RepoRoot $CapsuleRoot)) { $sourceFileList.Add([string]$relative) }
  $sourceFileList.Sort([StringComparer]::Ordinal)
  $sourceFiles = @($sourceFileList)
  if (($sourceFiles -join '|') -cne (@($packageFiles.path) -join '|')) { throw 'Git package tree proof is not total over package source.' }

  $treeObjects = @()
  $treeIdList = [Collections.Generic.List[string]]::new()
  foreach ($treeId in $treeIds) { $treeIdList.Add($treeId) }
  $treeIdList.Sort([StringComparer]::Ordinal)
  foreach ($treeId in $treeIdList) {
    $relativePayload = ".mir/capsule/git/trees/$treeId.tree"
    $payload = Join-Path $CapsuleRoot $relativePayload
    Invoke-MIR4GitCatFileToPath -RepoRoot $RepoRoot -Type tree -ObjectId $treeId -OutputPath $payload
    $bytes = [IO.File]::ReadAllBytes($payload)
    if ((Get-MIR4GitObjectSha1 -Type tree -Bytes $bytes) -cne $treeId) { throw "Captured Git tree payload does not reproduce $treeId." }
    $treeObjects += [pscustomobject][ordered]@{
      sha1 = $treeId
      payload_path = $relativePayload
      bytes = [long]$bytes.Length
      sha256 = Get-MIR4Sha256Bytes -Bytes $bytes
    }
  }
  $commitIdentity = Get-MIR4RawFileIdentity -Path $commitPayload
  $proof = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4BootstrapGitSourceProofV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    candidate_commit = $Commit
    source_tree = $ExpectedTree
    commit = [pscustomobject][ordered]@{
      sha1 = $Commit
      payload_path = '.mir/capsule/git/commit.raw'
      bytes = $commitIdentity.bytes
      sha256 = $commitIdentity.sha256
    }
    tree_objects = $treeObjects
    package_files = $packageFiles
    record_sha256 = ''
  }
  $proofPath = Join-Path $gitRoot 'source-identity.json'
  $null = Write-MIR4BootstrapRecord -Record $proof -Path $proofPath
  $null = Assert-MIR4GitSourceProof -CapsuleRoot $CapsuleRoot -Proof $proof
  return $proof
}
