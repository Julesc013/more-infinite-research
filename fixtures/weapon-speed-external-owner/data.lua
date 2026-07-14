local source = data.raw.technology["weapon-shooting-speed-6"] or data.raw.technology["weapon-shooting-speed-5"]
if not source then
  error("MIR external weapon owner fixture could not find a vanilla weapon shooting speed technology.")
end

local owner = table.deepcopy(source)
owner.name = "mir-fixture-external-weapon-speed-owner"
owner.localised_name = "MIR fixture external weapon speed owner"
owner.localised_description = "Exact external replacement coverage used by MIR validation."
owner.prerequisites = {"rocketry", "tank"}
owner.effects = {
  {type = "gun-speed", ammo_category = "rocket", modifier = 0.1},
  {type = "gun-speed", ammo_category = "cannon-shell", modifier = 0.1}
}
owner.unit = table.deepcopy(source.unit)
owner.unit.count = nil
owner.unit.count_formula = "1000 * 2^(L-1)"
owner.max_level = "infinite"
owner.level = 1
owner.upgrade = true
owner.hidden = true

local science_pack_type = data.raw.tool and data.raw.tool["automation-science-pack"] and "tool" or "item"
local unreachable_pack = {
  type = science_pack_type,
  name = "mir-fixture-unreachable-weapon-science-pack",
  icon = "__base__/graphics/icons/automation-science-pack.png",
  icon_size = 64,
  subgroup = "science-pack",
  order = "z[mir-fixture-unreachable-weapon-science-pack]",
  stack_size = 200
}
if science_pack_type == "tool" then
  unreachable_pack.durability = 1
  unreachable_pack.durability_description_key = "description.science-pack-remaining-amount-key"
  unreachable_pack.factoriopedia_durability_description_key = "description.factoriopedia-science-pack-remaining-amount-key"
  unreachable_pack.durability_description_value = "description.science-pack-remaining-amount-value"
end

local unreachable_recipe = {
  type = "recipe",
  name = unreachable_pack.name,
  enabled = false,
  ingredients = {{type = "item", name = "iron-plate", amount = 1}},
  results = {{type = "item", name = unreachable_pack.name, amount = 1}}
}

local unreachable_owner = table.deepcopy(owner)
unreachable_owner.name = "mir-fixture-unreachable-weapon-speed-owner"
unreachable_owner.unit.ingredients = {{unreachable_pack.name, 1}}

local external_continuation = table.deepcopy(owner)
external_continuation.name = "weapon-shooting-speed-99"
external_continuation.localised_name = "MIR fixture external numbered weapon speed continuation"

data:extend({owner, unreachable_pack, unreachable_recipe, unreachable_owner, external_continuation})

for _, lab in pairs(data.raw.lab or {}) do
  lab.inputs = lab.inputs or {}
  table.insert(lab.inputs, unreachable_pack.name)
end
