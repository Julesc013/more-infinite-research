# Append structured run events to events.jsonl.

function Write-MIREvent {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$Kind,
    [string]$Level = "info",
    [hashtable]$Data = @{}
  )

  $directory = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
  }

  $event = [ordered]@{
    schema = 1
    ts = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffK")
    run_id = $RunId
    level = $Level
    kind = $Kind
  }

  foreach ($key in $Data.Keys) {
    $event[$key] = $Data[$key]
  }

  ($event | ConvertTo-Json -Depth 20 -Compress) | Add-Content -LiteralPath $Path -Encoding UTF8
}
