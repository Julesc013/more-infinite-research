local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {}

-- This policy describes technology behavior, not whether a setting defaults on.

local CLASS_POLICIES = {
  ["factory-disruptive"] = {
    settings_rank = "000",
    fallback_tooltip_note = {
      "mod-setting-description.mir-note-risk-factory-disruptive"
    }
  }
}

local function context_suffix(context)
  if context == nil or context == "" then return "" end
  return " for " .. tostring(context)
end

local function validate_localised_string(value, context)
  if type(value) ~= "table" or type(value[1]) ~= "string" or value[1] == "" then
    error("Technology risk tooltip_note must be a localized string" .. context_suffix(context) .. ".", 3)
  end
end

function M.normalize(raw, context)
  if raw == nil then return nil end
  if type(raw) == "string" then raw = {class = raw} end
  if type(raw) ~= "table" then
    error("Technology risk must be a table or class id" .. context_suffix(context) .. ".", 3)
  end

  local class = raw.class
  local policy = CLASS_POLICIES[class]
  if not policy then
    error("Unknown technology risk class " .. tostring(class) .. context_suffix(context) .. ".", 3)
  end
  if type(raw.reason) ~= "string" or raw.reason == "" then
    error("Technology risk requires a stable reason" .. context_suffix(context) .. ".", 3)
  end

  local tooltip_note = raw.tooltip_note or policy.fallback_tooltip_note
  validate_localised_string(tooltip_note, context)
  return {
    schema = 1,
    class = class,
    reason = raw.reason,
    tooltip_note = deepcopy(tooltip_note),
    settings_rank = policy.settings_rank
  }
end

function M.settings_rank(raw)
  local risk = M.normalize(raw)
  return risk and risk.settings_rank or nil
end

local function contains_locale_key(value, locale_key, seen)
  if type(value) ~= "table" then return false end
  seen = seen or {}
  if seen[value] then return false end
  seen[value] = true
  if value[1] == locale_key then return true end
  for _, nested in pairs(value) do
    if contains_locale_key(nested, locale_key, seen) then return true end
  end
  return false
end

function M.append_tooltip(description, raw)
  local risk = M.normalize(raw)
  if not risk then return deepcopy(description) end
  local base = deepcopy(description)
  local note = deepcopy(risk.tooltip_note)
  if contains_locale_key(base, note[1]) then return base end
  if base == nil then return note end
  return {"", base, "\n\n", note}
end

function M.classification(raw)
  return M.normalize(raw)
end

return M
