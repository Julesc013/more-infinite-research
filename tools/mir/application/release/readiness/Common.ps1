Set-StrictMode -Version Latest

if (-not (Get-Command Get-MIR4BootstrapRecordSha256 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../../../../lib/mir4/BootstrapMaterialization.ps1')
}

function ConvertTo-MIR441CanonicalJson {
  param([Parameter(Mandatory)]$Value,[switch]$Compress)
  $json = if ($Compress) { $Value | ConvertTo-Json -Depth 100 -Compress } else { $Value | ConvertTo-Json -Depth 100 }
  return $json.Replace("`r`n","`n") + "`n"
}

function Write-MIR441Json {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path,[switch]$Append)
  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $json = ConvertTo-MIR441CanonicalJson -Value $Value -Compress:$Append
  if ($Append) { [IO.File]::AppendAllText($Path,$json,[Text.UTF8Encoding]::new($false)) }
  else { [IO.File]::WriteAllText($Path,$json,[Text.UTF8Encoding]::new($false)) }
}

function Get-MIR441FileIdentity {
  param([Parameter(Mandatory)][string]$Path,[string]$RelativePath='')
  $item = Get-Item -LiteralPath $Path -ErrorAction Stop
  return [pscustomobject][ordered]@{
    path = if ([string]::IsNullOrWhiteSpace($RelativePath)) { $item.Name } else { $RelativePath.Replace('\\','/') }
    bytes = [int64]$item.Length
    sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
  }
}

function Test-MIR441PathContained {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Path,[switch]$AllowEqual)
  $trim=[char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
  $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd($trim)
  $candidate = [IO.Path]::GetFullPath($Path).TrimEnd($trim)
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if ($AllowEqual -and $candidate.Equals($rootPath,$comparison)) { return $true }
  return $candidate.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar,$comparison)
}

function Assert-MIR441ExternalRoot {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name)
  if (-not [IO.Path]::IsPathRooted($Path)) { throw "[mir441-external-root-absolute] $Name" }
  $full = [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  if (Test-MIR441PathContained -Root $RepoRoot -Path $full -AllowEqual) { throw "[mir441-external-root-repository] $Name" }
  return $full
}

function Remove-MIR441ContainedTree {
  param([Parameter(Mandatory)][string]$AdmittedRoot,[Parameter(Mandatory)][string]$Path)
  $root = [IO.Path]::GetFullPath($AdmittedRoot)
  $target = [IO.Path]::GetFullPath($Path)
  if (-not (Test-MIR441PathContained -Root $root -Path $target)) { throw "[mir441-cleanup-containment] $target" }
  if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}

function Get-MIR441GitIdentity {
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$Revision='HEAD')
  $commit = (& git -C $RepoRoot rev-parse $Revision).Trim()
  if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-f0-9]{40}$') { throw '[mir441-git-commit]' }
  $tree = (& git -C $RepoRoot rev-parse "$Revision^{tree}").Trim()
  if ($LASTEXITCODE -ne 0 -or $tree -notmatch '^[a-f0-9]{40}$') { throw '[mir441-git-tree]' }
  return [pscustomobject][ordered]@{commit=$commit;tree=$tree}
}

function Assert-MIR441CleanTrackedSource {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $dirty=@(& git -C $RepoRoot status --porcelain --untracked-files=all)
  if($LASTEXITCODE-ne0){throw '[mir441-git-status]'}
  if($dirty.Count-ne0){throw '[mir441-source-dirty]'}
}

function Assert-MIR441MainAncestor {
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$Revision='HEAD')
  $main=(& git -C $RepoRoot rev-parse --verify refs/remotes/origin/main).Trim()
  if($LASTEXITCODE-ne0-or$main-notmatch'^[a-f0-9]{40}$'){throw '[mir441-main-ancestry-ref]'}
  & git -C $RepoRoot merge-base --is-ancestor $main $Revision
  if($LASTEXITCODE-ne0){throw "[mir441-main-ancestry-required] main=$main revision=$Revision"}
  return $main
}
