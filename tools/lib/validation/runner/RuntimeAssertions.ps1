function Get-LastStreamReportLine {
  param([string]$Key)
  $pattern = "kind=stream key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain diagnostics for $Key."
  }
  return $line.Line
}

function Get-LastExtensionReportLine {
  param([string]$Key)
  $pattern = "kind=extension key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain extension diagnostics for $Key."
  }
  return $line.Line
}

function Get-LastNativeModifierOverlapLine {
  param([string]$Key)
  $pattern = "kind=native_modifier_overlap key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain native modifier overlap diagnostics for $Key."
  }
  return $line.Line
}

function Get-LastCompatibilityPlanLine {
  param([string]$Key)
  $pattern = "kind=compatibility_plan key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain compatibility plan diagnostics for $Key."
  }
  return $line.Line
}

function Get-LastDiagnosticReportLine {
  param([string]$Kind, [string]$Key)
  $pattern = "kind=$([regex]::Escape($Kind)) key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain $Kind diagnostics for $Key."
  }
  return $line.Line
}

function Get-DiagnosticReportLineContaining {
  param([string]$Kind, [string]$Key, [string]$Expected)
  $pattern = "kind=$([regex]::Escape($Kind)) key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern |
    Where-Object { $_.Line.Contains($Expected) } |
    Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain $Kind diagnostics for $Key with expected text '$Expected'."
  }
  return $line.Line
}

function Assert-NoDiagnosticReportLineContaining {
  param([string]$Kind, [string]$Key, [string]$Unexpected, [string]$Context)
  $pattern = "kind=$([regex]::Escape($Kind)) key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern |
    Where-Object { $_.Line.Contains($Unexpected) } |
    Select-Object -Last 1
  if ($line) {
    throw "$Context unexpectedly found $Kind diagnostics for $Key with text '$Unexpected': $($line.Line)"
  }
}

function Get-LastRecipeCapReportLine {
  param([string]$Recipe)
  $pattern = "kind=recipe_cap .*recipe=$([regex]::Escape($Recipe))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain recipe cap diagnostics for $Recipe."
  }
  return $line.Line
}

function Assert-ReportLineGenerated {
  param([string]$Line, [string]$Context)
  if ($Line -notmatch "status=generated") {
    throw "$Context did not generate as expected: $Line"
  }
}

function Assert-ReportLineAdopted {
  param([string]$Line, [string]$Context)
  if ($Line -notmatch "status=adopted") {
    throw "$Context did not adopt as expected: $Line"
  }
}

function Assert-ReportLineContains {
  param([string]$Line, [string]$Expected, [string]$Context)
  if (-not $Line.Contains($Expected)) {
    throw "$Context did not include expected text '$Expected': $Line"
  }
}

function Assert-ReportLineDoesNotContain {
  param([string]$Line, [string]$Unexpected, [string]$Context)
  if ($Line.Contains($Unexpected)) {
    throw "$Context unexpectedly included '$Unexpected': $Line"
  }
}

function Get-ReportScienceField {
  param([string]$Line)
  $match = [regex]::Match($Line, " science=([^ ]*) ")
  if (-not $match.Success) {
    throw "Generation report line did not include a parseable science field: $Line"
  }
  return $match.Groups[1].Value
}

function Assert-ReportScienceContains {
  param([string]$Line, [string]$Expected, [string]$Context)
  $science = Get-ReportScienceField -Line $Line
  $packs = @()
  if ($science.Length -gt 0) { $packs = $science -split "," }
  if ($packs -notcontains $Expected) {
    throw "$Context science field did not include expected pack '$Expected': $Line"
  }
}

function Assert-ReportScienceDoesNotContain {
  param([string]$Line, [string]$Unexpected, [string]$Context)
  $science = Get-ReportScienceField -Line $Line
  $packs = @()
  if ($science.Length -gt 0) { $packs = $science -split "," }
  if ($packs -contains $Unexpected) {
    throw "$Context science field unexpectedly included pack '$Unexpected': $Line"
  }
}

function Assert-LogContains {
  param([string]$Expected, [string]$Context)
  $line = Select-String -LiteralPath $FactorioLog -Pattern $Expected -SimpleMatch | Select-Object -Last 1
  if (-not $line) {
    throw "$Context missing expected runtime log text '$Expected'."
  }
  return $line.Line
}

