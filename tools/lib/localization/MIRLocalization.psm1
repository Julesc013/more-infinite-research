Set-StrictMode -Version Latest

function Get-MIRTextSha256 {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "")
  }
  finally {
    $sha.Dispose()
  }
}

function Read-MIRLocaleFile {
  param([Parameter(Mandatory)][string]$Path)

  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $section = $null
  $sections = [System.Collections.Generic.List[string]]::new()
  $sectionKeys = [ordered]@{}
  $entries = [ordered]@{}
  $lineNumbers = @{}
  $lineNo = 0

  foreach ($line in Get-Content -LiteralPath $resolved -Encoding UTF8) {
    $lineNo++
    if ($line -match '^\s*$') { continue }
    if ($line -match '^\[([^\]]+)\]$') {
      $section = $matches[1]
      if ($sectionKeys.Contains($section)) {
        throw "$resolved`:$lineNo duplicates locale section [$section]."
      }
      $sections.Add($section)
      $sectionKeys[$section] = [System.Collections.Generic.List[string]]::new()
      continue
    }
    if ($line -match '^\s*[;#]') { continue }
    if ($null -eq $section) {
      throw "$resolved`:$lineNo has an entry before any section header."
    }

    $idx = $line.IndexOf("=")
    if ($idx -lt 1) {
      throw "$resolved`:$lineNo is not a valid Factorio locale key/value row."
    }

    $key = $line.Substring(0, $idx)
    $value = $line.Substring($idx + 1)
    if ($key -ne $key.Trim() -or $value -ne $value.Trim()) {
      throw "$resolved`:$lineNo has whitespace around the key or value. Factorio treats it as literal text."
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
      throw "$resolved`:$lineNo has an empty locale value for [$section].$key."
    }

    $fullKey = "$section.$key"
    if ($entries.Contains($fullKey)) {
      throw "$resolved`:$lineNo duplicates locale key $fullKey."
    }
    $entries[$fullKey] = $value
    $lineNumbers[$fullKey] = $lineNo
    $sectionKeys[$section].Add($key)
  }

  [pscustomobject]@{
    Path = $resolved
    Sections = @($sections)
    SectionKeys = $sectionKeys
    Entries = $entries
    LineNumbers = $lineNumbers
  }
}

function Get-MIRPlaceholderSequence {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
  return @([regex]::Matches($Text, '__\d+__') | ForEach-Object { $_.Value })
}

function Get-MIRFormattingSequence {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
  return @([regex]::Matches($Text, '\[(?:/?font(?:=[^\]]+)?|/?color(?:=[^\]]+)?)\]') | ForEach-Object { $_.Value })
}

function Test-MIRFormatInvariantValue {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
  return $Text -match '^[+\-]?\d+(?:\.\d+)?%$'
}

function Get-MIRVisibleTextLength {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
  $visible = [regex]::Replace($Text, '\[[^\]]+\]', '')
  $visible = [regex]::Replace($visible, '__\d+__', '0')
  return $visible.Length
}

function Get-MIRSectionLengthLimit {
  param(
    [Parameter(Mandatory)][string]$FullKey,
    [Parameter(Mandatory)]$Policy
  )

  $section = $FullKey.Substring(0, $FullKey.IndexOf('.'))
  $property = $Policy.ui_length_limits.PSObject.Properties[$section]
  if ($null -ne $property) { return [int]$property.Value }
  return [int]$Policy.ui_length_limits.default
}

function ConvertTo-MIRPropertyMap {
  param([Parameter(Mandatory)]$Object)
  $map = @{}
  foreach ($property in $Object.PSObject.Properties) {
    $map[$property.Name] = $property.Value
  }
  return $map
}

function Read-MIRLocalePolicy {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $Path) -Encoding UTF8 | ConvertFrom-Json)
}

function Write-MIRLocaleFile {
  param(
    [Parameter(Mandatory)]$Template,
    [Parameter(Mandatory)][System.Collections.IDictionary]$Values,
    [Parameter(Mandatory)][string]$Path
  )

  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($section in $Template.Sections) {
    $lines.Add("[$section]")
    foreach ($key in $Template.SectionKeys[$section]) {
      $fullKey = "$section.$key"
      if (-not $Values.Contains($fullKey)) {
        throw "Cannot generate $Path because translation $fullKey is missing."
      }
      $lines.Add("$key=$($Values[$fullKey])")
    }
    $lines.Add("")
  }
  if ($lines.Count -gt 0) { $lines.RemoveAt($lines.Count - 1) }

  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }
  Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
}

Export-ModuleMember -Function @(
  'ConvertTo-MIRPropertyMap',
  'Get-MIRFormattingSequence',
  'Get-MIRPlaceholderSequence',
  'Get-MIRSectionLengthLimit',
  'Get-MIRTextSha256',
  'Get-MIRVisibleTextLength',
  'Read-MIRLocaleFile',
  'Read-MIRLocalePolicy',
  'Test-MIRFormatInvariantValue',
  'Write-MIRLocaleFile'
)
