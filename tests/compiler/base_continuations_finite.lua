-- Controlled regression for finite upstream continuation chains.  It runs the
-- real planner with researchability/lab admission supplied by the test so the
-- assertion remains about terminal discovery and stable prerequisite identity.
mods = {base = "2.1.21"}
settings = {startup = {}}
feature_flags = {scripted_techs = true}
log = function() end
data = {raw = {technology = {}, item = {}, recipe = {}, lab = {}}}
function data:extend(rows)
  for _, row in ipairs(rows) do
    self.raw[row.type] = self.raw[row.type] or {}
    self.raw[row.type][row.name] = row
  end
end

local assertions = 0
local function check(condition, detail)
  assert(condition, detail)
  assertions = assertions + 1
  print("OBSERVED\t" .. detail)
end

local function has(rows, name)
  for _, row in ipairs(rows or {}) do
    if row == name or (type(row) == "table" and (row.name or row[1]) == name) then return true end
  end
  return false
end

local function technology(name, count, prerequisites, max_level)
  return {
    type = "technology", name = name, enabled = true, upgrade = true,
    effects = {{type = "worker-robot-storage", modifier = 1}},
    prerequisites = prerequisites or {},
    unit = {count = count, time = 60, ingredients = {{"automation-science-pack", 1}}},
    max_level = max_level
  }
end

local function separate_finite_tail(options)
  options = options or {}
  local out = {}
  for level = 1, 8 do
    local prerequisites = level == 1 and {} or {"worker-robots-storage-" .. (level - 1)}
    if level == 8 and options.tail_prerequisites then prerequisites = options.tail_prerequisites end
    out["worker-robots-storage-" .. level] = technology(
      "worker-robots-storage-" .. level, 100 * (2 ^ (level - 1)), prerequisites)
  end
  return out
end

-- Secretas' actual shape uses separate finite definitions through level eight.
data.raw.technology = separate_finite_tail()

-- The approved science facade must be sufficient for continuation planning;
-- loading one of the retired factory/research discovery solvers fails this
-- source control before the real planner can run.
for _, name in ipairs({
  "pack_production_reachability", "recipe_route_feasibility",
  "production_route_policy", "technology_researchability"
}) do
  package.preload["prototypes.mir.capabilities.science_integration." .. name] = function()
    error("retired discovery import: " .. name)
  end
end

