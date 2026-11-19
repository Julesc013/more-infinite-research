param([string]$CollectorPath = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$collector = $CollectorPath
if ([string]::IsNullOrWhiteSpace($collector)) { $collector = Join-Path $repoRoot 'scripts/Collect-MIRPlayerReport.ps1' }
$testRoot = Join-Path $repoRoot ('build/tmp/player-report-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$encoding = [Text.UTF8Encoding]::new($false)
$passed = $false
$cases = 0

function Assert-Report {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Write-TestText {
  param([string]$Path, [string]$Value)
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
  [IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Get-BytesHash {
  param([byte[]]$Bytes)
  $algorithm = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($algorithm.ComputeHash($Bytes)).Replace('-', '') }
  finally { $algorithm.Dispose() }
}

function Invoke-Report {
  param([string]$UserData, [hashtable]$Extra = @{})
  $parameters = @{FactorioUserData = $UserData; OutputDirectory = (Join-Path $testRoot 'reports')}
  foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
  $messages = @(& $collector @parameters 3>$null)
  $paths = @($messages | Where-Object { $_ -is [string] -and $_.StartsWith('MIR support report: ') })
  Assert-Report ($paths.Count -eq 1) 'Collector did not return exactly one report path.'
  return $paths[0].Substring('MIR support report: '.Length)
}

function Read-Report {
  param([string]$Path)
  $zip = [IO.Compression.ZipFile]::OpenRead($Path)
  $files = @{}
  try {
    foreach ($entry in $zip.Entries) {
      Assert-Report (-not $files.ContainsKey($entry.FullName)) 'Duplicate ZIP member.'
      $inputStream = $entry.Open()
      $buffer = [IO.MemoryStream]::new()
      try { $inputStream.CopyTo($buffer); $files[$entry.FullName] = $buffer.ToArray() }
      finally { $inputStream.Dispose(); $buffer.Dispose() }
    }
  } finally { $zip.Dispose() }
  $manifest = $encoding.GetString($files['manifest.json']) | ConvertFrom-Json
  return @{files = $files; manifest = $manifest}
}

try {
  $userData = Join-Path $testRoot 'user-data'
  $logPath = Join-Path $userData 'factorio-current.log'
  $startupLog = @'
Factorio 2.1.24
Loading mod more-infinite-research 5.0.21014 (data.lua)
Loading mod example 1.2.3 (data.lua)
  0.105 Loading mod example 1.2.3 (data-updates.lua)
C:\Users\Example\AppData\Roaming\Factorio\factorio-current.log
/home/Example/.factorio/factorio-current.log
mail=example@example.invalid
password="secret with spaces" token='another secret' api_key=private-token
Authorization: Bearer private-authorization
fatal: retained error
'@
  Write-TestText $logPath $startupLog
  Write-TestText (Join-Path $userData 'mods/mod-list.json') '{"mods":[{"name":"example","enabled":true}]}'
  Write-TestText (Join-Path $userData 'mods/mod-settings.dat') 'raw-settings-secret'
  Write-TestText (Join-Path $userData 'mods/more-infinite-research_5.0.21014.zip') 'synthetic MIR archive identity'
  Write-TestText (Join-Path $userData 'mods/example_1.2.3.zip') 'unrelated archive must not be included'
  Write-TestText (Join-Path $userData 'mods/example_1.2.2.zip') 'merely installed old version must not be selected'
  Write-TestText (Join-Path $userData 'player-data.json') '{"token":"unrelated-credential-file"}'
  Write-TestText (Join-Path $userData 'config/config.ini') 'unrelated configuration'
  Write-TestText (Join-Path $userData 'saves/unselected.zip') 'unselected-save-secret'
  Write-TestText (Join-Path $userData 'unrelated.txt') 'unrelated private file'

  $block = ('x' * 1023) + "`n"
  $longLog = "HEADER: Factorio 2.1.24; mod example 1.2.3`n" + ($block * 5120) +
    "MIDDLE-ONLY-MARKER`n" + ($block * 5120) + "TAIL: exact fatal error`n"
  Write-TestText $logPath $longLog
  $sourceBytes = [IO.File]::ReadAllBytes($logPath)
  $report = Read-Report (Invoke-Report $userData)
  $log = $encoding.GetString($report.files['logs/factorio-current.log'])
  Assert-Report ($log.Contains('HEADER: Factorio 2.1.24') -and $log.Contains('TAIL: exact fatal error')) 'Header or tail was lost.'
  $row = $report.manifest.logs[0]
  Assert-Report ($row.status -eq 'truncated' -and $row.tail_truncated) 'Oversized log not marked truncated.'
  Assert-Report (-not $log.Contains('MIDDLE-ONLY-MARKER') -and $log.Contains('MIR collector omitted')) 'Log omission is not explicit.'
  Assert-Report ($row.source_byte_ranges.Count -eq 2 -and $row.source_byte_ranges[0].start -eq 0 -and
    $row.source_byte_ranges[1].end -eq $sourceBytes.Length -and
    $row.source_byte_ranges[0].end -lt $row.source_byte_ranges[1].start) 'Source byte ranges do not describe the actual cuts.'
  Assert-Report ($log.StartsWith($encoding.GetString($sourceBytes, 0, [int]$row.source_byte_ranges[0].end))) 'Header range differs from captured prefix.'
  $tailStart = [int]$row.source_byte_ranges[1].start
  Assert-Report ($log.EndsWith($encoding.GetString($sourceBytes, $tailStart, $sourceBytes.Length - $tailStart))) 'Tail range differs from captured suffix.'
  Assert-Report ($row.captured_sha256 -eq (Get-BytesHash $report.files['logs/factorio-current.log'])) 'Truncated log hash differs.'
  Write-TestText $logPath $startupLog
  $cases++

  $report = Read-Report (Invoke-Report $userData)
  Assert-Report ($report.files.Count -eq 4) 'Default allowlist copied unexpected files.'
  $log = $encoding.GetString($report.files['logs/factorio-current.log'])
  Assert-Report ($log.Contains('fatal: retained error') -and $log.Contains('Loading mod example 1.2.3')) 'Useful startup/error evidence was lost.'
  foreach ($secret in @('secret with spaces', 'another secret', 'private-token', 'private-authorization',
      'example@example.invalid', 'C:\Users\Example', '/home/Example')) {
    Assert-Report (-not $log.Contains($secret)) ('Log redaction missed: ' + $secret)
  }
  Assert-Report ($report.manifest.logs[1].status -eq 'missing') 'Missing previous log was not recorded.'
  Assert-Report ($report.manifest.runtime_exports.Count -eq 2) 'Runtime export coverage missing.'
  foreach ($row in $report.manifest.runtime_exports) { Assert-Report ($row.status -eq 'missing') 'Absent runtime export was not recorded.' }
  Assert-Report ($report.manifest.mod_settings.status -eq 'hash-only' -and -not $report.manifest.mod_settings.included) 'Default collection included raw settings.'
  Assert-Report ($report.manifest.save.status -eq 'not-selected' -and -not $report.manifest.save.included) 'Default collection selected a save.'
  Assert-Report (-not $report.manifest.contains_unredacted_inputs) 'Raw input flag wrong for default report.'
  Assert-Report ($report.manifest.mir_archives.Count -eq 1 -and $report.manifest.mir_archives[0].sha256 -eq
    (Get-BytesHash ([IO.File]::ReadAllBytes((Join-Path $userData 'mods/more-infinite-research_5.0.21014.zip'))))) 'MIR identity hash differs.'
  Assert-Report ($report.manifest.logs[0].captured_sha256 -eq (Get-BytesHash $report.files['logs/factorio-current.log'])) 'Log hash is not the captured redacted bytes.'
  Assert-Report ($report.manifest.log_observed_archives.Count -eq 2) 'Mod observations were lost, duplicated, or guessed from installed ZIPs.'
  $exampleIdentity = @($report.manifest.log_observed_archives | Where-Object { $_.observed_mod_name -eq 'example' })[0]
  Assert-Report ($exampleIdentity.observed_mod_version -eq '1.2.3' -and $exampleIdentity.status -eq 'hash-only' -and
    $exampleIdentity.sha256 -ceq (Get-BytesHash ([IO.File]::ReadAllBytes((Join-Path $userData 'mods/example_1.2.3.zip'))))) 'Observed package filename/hash association differs.'
  $cases++

  $identityData = Join-Path $testRoot 'identity-data'
  Write-TestText (Join-Path $identityData 'factorio-current.log') @'
Loading mod archived 2.3.4 (data.lua)
Loading mod missing 0.0.1 (data.lua)
Loading mod unpacked 1.2.3 (data.lua)
Loading mod oversized 9.8.7 (data.lua)
Loading mod ../escape 1.0.0 (data.lua)
'@
  $packagePath = Join-Path $identityData 'mods/archived_2.3.4.zip'
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($packagePath))
  $package = [IO.Compression.ZipFile]::Open($packagePath, [IO.Compression.ZipArchiveMode]::Create)
  try { [void]$package.CreateEntry('archived_2.3.4/info.json') } finally { $package.Dispose() }
  Write-TestText (Join-Path $identityData 'mods/unpacked_1.2.3/info.json') '{}'
  $file = [IO.File]::Create((Join-Path $identityData 'mods/oversized_9.8.7.zip'))
  try { $file.SetLength(128MB + 1) } finally { $file.Dispose() }
  Write-TestText (Join-Path $identityData 'escape_1.0.0.zip') 'must not inspect outside mods'
  $report = Read-Report (Invoke-Report $identityData)
  $identities = @{}
  foreach ($row in $report.manifest.log_observed_archives) { $identities[$row.observed_mod_name] = $row }
  Assert-Report ($identities.Count -eq 4 -and $report.files.Count -eq 3) 'Unsafe name was followed or dependency archives were copied.'
  Assert-Report ($identities['archived'].status -eq 'hash-only' -and
    $identities['archived'].sha256 -ceq (Get-BytesHash ([IO.File]::ReadAllBytes($packagePath)))) 'Observed real ZIP identity differs.'
  Assert-Report ($identities['missing'].status -eq 'missing' -and -not $identities['missing'].unpacked_candidate_present) 'Missing archive association was hidden.'
  Assert-Report ($identities['unpacked'].status -eq 'missing' -and $identities['unpacked'].unpacked_candidate_present) 'Unpacked candidate was mistaken for an archive identity.'
  Assert-Report ($identities['oversized'].status -eq 'omitted-size' -and $identities['oversized'].limit_bytes -eq 128MB -and
    $identities['oversized'].bytes_read -eq 0) 'Archive hash bound read an oversized package.'
  $cases++

  $observations = [Text.StringBuilder]::new()
  for ($index = 0; $index -lt 4097; $index++) {
    [void]$observations.Append("Loading mod inventory-$index 1.0.0 (data.lua)`n")
  }
  Write-TestText (Join-Path $identityData 'factorio-current.log') $observations.ToString()
  $report = Read-Report (Invoke-Report $identityData)
  Assert-Report ($report.manifest.log_observed_archives.Count -eq 4096 -and
    $report.manifest.logs[0].observed_mod_versions.Count -eq 4096 -and
    $report.manifest.logs[0].mod_observations_truncated) 'Observed-mod inventory cap is too small or silently truncates.'
  Assert-Report ($report.manifest.log_observed_archives[4095].observed_mod_name -eq 'inventory-4095' -and
    $report.manifest.log_observed_archive_limits.max_observations -eq 4096) 'Large-pack metadata bound does not match its manifest.'
  $cases++

  $budgetData = Join-Path $testRoot 'budget-data'
  $reportBudgetMods = Join-Path $budgetData 'mods'
  [void][IO.Directory]::CreateDirectory($reportBudgetMods)
  for ($index = 1; $index -le 5; $index++) {
    [IO.File]::WriteAllBytes((Join-Path $reportBudgetMods "more-infinite-research_1.0.$index.zip"), [byte[]]@())
  }
  # Make directory metadata stale through real file growth after enumeration.
  # This also models link metadata differing from the opened target's length,
  # without requiring Windows symlink privileges. Files are sparse where supported.
  function Get-ChildItem {
    param([string]$LiteralPath, [switch]$File, [string]$Filter)
    $listed = @(Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters)
    if ($LiteralPath -ceq $reportBudgetMods -and $File -and $Filter -ceq 'more-infinite-research_*.zip') {
      foreach ($item in $listed) {
        Assert-Report ($item.Length -eq 0) 'Budget fixture did not capture the original directory length.'
        $grown = [IO.File]::OpenWrite($item.FullName)
        try { $grown.SetLength(128MB) } finally { $grown.Dispose() }
      }
    }
    return $listed
  }
  try { $report = Read-Report (Invoke-Report $budgetData) }
  finally { Remove-Item -LiteralPath Function:Get-ChildItem }
  Assert-Report ($report.manifest.mir_archives.Count -eq 5) ('MIR budget fixture inventory is unavailable: ' + ($Error | Select-Object -First 1))
  $readTotal = ($report.manifest.mir_archives | Measure-Object -Property bytes_read -Sum).Sum
  Assert-Report ($readTotal -eq 512MB) 'MIR inventory exceeded its total read budget when directory metadata was stale.'
  Assert-Report ($report.manifest.mir_archives.Count -eq 5 -and
    $report.manifest.mir_archives[4].status -eq 'omitted-budget' -and
    $report.manifest.mir_archives[4].bytes_read -eq 0) 'Exhausted MIR inventory budget did not explicitly omit the next archive.'
  foreach ($row in @($report.manifest.mir_archives | Select-Object -First 4)) {
    Assert-Report ($row.status -eq 'hash-only' -and $row.source_bytes -eq 128MB -and
      $row.bytes -eq $row.source_bytes -and $row.bytes_read -eq $row.source_bytes) 'MIR identity stats used stale enumerated length.'
  }
  $cases++

  $diagnosticPath = Join-Path $userData 'script-output/more-infinite-research/mir.log'
  $profileName = 'script-output/more-infinite-research/settings/mir-settings-profile.txt'
  Write-TestText $diagnosticPath "MIR diagnostic report`npassword=diagnostic-secret`n"
  Write-TestText (Join-Path $userData $profileName) "MIRSET1:opaque-profile-example`n"
  $report = Read-Report (Invoke-Report $userData)
  Assert-Report ($report.manifest.runtime_exports[0].status -eq 'captured' -and
    $report.manifest.runtime_exports[1].status -eq 'captured') 'Existing runtime exports were omitted.'
  Assert-Report (-not $encoding.GetString($report.files['script-output/more-infinite-research/mir.log']).Contains('diagnostic-secret')) 'Runtime report redaction missed a credential.'
  Assert-Report ($encoding.GetString($report.files[$profileName]) -ceq "MIRSET1:opaque-profile-example`n") 'Full profile text changed.'
  Assert-Report ($report.manifest.runtime_exports[1].redaction.Contains('not decoded or inspected')) 'Opaque profile incorrectly claims complete redaction.'
  Assert-Report ($report.manifest.contains_unredacted_inputs) 'Opaque profile was incorrectly labelled as fully sanitized.'
  $cases++

  $savePath = Join-Path $testRoot 'selected-original.zip'
  $saveZip = [IO.Compression.ZipFile]::Open($savePath, [IO.Compression.ZipArchiveMode]::Create)
  try {
    $entryStream = $saveZip.CreateEntry('factory/level.dat').Open()
    $bytes = New-Object byte[] 196731
    $random = [Random]::new(1942)
    $random.NextBytes($bytes)
    try { $entryStream.Write($bytes, 0, $bytes.Length) } finally { $entryStream.Dispose() }
  } finally { $saveZip.Dispose() }
  $settingsBytes = New-Object byte[] 131111
  $random.NextBytes($settingsBytes)
  [IO.File]::WriteAllBytes((Join-Path $userData 'mods/mod-settings.dat'), $settingsBytes)
  $saveBytes = [IO.File]::ReadAllBytes($savePath)
  $report = Read-Report (Invoke-Report $userData @{IncludeModSettings = $true; SavePath = $savePath})
  foreach ($pair in @(@('mods/mod-settings.dat', $settingsBytes, $report.manifest.mod_settings),
      @('inputs/save.zip', $saveBytes, $report.manifest.save))) {
    Assert-Report ((Get-BytesHash $report.files[$pair[0]]) -ceq (Get-BytesHash $pair[1])) 'Selected input bytes changed.'
    Assert-Report ($pair[2].status -eq 'captured' -and $pair[2].captured_sha256 -ceq (Get-BytesHash $pair[1]) -and -not $pair[2].redacted) 'Selected input identity/status is wrong.'
  }
  Assert-Report ($report.manifest.contains_unredacted_inputs -and $report.manifest.requested_inputs_captured) 'Selected-input coverage flag is wrong.'
  Assert-Report (-not $encoding.GetString($report.files['manifest.json']).Contains($savePath)) 'Selected source path leaked.'
  Assert-Report ((Get-BytesHash ([IO.File]::ReadAllBytes($savePath))) -ceq (Get-BytesHash $saveBytes)) 'Original save was modified.'
  $cases++

  $emptyData = Join-Path $testRoot 'empty-data'
  [void][IO.Directory]::CreateDirectory($emptyData)
  $report = Read-Report (Invoke-Report $emptyData @{IncludeModSettings = $true; SavePath = (Join-Path $testRoot 'missing.zip')})
  Assert-Report ($report.manifest.mod_settings.status -eq 'missing' -and $report.manifest.save.status -eq 'missing' -and
    -not $report.manifest.requested_inputs_captured) 'Missing requested inputs were treated as captured.'
  Assert-Report ($report.files.Count -eq 2) 'Missing inputs created unexpected ZIP members.'
  $cases++

  $oversizeSettings = Join-Path $emptyData 'mods/mod-settings.dat'
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($oversizeSettings))
  $file = [IO.File]::Create($oversizeSettings)
  try { $file.SetLength(16MB + 1) } finally { $file.Dispose() }
  $oversizeSave = Join-Path $testRoot 'oversized.zip'
  $file = [IO.File]::Create($oversizeSave)
  try { $file.SetLength(1MB + 1) } finally { $file.Dispose() }
  $report = Read-Report (Invoke-Report $emptyData @{IncludeModSettings = $true; SavePath = $oversizeSave; MaxSaveMiB = 1})
  Assert-Report ($report.manifest.mod_settings.status -eq 'omitted-size' -and $report.manifest.save.status -eq 'omitted-size' -and
    -not $report.manifest.requested_inputs_captured) 'Oversized requested inputs were not reported as omitted.'
  Assert-Report ($report.files.Count -eq 2) 'Oversized raw inputs were copied despite their bounds.'
  $cases++

  $held = [IO.File]::Open($logPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try { $report = Read-Report (Invoke-Report $userData) } finally { $held.Dispose() }
  Assert-Report ($report.manifest.logs[0].status -eq 'unreadable' -and -not $report.files.ContainsKey('logs/factorio-current.log')) 'Unreadable log was not isolated and reported.'
  Assert-Report ($report.files.ContainsKey($profileName)) 'Unreadable log suppressed other useful inputs.'
  $cases++

  $passed = $true
  Write-Output "MIR player report: $cases executable ZIP cases passed."
} finally {
  if ($passed) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
  else { Write-Output "Failed collector test inputs retained at $testRoot" }
}
