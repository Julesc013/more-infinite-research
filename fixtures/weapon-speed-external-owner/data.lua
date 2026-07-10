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

data:extend({owner})
