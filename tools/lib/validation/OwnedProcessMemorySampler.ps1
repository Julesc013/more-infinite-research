Set-StrictMode -Version Latest

$script:MIROwnedProcessMemoryIntervalMilliseconds = 250
$script:MIROwnedProcessMemoryMaximumDurationSeconds = 900
$script:MIROwnedProcessMemoryMaximumObservations = 12000
$script:MIROwnedProcessMemoryMaximumOutputBytes = 8MB
$script:MIROwnedProcessMemoryPhases = @('initial', 'rejoin', 'restart')
$script:MIROwnedProcessMemoryRoles = @('server', 'client-en', 'client-de')

function Set-MIROwnedProcessMemoryIncomplete {
  param([Parameter(Mandatory)]$Sampler,[Parameter(Mandatory)][string]$Reason)
  if (-not $Sampler.incomplete_reasons.Contains($Reason)) { [void]$Sampler.incomplete_reasons.Add($Reason) }
  $Sampler.incomplete = $true
}

function Set-MIROwnedProcessMemoryNextDue {
  param([Parameter(Mandatory)]$Sampler)
  $elapsed = [double]($Sampler.clock.Elapsed.TotalMilliseconds)
  $interval = [double]($Sampler.target_interval_milliseconds)
  $Sampler.next_due_monotonic_milliseconds = ([Math]::Floor($elapsed / $interval) + 1) * $interval
}

function New-MIROwnedProcessMemorySampler {
  param([Parameter(Mandatory)][object[]]$ExpectedSlots)
  if ($ExpectedSlots.Count -lt 1 -or $ExpectedSlots.Count -gt 9) { throw '[mir5-owned-process-memory-slot-count]' }
  $expected = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($slot in $ExpectedSlots) {
    $phase = [string]$slot.phase
    $role = [string]$slot.role
    if ($phase -notin $script:MIROwnedProcessMemoryPhases -or $role -notin $script:MIROwnedProcessMemoryRoles) {
      throw '[mir5-owned-process-memory-slot]'
    }
    $key = "$phase/$role"
    if ($expected.ContainsKey($key)) { throw '[mir5-owned-process-memory-duplicate-slot]' }
    $expected.Add($key, [pscustomobject][ordered]@{ phase=$phase; role=$role })
  }
  $clock = [Diagnostics.Stopwatch]::StartNew()
  [pscustomobject]@{
    kind = 'MIR5OwnedProcessMemoryObservationV1'
    target_interval_milliseconds = $script:MIROwnedProcessMemoryIntervalMilliseconds
    maximum_duration_seconds = $script:MIROwnedProcessMemoryMaximumDurationSeconds
    maximum_observations = $script:MIROwnedProcessMemoryMaximumObservations
    maximum_serialized_bytes = [int64]$script:MIROwnedProcessMemoryMaximumOutputBytes
    expected_slots = $expected
    registrations = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    observations = [Collections.Generic.List[object]]::new()
    incomplete_reasons = [Collections.Generic.List[string]]::new()
    incomplete = $false
    closed = $false
    clock = $clock
    next_due_monotonic_milliseconds = 0.0
    cycle = 0
  }
}

function Register-MIROwnedProcessMemoryProcess {
  param(
    [Parameter(Mandatory)]$Sampler,
    [Parameter(Mandatory)][ValidateSet('initial', 'rejoin', 'restart')][string]$Phase,
    [Parameter(Mandatory)][ValidateSet('server', 'client-en', 'client-de')][string]$Role,
    [Parameter(Mandatory)][Diagnostics.Process]$Process
  )
  $key = "$Phase/$Role"
  if ($Sampler.closed -or -not $Sampler.expected_slots.ContainsKey($key) -or $Sampler.registrations.ContainsKey($key)) {
    Set-MIROwnedProcessMemoryIncomplete -Sampler $Sampler -Reason 'registration-contract'
    return $null
  }
  try {
    if ($Process.HasExited) { throw 'exited' }
    $registration = [pscustomobject][ordered]@{
      phase = $Phase; role = $Role; process = $Process; pid = [int]$Process.Id
      start_utc = $Process.StartTime.ToUniversalTime().ToString('o')
      closed = $false; observation_count = 0
    }
    $Sampler.registrations.Add($key, $registration)
    return $registration
  } catch {
    Set-MIROwnedProcessMemoryIncomplete -Sampler $Sampler -Reason 'registration-process-unreadable'
    return $null
  }
}

function Add-MIROwnedProcessMemorySample {
  param([Parameter(Mandatory)]$Sampler)
  if ($Sampler.closed -or $Sampler.incomplete) { return }
  $elapsed = [double]($Sampler.clock.Elapsed.TotalMilliseconds)
  if ($elapsed -gt ([double]($Sampler.maximum_duration_seconds) * 1000)) {
    Set-MIROwnedProcessMemoryIncomplete -Sampler $Sampler -Reason 'duration-limit'
    return
  }
  if ($elapsed -lt [double]($Sampler.next_due_monotonic_milliseconds)) { return }
  Set-MIROwnedProcessMemoryNextDue -Sampler $Sampler
  $active = @($Sampler.registrations.Values | Where-Object { -not $_.closed } | Sort-Object phase, role)
  if ($active.Count -eq 0) { return }
  if (($Sampler.observations.Count + $active.Count) -gt [int]($Sampler.maximum_observations)) {
    Set-MIROwnedProcessMemoryIncomplete -Sampler $Sampler -Reason 'observation-limit'
    return
  }
  $Sampler.cycle++
  foreach ($registration in $active) {
    try {
      $process = $registration.process
      if ($process.HasExited) { throw 'exited' }
      $process.Refresh()
      if ([int]$process.Id -ne [int]$registration.pid -or
          $process.StartTime.ToUniversalTime().ToString('o') -cne [string]$registration.start_utc) {
        Set-MIROwnedProcessMemoryIncomplete -Sampler $Sampler -Reason 'process-identity-drift'
        return
      }
      $Sampler.observations.Add([pscustomobject][ordered]@{
        cycle = [int]($Sampler.cycle)
        elapsed_monotonic_milliseconds = [Math]::Round([double]($Sampler.clock.Elapsed.TotalMilliseconds), 3)
        phase = [string]$registration.phase
        role = [string]$registration.role
        pid = [int]$registration.pid
        start_utc = [string]$registration.start_utc
        working_set_bytes = [int64]$process.WorkingSet64
        private_bytes = [int64]$process.PrivateMemorySize64
      })
      $registration.observation_count++
    } catch {
      Set-MIROwnedProcessMemoryIncomplete -Sampler $Sampler -Reason 'process-sample-unreadable'
      return
    }
  }
}

