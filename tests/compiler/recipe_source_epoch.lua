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
  item = {A = {name = "A", type = "item"}, B = {name = "B", type = "item"}},
  lab = {lab = {inputs = {"A", "B"}}},
  character = {player = {crafting_categories = {"crafting"}}},
  resource = {},
  ["offshore-pump"] = {},
  ["space-location"] = {},
  planet = {},
  technology = {
    unlock_A = {
      effects = {{type = "unlock-recipe", recipe = "make-A"}},
      unit = {ingredients = {{name = "A", amount = 1}}}
    },
    unlock_B = {unit = {ingredients = {{name = "B", amount = 1}}}}
  },
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

  -- This cache records selections inferred through all prerequisite gates,
  -- whose answers can change with the recipe source. It is not epoch-aware,
  -- so a source replacement must stop before it can preserve stale progression.
  context:set_service("science.prereq_techs_for_science_pack", function(pack_name)
    if pack_name == "A" then return {"unlock_A", "unlock_B"} end
    return {}
  end)
  local selected = selection_policy.mod_progression_packs_for({"A"})
  check("R06A", #selected == 2 and selected[1] == "A" and selected[2] == "B"
    and context:has_state("mod_progression_cache"),
    "The real mod progression cache traverses every plural science prerequisite gate")

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

-- Exercise the real schema-2 normalizer under actual selected target contracts.
-- Its effective independent probability is not an authored modern field; an
-- explicit unsupported declaration must nevertheless remain withheld.
;(function()
  local target_contracts = require("fixtures.recipe_source_epoch.target_profiles")
  local profile_module = package.loaded["prototypes.mir.platform.factorio.target_profiles"]
  local old_current = profile_module.current
  local routes = require("prototypes.mir.capabilities.science_integration.recipe_route_feasibility")
  for _, version in ipairs({"2.1", "2.0", "1.1", "1.0"}) do
    local selected_profile = assert(target_contracts.profiles[version])
    profile_module.current = function() return selected_profile end
    local cases = {
      {fields={amount=1}, expected=true},
      {fields={amount=1,independent_probability=0.5}, expected=version=="2.1"},
      {fields={amount=1,shared_probability={min=0,max=1}}, expected=version=="2.1"},
      {fields={amount=0,extra_count_fraction=0.5}, expected=version=="2.1" or version=="2.0"},
      {fields={amount=1,probability=0}, expected=false}
    }
    for index, case in ipairs(cases) do
      local product = {type="item",name="A"}
      for key, value in pairs(case.fields) do product[key]=value end
      local canonical = recipe_facts.index_prototypes({["make-A"]={enabled=true,category="crafting",
        energy_required=1,ingredients={},results={product}}})
      local acquired = compiler_context.with_active(compiler_context.new(), function()
        return routes.initial_recipe_witness("make-A","A",{recipe_index=canonical})~=nil
      end)
      check("CP" .. version .. "/" .. index, acquired==case.expected,
        "Canonical product acquisition obeys the actual " .. version .. " field contract")
    end
  end
  profile_module.current = old_current
end)()

-- The composed Factorio-1 targets share this adapter. Generation must retain
-- the live base-version selector and its data/runtime disagreement checks.
;(function()
  local alias="fixtures.recipe_source_epoch.shared_base_profiles"
  local authority=require("fixtures.recipe_source_epoch.target_profiles")
  local previous_mods,previous_script,previous_module=mods,script,package.loaded[alias]
  local function equal(left,right)
    if type(left)~=type(right) then return false end
    if type(left)~="table" then return left==right end
    for key,value in pairs(left) do if not equal(value,right[key]) then return false end end
    for key in pairs(right) do if left[key]==nil then return false end end
    return true
  end
  local function load(data_mods,runtime_mods)
    _G.mods=data_mods
    _G.script=runtime_mods and {active_mods=runtime_mods} or nil
    package.loaded[alias]=nil
    return require(alias)
  end
  for _,line in ipairs({"1.1","1.0"}) do
    for _,phase in ipairs({"data","runtime"}) do
      local active={base=line..".0"}
      local adapter=phase=="data" and load(active,nil) or load(nil,active)
      check("BP"..line.."/"..phase,adapter.current_factorio_version==line
        and adapter.current()==adapter.profiles[line],"Shared adapter selects the live base line")
      local count=0
      for selected in pairs(adapter.profiles) do
        assert(selected=="1.1" or selected=="1.0","Shared adapter copied an unrelated profile")
        count=count+1
      end
      check("BPS"..line.."/"..phase,count==2,"Shared adapter contains only its two reduced contracts")
      local agrees=true
      for key,value in pairs(adapter.current()) do
        if not equal(value,authority.profiles[line][key]) then agrees=false end
      end
      check("BPA"..line.."/"..phase,agrees,"Every represented profile fact matches the authority")
    end
  end
  local matched=load({base="1.1.110"},{base="1.1.110"})
  check("BPM",matched.current_factorio_version=="1.1","Matching data/runtime authorities are accepted")
  check("BPD",not pcall(load,{base="1.1.110"},{base="1.0.0"}),"Conflicting base authorities remain rejected")
  check("BPU",not pcall(load,{base="2.1.20"},nil),"An unrelated engine line remains rejected")
  check("BPN",not pcall(load,nil,nil),"Missing base authority remains rejected")
  _G.mods,_G.script,package.loaded[alias]=previous_mods,previous_script,previous_module
end)()

