local deepcopy = require("prototypes.mir.core.deepcopy")
local base_extensions = require("prototypes.mir.emit.base_extensions")
local stream_compiler = require("prototypes.mir.planner.stream_compiler")
local generation_plan = require("prototypes.mir.planner.generation_plan")
local fingerprint = require("prototypes.mir.core.fingerprint")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local effect_safety = require("prototypes.mir.emit.effect_safety")
local effective_settings = require("prototypes.mir.settings.effective")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local M = {}
local latest = nil

local function materialized_stream_operations(artifact)
  local out = {}
  for _, row in ipairs(artifact.rows or {}) do
    if row.action == "emit" then
      table.insert(out, {
        schema = 2,
        operation = "emit_stream",
        stream_key = row.stream_key,
        manifest_id = row.manifest_id,
        technology_name = row.technology_name,
        technology = {
          name = row.technology_name,
          effects = deepcopy(row.fields.effects),
          prerequisites = deepcopy(row.fields.prerequisites),
          unit = {
            ingredients = deepcopy(row.fields.ingredients),
            count_formula = row.fields.count_formula,
            time = row.fields.research_time
          },
          max_level = row.fields.max_level,
          upgrade = true
        },
        registry = {kind = "stream", key = row.stream_key}
      })
    elseif row.action == "adopt" then
      table.insert(out, {
        schema = 2,
        operation = "adopt_stream",
        stream_key = row.stream_key,
        manifest_id = row.manifest_id,
        technology_name = row.adoption.owner,
        effects = deepcopy(row.adoption.effects)
      })
    end
  end
  return out
end

local function normalized_base_operation(operation)
  local out = deepcopy(operation)
  out.schema = 2
  out.manifest_id = out.manifest_id or ("base-extension:" .. tostring(out.key) .. ":" .. tostring(out.technology_name))
  out.registry = {kind = "base_extension", key = out.key}
  return out
end

local function apply_weapon_overlap_policy(operation, stream_operations, stream_rows)
  if operation.key ~= "weapon-shooting-speed" then return operation end
  local mode = effective_settings.get("mir-adjust-vanilla-weapon-speed-techs") or target_line.weapon_overlap_default()
  if mode == "off" then
    operation.planned_policy = "weapon-speed-overlap-retained"
    return operation
  end
  local strip = {}
  if mode == "always" then
    strip.rocket = true
    strip["cannon-shell"] = true
  else
    for _, stream_operation in ipairs(stream_operations) do
      for _, effect in ipairs((stream_operation.technology and stream_operation.technology.effects) or {}) do
        if effect.type == "gun-speed" and (effect.ammo_category == "rocket" or effect.ammo_category == "cannon-shell") then
          strip[effect.ammo_category] = true
        end
      end
    end
    -- An exact external infinite owner suppresses the MIR stream but still
    -- takes over the same category. Preserve that finalized skip decision in
    -- the base-operation plan so the later mutation and output validator use
    -- one authority.
    for _, row in ipairs(stream_rows or {}) do
      if row.action == "skip" and row.reason == "covered_by_existing_infinite_native_modifier" then
        for _, effect in ipairs((row.spec and row.spec.direct_effects) or {}) do
          if effect.type == "gun-speed" and (effect.ammo_category == "rocket" or effect.ammo_category == "cannon-shell") then
            strip[effect.ammo_category] = true
          end
        end
      end
    end
  end
  local filtered = {}
  for _, effect in ipairs(operation.technology.effects or {}) do
    if not (effect.type == "gun-speed" and strip[effect.ammo_category]) then table.insert(filtered, effect) end
  end
  operation.technology.effects = filtered
  operation.planned_policy = "weapon-speed-overlap"
  return operation
end

