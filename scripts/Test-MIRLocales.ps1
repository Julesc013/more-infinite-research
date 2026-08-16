param(
  [string]$LocaleRoot = (Join-Path $PSScriptRoot "..\locale"),
  [string]$PolicyPath = (Join-Path $PSScriptRoot "..\.mir\locales\manifest.json"),
  [string]$FactorioLocaleRoot,
  [switch]$AllowMissingSupportedLanguages
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../validation/tests/docs/Test-MIRLocales.ps1"
& $canonicalTest @PSBoundParameters