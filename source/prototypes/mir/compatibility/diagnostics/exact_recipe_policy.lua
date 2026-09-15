local D = require("prototypes.mir.report.diagnostics_sink")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local overlay_loader = require("prototypes.mir.compatibility.overlay_loader")
local report = require("prototypes.mir.report.compatibility_diagnostics")

local M = {}

local function bool_text(value)
  if value then return "true" end
  return "false"
end

local function has_recipe_productivity_effect(tech, recipe_name)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return true
    end
  end
  return false
end

local function recipe_set(recipes)
  local out = {}
  for _, recipe_name in ipairs(recipes or {}) do
    out[recipe_name] = true
  end
  return out
end

local function normalize_classification(result)
  if result == nil then return nil end
  if type(result) == "string" then return { family = result } end
  return result
end

local function emit_decision(ctx, row)
  row.policy = row.policy or ctx.policy
  row.source = row.source or ctx.source
  row.stable_stream_id = row.stable_stream_id or ctx.stream_id
  report.decision(D, row)
end

local function emit_loop_risk(recipe_name, risk, reason)
  report.loop_risk(D, {
    key = recipe_name,
    subject_type = "recipe",
    subject = recipe_name,
    status = "diagnostic",
    reason = reason,
    risks = risk,
    confidence = "0.95"
  })
end

local function emit_allowed(ctx, recipe_name)
  local emitted = has_recipe_productivity_effect(data_raw.technology(ctx.tech_name), recipe_name)
  emit_decision(ctx, {
    key = recipe_name,
    subject_type = "recipe",
    subject = recipe_name,
    family = ctx.allowed_family,
    confidence = emitted and ctx.allowed_generated_confidence or ctx.allowed_missing_stream_confidence,
    decision = emitted and "generate_stream" or "diagnose_only",
    emitted = bool_text(emitted),
    reason = emitted and ctx.allowed_generated_reason or ctx.allowed_not_emitted_reason,
    blockers = emitted and "" or "stream_not_emitted",
    risks = "",
    effects = emitted and "1" or "0"
  })
  return emitted and 1 or 0
end

local function emit_missing(ctx, recipe_name)
  emit_decision(ctx, {
    key = recipe_name,
    subject_type = "recipe",
    subject = recipe_name,
    family = ctx.allowed_family,
    confidence = "family=1.0,total=0.0",
    decision = "diagnose_only",
    emitted = "false",
    reason = ctx.missing_target_reason,
    blockers = "missing_target_recipe",
    risks = ""
  })
end

local function emit_denied(ctx, recipe_name, classification)
  local family = classification.family
  local deny = ctx.denied[family] or {}
  local reason = classification.reason or deny.reason or ctx.denied_reason
  local risk = classification.risk or deny.risk or family
  emit_loop_risk(recipe_name, risk, reason)
  emit_decision(ctx, {
    key = recipe_name,
    subject_type = "recipe",
    subject = recipe_name,
    family = family,
    confidence = classification.confidence or "family=0.95,loop_safety=0.0,total=0.95",
    decision = "diagnose_only",
    emitted = "false",
    reason = reason,
    blockers = risk,
    risks = risk
  })
end

local function emit_unknown(ctx, recipe_name, classification)
  local family = classification.family or ctx.unknown_family
  local risk = classification.risk or ctx.unknown_risk
  emit_decision(ctx, {
    key = recipe_name,
    subject_type = "recipe",
    subject = recipe_name,
    family = family,
    confidence = classification.confidence or "family=0.25,total=0.25",
    decision = "observe_unknown",
    emitted = "false",
    reason = classification.reason or ctx.unknown_reason,
    blockers = classification.blockers or risk,
    risks = risk
  })
end

