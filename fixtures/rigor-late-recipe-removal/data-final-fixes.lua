local target = "item-microculture-vat-incineration"

if not data.raw.recipe[target] then
  error("MIR late-removal fixture setup failed: missing recipe " .. target)
end

for technology_name, technology in pairs(data.raw.technology or {}) do
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == target then
      error("MIR late-removal fixture failed: "
        .. technology_name
        .. " references sink recipe "
        .. target)
    end
  end
end

data.raw.recipe[target] = nil
