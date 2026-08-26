param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputPath = 'build/results/mir4-t15/runner-publisher-confinement/receipt.json',
  [switch]$RequireClean
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/RunnerPublisherConfinement.ps1')

$output = if ([IO.Path]::IsPathRooted($OutputPath)) {
  [IO.Path]::GetFullPath($OutputPath)
} else {
  [IO.Path]::GetFullPath((Join-Path $repo $OutputPath))
}
$relative = [IO.Path]::GetRelativePath($repo, $output).Replace('\','/')
if ($relative -eq '..' -or $relative.StartsWith('../', [StringComparison]::Ordinal)) {
  throw '[mir4-runner-receipt-outside-repository]'
}
$receipt = New-MIR4RunnerPublisherConfinementReceiptV1 -RepoRoot $repo -RequireClean:$RequireClean
if (-not (Test-MIR4RunnerPublisherConfinementReceiptV1 -Receipt $receipt -RepoRoot $repo)) {
  throw '[mir4-runner-receipt-verification]'
}
Write-MIR4BootstrapRecord -Record $receipt -Path $output
$receipt
