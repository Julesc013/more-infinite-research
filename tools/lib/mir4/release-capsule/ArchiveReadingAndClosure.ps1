function Read-MIR4ReleaseCapsuleEntryBytesV1 {
  param(
    [Parameter(Mandatory)][string]$CapsulePath,
    [Parameter(Mandatory)][string]$RelativePath,
    [ValidateRange(1, 268435456)][long]$MaximumBytes = 16777216
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $CapsulePath).Path)
  try {
    $fullName = "$script:MIR4ReleaseCapsuleRootV1/$RelativePath"
    $entry = @($zip.Entries | Where-Object { [string]$_.FullName -ceq $fullName })
    if ($entry.Count -ne 1 -or [long]$entry[0].Length -gt $MaximumBytes) {
      throw "[mir4-release-capsule-entry-read] $RelativePath"
    }
    return ,([byte[]](Read-MIR4BoundedZipEntryBytes -Entry $entry[0] -MaximumBytes $MaximumBytes))
  } finally {
    $zip.Dispose()
  }
}

function Read-MIR4ReleaseCapsuleManifestV1 {
  param([Parameter(Mandatory)][string]$CapsulePath)
  $bytes = Read-MIR4ReleaseCapsuleEntryBytesV1 -CapsulePath $CapsulePath -RelativePath 'metadata/capsule-manifest.json'
  return [Text.UTF8Encoding]::new($false, $true).GetString($bytes) |
    ConvertFrom-Json -Depth 100 -DateKind String
}

function Test-MIR4ReleaseCapsuleRoleClosureV1 {
  param([Parameter(Mandatory)][object[]]$Objects)

  $exact = [ordered]@{
    'source-archive' = 1
    'source-archive-envelope' = 1
    'source-release-record' = 1
    'target-distribution-record-set' = 1
    'component-inventory' = 1
    'sbom-spdx-3.0.1' = 1
    'sbom-spdx-2.3' = 1
    'provenance-slsa-v1' = 1
    'supply-chain-attestation' = 1
    'proof-public-key' = 1
    'proof-closure-summary' = 1
    'restore-instructions' = 1
    'rights-custody-inventory' = 1
    'preview-asset' = 4
  }
  foreach ($entry in $exact.GetEnumerator()) {
    if (@($Objects | Where-Object { [string]$_.role -ceq [string]$entry.Key }).Count -ne [int]$entry.Value) {
      return $false
    }
  }
  return @($Objects | Where-Object { [string]$_.role -notin @($exact.Keys) }).Count -eq 0
}
