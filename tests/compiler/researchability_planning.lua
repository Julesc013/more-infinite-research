-- Controlled module tests, not a package, save, or ecosystem qualification.
local world, context, active_context, last_created_context
local registry, recipe_unlock_facts, production, researchability, feasibility, route_policy
local checks = 0
local failures = {}

local function stub(name, value) package.loaded[name] = value end
local function check(id, condition, detail)
  checks = checks + 1
  if not condition then
    local failure = "FAILED " .. id .. ": " .. detail
    failures[#failures + 1] = failure
    print(failure)
    return
  end
  print("OBSERVED\t" .. id .. "\t" .. detail)
end

_G.log = function(_) end
_G.data = {raw = {}, extend = function() error("Unexpected prototype mutation") end}
local target_profile = {current_factorio_version = "2.1"}
target_profile.current = function() return target_profile end
stub("prototypes.mir.platform.factorio.target_profiles", target_profile)
stub("prototypes.mir.platform.factorio.prototype_lookup", {
  item_prototype = function(name) return world.item_prototypes[name] end
})
stub("prototypes.mir.capabilities.science_integration.lab_compatibility", {
  ingredient_name = function(ingredient) return ingredient.name or ingredient[1] end,
  valid_research_ingredients = function(ingredients)
    for _, ingredient in ipairs(ingredients or {}) do
      local name = ingredient.name or ingredient[1]
      if not world.item_prototypes[name] then return false end
    end
    return true
  end
})
stub("prototypes.mir.index.recipe_facts", {
  view = function(name) return world.recipe_facts[name] end,
  recipes_by_output_view = function(name) return world.producers[name] or {} end,
  recipes_by_output_identity_view = function(entry_type, name)
    if world.producers_identity then return world.producers_identity[entry_type .. "\0" .. name] or {} end
    return entry_type == "item" and (world.producers[name] or {}) or {}
  end,
  index_view = function()
    return {
      facts = world.recipe_facts,
      by_output = world.producers,
      by_output_identity = world.producers_identity
    }
  end,
  source_epoch = function() return world.recipe_source_epoch or 1 end
})
local function new_context()
  local next_context = {states = {}, epochs = {}, services = {}, services_frozen = false}
  function next_context:execution_mode() return "SAFE" end
  function next_context:state_view(name, factory)
    if self.states[name] == nil and factory then
      self.states[name] = factory()
      self.epochs[name] = self.epochs[name] or 1
    end
    return self.states[name]
  end
  function next_context:set_state(name, value)
    if self.states[name] ~= nil then error("fixture state assigned twice: " .. name) end
    self.states[name] = value
    self.epochs[name] = 1
    return value
  end
  function next_context:has_state(name) return self.states[name] ~= nil end
  function next_context:state_epoch(name) return self.epochs[name] end
  function next_context:replace_epoch(name, value, expected_epoch)
    if self.states[name] == nil then error("fixture missing state: " .. name) end
    if expected_epoch ~= nil and self.epochs[name] ~= expected_epoch then error("fixture epoch mismatch: " .. name) end
    self.states[name] = value
    self.epochs[name] = self.epochs[name] + 1
    return value, self.epochs[name]
  end
  function next_context:set_service(name, implementation)
    if self.services_frozen then error("fixture services are frozen") end
    if self.services[name] ~= nil then error("fixture service assigned twice: " .. name) end
    self.services[name] = implementation
    return implementation
  end
  function next_context:has_service(name)
    return self.services[name] ~= nil
  end
  function next_context:freeze_services()
    self.services_frozen = true
  end
  function next_context:service(name)
    if self.services[name] then return self.services[name] end
    if name == "science.technology_researchability_reason" then return researchability.reason_with_context end
    if name == "science.pack_production_status" then return production.pack_production_status end
    if name == "science.independent_pack_acquisition_witness" then return production.independent_pack_acquisition_witness end
    if name == "science.prereq_tech_for_science_pack" then return production.prereq_tech_for_science_pack end
    if name == "science.prereq_techs_for_science_pack" then return production.prereq_techs_for_science_pack end
    if name == "science.production_route_for_pack" then return production.production_route_for_pack end
    error("Unexpected service: " .. tostring(name))
  end
  return next_context
end

stub("prototypes.mir.pipeline.compiler_context", {
  current = function() return active_context or context end,
  new = function()
    last_created_context = new_context()
    return last_created_context
  end,
  with_active = function(next_context, callback, ...)
    local previous = active_context
    active_context = next_context
    local results = {pcall(callback, ...)}
    active_context = previous
    if not results[1] then error(results[2]) end
    return table.unpack(results, 2)
  end
})
stub("prototypes.mir.report.compiler_telemetry", {
  observe_max = function(name, value)
    local telemetry = (active_context or context):state_view("compiler_telemetry", function()
      return {counters = {}}
    end)
    telemetry.counters[name] = math.max(telemetry.counters[name] or 0, value or 0)
  end,
  count = function(name, amount)
    local telemetry = (active_context or context):state_view("compiler_telemetry", function()
      return {counters = {}}
    end)
    telemetry.counters[name] = (telemetry.counters[name] or 0) + (amount or 1)
  end,
  start_phase = function(name)
    local telemetry = (active_context or context):state_view("compiler_telemetry", function()
      return {counters = {}}
    end)
    telemetry.counters["phase-start-" .. tostring(name)] = (telemetry.counters["phase-start-" .. tostring(name)] or 0) + 1
  end,
  finish_phase = function(name)
    local telemetry = (active_context or context):state_view("compiler_telemetry", function()
      return {counters = {}}
    end)
    telemetry.counters["phase-finish-" .. tostring(name)] = (telemetry.counters["phase-finish-" .. tostring(name)] or 0) + 1
  end
})

registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
recipe_unlock_facts = require("prototypes.mir.capabilities.science_integration.recipe_unlock_facts")
production = require("prototypes.mir.capabilities.science_integration.pack_production_reachability")
researchability = require("prototypes.mir.capabilities.science_integration.technology_researchability")
feasibility = require("prototypes.mir.capabilities.science_integration.recipe_route_feasibility")
route_policy = require("prototypes.mir.capabilities.science_integration.production_route_policy")

local function reset(next_world)
  world = next_world
  data.raw = {
    lab = world.labs or {},
    technology = world.techs or {},
    recipe = world.recipe_prototypes or {},
    character = world.characters or {player = {crafting_categories = {"crafting"}}},
    resource = world.resources or {},
    tree = world.trees or {},
    plant = world.plants or {},
    ["asteroid-chunk"] = world.asteroid_chunks or {},
    ["unit-spawner"] = world.unit_spawners or {},
    unit = world.units or {},
    turret = world.turrets or {},
    ["assembling-machine"] = world.assembling_machines or {},
    tile = world.tiles or {},
    ["offshore-pump"] = world.offshore_pumps or {},
    boiler = world.boilers or {},
    surface = world.surfaces or {},
    ["space-location"] = world.space_locations or {},
    planet = world.planets or {}
  }
  active_context = nil
  context = new_context()
  -- The real compiler reaches this diagnostic only after it has captured its
  -- immutable recipe snapshot. The ordinary controlled worlds retain a small
  -- equivalent parent snapshot while their recipe-facts facade remains stubbed;
  -- D23 below checks borrowing that controlled parent snapshot.
  context.states.recipe_source = world.recipe_prototypes or {}
  context.epochs.recipe_source = 1
  context.states.recipe_index = {
    facts = world.recipe_facts or {},
    by_output = world.producers or {},
    by_output_identity = world.producers_identity or {}
  }
  context.epochs.recipe_index = 1
end

local function representation_world(prototypes)
  return {
    item_prototypes = prototypes,
    labs = {lab = {inputs = {"custom-item-pack", "custom-tool-pack"}}},
    techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {}
  }
end

-- A physical item listed by a lab is a research pack regardless of a target
-- profile's nominal prototype kind.  No vanilla-named pack is present here,
-- and this harness deliberately provides no target-profile module: accidental
-- reintroduction of representation inference makes the controlled load fail.
reset(representation_world({["custom-item-pack"] = {type = "item"}, ["custom-tool-pack"] = {type = "tool"}}))
check("R01", registry.science_pack_exists("custom-item-pack") and registry.science_pack_exists("custom-tool-pack"),
  "Lab-listed physical item and tool packs are admitted without a vanilla-name or target-kind probe")
check("R02", table.concat(registry.all_lab_inputs(), ",") == "custom-item-pack,custom-tool-pack",
  "Lab-input admission remains deterministic across concrete item representations")
reset({
  item_prototypes = {orphan = {type = "item"}},
  labs = {lab = {inputs = {"missing-prototype"}}},
  techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {}
})
check("R03", not registry.science_pack_exists("orphan"),
  "A physical item absent from every lab remains excluded")
check("R04", not registry.science_pack_exists("missing-prototype"),
  "A lab input without a physical item prototype remains excluded")

local function technology(pack, unlock_recipe)
  local technology = {enabled = true, unit = {count = 1, time = 1, ingredients = {{name = pack, amount = 1}}}}
  if unlock_recipe then technology.effects = {{type = "unlock-recipe", recipe = unlock_recipe}} end
  return technology
end

local function pack_world(seed, initial_first)
  local a_recipes = initial_first and {"A-initial", "A-late"} or {"A-late", "A-initial"}
  local recipes = {
    ["A-initial"] = {enabled_without_research = true, result_names = {"A"}},
    ["A-late"] = {enabled_without_research = false, result_names = {"A"}},
    ["B-from-A"] = {enabled_without_research = false, result_names = {"B"}}
  }
  if not seed then
    recipes["A-initial"] = nil
    a_recipes = {"A-late"}
  end
  return {
    item_prototypes = {A = {type = "item"}, B = {type = "item"}},
    labs = {lab = {inputs = {"A", "B"}}},
    techs = {TechA = technology("A", "B-from-A"), TechB = technology("B", "A-late")},
    recipe_prototypes = {
      ["A-initial"] = {name = "A-initial"},
      ["A-late"] = {name = "A-late"},
      ["B-from-A"] = {name = "B-from-A"}
    },
    recipe_facts = recipes,
    producers = {A = a_recipes, B = {"B-from-A"}},
    unlockers = { ["A-late"] = {"TechB"}, ["B-from-A"] = {"TechA"} }
  }
end

-- An initially available A must make B researchable in both cold query orders.
reset(pack_world(true, true))
local a = production.pack_production_status("A", {})
local b = production.pack_production_status("B", {})
check("C01", a == "initial" and b == "research" and context.states.science_pack_production.entries.B.status == "research",
  "A then B is order-independent and caches only the resolved B route")
check("C02", production.pack_production_status("B", {}) == "research",
  "Warm B query reuses the resolved root result")
reset(pack_world(true, true))
b = production.pack_production_status("B", {})
a = production.pack_production_status("A", {})
check("C03", a == "initial" and b == "research",
  "B then A reaches the same seeded acquisition closure")
reset(pack_world(true, false))
a = production.pack_production_status("A", {})
b = production.pack_production_status("B", {})
check("C04", a == "initial" and b == "research",
  "Producer declaration order cannot change the seeded closure")
reset(pack_world(false, true))
a = production.pack_production_status("A", {})
b = production.pack_production_status("B", {})
check("C05", a == "unreachable" and b == "unreachable",
  "A genuinely unseeded production cycle remains rejected")
reset(pack_world(false, true))
b = production.pack_production_status("B", {})
a = production.pack_production_status("A", {})
check("C06", a == "unreachable" and b == "unreachable",
  "The unseeded rejection is also query-order independent")
reset(pack_world(true, true))
local conditional_b = production.pack_production_status("B", {}, {TechA = true})
b = production.pack_production_status("B", {})
check("C07", conditional_b == "unreachable" and b == "research",
  "A technology-conditional rejection cannot poison the reusable root cache")

-- A root result is a source-epoch-bound proof, so a different active route
-- may reuse it. The same active pack must still be rejected before consulting
-- that cache, or an unseeded self-cycle could be hidden.
reset(pack_world(true, true))
local root_recipe_status_calls = 0
local normal_recipe_status = recipe_unlock_facts.pack_recipe_status
recipe_unlock_facts.pack_recipe_status = function(...)
  root_recipe_status_calls = root_recipe_status_calls + 1
  return normal_recipe_status(...)
end
local root_a = production.pack_production_status("A", {})
local root_recipe_status_calls_after_root = root_recipe_status_calls
local active_a = production.pack_production_status("A", {B = true})
local self_active_a = production.pack_production_status("A", {A = true})
recipe_unlock_facts.pack_recipe_status = normal_recipe_status
check("C07A", root_a == "initial" and active_a == "initial"
  and self_active_a == "unreachable"
  and root_recipe_status_calls_after_root > 0
  and root_recipe_status_calls == root_recipe_status_calls_after_root,
  "An active route reuses only a root-proven pack result while retaining its same-pack cycle guard")

-- Separate root packs can inspect the same raw resource catalog. Reuse that
-- source-epoch-bound structural observation, while keeping each pack result
-- independently selected and cached.
reset({
  item_prototypes = {P = {type = "item"}, Q = {type = "item"}},
  labs = {lab = {inputs = {"P", "Q"}}},
  techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {},
  resources = {
    ["P-source"] = {minable = {result = "P", count = 1}},
    ["Q-source"] = {minable = {result = "Q", count = 1}}
  }
})
local resource_catalog_reads = 0
data.raw.resource = nil
setmetatable(data.raw, {
  __index = function(_, name)
    if name == "resource" then
      resource_catalog_reads = resource_catalog_reads + 1
      return world.resources
    end
  end
})
check("C08", production.pack_production_status("P", {}) == "non-recipe"
  and production.pack_production_status("Q", {}) == "non-recipe"
  -- data_raw.prototypes deliberately reads raw.resource once to establish
  -- presence and once to return it. One source-catalog construction therefore
  -- produces two raw-table reads.
  and resource_catalog_reads == 2,
  "Separate root packs reuse one immutable direct-source catalog")
world.recipe_source_epoch = 2
check("C08A", production.pack_production_status("P", {}) == "non-recipe"
  and resource_catalog_reads == 4,
  "A recipe-source epoch change replaces the shared direct-source catalog")

-- The planner asks root technology questions repeatedly while constructing
-- requirements and prerequisites. Those questions have no active traversal
-- or unlock recipe, so the exact root conclusion can be cached per source
-- epoch without changing contextual self-lock decisions.
reset(pack_world(true, true))
local root_pack_checks = 0
local normal_pack_status = context:service("science.pack_production_status")
context.services["science.pack_production_status"] = function(...)
  root_pack_checks = root_pack_checks + 1
  return normal_pack_status(...)
end
local root_reason_first = researchability.technology_researchability_reason("TechA")
local root_pack_checks_after_first = root_pack_checks
local root_reason_second = researchability.technology_researchability_reason("TechA")
check("C09", root_reason_first == nil
  and root_reason_second == nil
  and root_pack_checks_after_first > 0
  and root_pack_checks == root_pack_checks_after_first,
  "Repeated root technology researchability reuses its exact source-epoch conclusion")
world.recipe_source_epoch = 2
check("C09A", researchability.technology_researchability_reason("TechA") == nil
  and root_pack_checks > root_pack_checks_after_first,
  "A recipe-source epoch change invalidates the root technology conclusion")

local function improved_world(seed)
  local recipes = { ["A-improved"] = {enabled_without_research = false, result_names = {"A"}} }
  local producers = {A = {"A-improved"}}
  if seed then
    recipes["A-initial"] = {enabled_without_research = true, result_names = {"A"}}
    producers.A = {"A-initial", "A-improved"}
  end
  return {
    item_prototypes = {A = {type = "item"}},
    labs = {lab = {inputs = {"A"}}},
    techs = {TechA = technology("A", "A-improved")},
    recipe_prototypes = {
      ["A-initial"] = {name = "A-initial"},
      ["A-improved"] = {name = "A-improved"}
    },
    recipe_facts = recipes,
    producers = producers,
    unlockers = { ["A-improved"] = {"TechA"} }
  }
end

reset(improved_world(true))
local improved_reason = researchability.reason_with_context("TechA", {
  visiting_packs = {}, visiting_technologies = {}, unlock_recipe_name = "A-improved"
})
local improved_unlockers = production.researchable_unlockers_for_recipe("A-improved")
check("I01", improved_reason == nil and #improved_unlockers == 1 and improved_unlockers[1] == "TechA",
  "An independent initial A witness permits an improved A producer")
improved_reason = researchability.reason_with_context("TechA", {
  visiting_packs = {A = true}, visiting_technologies = {}, unlock_recipe_name = "A-improved"
})
check("I01A", improved_reason == nil,
  "The independent A witness remains valid during the active A route traversal")

-- An independent direct source is equally valid. A later self-output recipe
-- must not hide that source merely because a recipe row exists for the pack.
local source_seeded_improved = improved_world(false)
source_seeded_improved.resources = {A_source = {minable = {result = "A", count = 1}}}
reset(source_seeded_improved)
improved_reason = researchability.reason_with_context("TechA", {
  visiting_packs = {}, visiting_technologies = {}, unlock_recipe_name = "A-improved"
})
improved_unlockers = production.researchable_unlockers_for_recipe("A-improved")
check("I01B", improved_reason == nil and production.pack_production_status("A", {}) == "non-recipe"
  and #improved_unlockers == 1 and improved_unlockers[1] == "TechA",
  "An independent direct source permits an improved A producer despite its self-output recipe")
reset(improved_world(false))
improved_reason = researchability.reason_with_context("TechA", {
  visiting_packs = {}, visiting_technologies = {}, unlock_recipe_name = "A-improved"
})
improved_unlockers = production.researchable_unlockers_for_recipe("A-improved")
check("I02", improved_reason == "science-self-lock-A" and #improved_unlockers == 0,
  "An unseeded improved producer remains a science self-lock")

local function dependency_self_lock_world()
  local tech_a = technology("A", "A-self")
  local tech_b = technology("B", "A-alt")
  tech_b.prerequisites = {"TechA"}
  return {
    item_prototypes = {A = {type = "item"}, B = {type = "item"}},
    labs = {lab = {inputs = {"A", "B"}}},
    techs = {TechA = tech_a, TechB = tech_b},
    recipe_prototypes = {
      ["A-self"] = {name = "A-self"},
      ["A-alt"] = {name = "A-alt"},
      ["B-initial"] = {name = "B-initial"}
    },
    recipe_facts = {
      ["A-self"] = {enabled_without_research = false, result_names = {"A"}},
      ["A-alt"] = {enabled_without_research = false, result_names = {"A"}},
      ["B-initial"] = {enabled_without_research = true, result_names = {"B"}}
    },
    producers = {A = {"A-self", "A-alt"}, B = {"B-initial"}},
    unlockers = { ["A-self"] = {"TechA"}, ["A-alt"] = {"TechB"} }
  }
end

-- A route through TechB is not independent acquisition when TechB depends on
-- the active TechA. The active technology traversal must cross the nested
-- alternative-route query so the dependency-mediated self-lock terminates and
-- remains rejected.
reset(dependency_self_lock_world())
local dependency_status = production.pack_production_status("A", {})
local self_unlockers = production.researchable_unlockers_for_recipe("A-self")
local alternate_unlockers = production.researchable_unlockers_for_recipe("A-alt")
check("I03", dependency_status == "unreachable",
  "A dependency-mediated alternate producer cannot seed its active prerequisite")
check("I04", #self_unlockers == 0 and #alternate_unlockers == 0,
  "Neither side of the dependency-mediated self-lock is researchable")

-- This fixture advances the recipe-source dependency epoch directly to cover
-- consumer cache behavior.  recipe_source_epoch.lua separately exercises the
-- real recipe_facts.replace_source()/CompilerContext replacement operation.
-- The first direction proves a formerly negative root does not remain
-- poisoned after a source dependency change.
reset(pack_world(false, true))
check("E01", production.pack_production_status("A", {}) == "unreachable",
  "The unseeded root begins unreachable before the source replacement")
world.recipe_facts["A-initial"] = {enabled_without_research = true, result_names = {"A"}}
world.producers.A = {"A-initial", "A-late"}
world.recipe_source_epoch = 2
check("E02", production.pack_production_status("A", {}) == "initial"
  and production.pack_production_status("B", {}) == "research",
  "A source dependency change invalidates stale negative recipe and production caches")
check("E03", #recipe_unlock_facts.unlockers_for_recipe("B-from-A") == 1,
  "The context-aware recipe unlock index rebuilds against the replacement epoch")

-- The reverse direction is equally important: removal must not leave a
-- formerly positive acquisition route available through the warm root cache.
reset(pack_world(true, true))
check("E04", production.pack_production_status("B", {}) == "research",
  "The seeded route begins researchable before removal")
world.recipe_facts["A-initial"] = nil
world.producers.A = {"A-late"}
world.recipe_source_epoch = 2
check("E05", production.pack_production_status("A", {}) == "unreachable"
  and production.pack_production_status("B", {}) == "unreachable",
  "A source dependency change invalidates stale positive recipe and production caches")

local function route_fact(output, ingredients, options)
  options = options or {}
  return {
    enabled_without_research = options.enabled ~= false,
    source_class = options.source_class,
    result_names = {output},
    variants = options.variants or {{
      name = "default",
      enabled = options.enabled ~= false,
      hidden = false,
      categories = options.categories or {"crafting"},
      ingredients = ingredients or {},
      results = options.results or {{name = output, amount = options.amount or 1, probability = options.probability or 1}},
      energy_required = options.energy_required,
      surface_conditions = options.surface_conditions
    }}
  }
end

local function feasibility_world()
  return {
    item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, unlockers = {},
    recipe_facts = {
      ["pack-from-ore"] = route_fact("pack", {{name = "ore", amount = 1}}),
      ["locked-input"] = route_fact("locked", {}, {enabled = false}),
      ["pack-from-locked"] = route_fact("locked-pack", {{name = "locked", amount = 1}}),
      ["chemical-pack"] = route_fact("chemical-pack", {{name = "ore", amount = 1}}, {categories = {"chemistry"}}),
      ["surface-pack"] = route_fact("surface-pack", {{name = "ore", amount = 1}}, {
        surface_conditions = {{property = "pressure", min = 9999}}
      }),
      ["invalid-energy-pack"] = route_fact("invalid-energy-pack", {{name = "ore", amount = 1}}, {energy_required = 0}),
      ["zero-output-pack"] = route_fact("zero-output-pack", {{name = "ore", amount = 1}}, {amount = 0}),
      ["alternative-a"] = route_fact("alternative", {{name = "missing", amount = 1}}),
      ["alternative-b"] = route_fact("alternative", {{name = "ore", amount = 1}}),
      ["cycle-a"] = route_fact("cycle-a", {{name = "cycle-b", amount = 1}}),
      ["cycle-b"] = route_fact("cycle-b", {{name = "cycle-a", amount = 1}})
    },
    producers = {
      pack = {"pack-from-ore"}, locked = {"locked-input"}, ["locked-pack"] = {"pack-from-locked"},
      ["chemical-pack"] = {"chemical-pack"}, ["surface-pack"] = {"surface-pack"},
      ["invalid-energy-pack"] = {"invalid-energy-pack"}, ["zero-output-pack"] = {"zero-output-pack"},
      alternative = {"alternative-a", "alternative-b"}, ["cycle-a"] = {"cycle-a"}, ["cycle-b"] = {"cycle-b"}
    },
    resources = {ore = {minable = {result = "ore", count = 1}}}
  }
end

reset(feasibility_world())
check("F01", feasibility.initial_recipe_witness("pack-from-ore", "pack") ~= nil,
  "An enabled recipe is initial only after every ingredient has a concrete source witness")
check("F02", feasibility.initial_recipe_witness("pack-from-locked", "locked-pack") == nil,
  "A locked ingredient is not an initial acquisition witness")
check("F03", feasibility.initial_recipe_witness("chemical-pack", "chemical-pack") == nil,
  "A route without a compatible machine category is rejected")
check("F04", feasibility.initial_recipe_witness("surface-pack", "surface-pack") == nil,
  "An impossible surface condition is rejected")
check("F05", feasibility.initial_recipe_witness("invalid-energy-pack", "invalid-energy-pack") == nil,
  "A non-positive or non-finite recipe energy is rejected")
check("F06", feasibility.initial_recipe_witness("zero-output-pack", "zero-output-pack") == nil,
  "A route with no positive output is rejected")
check("F07", feasibility.acquisition_witness("alternative") ~= nil,
  "An infeasible producer does not prevent a later feasible recipe alternative")
check("F08", feasibility.acquisition_witness("missing") == nil
  and feasibility.acquisition_witness("missing", {source_witness = function(name)
    return name == "missing" and {kind = "fixture-source", item = name} or nil
  end}) ~= nil,
  "A no-recipe supply requires an explicit source witness")
check("F09", feasibility.acquisition_witness("cycle-a") == nil,
  "An unseeded item-production cycle remains rejected")

-- A caller's route options may be reused. The initial-only helper must not
-- write require_enabled back into that shared table.
local reusable_options = {require_enabled = false}
feasibility.initial_recipe_witness("pack-from-ore", "pack", reusable_options)
check("F09A", reusable_options.require_enabled == false,
  "Initial-route feasibility does not mutate caller options")

-- Structural search prefers a forward producer while retaining every
-- alternative. This fixture does not certify a non-ordinary science route.
local producer_order_world = {
  item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, unlockers = {},
  recipe_facts = {
    ["a-recycling"] = route_fact("component", {{name = "ore", amount = 1}}, {source_class = "recycling"}),
    ["z-ordinary"] = route_fact("component", {{name = "ore", amount = 1}})
  },
  producers = {component = {"a-recycling", "z-ordinary"}},
  resources = {ore = {minable = {result = "ore", count = 1}}}
}
reset(producer_order_world)
local ordered_acquisition = feasibility.acquisition_witness("component")
check("RS01", ordered_acquisition and ordered_acquisition.recipe == "z-ordinary",
  "Normal structural acquisition prefers a viable ordinary producer before a reverse recycling producer")
local order_observer = {visits = 0, limit = 1000}
function order_observer:reserve_visit()
  if self.visits >= self.limit then return false end
  self.visits = self.visits + 1
  return true
end
function order_observer:is_stopped() return self.visits >= self.limit end
local diagnostic_acquisition = feasibility.acquisition_witness("component", {diagnostic_observer = order_observer})
check("RS02", diagnostic_acquisition and diagnostic_acquisition.recipe == "a-recycling"
  and order_observer.visits > 0 and order_observer.visits <= order_observer.limit,
  "Bounded structural diagnostics retain their lexical branch order and irreversible visit accounting")
producer_order_world.recipe_facts["z-ordinary"] = route_fact("component", {{name = "missing", amount = 1}})
producer_order_world.recipe_facts["a-recycling"] = route_fact("component", {{name = "component", amount = 1}}, {source_class = "recycling"})
reset(producer_order_world)
local return_branch_visits = 0
local rejected_acquisition = feasibility.acquisition_witness("component", {
  source_witness = function(name)
    if name == "missing" then return_branch_visits = return_branch_visits + 1 end
    return nil
  end,
  diagnostic_failure = function(failure)
    if failure.recipe == "a-recycling" then return_branch_visits = return_branch_visits + 1 end
  end
})
check("RS03", rejected_acquisition == nil and return_branch_visits >= 2,
  "An infeasible forward producer still reaches the retained recycling alternative and rejects its unseeded cycle")

-- A recursive failure is conditional on its parent visitation set. In this
-- A <-> B graph, A's independent ore route must permit a later root B query;
-- the first nested B rejection must never poison the reusable root memo.
local cycle_with_ore = {
  item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, unlockers = {},
  recipe_facts = {
    ["a-from-b"] = route_fact("A", {{name = "B", amount = 1}}),
    ["a-from-ore"] = route_fact("A", {{name = "ore", amount = 1}}),
    ["b-from-a"] = route_fact("B", {{name = "A", amount = 1}})
  },
  producers = {A = {"a-from-b", "a-from-ore"}, B = {"b-from-a"}},
  resources = {ore = {minable = {result = "ore", count = 1}}}
}
reset(cycle_with_ore)
local cycle_with_ore_state = {}
check("F09AA", feasibility.acquisition_witness("A", nil, cycle_with_ore_state) ~= nil
  and feasibility.acquisition_witness("B", nil, cycle_with_ore_state) ~= nil,
  "A traversal-conditional B rejection cannot poison a later root B acquisition")

-- A caller-supplied index is part of the query identity. Reusing the state
-- with another index must reset an earlier positive memo even at the same
-- CompilerContext and recipe-source epoch.
local indexed_source = {
  facts = {["switch-from-ore"] = route_fact("switch", {{name = "ore", amount = 1}})},
  by_output = {switch = {"switch-from-ore"}}
}
local indexed_absence = {facts = {}, by_output = {}}
local indexed_state = {}
check("F09AB", feasibility.acquisition_witness("switch", {recipe_index = indexed_source}, indexed_state) ~= nil
  and feasibility.acquisition_witness("switch", {recipe_index = indexed_absence}, indexed_state) == nil,
  "A reusable query state cannot retain an acquisition result for another recipe index")

-- A reusable traversal state may retain raw-prototype scan results only while
-- its recipe-source epoch matches. The same state object must not retain a
-- positive raw source after the owning context moves to a replacement epoch.
reset(feasibility_world())
local shared_query_state = {}
check("F09AC", feasibility.acquisition_witness("pack", nil, shared_query_state) ~= nil,
  "One acquisition query may reuse its bounded source scan")
world.resources = {}
data.raw.resource = world.resources
world.recipe_source_epoch = 2
check("F09AD", feasibility.acquisition_witness("pack", nil, shared_query_state) == nil,
  "A reusable query state is discarded across a recipe-source epoch")

-- Natural sources are restricted by their own surface conditions. A real
-- surface prototype can satisfy those conditions; a matching space-location
-- alone cannot stand in for a buildable surface.
local source_surface_conditions = {{property = "pressure", min = 900}}
local function source_surface_world(surfaces, planets, space_locations)
  return {
    item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {},
    resources = {ore = {
      minable = {result = "ore", count = 1}, surface_conditions = source_surface_conditions
    }},
    offshore_pumps = {water = {fluid = "water", surface_conditions = source_surface_conditions}},
    surfaces = surfaces, planets = planets, space_locations = space_locations
  }
end
reset(source_surface_world({high_pressure = {surface_properties = {pressure = 1000}}}))
check("F09AE", feasibility.source_witness("ore") ~= nil
  and feasibility.source_witness({type = "fluid", name = "water"}) ~= nil,
  "A real SurfacePrototype satisfies resource and offshore-pump source conditions")
reset(source_surface_world(nil, nil, {orbit = {surface_properties = {pressure = 1000}}}))
check("F09AF", feasibility.source_witness("ore") == nil
  and feasibility.source_witness({type = "fluid", name = "water"}) == nil,
  "A non-surface space-location cannot satisfy natural-source feasibility")
reset(source_surface_world({low_pressure = {surface_properties = {pressure = 100}}}))
check("F09AG", feasibility.source_witness("ore") == nil
  and feasibility.source_witness({type = "fluid", name = "water"}) == nil,
  "Impossible source surface conditions reject resource and offshore-pump witnesses")

-- Name equality is never enough: the product indexes and route comparison
-- distinguish an item and a fluid that deliberately share one name. An
-- item-only route cannot prove the fluid request, while an exact fluid route
-- remains independently eligible.
local collision_index = {
  facts = {
    ["item-same"] = route_fact("same", {}, {
      results = {{type = "item", name = "same", amount = 1, probability = 1}}
    }),
    ["fluid-same"] = route_fact("same", {}, {
      results = {{type = "fluid", name = "same", amount = 1, probability = 1}}
    })
  },
  by_output = {same = {"item-same", "fluid-same"}},
  by_output_identity = {
    ["item\0same"] = {"item-same"},
    ["fluid\0same"] = {"fluid-same"}
  }
}
check("F09B", feasibility.initial_recipe_witness("item-same", {type = "fluid", name = "same"}, {
  recipe_index = collision_index
}) == nil and feasibility.initial_recipe_witness("fluid-same", {type = "fluid", name = "same"}, {
  recipe_index = collision_index
}) ~= nil,
  "A same-name item product cannot satisfy a fluid route identity")

reset({
  item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {},
  resources = {same_resource = {minable = {result = "same", count = 1}}},
  offshore_pumps = {same_pump = {fluid = "same"}}
})
check("F09C", feasibility.source_witness("same").kind == "minable-resource"
  and feasibility.source_witness({type = "fluid", name = "same"}).kind == "offshore-pump",
  "A same-name natural item source is not reused as a fluid source")

-- Current Factorio base offshore pumps expose their water source via a source
-- offset rather than the former `fluid` field. This still proves the exact
-- water fluid, never a same-named item identity.
reset({
  item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {},
  offshore_pumps = {base_pump = {fluid_source_offset = {0, -1}, fluid_box = {}}},
  tiles = {water = {fluid = "water"}}
})
local base_water_witness = feasibility.source_witness({type = "fluid", name = "water"})
check("F09C0", base_water_witness and base_water_witness.kind == "offshore-pump"
  and base_water_witness.product.type == "fluid" and base_water_witness.product.name == "water"
  and feasibility.source_witness({type = "item", name = "water"}) == nil,
  "A source-offset offshore pump supplies the exact base water fluid")

-- A fluid-box filter constrains a pump connection, but cannot establish that
-- the filtered fluid is naturally available. This must stay false even on
-- Factorio 2.1: otherwise a modded filtered molten-fluid pump could seed an
-- unproduced route cycle.
reset({
  item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {},
  offshore_pumps = {filtered_pump = {fluid_box = {filter = "molten-nickel"}}}
})
check("F09C0A", feasibility.source_witness({type = "fluid", name = "molten-nickel"}) == nil,
  "An F210 filtered offshore pump without a source offset is not a natural source")

-- The source-offset interpretation is a Factorio-2.1 contract. A fluid-box
-- filter remains insufficient on every target.
-- F200 keeps its established explicit-pump-field semantics; an F200 mod can
-- still declare a source through `fluid`.
target_profile.current_factorio_version = "2.0"
reset({
  item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {},
  offshore_pumps = {base_pump = {fluid_source_offset = {0, -1}, fluid_box = {filter = "water"}}}
})
check("F09C1", feasibility.source_witness({type = "fluid", name = "water"}) == nil,
  "An F200 source-offset or fluid-box pump does not infer a natural fluid source")
reset({
  item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {},
  offshore_pumps = {declared_pump = {fluid = "water"}}
})
check("F09C2", feasibility.source_witness({type = "fluid", name = "water"}) ~= nil,
  "An F200 pump preserves an explicit fluid source declaration")
target_profile.current_factorio_version = "2.1"

reset({
  item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {},
  plants = {yumako = {minable = {results = {{type = "item", name = "yumako", amount = 50}}}}},
  asteroid_chunks = {oxide = {minable = {result = "oxide-asteroid-chunk", count = 1}}},
  offshore_pumps = {pump = {fluid_source_offset = {0, -1}, fluid_box = {}}},
  tiles = {oil_ocean = {fluid = "heavy-oil"}, ammonia_ocean = {fluid = "ammoniacal-solution"}}
})
check("F09C3", feasibility.source_witness("yumako").kind == "minable-entity"
  and feasibility.source_witness("oxide-asteroid-chunk").kind == "minable-entity",
  "Space Age crops and asteroid chunks retain their declared natural item sources")
check("F09C4", feasibility.source_witness({type = "fluid", name = "heavy-oil"}) ~= nil
  and feasibility.source_witness({type = "fluid", name = "ammoniacal-solution"}) ~= nil
  and feasibility.source_witness({type = "fluid", name = "water"}) == nil,
  "F210 pumps use declared ocean fluids without inventing water")
check("F09C5", feasibility.source_witness({type = "fluid", name = "yumako"}) == nil
  and feasibility.source_witness({type = "item", name = "heavy-oil"}) == nil,
  "Planetary item and fluid sources preserve exact product identity")
world.offshore_pumps.pump.fluid_box.filter = "molten-nickel"
world.recipe_source_epoch = 2
check("F09C6", feasibility.source_witness({type = "fluid", name = "molten-nickel"}) == nil
  and feasibility.source_witness({type = "fluid", name = "heavy-oil"}) == nil,
  "A filtered F210 pump cannot create a fluid absent from tiles or accept a mismatched tile")
world.offshore_pumps.pump.fluid_box.filter = nil
world.tiles = {}
world.recipe_source_epoch = 3
check("F09C7", feasibility.source_witness({type = "fluid", name = "water"}) == nil,
  "A source offset without a declared fluid tile is not a natural source")

reset({
  item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, unlockers = {},
  recipe_facts = {eggs = route_fact("biter-egg", {}, {categories = {"captive-spawner-process"}})},
  producers = {["biter-egg"] = {"eggs"}},
  assembling_machines = {captive = {crafting_categories = {"captive-spawner-process"}, fixed_recipe = "eggs"}},
  unit_spawners = {wild = {loot = {
    {type = "item", name = "pentapod-egg", amount_min = 0, amount_max = 3},
    {type = "item", name = "zero-drop", amount = 0},
    {type = "item", name = "impossible-drop", amount = 3, probability = 0},
    {type = "fluid", name = "invalid-fluid-loot", amount = 3}
  }}}
})
local egg_source = feasibility.source_witness("pentapod-egg")
check("F09C8", egg_source and egg_source.kind == "entity-loot"
  and feasibility.source_witness({type = "fluid", name = "pentapod-egg"}) == nil,
  "Positive enemy loot supplies its declared item seed without inventing fluid output")
check("F09C9", feasibility.source_witness("zero-drop") == nil
  and feasibility.source_witness("impossible-drop") == nil
  and feasibility.source_witness({type = "fluid", name = "invalid-fluid-loot"}) == nil,
  "Zero, impossible and non-item loot cannot seed acquisition")
check("F09C10", feasibility.initial_recipe_witness("eggs", "biter-egg") ~= nil,
  "A captured spawner supplies its declared recipe category")
world.assembling_machines = {}
data.raw["assembling-machine"] = world.assembling_machines
world.recipe_source_epoch = 2
check("F09C11", feasibility.initial_recipe_witness("eggs", "biter-egg") == nil,
  "Captive-spawner recipes remain infeasible without a matching prototype category")

-- Natural minable entities are separate from resource prototypes.  Trees are
-- a real early wood source, so a route consuming wood must not be treated as
-- an unseeded cycle merely because it is absent from data.raw.resource.
reset({
  item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {},
  trees = {tree = {minable = {result = "wood", count = 1}}}
})
check("F09CA", feasibility.source_witness("wood").kind == "minable-entity"
  and feasibility.source_witness("ore") == nil,
  "A minable tree is an item source without inventing a resource-prototype witness")

local function boiler_source_world(input_source, boiler_conditions)
  return {
    item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {},
    offshore_pumps = input_source and {pump = {fluid = "water"}} or {},
    boilers = {boiler = {
      name = "boiler",
      fluid_box = {filter = "water"},
      output_fluid_box = {filter = "steam"},
      target_temperature = 165,
      energy_consumption = "1.8MW",
      energy_source = {type = "burner"},
      surface_conditions = boiler_conditions
    }}
  }
end
reset(boiler_source_world(true))
local steam_witness = feasibility.source_witness({type = "fluid", name = "steam"})
check("F09CB", steam_witness and steam_witness.kind == "boiler-conversion"
  and steam_witness.prototype == "boiler" and steam_witness.input.type == "fluid"
  and steam_witness.input.name == "water" and steam_witness.target_temperature == 165,
  "A boiler converts an unconditional naturally pumped input into an exact typed fluid source")
check("F09CC", feasibility.source_witness("steam") == nil,
  "A boiler fluid output never supplies a same-named item identity")
reset(boiler_source_world(false))
check("F09CD", feasibility.source_witness({type = "fluid", name = "steam"}) == nil,
  "A boiler output without an independently sourced input fluid remains unavailable")
reset(boiler_source_world(true, {{property = "pressure", min = 1000}}))
check("F09CE", feasibility.source_witness({type = "fluid", name = "steam"}) == nil,
  "A surface-constrained boiler remains conservative until same-surface input proof exists")

-- A contextual unlock callback disables the ordinary acquisition memo. Even
-- then, two sibling recipes may safely share a proved source/enabled-recipe
-- route from one explicit query state. The returned copy must remain
-- defensive, and a research-unlocked witness must never enter that stable
-- cache.
reset({
  item_prototypes = {}, labs = {}, techs = {}, recipe_prototypes = {}, unlockers = {},
  recipe_facts = {}, producers = {},
  resources = {shared_ore = {minable = {result = "shared-ore", count = 1}}}
})
local shared_fact_reads = 0
local shared_facts = {
  ["shared-enabled"] = route_fact("shared-item", {{name = "shared-ore", amount = 1}}),
  ["top-one"] = route_fact("top-one", {{name = "shared-item", amount = 1}}),
  ["top-two"] = route_fact("top-two", {{name = "shared-item", amount = 1}})
}
local shared_index = {
  facts = setmetatable({}, {__index = function(_, name)
    if name == "shared-enabled" then shared_fact_reads = shared_fact_reads + 1 end
    return shared_facts[name]
  end}),
  by_output = {
    ["shared-item"] = {"shared-enabled"},
    ["top-one"] = {"top-one"},
    ["top-two"] = {"top-two"}
  }
}
local shared_options = {
  recipe_index = shared_index,
  research_unlock_witness = function() return nil end
}
local shared_state = {}
local top_one = feasibility.recipe_witness("top-one", "top-one", shared_options, shared_state)
if top_one then top_one.ingredients[1].recipe = "forged" end
local top_two = feasibility.recipe_witness("top-two", "top-two", shared_options, shared_state)
check("F09CF", top_one and top_two and top_two.ingredients[1].recipe == "shared-enabled"
  and shared_fact_reads == 1,
  "Sibling routes reuse a defensive copy of one context-free enabled acquisition witness")

local contextual_calls = 0
local contextual_options = {
  recipe_index = {facts = {}, by_output = {}},
  research_unlock_witness = function(identity)
    contextual_calls = contextual_calls + 1
    return {kind = "research-unlocked-recipe", identity = identity, marker = contextual_calls}
  end
}
local contextual_state = {}
local contextual_one = feasibility.acquisition_witness("contextual-item", contextual_options, contextual_state)
local contextual_two = feasibility.acquisition_witness("contextual-item", contextual_options, contextual_state)
check("F09CG", contextual_calls == 2 and contextual_one.marker == 1 and contextual_two.marker == 2,
  "Research-unlocked witnesses remain query-contextual and are never stored as stable acquisitions")

reset({
  item_prototypes = {same = {type = "item"}},
  labs = {lab = {inputs = {"same"}}}, techs = {}, recipe_prototypes = {}, unlockers = {},
  recipe_facts = {
    ["fluid-same"] = {
      name = "fluid-same", enabled_without_research = true,
      result_names = {"same"}, result_identities = {{type = "fluid", name = "same"}}
    }
  },
  producers = {same = {"fluid-same"}},
  producers_identity = {["fluid\0same"] = {"fluid-same"}}
})
check("F09D", recipe_unlock_facts.recipe_outputs_item("fluid-same", "same") == false
  and production.pack_production_status("same", {}) == "unreachable",
  "A same-name fluid result neither reports as an item output nor seeds an item science pack")

-- A research trigger and a lab accepting an item do not, by themselves,
-- establish a no-recipe source for that science pack.
reset({
  item_prototypes = {trigger_pack = {type = "item"}},
  labs = {lab = {inputs = {"trigger_pack"}}},
  techs = {trigger_pack = {enabled = true, research_trigger = {type = "mine-entity"}}},
  recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {}
})
check("F10", production.pack_production_status("trigger_pack", {}) == "unreachable",
  "A trigger and accepting lab are not a production-source witness")

-- A science-pack recipe may legitimately consume an intermediate unlocked by
-- the same reachable technology as another necessary component. The unlocker
-- is a contextual proof, never a source by itself: a concrete route for each
-- recipe remains required (F10 covers trigger-only false admission).
local function same_unlocker_world(unseeded_cycle)
  local unlocks = {
    {type = "unlock-recipe", recipe = "A-from-B"},
    {type = "unlock-recipe", recipe = unseeded_cycle and "B-from-A" or "B-from-trigger"}
  }
  return {
    item_prototypes = {A = {type = "item"}, B = {type = "item"}},
    labs = {lab = {inputs = {"A", "B"}}},
    techs = {
      SharedUnlock = {
        enabled = true,
        research_trigger = {type = "craft-item", item = "lab"},
        effects = unlocks
      }
    },
    recipe_prototypes = {
      ["A-from-B"] = {name = "A-from-B"},
      [unseeded_cycle and "B-from-A" or "B-from-trigger"] = {
        name = unseeded_cycle and "B-from-A" or "B-from-trigger"
      }
    },
    recipe_facts = {
      ["A-from-B"] = route_fact("A", {{name = "B", amount = 1}}, {enabled = false}),
      [unseeded_cycle and "B-from-A" or "B-from-trigger"] = route_fact(
        "B",
        unseeded_cycle and {{name = "A", amount = 1}} or {},
        {enabled = false}
      )
    },
    producers = {A = {"A-from-B"}, B = {unseeded_cycle and "B-from-A" or "B-from-trigger"}}
  }
end

-- A research-unlocked item route may need a research-unlocked fluid output.
-- The output lookup must retain the exact fluid identity; item-only indexing
-- would reject this seeded route before its unlocker and ingredient proof run.
local function fluid_intermediate_world()
  return {
    item_prototypes = {fluid_pack = {type = "item"}},
    labs = {lab = {inputs = {"fluid_pack"}}},
    techs = {
      SharedFluidUnlock = {
        enabled = true,
        research_trigger = {type = "craft-item", item = "lab"},
        effects = {
          {type = "unlock-recipe", recipe = "pack-from-solder"},
          {type = "unlock-recipe", recipe = "solder-from-molten"},
          {type = "unlock-recipe", recipe = "molten-from-ore"}
        }
      }
    },
    recipe_prototypes = {
      ["pack-from-solder"] = {name = "pack-from-solder"},
      ["solder-from-molten"] = {name = "solder-from-molten"},
      ["molten-from-ore"] = {name = "molten-from-ore"}
    },
    recipe_facts = {
      ["pack-from-solder"] = route_fact("fluid_pack", {{type = "item", name = "solder", amount = 1}}, {enabled = false}),
      ["solder-from-molten"] = route_fact("solder", {{type = "fluid", name = "molten-solder", amount = 1}}, {enabled = false}),
      ["molten-from-ore"] = route_fact("molten-solder", {{type = "item", name = "tin-ore", amount = 1}}, {
        enabled = false,
        results = {{type = "fluid", name = "molten-solder", amount = 1, probability = 1}}
      })
    },
    producers = {fluid_pack = {"pack-from-solder"}, solder = {"solder-from-molten"}},
    producers_identity = {
      ["item\0fluid_pack"] = {"pack-from-solder"},
      ["item\0solder"] = {"solder-from-molten"},
      ["fluid\0molten-solder"] = {"molten-from-ore"}
    },
    unlockers = {
      ["pack-from-solder"] = {"SharedFluidUnlock"},
      ["solder-from-molten"] = {"SharedFluidUnlock"},
      ["molten-from-ore"] = {"SharedFluidUnlock"}
    },
    resources = {tin_ore = {minable = {result = "tin-ore", count = 1}}}
  }
end

-- These are diagnostic projections, not new admissions.  They intentionally
-- use the exact production query name seen in the Bob/Angel audit while each
-- controlled world isolates one first-rejection class.  The checks below make
-- the trace shape deterministic without asserting any ecosystem outcome.
local function logistic_trace_world(recipe_name, fact, tech_name, resources)
  return {
    item_prototypes = {['logistic-science-pack'] = {type = 'item'}},
    labs = {lab = {inputs = {'logistic-science-pack'}}},
    techs = {[tech_name] = technology('logistic-science-pack', recipe_name)},
    recipe_prototypes = {[recipe_name] = {name = recipe_name}},
    recipe_facts = {[recipe_name] = fact},
    producers = {['logistic-science-pack'] = {recipe_name}},
    unlockers = {[recipe_name] = {tech_name}},
    resources = resources
  }
end

local function only_candidate(projection, recipe_name)
  return projection and projection.candidates and #projection.candidates == 1
    and projection.candidates[1].recipe == recipe_name and projection.candidates[1] or nil
end

local observed_context_state_names = {
  'science_pack_production',
  'science_pack_recipe_status',
  'technology_researchability_index',
  'compiler_telemetry'
}

local function context_observation_snapshot()
  local snapshot = {}
  for _, name in ipairs(observed_context_state_names) do
    snapshot[name] = {value = context.states[name], epoch = context.epochs[name]}
  end
  return snapshot
end

local function context_observation_unchanged(snapshot)
  for _, name in ipairs(observed_context_state_names) do
    local before = snapshot[name]
    if context.states[name] ~= before.value or context.epochs[name] ~= before.epoch then return false end
  end
  return true
end

reset(logistic_trace_world(
  'logistic-science-pack-from-missing-category',
  route_fact('logistic-science-pack', {}, {enabled = false, categories = {'missing-crafting-category'}}),
  'trace-category-unlocker'
))
local logistic_status = production.pack_production_status('logistic-science-pack', {})
local before_projection = context_observation_snapshot()
local logistic_projection = production.pack_production_rejection_projection('logistic-science-pack')
local logistic_candidate = only_candidate(logistic_projection, 'logistic-science-pack-from-missing-category')
check('D01', logistic_status == 'unreachable' and logistic_projection
  and logistic_projection.schema == 2 and logistic_projection.kind == 'science-pack-production-rejection-projection'
  and logistic_projection.pack_name == 'logistic-science-pack' and logistic_projection.status == 'unreachable'
  and logistic_projection.truncation and #logistic_projection.truncation.truncated == 0
  and logistic_projection.truncation.usage.trace_events == 1,
  'The rejected logistic pack has one selected failure trace, excluding its bounded status preflight')
check('D02', logistic_candidate and logistic_candidate.first_failure.kind == 'category'
  and logistic_candidate.first_failure.category == 'missing-crafting-category'
  and logistic_candidate.first_failure.reason == 'no-compatible-machine-category'
  and logistic_candidate.unlockers[1].technology == 'trace-category-unlocker'
  and logistic_candidate.unlockers[1].status == 'not-evaluated',
  'A candidate recipe retains its first unavailable machine category and unlocker disposition')
check('D03', context_observation_unchanged(before_projection)
  and production.pack_production_status('logistic-science-pack', {}) == 'unreachable',
  'Observation runs in a fresh context and leaves production, recipe, graph, and telemetry state unchanged')

reset(logistic_trace_world(
  'logistic-science-pack-from-wrong-identity',
  route_fact('wrong-output', {}, {enabled = false}),
  'trace-identity-unlocker'
))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack')
logistic_candidate = only_candidate(logistic_projection, 'logistic-science-pack-from-wrong-identity')
check('D04', logistic_candidate and logistic_candidate.first_failure.kind == 'identity'
  and logistic_candidate.first_failure.identity.type == 'item'
  and logistic_candidate.first_failure.identity.name == 'logistic-science-pack'
  and logistic_candidate.first_failure.reason == 'output-identity-mismatch',
  'A malformed candidate retains the rejected output identity instead of matching by name alone')

reset(logistic_trace_world(
  'logistic-science-pack-from-missing-ingredient',
  route_fact('logistic-science-pack', {{name = 'missing-trace-ingredient', amount = 1}}, {enabled = false}),
  'trace-ingredient-unlocker'
))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack')
logistic_candidate = only_candidate(logistic_projection, 'logistic-science-pack-from-missing-ingredient')
check('D05', logistic_candidate and logistic_candidate.first_failure.kind == 'ingredient'
  and logistic_candidate.first_failure.identity.name == 'missing-trace-ingredient'
  and logistic_candidate.first_failure.reason == 'no-enabled-acquisition-route',
  'A candidate retains the first missing ingredient acquisition rejection')

-- Sibling output routes may have different outer unlockers while sharing a
-- complete inner proof. The inner proof must be reused without treating the
-- unrelated outer unlocker as part of its identity; its own recipe/unlocker
-- pair and active acquisition identities remain checked by the memo.
local function dependency_checked_positive_memo_world(width)
  local facts = {
    ["shared-inner-recipe"] = route_fact(
      "shared-inner", {{name = "shared-ore", amount = 1}}, {enabled = false})
  }
  local prototypes = { ["shared-inner-recipe"] = {name = "shared-inner-recipe"} }
  local techs = {
    RootUnlock = {enabled = true, research_trigger = {type = "craft-item", item = "lab"}, effects = {}},
    SharedInnerUnlock = {
      enabled = true,
      research_trigger = {type = "craft-item", item = "lab"},
      effects = {{type = "unlock-recipe", recipe = "shared-inner-recipe"}}
    }
  }
  local producers = { ["shared-inner"] = {"shared-inner-recipe"}, ["memo-pack"] = {} }
  local unlockers = { ["shared-inner-recipe"] = {"SharedInnerUnlock"} }
  local items = { ["memo-pack"] = {type = "item"}, ["shared-inner"] = {type = "item"} }
  for index = 1, width do
    local outer = string.format("memo-outer-%02d", index)
    local outer_recipe = outer .. "-recipe"
    local pack_recipe = string.format("memo-pack-%02d", index)
    items[outer] = {type = "item"}
    techs["OuterUnlock" .. index] = {
      enabled = true,
      research_trigger = {type = "craft-item", item = "lab"},
      effects = {{type = "unlock-recipe", recipe = outer_recipe}}
    }
    facts[outer_recipe] = route_fact(outer, {{name = "shared-inner", amount = 1}}, {enabled = false})
    facts[pack_recipe] = route_fact("memo-pack", {{name = outer, amount = 1}}, {enabled = false})
    prototypes[outer_recipe] = {name = outer_recipe}
    prototypes[pack_recipe] = {name = pack_recipe}
    producers[outer] = {outer_recipe}
    table.insert(producers["memo-pack"], pack_recipe)
    table.insert(techs.RootUnlock.effects, {type = "unlock-recipe", recipe = pack_recipe})
    unlockers[outer_recipe] = {"OuterUnlock" .. index}
    unlockers[pack_recipe] = {"RootUnlock"}
  end
  return {
    item_prototypes = items,
    labs = {lab = {inputs = {"memo-pack"}}},
    techs = techs,
    recipe_prototypes = prototypes,
    recipe_facts = facts,
    producers = producers,
    unlockers = unlockers,
    resources = { ["shared-ore"] = {minable = {result = "shared-ore", count = 1}} }
  }
end

reset(dependency_checked_positive_memo_world(12))
local canonical_recipe_facts = package.loaded["prototypes.mir.index.recipe_facts"]
local normal_shared_output_lookup = canonical_recipe_facts.recipes_by_output_identity_view
local shared_inner_output_lookups = 0
canonical_recipe_facts.recipes_by_output_identity_view = function(entry_type, name)
  if entry_type == "item" and name == "shared-inner" then
    shared_inner_output_lookups = shared_inner_output_lookups + 1
  end
  return normal_shared_output_lookup(entry_type, name)
end
local memo_status = production.pack_production_status("memo-pack", {})
canonical_recipe_facts.recipes_by_output_identity_view = normal_shared_output_lookup
check("U05B", memo_status == "research" and shared_inner_output_lookups == 1,
  "A complete inner unlock witness is reused across sibling routes with unrelated active unlockers")

-- Locked typed-output alternatives use the same normal producer ordering.
-- Count real technology service evaluations, rather than pre-cache entries.
local locked_order_world = {
  item_prototypes = {["order-pack"] = {type = "item"}, component = {type = "item"}},
  labs = {lab = {inputs = {"order-pack"}}},
  techs = {
    RootUnlock = {enabled = true, research_trigger = {type = "craft-item", item = "lab"},
      effects = {{type = "unlock-recipe", recipe = "order-pack"}}},
    OrdinaryUnlock = {enabled = true, research_trigger = {type = "craft-item", item = "lab"},
      effects = {{type = "unlock-recipe", recipe = "z-ordinary"}}},
    RecyclingUnlock = {enabled = true, research_trigger = {type = "craft-item", item = "lab"},
      effects = {{type = "unlock-recipe", recipe = "a-recycling"}}}
  },
  recipe_prototypes = { ["order-pack"] = {name = "order-pack"},
    ["z-ordinary"] = {name = "z-ordinary"}, ["a-recycling"] = {name = "a-recycling"}},
  recipe_facts = {
    ["order-pack"] = route_fact("order-pack", {{name = "component", amount = 1}}, {enabled = false}),
    ["z-ordinary"] = route_fact("component", {{name = "ore", amount = 1}}, {enabled = false}),
    ["a-recycling"] = route_fact("component", {{name = "ore", amount = 1}}, {enabled = false, source_class = "recycling"})
  },
  producers = {["order-pack"] = {"order-pack"}, component = {"a-recycling", "z-ordinary"}},
  unlockers = {}, resources = {ore = {minable = {result = "ore", count = 1}}}
}
reset(locked_order_world)
local unlock_evaluations = {}
context.services["science.technology_researchability_reason"] = function(name, reason_context)
  unlock_evaluations[name] = (unlock_evaluations[name] or 0) + 1
  return researchability.reason_with_context(name, reason_context)
end
local locked_order_status = production.pack_production_status("order-pack", {})
check("RS04", locked_order_status == "research" and unlock_evaluations.OrdinaryUnlock == 1
  and unlock_evaluations.RecyclingUnlock == nil,
  "A viable locked ordinary intermediate avoids evaluating the reverse recycling unlocker")
locked_order_world.recipe_facts["z-ordinary"] = route_fact(
  "component", {{name = "missing", amount = 1}}, {enabled = false})
locked_order_world.recipe_facts["a-recycling"] = route_fact(
  "component", {{name = "component", amount = 1}}, {enabled = false, source_class = "recycling"})
reset(locked_order_world)
local fallback_evaluations = {}
context.services["science.technology_researchability_reason"] = function(name, reason_context)
  fallback_evaluations[#fallback_evaluations + 1] = name
  return researchability.reason_with_context(name, reason_context)
end
check("RS05", production.pack_production_status("order-pack", {}) == "unreachable"
  and table.concat(fallback_evaluations, ",") == "OrdinaryUnlock,RecyclingUnlock",
  "A failed locked forward route retains the recycling unlock alternative and rejects its unseeded cycle")

-- Locked ordinary suppliers prefer earlier progression over lexical names,
-- without removing later alternatives when the earlier recipe cannot supply
-- the ingredient. Reuse the real contextual technology service in both cases.
local progression_order_world = require("prototypes.mir.core.deepcopy")(locked_order_world)
progression_order_world.recipe_facts["z-ordinary"] = route_fact(
  "component", {{name = "ore", amount = 1}}, {enabled = false})
progression_order_world.recipe_facts["a-recycling"] = route_fact(
  "component", {{name = "ore", amount = 1}}, {enabled = false})
progression_order_world.techs.RecyclingUnlock.prerequisites = {"OrdinaryUnlock"}
reset(progression_order_world)
local early_route = production.production_route_for_pack("order-pack")
local early_pairs = early_route and early_route.provenance.selected_research_unlock_pairs or {}
local has_early, has_late = false, false
for _, pair in ipairs(early_pairs) do
  has_early = has_early or pair.recipe == "z-ordinary"
  has_late = has_late or pair.recipe == "a-recycling"
end
check("RS06", early_route and has_early and not has_late,
  "An earlier ordinary unlock wins over an alphabetically earlier later ordinary supplier")

progression_order_world.recipe_facts["z-ordinary"] = route_fact(
  "component", {{name = "missing", amount = 1}}, {enabled = false})
reset(progression_order_world)
local later_route = production.production_route_for_pack("order-pack")
local later_pairs = later_route and later_route.provenance.selected_research_unlock_pairs or {}
local retained_late = false
for _, pair in ipairs(later_pairs) do retained_late = retained_late or pair.recipe == "a-recycling" end
check("RS07", later_route and retained_late,
  "A failed earlier supplier retains the seeded later ordinary route")

local multiple_unlocker_world = require("prototypes.mir.core.deepcopy")(progression_order_world)
multiple_unlocker_world.techs.ZEarlierUnlock = multiple_unlocker_world.techs.OrdinaryUnlock
multiple_unlocker_world.techs.ZEarlierUnlock.effects = {{type = "unlock-recipe", recipe = "a-recycling"}}
multiple_unlocker_world.techs.ALaterUnlock = multiple_unlocker_world.techs.RecyclingUnlock
multiple_unlocker_world.techs.ALaterUnlock.prerequisites = {"ZEarlierUnlock"}
multiple_unlocker_world.techs.OrdinaryUnlock = nil
multiple_unlocker_world.techs.RecyclingUnlock = nil
reset(multiple_unlocker_world)
local multiple_unlocker_route = production.production_route_for_pack("order-pack")
local chosen_earlier_unlocker = false
for _, pair in ipairs(multiple_unlocker_route and multiple_unlocker_route.provenance.selected_research_unlock_pairs or {}) do
  chosen_earlier_unlocker = chosen_earlier_unlocker or (pair.recipe == "a-recycling" and pair.unlocker == "ZEarlierUnlock")
end
check("RS08", multiple_unlocker_route and chosen_earlier_unlocker,
  "One recipe with alternative unlockers selects the earlier proved technology")

-- An enabled outer recipe is only initial when every selected acquisition is
-- enabled. Its locked component routes remain actual required gates, rather
-- than becoming a false initial classification or an arbitrary outer unlock.
local function enabled_future_gate_world(options)
  options = options or {}
  local has_second_gate = options.singleton ~= true
  local outer_ingredients = {{name = "gate-component-a", amount = 1}}
  if has_second_gate then table.insert(outer_ingredients, {name = "gate-component-b", amount = 1}) end
  local techs = {
    GateOne = technology("starter-pack", "gate-component-a-recipe")
  }
  local recipe_prototypes = {
    ["starter-pack-recipe"] = {name = "starter-pack-recipe"},
    ["gated-pack-recipe"] = {name = "gated-pack-recipe"},
    ["gate-component-a-recipe"] = {name = "gate-component-a-recipe"}
  }
  local recipe_facts = {
    ["starter-pack-recipe"] = route_fact("starter-pack", {{name = "gate-ore", amount = 1}}),
    ["gated-pack-recipe"] = route_fact("gated-pack", outer_ingredients),
    ["gate-component-a-recipe"] = route_fact(
      "gate-component-a", {{name = "gate-ore", amount = 1}}, {enabled = false})
  }
  local producers = {
    ["starter-pack"] = {"starter-pack-recipe"},
    ["gated-pack"] = {"gated-pack-recipe"},
    ["gate-component-a"] = {"gate-component-a-recipe"}
  }
  local unlockers = { ["gate-component-a-recipe"] = {"GateOne"} }
  local items = {
    ["starter-pack"] = {type = "item"},
    ["gated-pack"] = {type = "item"},
    ["gate-component-a"] = {type = "item"}
  }
  if has_second_gate then
    techs.GateTwo = technology("starter-pack", "gate-component-b-recipe")
    if options.dependent then techs.GateTwo.prerequisites = {"GateOne"} end
    if options.invalid then techs.GateTwo.enabled = false end
    recipe_prototypes["gate-component-b-recipe"] = {name = "gate-component-b-recipe"}
    recipe_facts["gate-component-b-recipe"] = route_fact(
      "gate-component-b", {{name = "gate-ore", amount = 1}}, {enabled = false})
    producers["gate-component-b"] = {"gate-component-b-recipe"}
    unlockers["gate-component-b-recipe"] = {"GateTwo"}
    items["gate-component-b"] = {type = "item"}
  end
  return {
    item_prototypes = items,
    labs = {lab = {inputs = {"starter-pack", "gated-pack"}}},
    techs = techs,
    recipe_prototypes = recipe_prototypes,
    recipe_facts = recipe_facts,
    producers = producers,
    unlockers = unlockers,
    resources = { ["gate-ore"] = {minable = {result = "gate-ore", count = 1}} }
  }
end

-- Supply matching raw recipes and normalized fixture facts while exercising
-- the actual F200 consumer and science facade. The recipe index remains a
-- controlled input; this case does not qualify its production builder.
local function enabled_future_gate_consumer_world()
  local actual = enabled_future_gate_world()
  actual.recipe_prototypes = {
    ["starter-pack-recipe"] = {
      name = "starter-pack-recipe", enabled = true, category = "crafting",
      ingredients = {{name = "gate-ore", amount = 1}},
      results = {{type = "item", name = "starter-pack", amount = 1}}
    },
    ["gated-pack-recipe"] = {
      name = "gated-pack-recipe", enabled = true, category = "crafting",
      ingredients = {{name = "gate-component-a", amount = 1}, {name = "gate-component-b", amount = 1}},
      results = {{type = "item", name = "gated-pack", amount = 1}}
    },
    ["gate-component-a-recipe"] = {
      name = "gate-component-a-recipe", enabled = false, category = "crafting",
      ingredients = {{name = "gate-ore", amount = 1}},
      results = {{type = "item", name = "gate-component-a", amount = 1}}
    },
    ["gate-component-b-recipe"] = {
      name = "gate-component-b-recipe", enabled = false, category = "crafting",
      ingredients = {{name = "gate-ore", amount = 1}},
      results = {{type = "item", name = "gate-component-b", amount = 1}}
    }
  }
  return actual
end

reset(enabled_future_gate_world())
local multi_gate_status = production.pack_production_status("gated-pack", {})
local multi_gate_route = production.production_route_for_pack("gated-pack")
local multi_gate_prereqs = production.prereq_techs_for_science_pack("gated-pack")
check("MG01", multi_gate_status == "research" and multi_gate_route and multi_gate_route.initial == false
  and table.concat(multi_gate_route.unlockers, ",") == "GateOne,GateTwo"
  and table.concat(multi_gate_prereqs, ",") == "GateOne,GateTwo"
  and production.prereq_tech_for_science_pack("gated-pack") == nil,
  "An enabled future pack retains every selected inner unlocker through the plural planner gate contract")

reset(enabled_future_gate_world({dependent = true}))
local dependent_route = production.production_route_for_pack("gated-pack")
check("MG02", dependent_route and table.concat(dependent_route.unlockers, ",") == "GateTwo"
  and table.concat(dependent_route.prerequisite_closure, ",") == "GateOne"
  and #dependent_route.provenance.selected_research_unlock_pairs == 2
  and table.concat(production.prereq_techs_for_science_pack("gated-pack"), ",") == "GateTwo",
  "A dependent selected inner unlocker reduces its direct gate while retaining closure and pair proof")

reset(enabled_future_gate_world({singleton = true}))
check("MG03", table.concat(production.prereq_techs_for_science_pack("gated-pack"), ",") == "GateOne"
  and production.prereq_tech_for_science_pack("gated-pack") == "GateOne",
  "The legacy scalar prerequisite remains available for an exact singleton gate")

reset(enabled_future_gate_world({invalid = true}))
check("MG04", production.pack_production_status("gated-pack", {}) == "unreachable"
  and #production.prereq_techs_for_science_pack("gated-pack") == 0
  and production.prereq_tech_for_science_pack("gated-pack") == nil,
  "A disabled selected inner unlocker rejects the enabled future route")

reset(enabled_future_gate_world({singleton = true}))
local initial_callback_calls = 0
local strict_initial = feasibility.initial_recipe_witness("gated-pack-recipe", "gated-pack", {
  research_unlock_witness = function()
    initial_callback_calls = initial_callback_calls + 1
    return {kind = "fixture-research-witness"}
  end
})
local true_initial_callback_calls = 0
local true_initial = feasibility.initial_recipe_witness("starter-pack-recipe", "starter-pack", {
  research_unlock_witness = function()
    true_initial_callback_calls = true_initial_callback_calls + 1
    return {kind = "fixture-research-witness"}
  end
})
check("MG05", strict_initial == nil and initial_callback_calls == 0
  and true_initial ~= nil and true_initial_callback_calls == 0,
  "Strict and truly initial feasibility never invokes a research-unlock callback")

reset(enabled_future_gate_world())
local plural_first = table.concat(production.prereq_techs_for_science_pack("gated-pack"), ",")
local route_after_plural = production.production_route_for_pack("gated-pack")
reset(enabled_future_gate_world())
local route_first = production.production_route_for_pack("gated-pack")
local plural_after_route = table.concat(production.prereq_techs_for_science_pack("gated-pack"), ",")
world.techs.GateTwo.enabled = false
world.recipe_source_epoch = 2
check("MG06", plural_first == "GateOne,GateTwo" and route_after_plural
  and route_first and plural_after_route == plural_first
  and production.pack_production_status("gated-pack", {}) == "unreachable"
  and #production.prereq_techs_for_science_pack("gated-pack") == 0,
  "Plural gates are query-order stable and discard stale entries at the recipe-source epoch boundary")

local function policy_route(recipe, unlockers, prerequisite_closure)
  return {
    recipe = recipe,
    reachable = true,
    initial = false,
    unlockers = unlockers,
    prerequisite_closure = prerequisite_closure or {},
    science_burden = {},
    progression_key = {
      science_burden_count = 0,
      prerequisite_count = 0,
      unlock_depth = 0,
      research_count = 0,
      research_time = 0
    }
  }
end
local graph_preferred = route_policy.select({
  policy_route("one-gate", {"GateOne"}),
  policy_route("two-gates", {"GateTwo"}, {"GateOne"})
})
local deterministic_policy = route_policy.select({
  policy_route("later", {"GateOne", "GateTwo"}),
  policy_route("earlier", {"GateOne", "GateThree"})
})
check("MG07", graph_preferred and graph_preferred.recipe == "one-gate"
  and deterministic_policy and deterministic_policy.recipe == "earlier",
  "Route policy compares the complete required gate set and resolves equal routes by sorted gates")

reset(logistic_trace_world(
  'logistic-science-pack-from-self-cycle',
  route_fact('logistic-science-pack', {{name = 'logistic-science-pack', amount = 1}}, {enabled = false}),
  'trace-cycle-unlocker'
))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack')
logistic_candidate = only_candidate(logistic_projection, 'logistic-science-pack-from-self-cycle')
check('D06', logistic_candidate and logistic_candidate.first_failure.kind == 'technology'
  and logistic_candidate.first_failure.technology == 'trace-cycle-unlocker'
  and logistic_candidate.first_failure.reason == 'technology-cycle'
  and logistic_candidate.structural_route.status == 'rejected'
  and logistic_candidate.unlockers[1].status == 'not-evaluated'
  and production.pack_production_status('logistic-science-pack', {}) == 'unreachable',
  'An unseeded self-cycle stays unreachable with the concrete recursive technology witness: '
    .. serpent.line(logistic_candidate))

reset(logistic_trace_world(
  'logistic-science-pack-from-ore',
  route_fact('logistic-science-pack', {{name = 'trace-ore', amount = 1}}, {enabled = false}),
  'trace-self-lock-unlocker',
  {trace_ore = {minable = {result = 'trace-ore', count = 1}}}
))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack')
logistic_candidate = only_candidate(logistic_projection, 'logistic-science-pack-from-ore')
check('D07', logistic_candidate and logistic_candidate.structural_route.status == 'reachable'
  and logistic_candidate.first_failure.kind == 'technology'
  and logistic_candidate.first_failure.technology == 'trace-self-lock-unlocker'
  and logistic_candidate.first_failure.reason == 'science-self-lock-logistic-science-pack'
  and logistic_candidate.unlockers[1].status == 'rejected',
  'A structurally seeded candidate retains its rejecting self-lock technology')

-- A rejected sibling variant is not part of the selected structural route.
-- The source-fed second variant reaches the sole unlocker, whose science cost
-- consumes the same pack. The reported first failure must therefore be that
-- self-lock, never the discarded first variant's machine category.
reset(logistic_trace_world(
  'logistic-science-pack-transactional-variants',
  route_fact('logistic-science-pack', nil, {
    enabled = false,
    variants = {
      {
        name = 'discarded-missing-category', enabled = false,
        categories = {'missing-crafting-category'}, ingredients = {},
        results = {{name = 'logistic-science-pack', amount = 1}}
      },
      {
        name = 'selected-source-fed-route', enabled = false,
        categories = {'crafting'}, ingredients = {{name = 'trace-ore', amount = 1}},
        results = {{name = 'logistic-science-pack', amount = 1}}
      }
    }
  }),
  'trace-transactional-self-lock',
  {trace_ore = {minable = {result = 'trace-ore', count = 1}}}
))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack')
logistic_candidate = only_candidate(logistic_projection, 'logistic-science-pack-transactional-variants')
check('D08', logistic_candidate and logistic_candidate.structural_route.status == 'reachable'
  and logistic_candidate.first_failure.kind == 'technology'
  and logistic_candidate.first_failure.reason == 'science-self-lock-logistic-science-pack'
  and logistic_candidate.first_failure.kind ~= 'category',
  'A later reachable variant discards provisional structural failures before the true self-lock is selected')

local function projection_truncated(projection, reason)
  for _, candidate in ipairs((projection and projection.truncation or {}).truncated or {}) do
    if candidate == reason then return true end
  end
  return false
end

local function projection_visits_within(projection, limit)
  local truncation = projection and projection.truncation or {}
  local usage = truncation.usage or {}
  return truncation.stopped == true and type(usage.visits) == 'number' and usage.visits <= limit
end

reset({
  item_prototypes = {['logistic-science-pack'] = {type = 'item'}},
  labs = {lab = {inputs = {'logistic-science-pack'}}},
  techs = {
    ['a-budget-unlocker'] = technology('logistic-science-pack', 'a-logistic-budget'),
    ['b-budget-unlocker'] = technology('logistic-science-pack', 'b-logistic-budget')
  },
  recipe_prototypes = {
    ['a-logistic-budget'] = {name = 'a-logistic-budget'},
    ['b-logistic-budget'] = {name = 'b-logistic-budget'}
  },
  recipe_facts = {
    ['a-logistic-budget'] = route_fact('logistic-science-pack', {}, {enabled = false, categories = {'missing-a'}}),
    ['b-logistic-budget'] = route_fact('logistic-science-pack', {}, {enabled = false, categories = {'missing-b'}})
  },
  producers = {['logistic-science-pack'] = {'a-logistic-budget', 'b-logistic-budget'}},
  unlockers = {
    ['a-logistic-budget'] = {'a-budget-unlocker'},
    ['b-logistic-budget'] = {'b-budget-unlocker'}
  }
})
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 1, nodes = 1024, depth = 32, bytes = 4096}
})
check('D09', logistic_projection.candidate_count == 2 and #logistic_projection.candidates == 1
  and projection_truncated(logistic_projection, 'candidates'),
  'Candidate output is capped deterministically with explicit truncation metadata: ' .. serpent.line(logistic_projection))

