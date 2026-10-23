-- These fixture-owned probes exist before MIR's data-final-fixes stage. The
-- ordinary recipe and slot receiver begin deliberately narrow; the parameter
-- recipe must remain narrow because the published override skips it exactly.
local category_name = "mir5-module-permissions-fixture"
local ordinary_recipe_name = "mir5-module-permissions-recipe"
local parameter_recipe_name = "mir5-module-permissions-parameter-recipe"
local receiver_name = "mir5-module-permissions-receiver"
local module_name = "mir5-module-permissions-module"

local ordinary = table.deepcopy(assert(data.raw.recipe["iron-gear-wheel"], "base gear recipe is absent"))
ordinary.name = ordinary_recipe_name
ordinary.enabled = false
ordinary.energy_required = 3
ordinary.hide_from_player_crafting = true
ordinary.allow_speed = false
ordinary.allow_productivity = false
ordinary.allow_consumption = false
ordinary.allow_pollution = false
ordinary.allow_quality = false
ordinary.allowed_module_categories = {"speed"}

local parameter = table.deepcopy(assert(data.raw.recipe["parameter-0"], "base parameter recipe is absent"))
parameter.name = parameter_recipe_name
parameter.allow_speed = false
parameter.allow_productivity = false
parameter.allow_consumption = false
parameter.allow_pollution = false
parameter.allow_quality = false
parameter.allowed_module_categories = {"speed"}

local receiver = table.deepcopy(assert(data.raw["assembling-machine"]
  and data.raw["assembling-machine"]["assembling-machine-1"], "base assembling machine is absent"))
receiver.name = receiver_name
receiver.module_slots = 2
receiver.crafting_speed = 0.5
receiver.energy_usage = "90kW"
receiver.allowed_effects = {"speed"}
receiver.allowed_module_categories = {"speed"}

local module = table.deepcopy(assert(data.raw.module and data.raw.module["speed-module"], "base speed module is absent"))
module.name = module_name
module.category = category_name

data:extend({
  {type = "module-category", name = category_name},
  module,
  ordinary,
  parameter,
  receiver
})
