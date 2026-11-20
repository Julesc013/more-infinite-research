[CmdletBinding()]
param(
    [ValidateSet('Validate', 'Compose', 'Execute')]
    [string]$Mode = 'Validate',
    [string]$PacketPath = (Join-Path $PSScriptRoot '../tests/fixtures/worker-storage-se-cap-ten-native.json'),
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# This is deliberately a case-specific owner.  Invoke-NativeFixture remains
# F210/default-settings-only for its existing finite-speed protocol.
$script:CargoActorRoot = 'tests/fixtures/worker-storage-se-cap-ten-native'
$script:CargoActorMembers = @(
    [ordered]@{path='control.lua';sha256='43BDC761671F6DE2DD43634C15B7A7A08E8F482E700045717145A52945BB7141';bytes=27285},
    [ordered]@{path='data-final-fixes.lua';sha256='E860A534CE99E25D300988E9684B1D03F2DC3CA6CAEF8BB0851E5066270B1926';bytes=3493},
    [ordered]@{path='data.lua';sha256='6C30FB3F21238E3D3AC46D09C7F23A2510FA215E26F312850276E2579C690CEF';bytes=1053},
    [ordered]@{path='info-f200.json';sha256='280292F01A17994DCEB5D7731FA60029928A7F9E9F28890EBB0872A099D01398';bytes=452},
    [ordered]@{path='prerequisites.lua';sha256='E5CE84A0AA88310D51D780E1C583FCB01C02C71A69AE9ED58471D26186188E5B';bytes=5699}
)
$script:CargoHelperPins = @(
    [ordered]@{path='tools/lib/validation/ImmutableInputStaging.ps1';sha256='25523C83C26501444A01729226E504199A3294F02E5330DEB1BB4D305832FBEE';bytes=27295},
    [ordered]@{path='tools/lib/compatibility/LibraryActivation.ps1';sha256='A98570967D35048ECFEAEC7124BB1D9A4501B208E9EAB8CC6E647A638CA2DF7D';bytes=41094},
    [ordered]@{path='tools/lib/validation/NativeProbeResources.ps1';sha256='1504B4BE12920BE4354CA74204D9B0621481215D08A5F4D231C8C75BCB8D7CB3';bytes=15778},
    [ordered]@{path='tools/lib/validation/ResourceGovernor.ps1';sha256='D7CEFFD1DC7D9E1A2B0D0CB19FE78D6AF31157B9CB40A0E4548F5397D6D43195';bytes=63682}
)
$script:CargoEngineBindings = [ordered]@{
    'linux-c9-headless-2.0.77' = [ordered]@{
        binding_id='linux-c9-headless-2.0.77';host_platform='Linux';headless_build=$true
        factorio_binary_sha256='C9AC91D318BDBCCE5AFAAC30D48F4B71DC38AF257712A5D4D4C4FEB625737198'
    }
    'windows-d3-full-2.0.77' = [ordered]@{
        binding_id='windows-d3-full-2.0.77';host_platform='Windows';headless_build=$false
        factorio_binary_sha256='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B';factorio_binary_bytes=43530192
        installation_root='D:/Games/Factorio/2.0'
    }
}
$script:CargoProfilePins = [ordered]@{
    'linux-c9-headless-2.0.77' = [ordered]@{
        source_sha256='FE43E77B748F026D0D040913A37BDA3687658AE1FA720F3DC96C6D5758CB7633';source_bytes=4809
        candidate_sha256='DE15A5B886E883C76B0C07FAF238571541E346C4A4CC76B1D25E42381902762B';candidate_bytes=4874
    }
    'windows-d3-full-2.0.77' = [ordered]@{
        source_sha256='76273C6BBE25D0E0CC18CD447057A715A4052E3186CD032DBCC02152D53FFF67';source_bytes=5007
        candidate_sha256='FFF9560988F0A6E7EC08C30245494DA38D0E3A50AAF4352F2A491930B2188490';candidate_bytes=5072
    }
}
$script:CargoSEMods = @(
    @('base','2.0.77'),@('aai-containers','0.3.2'),@('aai-industry','0.6.16'),@('aai-signal-transmission','0.5.3'),
    @('alien-biomes','0.7.4'),@('alien-biomes-graphics','0.7.1'),@('informatron','0.4.0'),@('jetpack','0.4.17'),
    @('robot_attrition','0.6.6'),@('shield-projector','0.2.2'),@('space-exploration','0.7.57'),@('space-exploration-graphics','0.7.5'),
    @('space-exploration-graphics-2','0.7.2'),@('space-exploration-graphics-3','0.7.2'),@('space-exploration-graphics-4','0.7.2'),
    @('space-exploration-graphics-5','0.7.3'),@('space-exploration-menu-simulations','0.7.4'),@('space-exploration-postprocess','0.7.5'),
    @('mir-fixture-mir5-worker-storage-se-cap-ten-native','0.1.0')
)
$script:CargoExpectedSettings = [ordered]@{
    'mir-enable-worker-robots-storage'='boolean:true'
    'mir-max-level-worker-robots-storage'='number:10'
    'mir-cost-base-worker-robots-storage'='number:200'
    'mir-cost-linear-increment-worker-robots-storage'='number:0'
    'mir-cost-growth-worker-robots-storage'='number:1.5'
    'mir-research-time-worker-robots-storage'='number:60'
    'mir-effect-per-level-worker-robots-storage'='number:1'
}
$script:CargoExpectedConstruction = [ordered]@{
    name='worker-robots-storage-4'
    prerequisite='worker-robots-storage-3'
    formula='675*1.5^(L-4)'
    time='60'
    ingredients='automation-science-pack:1,chemical-science-pack:1,logistic-science-pack:1,production-science-pack:1,se-material-science-pack-1:1,se-rocket-science-pack:1,space-science-pack:1'
    effects='worker-robot-storage:1'
}
$script:CargoSciencePacks = @(
    'automation-science-pack','logistic-science-pack','chemical-science-pack','production-science-pack',
    'se-rocket-science-pack','se-material-science-pack-1','space-science-pack'
)
$script:CargoSourceWorker = 'worker-robots-storage-4'
$script:CargoPrivateWorker = 'mir-worker-storage-default-4'
$script:CargoHeadWorker = 'mir-worker-storage-head-4'
$script:CargoTail = 'mir-fixture-worker-storage-se-cap-ten-tail'
# The reviewed fixture's source entrypoint starts a fresh --create world with
# `game.forces.player`; the default player force is index 1.  The marker has
# only numeric force indexes, so the reader must bind the earned delta to this
# owned role rather than accepting an arbitrary changed force.
$script:CargoPlayerForceIndex = '1'

function Get-CargoCapTenSha256 { param([Parameter(Mandatory)][string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Require-CargoCapTen { param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message} }
function Assert-CargoCapTenEqual { param($Actual,$Expected,[string]$Name) if($Actual -ne $Expected){throw "$Name differs; expected '$Expected', got '$Actual'"} }
function Assert-CargoCapTenNumber { param($Value,[string]$Name) if($null-eq$Value-or$Value-is[bool]-or$Value-is[char]){throw "$Name is not numeric"};[double]$number=0;if(-not[double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)){throw "$Name is not numeric"};if([double]::IsNaN($number)-or[double]::IsInfinity($number)){throw "$Name is nonfinite"};$number }
function Assert-CargoCapTenNear { param($Actual,[double]$Expected,[string]$Name) if([math]::Abs((Assert-CargoCapTenNumber $Actual $Name)-$Expected)-gt 1e-7){throw "$Name differs"} }

function Get-CargoCapTenEngineBinding {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Engine)
    Require-CargoCapTen ($Engine.Contains('binding_id')) 'engine binding is absent'
    $bindingId=[string]$Engine['binding_id'];Require-CargoCapTen ($script:CargoEngineBindings.Contains($bindingId)) 'engine binding differs'
    $binding=$script:CargoEngineBindings[$bindingId]
    foreach($field in @('binding_id','host_platform','factorio_binary_sha256')){Require-CargoCapTen ($Engine.Contains($field)) "engine $field is absent";$actual=([string]$Engine[$field]).ToUpperInvariant();$expected=([string]$binding[$field]).ToUpperInvariant();Assert-CargoCapTenEqual -Actual $actual -Expected $expected -Name "engine $field"}
    Require-CargoCapTen ($Engine.Contains('headless_build')-and$Engine['headless_build']-is[bool]) 'engine headless mode differs';Assert-CargoCapTenEqual -Actual ([bool]$Engine['headless_build']) -Expected ([bool]$binding['headless_build']) -Name 'engine headless mode'
    if($binding.Contains('factorio_binary_bytes')){Require-CargoCapTen ($Engine.Contains('factorio_binary_bytes')) 'engine binary bytes are absent';Assert-CargoCapTenEqual -Actual ([int64]$Engine['factorio_binary_bytes']) -Expected ([int64]$binding['factorio_binary_bytes']) -Name 'engine binary bytes'}
    elseif($Engine.Contains('factorio_binary_bytes')){throw 'engine binary bytes differ'}
    if($binding.Contains('installation_root')){Require-CargoCapTen ($Engine.Contains('installation_root')) 'engine installation root is absent';Assert-CargoCapTenEqual -Actual ([string]$Engine['installation_root']) -Expected ([string]$binding['installation_root']) -Name 'engine installation root'}
    elseif($Engine.Contains('installation_root')){throw 'engine installation root differs'}
    return $binding
}

function Get-CargoCapTenHostPlatform {
    if($IsWindows){return 'Windows'}
    if($IsLinux){return 'Linux'}
    throw 'cargo cap-ten host platform is unsupported'
}

function Assert-CargoCapTenHostEngineBinding {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Packet,[string]$HostPlatform)
    $binding=Get-CargoCapTenEngineBinding $Packet['inputs']['engine'];if([string]::IsNullOrWhiteSpace($HostPlatform)){$HostPlatform=Get-CargoCapTenHostPlatform}
    Assert-CargoCapTenEqual $HostPlatform $binding['host_platform'] 'engine host platform';return $binding
}

function Assert-CargoCapTenEnginePaths {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Packet,[Parameter(Mandatory)][System.Collections.IDictionary]$Binding)
    if(-not$Binding.Contains('installation_root')){return}
    $engine=$Packet['inputs']['engine'];$root=[IO.Path]::GetFullPath([string]$Binding['installation_root'])
    Assert-CargoCapTenEqual -Actual ([IO.Path]::GetFullPath([string]$engine['binary_path'])) -Expected ([IO.Path]::GetFullPath((Join-Path $root 'bin/x64/factorio.exe'))) -Name 'engine binary path'
    Assert-CargoCapTenEqual -Actual ([IO.Path]::GetFullPath([string]$engine['engine_data_path'])) -Expected ([IO.Path]::GetFullPath((Join-Path $root 'data'))) -Name 'engine data path'
}

