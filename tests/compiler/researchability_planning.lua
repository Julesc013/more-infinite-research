-- Controlled module tests, not a package, save, or ecosystem qualification.
local world, context, target_profile
local checks = 0

local function stub(name, value) package.loaded[name] = value end
local function check(id, condition, detail)
  checks = checks + 1
  if not condition then error("FAILED " .. id .. ": " .. detail) end
  print("OBSERVED\t" .. id .. "\t" .. detail)
end

_G.log = function(_) end
_G.data = {raw = {}, extend = function() error("Unexpected prototype mutation") end}
stub("prototypes.mir.platform.factorio.prototype_lookup", {
  item_prototype = function(name) return world.item_prototypes[name] end
})
stub("prototypes.mir.platform.factorio.target_profiles", {
  current = function() return target_profile end
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
stub("prototypes.mir.report.compiler_telemetry", {
  observe_max = function() end,
  count = function() end
})
stub("prototypes.mir.pipeline.compiler_context", {current = function() return context end})

local registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local recipe_unlock_facts = require("prototypes.mir.capabilities.science_integration.recipe_unlock_facts")
local production = require("prototypes.mir.capabilities.science_integration.pack_production_reachability")
local researchability = require("prototypes.mir.capabilities.science_integration.technology_researchability")
local feasibility = require("prototypes.mir.capabilities.science_integration.recipe_route_feasibility")

local function reset(next_world, kinds)
  world = next_world
  target_profile = {prototype_shapes = {science_pack_prototype_kinds = kinds}}
  data.raw = {
    lab = world.labs or {},
    technology = world.techs or {},
    recipe = world.recipe_prototypes or {},
    character = world.characters or {player = {crafting_categories = {"crafting"}}},
    resource = world.resources or {},
    ["offshore-pump"] = world.offshore_pumps or {},
    surface = world.surfaces or {},
    ["space-location"] = world.space_locations or {},
    planet = world.planets or {}
  }
  context = {states = {}, epochs = {}}
  function context:state_view(name, factory)
    if self.states[name] == nil and factory then
      self.states[name] = factory()
      self.epochs[name] = self.epochs[name] or 1
    end
    return self.states[name]
  end
  function context:set_state(name, value)
    if self.states[name] ~= nil then error("fixture state assigned twice: " .. name) end
    self.states[name] = value
    self.epochs[name] = 1
    return value
  end
  function context:has_state(name) return self.states[name] ~= nil end
  function context:state_epoch(name) return self.epochs[name] end
  function context:replace_epoch(name, value, expected_epoch)
    if self.states[name] == nil then error("fixture missing state: " .. name) end
    if expected_epoch ~= nil and self.epochs[name] ~= expected_epoch then error("fixture epoch mismatch: " .. name) end
    self.states[name] = value
    self.epochs[name] = self.epochs[name] + 1
    return value, self.epochs[name]
  end
  function context:service(name)
    if name == "science.technology_researchability_reason" then return researchability.reason_with_context end
    if name == "science.pack_production_status" then return production.pack_production_status end
    if name == "science.independent_pack_acquisition_witness" then return production.independent_pack_acquisition_witness end
    error("Unexpected service: " .. tostring(name))
  end
end

local function representation_world(prototypes)
  return {
    item_prototypes = prototypes,
    labs = {lab = {inputs = {"custom-item-pack", "custom-tool-pack"}}},
    techs = {}, recipe_prototypes = {}, recipe_facts = {}, producers = {}, unlockers = {}
  }
end

-- Representation follows the selected target contract, never the name or
-- content shape of automation-science-pack (which is absent from this world).
reset(representation_world({["custom-item-pack"] = {type = "item"}, ["custom-tool-pack"] = {type = "tool"}}), {"item"})
check("R01", registry.science_pack_exists("custom-item-pack") and not registry.science_pack_exists("custom-tool-pack"),
  "F210 item contract accepts an item science pack without a vanilla-name probe")
reset(representation_world({["custom-item-pack"] = {type = "item"}, ["custom-tool-pack"] = {type = "tool"}}), {"tool"})
check("R02", registry.science_pack_exists("custom-tool-pack") and not registry.science_pack_exists("custom-item-pack"),
  "F200 tool contract accepts the tool representation")
reset(representation_world({["custom-item-pack"] = {type = "item"}, ["custom-tool-pack"] = {type = "tool"}}), {"item", "tool"})
check("R03", registry.science_pack_exists("custom-item-pack") and registry.science_pack_exists("custom-tool-pack"),
  "A declared mixed representation accepts both kinds deterministically")

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
reset(pack_world(true, true), {"item"})
local a = production.pack_production_status("A", {})
local b = production.pack_production_status("B", {})
check("C01", a == "initial" and b == "research" and context.states.science_pack_production.entries.B.status == "research",
  "A then B is order-independent and caches only the resolved B route")
check("C02", production.pack_production_status("B", {}) == "research",
  "Warm B query reuses the resolved root result")
reset(pack_world(true, true), {"item"})
b = production.pack_production_status("B", {})
a = production.pack_production_status("A", {})
check("C03", a == "initial" and b == "research",
  "B then A reaches the same seeded acquisition closure")
reset(pack_world(true, false), {"item"})
a = production.pack_production_status("A", {})
b = production.pack_production_status("B", {})
check("C04", a == "initial" and b == "research",
  "Producer declaration order cannot change the seeded closure")
reset(pack_world(false, true), {"item"})
a = production.pack_production_status("A", {})
b = production.pack_production_status("B", {})
check("C05", a == "unreachable" and b == "unreachable",
  "A genuinely unseeded production cycle remains rejected")
reset(pack_world(false, true), {"item"})
b = production.pack_production_status("B", {})
a = production.pack_production_status("A", {})
check("C06", a == "unreachable" and b == "unreachable",
  "The unseeded rejection is also query-order independent")
reset(pack_world(true, true), {"item"})
local conditional_b = production.pack_production_status("B", {}, {TechA = true})
b = production.pack_production_status("B", {})
check("C07", conditional_b == "unreachable" and b == "research",
  "A technology-conditional rejection cannot poison the reusable root cache")

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

reset(improved_world(true), {"item"})
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
reset(improved_world(false), {"item"})
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
reset(dependency_self_lock_world(), {"item"})
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
reset(pack_world(false, true), {"item"})
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
reset(pack_world(true, true), {"item"})
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
    result_names = {output},
    variants = {{
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

reset(feasibility_world(), {"item"})
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
reset(cycle_with_ore, {"item"})
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
reset(feasibility_world(), {"item"})
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
reset(source_surface_world({high_pressure = {surface_properties = {pressure = 1000}}}), {"item"})
check("F09AE", feasibility.source_witness("ore") ~= nil
  and feasibility.source_witness({type = "fluid", name = "water"}) ~= nil,
  "A real SurfacePrototype satisfies resource and offshore-pump source conditions")
reset(source_surface_world(nil, nil, {orbit = {surface_properties = {pressure = 1000}}}), {"item"})
check("F09AF", feasibility.source_witness("ore") == nil
  and feasibility.source_witness({type = "fluid", name = "water"}) == nil,
  "A non-surface space-location cannot satisfy natural-source feasibility")
reset(source_surface_world({low_pressure = {surface_properties = {pressure = 100}}}), {"item"})
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
}, {"item"})
check("F09C", feasibility.source_witness("same").kind == "minable-resource"
  and feasibility.source_witness({type = "fluid", name = "same"}).kind == "offshore-pump",
  "A same-name natural item source is not reused as a fluid source")

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
}, {"item"})
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
}, {"item"})
check("F10", production.pack_production_status("trigger_pack", {}) == "unreachable",
  "A trigger and accepting lab are not a production-source witness")

print("MIR-RESEARCHABILITY-PLANNING-PASS " .. checks)
