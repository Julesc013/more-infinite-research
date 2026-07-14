local owner = data.raw.technology and data.raw.technology["processing-unit-productivity"]
if not owner then error("MIR native-owner source fixture requires processing-unit-productivity") end
owner.effects = owner.effects or {}
table.insert(owner.effects, {
  type = "ammo-damage",
  ammo_category = "bullet",
  modifier = 0.07
})
