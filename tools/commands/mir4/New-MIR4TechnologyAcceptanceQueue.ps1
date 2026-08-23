param(
  [Parameter(Mandatory)][string]$CatalogPath,
  [Parameter(Mandatory)][string]$Target,
  [Parameter(Mandatory)][string]$Ecosystem,
  [Parameter(Mandatory)][string]$OutputPath,
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..'))
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/TechnologyAcceptance.ps1')

$queue = New-MIR4TechnologyAcceptanceQueue -RepoRoot $RepoRoot -CatalogPath $CatalogPath -Target $Target -Ecosystem $Ecosystem
$json = $queue | ConvertTo-Json -Depth 100
if (-not ($json | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-technology-acceptance-queue-v1.schema.json') -ErrorAction Stop)) {
  throw '[mir4-acceptance-schema] Generated queue failed schema validation.'
}
$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "[ok] wrote MIR 4 technology acceptance queue $OutputPath target=$($queue.target) candidates=$($queue.candidate_count)"