function Find-CargoCapTenRepoRoot {
    param([Parameter(Mandatory)][string]$StartPath)
    $current=(Resolve-Path -LiteralPath $StartPath).Path
    while($true){
        if((Test-Path -LiteralPath (Join-Path $current 'tools')) -and (Test-Path -LiteralPath (Join-Path $current 'tests')) -and (Test-Path -LiteralPath (Join-Path $current 'source'))){return $current}
        $parent=Split-Path -Parent $current;if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$current){break};$current=$parent
    }
    throw 'MIR repository root is unavailable from executor location'
}
function Read-CargoCapTenJson { param([Parameter(Mandatory)][string]$Path) if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "JSON input is missing: $Path"};Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -AsHashtable -Depth 100 }
function Resolve-CargoCapTenPath { param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path) if([IO.Path]::IsPathRooted($Path)){return [IO.Path]::GetFullPath($Path)};[IO.Path]::GetFullPath((Join-Path $RepoRoot $Path)) }

function Test-CargoCapTenFile {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Descriptor,[Parameter(Mandatory)][string]$Label,[switch]$ObserveMismatch)
    $path=if($Descriptor.Contains('path') -and $null-ne$Descriptor['path']){[string]$Descriptor['path']}else{''}
    $expected=[string]$Descriptor['sha256'];$bytes=if($Descriptor.Contains('bytes') -and $null-ne$Descriptor['bytes']){[int64]$Descriptor['bytes']}else{$null}
    if([string]::IsNullOrWhiteSpace($path)-or-not(Test-Path -LiteralPath $path -PathType Leaf)){return [ordered]@{label=$Label;state='missing_local_input';path=$path;sha256=$expected;bytes=$bytes}}
    $item=Get-Item -LiteralPath $path -Force
    if($null-ne$bytes-and$item.Length-ne$bytes-and-not$ObserveMismatch){throw "$Label bytes differ"}
    $actual=Get-CargoCapTenSha256 $path
    if(($null-ne$bytes-and$item.Length-ne$bytes)-or$actual-cne$expected.ToUpperInvariant()){
        if(-not$ObserveMismatch){throw "$Label SHA-256 differs"}
        return [ordered]@{label=$Label;state='mismatched_local_input';path=$item.FullName;sha256=$expected;bytes=$bytes;observed_sha256=$actual;observed_bytes=$item.Length}
    }
    [ordered]@{label=$Label;state='verified_local_input';path=$item.FullName;sha256=$actual;bytes=$item.Length}
}

function Assert-CargoCapTenPacket {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Packet,[Parameter(Mandatory)][string]$RepoRoot,[switch]$DeferLocalHelperObservation)
    Assert-CargoCapTenEqual $Packet['schema'] 1 'packet schema'
    Assert-CargoCapTenEqual $Packet['kind'] 'MIRWorkerStorageSECargoCapTenF200NativeExecutorPacketV1' 'packet kind'
    Assert-CargoCapTenEqual $Packet['case_id'] 'gamer433-se0757-worker-storage-cap-ten-f394-to-e334' 'packet case'
    Assert-CargoCapTenEqual $Packet['inputs']['engine']['version'] '2.0.77' 'engine version'
    $engineBinding=Get-CargoCapTenEngineBinding $Packet['inputs']['engine']
    Assert-CargoCapTenEqual $Packet['inputs']['source_mir']['sha256'].ToUpperInvariant() 'F3943EB4D69CCDAC41BD9F922AD03A5C78F34F22D8E7FA5A88A7A658AB1010B7' 'source MIR SHA-256'
    Assert-CargoCapTenEqual ([int64]$Packet['inputs']['source_mir']['bytes']) 1449338 'source MIR bytes'
    Assert-CargoCapTenEqual $Packet['inputs']['candidate_mir']['sha256'].ToUpperInvariant() 'E334881F3BA653FAD1288E213D0EB5864551A10A2CE14911D1D0B54A1FE4C4CD' 'candidate MIR SHA-256'
    Assert-CargoCapTenEqual ([int64]$Packet['inputs']['candidate_mir']['bytes']) 1054386 'candidate MIR bytes'
    Assert-CargoCapTenEqual $Packet['inputs']['candidate_mir']['source_commit'] '862dee34c4716cb17dfb48deb12a99e6bc8f1dfc' 'candidate source commit'
    Assert-CargoCapTenEqual $Packet['inputs']['candidate_mir']['player_tree'] 'ec9abdc840aefdd25e66a5787d89e5ad045837c9' 'candidate player tree'
    Assert-CargoCapTenEqual $Packet['inputs']['fixture']['sha256'].ToUpperInvariant() '228791861B63A1C9B4FE6083594C20DE66C877F685652DD981B76491C598D52E' 'fixture SHA-256'
    Assert-CargoCapTenEqual ([int64]$Packet['inputs']['fixture']['bytes']) 11472 'fixture bytes'
    Assert-CargoCapTenEqual $Packet['inputs']['fixture']['source_commit'] '7cfad2708e790b024e2493d00ed5892ac0c2601a' 'fixture source commit'
    $expectedConstruction=$Packet['inputs']['fixture']['expected_data_stage_construction'];Require-CargoCapTen ($expectedConstruction-is[Collections.IDictionary]) 'fixture data-stage construction is unavailable';Require-CargoCapTen ($expectedConstruction.Count-eq$script:CargoExpectedConstruction.Count) 'fixture data-stage construction count differs'
    foreach($field in $script:CargoExpectedConstruction.Keys){Require-CargoCapTen ($expectedConstruction.Contains($field)) "fixture data-stage construction field is absent: $field";Assert-CargoCapTenEqual $expectedConstruction[$field] $script:CargoExpectedConstruction[$field] "fixture data-stage construction $field"}
    Assert-CargoCapTenEqual $Packet['inputs']['settings']['sha256'].ToUpperInvariant() '149E5D54766983A1FA22423439C8DA0ABDF5C8F3F27DF208A3FC753E681192F7' 'File settings SHA-256'
    Assert-CargoCapTenEqual ([int64]$Packet['inputs']['settings']['bytes']) 511 'File settings bytes'
    Assert-CargoCapTenEqual ([int]$Packet['inputs']['settings']['typed_value_count']) 7 'File settings typed values'
    $expectedSettings=$Packet['inputs']['settings']['expected_data_stage_values'];Require-CargoCapTen ($expectedSettings-is[Collections.IDictionary]) 'File settings data-stage values are unavailable';Require-CargoCapTen ($expectedSettings.Count-eq$script:CargoExpectedSettings.Count) 'File settings data-stage value count differs'
    foreach($name in $script:CargoExpectedSettings.Keys){Require-CargoCapTen ($expectedSettings.Contains($name)) "File settings data-stage value is absent: $name";Assert-CargoCapTenEqual $expectedSettings[$name] $script:CargoExpectedSettings[$name] "File settings data-stage value $name"}
    $profilePins=$script:CargoProfilePins[$engineBinding['binding_id']];Require-CargoCapTen ($null-ne$profilePins-and-not[string]::IsNullOrWhiteSpace([string]$profilePins['source_sha256'])) 'engine profile pins are unavailable'
    Assert-CargoCapTenEqual $Packet['inputs']['source_profile']['sha256'].ToUpperInvariant() $profilePins['source_sha256'] 'source profile SHA-256'
    Assert-CargoCapTenEqual ([int64]$Packet['inputs']['source_profile']['bytes']) ([int64]$profilePins['source_bytes']) 'source profile bytes'
    Assert-CargoCapTenEqual $Packet['inputs']['candidate_profile']['sha256'].ToUpperInvariant() $profilePins['candidate_sha256'] 'candidate profile SHA-256'
    Assert-CargoCapTenEqual ([int64]$Packet['inputs']['candidate_profile']['bytes']) ([int64]$profilePins['candidate_bytes']) 'candidate profile bytes'
    Assert-CargoCapTenEqual $Packet['protocol']['fixture_interface'] 'mir-fixture-mir5-worker-storage-se-cap-ten-native' 'fixture interface'
    Assert-CargoCapTenEqual $Packet['protocol']['begin_method'] 'begin' 'fixture begin method'
    Assert-CargoCapTenEqual $Packet['protocol']['confirmation_marker'] 'Using Lua console commands will disable achievements. Please repeat the command to proceed.' 'console confirmation marker'
    Require-CargoCapTen (-not $Packet['protocol'].Contains('candidate_console_command')) 'candidate stage must not send a second actor begin command'
    Assert-CargoCapTenEqual $Packet['protocol']['candidate']['configuration_callback_begins_work'] $true 'candidate configuration actor ownership'
    Assert-CargoCapTenEqual $Packet['protocol']['candidate']['no_console_command'] $true 'candidate command scope'
    Assert-CargoCapTenEqual ([int]$Packet['bounds']['expected_peak_memory_mib']) 8192 'memory budget'
    Assert-CargoCapTenEqual ([int]$Packet['bounds']['max_new_output_mib']) 1024 'output budget'
    Require-CargoCapTen ($Packet['inputs']['actor_members'] -is [Collections.IList] -and $Packet['inputs']['actor_members'].Count -eq $script:CargoActorMembers.Count) 'actor member count differs'
    foreach($canonical in $script:CargoActorMembers){
        $member=@($Packet['inputs']['actor_members']|Where-Object {[string]$_['path']-ceq$canonical.path})
        Require-CargoCapTen ($member.Count-eq1) "actor member selection differs: $($canonical.path)"
        Assert-CargoCapTenEqual $member[0]['sha256'].ToUpperInvariant() $canonical.sha256 "actor member SHA-256 $($canonical.path)"
        Assert-CargoCapTenEqual ([int64]$member[0]['bytes']) ([int64]$canonical.bytes) "actor member bytes $($canonical.path)"
        $path=Join-Path $RepoRoot (Join-Path $script:CargoActorRoot $canonical.path)
        $state=Test-CargoCapTenFile -Descriptor ([ordered]@{path=$path;sha256=$canonical.sha256;bytes=$canonical.bytes}) -Label "actor $($canonical.path)"
        Require-CargoCapTen ($state.state-ceq'verified_local_input') "actor source is unavailable: $($canonical.path)"
    }
    Require-CargoCapTen ($Packet['helper_pins'] -is [Collections.IList] -and $Packet['helper_pins'].Count -eq $script:CargoHelperPins.Count) 'helper pin count differs'
    foreach($canonical in $script:CargoHelperPins){
        $pin=@($Packet['helper_pins']|Where-Object {[string]$_['path']-ceq$canonical.path})
        Require-CargoCapTen ($pin.Count-eq1) "helper selection differs: $($canonical.path)"
        Assert-CargoCapTenEqual $pin[0]['sha256'].ToUpperInvariant() $canonical.sha256 "helper SHA-256 $($canonical.path)"
        Assert-CargoCapTenEqual ([int64]$pin[0]['bytes']) ([int64]$canonical.bytes) "helper bytes $($canonical.path)"
        $path=Resolve-CargoCapTenPath $RepoRoot $canonical.path
        if(-not$DeferLocalHelperObservation){
            $state=Test-CargoCapTenFile -Descriptor ([ordered]@{path=$path;sha256=$canonical.sha256;bytes=$canonical.bytes}) -Label "helper $($canonical.path)"
            Require-CargoCapTen ($state.state-ceq'verified_local_input') "helper source is unavailable: $($canonical.path)"
        }
    }
    $control=Get-Content -LiteralPath (Join-Path $RepoRoot (Join-Path $script:CargoActorRoot 'control.lua')) -Raw
    foreach($fragment in @('remote.add_interface(FIXTURE, {begin = begin_source})','local player = game.forces.player','check(event and event.research == target and event.by_script == false','state.source_frame, state.source_canonical, state.source_role, state.phase = frame(state),','assert_candidate_transfer(state)','assert_earned_bonuses(state, state.ordinary, state.candidate_events, "candidate cap")','assert_tail_current(state, "candidate cap")','cold_phase = type(state) == "table" and state.phase or nil','elseif cold_phase == "idle" then','elseif cold_phase == "source-partial" then','marker("candidate-closed", state, {cap_attempt = "refused"','marker("cold-read", state, {cold_writes = 0}')){
        Require-CargoCapTen $control.Contains($fragment) "actor contract source fragment is absent: $fragment"
    }
}

