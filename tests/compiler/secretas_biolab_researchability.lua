-- Controlled Secretas-shaped regression. This is intentionally a compact
-- prototype graph, not a native Secretas/Frozeta campaign: it retains the
-- concrete Biolab biter-egg acquisition path, the two level-eight science
-- packs, their real recipe categories/surface requirements, and real MIR science,
-- acquisition, researchability and continuation-planning services.
_G.log = function() end
-- The fixture models Secretas' emitted prototypes directly. It does not claim
-- that a partial fixture authorizes the wider Secretas compatibility pack.
_G.mods = {base = "2.1.21", ["space-age"] = "2.1.21"}
_G.settings = {startup = {
  ["mir-science-pack-ingredient-policy"] = {value = "configured"}
}}
_G.feature_flags = {scripted_techs = true}

local assertions = 0
local function check(condition, detail)
  assert(condition, detail)
  assertions = assertions + 1
  print("OBSERVED\t" .. detail)
end

local function includes(rows, name)
  for _, row in ipairs(rows or {}) do
    if row == name or type(row) == "table" and (row.name or row[1]) == name then return true end
  end
  return false
end

local function item(name, place_result)
  return {type = "item", name = name, place_result = place_result}
end

local function recipe(name, result, options)
  options = options or {}
  return {
    type = "recipe", name = name, enabled = options.enabled ~= false,
    category = options.category,
    ingredients = options.ingredients or {},
    results = options.results or {{type = "item", name = result, amount = 1}},
    energy_required = options.energy_required or 1,
    surface_conditions = options.surface_conditions
  }
end

local function technology(name, options)
  options = options or {}
  return {
    type = "technology", name = name, enabled = true,
    prerequisites = options.prerequisites or {}, effects = options.effects or {},
    research_trigger = options.research_trigger,
    unit = options.unit
  }
end

local base_packs = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "military-science-pack", "production-science-pack", "utility-science-pack",
  "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
  "electromagnetic-science-pack", "cryogenic-science-pack"
}

