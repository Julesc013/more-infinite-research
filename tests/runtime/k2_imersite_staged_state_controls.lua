-- Controlled unit coverage for the private K2 two-carrier migration contract.
-- It runs in the established compiler-regression host, not as a player
-- profile claim. The full published-4.6 upgrade/reload fixture remains the
-- native preservation authority.
local assertions = 0
local function check(value, message)
  assert(value, message)
  assertions = assertions + 1
end

local state = require("prototypes.mir.domain.research.k2_imersite_staged_state")

local legacy = state.legacy_technology
local continuation = state.continuation_technology
local early_holder = state.early.technology_name
local continuation_holder = state.continuation.technology_name

local available = {
  recipe = {[state.powder_recipe] = {}},
  item = {['automation-science-pack'] = {}, alpha = {}},
  tool = {}
}
local lab_inputs = {"beta", "zeta"}
local target = {factorio_version = "2.1"}
package.loaded["prototypes.mir.platform.factorio.data_raw"] = {
  prototype = function(kind, name) return available[kind] and available[kind][name] end,
  prototypes = function(kind) return available[kind] or {} end
}
package.loaded["prototypes.mir.platform.factorio.prototype_lookup"] = {
  item_prototype = function(name)
    return (available.item and available.item[name]) or (available.tool and available.tool[name])
  end
}
package.loaded["prototypes.mir.capabilities.science_integration.science_packs"] = {
  pack_list_all = function() return lab_inputs end
}
package.loaded["prototypes.mir.platform.factorio.target_line"] = {
  factorio_version = target.factorio_version,
  feature_enabled = function(name)
    return name == "scripted_techs" or name == "productivity_family_adoption"
  end
}
package.loaded["prototypes.mir.planner.costs"] = {
  model_for = function() return {base_cost = 200, count_formula = "200*2^(L-1)"} end,
  research_time_for = function() return 30 end,
  base_cost_for = function() return 200 end
}
package.loaded["prototypes.mir.domain.research_cost.model"] = {
  evaluate = function() return 1600 end,
  new = function(input) return {base_cost = input.base_cost, count_formula = "1600+200*(L-4)"} end
}
package.loaded["prototypes.mir.planner.stream_compiler.diagnostics"] = {
  plan_row = function(key, spec, action, reason, _, fields)
    local row = {manifest_id = spec.manifest_id or key, stream_key = key, spec = spec, action = action, reason = reason}
    for name, value in pairs(fields or {}) do row[name] = value end
    return row
  end
}
package.loaded["prototypes.mir.report.diagnostics_sink"] = {stream_fields = function() return {} end}
-- Load the controlled modules only after their narrow host dependencies are installed.
local planner = require("prototypes.mir.planner.stream_compiler.k2_imersite_migration_alias")
local runtime = require("prototypes.mir.runtime.k2_imersite_staged_state_migration")

