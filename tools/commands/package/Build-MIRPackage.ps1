param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [ValidateSet('f210','f200','f110','f100')]
  [string]$Target = 'f210',
  [ValidatePattern('^[A-Z0-9][A-Z0-9.-]*$')]
  [string]$CandidateId = 'MIR4-ORDINARY-BUILD',
  [string]$SourceVersion,
  [string]$DistributionVersion,
  [string]$OutputDir = 'build/packages/ordinary',
  [ValidateSet('Optimal')]
  [string]$CompressionLevel = 'Optimal'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build/packages'))
$outputRoot = if ([IO.Path]::IsPathRooted($OutputDir)) {
  [IO.Path]::GetFullPath($OutputDir)
} else {
  [IO.Path]::GetFullPath((Join-Path $repo $OutputDir))
}
$prefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputRoot -cne $allowedRoot -and -not $outputRoot.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "[mir4-package-output-authority] Package output must remain below build/packages: $outputRoot"
}

. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
$result = New-MIR4TargetPackage `
  -RepoRoot $repo `
  -Target $Target `
  -CandidateId $CandidateId `
  -SourceVersion $SourceVersion `
  -DistributionVersion $DistributionVersion `
  -OutputRoot $outputRoot

Write-Host "Built $([string]$result.archive_path)"
$result
