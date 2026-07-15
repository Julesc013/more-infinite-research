local exact_recipe_policy = require("prototypes.mir.compatibility.diagnostics.exact_recipe_policy")

local M = {}

local function contains_pattern(text, patterns)
  local value = string.lower(text or "")
  for _, pattern in ipairs(patterns or {}) do
    if string.find(value, pattern) then return true end
  end
  return false
end

local function classify_related_recipe(recipe_name)
  if not string.find(recipe_name or "", "^atan%-") then return nil end
  if not contains_pattern(recipe_name, {"ash"}) then return nil end
  if contains_pattern(recipe_name, {"landfill", "foundation", "tile"}) then return "tile_surface" end
  if contains_pattern(recipe_name, {"recovery", "recover", "recycle", "clean", "restore"}) then return "resource_recovery" end
  return "ash_sink"
end

function M.emit()
  exact_recipe_policy.emit({
    overlay_id = "atan-ash",
    policy = "atan-ash/ash-separation",
    allowed_generated_reason = "ash_separation_stream_emitted",
    allowed_family = "ash_separation",
    denied = {
      ash_sink = {
        reason = "ash_sink_outside_stream",
        risk = "ash_sink"
      },
      tile_surface = {
        reason = "tile_surface_outside_stream",
        risk = "tile_surface"
      },
      resource_recovery = {
        reason = "resource_recovery_outside_stream",
        risk = "resource_recovery"
      }
    },
    classify_related = classify_related_recipe
  })
end

return M