reset(logistic_trace_world(
  'logistic-science-pack-from-self-cycle',
  route_fact('logistic-science-pack', {{name = 'logistic-science-pack', amount = 1}}, {enabled = false}),
  'trace-cycle-unlocker'
))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 1, depth = 8, bytes = 4096}
})
check('D10', projection_truncated(logistic_projection, 'nodes'),
  'Node observations stop at the configured deterministic cap')

reset(logistic_trace_world(
  'logistic-science-pack-from-depth-chain',
  route_fact('logistic-science-pack', {{name = 'trace-middle', amount = 1}}, {enabled = false}),
  'trace-depth-unlocker'
))
world.recipe_prototypes['trace-middle-from-terminal'] = {name = 'trace-middle-from-terminal'}
world.recipe_facts['trace-middle-from-terminal'] = route_fact('trace-middle', {{name = 'trace-terminal', amount = 1}})
world.producers['trace-middle'] = {'trace-middle-from-terminal'}
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 32, depth = 1, bytes = 4096}
})
check('D11', projection_truncated(logistic_projection, 'depth'),
  'Nested acquisition observations stop at the configured deterministic depth')

reset(logistic_trace_world(
  'logistic-science-pack-from-missing-category',
  route_fact('logistic-science-pack', {}, {enabled = false, categories = {'missing-crafting-category'}}),
  'trace-category-unlocker'
))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 32, depth = 8, bytes = 1}
})
check('D12', #logistic_projection.candidates == 0 and logistic_projection.first_failure.kind == 'budget'
  and projection_truncated(logistic_projection, 'bytes'),
  'Byte-limited projections omit oversized trace output with stable budget metadata')

