[CmdletBinding()]
param(
    [string]$ControllerPath,
    [string]$PacketPath,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if ([string]::IsNullOrWhiteSpace($ControllerPath)) { $ControllerPath = Join-Path $repo 'tools/Invoke-WorkerStorageFiniteFourNative.ps1' }
if ([string]::IsNullOrWhiteSpace($PacketPath)) { $PacketPath = Join-Path $repo 'tests/fixtures/worker-storage-finite-four-native.json' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repo ('build/tmp/worker-storage-finite-four-native-host-controls-'+[guid]::NewGuid().ToString('N')) }

if (-not (Test-Path -LiteralPath $ControllerPath -PathType Leaf)) { throw "controller is missing: $ControllerPath" }
if (-not (Test-Path -LiteralPath $PacketPath -PathType Leaf)) { throw "packet is missing: $PacketPath" }
if (Test-Path -LiteralPath $OutputRoot) { throw "refusing to overwrite control output: $OutputRoot" }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
. $ControllerPath

function Write-ControlJson {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    [IO.File]::WriteAllText($Path,(($Value | ConvertTo-Json -Depth 64)+"`n"),[Text.UTF8Encoding]::new($false))
}

function Assert-Refuses {
    param([Parameter(Mandatory)][scriptblock]$Action,[Parameter(Mandatory)][string]$Contains)
    $refused=$false
    try { & $Action } catch {
        $refused=$true
        if ($_.Exception.Message -notmatch [regex]::Escape($Contains)) {
            throw "refusal had unexpected text '$($_.Exception.Message)', expected '$Contains'"
        }
    }
    if(-not $refused){throw "expected refusal containing '$Contains'"}
}

function Write-CleanScopeProbe {
    param([Parameter(Mandatory)][string]$Path,[ValidateSet('old','new')][string]$Kind)
    if($Kind -eq 'old'){
        $content=@'
param([string]$ControllerPath,[string]$RepoRoot)
$ErrorActionPreference='Stop'
function Import-FiniteFourNativeHelpers {
  param([string]$Root)
  . (Join-Path $Root 'tools/lib/validation/ImmutableInputStaging.ps1')
  . (Join-Path $Root 'tools/lib/compatibility/LibraryActivation.ps1')
  . (Join-Path $Root 'tools/lib/validation/NativeProbeResources.ps1')
}
Import-FiniteFourNativeHelpers -Root $RepoRoot
if(Get-Command New-MIRNativeProbeResourceContext -ErrorAction SilentlyContinue){exit 91}
exit 17
'@
    } else {
        $content=@'
param([string]$ControllerPath,[string]$RepoRoot)
$ErrorActionPreference='Stop'
. $ControllerPath
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($ControllerPath,[ref]$tokens,[ref]$errors)
if($errors.Count-ne0){exit 90}
$execution=@($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-FiniteFourNativeExecution'},$true))
if($execution.Count-ne1){exit 91}
$imports=@($execution[0].Body.EndBlock.Statements|Where-Object {$_.Extent.Text -match '^\s*\.\s*\(Join-Path \$RepoRoot '})
if($imports.Count-ne3){exit 92}
. ([scriptblock]::Create((@($imports|ForEach-Object {$_.Extent.Text}) -join "`n")))
foreach($name in @('Get-MIRImmutableInputFileIdentity','Start-MIRLibraryActivation','New-MIRNativeProbeResourceContext')){
  if(-not(Get-Command $name -ErrorAction SilentlyContinue)){exit 93}
}
exit 0
'@
    }
    [IO.File]::WriteAllText($Path,$content,[Text.UTF8Encoding]::new($false))
}

function Invoke-CleanScopeProbe {
    param([Parameter(Mandatory)][string]$ProbePath,[Parameter(Mandatory)][string]$Controller,[Parameter(Mandatory)][string]$RepoRoot)
    $pwsh=Get-Command pwsh -ErrorAction Stop
    $output=@(& $pwsh.Source -NoProfile -NonInteractive -File $ProbePath $Controller $RepoRoot 2>&1)
    [ordered]@{exit_code=$LASTEXITCODE;output=@($output|ForEach-Object {[string]$_})}
}

function New-SyntheticMarker {
    param([Parameter(Mandatory)][string]$Stage,[ValidateSet('source','successor')][string]$Role,[Parameter(Mandatory)][int]$Tick)
    $completed=if($Role -eq 'source' -or $Stage -in @('configuration','before-successor-lab')){1}else{2}
    $mir=if($Role -eq 'source'){'4.7.21003'}else{'5.0.21018'}
    [ordered]@{
        stage=$Stage;engine='2.1.24';tick=$Tick
        mods=[ordered]@{base='2.1.24';'mir-worker-storage-finite-fixture'='0.1.0';'mir-worker-storage-native-observer'='0.1.2';'more-infinite-research'=$mir}
        next_level=5+$completed;completed=$completed;worker_bonus=5+(2*$completed)
        finite_researched=$true;finite_maximum=4;finite_effect=2;research_progress=.42
        current='worker-robots-storage-5';queue=@('worker-robots-storage-5','mir-worker-test-unrelated')
        foreign_progress=.27;native_lab_completions=$completed
    }
}

function New-SyntheticSave {
    param([Parameter(Mandatory)][string]$Path,[string]$Payload='native-state')
    $zip=$null;$writer=$null
    try {
        $zip=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create)
        $entry=$zip.CreateEntry('level.dat')
        $writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false))
        $writer.Write($Payload)
    } finally {
        if($null-ne$writer){$writer.Dispose()}
        if($null-ne$zip){$zip.Dispose()}
    }
}

