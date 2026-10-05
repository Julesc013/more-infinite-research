# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
$fixture=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo ('build/tmp/native-probe-fixture-'+[guid]::NewGuid().ToString('N')))
$assertions=0;$lease=$null
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
    }
  }
  $source=Join-Path $fixture 'dependency.zip'
  [IO.File]::WriteAllBytes($source,[byte[]]::new(128KB))
  $archiveInput=[ordered]@{source_path=$source;file_name='dependency.zip';expected_sha256=Get-MIRImmutableInputSha256 $source;role='dependency-mod';identity=@{name='controlled'};provenance=@{kind='tiny-controlled-fixture'};immutable=$true}
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
  Assert-Probe ((Get-MIR421SpaceFakeUpgradeAliasBytes -Lease $lease) -eq 128KB) 'SIF byte allowance was not backed by the actual strict hardlink lease.'
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
  $sourceProfileLease=$null;$candidateProfileLease=$null
  try {
    $sourceArchive=Join-Path $fixture 'more-infinite-research_4.2.20000.zip'
    $candidateArchive=Join-Path $fixture 'more-infinite-research_4.2.20001.zip'
    [IO.File]::WriteAllText($sourceArchive,'controlled predecessor')
    [IO.File]::WriteAllText($candidateArchive,'controlled candidate')
    $sourceProfileLease=New-MIR421SpaceFakeUpgradeProfile -RunRoot (Join-Path $context.root 'source-profile') -Dependencies @($archiveInput) -Archive $sourceArchive -ExpectedSha256 (Get-MIRImmutableInputSha256 $sourceArchive) -Version '4.2.20000' -Role source
    $sourceBytes=Get-MIR421SpaceFakeUpgradeAliasBytes -Lease $sourceProfileLease
    $null=Complete-MIRImmutableInputLease -Lease $sourceProfileLease -Outcome passed
    Assert-Probe ((Get-MIR421SpaceFakeUpgradeAliasBytes -Lease $sourceProfileLease) -eq $sourceBytes) 'completed source-profile aliases lost their verified byte accounting.'
    $candidateProfileLease=New-MIR421SpaceFakeUpgradeProfile -RunRoot (Join-Path $context.root 'candidate-profile') -Dependencies @($archiveInput) -Archive $candidateArchive -ExpectedSha256 (Get-MIRImmutableInputSha256 $candidateArchive) -Version '4.2.20001' -Role candidate
    Assert-Probe (@($candidateProfileLease.record.inputs | Where-Object staging_mode -CNE 'hardlink').Count -eq 0) 'candidate profile copied an archive.'
    Assert-Probe (-not (Test-Path -LiteralPath (Join-Path $candidateProfileLease.record.stage_directory 'more-infinite-research_4.2.20000.zip'))) 'candidate profile retained the obsolete MIR version.'
    $sourceMods=$sourceProfileLease.record.stage_directory;$targetMods=$candidateProfileLease.record.stage_directory
    New-Item -ItemType Directory -Path (Join-Path $sourceMods 'controlled-fixture') | Out-Null
    [IO.File]::WriteAllText((Join-Path $sourceMods 'controlled-fixture/control.lua'),'controlled fixture')
    $settingsPath=Join-Path $sourceMods 'mod-settings.dat'
    [IO.File]::WriteAllBytes($settingsPath,[byte[]](1,2,3,4))
    $settingsHash=Get-MIRImmutableInputSha256 $settingsPath
    Move-MIR421SpaceFakeUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName 'controlled-fixture'
    Assert-Probe ((Get-MIRImmutableInputSha256 (Join-Path $targetMods 'mod-settings.dat')) -ceq $settingsHash -and -not (Test-Path -LiteralPath $settingsPath)) 'profile switch lost or duplicated writable settings.'
    Assert-Probe (Test-Path -LiteralPath (Join-Path $targetMods 'controlled-fixture/control.lua')) 'profile switch lost the specialized fixture.'
    Refuses-Probe {Move-MIR421SpaceFakeUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName '../outside'} 'move-boundary'
    Refuses-Probe {Move-MIR421SpaceFakeUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $fixture -FixtureName 'controlled-fixture'} 'move-boundary'
    Refuses-Probe {Move-MIR421SpaceFakeUpgradeProfileState -RunRoot $context.root -SourceMods $sourceMods -TargetMods $targetMods -FixtureName 'controlled-fixture'} 'state-collision'
    $null=Complete-MIRImmutableInputLease -Lease $candidateProfileLease -Outcome passed
    $sourceProfileLease.record.outcome='failed'
    Refuses-Probe {Get-MIR421SpaceFakeUpgradeAliasBytes -Lease $sourceProfileLease} 'completed passed'
  } finally {
    foreach ($profileLease in @($sourceProfileLease,$candidateProfileLease)) {
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
  $recoverySource=[ordered]@{commit='controlled-source';tree='controlled-tree';package_source_sha256=$archiveInput.expected_sha256;source_version='4.2.1';distribution_version='4.2.21001'}
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

  $failedRoot=Join-Path $fixture 'link-failure';New-Item -ItemType Directory -Path $failedRoot | Out-Null
  $copies=0
  function New-Item {
    param([string]$ItemType,[string]$Path,[string]$Target,[switch]$Force)
    if($ItemType -ceq 'HardLink') { throw 'controlled-link-failure' }
    Microsoft.PowerShell.Management\New-Item -ItemType $ItemType -Path $Path -Force:$Force
  }
  function Copy-Item { $script:copies++;throw 'copy fallback was invoked' }
  Refuses-Probe {New-MIRImmutableInputLease -RunRoot $failedRoot -StageDirectory (Join-Path $failedRoot 'mods') -Inputs @($archiveInput) -RequireHardLinks} 'requires a verified hard link'
  Assert-Probe ($copies -eq 0 -and (Get-MIRImmutableInputSha256 $source) -ceq $archiveInput.expected_sha256) 'strict link failure copied or modified the canonical input.'
} finally {
  if($null -ne $lease -and -not $lease.closed) { $null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed }
  if(Test-Path -LiteralPath $fixture) {
    $resolved=Resolve-MIR441RecoveryScratchPath -Path $fixture
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
[pscustomobject]@{status='passed';assertions=$assertions;native_factorio=$false;actual_materialization=$false;scope='Controlled lease, row budget, preallocation, browser engine/archive admission, owned small actors and completed-row custody parser; no native oracle';memory_enforcement='sampled-watchdog-not-hard-cap'}
