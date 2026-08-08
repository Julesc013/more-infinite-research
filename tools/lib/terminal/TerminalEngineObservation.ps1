function ConvertTo-MIRTerminalCanonicalValue {
  param($Value)

  if ($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or
      $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or
      $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or
      $Value -is [decimal]) {
    return $Value
  }
  if ($Value -is [Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
      $result[$key] = ConvertTo-MIRTerminalCanonicalValue $Value[$key]
    }
    return $result
  }
  if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    return @($Value | ForEach-Object { ConvertTo-MIRTerminalCanonicalValue $_ })
  }
  $result = [ordered]@{}
  foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
    $result[$property.Name] = ConvertTo-MIRTerminalCanonicalValue $property.Value
  }
  return $result
}

function ConvertTo-MIRTerminalCompactJson {
  param($Value)
  return (ConvertTo-MIRTerminalCanonicalValue $Value | ConvertTo-Json -Depth 100 -Compress)
}

function Get-MIRTerminalPropertyValue {
  param($Value, [string]$Name, $Default = $null)
  if ($null -eq $Value) { return $Default }
  $property = $Value.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function ConvertTo-MIRTerminalStringList {
  param($Value)
  if ($null -eq $Value) { return @() }
  return @($Value | ForEach-Object {
    if ($_ -is [string]) { $_ }
    elseif ($_ -is [Collections.IEnumerable] -and $_ -isnot [Collections.IDictionary]) {
      (@($_ | ForEach-Object { [string]$_ }) -join ":")
    } else {
      ConvertTo-MIRTerminalCompactJson $_
    }
  })
}

function Get-MIRTerminalEngineInventory {
  param(
    [Parameter(Mandatory)]$DataRaw,
    [Parameter(Mandatory)][string]$Release,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string[]]$DeclaredTechnologyNames,
    [Parameter(Mandatory)][string]$EvidencePath
  )

  $technologyTable = Get-MIRTerminalPropertyValue $DataRaw "technology"
  $technologyItems = @()
  $effectItems = @()
  foreach ($name in @($DeclaredTechnologyNames | Sort-Object -Unique)) {
    $technology = if ($technologyTable) { Get-MIRTerminalPropertyValue $technologyTable $name } else { $null }
    if ($null -eq $technology) { continue }
    $effects = @(Get-MIRTerminalPropertyValue $technology "effects" @())
    $attributes = @(
      [ordered]@{name="prototype_name";value=$name},
      [ordered]@{name="enabled";value=[bool](Get-MIRTerminalPropertyValue $technology "enabled" $true)},
      [ordered]@{name="hidden";value=[bool](Get-MIRTerminalPropertyValue $technology "hidden" $false)},
      [ordered]@{name="upgrade";value=[bool](Get-MIRTerminalPropertyValue $technology "upgrade" $false)},
      [ordered]@{name="max_level";value=$(if ($null -eq (Get-MIRTerminalPropertyValue $technology "max_level")) { $null } else { [string](Get-MIRTerminalPropertyValue $technology "max_level") })},
      [ordered]@{name="prerequisites";value=@(ConvertTo-MIRTerminalStringList (Get-MIRTerminalPropertyValue $technology "prerequisites" @()) | Sort-Object -Unique)},
      [ordered]@{name="unit";value=$(if ($null -eq (Get-MIRTerminalPropertyValue $technology "unit")) { $null } else { ConvertTo-MIRTerminalCompactJson (Get-MIRTerminalPropertyValue $technology "unit") })},
      [ordered]@{name="effects";value=$(if ($effects.Count -eq 0) { "[]" } else { ConvertTo-MIRTerminalCompactJson $effects })}
    )
    $technologyItems += [ordered]@{
      stable_id=$name; target=$Target; state="realized"; origin="exact-engine-data-raw";
      observed_release=$Release; source_evidence=@($EvidencePath);
      target_disposition="realized-on-target"; mir4_transition_rule="import-realized-prototype-as-terminal-baseline";
      attributes=$attributes
    }
    for ($index = 0; $index -lt $effects.Count; $index++) {
      $effect = $effects[$index]
      $effectItems += [ordered]@{
        stable_id=("{0}#effect-{1:D3}" -f $name, ($index + 1)); target=$Target; state="realized";
        origin="exact-engine-data-raw"; observed_release=$Release; source_evidence=@($EvidencePath);
        target_disposition="realized-owner-effect"; mir4_transition_rule="import-owner-and-effect-as-terminal-baseline";
        attributes=@(
          [ordered]@{name="technology";value=$name},
          [ordered]@{name="effect_type";value=[string](Get-MIRTerminalPropertyValue $effect "type" "unknown")},
          [ordered]@{name="effect";value=(ConvertTo-MIRTerminalCompactJson $effect)}
        )
      }
    }
  }

  $settingItems = @()
  foreach ($prototypeType in @("bool-setting", "double-setting", "int-setting", "string-setting")) {
    $settingTable = Get-MIRTerminalPropertyValue $DataRaw $prototypeType
    if ($null -eq $settingTable) { continue }
    foreach ($property in @($settingTable.PSObject.Properties | Where-Object Name -like "mir-*" | Sort-Object Name)) {
      $setting = $property.Value
      $attributes = @(
        [ordered]@{name="prototype_type";value=$prototypeType},
        [ordered]@{name="setting_type";value=[string](Get-MIRTerminalPropertyValue $setting "setting_type" "startup")},
        [ordered]@{name="default_value";value=(ConvertTo-MIRTerminalCompactJson (Get-MIRTerminalPropertyValue $setting "default_value"))},
        [ordered]@{name="minimum_value";value=$(if ($null -eq (Get-MIRTerminalPropertyValue $setting "minimum_value")) { $null } else { [string](Get-MIRTerminalPropertyValue $setting "minimum_value") })},
        [ordered]@{name="maximum_value";value=$(if ($null -eq (Get-MIRTerminalPropertyValue $setting "maximum_value")) { $null } else { [string](Get-MIRTerminalPropertyValue $setting "maximum_value") })},
        [ordered]@{name="allowed_values";value=@(ConvertTo-MIRTerminalStringList (Get-MIRTerminalPropertyValue $setting "allowed_values" @()))},
        [ordered]@{name="hidden";value=[bool](Get-MIRTerminalPropertyValue $setting "hidden" $false)}
      )
      $settingItems += [ordered]@{
        stable_id=$property.Name; target=$Target; state="realized"; origin="exact-engine-data-raw";
        observed_release=$Release; source_evidence=@($EvidencePath);
        target_disposition="realized-on-target"; mir4_transition_rule="import-realized-setting-as-terminal-baseline";
        attributes=$attributes
      }
    }
  }

  return [ordered]@{
    technologies=@($technologyItems | Sort-Object { [string]$_.stable_id })
    effects_and_owners=@($effectItems | Sort-Object { [string]$_.stable_id })
    settings=@($settingItems | Sort-Object { [string]$_.stable_id })
  }
}
