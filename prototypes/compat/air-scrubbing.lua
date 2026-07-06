local D = require("prototypes.diagnostics")

local M = {}

local STREAM_KEY = "research_air_scrubbing_clean_filter"
local STREAM_ID = "mir-prod-air-scrubbing-clean-filter"
local TECH_NAME = "recipe-prod-research_air_scrubbing_clean_filter-1"

local ALLOWED_RECIPES = {
  "atan-pollution-filter",
  "atan-spore-filter"
}

local ALLOWED = {}
for _, recipe_name in ipairs(ALLOWED_RECIPES) do
  ALLOWED[recipe_name] = true
end

local RELATED_PATTERNS = {
  "pollution",
  "spore",
  "filter",
  "scrub"
}

local function contains_pattern(text, patterns)
  local value = string.lower(text or "")
  for _, pattern in ipairs(patterns or {}) do
    if string.find(value, pattern) then return true end
  end
  return false
end

local function has_recipe_productivity_effect(tech, recipe_name)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return true
    end
  end
  return false
end

local function tech_emits_recipe(recipe_name)
  return has_recipe_productivity_effect((data.raw.technology or {})[TECH_NAME], recipe_name)
end

local function bool_text(value)
  if value then return "true" end
  return "false"
end

local function decision(row)
  row.policy = row.policy or "air-scrubbing/clean-filter"
  row.source = row.source or "compat_policy:air-scrubbing"
  row.stable_stream_id = row.stable_stream_id or STREAM_ID
  D.decision(row)
end

local function loop_risk(recipe_name, risk, reason)
  D.loop_risk({
    key = recipe_name,
    subject_type = "recipe",
    subject = recipe_name,
    status = "diagnostic",
    reason = reason,
    risks = risk,
    confidence = "0.95"
  })
end

local function classify_related_recipe(recipe_name)
  if ALLOWED[recipe_name] then return "clean_filter" end
  if not string.find(recipe_name or "", "^atan%-") then return nil end
  if not contains_pattern(recipe_name, RELATED_PATTERNS) then return nil end
  if contains_pattern(recipe_name, {"scrubbing"}) then return "scrubbing_environmental" end
  if contains_pattern(recipe_name, {"cleaning", "restore", "recovery", "recover", "recycle"}) then return "cleaning_recovery" end
  if contains_pattern(recipe_name, RELATED_PATTERNS) then return "unknown_related" end
  return nil
end

local function emit_allowed(recipe_name)
  local emitted = tech_emits_recipe(recipe_name)
  decision({
    key = recipe_name,
    subject_type = "recipe",
    subject = recipe_name,
    family = "clean_filter",
    confidence = emitted and "family=1.0,science=1.0,lab=1.0,loop_safety=1.0,owner=1.0,total=1.0" or "family=1.0,total=0.5",
    decision = emitted and "generate_stream" or "diagnose_only",
    emitted = bool_text(emitted),
    reason = emitted and "clean_filter_stream_emitted" or "allowed_target_not_emitted",
    blockers = emitted and "" or "stream_not_emitted",
    risks = "",
    effects = emitted and "1" or "0"
  })
  return emitted and 1 or 0
end

local function emit_missing(recipe_name)
  decision({
    key = recipe_name,
    subject_type = "recipe",
    subject = recipe_name,
    family = "clean_filter",
    confidence = "family=1.0,total=0.0",
    decision = "diagnose_only",
    emitted = "false",
    reason = "missing_target_recipe",
    blockers = "missing_target_recipe",
    risks = ""
  })
end

local function emit_denied(recipe_name, family, reason, risk)
  loop_risk(recipe_name, risk, reason)
  decision({
    key = recipe_name,
    subject_type = "recipe",
    subject = recipe_name,
    family = family,
    confidence = "family=0.95,loop_safety=0.0,total=0.95",
    decision = "diagnose_only",
    emitted = "false",
    reason = reason,
    blockers = risk,
    risks = risk
  })
end

local function emit_unknown(recipe_name)
  decision({
    key = recipe_name,
    subject_type = "recipe",
    subject = recipe_name,
    family = "unknown_related",
    confidence = "family=0.25,total=0.25",
    decision = "observe_unknown",
    emitted = "false",
    reason = "related_recipe_not_classified",
    blockers = "unknown_related_recipe",
    risks = "unknown_related_recipe"
  })
end

function M.emit()
  if not D.enabled() then return end

  local recipes = data.raw.recipe or {}
  local active = false
  for recipe_name, _ in pairs(recipes) do
    if classify_related_recipe(recipe_name) then
      active = true
      break
    end
  end
  if not active then return end

  local generated = 0
  local missing = 0
  local rejected = 0
  local unknown = 0

  for _, recipe_name in ipairs(ALLOWED_RECIPES) do
    if recipes[recipe_name] then
      generated = generated + emit_allowed(recipe_name)
    else
      missing = missing + 1
      emit_missing(recipe_name)
    end
  end

  local related = {}
  for recipe_name, _ in pairs(recipes) do
    if not ALLOWED[recipe_name] then
      local family = classify_related_recipe(recipe_name)
      if family then table.insert(related, {recipe = recipe_name, family = family}) end
    end
  end
  table.sort(related, function(a, b) return a.recipe < b.recipe end)

  for _, entry in ipairs(related) do
    if entry.family == "scrubbing_environmental" then
      rejected = rejected + 1
      emit_denied(entry.recipe, entry.family, "environmental_removal_loop", "scrubbing_environmental")
    elseif entry.family == "cleaning_recovery" then
      rejected = rejected + 1
      emit_denied(entry.recipe, entry.family, "recovery_loop", "cleaning_recovery")
    elseif entry.family == "unknown_related" then
      unknown = unknown + 1
      emit_unknown(entry.recipe)
    end
  end

  D.compatibility_plan({
    key = STREAM_KEY,
    status = "diagnostic",
    reason = "air_scrubbing_policy_summary",
    total = tostring(#ALLOWED_RECIPES),
    generated = tostring(generated),
    warnings = tostring(rejected + unknown + missing),
    rejected = tostring(rejected),
    unknown = tostring(unknown),
    missing = tostring(missing),
    stable_stream_id = STREAM_ID
  })
end

return M
