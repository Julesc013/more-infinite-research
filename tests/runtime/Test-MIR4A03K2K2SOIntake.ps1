# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$CandidateZip,
  [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

. (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')

function Assert-A03Equal {
  param([object]$Actual, [object]$Expected, [string]$Code)
  if ([string]$Actual -cne [string]$Expected) { throw "$Code expected='$Expected' actual='$Actual'" }
}

function Assert-A03Sequence {
  param([object[]]$Actual, [string[]]$Expected, [string]$Code)
  $actualText = @($Actual | ForEach-Object { [string]$_ }) -join "`n"
  $expectedText = @($Expected) -join "`n"
  if ($actualText -cne $expectedText) { throw "$Code expected='$expectedText' actual='$actualText'" }
}

function Get-A03Sha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-A03NormalizedText {
  param([Parameter(Mandatory)][byte[]]$Bytes)
  return ([Text.UTF8Encoding]::new($false).GetString($Bytes)).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Assert-A03GovernedArchive {
  param(
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][string]$ExpectedSha256,
    [Parameter(Mandatory)][string]$ArchiveRoot,
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string[]]$SourceFiles,
    [Parameter(Mandatory)][string]$Code
  )
  Assert-A03Equal -Actual (Get-A03Sha256 -Path $Archive) -Expected $ExpectedSha256 -Code "$Code-hash"
  Add-Type -AssemblyName System.IO.Compression
  $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Archive).Path)
  try {
    $expectedEntries = @($SourceFiles | ForEach-Object { "$ArchiveRoot/$($_.Replace('\', '/'))" } | Sort-Object)
    $actualEntries = @($zip.Entries | ForEach-Object { [string]$_.FullName } | Sort-Object)
    Assert-A03Sequence -Actual $actualEntries -Expected $expectedEntries -Code "$Code-entries"
    foreach ($sourceFile in $SourceFiles) {
      $sourcePath = Join-Path $SourceRoot $sourceFile
      if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "$Code-source-missing $sourceFile" }
      $entry = @($zip.Entries | Where-Object { [string]$_.FullName -ceq "$ArchiveRoot/$($sourceFile.Replace('\', '/'))" })
      if ($entry.Count -ne 1) { throw "$Code-entry-count $sourceFile" }
      $stream = $entry[0].Open()
      $memory = [IO.MemoryStream]::new()
      try {
        $stream.CopyTo($memory)
        if ((Get-A03NormalizedText -Bytes $memory.ToArray()) -cne (Get-A03NormalizedText -Bytes ([IO.File]::ReadAllBytes($sourcePath)))) { throw "$Code-source-diff $sourceFile" }
      } finally {
        $memory.Dispose()
        $stream.Dispose()
      }
    }
  } finally {
    $zip.Dispose()
  }
}

$expectedCandidate = Join-Path $RepoRoot 'build/packages/development-contracts/849fc8c0a1294b3faf7445de82da1127/f210/DEVELOPMENT-A/more-infinite-research_4.2.21000.zip'
$candidate = (Resolve-Path -LiteralPath $CandidateZip).Path
Assert-A03Equal -Actual $candidate -Expected ((Resolve-Path -LiteralPath $expectedCandidate).Path) -Code '[mir4-a03-candidate-path]'
Assert-A03Equal -Actual (Get-A03Sha256 -Path $candidate) -Expected '99C020CBA2800179FF2D76EE35F58B27A97CF2A7D89993CFFE06403DC140090E' -Code '[mir4-a03-candidate-sha256]'

$engine = (Resolve-Path -LiteralPath $FactorioBin).Path
Assert-A03Equal -Actual ([string](Get-Item -LiteralPath $engine).VersionInfo.ProductVersion) -Expected '2.1.17' -Code '[mir4-a03-factorio-version]'
Assert-A03Equal -Actual (Get-A03Sha256 -Path $engine) -Expected '710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8' -Code '[mir4-a03-factorio-sha256]'

