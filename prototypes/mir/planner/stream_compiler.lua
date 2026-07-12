local C = require("prototypes.mir.streams.registry")
local D = require("prototypes.mir.report.diagnostics_sink")
local deepcopy = require("prototypes.mir.core.deepcopy")
local table_utils = require("prototypes.mir.core.table")
local adoption_policy = require("prototypes.mir.policy.adoption_policy")
local costs = require("prototypes.mir.planner.costs")
local icon_builder = require("prototypes.mir.emit.icon_builder")
local owner_policy = require("prototypes.mir.policy.owner_policy")
local recipe_productivity_planner = require("prototypes.mir.capabilities.recipe_productivity.planner")
local direct_effects_planner = require("prototypes.mir.planner.direct_effects")
local native_modifiers = require("prototypes.mir.planner.native_modifiers")
local native_effect_coverage = require("prototypes.mir.policy.native_effect_coverage")
local planner_requirements = require("prototypes.mir.planner.requirements")
local planner_prerequisites = require("prototypes.mir.planner.prerequisites")
local planner_science = require("prototypes.mir.planner.science")
local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local stream_emitter = require("prototypes.mir.emit.stream_spec_adapter")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local effect_scaling = require("prototypes.mir.settings.effect_scaling")
local generation_plan = require("prototypes.mir.planner.generation_plan")
local family_resolver = require("prototypes.mir.families.resolver")
local family_registry = require("prototypes.mir.families.registry")
local fingerprint = require("prototypes.mir.core.fingerprint")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")
local effective_settings = require("prototypes.mir.settings.effective")
local compatibility_packs = require("prototypes.mir.compatibility.packs.registry")

local M = {}
local latest_plan = nil

local function proof_gates(action, reason)
  local materializes = action ~= "skip"
  return {
    target_supported = materializes or not tostring(reason):find("unsupported", 1, true),
    effect_valid = materializes or reason ~= "no_available_direct_effects",
    owner_conflict_free = materializes or not tostring(reason):find("ambiguous", 1, true),
    science_compatible = materializes or reason ~= "no_lab_compatible_science",
    lab_compatible = materializes or reason ~= "no_lab_compatible_science",
    prerequisites_acyclic = true,
    loop_safe = true
  }
end

local function lname(key, spec)
  if spec.localised_name then return spec.localised_name end
  local locale_key = "technology-name.more-infinite-research."..key
  local out = {locale_key}
  if spec.icon_item then
    table.insert(out, {"item-name."..spec.icon_item})
  elseif spec.icon_fluid then
    table.insert(out, {"fluid-name."..spec.icon_fluid})
  elseif spec.items and #spec.items == 1 then
    table.insert(out, {"item-name."..spec.items[1]})
  elseif spec.fluids and #spec.fluids == 1 then
    table.insert(out, {"fluid-name."..spec.fluids[1]})
  elseif spec.icon_tech then
    table.insert(out, {"technology-name."..spec.icon_tech})
  end
  return out
end

local function ldesc(spec)
  if spec.localised_description then return spec.localised_description end
  if spec.description_locale_key then return { spec.description_locale_key } end
  if spec.direct_effects then
    return {"technology-description.more-infinite-research.direct_effect"}
  end
  return {"technology-description.more-infinite-research.recipe_productivity"}
end

local function emit_stream_technology(key, spec, fields)
  return stream_emitter.emit(key, spec, fields)
end

local function append_unique_item(items, seen, item_name)
  if item_name and not seen[item_name] then
    seen[item_name] = true
    table.insert(items, item_name)
  end
end

local function expand_dynamic_items(spec)
  if not (spec and spec.dynamic_items_from_lab_inputs) then return spec end

  local out = deepcopy(spec)

  local base_group_items = {}
  for _, item_name in ipairs(out.items or {}) do
    table.insert(base_group_items, item_name)
  end

  if not out.groups then
    out.groups = {
      {
        change = C.shared.per_level_default,
        items = base_group_items
      }
    }
  end
  if not out.groups[1] then
    out.groups[1] = {
      change = C.shared.per_level_default,
      items = base_group_items
    }
  end
  out.groups[1].items = out.groups[1].items or {}

  local first_group_seen = {}
  for _, item_name in ipairs(out.groups[1].items) do
    first_group_seen[item_name] = true
  end
  for _, item_name in ipairs(base_group_items) do
    append_unique_item(out.groups[1].items, first_group_seen, item_name)
  end

  local seen = {}
  for _, item_name in ipairs(out.items or {}) do
    seen[item_name] = true
  end
  for _, group in ipairs(out.groups or {}) do
    for _, item_name in ipairs(group.items or {}) do
      seen[item_name] = true
    end
  end

  for _, item_name in ipairs(science_packs.pack_list_all()) do
    append_unique_item(out.groups[1].items, seen, item_name)
  end

  return out
