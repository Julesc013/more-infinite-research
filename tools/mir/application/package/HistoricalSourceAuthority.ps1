Set-StrictMode -Version Latest

function Assert-MIR4PinnedHistoricalSourceAuthority {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [Parameter(Mandatory)][string]$SchemaPath,
    [Parameter(Mandatory)][string]$Kind,
    [Parameter(Mandatory)][string]$AuthorityId
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
  . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
  $absoluteReceipt = Join-Path $repo $ReceiptPath
  $raw = Get-Content -Raw -LiteralPath $absoluteReceipt
  $schemaValid = $false
  try { $schemaValid = $raw | Test-Json -SchemaFile (Join-Path $repo $SchemaPath) -ErrorAction Stop } catch { $schemaValid = $false }
  if (-not $schemaValid) { throw "[mir4-pinned-historical-source-authority-schema] $AuthorityId" }
  $receipt = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$receipt.kind -cne $Kind) { throw "[mir4-pinned-historical-source-authority-kind] $AuthorityId" }
  if ($receipt.PSObject.Properties['record_sha256'] -and -not (Test-MIR4BootstrapRecordHash -Record $receipt)) {
    throw "[mir4-pinned-historical-source-authority-hash] $AuthorityId"
  }
  if ($receipt.PSObject.Properties['transition_gate'] -and @($receipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
    throw "[mir4-pinned-historical-source-authority-gate] $AuthorityId"
  }
  $current = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  if ([string]$current.editable_source_root -cne 'source' -or
      [string]$current.source_manifest.path -cne 'source/package-source.json' -or
      [string]$current.writer.implementation -cne 'tools/mir/application/package/TargetMaterializer.ps1') {
    throw "[mir4-pinned-historical-source-authority-current-successor] $AuthorityId"
  }
  return [pscustomobject][ordered]@{
    status = 'passed-pinned-historical-source-authority-verification'
    authority_id = $AuthorityId
    classification = 'historical-verification-only'
    receipt_path = $ReceiptPath
    receipt_kind = $Kind
    current_source_root = 'source'
    current_writer = 'tools/mir/application/package/TargetMaterializer.ps1'
    player_package_mutation_authorized = $false
    publication_authorized = $false
  }
}