-- The work counter is deliberately not transactional.  A broad OR fan-out
-- must stop before inspecting every sibling, even though discarded trace
-- branches are rolled back to retain only one selected failure tree.
local function wide_budget_world(width)
  local recipe_facts, recipe_prototypes, recipes = {}, {}, {}
  for index = 1, width do
    local name = 'wide-logistic-' .. index
    recipe_facts[name] = route_fact('logistic-science-pack', {{name = 'wide-missing-' .. index, amount = 1}}, {
      enabled = false
    })
    recipe_prototypes[name] = {name = name}
    table.insert(recipes, name)
  end
  return {
    item_prototypes = {['logistic-science-pack'] = {type = 'item'}},
    labs = {lab = {inputs = {'logistic-science-pack'}}},
    techs = {}, recipe_prototypes = recipe_prototypes, recipe_facts = recipe_facts,
    producers = {['logistic-science-pack'] = recipes}, unlockers = {}
  }
end

reset(wide_budget_world(24))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 24, nodes = 8, depth = 32, bytes = 4096}
})
check('D13', projection_truncated(logistic_projection, 'nodes')
  and projection_visits_within(logistic_projection, 8),
  'A wide candidate fan-out cannot consume more irreversible visits than its node cap')

-- A long AND chain exercises the recursive descent guard separately from a
-- wide recipe list. Its trace may roll back, but its work budget cannot.
local function deep_budget_world(depth)
  local recipe_facts, recipe_prototypes, producers = {}, {}, {
    ['logistic-science-pack'] = {'deep-logistic'}
  }
  recipe_facts['deep-logistic'] = route_fact('logistic-science-pack', {{name = 'deep-1', amount = 1}}, {
    enabled = false
  })
  recipe_prototypes['deep-logistic'] = {name = 'deep-logistic'}
  for index = 1, depth do
    local item_name = 'deep-' .. index
    local recipe_name = 'deep-recipe-' .. index
    local ingredients = index == depth and {{name = 'deep-terminal', amount = 1}}
      or {{name = 'deep-' .. (index + 1), amount = 1}}
    recipe_facts[recipe_name] = route_fact(item_name, ingredients)
    recipe_prototypes[recipe_name] = {name = recipe_name}
    producers[item_name] = {recipe_name}
  end
  return {
    item_prototypes = {['logistic-science-pack'] = {type = 'item'}},
    labs = {lab = {inputs = {'logistic-science-pack'}}},
    techs = {}, recipe_prototypes = recipe_prototypes, recipe_facts = recipe_facts,
    producers = producers, unlockers = {}
  }
