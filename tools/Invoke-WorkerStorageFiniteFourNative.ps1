[CmdletBinding()]
param(
    [ValidateSet('Validate', 'Compose', 'Execute')]
    [string]$Mode = 'Validate',
    [string]$PacketPath = (Join-Path $PSScriptRoot '../tests/fixtures/worker-storage-finite-four-native.json'),
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CanonicalActorMembers = @(
    [ordered]@{role='observer control';sha256='6C8FB257FEB3BE0614F32A4F8AADA558946F5C43EEC5378804F3FAF20630F276';bytes=6530},
    [ordered]@{role='observer info';sha256='CECDAE11F13FE2D4ED92FFD78AB0D153809703F3CA29DB8269118F0159C1A519';bytes=294},
    [ordered]@{role='observer data';sha256='6492E27219B136ED865FEE3F2125EC27D98DB716A6E19A4F2113454D5153BE9D';bytes=231},
    [ordered]@{role='provider info';sha256='DB8D808D99BF1ED151745672BE9BCB6266DECACF308E265D2BD2DDADBE88D733';bytes=363},
    [ordered]@{role='provider data';sha256='69BA675379EDB935267F59700BEC031033FB6D4354D0D7D02945EC5912EBD6E6';bytes=799}
)
$script:CanonicalHelperPins = @(
    [ordered]@{path='tools/lib/validation/ImmutableInputStaging.ps1';sha256='25523C83C26501444A01729226E504199A3294F02E5330DEB1BB4D305832FBEE';bytes=27295},
    [ordered]@{path='tools/lib/compatibility/LibraryActivation.ps1';sha256='A98570967D35048ECFEAEC7124BB1D9A4501B208E9EAB8CC6E647A638CA2DF7D';bytes=41094},
    [ordered]@{path='tools/lib/validation/NativeProbeResources.ps1';sha256='1504B4BE12920BE4354CA74204D9B0621481215D08A5F4D231C8C75BCB8D7CB3';bytes=15778},
    [ordered]@{path='tools/lib/validation/ResourceGovernor.ps1';sha256='A132F4921106DA917B931982B74887FD72A20AFFCE25EE37E8DC894461385674';bytes=63443}
)
$script:CanonicalFixtureArchives = @(
    [ordered]@{role='finite provider archive';filename='mir-worker-storage-finite-fixture_0.1.0.zip';sha256='6AB77CAF709F88029EE26E30CD932FD03558EE2059068176989B9423DCC678B1';bytes=1064},
    [ordered]@{role='native observer archive';filename='mir-worker-storage-native-observer_0.1.2.zip';sha256='DB33C8FABDF6AB1759726BE5D17F4920337478581E50838025B8F8F3755E7B0C';bytes=3086}
)

function Get-FiniteFourNativeSha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Read-FiniteFourNativeJson {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "packet is missing: $Path" }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
}

function Require-FiniteFourNative {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-FiniteFourNativeEqual {
    param($Actual,$Expected,[string]$Name)
    if ($Actual -is [bool] -or $Expected -is [bool]) {
        if (($Actual -isnot [bool]) -or ($Expected -isnot [bool]) -or $Actual -ne $Expected) { throw "$Name differs" }
        return
    }
    if ($Actual -ne $Expected) { throw "$Name differs; expected '$Expected', got '$Actual'" }
}

function Assert-FiniteFourNativeNumber {
    param($Value,[string]$Name)
    if ($Value -is [bool] -or $Value -isnot [ValueType] -or $Value -is [char]) { throw "$Name is not numeric" }
    [double]$Value
}

function Assert-FiniteFourNativeNear {
    param($Actual,[double]$Expected,[string]$Name)
    if ([math]::Abs((Assert-FiniteFourNativeNumber $Actual $Name)-$Expected) -gt 1e-8) { throw "$Name differs" }
}

function Get-FiniteFourNativePath {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Find-FiniteFourNativeRepoRoot {
    param([Parameter(Mandatory)][string]$StartPath)
    $current=(Resolve-Path -LiteralPath $StartPath).Path
    while($true){
        if((Test-Path -LiteralPath (Join-Path $current 'tools')) -and
           (Test-Path -LiteralPath (Join-Path $current 'tests')) -and
           (Test-Path -LiteralPath (Join-Path $current 'source'))){ return $current }
        $parent=Split-Path -Parent $current
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current){break}
        $current=$parent
    }
    throw 'MIR repository root is unavailable from executor location'
}

function Test-FiniteFourNativeFile {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Descriptor,
        [Parameter(Mandatory)][string]$Label
    )
    $path = if ($Descriptor.Contains('path')) { [string]$Descriptor['path'] } elseif ($Descriptor.Contains('local_path')) { [string]$Descriptor['local_path'] } else { '' }
    $sha = [string]$Descriptor['sha256']
    $bytes = if ($Descriptor.Contains('bytes') -and $null -ne $Descriptor['bytes']) { [int64]$Descriptor['bytes'] } else { $null }
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [ordered]@{label=$Label;state='missing_local_input';path=$path;sha256=$sha;bytes=$bytes}
    }
    $item=Get-Item -LiteralPath $path -Force
    if ($null -ne $bytes -and $item.Length -ne $bytes) { throw "$Label bytes differ" }
    $actual=Get-FiniteFourNativeSha256 $path
    if ($actual -ne $sha.ToUpperInvariant()) { throw "$Label SHA-256 differs" }
    [ordered]@{label=$Label;state='verified_local_input';path=$path;sha256=$actual;bytes=$item.Length}
}

