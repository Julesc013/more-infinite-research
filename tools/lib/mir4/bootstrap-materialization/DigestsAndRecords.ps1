function Get-MIR4Sha256Bytes {
  param([Parameter(Mandatory)][byte[]]$Bytes)

  $algorithm = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace("-", "")
  } finally {
    $algorithm.Dispose()
  }
}

function Get-MIR4Sha256String {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

  return Get-MIR4Sha256Bytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($Value))
}

function Get-MIR4DomainSha256 {
  param(
    [Parameter(Mandatory)][string]$Domain,
    [Parameter(Mandatory)][Collections.IDictionary]$Fields
  )

  if ($Domain -notmatch '^mir4\.[a-z0-9.-]+\.v[0-9]+$') { throw "Invalid MIR 4 digest domain: $Domain" }
  $material = [pscustomobject][ordered]@{ domain = $Domain; fields = $Fields }
  return Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $material)
}

function Get-MIR4Sha256File {
  param([Parameter(Mandatory)][string]$Path)

  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-MIR4BootstrapTextSha256 {
  param([Parameter(Mandatory)][string]$Path)

  $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
  $canonical = $text.Replace("`r`n", "`n").Replace("`r", "`n")
  return Get-MIR4Sha256String -Value $canonical
}

function Get-MIR4RawFileIdentity {
  param([Parameter(Mandatory)][string]$Path)

  $resolved = (Resolve-Path -LiteralPath $Path).Path
  return [pscustomobject][ordered]@{
    bytes = [long](Get-Item -LiteralPath $resolved).Length
    sha256 = Get-MIR4Sha256File -Path $resolved
  }
}

function Get-MIR4GitObjectSha1 {
  param(
    [Parameter(Mandatory)][ValidateSet('blob', 'tree', 'commit')][string]$Type,
    [Parameter(Mandatory)][byte[]]$Bytes
  )

  $prefix = [Text.Encoding]::ASCII.GetBytes("$Type $($Bytes.Length)`0")
  $material = [byte[]]::new($prefix.Length + $Bytes.Length)
  [Array]::Copy($prefix, 0, $material, 0, $prefix.Length)
  [Array]::Copy($Bytes, 0, $material, $prefix.Length, $Bytes.Length)
  $algorithm = [Security.Cryptography.SHA1]::Create()
  try {
    return ([BitConverter]::ToString($algorithm.ComputeHash($material))).Replace('-', '').ToLowerInvariant()
  } finally {
    $algorithm.Dispose()
  }
}

function Get-MIR4GitBlobSha1File {
  param([Parameter(Mandatory)][string]$Path)
  return Get-MIR4GitObjectSha1 -Type blob -Bytes ([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path))
}

function ConvertTo-MIR4BootstrapCanonicalValue {
  param([Parameter(Mandatory)][AllowNull()]$Value)

  if ($Value -is [string]) {
    # Canonical record timestamps are lexical RFC 3339 values. Converting them
    # to runtime date objects lets ConvertTo-Json apply host-version or local
    # time-zone rules, which makes an authority self-hash machine-dependent.
    return $Value
  }
  if ($Value -is [Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in $Value.Keys) {
      $result[$key] = ConvertTo-MIR4BootstrapCanonicalValue -Value $Value[$key]
    }
    return $result
  }
  if ($Value -is [pscustomobject]) {
    $result = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
      $result[$property.Name] = ConvertTo-MIR4BootstrapCanonicalValue -Value $property.Value
    }
    return [pscustomobject]$result
  }
  if ($Value -is [Collections.IEnumerable]) {
    $items = [Collections.Generic.List[object]]::new()
    foreach ($item in $Value) {
      $items.Add((ConvertTo-MIR4BootstrapCanonicalValue -Value $item))
    }
    return ,$items.ToArray()
  }
  return $Value
}