end

reset(deep_budget_world(24))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 12, depth = 32, bytes = 4096}
})
check('D14', projection_truncated(logistic_projection, 'nodes')
  and projection_visits_within(logistic_projection, 12),
  'A deep recursive acquisition chain cannot consume more irreversible visits than its node cap')

-- A bounded status pass is not allowed to turn a partial prefix of a recipe
-- list into a negative conclusion. The only valid route is deliberately last;
-- a narrow diagnostic budget must report indeterminate while normal admission
-- still finds the later initial route.
local function late_valid_route_world(invalid_count)
  local recipe_facts, recipe_prototypes, recipes = {}, {}, {}
  for index = 1, invalid_count do
    local name = string.format('a-late-invalid-%02d', index)
    recipe_facts[name] = route_fact('logistic-science-pack', {}, {
      enabled = false, categories = {'missing-late-category'}
    })
    recipe_prototypes[name] = {name = name}
    table.insert(recipes, name)
  end
  recipe_facts['z-late-valid'] = route_fact('logistic-science-pack', {{name = 'late-ore', amount = 1}})
  recipe_prototypes['z-late-valid'] = {name = 'z-late-valid'}
  table.insert(recipes, 'z-late-valid')
  return {
    item_prototypes = {['logistic-science-pack'] = {type = 'item'}},
    labs = {lab = {inputs = {'logistic-science-pack'}}},
    techs = {}, recipe_prototypes = recipe_prototypes, recipe_facts = recipe_facts,
    producers = {['logistic-science-pack'] = recipes}, unlockers = {},
    resources = {late_ore = {minable = {result = 'late-ore', count = 1}}}
  }