$environmentLockPath = Join-Path $RepoRoot 'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-current.lock.json'
$environmentLock = Get-Content -Raw -LiteralPath $environmentLockPath | ConvertFrom-Json -Depth 100 -DateKind String
Assert-A03Equal -Actual $environmentLock.kind -Expected 'MIR4EnvironmentLockV1' -Code '[mir4-a03-environment-lock-kind]'
Assert-A03Equal -Actual $environmentLock.capture -Expected 'engine-post-finalizer-exact' -Code '[mir4-a03-environment-lock-capture]'
Assert-A03Equal -Actual $environmentLock.digest -Expected 'sha256:93f96b639310a3e6a10e721eaf7f4db7b3ec5f15ccb877dee1dc847dcb3baf1f' -Code '[mir4-a03-environment-lock-digest]'
Assert-A03Equal -Actual $environmentLock.engine.version -Expected '2.1.17' -Code '[mir4-a03-environment-lock-engine-version]'
Assert-A03Equal -Actual $environmentLock.engine.executable_sha256 -Expected 'sha256:710b0278d3049564b122dafb3cd3d0338d0bde1cec3b7417ae1fc3fb37ab85a8' -Code '[mir4-a03-environment-lock-engine-sha256]'
Assert-A03Equal -Actual $environmentLock.mir.package_sha256 -Expected 'sha256:99c020cba2800179ff2d76ee35f58b27a97cf2a7d89993cffe06403dc140090e' -Code '[mir4-a03-environment-lock-candidate-sha256]'
if ([bool]$environmentLock.package_visible -or [bool]$environmentLock.player_mutation_authorized -or [bool]$environmentLock.prototype_write_authorized -or [bool]$environmentLock.public_support_authorized -or [bool]$environmentLock.release_authority) { throw '[mir4-a03-environment-lock-authority]' }
$expectedLockedMods = @(
  'Krastorio2|2.1.2|sha256:89989e60784ea3e94345289e063c64abfce5f35693db7b9a69d656a163620f43',
  'Krastorio2-spaced-out|2.0.13|sha256:a2eeb2e5a6119c4117bd3653979d40d305d17539e184bfa6f4ed53ef12a5f242',
  'Krastorio2Assets|2.1.0|sha256:39ef950ec8b21a40357dd0240ef8389501ee75cca82717f2773b98554da46e29',
  'Krastorio2MenuSimulations|2.1.0|sha256:3a485b449b356dc4b3eb4233de4e803b3a001259fbc251bdc9f9d9120b3c53a7',
  'flib|0.17.2|sha256:0a48c15dc0fc6c13bb3fe8293ba6cb35a07f3b0f37d37acb50ab30e32e8e019d',
  'k2so-assets|1.0.7|sha256:c3e11214407b08120b2ee717405d3b0398f533647695ab2e6ef6df9267d62017',
  'mir-validation-settings-overrides|0.1.0|sha256:0a6aaa9e8d89ddcc9e421f8ab065124554531588c4e4f91ec5e4d52ec0e10e26',
  'mir4-a03-k2-intake-observer|0.1.0|sha256:8031f2310b30e7b66a33edd125aa86137b9aba0b9dbff1e23cd3c31435be8d31',
  'xy-k2so-enhancements-nulls-fork|0.8.3|sha256:930f43b96b04012fef090c40d8b16a6b3f259d1713c86cf59dff3e9a5a97e2be'
)
$actualLockedMods = @($environmentLock.mods | ForEach-Object { '{0}|{1}|{2}' -f $_.name,$_.version,$_.sha256 })
Assert-A03Sequence -Actual $actualLockedMods -Expected $expectedLockedMods -Code '[mir4-a03-environment-lock-mods]'

$fixture = Join-Path $RepoRoot 'fixtures/assert-k2-k2so-f210-intake'
$initialObserverSource = Join-Path $fixture 'initial-observer-source'
$governedObserverSource = Join-Path $fixture 'governed-observer-source'
$settingsHelperSource = Join-Path $fixture 'settings-helper'
foreach ($path in @($initialObserverSource, $governedObserverSource, $settingsHelperSource)) {
  if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "[mir4-a03-fixture] $path" }
}
$observerLua = Get-Content -Raw -LiteralPath (Join-Path $governedObserverSource 'data-final-fixes.lua')
if ($observerLua -match 'data:extend' -or $observerLua -match 'data\.raw\[[^\r\n]+\]\s*=') { throw '[mir4-a03-observer-mutation-source]' }
if ($observerLua -notmatch 'post_finalizer_observation=true' -or $observerLua -notmatch 'mutation_authorized=false' -or $observerLua -notmatch 'effective_startup_settings' -or $observerLua -notmatch 'mir-debug-generation-report' -or $observerLua -notmatch 'debug_setting.value == true') { throw '[mir4-a03-observer-contract-source]' }
$helperLua = Get-Content -Raw -LiteralPath (Join-Path $settingsHelperSource 'settings-updates.lua')
if ($helperLua -notmatch 'override\("mir-debug-generation-report", true\)') { throw '[mir4-a03-settings-helper-source]' }