function Get-CargoCapTenInputStates {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Packet,[Parameter(Mandatory)][string]$RepoRoot)
    $states=@()
    foreach($helper in $Packet['helper_pins']){
        $descriptor=[ordered]@{path=(Resolve-CargoCapTenPath $RepoRoot $helper['path']);sha256=$helper['sha256'];bytes=$helper['bytes']}
        $states+=Test-CargoCapTenFile -Descriptor $descriptor -Label "helper $($helper['path'])" -ObserveMismatch
    }
    foreach($name in @('source_mir','candidate_mir','fixture','settings')){$states+=Test-CargoCapTenFile -Descriptor $Packet['inputs'][$name] -Label $name}
    $binding=Get-CargoCapTenEngineBinding $Packet['inputs']['engine'];$engine=[ordered]@{path=$Packet['inputs']['engine']['binary_path'];sha256=$Packet['inputs']['engine']['factorio_binary_sha256'];bytes=$(if($binding.Contains('factorio_binary_bytes')){[int64]$binding['factorio_binary_bytes']}else{$null})};$states+=Test-CargoCapTenFile -Descriptor $engine -Label 'Factorio 2.0.77 binary'
    $engineData=[string]$Packet['inputs']['engine']['engine_data_path']
    if([string]::IsNullOrWhiteSpace($engineData)-or-not(Test-Path -LiteralPath $engineData -PathType Container)){$states+=[ordered]@{label='engine_data_path';state='missing_local_binding';path=$engineData}}
    else {
        $baseInfo=Join-Path $engineData 'base/info.json'
        if(-not(Test-Path -LiteralPath $baseInfo -PathType Leaf)){throw 'engine data has no base info'}
        $base=Read-CargoCapTenJson $baseInfo;Assert-CargoCapTenEqual $base['version'] '2.0.77' 'engine base version'
        $states+=[ordered]@{label='engine_data_path';state='bound_local_input';path=(Resolve-Path -LiteralPath $engineData).Path}
    }
    foreach($name in @('source_profile','candidate_profile')){
        $profile=[ordered]@{path=$Packet['runtime_bindings'][$name];sha256=$Packet['inputs'][$name]['sha256'];bytes=$Packet['inputs'][$name]['bytes']}
        $states+=Test-CargoCapTenFile -Descriptor $profile -Label $name
    }
    foreach($name in @('library_directory','output_root','server_settings_template')){
        $path=[string]$Packet['runtime_bindings'][$name]
        if([string]::IsNullOrWhiteSpace($path)-or-not(Test-Path -LiteralPath $path)){$states+=[ordered]@{label=$name;state='missing_local_binding';path=$path}}
        else{$states+=[ordered]@{label=$name;state='bound_local_input';path=$path}}
    }
    $port=$Packet['runtime_bindings']['server_port']
    if($port-is[bool]-or$port-isnot[ValueType]-or[int64]$port-lt1024-or[int64]$port-gt65535){$states+=[ordered]@{label='server_port';state='missing_local_binding';path=[string]$port}}
    else{$states+=[ordered]@{label='server_port';state='bound_local_input';path=[string]$port}}
    return $states
}

function Get-CargoCapTenFingerprint { param([Parameter(Mandatory)][string]$Path) if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "file is missing: $Path"};$item=Get-Item -LiteralPath $Path -Force;[ordered]@{path=$item.FullName;bytes=[int64]$item.Length;sha256=(Get-CargoCapTenSha256 $item.FullName)} }
function Assert-CargoCapTenFingerprint { param($Before,[Parameter(Mandatory)][string]$Path,[string]$Name) $after=Get-CargoCapTenFingerprint $Path;Assert-CargoCapTenEqual $after.bytes $Before.bytes "$Name bytes";Assert-CargoCapTenEqual $after.sha256 $Before.sha256 "$Name SHA-256";$after }
function Assert-CargoCapTenDistinctPath { param([Parameter(Mandatory)][string]$ProtectedPath,[Parameter(Mandatory)][string]$WorkingPath,[string]$Name) if(([IO.Path]::GetFullPath($ProtectedPath))-eq([IO.Path]::GetFullPath($WorkingPath))){throw "$Name reuses protected pathname"};if(Get-Command Get-MIRImmutableInputFileIdentity -ErrorAction SilentlyContinue){if((Get-MIRImmutableInputFileIdentity -Path $ProtectedPath)-eq(Get-MIRImmutableInputFileIdentity -Path $WorkingPath)){throw "$Name aliases protected input"}} }
function New-CargoCapTenInitialCopyRecord { param([Parameter(Mandatory)][string]$ProtectedPath,[Parameter(Mandatory)][string]$WorkingPath,[string]$Name) Assert-CargoCapTenDistinctPath $ProtectedPath $WorkingPath $Name;Assert-CargoCapTenEqual (Get-CargoCapTenSha256 $WorkingPath) (Get-CargoCapTenSha256 $ProtectedPath) "$Name copy SHA-256";Get-CargoCapTenFingerprint $WorkingPath }
function Assert-CargoCapTenInitialCopyRecord { param([Parameter(Mandatory)]$ProtectedBefore,[Parameter(Mandatory)]$Initial,[Parameter(Mandatory)][string]$WorkingPath,[string]$Name) Require-CargoCapTen ($Initial-is[Collections.IDictionary]) "$Name initial copy record differs";Assert-CargoCapTenDistinctPath $ProtectedBefore.path $WorkingPath $Name;Assert-CargoCapTenEqual $Initial.path ([IO.Path]::GetFullPath($WorkingPath)) "$Name initial copy path";Assert-CargoCapTenEqual ([int64]$Initial.bytes) ([int64]$ProtectedBefore.bytes) "$Name initial copy bytes";Assert-CargoCapTenEqual $Initial.sha256 $ProtectedBefore.sha256 "$Name initial copy SHA-256" }