function New-SyntheticCompleteChain {
    param([Parameter(Mandatory)][string]$Root)
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    $markers=Join-Path $Root 'markers';[IO.Directory]::CreateDirectory($markers)|Out-Null
    $sourceSave=Join-Path $Root 'protected-source.zip';New-SyntheticSave $sourceSave 'source-earned'
    $successorSave=Join-Path $Root 'protected-successor.zip';New-SyntheticSave $successorSave 'successor-earned'
    $successorWorking=Join-Path $Root 'successor-working.zip';[IO.File]::Copy($sourceSave,$successorWorking,$false)
    $cold1Working=Join-Path $Root 'cold-1-working.zip';[IO.File]::Copy($successorSave,$cold1Working,$false)
    $cold2Working=Join-Path $Root 'cold-2-working.zip';[IO.File]::Copy($successorSave,$cold2Working,$false)
    foreach($row in @(
        @('source-earned','source',101),@('source-finished','source',105),@('configuration','successor',101),@('before-successor-lab','successor',102),
        @('successor-earned','successor',103),@('successor-finished','successor',107),@('reload-1','successor',104),@('reload-2','successor',104)
    )){Write-ControlJson -Path (Join-Path $markers ($row[0]+'.json')) -Value (New-SyntheticMarker -Stage $(if($row[0]-eq'reload-1'-or$row[0]-eq'reload-2'){'reload'}else{$row[0]}) -Role $row[1] -Tick $row[2])}
    $sourceLog=Join-Path $Root 'source.log';[IO.File]::WriteAllText($sourceLog,"MIR_WORKER_NATIVE source`nSaving finished`n",[Text.UTF8Encoding]::new($false))
    $successorLog=Join-Path $Root 'successor.log';[IO.File]::WriteAllText($successorLog,"MIR_WORKER_NATIVE successor`nSaving finished`n",[Text.UTF8Encoding]::new($false))
    $cold1Stdout=Join-Path $Root 'cold-1.stdout';[IO.File]::WriteAllText($cold1Stdout,"Test passed`n",[Text.UTF8Encoding]::new($false))
    $cold2Stdout=Join-Path $Root 'cold-2.stdout';[IO.File]::WriteAllText($cold2Stdout,"Test passed`n",[Text.UTF8Encoding]::new($false))
    [ordered]@{
        source=[ordered]@{run=[pscustomobject]@{passed=$true;timed_out=$false;completion_predicate_observed=$true;exit_code=137};earned_marker=(Join-Path $markers 'source-earned.json');finished_marker=(Join-Path $markers 'source-finished.json');log=$sourceLog;protected_save=$sourceSave;protected_initial=(Get-FiniteFourNativeFingerprint $sourceSave)}
        successor=[ordered]@{run=[pscustomobject]@{passed=$true;timed_out=$false;completion_predicate_observed=$true;exit_code=0};configuration_marker=(Join-Path $markers 'configuration.json');before_marker=(Join-Path $markers 'before-successor-lab.json');earned_marker=(Join-Path $markers 'successor-earned.json');finished_marker=(Join-Path $markers 'successor-finished.json');log=$successorLog;working_input=$successorWorking;protected_save=$successorSave;protected_initial=(Get-FiniteFourNativeFingerprint $successorSave);acceleration_reapplied=1000}
        cold1=[ordered]@{name='cold-1';run=[pscustomobject]@{passed=$true;timed_out=$false;exit_code=0};working_input=$cold1Working;marker=(Join-Path $markers 'reload-1.json');stdout=$cold1Stdout}
        cold2=[ordered]@{name='cold-2';run=[pscustomobject]@{passed=$true;timed_out=$false;exit_code=0};working_input=$cold2Working;marker=(Join-Path $markers 'reload-2.json');stdout=$cold2Stdout}
    }
}

function Copy-ControlChain {
    param([Parameter(Mandatory)][string]$Name)
    $destination=Join-Path $OutputRoot $Name
    Copy-Item -LiteralPath (Join-Path $OutputRoot 'healthy-chain') -Destination $destination -Recurse
    New-SyntheticCompleteChain -Root $destination
}

