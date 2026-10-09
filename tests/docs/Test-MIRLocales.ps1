# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$LocaleRoot = (Join-Path $PSScriptRoot "..\..\source\locale"),
  [string]$PolicyPath = (Join-Path $PSScriptRoot "..\..\.mir\locales\manifest.json"),
  [string]$FactorioLocaleRoot,
  [switch]$AllowMissingSupportedLanguages
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath (Join-Path $MirLegacyScriptRoot "..")).Path
Import-Module (Join-Path $MirLegacyScriptRoot "localization\MIRLocalization.psm1") -Force
if (-not (Test-MIRFormatInvariantValue -Text '__1__ × __2__') -or
    -not (Test-MIRFormatInvariantValue -Text 'Factorio  __1__\nMIR  __2__') -or
    (Test-MIRFormatInvariantValue -Text '__1__ amount __2__') -or
    (Test-MIRFormatInvariantValue -Text '__1__ × science __2__') -or
    (Test-MIRFormatInvariantValue -Text 'Factorio version __1__\nMIR __2__')) { throw '[mir-locales-quantity-format-boundary]' }
$canonicalFixture = Join-Path $repo ('build/tmp/mir-locale-lf-' + [guid]::NewGuid().ToString('N') + '.cfg')
try {
  Write-MIRLocaleFile -Template ([pscustomobject]@{Sections=@('test');SectionKeys=@{test=@('value')}}) -Values ([ordered]@{'test.value'='localized'}) -Path $canonicalFixture
  $canonicalBytes=[IO.File]::ReadAllBytes($canonicalFixture)
  if ($canonicalBytes -contains 13 -or $canonicalBytes[-1] -ne 10 -or $canonicalBytes[0] -ne 91) { throw '[mir-locales-canonical-lf-bytes]' }
} finally { if (Test-Path -LiteralPath $canonicalFixture -PathType Leaf) { Remove-Item -LiteralPath $canonicalFixture } }

# Exercise the consumed generator's preservation rule without executing its
# network translation or source-writing body.
$selectionTokens = $null; $selectionErrors = $null
$selectionAst = [Management.Automation.Language.Parser]::ParseFile(
  (Join-Path $repo 'tools/commands/localization/Update-MIRLocales.ps1'),
  [ref]$selectionTokens, [ref]$selectionErrors)
if ($selectionErrors.Count -gt 0) { throw '[mir-locales-selection-generator-parse]' }
$preservationFunction = @($selectionAst.FindAll({param($node)
  $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-MIRPreservedLocaleRecord'
}, $true))
if ($preservationFunction.Count -ne 1) { throw '[mir-locales-selection-generator-function]' }
. ([scriptblock]::Create($preservationFunction[0].Extent.Text))
$selectionMemory = @{kept = [pscustomobject]@{source_sha256='SOURCE';translation='retained';provenance='preexisting'}}
$selectionExisting = [pscustomobject]@{Entries=[ordered]@{kept='retained'}}
$preservedRecord = Get-MIRPreservedLocaleRecord -Key kept -SourceHash SOURCE -MemoryByKey $selectionMemory -Existing $selectionExisting
if ($preservedRecord.translation -cne 'retained' -or $preservedRecord.provenance -cne 'preexisting') { throw '[mir-locales-selection-preserved-record]' }
foreach ($opposing in @(
  @{key='absent';hash='SOURCE';existing=$selectionExisting},
  @{key='kept';hash='CHANGED';existing=$selectionExisting},
  @{key='kept';hash='SOURCE';existing=$null},
  @{key='kept';hash='SOURCE';existing=[pscustomobject]@{Entries=[ordered]@{kept='changed'}}}
)) {
  $rejected=$false
  try { $null=Get-MIRPreservedLocaleRecord -Key $opposing.key -SourceHash $opposing.hash -MemoryByKey $selectionMemory -Existing $opposing.existing }
  catch { $rejected=$true }
  if (-not $rejected) { throw '[mir-locales-selection-opposing-case]' }
}

function Get-MIRTechnicalLiteralSequence {
  param([string]$Text)
  $pattern = '(?<![\p{L}\p{M}\p{N}_./\\-])script-output/more-infinite-research/settings/browser-profile\.txt(?![\p{L}\p{M}\p{N}_/\\-]|[.][\p{L}\p{M}\p{N}_-])|(?<![\p{L}\p{M}\p{N}_])MIRSET1(?![\p{L}\p{M}\p{N}_])'
  return @([regex]::Matches($Text, $pattern) | ForEach-Object { $_.Value })
}

function Test-MIRTranslationMarkersAbsent {
  param([string]$Text)

  # A translation service can transliterate the internal "MIR" label.  The
  # delimiter glyphs themselves are therefore the stable rejection boundary.
  return $Text -notmatch 'MIRP\d|⟦|⟧|⟪|⟫'
}