-- The fact index and acquisition consumer must agree on effective categories.
-- A leftover singular category cannot supplement an explicit plural list.
;(function()
  local profiles = require("fixtures.recipe_source_epoch.target_profiles")
  local profile_module = require("prototypes.mir.platform.factorio.target_profiles")
  local previous_current = profile_module.current
  local routes = require("prototypes.mir.capabilities.science_integration.recipe_route_feasibility")
  local fingerprint = require("prototypes.mir.core.fingerprint")
  local deepcopy = require("prototypes.mir.core.deepcopy")
  local cases = {
    {id="default", fields={}, categories="crafting", acquired=true},
    {id="singular", fields={category="smelting"}, categories="smelting", acquired=false},
    {id="plural-wins", fields={category="crafting", categories={"angels-seed-extractor"}},
      categories="angels-seed-extractor", acquired=false},
    {id="plural-crafting", fields={category="smelting", categories={"crafting"}},
      categories="crafting", acquired=true},
    {id="plural-deduplicated", fields={categories={"z-extractor","crafting","crafting"}},
      categories="crafting|z-extractor", acquired=true},
    {id="empty-list", fields={category="crafting", categories={}}, categories="", acquired=false},
    {id="malformed-list", fields={category="crafting", categories=false}, categories="", acquired=false},
    {id="inherited-variant", fields={category="smelting", normal={enabled=true,
      energy_required=1, ingredients={}, results={{type="item",name="A",amount=1}}}},
      categories="smelting", acquired=false},
    {id="variant-overrides", fields={category="crafting",
      normal={enabled=true,category="smelting",energy_required=1,ingredients={},results={{type="item",name="A",amount=1}}},
      expensive={enabled=true,category="angels-seed-extractor",energy_required=1,ingredients={},results={{type="item",name="A",amount=1}}}},
      categories="angels-seed-extractor|smelting", acquired=false}
  }
  for _, line in ipairs({"2.1","2.0","1.1","1.0"}) do
    local profile = assert(profiles.profiles[line])
    profile_module.current = function() return profile end
    for _, case in ipairs(cases) do
      -- Historical engines use the singular/variant contract. A foreign
      -- plural field is not an upstream historical-engine qualification.
      if (line == "2.1" or line == "2.0") or case.fields.categories == nil then
      local raw = {name="category-producer",enabled=true,energy_required=1,ingredients={},
        results={{type="item",name="A",amount=1}}}
      for field, value in pairs(case.fields) do raw[field] = deepcopy(value) end
      local before = fingerprint.of(raw)
      local indexed = recipe_facts.index_prototypes({[raw.name]=raw})
      local fact = indexed.facts[raw.name]
      local id = "CAT" .. line .. "/" .. case.id
      local acquired = compiler_context.with_active(compiler_context.new(), function()
        return routes.initial_recipe_witness(raw.name,"A",{recipe_index=indexed})~=nil
      end)
      check(id .. "/acquisition", acquired==case.acquired,
        "The actual acquisition consumer cannot use a phantom hand-crafting category")
      check(id .. "/facts", table.concat(fact.categories,"|")==case.categories,
        "Canonical facts retain only effective variant categories")
      local has_crafting = string.find("|"..case.categories.."|","|crafting|",1,true)~=nil
      check(id .. "/index", (indexed.by_category.crafting~=nil)==has_crafting,
        "Category candidate index cannot advertise a discarded crafting route")
      if not raw.normal and not raw.expensive then
        check(id .. "/variant", table.concat(fact.variants[1].categories,"|")==case.categories,
          "The concrete route variant uses the same effective categories")
      end
      check(id .. "/immutable", fingerprint.of(raw)==before,
        "Category normalization and acquisition preserve prototype inputs")
      end
    end
  end
  profile_module.current = previous_current
end)()

