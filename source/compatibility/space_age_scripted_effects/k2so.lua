-- Exact published K2SO rows from the authenticated 4.7.21000 F210 capture.
-- Agriculture keeps the Space Age list; spoilage deliberately begins at the
-- production pack and must not regain the omitted early packs.
local M = {}

local item_types = {
  "tool", "item", "ammo", "capsule", "gun", "armor", "module", "repair-tool",
  "mining-tool", "item-with-entity-data", "item-with-inventory", "item-with-label",
  "item-with-tags", "selection-tool", "copy-paste-tool", "blueprint", "blueprint-book",
  "deconstruction-item", "upgrade-item", "spidertron-remote", "rail-planner",
  "space-platform-starter-pack"
}

local function require_item(raw, name)
  for _, kind in ipairs(item_types) do
    if raw[kind] and raw[kind][name] then return end
  end
  error("MIR K2SO scripted-effect binding is missing item " .. name, 3)
end

local function require_technology(raw, name)
  if raw.technology and raw.technology[name] then return end
  error("MIR K2SO scripted-effect binding is missing technology " .. name, 3)
end

function M.select(raw)
  if type(raw) ~= "table" then error("MIR K2SO scripted-effect binding needs data.raw", 2) end
  local names = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "space-science-pack", "agricultural-science-pack",
    "electromagnetic-science-pack", "cryogenic-science-pack"
  }
  require_item(raw, "spoilage")
  for _, name in ipairs(names) do require_item(raw, name); require_technology(raw, name) end
  return {
    agriculture = {
      prerequisites = {
        "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
        "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
        "cryogenic-science-pack"
      },
      ingredients = {
        {"automation-science-pack", 1}, {"logistic-science-pack", 1},
        {"chemical-science-pack", 1}, {"production-science-pack", 1},
        {"agricultural-science-pack", 1}, {"electromagnetic-science-pack", 1},
        {"cryogenic-science-pack", 1}
      }
    },
    spoilage = {
      prerequisites = {
        "production-science-pack", "space-science-pack", "agricultural-science-pack",
        "cryogenic-science-pack"
      },
      ingredients = {
        {"production-science-pack", 1}, {"space-science-pack", 1},
        {"agricultural-science-pack", 1}, {"cryogenic-science-pack", 1}
      }
    }
  }
end

return M
