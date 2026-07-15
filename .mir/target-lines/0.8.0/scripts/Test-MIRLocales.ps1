param(
  [string]$LocaleRoot = (Join-Path $PSScriptRoot "..\locale"),
  [string]$FactorioLocaleRoot = "C:\Program Files\Steam\steamapps\common\Factorio\data\base\locale",
  [switch]$AllowMissingSupportedLanguages
)

$ErrorActionPreference = "Stop"

function Read-MIRLocaleFile {
  param([string]$Path)

  $section = $null
  $entries = [ordered]@{}
  $lineNo = 0

  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    $lineNo++
    if ($line -match '^\s*$') { continue }
    if ($line -match '^\[([^\]]+)\]$') {
      $section = $matches[1]
      continue
    }
    if ($null -eq $section) {
      throw "$($Path):$lineNo has an entry before any section header."
    }

    $idx = $line.IndexOf("=")
    if ($idx -lt 1) {
      throw "$($Path):$lineNo is not a valid Factorio locale key/value row."
    }

    $key = $line.Substring(0, $idx)
    $value = $line.Substring($idx + 1)
    if ($key -ne $key.Trim() -or $value -ne $value.Trim()) {
      throw "$($Path):$lineNo has whitespace around the key or value. Factorio treats that whitespace as literal text."
    }

    $fullKey = "$section.$key"
    if ($entries.Contains($fullKey)) {
      throw "$($Path):$lineNo duplicates locale key $fullKey."
    }
    $entries[$fullKey] = $value
  }

  return $entries
}

function Get-PlaceholderSet {
  param([string]$Text)
  return @([regex]::Matches($Text, "__\d+__") | ForEach-Object { $_.Value } | Sort-Object)
}

$localeRootPath = (Resolve-Path -LiteralPath $LocaleRoot).Path
$englishPath = Join-Path $localeRootPath "en\more-infinite-research.cfg"
if (-not (Test-Path -LiteralPath $englishPath)) {
  throw "English fallback locale is missing: $englishPath"
}

$english = Read-MIRLocaleFile -Path $englishPath
$files = @(Get-ChildItem -LiteralPath $localeRootPath -Recurse -Filter "more-infinite-research.cfg")
if ($files.Count -eq 0) {
  throw "No locale files found under $localeRootPath."
}

foreach ($file in $files) {
  $entries = Read-MIRLocaleFile -Path $file.FullName
  $missing = @($english.Keys | Where-Object { -not $entries.Contains($_) })
  $extra = @($entries.Keys | Where-Object { -not $english.Contains($_) })

  if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
    throw "$($file.FullName) does not match English keys. Missing: $($missing -join ', ') Extra: $($extra -join ', ')"
  }

  foreach ($key in $english.Keys) {
    $expected = (Get-PlaceholderSet -Text $english[$key]) -join ","
    $actual = (Get-PlaceholderSet -Text $entries[$key]) -join ","
    if ($expected -ne $actual) {
      throw "$($file.FullName) has placeholder mismatch in $key. Expected [$expected], got [$actual]."
    }
  }
}

if (Test-Path -LiteralPath $FactorioLocaleRoot) {
  $supported = @(Get-ChildItem -LiteralPath $FactorioLocaleRoot -Directory | Select-Object -ExpandProperty Name)
  $localeDirs = @(Get-ChildItem -LiteralPath $localeRootPath -Directory | Select-Object -ExpandProperty Name)
  $unsupported = @($localeDirs | Where-Object { $_ -notin $supported })
  if ($unsupported.Count -gt 0) {
    throw "Unsupported Factorio locale directories: $($unsupported -join ', ')"
  }

  $emptyLocaleDirs = @(
    Get-ChildItem -LiteralPath $localeRootPath -Directory |
      Where-Object { -not (Test-Path -LiteralPath (Join-Path $_.FullName "more-infinite-research.cfg")) } |
      Select-Object -ExpandProperty Name
  )
  if ($emptyLocaleDirs.Count -gt 0) {
    throw "Empty locale placeholder directories are not allowed: $($emptyLocaleDirs -join ', ')"
  }

  if (-not $AllowMissingSupportedLanguages) {
    $missingSupported = @($supported | Where-Object { $_ -notin $localeDirs })
    if ($missingSupported.Count -gt 0) {
      Write-Warning "Missing Factorio-supported locale directories: $($missingSupported -join ', ')"
    }
  }
}

Write-Host "[ok] validated $($files.Count) locale files against English fallback and Factorio locale rules."
