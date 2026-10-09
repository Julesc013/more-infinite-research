# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$outputRelative = Join-Path 'build/packages' ("static-package-comparison-$([Guid]::NewGuid().ToString('N'))")
$outputRoot = Join-Path $repo $outputRelative

try {
  $packageResult = & (Join-Path $repo 'tools/commands/package/Build-MIRPackage.ps1') -Target f210 -CandidateId 'MIR4-STATIC-PACKAGE-COMPARISON' -OutputDir $outputRelative -CompressionLevel Optimal
  $CandidateZip = [string]$packageResult.archive_path
  if (-not (Test-Path -LiteralPath $CandidateZip -PathType Leaf)) { throw '[mir4-static-package-comparison-candidate]' }
  . (Join-Path $repo 'tools/lib/validation/CurrentTargetPackage.ps1')
  $script:MIR4CurrentTargetPackageContext = New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target f210
  $repoInfo = Get-MIR4CurrentTargetPackageOutputText -Context $script:MIR4CurrentTargetPackageContext -RelativePath 'info.json' | ConvertFrom-Json
  $script:staticPackageChecks = 0
  function Invoke-RepoCheck {
    param([string]$Description,[scriptblock]$Script)
    $script:staticPackageChecks++
    & $Script
  }
  . (Join-Path $repo 'tools/lib/validation/runner/StaticPackage.ps1')
  if ($script:staticPackageChecks -ne 3) { throw '[mir4-static-package-comparison-check-count]' }
  Write-Host '[ok] static package exact-candidate comparison uses selected target metadata and composition bytes.'
} finally {
  if (Test-Path -LiteralPath $outputRoot) { Remove-Item -LiteralPath $outputRoot -Recurse -Force }
}