$closureSource = Join-Path $RepoRoot 'build/synthesis-20260906/k2-engine-candidate/runs/u-ad28370088e7/mods'
$initialArtifactSource = Join-Path $RepoRoot 'build/mir4/a03-k2-intake/runtime/current-f210/mods'
$thirdPartyArchives = [ordered]@{
  'flib_0.17.2.zip' = '0A48C15DC0FC6C13BB3FE8293BA6CB35A07F3B0F37D37ACB50AB30E32E8E019D'
  'k2so-assets_1.0.7.zip' = 'C3E11214407B08120B2EE717405D3B0398F533647695AB2E6EF6DF9267D62017'
  'Krastorio2_2.1.2.zip' = '89989E60784EA3E94345289E063C64ABFCE5F35693DB7B9A69D656A163620F43'
  'Krastorio2-spaced-out_2.0.13.zip' = 'A2EEB2E5A6119C4117BD3653979D40D305D17539E184BFA6F4ED53EF12A5F242'
  'Krastorio2Assets_2.1.0.zip' = '39EF950EC8B21A40357DD0240EF8389501EE75CCA82717F2773B98554DA46E29'
  'Krastorio2MenuSimulations_2.1.0.zip' = '3A485B449B356DC4B3EB4233DE4E803B3A001259FBC251BDC9F9D9120B3C53A7'
  'xy-k2so-enhancements-nulls-fork_0.8.3.zip' = '930F43B96B04012FEF090C40D8B16A6B3F259D1713C86CF59DFF3E9A5A97E2BE'
}

$runParent = Join-Path $RepoRoot 'build/mir4/a03-k2-intake/runtime'
if (-not (Test-Path -LiteralPath $runParent -PathType Container)) { New-Item -ItemType Directory -Force -Path $runParent | Out-Null }
$root = New-MIRCompatUserDataDir -Root $runParent
$ownedInitial = @((Get-ChildItem -LiteralPath $root -Force | Select-Object -ExpandProperty Name) | Sort-Object)
Assert-A03Sequence -Actual $ownedInitial -Expected @('mods', 'saves') -Code '[mir4-a03-attempt-root-owned-state]'
$mods = Join-Path $root 'mods'

foreach ($entry in $thirdPartyArchives.GetEnumerator()) {
  $source = Join-Path $closureSource $entry.Key
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "[mir4-a03-third-party-archive-missing] $($entry.Key)" }
  Assert-A03Equal -Actual (Get-A03Sha256 -Path $source) -Expected $entry.Value -Code "[mir4-a03-third-party-archive-sha256] $($entry.Key)"
  Copy-Item -LiteralPath $source -Destination (Join-Path $mods $entry.Key)
}

$settingsArchive = Join-Path $initialArtifactSource 'mir-validation-settings-overrides_0.1.0.zip'
$initialObserverArchive = Join-Path $initialArtifactSource 'mir4-a03-k2-intake-observer_0.1.0.zip'
Assert-A03GovernedArchive -Archive $settingsArchive -ExpectedSha256 '0A6AAA9E8D89DDCC9E421F8AB065124554531588C4E4F91EC5E4D52EC0E10E26' -ArchiveRoot 'mir-validation-settings-overrides_0.1.0' -SourceRoot $settingsHelperSource -SourceFiles @('info.json', 'settings-updates.lua') -Code '[mir4-a03-settings-helper-archive]'
Assert-A03GovernedArchive -Archive $initialObserverArchive -ExpectedSha256 'D8547266E67E5C9E3CA1B1CDCAF1830EF3DEB9A4E706776189663FE0F9478F8B' -ArchiveRoot 'mir4-a03-k2-intake-observer_0.1.0' -SourceRoot $initialObserverSource -SourceFiles @('data-final-fixes.lua', 'info.json') -Code '[mir4-a03-initial-observer-archive]'
Copy-Item -LiteralPath $settingsArchive -Destination (Join-Path $mods (Get-Item -LiteralPath $settingsArchive).Name)
$governedObserverArchive = Publish-MIRModDirectoryArchive -Source $governedObserverSource -Name 'mir4-a03-k2-intake-observer' -Version '0.1.0' -ModsDir $mods
Assert-A03Equal -Actual (Get-A03Sha256 -Path $governedObserverArchive) -Expected '8031F2310B30E7B66A33EDD125AA86137B9ABA0B9DBFF1E23CD3C31435BE8D31' -Code '[mir4-a03-governed-observer-archive-sha256]'
Copy-Item -LiteralPath $candidate -Destination (Join-Path $mods (Get-Item -LiteralPath $candidate).Name)

