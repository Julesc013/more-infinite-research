# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$CandidateZip='',
  [string]$BobModsDir='C:\Projects\Factorio\testmods\2.1',
  [string]$OutputRoot='build/tests/mir42-bob-tin-qualification'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$bobMods=(Resolve-Path -LiteralPath $BobModsDir).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
if(-not $output.StartsWith((Join-Path $repo 'build')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Test outputs must be under build.' }
$expectedEngineSha256='710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8'
$engineSha256=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
if($engineSha256 -cne $expectedEngineSha256) { throw "Bob Tin qualification requires exact F210 engine SHA-256 $expectedEngineSha256." }
$version=(& $engine --version | Out-String)
if($LASTEXITCODE -ne 0 -or $version -notmatch 'Version: 2[.]1[.]17') { throw 'Bob Tin qualification requires the exact Steam F210 2.1.17 engine.' }
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim()
$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
if($sourceCommit -notmatch '^[0-9a-f]{40}$' -or $sourceTree -notmatch '^[0-9a-f]{40}$') { throw 'Bob Tin qualification could not bind the current source commit/tree.' }
$sourceRootChanges=@(& git -C $repo status --porcelain --untracked-files=all -- src/mod)
if($sourceRootChanges.Count -ne 0) { throw "Bob Tin qualification refuses a changed package-source root: $($sourceRootChanges -join '; ')" }
$packageSource=Join-Path $repo 'src/mod/package-source.json'
$packageSourceSha256=(Get-FileHash -LiteralPath $packageSource -Algorithm SHA256).Hash
$expectedHashes=[ordered]@{
  boblibrary='49EAE2D4D8E58EBD28BAFDB7E71D5307CBCE2077E0642440ED7EC527D466FFC4'
  bobores='7F8E33E35F59BB3F2CD72E3AB2FED30D1C2AE9C117E3731324AC307D9965082B'
  bobplates='503D7BF6E88DA1F99463AC00CEC959C2003B2701D80DC4A564CF2EC3920AC8AF'
}
$expectedNonClaims=@('F200','Angel or combined Bob/Angel route qualification','PIPE-01','infinite continuation','weighted balance','full BA-07 or PROG-01','release readiness')
function Assert-ExactValue([string]$Name,$Actual,$Expected) {
  if($Actual -cne $Expected) { throw "Bob Tin dossier $Name differs: expected '$Expected', actual '$Actual'." }
}
function Assert-ExactArray([string]$Name,$Actual,[string[]]$Expected) {
  $actualValues=@($Actual | ForEach-Object { [string]$_ })
  if($actualValues.Count -ne $Expected.Count -or (@(Compare-Object -CaseSensitive $Expected $actualValues)).Count -ne 0) {
    throw "Bob Tin dossier $Name differs from its exact expected values."
  }
}
function Assert-DossierProperties([string]$Name,$Object,[string[]]$Expected) {
  if($null -eq $Object) { throw "Bob Tin dossier $Name is absent." }
  Assert-ExactArray -Name "$Name properties" -Actual @($Object.PSObject.Properties.Name | Sort-Object) -Expected @($Expected | Sort-Object)
}
$fixtureSource=Join-Path $repo 'fixtures/assert-bob-tin-qualification'
$dossier=Join-Path $fixtureSource 'route-dossier.json'
try { $dossierValue=Get-Content -Raw -LiteralPath $dossier | ConvertFrom-Json -ErrorAction Stop } catch { throw "Bob Tin route dossier is not valid JSON: $($_.Exception.Message)" }
Assert-DossierProperties -Name 'root' -Object $dossierValue -Expected @('schema','scope','target','route','mir_owner','explicit_non_claims')
Assert-ExactValue -Name 'schema' -Actual $dossierValue.schema -Expected 1
Assert-ExactValue -Name 'scope' -Actual $dossierValue.scope -Expected 'F210 Bob-only finite Tin qualification; package-excluded fixture evidence'
Assert-DossierProperties -Name 'target' -Object $dossierValue.target -Expected @('factorio_line','factorio_version','bobplates_version','bobplates_sha256','boblibrary_version','boblibrary_sha256','bobores_version','bobores_sha256')
Assert-ExactValue -Name 'target.factorio_line' -Actual $dossierValue.target.factorio_line -Expected '2.1'
Assert-ExactValue -Name 'target.factorio_version' -Actual $dossierValue.target.factorio_version -Expected '2.1.17'
foreach($name in $expectedHashes.Keys) {
  Assert-ExactValue -Name ("target.$name`_version") -Actual $dossierValue.target."$($name)_version" -Expected (@{boblibrary='3.0.0';bobores='3.0.0';bobplates='3.0.1'}[$name])
  Assert-ExactValue -Name ("target.$name`_sha256") -Actual $dossierValue.target."$($name)_sha256" -Expected $expectedHashes[$name]
}
Assert-DossierProperties -Name 'route' -Object $dossierValue.route -Expected @('recipe','categories','machine_witness','input','output','allow_productivity','auto_recycle','byproducts','catalysts','return_or_recycling_paths')
Assert-ExactValue -Name 'route.recipe' -Actual $dossierValue.route.recipe -Expected 'bob-tin-plate'
Assert-ExactArray -Name 'route.categories' -Actual $dossierValue.route.categories -Expected @('smelting')
Assert-ExactValue -Name 'route.machine_witness' -Actual $dossierValue.route.machine_witness -Expected 'stone-furnace'
foreach($side in @('input','output')) {
  Assert-DossierProperties -Name "route.$side" -Object $dossierValue.route.$side -Expected @('type','name','amount')
}
Assert-ExactValue -Name 'route.input.type' -Actual $dossierValue.route.input.type -Expected 'item'
Assert-ExactValue -Name 'route.input.name' -Actual $dossierValue.route.input.name -Expected 'bob-tin-ore'
Assert-ExactValue -Name 'route.input.amount' -Actual $dossierValue.route.input.amount -Expected 1
Assert-ExactValue -Name 'route.output.type' -Actual $dossierValue.route.output.type -Expected 'item'
Assert-ExactValue -Name 'route.output.name' -Actual $dossierValue.route.output.name -Expected 'bob-tin-plate'
Assert-ExactValue -Name 'route.output.amount' -Actual $dossierValue.route.output.amount -Expected 1
Assert-ExactValue -Name 'route.allow_productivity' -Actual $dossierValue.route.allow_productivity -Expected $true
Assert-ExactValue -Name 'route.auto_recycle' -Actual $dossierValue.route.auto_recycle -Expected $false
foreach($name in @('byproducts','catalysts','return_or_recycling_paths')) { Assert-ExactArray -Name "route.$name" -Actual $dossierValue.route.$name -Expected @() }
Assert-DossierProperties -Name 'mir_owner' -Object $dossierValue.mir_owner -Expected @('stream_key','technology','effect_type','effect_recipe','runtime_enforced_max_level','prototype_max_level','raw_direct_max_level','mirset1_imported_max_level','identity_state')
Assert-ExactValue -Name 'mir_owner.stream_key' -Actual $dossierValue.mir_owner.stream_key -Expected 'research_material_tin'
Assert-ExactValue -Name 'mir_owner.technology' -Actual $dossierValue.mir_owner.technology -Expected 'recipe-prod-research_material_tin-1'
Assert-ExactValue -Name 'mir_owner.effect_type' -Actual $dossierValue.mir_owner.effect_type -Expected 'change-recipe-productivity'
Assert-ExactValue -Name 'mir_owner.effect_recipe' -Actual $dossierValue.mir_owner.effect_recipe -Expected 'bob-tin-plate'
Assert-ExactValue -Name 'mir_owner.runtime_enforced_max_level' -Actual $dossierValue.mir_owner.runtime_enforced_max_level -Expected 3
Assert-ExactValue -Name 'mir_owner.prototype_max_level' -Actual $dossierValue.mir_owner.prototype_max_level -Expected 'infinite'
Assert-ExactValue -Name 'mir_owner.raw_direct_max_level' -Actual $dossierValue.mir_owner.raw_direct_max_level -Expected 2
Assert-ExactValue -Name 'mir_owner.mirset1_imported_max_level' -Actual $dossierValue.mir_owner.mirset1_imported_max_level -Expected 3
Assert-ExactValue -Name 'mir_owner.identity_state' -Actual $dossierValue.mir_owner.identity_state -Expected 'stable-unreleased'
Assert-ExactArray -Name 'explicit_non_claims' -Actual $dossierValue.explicit_non_claims -Expected $expectedNonClaims
$dossierSha256=(Get-FileHash -LiteralPath $dossier -Algorithm SHA256).Hash
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')
$run=Join-Path $output ([guid]::NewGuid().ToString('N'))
$mods=Join-Path $run 'mods'
New-Item -ItemType Directory -Force -Path $mods,(Join-Path $run 'userdata') | Out-Null
if([string]::IsNullOrWhiteSpace($CandidateZip)) {
  $candidate=New-MIR4TargetPackage -RepoRoot $repo -Target 'f210' -CandidateId ('BOB-TIN-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()) -SourceVersion '4.2.0' -DistributionVersion '4.2.21000' -OutputRoot 'build/bob-tin-packages'
  $candidateZip=[string]$candidate.archive_path
} else {
  $candidateZip=(Resolve-Path -LiteralPath $CandidateZip).Path
}
Copy-Item -LiteralPath $candidateZip -Destination (Join-Path $mods ([IO.Path]::GetFileName($candidateZip)))
$archivePaths=[ordered]@{
  boblibrary='boblibrary_3.0.0.zip'
  bobores='bobores_3.0.0.zip'
  bobplates='bobplates_3.0.1.zip'
}
$archiveHashes=[ordered]@{}
foreach($entry in $archivePaths.GetEnumerator()) {
  $path=Join-Path $bobMods $entry.Value
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Bob fixture lock is unavailable: $path" }
  Copy-Item -LiteralPath $path -Destination (Join-Path $mods $entry.Value)
  $archiveHashes[$entry.Key]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
foreach($name in $expectedHashes.Keys) { if($archiveHashes[$name] -cne $expectedHashes[$name]) { throw "Bob fixture lock hash differs for $name." } }
Publish-MIRModDirectoryArchive -Source $fixtureSource -Name 'mir-fixture-assert-bob-tin-qualification' -Version '0.1.0' -ModsDir $mods | Out-Null
Initialize-MIRSettingsOverrideMod -ModsDir $mods -FactorioVersion '2.1'
Set-CopiedStartupSettingDefaults -ModsDir $mods -Overrides @{
  'ips-enable-research_material_tin'=$true
  'ips-max-level-research_material_tin'=2
}
Set-CopiedMIRSettingsProfileDefault -ModsDir $mods -Settings @{
  'ips-enable-research_material_tin'=$true
  'ips-max-level-research_material_tin'=3
}
Complete-MIRSettingsOverrideMod -ModsDir $mods
@{mods=@(
  @{name='base';enabled=$true},
  @{name='space-age';enabled=$false},
  @{name='elevated-rails';enabled=$false},
  @{name='quality';enabled=$false},
  @{name='recycler';enabled=$false},
  @{name='more-infinite-research';enabled=$true},
  @{name='boblibrary';enabled=$true},
  @{name='bobores';enabled=$true},
  @{name='bobplates';enabled=$true},
  @{name='mir-fixture-assert-bob-tin-qualification';enabled=$true},
  @{name='mir-validation-settings-overrides';enabled=$true}
)} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $mods 'mod-list.json') -Encoding utf8
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
$config="[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n"
Set-Content -LiteralPath (Join-Path $run 'config.ini') -Value $config -Encoding utf8
$save=Join-Path $run 'bob-tin-qualification.zip'
function Invoke-BobTinEngine([string]$Name,[string[]]$Arguments) {
  $start=[Diagnostics.ProcessStartInfo]::new($engine)
  $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
  $start.Environment['SteamAppId']='427520'; $start.Environment['SteamGameId']='427520'
  $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
  foreach($argument in @('--config',(Join-Path $run 'config.ini'),'--mod-directory',$mods)+$Arguments) { [void]$start.ArgumentList.Add($argument) }
  $process=[Diagnostics.Process]::Start($start)
  try {
    $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
    if(-not $process.WaitForExit(120000)) { $process.Kill($true); throw "Bob Tin engine timeout: $run" }
    $text=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
    Set-Content -LiteralPath (Join-Path $run ("engine-$Name.log")) -Value $text -Encoding utf8
    if($process.ExitCode -ne 0) { throw "Bob Tin engine failed during ${Name}: $run`n$($text.Substring([Math]::Max(0,$text.Length-2500)))" }
  } finally { $process.Dispose() }
  $factorioLog=Join-Path $run 'userdata/factorio-current.log'
  if(-not(Test-Path -LiteralPath $factorioLog -PathType Leaf)) { throw "Bob Tin Factorio log is absent after $Name." }
  $copy=Join-Path $run ("factorio-$Name.log")
  Copy-Item -LiteralPath $factorioLog -Destination $copy
  $log=Get-Content -Raw -LiteralPath $copy
  if($Name -eq 'create' -and $log -notmatch [regex]::Escape('[mir-bob-tin] DATA PASS final-route finite-owner no-return-path')) { throw "Bob Tin final-route assertion is absent after ${Name}: $copy" }
  if($Name -ne 'create' -and $log -notmatch [regex]::Escape('[mir-bob-tin] RUNTIME PASS direct=2 imported=3 effective=3 completed=2 fractional=0.42 queued=true production=true load-observation=true')) { throw "Bob Tin runtime assertion is absent after ${Name}: $copy" }
  return $copy
}
$createLog=Invoke-BobTinEngine -Name 'create' -Arguments @('--create',$save)
if(-not(Test-Path -LiteralPath $save -PathType Leaf)) { throw 'Bob Tin initialized current-candidate save was not created.' }
$reloadOne=Invoke-BobTinEngine -Name 'reload-one' -Arguments @('--benchmark',$save,'--benchmark-ticks','360','--benchmark-runs','1')
$reloadTwo=Invoke-BobTinEngine -Name 'reload-two' -Arguments @('--benchmark',$save,'--benchmark-ticks','360','--benchmark-runs','1')
$dossier=Join-Path $fixtureSource 'route-dossier.json'
$receipt=[ordered]@{
  schema=1
  status='passed'
  scope='F210 Bob-only finite Tin route and two independent loads of initialized current-candidate state'
  target='F210'
  engine_version=$version.Trim()
  engine_sha256=$engineSha256
  source=[ordered]@{
    commit=$sourceCommit
    tree=$sourceTree
    package_source_sha256=$packageSourceSha256
    package_source_roots_clean=$true
  }
  package_sha256=(Get-FileHash -LiteralPath $candidateZip -Algorithm SHA256).Hash
  bob_archive_sha256=$archiveHashes
  dossier_sha256=$dossierSha256
  fixture_hashes=[ordered]@{
    info=(Get-FileHash -LiteralPath (Join-Path $fixtureSource 'info.json') -Algorithm SHA256).Hash
    data_final_fixes=(Get-FileHash -LiteralPath (Join-Path $fixtureSource 'data-final-fixes.lua') -Algorithm SHA256).Hash
    control=(Get-FileHash -LiteralPath (Join-Path $fixtureSource 'control.lua') -Algorithm SHA256).Hash
  }
  harness_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
  initialized_save_sha256=(Get-FileHash -LiteralPath $save -Algorithm SHA256).Hash
  cap_transport=[ordered]@{raw_direct=2;mirset1_imported=3;effective=3}
  load_observations=2
  logs=[ordered]@{
    create=(Get-FileHash -LiteralPath $createLog -Algorithm SHA256).Hash
    reload_one=(Get-FileHash -LiteralPath $reloadOne -Algorithm SHA256).Hash
    reload_two=(Get-FileHash -LiteralPath $reloadTwo -Algorithm SHA256).Hash
  }
  non_claims=$expectedNonClaims
}
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
$receipt | ConvertTo-Json -Depth 8
Write-Output "Evidence: $run"
