param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$FromZip,
  [Parameter(Mandatory)][string]$ToZip,
  [Parameter(Mandatory)][string]$FromVersion,
  [Parameter(Mandatory)][string]$ToVersion,
  [string]$FixtureName = "assert-upgrade-3-1-9-to-3-2-0",
  [string]$OutputPath = "artifacts/assurance/3.2.0-upgrade-proof.json"
)

$ErrorActionPreference = "Stop"
$runner = Join-Path $RepoRoot "scripts\Test-MIRUpgrade.ps1"
$output = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }
$outputParent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputParent)) { New-Item -ItemType Directory -Force -Path $outputParent | Out-Null }

$cases = @(
  [ordered]@{ id = "base-default"; source_only = @() },
  [ordered]@{ id = "space-age-native-owner"; source_only = @() },
  [ordered]@{ id = "automatic-family-creation"; source_only = @() },
  [ordered]@{ id = "base-continuations"; source_only = @() },
  [ordered]@{ id = "mod-set-configuration-change"; source_only = @("upgrade-modset-source") }
)

$rows = @()
foreach ($case in $cases) {
  $rowOutput = Join-Path $outputParent "$ToVersion-upgrade-$($case.id).json"
  $arguments = @{
    RepoRoot = $RepoRoot
    FactorioBin = $FactorioBin
    FromZip = $FromZip
    ToZip = $ToZip
    FromVersion = $FromVersion
    ToVersion = $ToVersion
    FixtureName = $FixtureName
    Archetype = [string]$case.id
    SourceOnlyFixtureNames = @($case.source_only)
    OutputPath = $rowOutput
  }
  & $runner @arguments
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $rowOutput -PathType Leaf)) {
    throw "Upgrade matrix row failed: $($case.id)"
  }
  $result = Get-Content -Raw -LiteralPath $rowOutput | ConvertFrom-Json
  if ([int]$result.schema -ne 2 -or [string]$result.status -ne "passed" -or [string]$result.archetype -ne [string]$case.id) {
    throw "Upgrade matrix row is not an exact passing schema-2 result: $($case.id)"
  }
  $relative = [IO.Path]::GetRelativePath($RepoRoot, (Resolve-Path -LiteralPath $rowOutput).Path).Replace('\', '/')
  $rows += [ordered]@{
    id = [string]$case.id
    status = "passed"
    result = $relative
    result_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $rowOutput).Hash
    assertions = @($result.assertions)
  }
}

$factorio = if ([IO.Path]::IsPathRooted($FactorioBin)) { (Resolve-Path -LiteralPath $FactorioBin).Path } else { (Resolve-Path -LiteralPath (Join-Path $RepoRoot $FactorioBin)).Path }
$from = if ([IO.Path]::IsPathRooted($FromZip)) { (Resolve-Path -LiteralPath $FromZip).Path } else { (Resolve-Path -LiteralPath (Join-Path $RepoRoot $FromZip)).Path }
$to = if ([IO.Path]::IsPathRooted($ToZip)) { (Resolve-Path -LiteralPath $ToZip).Path } else { (Resolve-Path -LiteralPath (Join-Path $RepoRoot $ToZip)).Path }
$factorioVersion = (Get-Item -LiteralPath $factorio).VersionInfo.FileVersion

[ordered]@{
  schema = 1
  kind = "mir-upgrade-matrix"
  status = "passed"
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  source_commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  factorio = [ordered]@{
    version = $factorioVersion
    binary_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $factorio).Hash
  }
  baseline = [ordered]@{
    version = $FromVersion
    archive = (Split-Path -Leaf $from)
    archive_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $from).Hash
  }
  candidate = [ordered]@{
    version = $ToVersion
    archive = (Split-Path -Leaf $to)
    archive_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $to).Hash
  }
  required_archetypes = @($cases | ForEach-Object { [string]$_.id })
  rows = $rows
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $output -Encoding UTF8

Write-Host "[ok] MIR upgrade matrix: $output"