function Assert-FiniteFourNativePacket {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Packet,[Parameter(Mandatory)][string]$RepoRoot)
    Assert-FiniteFourNativeEqual $Packet['schema'] 1 'packet schema'
    Assert-FiniteFourNativeEqual $Packet['kind'] 'MIRWorkerStorageFiniteFourA504NativeExecutorPacketV1' 'packet kind'
    Assert-FiniteFourNativeEqual $Packet['case_id'] 'worker-storage-finite-four-published473-to-current-a504' 'packet case'
    Assert-FiniteFourNativeEqual $Packet['inputs']['source_mir']['sha256'].ToUpperInvariant() 'B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852' 'published473 SHA-256'
    Assert-FiniteFourNativeEqual ([int64]$Packet['inputs']['source_mir']['bytes']) ([int64]1463293) 'published473 bytes'
    Assert-FiniteFourNativeEqual $Packet['inputs']['candidate_mir']['sha256'].ToUpperInvariant() 'C9620529B4BBF65B30DF728DE47B93B0BE45D938417FD387D92F4B64AA1A837D' 'candidate SHA-256'
    Assert-FiniteFourNativeEqual ([int64]$Packet['inputs']['candidate_mir']['bytes']) ([int64]1053618) 'candidate bytes'
    Assert-FiniteFourNativeEqual $Packet['inputs']['candidate_mir']['source_commit'] '22f34725d00befd4c80160105b98b556824b57ed' 'candidate source commit'
    Assert-FiniteFourNativeEqual $Packet['inputs']['candidate_mir']['player_tree'] 'a504d92fe798d570df58514f9f839c4954af14f3' 'candidate player tree'
    Assert-FiniteFourNativeEqual $Packet['inputs']['engine']['archive_sha256'].ToUpperInvariant() 'C49B66CFF90ACEFF87B30F2973AF0DF7F51712CB2EE3153E0169D9BED46A964F' 'engine archive SHA-256'
    Assert-FiniteFourNativeEqual $Packet['inputs']['engine']['factorio_binary_sha256'].ToUpperInvariant() '062277B9D91F5DF9E655A77E6A94EC0208E668ECFC1C4424EE1B12C9AAAB2DCF' 'engine binary SHA-256'
    Assert-FiniteFourNativeEqual $Packet['inputs']['engine']['platform'] 'Linux headless' 'engine distribution'
    Assert-FiniteFourNativeEqual $Packet['inputs']['engine']['headless'] $true 'engine headless capability'
    Assert-FiniteFourNativeEqual $Packet['protocol']['confirmation_marker'] 'Using Lua console commands will disable achievements. Please repeat the command to proceed.' 'console confirmation marker'
    Require-FiniteFourNative ($Packet['inputs']['fixtures'] -is [System.Collections.IList] -and $Packet['inputs']['fixtures'].Count -eq 2) 'fixture archive selection differs'
    foreach($canonical in $script:CanonicalFixtureArchives){
        $fixture=@($Packet['inputs']['fixtures']|Where-Object { $_['role'] -eq $canonical.role })
        Require-FiniteFourNative ($fixture.Count -eq 1) "fixture archive selection differs: $($canonical.role)"
        Assert-FiniteFourNativeEqual $fixture[0]['filename'] $canonical.filename "fixture archive filename $($canonical.role)"
        Assert-FiniteFourNativeEqual $fixture[0]['sha256'].ToUpperInvariant() $canonical.sha256 "fixture archive SHA-256 $($canonical.role)"
        Assert-FiniteFourNativeEqual ([int64]$fixture[0]['bytes']) ([int64]$canonical.bytes) "fixture archive bytes $($canonical.role)"
    }
    Require-FiniteFourNative ($Packet['inputs']['actor_members'] -is [System.Collections.IList] -and $Packet['inputs']['actor_members'].Count -eq 5) 'actor member selection differs'
    foreach($canonical in $script:CanonicalActorMembers) {
        $member=@($Packet['inputs']['actor_members']|Where-Object { $_['role'] -eq $canonical.role })
        Require-FiniteFourNative ($member.Count -eq 1) "actor member selection differs: $($canonical.role)"
        Assert-FiniteFourNativeEqual $member[0]['sha256'].ToUpperInvariant() $canonical.sha256 "actor member SHA-256 $($canonical.role)"
        Assert-FiniteFourNativeEqual ([int64]$member[0]['bytes']) ([int64]$canonical.bytes) "actor member bytes $($canonical.role)"
        $memberPath=Get-FiniteFourNativePath $RepoRoot ([string]$member[0]['path'])
        $member[0]['path']=$memberPath
        $state=Test-FiniteFourNativeFile -Descriptor $member[0] -Label $canonical.role
        Require-FiniteFourNative ($state.state -eq 'verified_local_input') "actor member source is unavailable: $($canonical.role)"
    }
    Require-FiniteFourNative ($Packet['helper_pins'] -is [System.Collections.IList] -and $Packet['helper_pins'].Count -eq $script:CanonicalHelperPins.Count) 'helper selection differs'
    foreach($canonical in $script:CanonicalHelperPins) {
        $pin=@($Packet['helper_pins']|Where-Object { $_['path'] -eq $canonical.path })
        Require-FiniteFourNative ($pin.Count -eq 1) "helper selection differs: $($canonical.path)"
        Assert-FiniteFourNativeEqual $pin[0]['sha256'].ToUpperInvariant() $canonical.sha256 "helper SHA-256 $($canonical.path)"
        Assert-FiniteFourNativeEqual ([int64]$pin[0]['bytes']) ([int64]$canonical.bytes) "helper bytes $($canonical.path)"
        $helperPath=Get-FiniteFourNativePath $RepoRoot ([string]$pin[0]['path'])
        $pin[0]['path']=$helperPath
        $state=Test-FiniteFourNativeFile -Descriptor $pin[0] -Label "helper $([IO.Path]::GetFileName($helperPath))"
        Require-FiniteFourNative ($state.state -eq 'verified_local_input') 'required helper source is unavailable'
    }
    $controlPath=Get-FiniteFourNativePath $RepoRoot 'tests/fixtures/worker-storage-native-observer/control.lua'
    $controlText=Get-Content -LiteralPath $controlPath -Raw
    foreach($fragment in @('assert(event.by_script~=true,"MIR research was granted by script")','report("before-successor-lab")','force.laboratory_speed_modifier=1000')) {
        Require-FiniteFourNative $controlText.Contains($fragment) "actor contract source fragment is absent: $fragment"
    }
}

