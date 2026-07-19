param(
  [string]$LocaleRoot = (Join-Path $PSScriptRoot "..\locale"),
  [string]$PolicyPath = (Join-Path $PSScriptRoot "..\.mir\locales\manifest.json"),
  [string]$FactorioLocaleRoot,
  [switch]$AllowMissingSupportedLanguages
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Import-Module (Join-Path $PSScriptRoot "localization\MIRLocalization.psm1") -Force

$policy = Read-MIRLocalePolicy -Path $PolicyPath
$localeRootPath = (Resolve-Path -LiteralPath $LocaleRoot).Path
$englishPath = Join-Path $localeRootPath "$($policy.source_locale)\$($policy.generated_file_name)"
if (-not (Test-Path -LiteralPath $englishPath)) {
  throw "English source locale is missing: $englishPath"
}
$english = Read-MIRLocaleFile -Path $englishPath

$expectedLocales = @($policy.supported_factorio_locales | ForEach-Object { [string]$_.code } | Sort-Object)
$localeDirs = @(Get-ChildItem -LiteralPath $localeRootPath -Directory | Select-Object -ExpandProperty Name | Sort-Object)
$missingLocales = @($expectedLocales | Where-Object { $_ -notin $localeDirs })
$extraLocales = @($localeDirs | Where-Object { $_ -notin $expectedLocales })
if ($missingLocales.Count -gt 0 -or $extraLocales.Count -gt 0) {
  throw "Locale directories do not match the governed Factorio set. Missing: $($missingLocales -join ', ') Extra: $($extraLocales -join ', ')"
}

if ([string]::IsNullOrWhiteSpace($FactorioLocaleRoot)) {
  $FactorioLocaleRoot = @(
    "D:\Programs\Factorio\2.1\data\base\locale",
    "D:\Programs\Factorio\2.0\data\base\locale",
    "C:\Program Files\Steam\steamapps\common\Factorio\data\base\locale"
  ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not [string]::IsNullOrWhiteSpace($FactorioLocaleRoot) -and (Test-Path -LiteralPath $FactorioLocaleRoot)) {
  $installed = @(Get-ChildItem -LiteralPath $FactorioLocaleRoot -Directory | Select-Object -ExpandProperty Name | Sort-Object)
  $missingFromPolicy = @($installed | Where-Object { $_ -notin $expectedLocales })
  $notInstalled = @($expectedLocales | Where-Object { $_ -notin $installed })
  if ($missingFromPolicy.Count -gt 0 -or $notInstalled.Count -gt 0) {
    $message = "Locale policy differs from installed Factorio locales at $FactorioLocaleRoot. Policy missing: $($missingFromPolicy -join ', ') Not installed: $($notInstalled -join ', ')"
    if ($AllowMissingSupportedLanguages) { Write-Warning $message } else { throw $message }
  }
}

$memoryRoot = Join-Path $repo ($policy.translation_memory_directory -replace '/', '\')
$validatedValues = 0
foreach ($locale in $expectedLocales) {
  $localePolicy = $policy.supported_factorio_locales | Where-Object { $_.code -eq $locale } | Select-Object -First 1
  $path = Join-Path $localeRootPath "$locale\$($policy.generated_file_name)"
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Governed locale file is missing: $path"
  }
  $document = Read-MIRLocaleFile -Path $path
  $missing = @($english.Entries.Keys | Where-Object { -not $document.Entries.Contains($_) })
  $extra = @($document.Entries.Keys | Where-Object { -not $english.Entries.Contains($_) })
  if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
    throw "$path does not match English keys. Missing: $($missing -join ', ') Extra: $($extra -join ', ')"
  }

  $memory = @{}
  if ($locale -ne $policy.source_locale) {
    $memoryPath = Join-Path $memoryRoot "$locale.json"
    if (-not (Test-Path -LiteralPath $memoryPath)) {
      throw "Translation memory is missing for ${locale}: $memoryPath"
    }
    $memoryDocument = Get-Content -Raw -LiteralPath $memoryPath -Encoding UTF8 | ConvertFrom-Json
    if ([int]$memoryDocument.schema -ne 1 -or $memoryDocument.locale -ne $locale -or $memoryDocument.source_locale -ne $policy.source_locale) {
      throw "$memoryPath has invalid schema or locale authority."
    }
    foreach ($entry in $memoryDocument.entries) {
      if ($memory.ContainsKey([string]$entry.key)) {
        throw "$memoryPath duplicates translation-memory key $($entry.key)."
      }
      $memory[[string]$entry.key] = $entry
    }
  }

  foreach ($key in $english.Entries.Keys) {
    $sourceText = [string]$english.Entries[$key]
    $translatedText = [string]$document.Entries[$key]
    $line = $document.LineNumbers[$key]
    if ($translatedText -match '[\x00-\x08\x0B\x0C\x0E-\x1F]' -or $translatedText.Contains([char]0xFFFD)) {
      throw "$path`:$line contains an invalid control or Unicode replacement character in $key."
    }
    if ($translatedText -match 'MIRP\d|⟦MIR|⟪MIR') {
      throw "$path`:$line contains an internal translation sentinel in $key."
    }
    $sourcePlaceholders = (Get-MIRPlaceholderSequence -Text $sourceText) -join "|"
    $translatedPlaceholders = (Get-MIRPlaceholderSequence -Text $translatedText) -join "|"
    if ($sourcePlaceholders -ne $translatedPlaceholders) {
      throw "$path`:$line has placeholder-order drift in $key."
    }
    $sourceFormatting = (Get-MIRFormattingSequence -Text $sourceText) -join "|"
    $translatedFormatting = (Get-MIRFormattingSequence -Text $translatedText) -join "|"
    if ($sourceFormatting -ne $translatedFormatting) {
      throw "$path`:$line has Factorio rich-text tag drift in $key."
    }
    $limit = Get-MIRSectionLengthLimit -FullKey $key -Policy $policy
    $length = Get-MIRVisibleTextLength -Text $translatedText
    if ($length -gt $limit) {
      throw "$path`:$line exceeds the $limit-character UI prose budget for $key (actual $length)."
    }

    if ($locale -ne $policy.source_locale) {
      if (-not $memory.ContainsKey($key)) {
        throw "Translation memory for $locale is missing $key."
      }
      $record = $memory[$key]
      $sourceHash = Get-MIRTextSha256 -Text $sourceText
      if ([string]$record.source_sha256 -ne $sourceHash) {
        throw "Translation memory for $locale is stale at $key. Expected source SHA-256 $sourceHash, got $($record.source_sha256)."
      }
      if ([string]$record.translation -cne $translatedText) {
        throw "$path`:$line differs from governed translation memory at $key."
      }
      if (-not (Test-MIRFormatInvariantValue -Text $sourceText) -and $translatedText -ceq $sourceText) {
        throw "$path`:$line copies untranslated English prose at $key."
      }
      foreach ($category in $policy.setting_categories) {
        if ($translatedText.Contains("]${category}:[/color]")) {
          throw "$path`:$line retains untranslated setting category '$category' in $key."
        }
      }
      if (
        $sourceText -match '[A-Za-z]{3,}' -and
        -not [string]::IsNullOrWhiteSpace([string]$localePolicy.required_script_pattern) -and
        $translatedText -notmatch [string]$localePolicy.required_script_pattern
      ) {
        throw "$path`:$line contains no expected $($localePolicy.name) script characters in translatable value $key."
      }
      if ([string]::IsNullOrWhiteSpace([string]$record.provenance)) {
        throw "Translation memory for $locale lacks provenance at $key."
      }
    }
    $validatedValues++
  }
  if ($locale -ne $policy.source_locale -and $memory.Count -ne $english.Entries.Count) {
    throw "Translation memory for $locale has $($memory.Count) entries; expected $($english.Entries.Count)."
  }
}

Write-Host "[ok] validated $($expectedLocales.Count) complete Factorio locales and $validatedValues values against source hashes, placeholders, rich text, prose budgets, and translation memories."
