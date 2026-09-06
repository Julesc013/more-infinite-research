function Invoke-MIR4DevelopmentStaticChecks {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $epoch=Get-Content -Raw (Join-Path $RepoRoot 'governance/repository/development-epoch-v1.json') | ConvertFrom-Json
  if($epoch.schema -ne 1 -or $epoch.current_profile -cne 'mir4-development' -or $epoch.release_authority) { throw '[mir4-development-profile-authority]' }
  $catalog=Get-Content -Raw (Join-Path $RepoRoot 'validation/tests.yml') | ConvertFrom-Json
  $assurance=Get-Content -Raw (Join-Path $RepoRoot '.mir/assurance.json') | ConvertFrom-Json
  foreach($id in $assurance.profiles.($epoch.current_profile)) {
    $row=@($catalog.tests | Where-Object id -CEQ $id)
    if($row.Count -ne 1 -or $row[0].requires_factorio) { throw "[mir4-development-static-selection] $id" }
    $parts=([string]$row[0].command).Split(' ',[StringSplitOptions]::RemoveEmptyEntries)
    if($parts[0] -notmatch '^\./(?:tests|scripts)/[A-Za-z0-9/.-]+[.]ps1$') { throw "[mir4-development-static-command] $id" }
    $parts[0]=Join-Path $RepoRoot $parts[0]
    Write-Host "[current-development] $id"
    & pwsh -NoProfile -File @parts
    if($LASTEXITCODE -ne 0) { throw "[mir4-development-static-failed] $id" }
  }
  & git -C $RepoRoot diff --check
  if($LASTEXITCODE -ne 0) { throw '[mir4-development-whitespace]' }
}