function Get-FiniteFourNativeInputStates {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Packet)
    $state=@()
    $state += Test-FiniteFourNativeFile -Descriptor $Packet['inputs']['source_mir'] -Label 'published473 predecessor'
    $state += Test-FiniteFourNativeFile -Descriptor $Packet['inputs']['candidate_mir'] -Label 'a504 candidate'
    $engine=[ordered]@{path=$Packet['inputs']['engine']['binary_path'];sha256=$Packet['inputs']['engine']['factorio_binary_sha256'];bytes=$null}
    $state += Test-FiniteFourNativeFile -Descriptor $engine -Label 'official Factorio 2.1.24 binary'
    foreach($fixture in $Packet['inputs']['fixtures']) { $state += Test-FiniteFourNativeFile -Descriptor $fixture -Label ([string]$fixture['role']) }
    foreach($name in @('library_directory','output_root','source_profile','candidate_profile','server_settings_template','source_seed_map_gen_settings')) {
        $path=[string]$Packet['runtime_bindings'][$name]
        if([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) { $state += [ordered]@{label=$name;state='missing_local_binding';path=$path} }
        else { $state += [ordered]@{label=$name;state='bound_local_input';path=$path} }
    }
    return $state
}

function Get-FiniteFourNativeFingerprint {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "file is missing: $Path" }
    [ordered]@{path=$Path;bytes=(Get-Item -LiteralPath $Path -Force).Length;sha256=(Get-FiniteFourNativeSha256 $Path)}
}

function Assert-FiniteFourNativeFingerprint {
    param($Before,[Parameter(Mandatory)][string]$Path,[string]$Name)
    $after=Get-FiniteFourNativeFingerprint $Path
    Assert-FiniteFourNativeEqual $after.bytes $Before.bytes "$Name bytes"
    Assert-FiniteFourNativeEqual $after.sha256 $Before.sha256 "$Name SHA-256"
    $after
}

function Assert-FiniteFourNativeFingerprintRecord {
    param($Expected,[Parameter(Mandatory)][string]$Path,[string]$Name)
    Require-FiniteFourNative ($Expected -is [System.Collections.IDictionary]) "$Name initial fingerprint differs"
    $actual=Get-FiniteFourNativeFingerprint $Path
    Assert-FiniteFourNativeEqual ([int64]$actual.bytes) ([int64]$Expected['bytes']) "$Name initial bytes"
    Assert-FiniteFourNativeEqual $actual.sha256 $Expected['sha256'] "$Name initial SHA-256"
    return $actual
}

function Assert-FiniteFourNativeDistinctCopy {
    param([Parameter(Mandatory)][string]$ProtectedPath,[Parameter(Mandatory)][string]$WorkingPath,[string]$Name)
    Assert-FiniteFourNativeEqual (Get-FiniteFourNativeSha256 $WorkingPath) (Get-FiniteFourNativeSha256 $ProtectedPath) "$Name copy SHA-256"
    if (([IO.Path]::GetFullPath($ProtectedPath)) -eq ([IO.Path]::GetFullPath($WorkingPath))) { throw "$Name reuses protected pathname" }
    if (Get-Command Get-MIRImmutableInputFileIdentity -ErrorAction SilentlyContinue) {
        if ((Get-MIRImmutableInputFileIdentity -Path $ProtectedPath) -eq (Get-MIRImmutableInputFileIdentity -Path $WorkingPath)) { throw "$Name aliases protected input" }
    }
}

function Read-FiniteFourNativeMarker {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedStage,[ValidateSet('source','successor')][string]$Role)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "marker is missing: $Path" }
    $marker=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    foreach($field in @('stage','engine','mods','tick','next_level','completed','worker_bonus','finite_researched','finite_maximum','finite_effect','research_progress','current','queue','foreign_progress','native_lab_completions')){
        Require-FiniteFourNative ($marker.Contains($field)-and$null-ne$marker[$field]) "marker lacks $field"
    }
    Assert-FiniteFourNativeEqual $marker['stage'] $ExpectedStage 'marker stage'
    Assert-FiniteFourNativeEqual $marker['engine'] '2.1.24' 'marker engine'
    Require-FiniteFourNative ($marker['mods'] -is [System.Collections.IDictionary]) 'marker mods differs'
    Require-FiniteFourNative ($marker['mods'].Count -eq 4) 'marker mod closure differs'
    $mir=if($Role -eq 'source'){'4.7.21003'}else{'5.0.21018'}
    foreach($pair in @(@('base','2.1.24'),@('mir-worker-storage-finite-fixture','0.1.0'),@('mir-worker-storage-native-observer','0.1.2'),@('more-infinite-research',$mir))){Assert-FiniteFourNativeEqual $marker['mods'][$pair[0]] $pair[1] "marker mod $($pair[0])"}
    Assert-FiniteFourNativeEqual $marker['finite_researched'] $true 'finite researched'
    Assert-FiniteFourNativeEqual $marker['current'] 'worker-robots-storage-5' 'marker current'
    Require-FiniteFourNative ($marker['queue'] -is [System.Collections.IList] -and $marker['queue'].Count -eq 2) 'marker queue differs'
    Assert-FiniteFourNativeEqual $marker['queue'][0] 'worker-robots-storage-5' 'marker queue first'
    Assert-FiniteFourNativeEqual $marker['queue'][1] 'mir-worker-test-unrelated' 'marker queue second'
    Assert-FiniteFourNativeNear $marker['finite_maximum'] 4 'finite maximum';Assert-FiniteFourNativeNear $marker['finite_effect'] 2 'finite effect';Assert-FiniteFourNativeNear $marker['research_progress'] .42 'research sentinel';Assert-FiniteFourNativeNear $marker['foreign_progress'] .27 'foreign sentinel'
    $completion=if($Role -eq 'source' -or $ExpectedStage -in @('configuration','before-successor-lab')){1}else{2}
    Assert-FiniteFourNativeNear $marker['next_level'] (5+$completion) 'next level';Assert-FiniteFourNativeNear $marker['completed'] $completion 'completed';Assert-FiniteFourNativeNear $marker['worker_bonus'] (5+(2*$completion)) 'worker bonus';Assert-FiniteFourNativeNear $marker['native_lab_completions'] $completion 'lab completions'
    return $marker
}

function Assert-FiniteFourNativeLocalMarkerTicks {
    param([Parameter(Mandatory)][object[]]$Markers)
    $previous=[int64]-1
    foreach($marker in $Markers){
        $tick=Assert-FiniteFourNativeNumber $marker['tick'] 'marker tick'
        if([math]::Floor($tick) -ne $tick -or $tick -le $previous){throw 'local marker tick order differs'}
        $previous=[int64]$tick
    }
}