function Assert-CargoCapTenProfile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedSha,[Parameter(Mandatory)][string]$MirFilename,[Parameter(Mandatory)][string]$MirSha,[Parameter(Mandatory)][int64]$MirBytes,[Parameter(Mandatory)][System.Collections.IDictionary]$EngineBinding)
    $actual=Get-CargoCapTenSha256 $Path;Assert-CargoCapTenEqual $actual $ExpectedSha.ToUpperInvariant() 'profile SHA-256'
    $profile=Read-CargoCapTenJson $Path
    Assert-CargoCapTenEqual $profile['kind'] 'MIRGamer433SE0757WorkerCargoCap10NativeProfileV1' 'profile kind';Assert-CargoCapTenEqual $profile['target'] 'f200' 'profile target';Assert-CargoCapTenEqual $profile['factorio_line'] '2.0' 'profile line'
    Assert-CargoCapTenEqual $profile['engine']['version'] '2.0.77' 'profile engine';Assert-CargoCapTenEqual $profile['engine']['sha256'].ToUpperInvariant() $EngineBinding['factorio_binary_sha256'] 'profile engine SHA-256'
    if($EngineBinding['binding_id']-ceq'windows-d3-full-2.0.77'){
        Assert-CargoCapTenEqual $profile['engine']['binding_id'] $EngineBinding['binding_id'] 'profile engine binding';Assert-CargoCapTenEqual $profile['engine']['host_platform'] $EngineBinding['host_platform'] 'profile engine host platform';Require-CargoCapTen ($profile['engine']['headless_build']-is[bool]) 'profile engine headless mode differs';Assert-CargoCapTenEqual ([bool]$profile['engine']['headless_build']) ([bool]$EngineBinding['headless_build']) 'profile engine headless mode';Assert-CargoCapTenEqual $profile['engine']['audio_argument'] '--disable-audio' 'profile engine audio argument';Assert-CargoCapTenEqual $profile['engine']['installation_root'] $EngineBinding['installation_root'] 'profile engine installation root';Assert-CargoCapTenEqual ([int64]$profile['engine']['factorio_binary_bytes']) ([int64]$EngineBinding['factorio_binary_bytes']) 'profile engine binary bytes'
    }
    Assert-CargoCapTenEqual $profile['settings_mode'] 'File' 'profile settings mode';Assert-CargoCapTenEqual $profile['settings_input']['sha256'].ToUpperInvariant() '149E5D54766983A1FA22423439C8DA0ABDF5C8F3F27DF208A3FC753E681192F7' 'profile settings SHA-256';Assert-CargoCapTenEqual ([int]$profile['settings_input']['typed_value_count']) 7 'profile settings value count'
    Assert-CargoCapTenEqual $profile['mir_archive']['filename'] $MirFilename 'profile MIR filename';Assert-CargoCapTenEqual $profile['mir_archive']['sha256'].ToUpperInvariant() $MirSha 'profile MIR SHA-256';Assert-CargoCapTenEqual ([int64]$profile['mir_archive']['bytes']) $MirBytes 'profile MIR bytes'
    Require-CargoCapTen ($profile['mods'] -is [Collections.IList] -and $profile['mods'].Count-eq19) 'profile declared 19-mod closure differs'
    foreach($pair in $script:CargoSEMods){$row=@($profile['mods']|Where-Object {[string]$_['name']-ceq$pair[0]});Require-CargoCapTen ($row.Count-eq1) "profile mod differs: $($pair[0])";Assert-CargoCapTenEqual $row[0]['version'] $pair[1] "profile mod version $($pair[0])";Assert-CargoCapTenEqual $row[0]['enabled'] $true "profile mod enabled $($pair[0])"}
    Require-CargoCapTen (-not @($profile['mods']|Where-Object {[string]$_['name']-ceq'more-infinite-research'}).Count) 'prepared profile must remain the 19-row pre-MIR input'
    return $profile
}

function New-CargoCapTenRuntimeProfile {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Profile,[Parameter(Mandatory)][string]$MirFilename,[Parameter(Mandatory)][string]$MirVersion,[Parameter(Mandatory)][string]$MirSha,[Parameter(Mandatory)][string]$Path)
    $mods=[Collections.Generic.List[object]]::new();foreach($row in $Profile['mods']){[void]$mods.Add([ordered]@{name=[string]$row['name'];version=[string]$row['version'];enabled=[bool]$row['enabled']})};[void]$mods.Add([ordered]@{name='more-infinite-research';version=$MirVersion;enabled=$true})
    $hashes=[ordered]@{};foreach($name in @($Profile['archive_sha256'].Keys|Sort-Object)){$hashes[$name]=[string]$Profile['archive_sha256'][$name]};$hashes[$MirFilename]=$MirSha
    Require-CargoCapTen ($mods.Count-eq20) 'runtime profile must select exactly twenty mods'
    Require-CargoCapTen ($hashes.Count-eq19) 'runtime profile must bind nineteen non-base archives'
    $runtime=[ordered]@{schema=1;kind='MIRWorkerStorageSECargoCapTenRuntimeSelectionV1';mods=@($mods);archive_sha256=$hashes}
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((($runtime|ConvertTo-Json -Depth 32)+"`n"));$stream=$null;try{$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{if($null-ne$stream){$stream.Dispose()}}
    return $hashes
}

function New-CargoCapTenConfig { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$EngineData,[Parameter(Mandatory)][string]$WriteData) [IO.File]::WriteAllText($Path,"[path]`nread-data=$EngineData`nwrite-data=$WriteData`n`n[other]`nenable-new-mods=false`n",[Text.UTF8Encoding]::new($false)) }
function New-CargoCapTenEngineArguments {
    param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][System.Collections.IDictionary]$EngineBinding)
    $audio=@(Get-MIRNativeAudioArguments -Headless:([bool]$EngineBinding['headless_build']) )
    if([bool]$EngineBinding['headless_build']){Require-CargoCapTen ($audio.Count-eq0) 'headless engine audio arguments differ'}
    else{Require-CargoCapTen ($audio.Count-eq1-and$audio[0]-ceq'--disable-audio') 'full engine audio arguments differ'}
    return @('--config',$ConfigPath,'--mod-directory',$LibraryDirectory,'--no-log-rotation')+$audio
}
function New-CargoCapTenServerSettings { param([Parameter(Mandatory)][string]$Template,[Parameter(Mandatory)][string]$Path) $settings=Get-Content -LiteralPath $Template -Raw|ConvertFrom-Json -AsHashtable;$settings.name='MIR isolated SE cargo cap-ten check';$settings.description='';$settings.visibility=[ordered]@{public=$false;lan=$false};$settings.username='';$settings.password='';$settings.token='';$settings.game_password='';$settings.require_user_verification=$false;$settings.auto_pause=$false;$settings.autosave_interval=0;$settings.max_players=1;[IO.File]::WriteAllText($Path,(($settings|ConvertTo-Json -Depth 32)+"`n"),[Text.UTF8Encoding]::new($false)) }
function Complete-CargoCapTenActivation {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Execution,[Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]]$Restoration)
    $activation=$Execution['activation']
    if($null-eq$activation-or$activation.closed){return}
    $Restoration.Add((Complete-MIRLibraryActivation -Activation $activation))
    $Execution['activation']=$null
}

