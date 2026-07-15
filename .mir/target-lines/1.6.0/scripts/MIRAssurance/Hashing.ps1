function Get-MIRAssuranceRepositoryBlobId {
  param([Parameter(Mandatory)][string]$Path)
  $full = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Repository file not found: $Path" }
  $relative = Get-MIRAssuranceRepoRelativePath -Path $full
  $blob = @(& git -C $repo hash-object "--path=$relative" -- $full)
  if ($LASTEXITCODE -ne 0 -or $blob.Count -ne 1) { throw "Unable to calculate canonical Git blob identity for $relative." }
  return ([string]$blob[0]).Trim()
}

function Get-MIRAssuranceRepositoryFileHash {
  param([Parameter(Mandatory)][string]$Path)
  $full = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  $relative = Get-MIRAssuranceRepoRelativePath -Path $full
  return Get-MIRAssuranceTextHash -Text "$relative`t$(Get-MIRAssuranceRepositoryBlobId -Path $full)"
}

function Get-MIRAssuranceTreeHash {
  param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths)
  $rows = @()
  foreach ($path in @($Paths | Sort-Object -Unique)) {
    $full = if ([IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $repo $path }
    if (Test-Path -LiteralPath $full -PathType Leaf) {
      $relative = Get-MIRAssuranceRepoRelativePath -Path $full
      $rows += "$relative`t$(Get-MIRAssuranceRepositoryBlobId -Path $full)"
    } else {
      $rows += "$(([string]$path).Replace('\','/'))`tMISSING"
    }
  }
  if ($rows.Count -eq 0) { $rows += "EMPTY" }
  return Get-MIRAssuranceTextHash -Text (($rows | Sort-Object) -join "`n")
}