-- The public adapter line selects the native mining-input boundary. These
-- controlled observations do not execute nine engines or qualify packages.
;(function()
  local profile_module = require("prototypes.mir.platform.factorio.target_profiles")
  local previous_line = profile_module.current_factorio_version
  local routes = require("prototypes.mir.capabilities.science_integration.recipe_route_feasibility")
  local previous_raw = data.raw
  for _, line in ipairs({"2.1","2.0","1.1","1.0","0.17","0.16","0.15","0.14","0.13"}) do
    profile_module.current_factorio_version = line
    data.raw = {resource = {ore = {minable = {result="ore",fluid_amount=10,required_fluid="acid"}}}}
    compiler_context.with_active(compiler_context.new(), function()
      check("MF"..line.."/missing",(routes.source_witness("ore")~=nil)==(line=="0.13" or line=="0.14"),
        "The mining fluid requirement follows the selected native line contract")
    end)
    data.raw.resource.acid = {minable={results={{type="fluid",name="acid",amount=1}}}}
    data.raw['mining-drill']={miner={name='miner',resource_categories={'basic-solid'},mining_speed=1,
      input_fluid_box={},output_fluid_box={},vector_to_place_result={0,0}}}
    local legacy_box=line=='0.13' or line=='0.14'
    if legacy_box then
      data.raw['mining-drill'].miner.fluid_box={}
      data.raw['mining-drill'].miner.output_fluid_box=nil
    end
    data.raw.item={['miner-kit']={type='item',name='miner-kit',place_result='miner'}}
    data.raw.tree={kit={minable={result='miner-kit'}}}
    compiler_context.with_active(compiler_context.new(), function()
      local witness = routes.source_witness("ore")
      check("MF"..line.."/seeded",witness~=nil,
        "An independently acquired fluid retains the mined output")
      check("MF"..line.."/witness",line=="0.13" or line=="0.14"
        or witness.ingredients[1].product.type=="fluid" and witness.ingredients[1].product.name=="acid",
        "A supported mining input retains its typed acquisition witness")
      local fluid=routes.source_witness({type='fluid',name='acid'})
      check('MA'..line..'/fluid-actor',fluid and fluid.machine and fluid.machine.item=='miner-kit',
        'A fluid resource retains its compatible acquired drill on each native line')
    end)
    data.raw.tree={}
    compiler_context.with_active(compiler_context.new(),function()
      check('MA'..line..'/missing-actor',routes.source_witness({type='fluid',name='acid'})==nil,
        'A fluid resource cannot bypass missing drill acquisition')
    end)
    data.raw.tree={kit={minable={result='miner-kit'}}}
    local native_field=legacy_box and 'fluid_box' or 'output_fluid_box'
    local foreign_field=legacy_box and 'output_fluid_box' or 'fluid_box'
    data.raw['mining-drill'].miner[native_field]=nil
    data.raw['mining-drill'].miner[foreign_field]={}
    compiler_context.with_active(compiler_context.new(),function()
      check('MA'..line..'/foreign-box',routes.source_witness({type='fluid',name='acid'})==nil,
        'A foreign-era output box cannot invent native drill fluid capability')
    end)
  end
  data.raw = previous_raw
  profile_module.current_factorio_version = previous_line
end)()

