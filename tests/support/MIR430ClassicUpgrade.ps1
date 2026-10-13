Set-StrictMode -Version Latest

# Reduced-policy upgrade helpers. They construct a bounded fixture oracle for
# the five declared direct Classic rows and capture the actual MIR-prefix
# catalogue around the upgrade. The fixture deliberately does not claim
# preservation for unseen saves or non-Classic compiler modes.

function Assert-MIR430ClassicUpgradeMode {
  param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$SourceVersion,
    [Parameter(Mandatory)][string]$FromVersion,
    [Parameter(Mandatory)][string]$ToVersion,
    [Parameter(Mandatory)][string]$FixtureName,
    [Parameter(Mandatory)][string]$Archetype,
    [bool]$SpaceIsFake = $false,
    [string]$K2ImersiteInputProfile = '',
    [string]$F200BobAngelInputProfile = ''
  )
  if($SourceVersion -cne '4.3.0' -or $Target -cnotin @('f210','f200','f110','f100') -or
      $FixtureName -cne ('assert-upgrade-4-0-'+$Target.Substring(1)+'00-to-4-1-'+$Target.Substring(1)+'00') -or
      $Archetype -cne 'base-default' -or $SpaceIsFake -or $K2ImersiteInputProfile -or $F200BobAngelInputProfile) {
    throw '[mir430-classic-upgrade-mode]'
  }
  if($FromVersion -cnotmatch ('^4[.]2[.]'+$Target.Substring(1)+'(00|01|02)$') -or
      $ToVersion -cne ('4.3.'+$Target.Substring(1)+'00')) {
    throw '[mir430-classic-upgrade-transition]'
  }
}

