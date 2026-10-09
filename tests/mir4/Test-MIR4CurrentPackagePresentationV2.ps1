# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')

$verifier = Join-Path $repo 'tools/commands/mir4/Update-MIR4CurrentPackagePresentationV2Authority.ps1'
$result = & $verifier -RepoRoot $repo -Check
$v2 = Get-MIR4CurrentPackagePresentationV2 -RepoRoot $repo
if ([string]$result.status -cne 'passed-frozen-package-presentation-v2-verification' -or
    [string]$v2.record_sha256 -cne 'C33F1B568CA247108D88C4F2A109C45E29F2C77C4EE026CB4C9047BAA3A2360F' -or
    [string]$v2.package_source.fingerprint_sha256 -cne '2BE9A0C5510F6369DBE239746BB525F77952DC5E64C0C0D2DCD9E002B059779E') {
  throw '[mir4-package-presentation-v2-frozen-custody]'
}
$overwriteRejected = $false
try { & $verifier -RepoRoot $repo -RecordedAt '2026-09-15T15:00:01+10:00' | Out-Null } catch { $overwriteRejected = $_.Exception.Message -eq '[mir4-package-presentation-v2-authority-immutable-overwrite]' }
if (-not $overwriteRejected) { throw '[mir4-package-presentation-v2-overwrite]' }
Write-Host '[ok] MIR4 package presentation V2 is frozen historical evidence.'
