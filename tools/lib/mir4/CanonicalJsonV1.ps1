function New-MIR4CanonicalJsonV1Error {
  param([Parameter(Mandatory)][string]$Code,[string]$Detail='')
  $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " $Detail" }
  return [IO.InvalidDataException]::new("[$Code]$suffix")
}

function ConvertTo-MIR4CanonicalJsonV1String {
  param([AllowEmptyString()][string]$Value)
  try { $normalized = $Value.Normalize([Text.NormalizationForm]::FormC) }
  catch { throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-invalid-unicode') }
  $builder = [Text.StringBuilder]::new()
  [void]$builder.Append('"')
  for ($index = 0; $index -lt $normalized.Length; $index++) {
    $code = [int][char]$normalized[$index]
    if ($code -ge 0xD800 -and $code -le 0xDBFF) {
      if ($index + 1 -ge $normalized.Length) { throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-invalid-unicode') }
      $low = [int][char]$normalized[$index + 1]
      if ($low -lt 0xDC00 -or $low -gt 0xDFFF) { throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-invalid-unicode') }
      [void]$builder.Append($normalized[$index])
      [void]$builder.Append($normalized[$index + 1])
      $index++
      continue
    }
    if ($code -ge 0xDC00 -and $code -le 0xDFFF) { throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-invalid-unicode') }
    $escaped = switch ($code) {
      0x08 { '\b' }
      0x09 { '\t' }
      0x0A { '\n' }
      0x0C { '\f' }
      0x0D { '\r' }
      0x22 { '\"' }
      0x5C { '\\' }
      default { $null }
    }
    if ($null -ne $escaped) { [void]$builder.Append($escaped) }
    elseif ($code -lt 0x20) { [void]$builder.Append(('\u{0:x4}' -f $code)) }
    else { [void]$builder.Append([char]$code) }
  }
  [void]$builder.Append('"')
  return $builder.ToString()
}

function Write-MIR4CanonicalJsonV1Element {
  param(
    [Parameter(Mandatory)][System.Text.Json.JsonElement]$Element,
    [Parameter(Mandatory)][Text.StringBuilder]$Builder,
    [int]$Depth = 0
  )
  if ($Depth -gt 64) {
    throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-depth')
  }
  switch ($Element.ValueKind) {
    ([System.Text.Json.JsonValueKind]::Object) {
      $properties = [Collections.Generic.Dictionary[string,System.Text.Json.JsonElement]]::new([StringComparer]::Ordinal)
      $originalNames = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
      foreach ($property in $Element.EnumerateObject()) {
        try { $name = ([string]$property.Name).Normalize([Text.NormalizationForm]::FormC) }
        catch { throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-invalid-unicode') }
        if ($properties.ContainsKey($name)) {
          $code = if ([StringComparer]::Ordinal.Equals([string]$property.Name, $originalNames[$name])) { 'mir4-canon-duplicate-key' } else { 'mir4-canon-unicode-key-collision' }
          throw (New-MIR4CanonicalJsonV1Error -Code $code -Detail $name)
        }
        $properties.Add($name, $property.Value)
        $originalNames.Add($name, [string]$property.Name)
      }
      $keys = [string[]]@($properties.Keys)
      [Array]::Sort($keys, [StringComparer]::Ordinal)
      [void]$Builder.Append('{')
      for ($index = 0; $index -lt $keys.Count; $index++) {
        if ($index -gt 0) { [void]$Builder.Append(',') }
        [void]$Builder.Append((ConvertTo-MIR4CanonicalJsonV1String $keys[$index]))
        [void]$Builder.Append(':')
        Write-MIR4CanonicalJsonV1Element -Element $properties[$keys[$index]] -Builder $Builder -Depth ($Depth + 1)
      }
      [void]$Builder.Append('}')
      break
    }
    ([System.Text.Json.JsonValueKind]::Array) {
      [void]$Builder.Append('[')
      $index = 0
      foreach ($item in $Element.EnumerateArray()) {
        if ($index -gt 0) { [void]$Builder.Append(',') }
        Write-MIR4CanonicalJsonV1Element -Element $item -Builder $Builder -Depth ($Depth + 1)
        $index++
      }
      [void]$Builder.Append(']')
      break
    }
    ([System.Text.Json.JsonValueKind]::String) {
      try { $value = $Element.GetString() }
      catch { throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-invalid-unicode') }
      [void]$Builder.Append((ConvertTo-MIR4CanonicalJsonV1String $value))
      break
    }
    ([System.Text.Json.JsonValueKind]::Number) {
      $raw = $Element.GetRawText()
      if ($raw -notmatch '^-?(?:0|[1-9][0-9]*)$') {
        throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-unsupported-number' -Detail $raw)
      }
      if ($raw -ceq '-0') { throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-negative-zero') }
      $integer = [System.Numerics.BigInteger]::Parse($raw, [Globalization.CultureInfo]::InvariantCulture)
      if ($integer -lt [System.Numerics.BigInteger]::Parse('-9007199254740991') -or $integer -gt [System.Numerics.BigInteger]::Parse('9007199254740991')) {
        throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-unsafe-integer' -Detail $raw)
      }
      [void]$Builder.Append($raw)
      break
    }
    ([System.Text.Json.JsonValueKind]::True) { [void]$Builder.Append('true'); break }
    ([System.Text.Json.JsonValueKind]::False) { [void]$Builder.Append('false'); break }
    ([System.Text.Json.JsonValueKind]::Null) { [void]$Builder.Append('null'); break }
    default { throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-invalid-json') }
  }
}

function ConvertFrom-MIR4CanonicalJsonTextV1 {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)
  if ($Json.Length -gt 0 -and [int][char]$Json[0] -eq 0xFEFF) {
    throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-utf8-bom')
  }
  $options = [System.Text.Json.JsonDocumentOptions]::new()
  $options.AllowTrailingCommas = $false
  $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Disallow
  $options.MaxDepth = 65
  try { $document = [System.Text.Json.JsonDocument]::Parse($Json, $options) }
  catch [System.Text.Json.JsonException] {
    if ($_.Exception.Message -match 'maximum configured depth') { throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-depth') }
    throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-invalid-json')
  }
  try {
    $builder = [Text.StringBuilder]::new()
    Write-MIR4CanonicalJsonV1Element -Element $document.RootElement -Builder $builder
    return $builder.ToString()
  } finally {
    $document.Dispose()
  }
}

function ConvertTo-MIR4CanonicalJsonV1 {
  param([Parameter(Mandatory)][AllowNull()]$Value)
  $json = $Value | ConvertTo-Json -Depth 100 -Compress
  return ConvertFrom-MIR4CanonicalJsonTextV1 -Json $json
}

function Get-MIR4CanonicalDigestV1 {
  param(
    [Parameter(Mandatory)][AllowNull()]$Value,
    [Parameter(Mandatory)][ValidatePattern('^mir4:[a-z0-9][a-z0-9.:-]{0,95}$')][string]$Domain,
    [switch]$OmitTopLevelDigest
  )
  $material = $Value
  if ($OmitTopLevelDigest) {
    $copy = [ordered]@{}
    if ($Value -is [Collections.IDictionary]) {
      foreach ($key in $Value.Keys) { if ([string]$key -cne 'digest') { $copy[[string]$key] = $Value[$key] } }
    } else {
      foreach ($property in $Value.PSObject.Properties) { if ($property.Name -cne 'digest') { $copy[$property.Name] = $property.Value } }
    }
    $material = $copy
  }
  $canonical = ConvertTo-MIR4CanonicalJsonV1 -Value $material
  $encoding = [Text.UTF8Encoding]::new($false, $true)
  $prefix = $encoding.GetBytes("mir-canonical-json/1$([char]0)$Domain$([char]0)")
  $payload = $encoding.GetBytes($canonical)
  $bytes = [byte[]]::new($prefix.Length + $payload.Length)
  [Array]::Copy($prefix, 0, $bytes, 0, $prefix.Length)
  [Array]::Copy($payload, 0, $bytes, $prefix.Length, $payload.Length)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return 'sha256:' + ([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()) }
  finally { $sha.Dispose() }
}

function Get-MIR4RecordDigestDomainV1 {
  param([Parameter(Mandatory)]$Value)
  $kind = ''
  if ($Value -is [Collections.IDictionary]) {
    if ($Value.Contains('kind')) { $kind = [string]$Value['kind'] }
  } elseif ($null -ne $Value.PSObject.Properties['kind']) {
    $kind = [string]$Value.kind
  }
  switch ($kind) {
    'MIR4ApiResponseV1' { return 'mir4:api-response-v1' }
    'MIR4ExtensionEnvelopeV1' { return 'mir4:extension-envelope-v1' }
    'MIR4PlatformLockV1' { return 'mir4:platform-lock-v1' }
    default {
      if ([string]::IsNullOrWhiteSpace($kind)) { return 'mir4:module-value-v1' }
      if ($kind -notmatch '^[A-Za-z0-9.-]+$') {
        throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-record-kind')
      }
      return 'mir4:record:' + $kind.ToLowerInvariant()
    }
  }
}

function Test-MIR4CanonicalTimestampV1 {
  param([Parameter(Mandatory)][string]$Value)
  if ($Value -notmatch '^[0-9]{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12][0-9]|3[01])T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$') {
    throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-timestamp' -Detail $Value)
  }
  $parsed = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParseExact($Value, 'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
    throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-timestamp' -Detail $Value)
  }
  return $true
}

function Test-MIR4CanonicalTargetIdV1 {
  param([Parameter(Mandatory)][string]$Value)
  if ($Value -cnotmatch '^f[0-9]{3}$') { throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-canon-target-id' -Detail $Value) }
  return $true
}

function Test-MIR4ExplicitAvailabilityV1 {
  param([Parameter(Mandatory)]$Availability,[Parameter(Mandatory)]$Page)
  if ([string]$Availability.status -notin @('available','unavailable')) {
    throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-api-availability')
  }
  if ([string]$Availability.status -eq 'unavailable' -and ($null -ne $Page.total -or [int]$Page.returned -ne 0)) {
    throw (New-MIR4CanonicalJsonV1Error -Code 'mir4-api-unavailable-is-not-zero')
  }
  return $true
}

function Get-MIR4OrdinalSortedUniqueV1 {
  param([AllowEmptyCollection()][string[]]$Values)
  $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($value in @($Values)) { [void]$set.Add([string]$value) }
  $result = [string[]]@($set)
  [Array]::Sort($result, [StringComparer]::Ordinal)
  return @($result)
}

function Test-MIR4OrdinalSortedUniqueV1 {
  param([AllowEmptyCollection()][string[]]$Values,[string]$Diagnostic='mir4-canon-array-order')
  $expected = @(Get-MIR4OrdinalSortedUniqueV1 -Values $Values)
  if ($expected.Count -ne @($Values).Count) { throw (New-MIR4CanonicalJsonV1Error -Code $Diagnostic) }
  for ($index = 0; $index -lt $expected.Count; $index++) {
    if (-not [StringComparer]::Ordinal.Equals($expected[$index], [string]$Values[$index])) {
      throw (New-MIR4CanonicalJsonV1Error -Code $Diagnostic)
    }
  }
  return $true
}
