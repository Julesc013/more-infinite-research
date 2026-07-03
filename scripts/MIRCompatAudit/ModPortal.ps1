$ErrorActionPreference = "Stop"

function New-MIRQueryString {
  param([hashtable]$Query)

  if (-not $Query) { return "" }
  $parts = @()
  foreach ($key in ($Query.Keys | Sort-Object)) {
    $value = $Query[$key]
    if ($null -eq $value -or $value -eq "") { continue }
    $parts += "{0}={1}" -f [uri]::EscapeDataString([string]$key), [uri]::EscapeDataString([string]$value)
  }
  return ($parts -join "&")
}

function Invoke-MIRModPortalRequest {
  param(
    [Parameter(Mandatory)][string]$Path,
    [hashtable]$Query
  )

  $builder = [System.UriBuilder]::new("https://mods.factorio.com$Path")
  $builder.Query = New-MIRQueryString -Query $Query
  Invoke-RestMethod -Method Get -Uri $builder.Uri.AbsoluteUri -Headers @{
    "User-Agent" = "more-infinite-research-compat-audit"
  }
}

function Get-MIRModPortalCatalog {
  param(
    [int]$PageSize = 100,
    [int]$MaxPages = 0
  )

  $page = 1
  $mods = @()
  while ($true) {
    $response = Invoke-MIRModPortalRequest -Path "/api/mods" -Query @{
      page = $page
      page_size = $PageSize
      sort_attribute = "downloads_count"
      sort_order = "desc"
    }

    $mods += @($response.results)
    $pageCount = [int]($response.pagination.page_count)
    if ($MaxPages -gt 0 -and $page -ge $MaxPages) { break }
    if ($pageCount -le 0 -or $page -ge $pageCount) { break }
    $page++
  }

  return $mods
}

function Get-MIRModPortalFullMod {
  param([Parameter(Mandatory)][string]$Name)

  Invoke-MIRModPortalRequest -Path "/api/mods/$Name/full"
}

function ConvertTo-MIRVersionTuple {
  param([string]$Version)

  $match = [regex]::Match($Version, "(\d+)\.(\d+)(?:\.(\d+))?")
  if (-not $match.Success) { return @(0, 0, 0) }
  return @(
    [int]$match.Groups[1].Value,
    [int]$match.Groups[2].Value,
    $(if ($match.Groups[3].Success) { [int]$match.Groups[3].Value } else { 0 })
  )
}

function Test-MIRFactorioVersionCompatible {
  param(
    [Parameter(Mandatory)]$Release,
    [Parameter(Mandatory)][string[]]$FactorioVersions
  )

  $releaseVersion = [string]$Release.info_json.factorio_version
  if ([string]::IsNullOrWhiteSpace($releaseVersion)) { return $false }

  foreach ($version in $FactorioVersions) {
    $target = ConvertTo-MIRVersionTuple -Version $version
    if ($releaseVersion -match "^\s*$($target[0])\.$($target[1])(\D|$)") {
      return $true
    }
    if ($releaseVersion -match "(\d+\.\d+)\s*-\s*(\d+\.\d+)") {
      $min = ConvertTo-MIRVersionTuple -Version $matches[1]
      $max = ConvertTo-MIRVersionTuple -Version $matches[2]
      $targetMajorMinor = ($target[0] * 100) + $target[1]
      $minMajorMinor = ($min[0] * 100) + $min[1]
      $maxMajorMinor = ($max[0] * 100) + $max[1]
      if ($targetMajorMinor -ge $minMajorMinor -and $targetMajorMinor -le $maxMajorMinor) {
        return $true
      }
    }
  }

  return $false
}

function Select-MIRCompatibleRelease {
  param(
    [Parameter(Mandatory)]$FullMod,
    [Parameter(Mandatory)][string[]]$FactorioVersions
  )

  $releases = @($FullMod.releases) | Sort-Object { [version]($_.version -replace "[^\d\.].*$", "") } -Descending
  foreach ($release in $releases) {
    if (Test-MIRFactorioVersionCompatible -Release $release -FactorioVersions $FactorioVersions) {
      return $release
    }
  }
  return $null
}

function ConvertFrom-MIRDependencyString {
  param([Parameter(Mandatory)][string]$Dependency)

  $text = $Dependency.Trim()
  $kind = "required"
  if ($text.StartsWith("(?)")) {
    $kind = "hidden_optional"
    $text = $text.Substring(3).Trim()
  } elseif ($text.StartsWith("?")) {
    $kind = "optional"
    $text = $text.Substring(1).Trim()
  } elseif ($text.StartsWith("!")) {
    $kind = "incompatible"
    $text = $text.Substring(1).Trim()
  } elseif ($text.StartsWith("+")) {
    $kind = "recommended"
    $text = $text.Substring(1).Trim()
  } elseif ($text.StartsWith("~")) {
    $kind = "no_order"
    $text = $text.Substring(1).Trim()
  }

  $name = ($text -split "\s+")[0]
  [pscustomobject]@{
    raw = $Dependency
    name = $name
    kind = $kind
    required = $kind -eq "required"
  }
}

function Save-MIRModPortalDownload {
  param(
    [Parameter(Mandatory)]$Release,
    [Parameter(Mandatory)][string]$Username,
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$CacheDir
  )

  if (-not (Test-Path -LiteralPath $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir | Out-Null
  }

  function Test-MIRDownloadSha1 {
    param(
      [Parameter(Mandatory)][string]$Path,
      [string]$ExpectedSha1
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedSha1)) { return $true }
    $actual = (Get-FileHash -Algorithm SHA1 -LiteralPath $Path).Hash.ToLowerInvariant()
    return $actual -eq $ExpectedSha1.ToLowerInvariant()
  }

  $fileName = [string]$Release.file_name
  $target = Join-Path $CacheDir $fileName
  $expectedSha1 = [string]$Release.sha1
  if (Test-Path -LiteralPath $target) {
    if (Test-MIRDownloadSha1 -Path $target -ExpectedSha1 $expectedSha1) {
      return Get-Item -LiteralPath $target
    }
    Remove-Item -LiteralPath $target -Force
  }

  $url = "https://mods.factorio.com$($Release.download_url)?username=$([uri]::EscapeDataString($Username))&token=$([uri]::EscapeDataString($Token))"
  Invoke-WebRequest -Uri $url -OutFile $target -Headers @{
    "User-Agent" = "more-infinite-research-compat-audit"
  }

  if (-not (Test-MIRDownloadSha1 -Path $target -ExpectedSha1 $expectedSha1)) {
    Remove-Item -LiteralPath $target -Force
    throw "Downloaded mod archive failed SHA1 verification: $fileName"
  }

  return Get-Item -LiteralPath $target
}
