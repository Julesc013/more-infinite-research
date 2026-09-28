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
  Write-Output 'MIR player startup report: passed (offline crash, archive membership, redaction, settings exclusion)'
} finally {
  $absoluteRun = [IO.Path]::GetFullPath($run)
  if (-not $absoluteRun.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove a test path outside build: $absoluteRun"
  }
  if ([IO.Directory]::Exists($absoluteRun)) { [IO.Directory]::Delete($absoluteRun, $true) }
}
