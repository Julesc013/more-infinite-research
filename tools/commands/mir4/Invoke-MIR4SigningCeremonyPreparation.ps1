param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [Parameter(Mandatory)][string]$SshKeygenPath,
  [string]$ScratchRoot = 'build/results/mir4-t15/signing-ceremony-preparation/scratch',
  [string]$OutputPath = 'build/results/mir4-t15/signing-ceremony-preparation/receipt.json',
  [switch]$RequireClean
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/SigningCeremonyPreparation.ps1')

function Resolve-MIR4SigningPreparationOutputPath {
  param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string]$Label)
  $candidate = if ([IO.Path]::IsPathRooted($Value)) { [IO.Path]::GetFullPath($Value) } else { [IO.Path]::GetFullPath((Join-Path $repo $Value)) }
  $relative = [IO.Path]::GetRelativePath($repo, $candidate).Replace('\','/')
  if ($relative -eq '..' -or $relative.StartsWith('../', [StringComparison]::Ordinal)) { throw "[mir4-signing-preparation-output-outside-repository] $Label" }
  return Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $candidate -Label $Label
}

$scratch = Resolve-MIR4SigningPreparationOutputPath -Value $ScratchRoot -Label 'Signing preparation scratch root'
$output = Resolve-MIR4SigningPreparationOutputPath -Value $OutputPath -Label 'Signing preparation receipt'
$receipt = New-MIR4SigningCeremonyPreparationReceiptV1 -RepoRoot $repo -SshKeygenPath $SshKeygenPath -ScratchRoot $scratch -RequireClean:$RequireClean
if (-not (Test-MIR4SigningCeremonyPreparationReceiptV1 -Receipt $receipt -RepoRoot $repo)) { throw '[mir4-signing-preparation-receipt-verification]' }
$null = Write-MIR4BootstrapRecord -Record $receipt -Path $output
$receipt
