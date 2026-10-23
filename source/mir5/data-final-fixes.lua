-- Preserve the two delivered exact-version loader repairs independently of
-- research construction. Inactive profiles never import the override body.
if type(mods) == "table" and type(mods.base) == "string" and mods.base:match("^2%.1%.")
    and (mods["atan-ash"] == "2.2.1" or mods["atan-nuclear-science"] == "0.3.3") then
  require("overrides.recipe_schema").apply(data.raw, mods, log)
end

local configuration = require("research.settings")
local values = configuration.resolve(settings.startup, helpers, log)
local productivity = require("research.productivity")
local generator = require("research.generator")

local gear
if values.enabled == true then
  -- Disabled continuity keeps the owned identity but does not load or inspect
  -- an active profile binding. Active bindings preflight named recipes here.
  local binding = require("compatibility.gear_bindings").select(mods, data.raw)
  gear = productivity.gears(values, binding)
else
  gear = productivity.gears(values)
end
local technologies = {gear}

-- The full authored catalogue has exact Base, Space Age, and K2SO captures.
-- A Krastorio marker alone never admits ordinary Space Age definitions.
local ordinary_profile = type(mods) == "table" and mods.Krastorio2 == nil
local modern_catalogue = require("compatibility.modern_catalogue")
local modern, modern_selection, native_owner_patches
if ordinary_profile or modern_catalogue.is_k2so(mods) then
  modern = require("research.modern")
  modern_selection = modern_catalogue.select(mods)
  -- Check every selected narrow patch before any intended technology write.
  modern.preflight_recipe_patches(modern_selection, data.raw)
  native_owner_patches = modern.preflight_native_owner_patches(modern_selection, data.raw, values)
  local generated = modern.technologies(modern_selection, values)
  modern.apply_weapon_speed_overlap(modern_selection, generated, values)
  for index = 1, #generated do technologies[#technologies + 1] = generated[index] end
end

-- The two scripted streams have no base fallback. Require both their exact
-- bindings and authoring body only after Space Age is active. This keeps its
-- independently captured K2SO path while generator preflight remains one
-- local unit before the first data-stage write.
if type(mods) == "table" and mods["space-age"] ~= nil
    and values.agricultural_growth_speed ~= nil and values.spoilage_preservation ~= nil then
  local bindings = require("compatibility.space_age_scripted_effects").select(mods, data.raw)
  local scripted = require("research.scripted_effects").technologies(values, bindings)
  for index = 1, #scripted do technologies[#technologies + 1] = scripted[index] end
end

-- Retain broad product targeting in one relevant recipe pass. This extends
-- detached authored effects without discovering families or inspecting
-- foreign research. Existing named routes and weights retain precedence.
require("research.product_target_extension").extend(technologies, values, {raw=data.raw, mods=mods})

-- One lab/science view serves this complete owned catalogue. Native owners
-- and foreign research are outside this detached publication boundary.
require("research.science").apply_family(technologies, nil, {
  options=values.options, raw=data.raw, target=require("platform.target"), mods=mods, log=log,
})
generator.install(technologies, data)
if modern then
  modern.apply_native_owner_patches(native_owner_patches)
  modern.apply_recipe_patches(modern_selection, data.raw)
end

-- These independent prototype limits are opt-in. Test effective post-import
-- values before importing their body, so the normal data stage does not build
-- its recipe classifier or inspect unrelated prototype groups.
local prototype_limit_option_names = {
  "mir-prototype-productivity-cap",
  "mir-recycling-return-chance",
  "mir-productivity-cap-self-recycling-only",
  "mir-prototype-efficiency-cap",
  "mir-prototype-pollution-cap",
  "mir-prototype-speed-floor",
  "mir-prototype-speed-cap",
  "mir-prototype-quality-cap",
  "mir-prototype-positive-power-floor"
}
local prototype_limits_active = false
for _, name in ipairs(prototype_limit_option_names) do
  if values.options[name] ~= configuration.default_value(name) then
    prototype_limits_active = true
    break
  end
end
if prototype_limits_active then
  local result = require("overrides.prototype_limits").apply(data.raw, values.options)
  if result.unsupported_receiver_limits > 0 and type(log) == "function" then
    log("[more-infinite-research] This engine has fixed effect-receiver limits; "
      .. result.unsupported_receiver_limits .. " selected receiver limit overrides have no native effect.")
  end
end

-- The published experimental override is unavailable by default. Keeping its
-- require in this strict branch means disabled data stages never load or inspect it.
if values.unrestricted_modules == true then
  require("overrides.module_permissions").apply(data.raw, true)
end