end

reset(late_valid_route_world(24))
check('D15', production.pack_production_status('logistic-science-pack', {}) == 'initial',
  'Normal admission reaches a valid initial production route after invalid earlier alternatives')
before_projection = context_observation_snapshot()
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 24, nodes = 8, depth = 32, bytes = 4096}
})
check('D15A', logistic_projection and logistic_projection.status == 'indeterminate'
  and logistic_projection.first_failure.reason == 'diagnostic-work-budget-exhausted'
  and #logistic_projection.candidates == 0 and projection_truncated(logistic_projection, 'nodes')
  and projection_visits_within(logistic_projection, 8)
  and context_observation_unchanged(before_projection),
  'A capped status pass reports indeterminate rather than falsely rejecting a late valid route')

-- Depth applies to technology prerequisites as well as recipe acquisition.
-- The root route is structurally seeded, but the short closure cap must stop
-- before a deep prerequisite chain can be misreported as a science rejection.
local function deep_technology_chain_world(depth)
  local techs = {}
  for index = 1, depth do
    local name = string.format('tech-depth-%02d', index)
    techs[name] = {
      enabled = true,
      research_trigger = {type = 'craft-item', item = 'lab'},
      prerequisites = index < depth and {string.format('tech-depth-%02d', index + 1)} or nil
    }
  end
  techs['z-tech-depth-root'] = technology('logistic-science-pack', 'tech-depth-logistic-recipe')
  techs['z-tech-depth-root'].prerequisites = {'tech-depth-01'}
  return {
    item_prototypes = {['logistic-science-pack'] = {type = 'item'}},
    labs = {lab = {inputs = {'logistic-science-pack'}}},
    techs = techs,
    recipe_prototypes = {['tech-depth-logistic-recipe'] = {name = 'tech-depth-logistic-recipe'}},
    recipe_facts = {
      ['tech-depth-logistic-recipe'] = route_fact(
        'logistic-science-pack', {{name = 'tech-depth-ore', amount = 1}}, {enabled = false})
    },
    producers = {['logistic-science-pack'] = {'tech-depth-logistic-recipe'}},
    unlockers = {['tech-depth-logistic-recipe'] = {'z-tech-depth-root'}},
    resources = {tech_depth_ore = {minable = {result = 'tech-depth-ore', count = 1}}}
  }