function Get-CargoCapTenMarkers {
    param([Parameter(Mandatory)][string]$LogPath)
    if(-not(Test-Path -LiteralPath $LogPath -PathType Leaf)){throw "Factorio log is missing: $LogPath"}
    $rows=[Collections.Generic.List[object]]::new()
    foreach($line in Get-Content -LiteralPath $LogPath){
        $match=[regex]::Match($line,'\[MIR_SE_CARGO_NATIVE\]\|(?<fields>.+)$');if(-not$match.Success){continue}
        $marker=[ordered]@{}
        foreach($field in $match.Groups['fields'].Value.Split('|')){
            $parts=$field.Split('=',2);Require-CargoCapTen ($parts.Count-eq2-and-not[string]::IsNullOrWhiteSpace($parts[0])-and-not[string]::IsNullOrWhiteSpace($parts[1])) 'marker field differs'
            Require-CargoCapTen (-not$marker.Contains($parts[0])) "marker repeats field: $($parts[0])"
            if($parts[0]-in @('tick','progress')){
                [double]$numeric=0;if(-not[double]::TryParse($parts[1],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$numeric)){throw "marker numeric field differs: $($parts[0])"}
                if([double]::IsNaN($numeric)-or[double]::IsInfinity($numeric)){throw "marker numeric field is nonfinite: $($parts[0])"};$marker[$parts[0]]=$numeric
            }else{$marker[$parts[0]]=$parts[1]}
        }
        [void]$rows.Add($marker)
    }
    return @($rows)
}
function Get-CargoCapTenSettingsMarker {
    param([Parameter(Mandatory)][string]$LogPath)
    if(-not(Test-Path -LiteralPath $LogPath -PathType Leaf)){throw "Factorio log is missing: $LogPath"}
    $markers=[Collections.Generic.List[object]]::new()
    foreach($line in Get-Content -LiteralPath $LogPath){
        $match=[regex]::Match($line,'\[MIR_WORKER_STORAGE_SETTINGS\]\s+(?<fields>.+)$');if(-not$match.Success){continue}
        $values=[ordered]@{}
        foreach($field in $match.Groups['fields'].Value.Split('|')){
            $parts=$field.Split('=',2);Require-CargoCapTen ($parts.Count-eq2-and-not[string]::IsNullOrWhiteSpace($parts[0])-and-not[string]::IsNullOrWhiteSpace($parts[1])) 'settings data marker differs'
            Require-CargoCapTen (-not$values.Contains($parts[0])) 'settings data marker differs';$values[$parts[0]]=$parts[1]
        }
        [void]$markers.Add($values)
    }
    Require-CargoCapTen ($markers.Count-eq1) 'settings data marker differs';return $markers[0]
}
function Assert-CargoCapTenSettingsMarker {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Observed,[Parameter(Mandatory)][System.Collections.IDictionary]$Expected,[Parameter(Mandatory)][string]$Name)
    Require-CargoCapTen ($Observed.Count-eq$Expected.Count) "$Name settings data marker differs"
    foreach($setting in $Expected.Keys){Require-CargoCapTen ($Observed.Contains($setting)) "$Name settings data marker differs";Assert-CargoCapTenEqual $Observed[$setting] $Expected[$setting] "$Name settings data marker"}
}
function Get-CargoCapTenActiveModsMarker {
    param([Parameter(Mandatory)][string]$LogPath)
    if(-not(Test-Path -LiteralPath $LogPath -PathType Leaf)){throw "Factorio log is missing: $LogPath"}
    $markers=[Collections.Generic.List[object]]::new()
    foreach($line in Get-Content -LiteralPath $LogPath){
        $match=[regex]::Match($line,'\[MIR_ACTIVE_MODS\]\s+(?<fields>.+)$');if(-not$match.Success){continue}
        $values=[Collections.Generic.List[string]]::new();$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($field in $match.Groups['fields'].Value.Split('|')){Require-CargoCapTen ($field-match'^[^@|\s]+@[^@|\s]+$') 'active-mods data marker differs';Require-CargoCapTen ($seen.Add($field)) 'active-mods data marker differs';[void]$values.Add($field)}
        [void]$markers.Add(@($values))
    }
    Require-CargoCapTen ($markers.Count-eq1) 'active-mods data marker differs';return @($markers[0])
}
function Assert-CargoCapTenActiveModsMarker {
    param([Parameter(Mandatory)][string[]]$Observed,[Parameter(Mandatory)][string]$MirVersion,[Parameter(Mandatory)][string]$Name)
    $expected=[Collections.Generic.List[string]]::new();foreach($pair in $script:CargoSEMods){[void]$expected.Add("$($pair[0])@$($pair[1])")};[void]$expected.Add("more-infinite-research@$MirVersion")
    $left=@($Observed|Sort-Object);$right=@($expected|Sort-Object);Require-CargoCapTen ($left.Count-eq$right.Count) "$Name active-mods data marker differs";for($i=0;$i-lt$right.Count;$i++){Assert-CargoCapTenEqual $left[$i] $right[$i] "$Name active-mods data marker"}
}
function Get-CargoCapTenConstructionMarker {
    param([Parameter(Mandatory)][string]$LogPath)
    if(-not(Test-Path -LiteralPath $LogPath -PathType Leaf)){throw "Factorio log is missing: $LogPath"}
    $markers=[Collections.Generic.List[object]]::new()
    foreach($line in Get-Content -LiteralPath $LogPath){
        $match=[regex]::Match($line,'\[MIR_SE_CARGO_CONSTRUCTION\]\s+(?<fields>.+)$');if(-not$match.Success){continue}
        $values=[ordered]@{}
        foreach($field in $match.Groups['fields'].Value.Split('|')){$parts=$field.Split('=',2);Require-CargoCapTen ($parts.Count-eq2-and-not[string]::IsNullOrWhiteSpace($parts[0])-and-not[string]::IsNullOrWhiteSpace($parts[1])) 'construction data marker differs';Require-CargoCapTen (-not$values.Contains($parts[0])) 'construction data marker differs';$values[$parts[0]]=$parts[1]}
        [void]$markers.Add($values)
    }
    Require-CargoCapTen ($markers.Count-eq1) 'construction data marker differs';return $markers[0]
}
function Assert-CargoCapTenConstructionMarker {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Observed,[Parameter(Mandatory)][System.Collections.IDictionary]$Expected,[Parameter(Mandatory)][string]$Name)
    Require-CargoCapTen ($Observed.Count-eq$Expected.Count) "$Name construction data marker differs"
    foreach($field in $Expected.Keys){Require-CargoCapTen ($Observed.Contains($field)) "$Name construction data marker differs";Assert-CargoCapTenEqual $Observed[$field] $Expected[$field] "$Name construction data marker"}
}
function Get-CargoCapTenOneMarker { param([Parameter(Mandatory)][object[]]$Markers,[Parameter(Mandatory)][string]$Phase) $row=@($Markers|Where-Object {[string]$_['phase']-ceq$Phase});Require-CargoCapTen ($row.Count-eq1) "marker phase differs: $Phase";return $row[0] }
function Get-CargoCapTenNumericMap {
    param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Name)
    $rows=[ordered]@{}
    foreach($row in $Value.Split(',')){
        $parts=$row.Split(':',2);Require-CargoCapTen ($parts.Count-eq2-and$parts[0]-match'^[^,:=|\s]+$') "$Name map differs";Require-CargoCapTen (-not$rows.Contains($parts[0])) "$Name map differs"
        [double]$number=0;if(-not[double]::TryParse($parts[1],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)){throw "$Name map differs"};if([double]::IsNaN($number)-or[double]::IsInfinity($number)){throw "$Name map is nonfinite"};$rows[$parts[0]]=$number
    }
    return $rows
}
function Get-CargoCapTenScience {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Marker,[Parameter(Mandatory)][string]$Name)
    foreach($field in @('science_issued','science_remaining','science_debit')){Require-CargoCapTen ($Marker.Contains($field)) "$Name $field is absent"}
    $issued=Get-CargoCapTenNumericMap $Marker['science_issued'] "$Name science issued";$remaining=Get-CargoCapTenNumericMap $Marker['science_remaining'] "$Name science remaining";$debit=Get-CargoCapTenNumericMap $Marker['science_debit'] "$Name science debit"
    foreach($map in @($issued,$remaining,$debit)){Require-CargoCapTen ($map.Count-eq$script:CargoSciencePacks.Count) "$Name science pack count differs";foreach($pack in $script:CargoSciencePacks){Require-CargoCapTen ($map.Contains($pack)) "$Name science pack differs: $pack"}}
    foreach($pack in $script:CargoSciencePacks){Require-CargoCapTen ($issued[$pack]-ge0-and$remaining[$pack]-ge0-and$debit[$pack]-ge0) "$Name science quantity differs: $pack";Require-CargoCapTen ($issued[$pack]+1e-7-ge$remaining[$pack]) "$Name science debit differs: $pack";Assert-CargoCapTenNear $debit[$pack] ($issued[$pack]-$remaining[$pack]) "$Name science accounting $pack"}
    return [ordered]@{issued=$issued;remaining=$remaining;debit=$debit}
}
function Assert-CargoCapTenScienceEqual {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Actual,[Parameter(Mandatory)][System.Collections.IDictionary]$Expected,[Parameter(Mandatory)][string]$Name)
    foreach($field in @('issued','remaining','debit')){foreach($pack in $script:CargoSciencePacks){Assert-CargoCapTenNear $Actual[$field][$pack] $Expected[$field][$pack] "$Name science $field $pack"}}
}
function Assert-CargoCapTenForceBonuses {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Marker,[Parameter(Mandatory)][double]$ExpectedWorkerBonus,[Parameter(Mandatory)][string]$Name)
    Require-CargoCapTen ($Marker.Contains('force_bonuses')-and$Marker.Contains('expected_worker_bonus')) "$Name worker bonus marker is absent"
    $bonuses=Get-CargoCapTenNumericMap $Marker['force_bonuses'] "$Name force bonuses";Require-CargoCapTen ($bonuses.Count-gt0) "$Name force bonuses are absent"
    foreach($index in $bonuses.Keys){Require-CargoCapTen ($index-match'^[1-9][0-9]*$') "$Name force index differs"}
    Require-CargoCapTen ($bonuses.Contains($script:CargoPlayerForceIndex)) "$Name player force is absent"
    Assert-CargoCapTenNear $Marker['expected_worker_bonus'] $ExpectedWorkerBonus "$Name expected worker bonus";Assert-CargoCapTenNear $bonuses[$script:CargoPlayerForceIndex] $ExpectedWorkerBonus "$Name player worker bonus";return $bonuses
}
function Assert-CargoCapTenOnlyWorkerBonusAdvance {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Before,[Parameter(Mandatory)][System.Collections.IDictionary]$After,[Parameter(Mandatory)][double]$ExpectedWorkerBonus,[Parameter(Mandatory)][double]$ExpectedDelta,[Parameter(Mandatory)][string]$PlayerForceIndex,[Parameter(Mandatory)][string]$Name)
    Require-CargoCapTen ($Before.Count-eq$After.Count) "$Name force membership differs"
    Require-CargoCapTen ($Before.Contains($PlayerForceIndex)) "$Name player force is absent"
    foreach($index in $Before.Keys){
        Require-CargoCapTen ($After.Contains($index)) "$Name force membership differs"
        if($index-ceq$PlayerForceIndex){
            Assert-CargoCapTenNear ($After[$index]-$Before[$index]) $ExpectedDelta "$Name player worker bonus increment"
            Assert-CargoCapTenNear $After[$index] $ExpectedWorkerBonus "$Name player worker bonus endpoint"
        }else{
            Assert-CargoCapTenNear $After[$index] $Before[$index] "$Name foreign force bonus"
        }
    }
}
function Assert-CargoCapTenMarkerCommon {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Marker,[Parameter(Mandatory)][string]$Phase)
    foreach($field in @('phase','worker','level','current','progress','queue','ordinary','settings_file_values','laboratory_productivity_bonus','technology_price_multiplier','unit_count','unit_time')){Require-CargoCapTen ($Marker.Contains($field)) "marker field is absent: $field"}
    Assert-CargoCapTenEqual $Marker['phase'] $Phase 'marker phase';Assert-CargoCapTenEqual $Marker['settings_file_values'] 'true' 'marker File settings';$tick=Assert-CargoCapTenNumber $Marker['tick'] 'marker tick';Require-CargoCapTen ($tick-ge0-and[math]::Floor($tick)-eq$tick) 'marker tick differs'
    $level=Assert-CargoCapTenNumber $Marker['level'] 'marker level';Require-CargoCapTen ($level-ge1-and[math]::Floor($level)-eq$level) 'marker level differs';Assert-CargoCapTenNumber $Marker['progress'] 'marker progress'|Out-Null
    Assert-CargoCapTenNear $Marker['laboratory_productivity_bonus'] 0 'marker laboratory productivity';Assert-CargoCapTenNear $Marker['technology_price_multiplier'] 1 'marker technology price';$count=Assert-CargoCapTenNumber $Marker['unit_count'] 'marker unit count';Require-CargoCapTen ($count-gt0-and[math]::Floor($count)-eq$count) 'marker unit count differs';Assert-CargoCapTenNear $Marker['unit_time'] 3600 'marker unit time'
}
function Assert-CargoCapTenMarkerOrder { param([Parameter(Mandatory)][System.Collections.IDictionary]$Earlier,[Parameter(Mandatory)][System.Collections.IDictionary]$Later) if((Assert-CargoCapTenNumber $Later['tick'] 'later marker tick')-le(Assert-CargoCapTenNumber $Earlier['tick'] 'earlier marker tick')){throw 'local marker tick order differs'} }

