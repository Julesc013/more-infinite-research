-- Controlled module regression.  It exercises the real CompilerContext and
-- real recipe-source replacement contract; it is not a Factorio qualification.
local checks = 0

local function check(id, condition, detail)
  checks = checks + 1
  if not condition then error("FAILED " .. id .. ": " .. detail) end
  print("OBSERVED\t" .. id .. "\t" .. detail)
end

local function stub(name, value) package.loaded[name] = value end

_G.log = function(_) end
_G.data = {raw = {
  item = {A = {name = "A", type = "item"}},
  lab = {lab = {inputs = {"A"}}},
  character = {player = {crafting_categories = {"crafting"}}},
  resource = {},
  ["offshore-pump"] = {},
  ["space-location"] = {},
  planet = {},
  technology = {unlock_A = {
    effects = {{type = "unlock-recipe", recipe = "make-A"}},
    unit = {ingredients = {{name = "A", amount = 1}}}
  }},
  recipe = {
    ["make-A"] = {name = "make-A", enabled = true, category = "crafting", energy_required = 1, result = "A"}
  }
}, extend = function() error("Unexpected prototype mutation") end}

stub("prototypes.mir.platform.factorio.target_profiles", {
  current = function()
    return {prototype_shapes = {recipe_property_defaults = {
      allow_productivity = false, allow_quality = true, maximum_productivity = 3
    }, science_pack_prototype_kinds = {"item"}}}
  end
})
stub("prototypes.mir.platform.factorio.prototype_lookup", {
  item_prototype = function(name) return data.raw.item[name] end
})
stub("prototypes.mir.capabilities.science_integration.lab_compatibility", {
  ingredient_name = function(ingredient) return ingredient and (ingredient.name or ingredient[1]) or nil end
})

local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local recipe_unlock_facts = require("prototypes.mir.capabilities.science_integration.recipe_unlock_facts")
local production = require("prototypes.mir.capabilities.science_integration.pack_production_reachability")
local selection_policy = require("prototypes.mir.capabilities.science_integration.science_selection_policy")

local context = compiler_context.new()
compiler_context.with_active(context, function()
  check("R01", recipe_facts.view("make-A") ~= nil and recipe_facts.source_epoch() == 1,
    "The initial canonical recipe source is indexed at epoch one")
  check("R02", recipe_unlock_facts.pack_recipe_status("A").initially_available == true
    and production.pack_production_status("A", {}) == "initial",
    "The real recipe, status, and production caches agree on the initial route")
  check("R02A", #recipe_unlock_facts.unlockers_for_recipe("make-A") == 1,
    "The real context-aware recipe unlock cache resolves the declared unlocker")
  local unlock_index_epoch = context:state_epoch("recipe_unlock_index")

  local initial_epoch = recipe_facts.source_epoch()
  local removed_epoch = recipe_facts.replace_source({}, initial_epoch)
  check("R03", removed_epoch == initial_epoch + 1 and recipe_facts.view("make-A") == nil,
    "replace_source advances the real Context recipe epoch and replaces recipe facts")
  check("R04", recipe_unlock_facts.pack_recipe_status("A").has_recipe == false
    and production.pack_production_status("A", {}) == "unreachable",
    "A real source replacement invalidates warm positive recipe status and production caches")
  check("R04A", #recipe_unlock_facts.unlockers_for_recipe("make-A") == 1
    and context:state_epoch("recipe_unlock_index") == unlock_index_epoch + 1,
    "The context-aware recipe unlock cache is rebuilt for the replacement epoch")

  local restored = {
    ["make-A"] = {name = "make-A", enabled = true, category = "crafting", energy_required = 1, result = "A"}
  }
  local restored_epoch = recipe_facts.replace_source(restored, removed_epoch)
  check("R05", restored_epoch == removed_epoch + 1 and recipe_facts.view("make-A") ~= nil,
    "A second real replacement refreshes the canonical recipe facts")
  check("R06", recipe_unlock_facts.pack_recipe_status("A").initially_available == true
    and production.pack_production_status("A", {}) == "initial",
    "A real source replacement invalidates warm negative status and production caches")

  -- This cache records selections inferred through prereq_tech_for_science_pack,
  -- whose answer can change with the recipe source. It is not epoch-aware, so
  -- a source replacement must stop before it can preserve stale progression.
  context:set_service("science.prereq_tech_for_science_pack", function(pack_name)
    return pack_name == "A" and "unlock_A" or nil
  end)
  local selected = selection_policy.mod_progression_packs_for({"A"})
  check("R06A", #selected == 1 and selected[1] == "A" and context:has_state("mod_progression_cache"),
    "The real mod progression cache is warmed through its science prerequisite service")

  -- The replacement contract intentionally stops before broader immutable
  -- compilation snapshots and recipe-derived cache boundaries. It refreshes
  -- the narrow epoch-aware science caches above, but must not claim to rewrite
  -- every dependent plan.
  context:set_state("compilation_snapshot", {recipe_epoch = restored_epoch})
  local accepted, message = pcall(function()
    recipe_facts.replace_source({}, restored_epoch)
  end)
  check("R07", accepted == false and tostring(message):match("mod_progression_cache") ~= nil
    and recipe_facts.source_epoch() == restored_epoch,
    "replace_source rejects warm progression cache mutation without advancing the recipe epoch")
end)

print("MIR-RECIPE-SOURCE-EPOCH-PASS " .. checks)
