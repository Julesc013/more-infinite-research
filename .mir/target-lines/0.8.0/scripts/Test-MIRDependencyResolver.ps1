param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
. (Join-Path $RepoRoot "scripts\MIRCompatAudit\ModPortal.ps1")

$cases = @(
  @{ raw = "base >= 2.1.0"; name = "base"; kind = "required"; required = $true },
  @{ raw = "Flare Stack >= 4.0.0"; name = "Flare Stack"; kind = "required"; required = $true },
  @{ raw = "(?) PlutoniumEnergy"; name = "PlutoniumEnergy"; kind = "hidden_optional"; required = $false },
  @{ raw = "+ Space Exploration >= 0.6.0"; name = "Space Exploration"; kind = "recommended"; required = $false },
  @{ raw = "~ no-order helper"; name = "no-order helper"; kind = "no_order"; required = $true },
  @{ raw = "! incompatible mod <= 2.0.0"; name = "incompatible mod"; kind = "incompatible"; required = $false }
)

foreach ($case in $cases) {
  $actual = ConvertFrom-MIRDependencyString -Dependency $case.raw
  if ($actual.name -ne $case.name -or $actual.kind -ne $case.kind -or $actual.required -ne $case.required) {
    throw "Dependency parse mismatch for '$($case.raw)': name='$($actual.name)' kind='$($actual.kind)' required='$($actual.required)'."
  }
}

Write-Host "[ok] MIR dependency declarations preserve mod names with spaces."