end

reset(deep_technology_chain_world(12))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 64, depth = 2, bytes = 4096}
})
check('D16', logistic_projection and logistic_projection.status == 'indeterminate'
  and logistic_projection.first_failure.reason == 'diagnostic-work-budget-exhausted'
  and projection_truncated(logistic_projection, 'depth')
  and logistic_projection.truncation.usage.maximum_depth <= 2,
  'Technology-prerequisite recursion enforces the diagnostic depth cap before false rejection')

-- Every nested fan-out below is work-accounted. These worlds force the cap in
-- one inner collection at a time and require indeterminate, never a rejected
-- pack conclusion, when the collection is incomplete.
local function fanout_lab_input_world(width)
  local items, inputs = {['logistic-science-pack'] = {type = 'item'}}, {}
  for index = 1, width do
    local name = string.format('lab-fanout-%02d', index)
    items[name] = {type = 'item'}
    table.insert(inputs, name)
  end
  table.insert(inputs, 'logistic-science-pack')
  return {
    item_prototypes = items,
    labs = {lab = {inputs = inputs}}, techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {}
  }
end

-- Eight inputs fit in the collection budget, but the target pack is last.
-- The same fixed cap therefore reaches the separate input-to-pack comparison
-- loop and stops there rather than merely proving the outer collection loop.
reset(fanout_lab_input_world(7))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 12, depth = 32, bytes = 4096}
})
check('D17', logistic_projection and logistic_projection.status == 'indeterminate'
  and projection_truncated(logistic_projection, 'nodes') and projection_visits_within(logistic_projection, 12),
  'Lab-input enumeration and pack comparison fan-outs consume bounded irreversible work')

