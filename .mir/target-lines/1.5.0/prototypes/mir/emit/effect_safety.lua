local data_raw = require("prototypes.mir.platform.factorio.data_raw")

local S = {}

local blocked_effect_types = {
  ["character-item-pickup-distance"] = "item pickup reach can vacuum nearby belt items into player inventories and cause severe lag",
  ["character-loot-pickup-distance"] = "loot pickup reach can vacuum nearby belt items into player inventories and cause severe lag"
}

local generated_technology_names = {}

function S.assert_effect_allowed(effect, context)
  local effect_type = effect and effect.type
  local reason = blocked_effect_types[effect_type]
  if reason then
    error("MIR safety guard blocked unsafe technology effect "
      .. effect_type
      .. " in "
      .. tostring(context or "unknown technology")
      .. ": "
      .. reason
      .. ".")
  end
end

function S.assert_effects_allowed(effects, context)
  for _, effect in ipairs(effects or {}) do
    S.assert_effect_allowed(effect, context)
  end
end

function S.register_generated_technology(name)
  if name then
    generated_technology_names[name] = true
  end
end

function S.contains_generated_technology(name)
  return generated_technology_names[name] == true
end

function S.sorted_generated_technology_names()
  local names = {}
  for name, _ in pairs(generated_technology_names) do table.insert(names, name) end
  table.sort(names)
  return names
end

function S.assert_registered_technology_effects()
  for name, _ in pairs(generated_technology_names) do
    local tech = data_raw.technology(name)
    if tech then
      S.assert_effects_allowed(tech.effects, name)
    end
  end
end

return S
