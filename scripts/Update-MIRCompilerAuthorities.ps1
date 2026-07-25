param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")),
  [switch]$Check
)

$ErrorActionPreference = "Stop"

function ConvertTo-MIRLuaString([string]$Value) {
  return '"' + $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n') + '"'
}

function ConvertTo-MIRLuaLiteral($Value, [int]$Indent = 0) {
  if ($null -eq $Value) { return "nil" }
  if ($Value -is [bool]) { return $(if ($Value) { "true" } else { "false" }) }
  if ($Value -is [string]) { return ConvertTo-MIRLuaString $Value }
  if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or
      $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
    return [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
  }
  $padding = "  " * $Indent
  $childPadding = "  " * ($Indent + 1)
  if ($Value -is [Collections.IDictionary] -or $Value -is [pscustomobject]) {
    $properties = if ($Value -is [Collections.IDictionary]) {
      @($Value.Keys | ForEach-Object { [pscustomobject]@{Name=[string]$_; Value=$Value[$_]} })
    } else {
      @($Value.PSObject.Properties | ForEach-Object { [pscustomobject]@{Name=$_.Name; Value=$_.Value} })
    }
    $properties = @($properties | Sort-Object Name)
    if ($properties.Count -eq 0) { return "{}" }
    $rows = foreach ($property in $properties) {
      $key = if ($property.Name -match '^[A-Za-z_][A-Za-z0-9_]*$') { $property.Name }
        else { '[' + (ConvertTo-MIRLuaString $property.Name) + ']' }
      $childPadding + $key + ' = ' + (ConvertTo-MIRLuaLiteral $property.Value ($Indent + 1))
    }
    return "{`n" + ($rows -join ",`n") + "`n$padding}"
  }
  if ($Value -is [Collections.IEnumerable]) {
    $items = @($Value)
    if ($items.Count -eq 0) { return "{}" }
    $rows = @($items | ForEach-Object { $childPadding + (ConvertTo-MIRLuaLiteral $_ ($Indent + 1)) })
    return "{`n" + ($rows -join ",`n") + "`n$padding}"
  }
  throw "Unsupported generated Lua value type: $($Value.GetType().FullName)"
}

function Set-MIRGeneratedLua([string]$RelativePath, [string]$Source, $Value) {
  $path = Join-Path $RepoRoot $RelativePath
  $content = "-- Generated from $Source. Do not edit by hand.`nreturn " + (ConvertTo-MIRLuaLiteral $Value) + "`n"
  if ($Check) {
    if (-not (Test-Path -LiteralPath $path) -or (Get-Content -Raw -LiteralPath $path).Replace("`r`n", "`n") -ne $content) {
      throw "Generated compiler authority differs: $RelativePath"
    }
    return
  }
  Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline
}

$effectSource = ".mir/technology-effect-targets.json"
$effectProfile = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $effectSource) | ConvertFrom-Json
$contracts = [ordered]@{}
foreach ($modifier in @($effectProfile.target_bearing_modifiers | Sort-Object type)) {
  $identityFields = @("type") + @($modifier.targets | ForEach-Object { [string]$_.field })
  $contracts[[string]$modifier.type] = [ordered]@{
    identity_fields = $identityFields
    targets = @($modifier.targets)
  }
}
Set-MIRGeneratedLua "prototypes/mir/domain/effects/generated_target_contracts.lua" $effectSource ([ordered]@{
  schema = [int]$effectProfile.schema
  factorio_target = [string]$effectProfile.factorio_target
  factorio_api_version = [string]$effectProfile.factorio_api_version
  contracts = $contracts
})

$gateSource = ".mir/technology-hard-gates.json"
$gateProfile = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $gateSource) | ConvertFrom-Json
Set-MIRGeneratedLua "prototypes/mir/domain/technology/generated_hard_gate_authority.lua" $gateSource $gateProfile

$qualitySource = ".mir/technology-quality-profiles.json"
$qualityProfiles = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $qualitySource) | ConvertFrom-Json
if ([int]$qualityProfiles.schema -ne 2 -or [string]$qualityProfiles.authority -ne "mir-technology-quality-profiles-v2") {
  throw "Technology quality profile authority schema is invalid."
}
$requiredProfiles = @(
  "existing-stream-attachment-v1", "native-owner-patch-v1", "base-continuation-v1",
  "new-machine-manufacturing-v1", "new-lab-manufacturing-v1", "exact-overhaul-material-v1",
  "process-family-experimental-v1"
)
$profileIds = @($qualityProfiles.profiles | ForEach-Object { [string]$_.profile_id })
if (@($profileIds | Sort-Object -Unique).Count -ne $requiredProfiles.Count) {
  throw "Technology quality profile ids are missing or duplicated."
}
foreach ($profileId in $requiredProfiles) {
  $profile = @($qualityProfiles.profiles | Where-Object { [string]$_.profile_id -eq $profileId })
  if ($profile.Count -ne 1) { throw "Required technology quality profile is missing: $profileId" }
  foreach ($field in @(
    "candidate_class", "minimum_members", "maximum_members", "maximum_semantic_clusters",
    "maximum_progression_span", "maximum_owner_conflicts", "minimum_accepting_labs",
    "minimum_useful_levels_before_cap", "maximum_science_tier_span",
    "required_semantic_evidence", "required_observational_evidence"
  )) {
    if ($null -eq $profile[0].PSObject.Properties[$field]) {
      throw "Technology quality profile $profileId lacks required field: $field"
    }
  }
}
Set-MIRGeneratedLua "prototypes/mir/domain/technology/generated_quality_profiles.lua" $qualitySource $qualityProfiles

if ($Check) { Write-Host "[ok] Generated compiler authorities converge with their machine sources." }
