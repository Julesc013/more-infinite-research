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
local modern, modern_selection, native_owner_patches, withheld_native_owners
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
  if modern_selection.bob_angel or modern_selection.bob_angel_f200_combined then
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
  native_owner_patches, withheld_native_owners = modern.preflight_native_owner_patches(modern_selection, data.raw, values)
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
  if modern_selection and modern_selection.bob_angel_f200_combined then
    bindings = require("compatibility.modern_catalogue.bob_angel_f200_combined").scripted_effect_bindings()
  end
  local scripted = require("research.scripted_effects").technologies(values, bindings)
  for index = 1, #scripted do technologies[#technologies + 1] = scripted[index] end
end

-- Retain broad product targeting in one relevant recipe pass. This extends
-- detached authored effects without discovering families or inspecting
-- foreign research. Existing named routes and weights retain precedence.
local native_owner_targets = modern and modern.native_owner_product_targets(
  modern_selection, data.raw, values, native_owner_patches, mods, withheld_native_owners)
local native_fallbacks, native_fallback_owners = {}, {}
if modern then
  for _, fallback in ipairs(modern_catalogue.native_owner_fallbacks(mods, withheld_native_owners)) do
    local technology = modern.technology(fallback.definition, values)
    native_fallbacks[#native_fallbacks + 1] = technology
    native_fallback_owners[technology] = fallback.owner
  end
end
local native_credit_targets, native_credit_ids = {}, {}
if modern and (prerequisite_target.id == "f200" or prerequisite_target.id == "f210") then
  for _, binding in ipairs(require("compatibility.product_bindings").native_owner_bindings) do
    native_credit_ids["recipe-prod-" .. binding.family .. "-1"] = binding.family
  end
  for _, technology in ipairs(technologies) do
    local family = native_credit_ids[technology.name]
    if family then native_credit_targets[family] = {} end
  end
end
require("research.product_target_extension").extend(technologies, values, {raw=data.raw, mods=mods, log=log,
  native_owner_targets=native_owner_targets,
  native_owner_fallbacks=native_fallbacks,
  native_credit_targets=native_credit_targets,
  required_product_targets=modern_selection and modern_selection.required_product_targets,
  additional_product_bindings=modern_selection and modern_selection.additional_product_bindings,
  exact_product_bindings=modern_selection and modern_selection.exact_product_bindings,
  exact_product_target_families=modern_selection and modern_selection.exact_product_target_families,
  replacement_product_target_families=modern_selection and modern_selection.replacement_product_target_families,
  excluded_product_target_recipes=modern_selection and modern_selection.excluded_product_target_recipes})
if modern then modern.preflight_collected_native_owner_targets(native_owner_targets, native_owner_patches) end
for _, fallback in ipairs(native_fallbacks) do
  if #fallback.effects > 0 then
    -- Replace this same identity's detached private holder with the public
    -- uncovered route. Runtime credits preserve its prior per-recipe mask.
    local replaced = false
    for index, technology in ipairs(technologies) do
      if technology.name == fallback.name and technology.hidden == true then
        technologies[index], replaced = fallback, true
        break
      end
    end
    if not replaced then technologies[#technologies + 1] = fallback end
    withheld_native_owners[native_fallback_owners[fallback]].generated = true
  end
end
-- Preserve the finite canonical SIF routes alongside all current matches,
-- including recipes now earned through a native owner. Absence from today's
-- public vector must not erase an already-earned signed credit route.
if next(native_credit_targets) ~= nil then
  for family, recipes in pairs(require("research.native_credit_definitions").published_sif_paid_recipe_sets()) do
    local targets = native_credit_targets[family]
    if targets then
      for recipe in pairs(recipes) do
        if data.raw.recipe[recipe] then targets[recipe] = values.streams[family].effect_percent / 100 end
      end
    end
  end
  for _, technology in ipairs(technologies) do
    local targets = native_credit_targets[native_credit_ids[technology.name]]
    if targets then
      for _, effect in ipairs(technology.effects or {}) do
        if effect.type == "change-recipe-productivity" and data.raw.recipe[effect.recipe] then
          targets[effect.recipe] = effect.change
        end
      end
    end
  end
end
local native_credit_groups = {}
for family, targets in pairs(native_credit_targets) do
  local rows = {}
  for recipe, change in pairs(targets) do rows[#rows + 1] = {recipe=recipe, change=change} end
  table.sort(rows, function(left, right) return left.recipe < right.recipe end)
  native_credit_groups[family] = rows
end
local native_adoption_patch

if modern_selection and modern_selection.bob_angel_f200_combined then
  require("compatibility.modern_catalogue.bob_angel_f200_combined").apply_effect_order(technologies)
end

if modern_catalogue.is_k2so(mods) then
  local materials = require("compatibility.material_catalogue").technologies(values, data.raw, mods, settings and settings.startup)
  for index = 1, #materials do technologies[#technologies + 1] = materials[index] end
end

-- Only selected RIC/lead consumers request this index. Their constructors below
-- read recipes and return detached technologies; no recipe writes occur in this
-- window, so both can share one preparation without a module-global cache.
local material_return_context
local function selected_material_return_context()
  if material_return_context == nil then
    material_return_context = require("compatibility.material_returns").prepare(data.raw)
  end
  return material_return_context
end

if prerequisite_target.id == "f210" and type(mods) == "table" and mods["real-industrial-chemistry"] then
  local ric_mode = settings and settings.startup and settings.startup["ric-world-mode"]
  if not ric_mode or ric_mode.value ~= "continental" then
    local ric = require("integrations.ric.research").technologies(
      values, data.raw, mods, settings and settings.startup, selected_material_return_context)
    for index = 1, #ric do technologies[#technologies + 1] = ric[index] end
  end
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
  local materials = require("compatibility.bob_core_materials").technologies(
    values, data.raw, mods, selected_material_return_context)
  for index = 1, #materials do technologies[#technologies + 1] = materials[index] end
end

if modern_selection and modern_selection.bob_plates_profile then
  local materials = require("compatibility.bob_plates_materials").technologies(
    values, data.raw, mods, selected_material_return_context)
  for index = 1, #materials do technologies[#technologies + 1] = materials[index] end
end

-- One lab/science view serves this complete owned catalogue. Native owners
-- and foreign research are outside this detached publication boundary.
local science = require("research.science")
local science_environment = {
  options=values.options, raw=data.raw, target=require("platform.target"), mods=mods, log=log,
}
local science_context = science.prepare(science_environment)
local electric_full
if modern_selection then electric_full = modern.retain_external_weapon_coverage(modern_selection, technologies, science_context) end
local science_family_bindings
local worker_storage = modern_selection and modern_selection.worker_storage
local worker_default_authored, worker_default_available, worker_default_is_head
if worker_storage and worker_storage.owned then
  local binding = require("compatibility.science_bindings").conditions_for("worker-robots-storage")
  binding.inherit_worker_storage_prerequisites = not modern_catalogue.has_secretas(mods)
  science_family_bindings = {[worker_storage.technology]=binding}
end
if prerequisite_target.id == "f200" or prerequisite_target.id == "f210" then
  -- This stable private identity is built from MIR's authored Base/Space Age
  -- default4, independently of a currently selected foreign finite route.
  local recovery = require("research.worker_storage_recovery")
  local baseline_mods = mods["space-age"] and {["space-age"]=mods["space-age"]} or {}
  local definition
  for _, row in ipairs(modern_catalogue.continuations(baseline_mods, nil)) do
    if row.id == recovery.canonical then definition = row; break end
  end
  assert(definition, "MIR worker recovery default declaration is absent")
  local recovery_values = values
  local missing_stream = values.streams["worker-robots-storage"] == nil
  if missing_stream then
    recovery_values = {}
    for key, value in pairs(values) do recovery_values[key] = value end
    recovery_values.streams = {}
    for key, value in pairs(values.streams) do recovery_values.streams[key] = value end
    recovery_values.streams["worker-robots-storage"] = definition.defaults
  end
  local authored = require("research.modern").continuation(definition, recovery_values)
  -- Capture the full MIR work contract before constructing or adapting any
  -- split identities. The foreign finite provider is never its producer.
  assert(recovery.matches_default(authored, authored), "MIR worker authored default contract is invalid")
  local default_emitted = false
  for _, row in ipairs(technologies) do
    if row.name == recovery.canonical then default_emitted = recovery.matches_default(row, authored); break end
  end
  local finite_available = worker_storage and worker_storage.finite and #worker_storage.finite > 0
  if finite_available then
    -- Only the finite route's available authored default inputs may support
    -- old default work. No foreign unit/effect is a source for this holder.
    for _, name in ipairs(authored.prerequisites) do
      if not data.raw.technology[name] then finite_available = false; break end
    end
    for _, ingredient in ipairs(authored.unit.ingredients) do
      -- Factorio2.0 science packs are tools; Factorio2.1 uses ordinary items.
      local name = ingredient[1]
      if not ((data.raw.tool and data.raw.tool[name]) or (data.raw.item and data.raw.item[name])) then
        finite_available = false; break
      end
    end
  end
  -- A same-name SE/overhaul row can have a different work contract; settings
  -- identity or its mere emission does not establish an available default4.
  local unavailable = missing_stream or not default_emitted and not finite_available
  worker_default_authored, worker_default_available = authored, not unavailable
  worker_default_is_head = not unavailable and default_emitted
  local row = unavailable and recovery.uninvested(authored, gear.unit.ingredients[1][1]) or recovery.prototype(authored)
  technologies[#technologies + 1] = row
  if not unavailable then
    science_family_bindings = science_family_bindings or {}
    science_family_bindings[recovery.id] = require("compatibility.science_bindings").conditions_for("worker-robots-storage")
  end
end
science.apply_family(technologies, science_family_bindings, science_environment, science_context)
if worker_default_available then
  local recovery = require("research.worker_storage_recovery")
  -- The detached default follows the same science policy as the legacy
  -- holder. Construct the bookkeeping gate afterwards: it must not acquire
  -- end-game science, price or prerequisite policy of its own.
  science.apply_family({worker_default_authored}, {[recovery.canonical]=
    require("compatibility.science_bindings").conditions_for("worker-robots-storage")},
    science_environment, science_context)
  local tail = recovery.default_tail(worker_default_authored)
  if not worker_default_is_head then
    -- Current finite profiles retain the old contract without offering a
    -- second ordinary infinite route. Runtime retirement remains explicit.
    tail.hidden, tail.enabled, tail.visible_when_disabled = true, false, false
  end
  technologies[#technologies + 1] = tail
  technologies[#technologies + 1] = recovery.head_gate(worker_default_authored)
end
native_adoption_patch = modern and require("research.native_adoption").plan(
  data.raw, native_owner_targets, withheld_native_owners, native_credit_groups,
  modern_selection.worker_storage, worker_default_available)
if electric_full then
  for _, technology in ipairs(technologies) do
    if technology.name == electric_full.name then
      electric_full.unit = technology.unit
      for _, holder in ipairs(require("research.native_gun_credit_definitions").technologies(electric_full, technology)) do
        technologies[#technologies + 1] = holder
      end
      break
    end
  end
end
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
if modern and require("research.product_target_extension").retain_galore_carbon_owner(technologies) then
  if not native_adoption_patch then error("MIR Galore missing private admission facts", 0) end
  native_adoption_patch.galore_sulfur_retired = true
end
require("research.native_credit_definitions").append(technologies, data.raw, values, require("platform.target"), native_credit_groups)

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
  require("research.native_adoption").apply(native_adoption_patch)
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
