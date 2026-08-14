function Initialize-MIRSettingsOverrideMod {
  param(
    [Parameter(Mandatory)][string]$ModsDir,
    [Parameter(Mandatory)][string]$FactorioVersion
  )

  $path = Join-Path $ModsDir "mir-validation-settings-overrides"
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  @{
    name = "mir-validation-settings-overrides"
    version = "0.1.0"
    title = "MIR Validation Settings Overrides"
    author = "MIR validation harness"
    factorio_version = $FactorioVersion
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

function Complete-MIRSettingsOverrideMod {
  param([Parameter(Mandatory)][string]$ModsDir)

  $sourcePath = Join-Path $ModsDir "mir-validation-settings-overrides"
  $infoPath = Join-Path $sourcePath "info.json"
  $settingsPath = Join-Path $sourcePath "settings-updates.lua"
  if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf) -or
      -not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw "Generated validation settings override is incomplete before publication."
  }

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archiveRoot = "mir-validation-settings-overrides_0.1.0"
  $finalPath = Join-Path $ModsDir "$archiveRoot.zip"
  Assert-MIRFactorioPathBudget -Path $finalPath -Context "Validation settings override archive path"
  $temporaryPath = Join-Path $ModsDir (".mir-validation-settings-overrides-{0}.zip" -f [guid]::NewGuid().ToString("N"))
  try {
    $archive = [IO.Compression.ZipFile]::Open($temporaryPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
      foreach ($name in @("info.json", "settings-updates.lua")) {
        $entry = $archive.CreateEntry("$archiveRoot/$name", [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $inputStream = [IO.File]::OpenRead((Join-Path $sourcePath $name))
        $outputStream = $entry.Open()
        try {
          $inputStream.CopyTo($outputStream)
        } finally {
          $outputStream.Dispose()
          $inputStream.Dispose()
        }
      }
    } finally {
      $archive.Dispose()
    }
    $archive = [IO.Compression.ZipFile]::OpenRead($temporaryPath)
    try {
      $entries = @($archive.Entries | ForEach-Object { [string]$_.FullName } | Sort-Object)
      if (($entries -join "`n") -cne "$archiveRoot/info.json`n$archiveRoot/settings-updates.lua") {
        throw "Generated validation settings override archive has unexpected entries: $($entries -join ', ')."
      }
    } finally {
      $archive.Dispose()
    }
    Move-Item -LiteralPath $temporaryPath -Destination $finalPath -Force
    Remove-Item -LiteralPath $sourcePath -Recurse -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
      Remove-Item -LiteralPath $temporaryPath -Force
    }
  }
  if (-not (Test-Path -LiteralPath $finalPath -PathType Leaf)) {
    throw "Generated validation settings override archive was not published."
  }
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

function ConvertTo-MIRLuaLiteral {
  param([Parameter(Mandatory)]$Value)

  if ($Value -is [bool]) { return $(if ($Value) { "true" } else { "false" }) }
  if ($Value -is [string]) {
    $escaped = $Value.Replace("\", "\\").Replace('"', '\"')
    return '"' + $escaped + '"'
  }
  if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] `
      -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64] `
      -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
    return ([System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture))
  }
  throw "Unsupported MIR startup-setting override value type: $($Value.GetType().FullName)"
}

function Set-CopiedStartupSettingDefaults {
  param(
    [Parameter(Mandatory)][string]$ModsDir,
    [hashtable]$Overrides = @{}
  )

  foreach ($name in @($Overrides.Keys | Sort-Object)) {
    Set-CopiedStartupSettingDefault `
      -ModsDir $ModsDir `
      -Name $name `
      -ValueLiteral (ConvertTo-MIRLuaLiteral -Value $Overrides[$name])
  }
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
