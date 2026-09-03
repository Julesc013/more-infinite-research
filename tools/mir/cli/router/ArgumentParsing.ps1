function Get-MIRArgValue {
  param(
    [string[]]$Items,
    [string]$Name,
    [string]$Default = ""
  )
  for ($i = 0; $i -lt $Items.Count; $i++) {
    if ($Items[$i] -eq $Name -and $i + 1 -lt $Items.Count) { return $Items[$i + 1] }
  }
  return $Default
}

function Get-MIRArgValues {
  param([string[]]$Items,[string]$Name)
  $values = @()
  for ($i = 0; $i -lt $Items.Count; $i++) {
    if ($Items[$i] -eq $Name -and $i + 1 -lt $Items.Count) { $values += [string]$Items[$i + 1] }
  }
  return @($values)
}

function Test-MIRArgSwitch {
  param([string[]]$Items, [string]$Name)
  return $Items -contains $Name
}
