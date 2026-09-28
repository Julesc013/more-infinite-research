$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$buildRoot = (Resolve-Path -LiteralPath (Join-Path $repo 'build')).Path
$run = Join-Path $buildRoot ('player-report-' + [guid]::NewGuid().ToString('N'))
$userData = Join-Path $run 'userdata'
$mods = Join-Path $userData 'mods'
$output = Join-Path $run 'output'

try {
  New-Item -ItemType Directory -Force -Path $mods, $output | Out-Null
  [IO.File]::WriteAllText((Join-Path $userData 'factorio-current.log'),
    'Factorio failed before MIR loaded at C:\Users\Example\AppData\Roaming\Factorio token=private123',
    [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $mods 'mod-list.json'),
    '{"mods":[{"name":"base","enabled":true},{"name":"more-infinite-research","enabled":true}]}',
    [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllBytes((Join-Path $mods 'mod-settings.dat'), [byte[]](1, 2, 3, 4))

  & (Join-Path $repo 'scripts/Collect-MIRPlayerReport.ps1') -FactorioUserData $userData -OutputDirectory $output | Out-Null
  $bundles = @(Get-ChildItem -LiteralPath $output -File -Filter 'MIR-support-*.zip')
  if ($bundles.Count -ne 1) { throw 'The offline startup collector must produce exactly one report.' }
  $zip = [IO.Compression.ZipFile]::OpenRead($bundles[0].FullName)
  try {
    $names = @($zip.Entries | ForEach-Object FullName)
    foreach ($required in @('logs/factorio-current.log', 'mods/mod-list.json', 'README.txt', 'manifest.json')) {
      if ($names -notcontains $required) { throw "Missing support report entry: $required" }
    }
    if ($names -contains 'mod-settings.dat') { throw 'Binary startup settings must not enter the report.' }
    $reader = [IO.StreamReader]::new($zip.GetEntry('logs/factorio-current.log').Open())
    try { $logText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ($logText -match 'Example|private123' -or $logText -notmatch 'failed before MIR loaded') {
      throw 'The report must retain the startup failure while redacting user paths and tokens.'
    }
    $reader = [IO.StreamReader]::new($zip.GetEntry('manifest.json').Open())
    try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    if ($manifest.kind -cne 'MIRPlayerStartupReportV1' -or $manifest.logs.Count -ne 1 -or $manifest.mod_settings.included -ne $false) {
      throw 'The report manifest does not describe the offline startup failure accurately.'
    }
  } finally { $zip.Dispose() }

  [IO.File]::WriteAllText((Join-Path $userData 'factorio-previous.log'), 'Previous Factorio startup failed before MIR loaded', [Text.UTF8Encoding]::new($false))
  $mirZip = Join-Path $mods 'more-infinite-research_4.2.0.zip'
  [IO.File]::WriteAllBytes($mirZip, [byte[]](5, 6, 7, 8))
  $locks = @()
  try {
    foreach ($path in @((Join-Path $userData 'factorio-current.log'), (Join-Path $mods 'mod-list.json'),
        (Join-Path $mods 'mod-settings.dat'), $mirZip)) {
      $locks += [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    }
    $lockedOutput = Join-Path $run 'locked-output'
    New-Item -ItemType Directory -Force -Path $lockedOutput | Out-Null
    & (Join-Path $repo 'scripts/Collect-MIRPlayerReport.ps1') -FactorioUserData $userData -OutputDirectory $lockedOutput | Out-Null
    $lockedBundles = @(Get-ChildItem -LiteralPath $lockedOutput -File -Filter 'MIR-support-*.zip')
    if ($lockedBundles.Count -ne 1) { throw 'Locked startup files must still produce one partial report.' }
    $lockedReport = [IO.Compression.ZipFile]::OpenRead($lockedBundles[0].FullName)
    try {
      $names = @($lockedReport.Entries | ForEach-Object FullName)
      if ($names -notcontains 'logs/factorio-previous.log' -or $names -contains 'logs/factorio-current.log' -or
          $names -contains 'mods/mod-list.json') { throw 'The partial report must retain readable evidence and omit locked files.' }
      $reader = [IO.StreamReader]::new($lockedReport.GetEntry('manifest.json').Open())
      try { $lockedManifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
      if ($lockedManifest.logs.Count -ne 1 -or $lockedManifest.mod_list -or $lockedManifest.mod_settings -or
          $lockedManifest.mir_archives.Count -ne 0) { throw 'The partial manifest claims unavailable evidence.' }
      $notes = @($lockedManifest.notes) -join '|'
      foreach ($name in @('factorio-current.log', 'mod-list.json', 'mod-settings.dat', 'more-infinite-research_4.2.0.zip')) {
        if (-not $notes.Contains($name)) { throw "Missing unavailable-file note: $name" }
      }
      if ($notes.Contains('No MIR ZIP was found') -or $notes.Contains('No Factorio current or previous log was found')) {
        throw 'The partial report must distinguish locked files from absent files.'
      }
    } finally { $lockedReport.Dispose() }
  } finally {
    foreach ($lock in $locks) { $lock.Dispose() }
  }
  Write-Output 'MIR player startup report: passed (offline crash, redaction, settings exclusion, locked-file partial report)'
} finally {
  $absoluteRun = [IO.Path]::GetFullPath($run)
  if (-not $absoluteRun.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove a test path outside build: $absoluteRun"
  }
  if ([IO.Directory]::Exists($absoluteRun)) { [IO.Directory]::Delete($absoluteRun, $true) }
}
