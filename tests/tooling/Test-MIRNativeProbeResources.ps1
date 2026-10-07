# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,[switch]$CapOwnershipInputsOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/BrowserContinuityInputs.ps1')
. (Join-Path $repo 'tests/support/MIRMaterialAuditInputs.ps1')
$fixture=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo ('build/tmp/native-probe-fixture-'+[guid]::NewGuid().ToString('N')))
$assertions=0;$lease=$null;$completed=$false
function Assert-Probe([bool]$Condition,[string]$Message) {
  if(-not $Condition) { throw "Native probe resources: $Message" }
  $script:assertions++
}
function Refuses-Probe([scriptblock]$Action,[string]$Expected) {
  $failure=''
  try { & $Action | Out-Null } catch { $failure=$_.Exception.Message }
  Assert-Probe ($failure.Contains($Expected)) "expected $Expected; got $failure"
}
# Fake capacity is confined to tiny controlled process/metadata fixtures.
# This suite never launches Factorio or the real package materializer.
function Get-MIR441ResourceSnapshot {
  param([string]$WorkRoot)
  [pscustomobject]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');memory=[pscustomobject]@{total_bytes=16GB;free_bytes=12GB;committed_bytes=4GB;commit_limit_bytes=20GB};system_volume=[pscustomobject]@{free_bytes=100GB};work_volume=[pscustomobject]@{free_bytes=100GB}}
}
function Assert-F210CapSharedInputs {
  . (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
  . (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')
  $capRoot=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo ('build/tmp/f210-cap-controls-'+[guid]::NewGuid().ToString('N')))
  $tokens=$null;$errors=$null
  $harness=Join-Path $repo 'tests/runtime/Test-MIR42CapOwnershipMultiforce.ps1'
  $ast=[Management.Automation.Language.Parser]::ParseFile($harness,[ref]$tokens,[ref]$errors)
  Assert-Probe (@($errors).Count -eq 0) 'F210 cap harness no longer parses.'
  foreach($name in @('Assert-MIR42','Assert-Exact','New-MIR42Stage','Invoke-MIR42Engine','Invoke-MIR42ServerSave','Get-MIR42GovernedEngineResolution')) {
    $definition=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$false))
    Assert-Probe ($definition.Count -eq 1) "expected one consumed F210 cap function: $name"
    . ([scriptblock]::Create($definition[0].Extent.Text))
  }
  $inputLeases=[Collections.Generic.List[object]]::new()
  try {
    $null=New-Item -ItemType Directory -Path $capRoot
    $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $capRoot -ExpectedPeakMemoryMiB 1024 -MaxNewOutputMiB 4
    $run=$resources.root;$engineRoot=$capRoot;$engine='controlled-engine-never-executed';$FactorioBin='controlled requested engine';$SteamManifest='controlled requested manifest'
    $candidateZip=Join-Path $capRoot 'more-infinite-research_4.2.21001.zip'
    [IO.File]::WriteAllText($candidateZip,'tiny immutable F210 cap candidate control')
    $candidateHash=Get-MIRImmutableInputSha256 $candidateZip
    $candidateInput=[pscustomobject]@{receipt=[pscustomobject]@{archive_sha256=$candidateHash;package_source_sha256=('A'*64)}}
    $fixture=Join-Path $repo 'fixtures/assert-mir42-cap-ownership-multiforce'
    $blockerFixture=Join-Path $repo 'fixtures/late-mir42-cap-binding-blocker'
    $policyBlockerFixture=Join-Path $repo 'fixtures/late-mir42-policy-binding-blocker'
    $fixtureName='mir-fixture-assert-mir42-cap-ownership-multiforce';$blockerName='late-mir42-cap-binding-blocker';$policyBlockerName='late-mir42-policy-binding-blocker'
    $stages=@((New-MIR42Stage seed 0 $false $false),(New-MIR42Stage capped 3 $false $false),(New-MIR42Stage policy-blocked 3 $false $true),(New-MIR42Stage blocked 3 $true $false),(New-MIR42Stage removal 0 $false $false))
    foreach($stage in $stages) {
      $input=$stage.lease.record.inputs[0]
      Assert-Probe ($stage.lease.record.require_hard_links -and $input.staging_mode -ceq 'hardlink' -and (Get-MIRImmutableInputFileIdentity $candidateZip) -ceq (Get-MIRImmutableInputFileIdentity $input.stage_path)) "F210 $($stage.name) copied its candidate."
      $modList=Get-Content -Raw -LiteralPath $stage.mod_list|ConvertFrom-Json
      Assert-Probe (($blockerName -in @($modList.mods.name)) -eq $stage.blocker -and ($policyBlockerName -in @($modList.mods.name)) -eq $stage.policy_blocker) "F210 $($stage.name) changed blocker selection."
      $zip=[IO.Compression.ZipFile]::OpenRead($stage.settings_archive)
      try {$reader=[IO.StreamReader]::new($zip.GetEntry('mir-validation-settings-overrides_0.1.0/settings-updates.lua').Open());try {$text=$reader.ReadToEnd()} finally {$reader.Dispose()}} finally {$zip.Dispose()}
      Assert-Probe ($text.Contains('override("ips-max-level-research_copper", '+$stage.cap+')')) "F210 $($stage.name) lost its private cap value."
      [IO.File]::WriteAllText((Join-Path $stage.mods 'mod-settings.dat'),"private $($stage.name)")
    }
    Assert-Probe ($resources.shared_alias_bytes -eq 5*(Get-Item -LiteralPath $candidateZip).Length) 'F210 cap alias output accounting differs.'
    Assert-Probe (@($stages|ForEach-Object {Get-MIRImmutableInputFileIdentity (Join-Path $_.mods 'mod-settings.dat')}|Sort-Object -Unique).Count -eq 5) 'F210 cap mutable settings share file identities.'
    $script:capCopies=0
    function New-Item { [CmdletBinding()]param([string]$ItemType,[string[]]$Path,[string]$Target,[switch]$Force);if($ItemType -ceq 'HardLink'){throw 'controlled unavailable hardlink'};Microsoft.PowerShell.Management\New-Item @PSBoundParameters }
    function Copy-Item { $script:capCopies++;throw 'copy attempted' }
    try {Refuses-Probe {New-MIR42Stage unavailable 0 $false $false} 'requires a verified hard link';Assert-Probe ($script:capCopies -eq 0) 'F210 cap link failure invoked copying.'} finally {Remove-Item Function:\New-Item;Remove-Item Function:\Copy-Item}

    # Stubs exercise the consumed entry points and predicates; no engine runs.
    function Invoke-MIRNativeProbeProcess {
      param($Context,[string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds)
      Assert-Probe ($Context -eq $resources -and $FilePath -ceq (Get-Command pwsh).Source -and $TimeoutSeconds -eq 30 -and $Arguments -contains $FactorioBin -and $Arguments -contains $SteamManifest) 'F210 resolver lost its governed context, inputs or timeout.'
      $driver=Get-Content -Raw -LiteralPath (Join-Path $Context.root 'resolve-engine.ps1')
      Assert-Probe ($driver.Contains('Resolve-MIR4F210CurrentEngineCapHarnessAdmissionV3') -and $driver.Contains("-HarnessId 'runtime.maximum-level-cap-ownership-multiforce-f210'")) 'F210 resolver bypasses its existing admission oracle.'
      [IO.File]::WriteAllText((Join-Path $Context.root 'engine-resolution.json'),'{"engine":{"version":"controlled","sha256":"controlled"},"record_sha256":"controlled"}')
    }
    $resolution=Get-MIR42GovernedEngineResolution
    Assert-Probe ($resolution.engine.version -ceq 'controlled' -and $resolution.record_sha256 -ceq 'controlled') 'F210 resolution response was reconstructed or lost.'
    $expectedSave=Join-Path $stages[0].userdata 'saves/successor.zip';$reportCompletion=$true
    function Invoke-MIRNativeProbeFactorioProcess {
      param($Context,[string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds,[scriptblock]$CompletionPredicate)
      Assert-Probe ($Context -eq $resources -and $FilePath -ceq $engine -and $Arguments -contains $stages[0].config) 'F210 actor lost private context or engine.'
      $log=Join-Path $stages[0].userdata 'factorio-current.log'
      if($null -eq $CompletionPredicate){Assert-Probe ($TimeoutSeconds -eq 120 -and $Arguments -contains '--create') 'F210 create actor lost its timeout or arguments.';[IO.File]::WriteAllText($log,'tiny creation control');return [pscustomobject]@{result=[pscustomobject]@{completion_predicate_observed=$false}}}
      Assert-Probe ($TimeoutSeconds -eq 60 -and $Arguments -contains '--start-server' -and $Arguments -contains $stages[0].server_settings) 'F210 server lost its controls or timeout.'
      if(Test-Path -LiteralPath $expectedSave){Remove-Item -LiteralPath $expectedSave}
      Assert-Probe (-not (& $CompletionPredicate)) 'F210 completion accepts absent log/save.'
      [IO.File]::WriteAllText($log,'Saving finished');Assert-Probe (-not (& $CompletionPredicate)) 'F210 completion accepts absent save.'
      [IO.File]::WriteAllText($expectedSave,'tiny save control');Assert-Probe (-not (& $CompletionPredicate)) 'F210 completion accepts absent state.'
      [IO.File]::WriteAllText($log,'[mir42-cap-ownership-multiforce] STATE JSON {"stage":"event-probe"}');Assert-Probe (-not (& $CompletionPredicate)) 'F210 completion accepts an unfinished save.'
      [IO.File]::WriteAllText($log,'[mir42-cap-ownership-multiforce] STATE JSON {"stage":"blocked"} Saving finished');Assert-Probe (-not (& $CompletionPredicate)) 'F210 completion accepts another stage.'
      [IO.File]::WriteAllText($log,'[mir42-cap-ownership-multiforce] STATE JSON {"stage":"event-probe"} Saving finished');Assert-Probe (& $CompletionPredicate) 'F210 completion rejects all original conditions.'
      [pscustomobject]@{result=[pscustomobject]@{completion_predicate_observed=$reportCompletion}}
    }
    $null=Invoke-MIR42Engine $stages[0] seed @('--create','controlled-input.zip')
    $null=Invoke-MIR42ServerSave $stages[0] capped 'controlled-input.zip' $expectedSave event-probe
    $reportCompletion=$false
    Refuses-Probe {Invoke-MIR42ServerSave $stages[0] incomplete 'controlled-input.zip' $expectedSave event-probe} 'did not create incomplete successor'
    foreach($stage in $stages){$terminal=Complete-MIRImmutableInputLease -Lease $stage.lease -Outcome passed;$null=Assert-MIRImmutableInputTerminalReceipt -Receipt $terminal;$null=Assert-MIRImmutableInputLeaseReclaimable -RunRoot $stage.root -Context 'completed tiny F210 cap stage';$null=Assert-MIRImmutableInputPathWithin -Path $stage.root -Root $capRoot -Context 'tiny F210 stage cleanup';Remove-Item -LiteralPath $stage.root -Recurse}
    Assert-Probe ((Get-MIRImmutableInputSha256 $candidateZip) -ceq $candidateHash) 'F210 cap retirement changed or removed source bytes.'
    Write-Host '[ok] F210 cap consumer: five strict-link stages, private settings, no-copy failure, governed resolver transport and original save-completion prerequisites; no Factorio or construction.'
  } finally {
    foreach($inputLease in $inputLeases){if(-not $inputLease.closed){$null=Complete-MIRImmutableInputLease -Lease $inputLease -Outcome failed}}
    if(Test-Path -LiteralPath $capRoot){$null=Assert-MIRImmutableInputPathWithin -Path $capRoot -Root (Join-Path $repo 'build/tmp') -Context 'owned tiny F210 control cleanup';Remove-Item -LiteralPath $capRoot -Recurse -Force}
  }
}
Assert-F210CapSharedInputs
if($CapOwnershipInputsOnly){return}
try {
  . (Join-Path $repo 'tests/support/MIR421SpaceFakeUpgrade.ps1')
  foreach ($target in @('f210','f200')) {
    $code=$target.Substring(1)
    $sifArguments=@{Target=$target;FromVersion="4.2.${code}00";ToVersion="4.2.${code}01";FixtureName="assert-upgrade-4-0-${code}00-to-4-1-${code}00";Archetype=$(if($target -ceq 'f210'){'base-continuations'}else{'base-default'})}
    $descriptor=Get-MIR421SpaceFakeUpgradeDescriptor @sifArguments
    Assert-Probe ($descriptor.inputs.Count -eq 2 -and ($descriptor.mod_names -join '|') -ceq 'space-is-fake|cr-commons' -and $descriptor.request -ceq 'SIF-01') "exact $target native dependency profile lost its inputs."
    $bad=$sifArguments.Clone();$bad.ToVersion="4.2.${code}02"
    Refuses-Probe {Get-MIR421SpaceFakeUpgradeDescriptor @bad} 'sif-transition'
    $bad=$sifArguments.Clone();$bad.FromVersion="4.1.${code}00"
    Refuses-Probe {Get-MIR421SpaceFakeUpgradeDescriptor @bad} 'sif-transition'
    $bad=$sifArguments.Clone();$bad.Archetype='space-age-native-owner'
    Refuses-Probe {Get-MIR421SpaceFakeUpgradeDescriptor @bad} 'sif-transition'
    $control=Get-Content -Raw -LiteralPath (Join-Path $repo ('fixtures/'+$sifArguments.FixtureName+'/control.lua'))
    $specialized=Add-MIR421SpaceFakeUpgradeOracle -ControlText $control
    Assert-Probe ($specialized.Contains('sif.capture()') -and $specialized.Contains('sif.verify("upgrade")') -and $specialized.Contains('sif.verify("reload")') -and $specialized.Contains('force.research_progress=expected_progress')) "actual $target staged fixture lost the original research oracle."
    Refuses-Probe {Add-MIR421SpaceFakeUpgradeOracle -ControlText $specialized} 'sif-fixture-anchor'
  }
  Refuses-Probe {Get-MIR421SpaceFakeUpgradeDescriptor -Target f110} 'sif-target'
  Refuses-Probe {Get-MIR421SpaceFakeUpgradeDescriptor -Target F210} 'sif-target'
  foreach($stage in @('source','upgrade','reload')) {
    Assert-MIR421SpaceFakeUpgradeMarker -Text "[mir-fixture] SIF-01 native continuations verified stage=$stage" -Stage $stage
    Refuses-Probe {Assert-MIR421SpaceFakeUpgradeMarker -Text 'generic load passed' -Stage $stage} "sif-$stage-marker"
    Refuses-Probe {Assert-MIR421SpaceFakeUpgradeMarker -Text "[mir-fixture] SIF-01 native continuations verified stage=$stage-incomplete" -Stage $stage} "sif-$stage-marker"
  }
  . (Join-Path $repo 'tools/lib/assurance/evidence/CommandExecution.ps1')
  $catalog=Get-Content -LiteralPath (Join-Path $repo 'validation/tests.yml') -Raw | ConvertFrom-Json
  $command=[string](@($catalog.tests | Where-Object id -CEQ 'runtime.material-route-guard')[0].command)
  foreach($line in @('2.0','2.1')) {
    $engine=if($line -ceq '2.0') { 'D:\Programs\Factorio\2.0\bin\x64\factorio.exe' } else { 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' }
    $resolved=Resolve-MIRAssuranceCommandText -Command $command -Context ([pscustomobject]@{factorio=$engine;target=$line}) -Plan ([pscustomobject]@{})
    Assert-Probe ($resolved.Contains("-FactorioBin '$engine'") -and $resolved.Contains("-ExpectedFactorioLine '$line'") -and $resolved.Contains('-ExpectedPeakMemoryMiB 2048') -and $resolved.Contains('-MaxNewOutputMiB 120')) "selected $line command lost its engine, line or explicit resource budgets."
    $browserCommand=[string](@($catalog.tests | Where-Object id -CEQ 'runtime.research-browser')[0].command)
    $browserResolved=Resolve-MIRAssuranceCommandText -Command $browserCommand -Context ([pscustomobject]@{factorio=$engine;target=$line;candidate='controlled-candidate.zip'}) -Plan ([pscustomobject]@{})
    Assert-Probe ($browserResolved.Contains("-FactorioBin '$engine'") -and $browserResolved.Contains("-Target '$line'") -and $browserResolved.Contains('-ExpectedPeakMemoryMiB 2048') -and $browserResolved.Contains('-MaxNewOutputMiB 120')) "selected browser $line command lost its actual engine, target or resource budgets."
  }
  $arguments=@{RepoRoot=$repo;OutputRoot=$fixture;MaxNewOutputMiB=1}
  Refuses-Probe {New-MIRNativeProbeResourceContext @arguments} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'missing-budget refusal allocated staging.'
  Refuses-Probe {New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot 'D:\outside-native-probe' -ExpectedPeakMemoryMiB 1024} 'resource-output-root'
  foreach($script in @('tests/compiler/Test-MIRMaterialRoutes.ps1','tests/runtime/Test-MIRF210CurrentBobAngelTinRouteObserver.ps1','tests/runtime/Test-MIRF210CurrentBobAngelFinalRoutesObserver.ps1')) {
    $probeArguments=@{RepoRoot=$repo;FactorioBin='absent-engine';OutputRoot=$fixture}
    if($script.StartsWith('tests/runtime/')) {$probeArguments.ExactStageRoot=Join-Path $fixture 'absent-stage'}
    Refuses-Probe {& (Join-Path $repo $script) @probeArguments} 'resource-peak-budget-required'
    Assert-Probe (-not (Test-Path -LiteralPath $fixture)) "$script allocated staging before refusal."
  }
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelTinRouteObserver.ps1') -RepoRoot $repo -PrepareOnly -OutputRoot $fixture} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'PrepareOnly bypassed allocation admission.'
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelFinalRoutesObserver.ps1') -RepoRoot $repo -PrepareOnly -ExactStageRoot (Join-Path $fixture 'absent-stage') -OutputRoot $fixture} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'Final observer PrepareOnly bypassed allocation admission.'
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRResearchBrowser.ps1') -RepoRoot $repo -FactorioBin 'absent-browser-engine' -OutputRoot $fixture} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'Browser harness allocated before peak-budget admission.'
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRPassiveRepair.ps1') -RepoRoot $repo -CandidateZip 'absent-passive-candidate' -FactorioBin 'absent-passive-engine' -OutputRoot $fixture} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'Passive repair allocated or probed an engine before peak-budget admission.'
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRBobTinBrowserExplanation.ps1') -RepoRoot $repo -CandidateZip 'absent-tin-candidate' -BobModsDir 'absent-tin-library' -FactorioBin 'absent-tin-engine' -OutputRoot $fixture} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'Tin browser allocated or probed an input before peak-budget admission.'
  foreach ($prepare in @($false,$true)) {
    Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobTinLevel4Continuation.ps1') -RepoRoot $repo -FactorioBin 'absent-tin-engine' -CandidateZip 'absent-tin-candidate' -SettingsPath 'absent-settings' -OutputRoot $fixture -PrepareOnly:$prepare} 'resource-peak-budget-required'
    Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'Tin continuation prepared inputs before resource admission.'
  }
  $context=New-MIRNativeProbeResourceContext @arguments -ExpectedPeakMemoryMiB 1024
  Assert-Probe (-not (Test-Path -LiteralPath $context.root)) 'successful admission allocated before caller initialization.'
  New-Item -ItemType Directory -Path $context.root | Out-Null
  # Extract the consumed harness functions, rather than a second validator.
  # These tiny ZIPs contain only identity/module controls, not player packages.
  $browserTokens=$null;$browserErrors=$null
  $browserAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIRResearchBrowser.ps1'),[ref]$browserTokens,[ref]$browserErrors)
  Assert-Probe ($browserErrors.Count -eq 0) 'browser harness syntax differs.'
  foreach($name in @('Resolve-BrowserEnginePath','Test-BrowserCandidate')) {
    $definitions=@($browserAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false))
    Assert-Probe ($definitions.Count -eq 1) "expected one actual browser admission function: $name"
    . ([scriptblock]::Create($definitions[0].Extent.Text))
  }
  $tinAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIRBobTinBrowserExplanation.ps1'),[ref]$browserTokens,[ref]$browserErrors)
  Assert-Probe ($browserErrors.Count -eq 0) 'tin browser harness syntax differs.'
  foreach($name in @('Resolve-TinBrowserEnginePath','Test-TinBrowserCandidate')) {
    $definitions=@($tinAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false))
    Assert-Probe ($definitions.Count -eq 1) "expected one actual tin browser admission function: $name"
    . ([scriptblock]::Create($definitions[0].Extent.Text))
  }
  $currentTin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
  Assert-Probe ((Resolve-TinBrowserEnginePath $currentTin) -ceq $currentTin) 'tin browser changed its authorized engine path.'
  Refuses-Probe {Resolve-TinBrowserEnginePath 'D:\Programs\Factorio\2.0\bin\x64\factorio.exe'} 'engine-location'
  $historical='D:\Programs\Factorio\2.0\bin\x64\factorio.exe'
  $current='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
  Assert-Probe ((Resolve-BrowserEnginePath -Line '2.0' -Requested '') -ceq $historical) '2.0 default used another engine authority.'
  Assert-Probe ((Resolve-BrowserEnginePath -Line '2.1' -Requested '') -ceq $current) '2.1 default used another engine authority.'
  Assert-Probe ((Resolve-BrowserEnginePath -Line '2.0' -Requested $historical) -ceq $historical) 'explicit historical engine was refused.'
  Refuses-Probe {Resolve-BrowserEnginePath -Line '2.0' -Requested $current} 'engine-location'
  Refuses-Probe {Resolve-BrowserEnginePath -Line '2.1' -Requested $historical} 'engine-location'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  function New-ControlledBrowserArchive([string]$Line,$Identity,[string]$Variant='valid') {
    $directory=Join-Path $fixture ('browser-inputs/'+[guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $directory
    $fileName=if($Variant -ceq 'filename'){'wrong-name.zip'}else{$Identity.package_name}
    $path=Join-Path $directory $fileName
    $root='more-infinite-research_'+$Identity.distribution_version
    $info=[ordered]@{name='more-infinite-research';version=$Identity.distribution_version;factorio_version=$Line}
    if($Variant -ceq 'patch-zero'){$info.version=$info.version.Substring(0,$info.version.Length-2)+'00'}
    if($Variant -ceq 'patch-two'){$info.version=$info.version.Substring(0,$info.version.Length-2)+'02'}
    if($Variant -ceq 'wrong-target'){$info.factorio_version=if($Line -ceq '2.1'){'2.0'}else{'2.1'}}
    if($Variant -ceq 'root'){$root='wrong-root'}
    $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
    try {
      $infoText=ConvertTo-Json -InputObject $info -Compress
      if($Variant -ceq 'info-budget'){$infoText+=' '*64KB}
      $entry=$zip.CreateEntry($root+'/info.json');$writer=[IO.StreamWriter]::new($entry.Open())
      try{$writer.Write($infoText)}finally{$writer.Dispose()}
      if($Variant -ceq 'duplicate-info'){$null=$zip.CreateEntry($root+'/info.json')}
      $modules=@('research_browser.lua','research_browser_core.lua','research_browser_factorio_catalogue.lua','research_browser_mir_provider.lua','research_browser_actions.lua')
      foreach($module in $modules) {
        if($Variant -ceq 'missing-module' -and $module -ceq $modules[0]){continue}
        $entryName=$root+'/prototypes/mir/runtime/'+$module
        if($Variant -ceq 'nested-module' -and $module -ceq $modules[0]){$entryName=$root+'/nested/prototypes/mir/runtime/'+$module}
        $bytes=[IO.File]::ReadAllBytes((Join-Path $repo ('source/prototypes/mir/runtime/'+$module)))
        if($Variant -ceq 'changed-module' -and $module -ceq $modules[0]){$bytes[0]=$bytes[0] -bxor 1}
        $entry=$zip.CreateEntry($entryName);$stream=$entry.Open()
        try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
        if($Variant -ceq 'duplicate-module' -and $module -ceq $modules[0]){$null=$zip.CreateEntry($entryName)}
      }
      $extra=switch -CaseSensitive ($Variant) {
        'outside' {'outside/extra.lua'}
        'root-case' {$root.ToUpperInvariant()+'/extra.lua'}
        'traversal' {$root+'/../outside.lua'}
        'backslash' {$root+'/nested\extra.lua'}
        'forbidden-repo' {$root+'/fixtures/unowned.lua'}
        default {''}
      }
      if($extra){$null=$zip.CreateEntry($extra)}
    }finally{$zip.Dispose()}
    return $path
  }
  foreach($line in @('2.1','2.0')) {
    $code=if($line -ceq '2.1'){'210'}else{'200'}
    $identity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $code -SourceMinor 2 -SourcePatch 1
    $valid=New-ControlledBrowserArchive -Line $line -Identity $identity
    $checked=Test-BrowserCandidate -Candidate $valid -Line $line -Identity $identity -Repository $repo
    Assert-Probe ($checked.info.version -ceq $identity.distribution_version -and $checked.sha256 -ceq (Get-FileHash -LiteralPath $valid).Hash) "actual browser $line validator lost exact patch-one identity or input hash."
    if($line -ceq '2.1') {
      $tinChecked=Test-TinBrowserCandidate -Candidate $valid -Line $line -Identity $identity -Repository $repo
      Assert-Probe ($tinChecked.sha256 -ceq $checked.sha256 -and $tinChecked.info.version -ceq '4.2.21001') 'tin browser lost its actual current source-patch identity.'
      $forbidden=New-ControlledBrowserArchive -Line $line -Identity $identity -Variant forbidden-repo
      Refuses-Probe {Test-TinBrowserCandidate -Candidate $forbidden -Line $line -Identity $identity -Repository $repo} 'candidate-exclusions'
    }
    foreach($case in @(
      @{variant='patch-zero';error='candidate-identity'},@{variant='patch-two';error='candidate-identity'},
      @{variant='wrong-target';error='target mismatch'},@{variant='filename';error='candidate-identity'},
      @{variant='root';error='candidate-identity'},@{variant='outside';error='candidate-identity'},
      @{variant='root-case';error='candidate-identity'},@{variant='traversal';error='candidate-identity'},
      @{variant='backslash';error='candidate-identity'},@{variant='duplicate-info';error='one mod identity'},
      @{variant='info-budget';error='info-budget'},@{variant='missing-module';error='exactly one'},
      @{variant='nested-module';error='exactly one'},@{variant='duplicate-module';error='exactly one'},
      @{variant='changed-module';error='differs from the controlled source'}
    )) {
      $invalid=New-ControlledBrowserArchive -Line $line -Identity $identity -Variant $case.variant
      Refuses-Probe {Test-BrowserCandidate -Candidate $invalid -Line $line -Identity $identity -Repository $repo} $case.error
      if($line -ceq '2.1'){Refuses-Probe {Test-TinBrowserCandidate -Candidate $invalid -Line $line -Identity $identity -Repository $repo} $case.error}
    }
  }
  $continuityAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIRBrowserPersonalStateContinuity.ps1'),[ref]$browserTokens,[ref]$browserErrors)
  Assert-Probe ($browserErrors.Count-eq 0) 'continuity harness syntax differs.'
  . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
  foreach($name in @('Fail','Assert-True','Assert-Equal','Get-Sha256','Get-ZipEntry','Get-ZipEntrySha256','Get-ZipEntryText','Normalize-ZipMember','Test-Candidate')){
    $definitions=@($continuityAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$false))
    Assert-Probe ($definitions.Count-eq 1) "expected one continuity admission function: $name"
    . ([scriptblock]::Create($definitions[0].Extent.Text))
  }
  foreach($target in @('f210','f200')){
    $Target=$target.ToUpperInvariant();$line=if($target-ceq'f210'){'2.1'}else{'2.0'};$TargetContract=@{factorio_line=$line}
    $hostPath=Join-Path $repo 'source/prototypes/mir/runtime/research_browser.lua';$locale=Join-Path $repo 'source/locale/en/more-infinite-research.cfg'
    $readmePath=Join-Path $repo "source/presentation/$target/README.md.template"
    foreach($sourceVersion in @('4.2.0','4.2.1')){
      $identity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $target.Substring(1) -SourceMinor 2 -SourcePatch ([int]$sourceVersion.Split('.')[2])
      $ExpectedDistributionVersion=$identity.distribution_version;$ExpectedPackageRoot='more-infinite-research_'+$ExpectedDistributionVersion
      $ExpectedReadmeSha256=Get-MIRBrowserContinuityReadmeSha256 -RepositoryRoot $repo -Target $target -SourceVersion $sourceVersion -ReadmePath $readmePath
      $readmeBytes=[IO.File]::ReadAllBytes($readmePath)
      if($sourceVersion-ceq'4.2.1'){
        $readmeBytes=Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes $readmeBytes -DistributionVersion $ExpectedDistributionVersion
        Assert-Probe ((Get-MIR4Sha256Bytes -Bytes (Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes $readmeBytes -DistributionVersion $ExpectedDistributionVersion))-ceq$ExpectedReadmeSha256) 'private readme identity transformation is not idempotent.'
      }
      $valid=New-ControlledBrowserArchive -Line $line -Identity $identity
      $zip=[IO.Compression.ZipFile]::Open($valid,[IO.Compression.ZipArchiveMode]::Update)
      try{
        foreach($member in @(@{path='README.md';bytes=$readmeBytes},@{path='locale/en/more-infinite-research.cfg';bytes=[IO.File]::ReadAllBytes($locale)})){
          $entry=$zip.CreateEntry($ExpectedPackageRoot+'/'+$member.path);$stream=$entry.Open()
          try{$stream.Write($member.bytes,0,$member.bytes.Length)}finally{$stream.Dispose()}
        }
      }finally{$zip.Dispose()}
      $checked=Test-Candidate $valid $hostPath $locale $readmePath
      Assert-Probe ($checked.entry_hashes.readme_md-ceq$ExpectedReadmeSha256-and$checked.package_root-ceq$ExpectedPackageRoot) "continuity $target $sourceVersion admission lost materialized identity or README authority."
      if($sourceVersion-ceq'4.2.1'){
        $zip=[IO.Compression.ZipFile]::Open($valid,[IO.Compression.ZipArchiveMode]::Update)
        try{$zip.GetEntry($ExpectedPackageRoot+'/README.md').Delete();$entry=$zip.CreateEntry($ExpectedPackageRoot+'/README.md');$stream=$entry.Open();try{$bytes=[IO.File]::ReadAllBytes($readmePath);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}}finally{$zip.Dispose()}
        Refuses-Probe {Test-Candidate $valid $hostPath $locale $readmePath} 'README differs from expected governed hash'
        $invalid=New-ControlledBrowserArchive -Line $line -Identity $identity -Variant patch-two
        Refuses-Probe {Test-Candidate $invalid $hostPath $locale $readmePath} 'candidate distribution version'
      }
    }
    Refuses-Probe {Get-MIRBrowserContinuityReadmeSha256 -RepositoryRoot $repo -Target $target -SourceVersion '4.2.1' -ReadmePath $hostPath} 'readme-authority'
  }
  Refuses-Probe {Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes ([byte[]]@(65)) -DistributionVersion '4.2.21002'} 'source-patch'
  $source=Join-Path $fixture 'dependency.zip'
  [IO.File]::WriteAllBytes($source,[byte[]]::new(128KB))
  $archiveInput=[ordered]@{source_path=$source;file_name='dependency.zip';expected_sha256=Get-MIRImmutableInputSha256 $source;role='dependency-mod';identity=@{name='controlled'};provenance=@{kind='tiny-controlled-fixture'};immutable=$true}
  $auditCandidate=Join-Path $fixture 'more-infinite-research_4.2.21000.zip';[IO.File]::WriteAllBytes($auditCandidate,[byte[]]::new(64))
  & {
    # Consume the actual passive-repair input and engine adapters. The tiny
    # archive and mocked engine output prove staging/forwarding, not gameplay.
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/runtime/Test-MIRPassiveRepair.ps1'),[ref]$tokens,[ref]$errors)
    Assert-Probe ($errors.Count-eq0) 'passive repair harness parse failed.'
    foreach($name in @('New-PassiveRepairInputLease','Invoke-ProbeEngine')){
      $functions=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$false))
      Assert-Probe ($functions.Count-eq1) "passive repair adapter missing: $name"
      . ([scriptblock]::Create($functions[0].Extent.Text))
    }
    $run=Join-Path $fixture 'passive-repair';$mods=Join-Path $run 'mods'
    New-Item -ItemType Directory -Path $run | Out-Null
    $inputLease=New-PassiveRepairInputLease -Candidate $auditCandidate -ExpectedSha256 (Get-MIRImmutableInputSha256 $auditCandidate) -RunRoot $run -ModsDirectory $mods
    try{
      Assert-Probe ($inputLease.record.require_hard_links-and$inputLease.record.inputs.Count-eq1) 'passive repair did not require one strict archive input.'
      Assert-Probe ((Get-MIRImmutableInputFileIdentity $auditCandidate)-ceq(Get-MIRImmutableInputFileIdentity (Join-Path $mods ([IO.Path]::GetFileName($auditCandidate))))) 'passive repair copied its candidate.'
      $terminal=Complete-MIRImmutableInputLease -Lease $inputLease
      $null=Assert-MIRImmutableInputTerminalReceipt -Receipt $terminal
      Assert-Probe ($terminal.inputs[0].role-ceq'candidate') 'passive repair lost candidate custody.'
    }finally{if(-not$inputLease.closed){$null=Complete-MIRImmutableInputLease -Lease $inputLease -Outcome failed}}
    $resources=[pscustomobject]@{controlled=$true};$engine='controlled-native-engine';$calls=[Collections.Generic.List[object]]::new()
    $stdout=Join-Path $run 'stdout.txt';$stderr=Join-Path $run 'stderr.txt'
    [IO.File]::WriteAllText($stdout,'controlled healthy output');[IO.File]::WriteAllText($stderr,'')
    function Invoke-MIRNativeProbeFactorioProcess {
      param($Context,[string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds)
      $calls.Add([pscustomobject]@{context=$Context;path=$FilePath;arguments=$Arguments;timeout=$TimeoutSeconds})
      [pscustomobject]@{stdout=$stdout;stderr=$stderr}
    }
    Invoke-ProbeEngine -Label controlled -Arguments @('--benchmark','owned-save.zip')
    Assert-Probe ($calls.Count-eq1-and$calls[0].context.controlled-and$calls[0].path-ceq$engine-and$calls[0].timeout-eq60) 'passive repair bypassed the governed actor.'
    $expected=@('--config',(Join-Path $run 'config.ini'),'--mod-directory',$mods,'--benchmark','owned-save.zip')
    Assert-Probe (($calls[0].arguments-join'|')-ceq($expected-join'|')) 'passive repair changed engine arguments.'
    [IO.File]::WriteAllText($stdout,'Exception at tick controlled')
    Refuses-Probe {Invoke-ProbeEngine -Label controlled-error -Arguments @('--create','owned-save.zip')} 'Passive repair controlled-error failed'
    Assert-Probe ((Get-Content -Raw (Join-Path $run 'controlled-error.log'))-ceq'Exception at tick controlled') 'passive repair discarded its failed log.'
  }
  & {
    $functions=@($tinAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Invoke-Engine'},$false))
    Assert-Probe ($functions.Count-eq1) 'tin browser engine adapter is missing.'
    . ([scriptblock]::Create($functions[0].Extent.Text))
    $run=Join-Path $fixture 'tin-browser';$mods=Join-Path $run 'mods'
    New-Item -ItemType Directory -Path (Join-Path $run 'userdata') | Out-Null
    $resources=[pscustomobject]@{controlled=$true};$engine='controlled-tin-engine'
    $calls=[Collections.Generic.List[object]]::new();$budgets=[Collections.Generic.List[object]]::new()
    $stdout=Join-Path $run 'stdout.txt';$stderr=Join-Path $run 'stderr.txt'
    [IO.File]::WriteAllText($stdout,'controlled output');[IO.File]::WriteAllText($stderr,'')
    [IO.File]::WriteAllText((Join-Path $run 'userdata/factorio-current.log'),'controlled native log')
    function Invoke-MIRNativeProbeFactorioProcess {
      param($Context,[string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds)
      $calls.Add([pscustomobject]@{context=$Context;path=$FilePath;arguments=$Arguments;timeout=$TimeoutSeconds})
      if($Arguments -contains 'controlled-failure'){throw 'controlled governed interruption'}
      [pscustomobject]@{stdout=$stdout;stderr=$stderr}
    }
    function Get-MIRNativeProbeRemainingOutputBytes {param($Context);$budgets.Add($Context);return 1MB}
    $log=Invoke-Engine create @('--create','owned-save.zip')
    Assert-Probe ($calls.Count-eq1-and$calls[0].context.controlled-and$calls[0].path-ceq$engine-and$calls[0].timeout-eq120) 'tin browser bypassed the governed actor.'
    $expected=@('--config',(Join-Path $run 'config.ini'),'--mod-directory',$mods,'--create','owned-save.zip')
    Assert-Probe (($calls[0].arguments-join'|')-ceq($expected-join'|')) 'tin browser changed its native arguments.'
    Assert-Probe ((Get-Content -LiteralPath $log -Raw)-ceq'controlled native log'-and$budgets.Count-eq1-and$budgets[0].controlled) 'tin browser lost its original native log or total output check.'
    Refuses-Probe {Invoke-Engine runtime @('controlled-failure')} 'controlled governed interruption'
    Assert-Probe ($budgets.Count-eq1-and-not(Test-Path -LiteralPath (Join-Path $run 'factorio-runtime.log'))) 'tin browser continued after governed failure.'
  }
  & {
    . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
    . (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
    $tokens=$null;$errors=$null
    $path=Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobTinLevel4Continuation.ps1'
    $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    Assert-Probe ($errors.Count-eq0) 'Tin continuation harness parse failed.'
    foreach($name in @('Assert-Tin','Read-TinCurrentCandidate','Invoke-TinGovernedEngine','Invoke-TinBoundedReload','Get-TinSha')) {
      $function=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$false))
      Assert-Probe ($function.Count-eq1) "Tin continuation consumed adapter absent: $name"
      . ([scriptblock]::Create($function[0].Extent.Text))
    }
    $k2Path=Join-Path $repo 'tests/runtime/Test-MIRK2213ImersiteContinuation.ps1'
    $k2Ast=[Management.Automation.Language.Parser]::ParseFile($k2Path,[ref]$tokens,[ref]$errors)
    Assert-Probe ($errors.Count-eq0) 'K2 continuation harness parse failed.'
    foreach($name in @('Fail-K2213','Assert-K2213','Get-K2213Sha256','Get-K2213ZipInfo','Assert-K2213ArchiveIdentity','Read-K2213CurrentCandidate','Read-K2213DependencyInputs')) {
      $function=@($k2Ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$false))
      Assert-Probe ($function.Count-eq1) "K2 continuation consumed adapter absent: $name"
      . ([scriptblock]::Create($function[0].Extent.Text))
    }
    $RepoRoot=$repo
    # Synthetic membership isolates the reader; this is not a MIR package.
    $run=Join-Path $fixture 'tin-continuation';New-Item -ItemType Directory -Path $run|Out-Null
    $candidate=Join-Path $run 'more-infinite-research_4.2.21001.zip'
    $receiptPath=Join-Path $run 'materialized.json'
    $bytes=[Text.Encoding]::UTF8.GetBytes('controlled runtime bytes')
    $binding=[pscustomobject]@{output_path='control.lua';output_bytes=$bytes.Length;output_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
    function Get-MIR4TargetMaterializerState {param($RepoRoot,$Target);[pscustomobject]@{manifest=@{record_sha256=('1'*64)};composition=@{record_sha256=('2'*64)}}}
    function Get-MIR4TargetMaterializationBindings {param($State);[pscustomobject]@{bindings=@([pscustomobject]@{output_path='info.json'},$binding)}}
    $zip=[IO.Compression.ZipFile]::Open($candidate,[IO.Compression.ZipArchiveMode]::Create)
    try {
      foreach($member in @(@{path='info.json';bytes=[Text.Encoding]::UTF8.GetBytes('{"name":"more-infinite-research","version":"4.2.21001","factorio_version":"2.1"}')},@{path='control.lua';bytes=$bytes})) {
        $stream=$zip.CreateEntry('more-infinite-research_4.2.21001/'+$member.path).Open()
        try{$stream.Write($member.bytes,0,$member.bytes.Length)}finally{$stream.Dispose()}
      }
    }finally{$zip.Dispose()}
    $inventory=Get-MIR4ArchiveInventory -Path $candidate
    $record=[ordered]@{schema=1;kind='MIR4PackageCompositionResultV1';status='passed-canonical-package-authority-materialization';materializer_abi='mir4-target-materializer/1';target='f210';candidate_id='CONTROLLED';source_version='4.2.1';distribution_version='4.2.21001';package_authority_sha256=('A'*64);package_source_sha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo;source_manifest_sha256=('1'*64);target_registry_sha256=('A'*64);support_policy_sha256=('A'*64);target_overlay_sha256=('2'*64);source_binding_count=2;omission_count=0;tree_path=$run;archive_path=$candidate;archive_sha256=$inventory.archive_sha256;content_sha256=$inventory.content_sha256;entry_count=$inventory.entry_count;invariants=[ordered]@{no_historical_archive_input=$true;all_source_hashes_verified=$true;all_output_hashes_verified=$true;all_target_differences_explicit=$true;scoped_operation_closure=$true;version_identity_verified=$true;canonical_package_authority=$true};transition_gate=[ordered]@{package_cutover=$true;old_writer_retirement=$true;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false};record_sha256=''}
    function Save-ControlledTinRecord {$record.record_sha256=Get-MIR4BootstrapRecordSha256 -Record ([pscustomobject]$record);$record|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $receiptPath -Encoding utf8}
    Save-ControlledTinRecord
    $read=Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath
    Assert-Probe ($read.path-ceq$candidate-and$read.receipt.distribution_version-ceq'4.2.21001') 'Tin continuation lost patch-one identity.'
    $k2Read=Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath
    Assert-Probe ($k2Read.path-ceq$candidate-and$k2Read.receipt.distribution_version-ceq'4.2.21001') 'K2 continuation did not consume the shared current-candidate reader.'
    Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive '' -ReceiptPath ''} 'supply candidate'
    $savedFingerprint=$record.package_source_sha256;$record.package_source_sha256='0'*64;Save-ControlledTinRecord
    Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath} 'candidate source fingerprint differs'
    Refuses-Probe {Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath} 'candidate source fingerprint differs'
    $record.package_source_sha256=$savedFingerprint
    foreach($version in @('4.2.21000','4.2.21002')) {
      $record.distribution_version=$version;Save-ControlledTinRecord
      Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath} 'candidate materialization identity differs'
      Refuses-Probe {Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath} 'candidate materialization identity differs'
    }
    $record.distribution_version='4.2.21001';$record.source_manifest_sha256='0'*64;Save-ControlledTinRecord
    Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath} 'candidate composition authority differs'
    $record.source_manifest_sha256='1'*64;Save-ControlledTinRecord
    $binding.output_sha256='0'*64
    Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath} 'candidate binding hash differs'
    Refuses-Probe {Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath} 'candidate binding hash differs'
    $binding.output_bytes++
    Refuses-Probe {Read-TinCurrentCandidate -Repository $repo -Archive $candidate -ReceiptPath $receiptPath} 'candidate binding size differs'
    Refuses-Probe {Read-K2213CurrentCandidate -Archive $candidate -ReceiptPath $receiptPath} 'candidate binding size differs'

    $flat=Join-Path $run 'flat-library';New-Item -ItemType Directory -Path $flat|Out-Null
    $dependency=Join-Path $flat 'controlled-k2_1.0.0.zip'
    $zip=[IO.Compression.ZipFile]::Open($dependency,[IO.Compression.ZipArchiveMode]::Create)
    try{$stream=[IO.StreamWriter]::new($zip.CreateEntry('controlled-k2_1.0.0/info.json').Open());try{$stream.Write('{"name":"controlled-k2","version":"1.0.0","factorio_version":"2.1"}')}finally{$stream.Dispose()}}finally{$zip.Dispose()}
    $retired=Join-Path $run 'retired-v5-profile/mods/controlled-k2_1.0.0.zip'
    $observation=[pscustomobject]@{staged_inputs=@([pscustomobject]@{source_path=$retired;sha256=Get-K2213Sha256 $dependency;source_match=$true;stage_match=$true})}
    $expected=[ordered]@{'controlled-k2_1.0.0.zip'=@('controlled-k2','1.0.0')}
    $observationPath=Join-Path $run 'controlled-v5.json';$observation|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $observationPath
    $resolved=@(Read-K2213DependencyInputs -Observation $observation -ExpectedDependencies $expected -Libraries @($flat) -ObservationPath $observationPath)
    Assert-Probe ($resolved.Count-eq1-and$resolved[0].source_path-ceq$dependency-and$resolved[0].provenance.historical_source_path-ceq$retired) 'K2 resolution lost shared archive or historical custody.'
    Assert-Probe (-not(Test-Path -LiteralPath (Join-Path $run 'retired-v5-profile'))) 'K2 library resolution recreated a retired profile.'
    Refuses-Probe {Read-K2213DependencyInputs -Observation $observation -ExpectedDependencies $expected -Libraries @((Join-Path $run 'absent-library')) -ObservationPath $observationPath} 'dependency-missing'
    $observation.staged_inputs[0].sha256='0'*64
    Refuses-Probe {Read-K2213DependencyInputs -Observation $observation -ExpectedDependencies $expected -Libraries @($flat) -ObservationPath $observationPath} 'dependency-hash'
    $observation.staged_inputs[0].sha256=Get-K2213Sha256 $dependency
    $observation.staged_inputs+=@($observation.staged_inputs[0])
    Refuses-Probe {Read-K2213DependencyInputs -Observation $observation -ExpectedDependencies $expected -Libraries @($flat) -ObservationPath $observationPath} 'v5-dependency-lock'
    $observation.staged_inputs=@($observation.staged_inputs[0]);$observation.staged_inputs[0].source_match=$false
    Refuses-Probe {Read-K2213DependencyInputs -Observation $observation -ExpectedDependencies $expected -Libraries @($flat) -ObservationPath $observationPath} 'v5-dependency-lock-integrity'
    $observation.staged_inputs[0].source_match=$true
    $expected['controlled-k2_1.0.0.zip']=@('wrong-identity','1.0.0')
    Refuses-Probe {Read-K2213DependencyInputs -Observation $observation -ExpectedDependencies $expected -Libraries @($flat) -ObservationPath $observationPath} 'archive-name'

    $resources=[pscustomobject]@{controlled=$true};$engine='controlled-tin-engine';$calls=[Collections.Generic.List[object]]::new()
    $tinActorStdout=Join-Path $run 'actor.stdout';$tinActorStderr=Join-Path $run 'actor.stderr'
    [IO.File]::WriteAllText($tinActorStdout,'controlled healthy output');[IO.File]::WriteAllText($tinActorStderr,'')
    [IO.File]::WriteAllText((Join-Path $run 'factorio-current.log'),'controlled native log')
    function Invoke-MIRNativeProbeFactorioProcess {param($Context,$FilePath,$Arguments,$TimeoutSeconds);$calls.Add(@{context=$Context;path=$FilePath;arguments=$Arguments;timeout=$TimeoutSeconds});if($Arguments-contains'controlled-failure'){throw 'controlled governed interruption'};[IO.File]::WriteAllText((Join-Path $run 'factorio-current.log'),'controlled native log');[pscustomobject]@{stdout=$tinActorStdout;stderr=$tinActorStderr;result=@{duration_seconds=0.01}}}
    function Get-MIRNativeProbeRemainingOutputBytes {param($Context);return 1MB}
    $save=Join-Path $run 'owned-save.zip';[IO.File]::WriteAllText($save,'controlled saved state')
    $reload=Invoke-TinBoundedReload -Factorio $engine -RunRoot $run -Scenario controlled -SavePath $save -Ticks 30000 -TimeoutSeconds 240
    Assert-Probe ($reload.passed-and$reload.save_byte_identical-and$reload.benchmark_ticks-eq30000) 'Tin continuation lost saved-state and tick bounds.'
    Assert-Probe ($calls.Count-eq1-and$calls[0].context.controlled-and$calls[0].path-ceq$engine-and$calls[0].timeout-eq240-and'--benchmark-sanitize'-in$calls[0].arguments) 'Tin continuation bypassed governor or changed reload arguments.'
    Refuses-Probe {Invoke-TinGovernedEngine -Scenario refused -Arguments @('controlled-failure') -TimeoutSeconds 240} 'controlled governed interruption'
    Assert-Probe (-not(Test-Path -LiteralPath (Join-Path $run 'refused.factorio.log'))) 'Tin continuation wrote a successful log after interruption.'
    $function=@($k2Ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Invoke-MIRCompatFactorioProcess'},$false))
    Assert-Probe ($function.Count-eq1) 'K2 continuation governed collector adapter absent.'
    . ([scriptblock]::Create($function[0].Extent.Text))
    $controlledEngine=Join-Path $run 'engine/bin/x64/factorio.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $controlledEngine),(Join-Path $run 'engine/data'),(Join-Path $run 'saves')|Out-Null
    [IO.File]::WriteAllText($controlledEngine,'controlled actor locator; not an executable')
    $data=Join-Path $run 'engine/data'
    New-Item -ItemType Directory -Path (Join-Path $data 'base')|Out-Null
    [IO.File]::WriteAllText((Join-Path $data 'base/info.json'),'{"name":"base","version":"2.1.20","dependencies":[]}')
    $profilePath=Join-Path $run 'selection.json'
    [IO.File]::WriteAllText($profilePath,'{"mods":[{"name":"base","version":"2.1.20","enabled":true},{"name":"controlled-k2","version":"1.0.0","enabled":true}]}')
    $activation=Start-MIRLibraryActivation -LibraryDirectory $flat -EngineDataDirectory $data -ProfilePath $profilePath -ArchiveHashes @{'controlled-k2_1.0.0.zip'=(Get-K2213Sha256 $dependency)}
    $calls.Clear();$budgets=[Collections.Generic.List[object]]::new()
    function Get-MIRNativeProbeRemainingOutputBytes {param($Context);$budgets.Add($Context);return 1MB}
    function Invoke-MIRNativeProbeFactorioProcess {
      param($Context,$FilePath,$Arguments,$TimeoutSeconds)
      $calls.Add(@{context=$Context;path=$FilePath;arguments=$Arguments;timeout=$TimeoutSeconds})
      if($Arguments-contains'controlled-failure'){throw 'controlled governed interruption'}
      $index=[Array]::IndexOf($Arguments,'--create')
      if($index-ge0){[IO.File]::WriteAllText($Arguments[$index+1],'controlled save; not Factorio data');$marker='initial'}else{$marker='reload'}
      $lines=@($activation.selected|ForEach-Object {'0.1 Loading mod '+$_.name+' '+$_.version+' (data.lua)'})
      $lines+=('[MIR42_K2_213_IMERSITE_CONTINUATION] stage='+$marker+';completed_level=4;next_level=5;bonus=0.08;progress=0.42')
      [IO.File]::WriteAllLines((Join-Path $run 'factorio-current.log'),$lines)
      [pscustomobject]@{stdout=$tinActorStdout;stderr=$tinActorStderr;result=@{passed=$true;exit_code=0;timed_out=$false;duration_seconds=0.01}}
    }
    try {
    $create=Invoke-MIRFactorioLoadCheck -FactorioBin $controlledEngine -UserDataDir $run -ScenarioName controlled-k2 -ScenarioTimeoutSeconds 90 -LibraryActivation $activation
    $reload=Invoke-MIRFactorioReloadContract -FactorioBin $controlledEngine -UserDataDir $run -ScenarioName controlled-k2 -SavePath $create.save -RequiredReloadCount 1 -MaxReloadDurationSeconds 90 -RequiredLogFragments '[MIR42_K2_213_IMERSITE_CONTINUATION] stage=reload;completed_level=4;next_level=5;bonus=0.08;progress=0.42' -LibraryActivation $activation
    Assert-Probe ($create.passed-and$reload.passed-and$calls.Count-eq2-and$budgets.Count-eq2) 'K2 create/reload collectors did not use the shared governed row.'
    Assert-Probe ($calls[0].context.controlled-and$calls[1].context.controlled-and$calls[0].path-ceq$controlledEngine-and$calls[0].timeout-eq90-and$calls[1].timeout-eq90) 'K2 collector lost actor/context/timeout identity.'
    Assert-Probe ('--create'-in$calls[0].arguments-and'--benchmark'-in$calls[1].arguments-and'--benchmark-sanitize'-in$calls[1].arguments-and$reload.reloads[0].save_byte_identical) 'K2 native create/reload arguments or saved-state custody changed.'
    Assert-Probe ($create.stderr_sha256-ceq'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'-and$reload.reloads[0].reload_log_contract_passed) 'K2 collector lost stderr or exact reload-marker checks.'
    $refusedOut=Join-Path $run 'k2-refused.stdout';$refusedErr=Join-Path $run 'k2-refused.stderr'
    Refuses-Probe {Invoke-MIRCompatFactorioProcess -FactorioBin $controlledEngine -ArgumentList @($calls[0].arguments+'controlled-failure') -StdoutPath $refusedOut -StderrPath $refusedErr -TimeoutSeconds 90 -LibraryActivation $activation} 'controlled governed interruption'
    Assert-Probe ($budgets.Count-eq2-and-not(Test-Path -LiteralPath $refusedOut)-and-not(Test-Path -LiteralPath $refusedErr)) 'K2 collector continued or wrote success after governed interruption.'
    } finally {$null=Complete-MIRLibraryActivation $activation}
  }
  $auditRun=Join-Path $fixture 'material-audit';New-Item -ItemType Directory -Path $auditRun|Out-Null
  $auditLease=New-MIRMaterialAuditInputLease -RunRoot $auditRun -ModsDirectory (Join-Path $auditRun 'mods') -CandidateArchive $auditCandidate -DependencyDirectory $fixture -ExpectedArchives ([ordered]@{'dependency.zip'=$archiveInput.expected_sha256})
  try{
    Assert-Probe ($auditLease.record.require_hard_links-and$auditLease.record.inputs.Count-eq 2) 'material audit did not require strict candidate/dependency inputs.'
    foreach($input in $auditLease.record.inputs){Assert-Probe ((Get-MIRImmutableInputFileIdentity $input.source_path)-ceq(Get-MIRImmutableInputFileIdentity $input.stage_path)) 'material audit copied an archive.'}
    $auditTerminal=Complete-MIRImmutableInputLease -Lease $auditLease
    $null=Assert-MIRImmutableInputTerminalReceipt -Receipt $auditTerminal
    Assert-Probe (($auditTerminal.inputs.role-join'|')-ceq'candidate|dependency-mod') 'material audit lost candidate/dependency roles.'
  }finally{if(-not$auditLease.closed){$null=Complete-MIRImmutableInputLease -Lease $auditLease -Outcome failed}}
  $badRun=Join-Path $fixture 'material-audit-invalid'
  Refuses-Probe {New-MIRMaterialAuditInputLease -RunRoot $badRun -ModsDirectory (Join-Path $badRun 'mods') -CandidateArchive $auditCandidate -DependencyDirectory $fixture -ExpectedArchives ([ordered]@{'dependency.zip'=('0'*64)})} 'dependency-hash'
  Assert-Probe (-not(Test-Path -LiteralPath $badRun)) 'material audit allocated before exact dependency validation.'
  Refuses-Probe {New-MIRMaterialAuditInputLease -RunRoot $badRun -ModsDirectory (Join-Path $badRun 'mods') -CandidateArchive $auditCandidate -DependencyDirectory $fixture -ExpectedArchives ([ordered]@{'absent.zip'=$archiveInput.expected_sha256})} 'dependency-missing'
  . (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
  $compatMods=Join-Path $fixture 'compat-mods';New-Item -ItemType Directory -Path $compatMods | Out-Null
  $compatEntry=[pscustomobject]@{file_name='dependency.zip';source_path=$source;sha256=$archiveInput.expected_sha256}
  Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($compatEntry)
  Assert-Probe ((Get-MIRImmutableInputFileIdentity (Join-Path $compatMods 'dependency.zip')) -ceq (Get-MIRImmutableInputFileIdentity $source)) 'compatibility staging copied a shared archive.'
  Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($compatEntry)
  Assert-Probe ((Get-MIRImmutableInputSha256 $source) -ceq $compatEntry.sha256) 'matching alias reuse changed canonical bytes.'
  Refuses-Probe {Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($compatEntry) -LinkMode Copy} 'Hardlink'
  Refuses-Probe {Copy-MIRModUnderTest -RepoRoot $repo -ModsDir $compatMods} 'package-required'
  $badEntry=[pscustomobject]@{file_name='../outside.zip';source_path=$source}
  Refuses-Probe {Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($badEntry)} 'archive-name'
  $badEntry=[pscustomobject]@{file_name='missing.zip';source_path=(Join-Path $fixture 'missing.zip')}
  Refuses-Probe {Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($badEntry)} 'archive-missing'
  $badEntry=[pscustomobject]@{file_name='wrong-hash.zip';source_path=$source;sha256=('0'*64)}
  Refuses-Probe {Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($badEntry)} 'archive-hash'
  [IO.File]::WriteAllBytes((Join-Path $compatMods 'unrelated.zip'),[byte[]]::new(16))
  $badEntry=[pscustomobject]@{file_name='unrelated.zip';source_path=$source}
  Refuses-Probe {Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $compatMods -LockEntries @($badEntry)} 'archive-alias'
  $packageMods=Join-Path $fixture 'compat-package';New-Item -ItemType Directory -Path $packageMods | Out-Null
  $linkedPackage=Copy-MIRModUnderTest -RepoRoot $repo -ModsDir $packageMods -ZipPath $source
  Assert-Probe ((Get-MIRImmutableInputFileIdentity $linkedPackage) -ceq (Get-MIRImmutableInputFileIdentity $source)) 'mod-under-test ZIP was copied.'
  $sharedLibraryArchive=Join-Path $fixture 'dependency_1.zip'
  New-Item -ItemType HardLink -Path $sharedLibraryArchive -Target $source | Out-Null
  $controlledDescriptor=[pscustomobject]@{line='controlled';target='controlled';inputs=@([pscustomobject]@{name='dependency';version='1';sha256=$archiveInput.expected_sha256})}
  $configuredInputs=@(Resolve-MIR421SpaceFakeUpgradeInputs -RepoRoot $fixture -Descriptor $controlledDescriptor -LocalModLibraryDirs @((Join-Path $fixture 'absent-library'),$fixture))
  Assert-Probe ($configuredInputs.Count -eq 1 -and $configuredInputs[0].source_path -ceq $sharedLibraryArchive) 'SIF inputs did not resolve the retained shared library.'
  Assert-Probe (-not (Test-Path -LiteralPath (Join-Path $fixture 'build/tmp/mir421-sif-input-lookup-controlled'))) 'SIF library lookup created a profile.'
  Refuses-Probe {Resolve-MIR421SpaceFakeUpgradeInputs -RepoRoot $fixture -Descriptor $controlledDescriptor -LocalModLibraryDirs @((Join-Path $fixture 'absent-library'))} 'dependency-missing'
  $emptyStage=Join-Path $fixture 'empty-preserved-stage'
  $lookup=Resolve-MIRNativeProbeDependencyInputs -StageRoot $emptyStage -ExpectedArchives @{'dependency.zip'=$archiveInput.expected_sha256} -LocalModLibraryDirs @($fixture)
  Assert-Probe ($lookup['dependency.zip'].source_path -ceq $source -and $lookup['dependency.zip'].provenance_kind -ceq 'verified-local-dependency-library' -and -not (Test-Path -LiteralPath $emptyStage)) 'missing-stage lookup failed or restored a staging copy.'
  $flatOnly=Resolve-MIRNativeProbeDependencyInputs -ExpectedArchives @{'dependency.zip'=$archiveInput.expected_sha256} -LocalModLibraryDirs @($fixture)
  Assert-Probe ($flatOnly['dependency.zip'].source_path -ceq $source -and $flatOnly['dependency.zip'].provenance_kind -ceq 'verified-local-dependency-library') 'flat-only lookup needed a retained profile.'
  Refuses-Probe {Resolve-MIRNativeProbeDependencyInputs -StageRoot $emptyStage -ExpectedArchives @{'dependency.zip'=$archiveInput.expected_sha256}} 'dependency-missing'
  $lookupStage=Join-Path $fixture 'lookup-stage';New-Item -ItemType Directory -Path (Join-Path $lookupStage 'mods')|Out-Null
  $stageArchive=Join-Path $lookupStage 'mods/dependency.zip';[IO.File]::Copy($source,$stageArchive)
  $lookup=Resolve-MIRNativeProbeDependencyInputs -StageRoot $lookupStage -ExpectedArchives @{'dependency.zip'=$archiveInput.expected_sha256} -LocalModLibraryDirs @($fixture)
  Assert-Probe ($lookup['dependency.zip'].source_path -ceq $stageArchive -and $lookup['dependency.zip'].provenance_kind -ceq 'exact-preserved-stage') 'verified original stage did not retain priority.'
  [IO.File]::WriteAllText($stageArchive,'controlled wrong stage bytes')
  Refuses-Probe {Resolve-MIRNativeProbeDependencyInputs -StageRoot $lookupStage -ExpectedArchives @{'dependency.zip'=$archiveInput.expected_sha256} -LocalModLibraryDirs @($fixture)} 'dependency-hash'
  Refuses-Probe {Resolve-MIRNativeProbeDependencyInputs -StageRoot $emptyStage -ExpectedArchives @{'../dependency.zip'=$archiveInput.expected_sha256} -LocalModLibraryDirs @($fixture)} 'dependency-identity'
  $leaseRoot=Join-Path $context.root 'stage';New-Item -ItemType Directory -Path $leaseRoot | Out-Null
  Refuses-Probe {New-MIRImmutableInputLease -RunRoot $leaseRoot -StageDirectory (Join-Path $leaseRoot 'mods') -Inputs @($archiveInput) -RequireHardLinks -ForceCopy} 'cannot request copy mode'
  $lease=New-MIRImmutableInputLease -RunRoot $leaseRoot -StageDirectory (Join-Path $leaseRoot 'mods') -Inputs @($archiveInput) -RequireHardLinks
  Assert-Probe ((Get-MIRUpgradeLinkedArchiveBytes -Lease $lease) -eq 128KB) 'SIF byte allowance was not backed by the actual strict hardlink lease.'
  Add-MIRNativeProbeImmutableLease -Context $context -Lease $lease
  Assert-Probe ($context.shared_alias_bytes -eq 128KB) 'strict leased alias bytes were not identified.'
  Refuses-Probe {Add-MIRNativeProbeImmutableLease -Context $context -Lease $lease} 'shared-alias-identity'
  Assert-Probe ($context.shared_alias_bytes -eq 128KB) 'duplicate registration widened the byte exemption.'
  $before=Get-MIRNativeProbeRemainingOutputBytes -Context $context
  $budgetFile=Join-Path $context.root 'new-output.bin'
  [IO.File]::WriteAllBytes($budgetFile,[byte[]]::new(64KB))
  Assert-Probe ((Get-MIRNativeProbeRemainingOutputBytes -Context $context) -eq $before-64KB) 'ordinary new output escaped the cumulative row budget.'
  [IO.File]::WriteAllBytes($budgetFile,[byte[]]::new(1MB))
  Refuses-Probe {Get-MIRNativeProbeRemainingOutputBytes -Context $context} 'resource-output-budget'
  Remove-Item -LiteralPath $budgetFile
  $pwsh=(Get-Command pwsh).Source
  $run=Invoke-MIRNativeProbeProcess -Context $context -FilePath $pwsh -Arguments @('-NoProfile','-Command','Write-Output $env:TEMP') -TimeoutSeconds 20
  Assert-Probe ($run.result.passed -and (Test-Path -LiteralPath $run.ledger)) 'actual owned small process did not retain its resource ledger.'
  $privateTemp=(Get-Content -LiteralPath $run.stdout -Raw).Trim()
  Assert-Probe ((Test-MIR441PathContained -Root $context.root -Path $privateTemp) -and -not (Test-Path -LiteralPath $privateTemp)) 'process temp was not isolated and retired.'
  Refuses-Probe {Invoke-MIRNativeProbeProcess -Context $context -FilePath $pwsh -Arguments @('-NoProfile','-Command','exit 7') -TimeoutSeconds 20} 'mir441-process-exit'
  Assert-Probe ($context.runs[$context.runs.Count-1].status -ceq 'interrupted' -and (Test-Path -LiteralPath $context.runs[$context.runs.Count-1].ledger)) 'failed actor lost its ledger reference.'
  $terminal=Complete-MIRImmutableInputLease -Lease $lease -Outcome passed
  $lease=$null
  Assert-Probe ($terminal.state -ceq 'completed' -and $terminal.inputs_sha256_match) 'strict lease did not retain verified terminal custody.'

  # Two upgrade phases share dependency/archive bytes and keep distinct custody.
  # These tiny text inputs exercise staging; they are not Factorio packages.
  $sourceProfileLease=$null;$candidateProfileLease=$null;$plainProfileLease=$null
  try {
    $sourceArchive=Join-Path $fixture 'more-infinite-research_4.2.20000.zip'
    $candidateArchive=Join-Path $fixture 'more-infinite-research_4.2.20001.zip'
    [IO.File]::WriteAllText($sourceArchive,'controlled predecessor')
    [IO.File]::WriteAllText($candidateArchive,'controlled candidate')
    $sourceProfileLease=New-MIRUpgradeLinkedProfile -RunRoot (Join-Path $context.root 'source-profile') -Dependencies @($archiveInput) -Archive $sourceArchive -ExpectedSha256 (Get-MIRImmutableInputSha256 $sourceArchive) -Version '4.2.20000' -Role source
    $sourceBytes=Get-MIRUpgradeLinkedArchiveBytes -Lease $sourceProfileLease
    $null=Complete-MIRImmutableInputLease -Lease $sourceProfileLease -Outcome passed
    Assert-Probe ((Get-MIRUpgradeLinkedArchiveBytes -Lease $sourceProfileLease) -eq $sourceBytes) 'completed source-profile aliases lost their verified byte accounting.'
    $candidateProfileLease=New-MIRUpgradeLinkedProfile -RunRoot (Join-Path $context.root 'candidate-profile') -Dependencies @($archiveInput) -Archive $candidateArchive -ExpectedSha256 (Get-MIRImmutableInputSha256 $candidateArchive) -Version '4.2.20001' -Role candidate
    Assert-Probe (@($candidateProfileLease.record.inputs | Where-Object staging_mode -CNE 'hardlink').Count -eq 0) 'candidate profile copied an archive.'
    Assert-Probe (-not (Test-Path -LiteralPath (Join-Path $candidateProfileLease.record.stage_directory 'more-infinite-research_4.2.20000.zip'))) 'candidate profile retained the obsolete MIR version.'
    $sourceMods=$sourceProfileLease.record.stage_directory;$targetMods=$candidateProfileLease.record.stage_directory
    New-Item -ItemType Directory -Path (Join-Path $sourceMods 'controlled-fixture') | Out-Null
    [IO.File]::WriteAllText((Join-Path $sourceMods 'controlled-fixture/control.lua'),'controlled fixture')
    $settingsPath=Join-Path $sourceMods 'mod-settings.dat'
    [IO.File]::WriteAllBytes($settingsPath,[byte[]](1,2,3,4))
    $settingsHash=Get-MIRImmutableInputSha256 $settingsPath
    Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName 'controlled-fixture'
    Assert-Probe ((Get-MIRImmutableInputSha256 (Join-Path $targetMods 'mod-settings.dat')) -ceq $settingsHash -and -not (Test-Path -LiteralPath $settingsPath)) 'profile switch lost or duplicated writable settings.'
    Assert-Probe (Test-Path -LiteralPath (Join-Path $targetMods 'controlled-fixture/control.lua')) 'profile switch lost the specialized fixture.'
    Refuses-Probe {Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName '../outside'} 'move-boundary'
    Refuses-Probe {Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $fixture -FixtureName 'controlled-fixture'} 'move-boundary'
    Refuses-Probe {Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName 'controlled-fixture'} 'fixture-missing'
    New-Item -ItemType Directory -Path (Join-Path $sourceMods 'controlled-fixture') | Out-Null
    Refuses-Probe {Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName 'controlled-fixture'} 'state-collision'
    New-Item -ItemType Directory -Path (Join-Path $sourceMods 'settings-collision-fixture') | Out-Null
    [IO.File]::WriteAllBytes($settingsPath,[byte[]](5,6,7,8))
    Refuses-Probe {Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName 'settings-collision-fixture'} 'state-collision'
    Assert-Probe (Test-Path -LiteralPath (Join-Path $sourceMods 'settings-collision-fixture')) 'settings collision partially moved the fixture.'
    $null=Complete-MIRImmutableInputLease -Lease $candidateProfileLease -Outcome passed
    $plainProfileLease=New-MIRUpgradeLinkedProfile -RunRoot (Join-Path $context.root 'plain-profile') -Dependencies @() -Archive $candidateArchive -ExpectedSha256 (Get-MIRImmutableInputSha256 $candidateArchive) -Version '4.2.20001' -Role candidate
    Assert-Probe ($plainProfileLease.record.inputs.Count -eq 1 -and $plainProfileLease.record.inputs[0].staging_mode -ceq 'hardlink') 'base-only upgrade copied its archive or required a mod-set profile.'
    $plainMods=$plainProfileLease.record.stage_directory
    New-Item -ItemType Directory -Path (Join-Path $plainMods 'controlled-fixture_1.0.0') | Out-Null
    Move-MIRUpgradeProfileState -RunRoot $context.root -SourceMods $plainMods -TargetMods $targetMods -FixtureName 'controlled-fixture_1.0.0'
    Assert-Probe (Test-Path -LiteralPath (Join-Path $targetMods 'controlled-fixture_1.0.0')) 'versioned historical fixture directory did not survive a profile switch.'
    $null=Complete-MIRImmutableInputLease -Lease $plainProfileLease -Outcome passed
    $sourceProfileLease.record.outcome='failed'
    Refuses-Probe {Get-MIRUpgradeLinkedArchiveBytes -Lease $sourceProfileLease} 'completed passed'
  } finally {
    foreach ($profileLease in @($sourceProfileLease,$candidateProfileLease,$plainProfileLease)) {
      if ($null -ne $profileLease -and -not $profileLease.closed) { Close-MIRImmutableInputLeaseHandles -Lease $profileLease }
    }
  }

  # Exercise the production driver and process adapter with a tiny fake
  # materializer dependency. There is no Git clone or actual player package.
  $fakeRepo=Join-Path $fixture 'driver-fixture'
  $library=Join-Path $fakeRepo 'tools/mir/application/package/TargetMaterializer.ps1'
  New-Item -ItemType Directory -Path (Split-Path -Parent $library) | Out-Null
  $stub=@'
function New-MIR4TargetPackage {
  param([string]$RepoRoot,[string]$Target,[string]$CandidateId,[string]$SourceVersion,[string]$DistributionVersion,[string]$OutputRoot)
  if($CandidateId -cnotmatch '^[A-Z0-9][A-Z0-9.-]*$') { throw 'candidate id outside canonical contract' }
  [pscustomobject]@{target=$Target;candidate_id=$CandidateId;source_version=$SourceVersion;distribution_version=$DistributionVersion;output=[IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputRoot));actual_package=$false}
}
'@
  [IO.File]::WriteAllText($library,$stub,[Text.UTF8Encoding]::new($false))
  $package=New-MIRNativeProbeTargetPackage -Context $context -RepoRoot $fakeRepo
  Assert-Probe ($package.source_version -ceq '4.2.1' -and $package.distribution_version -ceq '4.2.21001' -and $package.target -ceq 'f210') 'driver lost the required patch/target identity.'
  Assert-Probe ($package.output -ceq (Join-Path $context.root 'packages') -and -not $package.actual_package) 'driver output escaped its row or fixture became a real materializer.'
  $finalPackage=New-MIRNativeProbeTargetPackage -Context $context -RepoRoot $fakeRepo -CandidatePrefix 'F210-CURRENT-BA-FINAL-ROUTES-OBSERVER'
  Assert-Probe ($finalPackage.candidate_id -cmatch '^F210-CURRENT-BA-FINAL-ROUTES-OBSERVER-[0-9A-F]{8}$' -and $finalPackage.distribution_version -ceq '4.2.21001' -and -not $finalPackage.actual_package) 'final observer driver lost its candidate or patch identity.'
  Refuses-Probe {New-MIRNativeProbeTargetPackage -Context $context -RepoRoot $fakeRepo -Target f200} 'observer-target'
  foreach($target in @('f210','f200')) {
    $browserPackage=New-MIRNativeProbeTargetPackage -Context $context -RepoRoot $fakeRepo -Target $target -CandidatePrefix BROWSER
    $browserIdentity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $target.Substring(1) -SourceMinor 2 -SourcePatch 1
    Assert-Probe ($browserPackage.target -ceq $target -and $browserPackage.source_version -ceq '4.2.1' -and $browserPackage.distribution_version -ceq $browserIdentity.distribution_version -and $browserPackage.candidate_id.StartsWith($target.ToUpperInvariant()+'-BROWSER-') -and -not $browserPackage.actual_package) "browser driver lost the exact $target source-patch or target identity."
  }
  $echo=Join-Path $context.root 'argv-echo.ps1'
  [IO.File]::WriteAllText($echo,@'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Values)
[ordered]@{values=@($Values);steam_app=$env:SteamAppId;steam_game=$env:SteamGameId;temp=$env:TEMP} | ConvertTo-Json -Compress
'@,[Text.UTF8Encoding]::new($false))
  $parentApp=[Environment]::GetEnvironmentVariable('SteamAppId');$parentGame=[Environment]::GetEnvironmentVariable('SteamGameId')
  $literalValues=@('path with spaces','literal $(Get-Process) ; "quote" & marker','Unicode: π')
  $nativeActor=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $pwsh -Arguments (@('-NoProfile','-File',$echo)+$literalValues) -TimeoutSeconds 30
  $echoed=Get-Content -LiteralPath $nativeActor.stdout -Raw | ConvertFrom-Json
  Assert-Probe (($echoed.values | ConvertTo-Json -Compress) -ceq ($literalValues | ConvertTo-Json -Compress)) 'native wrapper changed literal argument data.'
  Assert-Probe ($echoed.steam_app -ceq '427520' -and $echoed.steam_game -ceq '427520' -and [Environment]::GetEnvironmentVariable('SteamAppId') -ceq $parentApp -and [Environment]::GetEnvironmentVariable('SteamGameId') -ceq $parentGame) 'Steam launch identifiers escaped the owned child.'
  Assert-Probe ((Test-MIR441PathContained -Root $context.root -Path $echoed.temp) -and -not (Test-Path -LiteralPath $echoed.temp) -and (Test-Path -LiteralPath $nativeActor.ledger)) 'native wrapper bypassed the private-temp or resource ledger authority.'
  $priorIndex=$context.process_index
  Refuses-Probe {Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $pwsh -Arguments @('x'*20KB)} 'argument-budget'
  Assert-Probe ($context.process_index -eq $priorIndex) 'oversized argument data launched an actor.'
  Write-MIRNativeProbeResult -Context $context -Record @{status='controlled-passed';native_factorio=$false;actual_materialization=$false;actor_count=$context.runs.Count}
  Assert-Probe ((Get-Content -LiteralPath (Join-Path $context.root 'result.json') -Raw | ConvertFrom-Json).actor_count -eq 7) 'reserved result did not preserve actual actor inventory.'
  $resultPath=Join-Path $context.root 'result.json';Remove-Item -LiteralPath $resultPath
  [IO.File]::WriteAllBytes($budgetFile,[byte[]]::new(960KB))
  Refuses-Probe {Write-MIRNativeProbeResult -Context $context -Record @{payload=('x'*128KB)}} 'resource-output-budget'
  Assert-Probe (-not (Test-Path -LiteralPath $resultPath)) 'oversized result was written as success.'
  # A missing shared alias must refuse even when other output masks the
  # subtraction in the logical tree total. The strict lease is closed here.
  Remove-Item -LiteralPath $context.aliases[0].stage_path
  Refuses-Probe {Get-MIRNativeProbeRemainingOutputBytes -Context $context} 'shared-alias-identity'
  Assert-Probe ((Get-MIRImmutableInputSha256 $source) -ceq $archiveInput.expected_sha256) 'alias retirement changed its canonical archive.'

  # Test the actual completed-row custody reader with synthetic archives,
  # three tiny pwsh actors and a dummy log/save. This is not a native oracle.
  $parseTokens=$null;$parseErrors=$null
  $observerPath=Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelFinalRoutesObserver.ps1'
  $observerAst=[Management.Automation.Language.Parser]::ParseFile($observerPath,[ref]$parseTokens,[ref]$parseErrors)
  Assert-Probe ($parseErrors.Count -eq 0) 'final observer syntax differs.'
  foreach($name in @('Assert-Observer','Get-ObserverSha','Get-ObserverArtifact','Get-ObserverZipInfo','Get-ObserverCompletedRecovery')) {
    $definitions=@($observerAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false))
    Assert-Probe ($definitions.Count -eq 1) "expected one actual recovery function: $name"
    . ([scriptblock]::Create($definitions[0].Extent.Text))
  }
  $recoveryContext=New-MIRNativeProbeResourceContext @arguments -ExpectedPeakMemoryMiB 1024
  $recoveryRoot=$recoveryContext.root
  New-Item -ItemType Directory -Path (Join-Path $recoveryRoot 'packages'),(Join-Path $recoveryRoot 'userdata'),(Join-Path $recoveryRoot 'stage')|Out-Null
  $syntheticCandidate=Join-Path $recoveryRoot 'packages/more-infinite-research_4.2.21001.zip'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipFile]::Open($syntheticCandidate,[IO.Compression.ZipArchiveMode]::Create)
  try {$entry=$zip.CreateEntry('more-infinite-research_4.2.21001/info.json');$writer=[IO.StreamWriter]::new($entry.Open());try {$writer.Write('{"name":"more-infinite-research","version":"4.2.21001","factorio_version":"2.1"}')}finally{$writer.Dispose()}}finally{$zip.Dispose()}
  $candidateInput=[ordered]@{source_path=$syntheticCandidate;file_name=[IO.Path]::GetFileName($syntheticCandidate);expected_sha256=Get-MIRImmutableInputSha256 $syntheticCandidate;role='candidate';identity=@{fixture='synthetic-archive-only'};provenance=@{kind='controlled-parser-fixture'};immutable=$true}
  $lease=New-MIRImmutableInputLease -RunRoot (Join-Path $recoveryRoot 'stage') -StageDirectory (Join-Path $recoveryRoot 'stage/mods') -Inputs @($candidateInput,$archiveInput) -RequireHardLinks
  Add-MIRNativeProbeImmutableLease -Context $recoveryContext -Lease $lease
  foreach($number in 1..3){$null=Invoke-MIRNativeProbeProcess -Context $recoveryContext -FilePath $pwsh -Arguments @('-NoProfile','-Command','Write-Output controlled-recovery-parser-actor') -TimeoutSeconds 20}
  $terminal=Complete-MIRImmutableInputLease -Lease $lease -Outcome passed;$lease=$null
  # A serialized custody control with significant trailing timestamp zeros
  # must retain its exact strings through the reader's JSON round trip.
  foreach($name in @('started_utc','receipt_captured_utc','completed_utc')) {$terminal.$name='2026-10-04T00:00:00.1200000Z'}
  $terminal.terminal_record_sha256=Get-MIRImmutableInputRecordSha256 -Record $terminal
  $dummyLog=Join-Path $recoveryRoot 'userdata/factorio-current.log';[IO.File]::WriteAllText($dummyLog,'controlled custody fixture; no native engine or final oracle')
  $dummySave=Join-Path $recoveryRoot 'observer.zip';[IO.File]::WriteAllText($dummySave,'controlled custody fixture; not a Factorio save')
  $syntheticSourceManifest=Join-Path $recoveryRoot 'controlled-source-manifest.json'
  [IO.File]::WriteAllText($syntheticSourceManifest,'{"controlled_parser_fixture":true,"native_proof":false}')
  $recoverySource=[ordered]@{commit='controlled-source';tree='controlled-tree';package_source_sha256=$archiveInput.expected_sha256;source_manifest_sha256=Get-ObserverSha $syntheticSourceManifest;source_version='4.2.1';distribution_version='4.2.21001'}
  $fixtureDirectory=Join-Path $repo 'fixtures/assert-f210-current-bob-angel-final-routes-observer'
  $lastActor=$recoveryContext.runs[2]
  $controlledRecord=[ordered]@{
    schema=2;kind='MIR4F210CurrentBobAngelFinalRoutesObservationV1';status='observed';run_root=$recoveryRoot;source=$recoverySource
    harness=Get-ObserverArtifact $observerPath;exact_stage=@{receipt_sha256=Get-ObserverSha $source;engine_sha256=Get-ObserverSha $pwsh}
    engine=@{executable_sha256=Get-ObserverSha $pwsh;version='Version: 2.1.20 controlled-parser-fixture'}
    fixture=@('info.json','data-final-fixes.lua','control.lua','material-outcome-inventory.lua'|ForEach-Object{Get-ObserverArtifact (Join-Path $fixtureDirectory $_)})
    candidate=Get-ObserverArtifact $syntheticCandidate;input_lease=$terminal;resource_runs=$recoveryContext.runs.ToArray()
    logs=@{stdout=Get-ObserverArtifact $lastActor.stdout;stderr=Get-ObserverArtifact $lastActor.stderr;factorio=Get-ObserverArtifact $dummyLog};save=Get-ObserverArtifact $dummySave
  }
  $recoveryArguments=@{RunRoot=$recoveryRoot;OutputRoot=$fixture;Source=$recoverySource;Fixture=$fixtureDirectory;HarnessPath=$observerPath;StageReceiptPath=$source;ExpectedArchives=@{'dependency.zip'=$archiveInput.expected_sha256};Engine=$pwsh}
  Write-MIRNativeProbeResult -Context $recoveryContext -Record $controlledRecord
  $rowPath=Join-Path $recoveryRoot 'result.json';$rowHash=Get-ObserverSha $rowPath
  $recovered=Get-ObserverCompletedRecovery @recoveryArguments
  Assert-Probe ($recovered.source.distribution_version -ceq '4.2.21001' -and (Get-ObserverSha $rowPath) -ceq $rowHash) 'completed custody replay wrote its historical receipt.'
  Assert-Probe ($recovered.source.source_manifest_sha256 -ceq (Get-ObserverSha $syntheticSourceManifest) -and $recovered.source.source_manifest_sha256 -cne $recovered.source.package_source_sha256) 'controlled recovery conflated manifest custody with its package fingerprint.'
  Assert-Probe ($recovered.input_lease.started_utc -is [string] -and $recovered.input_lease.started_utc -ceq '2026-10-04T00:00:00.1200000Z') 'recovery normalized a timestamp covered by its custody hash.'
  $fallbackRecovered=& {
    function Get-Command {
      param([string]$Name)
      if($Name -ceq 'ConvertFrom-Json'){return [pscustomobject]@{Parameters=@{}}}
      Microsoft.PowerShell.Core\Get-Command $Name
    }
    Get-ObserverCompletedRecovery @recoveryArguments
  }
  Assert-Probe ($fallbackRecovered.input_lease.started_utc -ceq '2026-10-04T00:00:00.1200000Z' -and (Get-ObserverSha $rowPath) -ceq $rowHash) 'older-PowerShell recovery fallback altered timestamp custody or wrote the receipt.'
  foreach($case in @(
    @{change={$args[0].schema=1};error='completed governed observation'},
    @{change={$args[0].source.distribution_version='4.2.21002'};error='source fingerprint differs'},
    @{change={$args[0].source.package_source_sha256=('A'*64)};error='source fingerprint differs'},
    @{change={$args[0].source.source_manifest_sha256=('A'*64)};error='source fingerprint differs'},
    @{change={$args[0].harness.sha256=('A'*64)};error='harness fingerprint differs'},
    @{change={$args[0].fixture=$args[0].fixture[0..2]};error='fixture inventory differs'},
    @{change={$args[0].input_lease.outcome='failed'};error='completed passed immutable-input receipt'},
    @{change={$args[0].resource_runs[2].index=2};error='duplicated identity'},
    @{change={$args[0].logs.factorio.sha256=('A'*64)};error='log custody differs'},
    @{change={$args[0].save.sha256=('A'*64)};error='save custody differs'}
  )) {
    $changed=($controlledRecord|ConvertTo-Json -Depth 30)|ConvertFrom-Json -AsHashtable -Depth 30
    foreach($name in @('started_utc','receipt_captured_utc','completed_utc')) {$changed.input_lease[$name]=$terminal.$name}
    & $case.change $changed
    Write-MIRNativeProbeResult -Context $recoveryContext -Record $changed
    Refuses-Probe {Get-ObserverCompletedRecovery @recoveryArguments} $case.error
  }
  Assert-Probe ((Get-MIRImmutableInputSha256 $source) -ceq $archiveInput.expected_sha256) 'controlled recovery changed a canonical input.'

  $browserJob=Join-Path $fixture 'browser-lifecycle'
  $mirInput=[ordered]@{};foreach($entry in $archiveInput.GetEnumerator()){$mirInput[$entry.Key]=$entry.Value};$mirInput.role='mir-candidate';$mirInput.file_name='more-infinite-research_4.2.20001.zip'
  $fixtureInput=[ordered]@{};foreach($entry in $archiveInput.GetEnumerator()){$fixtureInput[$entry.Key]=$entry.Value};$fixtureInput.role='continuity-fixture';$fixtureInput.file_name='continuity-fixture.zip'
  $profileInputs=@($mirInput,$fixtureInput)
  $profile=New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase initial -Inputs $profileInputs
  Assert-Probe ((Get-MIRImmutableInputFileIdentity (Join-Path $profile.mods $mirInput.file_name)) -ceq (Get-MIRImmutableInputFileIdentity $source)) 'browser lifecycle initial profile copied its archive.'
  [IO.File]::WriteAllText((Join-Path $profile.mods 'mod-settings.dat'),'private settings')
  Refuses-Probe {New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase configured -Inputs @($archiveInput) -PreviousProfile $profile} 'previous-profile-active'
  $terminal=Complete-MIRImmutableInputLease -Lease $profile.lease -Outcome passed
  $priorSettings=Join-Path $profile.mods 'mod-settings.dat'
  foreach($phase in @('configured','removed','readded')){
    $phaseInputs=if($phase-ceq'removed'){@($profileInputs|Where-Object role -ne 'mir-candidate')}else{$profileInputs}
    $profile=New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase $phase -Inputs $phaseInputs -PreviousProfile $profile
    Assert-Probe (-not(Test-Path -LiteralPath $priorSettings) -and (Get-Content -LiteralPath (Join-Path $profile.mods 'mod-settings.dat') -Raw) -ceq 'private settings') "browser $phase copied or lost private settings."
    Assert-Probe ((Get-MIRImmutableInputFileIdentity (Join-Path $profile.mods $fixtureInput.file_name)) -ceq (Get-MIRImmutableInputFileIdentity $source)) "browser $phase lost shared archive identity."
    Assert-Probe ((Test-Path -LiteralPath (Join-Path $profile.mods $mirInput.file_name))-eq($phase-cne'removed')) "browser $phase has the wrong literal MIR presence."
    $terminal=Complete-MIRImmutableInputLease -Lease $profile.lease -Outcome passed
    $priorSettings=Join-Path $profile.mods 'mod-settings.dat'
  }
  Refuses-Probe {New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase readded -Inputs @($archiveInput) -PreviousProfile $profile} 'profile-preserved'
  Refuses-Probe {New-MIRBrowserContinuityProfile -JobRoot $browserJob -Phase '../outside' -Inputs @($archiveInput)} 'profile-phase'

  & {
    # Run the real parent/owned-child protocol with a tiny synthetic worker.
    # Existing fake capacity applies only to this child; no Factorio executes.
    $gitExecutable=@(Microsoft.PowerShell.Core\Get-Command git -CommandType Application)[0].Source
    function git {if('status'-in$args){$global:LASTEXITCODE=0;return};& $gitExecutable @args;$global:LASTEXITCODE=$LASTEXITCODE}
    $worker=Join-Path $fixture 'synthetic-browser-worker.ps1'
    $workerText=@'
param($CandidateArchive,$RepositoryRoot,$Target,$FactorioExe,$TimeoutSeconds,$StageLimit,$InputMode,$SourceVersion,$OwnedJobPath,$OwnedJobSha256)
$ErrorActionPreference='Stop'
. (Join-Path $RepositoryRoot 'tools/lib/validation/BrowserContinuityInputs.ps1')
$job=Read-MIRBrowserContinuityOwnedJob -RepositoryRoot $RepositoryRoot -ScriptPath $PSCommandPath -RequestPath $OwnedJobPath -RequestSha256 $OwnedJobSha256
$syntheticInput=[ordered]@{source_path=$CandidateArchive;file_name='synthetic-input.zip';expected_sha256=(Get-FileHash $CandidateArchive).Hash;role='synthetic-fixture';identity=@{synthetic=$true};provenance=@{kind='not-factorio'};immutable=$true}
$root=Join-Path $job.root 'worker';$profile=New-MIRBrowserContinuityProfile -JobRoot $root -Phase initial -Inputs @($syntheticInput)
$receipt=Complete-MIRImmutableInputLease -Lease $profile.lease -Outcome passed
$record=[ordered]@{schema=1;status='checkpointed';scope='synthetic actor protocol, not Factorio';source=@{harness_sha256=$job.harness_sha256};source_version=$SourceVersion;target=@{key=$Target};input_mode=$InputMode;candidate=@{archive_sha256=(Get-FileHash $CandidateArchive).Hash};stages=@(@{stage='initial'});immutable_input_receipts=@($receipt)}
[IO.File]::WriteAllText((Join-Path $root 'browser-personal-state-continuity-receipt.json'),($record|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
'@
    [IO.File]::WriteAllText($worker,$workerText,[Text.UTF8Encoding]::new($false))
    $parameters=[ordered]@{CandidateArchive=$source;RepositoryRoot=$repo;Target='F200';FactorioExe=$pwsh;TimeoutSeconds=30;StageLimit='Initial';InputMode='ScriptedFixture';SourceVersion='4.2.1'}
    $output=@(Invoke-MIRBrowserContinuityGovernedRun -RepositoryRoot $repo -ScriptPath $worker -Parameters $parameters -OutputRoot $fixture -ExpectedPeakMemoryMiB 512 -MaxNewOutputMiB 8)
    $resultPath=($output|Where-Object{$_-like'MIR_BROWSER_CONTINUITY_GOVERNED_RESULT=*'}).Substring('MIR_BROWSER_CONTINUITY_GOVERNED_RESULT='.Length)
    $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json -Depth 40 -DateKind String
    Assert-Probe ($result.status -ceq 'checkpointed' -and -not$result.release_qualification -and $result.whole_process_tree.result.passed -and $result.archive_bytes_discounted -eq 0) 'browser owned synthetic actor lost the shared governor or claimed qualification.'
    $request=Join-Path (Split-Path -Parent $resultPath) 'owned-job.json'
    Refuses-Probe {Read-MIRBrowserContinuityOwnedJob -RepositoryRoot $repo -ScriptPath $worker -RequestPath $request -RequestSha256 ('0'*64)} 'owned-request-hash'
    Refuses-Probe {Read-MIRBrowserContinuityOwnedJob -RepositoryRoot $repo -ScriptPath $worker -RequestPath $request -RequestSha256 (Get-FileHash $request).Hash} 'owned-request-binding'
    $fallback=& {
      function Get-Command {param([string]$Name) if($Name-ceq'ConvertFrom-Json'){return [pscustomobject]@{Parameters=@{}}};Microsoft.PowerShell.Core\Get-Command $Name}
      Read-MIRBrowserContinuityJson -Path $result.receipt -LeaseReceipts
    }
    $null=Assert-MIRImmutableInputTerminalReceipt -Receipt $fallback.immutable_input_receipts[0]
    Assert-Probe ($fallback.immutable_input_receipts[0].started_utc -is [string]) 'browser fallback reader normalized canonical lease timestamps.'
  }

  $failedRoot=Join-Path $fixture 'link-failure';New-Item -ItemType Directory -Path $failedRoot | Out-Null
  $copies=0
  function New-Item {
    param([string]$ItemType,[string]$Path,[string]$Target,[switch]$Force)
    if($ItemType -ceq 'HardLink') { throw 'controlled-link-failure' }
    Microsoft.PowerShell.Management\New-Item -ItemType $ItemType -Path $Path -Force:$Force
  }
  function Copy-Item { $script:copies++;throw 'copy fallback was invoked' }
  Refuses-Probe {New-MIRImmutableInputLease -RunRoot $failedRoot -StageDirectory (Join-Path $failedRoot 'mods') -Inputs @($archiveInput) -RequireHardLinks} 'requires a verified hard link'
  Refuses-Probe {Copy-MIRCachedModZips -CacheDir $fixture -ModsDir $failedRoot -LockEntries @($compatEntry)} 'controlled-link-failure'
  Refuses-Probe {Copy-MIRModUnderTest -RepoRoot $repo -ModsDir $failedRoot -ZipPath $source} 'controlled-link-failure'
  Assert-Probe ($copies -eq 0 -and (Get-MIRImmutableInputSha256 $source) -ceq $archiveInput.expected_sha256) 'strict link failure copied or modified the canonical input.'
  $completed=$true
} finally {
  if($null -ne $lease -and -not $lease.closed) { $null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed }
  if($completed-and(Test-Path -LiteralPath $fixture)) {
    $resolved=Resolve-MIR441RecoveryScratchPath -Path $fixture
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }else{Write-Warning "Controlled failure diagnostics retained at $fixture"}
}
[pscustomobject]@{status='passed';assertions=$assertions;native_factorio=$false;actual_materialization=$false;scope='Controlled lease, row budget, preallocation, browser engine/archive admission, owned small actors and completed-row custody parser; no native oracle';memory_enforcement='sampled-watchdog-not-hard-cap'}
