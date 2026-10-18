-- Keep the stable startup-setting identity without exposing a second compiler.
-- A saved 4.3.0 Classic selection is accepted as a Full compatibility alias;
-- it must never silently omit established technologies during an upgrade.
local M = {name = "mir-compiler-profile"}

function M.get(factorio_line)
  -- Historical packages retain their numeric-unit and reduced-surface path.
  -- They do not share the modern startup/profile contract.
  if type(factorio_line) == "string" and factorio_line:match("^0%.") then return "full" end
  local setting = settings and settings.startup and settings.startup[M.name]
  -- Normalize raw old values too: engine setting normalization is not the
  -- only caller (runtime settings readers and controlled contexts also call).
  local value = setting and setting.value or "full"
  if value ~= "classic" and value ~= "full" then
    error("Unsupported MIR compiler profile: " .. tostring(value), 2)
  end
  return "full"
end

function M.prototype()
  return {
    type = "string-setting",
    name = M.name,
    setting_type = "startup",
    default_value = "full",
    -- Retain the old serialized value so Factorio need not discard or rewrite
    -- stored startup settings. Both values execute Full; this compatibility
    -- field is hidden rather than offered as a second player-facing mode.
    allowed_values = {"full", "classic"},
    hidden = true,
    order = "a-000-compiler-profile",
    localised_name = {"mod-setting-name.mir-compiler-profile"},
    localised_description = {"mod-setting-description.mir-compiler-profile"}
  }
end

return M
