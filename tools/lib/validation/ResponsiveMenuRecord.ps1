# Canonical record validator for the direct-library responsive-menu owner.
# Record validation alone does not establish a live process or native acceptance.
function Read-MIRDirectLibraryResponsiveMenuRecord {
  param(
    [Parameter(Mandatory)]$Observation,
    [Parameter(Mandatory)][int]$OwnedProcessId,
    [Parameter(Mandatory)][datetime]$OwnedProcessStartUtc,
    [Parameter(Mandatory)][long]$LaunchBeforeQpc,
    [Parameter(Mandatory)][long]$LaunchAfterQpc,
    [Parameter(Mandatory)][long]$ClockFrequency,
    [Parameter(Mandatory)][string]$ArtifactRoot,
    [ValidateRange(1,3600)][int]$TimeoutSeconds=300
  )
  function Assert-MenuRecord([bool]$Value,[string]$Code){if(-not $Value){throw "[mir-responsive-menu-$Code]"}}
  Assert-MenuRecord ($OwnedProcessId-gt0-and$ClockFrequency-gt0-and$LaunchBeforeQpc-gt0-and$LaunchAfterQpc-ge$LaunchBeforeQpc) 'launch-clock'
  $o=$Observation
  Assert-MenuRecord ([string]$o.status-ceq'owned-menu-settings-response-observed'-and[int]$o.process_id-eq$OwnedProcessId) 'response-status-and-pid'
  Assert-MenuRecord ([long]$o.launch_qpc-eq$LaunchBeforeQpc-and[long]$o.clock_frequency-eq$ClockFrequency) 'same-clock'
  $main=$o.first_menu;$response=$o.response;$action=$o.action
  Assert-MenuRecord ([string]$action.kind-ceq'owned-window-settings-click'-and[int]$action.process_id-eq$OwnedProcessId) 'owned-action'
  $root=(Resolve-Path -LiteralPath $ArtifactRoot).Path.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
  foreach($frame in @($main,$response)){
    $capture=$frame.capture;$window=$capture.window
    Assert-MenuRecord ([int]$window.process_id-eq$OwnedProcessId-and([datetime]$window.start_utc).ToUniversalTime()-eq$OwnedProcessStartUtc.ToUniversalTime()) 'frame-process-identity'
    Assert-MenuRecord ([long]$window.handle-ne0-and[long]$window.handle-eq[long]$action.window_handle) 'frame-window-identity'
    Assert-MenuRecord ([string]$capture.method-ceq'owned-hwnd-printwindow-client') 'owned-capture-method'
    Assert-MenuRecord ([int]$frame.ocr.width-eq[int]$window.width-and[int]$frame.ocr.height-eq[int]$window.height-and[int]$window.width-ge100-and[int]$window.height-ge100-and[int]$window.width-le4096-and[int]$window.height-le4096) 'frame-shape'
    $path=[IO.Path]::GetFullPath([string]$capture.path)
    Assert-MenuRecord ($path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)-and(Test-Path -LiteralPath $path -PathType Leaf)) 'frame-custody'
    $file=Get-Item -LiteralPath $path
    Assert-MenuRecord ($file.Length-gt0-and$file.Length-le32MB-and-not($file.Attributes-band[IO.FileAttributes]::ReparsePoint)) 'frame-file'
    Assert-MenuRecord ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash-ceq[string]$capture.sha256) 'frame-hash'
    Assert-MenuRecord ([long]$capture.capture_started_qpc-le[long]$capture.capture_completed_qpc-and[long]$capture.capture_completed_qpc-le[long]$frame.observed_qpc) 'frame-clock'
    $lines=@($frame.ocr.lines|ForEach-Object {[string]$_.normalized})
    Assert-MenuRecord (@($lines|Where-Object {$_-match'(^| )(error|notice|failed to load|loading mods|loading sprites)( |$)'}).Count-eq0) 'frame-not-loading-or-error'
  }
  $mainLines=@($main.ocr.lines|ForEach-Object {[string]$_.normalized})
  $responseLines=@($response.ocr.lines|ForEach-Object {[string]$_.normalized})
  Assert-MenuRecord (@('single player','multiplayer','settings'|Where-Object {$_-notin$mainLines}).Count-eq0-and('main menu'-in$mainLines-or'mods'-in$mainLines)) 'main-menu-state'
  Assert-MenuRecord (@('graphics','controls','interface'|Where-Object {$_-notin$responseLines}).Count-eq0-and('sounds'-in$responseLines-or'mod settings'-in$responseLines)-and-not('single player'-in$responseLines)) 'changed-settings-state'
  Assert-MenuRecord ([long]$main.capture.capture_started_qpc-ge$LaunchAfterQpc-and[long]$main.observed_qpc-le[long]$action.posted_qpc-and[long]$action.posted_qpc-lt[long]$response.capture.capture_started_qpc) 'challenge-response-order'
  Assert-MenuRecord ([int]$action.x-ge0-and[int]$action.y-ge0-and[int]$action.x-lt[int]$main.ocr.width-and[int]$action.y-lt[int]$main.ocr.height) 'action-bounds'
  $seconds=([long]$response.observed_qpc-$LaunchBeforeQpc)/[double]$ClockFrequency
  Assert-MenuRecord ($seconds-gt0-and$seconds-le$TimeoutSeconds-and[Math]::Abs([double]$o.confirmed_response_seconds-$seconds)-le1e-9) 'endpoint-seconds'
  Assert-MenuRecord ([long]$response.observed_qpc-ge[long]$response.capture.capture_completed_qpc) 'response-observed'
  [pscustomobject][ordered]@{
    status='validated-recorded-menu-interaction-response'
    endpoint_class='ordinary-responsive-menu'
    elapsed_seconds=$seconds
    elapsed_lower_bound_seconds=([long]$response.observed_qpc-$LaunchAfterQpc)/[double]$ClockFrequency
    process_start_bracket_seconds=($LaunchAfterQpc-$LaunchBeforeQpc)/[double]$ClockFrequency
    response_observed_qpc=[long]$response.observed_qpc
    clock_frequency=$ClockFrequency
    process_id=$OwnedProcessId
    first_menu_sha256=[string]$main.capture.sha256
    settings_response_sha256=[string]$response.capture.sha256
    interaction_response_seconds=([long]$response.observed_qpc-[long]$action.posted_qpc)/[double]$ClockFrequency
    observer_max_iteration_seconds=[double]$o.observer_max_iteration_seconds
    poll_interval_milliseconds=[int]$o.poll_interval_milliseconds
    shutdown_and_cleanup_included=$false
    claims_live_process_or_native_acceptance=$false
  }
}