function Test-CargoCapTenSaveZip {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Name save is missing"};$python=Get-Command python3 -ErrorAction SilentlyContinue;if($null-eq$python){$python=Get-Command python -ErrorAction SilentlyContinue};if($null-eq$python){throw "$Name save CRC reader is unavailable"}
    $program='import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; assert any(e.filename.endswith(("level.dat","level.dat0")) for e in z.infolist())';$output=@(& $python.Source -I -c $program $Path 2>&1);if($LASTEXITCODE-ne0){throw "$Name save CRC or level data differs: $($output -join ' ')"}
}
function Test-CargoCapTenCompleteSave { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name) if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $false};try{Test-CargoCapTenSaveZip $Path $Name;return $true}catch{return $false} }
function Assert-CargoCapTenEarnedRun { param([Parameter(Mandatory)]$Run,[Parameter(Mandatory)][string]$Name) Assert-CargoCapTenEqual $Run.passed $true "$Name passed";Assert-CargoCapTenEqual $Run.timed_out $false "$Name timeout";Assert-CargoCapTenEqual $Run.completion_predicate_observed $true "$Name completion predicate";if($Run.exit_code-ne0-and$Run.exit_code-ne137){throw "$Name exit code differs"} }
function Assert-CargoCapTenColdRun { param([Parameter(Mandatory)]$Run,[Parameter(Mandatory)][string]$Name) Assert-CargoCapTenEqual $Run.passed $true "$Name passed";Assert-CargoCapTenEqual $Run.timed_out $false "$Name timeout";Assert-CargoCapTenEqual $Run.exit_code 0 "$Name natural exit" }

function Read-CargoCapTenCompleteChain {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Chain,[System.Collections.IDictionary]$ExpectedSettings,[System.Collections.IDictionary]$ExpectedConstruction,[string]$SourceMirVersion='4.7.20002',[string]$CandidateMirVersion='5.0.20018')
    if($null-eq$ExpectedSettings){$ExpectedSettings=$script:CargoExpectedSettings}
    Require-CargoCapTen ($ExpectedSettings.Count-eq$script:CargoExpectedSettings.Count) 'settings data marker expectation differs'
    foreach($setting in $script:CargoExpectedSettings.Keys){Require-CargoCapTen ($ExpectedSettings.Contains($setting)) 'settings data marker expectation differs';Assert-CargoCapTenEqual $ExpectedSettings[$setting] $script:CargoExpectedSettings[$setting] 'settings data marker expectation'}
    if($null-eq$ExpectedConstruction){$ExpectedConstruction=$script:CargoExpectedConstruction}
    Require-CargoCapTen ($ExpectedConstruction.Count-eq$script:CargoExpectedConstruction.Count) 'construction data marker expectation differs'
    foreach($field in $script:CargoExpectedConstruction.Keys){Require-CargoCapTen ($ExpectedConstruction.Contains($field)) 'construction data marker expectation differs';Assert-CargoCapTenEqual $ExpectedConstruction[$field] $script:CargoExpectedConstruction[$field] 'construction data marker expectation'}
    foreach($name in @('source','candidate','cold1','cold2')){Require-CargoCapTen ($Chain.Contains($name)-and$Chain[$name]-is[Collections.IDictionary]) "chain lacks $name"}
    $source=$Chain['source'];$candidate=$Chain['candidate'];$cold1=$Chain['cold1'];$cold2=$Chain['cold2']
    Assert-CargoCapTenEarnedRun $source['run'] 'source';Assert-CargoCapTenActiveModsMarker (Get-CargoCapTenActiveModsMarker $source['log']) $SourceMirVersion 'source';Assert-CargoCapTenSettingsMarker (Get-CargoCapTenSettingsMarker $source['log']) $ExpectedSettings 'source';Assert-CargoCapTenConstructionMarker (Get-CargoCapTenConstructionMarker $source['log']) $ExpectedConstruction 'source';$sourceMarkers=Get-CargoCapTenMarkers $source['log'];$sourceBegin=Get-CargoCapTenOneMarker $sourceMarkers 'source-begin';$sourcePartial=Get-CargoCapTenOneMarker $sourceMarkers 'source-partial';Assert-CargoCapTenMarkerCommon $sourceBegin 'source-begin';Assert-CargoCapTenMarkerCommon $sourcePartial 'source-partial';Assert-CargoCapTenMarkerOrder $sourceBegin $sourcePartial
    $sourceBaseline=Assert-CargoCapTenNumber $sourceBegin['expected_worker_bonus'] 'source begin expected worker bonus';$sourceBeginBonuses=Assert-CargoCapTenForceBonuses $sourceBegin $sourceBaseline 'source begin';$sourceExpectedWorkerBonus=$sourceBaseline+5
    Assert-CargoCapTenEqual $sourcePartial['worker'] $script:CargoSourceWorker 'source partial worker';Assert-CargoCapTenEqual $sourcePartial['level'] '9' 'source partial level';Assert-CargoCapTenEqual $sourcePartial['ordinary'] '5' 'source ordinary completion count';Assert-CargoCapTenEqual $sourcePartial['current'] $script:CargoSourceWorker 'source partial current';Assert-CargoCapTenEqual $sourcePartial['queue'] "$($script:CargoSourceWorker),$($script:CargoSourceWorker),$($script:CargoTail)" 'source partial queue';Assert-CargoCapTenEqual $sourcePartial['source_role'] "$($script:CargoSourceWorker):9:false:true:false" 'source retained role';$sourceProgress=Assert-CargoCapTenNumber $sourcePartial['progress'] 'source partial progress';Require-CargoCapTen ($sourceProgress-gt0-and$sourceProgress-lt1) 'source partial is not earned work';$sourceBonuses=Assert-CargoCapTenForceBonuses $sourcePartial $sourceExpectedWorkerBonus 'source partial';Assert-CargoCapTenOnlyWorkerBonusAdvance $sourceBeginBonuses $sourceBonuses $sourceExpectedWorkerBonus 5 $script:CargoPlayerForceIndex 'source';$sourceScience=Get-CargoCapTenScience $sourcePartial 'source partial';foreach($pack in $script:CargoSciencePacks){Require-CargoCapTen ($sourceScience.debit[$pack]-gt0) "source partial science debit differs: $pack"}
    Test-CargoCapTenSaveZip $source['protected_save'] 'source';$sourceBefore=$source['protected_initial'];Assert-CargoCapTenFingerprint $sourceBefore $source['protected_save'] 'protected source'|Out-Null;Assert-CargoCapTenInitialCopyRecord $sourceBefore $candidate['initial_working_copy'] $candidate['working_input'] 'candidate';Assert-CargoCapTenFingerprint $candidate['mutable_working_input'] $candidate['working_input'] 'candidate mutable working input'|Out-Null
    Assert-CargoCapTenEarnedRun $candidate['run'] 'candidate';Assert-CargoCapTenActiveModsMarker (Get-CargoCapTenActiveModsMarker $candidate['log']) $CandidateMirVersion 'candidate';Assert-CargoCapTenSettingsMarker (Get-CargoCapTenSettingsMarker $candidate['log']) $ExpectedSettings 'candidate';Assert-CargoCapTenConstructionMarker (Get-CargoCapTenConstructionMarker $candidate['log']) $ExpectedConstruction 'candidate';$candidateMarkers=Get-CargoCapTenMarkers $candidate['log'];$pre=Get-CargoCapTenOneMarker $candidateMarkers 'candidate-pre-work';$closed=Get-CargoCapTenOneMarker $candidateMarkers 'candidate-closed';Assert-CargoCapTenMarkerCommon $pre 'candidate-pre-work';Assert-CargoCapTenMarkerCommon $closed 'candidate-closed';Assert-CargoCapTenMarkerOrder $pre $closed
    Assert-CargoCapTenEqual $pre['worker'] $script:CargoPrivateWorker 'candidate pre-work worker';Assert-CargoCapTenEqual $pre['level'] '9' 'candidate pre-work level';Assert-CargoCapTenEqual $pre['current'] $script:CargoPrivateWorker 'candidate pre-work current';Assert-CargoCapTenNear $pre['progress'] $sourceProgress 'candidate pre-work partial';Assert-CargoCapTenEqual $pre['queue'] "$($script:CargoPrivateWorker),$($script:CargoPrivateWorker),$($script:CargoTail)" 'candidate pre-work queue';Assert-CargoCapTenEqual $pre['source_role'] "$($script:CargoSourceWorker):9:false:true:false" 'candidate source role';Assert-CargoCapTenEqual $pre['canonical_role'] "$($script:CargoSourceWorker):5:false:false:false" 'candidate canonical role';Assert-CargoCapTenEqual $pre['private_role'] "$($script:CargoPrivateWorker):9:false:true:false" 'candidate private role';Assert-CargoCapTenEqual $pre['head_role'] "$($script:CargoHeadWorker):5:false:false:false" 'candidate head role';Require-CargoCapTen ($pre.Contains('configuration_startup_settings_changed')-and$pre['configuration_startup_settings_changed']-in@('true','false')) 'candidate configuration observation differs';$preBonuses=Assert-CargoCapTenForceBonuses $pre $sourceExpectedWorkerBonus 'candidate pre-work';Assert-CargoCapTenOnlyWorkerBonusAdvance $sourceBonuses $preBonuses $sourceExpectedWorkerBonus 0 $script:CargoPlayerForceIndex 'candidate transfer';$preScience=Get-CargoCapTenScience $pre 'candidate pre-work';Assert-CargoCapTenScienceEqual $preScience $sourceScience 'candidate pre-work retained'
    $closedExpectedWorkerBonus=$sourceBaseline+7
    Assert-CargoCapTenEqual $closed['worker'] $script:CargoPrivateWorker 'candidate closed worker';Assert-CargoCapTenEqual $closed['level'] '11' 'candidate closed level';Assert-CargoCapTenEqual $closed['candidate_events'] '2' 'candidate event count';Assert-CargoCapTenEqual $closed['cap_attempt'] 'refused' 'candidate cap refusal';Assert-CargoCapTenEqual $closed['current'] $script:CargoTail 'candidate closed current';Assert-CargoCapTenEqual $closed['queue'] $script:CargoTail 'candidate closed queue';Require-CargoCapTen ($closed.Contains('configuration_startup_settings_changed')-and$closed['configuration_startup_settings_changed']-in@('true','false')) 'candidate closed configuration observation differs';$closedBonuses=Assert-CargoCapTenForceBonuses $closed $closedExpectedWorkerBonus 'candidate closed';Assert-CargoCapTenOnlyWorkerBonusAdvance $preBonuses $closedBonuses $closedExpectedWorkerBonus 2 $script:CargoPlayerForceIndex 'candidate';$closedScience=Get-CargoCapTenScience $closed 'candidate closed';foreach($pack in $script:CargoSciencePacks){Require-CargoCapTen ($closedScience.debit[$pack]-gt$sourceScience.debit[$pack]) "candidate closed science debit differs: $pack"}
    Assert-CargoCapTenFingerprint $sourceBefore $source['protected_save'] 'protected source'|Out-Null;Test-CargoCapTenSaveZip $candidate['protected_save'] 'candidate';$candidateBefore=$candidate['protected_initial'];Assert-CargoCapTenFingerprint $candidateBefore $candidate['protected_save'] 'protected candidate'|Out-Null
    foreach($cold in @($cold1,$cold2)){
        $coldName=[string]$cold['name'];Assert-CargoCapTenInitialCopyRecord $candidateBefore $cold['initial_working_copy'] $cold['working_input'] $coldName;Assert-CargoCapTenFingerprint $cold['mutable_working_input'] $cold['working_input'] "$coldName mutable working input"|Out-Null;Assert-CargoCapTenColdRun $cold['run'] $coldName;Assert-CargoCapTenActiveModsMarker (Get-CargoCapTenActiveModsMarker $cold['log']) $CandidateMirVersion $coldName;Assert-CargoCapTenSettingsMarker (Get-CargoCapTenSettingsMarker $cold['log']) $ExpectedSettings $coldName;Assert-CargoCapTenConstructionMarker (Get-CargoCapTenConstructionMarker $cold['log']) $ExpectedConstruction $coldName;$marker=Get-CargoCapTenOneMarker (Get-CargoCapTenMarkers $cold['log']) 'cold-read';Assert-CargoCapTenMarkerCommon $marker 'cold-read';Assert-CargoCapTenEqual $marker['cold_writes'] '0' 'cold no writes';Assert-CargoCapTenEqual $marker['worker'] $script:CargoPrivateWorker 'cold worker';Assert-CargoCapTenEqual $marker['level'] '11' 'cold level';Assert-CargoCapTenEqual $marker['current'] $script:CargoTail 'cold current';Assert-CargoCapTenEqual $marker['queue'] $script:CargoTail 'cold queue';Require-CargoCapTen ($marker.Contains('configuration_startup_settings_changed')-and$marker['configuration_startup_settings_changed']-in@('true','false')) 'cold configuration observation differs';$coldBonuses=Assert-CargoCapTenForceBonuses $marker $closedExpectedWorkerBonus $coldName;Assert-CargoCapTenOnlyWorkerBonusAdvance $closedBonuses $coldBonuses $closedExpectedWorkerBonus 0 $script:CargoPlayerForceIndex $coldName;$coldScience=Get-CargoCapTenScience $marker $coldName;Assert-CargoCapTenScienceEqual $coldScience $closedScience "$coldName retained";Assert-CargoCapTenFingerprint $candidateBefore $candidate['protected_save'] 'protected candidate'|Out-Null
    }
    [ordered]@{source=Get-CargoCapTenFingerprint $source['protected_save'];candidate=Get-CargoCapTenFingerprint $candidate['protected_save'];cold_working_inputs=@($cold1['working_input'],$cold2['working_input']);native_partial='source actor observed 0 < progress < 1 after five ordinary events';ordinary_events=[ordered]@{source=5;candidate=2;cap_start_refused=$true}}
}

