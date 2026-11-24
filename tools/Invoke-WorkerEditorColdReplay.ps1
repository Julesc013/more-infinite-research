[CmdletBinding()]
param([Parameter(Mandatory)][string]$CandidatePath,[Parameter(Mandatory)][string]$ObserverPath,
    [Parameter(Mandatory)][string]$StoragePlanPath,[Parameter(Mandatory)][string]$StoragePlanSha256)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'lib/validation/NativeProbeResources.ps1')
. (Join-Path $PSScriptRoot 'lib/compatibility/LibraryActivation.ps1')
function Require([bool]$condition,[string]$message) {
    if (-not $condition) { throw $message }
}
function Sha([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
function Json([string]$path,$value) {
    [IO.File]::WriteAllText($path, (($value | ConvertTo-Json -Depth 24) + [Environment]::NewLine))
}

$library = '/home/shared/Projects/Factorio/MIR/testmods/2.1'
$engineData = '/home/shared/Programs/Factorio/2.1/data'
$engine = '/home/shared/Programs/Factorio/2.1/bin/x64/factorio'
$engineHash = '1CD21159CB48B92C7258407ECD9D52CFE900F276A52D4DDA9577DCDB27AFC0CF'
$candidateSha = 'ED5984493EBFB6E5C11F8DE52C27CE80806669AD6CCADF58525E77A1593DD31F'
$candidateName = 'more-infinite-research_5.0.21023.zip'
$observerName = 'mir-fixture-worker-init-frame_0.1.2.zip'
$observerSource = Join-Path $repo 'tests/fixtures/worker-editor-cold-replay'
Require ((Split-Path -Leaf $CandidatePath) -ceq $candidateName -and (Sha $CandidatePath) -ceq $candidateSha) 'Frozen archive differs'
Require ((Split-Path -Leaf $ObserverPath) -ceq $observerName -and (Sha $engine) -ceq $engineHash) 'Observer identity or exact engine differs'
Assert-MIRLibraryFixtureArchive -Archive $ObserverPath -SourceDirectory $observerSource
$hashes = @{
    'EditorExtensions_2.6.1.zip'='CB2E9176A6CE9622AB042929FCF83A2B88FC435E5B5EA3209CDC20298BA42AE1'
    'flib_0.17.2.zip'='0A48C15DC0FC6C13BB3FE8293BA6CB35A07F3B0F37D37ACB50AB30E32E8E019D'
    $candidateName=$candidateSha
    $observerName=(Sha $ObserverPath)
}
$control = Join-Path $repo 'build/tmp/editor-cold'
$storage = @{RepoRoot=$repo;OutputRoot=$control;ExpectedPeakMemoryMiB=8192;MaxNewOutputMiB=192;
    UseExactOutputRoot=$true;LinuxStoragePlanPath=$StoragePlanPath;LinuxStoragePlanSha256=$StoragePlanSha256;LibraryRoot=$library}
$context = New-MIRNativeProbeResourceContext @storage
$out = $context.root
[IO.Directory]::CreateDirectory($out) | Out-Null

$mods = @('base','elevated-rails','quality','recycler','space-age' | ForEach-Object { @{name=$_;version='2.1.24';enabled=$true} })
$mods += @(
    @{name='EditorExtensions';version='2.6.1';enabled=$true},
    @{name='flib';version='0.17.2';enabled=$true},
    @{name='mir-fixture-worker-init-frame';version='0.1.2';enabled=$true},
    @{name='more-infinite-research';version='5.0.21023';enabled=$true}
)
$profile = Join-Path $out 'profile.json'
Json $profile @{schema=1;kind='editor-worker-reload';target='f210';engine=@{version='2.1.24';sha256=$engineHash};mods=$mods}
$server = Get-Content -LiteralPath (Join-Path $engineData 'server-settings.example.json') -Raw | ConvertFrom-Json -AsHashtable
$server.name = 'Isolated MIR Editor Extensions replay'
$server.visibility = @{public=$false;lan=$false}
$server.auto_pause = $false
$server.autosave_interval = 0
$server.require_user_verification = $false
$serverPath = Join-Path $out 'server-settings.json'
Json $serverPath $server

function Invoke-EditorLeg([string]$label,[string[]]$commands,[string]$saveName='') {
    $leg = Join-Path $out $label
    $write = Join-Path $leg 'write-data'
    [IO.Directory]::CreateDirectory((Join-Path $write 'saves')) | Out-Null
    $config = Join-Path $leg 'config.ini'
    [IO.File]::WriteAllLines($config, @('[path]',"read-data=$engineData","write-data=$write",'','[other]','enable-new-mods=false'))
    $arguments = @('--config',$config,'--mod-directory',$library,'--no-log-rotation') + $commands
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments -WriteStoragePolicy $context.policy
    $completion = $null
    if ($saveName) {
        $save = Join-Path $write "saves/$saveName.zip"
        $log = Join-Path $write 'factorio-current.log'
        $completion = { (Test-Path -LiteralPath $save -PathType Leaf) -and
            (Test-Path -LiteralPath $log -PathType Leaf) -and [IO.File]::ReadAllText($log).Contains('Saving finished') }.GetNewClosure()
    }
    $run = Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $engine -Arguments $arguments -TimeoutSeconds 120 -CompletionPredicate $completion
    Require ($run.status -ceq 'passed') "Native stage failed $label"
    return $write
}

$report = [ordered]@{kind='MIR523ExactEditorColdReplayV1';status='started';archive_sha256=$candidateSha;
    engine_sha256=$engineHash;archive_hashes=$hashes;archive_cleanup=$false;controls_restored=$false;
    owner=(& id -un);storage_plan_sha256=$StoragePlanSha256;cold_loads=0}
$created = [Collections.Generic.List[object]]::new()
$lock = $null
$activation = $null
$failure = $null
$cleanup = [Collections.Generic.List[string]]::new()
try {
    Assert-MIRLibraryPath $library
    $lockPath = Join-Path $library '.mir-library.lock'
    Assert-MIRLibraryPath $lockPath
    $lock = [IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    Assert-MIRLibraryIdle
    $journal = Join-Path $library '.mir-active-profile.json'
    Require (-not (Test-Path -LiteralPath $journal)) 'Shared selection is occupied'
    $controls = @{}
    foreach ($name in @('mod-list.json','mod-settings.dat','mod-settings.json')) {
        $controls[$name] = Read-MIRLibraryControl (Join-Path $library $name)
    }
    foreach ($source in @($CandidatePath,$ObserverPath)) {
        $name = Split-Path -Leaf $source
        $target = Join-Path $library $name
        Require (-not (Test-Path -LiteralPath $target)) "Existing archive has separate custody $name"
        $temp = $target + '.mir-editor-cold-' + [guid]::NewGuid().ToString('N')
        Require (-not (Test-Path -LiteralPath $temp)) 'Archive staging path occupied'
        try {
            [IO.File]::Copy($source,$temp,$false)
            Require ((Sha $temp) -ceq $hashes[$name]) "Staged archive differs $name"
            $identity = Get-MIRImmutableInputFileIdentity $temp
            [IO.File]::Move($temp,$target,$false)
            $created.Add(@{path=$target;sha256=$hashes[$name];identity=$identity})
        } finally {
            if (Test-Path -LiteralPath $temp) { [IO.File]::Delete($temp) }
        }
    }
    $activation = Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $engineData -ProfilePath $profile -ArchiveHashes $hashes -LibraryLock $lock
    $write = Invoke-EditorLeg 'initial' @('--start-server-load-scenario','EditorExtensions/testing',
        '--server-settings',$serverPath,'--bind','127.0.0.1','--port','34197') -saveName 'editor-testing'
    $initialText = Get-Content -LiteralPath (Join-Path $write 'factorio-current.log') -Raw
    Require ($initialText.Contains('Loading level.dat: 3537452 bytes.') -and $initialText.Contains('Map version 1.2.32-0')) 'Native Editor Extensions map differs'
    $saved = Join-Path $write 'saves/editor-testing.zip'
    $report['save_sha256'] = Sha $saved
    $test = 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; assert any(n.endswith(("/level.dat","/level.dat0")) for n in z.namelist())'
    & python3 -I -c $test $saved
    Require ($LASTEXITCODE -eq 0) 'Saved scenario ZIP is invalid'
    for ($i=1;$i -le 2;$i++) {
        $copy = Join-Path $out "input-cold-$i.zip"
        [IO.File]::Copy($saved,$copy,$false)
        $coldWrite = Invoke-EditorLeg "cold-$i" @('--test-save',$copy,'--test-arg','cold','--test-ticks','5')
        Require ((Sha $copy) -ceq $report.save_sha256 -and (Sha $saved) -ceq $report.save_sha256) 'Cold load changed saved bytes'
        Require ((Get-Content -LiteralPath (Join-Path $coldWrite 'factorio-current.log') -Raw).Contains('Test passed')) 'Cold engine test did not report success'
        $report.cold_loads++
    }
} catch {
    $failure = $_
} finally {
    try {
        if ($null -ne $activation) {
            $report['library_restoration'] = Complete-MIRLibraryActivation -Activation $activation
            foreach ($name in $controls.Keys) {
                $after = Read-MIRLibraryControl (Join-Path $library $name)
                Require ($after.exists -eq $controls[$name].exists -and $after.sha256 -ceq $controls[$name].sha256) "Original control differs $name"
            }
            $report.controls_restored = $true
        }
        if ($created.Count -gt 0) {
            Require (-not (Test-Path -LiteralPath $journal)) 'Preserve archives pending library recovery'
            foreach ($item in $created) {
                Require ((Get-MIRImmutableInputFileIdentity $item.path) -ceq $item.identity -and (Sha $item.path) -ceq $item.sha256) 'Preserve a changed staged archive'
                [IO.File]::Delete($item.path)
            }
            $report.archive_cleanup = $true
        }
    } catch {
        $cleanup.Add($_.Exception.Message)
    } finally {
        if ($null -ne $lock) { $lock.Dispose() }
    }
    $report['processes'] = $context.runs
    $report['cleanup_errors'] = @($cleanup)
    if ($null -eq $failure -and $cleanup.Count -eq 0 -and $report.cold_loads -eq 2 -and
        $report.controls_restored -and $report.archive_cleanup) {
        $report.status = 'passed'
    } else {
        $report.status = 'failed'
        if ($null -ne $failure) { $report['error'] = $failure.Exception.Message }
    }
    Write-MIRNativeProbeResult -Context $context -Record $report
}
if ($null -ne $failure) { throw $failure }
Require ($report.status -ceq 'passed') 'Replay or cleanup failed'
