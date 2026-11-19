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
    if($receipt.status-ne'DEFERRED_MISSING_LOCAL_BINDINGS'-or$receipt.native_processes_started-ne0-or$receipt.library_activation-or$receipt.resource_context_allocated){throw 'Validate crossed an execution boundary'}
}

Add-Check 'Compose reports the five bounded stages and remains non-activating' {
    $receipt=Invoke-FiniteFourNativeExecutor -RequestedMode Compose -RequestedPacketPath $PacketPath -RepoRoot (Find-FiniteFourNativeRepoRoot -StartPath $PSScriptRoot) -RequestedOutputPath (Join-Path $OutputRoot 'compose.json')
    if($receipt.status-ne'COMPOSED_DEFERRED_MISSING_LOCAL_BINDINGS'-or$receipt.execution_plan.stages.Count-ne5-or$receipt.library_activation-or$receipt.resource_context_allocated){throw 'Compose crossed an execution boundary or changed the five-stage contract'}
    if($receipt.execution_plan.stages[2].acceleration_reapplied-ne1000-or-not$receipt.execution_plan.stages[2].configuration_precedes_console_request-or$receipt.execution_plan.protocol_difference_from_r02-notmatch'ConsoleStartup'){throw 'Compose lost the bounded ConsoleStartup protocol'}
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
    result='PASS: host-only parser/chain/cleanup controls. No context, direct library activation, Factorio process, save creation by an engine, RCON listener, or gameplay result was created.'
    limits='Synthetic save ZIPs and marker files validate the controller reader only. Exact native inputs remain missing or deferred, and no current result is native evidence.'
}
Write-ControlJson -Path (Join-Path $OutputRoot 'result.json') -Value $receipt
$receipt | ConvertTo-Json -Depth 100
