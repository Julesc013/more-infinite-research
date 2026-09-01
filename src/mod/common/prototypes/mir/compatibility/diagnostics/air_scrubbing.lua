local exact_recipe_policy = require("prototypes.mir.compatibility.diagnostics.exact_recipe_policy")

local M = {}

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

local function classify_related_recipe(recipe_name)
  if not string.find(recipe_name or "", "^atan%-") then return nil end
  if not contains_pattern(recipe_name, RELATED_PATTERNS) then return nil end
  if contains_pattern(recipe_name, {"scrubbing"}) then return "scrubbing_environmental" end
  if contains_pattern(recipe_name, {"cleaning", "restore", "recovery", "recover", "recycle"}) then return "cleaning_recovery" end
  if contains_pattern(recipe_name, RELATED_PATTERNS) then
    return { family = "unknown_related", decision = "observe_unknown" }
  end
  return nil
end

function M.emit()
  exact_recipe_policy.emit({
    overlay_id = "air-scrubbing",
    policy = "air-scrubbing/clean-filter",
    allowed_generated_reason = "clean_filter_stream_emitted",
    allowed_family = "clean_filter",
    denied = {
      scrubbing_environmental = {
        reason = "environmental_removal_loop",
        risk = "scrubbing_environmental"
      },
      cleaning_recovery = {
        reason = "recovery_loop",
        risk = "cleaning_recovery"
      }
    },
    classify_related = classify_related_recipe
  })
end

return M
