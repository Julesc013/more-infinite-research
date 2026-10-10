# Optional native scenario inputs for the existing manifest-driven upgrade runner.
function Assert-MIR42CompleteCatalogueUpgradeMarker {
  param([Parameter(Mandatory)][string]$Text)
  $markers=[regex]::Matches($Text,'\[mir-fixture\] complete Space Age state retained technologies=(?<technologies>[0-9]+) recipes=(?<recipes>[0-9]+)')
  if($markers.Count-eq0-or @($markers|Where-Object {[int]$_.Groups['technologies'].Value-lt3-or[int]$_.Groups['recipes'].Value-lt1}).Count){
    throw '[mir42-complete-catalogue-upgrade-marker] Full-state oracle did not execute successfully.'
  }
}

function Set-MIR421ModernBaseUpgradeFixtureIdentity {
  param([Parameter(Mandatory)][string]$FixtureDirectory,
    [Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target,
    [ValidateSet('4.2.1','4.2.2')][string]$SourceVersion='4.2.1',
    [AllowEmptyString()][string]$FromVersion='',
    [switch]$SpaceIsFake,
    [switch]$SpaceAge)
  # Only the disposable prepared fixture changes. Identity includes the
  # predecessor when 4.2.2 tests both CCC00 -> CCC02 and CCC01 -> CCC02:
  # their specialized control.lua bytes differ and must never share a library
  # archive name/version.
  if($SpaceIsFake -and $Target -cnotin @('f210','f200')){throw '[mir421-sif-target]'}
  if($SpaceAge -and ($SpaceIsFake -or $Target-cne'f210')){throw '[mir422-space-age-fixture-target]'}
  $code=$Target.Substring(1)
  $sourcePatch=([version]$SourceVersion).Build
  if([string]::IsNullOrWhiteSpace($FromVersion)){$FromVersion='4.2.'+$code+($sourcePatch-1).ToString('00')}
  $fromMatch=[regex]::Match($FromVersion,('^4[.]2[.]'+$code+'(?<patch>00|01)$'))
  if(-not$fromMatch.Success-or([int]$fromMatch.Groups['patch'].Value-ge$sourcePatch)){throw '[mir42-upgrade-fixture-predecessor]'}
  $fromPatch=[int]$fromMatch.Groups['patch'].Value
  $direct420To422=$SourceVersion-ceq'4.2.2'-and$fromPatch-eq0
  $fixtureVersion=if($direct420To422){if($SpaceIsFake){'0.1.7'}elseif($SpaceAge){'0.1.10'}else{'0.1.6'}}elseif($SpaceIsFake){if($SourceVersion-ceq'4.2.2'){'0.1.3'}else{'0.1.0'}}elseif($SpaceAge){if($SourceVersion-ceq'4.2.2'){'0.1.9'}else{'0.1.4'}}elseif($SourceVersion-ceq'4.2.2'){'0.1.2'}else{'0.1.1'}
  $directory=Resolve-MIR441RecoveryScratchPath -Path $FixtureDirectory
  $path=Join-Path $directory 'info.json'
  Assert-MIRLibraryPath $path
  $info=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -DateKind String
  $line=switch($Target){f210{'2.1'};f200{'2.0'};f110{'1.1'};f100{'1.0'}}
  if($info.name-cne"mir-fixture-assert-upgrade-4-0-${code}00-to-4-1-${code}00"-or
    $info.factorio_version-cne$line-or$info.version-cnotin@('0.1.0',$fixtureVersion)){
    throw '[mir421-modern-base-fixture-template]'
  }
  if($info.version-ceq$fixtureVersion){return}
  $info.version=$fixtureVersion
  [IO.File]::WriteAllText($path,($info|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
}

function Set-MIR42HistoricalMaintenanceUpgradeFixtureIdentity {
  param([Parameter(Mandatory)][string]$FixtureDirectory,
    [Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target,
    [Parameter(Mandatory)][ValidateSet('4.2.1','4.2.2')][string]$SourceVersion,
    [AllowEmptyString()][string]$FromVersion='')
  $code=$Target.Substring(1)
  $sourcePatch=([version]$SourceVersion).Build
  if([string]::IsNullOrWhiteSpace($FromVersion)){$FromVersion='4.2.'+$code+($sourcePatch-1).ToString('00')}
  $fromMatch=[regex]::Match($FromVersion,('^4[.]2[.]'+$code+'(?<patch>00|01)$'))
  if(-not$fromMatch.Success-or([int]$fromMatch.Groups['patch'].Value-ge$sourcePatch)){throw '[mir42-upgrade-fixture-predecessor]'}
  $fromPatch=[int]$fromMatch.Groups['patch'].Value
  $directory=Resolve-MIR441RecoveryScratchPath -Path $FixtureDirectory
  $path=Join-Path $directory 'info.json'
  Assert-MIRLibraryPath $path
  $info=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -DateKind String
  $fixtureVersion=if($SourceVersion-ceq'4.2.2'-and$fromPatch-eq0){'1.0.3'}else{'1.0.'+$sourcePatch}
  $line='0.'+[int]$Target.Substring(1)
  if($info.name-cne'mir-fixture-assert-upgrade-historical-terminal-to-mir42'-or
    $info.factorio_version-cne$line-or$info.version-cnotin@('1.0.0',$fixtureVersion)){
    throw '[mir42-historical-maintenance-fixture-template]'
  }
  if($info.version-ceq$fixtureVersion){return}
  $info.version=$fixtureVersion
  [IO.File]::WriteAllText($path,($info|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
}

function Get-MIR421SpaceFakeUpgradeDescriptor {
  param([string]$Target,[string]$FromVersion,[string]$ToVersion,[string]$FixtureName,[string]$Archetype,
    [ValidateSet('4.2.1','4.2.2')][string]$SourceVersion='4.2.1')
  $code = switch -CaseSensitive ($Target) { 'f210' { '210' }; 'f200' { '200' }; default { throw '[mir421-sif-target]' } }
  $expectedFixture = "assert-upgrade-4-0-${code}00-to-4-1-${code}00"
  $expectedArchetype = if ($Target -ceq 'f210') { 'base-continuations' } else { 'base-default' }
  $patch=([version]$SourceVersion).Build
  $fromPatches=if($SourceVersion-ceq'4.2.2'){@(0,1)}else{@(0)}
  $allowedFrom=@($fromPatches|ForEach-Object {'4.2.'+$code+$_.ToString('00')})
  if ($FromVersion -cnotin $allowedFrom -or $ToVersion -cne ('4.2.'+$code+$patch.ToString('00')) -or
      $FixtureName -cne $expectedFixture -or $Archetype -cne $expectedArchetype) { throw '[mir421-sif-transition]' }
  $predecessorSourceVersion='4.2.'+[int]$FromVersion.Substring($FromVersion.Length-2)
  $line = if ($Target -ceq 'f210') { '2.1' } else { '2.0' }
  $inputs = if ($Target -ceq 'f210') { @(
    # 1.0.76 fails native 2.1.21 item validation before save creation; 1.0.78
    # carries the upstream fuel-categories correction and requires commons .33.
    [pscustomobject]@{name='space-is-fake';version='1.0.78';sha256='3B5F2A381ADF1D9AECF048293E20035963A528720FBDC148CCC2B0418049FF13'},
    [pscustomobject]@{name='cr-commons';version='1.0.33';sha256='378D3114B09C872358088B33500BC4AB0B9B9EFD9E5650DBEA0E87B5914C29BB'}
  ) } else { @(
    [pscustomobject]@{name='space-is-fake';version='1.0.60';sha256='860F2048A7E6F4C2ECD1A9CECA6ECDD340ECF797773EC582A6E60FFE6F8D87AC'},
    [pscustomobject]@{name='cr-commons';version='1.0.27';sha256='6F3622AE6270F9B365A9E2E07FA5E07B61B2BBFCAB3A4D930CC410EBDEB63B92'}
  ) }
  return [pscustomobject]@{request='SIF-01';line=$line;target=$Target;inputs=$inputs;mod_names=@($inputs | ForEach-Object name);
    source_version=$SourceVersion;predecessor_source_version=$predecessorSourceVersion;scenario="SIF-01-published-$predecessorSourceVersion-to-$SourceVersion"}
}

function Resolve-MIR421SpaceFakeUpgradeInputs {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Descriptor,[string[]]$LocalModLibraryDirs=@())
  # The dependency library is a read-only input. No downloads or copy fallback.
  if ($LocalModLibraryDirs.Count -eq 0) { throw '[mir-upgrade-library-required] Supply the selected machine-local archive library explicitly.' }
  $expected=[ordered]@{}
  foreach ($row in $Descriptor.inputs) { $expected[([string]$row.name+'_'+[string]$row.version+'.zip')]=[string]$row.sha256 }
  $resolved=Resolve-MIRNativeProbeDependencyInputs -StageRoot (Join-Path $RepoRoot ('build/tmp/mir421-sif-input-lookup-'+$Descriptor.target)) -ExpectedArchives $expected -LocalModLibraryDirs $LocalModLibraryDirs
  return @(foreach ($row in $Descriptor.inputs) {
    $fileName = [string]$row.name + '_' + [string]$row.version + '.zip'
    $path = $resolved[$fileName].source_path
    [pscustomobject]@{source_path=$path;file_name=$fileName;expected_sha256=[string]$row.sha256;immutable=$true;role='native-sif-dependency';identity=[ordered]@{name=$row.name;version=$row.version;factorio_line=$Descriptor.line};provenance=[ordered]@{kind='verified-canonical-local-library';request='SIF-01'}}
  })
}

function Get-MIRUpgradeLibrarySelection {
  param([Parameter(Mandatory)][string]$Library,[Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$ExpectedSha256,[object[]]$Dependencies=@(),
    [Parameter(Mandatory)][string[]]$FixtureDirectories,[bool]$EnableDlc=$false)
  $inventory=@(Get-MIRLibraryInventory -LibraryDirectory $Library -EngineDataDirectory $EngineDataDirectory)
  $rows=[Collections.Generic.List[object]]::new();$hashes=[ordered]@{}
  $builtins=@('base')
  if($EnableDlc){$builtins+=@('elevated-rails','quality','space-age')}
  if($EnableDlc-and@($inventory|Where-Object {$_.builtin-and$_.name-ceq'recycler'}).Count){$builtins+='recycler'}
  foreach($name in $builtins){
    $matches=@($inventory|Where-Object {$_.builtin-and$_.name-ceq$name})
    if($matches.Count-ne1){throw "[mir-upgrade-builtin-missing] $name"}
    $rows.Add([ordered]@{name=$name;version=$matches[0].version;enabled=$true})
  }
  $candidate=[ordered]@{file_name=[IO.Path]::GetFileName($Archive);expected_sha256=$ExpectedSha256;identity=@{name='more-infinite-research';version=$Version}}
  foreach($inputRow in @($Dependencies)+@($candidate)){
    $path=Join-Path $Library $inputRow.file_name
    $matches=@($inventory|Where-Object {-not$_.builtin-and$_.name-ceq$inputRow.identity.name-and$_.version-ceq$inputRow.identity.version})
    if($matches.Count-ne1-or$matches[0].path-cne$path){throw "[mir-upgrade-library-input-missing] $($inputRow.file_name)"}
    if((Get-MIRImmutableInputSha256 $path)-cne$inputRow.expected_sha256){throw "[mir-upgrade-library-input-hash] $($inputRow.file_name)"}
    $rows.Add([ordered]@{name=$matches[0].name;version=$matches[0].version;enabled=$true})
    $hashes[$inputRow.file_name]=[string]$inputRow.expected_sha256
  }
  foreach($directory in $FixtureDirectories){
    $info=Get-Content -LiteralPath (Join-Path $directory 'info.json') -Raw|ConvertFrom-Json
    $name=$info.name+'_'+$info.version+'.zip';$path=Join-Path $Library $name
    Assert-MIRLibraryFixtureArchive -Archive $path -SourceDirectory $directory
    $rows.Add([ordered]@{name=$info.name;version=$info.version;enabled=$true})
    $hashes[$name]=Get-MIRImmutableInputSha256 $path
  }
  if(@($rows|Group-Object {$_.name}|Where-Object Count -GT 1).Count){throw '[mir-upgrade-library-duplicate-name]'}
  return [pscustomobject]@{mod_list=[ordered]@{mods=@($rows)};archive_hashes=$hashes}
}

function Get-MIRUpgradeLinkedArchiveBytes {
  param([Parameter(Mandatory)]$Lease)
  [int64]$bytes = 0
  if (-not $Lease.record.require_hard_links) { throw '[mir421-sif-dependency-lease]' }
  if ($Lease.closed) { $null=Assert-MIRImmutableInputTerminalReceipt -Receipt $Lease.record }
  foreach ($input in $Lease.record.inputs) {
    if ($input.staging_mode -cne 'hardlink' -or
        (Get-MIRImmutableInputFileIdentity -Path $input.source_path) -cne (Get-MIRImmutableInputFileIdentity -Path $input.stage_path)) { throw '[mir421-sif-dependency-alias]' }
    $bytes += [int64](Get-Item -LiteralPath $input.stage_path).Length
  }
  return $bytes
}

function New-MIRUpgradeLinkedProfile {
  param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Dependencies,
    [Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$ExpectedSha256,
    [Parameter(Mandatory)][string]$Version,[ValidateSet('source','candidate')][string]$Role,[string]$Request='native-upgrade')
  $input=[ordered]@{source_path=$Archive;file_name=[IO.Path]::GetFileName($Archive);expected_sha256=$ExpectedSha256;
    immutable=$true;role=$Role;identity=[ordered]@{name='more-infinite-research';version=$Version};
    provenance=[ordered]@{kind='verified-upgrade-archive-input';request=$Request}}
  New-Item -ItemType Directory -Path $RunRoot -ErrorAction Stop | Out-Null
  return New-MIRImmutableInputLease -RunRoot $RunRoot -StageDirectory (Join-Path $RunRoot 'mods') -Inputs @($Dependencies+$input) -RequireHardLinks
}

function Move-MIRUpgradeProfileState {
  param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$SourceMods,
    [Parameter(Mandatory)][string]$TargetMods,[Parameter(Mandatory)][string]$FixtureName)
  if ($FixtureName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw '[mir421-sif-fixture-move-boundary]' }
  $moves=@()
  foreach ($name in @($FixtureName,'mod-settings.dat')) {
    $source=Join-Path $SourceMods $name
    $target=Join-Path $TargetMods $name
    foreach ($path in @($source,$target)) {
      if (-not (Test-MIR441PathContained -Root $RunRoot -Path ([IO.Path]::GetFullPath($path)))) { throw '[mir421-sif-fixture-move-boundary]' }
    }
    if (-not (Test-Path -LiteralPath $source)) {
      if ($name -ceq $FixtureName) { throw '[mir421-sif-fixture-missing]' }
      continue
    }
    if (Test-Path -LiteralPath $target) { throw '[mir421-sif-profile-state-collision]' }
    $moves += [pscustomobject]@{source=$source;target=$target}
  }
  foreach ($move in $moves) { Move-Item -LiteralPath $move.source -Destination $move.target }
}

function Assert-MIR421SpaceFakeUpgradeMarker {
  param([string]$Text,[ValidateSet('source','upgrade','reload')][string]$Stage)
  $marker=[regex]::Escape("[mir-fixture] SIF-01 native continuations verified stage=$Stage")
  if (-not [regex]::IsMatch($Text,'(^|\r?\n)[^\r\n]*'+$marker+'(\r?\n|$)')) { throw "[mir421-sif-$Stage-marker]" }
}

function Add-MIR421SpaceFakeUpgradeOracle {
  param([Parameter(Mandatory)][string]$ControlText)
  if ($ControlText.Contains('require("mir421_space_fake_upgrade")')) { throw '[mir421-sif-fixture-anchor]' }
  # This scenario always enables Space Age. Its native data updates remove
  # mining-productivity-4 and make mining-productivity-3 infinite. Keep the
  # F200 fixture's earned level and queued progress checks on that native owner.
  $baseMiningAnchor='local technology_name="mining-productivity-4"'
  if($ControlText.Contains($baseMiningAnchor)){
    if([regex]::Matches($ControlText,[regex]::Escape($baseMiningAnchor)).Count-ne1){throw '[mir421-sif-fixture-anchor]'}
    $ControlText=$ControlText.Replace($baseMiningAnchor,'local technology_name="mining-productivity-3"')
  }
  # Specialize only the disposable copy of the existing generated fixture.
  # Preserve its research/progress oracle and require each insertion anchor once.
  $anchors = @(
    @('log("[mir-fixture] "..from_version.." upgrade source proof complete archetype="..archetype)', 'sif.capture();log("[mir-fixture] "..from_version.." upgrade source proof complete archetype="..archetype)'),
    @('state.upgrade_complete=true;log', 'sif.verify("upgrade");state.upgrade_complete=true;log'),
    @('script.on_event(defines.events.on_tick,function()', 'script.on_event(defines.events.on_tick,function() if script.active_mods["more-infinite-research"] == to_version then sif.verify("reload") end;')
  )
  foreach ($pair in $anchors) {
    if ([regex]::Matches($ControlText,[regex]::Escape($pair[0])).Count -ne 1) { throw '[mir421-sif-fixture-anchor]' }
    $ControlText=$ControlText.Replace($pair[0],$pair[1])
  }
  return 'local sif = require("mir421_space_fake_upgrade")' + "`n" + $ControlText
}
