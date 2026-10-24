Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '../../../../lib/validation/NativeProbeCommon.ps1')

# NativeProbeCommon remains the single implementation authority for the
# legacy Common contract: Write-MIR441Json retains AppendAllText JSONL writes,
# and Assert-MIR441MainAncestor retains git merge-base --is-ancestor
# ancestry validation for the existing release callers.
if (-not (Get-Command Get-MIR4BootstrapRecordSha256 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../../../../lib/mir4/BootstrapMaterialization.ps1')
}