local function fanout_recipe_result_world(width)
  local results = {}
  for index = 1, width do table.insert(results, {name = 'recipe-result-' .. index, amount = 1}) end
  table.insert(results, {name = 'logistic-science-pack', amount = 1})
  return logistic_trace_world(
    'fanout-recipe-results',
    route_fact('logistic-science-pack', {}, {enabled = false, results = results}),
    'fanout-result-unlocker'
  )
end

reset(fanout_recipe_result_world(24))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 8, depth = 32, bytes = 4096}
})
check('D18', logistic_projection and logistic_projection.status == 'indeterminate'
  and projection_truncated(logistic_projection, 'nodes') and projection_visits_within(logistic_projection, 8),
  'Recipe-result identity fan-outs consume bounded irreversible work')

local function fanout_minable_result_world(width)
  local results = {}
  for index = 1, width do table.insert(results, {name = 'minable-result-' .. index, amount = 1}) end
  return {
    item_prototypes = {['logistic-science-pack'] = {type = 'item'}},
    labs = {lab = {inputs = {'logistic-science-pack'}}}, techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {},
    resources = {fanout_resource = {minable = {results = results}}}
  }
end

reset(fanout_minable_result_world(24))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 8, depth = 32, bytes = 4096}
})
check('D19', logistic_projection and logistic_projection.status == 'indeterminate'
  and projection_truncated(logistic_projection, 'nodes') and projection_visits_within(logistic_projection, 8),
  'Minable-result fan-outs consume bounded irreversible work')

local function fanout_technology_ingredient_world(width)
  local ingredients = {}
  for _ = 1, width do table.insert(ingredients, {name = 'logistic-science-pack', amount = 1}) end
  local root = technology('logistic-science-pack', 'fanout-tech-ingredients')
  root.unit.ingredients = ingredients
  return {
    item_prototypes = {['logistic-science-pack'] = {type = 'item'}},
    labs = {lab = {inputs = {'logistic-science-pack'}}},
    techs = {['fanout-tech-unlocker'] = root},
    recipe_prototypes = {['fanout-tech-ingredients'] = {name = 'fanout-tech-ingredients'}},
    recipe_facts = {
      ['fanout-tech-ingredients'] = route_fact(
        'logistic-science-pack', {{name = 'fanout-tech-ore', amount = 1}}, {enabled = false})
    },
    producers = {['logistic-science-pack'] = {'fanout-tech-ingredients'}},
    unlockers = {['fanout-tech-ingredients'] = {'fanout-tech-unlocker'}},
    resources = {fanout_tech_ore = {minable = {result = 'fanout-tech-ore', count = 1}}}
  }
end

reset(fanout_technology_ingredient_world(48))
logistic_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 56, depth = 32, bytes = 4096}
})
check('D20', logistic_projection and logistic_projection.status == 'indeterminate'
  and projection_truncated(logistic_projection, 'nodes') and projection_visits_within(logistic_projection, 56),
  'Technology science-ingredient enumeration consumes bounded irreversible work')

local function bounded_observer(limit)
  local observer = {visits = 0, limit = limit, stopped = false}
  function observer:is_stopped() return self.stopped end
  function observer:reserve_visit(_)
    if self.stopped or self.visits >= self.limit then
      self.stopped = true
      return false
    end
    self.visits = self.visits + 1
    return true
  end
  return observer
end

-- The technology's sole unlock recipe produces its own science pack, but the
-- output identity is deliberately after a wide result list. This exercises
-- recipe_unlock_facts.recipe_outputs_item in the self-lock path rather than
-- only the route-feasibility result scan covered by D18.
local function self_lock_output_fanout_world(width)
  local results = {}
  for index = 1, width do table.insert(results, {type = 'item', name = 'self-lock-result-' .. index, amount = 1}) end
  table.insert(results, {type = 'item', name = 'logistic-science-pack', amount = 1})
  local fact = route_fact('logistic-science-pack', {}, {enabled = false, results = results})
  -- recipe_outputs_item consumes canonical typed result identities first.
  -- Preserve that shape here so this is not accidentally satisfied by the
  -- route_fact convenience result_names field.
  fact.result_identities = results
  return {
    item_prototypes = {['logistic-science-pack'] = {type = 'item'}},
    labs = {lab = {inputs = {'logistic-science-pack'}}},
    techs = {['self-lock-result-unlocker'] = technology('logistic-science-pack', 'self-lock-result-recipe')},
    recipe_prototypes = {['self-lock-result-recipe'] = {name = 'self-lock-result-recipe'}},
    recipe_facts = {
      ['self-lock-result-recipe'] = fact
    },
    producers = {['logistic-science-pack'] = {'self-lock-result-recipe'}},
    unlockers = {['self-lock-result-recipe'] = {'self-lock-result-unlocker'}}
  }
end

reset(self_lock_output_fanout_world(24))
local self_lock_result_observer = bounded_observer(8)
check('D21', not recipe_unlock_facts.recipe_outputs_item(
  'self-lock-result-recipe',
  'logistic-science-pack',
  self_lock_result_observer
) and self_lock_result_observer.stopped and self_lock_result_observer.visits <= 8,
  'Self-lock result identity scanning is bounded before a late pack output')
local self_lock_reason_observer = bounded_observer(8)
check('D21A', researchability.reason_with_context('self-lock-result-unlocker', {
  visiting_packs = {},
  visiting_technologies = {},
  unlock_recipe_name = 'self-lock-result-recipe',
  diagnostic_observer = self_lock_reason_observer
}) == 'diagnostic-budget-exhausted'
  and self_lock_reason_observer.stopped and self_lock_reason_observer.visits <= 8,
  'The same bounded result scan is reached through the technology self-lock path')

reset(same_unlocker_world(false))
local same_unlocker_a_cold = production.pack_production_status("A", {})
local same_unlocker_b_warm = production.pack_production_status("B", {})
check("U01", same_unlocker_a_cold == "research" and same_unlocker_b_warm == "research",
  "Nested intermediates may reuse one proved unlocker through distinct recipe pairs")
before_projection = context_observation_snapshot()
check("U01A", production.pack_production_rejection_projection("A") == nil
  and context_observation_unchanged(before_projection),
  "A successful same-unlocker route remains projection-free and observationally isolated")
reset(same_unlocker_world(true))
check("U02", production.pack_production_status("A", {}) == "unreachable"
  and production.pack_production_status("B", {}) == "unreachable",
  "A same-unlocker, unseeded A-to-B-to-A cycle remains rejected")
local unseeded_projection = production.pack_production_rejection_projection("A", {
  limits = {candidates = 8, nodes = 2048, depth = 32, bytes = 16384}
})
check("U02A", unseeded_projection and unseeded_projection.status == "unreachable"
  and #unseeded_projection.candidates == 1
  and unseeded_projection.candidates[1].unlockers[1].technology == "SharedUnlock"
  and unseeded_projection.candidates[1].structural_route.status == "rejected"
  and unseeded_projection.candidates[1].unlockers[1].status == "not-evaluated"
  and unseeded_projection.candidates[1].first_failure.kind == "cycle"
  and unseeded_projection.candidates[1].first_failure.reason == "active-unlock-pair"
  and unseeded_projection.candidates[1].first_failure.recipe == "B-from-A"
  and unseeded_projection.candidates[1].first_failure.technology == "SharedUnlock",
  "The diagnostic projection identifies the active recipe/unlocker pair closing the unseeded cycle: " .. serpent.line(unseeded_projection))
reset(same_unlocker_world(false))
local same_unlocker_b_cold = production.pack_production_status("B", {})
local same_unlocker_a_warm = production.pack_production_status("A", {})
check("U03", same_unlocker_b_cold == "research" and same_unlocker_a_warm == "research",
  "Nested unlock-pair resolution is invariant to cold query order and warm cache reuse")
before_projection = context_observation_snapshot()
check("U03A", production.pack_production_rejection_projection("B") == nil
  and context_observation_unchanged(before_projection),
  "Query order and warm caches remain unchanged when a successful route is observed")
reset(fluid_intermediate_world())
check("U04", production.pack_production_status("fluid_pack", {}) == "research",
  "A seeded research-unlocked fluid intermediate retains its typed output route")
before_projection = context_observation_snapshot()
check("U04A", production.pack_production_rejection_projection("fluid_pack") == nil
  and context_observation_unchanged(before_projection),
  "Typed seeded fluid routes remain projection-free without mutating root caches or telemetry")

-- One pack may expose many producer recipes which all reach the same locked
-- intermediate. The technology decision is contextual, so it cannot use the
-- global pack cache; it can nevertheless be reused inside the one exact
-- route query when recipe, unlocker, and active visitation sets are identical.
local function contextual_reason_fanout_world(width)
  local facts, prototypes, pack_recipes = {
    ["shared-inner-recipe"] = route_fact(
      "shared-inner", {{name = "shared-ore", amount = 1}}, {enabled = false})
  }, { ["shared-inner-recipe"] = {name = "shared-inner-recipe"} }, {}
  for index = 1, width do
    local name = string.format("fanout-pack-%02d", index)
    facts[name] = route_fact("fanout-pack", {{name = "shared-inner", amount = 1}})
    prototypes[name] = {name = name}
    table.insert(pack_recipes, name)
  end
  return {
    item_prototypes = {
      ["fanout-pack"] = {type = "item"},
      ["shared-inner"] = {type = "item"}
    },
    labs = {lab = {inputs = {"fanout-pack"}}},
    techs = {SharedInnerUnlock = {
      enabled = true,
      research_trigger = {type = "craft-item", item = "lab"},
      effects = {{type = "unlock-recipe", recipe = "shared-inner-recipe"}}
    }},
    recipe_prototypes = prototypes,
    recipe_facts = facts,
    producers = {
      ["fanout-pack"] = pack_recipes,
      ["shared-inner"] = {"shared-inner-recipe"}
    },
    unlockers = {["shared-inner-recipe"] = {"SharedInnerUnlock"}},
    resources = {shared_ore = {minable = {result = "shared-ore", count = 1}}}
  }
end

reset(contextual_reason_fanout_world(24))
local contextual_reason_calls = 0
context.services["science.technology_researchability_reason"] = function(_, reason_context)
  contextual_reason_calls = contextual_reason_calls + 1
  check("U05A", reason_context.visiting_packs["fanout-pack"] == true
    and reason_context.unlock_recipe_name == "shared-inner-recipe",
    "The query-local memo is bound to the active pack and exact unlock recipe")
  return "fixture-contextual-rejection"
end
check("U05", production.pack_production_status("fanout-pack", {}) == "unreachable"
  and contextual_reason_calls == 1,
  "Repeated producer fan-out reuses one exact contextual technology rejection; calls=" .. contextual_reason_calls)

-- A reachable unlocker can still have an impossible ingredient route. Reuse
-- that completed rejection for identical sibling queries, rather than proving
-- the same unavailable intermediate once per outer producer.
local rejected_fanout_world = contextual_reason_fanout_world(24)
rejected_fanout_world.resources = {}
reset(rejected_fanout_world)
local saved_recipe_witness = feasibility.recipe_witness
local rejected_inner_calls = 0
feasibility.recipe_witness = function(recipe_name, ...)
  if recipe_name == "shared-inner-recipe" then rejected_inner_calls = rejected_inner_calls + 1 end
  return saved_recipe_witness(recipe_name, ...)
end
local rejected_fanout_status = production.pack_production_status("fanout-pack", {})
feasibility.recipe_witness = saved_recipe_witness
check("U06", rejected_fanout_status == "unreachable" and rejected_inner_calls == 1,
  "Identical failed unlock/acquisition contexts reuse one completed route rejection; calls=" .. rejected_inner_calls)

-- B first fails while A is active in an enabled cycle. After that branch has
-- failed, a sibling asks for B without A active and can use A's independent
-- seed. A name-only negative cache would incorrectly hide this valid route.
local function negative_context_world(seeded)
  return {
    item_prototypes = {["context-pack"] = {type = "item"}},
    labs = {lab = {inputs = {"context-pack"}}},
    techs = {UnlockB = {enabled = true, research_trigger = {type = "craft-item", item = "lab"},
      effects = {{type = "unlock-recipe", recipe = "locked-B"}}}},
    recipe_prototypes = {
      ["a-failing-root"] = {name = "a-failing-root"}, ["z-success-root"] = {name = "z-success-root"},
      ["a-loop-A"] = {name = "a-loop-A"}, ["z-seed-A"] = {name = "z-seed-A"},
      ["locked-B"] = {name = "locked-B"}
    },
    recipe_facts = {
      ["a-failing-root"] = route_fact("context-pack", {{name = "A", amount = 1}, {name = "missing-root", amount = 1}}),
      ["z-success-root"] = route_fact("context-pack", {{name = "B", amount = 1}}),
      ["a-loop-A"] = route_fact("A", {{name = "B", amount = 1}}),
      ["z-seed-A"] = route_fact("A", {{name = "seed-ore", amount = 1}}),
      ["locked-B"] = route_fact("B", {{name = "A", amount = 1}}, {enabled = false})
    },
    producers = {["context-pack"] = {"a-failing-root", "z-success-root"},
      A = {"a-loop-A", "z-seed-A"}, B = {"locked-B"}},
    unlockers = {["locked-B"] = {"UnlockB"}},
    resources = seeded and {seed = {minable = {result = "seed-ore", count = 1}}} or {}
  }
