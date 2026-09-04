local from_version = "4.0.21000"
local to_version = "4.1.21000"
local archetype = settings.startup["mir-upgrade-archetype"].value
local expected_progress = 0.42
local epsilon = 0.000001
local profiles = {
  ["base-default"]={technology="recipe-prod-research_iron-1",level=3},
  ["space-age-native-owner"]={technology="low-density-structure-productivity",level=4,requires_space_age=true,expected_absolute_cap=5},
  ["automatic-family-creation"]={technology="mir-auto-prod-manufacturing-assembling-machine-1",level=3,target_recipe="mir-upgrade-auto-assembler-recipe"},
  ["base-continuations"]={technology="inserter-capacity-bonus-8",level=8},
  ["mod-set-configuration-change"]={technology="recipe-prod-research_iron-1",level=3,target_recipe="mir-upgrade-removed-iron-plate",source_only_mod="mir-fixture-upgrade-modset-source"}
}
local profile=profiles[archetype]
if not profile then error("unknown MIR upgrade archetype "..tostring(archetype)) end
local function fail(message) error("MIR "..from_version.." to "..to_version.." "..archetype.." upgrade validation failed: "..message) end
local function technology() local value=game.forces.player.technologies[profile.technology];if not value then fail("missing technology "..profile.technology) end;return value end
local function science_names(value) local out={};for _,ingredient in pairs(value.research_unit_ingredients or {}) do table.insert(out,ingredient.name) end;table.sort(out);return out end
local function same_names(left,right) if #left~=#right then return false end;for index,value in ipairs(left) do if value~=right[index] then return false end end;return true end
local function has_recipe_effect(value,recipe_name) for _,effect in pairs((value.prototype and value.prototype.effects) or {}) do if effect.type=="change-recipe-productivity" and effect.recipe==recipe_name then return true end end;return false end

script.on_init(function()
  if script.active_mods["more-infinite-research"]~=from_version then fail("source save used wrong MIR version") end
  if profile.requires_space_age and not script.active_mods["space-age"] then fail("Space Age was not active") end
  if archetype=="base-default" and script.active_mods["space-age"] then fail("Space Age was unexpectedly active") end
  if profile.source_only_mod and not script.active_mods[profile.source_only_mod] then fail("source-only mod was not active") end
  local force=game.forces.player;local tech=technology()
  if profile.target_recipe and not has_recipe_effect(tech,profile.target_recipe) then fail("technology did not target source recipe") end
  force.research_all_technologies();tech.level=profile.level
  if not force.add_research(tech) then fail("could not queue research") end
  force.research_progress=expected_progress
  storage.mir_upgrade_fixture={archetype=archetype,technology=profile.technology,technology_level=tech.level,research_progress=force.research_progress,research_unit_count=tech.research_unit_count,science=science_names(tech),source_version=from_version}
  log("[mir-fixture] "..from_version.." upgrade source proof complete archetype="..archetype)
end)

script.on_configuration_changed(function()
  if script.active_mods["more-infinite-research"]~=to_version then fail("upgraded save used wrong MIR version") end
  local state=storage.mir_upgrade_fixture;if not state or state.source_version~=from_version then fail("fixture storage did not survive") end
  local force=game.forces.player;local tech=technology()
  if tech.level~=state.technology_level then fail("technology level did not survive") end
  if not force.current_research or force.current_research.name~=profile.technology then fail("current research did not survive") end
  local expected=math.max(0,math.min(1,state.research_progress*state.research_unit_count/tech.research_unit_count))
  if math.abs((force.research_progress or 0)-expected)>epsilon then fail("completed research work changed") end
  if not same_names(state.science,science_names(tech)) then fail("science ingredients changed") end
  if archetype=="space-age-native-owner" then
    if tech.prototype.max_level<4294967295 then fail("native owner is not losslessly infinite") end
    if settings.startup["ips-max-level-research_low_density_structure"].value~=profile.expected_absolute_cap then fail("absolute cap changed") end
  elseif archetype=="automatic-family-creation" and not has_recipe_effect(tech,profile.target_recipe) then fail("automatic-family effect disappeared")
  elseif archetype=="mod-set-configuration-change" then if script.active_mods[profile.source_only_mod] or prototypes.recipe[profile.target_recipe] or has_recipe_effect(tech,profile.target_recipe) then fail("removed subject survived sanitation") end end
  state.upgrade_complete=true;log("[mir-fixture] "..from_version.." to "..to_version.." upgrade proof complete archetype="..archetype)
end)
script.on_event(defines.events.on_tick,function() local state=storage.mir_upgrade_fixture;if state and state.upgrade_complete and not state.server_save_requested then state.server_save_requested=true;game.server_save("mir-4121000-upgraded") end end)
script.on_load(function() if storage.mir_upgrade_fixture and storage.mir_upgrade_fixture.upgrade_complete then log("[mir-fixture] "..to_version.." upgraded save reload proof complete archetype="..archetype) end end)
