-- Disposable test selection; player defaults and saved settings are untouched.
local choices = { ["ric-world-mode"] = "marine", ["ric-progression-mode"] = "nauvis-only" }
for name, value in pairs(choices) do
  local setting = data.raw["string-setting"] and data.raw["string-setting"][name]
  if not setting then error("[mir5-ric-context] upstream setting absent: " .. name) end
  setting.default_value = value
  setting.allowed_values = {value}
end
