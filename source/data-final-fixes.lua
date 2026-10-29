-- Preserve the two delivered exact-version loader repairs independently of
-- research construction. Inactive profiles never import the override body.
if type(mods) == "table" and type(mods.base) == "string" and mods.base:match("^2%.1%.")
    and (mods["atan-ash"] == "2.2.1" or mods["atan-nuclear-science"] == "0.3.3") then
  require("overrides.recipe_schema").apply(data.raw, mods, log)
end

-- Published named prerequisite repairs are independent of research selection.
-- Only F200/F210 with relevant optional inputs import their scoped bodies.
local prerequisite_target = require("platform.target")
if type(mods) == "table" and (prerequisite_target.id == "f200" or prerequisite_target.id == "f210")
    and ((type(mods.angelssmelting) == "string" and mods.angelssmelting ~= "")
      or (type(mods.astroponics) == "string" and mods.astroponics ~= ""
        and type(mods["planet-muluna"]) == "string" and mods["planet-muluna"] ~= "")) then
  require("overrides.prerequisite_repairs").apply(data.raw, mods, prerequisite_target, log)
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

-- K2 without Spaced Out has captured F200 Base and F210 Base/Space Age inputs.
-- Named native fields are preflighted here; those source facts do not qualify
-- a new MIR5 package. This route never imports the K2SO profile body.
local ordinary_profile = type(mods) == "table" and mods.Krastorio2 == nil
  and mods["Krastorio2-spaced-out"] == nil
