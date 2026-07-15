local owner = data.raw.technology and data.raw.technology["rocket-fuel-productivity"]
if owner then
  owner.effects = owner.effects or {}
  table.insert(owner.effects, {
    type = "change-recipe-productivity",
    recipe = "mir-fixture-prepatched-rocket-fuel",
    change = 0.1
  })
end
