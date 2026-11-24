# Isolated hosted qualification for the published 4.7.3 startup-settings boundary.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InputRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$root = (Resolve-Path -LiteralPath $InputRoot).Path
. (Join-Path $PSScriptRoot 'lib/validation/NativeProbeResources.ps1')
. (Join-Path $PSScriptRoot 'lib/compatibility/LibraryActivation.ps1')

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Sha([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function Write-Json([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 24) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}
function Read-Json([string]$Path) {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}
function Assert-Save([string]$Path) {
    $check = 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; assert any(n.endswith(("/level.dat","/level.dat0")) for n in z.namelist())'
    & python3 -I -c $check $Path
    Require ($LASTEXITCODE -eq 0) 'Save CRC or native level differs'
}

$engineData = Join-Path $root 'engine/factorio/data'
$engine = Join-Path $root 'engine/factorio/bin/x64/factorio'
$engineHash = '062277B9D91F5DF9E655A77E6A94EC0208E668ECFC1C4424EE1B12C9AAAB2DCF'
Require ((Sha $engine) -ceq $engineHash) 'Headless engine differs'
$library = Join-Path $root 'library'
$source = '4.7.21003'
$public = '5.0.21022'
$candidate = '5.0.21023'
$candidateRecord = Read-Json (Join-Path $root 'candidate-package.json')
Require ($candidateRecord.source_commit -ceq '41952c13dfab4602e0b06ab18f20a8792ab67836' -and
    $candidateRecord.version -ceq $candidate) 'Candidate source or distribution differs'
$archives = @{
    $source = 'B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852'
    $public = '847399EE8BCA28E1A893761873E5C8B04E9B0FD168D8669575CC9D080F4E602F'
    $candidate = $candidateRecord.sha256.ToUpperInvariant()
}
$official = @('base', 'elevated-rails', 'quality', 'recycler', 'space-age')
foreach ($name in $official) {
    Require ((Read-Json (Join-Path $engineData "$name/info.json")).version -ceq '2.1.24') "Wrong official mod $name"
}
foreach ($version in $archives.Keys) {
    Require ((Sha (Join-Path $library "more-infinite-research_$version.zip")) -ceq $archives[$version]) "MIR archive differs $version"
}
$out = Join-Path $root 'execution'
$context = New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $out -ExpectedPeakMemoryMiB 2048 -MaxNewOutputMiB 192 -UseExactOutputRoot
[IO.Directory]::CreateDirectory($context.root) | Out-Null
$scenario = Join-Path $repo 'tests/fixtures/worker-legacy-idle-replay/control.lua'
$server = Read-Json (Join-Path $engineData 'server-settings.example.json')
$server.name = 'MIR isolated legacy worker settings replay'
$server.visibility = @{public=$false;lan=$false}
$server.auto_pause = $false
$server.autosave_interval = 0
$serverPath = Join-Path $out 'server-settings.json'
Write-Json $serverPath $server
$restorations = [Collections.Generic.List[object]]::new()
$stages = [Collections.Generic.List[object]]::new()

function Invoke-Leg([string]$Name, [string]$Version, [string[]]$RunArgs, [string]$InputSave = '',
    [string[]]$SaveNames = @(), [string]$ExpectedError = '') {
    $leg = Join-Path $out $Name
    $write = Join-Path $leg 'write-data'
    [IO.Directory]::CreateDirectory((Join-Path $write 'saves')) | Out-Null
    if ($Version -ceq $source) {
        $directory = Join-Path $write 'scenarios/mir-worker-legacy-idle'
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        Copy-Item -LiteralPath $scenario -Destination (Join-Path $directory 'control.lua')
    }
    $saveDigest = $null
    if ($InputSave) {
        $saveDigest = Sha $InputSave
        $target = Join-Path $leg 'input.zip'
        [IO.File]::Copy($InputSave, $target, $false)
        Require ((Sha $target) -ceq $saveDigest) "Working save copy differs $Name"
        $RunArgs = @($RunArgs | ForEach-Object { if ($_ -ceq '<input>') { $target } else { $_ } })
    }
    $profile = Join-Path $leg 'profile.json'
    $mods = @($official | ForEach-Object { @{name=$_;version='2.1.24';enabled=$true} })
    $mods += @{name='more-infinite-research';version=$Version;enabled=$true}
    $settingsPath = Join-Path $root $(if ($Version -ceq $source) { 'settings-source.dat' } else { 'settings-upgrade.dat' })
    $settingsHash = Sha $settingsPath
    Write-Json $profile @{schema=1;kind='legacy-worker-startup-change';target='f210';factorio_line='2.1';
        engine=@{version='2.1.24';sha256=$engineHash};settings_mode='File';settings_sha256=$settingsHash;mods=$mods}
    $config = Join-Path $leg 'config.ini'
    [IO.File]::WriteAllLines($config, @('[path]',"read-data=$engineData","write-data=$write",'','[other]','enable-new-mods=false'))
    $arguments = @('--config',$config,'--mod-directory',$library,'--no-log-rotation') + $RunArgs
    $log = Join-Path $write 'factorio-current.log'
    $savePaths = @($SaveNames | ForEach-Object { Join-Path $write "saves/$_.zip" })
    $predicate = $null
    if ($savePaths.Count -gt 0) {
        $predicate = {
            if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { return $false }
            foreach ($path in $savePaths) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false } }
            return ([regex]::Matches([IO.File]::ReadAllText($log), 'Saving finished').Count -ge $savePaths.Count)
        }.GetNewClosure()
    }
    $asset = @{("more-infinite-research_$Version.zip")=$archives[$Version]}
    $selection = @{LibraryDirectory=$library;EngineDataDirectory=$engineData;ProfilePath=$profile;ArchiveHashes=$asset;
        SettingsMode='File';SettingsPath=$settingsPath;SettingsSha256=$settingsHash}
    $activation = Start-MIRLibraryActivation @selection
    try {
        Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments
        $run = $null
        try {
            $launch = @{Context=$context;FilePath=$engine;Arguments=$arguments;TimeoutSeconds=110;CompletionPredicate=$predicate}
            $run = Invoke-MIRNativeProbeFactorioProcess @launch
        } catch {
            if (-not $ExpectedError -or $context.runs.Count -eq 0) { throw }
            $run = $context.runs[$context.runs.Count - 1]
            if ($run.status -cne 'failed' -or -not (Test-Path -LiteralPath $log -PathType Leaf) -or
                -not [IO.File]::ReadAllText($log).Contains($ExpectedError)) { throw }
        }
        if ($ExpectedError) { Require ($run.status -ceq 'failed') "Expected a native refusal $Name" }
        if ($InputSave) {
            Require ((Sha $InputSave) -ceq $saveDigest -and (Sha $target) -ceq $saveDigest) "Protected input bytes changed $Name"
        }
        $saves = @()
        foreach ($path in $savePaths) {
            Assert-Save $path
            $saves += @{path=$path;sha256=(Sha $path)}
        }
        if ($ExpectedError) {
            Require (@(Get-ChildItem -LiteralPath $write -Filter '*.zip' -Recurse).Count -eq 0) "Refusal created a save $Name"
        }
        $stages.Add(@{name=$Name;archive_sha256=$archives[$Version];input_sha256=$saveDigest;
            settings_sha256=$settingsHash;saves=$saves;process=$run;expected_refusal=$ExpectedError})
    } finally {
        $restorations.Add((Complete-MIRLibraryActivation -Activation $activation))
    }
}

