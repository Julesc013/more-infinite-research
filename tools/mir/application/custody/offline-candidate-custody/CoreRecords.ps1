function Get-MIR4CustodyRepoRootV1 {
  param([string]$RepoRoot = "")

  if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Join-Path $script:MIR4OfflineCustodyApplicationRootV1 "../../../.."
  }
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4CustodySchemaRootV1 {
  param(
    [string]$RepoRoot = "",
    [string]$SchemaRoot = ""
  )

  if (-not [string]::IsNullOrWhiteSpace($SchemaRoot)) {
    return (Resolve-Path -LiteralPath $SchemaRoot).Path
  }
  return Join-Path (Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot) "spec/schemas"
}

function Write-MIR4CustodyRecordV1 {
  param(
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string]$Path
  )

  if ([string]$Record.canonicalization -cne $script:MIR4BootstrapCanonicalizationV1) {
    throw "MIR 4 custody records must declare $($script:MIR4BootstrapCanonicalizationV1)."
  }
  if (Test-Path -LiteralPath $Path) {
    throw "MIR 4 custody records are immutable and cannot overwrite an existing path: $Path"
  }
  $null = Write-MIR4BootstrapRecord -Record $Record -Path $Path
  return Assert-MIR4BootstrapRecordFileV1 -Path $Path
}

function Assert-MIR4BootstrapRecordFileV1 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$SchemaPath = ""
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "MIR 4 custody record is missing: $Path"
  }
  $bytes = [IO.File]::ReadAllBytes($Path)
  $decoder = [Text.UTF8Encoding]::new($false, $true)
  try { $text = $decoder.GetString($bytes) } catch { throw "MIR 4 custody record is not strict UTF-8: $Path" }
  if ($text.StartsWith([char]0xFEFF)) { throw "MIR 4 custody records must not contain a UTF-8 BOM: $Path" }
  try { $record = $text | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw "MIR 4 custody record is invalid JSON: $Path" }
  if (-not (Test-MIR4BootstrapRecordHash -Record $record)) {
    throw "MIR 4 custody record hash is invalid: $Path"
  }
  $canonicalText = (ConvertTo-MIR4BootstrapCanonicalJson -Value $record) + "`n"
  if ($text -cne $canonicalText) {
    throw "MIR 4 custody record bytes are not canonical $($script:MIR4BootstrapCanonicalizationV1): $Path"
  }
  if (-not [string]::IsNullOrWhiteSpace($SchemaPath)) {
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) { throw "MIR 4 custody schema is missing: $SchemaPath" }
    if (-not ($text | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) {
      throw "MIR 4 custody record does not satisfy its strict schema: $Path"
    }
  }
  return $record
}

function Assert-MIR4GovernedBootstrapRecordFileV1 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$SchemaPath
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "MIR 4 governed record is missing: $Path" }
  if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) { throw "MIR 4 governed schema is missing: $SchemaPath" }
  $bytes = [IO.File]::ReadAllBytes($Path)
  $decoder = [Text.UTF8Encoding]::new($false, $true)
  try { $text = $decoder.GetString($bytes) } catch { throw "MIR 4 governed record is not strict UTF-8: $Path" }
  if ($text.StartsWith([char]0xFEFF)) { throw "MIR 4 governed records must not contain a UTF-8 BOM: $Path" }
  try { $record = $text | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw "MIR 4 governed record is invalid JSON: $Path" }
  if (-not (Test-MIR4BootstrapRecordHash -Record $record)) { throw "MIR 4 governed record hash is invalid: $Path" }
  if (-not ($text | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) {
    throw "MIR 4 governed record does not satisfy its strict schema: $Path"
  }
  return $record
}

function Assert-MIR4CheckedRootSetFileV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$SchemaPath
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "MIR 4 bootstrap root set is missing: $Path" }
  if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) { throw "MIR 4 bootstrap root-set schema is missing: $SchemaPath" }
  $before = Get-MIR4Sha256File -Path $Path
  $checker = Join-Path $RepoRoot "tools/commands/release/New-MIR4BootstrapRootSet.ps1"
  $null = & $checker -RepoRoot $RepoRoot -OutputPath $Path -Check
  $after = Get-MIR4Sha256File -Path $Path
  if ($before -cne $after) { throw "MIR 4 bootstrap root set changed while custody verified it." }
  $bytes = [IO.File]::ReadAllBytes($Path)
  $decoder = [Text.UTF8Encoding]::new($false, $true)
  try { $text = $decoder.GetString($bytes) } catch { throw "MIR 4 bootstrap root set is not strict UTF-8: $Path" }
  if ($text.StartsWith([char]0xFEFF)) { throw "MIR 4 bootstrap root set must not contain a UTF-8 BOM: $Path" }
  if (-not ($text | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) {
    throw "MIR 4 bootstrap root set does not satisfy its strict schema: $Path"
  }
  return $text | ConvertFrom-Json -Depth 100 -DateKind String
}

function New-MIR4CustodyRecordBindingV1 {
  param(
    [Parameter(Mandatory)][string]$Role,
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string]$Path
  )

  return [pscustomobject][ordered]@{
    role = $Role
    kind = [string]$Record.kind
    record_sha256 = [string]$Record.record_sha256
    file_sha256 = Get-MIR4Sha256File -Path $Path
  }
}
