function New-MIR4DeterministicGitSourceArchiveV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SourceCommit,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ContainmentRoot
  )

  $repo = Get-MIR4ReleaseCapsuleRepoRootV1 -RepoRoot $RepoRoot
  if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$') { throw '[mir4-release-capsule-source-commit]' }
  $resolvedCommit = (& git -C $repo rev-parse --verify "$SourceCommit^{commit}").Trim()
  if ($LASTEXITCODE -ne 0 -or $resolvedCommit -cne $SourceCommit) {
    throw '[mir4-release-capsule-source-commit-unavailable]'
  }
  $sourceTree = (& git -C $repo rev-parse "$SourceCommit^{tree}").Trim()
  if ($LASTEXITCODE -ne 0 -or $sourceTree -cnotmatch '^[0-9a-f]{40}$') {
    throw '[mir4-release-capsule-source-tree]'
  }
  $output = Assert-MIR4DescendantPath -Root $ContainmentRoot -Path $OutputPath
  $null = Assert-MIR4NoReparseAncestors -Root $ContainmentRoot -Path $output
  $parent = Split-Path -Parent $output
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $temporary = $output + '.new'
  if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
  $git = @(Get-Command git -CommandType Application -ErrorAction Stop | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.Source) -and
    (Test-Path -LiteralPath $_.Source -PathType Leaf)
  } | Select-Object -First 1)
  if ($git.Count -ne 1) { throw '[mir4-release-capsule-git-executable]' }
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = [string]$git[0].Source
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  foreach ($argument in @(
    '-c', 'core.autocrlf=false', '-c', 'core.eol=lf',
    '-C', $repo, 'archive', '--format=zip', '--prefix=mir4-source/',
    "--output=$temporary", $SourceCommit
  )) {
    $null = $info.ArgumentList.Add($argument)
  }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  if (-not $process.Start()) { throw '[mir4-release-capsule-git-archive-start]' }
  $standardOutput = $process.StandardOutput.ReadToEnd()
  $standardError = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  $exitCode = $process.ExitCode
  $process.Dispose()
  if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $temporary -PathType Leaf)) {
    throw "[mir4-release-capsule-git-archive] $standardError $standardOutput"
  }
  $inventory = Get-MIR4ArchiveInventory -Path $temporary -MaxEntries 100000 -MaxEntryBytes 268435456 -MaxExpandedBytes 1073741824
  if ([string]$inventory.root -cne 'mir4-source') { throw '[mir4-release-capsule-source-root]' }
  if (Test-Path -LiteralPath $output -PathType Leaf) {
    $existingHash = Get-MIR4Sha256File -Path $output
    $newHash = Get-MIR4Sha256File -Path $temporary
    if ($existingHash -cne $newHash) { throw '[mir4-release-capsule-source-archive-append-only-conflict]' }
    Remove-Item -LiteralPath $temporary -Force
  } else {
    Move-Item -LiteralPath $temporary -Destination $output
  }
  $item = Get-Item -LiteralPath $output
  return [pscustomobject][ordered]@{
    kind = 'MIR4GitSourceArchiveV1'
    source_commit = $SourceCommit
    source_tree = $sourceTree
    root = 'mir4-source'
    archive_sha256 = Get-MIR4Sha256File -Path $output
    content_sha256 = [string]$inventory.content_sha256
    bytes = [long]$item.Length
    entry_count = [int]$inventory.entry_count
    network_required = $false
    path = $output
  }
}

function Get-MIR4ReleaseCapsuleDescriptorRowsV1 {
  param([Parameter(Mandatory)][object[]]$ObjectDescriptors)

  $rows = [Collections.Generic.List[object]]::new()
  $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($descriptor in $ObjectDescriptors) {
    $role = [string]$descriptor.role
    $logicalName = [string]$descriptor.logical_name
    $path = (Resolve-Path -LiteralPath ([string]$descriptor.path)).Path
    if ($role -cnotmatch '^[a-z0-9][a-z0-9.-]{0,63}$' -or
        $logicalName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or
        [string]$descriptor.media_type -cnotmatch '^[a-z0-9.+-]+/[a-z0-9.+-]+$') {
      throw '[mir4-release-capsule-object-identity]'
    }
    $objectId = "$role.$logicalName"
    if (-not $ids.Add($objectId)) {
      throw "[mir4-release-capsule-duplicate-object-id] $objectId"
    }
    $item = Get-Item -LiteralPath $path
    $sha256 = Get-MIR4Sha256File -Path $path
    $rows.Add([pscustomobject][ordered]@{
      object_id = $objectId
      role = $role
      logical_name = $logicalName
      media_type = [string]$descriptor.media_type
      component_id = if ($descriptor.PSObject.Properties.Name -contains 'component_id') { $descriptor.component_id } else { $null }
      target = if ($descriptor.PSObject.Properties.Name -contains 'target') { $descriptor.target } else { $null }
      sha256 = $sha256
      bytes = [long]$item.Length
      path = Get-MIR4ReleaseCapsuleObjectPathV1 -Sha256 $sha256
      required_for_restore = if ($descriptor.PSObject.Properties.Name -contains 'required_for_restore') { [bool]$descriptor.required_for_restore } else { $true }
      source_path = $path
    })
  }
  return $rows.ToArray()
}
