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
local compatibility_policy = require("prototypes.mir.compatibility.policy_authority")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local discover = require("prototypes.mir.planner.stream_compiler.discover")
local ownership = require("prototypes.mir.planner.stream_compiler.ownership")
local qualify = require("prototypes.mir.planner.stream_compiler.qualify")

local M = {}

local function compile_active(context, return_view)
  discover.ensure_services(context)
  local cached = context:state_view("generation_plan")
  if cached then return return_view and cached or deepcopy(cached) end
  local streams, native_owner_inputs = discover.source_snapshot()
  telemetry.start_phase("stream_compiler")
  local plan = generation_plan.new({
    source_fingerprints = {
      facts = recipe_facts.fingerprint(),
      risks = recipe_risk_facts.fingerprint(),
      rules = fingerprint.of({streams = streams, families = family_registry.view()}),
      providers = provider_registry.fingerprint(),
      compatibility_packs = fingerprint.of(compatibility_policy.active_packs()),
      target_profile = fingerprint.of(target_profiles.current()),
      native_owners = fingerprint.of(native_owner_inputs),
      provider_decisions = family_resolver.decision_set_fingerprint()
    }
  })
  local rows = {}
  for _, key in ipairs(table_utils.sorted_keys(streams)) do
    table.insert(rows, qualify.plan(key, streams[key]))
  end
  rows = ownership.resolve(rows)
  for _, row in ipairs(rows) do
    row.technology_design = technology_design.from_generation_row(row)
    plan:add_owned_derived(row)
  end
  local finalized = plan:finalize()
  local artifact = finalized:artifact_view()
  telemetry.count("stream_rows", #artifact.rows)
  telemetry.finish_phase("stream_compiler")
  context:set_state("generation_plan", artifact)
  return return_view and artifact or deepcopy(artifact)
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
  local artifact = type(plan.artifact) == "function" and plan:artifact() or deepcopy(plan)
  if context:has_state("generation_plan") then
    context:replace_epoch("generation_plan", artifact, context:state_epoch("generation_plan"))
  else
    context:set_state("generation_plan", artifact)
  end
end

function M.latest_artifact(context)
  context = context or compiler_context.current()
  return context:state_snapshot("generation_plan")
end

function M.accept_artifact(artifact, context, options)
  context = context or compiler_context.current()
  local accepted = options and options.trusted and artifact or deepcopy(artifact)
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
