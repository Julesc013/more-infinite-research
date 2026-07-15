. (Join-Path $PSScriptRoot "Checkpoint.ps1")

function Write-MIRArtifactIndex {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$RunId,
    [hashtable]$Files = @{},
    [object[]]$Tiers = @()
  )

  Write-MIRJsonAtomic -Path $Path -Data ([ordered]@{
    schema = 1
    run_id = $RunId
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    files = $Files
    tiers = @($Tiers)
  })
}