end
reset(negative_context_world(true))
check("U07", production.pack_production_status("context-pack", {}) == "research",
  "A failed active-identity context cannot poison a later independently seeded sibling")
reset(negative_context_world(false))
check("U08", production.pack_production_status("context-pack", {}) == "unreachable",
  "The matching unseeded cycle remains unreachable after negative memoization")

reset({
  item_prototypes = {["memo-pack"] = {type = "item"}},
  labs = {lab = {inputs = {"memo-pack"}}},
  techs = {MemoUnlock = {enabled = true, unit = {count = 1, time = 1, ingredients = {{"memo-pack", 1}}}}},
  recipe_prototypes = {ordinary_one = {name = "ordinary_one"}, ordinary_two = {name = "ordinary_two"},
    self_pack = {name = "self_pack"}, seed_pack = {name = "seed_pack"}},
  recipe_facts = {ordinary_one = route_fact("ordinary-one"), ordinary_two = route_fact("ordinary-two"),
    self_pack = route_fact("memo-pack", {}, {enabled = false}), seed_pack = route_fact("memo-pack")},
  producers = {["memo-pack"] = {"seed_pack"}}, unlockers = {}, resources = {}
})
check("U09", production.pack_production_status("memo-pack", {}) == "initial",
  "The mechanism memo fixture starts with a real independently proved pack root")
local mechanism_memo, mechanism_calls = {}, 0
context.services["science.pack_production_status"] = function(...)
  mechanism_calls = mechanism_calls + 1
  return production.pack_production_status(...)
end
local ordinary_one_reason = researchability.reason_with_context("MemoUnlock", {
  unlock_recipe_name = "ordinary_one", visiting_packs = {}, visiting_technologies = {}, mechanism_memo = mechanism_memo})
local ordinary_two_reason = researchability.reason_with_context("MemoUnlock", {
  unlock_recipe_name = "ordinary_two", visiting_packs = {}, visiting_technologies = {}, mechanism_memo = mechanism_memo})
check("U10", ordinary_one_reason == nil and ordinary_two_reason == nil and mechanism_calls == 1,
  "Distinct ordinary recipes share one researchability evaluation only after its science roots are proved")
local independent_calls = 0
context.services["science.independent_pack_acquisition_witness"] = function()
  independent_calls = independent_calls + 1
  return nil
end
check("U11", researchability.reason_with_context("MemoUnlock", {
  unlock_recipe_name = "self_pack", visiting_packs = {}, visiting_technologies = {}, mechanism_memo = mechanism_memo})
    == "science-self-lock-memo-pack" and independent_calls == 1,
  "A self-producing recipe still asks the independent route service and cannot borrow an ordinary recipe's result")
check("U12", researchability.reason_with_context("MemoUnlock", {
  unlock_recipe_name = "ordinary_two", visiting_packs = {["memo-pack"] = true}, visiting_technologies = {}, mechanism_memo = mechanism_memo})
    == "unreachable-science-memo-pack",
  "A changed active pack boundary cannot borrow a successful mechanism result")
check("U13", researchability.reason_with_context("MemoUnlock", {
  unlock_recipe_name = "ordinary_two", visiting_packs = {}, visiting_technologies = {MemoUnlock = true}, mechanism_memo = mechanism_memo})
    == "technology-cycle",
  "A changed active technology boundary retains its cycle rejection")
world.recipe_source_epoch = 2
world.producers["memo-pack"] = {}
check("U14", researchability.reason_with_context("MemoUnlock", {
  unlock_recipe_name = "ordinary_one", visiting_packs = {}, visiting_technologies = {}, mechanism_memo = mechanism_memo})
    == "unreachable-science-memo-pack",
  "A source epoch change invalidates the old root-qualified mechanism answer")

world.recipe_source_epoch = 1
world.producers["memo-pack"] = {"seed_pack"}
reset(world)
local cold_mechanism_memo, cold_mechanism_calls = {}, 0
context.services["science.pack_production_status"] = function(...)
  cold_mechanism_calls = cold_mechanism_calls + 1
  return production.pack_production_status(...)
end
local cold_reasons = {}
local cold_first_reason = researchability.reason_with_context("MemoUnlock", {
  unlock_recipe_name = "ordinary_one", visiting_packs = {}, visiting_technologies = {}, mechanism_memo = cold_mechanism_memo})
local cold_root_unresolved = context:state_view("science_pack_production").entries["memo-pack"] == nil
local cold_root_status = production.pack_production_status("memo-pack", {})
cold_reasons[1] = cold_first_reason or false
for _, recipe_name in ipairs({"ordinary_two", "ordinary_one"}) do
  cold_reasons[#cold_reasons + 1] = researchability.reason_with_context("MemoUnlock", {
    unlock_recipe_name = recipe_name, visiting_packs = {}, visiting_technologies = {}, mechanism_memo = cold_mechanism_memo}) or false
end
check("U15", cold_root_unresolved and cold_root_status == "initial"
  and cold_reasons[1] == false and cold_reasons[2] == false and cold_reasons[3] == false
  and cold_mechanism_calls == 2,
  "The unresolved root bypasses mechanism sharing; only its subsequent proved-root evaluation may be reused")

-- The bounded status pass needs exactly four visits to establish that this
-- physical lab input has no recipe. An old trace then repeated the existence
-- scan, stopped on visit five, and incorrectly called the same pack non-lab.
local function exact_cap_no_recipe_world()
  return {
    item_prototypes = {['logistic-science-pack'] = {type = 'item'}},
    labs = {lab = {inputs = {'logistic-science-pack'}}},
    techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {}
  }
end

reset(exact_cap_no_recipe_world())
local exact_cap_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 4, depth = 32, bytes = 4096}
})
check('D25', exact_cap_projection and exact_cap_projection.status == 'unreachable'
  and exact_cap_projection.first_failure.reason == 'no-pack-recipe'
  and exact_cap_projection.truncation.stopped == false
  and exact_cap_projection.truncation.usage.visits == 4,
  'An exactly capped root existence fact is reused without a false no-lab trace failure')

-- Trace collection still may need one more fact lookup. Its exhaustion must
-- have an explicit outcome, not return nil after the root query was already
-- proven unreachable. The temporary controlled facade charges one lookup in
-- each phase to isolate that boundary.
reset(exact_cap_no_recipe_world())
local saved_pack_recipe_status = recipe_unlock_facts.pack_recipe_status
recipe_unlock_facts.pack_recipe_status = function(pack_name, observer)
  if observer and type(observer.reserve_visit) == 'function' then observer:reserve_visit(0) end
  return {pack_name = pack_name, has_recipe = false, initially_available = false, recipes = {}}
end
local trace_exhaustion_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 5, depth = 32, bytes = 4096}
})
recipe_unlock_facts.pack_recipe_status = saved_pack_recipe_status
check('D25A', trace_exhaustion_projection and trace_exhaustion_projection.status == 'indeterminate'
  and trace_exhaustion_projection.first_failure.reason == 'diagnostic-work-budget-exhausted'
  and projection_truncated(trace_exhaustion_projection, 'nodes')
  and projection_visits_within(trace_exhaustion_projection, 5),
  'Trace-stage recipe-status exhaustion is explicit indeterminate rather than nil')

-- Reload the actual lab and recipe-facts source for the assertions below. The
-- established planner worlds above intentionally stub recipe facts, so they
-- cannot prove that a fresh diagnostic avoids its normal full-index builder.
for _, module_name in ipairs({
  'prototypes.mir.index.recipe_facts',
  'prototypes.mir.index.recipe_unlocks',
  'prototypes.mir.capabilities.science_integration.pack_registry',
  'prototypes.mir.capabilities.science_integration.recipe_unlock_facts',
  'prototypes.mir.capabilities.science_integration.recipe_route_feasibility',
  'prototypes.mir.capabilities.science_integration.technology_researchability',
  'prototypes.mir.capabilities.science_integration.pack_production_reachability',
  'prototypes.mir.capabilities.science_integration.lab_compatibility'
}) do
  package.loaded[module_name] = nil
end
stub('prototypes.mir.settings.effective', {get = function() return 'reduce' end})
local actual_lab_compatibility = require('prototypes.mir.capabilities.science_integration.lab_compatibility')

world = {item_prototypes = {}, labs = {lab = {inputs = {'lab-pack-1', 'lab-pack-2', 'lab-pack-3', 'lab-pack-4'}}}}
data.raw = {
  lab = world.labs,
  technology = {},
  recipe = {},
  character = {player = {crafting_categories = {'crafting'}}},
  resource = {}, tree = {}, ['offshore-pump'] = {}, surface = {}, ['space-location'] = {}, planet = {}
}
local lab_comparison_observer = bounded_observer(11)
check('D22', not actual_lab_compatibility.valid_research_ingredients({
  {name = 'lab-pack-1', amount = 1},
  {name = 'lab-pack-2', amount = 1},
  {name = 'lab-pack-3', amount = 1},
  {name = 'lab-pack-4', amount = 1}
}, lab_comparison_observer) and lab_comparison_observer.stopped and lab_comparison_observer.visits <= 11,
  'Actual any_lab_accepts_all/lab_accepts_all input and pack comparisons are bounded')

-- Build the controlled parent index once, erase its telemetry, and
-- run a capped projection. The observation must borrow that exact immutable
-- snapshot; a missing borrow would rebuild recipe facts in the fresh context
-- and recreate recipe-index telemetry before the cap can stop traversal.
world = {
  item_prototypes = {['logistic-science-pack'] = {type = 'item'}},
  labs = {lab = {inputs = {'logistic-science-pack'}}},
  techs = {},
  recipe_prototypes = {
    ['real-index-logistic-recipe'] = {
      type = 'recipe',
      name = 'real-index-logistic-recipe',
      enabled = false,
      ingredients = {},
      results = {{type = 'item', name = 'logistic-science-pack', amount = 1}}
    }
  }
}
data.raw = {
  item = world.item_prototypes,
  lab = world.labs,
  technology = world.techs,
  recipe = world.recipe_prototypes,
  character = {player = {crafting_categories = {'crafting'}}},
  resource = {}, tree = {}, ['offshore-pump'] = {}, surface = {}, ['space-location'] = {}, planet = {}
}
active_context = nil
context = new_context()
local fixture_recipe_facts = require('prototypes.mir.index.recipe_facts')
local parent_recipe_index = fixture_recipe_facts.index_view()
local parent_recipe_source = context.states.recipe_source
local parent_recipe_index_epoch = context.epochs.recipe_index
local parent_recipe_source_epoch = context.epochs.recipe_source
-- The prebuild is intentional setup. Any telemetry or index created after
-- this reset is attributable to the diagnostic itself.
context.states.compiler_telemetry = nil
context.epochs.compiler_telemetry = nil
last_created_context = nil
production = require('prototypes.mir.capabilities.science_integration.pack_production_reachability')
local real_source_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 5, depth = 32, bytes = 4096}
})
check('D23', real_source_projection and real_source_projection.status == 'indeterminate'
  and real_source_projection.first_failure.reason == 'diagnostic-work-budget-exhausted'
  and last_created_context and last_created_context.states.recipe_index == parent_recipe_index
  and last_created_context.states.recipe_source == parent_recipe_source
  and last_created_context.states.compiler_telemetry == nil
  and context.states.recipe_index == parent_recipe_index
  and context.states.recipe_source == parent_recipe_source
  and context.epochs.recipe_index == parent_recipe_index_epoch
  and context.epochs.recipe_source == parent_recipe_source_epoch
  and context.states.compiler_telemetry == nil,
  'A capped diagnostic reuses the real parent recipe snapshot without a fresh full index or telemetry')

-- A parent that has not built recipe facts is also safe: diagnostics refuse the
-- query explicitly rather than asking the fresh context to construct the full
-- canonical index before its observer can apply a cap.
context = new_context()
active_context = nil
last_created_context = nil
local unavailable_projection = production.pack_production_rejection_projection('logistic-science-pack', {
  limits = {candidates = 4, nodes = 5, depth = 32, bytes = 4096}
})
check('D24', unavailable_projection and unavailable_projection.status == 'indeterminate'
  and unavailable_projection.first_failure.reason == 'diagnostic-recipe-index-unavailable'
  and unavailable_projection.truncation and unavailable_projection.truncation.unavailable[1] == 'recipe-index'
  and context.states.recipe_index == nil and context.states.recipe_source == nil
  and context.states.compiler_telemetry == nil
  and last_created_context and last_created_context.states.recipe_index == nil
  and last_created_context.states.recipe_source == nil
  and last_created_context.states.compiler_telemetry == nil,
  'A missing real parent index is explicit indeterminate without index or telemetry construction')

-- Load the exact F200 composition overlay under a test-only module identity.
-- Its science facade remains real: the controlled enabled-future pack must
-- emit both independently selected inner gates, once each, to the F200
-- continuation qualifier.
reset(enabled_future_gate_consumer_world())
context.states.recipe_index = nil
context.epochs.recipe_index = nil
stub("prototypes.mir.settings.resolver", {base_enabled = function() return true end})
stub("prototypes.mir.planner.prerequisites", {
  append_end_game_gate_prerequisite = function(prereqs) return prereqs, nil end
})
stub("prototypes.mir.capabilities.science_integration.science_selector", {
  apply_science_pack_ingredient_policy = function(ingredients) return ingredients end
})
stub("prototypes.mir.settings.effective", {get = function() return nil end})
local f200_qualify = require("fixtures.f200.base_continuations.qualify")
local f200_prereqs, f200_gate_reason = f200_qualify.append_end_game_prerequisite(
  {"existing"}, {{"gated-pack", 1}, {"gated-pack", 1}})
check("MG08", f200_gate_reason == nil and table.concat(f200_prereqs, ",") == "existing,GateOne,GateTwo",
  "The actual F200 continuation qualifier emits both real plural gates once: "
    .. table.concat(f200_prereqs or {}, ",") .. "; reason=" .. tostring(f200_gate_reason))

if #failures > 0 then error(table.concat(failures, "\n")) end
print("MIR-RESEARCHABILITY-PLANNING-PASS " .. checks)