function Assert-FiniteFourNativeEarnedRun {
    param([Parameter(Mandatory)]$Run,[Parameter(Mandatory)][string]$Name)
    foreach($field in @('passed','timed_out','completion_predicate_observed','exit_code')){Require-FiniteFourNative ($null-ne$Run.PSObject.Properties[$field]) "$Name result lacks $field"}
    Assert-FiniteFourNativeEqual $Run.passed $true "$Name passed";Assert-FiniteFourNativeEqual $Run.timed_out $false "$Name timeout";Assert-FiniteFourNativeEqual $Run.completion_predicate_observed $true "$Name completion predicate"
    if($Run.exit_code -ne 0 -and $Run.exit_code -ne 137){throw "$Name exit code differs"}
    return [ordered]@{exit_code=$Run.exit_code;completion_predicate_observed=$Run.completion_predicate_observed;governed_stop=($Run.exit_code -eq 137)}
}

function Assert-FiniteFourNativeColdRun {
    param([Parameter(Mandatory)]$Run,[Parameter(Mandatory)][string]$StdoutPath,[Parameter(Mandatory)][string]$Name)
    Assert-FiniteFourNativeEqual $Run.passed $true "$Name passed";Assert-FiniteFourNativeEqual $Run.timed_out $false "$Name timeout";Assert-FiniteFourNativeEqual $Run.exit_code 0 "$Name natural exit"
    if(-not(Test-Path -LiteralPath $StdoutPath -PathType Leaf)-or -not([IO.File]::ReadAllText($StdoutPath).Contains('Test passed'))){throw "$Name lacks Test passed"}
}

function Test-FiniteFourNativeSaveZip {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Name save is missing"}
    $python=Get-Command python3 -ErrorAction SilentlyContinue
    if($null-eq$python){$python=Get-Command python -ErrorAction SilentlyContinue}
    if($null-eq$python){throw "$Name save CRC reader is unavailable"}
    $program='import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; assert any(e.filename.endswith(("level.dat","level.dat0")) for e in z.infolist())'
    $output=@(& $python.Source -I -c $program $Path 2>&1)
    if($LASTEXITCODE-ne0){throw "$Name save CRC or level data differs: $($output -join ' ')"}
}

function Read-FiniteFourNativeCompleteChain {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Chain)
    foreach($stage in @('source','successor','cold1','cold2')){Require-FiniteFourNative ($Chain.Contains($stage)-and$Chain[$stage]-is[System.Collections.IDictionary]) "chain lacks $stage"}
    $source=$Chain['source'];$successor=$Chain['successor'];$cold1=$Chain['cold1'];$cold2=$Chain['cold2']
    Assert-FiniteFourNativeEarnedRun -Run $source['run'] -Name 'source'|Out-Null
    $sourceEarned=Read-FiniteFourNativeMarker -Path $source['earned_marker'] -ExpectedStage 'source-earned' -Role source
    $sourceFinished=Read-FiniteFourNativeMarker -Path $source['finished_marker'] -ExpectedStage 'source-finished' -Role source
    if ((-not [IO.File]::ReadAllText($source['log']).Contains('MIR_WORKER_NATIVE')) -or
        (-not [IO.File]::ReadAllText($source['log']).Contains('Saving finished'))) {
        throw 'source log lacks completion/save evidence'
    }
    Test-FiniteFourNativeSaveZip -Path $source['protected_save'] -Name 'source'
    Require-FiniteFourNative $source.Contains('protected_initial') 'source protected initial fingerprint is absent'
    $sourceBefore=Assert-FiniteFourNativeFingerprintRecord -Expected $source['protected_initial'] -Path $source['protected_save'] -Name 'protected source'
    Assert-FiniteFourNativeDistinctCopy -ProtectedPath $source['protected_save'] -WorkingPath $successor['working_input'] -Name 'successor'
    Assert-FiniteFourNativeEarnedRun -Run $successor['run'] -Name 'successor'|Out-Null
    $configuration=Read-FiniteFourNativeMarker -Path $successor['configuration_marker'] -ExpectedStage 'configuration' -Role successor
    $before=Read-FiniteFourNativeMarker -Path $successor['before_marker'] -ExpectedStage 'before-successor-lab' -Role successor
    $successorEarned=Read-FiniteFourNativeMarker -Path $successor['earned_marker'] -ExpectedStage 'successor-earned' -Role successor
    $successorFinished=Read-FiniteFourNativeMarker -Path $successor['finished_marker'] -ExpectedStage 'successor-finished' -Role successor
    Assert-FiniteFourNativeEqual $successor['acceleration_reapplied'] 1000 'successor accelerator'
    if ((-not [IO.File]::ReadAllText($successor['log']).Contains('MIR_WORKER_NATIVE')) -or
        (-not [IO.File]::ReadAllText($successor['log']).Contains('Saving finished'))) {
        throw 'successor log lacks completion/save evidence'
    }
    Assert-FiniteFourNativeFingerprint -Before $sourceBefore -Path $source['protected_save'] -Name 'protected source'|Out-Null
    Test-FiniteFourNativeSaveZip -Path $successor['protected_save'] -Name 'successor'
    Require-FiniteFourNative $successor.Contains('protected_initial') 'successor protected initial fingerprint is absent'
    $successorBefore=Assert-FiniteFourNativeFingerprintRecord -Expected $successor['protected_initial'] -Path $successor['protected_save'] -Name 'protected successor'
    foreach($cold in @($cold1,$cold2)){
        Assert-FiniteFourNativeDistinctCopy -ProtectedPath $successor['protected_save'] -WorkingPath $cold['working_input'] -Name ([string]$cold['name'])
        Assert-FiniteFourNativeColdRun -Run $cold['run'] -StdoutPath $cold['stdout'] -Name ([string]$cold['name'])
        [void](Read-FiniteFourNativeMarker -Path $cold['marker'] -ExpectedStage 'reload' -Role successor)
        Assert-FiniteFourNativeFingerprint -Before $successorBefore -Path $successor['protected_save'] -Name 'protected successor'|Out-Null
    }
    # Saves bind processes by protected-copy hash. Factorio persists the actor
    # tick in each save, so no global tick monotonicity is valid across source,
    # successor, and independent cold reload processes.
    Assert-FiniteFourNativeLocalMarkerTicks -Markers @($sourceEarned,$sourceFinished)
    Assert-FiniteFourNativeLocalMarkerTicks -Markers @($configuration,$before,$successorEarned,$successorFinished)
    return [ordered]@{source=Get-FiniteFourNativeFingerprint $source['protected_save'];successor=Get-FiniteFourNativeFingerprint $successor['protected_save'];cold_working_inputs=@($cold1['working_input'],$cold2['working_input']);governed_earning_stops=@($source['run'].exit_code,$successor['run'].exit_code)}
}

