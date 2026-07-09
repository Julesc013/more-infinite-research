local denied_recipes = {
  ["mir-self-loop-filter-cleaning"] = true,
  ["mir-barrel-return-loop"] = true,
  ["mir-voiding-sink"] = true,
  ["mir-matter-transmutation"] = true,
  ["mir-zero-cap-productivity"] = true,
  ["mir-hidden-internal-recipe"] = true,
  ["mir-loader-like-container"] = true,
  ["mir-drill-like-container"] = true
}

for tech_name, tech in pairs(data.raw.technology or {}) do
  for _, effect in ipairs(tech.effects or {}) do
    if effect.type == "change-recipe-productivity" and denied_recipes[effect.recipe] then
      error("MIR negative capability validation failed: " .. effect.recipe .. " received productivity from " .. tech_name .. ".")
    end
  end
end