function ConvertTo-MIR4BootstrapCanonicalJson {
  param([Parameter(Mandatory)]$Value)

  # BootstrapCanonicalJsonV1 is intentionally narrow: tool-created ordered objects,
  # integer numbers, arrays in authority order, lexical RFC 3339 timestamps,
  # UTF-8, no BOM, and no insignificant space. Timestamp text preserves its
  # explicit offset (or Z), independent of the runner time zone.
  $canonicalValue = ConvertTo-MIR4BootstrapCanonicalValue -Value $Value
  return (($canonicalValue | ConvertTo-Json -Depth 100 -Compress) -replace "`r`n", "`n" -replace "`r", "`n")
}

function Get-MIR4BootstrapRecordSha256 {
  param([Parameter(Mandatory)]$Record)

  $unsigned = [ordered]@{}
  foreach ($property in $Record.PSObject.Properties) {
    if ($property.Name -ne "record_sha256") {
      $unsigned[$property.Name] = $property.Value
    }
  }
  return Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value ([pscustomobject]$unsigned))
}

function Write-MIR4BootstrapRecord {
  param(
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string]$Path
  )

  $hash = Get-MIR4BootstrapRecordSha256 -Record $Record
  if ($Record -is [Collections.IDictionary]) {
    $Record["record_sha256"] = $hash
  } else {
    $existing = $Record.PSObject.Properties["record_sha256"]
    if ($null -eq $existing) {
      $Record | Add-Member -NotePropertyName record_sha256 -NotePropertyValue $hash
    } else {
      $existing.Value = $hash
    }
  }

  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $json = ConvertTo-MIR4BootstrapCanonicalJson -Value $Record
  [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
  return $hash
}

function Test-MIR4BootstrapRecordHash {
  param([Parameter(Mandatory)]$Record)

  $expected = [string]$Record.record_sha256
  return $expected -match '^[A-F0-9]{64}$' -and $expected -eq (Get-MIR4BootstrapRecordSha256 -Record $Record)
}

function Test-MIR3Dot9PortalVisibilityHashReconciliation {
  param(
    [Parameter(Mandatory)]$HistoricalRecord,
    [Parameter(Mandatory)]$Reconciliation,
    [Parameter(Mandatory)][string]$HistoricalRecordPath
  )

  if (-not (Test-Path -LiteralPath $HistoricalRecordPath -PathType Leaf) -or
      -not (Test-MIR4BootstrapRecordHash -Record $Reconciliation) -or
      (Get-MIR4Sha256File -Path $HistoricalRecordPath) -cne [string]$Reconciliation.historical_record.raw_sha256 -or
      [string]$Reconciliation.historical_record.path -cne '.mir/evidence/terminal-publication/2026-08-16/mod-portal/MIR3-Dot9-ModPortal-VisibilityRecheckV1.json' -or
      [string]$Reconciliation.historical_record.normalized_field -cne 'sources[0].matched_rows[1].released_at:.140Z-to-.14Z' -or
      [string]$Reconciliation.classification -cne 'inherited-self-hash-canonicalization-interpretation-contradiction' -or
      [bool]$Reconciliation.current_portal_claim_authorized -or
      @($Reconciliation.authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
    return $false
  }

  $legacyRecord = $HistoricalRecord | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  foreach ($source in @($legacyRecord.sources)) {
    foreach ($row in @($source.matched_rows)) {
      if ($null -ne $row.PSObject.Properties['released_at'] -and [string]$row.released_at -match '^(?<prefix>.+\.\d*?[1-9])0+Z$') {
        $row.released_at = [string]$Matches.prefix + 'Z'
      }
    }
  }
  $legacyHash = Get-MIR4BootstrapRecordSha256 -Record $legacyRecord
  $lexicalHash = Get-MIR4BootstrapRecordSha256 -Record $HistoricalRecord
  return $legacyHash -ceq [string]$HistoricalRecord.record_sha256 -and
    $legacyHash -ceq [string]$Reconciliation.historical_record.stored_record_sha256 -and
    $legacyHash -ceq [string]$Reconciliation.historical_record.legacy_timestamp_normalized_sha256 -and
    $lexicalHash -ceq [string]$Reconciliation.historical_record.lexical_rfc3339_sha256 -and
    $legacyHash -cne $lexicalHash
}