function New-FiniteFourNativeComposePlan {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Packet)
    [ordered]@{
        status='COMPOSED_EXECUTOR_PLAN_NOT_ADMITTED'
        stages=@(
            [ordered]@{name='create-source-seed';arguments=@('--create','<source-seed.zip>');natural_exit_required=$true},
            [ordered]@{name='source-server';console_command=$Packet['protocol']['source_console_command'];marker_order=@('source-earned','source-finished');completion_predicate_required=$true;governed_stop_permitted=$true},
            [ordered]@{name='successor-server';console_command=$Packet['protocol']['successor_console_command'];configuration_precedes_console_request=$true;marker_order_after_console_request=@('before-successor-lab','successor-earned','successor-finished');acceleration_reapplied=1000;completion_predicate_required=$true;governed_stop_permitted=$true},
            [ordered]@{name='cold-reload-1';arguments=@('--test-save','<distinct copy>','--test-arg','reload','--test-ticks',$Packet['bounds']['cold_test_ticks']);natural_exit_required=$true;test_passed_required=$true},
            [ordered]@{name='cold-reload-2';arguments=@('--test-save','<distinct copy>','--test-arg','reload','--test-ticks',$Packet['bounds']['cold_test_ticks']);natural_exit_required=$true;test_passed_required=$true}
        )
        protocol_difference_from_r02=$Packet['prepared_from']['executor_difference_from_r02']
        no_native_claim='Compose validates only the controller contract; it does not create an output root, context, lease, library activation, process, RCON listener, or save.'
    }
}

function New-FiniteFourNativeConfig {
    param([string]$Path,[string]$EngineData,[string]$WriteData)
    $content="[path]`nread-data=$EngineData`nwrite-data=$WriteData`n`n[other]`nenable-new-mods=false`n"
    [IO.File]::WriteAllText($Path,$content,[Text.UTF8Encoding]::new($false))
}

function New-FiniteFourNativeEngineArguments {
    param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$LibraryDirectory)
    # The selected 2.1.24 distribution is headless. Use the established
    # capability helper rather than passing the GUI-only --disable-audio flag.
    return @('--config',$ConfigPath,'--mod-directory',$LibraryDirectory,'--no-log-rotation') + @(Get-MIRNativeAudioArguments -Headless)
}

function New-FiniteFourNativeServerSettings {
    param([string]$Template,[string]$Path)
    $settings=Get-Content -LiteralPath $Template -Raw|ConvertFrom-Json -AsHashtable
    $settings.name='MIR isolated finite-four worker check';$settings.description='';$settings.visibility=[ordered]@{public=$false;lan=$false};$settings.username='';$settings.password='';$settings.token='';$settings.game_password='';$settings.require_user_verification=$false;$settings.auto_pause=$false;$settings.autosave_interval=0;$settings.max_players=1
    [IO.File]::WriteAllText($Path,(($settings|ConvertTo-Json -Depth 32)+"`n"),[Text.UTF8Encoding]::new($false))
}

function Complete-FiniteFourNativeCleanup {
    param(
        $PrimaryError,
        [Parameter(Mandatory)][scriptblock]$CleanupAction
    )
    $cleanupErrors=[Collections.Generic.List[string]]::new()
    try { & $CleanupAction } catch { $cleanupErrors.Add($_.Exception.Message) }
    if($cleanupErrors.Count -eq 0){ return }
    if($null-ne$PrimaryError){
        $PrimaryError.Exception.Data['finite_four_cleanup_errors']=@($cleanupErrors)
        throw $PrimaryError
    }
    throw ('finite-four cleanup failed: '+($cleanupErrors -join '; '))
}

function Get-FiniteFourNativeException {
    param([Parameter(Mandatory)]$ErrorRecord)
    if ($ErrorRecord -is [Management.Automation.ErrorRecord]) { return $ErrorRecord.Exception }
    if ($ErrorRecord -is [Exception]) { return $ErrorRecord }
    throw 'finite-four primary failure type differs'
}

function Get-FiniteFourNativeRunList {
    param($Context)
    if ($null -eq $Context) { return @() }
    $runsProperty=$Context.PSObject.Properties['runs']
    if ($null -eq $runsProperty -or $null -eq $runsProperty.Value) { return @() }
    return @($runsProperty.Value | ForEach-Object { $_ })
}

function Get-FiniteFourNativeStartedProcessState {
    param($Context)
    $invocationCount=0
    if($null-ne$Context){
        $indexProperty=$Context.PSObject.Properties['process_index']
        if($null-ne$indexProperty-and$indexProperty.Value-is[ValueType]-and$indexProperty.Value-isnot[bool]-and[int64]$indexProperty.Value-ge0){$invocationCount=[int]$indexProperty.Value}
    }
    $processIds=[Collections.Generic.List[int64]]::new();$ledgerErrors=[Collections.Generic.List[string]]::new()
    foreach($run in Get-FiniteFourNativeRunList $Context){
        $ledgerProperty=$run.PSObject.Properties['ledger']
        if($null-eq$ledgerProperty-or[string]::IsNullOrWhiteSpace([string]$ledgerProperty.Value)-or-not(Test-Path -LiteralPath ([string]$ledgerProperty.Value) -PathType Leaf)){continue}
        try {
            foreach($line in Get-Content -LiteralPath ([string]$ledgerProperty.Value)){
                if([string]::IsNullOrWhiteSpace($line)){continue}
                $sample=$line|ConvertFrom-Json -AsHashtable -Depth 64
                if($sample-isnot[Collections.IDictionary]-or$sample['process']-isnot[Collections.IDictionary]){continue}
                $process=$sample['process']
                if(-not$process.Contains('id')-or-not$process.Contains('phase')-or$process['phase']-cne'running'-or-not$process.Contains('start_identity')-or$null-eq$process['start_identity']){continue}
                $id=$process['id']
                if($id-is[ValueType]-and$id-isnot[bool]-and[int64]$id-gt0-and-not$processIds.Contains([int64]$id)){[void]$processIds.Add([int64]$id)}
            }
        } catch {
            [void]$ledgerErrors.Add((([string]$ledgerProperty.Value)+': '+$_.Exception.Message))
        }
    }
    return [ordered]@{invocation_count=$invocationCount;actual_started_process_ids=@($processIds);ledger_read_errors=@($ledgerErrors)}
}

