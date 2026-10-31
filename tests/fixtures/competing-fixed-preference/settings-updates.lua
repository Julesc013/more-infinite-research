local PROVIDERS = {
  ["plates-n-circuit-productivity"] = "0.0.2",
  ["Science_packs_productivity"] = "0.0.1",
  ["bioflux-productivity"] = "0.1.0",
  ["fish-productivity"] = "1.0.0",
}

local function fail(message)
  error("[mir5-fixed-competing-preference] " .. message)
end

if type(mods) ~= "table" or mods.base ~= "2.0.77" or mods["space-age"] ~= "2.0.77"
    or mods["more-infinite-research"] ~= "4.7.20002" then
  fail("unexpected F200 Space Age published reference closure")
end

local selected = 0
for name, version in pairs(PROVIDERS) do
  local actual = mods[name]
  if actual ~= nil and actual ~= version then fail("unsupported provider version: " .. name) end
  if actual == version then selected = selected + 1 end
end
if selected ~= 1 then fail("reference requires exactly one supported fixed provider") end

local settings = data.raw["bool-setting"]
local preference = settings and settings["mir-prefer-this-mod-for-competing-techs"]
if preference == nil or preference.setting_type ~= "startup"
    or type(preference.default_value) ~= "boolean" then
  fail("published competing-owner preference setting is absent or malformed")
end
preference.default_value = false
