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

-- This is intentionally numbered before MIR's compilation runs.  A name that
-- resembles a base continuation is not MIR authority: the generated registry
-- must prove that MIR created the base extension before it can be replaced.
local numbered_continuation = table.deepcopy(owner)
numbered_continuation.name = "weapon-shooting-speed-99"
numbered_continuation.localised_name = "MIR fixture external weapon speed continuation"
numbered_continuation.localised_description =
  "Pre-compilation external numbered continuation; MIR must preserve its exact owners."
numbered_continuation.level = 99

-- These deliberately non-qualifying native-owner sightings exercise the
-- NATIVE-01 / STACK-02 diagnostics. They must remain visible as raw sightings
-- without becoming confidence, coverage, or duplicate-owner authority.
local finite_native_owner = table.deepcopy(owner)
finite_native_owner.name = "mir-fixture-finite-belt-stack-owner"
finite_native_owner.effects = {{type = "belt-stack-size-bonus", modifier = 1}}
finite_native_owner.max_level = 1
finite_native_owner.level = 1

local disabled_native_owner = table.deepcopy(owner)
disabled_native_owner.name = "mir-fixture-disabled-inserter-stack-owner"
disabled_native_owner.effects = {{type = "inserter-stack-size-bonus", modifier = 1}}
disabled_native_owner.enabled = false

local zero_native_owner = table.deepcopy(owner)
zero_native_owner.name = "mir-fixture-zero-stack-inserter-owner"
zero_native_owner.effects = {{type = "stack-inserter-capacity-bonus", modifier = 0}}

data:extend({
  owner, numbered_continuation, unreachable_pack, unreachable_recipe, unreachable_owner,
  finite_native_owner, disabled_native_owner, zero_native_owner
})

for _, lab in pairs(data.raw.lab or {}) do
  lab.inputs = lab.inputs or {}
  table.insert(lab.inputs, unreachable_pack.name)
end