-- The installed 2.0 spawner uses LootItem.item/counts; 2.1 uses native item
-- products. Adapter selection owns the interpretation, including the seven
-- reduced lines. These are controlled contracts, not nine engine executions.
;(function()
  local fingerprint = require("prototypes.mir.core.fingerprint")
  local profile_module = require("prototypes.mir.platform.factorio.target_profiles")
  local previous_line, previous_raw = profile_module.current_factorio_version, data.raw
  local routes = require("prototypes.mir.capabilities.science_integration.recipe_route_feasibility")
  for _, line in ipairs({"2.1","2.0","1.1","1.0","0.17","0.16","0.15","0.14","0.13"}) do
    profile_module.current_factorio_version = line
    local modern = line == "2.1"
    local native = modern and {type="item",name="pentapod-egg",amount_min=1,amount_max=3}
      or {item="pentapod-egg",probability=1,count_min=1,count_max=3}
    local defaults = modern and {type="item",name="default-drop"} or {item="default-drop"}
    local foreign = modern and {item="foreign-drop",count_max=3}
      or {type="item",name="foreign-drop",amount=3}
    data.raw = {["unit-spawner"]={wild={loot={native,defaults,foreign}}}}
    compiler_context.with_active(compiler_context.new(), function()
      local before = fingerprint.of(data.raw)
      local witness = routes.source_witness("pentapod-egg")
      check("LS"..line.."/native",witness and witness.kind=="entity-loot"
        and witness.product.type=="item" and witness.product.name=="pentapod-egg",
        "The actual source consumer reads the selected native loot identity")
      check("LS"..line.."/defaults",routes.source_witness("default-drop")~=nil,
        "Omitted native loot counts and probability retain their positive defaults")
      check("LS"..line.."/foreign",routes.source_witness("foreign-drop")==nil,
        "Another target's loot shape cannot invent a source")
      check("LS"..line.."/fluid",routes.source_witness({type="fluid",name="pentapod-egg"})==nil,
        "Enemy loot never creates a same-named fluid source")
      check("LS"..line.."/immutable",fingerprint.of(data.raw)==before,
        "Reading native loot does not rewrite prototype inputs")
    end)
  end
  for _, line in ipairs({"2.0","1.1","0.13"}) do
    profile_module.current_factorio_version = line
    data.raw = {unit={dropper={loot={{item="real-drop",name="phantom-drop",type="fluid",
      count_min=1,count_max=3,amount=0,independent_probability=0}}}}}
    compiler_context.with_active(compiler_context.new(), function()
      check("LS"..line.."/native-fields",routes.source_witness("real-drop")~=nil
        and routes.source_witness("phantom-drop")==nil
        and routes.source_witness({type="fluid",name="real-drop"})==nil,
        "Native LootItem fields own identity/counts; foreign product fields have no authority")
    end)
    data.raw.unit.dropper.loot[1]={item="empty-drop",count_min=0,count_max=0,
      amount=3,extra_count_fraction=1}
    compiler_context.with_active(compiler_context.new(), function()
      check("LS"..line.."/no-foreign-revival",routes.source_witness("empty-drop")==nil,
        "Foreign product quantities and extra rolls cannot revive an empty native loot range")
    end)
  end
  profile_module.current_factorio_version = "unregistered"
  data.raw = {unit={dropper={loot={{item="unknown-drop",name="unknown-drop",amount=1}}}}}
  compiler_context.with_active(compiler_context.new(), function()
    check("LSunknown",routes.source_witness("unknown-drop")==nil,
      "An unregistered target cannot choose a loot contract by guessing")
  end)
  data.raw, profile_module.current_factorio_version = previous_raw, previous_line
end)()

-- Native offshore-pump fields changed in 2.0, independently of the 2.1 loot
-- change. Select each line contract through the actual source consumer.
;(function()
  local fingerprint = require("prototypes.mir.core.fingerprint")
  local profile_module = require("prototypes.mir.platform.factorio.target_profiles")
  local previous_line, previous_raw = profile_module.current_factorio_version, data.raw
  local routes = require("prototypes.mir.capabilities.science_integration.recipe_route_feasibility")
  for _, line in ipairs({"2.1","2.0","1.1","1.0","0.17","0.16","0.15","0.14","0.13"}) do
    profile_module.current_factorio_version=line
    local modern = line=="2.1" or line=="2.0"
    data.raw={item={['pump-kit']={type='item',name='pump-kit',place_result='pump'}},
      resource={kit={minable={result='pump-kit',count=1}}},
      ['offshore-pump']={pump={fluid_source_offset={0,-1},fluid_box={}}},
      tile={water={fluid="water"}}}
    compiler_context.with_active(compiler_context.new(),function()
      local before=fingerprint.of(data.raw)
      check("PS"..line.."/offset",(routes.source_witness({type="fluid",name="water"})~=nil)==modern,
        "Only the two modern native pump lines consume tile source offsets")
      check("PS"..line.."/typed",routes.source_witness("water")==nil,
        "A pumped fluid cannot supply a same-named item")
      check("PS"..line.."/immutable",fingerprint.of(data.raw)==before,
        "Pump source reading preserves the supplied native facts")
    end)
    data.raw['offshore-pump'].pump.fluid="molten-nickel"
    compiler_context.with_active(compiler_context.new(),function()
      check("PS"..line.."/native-fields",
        (routes.source_witness({type="fluid",name="water"})~=nil)==modern
        and (routes.source_witness({type="fluid",name="molten-nickel"})~=nil)==not modern,
        "The native pump line owns its fluid fields; foreign fields cannot override it")
    end)
    data.raw['offshore-pump'].pump={fluid_box={filter="water"}}
    compiler_context.with_active(compiler_context.new(),function()
      check("PS"..line.."/filter-only",routes.source_witness({type="fluid",name="water"})==nil,
        "A machine connection filter cannot invent a natural fluid source")
    end)
    data.raw['offshore-pump'].pump={fluid="water"}
    compiler_context.with_active(compiler_context.new(),function()
      check("PS"..line.."/explicit",(routes.source_witness({type="fluid",name="water"})~=nil)==not modern,
        "The explicit fluid declaration remains native only before2.0")
    end)
    data.raw['offshore-pump'].pump = modern
      and {fluid_source_offset={0,-1},fluid_box={}} or {fluid="water"}
    data.raw.resource = {}
    compiler_context.with_active(compiler_context.new(),function()
      check("PS"..line.."/unacquired",routes.source_witness({type="fluid",name="water"})==nil,
        "A native pump prototype cannot supply water without its placement item")
    end)
    data.raw.resource.kit = {minable={result='pump-kit',count=1}}
    compiler_context.with_active(compiler_context.new(),function()
      local witness=routes.source_witness({type="fluid",name="water"})
      check("PS"..line.."/actor",witness and witness.machine
        and witness.machine.prototype_type=="offshore-pump"
        and witness.machine.item=="pump-kit",
        "The shared placement index and source consumer retain the acquired native actor")
    end)
  end
  profile_module.current_factorio_version, data.raw=previous_line, previous_raw
end)()