$settingsSourcePath = Join-Path $closureSource 'mod-settings.dat'
$settingsSourceItem = Get-Item -LiteralPath $settingsSourcePath
Assert-A03Equal -Actual $settingsSourceItem.Name -Expected 'mod-settings.dat' -Code '[mir4-a03-mod-settings-filename]'
Assert-A03Equal -Actual (Get-A03Sha256 -Path $settingsSourcePath) -Expected '6AF4D7F55D19D9F105BCD540FFCA61267613843BC7AFEB457241BFB3703977A4' -Code '[mir4-a03-mod-settings-source-sha256]'
Copy-Item -LiteralPath $settingsSourcePath -Destination (Join-Path $mods $settingsSourceItem.Name)

$modListSourcePath = Join-Path $closureSource 'mod-list.json'
$modListSourceItem = Get-Item -LiteralPath $modListSourcePath
Assert-A03Equal -Actual $modListSourceItem.Name -Expected 'mod-list.json' -Code '[mir4-a03-mod-list-filename]'
Assert-A03Equal -Actual (Get-A03Sha256 -Path $modListSourcePath) -Expected 'FC7D944550AE7C4DEABAC91EF20CD2CC8E1ABFEDA0F96953284CDBFAB608FCAD' -Code '[mir4-a03-mod-list-source-sha256]'
$modList = Get-Content -Raw -LiteralPath $modListSourcePath | ConvertFrom-Json -Depth 10
$modList.mods = @($modList.mods) + @([pscustomobject][ordered]@{ name = 'mir4-a03-k2-intake-observer'; enabled = $true })
$modListDestination = Join-Path $mods $modListSourceItem.Name
[IO.File]::WriteAllText($modListDestination, (($modList | ConvertTo-Json -Depth 10) + "`n"), [Text.UTF8Encoding]::new($false))
$modListDestinationItem = Get-Item -LiteralPath $modListDestination
Assert-A03Equal -Actual $modListDestinationItem.Name -Expected 'mod-list.json' -Code '[mir4-a03-mod-list-destination-filename]'
$actualEnabledMods = @((Get-Content -Raw -LiteralPath $modListDestination | ConvertFrom-Json -Depth 10).mods | Where-Object { $_.enabled } | ForEach-Object { [string]$_.name })
Assert-A03Sequence -Actual $actualEnabledMods -Expected @('base', 'elevated-rails', 'quality', 'recycler', 'space-age', 'flib', 'k2so-assets', 'Krastorio2', 'Krastorio2-spaced-out', 'Krastorio2Assets', 'Krastorio2MenuSimulations', 'mir-validation-settings-overrides', 'more-infinite-research', 'xy-k2so-enhancements-nulls-fork', 'mir4-a03-k2-intake-observer') -Code '[mir4-a03-mod-list-exact-enabled-set]'

$factorioRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $engine))
$readData = Join-Path $factorioRoot 'data'
if (-not (Test-Path -LiteralPath $readData -PathType Container)) { throw '[mir4-a03-read-data]' }
$configPath = Join-Path $root 'mir-compat-config.ini'
$configText = @"
; Generated by More Infinite Research compatibility audit.
[path]
read-data=$readData
write-data=$root

[general]
locale=auto

[other]
enable-steam-networking=false
disable-blueprint-storage=true
"@
[IO.File]::WriteAllText($configPath, $configText, [Text.UTF8Encoding]::new($false))

$save = Join-Path $root 'saves/a03-k2-k2so-f210-intake.zip'
$stdoutPath = Join-Path $root 'a03-k2-k2so-f210-intake.stdout.log'
$stderrPath = Join-Path $root 'a03-k2-k2so-f210-intake.stderr.log'
$processInfo = [Diagnostics.ProcessStartInfo]::new($engine)
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $true
$processInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.Environment['SteamAppId'] = '427520'
$processInfo.Environment['SteamGameId'] = '427520'
foreach ($argument in @('--config', $configPath, '--no-log-rotation', '--disable-audio', '--mod-directory', $mods, '--create', $save)) { [void]$processInfo.ArgumentList.Add($argument) }

