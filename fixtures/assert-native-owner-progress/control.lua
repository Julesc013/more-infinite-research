local technology_name = "low-density-structure-productivity"
local expected_progress = 0.42
local epsilon = 0.000001
local cost_model = require("__more-infinite-research__.prototypes.mir.domain.research_cost.model")
local transition_descriptor = require("__more-infinite-research__.prototypes.mir.domain.research_cost.transition_descriptor")
local adoption_data_name = "more-infinite-research-productivity-family-adoption"

local function fail(message)
  error("MIR native-owner progress validation failed: " .. message)
end

local function copy_value(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, nested in pairs(value) do result[copy_value(key)] = copy_value(nested) end
  return result
end

local function technology()
  local value = game.forces.player.technologies[technology_name]
  if not value then fail("missing low-density-structure productivity technology") end
  return value
end

local function descriptor(parameters)
  return transition_descriptor.from_model(cost_model.new({
    anchor_level = 1,
    base_cost = parameters.base,
    linear_increment = parameters.increment,
    growth_factor = parameters.growth,
    provenance = {
      anchor_level = "fixture",
      base_cost = "fixture",
      linear_increment = "fixture",
      growth_factor = "fixture"
    }
  }))
end

local function assert_transition_matrix(phase)
  local models = {
    fixed = descriptor({base = 1000, increment = 0, growth = 1}),
    linear = descriptor({base = 1000, increment = 250, growth = 1}),
    exponential = descriptor({base = 1000, increment = 0, growth = 1.5}),
    hybrid = descriptor({base = 1000, increment = 250, growth = 1.5})
  }
  local rows = 0
  for previous_kind, previous in pairs(models) do
    for current_kind, current in pairs(models) do
      local previous_cost = assert(transition_descriptor.evaluate(previous, 5))
      local current_cost = assert(transition_descriptor.evaluate(current, 5))
      local actual, detail = transition_descriptor.convert_fraction(expected_progress, previous, current, 5)
      if not actual then fail("matrix conversion refused " .. previous_kind .. " -> " .. current_kind
        .. ": " .. tostring(detail)) end
      local expected = math.max(0, math.min(1, expected_progress * previous_cost / current_cost))
      if math.abs(actual - expected) > epsilon then
        fail("matrix conversion drifted " .. previous_kind .. " -> " .. current_kind)
      end
      if detail.previous_cost ~= previous_cost or detail.current_cost ~= current_cost then
        fail("matrix cost evidence drifted " .. previous_kind .. " -> " .. current_kind)
      end
      rows = rows + 1
    end
  end
  if rows ~= 16 then fail("transition matrix did not contain sixteen rows") end

  local tampered = copy_value(models.fixed)
  tampered.semantic_digest = "mir32-00000000"
  if transition_descriptor.convert_fraction(expected_progress, tampered, models.linear, 5) ~= nil then
    fail("semantic-digest tamper did not fail closed")
  end
  local over_budget = descriptor({base = 1, increment = 0, growth = 10})
  if transition_descriptor.evaluate(over_budget, 302) ~= nil then
    fail("over-budget evaluation did not fail closed")
  end
  log("[mir-fixture] research-cost transition matrix proof complete phase=" .. phase .. " rows=" .. rows)
end

local function adoption_binding()
  local prototype = prototypes and prototypes.mod_data and prototypes.mod_data[adoption_data_name]
  local data = prototype and prototype.data
  if not data or data.version ~= 3 then fail("native-owner adoption descriptor schema 3 is absent") end
  for _, binding in ipairs(data.bindings or {}) do
    if binding.owner == technology_name then return binding end
  end
  fail("low-density-structure adoption binding is absent")
end

script.on_init(function()
  assert_transition_matrix("init")
  local force = game.forces.player
  local tech = technology()
  adoption_binding()
  force.research_all_technologies()
  tech.level = 5
  if not force.add_research(tech) then fail("could not queue native-owner research") end
  force.research_progress = expected_progress
  local research_unit_count = tech.research_unit_count
  if not research_unit_count or research_unit_count <= 0 then
    fail("initial engine research-unit count is unavailable")
  end
  storage.mir_native_owner_progress_fixture = {
    technology_level = tech.level,
    research_progress = force.research_progress,
    research_unit_count = research_unit_count
  }
  if not remote.interfaces["mir-native-owner-reset-safety"] then
    fail("reset-safety source interface is absent during initialization")
  end
  remote.call("mir-native-owner-reset-safety", "seal_initial_inventory")
  log("[mir-fixture] native-owner progress source proof complete")
end)

script.on_configuration_changed(function()
  assert_transition_matrix("configuration-changed")
  local state = storage.mir_native_owner_progress_fixture
  if not state then fail("fixture storage did not survive configuration change") end
  local force = game.forces.player
  local tech = technology()
  if tech.level ~= state.technology_level then
    fail("native-owner technology level did not survive configuration change")
  end
  if not force.current_research or force.current_research.name ~= technology_name then
    fail("current native-owner research did not survive configuration change")
  end
  if not state.research_unit_count or state.research_unit_count <= 0 then
    fail("prior engine research-unit count evidence is unavailable")
  end
  local observed_progress = force.research_progress
  if not observed_progress or observed_progress < 0 or observed_progress > 1 then
    fail("native-owner observed research progress is outside the engine range")
  end
  if not remote.interfaces["mir-native-owner-reset-safety"] then
    fail("reset-safety source interface is absent")
  end
  local reset_snapshot = remote.call("mir-native-owner-reset-safety", "configuration_snapshot")
  local player = game.get_player(1)
  local token_count = player and player.get_item_count("mir-reset-safety-token") or 0
  local reset_recipe = force.recipes["mir-reset-safety-recipe"]
  if not reset_snapshot.configuration_change_seen then
    fail("reset-safety source did not observe configuration change before MIR")
  end
  if reset_snapshot.player_inventory_available
    and reset_snapshot.token_count_before_mir ~= reset_snapshot.initial_token_count then
    fail("external give-item inventory changed before MIR configuration handling")
  end
  if reset_snapshot.player_inventory_available and token_count ~= reset_snapshot.token_count_before_mir then
    fail("MIR duplicated an external give-item effect during configuration change")
  end
  if reset_snapshot.recipe_enabled_after_override ~= false or not reset_recipe or reset_recipe.enabled ~= false then
    fail("MIR lost another mod's configuration-change recipe state")
  end
  if not reset_snapshot.research_progress_before_mir then
    fail("pre-MIR native-owner research observation is absent")
  end
  local current_research_unit_count = tech.research_unit_count
  if not current_research_unit_count or current_research_unit_count <= 0 then
    fail("current engine research-unit count evidence is unavailable")
  end
  local expected_progress_after_change = math.max(0, math.min(1,
    state.research_progress * state.research_unit_count / current_research_unit_count))
  if math.abs(reset_snapshot.research_progress_before_mir - expected_progress_after_change) > epsilon then
    fail("Factorio did not preserve completed research-unit work before MIR configuration handling")
  end
  if math.abs(observed_progress - expected_progress_after_change) > epsilon then
    fail("MIR changed Factorio-normalized completed research-unit work")
  end
  log("[mir-fixture] native-owner force-state preservation proof complete"
    .. " player_inventory_asserted=" .. tostring(reset_snapshot.player_inventory_available))
  log("[mir-fixture] native-owner observed progress proof source-progress=" .. tostring(state.research_progress)
    .. " before=" .. tostring(reset_snapshot.research_progress_before_mir)
    .. " after=" .. tostring(observed_progress)
    .. " prior-cost=" .. tostring(state.research_unit_count)
    .. " current-cost=" .. tostring(current_research_unit_count)
    .. " level=" .. tostring(tech.level))
  log("[mir-fixture] native-owner progress configuration-change proof complete")
end)