-- Recipe replacement must invalidate a warm actor acquisition. The entity
-- and placement item stay fixed; only the actual canonical recipe source moves.
;(function()
  local profile_module=require("prototypes.mir.platform.factorio.target_profiles")
  local previous_line,previous_raw=profile_module.current_factorio_version,data.raw
  profile_module.current_factorio_version="2.0"
  local routes=require("prototypes.mir.capabilities.science_integration.recipe_route_feasibility")
  data.raw={item={kit={type="item",name="kit",place_result="pump"}},
    ['offshore-pump']={pump={fluid_source_offset={0,-1},fluid_box={}}},
    tile={water={fluid="water"}},character={player={crafting_categories={"crafting"}}},
    recipe={kit={name="kit",enabled=true,energy_required=1,ingredients={},result="kit"}}}
  compiler_context.with_active(compiler_context.new(),function()
    local state={}
    local water={type="fluid",name="water"}
    check("PAE/initial",routes.source_witness(water,nil,state)~=nil,
      "The real actor source consumer warms a craftable placement item")
    local epoch=recipe_facts.source_epoch()
    local removed=recipe_facts.replace_source({},epoch)
    check("PAE/removed",routes.source_witness(water,nil,state)==nil,
      "A real recipe-source replacement removes the warm pump acquisition")
    recipe_facts.replace_source(data.raw.recipe,removed)
    check("PAE/restored",routes.source_witness(water,nil,state)~=nil,
      "The same query state recovers after real source restoration")
  end)
  profile_module.current_factorio_version,data.raw=previous_line,previous_raw
end)()
-- A selected fluid resource uses the same source epoch and placement index.
;(function()
  local routes=require('prototypes.mir.capabilities.science_integration.recipe_route_feasibility')
  local previous_raw=data.raw
  data.raw={resource={oil={category='basic-fluid',minable={results={{type='fluid',name='oil',amount=1}}}}},
    item={kit={type='item',name='kit',place_result='pumpjack'}},
    ['mining-drill']={pumpjack={name='pumpjack',resource_categories={'basic-fluid'},mining_speed=1,output_fluid_box={}}},
    character={player={crafting_categories={'crafting'}}},
    recipe={kit={name='kit',enabled=true,energy_required=1,ingredients={},result='kit'}}}
  compiler_context.with_active(compiler_context.new(),function()
    local state={}
    local fluid={type='fluid',name='oil'}
    check('MAE/initial',routes.source_witness(fluid,nil,state)~=nil,
      'The real source consumer acquires a matching basic-fluid drill')
    local epoch=recipe_facts.source_epoch()
    local removed=recipe_facts.replace_source({},epoch)
    check('MAE/removed',routes.source_witness(fluid,nil,state)==nil,
      'Actual recipe replacement removes warm drill acquisition')
    recipe_facts.replace_source(data.raw.recipe,removed)
    check('MAE/restored',routes.source_witness(fluid,nil,state)~=nil,
      'The same state recovers the drill after source restoration')
  end)
  data.raw=previous_raw
end)()
print("MIR-RECIPE-SOURCE-EPOCH-PASS " .. checks)