local function unit(packs)
  local ingredients = {}
  for _, name in ipairs(packs) do ingredients[#ingredients + 1] = {name, 1} end
  return {count = 1000, time = 60, ingredients = ingredients}
end

local function upstream_worker(level, previous, packs)
  return technology("worker-robots-storage-" .. level, {
    prerequisites = previous and {previous} or {},
    unit = unit(packs),
    effects = {{type = "worker-robot-storage", modifier = 1}}
  })
end

local function world(include_pressure_default)
  local raw = {
    item = {}, fluid = {steam = {type = "fluid", name = "steam", default_temperature = 165}},
    recipe = {}, technology = {}, lab = {}, character = {
      player = {type = "character", name = "player", crafting_categories = {"crafting"}}
    },
    ["assembling-machine"] = {}, surface = {
      ["space-platform"] = {type = "surface", name = "space-platform", surface_properties = {gravity = 0, pressure = 0}}
    },
    planet = {
      nauvis = {type = "planet", name = "nauvis", surface_properties = {}},
      frozeta = {type = "planet", name = "frozeta", surface_properties = {pressure = 280}}
    }
  }
  if include_pressure_default then
    raw["surface-property"] = {pressure = {type = "surface-property", name = "pressure", default_value = 1000}}
  end

  -- The standard lab provides the earlier Biolab technology route. Biolab is
  -- the only lab in this graph that accepts the Secretas high-science pair.
  raw.item.lab = item("lab", "lab")
  raw.lab.lab = {type = "lab", name = "lab", inputs = base_packs}
  raw.recipe["make-lab"] = recipe("make-lab", "lab")
  raw.item.biolab = item("biolab", "biolab")
  raw.lab.biolab = {
    type = "lab", name = "biolab",
    inputs = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "military-science-pack", "production-science-pack", "utility-science-pack",
      "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
      "electromagnetic-science-pack", "cryogenic-science-pack", "golden-science-pack",
      "promethium-science-pack"
    },
    surface_conditions = {{property = "pressure", min = 1000, max = 1000}}
  }

  -- A normal acquired crafting machine supplies the actual special categories
  -- used by the two high-science recipes. Its placement item remains a real
  -- acquisition query, rather than a machine-category service stub.
  raw.item["science-assembler"] = item("science-assembler", "science-assembler")
  raw.recipe["make-science-assembler"] = recipe("make-science-assembler", "science-assembler")
  raw["assembling-machine"]["science-assembler"] = {
    type = "assembling-machine", name = "science-assembler",
    crafting_categories = {"crafting-with-fluid", "cryogenics"},
    fluid_boxes = {{production_type = "input"}, {production_type = "output"}}
  }

  -- Controlled, individually acquired ordinary pack routes provide the
  -- prerequisite research graph for Biolab and Promethium. Golden and
  -- Promethium themselves remain research-unlocked routes below.
  for _, name in ipairs(base_packs) do
    raw.item[name] = item(name)
    raw.recipe["make-" .. name] = recipe("make-" .. name, name)
  end
  for _, name in ipairs({"gold-plate", "steam-turbine", "solid-fuel", "arithmetic-combinator",
      "promethium-asteroid-chunk", "quantum-processor", "refined-concrete", "uranium-235"}) do
    raw.item[name] = item(name)
    raw.recipe["make-" .. name] = recipe("make-" .. name, name)
  end
  raw.recipe["make-steam"] = recipe("make-steam", nil, {
    category = "crafting-with-fluid", results = {{type = "fluid", name = "steam", amount = 1}}
  })

  -- Biter eggs are not a generic seed. The native fixed recipe belongs to a
  -- captive spawner, which MIR recognizes only through the direct
  -- rocket-ammo -> projectile -> capture-robot -> captured-spawner path. Its
  -- pressure-1000 placement condition is the minimal causal route to Biolab.
  raw.recipe["biter-egg"] = recipe("biter-egg", "biter-egg", {
    enabled = false, category = "captive-spawner-process", energy_required = 10
  })
  raw["assembling-machine"]["captive-biter-spawner"] = {
    type = "assembling-machine", name = "captive-biter-spawner",
    crafting_categories = {"captive-spawner-process"}, fixed_recipe = "biter-egg",
    surface_conditions = {{property = "pressure", min = 1000, max = 1000}}
  }
  raw["unit-spawner"] = {
    ["biter-spawner"] = {type = "unit-spawner", name = "biter-spawner", captured_spawner_entity = "captive-biter-spawner"}
  }
  raw.ammo = {
    ["capture-robot-rocket"] = {
      type = "ammo", name = "capture-robot-rocket", ammo_category = "rocket",
      ammo_type = {target_filter = {"biter-spawner"}, action = {type = "direct", action_delivery = {
        type = "projectile", projectile = "capture-robot-rocket"
      }}}
    }
  }
  raw.gun = {
    ["rocket-launcher"] = {type = "gun", name = "rocket-launcher", attack_parameters = {ammo_categories = {"rocket"}}}
  }
  raw.projectile = {
    ["capture-robot-rocket"] = {type = "projectile", name = "capture-robot-rocket", action = {type = "direct", action_delivery = {
      type = "instant", target_effects = {type = "create-entity", entity_name = "capture-robot"}
    }}}
  }
  raw["capture-robot"] = { ["capture-robot"] = {type = "capture-robot", name = "capture-robot", capture_speed = 1} }
  raw.item["rocket-launcher"] = item("rocket-launcher")
  raw.recipe["make-rocket-launcher"] = recipe("make-rocket-launcher", "rocket-launcher")
  raw.recipe["make-capture-robot-rocket"] = recipe("make-capture-robot-rocket", "capture-robot-rocket")

  raw.item["golden-science-pack"] = item("golden-science-pack")
  raw.recipe["golden-science-pack"] = recipe("golden-science-pack", "golden-science-pack", {
    enabled = false, category = "crafting-with-fluid",
    ingredients = {
      {type = "item", name = "gold-plate", amount = 14},
      {type = "item", name = "steam-turbine", amount = 2},
      {type = "item", name = "solid-fuel", amount = 7},
      {type = "item", name = "arithmetic-combinator", amount = 14},
      {type = "fluid", name = "steam", amount = 250}
    },
    surface_conditions = {{property = "pressure", min = 200, max = 280}}
  })
  raw.technology["golden-science-pack"] = technology("golden-science-pack", {
    research_trigger = {type = "craft-item", item = "gold-plate", count = 20},
    effects = {{type = "unlock-recipe", recipe = "golden-science-pack"}}
  })

  raw.item["promethium-science-pack"] = item("promethium-science-pack")
  raw.recipe["promethium-science-pack"] = recipe("promethium-science-pack", "promethium-science-pack", {
    enabled = false, category = "cryogenics",
    ingredients = {
      {type = "item", name = "promethium-asteroid-chunk", amount = 25},
      {type = "item", name = "quantum-processor", amount = 1},
      {type = "item", name = "biter-egg", amount = 10}
    },
    surface_conditions = {{property = "gravity", min = 0, max = 0}}
  })
  raw.technology["promethium-science-pack"] = technology("promethium-science-pack", {
    prerequisites = {"biter-egg-handling", "stellar-discovery-solar-system-edge"},
    unit = unit(base_packs),
    effects = {{type = "unlock-recipe", recipe = "promethium-science-pack"}}
  })

  -- These two trigger-predecessors stand for the engine-owned event gates.
  -- They keep the compact graph within MIR's actual trigger semantics.
  raw.technology["biter-egg-handling"] = technology("biter-egg-handling", {
    research_trigger = {type = "capture-spawner"},
    effects = {{type = "unlock-recipe", recipe = "biter-egg"}}
  })
  raw.technology["stellar-discovery-solar-system-edge"] = technology("stellar-discovery-solar-system-edge", {
    research_trigger = {type = "discover-space-location", space_location = "shattered-planet"}
  })
  for _, name in ipairs({"production-science-pack", "utility-science-pack", "uranium-processing"}) do
    raw.technology[name] = technology(name, {research_trigger = {type = "mine-entity", entity = "fixture"}})
  end

  -- These are the native Biolab recipe ingredients. They are each supplied by
  -- the small independent routes above; no item-acquisition service is faked.
  raw.recipe.biolab = recipe("biolab", "biolab", {
    enabled = false,
    ingredients = {
      {type = "item", name = "lab", amount = 1},
      {type = "item", name = "biter-egg", amount = 10},
      {type = "item", name = "refined-concrete", amount = 25},
      {type = "item", name = "capture-robot-rocket", amount = 2},
      {type = "item", name = "uranium-235", amount = 3}
    }
  })
  raw.technology.biolab = technology("biolab", {
    prerequisites = {"biter-egg-handling", "production-science-pack", "utility-science-pack", "uranium-processing"},
    unit = unit({
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "military-science-pack", "production-science-pack", "utility-science-pack",
      "space-science-pack", "agricultural-science-pack"
    }),
    effects = {{type = "unlock-recipe", recipe = "biolab"}}
  })

  for level = 1, 8 do
    raw.technology["worker-robots-storage-" .. level] = upstream_worker(
      level, level > 1 and "worker-robots-storage-" .. (level - 1) or nil,
      level == 8 and {"golden-science-pack", "promethium-science-pack"} or {"automation-science-pack"})
  end
  return raw