function New-CargoCapTenComposePlan {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Packet)
    [ordered]@{status='COMPOSED_EXECUTOR_PLAN_NOT_ADMITTED';stages=@(
        [ordered]@{name='create-source-seed';arguments=@('--create','<source-seed.zip>');natural_exit_required=$true},
        [ordered]@{name='source-server';console_command=$Packet['protocol']['source_console_command'];requires=@('five ordinary source completion events','source-partial saved state','protected source copy')},
        [ordered]@{name='candidate-server';configuration_callback_begins_work=$true;no_candidate_console_command=$true;requires=@('candidate-pre-work','two ordinary candidate completion events','cap 11 next-start refusal','protected candidate copy')},
        [ordered]@{name='cold-1';arguments=@('--test-save','<distinct candidate copy>','--test-arg','reload')},
        [ordered]@{name='cold-2';arguments=@('--test-save','<distinct candidate copy>','--test-arg','reload')}
    );no_native_claim='Compose validates only packet shape and local bindings. It creates no context, direct-library activation, process, console write, save, or gameplay result.'}
}

function Write-CargoCapTenReceipt { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Record) $parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw "output parent is missing: $parent"};$bytes=[Text.UTF8Encoding]::new($false).GetBytes((($Record|ConvertTo-Json -Depth 100)+"`n"));$stream=$null;try{$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{if($null-ne$stream){$stream.Dispose()}} }

