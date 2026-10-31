-- Fixture-owned, acyclic probes. MIR's normal data-final stage changes these
-- deliberately narrow native definitions; this file does not import MIR code.
local prefix = "mir5-override-"
local ordinary = table.deepcopy(assert(data.raw.recipe["iron-gear-wheel"], "base gear recipe is absent"))
ordinary.name = prefix .. "ordinary"
ordinary.enabled = true
ordinary.ingredients = {{type="item", name="iron-plate", amount=2}}
ordinary.results = {{type="item", name="iron-gear-wheel", amount=1}}
ordinary.energy_required = 0.5
ordinary.maximum_productivity = 3
ordinary.allow_speed = false
ordinary.allow_productivity = false
ordinary.allow_consumption = false
ordinary.allow_pollution = false
ordinary.allow_quality = false
ordinary.allowed_module_categories = {"speed"}

local recycled = {
  type="recipe", name=prefix .. "recycling", categories={"recycling"}, enabled=true,
  hidden=true, unlock_results=false, maximum_productivity=0.5,
  ingredients={{type="item", name="iron-plate", amount=1}},
  results={{type="item", name="iron-plate", amount=1, probability=0.25}}
}

local parameter = table.deepcopy(assert(data.raw.recipe["parameter-0"], "base parameter recipe is absent"))
parameter.name = prefix .. "parameter"
parameter.allow_speed = false
parameter.allow_productivity = false
parameter.allow_consumption = false
parameter.allow_pollution = false
parameter.allow_quality = false
parameter.allowed_module_categories = {"speed"}

local category = prefix .. "module-category"
local module = table.deepcopy(assert(data.raw.module["productivity-module-3"], "productivity module is absent"))
module.name = prefix .. "module"
module.category = category
module.limitation = nil
module.limitation_message_key = nil

local machine = table.deepcopy(assert(data.raw["assembling-machine"] and data.raw["assembling-machine"]["assembling-machine-1"], "base assembler is absent"))
machine.name = prefix .. "assembler"
machine.module_slots = 2
machine.crafting_speed = 1
machine.energy_usage = "0kW"
machine.allowed_effects = {"speed"}
machine.allowed_module_categories = {"speed"}
machine.effect_receiver = {base_effect={speed=0}, uses_module_effects=true, uses_beacon_effects=true, uses_surface_effects=true}

local pipeline = table.deepcopy(assert(data.raw["assembling-machine"] and data.raw["assembling-machine"]["chemical-plant"], "base chemical plant is absent"))
pipeline.name = prefix .. "pipeline"
local boxes = assert(pipeline.fluid_boxes, "base chemical plant fluid boxes are absent")
assert(#boxes >= 2, "base chemical plant needs implicit and explicit pipeline boxes")
for index, box in ipairs(boxes) do
  if index == 1 then box.max_pipeline_extent = nil
  else box.max_pipeline_extent = 320 end
end

-- This is the fixture's only global pipeline input.  Keep every other utility
-- constant native, so the post-MIR witness can distinguish inherited extent
-- from the explicit 320 fields above without adding non-prototype markers.
local utility = assert(data.raw["utility-constants"] and data.raw["utility-constants"].default,
  "base utility constants are absent")
utility.default_pipeline_extent = 640

data:extend({
  {type="module-category", name=category}, module, ordinary, recycled, parameter, machine, pipeline
})
