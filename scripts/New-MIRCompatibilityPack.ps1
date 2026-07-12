param(
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9._-]*$')][string]$Id,
  [Parameter(Mandatory)][string]$ModId,
  [string]$Version = "*",
  [ValidateSet("2.0", "2.1")][string[]]$FactorioLines = @("2.1"),
  [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
if (Test-Path -LiteralPath $OutputPath) { throw "Refusing to overwrite existing compatibility-pack scaffold: $OutputPath" }

$pack = [ordered]@{
  schema = 2
  id = $Id
  applicability = [ordered]@{ mods = @([ordered]@{ id = $ModId; version = $Version }) }
  aliases = [ordered]@{}
  exact = [ordered]@{ includes = @(); excludes = @() }
  family_hints = @()
  science_roles = @()
  owner_claims = [ordered]@{}
  risk_overrides = @()
  targets = [ordered]@{ factorio_lines = @($FactorioLines | Sort-Object -Unique) }
  evidence = [ordered]@{ fixtures = @(); real_mod = @() }
  claim = [ordered]@{ level = "diagnostic-only"; public = $false }
  review = [ordered]@{ required = $true; status = "scaffold" }
}
$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$pack | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "[ok] wrote review-required CompatibilityPack scaffold $OutputPath"
