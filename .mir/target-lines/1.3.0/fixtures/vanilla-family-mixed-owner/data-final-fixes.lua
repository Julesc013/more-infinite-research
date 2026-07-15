local owner = data.raw.technology and data.raw.technology["rocket-fuel-productivity"]
if owner and owner.effects and owner.effects[1] and owner.effects[2] then
  owner.effects[1].change = 0.1
  owner.effects[2].change = 0.2
end
