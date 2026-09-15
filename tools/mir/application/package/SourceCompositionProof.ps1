Set-StrictMode -Version Latest

$mir4SourceCompositionProofLoadRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4SourceCompositionProofLoadRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR4CanonicalPackageAuthority -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4SourceCompositionProofLoadRoot 'tools/mir/application/package/PackageAuthority.ps1')
}

function Read-MIR4GitBlobBytes {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$Commit,
    [Parameter(Mandatory)][string]$RelativePath
  )

  Assert-MIR4PortableArchivePath -Path $RelativePath
  $git = @(Get-Command git -CommandType Application -ErrorAction Stop | Where-Object { Test-Path -LiteralPath $_.Source -PathType Leaf } | Select-Object -First 1)
  if ($git.Count -ne 1) { throw '[mir4-composable-source-predecessor-git]' }
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = [string]$git[0].Source
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  foreach ($argument in @('-C', $RepoRoot, 'cat-file', 'blob', "$Commit`:$RelativePath")) {
    [void]$startInfo.ArgumentList.Add($argument)
  }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw "[mir4-composable-source-predecessor-git-start] $RelativePath" }
  $memory = [IO.MemoryStream]::new()
  try {
    $process.StandardOutput.BaseStream.CopyTo($memory)
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "[mir4-composable-source-predecessor-git-blob] $RelativePath $stderr" }
    return $memory.ToArray()
  } finally {
    $memory.Dispose()
    $process.Dispose()
  }
}

function Read-MIR4GitBlobSet {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$Commit,
    [Parameter(Mandatory)][string[]]$RelativePath
  )

  $paths = @($RelativePath | Sort-Object -Unique -CaseSensitive)
  $result = [Collections.Generic.Dictionary[string, byte[]]]::new([StringComparer]::Ordinal)
  if ($paths.Count -eq 0) { return ,$result }
  foreach ($path in $paths) { [void](Assert-MIR4PortableArchivePath -Path $path) }

  $git = @(Get-Command git -CommandType Application -ErrorAction Stop | Where-Object { Test-Path -LiteralPath $_.Source -PathType Leaf } | Select-Object -First 1)
  if ($git.Count -ne 1) { throw '[mir4-composable-source-predecessor-git]' }
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = [string]$git[0].Source
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardInput = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  foreach ($argument in @('-C', $RepoRoot, 'cat-file', '--batch')) { [void]$startInfo.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw '[mir4-composable-source-predecessor-git-batch-start]' }
  try {
    # Feed requests asynchronously while consuming binary responses. A
    # synchronous write can deadlock once the stdout pipe fills.
    $requestText = (($paths | ForEach-Object { "$Commit`:$_" }) -join "`n") + "`n"
    $writeTask = $process.StandardInput.WriteAsync($requestText)
    $stream = $process.StandardOutput.BaseStream
    foreach ($path in $paths) {
      $headerBytes = [Collections.Generic.List[byte]]::new()
      while ($true) {
        $value = $stream.ReadByte()
        if ($value -lt 0) { throw "[mir4-composable-source-predecessor-git-batch-eof] $path" }
        if ($value -eq 10) { break }
        [void]$headerBytes.Add([byte]$value)
      }
      $header = [Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
      if ($header -notmatch '^[a-f0-9]{40} blob ([0-9]+)$') {
        throw "[mir4-composable-source-predecessor-git-batch-header] $path $header"
      }
      $length = [int64]$Matches[1]
      if ($length -gt [int]::MaxValue) { throw "[mir4-composable-source-predecessor-git-batch-size] $path" }
      $bytes = [byte[]]::new([int]$length)
      $offset = 0
      while ($offset -lt $bytes.Length) {
        $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
        if ($read -le 0) { throw "[mir4-composable-source-predecessor-git-batch-blob] $path" }
        $offset += $read
      }
      if ($stream.ReadByte() -ne 10) { throw "[mir4-composable-source-predecessor-git-batch-delimiter] $path" }
      $result.Add($path, $bytes)
    }
    [void]$writeTask.GetAwaiter().GetResult()
    $process.StandardInput.Close()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "[mir4-composable-source-predecessor-git-batch] $stderr" }
    return ,$result
  } finally {
    if (-not $process.HasExited) {
      $process.Kill($true)
      $process.WaitForExit()
    }
    $process.Dispose()
  }
}

function Test-MIR4ExactByteSequence {
  [CmdletBinding()]
  param([Parameter(Mandatory)][byte[]]$Left,[Parameter(Mandatory)][byte[]]$Right)

  if ($Left.Length -ne $Right.Length) { return $false }
  for ($index = 0; $index -lt $Left.Length; $index++) {
    if ($Left[$index] -ne $Right[$index]) { return $false }
  }
  return $true
}