function Complete-MIROwnedProcessMemoryProcess {
  param([Parameter(Mandatory)]$Sampler,$Registration)
  if ($null -eq $Registration -or $Sampler.closed -or $Registration.closed) { return }
  if (-not $Sampler.registrations.ContainsKey("$($Registration.phase)/$($Registration.role)")) {
    Set-MIROwnedProcessMemoryIncomplete -Sampler $Sampler -Reason 'completion-contract'
    return
  }
  Add-MIROwnedProcessMemorySample -Sampler $Sampler
  $Registration.closed = $true
  if ([int]$Registration.observation_count -lt 1) {
    Set-MIROwnedProcessMemoryIncomplete -Sampler $Sampler -Reason 'missing-process-observation'
  }
}

function Get-MIROwnedProcessMemorySleepMilliseconds {
  param([Parameter(Mandatory)]$Sampler,[ValidateRange(1,200)][int]$MaximumDelayMilliseconds=200)
  if ($Sampler.closed -or $Sampler.incomplete -or @($Sampler.registrations.Values | Where-Object { -not $_.closed }).Count -eq 0) {
    return $MaximumDelayMilliseconds
  }
  $remaining = [double]($Sampler.next_due_monotonic_milliseconds) - [double]($Sampler.clock.Elapsed.TotalMilliseconds)
  return [Math]::Max(1, [Math]::Min($MaximumDelayMilliseconds, [int][Math]::Ceiling($remaining)))
}

function ConvertTo-MIROwnedProcessMemoryObservationBytes {
  param([Parameter(Mandatory)]$Receipt)
  $json = $Receipt | ConvertTo-Json -Depth 8 -Compress
  return ,[Text.UTF8Encoding]::new($false).GetBytes($json)
}

function Get-MIROwnedProcessMemoryObservationReceipt {
  param([Parameter(Mandatory)]$Sampler)
  foreach ($key in $Sampler.expected_slots.Keys) {
    if (-not $Sampler.registrations.ContainsKey($key)) { Set-MIROwnedProcessMemoryIncomplete -Sampler $Sampler -Reason 'missing-expected-process' }
    elseif (-not $Sampler.registrations[$key].closed) { Set-MIROwnedProcessMemoryIncomplete -Sampler $Sampler -Reason 'open-process-registration' }
  }
  $Sampler.closed = $true
  $receipt = [ordered]@{
    kind = $Sampler.kind
    status = $(if ($Sampler.incomplete) { 'incomplete-observation' } else { 'complete-observation' })
    performance_acceptance = $false
    target_interval_milliseconds = [int]($Sampler.target_interval_milliseconds)
    maximum_duration_seconds = [int]($Sampler.maximum_duration_seconds)
    maximum_observations = [int]($Sampler.maximum_observations)
    maximum_serialized_bytes = [int64]$script:MIROwnedProcessMemoryMaximumOutputBytes
    observations = @($Sampler.observations)
    incomplete_reasons = @($Sampler.incomplete_reasons)
  }
  $bytes = ConvertTo-MIROwnedProcessMemoryObservationBytes -Receipt $receipt
  if ($bytes.Length -gt [int64]$script:MIROwnedProcessMemoryMaximumOutputBytes) {
    $Sampler.observations.Clear()
    Set-MIROwnedProcessMemoryIncomplete -Sampler $Sampler -Reason 'serialized-output-limit'
    $receipt.status = 'incomplete-observation'
    $receipt.observations = @()
    $receipt.incomplete_reasons = @($Sampler.incomplete_reasons)
    $bytes = ConvertTo-MIROwnedProcessMemoryObservationBytes -Receipt $receipt
  }
  if ($bytes.Length -gt [int64]$script:MIROwnedProcessMemoryMaximumOutputBytes) {
    throw '[mir5-owned-process-memory-receipt-limit]'
  }
  return [pscustomobject]$receipt
}

function Write-MIROwnedProcessMemoryObservationReceipt {
  param(
    [Parameter(Mandatory)]$Sampler,
    [Parameter(Mandatory)][string]$Path
  )
  $receipt = Get-MIROwnedProcessMemoryObservationReceipt -Sampler $Sampler
  $bytes = ConvertTo-MIROwnedProcessMemoryObservationBytes -Receipt $receipt
  if ($bytes.Length -gt [int64]$script:MIROwnedProcessMemoryMaximumOutputBytes) {
    throw '[mir5-owned-process-memory-receipt-limit]'
  }
  [IO.File]::WriteAllBytes($Path, $bytes)
  return $receipt
}