local function build_context(config)
  local overlay = overlay_loader.get(config.overlay_id)
  local capability = overlay.capabilities[config.capability or "recipe-productivity"]
  local diagnostics = capability.diagnostics or {}
  local stream = capability.stream
  local allowed_recipes = capability.exact_recipes or {}

  return {
    overlay = overlay,
    capability = capability,
    stream_key = stream.key,
    stream_id = stream.id,
    tech_name = stream.technology,
    allowed_recipes = allowed_recipes,
    allowed = recipe_set(allowed_recipes),
    allowed_family = config.allowed_family or capability.family,
    policy = config.policy or (overlay.id .. "/" .. tostring(capability.family or "exact")),
    source = config.source or ("compat_policy:" .. overlay.id),
    classify_related = config.classify_related,
    denied = config.denied or {},
    denied_reason = config.denied_reason or diagnostics.denied_reason or "outside_exact_recipe_policy",
    missing_target_reason = config.missing_target_reason or diagnostics.missing_target_reason or "missing_target_recipe",
    allowed_generated_reason = config.allowed_generated_reason or "exact_recipe_stream_emitted",
    allowed_not_emitted_reason = config.allowed_not_emitted_reason or "allowed_target_not_emitted",
    allowed_generated_confidence = config.allowed_generated_confidence or "family=1.0,science=1.0,lab=1.0,loop_safety=1.0,owner=1.0,total=1.0",
    allowed_missing_stream_confidence = config.allowed_missing_stream_confidence or "family=1.0,total=0.5",
    policy_summary_reason = config.policy_summary_reason or diagnostics.policy_summary_reason or "exact_recipe_policy_summary",
    unknown_family = config.unknown_family or "unknown_related",
    unknown_reason = config.unknown_reason or diagnostics.unknown_reason or "related_recipe_not_classified",
    unknown_risk = config.unknown_risk or "unknown_related_recipe"
  }
end

local function classify_recipe(ctx, recipe_name)
  if ctx.allowed[recipe_name] then return { family = ctx.allowed_family, disposition = "allowed" } end
  if not ctx.classify_related then return nil end
  return normalize_classification(ctx.classify_related(recipe_name, ctx))
end

function M.emit(config)
  if not D.enabled() then return end

  local ctx = build_context(config or {})
  local recipe_names = recipe_facts.all_names()
  local recipes = {}
  for _, recipe_name in ipairs(recipe_names) do recipes[recipe_name] = true end
  local active = false
  for _, recipe_name in ipairs(recipe_names) do
    if classify_recipe(ctx, recipe_name) then
      active = true
      break
    end
  end
  if not active then return end

  local generated = 0
  local missing = 0
  local rejected = 0
  local unknown = 0

  for _, recipe_name in ipairs(ctx.allowed_recipes) do
    if recipes[recipe_name] then
      generated = generated + emit_allowed(ctx, recipe_name)
    else
      missing = missing + 1
      emit_missing(ctx, recipe_name)
    end
  end

  local related = {}
  for _, recipe_name in ipairs(recipe_names) do
    if not ctx.allowed[recipe_name] then
      local classification = classify_recipe(ctx, recipe_name)
      if classification then
        table.insert(related, { recipe = recipe_name, classification = classification })
      end
    end
  end
  table.sort(related, function(a, b) return a.recipe < b.recipe end)

  for _, entry in ipairs(related) do
    local classification = entry.classification
    if classification.decision == "observe_unknown" or classification.family == ctx.unknown_family then
      unknown = unknown + 1
      emit_unknown(ctx, entry.recipe, classification)
    else
      rejected = rejected + 1
      emit_denied(ctx, entry.recipe, classification)
    end
  end

  report.compatibility_plan(D, {
    key = ctx.stream_key,
    status = "diagnostic",
    reason = ctx.policy_summary_reason,
    total = tostring(#ctx.allowed_recipes),
    generated = tostring(generated),
    warnings = tostring(rejected + unknown + missing),
    rejected = tostring(rejected),
    unknown = tostring(unknown),
    missing = tostring(missing),
    stable_stream_id = ctx.stream_id
  })
end

return M