$verdict = [ordered]@{kind='MIRLegacyWorkerStartupSettingsReplayV1';status='started';archive=$candidateRecord.sha256;
    engine=$engineHash;scenario_sha256=(Sha $scenario);stages=$stages;restorations=$restorations}
try {
    $serverArgs = @('--server-settings',$serverPath,'--bind','127.0.0.1','--port','34197')
    Invoke-Leg 'source' $source (@('--start-server-load-scenario','mir-worker-legacy-idle','--map-gen-seed','424242') + $serverArgs) -SaveNames @('predecessor-empty','predecessor-paid')
    $sourcePath = Join-Path $out 'source/write-data'
    $empty = Join-Path $sourcePath 'saves/predecessor-empty.zip'
    $paid = Join-Path $sourcePath 'saves/predecessor-paid.zip'
    $emptyFrame = Read-Json (Join-Path $sourcePath 'script-output/source-empty.json')
    $paidFrame = Read-Json (Join-Path $sourcePath 'script-output/source-paid.json')
    Require ($emptyFrame.workers.player.public.saved -eq 0 -and [Math]::Abs($paidFrame.workers.player.public.saved - .27) -lt 1e-7) 'Source work opponents differ'
    $refuseArgs = @('--test-save','<input>','--test-ticks','1')
    Invoke-Leg 'public-refusal' $public $refuseArgs -InputSave $empty -ExpectedError 'unrecorded default source requires unchanged startup settings'
    Invoke-Leg 'upgrade' $candidate (@('--start-server','<input>') + $serverArgs) -InputSave $empty -SaveNames @('successor')
    Invoke-Leg 'paid-refusal' $candidate $refuseArgs -InputSave $paid -ExpectedError 'older default source has unfinished native worker work'
    $successor = Join-Path $out 'upgrade/write-data/saves/successor.zip'
    $closedPath = Join-Path $out 'upgrade/write-data/script-output/closed.json'
    for ($i=1; $i -le 2; $i++) {
        $tag = "cold-$i"
        Invoke-Leg $tag $candidate @('--test-save','<input>','--test-arg','reload','--test-ticks','4') -InputSave $successor
        $coldPath = Join-Path $out "$tag/write-data/script-output/cold.json"
        $compare = 'import json,sys; a,b=[json.load(open(n,encoding="utf-8")) for n in sys.argv[1:]]; assert all(a[k]==b[k] for k in ("workers","unrelated","spent"))'
        & python3 -I -c $compare $closedPath $coldPath
        Require ($LASTEXITCODE -eq 0) "Cold readback differs $tag"
    }
    Require (-not (Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json'))) 'Library activation did not restore'
    foreach ($version in $archives.Keys) {
        Require ((Sha (Join-Path $library "more-infinite-research_$version.zip")) -ceq $archives[$version]) "Restored archive differs $version"
    }
    Require ($stages.Count -eq 6 -and $restorations.Count -eq 6) 'Stage or restoration count differs'
    $verdict.status = 'passed'
} catch {
    $verdict.status = 'failed'
    $verdict.error = $_.Exception.Message
    throw
} finally {
    $verdict.processes = $context.runs
    Write-MIRNativeProbeResult -Context $context -Record $verdict
}