# Keep these probes local to the canonical validator.  They specifically cover
# the transliterated Serbian form which an ASCII-only `MIR` pattern misses.
if (Test-MIRTranslationMarkersAbsent -Text '⟦МИР0001⟧ leaked batch marker') {
  throw '[mir-locales-transliterated-marker-regression]'
}
$technicalProbe = 'script-output/more-infinite-research/settings/browser-profile.txt MIRSET1'
$technicalDriftProbe = 'script-output/more-infinite-research/settings/browser-profile.txt МИРСЕТ1'
if (((Get-MIRTechnicalLiteralSequence -Text $technicalProbe) -join '|') -eq ((Get-MIRTechnicalLiteralSequence -Text $technicalDriftProbe) -join '|')) {
  throw '[mir-locales-technical-literal-regression]'
}
$technicalTokenExtensionProbe = 'script-output/more-infinite-research/settings/browser-profile.txt MIRSET1X'
$technicalPathExtensionProbe = 'script-output/more-infinite-research/settings/browser-profile.txt.bak MIRSET1'
foreach ($invalidProbe in @($technicalTokenExtensionProbe, $technicalPathExtensionProbe)) {
  if (((Get-MIRTechnicalLiteralSequence -Text $technicalProbe) -join '|') -eq ((Get-MIRTechnicalLiteralSequence -Text $invalidProbe) -join '|')) {
    throw '[mir-locales-technical-literal-extension-regression]'
  }
}
$technicalPunctuationProbe = 'script-output/more-infinite-research/settings/browser-profile.txt. MIRSET1.'
if (((Get-MIRTechnicalLiteralSequence -Text $technicalProbe) -join '|') -ne ((Get-MIRTechnicalLiteralSequence -Text $technicalPunctuationProbe) -join '|')) {
  throw '[mir-locales-technical-literal-punctuation-regression]'
}

# Execute the generator's actual reuse decision. A generated translation with
# known stale provenance must never be rebound to the changed English hash.
foreach ($functionName in @('Test-MIRReusablePreexistingTranslation','Test-MIRTranslationStructure','Get-MIRReusableLocaleRecord')) {
  $function = @($selectionAst.FindAll({param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName
  }, $true))
  if ($function.Count -ne 1) { throw "[mir-locales-generator-function:$functionName]" }
  . ([scriptblock]::Create($function[0].Extent.Text))
}
$reuseArguments = @{SourceText='Use base icons __1__';SourceHash='CURRENT';ExistingTranslation='Utiliser les icônes __1__'}
$currentMemory = [pscustomobject]@{source_sha256='CURRENT';translation='Utiliser les icônes __1__';provenance='machine-assisted'}
$reused = Get-MIRReusableLocaleRecord @reuseArguments -MemoryRecord $currentMemory
if ($null -eq $reused -or $reused.provenance -cne 'machine-assisted' -or $reused.source_sha256 -cne 'CURRENT') { throw '[mir-locales-current-memory-reuse]' }
$bootstrap = Get-MIRReusableLocaleRecord @reuseArguments
if ($null -eq $bootstrap -or $bootstrap.provenance -cne 'preexisting') { throw '[mir-locales-untracked-translation-bootstrap]' }
foreach ($opposing in @(
  @{MemoryRecord=[pscustomobject]@{source_sha256='OLD';translation=$currentMemory.translation;provenance='machine-assisted'}},
  @{MemoryRecord=[pscustomobject]@{source_sha256='CURRENT';translation='Utiliser les icônes __2__';provenance='machine-assisted'}},
  @{MemoryRecord=$currentMemory;Refresh=$true},
  @{Refresh=$true}
)) {
  if ($null -ne (Get-MIRReusableLocaleRecord @reuseArguments @opposing)) { throw '[mir-locales-stale-or-refresh-reused-generated-prose]' }
}

$canonicalJsonProbeRoot = Join-Path $repo ('build/tests/locales/canonical-json-' + [guid]::NewGuid().ToString('N'))
$canonicalJsonProbePath = Join-Path $canonicalJsonProbeRoot 'probe.json'
New-Item -ItemType Directory -Force -Path $canonicalJsonProbeRoot | Out-Null
try {
  $canonicalJsonProbe = [ordered]@{schema=1;values=@('alpha','beta');nested=[ordered]@{enabled=$true}}
  Write-MIRCanonicalJson -Value $canonicalJsonProbe -Path $canonicalJsonProbePath
  $firstCanonicalBytes = [IO.File]::ReadAllBytes($canonicalJsonProbePath)
  if ($firstCanonicalBytes.Length -lt 2 -or $firstCanonicalBytes[0] -eq 0xEF -or $firstCanonicalBytes -contains 0x0D -or $firstCanonicalBytes[-1] -ne 0x0A) {
    throw '[mir-locales-canonical-json-bytes]'
  }
  Write-MIRCanonicalJson -Value $canonicalJsonProbe -Path $canonicalJsonProbePath
  $secondCanonicalBytes = [IO.File]::ReadAllBytes($canonicalJsonProbePath)
  if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$firstCanonicalBytes,[byte[]]$secondCanonicalBytes)) {
    throw '[mir-locales-canonical-json-idempotence]'
  }
  $canonicalJsonProbeRoundTrip = [Text.UTF8Encoding]::new($false).GetString($secondCanonicalBytes) | ConvertFrom-Json -Depth 100
  if ([int]$canonicalJsonProbeRoundTrip.schema -ne 1 -or @($canonicalJsonProbeRoundTrip.values).Count -ne 2 -or -not [bool]$canonicalJsonProbeRoundTrip.nested.enabled) {
    throw '[mir-locales-canonical-json-round-trip]'
  }
} finally {
  if (Test-Path -LiteralPath $canonicalJsonProbePath -PathType Leaf) { Remove-Item -LiteralPath $canonicalJsonProbePath -Force }
  if (Test-Path -LiteralPath $canonicalJsonProbeRoot -PathType Container) { Remove-Item -LiteralPath $canonicalJsonProbeRoot -Force }
}

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
    if (-not (Test-MIRTranslationMarkersAbsent -Text $translatedText)) {
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
    $sourceLiterals = (Get-MIRTechnicalLiteralSequence -Text $sourceText) -join '|'
    $translatedLiterals = (Get-MIRTechnicalLiteralSequence -Text $translatedText) -join '|'
    if ($sourceLiterals -ne $translatedLiterals) {
      throw "$path`:$line has technical-literal drift in $key."
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
        -not (Test-MIRFormatInvariantValue -Text $sourceText) -and
        $null -ne $localePolicy.PSObject.Properties['required_script_pattern'] -and
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