function Invoke-ConsoleStartupControl {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Protocol,
        [Parameter(Mandatory)][string]$Root,
        [ValidateSet('observed','wrong','absent','unrelated')][string]$Confirmation
    )
    . (Join-Path (Find-FiniteFourNativeRepoRoot -StartPath $PSScriptRoot) 'tools/lib/validation/ResourceGovernor.ps1')
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    $stdout=Join-Path $Root 'source.stdout.txt'
    [IO.File]::WriteAllText($stdout,($Protocol['console_ready_marker']+"`n"),[Text.UTF8Encoding]::new($false))
    $state=New-MIR441FactorioConsoleStartup -Definition ([ordered]@{
        command=[string]$Protocol['source_console_command']
        ready_marker=[string]$Protocol['console_ready_marker']
        confirmation_marker=[string]$Protocol['confirmation_marker']
    })
    Add-MIR441FactorioConsoleStartupOutput -State $state -Kind stdout -Path $stdout
    $stream=[IO.MemoryStream]::new();$writer=[IO.StreamWriter]::new($stream,[Text.UTF8Encoding]::new($false),1024,$true);$timer=[Diagnostics.Stopwatch]::StartNew()
    try {
        $step={
            if(Update-MIR441FactorioConsoleStartupOutput -State $state){
                if(-not$state.receipt.ready_marker_observed-and$state.ready_marker_seen){
                    $state.receipt.ready_marker_observed=$true
                    $state.receipt.ready_elapsed_monotonic_milliseconds=[Math]::Round([double]$timer.Elapsed.TotalMilliseconds,3)
                    Send-MIR441FactorioConsoleStartupLine -State $state -Writer $writer -Timer $timer -Kind command
                }
                if($state.receipt.send_count-eq1-and$state.confirmation_marker.Length-gt0-and$state.confirmation_marker_seen){
                    $state.receipt.confirmation_marker_observed=$true
                    $state.receipt.confirmation_elapsed_monotonic_milliseconds=[Math]::Round([double]$timer.Elapsed.TotalMilliseconds,3)
                    Send-MIR441FactorioConsoleStartupLine -State $state -Writer $writer -Timer $timer -Kind confirmation-replay
                }
            }
        }
        & $step
        $line=switch($Confirmation){
            'observed' { '2026-11-19 21:06:57 [WARNING] '+$Protocol['confirmation_marker'] }
            'wrong' { '2026-11-19 21:06:57 [WARNING] Using Lua console commands will disable achievements. Please repeat a different command to proceed.' }
            'unrelated' { '2026-11-19 21:06:57 [WARNING] unrelated server warning' }
            'absent' { $null }
        }
        if($null-ne$line){[IO.File]::AppendAllText($stdout,($line+"`n"),[Text.UTF8Encoding]::new($false))}
        & $step
        $writer.Flush()
        return [ordered]@{receipt=$state.receipt;stdin=[Text.UTF8Encoding]::new($false).GetString($stream.ToArray())}
    } finally {
        $timer.Stop();$writer.Dispose();$stream.Dispose()
    }
}

