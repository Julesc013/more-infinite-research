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
  . (Join-Path $repo 'tools/lib/assurance/evidence/CommandExecution.ps1')
  $catalog=Get-Content -LiteralPath (Join-Path $repo 'validation/tests.yml') -Raw | ConvertFrom-Json
  $command=[string](@($catalog.tests | Where-Object id -CEQ 'runtime.material-route-guard')[0].command)
  foreach($line in @('2.0','2.1')) {
    $engine=if($line -ceq '2.0') { 'D:\Programs\Factorio\2.0\bin\x64\factorio.exe' } else { 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' }
    $resolved=Resolve-MIRAssuranceCommandText -Command $command -Context ([pscustomobject]@{factorio=$engine;target=$line}) -Plan ([pscustomobject]@{})
    Assert-Probe ($resolved.Contains("-FactorioBin '$engine'") -and $resolved.Contains("-ExpectedFactorioLine '$line'") -and $resolved.Contains('-ExpectedPeakMemoryMiB 2048') -and $resolved.Contains('-MaxNewOutputMiB 120')) "selected $line command lost its engine, line or explicit resource budgets."
  }
  $arguments=@{RepoRoot=$repo;OutputRoot=$fixture;MaxNewOutputMiB=1}
  Refuses-Probe {New-MIRNativeProbeResourceContext @arguments} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'missing-budget refusal allocated staging.'
  Refuses-Probe {New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot 'D:\outside-native-probe' -ExpectedPeakMemoryMiB 1024} 'resource-output-root'
  foreach($script in @('tests/compiler/Test-MIRMaterialRoutes.ps1','tests/runtime/Test-MIRF210CurrentBobAngelTinRouteObserver.ps1')) {
    Refuses-Probe {& (Join-Path $repo $script) -RepoRoot $repo -FactorioBin 'absent-engine' -OutputRoot $fixture} 'resource-peak-budget-required'
    Assert-Probe (-not (Test-Path -LiteralPath $fixture)) "$script allocated staging before refusal."
  }
  Refuses-Probe {& (Join-Path $repo 'tests/runtime/Test-MIRF210CurrentBobAngelTinRouteObserver.ps1') -RepoRoot $repo -PrepareOnly -OutputRoot $fixture} 'resource-peak-budget-required'
  Assert-Probe (-not (Test-Path -LiteralPath $fixture)) 'PrepareOnly bypassed allocation admission.'
  $context=New-MIRNativeProbeResourceContext @arguments -ExpectedPeakMemoryMiB 1024
  Assert-Probe (-not (Test-Path -LiteralPath $context.root)) 'successful admission allocated before caller initialization.'
  New-Item -ItemType Directory -Path $context.root | Out-Null
  $source=Join-Path $fixture 'dependency.zip'
  [IO.File]::WriteAllBytes($source,[byte[]]::new(128KB))
  $archiveInput=[ordered]@{source_path=$source;file_name='dependency.zip';expected_sha256=Get-MIRImmutableInputSha256 $source;role='dependency-mod';identity=@{name='controlled'};provenance=@{kind='tiny-controlled-fixture'};immutable=$true}
  $leaseRoot=Join-Path $context.root 'stage';New-Item -ItemType Directory -Path $leaseRoot | Out-Null
  Refuses-Probe {New-MIRImmutableInputLease -RunRoot $leaseRoot -StageDirectory (Join-Path $leaseRoot 'mods') -Inputs @($archiveInput) -RequireHardLinks -ForceCopy} 'cannot request copy mode'
  $lease=New-MIRImmutableInputLease -RunRoot $leaseRoot -StageDirectory (Join-Path $leaseRoot 'mods') -Inputs @($archiveInput) -RequireHardLinks
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
  Write-MIRNativeProbeResult -Context $context -Record @{status='controlled-passed';native_factorio=$false;actual_materialization=$false;actor_count=$context.runs.Count}
  Assert-Probe ((Get-Content -LiteralPath (Join-Path $context.root 'result.json') -Raw | ConvertFrom-Json).actor_count -eq 3) 'reserved result did not preserve actual actor inventory.'
  $resultPath=Join-Path $context.root 'result.json';Remove-Item -LiteralPath $resultPath
  [IO.File]::WriteAllBytes($budgetFile,[byte[]]::new(960KB))
  Refuses-Probe {Write-MIRNativeProbeResult -Context $context -Record @{payload=('x'*128KB)}} 'resource-output-budget'
  Assert-Probe (-not (Test-Path -LiteralPath $resultPath)) 'oversized result was written as success.'
  # A missing shared alias must refuse even when other output masks the
  # subtraction in the logical tree total. The strict lease is closed here.
  Remove-Item -LiteralPath $context.aliases[0].stage_path
  Refuses-Probe {Get-MIRNativeProbeRemainingOutputBytes -Context $context} 'shared-alias-identity'
  Assert-Probe ((Get-MIRImmutableInputSha256 $source) -ceq $archiveInput.expected_sha256) 'alias retirement changed its canonical archive.'

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
[pscustomobject]@{status='passed';assertions=$assertions;native_factorio=$false;actual_materialization=$false;scope='Controlled lease, row budget, preallocation and owned small-process adapter proof';memory_enforcement='sampled-watchdog-not-hard-cap'}