local function validate_operations(operations)
  local technology_names, manifest_ids, effects = {}, {}, {}
  local planned_overlaps = {}
  local planned_technologies = {}
  for _, operation in ipairs(operations) do
    if operation.operation == "emit_stream" or operation.operation == "emit_base_extension" then
      if technology_names[operation.technology_name] then
        error("CompilationPlan contains technology-name collision: " .. operation.technology_name, 2)
      end
      technology_names[operation.technology_name] = operation.operation
      planned_technologies[operation.technology_name] = true
      if manifest_ids[operation.manifest_id] then
        error("CompilationPlan contains manifest collision: " .. operation.manifest_id, 2)
      end
      manifest_ids[operation.manifest_id] = operation.operation
    end
  end

  for _, operation in ipairs(operations) do
    local expected_effects = operation.effects or (operation.technology and operation.technology.effects) or {}
    effect_safety.assert_effects_allowed(expected_effects, "CompilationPlan " .. tostring(operation.technology_name))
    for _, effect in ipairs(expected_effects) do
      local identity = generation_plan.effect_identity(effect)
      if identity ~= "" then
        if effects[identity] then
          if operation.planned_policy == "weapon-speed-overlap-retained"
            or effects[identity].planned_policy == "weapon-speed-overlap-retained" then
            table.insert(planned_overlaps, {
              identity = identity,
              owners = {effects[identity].technology_name, operation.technology_name},
              policy = "weapon-speed-overlap-retained"
            })
          else
            error("CompilationPlan contains duplicate direct-effect identity: " .. identity, 2)
          end
        end
        effects[identity] = effects[identity] or operation
      end
    end
    if operation.technology then
      for _, prerequisite in ipairs(operation.technology.prerequisites or {}) do
        if not planned_technologies[prerequisite] and not data_raw.technology(prerequisite) then
          error("CompilationPlan prerequisite target is missing: " .. operation.technology_name .. " -> " .. prerequisite, 2)
        end
      end
    end
  end
  return {
    valid = true,
    operation_count = #operations,
    technology_count = (function() local count = 0; for _ in pairs(technology_names) do count = count + 1 end; return count end)(),
    manifest_count = (function() local count = 0; for _ in pairs(manifest_ids) do count = count + 1 end; return count end)(),
    effect_count = (function() local count = 0; for _ in pairs(effects) do count = count + 1 end; return count end)(),
    planned_overlap_count = #planned_overlaps,
    planned_overlaps = planned_overlaps
  }
end

function M.finalize(stream_plan, base_plan)
  local stream_artifact = type(stream_plan.artifact) == "function" and stream_plan:artifact() or deepcopy(stream_plan)
  if not stream_artifact or stream_artifact.schema ~= 3 then error("CompilationPlan requires GenerationPlan schema 3", 2) end
  local operations = materialized_stream_operations(stream_artifact)
  local stream_operations = deepcopy(operations)
  local normalized_base = {}
  for _, operation in ipairs(base_plan or {}) do
    local normalized = apply_weapon_overlap_policy(normalized_base_operation(operation), stream_operations, stream_artifact.rows)
    table.insert(normalized_base, normalized)
    table.insert(operations, deepcopy(normalized))
  end
  table.sort(operations, function(a, b)
    if a.technology_name ~= b.technology_name then return a.technology_name < b.technology_name end
    if a.operation ~= b.operation then return a.operation < b.operation end
    return tostring(a.manifest_id) < tostring(b.manifest_id)
  end)
  local validation_summary = validate_operations(operations)
  local source_fingerprints = deepcopy(stream_artifact.source_fingerprints or {})
  source_fingerprints.base_extensions = fingerprint.of(normalized_base)
  local artifact = {
    schema = 2,
    source_fingerprints = source_fingerprints,
    operations = operations,
    stream_plan = stream_artifact,
    base_extension_operations = normalized_base,
    validation_summary = validation_summary
  }
  artifact.fingerprint = fingerprint.of(artifact)
  return artifact
end

function M.compile()
  if latest then return latest end
  local stream_plan = stream_compiler.compile()
  local base_plan = base_extensions.plan_all()
  latest = M.finalize(stream_plan, base_plan)
  latest.stream_plan_object = stream_plan
  stream_compiler.accept(stream_plan)
  require("prototypes.mir.emit.mod_data").emit_generation_plan(latest.stream_plan)
  return latest
end

function M.apply_streams()
  local plan = M.compile()
  stream_compiler.apply(plan.stream_plan_object)
end

function M.apply_base_extensions()
  local plan = M.compile()
  base_extensions.apply_plan(plan.base_extension_operations)
end

function M.snapshot()
  local plan = M.compile()
  return deepcopy({
    schema = plan.schema,
    fingerprint = plan.fingerprint,
    source_fingerprints = plan.source_fingerprints,
    operations = plan.operations,
    stream_plan = plan.stream_plan,
    base_extension_operations = plan.base_extension_operations,
    validation_summary = plan.validation_summary
  })
end

function M.assert_output()
  return require("prototypes.mir.planner.output_validator").assert_compilation_artifact(M.snapshot())
end

return M
