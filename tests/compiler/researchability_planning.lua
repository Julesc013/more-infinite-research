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
stub("prototypes.mir.index.recipe_unlocks", {
  for_recipe = function(name) return world.unlockers[name] or {} end
})
stub("prototypes.mir.index.recipe_facts", {
  view = function(name) return world.recipe_facts[name] end,
  recipes_by_output_view = function(name) return world.producers[name] or {} end
})
stub("prototypes.mir.report.compiler_telemetry", {
  observe_max = function() end,
  count = function() end
})
stub("prototypes.mir.pipeline.compiler_context", {current = function() return context end})

local registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local production = require("prototypes.mir.capabilities.science_integration.pack_production_reachability")
local researchability = require("prototypes.mir.capabilities.science_integration.technology_researchability")

local function reset(next_world, kinds)
  world = next_world
  target_profile = {prototype_shapes = {science_pack_prototype_kinds = kinds}}
  data.raw = {
    lab = world.labs or {},
    technology = world.techs or {},
    recipe = world.recipe_prototypes or {}
  }
  context = {states = {}}
  function context:state_view(name, factory)
    if self.states[name] == nil and factory then self.states[name] = factory() end
    return self.states[name]
  end
  function context:set_state(name, value)
    if self.states[name] ~= nil then error("fixture state assigned twice: " .. name) end
    self.states[name] = value
    return value
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

local function technology(pack)
  return {enabled = true, unit = {count = 1, time = 1, ingredients = {{name = pack, amount = 1}}}}
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
    techs = {TechA = technology("A"), TechB = technology("B")},
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
check("C01", a == "initial" and b == "research" and context.states.science_pack_production.B.status == "research",
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
    techs = {TechA = technology("A")},
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
  local tech_a = technology("A")
  local tech_b = technology("B")
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

print("MIR-RESEARCHABILITY-PLANNING-PASS " .. checks)
