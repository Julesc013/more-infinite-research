local M = {}
local deepcopy = require("prototypes.mir.core.deepcopy")
local descriptor = require("prototypes.mir.domain.streams.descriptor")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local initial_crafting_machine = {
  name = "assembling-machine-1", category = "crafting", ingredient_count = 2, unlocker = "automation",
  capability_machine = {name = "assembling-machine-2", category = "crafting", ingredient_count = 4, unlocker = "automation-2"},
  early_unlockers = {"automation", "electronics"}
}

M.shared = {
  per_level_default = 0.10,
  base_cost = 8000,
  growth_factor = 2,
  research_time = 60,
  science_binding_policy = {
    -- Parameterized sources prefer the named recipe, with finite direct
    -- alternatives and unique unlock owners; they never explore factories.
    named_pack_recipe = true,
    unique_direct_recipe = true,
    unique_direct_unlock = true,
    -- DMR Reborn's specialist lab consumes this mined tool directly. Validate
    -- its actual resource instead of searching for a nonexistent recipe.
    resource_pack_sources = { ["dmrsa-tenemut"] = "dmrsa-tenemut" },
    -- Preserve the published launch-source admission contract. Correcting
    -- that historical policy is a separate semantic/migration change.
    retained_launch_source = {pack = "space-science-pack", payload = "satellite"},
    -- Factorio 0.15/0.16 approved pack recipes have published prerequisite
    -- frontier that is not represented by their direct recipe unlock alone.
    -- These are negative-safe, target-specific declarations: every row must
    -- match the actual recipe, direct unlocker, category and item inputs
    -- before its progression gates are used. They do not discover factories
    -- or prove acquisition.
    retained_progression_prerequisites = {
      ["0.15"] = {
        ["high-tech-science-pack"] = {
          recipe = "high-tech-science-pack",
          unlocker = "advanced-electronics-2",
          categories = {"crafting"},
          ingredients = {"battery", "copper-cable", "processing-unit", "speed-module"},
          initial_machine = initial_crafting_machine,
          prerequisites = {"automation-2", "battery", "speed-module"}
        },
        ["production-science-pack"] = {
          recipe = "production-science-pack",
          unlocker = "advanced-material-processing-2",
          categories = {"crafting"},
          ingredients = {"assembling-machine-1", "electric-engine-unit", "electric-furnace"},
          prerequisites = {"electric-engine", "engine"}
        },
        ["military-science-pack"] = {
          recipe = "military-science-pack",
          unlocker = "military-2",
          categories = {"crafting"},
          ingredients = {"grenade", "gun-turret", "piercing-rounds-magazine"},
          prerequisites = {"turrets"}
        }
      },
      ["0.16"] = {
        ["high-tech-science-pack"] = {
          recipe = "high-tech-science-pack",
          unlocker = "advanced-electronics-2",
          categories = {"crafting"},
          ingredients = {"battery", "copper-cable", "processing-unit", "speed-module"},
          initial_machine = initial_crafting_machine,
          prerequisites = {"automation-2", "battery", "speed-module"}
        },
        ["production-science-pack"] = {
          recipe = "production-science-pack",
          unlocker = "advanced-material-processing-2",
          categories = {"crafting"},
          ingredients = {"electric-engine-unit", "electric-furnace"},
          prerequisites = {"electric-engine", "engine"}
        },
        ["military-science-pack"] = {
          recipe = "military-science-pack",
          unlocker = "military-2",
          categories = {"crafting"},
          ingredients = {"grenade", "gun-turret", "piercing-rounds-magazine"},
          prerequisites = {"turrets"}
        },
        ["science-pack-3"] = {
          recipe = "science-pack-3",
          unlocker = "advanced-electronics",
          categories = {"crafting"},
          ingredients = {"advanced-circuit", "electric-mining-drill", "engine-unit"},
          prerequisites = {"engine"}
        }
      }
    }
  },
  -- Shared source declarations for the ordinary productivity-family science
  -- vector. These are authored progression bindings, not cached discoveries.
  -- The target adapter translates the roles to historical item spellings.
  science_bindings = {
    ["automation-science-pack"] = {
      recipe = "automation-science-pack", technology = "automation-science-pack", allow_initial = true
    },
    ["logistic-science-pack"] = {
      recipe = "logistic-science-pack", technology = "logistic-science-pack", allow_initial = true
    },
    ["chemical-science-pack"] = {
      recipe = "chemical-science-pack", technology = "chemical-science-pack", allow_initial = true
    },
    ["production-science-pack"] = {
      recipe = "production-science-pack", technology = "production-science-pack", allow_initial = true
    },
    ["promethium-science-pack"] = {
      recipe = "promethium-science-pack", technology = "promethium-science-pack", allow_initial = true
    },
    -- Angel's Biology token has several producers.  This is the reviewed
    -- early producer, with its explicit direct unlock owner; it is not a
    -- traversal-selected alternative or a material-acquisition proof.
    ["angels-token-bio"] = {
      recipe = "angels-temperate-garden-a", technology = "angels-gardens", allow_initial = true
    }
  }
}

local raw_streams = require("prototypes.streams.init")
require("prototypes.mir.compatibility.profiles").apply({ streams = raw_streams })

local canonical_streams = {}
for key, raw_spec in pairs(raw_streams) do
  local spec = descriptor.normalize(key, raw_spec)
  if target_line.stream_supported(key, spec) then canonical_streams[key] = spec end
end

function M.snapshot()
  return deepcopy(canonical_streams)
end

-- Internal planning boundary for source-owned normalized stream policy.
-- Callers must treat the returned catalog as immutable; snapshot() and get()
-- remain the defensive-copy surfaces for independently owned values.
function M.view()
  return canonical_streams
end

function M.get(key)
  local spec = canonical_streams[key]
  return spec and deepcopy(spec) or nil
end

function M.sorted_keys()
  local keys = {}
  for key, _ in pairs(canonical_streams) do table.insert(keys, key) end
  table.sort(keys)
  return keys
end

return M