function New-SyntheticInterruptedContext {
    param([Parameter(Mandatory)][string]$Root)
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    $startedLedger=Join-Path $Root 'process-1.resources.jsonl'
    $preAdmissionLedger=Join-Path $Root 'process-2.resources.jsonl'
    $running=[ordered]@{process=[ordered]@{id=4123;phase='running';start_identity=[ordered]@{pid=4123;start_ticks=77;session_id=4123;kind='MIR441LinuxNativeLaunchV1'}}}
    $terminal=[ordered]@{phase='interrupted';error='[mir441-resource-admission-memory]'}
    [IO.File]::WriteAllText($startedLedger,(($running|ConvertTo-Json -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($preAdmissionLedger,(($terminal|ConvertTo-Json -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
    $runs=[Collections.Generic.List[object]]::new()
    $runs.Add([pscustomobject]@{index=1;status='passed';ledger=$startedLedger;stdout=(Join-Path $Root 'process-1.stdout.txt');stderr=(Join-Path $Root 'process-1.stderr.txt')})
    $runs.Add([pscustomobject]@{index=2;status='interrupted';ledger=$preAdmissionLedger;stdout=(Join-Path $Root 'process-2.stdout.txt');stderr=(Join-Path $Root 'process-2.stderr.txt');error='[mir441-resource-admission-memory]'})
    return [pscustomobject]@{root=$Root;process_index=2;runs=$runs}
}

function New-SyntheticExecutionFailureHelperRoot {
    param([Parameter(Mandatory)][string]$Root)
    foreach($path in @(
        (Join-Path $Root 'tools/lib/validation'),
        (Join-Path $Root 'tools/lib/compatibility')
    )) {[IO.Directory]::CreateDirectory($path)|Out-Null}
    [IO.File]::WriteAllText((Join-Path $Root 'tools/lib/validation/ImmutableInputStaging.ps1'),'',[Text.UTF8Encoding]::new($false))
    $library=@'
function Start-MIRLibraryActivation {
  param($LibraryDirectory,$EngineDataDirectory,$ProfilePath,$ArchiveHashes,$SettingsMode)
  $activation=[pscustomobject]@{closed=$false;synthetic=$true}
  $global:FiniteFourFailurePathState.activation=$activation
  $global:FiniteFourFailurePathState.activation_started++
  return $activation
}
function Add-MIRNativeProbeLibraryActivation {param($Context,$Activation)}
function Complete-MIRLibraryActivation {
  param($Activation)
  $Activation.closed=$true
  $global:FiniteFourFailurePathState.cleanup_count++
  return [ordered]@{state='synthetic-restored';library_lock_released=$true}
}
function Assert-MIRLibraryLaunch {param($Activation,$FactorioBin,$Arguments)}
'@
    [IO.File]::WriteAllText((Join-Path $Root 'tools/lib/compatibility/LibraryActivation.ps1'),$library,[Text.UTF8Encoding]::new($false))
    $native=@'
function New-MIRNativeProbeResourceContext {
  param($RepoRoot,$OutputRoot,$ExpectedPeakMemoryMiB,$MaxNewOutputMiB,[switch]$UseExactOutputRoot)
  return [pscustomobject]@{root=$OutputRoot;process_index=0;runs=[Collections.Generic.List[object]]::new()}
}
function Get-MIRNativeAudioArguments {param([switch]$Headless);if(-not$Headless){throw 'synthetic headless capability differs'};return @()}
function Invoke-MIRNativeProbeFactorioProcess {
  param($Context,$FilePath,$Arguments,$TimeoutSeconds,$CompletionPredicate,$ConsoleStartup)
  $Context.process_index++
  $Context.runs.Add([pscustomobject]@{index=$Context.process_index;status='interrupted';ledger=(Join-Path $Context.root ('process-'+$Context.process_index+'.resources.jsonl'));error='[mir441-process-timeout]'})
  $global:FiniteFourFailurePathState.native_call_count++
  $failure=[TimeoutException]::new('[mir441-process-timeout]')
  $failure.Data['mir441_factorio_console_startup']=[ordered]@{send_count=1;ready_marker_observed=$true;confirmation_marker_observed=$false}
  throw $failure
}
function Write-MIRNativeProbeResult {
  param($Context,$Record)
  if($global:FiniteFourFailurePathState.cleanup_count-ne1-or$null-eq$global:FiniteFourFailurePathState.activation-or-not$global:FiniteFourFailurePathState.activation.closed){throw 'synthetic result write preceded cleanup'}
  $global:FiniteFourFailurePathState.result_write_count++
  $global:FiniteFourFailurePathState.result=$Record
}
'@
    [IO.File]::WriteAllText((Join-Path $Root 'tools/lib/validation/NativeProbeResources.ps1'),$native,[Text.UTF8Encoding]::new($false))
}

$checks=[Collections.Generic.List[object]]::new()
function Add-Check { param([string]$Name,[scriptblock]$Action) & $Action;$checks.Add([ordered]@{name=$Name;passed=$true}) }

Add-Check 'Validate requires an explicit receipt path and defers missing runtime bindings without an execution boundary' {
    $pwsh=Get-Command pwsh -ErrorAction Stop
    $missingOutput=@(& $pwsh.Source -NoProfile -NonInteractive -File $ControllerPath -Mode Validate 2>&1)
    if($LASTEXITCODE-eq0-or($missingOutput-join "`n")-notmatch'OutputPath is required'){throw 'Validate accepted an implicit sidecar receipt path'}
    $receiptPath=Join-Path $OutputRoot 'validate.json'
    $output=@(& $pwsh.Source -NoProfile -NonInteractive -File $ControllerPath -Mode Validate -OutputPath $receiptPath 2>&1)
    if($LASTEXITCODE-ne0){throw "Validate command failed: $($output -join ' ' )"}
    $receipt=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
    if($receipt.native_processes_started-ne0-or$receipt.library_activation-or$receipt.resource_context_allocated){throw 'Validate crossed an execution boundary'}
    $packet=Read-FiniteFourNativeJson $PacketPath
    $helpers=@($receipt.input_states | Where-Object {$_.label -like 'helper *'})
    if($helpers.Count -ne $packet.helper_pins.Count){throw 'Validate did not report all frozen helper identities'}
    $hasMismatch=$false
    foreach($pin in $packet.helper_pins){
        $label="helper $([IO.Path]::GetFileName($pin.path))"
        $reported=@($helpers | Where-Object label -CEQ $label)
        if($reported.Count-ne1-or$reported[0].sha256-cne$pin.sha256-or$reported[0].bytes-ne$pin.bytes){throw "Frozen helper identity in Validate differs for $label"}
        $actual=Get-Item -LiteralPath (Join-Path $repo $pin.path)
        $hash=(Get-FileHash -LiteralPath $actual.FullName -Algorithm SHA256).Hash
        if($actual.Length-eq$pin.bytes-and$hash-ceq$pin.sha256){
            if($reported[0].state-cne'verified_local_input'){throw "Matching helper was not verified for $label"}
        }else{
            $hasMismatch=$true
            if($reported[0].state-cne'mismatched_local_input'-or$reported[0].observed_sha256-cne$hash-or$reported[0].observed_bytes-ne$actual.Length){throw "Observed helper mismatch differs for $label"}
        }
    }
    $expectedStatus=if($hasMismatch){'DEFERRED_LOCAL_HELPER_MISMATCH'}else{'DEFERRED_MISSING_LOCAL_BINDINGS'}
    if($receipt.status-cne$expectedStatus){throw 'Validate did not defer for the observed reason'}
}

Add-Check 'Compose reports the five bounded stages and remains non-activating' {
    $receipt=Invoke-FiniteFourNativeExecutor -RequestedMode Compose -RequestedPacketPath $PacketPath -RepoRoot (Find-FiniteFourNativeRepoRoot -StartPath $PSScriptRoot) -RequestedOutputPath (Join-Path $OutputRoot 'compose.json')
    if($receipt.status -cnotin @('COMPOSED_DEFERRED_MISSING_LOCAL_BINDINGS','COMPOSED_DEFERRED_LOCAL_HELPER_MISMATCH') -or$receipt.execution_plan.stages.Count-ne5-or$receipt.library_activation-or$receipt.resource_context_allocated){throw 'Compose crossed an execution boundary or changed the five-stage contract'}
    if($receipt.execution_plan.stages[2].acceleration_reapplied-ne1000-or-not$receipt.execution_plan.stages[2].configuration_precedes_console_request-or$receipt.execution_plan.protocol_difference_from_r02-notmatch'ConsoleStartup'){throw 'Compose lost the bounded ConsoleStartup protocol'}
}

Add-Check 'local helper observations retain exact expected and observed identity while strict file admission still refuses' {
    $path=Join-Path $OutputRoot 'helper-identity.txt'
    [IO.File]::WriteAllText($path,'ABCD',[Text.UTF8Encoding]::new($false))
    $descriptor=[ordered]@{path=$path;bytes=4;sha256='E12E115ACF4552B2568B55E93CBD39394C4EF81C82447FAFC997882A02D23677'}
    $matching=Test-FiniteFourNativeFile -Descriptor $descriptor -Label 'helper control' -ObserveMismatch
    if($matching.state -cne 'verified_local_input'){throw 'matching frozen helper did not verify'}
    [IO.File]::WriteAllText($path,'WXYZ',[Text.UTF8Encoding]::new($false))
    $changed=Test-FiniteFourNativeFile -Descriptor $descriptor -Label 'helper control' -ObserveMismatch
    if($changed.state -cne 'mismatched_local_input' -or $changed.sha256 -cne $descriptor.sha256 -or $changed.observed_sha256 -cne '21E32F5321CAD49AB4CF78BA5ED231E0F36D0C78D34108FDA1BE939F33FBA149' -or $changed.observed_bytes -ne 4){throw 'same-size helper drift was hidden or adopted'}
    Assert-Refuses {Test-FiniteFourNativeFile -Descriptor $descriptor -Label 'helper control'} 'helper control SHA-256 differs'
    [IO.File]::WriteAllText($path,'ABCDE',[Text.UTF8Encoding]::new($false))
    $changed=Test-FiniteFourNativeFile -Descriptor $descriptor -Label 'helper control' -ObserveMismatch
    if($changed.state -cne 'mismatched_local_input' -or $changed.bytes -ne 4 -or $changed.observed_bytes -ne 5){throw 'helper byte drift was hidden or adopted'}
    Assert-Refuses {Test-FiniteFourNativeFile -Descriptor $descriptor -Label 'helper control'} 'helper control bytes differ'
}

Add-Check 'nonexecuting helper observation cannot authorize changed canonical packet pins' {
    $packet=Read-FiniteFourNativeJson $PacketPath
    $packet.helper_pins[2].sha256='A'*64
    Assert-Refuses {Assert-FiniteFourNativePacket -Packet $packet -RepoRoot $repo -DeferLocalHelperObservation} 'helper SHA-256'
}

Add-Check 'Execute refuses unavailable exact helpers or runtime inputs before its execution function' {
    $prior=(Get-Command Invoke-FiniteFourNativeExecution -CommandType Function).ScriptBlock
    $script:finiteFourUnexpectedExecution=$false
    try{
        Set-Item -Path Function:Invoke-FiniteFourNativeExecution -Value {param($Packet,$RepoRoot) $script:finiteFourUnexpectedExecution=$true;throw 'unexpected execution boundary'}
        $errorText=''
        try{Invoke-FiniteFourNativeExecutor -RequestedMode Execute -RequestedPacketPath $PacketPath -RepoRoot $repo -RequestedOutputPath (Join-Path $OutputRoot 'must-not-execute.json')|Out-Null}catch{$errorText=$_.Exception.Message}
        if($script:finiteFourUnexpectedExecution -or $errorText -notmatch 'helper .+ (bytes differ|SHA-256 differs)|Execute refuses missing local bindings' -or (Test-Path -LiteralPath (Join-Path $OutputRoot 'must-not-execute.json'))){throw "unavailable inputs crossed execution: $errorText"}
    }finally{Set-Item -Path Function:Invoke-FiniteFourNativeExecution -Value $prior}
}

Add-Check 'clean PowerShell reproduces the retained r01 scope adverse and proves public Execution imports helpers in the caller scope' {
    $repo=Find-FiniteFourNativeRepoRoot -StartPath $PSScriptRoot
    $oldProbe=Join-Path $OutputRoot 'clean-r01-scope-adverse-probe.ps1';$newProbe=Join-Path $OutputRoot 'clean-public-execution-scope-probe.ps1'
    Write-CleanScopeProbe -Path $oldProbe -Kind old;Write-CleanScopeProbe -Path $newProbe -Kind new
    $old=Invoke-CleanScopeProbe -ProbePath $oldProbe -Controller $ControllerPath -RepoRoot $repo
    if($old.exit_code-ne17){throw "retained r01 scope adverse was not reproduced: exit $($old.exit_code) $($old.output -join ' ')"}
    $new=Invoke-CleanScopeProbe -ProbePath $newProbe -Controller $ControllerPath -RepoRoot $repo
    if($new.exit_code-ne0){throw "public Execution import AST failed in clean PowerShell: exit $($new.exit_code) $($new.output -join ' ')"}
}

Add-Check 'headless create, server, and cold argument construction omits the GUI-only audio switch' {
    . (Join-Path (Find-FiniteFourNativeRepoRoot -StartPath $PSScriptRoot) 'tools/lib/validation/NativeProbeCommon.ps1')
    $headlessRoot=Join-Path $OutputRoot 'headless-arguments'
    $base=New-FiniteFourNativeEngineArguments -ConfigPath (Join-Path $headlessRoot 'factorio.cfg') -LibraryDirectory (Join-Path $headlessRoot 'mods')
    $argumentSets=@(
        [pscustomobject]@{value=@($base+@('--create',(Join-Path $headlessRoot 'seed.zip')))},
        [pscustomobject]@{value=@($base+@('--start-server',(Join-Path $headlessRoot 'source.zip')))},
        [pscustomobject]@{value=@($base+@('--test-save',(Join-Path $headlessRoot 'cold.zip'),'--test-arg','reload'))}
    )
    foreach($set in $argumentSets){
        $arguments=@($set.value)
        if($arguments-notcontains'--config'-or$arguments-notcontains'--mod-directory'-or$arguments-contains'--disable-audio'){throw 'headless Factorio argument shape differs'}
    }
}

Add-Check 'the observed 2.1.24 console confirmation replays the identical source command once after its first send' {
    . (Join-Path (Find-FiniteFourNativeRepoRoot -StartPath $PSScriptRoot) 'tools/lib/validation/ResourceGovernor.ps1')
    $packet=Read-FiniteFourNativeJson $PacketPath
    $protocol=$packet['protocol']
    $expected='Using Lua console commands will disable achievements. Please repeat the command to proceed.'
    if($protocol['confirmation_marker']-cne$expected-or(Get-MIR441TextSha256 $expected).ToUpperInvariant()-cne'F5F37A7206390ADD9B1DB0C2F108794CC75C58DC69F55EEFEDC0D06352DEF588'){throw 'packet does not bind the observed console confirmation marker'}
    $result=Invoke-ConsoleStartupControl -Protocol $protocol -Root (Join-Path $OutputRoot 'console-confirmation-observed') -Confirmation observed
    if($result.receipt.send_count-ne2-or-not$result.receipt.ready_marker_observed-or-not$result.receipt.confirmation_marker_observed-or$result.receipt.sends[0].kind-cne'command'-or$result.receipt.sends[1].kind-cne'confirmation-replay'){throw 'observed confirmation did not produce the one bounded replay'}
    $lines=@($result.stdin -split "`r?`n" | Where-Object {$_-ne''})
    if($lines.Count-ne2-or$lines[0]-cne$protocol['source_console_command']-or$lines[1]-cne$protocol['source_console_command']){throw 'confirmation replay changed or duplicated the source command'}
}

Add-Check 'wrong, absent, and unrelated output cannot request a console confirmation replay' {
    $protocol=(Read-FiniteFourNativeJson $PacketPath)['protocol']
    foreach($case in @('wrong','absent','unrelated')){
        $result=Invoke-ConsoleStartupControl -Protocol $protocol -Root (Join-Path $OutputRoot ('console-confirmation-'+$case)) -Confirmation $case
        if($result.receipt.send_count-ne1-or$result.receipt.confirmation_marker_observed-or$result.receipt.sends[0].kind-cne'command'){throw "console confirmation '$case' was accepted"}
        $lines=@($result.stdin -split "`r?`n" | Where-Object {$_-ne''})
        if($lines.Count-ne1-or$lines[0]-cne$protocol['source_console_command']){throw "console confirmation '$case' changed the authorized command boundary"}
    }
}

$healthy=New-SyntheticCompleteChain -Root (Join-Path $OutputRoot 'healthy-chain')
Add-Check 'complete reader accepts two governed earned completions and two natural cold reloads' {
    $result=Read-FiniteFourNativeCompleteChain -Chain $healthy
    if($result.governed_earning_stops[0]-ne137-or$result.governed_earning_stops[1]-ne0-or$result.cold_working_inputs.Count-ne2){throw 'complete-chain governed/natural result differs'}
}

Add-Check 'complete reader rejects a marker from the wrong ordered stage' {
    $chain=New-SyntheticCompleteChain -Root (Join-Path $OutputRoot 'wrong-stage')
    Write-ControlJson -Path $chain.successor.configuration_marker -Value (New-SyntheticMarker -Stage 'before-successor-lab' -Role successor -Tick 101)
    Assert-Refuses -Contains 'marker stage' -Action { Read-FiniteFourNativeCompleteChain -Chain $chain | Out-Null }
}

Add-Check 'complete reader rejects an extra active mod outside the Base-only four-member closure' {
    $chain=New-SyntheticCompleteChain -Root (Join-Path $OutputRoot 'extra-active-mod')
    $marker=New-SyntheticMarker -Stage 'source-earned' -Role source -Tick 101
    $marker.mods['space-age']='2.0.0'
    Write-ControlJson -Path $chain.source.earned_marker -Value $marker
    Assert-Refuses -Contains 'marker mod closure differs' -Action { Read-FiniteFourNativeCompleteChain -Chain $chain | Out-Null }
}

Add-Check 'complete reader rejects a successor marker recorded before its configuration callback' {
    $chain=New-SyntheticCompleteChain -Root (Join-Path $OutputRoot 'wrong-temporal-order')
    Write-ControlJson -Path $chain.successor.before_marker -Value (New-SyntheticMarker -Stage 'before-successor-lab' -Role successor -Tick 100)
    Assert-Refuses -Contains 'local marker tick order differs' -Action { Read-FiniteFourNativeCompleteChain -Chain $chain | Out-Null }
}

Add-Check 'complete reader rejects candidate configuration that incorrectly claims the second completion before its lab starts' {
    $chain=New-SyntheticCompleteChain -Root (Join-Path $OutputRoot 'wrong-configuration-completion')
    $marker=New-SyntheticMarker -Stage 'configuration' -Role successor -Tick 101
    $marker.next_level=7;$marker.completed=2;$marker.worker_bonus=9;$marker.native_lab_completions=2
    Write-ControlJson -Path $chain.successor.configuration_marker -Value $marker
    Assert-Refuses -Contains 'next level differs' -Action { Read-FiniteFourNativeCompleteChain -Chain $chain | Out-Null }
}

Add-Check 'complete reader rejects a cold reload without Test passed' {
    $chain=New-SyntheticCompleteChain -Root (Join-Path $OutputRoot 'missing-test-passed')
    [IO.File]::WriteAllText($chain.cold2.stdout,"engine exited normally`n",[Text.UTF8Encoding]::new($false))
    Assert-Refuses -Contains 'lacks Test passed' -Action { Read-FiniteFourNativeCompleteChain -Chain $chain | Out-Null }
}

Add-Check 'complete reader rejects a save whose ZIP member CRC no longer verifies' {
    $chain=New-SyntheticCompleteChain -Root (Join-Path $OutputRoot 'corrupt-source-save')
    $bytes=[IO.File]::ReadAllBytes($chain.source.protected_save)
    $bytes[50]=$bytes[50]-bxor1
    [IO.File]::WriteAllBytes($chain.source.protected_save,$bytes)
    $chain.source.protected_initial=Get-FiniteFourNativeFingerprint $chain.source.protected_save
    Assert-Refuses -Contains 'source save CRC or level data differs' -Action { Read-FiniteFourNativeCompleteChain -Chain $chain | Out-Null }
}

Add-Check 'complete reader rejects an altered protected source after its captured source completion' {
    $chain=New-SyntheticCompleteChain -Root (Join-Path $OutputRoot 'changed-protected-source')
    [IO.File]::AppendAllText($chain.source.protected_save,'changed-after-source',[Text.UTF8Encoding]::new($false))
    Assert-Refuses -Contains 'protected source initial' -Action { Read-FiniteFourNativeCompleteChain -Chain $chain | Out-Null }
}

Add-Check 'complete reader rejects a protected successor reused as a cold working input' {
    $chain=New-SyntheticCompleteChain -Root (Join-Path $OutputRoot 'aliased-cold-input')
    $chain.cold1.working_input=$chain.successor.protected_save
    Assert-Refuses -Contains 'reuses protected pathname' -Action { Read-FiniteFourNativeCompleteChain -Chain $chain | Out-Null }
}

Add-Check 'failed execution custody separates attempted invocations from ledger-proved started PIDs and retains cleanup facts' {
    $context=New-SyntheticInterruptedContext -Root (Join-Path $OutputRoot 'failed-execution-custody')
    $primary=[TimeoutException]::new('[mir441-process-timeout]')
    $primary.Data['mir441_factorio_console_startup']=[ordered]@{send_count=1;ready_marker_observed=$true;confirmation_marker_observed=$false}
    $primary.Data['mir441_process_cleanup_facts']=@([ordered]@{step='process-stop-finally';succeeded=$true})
    $restoration=[Collections.Generic.List[object]]::new();$restoration.Add([ordered]@{state='restored-direct-library-controls';library_lock_released=$true})
    $record=New-FiniteFourNativeFailedExecutionRecord -PrimaryError $primary -Context $context -ExecutionState ([ordered]@{restoration=$restoration}) -CleanupOutcome ([ordered]@{attempted=$true;succeeded=$false;errors=@('library restoration failed');library_restoration=[ordered]@{applicable=$true;attempted=$true;succeeded=$false;records=@()}})
    if($record.status-cne'failed-retained-adverse'-or$record.primary_cause.message-cne'[mir441-process-timeout]' -or$record.attempted_invocations-ne2-or$record.actual_started_process_ids.Count-ne1-or$record.actual_started_process_ids[0]-ne4123){throw 'failure custody changed attempted-versus-started process facts'}
    if($record.resource_runs.Count-ne2-or$record.console_startup.send_count-ne1-or$record.process_cleanup_facts.Count-ne1-or$record.restoration.Count-ne1-or$record.cleanup.succeeded-or$record.cleanup.errors[0]-cne'library restoration failed'-or-not$record.cleanup.library_restoration.applicable-or-not$record.cleanup.library_restoration.attempted-or$record.cleanup.library_restoration.succeeded){throw 'failure custody omitted console, restoration, or cleanup facts'}
}

Add-Check 'failure result write refusal cannot replace the original timeout or fabricate a written terminal result' {
    . (Join-Path (Find-FiniteFourNativeRepoRoot -StartPath $PSScriptRoot) 'tools/lib/validation/NativeProbeResources.ps1')
    $context=New-SyntheticInterruptedContext -Root (Join-Path $OutputRoot 'failure-result-write-refusal')
    $primary=[TimeoutException]::new('[mir441-process-timeout]')
    $priorWriter=(Get-Command Write-MIRNativeProbeResult -CommandType Function -ErrorAction Stop).ScriptBlock
    try {
        Set-Item -Path Function:Write-MIRNativeProbeResult -Value {param($Context,$Record) throw 'controlled result write refusal'}
        $written=Write-FiniteFourNativeFailedExecutionResult -PrimaryError $primary -Context $context -ExecutionState ([ordered]@{restoration=@()}) -CleanupOutcome ([ordered]@{attempted=$true;succeeded=$true;errors=@()})
        if($written-or$primary.Message-cne'[mir441-process-timeout]' -or-not$primary.Data['finite_four_failure_ledger_write_attempted']-or$primary.Data['finite_four_failure_ledger_write_succeeded']-or$primary.Data['finite_four_failure_ledger_write_error']-notmatch'controlled result write refusal'){throw 'failure result writer masked the primary timeout'}
    } finally {
        Set-Item -Path Function:Write-MIRNativeProbeResult -Value $priorWriter
    }
}

Add-Check 'Execution writes one failed context result only after synthetic cleanup and rethrows its controlled native timeout' {
    $stubRoot=Join-Path $OutputRoot 'execution-failure-helper-root';New-SyntheticExecutionFailureHelperRoot -Root $stubRoot
    $global:FiniteFourFailurePathState=[ordered]@{activation=$null;activation_started=0;cleanup_count=0;native_call_count=0;result_write_count=0;result=$null}
    $executionRoot=Join-Path $OutputRoot 'execution-failure-context'
    $packet=[ordered]@{
        runtime_bindings=[ordered]@{output_root=$executionRoot;library_directory='synthetic-library';source_profile='synthetic-source-profile';candidate_profile='synthetic-candidate-profile';source_seed_map_gen_settings='synthetic-map-settings';server_settings_template='synthetic-server-settings';server_port=34197}
        inputs=[ordered]@{engine=[ordered]@{binary_path='synthetic-factorio';engine_data_path='synthetic-data'};source_mir=[ordered]@{filename='source.zip';sha256='source'};candidate_mir=[ordered]@{filename='candidate.zip';sha256='candidate'};fixtures=@()}
        bounds=[ordered]@{expected_peak_memory_mib=4096;max_new_output_mib=512;create_timeout_seconds=240;server_timeout_seconds=240;cold_timeout_seconds=120;cold_test_ticks=10}
        protocol=[ordered]@{source_console_command='/c remote.call("mir-worker-storage-native-observer", "begin", "source")';successor_console_command='/c remote.call("mir-worker-storage-native-observer", "begin", "successor")';console_ready_marker='Hosting game at IP ADDR:';confirmation_marker='Using Lua console commands will disable achievements. Please repeat the command to proceed.'}
    }
    $seen=$null
    try { Invoke-FiniteFourNativeExecution -Packet $packet -RepoRoot $stubRoot|Out-Null } catch {$seen=$_}
    try {
        if($null-eq$seen-or$seen.Exception.Message-cne'[mir441-process-timeout]'){throw "Execution did not preserve the controlled native timeout: $($seen.Exception.Message)"}
        $state=$global:FiniteFourFailurePathState
        if($state.native_call_count-ne1-or$state.activation_started-ne1-or$state.cleanup_count-ne1-or$state.result_write_count-ne1-or$null-eq$state.result){throw 'Execution did not run the one-call cleanup-before-result boundary'}
        if($state.result.status-cne'failed-retained-adverse'-or$state.result.primary_cause.message-cne'[mir441-process-timeout]' -or$state.result.attempted_invocations-ne1-or$state.result.actual_started_process_ids.Count-ne0-or-not$state.result.cleanup.library_restoration.applicable-or-not$state.result.cleanup.library_restoration.attempted-or-not$state.result.cleanup.library_restoration.succeeded){throw 'Execution failed result differs from the controlled timeout boundary'}
    } finally {
        Remove-Variable -Name FiniteFourFailurePathState -Scope Global -ErrorAction SilentlyContinue
    }
}

Add-Check 'the executor contains an explicit post-cleanup failed-context writer instead of a success-only result path' {
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($ControllerPath,[ref]$tokens,[ref]$errors)
    if($errors.Count-ne0){throw 'controller parse failed'}
    $execution=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Invoke-FiniteFourNativeExecution'},$true))
    if($execution.Count-ne1-or$execution[0].Extent.Text-notmatch'Write-FiniteFourNativeFailedExecutionResult'-or$execution[0].Extent.Text-notmatch'library_restoration'){throw 'executor retains the prior success-only failure path'}
}

Add-Check 'cleanup retains the primary chain failure and records the restoration failure' {
    $primary=$null;try{throw 'primary chain rejection'}catch{$primary=$_}
    $seen=$null
    try { Complete-FiniteFourNativeCleanup -PrimaryError $primary -CleanupAction { throw 'library restoration failed' } } catch { $seen=$_ }
    if($null-eq$seen-or$seen.Exception.Message-notmatch'primary chain rejection'-or$seen.Exception.Data['finite_four_cleanup_errors'][0]-notmatch'library restoration failed'){throw 'cleanup masked the primary cause'}
}

Add-Check 'cleanup alone refuses a failed restoration' {
    Assert-Refuses -Contains 'finite-four cleanup failed' -Action { Complete-FiniteFourNativeCleanup -PrimaryError $null -CleanupAction { throw 'library restoration failed' } }
}

$controllerHash=(Get-FileHash -LiteralPath $ControllerPath -Algorithm SHA256).Hash
$packetHash=(Get-FileHash -LiteralPath $PacketPath -Algorithm SHA256).Hash
$testHash=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
$receipt=[ordered]@{
    schema=1;kind='MIRWorkerStorageFiniteFourA504NativeExecutorHostControlReceiptV1'
    controller=[ordered]@{path=$ControllerPath;sha256=$controllerHash;bytes=(Get-Item -LiteralPath $ControllerPath).Length}
    packet=[ordered]@{path=$PacketPath;sha256=$packetHash;bytes=(Get-Item -LiteralPath $PacketPath).Length}
    control_script=[ordered]@{path=$PSCommandPath;sha256=$testHash;bytes=(Get-Item -LiteralPath $PSCommandPath).Length}
    controls=$checks;count=$checks.Count
    result='PASS: host-only parser/chain/cleanup controls. No actual ResourceGovernor context, direct library activation, Factorio process, save creation by an engine, RCON listener, or gameplay result was created.'
    limits='Synthetic save ZIPs and marker files validate the controller reader only. Exact native inputs remain missing or deferred, and no current result is native evidence.'
}
Write-ControlJson -Path (Join-Path $OutputRoot 'result.json') -Value $receipt
$receipt | ConvertTo-Json -Depth 100
