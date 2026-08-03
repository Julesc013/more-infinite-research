param(
  [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$PolicyPath,
  [switch]$MachineTranslateMissing,
  [switch]$RefreshMachineTranslations
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/localization/Update-MIRLocales.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE