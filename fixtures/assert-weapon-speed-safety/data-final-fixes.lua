local function has_gun_speed(tech, ammo_category)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "gun-speed" and effect.ammo_category == ammo_category then
      return true
    end
  end
  return false
end

local techs = data.raw.technology or {}

for _, tech_name in ipairs({"weapon-shooting-speed-5", "weapon-shooting-speed-6"}) do
  if not has_gun_speed(techs[tech_name], "cannon-shell") then
    error("MIR validation failed: finite vanilla " .. tech_name .. " lost cannon-shell shooting-speed.")
  end
end

local external = techs["weapon-shooting-speed-7"]
if not has_gun_speed(external, "cannon-shell") or not has_gun_speed(external, "rocket") then
  error("MIR validation failed: external numbered infinite weapon technology was mutated.")
end

local generated
for name, tech in pairs(techs) do
  if name ~= "weapon-shooting-speed-7"
    and string.match(name, "^weapon%-shooting%-speed%-%d+$")
    and tech.unit
    and tech.unit.count_formula
  then
    generated = tech
    break
  end
end

if not generated and not external then
  error("MIR validation failed: neither generated nor external weapon shooting speed continuation was found.")
end

if generated and (has_gun_speed(generated, "cannon-shell") or has_gun_speed(generated, "rocket")) then
  error("MIR validation failed: generated weapon shooting speed continuation still contains rocket or cannon-shell overlap effects.")
end
