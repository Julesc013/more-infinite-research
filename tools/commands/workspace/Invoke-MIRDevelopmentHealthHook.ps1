# MIR4-CANONICAL-DEVELOPMENT-HEALTH-HOOK
[CmdletBinding()]
param(
  [ValidateSet('SessionStart','Stop')][string]$Event = 'SessionStart',
  [Parameter(DontShow)][string]$CheckerRepoRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Codex sends its hook event on native standard input. Read it once rather than
# relying on PowerShell's pipeline enumerator, which is not connected to a
# child process' standard input. A malformed event never earns a continuation.
$eventPayload = $null
$eventReadable = $true
try {
  $rawEvent = [Console]::In.ReadToEnd()
  if (-not [string]::IsNullOrWhiteSpace($rawEvent)) { $eventPayload = $rawEvent | ConvertFrom-Json -Depth 12 }
} catch {
  $eventReadable = $false
}
$stopHookActive = $false
if ($Event -eq 'Stop') {
  if ($null -eq $eventPayload) {
    $eventReadable = $false
  } else {
    $property = $eventPayload.PSObject.Properties['stop_hook_active']
    if ($null -eq $property -or $property.Value -isnot [bool]) { $eventReadable = $false }
    else { $stopHookActive = [bool]$property.Value }
  }
}

$blockStop = $false
try {
  $sourceRepo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
  $checkerRepo = if ([string]::IsNullOrWhiteSpace($CheckerRepoRoot)) { $sourceRepo } else { $CheckerRepoRoot }
  $checker = Join-Path $sourceRepo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1'
  $reportJson = & $checker -RepoRoot $checkerRepo -Mode Hook -AsJson -MaxScanSeconds 4 -MaxEntriesPerRoot 512 -MaxWorktrees 8 -MaxBranches 64
  $report = $reportJson | ConvertFrom-Json -Depth 12
  $message = [string]$report.hook_message
  if ([string]::IsNullOrWhiteSpace($message)) { throw 'Health checker returned no advisory message.' }
  $actionable = [bool]$report.checkpoint_required
  if ($Event -eq 'Stop') {
    # Only the first Stop for actionable pressure requests a checkpoint turn.
    # A Stop triggered by that turn has stop_hook_active=true and passes, so
    # the hook cannot create an unbounded continuation loop.
    $blockStop = $eventReadable -and $actionable -and (-not $stopHookActive)
    if ($blockStop) { $message += ' Checkpoint or choose the named corrective command before stopping.' }
    elseif ($stopHookActive) { $message += ' Stop hook is already active; no further checkpoint is requested.' }
    elseif (-not $eventReadable) { $message += ' Stop event was unreadable; no checkpoint is requested.' }
    else { $message += ' No workspace checkpoint action is required.' }
  }
} catch {
  $message = "MIR development health advisory unavailable: $($_.Exception.Message). Run .\\tools\\commands\\workspace\\Test-MIRDevelopmentHealth.ps1 manually."
  $blockStop = $false
}

# Advisory only: no PreTool hook and no write. A block decision is emitted
# once for a fresh, actionable Stop. All repeated or non-actionable Stops pass
# through without a decision; normal Git/GitHub work is never intercepted.
$output = [ordered]@{ systemMessage = $message }
if ($Event -eq 'Stop' -and $blockStop) {
  $output.decision = 'block'
  $output.reason = $message
}
[pscustomobject]$output | ConvertTo-Json -Compress