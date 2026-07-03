param(
  [Parameter(Mandatory)][string]$GroupedFailures,
  [Parameter(Mandatory)][string]$GroupId,
  [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Read-MIRJsonFile {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Grouped failure file not found: $Path"
  }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function ConvertTo-MIRArray {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [array]) { return @($Value) }
  return @($Value)
}

function Get-MIRObjectProperty {
  param($Object, [string]$Name, $Default = "")
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function ConvertTo-MIRLuaString {
  param([string]$Value)
  if ($null -eq $Value) { $Value = "" }
  return '"' + (($Value -replace '\\', '\\') -replace '"', '\"') + '"'
}

function ConvertTo-MIRLuaPatternLiteral {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
  $escaped = $Value
  foreach ($character in @("%", "^", "$", "(", ")", ".", "[", "]", "*", "+", "-", "?")) {
    $escaped = $escaped.Replace($character, "%$character")
  }
  return "^$escaped$"
}

function ConvertTo-MIRSafeFileName {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return "unknown" }
  $invalid = [IO.Path]::GetInvalidFileNameChars()
  $safe = $Value
  foreach ($character in $invalid) {
    $safe = $safe.Replace([string]$character, "-")
  }
  return ($safe -replace "\s+", "-")
}

$resolvedGrouped = (Resolve-Path -LiteralPath $GroupedFailures).Path
$data = Read-MIRJsonFile -Path $resolvedGrouped
$groups = ConvertTo-MIRArray (Get-MIRObjectProperty $data "groups" @())
$group = $groups | Where-Object { (Get-MIRObjectProperty $_ "id") -eq $GroupId } | Select-Object -First 1
if ($null -eq $group) {
  throw "Failure group not found: $GroupId"
}

$kind = [string](Get-MIRObjectProperty $group "kind")
$mod = [string](Get-MIRObjectProperty $group "mod")
$scenario = [string](Get-MIRObjectProperty $group "scenario")
$stream = [string](Get-MIRObjectProperty $group "stream")
$recipe = [string](Get-MIRObjectProperty $group "recipe")
$reason = [string](Get-MIRObjectProperty $group "reason")
$evidence = [string](Get-MIRObjectProperty $group "evidence")

$ownerPatterns = @()
foreach ($candidate in @($evidence -split ",")) {
  $trimmed = $candidate.Trim()
  if ($trimmed -match "^[A-Za-z0-9_.-]+$") {
    $pattern = ConvertTo-MIRLuaPatternLiteral -Value $trimmed
    if ($pattern) { $ownerPatterns += $pattern }
  }
}
$ownerPatterns = @($ownerPatterns | Sort-Object -Unique)

if ([string]::IsNullOrWhiteSpace($mod)) {
  $mod = "review-required-mod"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $outputDir = Join-Path (Split-Path -Parent $resolvedGrouped) "profile-stubs"
  if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
  }
  $OutputPath = Join-Path $outputDir ("{0}-{1}.lua" -f $GroupId, (ConvertTo-MIRSafeFileName $mod))
} else {
  $parent = Split-Path -Parent $OutputPath
  if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
  }
}

$lines = @()
$lines += "-- Generated from MIR compatibility audit evidence."
$lines += "-- Review and refine this stub before enabling it in prototypes/compat/profiles.lua."
$lines += "-- Group: $GroupId"
$lines += "-- Kind: $kind"
$lines += ""
$lines += "return {"
$lines += "  [" + (ConvertTo-MIRLuaString $mod) + "] = {"
$lines += "    mode = " + (ConvertTo-MIRLuaString "review_required") + ","
$lines += "    evidence = {"
$lines += "      group_id = " + (ConvertTo-MIRLuaString $GroupId) + ","
$lines += "      kind = " + (ConvertTo-MIRLuaString $kind) + ","
$lines += "      scenario = " + (ConvertTo-MIRLuaString $scenario) + ","
$lines += "      stream = " + (ConvertTo-MIRLuaString $stream) + ","
$lines += "      recipe = " + (ConvertTo-MIRLuaString $recipe) + ","
$lines += "      reason = " + (ConvertTo-MIRLuaString $reason) + ","
$lines += "      evidence = " + (ConvertTo-MIRLuaString $evidence) + ","
$lines += "    },"
$lines += "    known_competing_productivity = {"
$lines += "      require_review = true,"
$lines += "      tech_patterns = {"
if ($ownerPatterns.Count -eq 0) {
  $lines += "        -- Add anchored candidate technology patterns after reviewing the audit evidence."
} else {
  foreach ($pattern in $ownerPatterns) {
    $lines += "        " + (ConvertTo-MIRLuaString $pattern) + ","
  }
}
$lines += "      },"
$lines += "    },"
$lines += "  },"
$lines += "}"

$lines -join "`n" | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "[compat-profile-stub] wrote $OutputPath"
