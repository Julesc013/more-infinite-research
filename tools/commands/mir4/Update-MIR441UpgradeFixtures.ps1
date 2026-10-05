[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [switch]$Check
)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$lf=[string][char]10
$rows=@(
  [ordered]@{source='assert-upgrade-3-2-11-to-4-0-21000';name='assert-upgrade-4-0-21000-to-4-1-21000';from='4.0.21000';to='4.1.21000';old_save='mir-4021000-upgraded';save='mir-4121000-upgraded';factorio='2.1';base='2.1.14';archetypes=@('base-default','space-age-native-owner','automatic-family-creation','base-continuations','mod-set-configuration-change')}
  [ordered]@{source='assert-upgrade-2-5-11-to-4-0-20000';name='assert-upgrade-4-0-20000-to-4-1-20000';from='4.0.20000';to='4.1.20000';old_save='mir-4020000-upgraded';save='mir-4120000-upgraded';factorio='2.0';base='2.0.77';archetypes=@('base-default')}
  [ordered]@{source='assert-upgrade-1-9-9-to-4-0-11000';name='assert-upgrade-4-0-11000-to-4-1-11000';from='4.0.11000';to='4.1.11000';old_save='mir-4011000-upgraded';save='mir-4111000-upgraded';factorio='1.1';base='1.1';archetypes=@('base-default')}
  [ordered]@{source='assert-upgrade-1-8-9-to-4-0-10000';name='assert-upgrade-4-0-10000-to-4-1-10000';from='4.0.10000';to='4.1.10000';old_save='mir-4010000-upgraded';save='mir-4110000-upgraded';factorio='1.0';base='1.0';archetypes=@('base-default')}
)