$timer = [Diagnostics.Stopwatch]::StartNew()
$process = [Diagnostics.Process]::Start($processInfo)
try {
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit(300000)) {
    $process.Kill($true)
    throw "[mir4-a03-factorio-timeout] $root"
  }
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  [IO.File]::WriteAllText($stdoutPath, $stdout, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($stderrPath, $stderr, [Text.UTF8Encoding]::new($false))
  if ($process.ExitCode -ne 0) { throw "[mir4-a03-factorio-exit] $($process.ExitCode) $root" }
  if (-not [string]::IsNullOrEmpty($stderr)) { throw "[mir4-a03-factorio-stderr] $stderrPath" }
} finally {
  $timer.Stop()
  $process.Dispose()
}

if (-not (Test-Path -LiteralPath $save -PathType Leaf)) { throw '[mir4-a03-save-missing]' }
$factorioLog = Join-Path $root 'factorio-current.log'
if (-not (Test-Path -LiteralPath $factorioLog -PathType Leaf)) { throw '[mir4-a03-factorio-log-missing]' }
$factorioLogText = Get-Content -Raw -LiteralPath $factorioLog
$markers = [regex]::Matches($factorioLogText, '\[MIR4_A03_K2_INTAKE\]\s+(\{[^\r\n]*\})')
if ($markers.Count -ne 1) { throw "[mir4-a03-observer-marker-count] $($markers.Count)" }
$xyFinalizer = $factorioLogText.IndexOf('Loading mod xy-k2so-enhancements-nulls-fork 0.8.3 (data-final-fixes.lua)', [StringComparison]::Ordinal)
if ($xyFinalizer -lt 0 -or $xyFinalizer -gt $markers[0].Index) { throw '[mir4-a03-post-finalizer-order]' }
if ($factorioLogText.IndexOf('[more-infinite-research] Audit report end', [StringComparison]::Ordinal) -lt 0) { throw '[mir4-a03-effective-debug-setting]' }
$observation = $markers[0].Groups[1].Value | ConvertFrom-Json -Depth 100 -DateKind String
$expectedObservation = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-k2-k2so-f210-intake/expected-observation.json') | ConvertFrom-Json -Depth 100 -DateKind String
Assert-A03Equal -Actual (ConvertTo-MIR4BootstrapCanonicalJson $observation) -Expected (ConvertTo-MIR4BootstrapCanonicalJson $expectedObservation) -Code '[mir4-a03-exact-observation-fixture]'
Assert-A03Equal -Actual $observation.kind -Expected 'MIR4A03K2IntakeObservationV1' -Code '[mir4-a03-observation-kind]'
if (-not [bool]$observation.post_finalizer_observation) { throw '[mir4-a03-post-finalizer]' }
if (-not [bool]$observation.effective_startup_settings.'mir-debug-generation-report') { throw '[mir4-a03-effective-debug-setting]' }
if ([bool]$observation.mutation_authorized -or [bool]$observation.package_visible) { throw '[mir4-a03-observer-authority]' }
Assert-A03Equal -Actual $observation.native_reference_technology.id -Expected 'kr-singularity-lab' -Code '[mir4-a03-native-reference-tech]'
Assert-A03Sequence -Actual @($observation.native_reference_technology.prerequisites) -Expected @('kr-singularity-tech-card', 'quantum-processor') -Code '[mir4-a03-native-prerequisites]'
Assert-A03Sequence -Actual @($observation.native_reference_technology.science) -Expected @('agricultural-science-pack', 'cryogenic-science-pack', 'electromagnetic-science-pack', 'kr-advanced-tech-card', 'kr-matter-tech-card', 'kr-singularity-tech-card', 'metallurgic-science-pack', 'production-science-pack', 'space-science-pack', 'utility-science-pack') -Code '[mir4-a03-native-science]'

