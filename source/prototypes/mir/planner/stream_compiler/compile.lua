local deepcopy = require("prototypes.mir.core.deepcopy")
local table_utils = require("prototypes.mir.core.table")
local generation_plan = require("prototypes.mir.planner.generation_plan")
local family_resolver = require("prototypes.mir.families.resolver")
local family_registry = require("prototypes.mir.families.registry")
local provider_registry = require("prototypes.mir.providers.registry")
local fingerprint = require("prototypes.mir.core.fingerprint")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local recipe_risk_facts = require("prototypes.mir.index.recipe_risk_facts")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local compatibility_policy = require("prototypes.mir.compatibility.policy_authority")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local discover = require("prototypes.mir.planner.stream_compiler.discover")
local ownership = require("prototypes.mir.planner.stream_compiler.ownership")
local qualify = require("prototypes.mir.planner.stream_compiler.qualify")
local material_continuation = require("prototypes.mir.planner.stream_compiler.material_continuation")
-- The compatibility JSON and its carriers are F210-only.  F200 also has
-- scripted technologies, so feature support alone is not a target boundary.
local k2_imersite_migration_alias = target_line.factorio_version == "2.1"
  and target_line.feature_enabled("scripted_techs")
  and require("prototypes.mir.planner.stream_compiler.k2_imersite_migration_alias") or nil

local M = {}
local pregraph_drafts = setmetatable({}, {__mode = "k"})

local function exported_artifact(artifact)
  return generation_plan.is_draft(artifact)
    and generation_plan.materialize_draft(artifact) or deepcopy(artifact)
end

local function compile_active(context, return_view)
  discover.ensure_services(context)
  local cached = context:state_view("generation_plan") or pregraph_drafts[context]
  if cached then return return_view and cached or exported_artifact(cached) end
  local streams, native_owner_inputs, shared_rules = discover.source_snapshot()
  telemetry.start_phase("stream_compiler")
  local recipe_source = {}
  -- A Context export is the established generic snapshot boundary and keeps
  -- its legacy full recipe-index source digest. The active data-stage path
  -- publishes a distinct, explicitly versioned normalized-input identity.
  if context:legacy_compiler_export_requested() then
    recipe_source.facts = recipe_facts.fingerprint()
  else
    recipe_source.recipe_input = recipe_facts.active_input_identity()
  end
  local metadata = {
    source_fingerprints = {
      facts = recipe_source.facts,
      recipe_input = recipe_source.recipe_input,
      risk_inputs = recipe_risk_facts.source_fingerprint(),
      rules = fingerprint.of({streams = streams, families = family_registry.view(),
        science_bindings = shared_rules.science_bindings, science_binding_policy = shared_rules.science_binding_policy}),
      providers = provider_registry.fingerprint(),
      compatibility_packs = fingerprint.of(compatibility_policy.active_packs()),
      target_profile = fingerprint.of(target_profiles.current()),
      native_owners = fingerprint.of(native_owner_inputs),
      provider_decisions = family_resolver.decision_set_fingerprint()
    }
  }
  local rows = {}
  for _, key in ipairs(table_utils.sorted_keys(streams)) do
    table.insert(rows, qualify.plan(key, streams[key]))
  end
  rows = ownership.resolve(rows)
  local staged_rows = {}
  for _, row in ipairs(rows) do
    table.insert(staged_rows, row)
    -- Reuse only the effects that won the ordinary owner reconciliation.
    -- A native or competing owner cannot be extended by an MIR continuation.
    local continuation = material_continuation.plan(row)
    if continuation then table.insert(staged_rows, continuation) end
  end
  -- The hidden compatibility carriers use the normal TechnologyDesign/create
  -- path but have no player stream authority.
  if k2_imersite_migration_alias then
    for _, migration_holder in ipairs(k2_imersite_migration_alias.plan_rows(streams, rows, staged_rows)) do
      table.insert(staged_rows, migration_holder)
    end
  end
  rows = staged_rows
  local artifact = generation_plan.prepare(rows, metadata)
  telemetry.count("stream_rows", #artifact.rows)
  telemetry.finish_phase("stream_compiler")
  pregraph_drafts[context] = artifact
  return return_view and artifact or exported_artifact(artifact)
end

local function compile(context, return_view)
  context = context or compiler_context.current()
  return compiler_context.with_active(context, compile_active, context, return_view)
end

function M.compile(context)
  return compile(context, false)
end

function M.compile_view(context)
  return compile(context, true)
end

function M.accept(plan, context)
  context = context or compiler_context.current()
  local artifact = generation_plan.is_draft(plan) and generation_plan.materialize_draft(plan)
    or (type(plan.artifact) == "function" and plan:artifact() or deepcopy(plan))
  pregraph_drafts[context] = nil
  if context:has_state("generation_plan") then
    context:replace_epoch("generation_plan", artifact, context:state_epoch("generation_plan"))
  else
    context:set_state("generation_plan", artifact)
  end
end

function M.latest_artifact(context)
  context = context or compiler_context.current()
  local artifact = context:state_view("generation_plan") or pregraph_drafts[context]
  return artifact and exported_artifact(artifact) or nil
end

function M.accept_artifact(artifact, context, options)
  context = context or compiler_context.current()
  local accepted = options and options.trusted and artifact or deepcopy(artifact)
  if generation_plan.is_draft(accepted) then
    error("A private GenerationDraft cannot become the public GenerationPlan.", 2)
  end
  pregraph_drafts[context] = nil
  if context:has_state("generation_plan") then
    context:replace_epoch("generation_plan", accepted, context:state_epoch("generation_plan"))
  else
    context:set_state("generation_plan", accepted)
  end
end

function M.assert_output(context)
  return require("prototypes.mir.planner.output_validator").assert_artifact(M.latest_artifact(context))
end

return M