function New-FiniteFourNativeFailedExecutionRecord {
    param(
        [Parameter(Mandatory)]$PrimaryError,
        $Context,
        [Parameter(Mandatory)][System.Collections.IDictionary]$ExecutionState,
        [Parameter(Mandatory)][System.Collections.IDictionary]$CleanupOutcome
    )
    $exception=Get-FiniteFourNativeException $PrimaryError
    $started=Get-FiniteFourNativeStartedProcessState $Context
    $consoleFacts=$exception.Data['mir441_factorio_console_startup']
    $processCleanupFacts=$exception.Data['mir441_process_cleanup_facts']
    $restoration=[Collections.Generic.List[object]]::new()
    if($ExecutionState.Contains('restoration')-and$null-ne$ExecutionState['restoration']){foreach($item in $ExecutionState['restoration']){[void]$restoration.Add($item)}}
    $cleanupFacts=[Collections.Generic.List[object]]::new()
    if($processCleanupFacts-is[Collections.IEnumerable]-and$processCleanupFacts-isnot[string]){foreach($item in $processCleanupFacts){[void]$cleanupFacts.Add($item)}}
    $resourceRuns=[Collections.Generic.List[object]]::new()
    foreach($run in Get-FiniteFourNativeRunList $Context){[void]$resourceRuns.Add($run)}
    return [ordered]@{
        schema=1
        kind='MIRWorkerStorageFiniteFourA504NativeExecutionResultV1'
        status='failed-retained-adverse'
        primary_cause=[ordered]@{message=$exception.Message;type=$exception.GetType().FullName}
        resource_admission=$exception.Data['mir441_resource_admission']
        attempted_invocations=$started.invocation_count
        actual_started_process_ids=$started.actual_started_process_ids
        started_process_ledger_read_errors=$started.ledger_read_errors
        resource_runs=$resourceRuns
        console_startup=$consoleFacts
        process_cleanup_facts=$cleanupFacts
        restoration=$restoration
        cleanup=$CleanupOutcome
    }
}

function Write-FiniteFourNativeFailedExecutionResult {
    param(
        [Parameter(Mandatory)]$PrimaryError,
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][System.Collections.IDictionary]$ExecutionState,
        [Parameter(Mandatory)][System.Collections.IDictionary]$CleanupOutcome
    )
    try {
        $record=New-FiniteFourNativeFailedExecutionRecord -PrimaryError $PrimaryError -Context $Context -ExecutionState $ExecutionState -CleanupOutcome $CleanupOutcome
        Write-MIRNativeProbeResult -Context $Context -Record $record
        return $true
    } catch {
        $exception=Get-FiniteFourNativeException $PrimaryError
        $exception.Data['finite_four_failure_ledger_write_attempted']=$true
        $exception.Data['finite_four_failure_ledger_write_succeeded']=$false
        $exception.Data['finite_four_failure_ledger_write_error']=$_.Exception.Message
        return $false
    }
}

