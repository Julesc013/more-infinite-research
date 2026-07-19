param(
  [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$PolicyPath,
  [switch]$MachineTranslateMissing,
  [switch]$RefreshMachineTranslations
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
  $PolicyPath = Join-Path $repo ".mir\locales\manifest.json"
}

Import-Module (Join-Path $repo "scripts\localization\MIRLocalization.psm1") -Force
$policy = Read-MIRLocalePolicy -Path $PolicyPath
$sourcePath = Join-Path $repo ($policy.source_file -replace '/', '\')
$source = Read-MIRLocaleFile -Path $sourcePath
$memoryRoot = Join-Path $repo ($policy.translation_memory_directory -replace '/', '\')
$overridePath = Join-Path $repo ($policy.translation_overrides -replace '/', '\')
$overrideDocument = Get-Content -Raw -LiteralPath $overridePath -Encoding UTF8 | ConvertFrom-Json
$overridesByLocale = ConvertTo-MIRPropertyMap -Object $overrideDocument.locales

function Protect-MIRTranslationSyntax {
  param([string]$Text, [int]$EntryIndex)
  $tokens = [ordered]@{}
  $counter = [pscustomobject]@{ Value = 0 }
  $protected = [regex]::Replace($Text, '__\d+__|\[[^\]]+\]', {
    param($match)
    $token = "⟪MIRP$('{0:D4}' -f $EntryIndex)$('{0:D2}' -f $counter.Value)⟫"
    $counter.Value++
    $tokens[$token] = $match.Value
    return $token
  })
  return [pscustomobject]@{ Text = $protected; Tokens = $tokens }
}

function Restore-MIRTranslationSyntax {
  param([string]$Text, [System.Collections.IDictionary]$Tokens)
  $restored = $Text
  foreach ($token in $Tokens.Keys) {
    $restored = $restored.Replace([string]$token, [string]$Tokens[$token])
  }
  return $restored
}

function Test-MIRReusablePreexistingTranslation {
  param([string]$SourceText, [string]$Translation)

  if ($Translation -ceq $SourceText) { return $false }
  $sourcePlaceholders = (Get-MIRPlaceholderSequence -Text $SourceText) -join '|'
  $translationPlaceholders = (Get-MIRPlaceholderSequence -Text $Translation) -join '|'
  if ($sourcePlaceholders -ne $translationPlaceholders) { return $false }
  $sourceFormatting = (Get-MIRFormattingSequence -Text $SourceText) -join '|'
  $translationFormatting = (Get-MIRFormattingSequence -Text $Translation) -join '|'
  if ($sourceFormatting -ne $translationFormatting) { return $false }

  $sourceWords = @([regex]::Matches($SourceText.ToLowerInvariant(), '[a-z]{3,}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
  $translationWords = @([regex]::Matches($Translation.ToLowerInvariant(), '[a-z]{3,}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
  if ($sourceWords.Count -gt 0 -and $translationWords.Count -gt 0) {
    $common = @($translationWords | Where-Object { $_ -in $sourceWords }).Count
    $overlap = $common / [Math]::Min($sourceWords.Count, $translationWords.Count)
    if ($overlap -ge 0.72) { return $false }
  }
  return $true
}

function Test-MIRTranslationStructure {
  param([string]$SourceText, [string]$Translation)
  if ([string]::IsNullOrWhiteSpace($Translation)) { return $false }
  if ($Translation -match 'MIRP\d|⟦MIR|⟪MIR') { return $false }
  $sourcePlaceholders = (Get-MIRPlaceholderSequence -Text $SourceText) -join '|'
  $translationPlaceholders = (Get-MIRPlaceholderSequence -Text $Translation) -join '|'
  if ($sourcePlaceholders -ne $translationPlaceholders) { return $false }
  $sourceFormatting = (Get-MIRFormattingSequence -Text $SourceText) -join '|'
  $translationFormatting = (Get-MIRFormattingSequence -Text $Translation) -join '|'
  return $sourceFormatting -eq $translationFormatting
}

function Invoke-MIRRawMachineTranslation {
  param([string]$Text, [string]$TargetLanguage)
  $query = [uri]::EscapeDataString($Text)
  $uri = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=$TargetLanguage&dt=t&q=$query"
  for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
      $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 45
      return (($response[0] | ForEach-Object { $_[0] }) -join '').Trim()
    }
    catch {
      if ($attempt -eq 5) { throw }
      Start-Sleep -Seconds ([Math]::Min(8, [Math]::Pow(2, $attempt)))
    }
  }
}

function Invoke-MIRStructureSafeTranslation {
  param([string]$SourceText, [string]$TargetLanguage)
  $parts = [regex]::Split($SourceText, '(__\d+__|\[[^\]]+\])')
  $output = [System.Text.StringBuilder]::new()
  foreach ($part in $parts) {
    if ([string]::IsNullOrEmpty($part)) { continue }
    if ($part -match '^__\d+__$|^\[[^\]]+\]$') {
      [void]$output.Append($part)
      continue
    }
    if ($part -match '^(?<leading>\s*)(?<core>.*?)(?<trailing>\s*)$') {
      $core = $matches['core']
      [void]$output.Append($matches['leading'])
      if (-not [string]::IsNullOrWhiteSpace($core)) {
        [void]$output.Append((Invoke-MIRRawMachineTranslation -Text $core -TargetLanguage $TargetLanguage))
      }
      [void]$output.Append($matches['trailing'])
    }
  }
  return $output.ToString()
}

function Set-MIRLocalizedCategoryLabels {
  param([string]$Text, [System.Collections.IDictionary]$Labels)
  $normalized = $Text
  foreach ($category in $Labels.Keys) {
    $replacement = [string]$Labels[$category]
    $normalized = $normalized.Replace("]${category}:[/color]", "]${replacement}:[/color]")
  }
  return $normalized
}

function Invoke-MIRMachineTranslationBatch {
  param([array]$Items, [string]$TargetLanguage)

  $lines = [System.Collections.Generic.List[string]]::new()
  $syntax = @{}
  foreach ($item in $Items) {
    $protected = Protect-MIRTranslationSyntax -Text $item.Source -EntryIndex $item.Index
    $syntax[$item.Index] = $protected.Tokens
    $lines.Add("⟦MIR$('{0:D4}' -f $item.Index)⟧ $($protected.Text)")
  }

  $query = [uri]::EscapeDataString(($lines -join "`n"))
  $uri = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=$TargetLanguage&dt=t&q=$query"
  $response = $null
  for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
      $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 45
      break
    }
    catch {
      if ($attempt -eq 5) { throw }
      Start-Sleep -Seconds ([Math]::Min(8, [Math]::Pow(2, $attempt)))
    }
  }

  $translatedBlock = ($response[0] | ForEach-Object { $_[0] }) -join ''
  $result = @{}
  $pattern = '(?ms)^⟦MIR(?<index>\d{4})⟧\s*(?<text>.*?)(?=^⟦MIR\d{4}⟧|\z)'
  foreach ($match in [regex]::Matches($translatedBlock, $pattern)) {
    $index = [int]$match.Groups['index'].Value
    $text = $match.Groups['text'].Value.Trim()
    $result[$index] = Restore-MIRTranslationSyntax -Text $text -Tokens $syntax[$index]
  }
  if ($result.Count -ne $Items.Count) {
    if ($Items.Count -gt 1) {
      $middle = [int][Math]::Floor($Items.Count / 2)
      $left = Invoke-MIRMachineTranslationBatch -Items @($Items[0..($middle - 1)]) -TargetLanguage $TargetLanguage
      $right = Invoke-MIRMachineTranslationBatch -Items @($Items[$middle..($Items.Count - 1)]) -TargetLanguage $TargetLanguage
      foreach ($key in $left.Keys) { $result[$key] = $left[$key] }
      foreach ($key in $right.Keys) { $result[$key] = $right[$key] }
      return $result
    }
    $only = $Items[0]
    $text = [regex]::Replace($translatedBlock, '^\s*⟦?MIR\d{4}⟧?\s*', '').Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
      throw "Translation service returned no usable value for $($only.Key) in $TargetLanguage."
    }
    $result[$only.Index] = Restore-MIRTranslationSyntax -Text $text -Tokens $syntax[$only.Index]
  }
  return $result
}

function Invoke-MIRMachineTranslation {
  param([array]$Items, [string]$TargetLanguage)
  $result = @{}
  $batch = [System.Collections.Generic.List[object]]::new()
  $batchChars = 0
  foreach ($item in $Items) {
    $cost = $item.Source.Length + 20
    if ($batch.Count -gt 0 -and ($batchChars + $cost) -gt 2800) {
      $translated = Invoke-MIRMachineTranslationBatch -Items @($batch) -TargetLanguage $TargetLanguage
      foreach ($key in $translated.Keys) { $result[$key] = $translated[$key] }
      $batch.Clear()
      $batchChars = 0
      Start-Sleep -Milliseconds 100
    }
    $batch.Add($item)
    $batchChars += $cost
  }
  if ($batch.Count -gt 0) {
    $translated = Invoke-MIRMachineTranslationBatch -Items @($batch) -TargetLanguage $TargetLanguage
    foreach ($key in $translated.Keys) { $result[$key] = $translated[$key] }
  }
  return $result
}

$categoryPath = Join-Path $repo ($policy.category_labels -replace '/', '\')
if (-not (Test-Path -LiteralPath $categoryPath)) {
  if (-not $MachineTranslateMissing) {
    throw "Locale category-label catalog is missing: $categoryPath. Re-run with -MachineTranslateMissing to create it."
  }
  $categoryLocales = [ordered]@{}
  foreach ($locale in $policy.supported_factorio_locales) {
    if ($locale.code -eq $policy.source_locale) { continue }
    Write-Host "[translate] $($locale.code): drafting standard setting-category labels..."
    $labels = [ordered]@{}
    foreach ($category in $policy.setting_categories) {
      $labels[[string]$category] = Invoke-MIRRawMachineTranslation -Text ([string]$category) -TargetLanguage ([string]$locale.translation_code)
    }
    $categoryLocales[[string]$locale.code] = $labels
  }
  [ordered]@{schema=1;source_locale=[string]$policy.source_locale;locales=$categoryLocales} |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $categoryPath -Encoding utf8
}
$categoryDocument = Get-Content -Raw -LiteralPath $categoryPath -Encoding UTF8 | ConvertFrom-Json
$categoryByLocale = ConvertTo-MIRPropertyMap -Object $categoryDocument.locales

if (-not (Test-Path -LiteralPath $memoryRoot)) {
  New-Item -ItemType Directory -Path $memoryRoot -Force | Out-Null
}

foreach ($locale in $policy.supported_factorio_locales) {
  $code = [string]$locale.code
  if ($code -eq $policy.source_locale) { continue }

  $outputPath = Join-Path $repo "locale\$code\$($policy.generated_file_name)"
  $memoryPath = Join-Path $memoryRoot "$code.json"
  $existing = $null
  if (Test-Path -LiteralPath $outputPath) {
    $existing = Read-MIRLocaleFile -Path $outputPath
  }

  $memoryByKey = @{}
  if ((Test-Path -LiteralPath $memoryPath) -and -not $RefreshMachineTranslations) {
    $memory = Get-Content -Raw -LiteralPath $memoryPath -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in $memory.entries) { $memoryByKey[$entry.key] = $entry }
  }
  $localeOverrides = @{}
  if ($overridesByLocale.ContainsKey($code)) {
    $localeOverrides = ConvertTo-MIRPropertyMap -Object $overridesByLocale[$code]
  }
  if (-not $categoryByLocale.ContainsKey($code)) {
    throw "Locale category-label catalog is missing $code."
  }
  $categoryLabels = ConvertTo-MIRPropertyMap -Object $categoryByLocale[$code]

  $records = [ordered]@{}
  $missing = [System.Collections.Generic.List[object]]::new()
  $index = 0
  foreach ($key in $source.Entries.Keys) {
    $sourceText = [string]$source.Entries[$key]
    $sourceHash = Get-MIRTextSha256 -Text $sourceText
    if ($localeOverrides.ContainsKey($key)) {
      $override = [string]$localeOverrides[$key]
      if (-not (Test-MIRTranslationStructure -SourceText $sourceText -Translation $override)) {
        throw "Governed translation override for ${code}.$key violates protected syntax."
      }
      $records[$key] = [pscustomobject]@{source_sha256=$sourceHash;translation=$override;provenance='maintainer-override'}
    }
    elseif (Test-MIRFormatInvariantValue -Text $sourceText) {
      $records[$key] = [pscustomobject]@{source_sha256=$sourceHash;translation=$sourceText;provenance='format-invariant'}
    }
    elseif (
      $memoryByKey.ContainsKey($key) -and
      $memoryByKey[$key].source_sha256 -eq $sourceHash -and
      (Test-MIRTranslationStructure -SourceText $sourceText -Translation ([string]$memoryByKey[$key].translation)) -and
      (
        $memoryByKey[$key].provenance -ne 'preexisting' -or
        (Test-MIRReusablePreexistingTranslation -SourceText $sourceText -Translation ([string]$memoryByKey[$key].translation))
      )
    ) {
      $records[$key] = [pscustomobject]@{source_sha256=$sourceHash;translation=[string]$memoryByKey[$key].translation;provenance=[string]$memoryByKey[$key].provenance}
    }
    elseif (
      $null -ne $existing -and
      $existing.Entries.Contains($key) -and
      (Test-MIRReusablePreexistingTranslation -SourceText $sourceText -Translation ([string]$existing.Entries[$key])
    )) {
      $records[$key] = [pscustomobject]@{source_sha256=$sourceHash;translation=[string]$existing.Entries[$key];provenance='preexisting'}
    }
    else {
      $missing.Add([pscustomobject]@{Index=$index;Key=$key;Source=$sourceText;SourceHash=$sourceHash})
    }
    $index++
  }

  if ($missing.Count -gt 0) {
    if (-not $MachineTranslateMissing) {
      throw "${code} has $($missing.Count) missing or stale translations. Re-run with -MachineTranslateMissing to draft them."
    }
    Write-Host "[translate] ${code}: drafting $($missing.Count) values..."
    $translated = Invoke-MIRMachineTranslation -Items @($missing) -TargetLanguage ([string]$locale.translation_code)
    foreach ($item in $missing) {
      $translation = [string]$translated[$item.Index]
      if (-not (Test-MIRTranslationStructure -SourceText $item.Source -Translation $translation)) {
        Write-Host "[repair] ${code}: reconstructing protected syntax for $($item.Key)..."
        $translation = Invoke-MIRStructureSafeTranslation -SourceText $item.Source -TargetLanguage ([string]$locale.translation_code)
      }
      if (-not (Test-MIRTranslationStructure -SourceText $item.Source -Translation $translation)) {
        throw "Machine translation for ${code}.$($item.Key) still violates protected syntax after reconstruction."
      }
      $records[$item.Key] = [pscustomobject]@{source_sha256=$item.SourceHash;translation=$translation;provenance='machine-assisted'}
    }
  }

  $orderedRecords = [System.Collections.Generic.List[object]]::new()
  $values = [ordered]@{}
  foreach ($key in $source.Entries.Keys) {
    $record = $records[$key]
    $normalizedTranslation = Set-MIRLocalizedCategoryLabels -Text ([string]$record.translation) -Labels $categoryLabels
    $normalizedProvenance = [string]$record.provenance
    if ($normalizedTranslation -cne [string]$record.translation) {
      $normalizedProvenance = "$normalizedProvenance+terminology"
    }
    $orderedRecords.Add([ordered]@{
      key = $key
      source_sha256 = $record.source_sha256
      translation = $normalizedTranslation
      provenance = $normalizedProvenance
    })
    $values[$key] = $normalizedTranslation
  }

  $memoryDocument = [ordered]@{
    schema = 1
    locale = $code
    language = [string]$locale.name
    source_locale = [string]$policy.source_locale
    entries = @($orderedRecords)
  }
  $memoryDocument | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $memoryPath -Encoding utf8
  Write-MIRLocaleFile -Template $source -Values $values -Path $outputPath
  Write-Host "[ok] ${code}: generated $($values.Count) values."
}

Write-Host "[ok] synchronized all governed MIR locale files and translation memories."