$expectedLabs = [ordered]@{
  'biolab' = @('agricultural-science-pack', 'automation-science-pack', 'chemical-science-pack', 'cryogenic-science-pack', 'electromagnetic-science-pack', 'kr-advanced-tech-card', 'kr-matter-tech-card', 'kr-singularity-tech-card', 'logistic-science-pack', 'metallurgic-science-pack', 'military-science-pack', 'production-science-pack', 'space-science-pack', 'utility-science-pack')
  'kr-advanced-lab' = @('agricultural-science-pack', 'automation-science-pack', 'chemical-science-pack', 'cryogenic-science-pack', 'electromagnetic-science-pack', 'kr-advanced-tech-card', 'kr-matter-tech-card', 'kr-singularity-tech-card', 'logistic-science-pack', 'metallurgic-science-pack', 'military-science-pack', 'production-science-pack', 'space-science-pack', 'utility-science-pack')
  'kr-singularity-lab' = @('agricultural-science-pack', 'automation-science-pack', 'chemical-science-pack', 'cryogenic-science-pack', 'electromagnetic-science-pack', 'kr-advanced-tech-card', 'kr-matter-tech-card', 'kr-singularity-tech-card', 'logistic-science-pack', 'metallurgic-science-pack', 'military-science-pack', 'production-science-pack', 'promethium-science-pack', 'space-science-pack', 'utility-science-pack')
  'lab' = @('agricultural-science-pack', 'automation-science-pack', 'chemical-science-pack', 'cryogenic-science-pack', 'electromagnetic-science-pack', 'kr-advanced-tech-card', 'kr-matter-tech-card', 'kr-singularity-tech-card', 'logistic-science-pack', 'metallurgic-science-pack', 'military-science-pack', 'production-science-pack', 'space-science-pack', 'utility-science-pack')
}
Assert-A03Sequence -Actual @($observation.compatible_labs | ForEach-Object { [string]$_.id }) -Expected @($expectedLabs.Keys) -Code '[mir4-a03-compatible-labs]'
foreach ($lab in @($observation.compatible_labs)) { Assert-A03Sequence -Actual @($lab.inputs) -Expected @($expectedLabs[[string]$lab.id]) -Code "[mir4-a03-lab-inputs] $($lab.id)" }

$archiveHashes = [ordered]@{}
foreach ($file in @(Get-ChildItem -LiteralPath $mods -File | Sort-Object Name)) { $archiveHashes[$file.Name] = Get-A03Sha256 -Path $file.FullName }
$result = [pscustomobject][ordered]@{
  schema = 1
  kind = 'MIR4A03K2K2SOIntakeRuntimeResultV1'
  recorded_at = (Get-Date).ToUniversalTime().ToString('o')
  target = 'f210'
  attempt_root = $root
  factorio = [ordered]@{ version = '2.1.17'; executable_sha256 = Get-A03Sha256 -Path $engine }
  candidate = [ordered]@{ path = $candidate; sha256 = Get-A03Sha256 -Path $candidate; bytes = (Get-Item -LiteralPath $candidate).Length }
  initial_observation_artifacts = [ordered]@{ observer_archive_sha256 = Get-A03Sha256 -Path $initialObserverArchive; observer_source_sha256 = [ordered]@{ data_final_fixes = Get-A03Sha256 -Path (Join-Path $initialObserverSource 'data-final-fixes.lua'); info = Get-A03Sha256 -Path (Join-Path $initialObserverSource 'info.json') } }
  governed_run_observer = [ordered]@{ archive_sha256 = Get-A03Sha256 -Path $governedObserverArchive; source_sha256 = [ordered]@{ data_final_fixes = Get-A03Sha256 -Path (Join-Path $governedObserverSource 'data-final-fixes.lua'); info = Get-A03Sha256 -Path (Join-Path $governedObserverSource 'info.json') } }
  closure_archives = $archiveHashes
  result = 'passed'
  duration_seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 6)
  stdout_sha256 = Get-A03Sha256 -Path $stdoutPath
  stderr_sha256 = Get-A03Sha256 -Path $stderrPath
  factorio_log_sha256 = Get-A03Sha256 -Path $factorioLog
  save_sha256 = Get-A03Sha256 -Path $save
  observer_marker_count = $markers.Count
  observation = $observation
}
$resultPath = Join-Path $root 'a03-k2-k2so-f210-intake-runtime-result.json'
$resultHash = Write-MIR4BootstrapRecord -Record $result -Path $resultPath
 $persistedResult = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json -Depth 100 -DateKind String
if (-not (Test-MIR4BootstrapRecordHash -Record $persistedResult)) { throw '[mir4-a03-runtime-result-self-hash]' }
Write-Host "[MIR4_A03_RUNTIME_RESULT] path=$resultPath sha256=$resultHash"