function Invoke-CargoCapTenExecution {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Packet,[Parameter(Mandatory)][string]$RepoRoot)
    . (Join-Path $RepoRoot 'tools/lib/validation/ImmutableInputStaging.ps1');. (Join-Path $RepoRoot 'tools/lib/compatibility/LibraryActivation.ps1');. (Join-Path $RepoRoot 'tools/lib/validation/NativeProbeResources.ps1')
    $runtime=$Packet['runtime_bindings'];$inputs=$Packet['inputs'];$engineBinding=Get-CargoCapTenEngineBinding $inputs['engine'];$bounds=$Packet['bounds'];$context=$null;$execution=[ordered]@{activation=$null};$restoration=[Collections.Generic.List[object]]::new();$primary=$null;$chain=$null
    function Close-CargoCapTenActivation { Complete-CargoCapTenActivation -Execution $execution -Restoration $restoration }
    try {
        $context=New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot ([string]$runtime['output_root']) -ExpectedPeakMemoryMiB ([int]$bounds['expected_peak_memory_mib']) -MaxNewOutputMiB ([int]$bounds['max_new_output_mib']) -UseExactOutputRoot
        [IO.Directory]::CreateDirectory($context.root)|Out-Null
        $engine=[string]$inputs['engine']['binary_path'];$engineData=[string]$inputs['engine']['engine_data_path'];$library=[string]$runtime['library_directory'];$settings=[string]$inputs['settings']['path']
        $sourceDefinition=Assert-CargoCapTenProfile -Path ([string]$runtime['source_profile']) -ExpectedSha ([string]$inputs['source_profile']['sha256']) -MirFilename ([string]$inputs['source_mir']['filename']) -MirSha ([string]$inputs['source_mir']['sha256']) -MirBytes ([int64]$inputs['source_mir']['bytes']) -EngineBinding $engineBinding
        $candidateDefinition=Assert-CargoCapTenProfile -Path ([string]$runtime['candidate_profile']) -ExpectedSha ([string]$inputs['candidate_profile']['sha256']) -MirFilename ([string]$inputs['candidate_mir']['filename']) -MirSha ([string]$inputs['candidate_mir']['sha256']) -MirBytes ([int64]$inputs['candidate_mir']['bytes']) -EngineBinding $engineBinding
        $sourceRoot=Join-Path $context.root 'source';$candidateRoot=Join-Path $context.root 'candidate';[IO.Directory]::CreateDirectory($sourceRoot)|Out-Null;[IO.Directory]::CreateDirectory($candidateRoot)|Out-Null
        function Open-CargoCapTenActivation([string]$Profile,[hashtable]$Archives){$execution['activation']=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $engineData -ProfilePath $Profile -ArchiveHashes $Archives -SettingsMode File -SettingsPath $settings -SettingsSha256 ([string]$inputs['settings']['sha256']);Add-MIRNativeProbeLibraryActivation -Context $context -Activation $execution['activation']}
        $sourceRuntimeProfile=Join-Path $sourceRoot 'profile.json';$sourceArchives=New-CargoCapTenRuntimeProfile -Profile $sourceDefinition -MirFilename ([string]$inputs['source_mir']['filename']) -MirVersion '4.7.20002' -MirSha ([string]$inputs['source_mir']['sha256']) -Path $sourceRuntimeProfile
        Open-CargoCapTenActivation $sourceRuntimeProfile $sourceArchives
        $sourceWrite=Join-Path $sourceRoot 'write-data';$sourceSaves=Join-Path $sourceWrite 'saves';[IO.Directory]::CreateDirectory($sourceSaves)|Out-Null;$sourceConfig=Join-Path $sourceRoot 'config.ini';New-CargoCapTenConfig $sourceConfig $engineData $sourceWrite
        $seed=Join-Path $sourceRoot 'seed.zip';$createArgs=(New-CargoCapTenEngineArguments $sourceConfig $library $engineBinding)+@('--create',$seed);Assert-MIRLibraryLaunch -Activation $execution['activation'] -FactorioBin $engine -Arguments $createArgs;$create=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $engine -Arguments $createArgs -TimeoutSeconds ([int]$bounds['create_timeout_seconds']);Assert-CargoCapTenEqual $create.result.exit_code 0 'source create exit'
        $sourceWorking=Join-Path $sourceRoot 'source-working.zip';[IO.File]::Copy($seed,$sourceWorking,$false);New-CargoCapTenInitialCopyRecord $seed $sourceWorking 'source'|Out-Null
        $sourceServerSettings=Join-Path $sourceRoot 'server-settings.json';New-CargoCapTenServerSettings ([string]$runtime['server_settings_template']) $sourceServerSettings;$sourceSave=Join-Path $sourceSaves 'mir5-se-worker-storage-cap10-source.zip';$sourceLog=Join-Path $sourceWrite 'factorio-current.log';$sourcePredicate={(Test-CargoCapTenCompleteSave $sourceSave 'source')-and(Test-Path -LiteralPath $sourceLog -PathType Leaf)-and([IO.File]::ReadAllText($sourceLog).Contains('phase=source-partial'))}.GetNewClosure();$sourceArgs=(New-CargoCapTenEngineArguments $sourceConfig $library $engineBinding)+@('--start-server',$sourceWorking,'--server-settings',$sourceServerSettings,'--bind','127.0.0.1','--port',[string]$runtime['server_port']);Assert-MIRLibraryLaunch -Activation $execution['activation'] -FactorioBin $engine -Arguments $sourceArgs;$sourceRun=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $engine -Arguments $sourceArgs -TimeoutSeconds ([int]$bounds['server_timeout_seconds']) -CompletionPredicate $sourcePredicate -ConsoleStartup ([ordered]@{command=$Packet['protocol']['source_console_command'];ready_marker=$Packet['protocol']['console_ready_marker'];confirmation_marker=$Packet['protocol']['confirmation_marker']});Close-CargoCapTenActivation
        $protectedSource=Join-Path $context.root 'protected-source.zip';[IO.File]::Copy($sourceSave,$protectedSource,$false);$sourceInitial=Get-CargoCapTenFingerprint $protectedSource
        $candidateWorking=Join-Path $candidateRoot 'candidate-working.zip';[IO.File]::Copy($protectedSource,$candidateWorking,$false);$candidateInitialWorking=New-CargoCapTenInitialCopyRecord $protectedSource $candidateWorking 'candidate'
        $candidateRuntimeProfile=Join-Path $candidateRoot 'profile.json';$candidateArchives=New-CargoCapTenRuntimeProfile -Profile $candidateDefinition -MirFilename ([string]$inputs['candidate_mir']['filename']) -MirVersion '5.0.20018' -MirSha ([string]$inputs['candidate_mir']['sha256']) -Path $candidateRuntimeProfile
        $candidateWrite=Join-Path $candidateRoot 'write-data';$candidateSaves=Join-Path $candidateWrite 'saves';[IO.Directory]::CreateDirectory($candidateSaves)|Out-Null;$candidateConfig=Join-Path $candidateRoot 'config.ini';New-CargoCapTenConfig $candidateConfig $engineData $candidateWrite;$candidateServerSettings=Join-Path $candidateRoot 'server-settings.json';New-CargoCapTenServerSettings ([string]$runtime['server_settings_template']) $candidateServerSettings;$candidateSave=Join-Path $candidateSaves 'mir5-se-worker-storage-cap10-candidate.zip';$candidateLog=Join-Path $candidateWrite 'factorio-current.log';$candidatePredicate={(Test-CargoCapTenCompleteSave $candidateSave 'candidate')-and(Test-Path -LiteralPath $candidateLog -PathType Leaf)-and([IO.File]::ReadAllText($candidateLog).Contains('phase=candidate-closed'))}.GetNewClosure()
        Open-CargoCapTenActivation $candidateRuntimeProfile $candidateArchives;$candidateArgs=(New-CargoCapTenEngineArguments $candidateConfig $library $engineBinding)+@('--start-server',$candidateWorking,'--server-settings',$candidateServerSettings,'--bind','127.0.0.1','--port',[string]$runtime['server_port']);Assert-MIRLibraryLaunch -Activation $execution['activation'] -FactorioBin $engine -Arguments $candidateArgs;$candidateRun=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $engine -Arguments $candidateArgs -TimeoutSeconds ([int]$bounds['server_timeout_seconds']) -CompletionPredicate $candidatePredicate;Close-CargoCapTenActivation
        Assert-CargoCapTenFingerprint $sourceInitial $protectedSource 'protected source'|Out-Null;$protectedCandidate=Join-Path $context.root 'protected-candidate.zip';[IO.File]::Copy($candidateSave,$protectedCandidate,$false);$candidateInitial=Get-CargoCapTenFingerprint $protectedCandidate
        $chain=[ordered]@{source=[ordered]@{run=$sourceRun.result;log=$sourceLog;protected_save=$protectedSource;protected_initial=$sourceInitial};candidate=[ordered]@{run=$candidateRun.result;log=$candidateLog;working_input=$candidateWorking;initial_working_copy=$candidateInitialWorking;mutable_working_input=(Get-CargoCapTenFingerprint $candidateWorking);protected_save=$protectedCandidate;protected_initial=$candidateInitial}}
        for($i=1;$i-le2;$i++){$coldRoot=Join-Path $context.root ("cold-$i");$coldWrite=Join-Path $coldRoot 'write-data';[IO.Directory]::CreateDirectory($coldWrite)|Out-Null;$coldConfig=Join-Path $coldRoot 'config.ini';New-CargoCapTenConfig $coldConfig $engineData $coldWrite;$coldWorking=Join-Path $coldRoot 'cold-input.zip';[IO.File]::Copy($protectedCandidate,$coldWorking,$false);$coldInitialWorking=New-CargoCapTenInitialCopyRecord $protectedCandidate $coldWorking "cold-$i";Open-CargoCapTenActivation $candidateRuntimeProfile $candidateArchives;$coldArgs=(New-CargoCapTenEngineArguments $coldConfig $library $engineBinding)+@('--test-save',$coldWorking,'--test-arg','reload','--test-ticks',[string]$bounds['cold_test_ticks']);Assert-MIRLibraryLaunch -Activation $execution['activation'] -FactorioBin $engine -Arguments $coldArgs;$coldRun=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $engine -Arguments $coldArgs -TimeoutSeconds ([int]$bounds['cold_timeout_seconds']);Close-CargoCapTenActivation;$chain["cold$i"]=[ordered]@{name="cold-$i";run=$coldRun.result;working_input=$coldWorking;initial_working_copy=$coldInitialWorking;mutable_working_input=(Get-CargoCapTenFingerprint $coldWorking);log=(Join-Path $coldWrite 'factorio-current.log')}}
        $verified=Read-CargoCapTenCompleteChain $chain -ExpectedSettings $inputs['settings']['expected_data_stage_values'] -ExpectedConstruction $inputs['fixture']['expected_data_stage_construction']
    } catch {$primary=$_} finally {
        if($null-ne$execution['activation']-and-not$execution['activation'].closed){try{Complete-CargoCapTenActivation -Execution $execution -Restoration $restoration}catch{if($null-eq$primary){$primary=$_}else{$primary.Exception.Data['cargo_cap_ten_restoration_error']=$_.Exception.Message}}}
    }
    if($null-ne$primary){
        if($null-ne$context){$failure=[ordered]@{schema=1;kind='MIRWorkerStorageSECargoCapTenF200NativeExecutionResultV1';status='failed-retained-adverse';primary_cause=[ordered]@{message=$primary.Exception.Message;type=$primary.Exception.GetType().FullName};resource_runs=@($context.runs);restoration=@($restoration);native_completion_count=0};try{Write-MIRNativeProbeResult -Context $context -Record $failure}catch{$primary.Exception.Data['cargo_cap_ten_failure_result_error']=$_.Exception.Message}}
        throw $primary
    }
    $record=[ordered]@{schema=1;kind='MIRWorkerStorageSECargoCapTenF200NativeExecutionResultV1';status='completed-await-independent-review';chain=$verified;resource_runs=@($context.runs);restoration=@($restoration);native_completion_count=5;candidate_completion_count=2;cold_count=2}
    Write-MIRNativeProbeResult -Context $context -Record $record;return $record
}

function Invoke-CargoCapTenExecutor {
    param([Parameter(Mandatory)][ValidateSet('Validate','Compose','Execute')][string]$RequestedMode,[Parameter(Mandatory)][string]$RequestedPacketPath,[Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RequestedOutputPath)
    $packet=Read-CargoCapTenJson $RequestedPacketPath
    # Planning may describe absent frozen helpers; execution still requires
    # every exact pinned byte before importing or allocating anything native.
    Assert-CargoCapTenPacket $packet $RepoRoot -DeferLocalHelperObservation:($RequestedMode -ne 'Execute')
    $states=Get-CargoCapTenInputStates $packet $RepoRoot;$missing=@($states|Where-Object {$_.state -match '^missing'})
    $mismatched=@($states|Where-Object {$_.state -ceq 'mismatched_local_input'})
    $record=[ordered]@{schema=1;kind='MIRWorkerStorageSECargoCapTenF200NativeExecutorReceiptV1';mode=$RequestedMode;packet_sha256=(Get-CargoCapTenSha256 $RequestedPacketPath);input_states=$states;deferred_missing_bindings=@($missing|ForEach-Object label);native_processes_started=0;library_activation=$false;resource_context_allocated=$false;execution_plan=(New-CargoCapTenComposePlan $packet);limit='No current result is gameplay evidence.'}
    $record.unavailable_helper_bindings=@($states|Where-Object {$_.label -like 'helper *' -and $_.state -cne 'verified_local_input'}|ForEach-Object label)
    if($RequestedMode-eq'Validate'){$record.status=if($mismatched.Count){'DEFERRED_LOCAL_HELPER_MISMATCH'}elseif($missing.Count){'DEFERRED_MISSING_LOCAL_BINDINGS'}else{'VALIDATED_NOT_ADMITTED'}}
    elseif($RequestedMode-eq'Compose'){$record.status=if($mismatched.Count){'COMPOSED_DEFERRED_LOCAL_HELPER_MISMATCH'}elseif($missing.Count){'COMPOSED_DEFERRED_MISSING_LOCAL_BINDINGS'}else{'COMPOSED_NOT_ADMITTED'}}
    else{$binding=Assert-CargoCapTenHostEngineBinding $packet;if($mismatched.Count){throw 'Execute refuses mismatched local helpers'};if($missing.Count){throw 'Execute refuses missing local bindings'};Assert-CargoCapTenEnginePaths $packet $binding;$record=Invoke-CargoCapTenExecution $packet $RepoRoot}
    Write-CargoCapTenReceipt $RequestedOutputPath $record;[pscustomobject]$record
}

if($MyInvocation.InvocationName-ne'.'){
    if([string]::IsNullOrWhiteSpace($OutputPath)){throw 'OutputPath is required; choose a new explicit custody path.'}
    Invoke-CargoCapTenExecutor -RequestedMode $Mode -RequestedPacketPath $PacketPath -RepoRoot (Find-CargoCapTenRepoRoot $PSScriptRoot) -RequestedOutputPath $OutputPath
}