local modern_catalogue = require("compatibility.modern_catalogue")
local modern, modern_selection, native_owner_patches
if ordinary_profile or modern_catalogue.is_k2_base(mods) or modern_catalogue.is_k2so(mods) then
  modern = require("research.modern")
  modern_selection = modern_catalogue.select(mods, data.raw)
  if modern_selection.bob_native_continuations then
    require("compatibility.bob_native_continuations").preflight(data.raw)
  end
  if mods["atan-air-scrubbing"] or mods["atan-ash"] then
    local definitions = require("compatibility.atan_productivity").select(mods, data.raw)
    for _, definition in ipairs(definitions) do
      modern_selection.definitions[#modern_selection.definitions + 1] = definition
    end
  end
  if modern_selection.bob_angel then
    gear.unit.ingredients = modern_catalogue.science_ingredients("science_automation_logistic")
    gear.prerequisites = modern_catalogue.science_names("science_automation_logistic")
  end
  if modern_selection.py_hightech then
    require("compatibility.modern_catalogue.py").preflight(data.raw)
  end
  if modern_selection.bob_warfare then
    require("compatibility.modern_catalogue.bob_warfare").preflight(data.raw, mods)
  end
  if modern_selection.bob_productivity then
    require("compatibility.bob_productivity").preflight(data.raw, mods)
  end
  if modern_selection.ironclad then
    require("compatibility.ironclad").preflight(data.raw)
  end
  if modern_selection.py_coal or modern_selection.py_hightech or modern_selection.bob_warfare then
    require("compatibility.native_modded_continuations").preflight(mods, data.raw)
  end
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
require("research.product_target_extension").extend(technologies, values, {raw=data.raw, mods=mods, log=log,
  required_product_targets=modern_selection and modern_selection.required_product_targets,
  additional_product_bindings=modern_selection and modern_selection.additional_product_bindings,
  exact_product_bindings=modern_selection and modern_selection.exact_product_bindings,
  exact_product_target_families=modern_selection and modern_selection.exact_product_target_families,
  replacement_product_target_families=modern_selection and modern_selection.replacement_product_target_families,
  excluded_product_target_recipes=modern_selection and modern_selection.excluded_product_target_recipes})

if modern_catalogue.is_k2so(mods) then
  local materials = require("compatibility.material_catalogue").technologies(values, data.raw, mods)
  for index = 1, #materials do technologies[#technologies + 1] = materials[index] end
end

if modern_selection and modern_selection.bob_angel then
  local materials = require("compatibility.bob_angel_materials").technologies(values, data.raw, mods)
  for index = 1, #materials do technologies[#technologies + 1] = materials[index] end
end

if modern_selection and modern_selection.py_coal then
  local materials = require("compatibility.py_materials").technologies(values, data.raw, mods)
  for index = 1, #materials do technologies[#technologies + 1] = materials[index] end
end

-- The exact F210 BobTech plus Angel Smelting tuple has five separately
-- captured material rows.  It deliberately stays outside the F200
-- no-BobTech material selector and does not reconstruct other Bob/Angel
-- routes from the installed prototype world.
if modern_selection and modern_selection.bob_tech_materials then
  local materials = require("compatibility.bob_tech_materials").technologies(values, data.raw, mods)
  for index = 1, #materials do technologies[#technologies + 1] = materials[index] end
end

-- The independent F210 Bob Core capture has no Angel modules.  Its seven
-- named routes are separate from the BobTech-plus-Angel material adapter;
-- neither profile derives routes from the other.
if require("compatibility.bob_core_profile").applies(mods) then
  local materials = require("compatibility.bob_core_materials").technologies(values, data.raw, mods)
  for index = 1, #materials do technologies[#technologies + 1] = materials[index] end
end

if modern_selection and modern_selection.bob_plates_profile then
  local materials = require("compatibility.bob_plates_materials").technologies(values, data.raw, mods)
  for index = 1, #materials do technologies[#technologies + 1] = materials[index] end
end

-- One lab/science view serves this complete owned catalogue. Native owners
-- and foreign research are outside this detached publication boundary.
require("research.science").apply_family(technologies, nil, {
  options=values.options, raw=data.raw, target=require("platform.target"), mods=mods, log=log,
})
if require("platform.target").id == "f200" and type(mods) == "table"
    and (mods.ExpandedProductivityResearch or mods["plates-n-circuit-productivity"]
      or mods.Science_packs_productivity or mods["bioflux-productivity"] or mods["fish-productivity"]
      or mods["crafting-efficiency-2"] or mods.ProductivityResearch) then
  require("compatibility.competing_productivity").retain_foreign_coverage(
    technologies, data.raw, mods, require("platform.target"),
    values.options["mir-prefer-this-mod-for-competing-techs"])
end

-- Stable native credit holders preserve already-earned partial overlaps when
-- a provider or its ownership preference changes. They are explicit authored
-- rows, independent of whether the provider is currently installed.
require("research.native_credit_definitions").append(technologies, data.raw, values, require("platform.target"))

-- Fixed native holders retain MIR1.1's already-earned extra module effects.
-- A removed optional recipe cannot make its hidden holder a startup failure.
if require("platform.target").recipe_productivity == true then
  local module_main_present = false
  for _, technology in ipairs(technologies) do
    if technology.name == "recipe-prod-research_modules-1" then module_main_present = true; break end
  end
  if module_main_present then
    for _, holder in ipairs(require("research.legacy_module_credit_definitions").technologies()) do
      if data.raw.recipe[holder.effects[1].recipe] ~= nil then
        technologies[#technologies + 1] = holder
      end
    end
  end
end

-- Published MIR 1.2 combined rocket/cannon levels retain their rocket effect
-- publicly.  Stage one explicit cannon-only holder beside that already-built
-- row so runtime can preserve earned levels without changing either public
-- stream or inspecting foreign prototypes.
require("research.legacy_cannon_credit_definitions").append(
  technologies, require("platform.target"), data.raw)

local function finite_effect_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function removable_missing_recipe_productivity_effect(effect)
  return type(effect) == "table" and effect.type == "change-recipe-productivity"
    and type(effect.recipe) == "string" and effect.recipe ~= ""
    and finite_effect_number(effect.change)
    and (effect.modifier == nil or finite_effect_number(effect.modifier))
    and data.raw.recipe[effect.recipe] == nil
end

-- A foreign data-updates stage may remove an authored recipe while retaining
-- its product through other producers. Keep the collected replacement effects
-- and compact only missing targets out of our detached emission. This visits
-- the finite owned effect vectors, never foreign technologies or recipe trees.
for _, technology in ipairs(technologies) do
  local effects, retained = technology.effects or {}, 0
  local count = #effects
  for index = 1, count do
    local effect = effects[index]
    if not removable_missing_recipe_productivity_effect(effect) then
      retained = retained + 1
      if retained ~= index then effects[retained] = effect end
    elseif values.options["mir-debug-recipe-matches"] == true and type(log) == "function" then
      log("[more-infinite-research] withheld missing recipe target family=" .. technology.name .. " recipe=" .. effect.recipe)
    end
  end
  for index = count, retained + 1, -1 do effects[index] = nil end
  -- Preserve historical identities and leave existing empty carriers as authored.
  if count > 0 and retained == 0 then technology.enabled = false end
end

generator.install(technologies, data)
if modern then
  modern.apply_native_owner_patches(native_owner_patches)
  modern.apply_recipe_patches(modern_selection, data.raw)
end

-- These independent prototype limits are opt-in. Test effective post-import
-- values before importing their body, so the normal data stage does not build
-- its recipe classifier or inspect unrelated prototype groups.
local pipeline_extent = values.options["mir-pipeline-extent-multiplier"]
if pipeline_extent ~= nil and pipeline_extent ~= "100" and pipeline_extent ~= 100 then
  require("overrides.pipeline_extent").apply(data.raw, pipeline_extent)
end

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