end

local context = require("prototypes.mir.pipeline.compiler_context")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")
local researchability = require("prototypes.mir.capabilities.science_integration.technology_researchability")
local plan = require("prototypes.mir.planner.base_continuations.plan")
local fingerprint = require("prototypes.mir.core.fingerprint")

local function run(raw, callback)
  _G.data = {raw = raw, extend = function() error("Unexpected prototype mutation") end}
  local owner = context.new()
  science.ensure_services(owner)
  owner:freeze_services()
  return context.with_active(owner, callback)
end

run(world(false), function()
  check(researchability.technology_researchability_reason("worker-robots-storage-8") == "no-accepting-lab",
    "Secretas level eight is rejected when Biolab's biter-egg route lacks inherited pressure")
end)

run(world(true), function()
  local before = fingerprint.of(data.raw)
  check(researchability.technology_researchability_reason("worker-robots-storage-8") == nil,
    "Secretas level eight becomes researchable through Biolab's acquired pressure-1000 biter-egg route")
  local operation
  for _, candidate in ipairs(plan.plan_all()) do
    if candidate.technology_name == "worker-robots-storage-9" then operation = candidate end
  end
  check(operation ~= nil and operation.base_technology_name == "worker-robots-storage-8"
      and includes(operation.technology.prerequisites, "worker-robots-storage-8"),
    "Real shared researchability admits a level-nine MIR continuation after Secretas finite level eight")
  check(includes(operation.technology.unit.ingredients, "golden-science-pack")
      and includes(operation.technology.unit.ingredients, "promethium-science-pack"),
    "The continuation preserves Secretas's high-science requirements")
  check(fingerprint.of(data.raw) == before,
    "Secretas-shaped researchability and planning preserve observed prototypes")
end)

print("MIR-SECRETAS-BIOLAB-RESEARCHABILITY-PASS " .. assertions)