function Get-MIR430ClassicUpgradeFixtureControl {
  param([Parameter(Mandatory)][string]$FromVersion,[Parameter(Mandatory)][string]$ToVersion)
  # The technology ids and Classic effect are declarations, not inferred
  # output. If any named technology is absent, Factorio fails the fixture.
  @'
local from_version = "__FROM_VERSION__"
local to_version = "__TO_VERSION__"
local mir_prefix = "recipe-prod-research_"
local omitted_name = "recipe-prod-research_iron-1"
local base_name = "mining-productivity-4"
local compiler_setting = "mir-compiler-profile"
local expected_progress = 0.42
local epsilon = 0.000001
local loaded = false
local direct_rows = {
  {
    name = "recipe-prod-research_inventory_capacity-1",
    effects = {
      {type = "character-inventory-slots-bonus", modifier = 1},
      {type = "character-logistic-trash-slots", modifier = 1}
    }
  },
  {
    name = "recipe-prod-research_character_crafting_speed-1",
    effects = {{type = "character-crafting-speed", modifier = 0.05}}
  },
  {
    name = "recipe-prod-research_character_mining_speed-1",
    effects = {{type = "character-mining-speed", modifier = 0.05}}
  },
  {
    name = "recipe-prod-research_character_reach-1",
    effects = {
      {type = "character-reach-distance", modifier = 10},
      {type = "character-build-distance", modifier = 10},
      {type = "character-resource-reach-distance", modifier = 10},
      {type = "character-item-drop-distance", modifier = 10}
    }
  },
  {
    name = "recipe-prod-research_character_walking_speed-1",
    effects = {{type = "character-running-speed", modifier = 0.05}}
  }
}
local direct_queue = {
  "recipe-prod-research_character_crafting_speed-1",
  "recipe-prod-research_inventory_capacity-1",
  "recipe-prod-research_character_mining_speed-1",
  "recipe-prod-research_character_reach-1",
  "recipe-prod-research_character_walking_speed-1"
}
local direct_by_name = {}
for _, row in ipairs(direct_rows) do direct_by_name[row.name] = row end
local native_names = {
  "braking-force-1", "research-speed-1", "worker-robots-storage-1",
  "inserter-capacity-bonus-1", "weapon-shooting-speed-1", "laser-shooting-speed-1"
}
local base_force_effect_fields = {"mining_drill_productivity_bonus"}
local native_force_effect_fields = {
  "train_braking_force_bonus",
  "laboratory_speed_modifier", "worker_robots_storage_bonus",
  "inserter_stack_size_bonus"
}
local native_gun_speed_categories = {"bullet", "laser"}
local direct_force_effect_fields = {
  "character_inventory_slots_bonus",
  "character_trash_slot_count", "manual_crafting_speed_modifier",
  "manual_mining_speed_modifier", "character_reach_distance_bonus",
  "character_build_distance_bonus", "character_resource_reach_distance_bonus",
  "character_item_drop_distance_bonus", "character_running_speed_modifier"
}
-- Factorio 2.x exposes persistent state as storage; the retained F1.0/F1.1
-- target fixtures use global.  This fixture is intentionally target-local.
local state_root = storage or global

local function fail(message)
  error("MIR Classic upgrade fixture failed: " .. message)
end

local function force()
  local value = game.forces.player
  if not value then fail("player force missing") end
  return value
end

local function technology(name)
  local value = force().technologies[name]
  if not value then fail("required technology missing: " .. name) end
  return value
end

local function effects(value)
  local out = {}
  for _, effect in pairs((value.prototype and value.prototype.effects) or {}) do
    out[#out + 1] = {type = effect.type, modifier = effect.modifier, ammo_category = effect.ammo_category}
  end
  table.sort(out, function(left, right)
    return tostring(left.type) .. ":" .. tostring(left.ammo_category or "") < tostring(right.type) .. ":" .. tostring(right.ammo_category or "")
  end)
  return out
end

local function ingredients(value)
  local out = {}
  for _, ingredient in pairs(value.research_unit_ingredients or {}) do
    out[#out + 1] = {
      name = ingredient.name or ingredient[1],
      amount = ingredient.amount or ingredient[2]
    }
  end
  table.sort(out, function(left, right)
    return tostring(left.name) .. ":" .. tostring(left.amount) < tostring(right.name) .. ":" .. tostring(right.amount)
  end)
  return out
end

local function prerequisites(value)
  local out = {}
  for _, prerequisite in pairs(value.prerequisites or {}) do out[#out + 1] = prerequisite.name end
  table.sort(out)
  return out
end

local function write_snapshot_file(name, value)
  if helpers and helpers.write_file and helpers.table_to_json then
    helpers.write_file(name, helpers.table_to_json(value))
  elseif game.write_file and game.table_to_json then
    game.write_file(name, game.table_to_json(value), false)
  else
    fail("no supported JSON snapshot writer")
  end
end

local function has_expected_effects(value, expected)
  local actual = effects(value)
  if #actual ~= #expected then return false end
  local expected_copy = {}
  for index, effect in ipairs(expected) do
    expected_copy[index] = {type = effect.type, modifier = effect.modifier, ammo_category = effect.ammo_category}
  end
  table.sort(expected_copy, function(left, right)
    return tostring(left.type) .. ":" .. tostring(left.ammo_category or "") < tostring(right.type) .. ":" .. tostring(right.ammo_category or "")
  end)
  for index, effect in ipairs(actual) do
    local wanted = expected_copy[index]
    if effect.type ~= wanted.type or effect.modifier ~= wanted.modifier or effect.ammo_category ~= wanted.ammo_category then
      return false
    end
  end
  return true
end

local function queue_names()
  local out = {}
  for _, value in ipairs(force().research_queue or {}) do out[#out + 1] = value.name end
  return out
end

local function state_for_value(name, value)
  return {
    name = name,
    level = value.level,
    researched = value.researched,
    enabled = value.enabled,
    unit_count = value.research_unit_count,
    unit_energy = value.research_unit_energy,
    unit_ingredients = ingredients(value),
    prerequisites = prerequisites(value),
    effects = effects(value),
    hidden = value.prototype and value.prototype.hidden or false,
    max_level = value.prototype and value.prototype.max_level or false
  }
end

local function state_for(name)
  return state_for_value(name, technology(name))
end

local function states_for_names(names, required)
  local out = {}
  for _, name in ipairs(names) do
    local value = force().technologies[name]
    if value then
      out[#out + 1] = state_for_value(name, value)
    elseif required then
      fail("required technology missing: " .. name)
    end
  end
  table.sort(out, function(left, right) return left.name < right.name end)
  return out
end

local function mir_prefix_states()
  local out = {}
  for name, value in pairs(force().technologies) do
    if string.sub(name, 1, #mir_prefix) == mir_prefix then
      out[#out + 1] = state_for_value(name, value)
    end
  end
  table.sort(out, function(left, right) return left.name < right.name end)
  return out
end

local function force_effects(fields)
  local out, value = {}, force()
  for _, field in ipairs(fields) do
    local current = value[field]
    if type(current) ~= "number" then fail("force modifier missing: " .. field) end
    out[field] = current
  end
  return out
end

local function gun_speed_modifiers(categories)
  local out, value = {}, force()
  if type(value.get_gun_speed_modifier) ~= "function" then
    fail("gun speed modifier reader missing")
  end
  for _, category in ipairs(categories) do
    local current = value.get_gun_speed_modifier(category)
    if type(current) ~= "number" then
      fail("gun speed modifier missing: " .. category)
    end
    out[category] = current
  end
  return out
end

local function same_sequence(left, right)
  if #left ~= #right then return false end
  for index, value in ipairs(left) do if value ~= right[index] then return false end end
  return true
end

local function by_name(rows)
  local out = {}
  for _, row in ipairs(rows) do out[row.name] = row end
  return out
end

local function same_state(left, right)
  if not left or not right then return false end
  return left.name == right.name and left.level == right.level and left.researched == right.researched and left.enabled == right.enabled
end

local function same_map(left, right)
  for key, value in pairs(left) do if right[key] ~= value then return false end end
  for key, value in pairs(right) do if left[key] ~= value then return false end end
  return true
end

local function declared_direct_ids()
  local out = {}
  for _, row in ipairs(direct_rows) do out[#out + 1] = row.name end
  table.sort(out)
  return out
end

local function write_snapshot(stage)
  local value = force()
  local base = state_for(base_name)
  -- Retain the original narrow fields as a compatibility projection for the
  -- existing release reader. The complete arrays below are the candidate-bound
  -- Classic catalogue evidence.
  local core = state_for(direct_queue[1])
  core.current_research = value.current_research and value.current_research.name or false
  core.research_progress = value.research_progress or 0
  core.queue = queue_names()
  core.force_modifier = value.manual_crafting_speed_modifier
  base.force_modifier = value.mining_drill_productivity_bonus
  local compiler = settings.startup[compiler_setting]
  write_snapshot_file("mir-upgrade-classic-state-" .. stage .. ".json", {
    schema = 1,
    kind = "MIR430ClassicUpgradeSnapshotV1",
    stage = stage,
    from_version = from_version,
    to_version = to_version,
    compiler_profile = compiler and compiler.value or false,
    -- The legacy source retains its whole MIR prefix here. The candidate is
    -- deliberately not a full-catalogue evaluation; that status remains
    -- explicit in every candidate snapshot and receipt.
    full_catalog_status = stage == "source" and "source-full" or "not-evaluated",
    base = base,
    retained_core = core,
    omitted = {
      technology_id = omitted_name,
      source_present = true,
      candidate_present = value.technologies[omitted_name] ~= nil,
      consequence = stage == "source" and "not-yet-applied" or "removed-reduced-policy-no-preservation"
    },
    base_force_effects = force_effects(base_force_effect_fields),
    current_research = value.current_research and value.current_research.name or false,
    research_progress = value.research_progress or 0,
    research_queue = queue_names(),
    declared_direct_ids = declared_direct_ids(),
    declared_direct_technologies = states_for_names(declared_direct_ids(), false),
    declared_direct_force_effects = force_effects(direct_force_effect_fields),
    mir_prefix_technologies = mir_prefix_states(),
    native_technologies = states_for_names(native_names, false),
    native_force_effects = force_effects(native_force_effect_fields),
    native_gun_speed_modifiers = gun_speed_modifiers(native_gun_speed_categories),
    known_omitted_id = omitted_name
  })
end

local function assert_retained(stage)
  local state = state_root.mir430_classic_upgrade
  if not state or state.from_version ~= from_version or state.to_version ~= to_version then fail(stage .. " lost fixture state") end
  if not settings.startup[compiler_setting] or settings.startup[compiler_setting].value ~= "classic" then
    fail(stage .. " did not select Classic compiler profile")
  end
  local source_direct = by_name(state.source_direct)
  for _, declaration in ipairs(direct_rows) do
    local source = source_direct[declaration.name]
    local candidate = force().technologies[declaration.name]
    if not source or not candidate or not same_state(source, state_for_value(declaration.name, candidate))
        or not has_expected_effects(candidate, declaration.effects) then
      fail(stage .. " changed retained Classic direct state or declared effect: " .. declaration.name)
    end
  end
  if not force().current_research or force().current_research.name ~= direct_queue[1] then
    fail(stage .. " changed retained Classic current research")
  end
  if not same_sequence(queue_names(), state.source_queue) then
    fail(stage .. " changed retained Classic research queue")
  end
  local core = technology(direct_queue[1])
  local expected = math.max(0, math.min(1, state.source_progress * state.source_current_unit_count / core.research_unit_count))
  if math.abs((force().research_progress or 0) - expected) > epsilon then
    fail(stage .. " changed retained Classic completed research work")
  end
  if not same_state(state.source_base, state_for(base_name)) or not same_map(state.source_base_force_effects, force_effects(base_force_effect_fields)) then
    fail(stage .. " changed base research integrity")
  end
  local source_native = by_name(state.source_native)
  for name, source in pairs(source_native) do
    local candidate = force().technologies[name]
    if not candidate or not same_state(source, state_for_value(name, candidate)) then
      fail(stage .. " changed native research integrity: " .. name)
    end
  end
  if not same_map(state.source_native_force_effects, force_effects(native_force_effect_fields)) or
      not same_map(state.source_native_gun_speed_modifiers, gun_speed_modifiers(native_gun_speed_categories)) then
    fail(stage .. " changed native force effects")
  end
  local source_prefix = by_name(state.source_mir_prefix)
  local candidate_prefix = by_name(mir_prefix_states())
  for name in pairs(source_prefix) do
    if direct_by_name[name] then
      if not candidate_prefix[name] then fail(stage .. " removed declared Classic direct research: " .. name) end
    elseif candidate_prefix[name] then
      fail(stage .. " retained unsupported MIR-prefix research: " .. name)
    end
  end
  for name in pairs(candidate_prefix) do
    if not direct_by_name[name] then fail(stage .. " emitted undeclared MIR-prefix research: " .. name) end
  end
  if candidate_prefix[omitted_name] then
    fail(stage .. " retained known omitted 4.2 research")
  end
end

script.on_init(function()
  if script.active_mods["more-infinite-research"] ~= from_version then fail("source version drift") end
  local value = force()
  local omitted, base = technology(omitted_name), technology(base_name)
  local direct = {}
  for _, declaration in ipairs(direct_rows) do direct[declaration.name] = technology(declaration.name) end
  value.research_all_technologies()
  for index, name in ipairs(direct_queue) do
    direct[name].level = index + 2
    direct[name].researched = false
  end
  if value.reset_technology_effects then value.reset_technology_effects() end
  for _, name in ipairs(direct_queue) do
    if not value.add_research(direct[name]) then fail("could not queue source Classic direct research: " .. name) end
  end
  value.research_progress = expected_progress
  state_root.mir430_classic_upgrade = {
    from_version = from_version, to_version = to_version,
    source_direct = states_for_names(declared_direct_ids(), true),
    source_queue = queue_names(),
    source_progress = value.research_progress,
    source_current_unit_count = direct[direct_queue[1]].research_unit_count,
    source_base = state_for_value(base_name, base),
    source_base_force_effects = force_effects(base_force_effect_fields),
    source_native = states_for_names(native_names, false),
    source_native_force_effects = force_effects(native_force_effect_fields),
    source_native_gun_speed_modifiers = gun_speed_modifiers(native_gun_speed_categories),
    source_mir_prefix = mir_prefix_states(),
    omitted_was_present = omitted ~= nil
  }
  if not state_root.mir430_classic_upgrade.omitted_was_present then fail("source omitted subject absent") end
  if not same_sequence(state_root.mir430_classic_upgrade.source_queue, direct_queue) then
    fail("source Classic direct research queue was not retained exactly")
  end
  write_snapshot("source")
  log("[mir-fixture] " .. from_version .. " classic reduced-policy source proof complete")
end)

script.on_configuration_changed(function()
  if script.active_mods["more-infinite-research"] ~= to_version then fail("candidate version drift") end
  assert_retained("upgrade")
  write_snapshot("upgrade")
  state_root.mir430_classic_upgrade.upgrade_complete = true
  log("[mir-fixture] " .. from_version .. " to " .. to_version .. " classic reduced-policy upgrade proof complete")
end)

script.on_load(function()
  loaded = state_root.mir430_classic_upgrade and state_root.mir430_classic_upgrade.upgrade_complete or false
end)

script.on_event(defines.events.on_tick, function()
  if loaded then
    assert_retained("reload")
    write_snapshot("reload")
    log("[mir-fixture] " .. to_version .. " classic reduced-policy reload proof complete")
    loaded = false
  end
  local state = state_root.mir430_classic_upgrade
  if state and state.upgrade_complete and not state.server_save_requested then
    state.server_save_requested = true
    game.server_save("mir-430-classic-upgraded")
  end
end)
'@.Replace('__FROM_VERSION__',$FromVersion).Replace('__TO_VERSION__',$ToVersion)
}

function Set-MIR430ClassicUpgradeFixture {
  param(
    [Parameter(Mandatory)][string]$FixtureDirectory,
    [Parameter(Mandatory)][string]$FromVersion,
    [Parameter(Mandatory)][string]$ToVersion
  )
  if(-not(Test-Path -LiteralPath $FixtureDirectory -PathType Container)){throw '[mir430-classic-upgrade-fixture-directory]'}
  [IO.File]::WriteAllText((Join-Path $FixtureDirectory 'control.lua'),
    (Get-MIR430ClassicUpgradeFixtureControl -FromVersion $FromVersion -ToVersion $ToVersion),
    [Text.UTF8Encoding]::new($false))
}

function Assert-MIR430ClassicUpgradeMarker {
  param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)][ValidateSet('source','upgrade','reload')][string]$Stage)
  $needle = switch($Stage) {
    'source' {'classic reduced-policy source proof complete'}
    'upgrade' {'classic reduced-policy upgrade proof complete'}
    'reload' {'classic reduced-policy reload proof complete'}
  }
  if(-not $Text.Contains($needle)){throw '[mir430-classic-upgrade-marker]'}
}

function Copy-MIR430ClassicUpgradeSnapshotEvidence {
  param(
    [Parameter(Mandatory)][ValidateSet('source','upgrade','reload')][string]$SnapshotStage,
    [Parameter(Mandatory)][ValidateSet('source','upgrade','reload-1','reload-2')][string]$EvidenceStage,
    [Parameter(Mandatory)][string]$UserdataRoot,
    [Parameter(Mandatory)][string]$OutputParent,
    [Parameter(Mandatory)][string]$ToVersion,
    [Parameter(Mandatory)][string]$ArtifactSlug,
    [Parameter(Mandatory)][string]$FromVersion
  )
  $snapshot=Join-Path $UserdataRoot ('script-output/mir-upgrade-classic-state-'+$SnapshotStage+'.json')
  if(-not(Test-Path -LiteralPath $snapshot -PathType Leaf)){throw '[mir430-classic-upgrade-snapshot-missing]'}
  $value=Get-Content -LiteralPath $snapshot -Raw|ConvertFrom-Json -AsHashtable -Depth 100
  if($value.schema-ne1-or$value.kind-cne'MIR430ClassicUpgradeSnapshotV1'-or$value.stage-cne$SnapshotStage-or
      $value.from_version-cne$FromVersion-or$value.to_version-cne$ToVersion){throw '[mir430-classic-upgrade-snapshot-identity]'}
  $destination=Join-Path $OutputParent ("$ToVersion-upgrade-$ArtifactSlug-from-$FromVersion-classic-$EvidenceStage.json")
  Copy-Item -LiteralPath $snapshot -Destination $destination
  return [ordered]@{stage=$EvidenceStage;snapshot_stage=$SnapshotStage;path=$destination;sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $destination).Length}
}

function Get-MIR430ClassicSnapshotValue {
  param([Parameter(Mandatory)][Collections.IDictionary]$Snapshot,[Parameter(Mandatory)][string]$Name)
  if(-not $Snapshot.Contains($Name)){throw "[mir430-classic-upgrade-snapshot-field] $Name"}
  return $Snapshot[$Name]
}

function ConvertTo-MIR430ClassicSnapshotJson {
  param([Parameter(Mandatory)]$Value)
  return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Get-MIR430ClassicSnapshotMap {
  param([Parameter(Mandatory)]$Rows,[Parameter(Mandatory)][string]$Name)
  if($Rows -isnot [array]){throw "[mir430-classic-upgrade-$Name-shape]"}
  $map=@{}
  foreach($row in @($Rows)){
    if($row -isnot [Collections.IDictionary] -or -not $row.Contains('name') -or [string]::IsNullOrWhiteSpace([string]$row['name']) -or
        $map.ContainsKey([string]$row['name'])){throw "[mir430-classic-upgrade-$Name-shape]"}
    $map[[string]$row['name']]=$row
  }
  return $map
}

function Get-MIR430ClassicStateProjection {
  param([Parameter(Mandatory)][Collections.IDictionary]$State)
  $projection=[ordered]@{}
  foreach($field in @('name','level','researched','enabled')){
    if(-not $State.Contains($field)){throw "[mir430-classic-upgrade-state-field] $field"}
    $projection[$field]=$State[$field]
  }
  return $projection
}

function Get-MIR430ClassicDefinitionProjection {
  param([Parameter(Mandatory)][Collections.IDictionary]$State)
  $projection=[ordered]@{}
  foreach($field in @('unit_count','unit_energy','unit_ingredients','prerequisites','effects','hidden','max_level')){
    if(-not $State.Contains($field)){throw "[mir430-classic-upgrade-definition-field] $field"}
    $projection[$field]=$State[$field]
  }
  return $projection
}

function Get-MIR430ClassicCatalogDisposition {
  param(
    [Parameter(Mandatory)][Collections.IDictionary]$Source,
    [Parameter(Mandatory)][Collections.IDictionary]$Candidate
  )
  foreach($snapshot in @($Source,$Candidate)){
    if([int]$snapshot['schema'] -ne 1 -or [string]$snapshot['kind'] -cne 'MIR430ClassicUpgradeSnapshotV1'){
      throw '[mir430-classic-upgrade-snapshot-shape]'
    }
  }
  $sourcePrefix=Get-MIR430ClassicSnapshotMap -Rows (Get-MIR430ClassicSnapshotValue $Source 'mir_prefix_technologies') -Name 'mir-prefix'
  $candidatePrefix=Get-MIR430ClassicSnapshotMap -Rows (Get-MIR430ClassicSnapshotValue $Candidate 'mir_prefix_technologies') -Name 'mir-prefix'
  $sourceDirect=@(Get-MIR430ClassicSnapshotValue $Source 'declared_direct_ids')
  $candidateDirect=@(Get-MIR430ClassicSnapshotValue $Candidate 'declared_direct_ids')
  $expectedDirect=@(
    'recipe-prod-research_inventory_capacity-1',
    'recipe-prod-research_character_crafting_speed-1',
    'recipe-prod-research_character_mining_speed-1',
    'recipe-prod-research_character_reach-1',
    'recipe-prod-research_character_walking_speed-1'
  )
  $sourceDirectSet=(@($sourceDirect | Sort-Object) -join '|')
  $candidateDirectSet=(@($candidateDirect | Sort-Object) -join '|')
  $expectedDirectSet=(@($expectedDirect | Sort-Object) -join '|')
  if($sourceDirectSet -cne $expectedDirectSet -or $candidateDirectSet -cne $expectedDirectSet -or $sourceDirect.Count -ne $expectedDirect.Count){
    throw '[mir430-classic-upgrade-declared-direct-set]'
  }
  $direct=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($id in $sourceDirect){
    if(([string]$id -notmatch '^recipe-prod-research_.+?-1$') -or -not $direct.Add([string]$id)){throw '[mir430-classic-upgrade-declared-direct-set]'}
  }
  $sourceDeclared=Get-MIR430ClassicSnapshotMap -Rows (Get-MIR430ClassicSnapshotValue $Source 'declared_direct_technologies') -Name 'declared-direct'
  $candidateDeclared=Get-MIR430ClassicSnapshotMap -Rows (Get-MIR430ClassicSnapshotValue $Candidate 'declared_direct_technologies') -Name 'declared-direct'
  if($sourceDeclared.Count -ne $sourceDirect.Count -or $candidateDeclared.Count -ne $sourceDirect.Count){throw '[mir430-classic-upgrade-declared-direct-catalog]'}
  foreach($id in $sourceDirect){
    $sourceRow=$sourcePrefix[$id];$candidateRow=$candidatePrefix[$id]
    if($null -eq $sourceRow -or $null -eq $candidateRow -or $null -eq $sourceDeclared[$id] -or $null -eq $candidateDeclared[$id] -or
        (ConvertTo-MIR430ClassicSnapshotJson $sourceRow) -cne (ConvertTo-MIR430ClassicSnapshotJson $sourceDeclared[$id]) -or
        (ConvertTo-MIR430ClassicSnapshotJson $candidateRow) -cne (ConvertTo-MIR430ClassicSnapshotJson $candidateDeclared[$id])){
      throw '[mir430-classic-upgrade-declared-direct-catalog]'
    }
  }
  $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($name in @($sourcePrefix.Keys)+@($candidatePrefix.Keys)){[void]$names.Add([string]$name)}
  $dispositions=@()
  foreach($name in @($names | Sort-Object)){
    $before=$sourcePrefix[$name];$after=$candidatePrefix[$name]
    if($null -ne $before -and $null -ne $after){
      $stateRetained=(ConvertTo-MIR430ClassicSnapshotJson (Get-MIR430ClassicStateProjection $before)) -ceq (ConvertTo-MIR430ClassicSnapshotJson (Get-MIR430ClassicStateProjection $after))
      $definitionChanged=(ConvertTo-MIR430ClassicSnapshotJson (Get-MIR430ClassicDefinitionProjection $before)) -cne (ConvertTo-MIR430ClassicSnapshotJson (Get-MIR430ClassicDefinitionProjection $after))
      $disposition=if($direct.Contains($name)){'retained'}else{'retained-outside-declared-classic-scope'}
      $consequence=if($disposition -ceq 'retained'){'classic-declared-core-definition'}else{'outside-classic-declared-core'}
      $dispositions += [ordered]@{technology_id=$name;source_present=$true;candidate_present=$true;disposition=$disposition;consequence=$consequence;state_retained=$stateRetained;definition_changed=$definitionChanged}
    }elseif($null -ne $before){
      $dispositions += [ordered]@{technology_id=$name;source_present=$true;candidate_present=$false;disposition='removed';consequence='removed-reduced-policy-no-preservation';state_retained=$false;definition_changed=$null}
    }else{
      $dispositions += [ordered]@{technology_id=$name;source_present=$false;candidate_present=$true;disposition='introduced';consequence='unexpected-candidate-mir-prefix';state_retained=$false;definition_changed=$null}
    }
  }
  foreach($id in $sourceDirect){
    $match=@($dispositions | Where-Object { [string]$_.technology_id -ceq [string]$id })
    if($match.Count-ne1 -or -not [bool]$match[0].source_present -or -not [bool]$match[0].candidate_present -or
        -not [bool]$match[0].state_retained){throw '[mir430-classic-upgrade-declared-direct-state]'}
  }
  foreach($row in @($dispositions | Where-Object { [bool]$_.candidate_present -and $_.disposition -ne 'retained' })){
    throw "[mir430-classic-upgrade-undeclared-candidate-prefix] $($row.technology_id)"
  }
  foreach($field in @('base','base_force_effects','native_technologies','native_force_effects','native_gun_speed_modifiers','declared_direct_force_effects','current_research','research_progress','research_queue')){
    $null=Get-MIR430ClassicSnapshotValue $Source $field
    $null=Get-MIR430ClassicSnapshotValue $Candidate $field
  }
  if((ConvertTo-MIR430ClassicSnapshotJson $Source['base']) -cne (ConvertTo-MIR430ClassicSnapshotJson $Candidate['base']) -or
      (ConvertTo-MIR430ClassicSnapshotJson $Source['base_force_effects']) -cne (ConvertTo-MIR430ClassicSnapshotJson $Candidate['base_force_effects']) -or
      (ConvertTo-MIR430ClassicSnapshotJson $Source['native_technologies']) -cne (ConvertTo-MIR430ClassicSnapshotJson $Candidate['native_technologies']) -or
      (ConvertTo-MIR430ClassicSnapshotJson $Source['native_force_effects']) -cne (ConvertTo-MIR430ClassicSnapshotJson $Candidate['native_force_effects']) -or
      (ConvertTo-MIR430ClassicSnapshotJson $Source['native_gun_speed_modifiers']) -cne (ConvertTo-MIR430ClassicSnapshotJson $Candidate['native_gun_speed_modifiers']) -or
      (ConvertTo-MIR430ClassicSnapshotJson $Source['declared_direct_force_effects']) -cne (ConvertTo-MIR430ClassicSnapshotJson $Candidate['declared_direct_force_effects'])){
    throw '[mir430-classic-upgrade-base-native-state]'
  }
  $sourceCurrent=[string]$Source['current_research'];$candidateCurrent=[string]$Candidate['current_research']
  if($sourceCurrent -cne $candidateCurrent -or -not $direct.Contains($sourceCurrent) -or
      (ConvertTo-MIR430ClassicSnapshotJson @($Source['research_queue'])) -cne (ConvertTo-MIR430ClassicSnapshotJson @($Candidate['research_queue']))){
    throw '[mir430-classic-upgrade-current-queue-state]'
  }
  $sourceCore=$sourcePrefix[$sourceCurrent];$candidateCore=$candidatePrefix[$candidateCurrent]
  if($null -eq $sourceCore -or $null -eq $candidateCore){throw '[mir430-classic-upgrade-current-work-state]'}
  $sourceProgress=[double]($Source['research_progress'])
  $sourceUnitCount=[double]($sourceCore['unit_count'])
  $candidateUnitCount=[double]($candidateCore['unit_count'])
  $candidateProgress=[double]($Candidate['research_progress'])
  if($candidateUnitCount -le 0 -or $sourceUnitCount -le 0 -or $sourceProgress -lt 0 -or $sourceProgress -gt 1 -or $candidateProgress -lt 0 -or $candidateProgress -gt 1 -or [double]::IsNaN($sourceUnitCount) -or [double]::IsNaN($candidateUnitCount) -or [double]::IsNaN($sourceProgress) -or [double]::IsNaN($candidateProgress) -or [double]::IsInfinity($sourceUnitCount) -or [double]::IsInfinity($candidateUnitCount) -or [double]::IsInfinity($sourceProgress) -or [double]::IsInfinity($candidateProgress)){throw '[mir430-classic-upgrade-current-work-state]'}
  $expected=[Math]::Max([double]0,[Math]::Min([double]1,[double](($sourceProgress * $sourceUnitCount) / $candidateUnitCount)))
  if([Math]::Abs(($candidateProgress - $expected)) -gt 0.000001){throw '[mir430-classic-upgrade-current-work-state]'}
  return [ordered]@{
    schema=1
    kind='MIR430ClassicActualPrefixCatalogDispositionV1'
    scope='candidate-bound-active-base-default-classic-mir-prefix-catalog'
    source_mir_prefix_count=$sourcePrefix.Count
    candidate_mir_prefix_count=$candidatePrefix.Count
    declared_direct_technology_ids=@($sourceDirect | Sort-Object)
    dispositions=@($dispositions)
  }
}
