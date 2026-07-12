function Initialize-MIRSettingsOverrideMod {
  param([Parameter(Mandatory)][string]$ModsDir)

  $path = Join-Path $ModsDir "mir-validation-settings-overrides"
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  @{
    name = "mir-validation-settings-overrides"
    version = "0.1.0"
    title = "MIR Validation Settings Overrides"
    author = "MIR validation harness"
    factorio_version = "2.1"
    dependencies = @("more-infinite-research")
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $path "info.json") -Encoding UTF8
  @'
local function override(name, value)
  for _, prototype_type in ipairs({"bool-setting", "string-setting", "int-setting", "double-setting"}) do
    local prototype = data.raw[prototype_type] and data.raw[prototype_type][name]
    if prototype then prototype.default_value = value; return end
  end
  error("MIR validation override references missing startup setting " .. name)
end
'@ | Set-Content -LiteralPath (Join-Path $path "settings-updates.lua") -Encoding UTF8
}

function Enable-CopiedDiagnostics {
  param([string]$ModsDir)
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "mir-debug-generation-report" -ValueLiteral "true"
}

function Enable-CopiedScriptedDiagnostics {
  param([string]$ModsDir)
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "mir-debug-scripted-effects" -ValueLiteral "true"
}

function Set-CopiedStartupSettingDefault {
  param(
    [string]$ModsDir,
    [string]$Name,
    [string]$ValueLiteral
  )

  $overridePath = Join-Path $ModsDir "mir-validation-settings-overrides\settings-updates.lua"
  if (-not (Test-Path -LiteralPath $overridePath -PathType Leaf)) {
    throw "Unable to find validation settings override fixture."
  }
  $escapedNameLiteral = $Name.Replace("\", "\\").Replace('"', '\"')
  Add-Content -LiteralPath $overridePath -Value "override(`"$escapedNameLiteral`", $ValueLiteral)" -Encoding UTF8
}

function Set-CopiedGeneratedStartupSettingDefault {
  param(
    [string]$ModsDir,
    [string]$Name,
    [string]$ValueLiteral
  )

  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name $Name -ValueLiteral $ValueLiteral
}

function Set-CopiedEffectPerLevelDefaults {
  param(
    [string]$ModsDir,
    [hashtable]$Overrides
  )

  foreach ($streamKey in @($Overrides.Keys | Sort-Object)) {
    $value = [double]$Overrides[$streamKey]
    $literal = $value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    Set-CopiedGeneratedStartupSettingDefault `
      -ModsDir $ModsDir `
      -Name "ips-effect-per-level-$streamKey" `
      -ValueLiteral $literal
  }
}

