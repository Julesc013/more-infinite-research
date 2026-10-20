local from_version, to_version = "4.6.21000", "4.7.21000"
local fixture_name = "mir-fixture-assert-k2-imersite-460-to-470-upgrade"
local legacy_name = "recipe-prod-research_material_imersite-1"
local continuation_name = "recipe-prod-research_material_imersite-4"
local native_name = "kr-imersite-productivity"
local powder_name, crystal_name = "kr-imersite-powder", "kr-imersite-crystal"
local zero_force_name, low_force_name = "mir-k2-migration-zero", "mir-k2-migration-low"
local high_force_name, control_force_name = "mir-k2-migration-high", "mir-k2-migration-control"
local epsilon, infinite_level, progress = 0.000001, 4294967295, 0.42
local loaded, reload_checked = false, false

local function fail(message)
  error("MIR K2 4.6 to 4.7 Imersite migration validation failed: " .. message)
end

local function close(name, actual, expected)
  if type(actual) ~= "number" or math.abs(actual - expected) > epsilon then
    fail(name .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end
end

local function deep_copy(value)
  if type(value) ~= "table" then
    if value == nil or type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
      return value
    end
    fail("unsupported snapshot value " .. type(value))
  end
  local out = {}
  for key, item in pairs(value) do
    if type(key) ~= "string" and type(key) ~= "number" then fail("non-scalar snapshot key") end
    out[key] = deep_copy(item)
  end
  return out
end

local function equal_state(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) == "number" then return math.abs(left - right) <= epsilon end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not equal_state(value, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
end

local function profile(version)
  local expected = {
    base = "2.1.22", Krastorio2 = "2.1.4", ["Krastorio2-spaced-out"] = "2.0.19",
    ["more-infinite-research"] = version, [fixture_name] = "0.1.4700"
  }
  for name, value in pairs(expected) do
    if script.active_mods[name] ~= value then
      fail("wrong input " .. name .. "=" .. tostring(script.active_mods[name]))
    end
  end
end

local function cap()
  local value = settings.startup["ips-max-level-research_material_imersite"].value
  if value ~= 0 then fail("fixture requires explicit unlimited source cap, got " .. tostring(value)) end
  return value
end

local function queue_names(force)
  local out = {}
  for _, technology in ipairs(force.research_queue or {}) do out[#out + 1] = technology.name end
  return out
end

local function same_names(left, right)
  if #left ~= #right then return false end
  for index, value in ipairs(left) do if value ~= right[index] then return false end end
  return true
end

local function technology_prototype_state(technology)
  local prototype = technology.prototype
  if not prototype then fail("technology prototype missing: " .. technology.name) end
  local prerequisites, ingredients = {}, {}
  for name in pairs(prototype.prerequisites) do prerequisites[#prerequisites + 1] = name end
  table.sort(prerequisites)
  for _, ingredient in pairs(technology.research_unit_ingredients) do
    ingredients[#ingredients + 1] = {name = ingredient.name, amount = ingredient.amount}
  end
  table.sort(ingredients, function(a, b) return a.name < b.name end)
  return {
    order = prototype.order, hidden = prototype.hidden, hidden_in_factoriopedia = prototype.hidden_in_factoriopedia,
    max_level = prototype.max_level, prerequisites = prerequisites, ingredients = ingredients,
    effects = deep_copy(prototype.effects), unit_count = technology.research_unit_count,
    unit_count_formula = technology.research_unit_count_formula or false, unit_energy = technology.research_unit_energy
  }
end

local force_effect_fields = {
  "artillery_range_modifier", "beacon_distribution_modifier", "belt_stack_size_bonus",
  "bulk_inserter_capacity_bonus", "character_build_distance_bonus", "character_health_bonus",
  "character_inventory_slots_bonus", "character_item_drop_distance_bonus", "character_item_pickup_distance_bonus",
  "character_loot_pickup_distance_bonus", "character_reach_distance_bonus", "character_resource_reach_distance_bonus",
  "character_running_speed_modifier", "following_robots_lifetime_modifier", "inserter_stack_size_bonus",
  "laboratory_productivity_bonus", "laboratory_speed_modifier", "manual_crafting_speed_modifier",
  "manual_mining_speed_modifier", "train_braking_force_bonus",
  "worker_robots_battery_modifier", "worker_robots_speed_modifier", "worker_robots_storage_bonus"
}

local function complete_state(force)
  local state = {technologies = {}, bonuses = {}, queue = queue_names(force), effects = {}}
  for name, technology in pairs(force.technologies) do
    state.technologies[name] = {
      level = technology.level, researched = technology.researched, enabled = technology.enabled,
      visible_when_disabled = technology.visible_when_disabled, saved_progress = technology.saved_progress,
      prototype = technology_prototype_state(technology)
    }
  end
  for _, name in ipairs(force_effect_fields) do
    if type(force[name]) ~= "number" then fail("force effect unavailable: " .. name) end
    state.effects[name] = force[name]
  end
  for name, recipe in pairs(force.recipes) do state.bonuses[name] = recipe.productivity_bonus end
  state.current_research = force.current_research and force.current_research.name or false
  state.research_progress = force.research_progress
  return state
end

local function all_force_states()
  local out = {}
  for name, force in pairs(game.forces) do out[name] = complete_state(force) end
  return out
end

local function startup_settings()
  local out = {}
  for name, setting in pairs(settings.startup) do out[name] = deep_copy(setting.value) end
  return out
end

local function export_state(stage)
  helpers.write_file("mir-upgrade-full-state-" .. stage .. ".json", helpers.table_to_json({
    from_version = from_version, to_version = to_version, stage = stage,
    active_mods = deep_copy(script.active_mods), startup_settings = startup_settings(), forces = all_force_states()
  }))
end

local function exact_productivity_effect(technology, recipe, expected, label)
  local matches = 0
  for _, effect in pairs(technology.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe then
      matches = matches + 1
      close(label, effect.change, expected)
    end
  end
  if matches ~= 1 then fail(label .. " exact owner/effect missing") end
end

local function no_productivity_effect(technology, recipe, label)
  for _, effect in pairs(technology.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe then
      fail(label .. " crossed ownership boundary")
    end
  end
end

local function source_definition(force)
  local legacy, continuation, native = force.technologies[legacy_name], force.technologies[continuation_name], force.technologies[native_name]
  if continuation then fail("published predecessor unexpectedly contains the 4.7 continuation") end
  if not legacy or legacy.prototype.max_level < infinite_level then
    fail("published 4.6 source must expose its genuine infinite Imersite predecessor")
  end
  exact_productivity_effect(legacy, powder_name, 0.02, "source Imersite powder effect")
  no_productivity_effect(legacy, crystal_name, "source Imersite owner")
  if not native then fail("native Imersite crystal owner absent") end
  exact_productivity_effect(native, crystal_name, 0.10, "native Imersite crystal effect")
  no_productivity_effect(native, powder_name, "native Imersite owner")
end

local function candidate_definitions(force)
  local legacy, continuation, native = force.technologies[legacy_name], force.technologies[continuation_name], force.technologies[native_name]
  if not legacy or legacy.prototype.max_level ~= 3 then
    fail("candidate finite Imersite levels one through three are absent")
  end
  exact_productivity_effect(legacy, powder_name, 0.02, "candidate finite Imersite powder effect")
  no_productivity_effect(legacy, crystal_name, "candidate finite Imersite owner")
  if not continuation or continuation.prototype.max_level < infinite_level or not continuation.enabled then
    fail("candidate level-four Imersite continuation is absent")
  end
  exact_productivity_effect(continuation, powder_name, 0.02, "candidate continuation powder effect")
  no_productivity_effect(continuation, crystal_name, "candidate continuation owner")
  local follows_legacy = false
  for _, prerequisite in pairs(continuation.prerequisites) do
    if prerequisite.name == legacy_name then follows_legacy = true end
  end
  if not follows_legacy then fail("candidate continuation does not require finite Imersite stage") end
  if not native then fail("candidate native Imersite crystal owner absent") end
  exact_productivity_effect(native, crystal_name, 0.10, "candidate native Imersite crystal effect")
  no_productivity_effect(native, powder_name, "candidate native Imersite owner")
end

local function seed_infinite_progress(force, completed)
  local legacy = force.technologies[legacy_name]
  source_definition(force)
  force.research_all_technologies()
  if force.current_research then force.cancel_current_research() end
  legacy.enabled = true
  -- For an infinite technology, `level` is the next level. Assigning four
  -- therefore preserves three completed 2% effects; assigning eight preserves seven.
  local next_level = completed + 1
  legacy.level = next_level
  if legacy.level ~= next_level or legacy.researched then
    fail("could not seed genuine infinite Imersite completed=" .. tostring(completed))
  end
  force.reset_technology_effects()
  if not force.add_research(legacy) or not force.current_research or force.current_research.name ~= legacy_name then
    fail("could not queue source infinite Imersite next level " .. tostring(next_level))
  end
  force.research_queue = {legacy}
  force.research_progress = progress
  close("seeded powder productivity " .. force.name, force.recipes[powder_name].productivity_bonus, completed * 0.02)
  close("seeded independent crystal productivity " .. force.name, force.recipes[crystal_name].productivity_bonus, 0.10)
  if not same_names(queue_names(force), {legacy_name}) or not force.current_research
      or force.current_research.name ~= legacy_name then
    fail("source infinite Imersite queue differs for " .. force.name)
  end
  close("seeded research progress " .. force.name, force.research_progress, progress)
  return {force_name = force.name, completed = completed, next_level = next_level, powder_bonus = completed * 0.02}
end

-- Independently reviewed V7 phase retirement on the published predecessor.
-- These identities come from its manifests and declared late-science inputs;
-- the destination cannot teach this oracle which changes to accept.
local v7_phase_two_technologies = {
  ["braking-force-8"] = true,
  ["laser-shooting-speed-8"] = true,
  ["recipe-prod-research_artificial_soil-1"] = true,
  ["recipe-prod-research_belts-1"] = true,
  ["recipe-prod-research_bullets-1"] = true,
  ["recipe-prod-research_carbon-1"] = true,
  ["recipe-prod-research_cargo_bay_unloading_distance-1"] = true,
  ["recipe-prod-research_cargo_landing_pad_count-1"] = true,
  ["recipe-prod-research_concrete-1"] = true,
  ["recipe-prod-research_flamethrower_shooting_speed-1"] = true,
  ["recipe-prod-research_grenades-1"] = true,
  ["recipe-prod-research_heavy_ammo-1"] = true,
  ["recipe-prod-research_ice-1"] = true,
  ["recipe-prod-research_inserters-1"] = true,
  ["recipe-prod-research_landfill-1"] = true,
  ["recipe-prod-research_platform-1"] = true,
  ["recipe-prod-research_rails-1"] = true,
  ["recipe-prod-research_robot_battery-1"] = true,
  ["recipe-prod-research_science_pack_productivity-1"] = true,
  ["recipe-prod-research_spoilage_preservation-1"] = true,
  ["recipe-prod-research_thruster_fuel_productivity-1"] = true,
  ["recipe-prod-research_thruster_oxidizer_productivity-1"] = true,
  ["recipe-prod-research_walls-1"] = true,
  ["research-speed-7"] = true,
  ["weapon-shooting-speed-7"] = true,
}
local v7_early_science = {
  ["kr-basic-tech-card"] = true, ["automation-science-pack"] = true,
  ["logistic-science-pack"] = true, ["military-science-pack"] = true,
  ["chemical-science-pack"] = true
}
local v7_phase_two_triggers = {
  ["space-science-pack"] = true, ["kr-advanced-tech-card"] = true,
  ["kr-matter-tech-card"] = true, ["kr-singularity-tech-card"] = true
}

local function expected_policy_technology_state(name, prior)
  if not v7_phase_two_technologies[name] then return prior end
  local expected = deep_copy(prior)
  local has_late_source = false
  for _, ingredient in ipairs(prior.prototype.ingredients) do
    if v7_phase_two_triggers[ingredient.name] then has_late_source = true end
  end
  if not has_late_source then fail("reviewed V7 predecessor lost its late-science trigger: " .. name) end
  local ingredients, prerequisites = {}, {}
  for _, ingredient in ipairs(prior.prototype.ingredients) do
    if not v7_early_science[ingredient.name] then ingredients[#ingredients + 1] = deep_copy(ingredient) end
  end
  for _, prerequisite in ipairs(prior.prototype.prerequisites) do
    if not v7_early_science[prerequisite] then prerequisites[#prerequisites + 1] = prerequisite end
  end
  expected.prototype.ingredients, expected.prototype.prerequisites = ingredients, prerequisites
  return expected
end

local function verify_unrelated_state(name, force, before)
  local current = complete_state(force)
  for technology_name, prior in pairs(before.technologies) do
    local observed = current.technologies[technology_name]
    if not observed then fail("existing technology disappeared for " .. name .. ": " .. technology_name) end
    if technology_name ~= legacy_name and not equal_state(observed, expected_policy_technology_state(technology_name, prior)) then
      fail("unrelated technology state or definition changed for " .. name .. ": " .. technology_name)
    end
  end
  for technology_name in pairs(current.technologies) do
    if not before.technologies[technology_name] and technology_name ~= continuation_name then
      fail("unexpected technology added for " .. name .. ": " .. technology_name)
    end
  end
  if not current.technologies[continuation_name] then fail("candidate continuation omitted for " .. name) end
  for recipe, prior_bonus in pairs(before.bonuses) do
    if current.bonuses[recipe] == nil or math.abs(current.bonuses[recipe] - prior_bonus) > epsilon then
      fail("unrelated recipe research bonus changed for " .. name .. ": " .. recipe)
    end
  end
  for recipe in pairs(current.bonuses) do
    if before.bonuses[recipe] == nil then fail("unexpected recipe bonus added for " .. name .. ": " .. recipe) end
  end
  if not equal_state(current.effects, before.effects) then fail("force effect changed for " .. name) end
end

local function verify_case(case, state, stage)
  local force = game.forces[case.force_name]
  if not force then fail("migration force disappeared: " .. case.force_name) end
  verify_unrelated_state(case.force_name, force, state.forces[case.force_name])
  candidate_definitions(force)
  local legacy, continuation = force.technologies[legacy_name], force.technologies[continuation_name]
  if case.completed < 3 then
    -- An old infinite level below the split is the finite stage currently in
    -- progress. It must remain there; completing it or moving its queued work
    -- to -4 would invent credit that the predecessor did not earn.
    if legacy.level ~= case.next_level or legacy.researched then
      fail("low earned finite stage changed or was over-credited for " .. case.force_name .. " at " .. stage)
    end
    if continuation.level ~= 4 or continuation.researched then
      fail("low earned continuation was changed before its prerequisite for " .. case.force_name .. " at " .. stage)
    end
    if not same_names(queue_names(force), {legacy_name}) or not force.current_research
        or force.current_research.name ~= legacy_name then
      fail("low earned finite Imersite queue was transferred too early for " .. case.force_name .. " at " .. stage)
    end
  else
    if legacy.level ~= 3 or not legacy.researched then
      fail("completed finite stage lost or duplicated for " .. case.force_name .. " at " .. stage)
    end
    -- Levels completed before the split retain their total 2% awards. The
    -- continuation's next level is the old infinite next level: 4 for the
    -- three-level case and 8 for the seven-level case.
    if continuation.level ~= case.next_level or continuation.researched then
      fail("continuation level transfer lost or duplicated for " .. case.force_name .. " at " .. stage)
    end
    if not same_names(queue_names(force), {continuation_name}) or not force.current_research
        or force.current_research.name ~= continuation_name then
      fail("queued infinite Imersite research was not transferred for " .. case.force_name .. " at " .. stage)
    end
  end
  close("preserved fractional progress " .. case.force_name .. " at " .. stage, force.research_progress, progress)
  close("preserved Imersite powder bonus " .. case.force_name .. " at " .. stage,
    force.recipes[powder_name].productivity_bonus, case.powder_bonus)
  close("independent crystal owner " .. case.force_name .. " at " .. stage,
    force.recipes[crystal_name].productivity_bonus, 0.10)
end

local function verify_control_force(state, stage)
  local force = game.forces[control_force_name]
  if not force then fail("untouched control force disappeared") end
  verify_unrelated_state(control_force_name, force, state.forces[control_force_name])
  candidate_definitions(force)
  local before = state.forces[control_force_name]
  if not same_names(queue_names(force), before.queue) or (force.current_research and force.current_research.name or false) ~= before.current_research then
    fail("untouched control force queue changed at " .. stage)
  end
  close("untouched control force progress " .. stage, force.research_progress, before.research_progress)
  close("untouched control force powder bonus " .. stage, force.recipes[powder_name].productivity_bonus, before.bonuses[powder_name])
  close("untouched control force crystal bonus " .. stage, force.recipes[crystal_name].productivity_bonus, before.bonuses[crystal_name])
end

local function verify_other_forces(state, stage)
  for name, before in pairs(state.forces) do
    if name ~= "player" and name ~= zero_force_name and name ~= low_force_name
        and name ~= high_force_name and name ~= control_force_name then
      local force = game.forces[name]
      if not force then fail("unseeded force disappeared: " .. name) end
      verify_unrelated_state(name, force, before)
      candidate_definitions(force)
      if not same_names(queue_names(force), before.queue)
          or (force.current_research and force.current_research.name or false) ~= before.current_research then
        fail("unseeded force queue changed for " .. name .. " at " .. stage)
      end
      close("unseeded force progress " .. name .. " at " .. stage, force.research_progress, before.research_progress)
    end
  end
end

local function verify_candidate(state, stage)
  profile(to_version)
  if state.cap ~= cap() then fail("configured unlimited cap changed") end
  if not equal_state(startup_settings(), state.startup_settings) then fail("startup setting changed") end
  for _, case in ipairs(state.cases) do verify_case(case, state, stage) end
  verify_control_force(state, stage)
  verify_other_forces(state, stage)
end

local function marker(stage)
  if stage ~= "source" then
    local technologies, recipes = 0, 0
    for _ in pairs(game.forces.player.technologies) do technologies = technologies + 1 end
    for _ in pairs(game.forces.player.recipes) do recipes = recipes + 1 end
    log("[mir-fixture] complete research state retained technologies=" .. technologies .. " recipes=" .. recipes)
  end
  log("[mir-fixture] K2-470 maintenance state verified stage=" .. stage .. ";cap=" .. cap())
  log("[mir-fixture] K2-470 infinite predecessor split mapping verified completed=0,2,3,7;progress=0.42")
end

script.on_init(function()
  profile(from_version)
  cap()
  local player = game.forces.player
  source_definition(player)
  if player.technologies[continuation_name] then fail("published predecessor contains candidate continuation") end
  local control = game.create_force(control_force_name)
  local zero = game.create_force(zero_force_name)
  local low = game.create_force(low_force_name)
  local high = game.create_force(high_force_name)
  source_definition(control)
  source_definition(zero)
  source_definition(low)
  source_definition(high)
  local cases = {
    seed_infinite_progress(zero, 0), seed_infinite_progress(low, 2),
    seed_infinite_progress(player, 3), seed_infinite_progress(high, 7)
  }
  -- The control and pre-existing forces intentionally receive no seed,
  -- research mutation, or queue rewrite. Their candidate state is compared
  -- around only the independently specified staged-definition delta.
  local state = {
    source_version = from_version, cap = cap(), phase = "source", cases = cases,
    startup_settings = startup_settings(), forces = all_force_states()
  }
  storage.mir_k2_460_to_470 = state
  export_state("source")
  marker("source")
  log("[mir-fixture] " .. from_version .. " upgrade source proof complete")
end)

script.on_configuration_changed(function()
  local state = storage.mir_k2_460_to_470
  if not state or state.source_version ~= from_version or state.phase ~= "source" then
    fail("source migration state is absent or changed")
  end
  -- Keep the actual destination state if the opposing check fails. This
  -- distinct observation is never a successful upgrade acceptance record.
  export_state("upgrade-observed-before-check")
  verify_candidate(state, "upgrade")
  state.phase = "upgraded"
  export_state("upgrade")
  marker("upgrade")
  log("[mir-fixture] " .. from_version .. " to " .. to_version .. " upgrade proof complete")
  game.server_save("mir-4721000-upgraded")
end)

script.on_load(function() loaded = true end)

script.on_event(defines.events.on_tick, function()
  local state = storage.mir_k2_460_to_470
  if not loaded or reload_checked or not state or state.phase ~= "upgraded" then return end
  verify_candidate(state, "reload")
  export_state("reload")
  marker("reload")
  log("[mir-fixture] " .. to_version .. " upgraded save reload proof complete archetype=")
  reload_checked = true
end)
