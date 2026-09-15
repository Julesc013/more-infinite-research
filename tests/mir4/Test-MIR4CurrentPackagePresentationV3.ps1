# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
$writer = Join-Path $repo 'tools/commands/mir4/Update-MIR4CurrentPackagePresentationV3Authority.ps1'

& $writer -RepoRoot $repo -Check | Out-Null
$v3 = Get-MIR4CurrentPackagePresentationV3Historical -RepoRoot $repo
if ([string]$v3.record_sha256 -cne '0E66F8BD58371E54BF3783200A73423703BCC539D9538526D1BEABA05C494790' -or -not [bool]$v3.authority_invariants.package_bytes_unchanged -or [bool]$v3.authority_invariants.gameplay_semantics_changed) { throw '[mir4-package-presentation-v3-historical-receipt]' }
$scratch = Join-Path $repo ('build/mir4/test-package-presentation-v3-' + [guid]::NewGuid().ToString('N') + '.json')
$stale = $false
try { & $writer -RepoRoot $repo -Check -CheckAuthorityPath $scratch | Out-Null } catch { $stale = $_.Exception.Message -eq '[mir4-package-presentation-v3-historical-stale]' }
if (-not $stale -or (Test-Path -LiteralPath $scratch)) { throw '[mir4-package-presentation-v3-historical-check-isolation]' }
$writeRetired = $false
try { & $writer -RepoRoot $repo | Out-Null } catch { $writeRetired = $_.Exception.Message -eq '[mir4-package-presentation-v3-historical-write-retired]' }
if (-not $writeRetired) { throw '[mir4-package-presentation-v3-historical-write]' }
Write-Host '[ok] MIR4 package presentation V3 remains a frozen historical receipt.'