function Invoke-FiniteFourNativeExecution {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Packet,[Parameter(Mandatory)][string]$RepoRoot)
    # Dot-source in this caller scope. Importing through a helper function
    # would discard its function-local definitions before this execution can
    # call the governor, direct-library, and immutable-input helpers.
    . (Join-Path $RepoRoot 'tools/lib/validation/ImmutableInputStaging.ps1')
    . (Join-Path $RepoRoot 'tools/lib/compatibility/LibraryActivation.ps1')
    . (Join-Path $RepoRoot 'tools/lib/validation/NativeProbeResources.ps1')
    $runtime=$Packet['runtime_bindings'];$inputs=$Packet['inputs'];$bounds=$Packet['bounds'];$executionState=[ordered]@{activation=$null;restoration=[Collections.Generic.List[object]]::new()};$context=$null;$primary=$null;$validated=$null;$cleanupOutcome=[ordered]@{attempted=$false;succeeded=$true;errors=@();library_restoration=[ordered]@{applicable=$false;attempted=$false;succeeded=$null;records=@()}}
    try {
        $context=New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot ([string]$runtime['output_root']) -ExpectedPeakMemoryMiB ([int]$bounds['expected_peak_memory_mib']) -MaxNewOutputMiB ([int]$bounds['max_new_output_mib']) -UseExactOutputRoot
        [IO.Directory]::CreateDirectory($context.root)|Out-Null
        $engine=[string]$inputs['engine']['binary_path'];$engineData=[string]$inputs['engine']['engine_data_path'];$library=[string]$runtime['library_directory']
        $source=$inputs['source_mir'];$candidate=$inputs['candidate_mir'];$fixtures=@($inputs['fixtures'])
        $sourceProfile=[string]$runtime['source_profile'];$candidateProfile=[string]$runtime['candidate_profile']
        $sourceRoot=Join-Path $context.root 'source';$successorRoot=Join-Path $context.root 'successor';[IO.Directory]::CreateDirectory($sourceRoot)|Out-Null;[IO.Directory]::CreateDirectory($successorRoot)|Out-Null
        function Invoke-LegActivation([string]$Profile,[hashtable]$Archives){
            $executionState.activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $engineData -ProfilePath $Profile -ArchiveHashes $Archives -SettingsMode Defaults
            Add-MIRNativeProbeLibraryActivation -Context $context -Activation $executionState.activation
        }
        function Close-LegActivation(){
            if($null-ne$executionState.activation-and-not$executionState.activation.closed){
                $executionState.restoration.Add((Complete-MIRLibraryActivation -Activation $executionState.activation))
                $executionState.activation=$null
            }
        }
        $sourceArchives=@{};$sourceArchives[[string]$source['filename']]=[string]$source['sha256'];foreach($row in $fixtures){$sourceArchives[[string]$row['filename']]=[string]$row['sha256']}
        Invoke-LegActivation $sourceProfile $sourceArchives
        $sourceWrite=Join-Path $sourceRoot 'write-data';$sourceSaves=Join-Path $sourceWrite 'saves';[IO.Directory]::CreateDirectory($sourceSaves)|Out-Null;$sourceConfig=Join-Path $sourceRoot 'config.ini';New-FiniteFourNativeConfig $sourceConfig $engineData $sourceWrite
        $seed=Join-Path $sourceRoot 'seed.zip';$createArguments=(New-FiniteFourNativeEngineArguments -ConfigPath $sourceConfig -LibraryDirectory $library)+@('--create',$seed,'--map-gen-settings',[string]$runtime['source_seed_map_gen_settings']);Assert-MIRLibraryLaunch -Activation $executionState.activation -FactorioBin $engine -Arguments $createArguments
        $create=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $engine -Arguments $createArguments -TimeoutSeconds ([int]$bounds['create_timeout_seconds'])
        Assert-FiniteFourNativeEqual $create.result.exit_code 0 'create natural exit';Assert-FiniteFourNativeEqual $create.result.completion_predicate_observed $false 'create completion predicate'
        $sourceWork=Join-Path $sourceRoot 'source-consumed.zip';[IO.File]::Copy($seed,$sourceWork,$false);Assert-FiniteFourNativeDistinctCopy $seed $sourceWork 'source'
        $sourceSettings=Join-Path $sourceRoot 'server-settings.json';New-FiniteFourNativeServerSettings ([string]$runtime['server_settings_template']) $sourceSettings
        $sourceSave=Join-Path $sourceSaves 'worker-source.zip';$sourceMarkerDir=Join-Path $sourceWrite 'script-output/worker-storage';$sourceLog=Join-Path $sourceWrite 'factorio-current.log';$sourceFinished=Join-Path $sourceMarkerDir 'source-finished.json'
        $sourceCompletion={ (Test-Path -LiteralPath $sourceFinished -PathType Leaf) -and (Test-Path -LiteralPath $sourceSave -PathType Leaf) -and (Test-Path -LiteralPath $sourceLog -PathType Leaf) -and ([IO.File]::ReadAllText($sourceLog).Contains('Saving finished')) }.GetNewClosure()
        $sourceArguments=(New-FiniteFourNativeEngineArguments -ConfigPath $sourceConfig -LibraryDirectory $library)+@('--start-server',$sourceWork,'--server-settings',$sourceSettings,'--bind','127.0.0.1','--port',[string]$runtime['server_port'])
        Assert-MIRLibraryLaunch -Activation $executionState.activation -FactorioBin $engine -Arguments $sourceArguments
        $sourceRun=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $engine -Arguments $sourceArguments -TimeoutSeconds ([int]$bounds['server_timeout_seconds']) -CompletionPredicate $sourceCompletion -ConsoleStartup ([ordered]@{command=$Packet['protocol']['source_console_command'];ready_marker=$Packet['protocol']['console_ready_marker'];confirmation_marker=$Packet['protocol']['confirmation_marker']})
        Close-LegActivation
        $protectedSource=Join-Path $context.root 'protected-source.zip';[IO.File]::Copy($sourceSave,$protectedSource,$false);$protectedSourceInitial=Get-FiniteFourNativeFingerprint $protectedSource
        $candidateArchives=@{};$candidateArchives[[string]$candidate['filename']]=[string]$candidate['sha256'];foreach($row in $fixtures){$candidateArchives[[string]$row['filename']]=[string]$row['sha256']}
        Invoke-LegActivation $candidateProfile $candidateArchives
        $successorWrite=Join-Path $successorRoot 'write-data';$successorSaves=Join-Path $successorWrite 'saves';[IO.Directory]::CreateDirectory($successorSaves)|Out-Null;$successorConfig=Join-Path $successorRoot 'config.ini';New-FiniteFourNativeConfig $successorConfig $engineData $successorWrite
        $successorWork=Join-Path $successorRoot 'successor-consumed.zip';[IO.File]::Copy($protectedSource,$successorWork,$false);Assert-FiniteFourNativeDistinctCopy $protectedSource $successorWork 'successor'
        $successorSettings=Join-Path $successorRoot 'server-settings.json';New-FiniteFourNativeServerSettings ([string]$runtime['server_settings_template']) $successorSettings
        $successorSave=Join-Path $successorSaves 'worker-successor.zip';$successorMarkerDir=Join-Path $successorWrite 'script-output/worker-storage';$successorLog=Join-Path $successorWrite 'factorio-current.log';$successorFinished=Join-Path $successorMarkerDir 'successor-finished.json'
        $successorCompletion={ (Test-Path -LiteralPath $successorFinished -PathType Leaf) -and (Test-Path -LiteralPath $successorSave -PathType Leaf) -and (Test-Path -LiteralPath $successorLog -PathType Leaf) -and ([IO.File]::ReadAllText($successorLog).Contains('Saving finished')) }.GetNewClosure()
        $successorArguments=(New-FiniteFourNativeEngineArguments -ConfigPath $successorConfig -LibraryDirectory $library)+@('--start-server',$successorWork,'--server-settings',$successorSettings,'--bind','127.0.0.1','--port',[string]$runtime['server_port'])
        Assert-MIRLibraryLaunch -Activation $executionState.activation -FactorioBin $engine -Arguments $successorArguments
        $successorRun=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $engine -Arguments $successorArguments -TimeoutSeconds ([int]$bounds['server_timeout_seconds']) -CompletionPredicate $successorCompletion -ConsoleStartup ([ordered]@{command=$Packet['protocol']['successor_console_command'];ready_marker=$Packet['protocol']['console_ready_marker'];confirmation_marker=$Packet['protocol']['confirmation_marker']})
        Close-LegActivation
        $protectedSuccessor=Join-Path $context.root 'protected-successor.zip';[IO.File]::Copy($successorSave,$protectedSuccessor,$false);$protectedSuccessorInitial=Get-FiniteFourNativeFingerprint $protectedSuccessor
        $chain=[ordered]@{source=[ordered]@{run=$sourceRun.result;earned_marker=(Join-Path $sourceMarkerDir 'source-earned.json');finished_marker=$sourceFinished;log=$sourceLog;protected_save=$protectedSource;protected_initial=$protectedSourceInitial};successor=[ordered]@{run=$successorRun.result;configuration_marker=(Join-Path $successorMarkerDir 'configuration.json');before_marker=(Join-Path $successorMarkerDir 'before-successor-lab.json');earned_marker=(Join-Path $successorMarkerDir 'successor-earned.json');finished_marker=$successorFinished;log=$successorLog;working_input=$successorWork;protected_save=$protectedSuccessor;protected_initial=$protectedSuccessorInitial;acceleration_reapplied=1000}}
        for($i=1;$i-le2;$i++){
            $coldRoot=Join-Path $context.root ("cold-$i");$coldWrite=Join-Path $coldRoot 'write-data';[IO.Directory]::CreateDirectory($coldWrite)|Out-Null;$coldConfig=Join-Path $coldRoot 'config.ini';New-FiniteFourNativeConfig $coldConfig $engineData $coldWrite;$coldWork=Join-Path $coldRoot 'cold-input.zip';[IO.File]::Copy($protectedSuccessor,$coldWork,$false);Assert-FiniteFourNativeDistinctCopy $protectedSuccessor $coldWork "cold-$i"
            Invoke-LegActivation $candidateProfile $candidateArchives
            $coldArguments=(New-FiniteFourNativeEngineArguments -ConfigPath $coldConfig -LibraryDirectory $library)+@('--test-save',$coldWork,'--test-arg','reload','--test-ticks',[string]$bounds['cold_test_ticks'])
            Assert-MIRLibraryLaunch -Activation $executionState.activation -FactorioBin $engine -Arguments $coldArguments
            $coldRun=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $engine -Arguments $coldArguments -TimeoutSeconds ([int]$bounds['cold_timeout_seconds'])
            Close-LegActivation
            $chain["cold$i"]=[ordered]@{name="cold-$i";run=$coldRun.result;working_input=$coldWork;marker=(Join-Path $coldWrite 'script-output/worker-storage/reload.json');stdout=$coldRun.stdout}
        }
        $validated=Read-FiniteFourNativeCompleteChain -Chain $chain
    } catch { $primary=$_ } finally {
        $cleanupOutcome.attempted=$true
        try {
            Complete-FiniteFourNativeCleanup -PrimaryError $primary -CleanupAction {
                if($null-ne$executionState.activation-and-not$executionState.activation.closed){
                    $cleanupOutcome.library_restoration.applicable=$true
                    $cleanupOutcome.library_restoration.attempted=$true
                    try {
                        $restoration=Complete-MIRLibraryActivation -Activation $executionState.activation
                        $executionState.restoration.Add($restoration)
                        $cleanupOutcome.library_restoration.records=@($executionState.restoration|ForEach-Object {$_})
                        $cleanupOutcome.library_restoration.succeeded=$true
                        $executionState.activation=$null
                    } catch {
                        $cleanupOutcome.library_restoration.succeeded=$false
                        throw
                    }
                }
            }
        } catch {
            $cleanupOutcome.succeeded=$false
            $cleanupErrors=$_.Exception.Data['finite_four_cleanup_errors']
            $cleanupOutcome.errors=if($cleanupErrors-is[Collections.IEnumerable]-and$cleanupErrors-isnot[string]){@($cleanupErrors|ForEach-Object {[string]$_})}else{@($_.Exception.Message)}
            if($null-eq$primary){$primary=$_}
        }
    }
    if($null-ne$primary){
        if($null-ne$context){
            $null=Write-FiniteFourNativeFailedExecutionResult -PrimaryError $primary -Context $context -ExecutionState $executionState -CleanupOutcome $cleanupOutcome
        }
        throw $primary
    }
    if($null-eq$validated){throw 'finite-four execution produced no terminal record'}
    $completedRecord=[ordered]@{schema=1;kind='MIRWorkerStorageFiniteFourA504NativeExecutionResultV1';status='completed-await-independent-review';chain=$validated;resource_runs=$context.runs;restoration=$executionState.restoration;cleanup=$cleanupOutcome}
    Write-MIRNativeProbeResult -Context $context -Record $completedRecord
    return $completedRecord
}