function Set-CopiedBaseEffectPerLevelDefaults {
  param(
    [string]$ModsDir,
    [hashtable]$Overrides
  )

  foreach ($baseExtensionKey in @($Overrides.Keys | Sort-Object)) {
    $value = [double]$Overrides[$baseExtensionKey]
    $literal = $value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    Set-CopiedGeneratedStartupSettingDefault `
      -ModsDir $ModsDir `
      -Name "mir-effect-per-level-$baseExtensionKey" `
      -ValueLiteral $literal
  }
}

function Set-CopiedLabPolicySkip {
  param([string]$ModsDir)
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "mir-lab-incompatibility-policy" -ValueLiteral '"skip"'
}

function Set-CopiedSciencePackIngredientPolicy {
  param(
    [string]$ModsDir,
    [ValidateSet("configured", "space", "space-and-promethium", "space-age-progression", "official-progression", "mod-progression", "all-official", "all")]
    [string]$Policy
  )
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "mir-science-pack-ingredient-policy" -ValueLiteral "`"$Policy`""
}

function Set-CopiedRequireSpaceGate {
  param([string]$ModsDir)
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "ips-require-space-gate" -ValueLiteral "true"
}

function Set-CopiedPipelineExtentMultiplier {
  param(
    [string]$ModsDir,
    [double]$Multiplier
  )
  $percent = [int][Math]::Round($Multiplier * 100)
  $allowedPercents = @(25, 50, 75, 100, 125, 150, 200, 250, 300, 400, 500, 750, 1000)
  if ($allowedPercents -notcontains $percent) {
    throw "Unsupported pipeline extent multiplier for dropdown validation: $Multiplier ($percent%)."
  }
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "mir-pipeline-extent-multiplier" -ValueLiteral "`"$percent`""
}

function Set-CopiedPrototypeLimitDefaults {
  param(
    [string]$ModsDir,
    [string]$ProductivityCap,
    [string]$EfficiencyCap,
    [string]$PollutionCap,
    [string]$SpeedFloor,
    [string]$SpeedCap,
    [string]$QualityCap,
    [string]$RecyclingReturnChance,
    [bool]$PositivePowerFloor = $false,
    [bool]$ProductivityCapSelfRecyclingOnly = $false,
    [bool]$UnrestrictedModules = $false
  )

  if (-not [string]::IsNullOrWhiteSpace($ProductivityCap)) {
    Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "mir-prototype-productivity-cap" -ValueLiteral "`"$ProductivityCap`""
  }
  if (-not [string]::IsNullOrWhiteSpace($EfficiencyCap)) {
    Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "mir-prototype-efficiency-cap" -ValueLiteral "`"$EfficiencyCap`""
  }
  if (-not [string]::IsNullOrWhiteSpace($PollutionCap)) {
    Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "mir-prototype-pollution-cap" -ValueLiteral "`"$PollutionCap`""
  }
  if (-not [string]::IsNullOrWhiteSpace($SpeedFloor)) {
    Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "mir-prototype-speed-floor" -ValueLiteral "`"$SpeedFloor`""
  }
  if (-not [string]::IsNullOrWhiteSpace($SpeedCap)) {
    Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "mir-prototype-speed-cap" -ValueLiteral "`"$SpeedCap`""
  }
  if (-not [string]::IsNullOrWhiteSpace($QualityCap)) {
    Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "mir-prototype-quality-cap" -ValueLiteral "`"$QualityCap`""
  }
  if ($PositivePowerFloor) {
    Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "mir-prototype-positive-power-floor" -ValueLiteral "true"
  }
  if (-not [string]::IsNullOrWhiteSpace($RecyclingReturnChance)) {
    Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "mir-recycling-return-chance" -ValueLiteral "`"$RecyclingReturnChance`""
  }
  if ($ProductivityCapSelfRecyclingOnly) {
    Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "mir-productivity-cap-self-recycling-only" -ValueLiteral "true"
  }
  if ($UnrestrictedModules) {
    Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "mir-unrestricted-modules" -ValueLiteral "true"
  }
}

function Set-CopiedStreamCheckboxDefault {
  param(
    [string]$ModsDir,
    [string]$StreamKey,
    [bool]$Enabled
  )

  $valueLiteral = if ($Enabled) { "true" } else { "false" }
  Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "ips-enable-$StreamKey" -ValueLiteral $valueLiteral
}

function Set-CopiedStreamEnabled {
  param([string]$ModsDir, [string]$StreamKey)
  Set-CopiedStreamCheckboxDefault -ModsDir $ModsDir -StreamKey $StreamKey -Enabled $true
}

function Set-CopiedStreamDisabled {
  param([string]$ModsDir, [string]$StreamKey)
  Set-CopiedStreamCheckboxDefault -ModsDir $ModsDir -StreamKey $StreamKey -Enabled $false
}

function Set-CopiedBaseExtensionDefault {
  param(
    [string]$ModsDir,
    [string]$BaseExtensionKey,
    [bool]$Enabled
  )
  $valueLiteral = if ($Enabled) { "true" } else { "false" }
  Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "mir-enable-$BaseExtensionKey" -ValueLiteral $valueLiteral
}

function Set-CopiedBaseExtensionEnabled {
  param([string]$ModsDir, [string]$BaseExtensionKey)
  Set-CopiedBaseExtensionDefault -ModsDir $ModsDir -BaseExtensionKey $BaseExtensionKey -Enabled $true
}

function Set-CopiedBaseExtensionDisabled {
  param([string]$ModsDir, [string]$BaseExtensionKey)
  Set-CopiedBaseExtensionDefault -ModsDir $ModsDir -BaseExtensionKey $BaseExtensionKey -Enabled $false
}

function Set-CopiedLabPolicyEngineDefault {
  param([string]$ModsDir)
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "mir-lab-incompatibility-policy" -ValueLiteral '"engine-default"'
}

function Set-CopiedBaseExtensionMaxLevel {
  param(
    [string]$ModsDir,
    [string]$BaseExtensionKey,
    [int]$MaxLevel
  )

  Set-CopiedGeneratedStartupSettingDefault `
    -ModsDir $ModsDir `
    -Name "mir-max-level-$BaseExtensionKey" `
    -ValueLiteral $MaxLevel
}