function Add-MIR441SpaceAgeCatalogueOracle {
  param([Parameter(Mandatory)][string]$Control,[Parameter(Mandatory)][ValidatePattern('^mir-[0-9]+-upgraded$')][string]$SaveName)

  # Preserve the adopted F210 oracle when deriving the direct upgrade fixture
  # from its historical sample. Historical fixture bytes remain authoritative
  # for their own releases; this enhancement belongs only to the derived row.
  $catalogue=@'
-- The 4.2 Space Age regression removed research outside the former one-owner
-- sample. Its specialized upgrade must preserve every existing technology's
-- state and every recipe's live research bonus, including the reported rows.
-- Escaped version patterns survive the runner's exact template substitutions.
local complete_catalogue_upgrade = archetype == "space-age-native-owner"
  and from_version:match("^4%.1%.21000$") and to_version:match("^4%.2%.21000$")
local function complete_state(force)
  local state = {technologies = {}, bonuses = {}, queue = {}}
  for name, technology in pairs(force.technologies) do
    state.technologies[name] = {
      level = technology.level, researched = technology.researched,
      enabled = technology.enabled, saved_progress = technology.saved_progress
    }
  end
  for name, recipe in pairs(force.recipes) do state.bonuses[name] = recipe.productivity_bonus end
  for _, technology in ipairs(force.research_queue or {}) do state.queue[#state.queue + 1] = technology.name end
  return state
end
local function verify_complete_state(force, expected)
  local technology_count, recipe_count = 0, 0
  for name, before in pairs(expected.technologies) do
    local after = force.technologies[name]
    if not after then fail("existing technology disappeared: " .. name) end
    if after.level ~= before.level or after.researched ~= before.researched or after.enabled ~= before.enabled then
      fail("existing technology state changed: " .. name)
    end
    if math.abs(after.saved_progress - before.saved_progress) > epsilon then fail("saved research progress changed: " .. name) end
    technology_count = technology_count + 1
  end
  for name, before in pairs(expected.bonuses) do
    local after = force.recipes[name]
    if not after or math.abs(after.productivity_bonus - before) > epsilon then fail("recipe research bonus changed: " .. name) end
    recipe_count = recipe_count + 1
  end
  local queue = {}
  for _, technology in ipairs(force.research_queue or {}) do queue[#queue + 1] = technology.name end
  if not same_names(queue, expected.queue) then fail("research queue changed") end
  for _, name in ipairs({"recipe-prod-research_cargo_bay_unloading_distance-1", "recipe-prod-research_ice-1", "recipe-prod-research_science_pack_productivity-1"}) do
    if not expected.technologies[name] or not force.technologies[name] then fail("reported technology absent: " .. name) end
  end
  log("[mir-fixture] complete Space Age state retained technologies=" .. technology_count .. " recipes=" .. recipe_count)
end
'@
  $verify=@'
  if complete_catalogue_upgrade then
    if not state.complete_state then fail("complete source state missing") end
    verify_complete_state(game.forces.player, state.complete_state)
  end
'@
  $reload=@'
local checked_complete_reload = false
script.on_event(defines.events.on_tick,function()
  local state=storage.mir_upgrade_fixture
  if state and state.upgrade_complete then
    if complete_catalogue_upgrade and not checked_complete_reload then
      verify_complete_state(game.forces.player, state.complete_state)
      checked_complete_reload = true
    end
    if not state.server_save_requested then state.server_save_requested=true;game.server_save("MIR_SAVE_NAME") end
  end
end)
'@
  $newline=[string][char]10
  $replacements=@(
    @{anchor='script.on_init(function()';value=($catalogue.Replace([string][char]13,'') + $newline + $newline + 'script.on_init(function()')},
    @{anchor='  log("[mir-fixture] "..from_version.." upgrade source proof complete archetype="..archetype)';value=('  if complete_catalogue_upgrade then storage.mir_upgrade_fixture.complete_state = complete_state(force) end' + $newline + '  log("[mir-fixture] "..from_version.." upgrade source proof complete archetype="..archetype)')},
    @{anchor='  state.upgrade_complete=true;log("[mir-fixture] "..from_version.." to "..to_version.." upgrade proof complete archetype="..archetype)';value=($verify.Replace([string][char]13,'') + $newline + '  state.upgrade_complete=true;log("[mir-fixture] "..from_version.." to "..to_version.." upgrade proof complete archetype="..archetype)')},
    @{anchor=('script.on_event(defines.events.on_tick,function() local state=storage.mir_upgrade_fixture;if state and state.upgrade_complete and not state.server_save_requested then state.server_save_requested=true;game.server_save("' + $SaveName + '") end end)');value=$reload.Replace([string][char]13,'').Replace('MIR_SAVE_NAME',$SaveName)}
  )
  foreach($replacement in $replacements){
    $first=$Control.IndexOf([string]$replacement.anchor,[StringComparison]::Ordinal)
    if($first -lt 0 -or $first -ne $Control.LastIndexOf([string]$replacement.anchor,[StringComparison]::Ordinal)){throw '[mir441-space-age-oracle-anchor]'}
  }
  foreach($replacement in $replacements){$Control=$Control.Replace([string]$replacement.anchor,[string]$replacement.value)}
  return $Control
}

function Get-MIR441DerivedFixtureFiles($Row){
  $sourceRoot=Join-Path $repo "fixtures/$($Row.source)"
  $files=[ordered]@{}
  foreach($item in Get-ChildItem -LiteralPath $sourceRoot -File|Sort-Object Name){
    $text=[IO.File]::ReadAllText($item.FullName).Replace([string][char]13,'')
    $text=$text.Replace("mir-fixture-$($Row.source)","mir-fixture-$($Row.name)")
    if($item.Name-ceq'control.lua'){
      $fromRegex=[regex]'(from_version[ ]*=[ ]*")[^"]+(")'
      $toRegex=[regex]'(to_version[ ]*=[ ]*")[^"]+(")'
      if(-not$fromRegex.IsMatch($text)-or-not$toRegex.IsMatch($text)){throw "[mir441-fixture-source-version] $($Row.source)"}
      $text=$fromRegex.Replace($text,{param($match)$match.Groups[1].Value+[string]$Row.from+$match.Groups[2].Value},1)
      $text=$toRegex.Replace($text,{param($match)$match.Groups[1].Value+[string]$Row.to+$match.Groups[2].Value},1)
      $text=$text.Replace([string]$Row.old_save,[string]$Row.save)
      if($Row.factorio-ceq'2.1'){$text=Add-MIR441SpaceAgeCatalogueOracle -Control $text -SaveName ([string]$Row.save)}
    }elseif($item.Name-ceq'info.json'){
      $info=$text|ConvertFrom-Json -Depth 20
      $info.name="mir-fixture-$($Row.name)"
      $info.title="MIR Fixture - Assert $($Row.from) to $($Row.to) Upgrade"
      $dependencies=[Collections.Generic.List[string]]::new()
      $dependencies.Add("base >= $($Row.base)")
      if($Row.factorio-ceq'2.1'){$dependencies.Add("(?) space-age >= $($Row.base)")}
      $dependencies.Add("more-infinite-research >= $($Row.from)")
      $info.dependencies=@($dependencies)
      $text=($info|ConvertTo-Json -Depth 20).Replace([string][char]13,'')+$lf
    }elseif($item.Name-ceq'settings-updates.lua'){
      $transitionRegex=[regex]'missing [0-9]+(?:[.][0-9]+)+ to [0-9]+(?:[.][0-9]+)+ upgrade setting'
      $text=$transitionRegex.Replace($text,"missing $($Row.from) to $($Row.to) upgrade setting")
    }
    $files[$item.Name]=$text
  }
  return $files
}

foreach($row in $rows){
  $targetRoot=Join-Path $repo "fixtures/$($row.name)"
  $files=Get-MIR441DerivedFixtureFiles -Row $row
  if($Check){
    if(-not(Test-Path -LiteralPath $targetRoot -PathType Container)){throw "[mir441-fixture-missing] $($row.name)"}
    $actual=@(Get-ChildItem -LiteralPath $targetRoot -File|Sort-Object Name|ForEach-Object{$_.Name})
    if(($actual-join'|')-cne(@($files.Keys)-join'|')){throw "[mir441-fixture-file-set] $($row.name)"}
    foreach($name in $files.Keys){
      if([IO.File]::ReadAllText((Join-Path $targetRoot $name)).Replace([string][char]13,'')-cne[string]$files[$name]){throw "[mir441-fixture-stale] $($row.name)/$name"}
    }
  }else{
    if(-not(Test-Path -LiteralPath $targetRoot)){New-Item -ItemType Directory -Path $targetRoot|Out-Null}
    foreach($name in $files.Keys){[IO.File]::WriteAllText((Join-Path $targetRoot $name),[string]$files[$name],[Text.UTF8Encoding]::new($false))}
  }
}

$catalogPath=Join-Path $repo '.mir/fixtures.yml'
$catalog=[IO.File]::ReadAllText($catalogPath).Replace([string][char]13,'')
$start='# MIR441-DIRECT-UPGRADE-FIXTURES-BEGIN'
$end='# MIR441-DIRECT-UPGRADE-FIXTURES-END'
$builder=[Text.StringBuilder]::new()
[void]$builder.AppendLine($start)
foreach($row in $rows){
  $key=([string]$row.name).Substring('assert-'.Length)
  [void]$builder.AppendLine("  ${key}:")
  [void]$builder.AppendLine('    requires_features: []')
  [void]$builder.AppendLine("    assertion_path: fixtures/$($row.name)")
  [void]$builder.AppendLine('    harness: tests/runtime/Test-MIRUpgradeMatrix.ps1')
  [void]$builder.AppendLine("    primary_source_version: $($row.from)")
  [void]$builder.AppendLine('    archetypes:')
  foreach($archetype in $row.archetypes){[void]$builder.AppendLine("      - $archetype")}
  [void]$builder.AppendLine('    validates:')
  foreach($claim in @('exact-4-0-source-archive','stable-technology-and-setting-identity-retention','current-research-and-fractional-progress-retention','fixture-state-retention','upgraded-save-two-reload-proof','exact-4-1-candidate-normal-mod-directory-load')){[void]$builder.AppendLine("      - $claim")}
  [void]$builder.AppendLine('')
}
[void]$builder.AppendLine($end)
$expectedBlock=$builder.ToString().Replace([string][char]13,'').TrimEnd()+$lf
if($catalog.Contains($start)){
  $first=$catalog.IndexOf($start,[StringComparison]::Ordinal)
  $last=$catalog.IndexOf($end,$first,[StringComparison]::Ordinal)
  if($last-lt0){throw '[mir441-fixture-catalog-marker]'}
  $lineEnd=$catalog.IndexOf($lf,$last,[StringComparison]::Ordinal)
  if($lineEnd-lt0){$lineEnd=$catalog.Length-1}
  $expected=$catalog.Substring(0,$first)+$expectedBlock+$catalog.Substring($lineEnd+1)
}else{$expected=$catalog.TrimEnd()+$lf+$lf+$expectedBlock}
if($Check){
  if($catalog-cne$expected){throw '[mir441-fixture-catalog-stale]'}
}else{[IO.File]::WriteAllText($catalogPath,$expected,[Text.UTF8Encoding]::new($false))}

[pscustomobject][ordered]@{status='MIR-4.1-DIRECT-UPGRADE-FIXTURES-PASSED';fixture_count=$rows.Count;check=[bool]$Check;publication_authorized=$false}