local stream = {research_material_imersite = {}}
local visible_early = {
  action = "emit", technology_name = legacy,
  fields = {ingredients = {{"alpha", 1}}, count_formula = "visible-early", count = nil,
    research_time = 41, cost_model = {base_cost = 200, count_formula = "visible-early"}}
}
local visible_continuation = {
  action = "emit", technology_name = continuation,
  fields = {ingredients = {{"alpha", 1}}, count_formula = "visible-continuation", count = nil,
    research_time = 43, cost_model = {base_cost = 1600, count_formula = "visible-continuation"}}
}
local rows = planner.plan_rows(stream, {visible_early}, {visible_early, visible_continuation})
check(#rows == 2 and state.is_row(rows[1]) and state.is_row(rows[2]),
  "the F210 K2 plan emits exactly the two governed migration carriers rows=" .. tostring(#rows)
    .. " first=" .. tostring(rows[1] and state.is_row(rows[1])))
check(rows[1].technology_name == early_holder and rows[2].technology_name == continuation_holder
    and rows[1].fields.hidden and rows[2].fields.hidden and rows[1].fields.enabled and rows[2].fields.enabled,
  "carrier identities are exact and initially require runtime cleanup")
check(rows[1].fields.count_formula == "visible-early" and rows[1].fields.research_time == 41
    and rows[2].fields.count_formula == "visible-continuation" and rows[2].fields.research_time == 43,
  "carrier units reuse the ordinary emitted cost/time descriptors")

-- F200 still exposes science packs as tools; the shared item abstraction must
-- retain this older valid shape without a target-specific planner branch.
available.item.alpha = nil
available.tool.alpha = {}
local tool_rows = planner.plan_rows(stream, {visible_early}, {visible_early, visible_continuation})
check(#tool_rows == 2 and tool_rows[1].fields.ingredients[1][1] == "alpha"
    and tool_rows[2].fields.ingredients[1][1] == "alpha",
  "the item abstraction accepts the established F200 tool-shaped science ingredient")
available.tool.alpha = nil
available.item["automation-science-pack"] = nil
available.item.beta = {}
local fallback = planner.plan_rows(stream, {visible_early}, {})
check(#fallback == 2 and fallback[1].fields.ingredients[1][1] == "beta"
    and fallback[2].fields.ingredients[1][1] == "beta",
  "a hidden holder uses the first deterministic available lab input when automation is replaced")
available.item.beta = nil
lab_inputs = {}
check(#planner.plan_rows(stream, {visible_early}, {}) == 0,
  "no admitted lab input leaves no hidden carrier rather than selecting an arbitrary item")
lab_inputs = {"beta", "zeta"}
available.item.beta = {}
available.recipe[state.powder_recipe] = nil
check(#planner.plan_rows(stream, {visible_early}, {}) == 0,
  "no K2 powder recipe means no hidden carrier or public fallback")
available.recipe[state.powder_recipe] = {}
target.factorio_version = "2.0"
package.loaded["prototypes.mir.platform.factorio.target_line"].factorio_version = "2.0"
check(#planner.plan_rows(stream, {visible_early}, {visible_early, visible_continuation}) == 0,
  "the state-carrier planner is F210-only")
target.factorio_version = "2.1"
package.loaded["prototypes.mir.platform.factorio.target_line"].factorio_version = "2.1"

local function powder_effects()
  return {{type = "change-recipe-productivity", recipe = state.powder_recipe, change = 0.02}}
end
local function technology(name, level, max_level, prerequisites)
  return {
    name = name, level = level, researched = false, saved_progress = 0,
    enabled = true, visible_when_disabled = false,
    research_unit_count_formula = "200*2^(L-1)", research_unit_energy = 30,
    research_unit_ingredients = {{name = "alpha", amount = 1}},
    prototype = {hidden = name == early_holder or name == continuation_holder,
      max_level = max_level, effects = powder_effects(), prerequisites = prerequisites or {}}
  }
end
local function queue_names(force)
  local out = {}
  for _, value in ipairs(force.research_queue or {}) do out[#out + 1] = value.name end
  return out
end

local function same_names(left, right)
  if #left ~= #right then return false end
  for index, value in ipairs(left) do if value ~= right[index] then return false end end
  return true
end

local function make_force(technology_map, queue, current, progress, index, queue_faults)
  local force = {technologies = technology_map, _queue = {}, _queue_faults = {}, index = index,
    research_progress = progress or 0}
  setmetatable(force, {__index = function(self, key)
    if key == "research_queue" then return rawget(self, "_queue") end
    return rawget(self, key)
  end, __newindex = function(self, key, value)
    if key == "research_queue" then
      local faults = rawget(self, "_queue_faults") or {}
      if (faults.refuse or 0) > 0 then
        faults.refuse = faults.refuse - 1
        error("intentional queue assignment refusal")
      end
      if (faults.readback_mismatch or 0) > 0 then
        faults.readback_mismatch = faults.readback_mismatch - 1
        rawset(self, "_queue", {})
        rawset(self, "current_research", nil)
        return
      end
      rawset(self, "_queue", value)
      rawset(self, "current_research", value[1])
    else rawset(self, key, value) end
  end})
  local values = {}
  for _, name in ipairs(queue or {}) do values[#values + 1] = assert(technology_map[name]) end
  force.research_queue = values
  force.current_research = current and technology_map[current] or nil
  force._queue_faults = queue_faults or {}
  return force
end
local function holders(early_level, tail_level)
  return technology(early_holder, early_level, "infinite"), technology(continuation_holder, tail_level, "infinite")
end
local function staged(force, early, tail)
  game = {forces = {player = force}}
  local state_root = {}
  runtime.reconcile({mod_changes = {["more-infinite-research"] = {old_version = "4.6.21000"}}}, state_root)
  return state_root
end

-- Released infinite level eight becomes completed finite level three and the
-- original queued next level in the continuation; both hidden carriers clear.
do
  local early, tail = holders(8, 4)
  local finite = technology(legacy, 1, 3)
  local late = technology(continuation, 4, "infinite", {{name = legacy}})
  local force = make_force({[early_holder] = early, [continuation_holder] = tail, [legacy] = finite, [continuation] = late},
    {early_holder}, early_holder, 0.42, 1)
  staged(force, early, tail)
  check(finite.level == 3 and finite.researched and late.level == 8 and not late.researched,
    "earned level seven maps once across finite and continuation stages")
  check(force.research_queue[1].name == continuation and force.current_research.name == continuation
      and force.research_progress == 0.42,
    "queued fractional work follows the old infinite level")
  check(not early.enabled and early.level == 1 and not tail.enabled and tail.level == 4,
    "completed transfer clears state-only carriers")
end

-- A predecessor already staged by an older release keeps the existing
-- continuation and its active work through the second independent carrier.
do
  local early, tail = holders(4, 8)
  local finite = technology(legacy, 3, 3); finite.researched = true
  local late = technology(continuation, 4, "infinite", {{name = legacy}})
  local force = make_force({[early_holder] = early, [continuation_holder] = tail, [legacy] = finite, [continuation] = late},
    {continuation_holder}, continuation_holder, 0.42, 2)
  staged(force, early, tail)
  check(finite.level == 3 and finite.researched and late.level == 8
      and force.current_research.name == continuation and force.research_progress == 0.42,
    "existing staged continuation state is retained instead of being reset by the old prerequisite")
end

-- Fresh defaults never become a hidden research path.
do
  local early, tail = holders(1, 4)
  local finite = technology(legacy, 1, 3)
  local late = technology(continuation, 4, "infinite", {{name = legacy}})
  local force = make_force({[early_holder] = early, [continuation_holder] = tail, [legacy] = finite, [continuation] = late}, {}, nil, 0, 3)
  game = {forces = {player = force}}
  runtime.initialize_fresh({})
  check(not early.enabled and not tail.enabled and early.level == 1 and tail.level == 4,
    "fresh default holders are disabled without a synthetic predecessor record")
end


-- A cap/profile may omit the public continuation. The disabled holder must
-- retain exactly the earned tail effect so migration neither loses nor doubles
-- Imersite productivity, then converge without replaying a player-changed queue.
local function powder_total(force)
  local total = 0
  local minimums = {[legacy] = 1, [continuation] = 4, [early_holder] = 1, [continuation_holder] = 4}
  for name, minimum in pairs(minimums) do
    local value = force.technologies[name]
    if value then
      local completed = value.researched and value.level or value.level - minimum
      total = total + completed * 0.02
    end
  end
  return total
end

do
  local early, tail = holders(8, 4)
  local finite = technology(legacy, 1, 3)
  local force = make_force({[early_holder] = early, [continuation_holder] = tail, [legacy] = finite},
    {early_holder}, early_holder, 0.42, 4)
  check(math.abs(powder_total(force) - 0.14) < 0.000001,
    "the source holder represents seven earned two-percent powder levels")
  local state_root = staged(force, early, tail)
  check(finite.level == 3 and finite.researched and not tail.enabled and tail.level == 8 and not tail.researched,
    "finite-only destination keeps the unavailable continuation tail in the hidden carrier")
  check(math.abs(powder_total(force) - 0.14) < 0.000001,
    "finite-only cap/profile preserves the exact earned powder total without duplicate credit")
  check(#force.research_queue == 0 and force.current_research == nil
      and state_root.k2_imersite_staged_migration[4].phase == "tail-held-no-continuation",
    "held tail removes only the unavailable carrier queue and records convergent state")

  local unrelated = technology("unrelated", 1, 1)
  force.technologies.unrelated = unrelated
  force.research_queue = {unrelated}
  force.research_progress = 0.11
  local late = technology(continuation, 4, "infinite", {{name = legacy}})
  force.technologies[continuation] = late
  runtime.reconcile(nil, state_root)
  check(late.level == 8 and not late.researched and not tail.enabled and tail.level == 4,
    "a later valid continuation consumes the held tail exactly once")
  check(math.abs(powder_total(force) - 0.14) < 0.000001,
    "held-tail convergence preserves total earned powder productivity without replay")
  check(force.current_research == unrelated and force.research_progress == 0.11,
    "held-tail convergence retains a player-changed unrelated queue")
end

-- A save can contain interleaved repeated carrier entries.  Preserve exact
-- order and multiplicity, then leave a completed record inert if the same
-- configuration callback is delivered again.
do
  local early, tail = holders(8, 4)
  local finite = technology(legacy, 1, 3)
  local late = technology(continuation, 4, "infinite", {{name = legacy}})
  local before = technology("unrelated-before", 1, 1)
  local middle = technology("unrelated-middle", 1, 1)
  local force = make_force({
      [early_holder] = early, [continuation_holder] = tail, [legacy] = finite,
      [continuation] = late, [before.name] = before, [middle.name] = middle
    }, {before.name, early_holder, middle.name, early_holder, continuation_holder, before.name}, before.name, 0.42, 5)
  local state_root = staged(force, early, tail)
  local expected = {before.name, continuation, middle.name, continuation, continuation, before.name}
  check(same_names(queue_names(force), expected) and force.current_research == before
      and force.research_progress == 0.42,
    "interleaved duplicate carrier queue entries map in order without collapsing unrelated research")
  runtime.reconcile(nil, state_root)
  check(same_names(queue_names(force), expected) and force.current_research == before
      and force.research_progress == 0.42 and early.level == 1 and tail.level == 4
      and state_root.k2_imersite_staged_migration[5].phase == "completed-staged",
    "a duplicate configuration callback leaves an accepted staged transfer inert")
end

-- The runtime must retain the JSON carriers if Factorio refuses the queue
-- assignment or does not report the requested queue back.  Once the transient
-- failure clears, the same captured record can transfer exactly once.
local function assert_retryable_queue_fault(faults, label, index)
  local early, tail = holders(8, 4)
  local finite = technology(legacy, 1, 3)
  local late = technology(continuation, 4, "infinite", {{name = legacy}})
  local force = make_force({[early_holder] = early, [continuation_holder] = tail, [legacy] = finite,
      [continuation] = late}, {early_holder}, early_holder, 0.42, index, faults)
  local state_root = staged(force, early, tail)
  local record = state_root.k2_imersite_staged_migration[index]
  check(record.phase == "holder-retained-retryable" and early.level == 8 and not early.researched
      and tail.level == 4 and not tail.researched and finite.level == 1 and not finite.researched
      and same_names(queue_names(force), {early_holder}) and force.current_research == early
      and force.research_progress == 0.42,
    label .. " rolls back destination state and retains the source carrier for retry")
  runtime.reconcile(nil, state_root)
  check(record.phase == "completed-staged" and finite.level == 3 and finite.researched
      and late.level == 8 and not late.researched and early.level == 1 and tail.level == 4
      and same_names(queue_names(force), {continuation}) and force.current_research == late
      and force.research_progress == 0.42,
    label .. " retries the captured transfer once the exact queue readback is available")
end

assert_retryable_queue_fault({refuse = 1}, "queue assignment refusal", 6)
assert_retryable_queue_fault({readback_mismatch = 1}, "queue readback mismatch", 7)
print("MIR-K2-STAGED-STATE-PASS " .. assertions)
