local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local declared_planner = require("prototypes.mir.planner.classic.plan")
local compiler = require("prototypes.mir.planner.compiler")
local executor = require("prototypes.mir.emit.technology_operation_executor")
local mutation_journal = require("prototypes.mir.domain.compiler.mutation_journal")
local fingerprint = require("prototypes.mir.core.fingerprint")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local mod_data = require("prototypes.mir.emit.mod_data")

local M = {}

local function apply_independent_features()
  if target_line.feature_enabled("compatibility_repairs") then
    require("prototypes.mir.compatibility.repairs.registry").apply({bounded = true})
  end
  if target_line.feature_enabled("module_permissions") then
    require("prototypes.mir.pipeline.module_permissions").apply()
  end
  if target_line.feature_enabled("prototype_limits") then
    require("prototypes.mir.pipeline.prototype_limits").apply({allow_material_analysis = false})
  end
  if target_line.feature_enabled("pipeline_extent") then
    local value = require("prototypes.mir.settings.effective").get("mir-pipeline-extent-multiplier")
    local multiplier = require("prototypes.mir.settings.pipeline_extent").multiplier(value)
    if multiplier ~= 1 then require("prototypes.mir.pipeline.extent").apply(multiplier) end
  end
end

function M.run()
  local context = compiler_context.new()
  return compiler_context.with_active(context, function()
    apply_independent_features()
    local selected = declared_planner.compile(context)
    local ids = {}
    for _, row in ipairs(selected.stream_plan.rows or {}) do
      if row.action == "emit" then table.insert(ids, row.manifest_id) end
    end
    for _, row in ipairs(selected.base_extension_operations or {}) do
      table.insert(ids, row.manifest_id)
    end
    table.sort(ids)
    local profile = {
      schema = 1,
      kind = "mir-classic-profile-public",
      profile = "classic",
      full_catalog_status = "not-evaluated",
      supported_manifest_ids = ids,
      unsupported_classes = {
        "automatic-families", "competing-owner-replacements", "generic-mod-inference",
        "material-progression", "recipe-productivity", "weapon-speed-redistribution"
      },
      omitted_research_not_preserved = true
    }
    profile.profile_fingerprint = fingerprint.of(profile)
    local plan = compiler.compile_declared_plan(selected.stream_plan,
      selected.base_extension_operations, {
        profile_fingerprint = profile.profile_fingerprint,
        source_fingerprint = fingerprint.of(selected.source_fingerprints or {})
      })
    local journal = mutation_journal.new(plan)
    executor.apply_plan(plan, journal)
    local receipt = journal:finalize()
    if target_line.feature_enabled("scripted_techs") then
      local policy = require("prototypes.mir.domain.technology.maximum_level_binding")
        .from_plan(selected, {
          plan_fingerprint = plan.plan_fingerprint,
          scripted_techs_supported = true,
          mod_data_supported = target_line.mod_data_supported()
        })
      policy = require("prototypes.mir.pipeline.mutations.maximum_level_presentation")
        .apply_policy(policy)
      mod_data.emit_maximum_level_policy(policy)
    end
    if target_line.mod_data_supported() then
      mod_data.emit_compiler_profile(profile)
    end
    context:set_state("classic_compilation_plan", selected)
    context:set_state("classic_profile", profile)
    context:set_state("classic_mutation_journal", receipt)
    if log then
      log("[more-infinite-research] Classic compiler completed: emitted=" .. #plan.operations
        .. " full-catalog=not-evaluated; recipe-productivity, material and generic mod support omitted."
        .. " Previously generated research outside this profile is not preserved."
        .. " Select the full compiler startup profile before loading a factory that needs that research.")
    end
    require("prototypes.mir.report.diagnostics_sink").flush()
    return context
  end)
end

return M