function Write-FiniteFourNativeReceipt {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Record)
    $parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw "output parent is missing: $parent"}
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((($Record|ConvertTo-Json -Depth 100)+"`n"));$stream=$null
    try{$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{if($null-ne$stream){$stream.Dispose()}}
}

function Invoke-FiniteFourNativeExecutor {
    param([Parameter(Mandatory)][ValidateSet('Validate','Compose','Execute')][string]$RequestedMode,[Parameter(Mandatory)][string]$RequestedPacketPath,[Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RequestedOutputPath)
    $packet=Read-FiniteFourNativeJson $RequestedPacketPath;Assert-FiniteFourNativePacket -Packet $packet -RepoRoot $RepoRoot;$inputs=Get-FiniteFourNativeInputStates $packet;$missing=@($inputs|Where-Object {$_.state -match '^missing'})
    $record=[ordered]@{schema=1;kind='MIRWorkerStorageFiniteFourA504NativeExecutorReceiptV1';mode=$RequestedMode;packet_sha256=(Get-FiniteFourNativeSha256 $RequestedPacketPath);input_states=$inputs;deferred_missing_bindings=@($missing|ForEach-Object label);native_processes_started=0;library_activation=$false;resource_context_allocated=$false;execution_plan=(New-FiniteFourNativeComposePlan $packet);limit='No current result is gameplay evidence.'}
    if($RequestedMode -eq 'Validate'){$record.status=if($missing.Count){'DEFERRED_MISSING_LOCAL_BINDINGS'}else{'VALIDATED_NOT_ADMITTED'}}
    elseif($RequestedMode -eq 'Compose'){$record.status=if($missing.Count){'COMPOSED_DEFERRED_MISSING_LOCAL_BINDINGS'}else{'COMPOSED_NOT_ADMITTED'}}
    else {if($missing.Count){throw 'Execute refuses missing local bindings'};$record=Invoke-FiniteFourNativeExecution -Packet $packet -RepoRoot $RepoRoot}
    Write-FiniteFourNativeReceipt -Path $RequestedOutputPath -Record $record
    [pscustomobject]$record
}

if($MyInvocation.InvocationName -ne '.'){
    if([string]::IsNullOrWhiteSpace($OutputPath)){
        throw 'OutputPath is required; choose a new path under build/ or another explicit custody directory.'
    }
    Invoke-FiniteFourNativeExecutor -RequestedMode $Mode -RequestedPacketPath $PacketPath -RepoRoot (Find-FiniteFourNativeRepoRoot -StartPath $PSScriptRoot) -RequestedOutputPath $OutputPath
}