local discover = require("prototypes.mir.planner.base_continuations.discover")
local levels, _, has_infinite, terminals = discover.chain("worker-robots-storage")
check(not has_infinite and levels[#levels] == 8 and terminals[8].name == "worker-robots-storage-8",
  "separate finite levels retain their real terminal prototype")

local science = require("prototypes.mir.capabilities.science_integration.science_packs")
science.technology_researchability_reason = function(name)
  check(name == "worker-robots-storage-8" or name == "worker-robots-storage-4",
    "finite continuation checks a real terminal prototype name")
  return nil
end
local qualify = require("prototypes.mir.planner.base_continuations.qualify")
qualify.is_enabled = function(key) return key == "worker-robots-storage" end
local selected_cap = nil
qualify.startup_setting = function(name)
  if name == "mir-max-level-worker-robots-storage" then return selected_cap end
  return nil
end
qualify.resolve_ingredients = function(_, unit)
  return unit.ingredients, "full", nil
end
qualify.append_end_game_prerequisite = function(prerequisites) return prerequisites end
qualify.prefer_this_mod_for_competing_techs = function() return true end

local plan = require("prototypes.mir.planner.base_continuations.plan")
local context = require("prototypes.mir.pipeline.compiler_context")
local function planned_worker_continuation()
  local operation
  context.with_active(context.new(), function()
    local planned = plan.plan_all()
    for _, candidate in ipairs(planned) do
      if candidate.technology_name == "worker-robots-storage-9" then operation = candidate end
    end
  end)
  return operation
end

-- The continuation must travel through the normal plan-bound operation
-- executor.  This remains a source control, not an engine/save assertion.
local function emit_through_common_executor(operation)
  local operation_contract = require("prototypes.mir.domain.compiler.transformation_operation")
  local transformation_plan = require("prototypes.mir.domain.compiler.transformation_plan")
  local mutation_journal = require("prototypes.mir.domain.compiler.mutation_journal")
  local executor = require("prototypes.mir.emit.base_continuation_executor")
  local technology_design = require("prototypes.mir.domain.technology.technology_design")
  local generated = require("prototypes.mir.domain.facts.generated_technology_registry")
  local design = operation.technology_design
  technology_design.assert_trusted(design)
  local expected_after = technology_design.trusted_prototype_projection_view(design)
  expected_after.type = "technology"
  local emitted_operation = operation_contract.new({
    operation_id = "technology/create/" .. operation.technology_name,
    phase = "technology-materialization",
    action = "create",
    subject = {type = "technology", id = operation.technology_name},
    expected_before_snapshot = {
      presence = "absent", prototype_type = "technology", id = operation.technology_name
    },
    expected_after_projection = expected_after,
    allowed_delta = {engine_default_fields = true},
    authority_fingerprint = "finite-continuation-control",
    qualification_fingerprint = design.qualification_fingerprint,
    source = {
      candidate_id = design.candidate_id,
      alternative_id = "create:" .. operation.technology_name
    },
    payload = {
      kind = "base-continuation",
      key = operation.key,
      manifest_id = operation.manifest_id,
      technology_design = design
    },
    evidence = {gates = operation.gates}
  })
  local bound_plan = transformation_plan.new({
    phase = "finite-continuation-control",
    execution_mode = "SAFE",
    compilation_snapshot_fingerprint = "finite-continuation-source",
    policy_fingerprint = "finite-continuation-policy",
    operations = {emitted_operation}
  })
  local outcome
  context.with_active(context.new(), function()
    local journal = mutation_journal.new(bound_plan)
    outcome = executor.apply_plan({operation}, bound_plan, journal)
    local receipt = journal:finalize()
    check(receipt.complete == true and #receipt.entries == 1,
      "finite continuation completes the common plan-bound mutation journal")
    check(generated.get(operation.technology_name).kind == "base_extension",
      "common emitter retains finite continuation ownership")
  end)
  return outcome
end

local separate_operation = planned_worker_continuation()
check(separate_operation and separate_operation.base_technology_name == "worker-robots-storage-8"
  and has(separate_operation.technology.prerequisites, "worker-robots-storage-8"),
  "separate finite level-eight chain produces a level-nine continuation")
local source_effect = data.raw.technology["worker-robots-storage-8"].effects[1]
local realized = emit_through_common_executor(separate_operation)
local emitted = data.raw.technology["worker-robots-storage-9"]
check(#realized == 1 and emitted and emitted.max_level == "infinite"
    and emitted.level == 9 and emitted.upgrade == true,
  "common emitter materializes exactly one level-nine infinite continuation")
check(emitted.effects[1].type == source_effect.type and emitted.effects[1].modifier == source_effect.modifier
    and data.raw.technology["worker-robots-storage-8"].effects[1].modifier == source_effect.modifier,
  "continuation preserves the earned finite cargo effect without rewriting level eight")

-- An upstream numeric range is represented by one prototype named at its
-- first level.  Its MIR continuation begins after max_level and depends on
-- that real prototype, never an invented intermediate name.
data.raw.technology = {
  ["worker-robots-storage-1"] = technology("worker-robots-storage-1", 100),
  ["worker-robots-storage-2"] = technology("worker-robots-storage-2", 200, {"worker-robots-storage-1"}),
  ["worker-robots-storage-3"] = technology("worker-robots-storage-3", 400, {"worker-robots-storage-2"}),
  ["worker-robots-storage-4"] = technology("worker-robots-storage-4", 800, {"worker-robots-storage-3"}, 8)
}
levels, _, has_infinite, terminals = discover.chain("worker-robots-storage")
check(not has_infinite and levels[#levels] == 4 and terminals[8].name == "worker-robots-storage-4",
  "finite numeric range retains terminal level and real anchor")

local operation = planned_worker_continuation()
check(operation ~= nil, "finite numeric range produces level-nine MIR continuation")
check(operation.base_technology_name == "worker-robots-storage-4"
  and has(operation.technology.prerequisites, "worker-robots-storage-4")
  and not has(operation.technology.prerequisites, "worker-robots-storage-8"),
  "level-nine continuation preserves the finite range's real prerequisite")

selected_cap = 8
local capped_operation = planned_worker_continuation()
check(capped_operation == nil or (capped_operation.planned_max_level == 8
    and capped_operation.technology.hidden == true),
  "configured cap remains authoritative when it is below the first finite continuation")
selected_cap = nil

-- Secretas/Frozeta-shaped tails can be non-adjacent and carry additional
-- finite progression prerequisites.  The binding must use the actual level
-- eight prototype, preserve its side prerequisite, and never invent a level.
data.raw.technology = separate_finite_tail({
  tail_prerequisites = {"worker-robots-storage-7", "frozeta-robot-cargo-certification"}
})
data.raw.technology["frozeta-robot-cargo-certification"] = {
  type = "technology", name = "frozeta-robot-cargo-certification", enabled = true,
  prerequisites = {}, unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}}
}
local shaped_operation = planned_worker_continuation()
check(shaped_operation and shaped_operation.base_technology_name == "worker-robots-storage-8"
    and has(shaped_operation.technology.prerequisites, "worker-robots-storage-8")
    and has(shaped_operation.technology.prerequisites, "frozeta-robot-cargo-certification"),
  "non-adjacent Frozeta-shaped finite tail keeps its real terminal and side prerequisite")

-- A separate mod's genuine infinite owner is authoritative even when it is
-- not named as part of the finite upstream chain.
data.raw.technology["frozeta-worker-robots-storage-infinite"] = technology(
  "frozeta-worker-robots-storage-infinite", 1, {"worker-robots-storage-8"}, "infinite")
local _, _, shaped_has_infinite = discover.chain("worker-robots-storage")
check(not shaped_has_infinite, "external infinite owner is not misclassified as the finite upstream chain")
check(planned_worker_continuation() == nil,
  "external infinite owner suppresses a duplicate MIR finite continuation")

data.raw.technology = separate_finite_tail()
data.raw.technology["worker-robots-storage-4"].max_level = "infinite"
local _, _, infinite = discover.chain("worker-robots-storage")
check(infinite, "true infinite owner remains detected")
check(planned_worker_continuation() == nil, "true infinite owner prevents a duplicate MIR continuation")

print("MIR-BASE-CONTINUATIONS-FINITE-PASS " .. assertions)
