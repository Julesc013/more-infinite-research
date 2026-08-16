function Write-MIRJsonAtomic {
  param(
    [Parameter(Mandatory)]$Data,
    [Parameter(Mandatory)][string]$Path,
    [int]$Depth = 20
  )

  $directory = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
  }

  $tmp = "$Path.tmp"
  $Data | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $tmp -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Read-MIRJsonOrDefault {
  param(
    [Parameter(Mandatory)][string]$Path,
    $Default = $null
  )

  if (-not (Test-Path -LiteralPath $Path)) { return $Default }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Update-MIRScenarioState {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Scenario,
    [Parameter(Mandatory)][string]$Status,
    [int]$ExitCode = 0,
    [double]$Seconds = 0,
    [string[]]$Missing = @()
  )

  $state = Read-MIRJsonOrDefault -Path $Path -Default ([pscustomobject]@{
    schema = 1
    run_id = ""
    scenarios = [pscustomobject]@{}
  })

  $scenarios = @{}
  foreach ($property in $state.scenarios.PSObject.Properties) {
    $scenarios[$property.Name] = $property.Value
  }

  $attempts = 1
  if ($scenarios.ContainsKey($Scenario)) {
    $previous = $scenarios[$Scenario]
    if ($previous.PSObject.Properties["attempts"]) {
      $attempts = [int]$previous.attempts + 1
    }
  }

  $scenarios[$Scenario] = [ordered]@{
    status = $Status
    attempts = $attempts
    last_exit_code = $ExitCode
    seconds = $Seconds
    missing = @($Missing)
    updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
  }

  Write-MIRJsonAtomic -Path $Path -Data ([ordered]@{
    schema = 1
    scenarios = $scenarios
  })
}