function Assert-NativeOwnerResearchWorkPreserved {
  param([string]$Context)
  $logText = Get-Content -Raw -LiteralPath $FactorioLog
  $observationPattern = '\[mir-fixture\] native-owner observed progress proof source-progress=(?<source>[0-9.eE+-]+) before=(?<before>[0-9.eE+-]+) after=(?<after>[0-9.eE+-]+) prior-cost=(?<previous>[0-9.eE+-]+) current-cost=(?<current>[0-9.eE+-]+) level=(?<level>[0-9]+)'
  $observation = [regex]::Match($logText, $observationPattern)
  if (-not $observation.Success) {
    throw "$Context is missing parseable independent research-work observation evidence."
  }
  $culture = [Globalization.CultureInfo]::InvariantCulture
  $source = [double]::Parse($observation.Groups['source'].Value, $culture)
  $before = [double]::Parse($observation.Groups['before'].Value, $culture)
  $after = [double]::Parse($observation.Groups['after'].Value, $culture)
  $previous = [double]::Parse($observation.Groups['previous'].Value, $culture)
  $current = [double]::Parse($observation.Groups['current'].Value, $culture)
  $expected = [Math]::Max(0.0, [Math]::Min(1.0, $source * $previous / $current))
  $epsilon = 0.000001
  if ([Math]::Abs($before - $expected) -gt $epsilon -or
      [Math]::Abs($after - $expected) -gt $epsilon) {
    throw "$Context did not retain Factorio-normalized completed research-unit work."
  }
}

function Assert-LogDoesNotContain {
  param([string]$Unexpected, [string]$Context)
  $line = Select-String -LiteralPath $FactorioLog -Pattern $Unexpected -SimpleMatch | Select-Object -Last 1
  if ($line) {
    throw "$Context unexpectedly found runtime log text '$Unexpected': $($line.Line)"
  }
}

function Assert-NoStreamReportLine {
  param([string]$Key, [string]$Context)
  $pattern = "kind=stream key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if ($line) {
    throw "$Context unexpectedly found stream diagnostics for ${Key}: $($line.Line)"
  }
}

$defaultEnabledBaseExtensionKeys = @(
  "braking-force",
  "research-speed",
  "worker-robots-storage",
  "inserter-capacity-bonus",
  "weapon-shooting-speed",
  "laser-shooting-speed"
)
if ($isFactorio10Line) {
  $defaultEnabledBaseExtensionKeys = @($defaultEnabledBaseExtensionKeys | Where-Object { $_ -ne "laser-shooting-speed" })
}

$spaceAgeVanillaOwnedProductivityStreams = @(
  "research_low_density_structure",
  "research_plastic",
  "research_processing_unit",
  "research_rocket_fuel",
  "research_steel"
)

function Assert-DefaultBaseExtensionDiagnostics {
  param([string]$Context)

  $expectedGenerated = @($defaultEnabledBaseExtensionKeys)

  foreach ($key in $expectedGenerated) {
    $line = Get-LastExtensionReportLine -Key $key
    Assert-ReportLineGenerated -Line $line -Context "$Context base extension $key"
  }

}

function ConvertTo-MIRScenarioParameterValue {
  param($Value)
  if ($null -ne $Value -and $Value.GetType() -eq [System.Management.Automation.PSCustomObject]) {
    $table = @{}
    foreach ($property in $Value.PSObject.Properties) {
      $table[$property.Name] = ConvertTo-MIRScenarioParameterValue -Value $property.Value
    }
    return $table
  }
  if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) {
    return @($Value | ForEach-Object { ConvertTo-MIRScenarioParameterValue -Value $_ })
  }
  return $Value
}

function Assert-SpaceAgeVanillaOwnedProductivityStreamsBound {
  param([string]$Context)

  foreach ($vanillaOwnedStream in $spaceAgeVanillaOwnedProductivityStreams) {
    $vanillaOwnedLine = Get-LastStreamReportLine -Key $vanillaOwnedStream
    if ($vanillaOwnedLine -notmatch "status=adopted" -or $vanillaOwnedLine -notmatch "reason=preserve_native_owner") {
      throw "$Context should preserve the vanilla owner instead of generating a parallel MIR technology: $vanillaOwnedLine"
    }
  }
}

function Assert-BaseCoreProductivityStreamsGenerated {
  param([string]$Context)

  foreach ($stream in @(
    "research_electronic_circuit",
    "research_advanced_circuit",
    "research_processing_unit",
    "research_low_density_structure",
    "research_plastic",
    "research_rocket_fuel",
    "research_steel"
  )) {
    $line = Get-LastStreamReportLine -Key $stream
    Assert-ReportLineGenerated -Line $line -Context "$Context stream $stream"
  }
}

