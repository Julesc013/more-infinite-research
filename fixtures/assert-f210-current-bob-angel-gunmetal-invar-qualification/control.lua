local subjects = {
  {
    family = "gunmetal",
    recipe = "angels-plate-gunmetal",
    early = "recipe-prod-research_material_gunmetal-1",
    continuation = "recipe-prod-research_material_gunmetal-4"
  },
  {
    family = "invar",
    recipe = "angels-plate-invar",
    early = "recipe-prod-research_material_invar-1",
    continuation = "recipe-prod-research_material_invar-4"
  }
}

local EFFECT_CHANGE = 0.02
local FINITE_BONUS = 0.06
local CONTINUATION_BONUS = 0.08
local PROGRESS = 0.42
local EPSILON = 0.000001
local reload_pending = false

local function fail(message)
  error("[mir-f210-current-ba-gunmetal-invar] " .. message)
end

local function near(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) < EPSILON
end

local function effect_change(technology, subject, phase)
  local count, change = 0, nil
  for _, effect in ipairs(technology.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == subject.recipe then
      count = count + 1
      change = effect.change
    end
  end
  if count ~= 1 or not near(change, EFFECT_CHANGE) then
    fail(phase .. " productivity effect differs " .. technology.name)
  end
end

local function productivity_bonus(force, subject, phase)
  local recipe = force.recipes[subject.recipe]
  if not recipe or type(recipe.productivity_bonus) ~= "number" then
    fail(phase .. " force recipe productivity is absent " .. subject.recipe)
  end
  return recipe.productivity_bonus
end

local function complete_research(force, technology, subject, finite, label)
  local current_level = technology.level
  if not force.add_research(technology) or not force.current_research
      or force.current_research.name ~= technology.name then
    fail("add_research did not admit " .. label)
  end
  force.research_queue = nil
  -- LuaTechnology.level advances the previously current level.  The finite
  -- level-three terminal transition instead uses researched=true, after the
  -- engine accepted it as current research.
  if finite and current_level == 3 then
    technology.researched = true
    if not technology.researched then fail("finite terminal completion differs " .. label) end
  else
    technology.level = current_level + 1
    if technology.level ~= current_level + 1 then
      fail("research completion level differs " .. label)
    end
  end
  if force.current_research then force.cancel_current_research() end
  effect_change(technology, subject, label)
end

local function prepare_subject(force, subject)
  local early = force.technologies[subject.early]
  local continuation = force.technologies[subject.continuation]
  if not early or not continuation then fail(subject.family .. " staged technology is absent") end
  effect_change(early, subject, subject.family .. " finite")
  effect_change(continuation, subject, subject.family .. " continuation")

  for _, prerequisite in pairs(early.prerequisites) do prerequisite.research_recursive() end
  for level = 1, 3 do
    if early.level ~= level then fail(subject.family .. " finite level differs before " .. tostring(level)) end
    complete_research(force, early, subject, true, subject.family .. " finite-" .. tostring(level))
  end
  if not early.researched or not near(productivity_bonus(force, subject, subject.family .. " finite"), FINITE_BONUS) then
    fail(subject.family .. " finite earned productivity differs")
  end

  for _, prerequisite in pairs(continuation.prerequisites) do
    if prerequisite.name ~= subject.early then prerequisite.research_recursive() end
  end
  if continuation.level ~= 4 then fail(subject.family .. " continuation does not start at level four") end
  complete_research(force, continuation, subject, false, subject.family .. " continuation-4")
  if continuation.level ~= 5 or not near(productivity_bonus(force, subject, subject.family .. " continuation"), CONTINUATION_BONUS) then
    fail(subject.family .. " continuation earned productivity differs")
  end
  return {early = early, continuation = continuation}
end

local function prepare_next_level_queue(force, prepared)
  if not force.research_queue_enabled then force.research_queue_enabled = true end
  if not force.research_queue_enabled then fail("research queue could not be enabled") end
  force.research_queue = nil
  local gunmetal, invar = prepared.gunmetal.continuation, prepared.invar.continuation
  if not force.add_research(gunmetal) or not force.add_research(invar) then
    fail("could not admit ordered continuation queue")
  end
  force.research_progress = PROGRESS
end

local function assert_runtime_state(stage)
  local state = storage.mir_f210_current_ba_gunmetal_invar
  if not state or state.version ~= 2 or state.completed ~= true then fail(stage .. " stored state differs") end
  local force = game.forces.player
  if not force then fail(stage .. " player force is absent") end
  for _, subject in ipairs(subjects) do
    local saved = state.subjects and state.subjects[subject.family]
    local early = force.technologies[subject.early]
    local continuation = force.technologies[subject.continuation]
    if not saved or not early or not continuation or not early.researched or continuation.level ~= 5 then
      fail(stage .. " earned research state differs " .. subject.family)
    end
    effect_change(early, subject, stage .. " finite")
    effect_change(continuation, subject, stage .. " continuation")
    if not near(productivity_bonus(force, subject, stage), CONTINUATION_BONUS)
        or saved.continuation_level ~= continuation.level
        or not near(saved.productivity_bonus, CONTINUATION_BONUS) then
      fail(stage .. " earned productivity differs " .. subject.family)
    end
  end
  local queue = force.research_queue or {}
  if not force.research_queue_enabled or not force.current_research or force.current_research.name ~= subjects[1].continuation
      or #queue ~= 2 or queue[1].name ~= subjects[1].continuation
      or queue[2].name ~= subjects[2].continuation
      or not near(force.research_progress, PROGRESS) then
    fail(stage .. " next-level queue or progress differs")
  end
end

local function runtime_marker(stage)
  return "[mir-f210-current-ba-gunmetal-invar] " .. stage
    .. " finite=researched continuation-level=5 bonuses=0.08"
    .. " queue=gunmetal-then-invar progress=0.42"
end

script.on_init(function()
  local force = game.forces.player
  if not force then fail("initial player force is absent") end
  force.enable_all_prototypes()
  local prepared = {}
  for _, subject in ipairs(subjects) do prepared[subject.family] = prepare_subject(force, subject) end
  prepare_next_level_queue(force, prepared)
  storage.mir_f210_current_ba_gunmetal_invar = {
    version = 2,
    completed = true,
    subjects = {
      gunmetal = {continuation_level = prepared.gunmetal.continuation.level, productivity_bonus = productivity_bonus(force, subjects[1], "initial")},
      invar = {continuation_level = prepared.invar.continuation.level, productivity_bonus = productivity_bonus(force, subjects[2], "initial")}
    }
  }
  assert_runtime_state("initial")
  log(runtime_marker("RUNTIME PASS stage=create"))
end)

script.on_load(function()
  reload_pending = true
end)

script.on_event(defines.events.on_tick, function()
  if not reload_pending then return end
  reload_pending = false
  assert_runtime_state("reload")
  log(runtime_marker("RELOAD PASS stage=reload"))
end)