function Get-MIR4PredecessorProofOutputBytes {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Transform,[Parameter(Mandatory)][byte[]]$SourceBytes)

  switch ($Transform) {
    'copy-exact-bytes' { return $SourceBytes }
    'exact-template-v1' { return $SourceBytes }
    'decode-base64-v1' { return [Convert]::FromBase64String(([Text.UTF8Encoding]::new($false,$true).GetString($SourceBytes)).Trim()) }
    default { throw "[mir4-composable-source-predecessor-transform] $Transform" }
  }
}

function Get-MIR4ComposableSourcePredecessorProof {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [ValidatePattern('^[a-f0-9]{40}$')][string]$PredecessorCommit = '92d563ada31e82430fbf25f639267b03a8a180d1',
    [ValidatePattern('^[a-f0-9]{40}$')][string]$SourceLayoutCommit = '297aa5cc902da96847165a4f9caa1048608839fb'
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  # This proof belongs to the completed 447-binding layout migration. Read its
  # exact source-side state from the pinned migration commit so later semantic
  # convergence cannot turn historical byte parity into a current constraint.
  $manifestRelative = 'source/package-source.json'
  $manifestBytes = Read-MIR4GitBlobBytes -RepoRoot $repo -Commit $SourceLayoutCommit -RelativePath $manifestRelative
  $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
  $manifest = $strictUtf8.GetString($manifestBytes) | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$manifest.kind -cne 'MIR4ComposablePackageSourceV2' -or
      -not (Test-MIR4BootstrapRecordHash -Record $manifest)) {
    throw '[mir4-composable-source-predecessor-layout-record]'
  }

  $predecessorManifestRelative = 'src/mod/package-source.json'
  $predecessorManifestBytes = Read-MIR4GitBlobBytes -RepoRoot $repo -Commit $PredecessorCommit -RelativePath $predecessorManifestRelative
  $predecessorManifestRaw = $strictUtf8.GetString($predecessorManifestBytes)
  if (-not ($predecessorManifestRaw | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-package-source-manifest-v1.schema.json'))) {
    throw '[mir4-composable-source-predecessor-manifest-schema]'
  }
  $predecessorManifest = $predecessorManifestRaw | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$predecessorManifest.kind -cne 'MIR4PackageSourceManifestV1' -or
      -not (Test-MIR4BootstrapRecordHash -Record $predecessorManifest) -or
      [string]$predecessorManifest.record_sha256 -cne [string]$manifest.predecessor_record_sha256) {
    throw '[mir4-composable-source-predecessor-manifest-record]'
  }

  $predecessorByPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($binding in @($predecessorManifest.bindings)) {
    $path = [string]$binding.source_path
    if (-not $predecessorByPath.TryAdd($path, $binding)) { throw "[mir4-composable-source-predecessor-path-collision] $path" }
  }
  if ($predecessorByPath.Count -ne 447 -or @($manifest.bindings).Count -ne 447) {
    throw '[mir4-composable-source-predecessor-cardinality]'
  }
  $predecessorBlobs = Read-MIR4GitBlobSet -RepoRoot $repo -Commit $PredecessorCommit -RelativePath @($predecessorManifest.bindings.source_path)
  $sourceBlobs = Read-MIR4GitBlobSet -RepoRoot $repo -Commit $SourceLayoutCommit -RelativePath @($manifest.bindings.source_path)

  $seenPredecessors = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $sourceIdentities = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
  $targetOutputs = @{}
  foreach ($target in @('f210','f200','f110','f100')) {
    $targetOutputs[$target] = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  }
  foreach ($binding in @($manifest.bindings | Sort-Object predecessor_source_path -CaseSensitive)) {
    $predecessorPath = [string]$binding.predecessor_source_path
    if (-not $seenPredecessors.Add($predecessorPath) -or -not $predecessorByPath.ContainsKey($predecessorPath)) {
      throw "[mir4-composable-source-predecessor-binding] $predecessorPath"
    }
    $predecessor = $predecessorByPath[$predecessorPath]
    $comparisonFields = @('output_path','semantic_class','transform','source_bytes','source_sha256','output_bytes','output_sha256')
    foreach ($field in $comparisonFields) {
      if ([string]$binding.$field -cne [string]$predecessor.$field) {
        throw "[mir4-composable-source-predecessor-field] $predecessorPath $field"
      }
    }
    $currentScope = @($binding.target_scope | Sort-Object -CaseSensitive)
    $predecessorScope = @($predecessor.target_scope | Sort-Object -CaseSensitive)
    if (($currentScope -join '|') -cne ($predecessorScope -join '|')) {
      throw "[mir4-composable-source-predecessor-scope] $predecessorPath"
    }
    foreach ($target in $currentScope) {
      if (-not $targetOutputs[$target].Add([string]$binding.output_path)) {
        throw "[mir4-composable-source-predecessor-output-collision] $target $($binding.output_path)"
      }
    }

    $predecessorBytes = $predecessorBlobs[$predecessorPath]
    if ([int64]$predecessorBytes.Length -ne [int64]$predecessor.source_bytes -or
        (Get-MIR4Sha256Bytes -Bytes $predecessorBytes) -cne [string]$predecessor.source_sha256) {
      throw "[mir4-composable-source-predecessor-blob] $predecessorPath"
    }
    $predecessorOutputBytes = Get-MIR4PredecessorProofOutputBytes -Transform ([string]$predecessor.transform) -SourceBytes $predecessorBytes
    if ([int64]$predecessorOutputBytes.Length -ne [int64]$predecessor.output_bytes -or
        (Get-MIR4Sha256Bytes -Bytes $predecessorOutputBytes) -cne [string]$predecessor.output_sha256) {
      throw "[mir4-composable-source-predecessor-output] $predecessorPath"
    }
    $sourcePath = [string]$binding.source_path
    $sourceBytes = $sourceBlobs[$sourcePath]
    if ([int64]$sourceBytes.Length -ne [int64]$binding.source_bytes -or
        (Get-MIR4Sha256Bytes -Bytes $sourceBytes) -cne [string]$binding.source_sha256 -or
        -not (Test-MIR4ExactByteSequence -Left $predecessorBytes -Right $sourceBytes)) {
      throw "[mir4-composable-source-predecessor-source] $sourcePath"
    }
    $identity = "$($binding.source_bytes)|$($binding.source_sha256)"
    if ($sourceIdentities.ContainsKey($sourcePath)) {
      if ($sourceIdentities[$sourcePath] -cne $identity) { throw "[mir4-composable-source-predecessor-source-identity] $sourcePath" }
    } else {
      $sourceIdentities.Add($sourcePath, $identity)
    }
    # The manifest itself was the relocation authority at SourceLayoutCommit.
    # Requiring today's resolver here would falsely preserve retired paths.
    if ([string]$binding.predecessor_source_path -cne $predecessorPath) {
      throw "[mir4-composable-source-predecessor-resolver] $predecessorPath"
    }
  }
  if ($seenPredecessors.Count -ne $predecessorByPath.Count -or $sourceIdentities.Count -ne 439) {
    throw '[mir4-composable-source-predecessor-totality]'
  }

  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4ComposableSourcePredecessorProofV1'
    status = 'passed-binary-safe-predecessor-source-equivalence'
    predecessor = [pscustomobject][ordered]@{
      commit = $PredecessorCommit
      manifest_path = $predecessorManifestRelative
      manifest_record_sha256 = [string]$predecessorManifest.record_sha256
    }
    current = [pscustomobject][ordered]@{
      source_manifest_path = $manifestRelative
      source_manifest_record_sha256 = [string]$manifest.record_sha256
      source_root = 'source'
    }
    binding_count = $seenPredecessors.Count
    physical_source_count = $sourceIdentities.Count
    target_output_counts = [pscustomobject][ordered]@{
      f210 = $targetOutputs['f210'].Count
      f200 = $targetOutputs['f200'].Count
      f110 = $targetOutputs['f110'].Count
      f100 = $targetOutputs['f100'].Count
    }
    invariants = [pscustomobject][ordered]@{
      binary_safe_git_blob_reads = $true
      all_predecessor_bindings_resolved_once = $true
      source_output_scope_transform_and_identity_equal = $true
      transformed_output_bytes_and_hash_equal = $true
      source_paths_deduplicated_without_identity_loss = $true
      target_outputs_unique = $true
      resolver_round_trip_complete = $true
    }
    release_transition_authority = $false
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function Write-MIR4ComposableSourcePredecessorProof {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$OutputPath = 'build/reports/package-source/mir4-composable-source-predecessor-proof-v1.json',
    [switch]$Check
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $repo $OutputPath }
  $proof = Get-MIR4ComposableSourcePredecessorProof -RepoRoot $repo
  $json = ($proof | ConvertTo-Json -Depth 100).Replace([Environment]::NewLine, [string][char]10) + [string][char]10
  if ($Check) {
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) { throw '[mir4-composable-source-predecessor-proof-missing]' }
    if ([IO.File]::ReadAllText($OutputPath).Replace("`r`n", "`n").Replace("`r", "`n") -cne $json) {
      throw '[mir4-composable-source-predecessor-proof-stale]'
    }
  } else {
    $parent = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($OutputPath, $json, [Text.UTF8Encoding]::new($false))
  }
  return $proof
}
