param(
  [Parameter(Mandatory)][string]$AuditDir,
  [string]$OutputDir = $AuditDir,
  [string]$ExpectedFailures = (Join-Path $PSScriptRoot "..\validation\assertions\expected-failures.json")
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/compatibility/Convert-MIRCompatAuditResults.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE