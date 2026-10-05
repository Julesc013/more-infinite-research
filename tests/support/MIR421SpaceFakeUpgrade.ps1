# Optional native scenario inputs for the existing manifest-driven upgrade runner.
function Get-MIR421SpaceFakeUpgradeDescriptor {
  param([string]$Target,[string]$FromVersion,[string]$ToVersion,[string]$FixtureName,[string]$Archetype)
  $code = switch -CaseSensitive ($Target) { 'f210' { '210' }; 'f200' { '200' }; default { throw '[mir421-sif-target]' } }
  $expectedFixture = "assert-upgrade-4-0-${code}00-to-4-1-${code}00"
  $expectedArchetype = if ($Target -ceq 'f210') { 'base-continuations' } else { 'base-default' }
  if ($FromVersion -cne "4.2.${code}00" -or $ToVersion -cne "4.2.${code}01" -or
      $FixtureName -cne $expectedFixture -or $Archetype -cne $expectedArchetype) { throw '[mir421-sif-transition]' }
  $line = if ($Target -ceq 'f210') { '2.1' } else { '2.0' }
  $inputs = if ($Target -ceq 'f210') { @(
    [pscustomobject]@{name='space-is-fake';version='1.0.76';sha256='064F2DF2D669AA0EE12A27146EFA32B5243AEBA86D7B72241A540D635F0461FF'},
    [pscustomobject]@{name='cr-commons';version='1.0.32';sha256='75C8010ADBB03173E46C1E6A52E64239C3A837C826E385706AC0C9C6EDA69CDC'}
  ) } else { @(
    [pscustomobject]@{name='space-is-fake';version='1.0.60';sha256='860F2048A7E6F4C2ECD1A9CECA6ECDD340ECF797773EC582A6E60FFE6F8D87AC'},
    [pscustomobject]@{name='cr-commons';version='1.0.27';sha256='6F3622AE6270F9B365A9E2E07FA5E07B61B2BBFCAB3A4D930CC410EBDEB63B92'}
  ) }
  return [pscustomobject]@{request='SIF-01';line=$line;target=$Target;inputs=$inputs;mod_names=@($inputs | ForEach-Object name)}
}

function Resolve-MIR421SpaceFakeUpgradeInputs {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Descriptor,[string[]]$LocalModLibraryDirs=@())
  # The dependency library is a read-only input. No downloads or copy fallback.
  if ($LocalModLibraryDirs.Count -eq 0) { $LocalModLibraryDirs=@(Join-Path (Split-Path -Parent $RepoRoot) ('testmods/'+$Descriptor.line)) }
  $expected=[ordered]@{}
  foreach ($row in $Descriptor.inputs) { $expected[([string]$row.name+'_'+[string]$row.version+'.zip')]=[string]$row.sha256 }
  $resolved=Resolve-MIRNativeProbeDependencyInputs -StageRoot (Join-Path $RepoRoot ('build/tmp/mir421-sif-input-lookup-'+$Descriptor.target)) -ExpectedArchives $expected -LocalModLibraryDirs $LocalModLibraryDirs
  return @(foreach ($row in $Descriptor.inputs) {
    $fileName = [string]$row.name + '_' + [string]$row.version + '.zip'
    $path = $resolved[$fileName].source_path
    [pscustomobject]@{source_path=$path;file_name=$fileName;expected_sha256=[string]$row.sha256;immutable=$true;role='native-sif-dependency';identity=[ordered]@{name=$row.name;version=$row.version;factorio_line=$Descriptor.line};provenance=[ordered]@{kind='verified-canonical-local-library';request='SIF-01'}}
  })
}

function Get-MIR421SpaceFakeUpgradeAliasBytes {
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

function New-MIR421SpaceFakeUpgradeProfile {
  param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][object[]]$Dependencies,
    [Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$ExpectedSha256,
    [Parameter(Mandatory)][string]$Version,[ValidateSet('source','candidate')][string]$Role)
  $input=[ordered]@{source_path=$Archive;file_name=[IO.Path]::GetFileName($Archive);expected_sha256=$ExpectedSha256;
    immutable=$true;role=$Role;identity=[ordered]@{name='more-infinite-research';version=$Version};
    provenance=[ordered]@{kind='manifest-authenticated-upgrade-input';request='SIF-01'}}
  New-Item -ItemType Directory -Path $RunRoot -ErrorAction Stop | Out-Null
  return New-MIRImmutableInputLease -RunRoot $RunRoot -StageDirectory (Join-Path $RunRoot 'mods') -Inputs @($Dependencies+$input) -RequireHardLinks
}

function Assert-MIR421SpaceFakeUpgradeMarker {
  param([string]$Text,[ValidateSet('source','upgrade','reload')][string]$Stage)
  $marker=[regex]::Escape("[mir-fixture] SIF-01 native continuations verified stage=$Stage")
  if (-not [regex]::IsMatch($Text,'(^|\r?\n)[^\r\n]*'+$marker+'(\r?\n|$)')) { throw "[mir421-sif-$Stage-marker]" }
}

function Add-MIR421SpaceFakeUpgradeOracle {
  param([Parameter(Mandatory)][string]$ControlText)
  if ($ControlText.Contains('require("mir421_space_fake_upgrade")')) { throw '[mir421-sif-fixture-anchor]' }
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
