param(
  [ValidateSet('inspect','check')][string]$Command = 'inspect',
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$FactorioBin = 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$OutputPath = 'build/results/engine-channel/factorio-2.1-review.json'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioVersionPolicy.ps1')
$review = Get-MIR4Factorio21ChannelReview -FactorioBin $FactorioBin -RepoRoot $RepoRoot
$output = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }
$written = Write-MIR4Factorio21ChannelReview -Review $review -OutputPath $output
Write-Host "[$($review.status)] Factorio $($review.observed_identity.version) channel review: $written"
if ($Command -eq 'check' -and [string]$review.status -ne 'current-reviewed') {
  throw "Factorio 2.1 experimental-channel review is not current: $($review.status)."
}