end

local function plan_row(key, spec, action, reason, diagnostics, extra)
  local row = {
    schema = 2,
    manifest_id = spec.manifest_id or key,
    stream_key = key,
    action = action,
    reason = reason,
    source = spec.automatic_family and "family-rule" or "fixed-stream",
    spec = spec,
    diagnostics = diagnostics,
    gates = proof_gates(action, reason)
  }
  for field, value in pairs(extra or {}) do row[field] = value end
  return row
end

local function skip_row(key, spec, reason, ingredients, effects, lab_status, extra)
  return plan_row(
    key,
    spec,
    "skip",
    reason,
    D.stream_fields(key, spec, "skipped", reason, ingredients, nil, effects, lab_status, extra)
  )
end

local function attach_family_recipes(key, buckets)
  local mode = effective_settings.get("mir-automatic-compiler-mode") or "safe-attach"
  if mode == "off" or mode == "report" then return buckets end
  local attachments = family_resolver.attachments_for_stream(key)
  if #attachments == 0 then return buckets end

  local assigned, buckets_by_change = {}, {}
  for _, bucket in ipairs(buckets or {}) do
    buckets_by_change[bucket.change] = bucket
    for _, recipe_name in ipairs(bucket.recipes or {}) do assigned[recipe_name] = true end
  end
  for _, attachment in ipairs(attachments) do
    if not assigned[attachment.recipe] then
      local bucket = buckets_by_change[attachment.change]
      if not bucket then
        bucket = {change = attachment.change, recipes = {}}
        buckets_by_change[attachment.change] = bucket
        table.insert(buckets, bucket)
      end
      table.insert(bucket.recipes, attachment.recipe)
      assigned[attachment.recipe] = true
    end
  end
  for _, bucket in ipairs(buckets or {}) do table.sort(bucket.recipes) end
  return buckets
end

