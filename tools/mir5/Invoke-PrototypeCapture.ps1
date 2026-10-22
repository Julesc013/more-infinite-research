# Native data-stage observer for MIR 4/5 archive custody. It creates no map,
# save, gameplay, menu, or release claim; its payload is Factorio --dump-data.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ArchiveLibrary,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ProfilePath,
  [Parameter(Mandatory)][string]$OutputRoot,
  [string]$MIRArchive = '',
  [string]$ExpectedMIRArchiveSha256 = '',
  [ValidateRange(30,600)][int]$TimeoutSeconds = 240,
  [ValidateRange(64,8192)][int]$ExpectedPeakMemoryMiB = 1024,
  [ValidateRange(16,2048)][int]$MaxNewOutputMiB = 512,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-MIR5PrototypeCapture {
  param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
  if (-not $Condition) { throw "[mir5-prototype-capture] $Message" }
}

function Get-MIR5PrototypeCaptureSha256 {
  param([Parameter(Mandatory)][string]$Path)
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-MIR5PrototypeCaptureContainedPath {
  param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)
  $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
  $resolvedPath = [IO.Path]::GetFullPath($Path)
  $resolvedPath.StartsWith($resolvedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-MIR5PrototypeCaptureMIRArchive {
  param(
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][string]$Library,
    [Parameter(Mandatory)][string]$ExpectedSha256,
    [Parameter(Mandatory)][string]$EngineLine
  )
  Assert-MIR5PrototypeCapture ($ExpectedSha256 -match '^[A-Fa-f0-9]{64}$') 'MIR archive requires a 64-character expected SHA-256'
  $path = (Resolve-Path -LiteralPath $Archive).Path
  Assert-MIR5PrototypeCapture ([IO.Path]::GetDirectoryName($path) -ceq $Library) 'MIR archive must already be installed in the selected direct library'
  Assert-MIR5PrototypeCapture ((Get-MIR5PrototypeCaptureSha256 $path) -ceq $ExpectedSha256.ToUpperInvariant()) 'MIR archive SHA-256 differs from expected input'

  Add-Type -AssemblyName System.IO.Compression
  $zip = [IO.Compression.ZipFile]::OpenRead($path)
  try {
    $entries = @($zip.Entries | Where-Object { $_.FullName -match '^[^/]+/info[.]json$' })
    Assert-MIR5PrototypeCapture ($entries.Count -eq 1 -and $entries[0].Length -le 64KB) 'MIR archive lacks one bounded rooted info.json'
    $root = $entries[0].FullName.Substring(0, $entries[0].FullName.Length - ('info.json').Length).TrimEnd('/')
    $reader = [IO.StreamReader]::new($entries[0].Open())
    try { $info = $reader.ReadToEnd() | ConvertFrom-Json -AsHashtable } finally { $reader.Dispose() }
    Assert-MIR5PrototypeCapture ([string]$info.name -ceq 'more-infinite-research') 'MIR archive name differs'
    Assert-MIR5PrototypeCapture ([string]$info.version -match '^(?:4[.]\d{1,5}[.]\d{5}|5[.]\d{1,5}[.]\d{5})$') 'MIR archive must be a 4.x or 5.x numeric distribution'
    Assert-MIR5PrototypeCapture ([string]$info.factorio_version -ceq $EngineLine) 'MIR archive Factorio family differs from selected engine'
    Assert-MIR5PrototypeCapture ($root -ceq ([string]$info.name + '_' + [string]$info.version)) 'MIR archive root differs from metadata'
    Assert-MIR5PrototypeCapture ([IO.Path]::GetFileName($path) -ceq ($root + '.zip')) 'MIR archive filename differs from metadata'
    [pscustomobject][ordered]@{path=$path;sha256=Get-MIR5PrototypeCaptureSha256 $path;name=[string]$info.name;version=[string]$info.version;factorio_version=[string]$info.factorio_version;root=$root}
  } finally { $zip.Dispose() }
}

function Get-MIR5PrototypeCaptureFatalDiagnostic {
  param([AllowNull()][string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return $null }
  [regex]::Match($Text, '(?im)^\s*\d+[.]\d+\s+Error\b.*$|^Error while running event\b.*$|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$')
}

function Assert-MIR5PrototypeCaptureNoFatalDiagnostic {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Kind)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  $fatal = Get-MIR5PrototypeCaptureFatalDiagnostic ([IO.File]::ReadAllText($Path))
  if ($null -ne $fatal -and $fatal.Success) {
    throw "native $Kind diagnostic is fatal: $($fatal.Value)"
  }
}

function Get-MIR5PrototypeCaptureDumpFile {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$OutputRoot)
  Assert-MIR5PrototypeCapture (Test-Path -LiteralPath $Path -PathType Leaf) "required dump is absent: $([IO.Path]::GetFileName($Path))"
  $item = Get-Item -LiteralPath $Path
  Assert-MIR5PrototypeCapture ($item.Length -gt 0) "dump is empty: $($item.Name)"
  Assert-MIR5PrototypeCapture (([IO.File]::ReadAllText($item.FullName)) | Test-Json) "dump is not valid JSON: $($item.Name)"
  [ordered]@{path=[IO.Path]::GetRelativePath($OutputRoot,$item.FullName).Replace('\','/');bytes=[int64]$item.Length;sha256=Get-MIR5PrototypeCaptureSha256 $item.FullName}
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$library = (Resolve-Path -LiteralPath $ArchiveLibrary).Path
$engine = (Resolve-Path -LiteralPath $FactorioBin).Path
Assert-MIR5PrototypeCapture (Test-Path -LiteralPath $engine -PathType Leaf) 'Factorio executable is absent'
$engineRoot = (Get-Item -LiteralPath $engine).Directory.Parent.Parent.FullName
$engineData = Join-Path $engineRoot 'data'
Assert-MIR5PrototypeCapture (Test-Path -LiteralPath (Join-Path $engineData 'base/info.json') -PathType Leaf) 'Factorio data/base metadata is absent'
$base = Get-Content -LiteralPath (Join-Path $engineData 'base/info.json') -Raw | ConvertFrom-Json -AsHashtable
Assert-MIR5PrototypeCapture ([string]$base.version -match '^\d+[.]\d+[.]\d+$') 'Factorio base version is invalid'
$engineLine = ([version][string]$base.version).ToString(2)

$profileInput = (Resolve-Path -LiteralPath $ProfilePath).Path
$profileDefinition = (Get-Content -LiteralPath $profileInput -Raw).TrimStart([char]0xFEFF) | ConvertFrom-Json -AsHashtable
Assert-MIR5PrototypeCapture ($profileDefinition.ContainsKey('mods') -and $profileDefinition.mods -is [array]) 'profile must contain a mods array'
Assert-MIR5PrototypeCapture (@($profileDefinition.mods | Where-Object { [string]$_.name -ceq 'more-infinite-research' }).Count -eq 0) 'profile must omit MIR; MIRArchive is the sole explicit MIR selection'
$hasMIRArchive = -not [string]::IsNullOrWhiteSpace($MIRArchive)
Assert-MIR5PrototypeCapture ($hasMIRArchive -eq (-not [string]::IsNullOrWhiteSpace($ExpectedMIRArchiveSha256))) 'MIRArchive and ExpectedMIRArchiveSha256 must be supplied together'

# LibraryActivation receives only generic immutable-input primitives. The
# existing direct-library and governed-resource modules remain the host.
$identityModule = New-Module -Name MIR5PrototypeCaptureImmutableInputs -ArgumentList (Join-Path $repo 'tools/lib/validation/ImmutableInputStaging.ps1') -ScriptBlock {
  param($Path)
  . $Path
  Export-ModuleMember -Function Get-MIRImmutableInputSha256, Get-MIRImmutableInputFileIdentity, Assert-MIRCheckoutHardLinkBoundary
}
Import-Module $identityModule -Force
. (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')

$baseRows = @(Read-MIRDirectLibraryStartupProfile -Path $profileInput)
$mir = if ($hasMIRArchive) { Get-MIR5PrototypeCaptureMIRArchive -Archive $MIRArchive -Library $library -ExpectedSha256 $ExpectedMIRArchiveSha256 -EngineLine $engineLine } else { $null }

$buildTmp = Join-Path $repo 'build/tmp'
$output = [IO.Path]::GetFullPath($OutputRoot)
Assert-MIR5PrototypeCapture (Test-MIR5PrototypeCaptureContainedPath -Root $buildTmp -Path $output) 'OutputRoot must be a new directory beneath build/tmp'
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 2 -MaxEntriesPerRoot 500 | Out-Host

$resources = $null
$activation = $null
$pendingFailure = $null
$record = [ordered]@{
  schema=1;kind='MIR5PrototypeCaptureV1';status='prepared';endpoint_class='factorio-data-stage-dump-only'
  claims=[ordered]@{gameplay=$false;menu=$false;save=$false;release_qualification=$false}
  source_head=[string](& git -C $repo rev-parse HEAD)
  harness=[ordered]@{
    path=[IO.Path]::GetRelativePath($repo,$PSCommandPath).Replace('\','/')
    sha256=Get-MIR5PrototypeCaptureSha256 $PSCommandPath
    direct_library_startup_measurement_sha256=Get-MIR5PrototypeCaptureSha256 (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
    native_probe_resources_sha256=Get-MIR5PrototypeCaptureSha256 (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
    library_activation_sha256=Get-MIR5PrototypeCaptureSha256 (Join-Path $repo 'tools/lib/compatibility/LibraryActivation.ps1')
  }
  engine=[ordered]@{path=$engine;sha256=Get-MIR5PrototypeCaptureSha256 $engine;base_version=[string]$base.version;factorio_version=$engineLine}
  profile_input=[ordered]@{path=$profileInput;sha256=Get-MIR5PrototypeCaptureSha256 $profileInput}
  mir_archive=$mir
  budget=[ordered]@{timeout_seconds=$TimeoutSeconds;expected_peak_memory_mib=$ExpectedPeakMemoryMiB;max_new_output_mib=$MaxNewOutputMiB}
  native_qualification=$false
}

try {
  $resources = New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $output -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB -UseExactOutputRoot
  $run = $resources.root
  $writeData = Join-Path $run 'write-data'
  [IO.Directory]::CreateDirectory($writeData) | Out-Null
  $selection = Join-Path $run 'selection.json'
  Write-MIRDirectLibraryStartupProfile -Path $selection -BaseRows $baseRows -MirArchive $mir
  $config = Join-Path $run 'config.ini'
  New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $engineData -WriteDataDirectory $writeData
  $archiveHashes = Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $library -EngineDataDirectory $engineData -BaseRows $baseRows -MirArchive $mir

  $activation = Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $engineData -ProfilePath $selection -ArchiveHashes $archiveHashes -SettingsMode Defaults
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  $record.generated_selection = [ordered]@{
    path=[IO.Path]::GetRelativePath($run,$selection).Replace('\','/')
    sha256=Get-MIR5PrototypeCaptureSha256 $selection
    mods=(Get-Content -LiteralPath $selection -Raw | ConvertFrom-Json -AsHashtable).mods
  }
  $record.selected_archives = @($activation.selected | ForEach-Object {
    [ordered]@{name=[string]$_.name;version=[string]$_.version;builtin=[bool]$_.builtin;path=[string]$_.path;sha256=[string]$_.sha256}
  } | Sort-Object name,version)

  $arguments = @('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation','--disable-audio','--dump-data')
  Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments
  $native = Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
  $record.process = $native.result
  Assert-MIR5PrototypeCapture ([bool]$native.result.passed -and -not [bool]$native.result.timed_out -and [int]$native.result.exit_code -eq 0) 'Factorio dump process must exit naturally with code zero'

  $factorioLog = Join-Path $writeData 'factorio-current.log'
  Assert-MIR5PrototypeCapture (Test-Path -LiteralPath $factorioLog -PathType Leaf) 'Factorio did not produce factorio-current.log'
  Assert-MIR5PrototypeCaptureNoFatalDiagnostic -Path $factorioLog -Kind 'Factorio'
  foreach ($diagnostic in @($native.stdout,$native.stderr,(Join-Path $run 'process-1.stdout.txt'),(Join-Path $run 'process-1.stderr.txt')) | Select-Object -Unique) {
    if ($null -ne $diagnostic -and -not [string]::IsNullOrWhiteSpace([string]$diagnostic)) {
      Assert-MIR5PrototypeCaptureNoFatalDiagnostic -Path ([string]$diagnostic) -Kind 'process'
    }
  }

  $record.loaded_selection = Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $factorioLog -LatestInvocation
  $dumpRoot = Join-Path $writeData 'script-output'
  Assert-MIR5PrototypeCapture (Test-Path -LiteralPath $dumpRoot -PathType Container) 'Factorio dump script-output directory is absent'
  $jsonDumps = @(Get-ChildItem -LiteralPath $dumpRoot -File -Filter '*.json')
  $unexpected = @($jsonDumps | Where-Object { $_.Name -cnotin @('data-raw-dump.json','mod-settings-dump.json') })
  Assert-MIR5PrototypeCapture ($unexpected.Count -eq 0) 'Factorio produced an unexpected JSON dump'
  $dataRaw = Get-MIR5PrototypeCaptureDumpFile -Path (Join-Path $dumpRoot 'data-raw-dump.json') -OutputRoot $run
  $modSettingsPath = Join-Path $dumpRoot 'mod-settings-dump.json'
  $record.dumps = [ordered]@{
    data_raw=$dataRaw
    mod_settings=if(Test-Path -LiteralPath $modSettingsPath -PathType Leaf){Get-MIR5PrototypeCaptureDumpFile -Path $modSettingsPath -OutputRoot $run}else{$null}
  }
  $record.status = 'completed-data-stage-observation-only'
} catch {
  $record.status = 'failed'
  $record.failure = $_.Exception.Message
  $pendingFailure = $_
} finally {
  if ($null -ne $activation -and -not $activation.closed) {
    try {$record.library_control_restoration = Complete-MIRLibraryActivation -Activation $activation}
    catch {
      $record.library_control_restoration_failure = $_.Exception.Message
      if ($null -eq $pendingFailure) {$record.status='failed';$record.failure=$_.Exception.Message;$pendingFailure=$_}
    }
  }
  $record.library_controls_restored = -not (Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json'))
  if ($null -ne $resources) {
    try {Write-MIRNativeProbeResult -Context $resources -Record $record}
    catch {
      if ($null -eq $pendingFailure) {$record.status='failed';$record.failure=$_.Exception.Message;$pendingFailure=$_}
    }
  }
}
if ($null -ne $pendingFailure) { throw $pendingFailure }
[pscustomobject]$record