local function plan_stream(key, raw_spec)
  if raw_spec.automatic_family then
    local mode = effective_settings.get("mir-automatic-compiler-mode") or "safe-attach"
    if mode ~= "safe-generate" and mode ~= "exact-pack" then
      return skip_row(key, raw_spec, "automatic_family_mode_" .. tostring(mode))
    end
  end
  if not costs.enabled_for(key, raw_spec) then
    return skip_row(key, raw_spec, "disabled")
  end
  local missing = planner_requirements.missing_reason(key, raw_spec)
  if missing then
    return skip_row(key, raw_spec, missing)
  end

  local spec = expand_dynamic_items(raw_spec)

  local base_cost = costs.base_cost_for(key, spec)
  local growth_factor = costs.growth_factor_for(key, spec)
  local max_level = costs.max_level_for(key, spec)
  local count_formula = tostring(base_cost) .. " * " .. tostring(growth_factor) .. "^(L-1)"
  local research_time = costs.research_time_for(key, spec)

  local direct_effects = nil
  if spec.direct_effects then
    direct_effects = direct_effects_planner.available_for_stream(key, spec)
    if #direct_effects == 0 then
      return skip_row(key, spec, "no_available_direct_effects")
    end
    if spec.adopt_exact_native_effect_owner and not native_effect_coverage.prefer_mir() then
      local covered, owners = native_effect_coverage.external_coverage_for_effects(direct_effects)
      if covered then
        return skip_row(key, spec, "covered_by_existing_infinite_native_modifier", nil, direct_effects, nil, {
          owners = table.concat(owners, ",")
        })
      end
    end
  end

  local ingredients, lab_status = planner_science.ingredients_for_stream(key, spec)
  if not ingredients or #ingredients == 0 then
    return skip_row(key, spec, "no_lab_compatible_science", ingredients, direct_effects, lab_status)
  end

  if direct_effects and #direct_effects > 0 then
    local prerequisites = planner_prerequisites.build_for(key, ingredients)
    local emitted_effects = effect_scaling.scale_stream_effects(key, spec, direct_effects)
    local fields = {
      localised_name = lname(key, spec),
      localised_description = ldesc(spec),
      icons = icon_builder.icons_for_stream(spec),
      effects = emitted_effects,
      prerequisites = prerequisites,
      count_formula = count_formula,
      ingredients = ingredients,
      research_time = research_time,
      max_level = max_level,
    }
    return plan_row(key, spec, "emit", "direct_effect",
      D.stream_fields(key, spec, "generated", "direct_effect", ingredients, prerequisites, emitted_effects, lab_status), {
        technology_name = spec.technology_name or ("recipe-prod-" .. key .. "-1"),
        fields = fields,
        direct_effects = true,
        overlap_effects = direct_effects
      })
  end

  if not target_line.feature_enabled("recipe_productivity") then
    return skip_row(key, spec, "recipe_productivity_unsupported", ingredients, {}, lab_status)
  end

  local buckets = recipe_productivity_planner.match_buckets(key, spec)
  buckets = attach_family_recipes(key, buckets)
  local covered_by_existing
  buckets, covered_by_existing = owner_policy.filter_existing_recipe_productivity(key, spec, buckets)
  local adopted_effects, family_blocked, adoption_owner_name, adoption
  buckets, adopted_effects, family_blocked, adoption_owner_name, adoption = adoption_policy.plan_recipe_productivity_family(key, spec, buckets)
  if adopted_effects and #adopted_effects > 0 then
    return plan_row(key, spec, "adopt", "adopted_into_existing_productivity_family",
      D.stream_fields(key, spec, "adopted", "adopted_into_existing_productivity_family", ingredients, nil, adopted_effects, lab_status, {
        owners = adoption_owner_name,
        recipes = owner_policy.recipe_names_from_effects(adopted_effects)
      }), {
        adoption = adoption
      })
  end
  local effects = recipe_productivity_planner.effects_from_buckets(key, buckets)
  if #effects == 0 then
    if adopted_effects and #adopted_effects > 0 then
      error("GenerationPlan adoption row was not created for stream " .. key)
    end
    local reason = "no_matching_recipes"
    if covered_by_existing and #covered_by_existing > 0 then
      reason = "covered_by_existing_infinite_recipe_productivity"
    elseif family_blocked and #family_blocked > 0 then
      reason = family_blocked[1].reason
    end
    return skip_row(key, spec, reason, ingredients, effects, lab_status)
  end

  local prerequisites = planner_prerequisites.build_for(key, ingredients)
  local emitted_effects = effect_scaling.scale_stream_effects(key, spec, effects)
  local fields = {
    localised_name = lname(key, spec),
    localised_description = ldesc(spec),
    icons = icon_builder.icons_for_stream(spec),
    effects = emitted_effects,
    prerequisites = prerequisites,
    count_formula = count_formula,
    ingredients = ingredients,
    research_time = research_time,
    max_level = max_level,
  }
  return plan_row(key, spec, "emit", "recipe_productivity",
    D.stream_fields(key, spec, "generated", "recipe_productivity", ingredients, prerequisites, emitted_effects, lab_status), {
      technology_name = spec.technology_name or ("recipe-prod-" .. key .. "-1"),
      fields = fields,
      direct_effects = false
    })
end

function M.compile()
  local streams = C.snapshot()
  local plan = generation_plan.new({
    source_fingerprints = {
      facts = fingerprint.of(recipe_facts.snapshot()),
      rules = fingerprint.of({streams = streams, families = family_registry.snapshot()}),
      compatibility_packs = fingerprint.of(compatibility_packs.snapshot()),
      target_profile = fingerprint.of(target_profiles.current())
    }
  })
  for _, key in ipairs(table_utils.sorted_keys(streams)) do
    plan:add(plan_stream(key, streams[key]))
  end
  return plan:finalize()
end

function M.apply(plan)
  for _, row in ipairs(plan:snapshot()) do
    if row.action == "emit" then
      if row.direct_effects then
        native_modifiers.record_overlaps(row.stream_key, row.overlap_effects)
      end
      local technology = emit_stream_technology(row.stream_key, row.spec, row.fields)
      if D.enabled() and not row.direct_effects then
        log("[more-infinite-research] Registered technology " .. technology.name)
      end
    elseif row.action == "adopt" then
      adoption_policy.apply_recipe_productivity_family(row.adoption)
    elseif row.reason ~= "disabled" then
      log("[more-infinite-research] Skipping stream " .. row.stream_key .. " because " .. row.reason .. ".")
    end
    D.stream(row.diagnostics)
  end

  if target_line.feature_enabled("recipe_productivity") then
    adoption_policy.emit_mod_data()
  end
end

function M.run()
  local plan = M.compile()
  latest_plan = plan
  M.apply(plan)
  return plan
end

function M.latest_artifact()
  return latest_plan and latest_plan:artifact() or nil
end

return M
