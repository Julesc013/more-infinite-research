-- Controlled acquisition regressions. No native package/save/ecosystem claim.
local checks = 0
local function check(id, condition, detail)
  checks = checks + 1
  assert(condition, 'FAILED ' .. id .. ': ' .. detail)
  print('OBSERVED\t' .. id .. '\t' .. detail)
end
_G.log = function() end
_G.mods = {base = MIR_LAB_TEST_BASE or '2.1.20'}
local lab_policy = 'reduce'
package.loaded['prototypes.mir.settings.effective'] = {get = function() return lab_policy end}
local context = require('prototypes.mir.pipeline.compiler_context')
local lab = require('prototypes.mir.capabilities.science_integration.lab_compatibility')
local production = require('prototypes.mir.capabilities.science_integration.pack_production_reachability')
local researchability = require('prototypes.mir.capabilities.science_integration.technology_researchability')
local recipe_facts = require('prototypes.mir.index.recipe_facts')
local item_facts = require('prototypes.mir.index.item_prototype_facts')
local prototype_lookup = require('prototypes.mir.platform.factorio.prototype_lookup')
local fingerprint = require('prototypes.mir.core.fingerprint')
local function recipe(name, product, enabled)
  return {type = 'recipe', name = name, enabled = enabled ~= false,
    ingredients = {}, results = {{type = 'item', name = product, amount = 1}}, energy_required = 1}
end
local function research(packs)
  local ingredients = {}; for _, name in ipairs(packs) do ingredients[#ingredients + 1] = {name, 1} end
  return {enabled = true, unit = {count = 1, time = 1, ingredients = ingredients}}
end
local function world()
  return {item = {A = {type = 'item', name = 'A'},
      ['lab-kit'] = {type = 'item', name = 'lab-kit', place_result = 'lab'}},
    tool = {B = {type = 'tool', name = 'B'}},
    lab = {lab = {type = 'lab', name = 'lab', inputs = {'A', 'B'}}},
    recipe = {make_A = recipe('make_A', 'A'), make_B = recipe('make_B', 'B'),
      make_lab = recipe('make_lab', 'lab-kit')},
    technology = {Probe = research({'A', 'B'})},
    character = {player = {type = 'character', crafting_categories = {'crafting'}}}}
end
local function run(raw, callback, technology_reason)
  _G.data = {raw = raw, extend = function() error('Unexpected prototype mutation') end}
  local owner = context.new()
  owner:set_service('science.pack_production_status', production.pack_production_status)
  owner:set_service('science.item_acquisition_witness', production.item_acquisition_witness or function() return nil end)
  owner:set_service('science.independent_pack_acquisition_witness', production.independent_pack_acquisition_witness)
  owner:set_service('science.technology_researchability_reason', technology_reason or researchability.reason_with_context)
  owner:freeze_services()
  return context.with_active(owner, callback, owner)
end
local raw = world()
raw.recipe.make_lab = nil
run(raw, function()
  check('LR01', not lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'A present accepting lab without an acquisition route cannot admit research')
end)
raw = world()
run(raw, function(owner)
  local ingredients = {{'A', 2}, {'B', 3}}
  local before = fingerprint.of(data.raw)
  check('LR02', lab.valid_research_ingredients(ingredients), 'An enabled lab-item recipe admits a complete lab')
  check('LR03', researchability.technology_researchability_reason('Probe') == nil,
    'Actual researchability consumes the lab acquisition witness')
  check('LR04', lab.best_lab_compatible_ingredients(ingredients, 'probe', {'A', 'B'}) ~= nil,
    'Selection retains reachable full ingredients and their required packs')
  check('LR05', fingerprint.of(data.raw) == before and ingredients[1][2] == 2 and ingredients[2][2] == 3,
    'Lab acquisition is observational and preserves caller amounts')
  local telemetry = owner:state_view('compiler_telemetry')
  check('LR06', telemetry and telemetry.counters.item_prototype_index_builds == 1,
    'Normal lab queries reuse the existing item prototype index')
end)
-- A spoilage result can also be a lab placement item. Exercise the real item
-- index, recipe facts, lab service and researchability together, with no
-- unconditional acquisition stub or Factorio process.
do
  local previous_flags = _G.feature_flags
  for _, case in ipairs({
    {id = 'enabled', flag = true, seed = true, expected = true},
    {id = 'disabled', flag = false, seed = true, expected = false},
    {id = 'unseeded', flag = true, seed = false, expected = false}
  }) do
    _G.feature_flags = {spoiling = case.flag}
    raw = world()
    raw.item['perishable-kit'] = {type = 'item', name = 'perishable-kit',
      spoil_ticks = 60, spoil_result = 'lab-kit'}
    raw.recipe.make_lab = case.seed and recipe('make_lab', 'perishable-kit') or nil
    run(raw, function()
      check('LR-SPOIL-' .. case.id,
        (researchability.technology_researchability_reason('Probe') == nil) == case.expected,
        'The real lab service requires an acquired spoilage input and the enabled engine capability')
    end)
  end
  _G.feature_flags = previous_flags
end

-- Historical engines use the player prototype for handcrafting. The selected
-- adapter owns that capability; an unrelated prototype table cannot grant it.
do
  local shapes = require('prototypes.mir.platform.factorio.target_profiles').current().prototype_shapes
  local previous = shapes.handcrafting_prototype_type
  for _, case in ipairs({
    {id='legacy-player',actor='player',selected='player',expected=true},
    {id='modern-character',actor='character',selected='character',expected=true},
    {id='modern-default',actor='character',expected=true},
    {id='legacy-rejects-character',actor='character',selected='player',expected=false},
    {id='modern-rejects-player',actor='player',expected=false},
    {id='legacy-wrong-category',actor='player',selected='player',category='unrelated',expected=false},
    {id='legacy-fluid-output',actor='player',selected='player',fluid=true,expected=false},
    {id='modern-fluid-output',actor='character',selected='character',fluid=true,expected=false}
  }) do
    shapes.handcrafting_prototype_type = case.selected
    raw = world()
    raw.character = nil
    raw[case.actor] = {player = {type=case.actor,crafting_categories={case.category or 'crafting'},
      fluid_boxes={{production_type='output'}}}}
    if case.fluid then
      raw.fluid = {water={type='fluid',name='water',default_temperature=15}}
      raw.recipe.make_lab.results[#raw.recipe.make_lab.results+1] = {type='fluid',name='water',amount=1}
    end
    run(raw, function()
      local before = fingerprint.of(data.raw)
      check('LRH/'..case.id,lab.valid_research_ingredients({{'A',2},{'B',3}})==case.expected,
        'Lab acquisition uses the declared handcrafting actor and excludes fluid crafting: '..case.id)
      check('LRH/'..case.id..'/research',
        (researchability.technology_researchability_reason('Probe')==nil)==case.expected,
        'Researchability consumes the same target-specific lab route: '..case.id)
      check('LRH/'..case.id..'/immutable',fingerprint.of(data.raw)==before,
        'Handcrafting acquisition preserves observed prototypes: '..case.id)
    end)
  end
  shapes.handcrafting_prototype_type = previous
end
-- A cloned or patched minable prototype may retain both declarations. The
-- native results list owns the drops; a stale singular result is not a second
-- acquisition route for the laboratory's placement item.
for _, case in ipairs({
  {id='list-replaces-stale-item',result='lab-kit',results={{type='item',name='A',amount=1}},expected=false},
  {id='list-supplies-lab',result='A',results={{type='item',name='lab-kit',amount=1}},expected=true},
  {id='empty-list-replaces-item',result='lab-kit',results={},expected=false},
  {id='zero-list-replaces-item',result='lab-kit',results={{type='item',name='lab-kit',amount=0}},expected=false},
  {id='fluid-list-replaces-item',result='lab-kit',results={{type='fluid',name='lab-kit',amount=1}},expected=false},
  {id='list-ignores-singular-count',result='lab-kit',count=0,results={{type='item',name='lab-kit',amount=1}},expected=true},
  {id='singular-fallback',result='lab-kit',expected=true},
  {id='zero-singular-count',result='lab-kit',count=0,expected=false}
}) do
  raw = world()
  raw.recipe.make_lab = nil
  raw.fluid = {['lab-kit']={type='fluid',name='lab-kit'}}
  raw.resource = {source={type='resource',name='source',minable={
    mining_time=1,result=case.result,results=case.results,count=case.count}}}
  run(raw, function()
    local before = fingerprint.of(data.raw)
    check('LRN/'..case.id,lab.valid_research_ingredients({{'A',1},{'B',1}})==case.expected,
      'Native minable-result precedence determines lab acquisition: '..case.id)
    check('LRN/'..case.id..'/research',
      (researchability.technology_researchability_reason('Probe')==nil)==case.expected,
      'Actual researchability consumes the same minable acquisition result: '..case.id)
    check('LRN/'..case.id..'/immutable',fingerprint.of(data.raw)==before,
      'Minable acquisition preserves declared prototype inputs: '..case.id)
  end)
end
-- Fluid-consuming mining is not an independent natural seed. Exercise the
-- real lab/researchability consumer, including typed and cyclic alternatives.
local function mining_fluid_world()
  local next_raw = world()
  next_raw.recipe.make_lab = nil
  next_raw.fluid = {acid={type='fluid',name='acid'}}
  next_raw.resource = {ore={type='resource',name='ore',minable={
    mining_time=1,result='lab-kit',fluid_amount=10,required_fluid='acid'}}}
  next_raw['mining-drill'] = {miner={type='mining-drill',name='miner',
    resource_categories={'basic-solid'},mining_speed=1,vector_to_place_result={0,-1},
    input_fluid_box={production_type='input'},output_fluid_box={production_type='output'}}}
  next_raw.item['miner-kit']={type='item',name='miner-kit',place_result='miner'}
  next_raw.recipe.make_miner=recipe('make_miner','miner-kit')
  return next_raw
end
raw = mining_fluid_world()
raw.resource.acid={minable={results={{type='fluid',name='acid',amount=1}}}}
raw.recipe.make_miner=nil
run(raw,function()
  check('LRMA/missing-drill-item',not lab.valid_research_ingredients({{'A',1},{'B',1}}),
    'An acquired mining fluid cannot substitute for acquisition of a compatible drill')
end)
for _, case in ipairs({
  {id='missing-fluid',expected=false},
  {id='same-named-item',item=true,expected=false},
  {id='natural-fluid',fluid=true,expected=true},
  {id='zero-fluid-amount',amount=0,expected=true},
  {id='default-fluid-amount',omit_amount=true,expected=true},
  {id='missing-fluid-identity',missing_name=true,expected=false},
  {id='self-mining-fluid',self=true,expected=false},
  {id='lab-fluid-cycle',cycle=true,expected=false},
  {id='independent-lab-alternative',alternative=true,expected=true},
  {id='independent-fluid-alternative',cycle=true,fluid=true,expected=true}
}) do
  raw = mining_fluid_world()
  if case.amount ~= nil then raw.resource.ore.minable.fluid_amount = case.amount end
  if case.omit_amount then raw.resource.ore.minable.fluid_amount = nil end
  if case.missing_name then raw.resource.ore.minable.required_fluid = nil end
  if case.item then
    raw.item.acid = {type='item',name='acid'}
    raw.resource.item_acid = {minable={result='acid'}}
  end
  if case.fluid then raw.resource.fluid_acid = {minable={results={{type='fluid',name='acid',amount=1}}}} end
  if case.self then raw.resource.fluid_acid = {minable={
    results={{type='fluid',name='acid',amount=1}},fluid_amount=1,required_fluid='acid'}} end
  if case.cycle then
    raw['assembling-machine'] = {builder={type='assembling-machine',name='builder',
      crafting_categories={'chemistry'},fluid_boxes={{production_type='output'}}}}
    raw.item['builder-kit'] = {type='item',name='builder-kit',place_result='builder'}
    raw.recipe.make_builder = recipe('make_builder','builder-kit')
    raw.recipe.make_acid = recipe('make_acid','acid')
    raw.recipe.make_acid.category = 'chemistry'
    raw.recipe.make_acid.results[1].type = 'fluid'
    raw.recipe.make_acid.ingredients = {{'lab-kit',1}}
  end
  if case.alternative then raw.recipe.make_lab = recipe('make_lab','lab-kit') end
  run(raw, function()
    local before = fingerprint.of(data.raw)
    check('LRQ/'..case.id,lab.valid_research_ingredients({{'A',1},{'B',1}})==case.expected,
      'Lab acquisition retains the mining fluid requirement: '..case.id)
    check('LRQ/'..case.id..'/research',
      (researchability.technology_researchability_reason('Probe')==nil)==case.expected,
      'Actual researchability consumes the mining fluid witness: '..case.id)
    check('LRQ/'..case.id..'/immutable',fingerprint.of(data.raw)==before,
      'Mining acquisition preserves prototype inputs: '..case.id)
  end)
end
 -- Actual modern native pumps draw the declared tile fluid through their
-- Conditional mining also retains the selected compatible placement actor.
for _, case in ipairs({
  {id='acquired-drill',expected=true,mutate=function()end},
  {id='missing-drill',expected=false,mutate=function(r)r['mining-drill']={}end},
  {id='missing-placement',expected=false,mutate=function(r)r.item['miner-kit'].place_result=nil end},
  {id='unacquired-placement',expected=false,mutate=function(r)r.recipe.make_miner=nil end},
  {id='wrong-category',expected=false,mutate=function(r)r['mining-drill'].miner.resource_categories={'foreign'}end},
  {id='missing-input-box',expected=false,mutate=function(r)r['mining-drill'].miner.input_fluid_box=nil end},
  {id='wrong-input-filter',expected=false,mutate=function(r)r['mining-drill'].miner.input_fluid_box.filter='water'end},
  {id='missing-output-box',expected=false,mutate=function(r)r['mining-drill'].miner.output_fluid_box=nil end},
  {id='wrong-output-filter',expected=false,mutate=function(r)r['mining-drill'].miner.output_fluid_box.filter='water'end},
  {id='zero-speed',expected=false,mutate=function(r)r['mining-drill'].miner.mining_speed=0 end},
  {id='missing-item-output',expected=false,mutate=function(r)r['mining-drill'].miner.vector_to_place_result=nil end},
  {id='placement-cycle',expected=false,mutate=function(r)r.recipe.make_miner.ingredients={{'lab-kit',1}}end},
  {id='independent-drill',expected=true,mutate=function(r)
    r['mining-drill'].unacquired={name='unacquired',mining_speed=1,resource_categories={'basic-solid'},
      input_fluid_box={},output_fluid_box={},vector_to_place_result={0,0}}
    r.item['unacquired-kit']={type='item',name='unacquired-kit',place_result='unacquired'}
  end},
  {id='independent-lab',expected=true,mutate=function(r)r.recipe.make_miner=nil;r.recipe.make_lab=recipe('make_lab','lab-kit')end},
  {id='dry-hand-source',expected=true,mutate=function(r)r['mining-drill']={};r.resource.ore.minable.fluid_amount=0 end},
  {id='multiple-resource-fluids',expected=false,mutate=function(r)
    r.resource.acid.minable.results[2]={type='fluid',name='other-fluid',amount=1}
  end}
}) do
  raw=mining_fluid_world()
  raw.resource.acid={minable={results={{type='fluid',name='acid',amount=1}}}}
  case.mutate(raw)
  run(raw,function()
    local before=fingerprint.of(data.raw)
    check('LRMA/'..case.id,lab.valid_research_ingredients({{'A',1},{'B',1}})==case.expected,
      'Wet/resource-fluid mining requires a compatible acquired drill: '..case.id)
    check('LRMA/'..case.id..'/research',(researchability.technology_researchability_reason('Probe')==nil)==case.expected,
      'The actual researchability consumer retains mining actor admission: '..case.id)
    check('LRMA/'..case.id..'/immutable',fingerprint.of(data.raw)==before,
      'Mining actor reading preserves supplied prototypes: '..case.id)
  end)
end
raw=mining_fluid_world()
raw.resource.acid={minable={results={{type='fluid',name='acid',amount=1}}}}
raw.recipe.make_miner.enabled=false
raw.recipe.make_B.ingredients={{'lab-kit',1}}
raw.lab.early={name='early',inputs={'A'}}
raw.item['early-kit']={type='item',name='early-kit',place_result='early'}
raw.recipe.make_early=recipe('make_early','early-kit')
raw.technology.DrillUnlock=research({'A'})
raw.technology.DrillUnlock.effects={{type='unlock-recipe',recipe='make_miner'}}
run(raw,function(owner)
  check('LRMA/frontier/status',production.pack_production_status('B',{})=='research',
    'A resource-backed pack retains the independently research-gated drill')
  local gates=production.prereq_techs_for_science_pack('B')
  check('LRMA/frontier/gate',#gates==1 and gates[1]=='DrillUnlock',
    'Both wet item mining and its mined input retain the actual drill unlock')
  local routes=require('prototypes.mir.capabilities.science_integration.recipe_route_feasibility')
  local state=assert(owner:state_view('science_pack_production').route_witness_state)
  check('LRMA/frontier/initial',routes.source_witness('lab-kit',nil,state)==nil,
    'A warm researched drill cannot become an initial source')
end)
raw.technology.DrillUnlock.unit.ingredients={{'B',1}}
run(raw,function()
  check('LRMA/self-funding',not lab.valid_research_ingredients({{'A',1},{'B',1}}),
    'A drill unlock cannot fund itself through the resource-backed pack')
end)
-- Actual modern native pumps draw the declared tile fluid through their
-- source offset. Consume that source through lab construction and research.
local function native_pump_world()
  local r = world()
  r['assembling-machine'] = {builder={type='assembling-machine',name='builder',
    crafting_categories={'chemistry'},fluid_boxes={{production_type='input'}}}}
  r.item['builder-kit'] = {type='item',name='builder-kit',place_result='builder'}
  r.recipe.make_builder = recipe('make_builder','builder-kit')
  r.recipe.make_lab.category = 'chemistry'
  r.recipe.make_lab.ingredients = {{type='fluid',name='water',amount=1}}
  r.fluid = {water={type='fluid',name='water',default_temperature=15,max_temperature=100}}
  r['offshore-pump'] = {native={type='offshore-pump',name='native',
    fluid_source_offset={0,-1},pumping_speed=20,fluid_box={production_type='output'}}}
  r.tile = {water={type='tile',name='water',fluid='water'}}
  r.item['pump-kit'] = {type='item',name='pump-kit',place_result='native'}
  r.recipe.make_pump = recipe('make_pump','pump-kit')
  return r
end
for _, case in ipairs({
  {id='native-water',expected=true,mutate=function() end},
  {id='filter-only',expected=false,mutate=function(r)
    r['offshore-pump'].native.fluid_source_offset=nil
    r['offshore-pump'].native.fluid_box.filter='water'
  end},
  {id='foreign-explicit-field',expected=false,mutate=function(r)
    r['offshore-pump'].native.fluid_source_offset=nil
    r['offshore-pump'].native.fluid='water'
  end},
  {id='absent-tile-fluid',expected=false,mutate=function(r) r.tile={} end},
  {id='mismatched-filter',expected=false,mutate=function(r)
    r['offshore-pump'].native.fluid_box.filter='molten-nickel'
  end},
  {id='stale-foreign-field',expected=true,mutate=function(r)
    r['offshore-pump'].native.fluid='molten-nickel'
  end}
}) do
  raw = native_pump_world(); case.mutate(raw)
  run(raw, function()
    local before = fingerprint.of(data.raw)
    check('LRP/'..case.id,lab.valid_research_ingredients({{'A',1},{'B',1}})==case.expected,
      'Native tile-fluid declaration controls acquired lab construction: '..case.id)
    check('LRP/'..case.id..'/research',
      (researchability.technology_researchability_reason('Probe')==nil)==case.expected,
      'Actual researchability consumes the native tile-fluid source: '..case.id)
    check('LRP/'..case.id..'/immutable',fingerprint.of(data.raw)==before,
      'Reading pump/tile source facts preserves prototype inputs: '..case.id)
  end)
end
raw = native_pump_world()
raw.recipe.make_pump = nil
run(raw, function()
  check('LRPA/missing-pump-item',not lab.valid_research_ingredients({{'A',1},{'B',1}}),
    'A native pump prototype without an acquired placement item cannot construct the lab')
end)
raw = native_pump_world()
raw.recipe.make_B.category = 'chemistry'
raw.recipe.make_B.ingredients = {{type='fluid',name='water',amount=1}}
raw.recipe.make_builder.enabled = false
raw.lab.early = {type='lab',name='early',inputs={'A'}}
raw.item['early-kit'] = {type='item',name='early-kit',place_result='early'}
raw.recipe.make_early = recipe('make_early','early-kit')
raw.technology.BuilderUnlock = research({'A'})
raw.technology.BuilderUnlock.effects = {{type='unlock-recipe',recipe='make_builder'}}
run(raw, function()
  check('LRP/frontier/status',production.pack_production_status('B',{})=='research',
    'Native water supplies the science recipe without flattening its machine unlock')
  local gates = production.prereq_techs_for_science_pack('B')
  check('LRP/frontier/gate',#gates==1 and gates[1]=='BuilderUnlock',
    'The science frontier retains the actual machine research gate')
end)
local function native_boiler_world()
  local r=native_pump_world()
  r.boiler={boiler={type='boiler',name='boiler',mode='output-to-separate-pipe',fluid_box={filter='water'},
    output_fluid_box={filter='steam'},target_temperature=165,energy_consumption='1.8MW',
    energy_source={type='burner'}}}
  r.item['boiler-kit']={type='item',name='boiler-kit',place_result='boiler'}
  r.recipe.make_boiler=recipe('make_boiler','boiler-kit')
  r.fluid.steam={type='fluid',name='steam',default_temperature=15,max_temperature=1000}
  r.recipe.make_lab.ingredients={{type='fluid',name='steam',amount=1}}
  return r
end
for _, case in ipairs({
  {id='acquired-pump-and-boiler',expected=true,mutate=function() end},
  {id='missing-pump',expected=false,mutate=function(r) r.recipe.make_pump=nil end},
  {id='missing-boiler',expected=false,mutate=function(r) r.recipe.make_boiler=nil end},
  {id='zero-boiler-output',expected=false,mutate=function(r) r.recipe.make_boiler.results[1].amount=0 end},
  {id='wrong-boiler-placement',expected=false,mutate=function(r) r.item['boiler-kit'].place_result='other' end},
  {id='pump-bootstrap-cycle',expected=false,mutate=function(r)
    r.recipe.make_pump.category='chemistry'
    r.recipe.make_pump.ingredients={{type='fluid',name='water',amount=1}}
  end},
  {id='boiler-bootstrap-cycle',expected=false,mutate=function(r)
    r.recipe.make_boiler.category='chemistry'
    r.recipe.make_boiler.ingredients={{type='fluid',name='steam',amount=1}}
  end},
  {id='independent-water-recipe',expected=true,mutate=function(r)
    r.recipe.make_pump=nil
    table.insert(r['assembling-machine'].builder.fluid_boxes,{production_type='output'})
    r.recipe.make_water=recipe('make_water','water')
    r.recipe.make_water.category='chemistry'; r.recipe.make_water.results[1].type='fluid'
  end},
  {id='later-pump-alternative',expected=true,mutate=function(r)
    r['offshore-pump']['a-broken']={type='offshore-pump',name='a-broken',
      fluid_source_offset={0,-1},fluid_box={}}
    r.item['broken-pump-kit']={type='item',name='broken-pump-kit',place_result='a-broken'}
    r.recipe.make_broken_pump=recipe('make_broken_pump','broken-pump-kit')
    r.recipe.make_broken_pump.category='chemistry'
    r.recipe.make_broken_pump.ingredients={{type='fluid',name='water',amount=1}}
  end},
  {id='declared-source-callback',expected=true,mutate=function(r)
    r.recipe.make_pump=nil; r.recipe.make_boiler=nil
  end,callback=true}
}) do
  raw=native_boiler_world(); case.mutate(raw)
  run(raw,function()
    local routes=require('prototypes.mir.capabilities.science_integration.recipe_route_feasibility')
    local before=fingerprint.of(data.raw)
    if case.callback then
      check('LRPA/'..case.id,routes.source_witness({type='fluid',name='steam'},{
        source_witness=function(name,kind) return name=='steam' and kind=='fluid' end})~=nil,
        'The explicit caller-owned source callback retains its separate boundary')
    else
      check('LRPA/'..case.id,lab.valid_research_ingredients({{'A',1},{'B',1}})==case.expected,
        'Lab construction consumes acquired native pump/boiler and input witnesses: '..case.id)
      check('LRPA/'..case.id..'/research',
        (researchability.technology_researchability_reason('Probe')==nil)==case.expected,
        'Actual researchability consumes the conditional fluid actor: '..case.id)
    end
    check('LRPA/'..case.id..'/immutable',fingerprint.of(data.raw)==before,
      'Fluid actor acquisition preserves prototype inputs: '..case.id)
  end)
end
raw=native_boiler_world()
raw.recipe.make_B.category='chemistry'
raw.recipe.make_B.ingredients={{type='fluid',name='steam',amount=1}}
raw.recipe.make_pump.enabled=false
raw.recipe.make_boiler.enabled=false
raw.lab.early={type='lab',name='early',inputs={'A'}}
raw.item['early-kit']={type='item',name='early-kit',place_result='early'}
raw.recipe.make_early=recipe('make_early','early-kit')
for _, entry in ipairs({{'PumpUnlock','make_pump'},{'BoilerUnlock','make_boiler'}}) do
  raw.technology[entry[1]]=research({'A'})
  raw.technology[entry[1]].effects={{type='unlock-recipe',recipe=entry[2]}}
end
run(raw,function(owner)
  local routes=require('prototypes.mir.capabilities.science_integration.recipe_route_feasibility')
  local before=fingerprint.of(data.raw)
  check('LRPA/frontier/status',production.pack_production_status('B',{})=='research',
    'Pump/boiler construction unlocks keep the fluid-dependent pack research-gated')
  local gates=production.prereq_techs_for_science_pack('B')
  check('LRPA/frontier/gates',#gates==2 and gates[1]=='BoilerUnlock' and gates[2]=='PumpUnlock',
    'The science frontier retains both selected native actor unlocks')
  local state=assert(owner:state_view('science_pack_production').route_witness_state)
  check('LRPA/frontier/initial',routes.initial_recipe_witness('make_B','B',nil,state)==nil,
    'A researched actor witness cannot warm the initial recipe memo')
  check('LRPA/frontier/source',routes.source_witness({type='fluid',name='steam'},nil,state)==nil,
    'A direct source preflight cannot borrow research-gated pump or boiler construction')
  check('LRPA/frontier/immutable',fingerprint.of(data.raw)==before,
    'Actor frontier extraction preserves final input facts')
end)
local actor_frontier_raw=raw
raw=native_boiler_world()
run(raw,function()
  local routes=require('prototypes.mir.capabilities.science_integration.recipe_route_feasibility')
  local first=assert(routes.source_witness({type='fluid',name='steam'}))
  check('LRPA/witness/actor',first.machine and first.machine.prototype=='boiler'
    and first.ingredients[1].machine.prototype=='native',
    'The native fluid witness retains both selected placement actors')
  first.machine.acquisition.kind='tampered'
  first.ingredients[1].machine.item='tampered'
  local second=assert(routes.source_witness({type='fluid',name='steam'}))
  check('LRPA/witness/defensive',second.machine.acquisition.kind~='tampered'
    and second.ingredients[1].machine.item=='pump-kit',
    'Returned actor/input witness mutation cannot poison the source catalogue')
end)
raw=actor_frontier_raw
raw.technology.PumpUnlock.unit.ingredients={{'B',1}}
run(raw,function()
  check('LRPA/self-funding-unlock',not lab.valid_research_ingredients({{'A',1},{'B',1}}),
    'The pump unlock cannot fund itself through its own pumped-fluid pack or lab')
end)
-- An enabled outer recipe can consume a mined item whose fluid is unlocked
-- through earlier research. The chosen route must keep that unlock and never
-- warm an enabled-only acquisition memo with its conditional conclusion.
raw = mining_fluid_world()
raw['assembling-machine'] = {builder={type='assembling-machine',name='builder',
  crafting_categories={'chemistry'},fluid_boxes={{production_type='output'}}}}
raw.item['builder-kit'] = {type='item',name='builder-kit',place_result='builder'}
raw.recipe.make_builder = recipe('make_builder','builder-kit')
raw.recipe.make_acid = recipe('make_acid','acid',false)
raw.recipe.make_acid.category = 'chemistry'
raw.recipe.make_acid.results[1].type = 'fluid'
raw.recipe.make_B.ingredients = {{'lab-kit',1}}
raw.lab.early = {type='lab',name='early',inputs={'A'}}
raw.item['early-kit'] = {type='item',name='early-kit',place_result='early'}
raw.recipe.make_early = recipe('make_early','early-kit')
raw.technology.FluidUnlock = research({'A'})
raw.technology.FluidUnlock.effects = {{type='unlock-recipe',recipe='make_acid'}}
run(raw, function(owner)
  local before = fingerprint.of(data.raw)
  check('LRQ/frontier/lab',lab.valid_research_ingredients({{'A',1},{'B',1}}),
    'An earlier acquired lab can unlock the required mining fluid')
  check('LRQ/frontier/status',production.pack_production_status('B',{})=='research',
    'An enabled pack recipe behind fluid-consuming mining remains research-gated')
  local gates = production.prereq_techs_for_science_pack('B')
  check('LRQ/frontier/gate',#gates==1 and gates[1]=='FluidUnlock',
    'The selected science frontier retains the actual mining fluid unlock')
  local routes = require('prototypes.mir.capabilities.science_integration.recipe_route_feasibility')
  local shared = assert(owner:state_view('science_pack_production').route_witness_state)
  check('LRQ/frontier/initial',routes.initial_recipe_witness('make_B','B',nil,shared)==nil,
    'A prior researched mining witness cannot become an enabled-only route')
  check('LRQ/frontier/source',routes.source_witness('lab-kit',nil,shared)==nil,
    'A source preflight cannot declare a research-dependent mined item initial')
  check('LRQ/frontier/immutable',fingerprint.of(data.raw)==before,
    'Mining input frontier extraction preserves prototype inputs')
end)
raw.technology.FluidUnlock.enabled = false
run(raw, function()
  check('LRQ/disabled-unlock',not lab.valid_research_ingredients({{'A',1},{'B',1}}),
    'A disabled mining fluid unlock cannot acquire the later lab')
end)
raw.technology.FluidUnlock.enabled = true
raw.technology.FluidUnlock.unit.ingredients = {{'B',1}}
run(raw, function()
  check('LRQ/research-cycle',not lab.valid_research_ingredients({{'A',1},{'B',1}}),
    'A mining fluid unlock cannot fund itself through its mined lab or pack')
end)
for index, mutate in ipairs({
  function(r) r.recipe.make_lab.results[1].amount = 0 end,
  function(r) r.recipe.make_lab.results[1].probability = 0 end,
  function(r) r.recipe.make_lab.hidden = true end,
  function(r) r.recipe.make_lab.energy_required = 0 end,
  function(r) r.recipe.make_lab.category = 'unavailable-machine' end,
  function(r) r.recipe.make_lab.ingredients = {{'missing-input', 1}} end,
  function(r) r.item['lab-kit'].place_result = 'other-entity' end,
  function(r) r.recipe.make_lab.enabled = false end,
  function(r) r.recipe.make_lab.results[1].type = 'fluid' end
}) do
  raw = world(); mutate(raw)
  run(raw, function()
    check('LRX' .. index, not lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
      'Invalid, unavailable or differently typed lab route is withheld: ' .. index)
  end)
end
raw = world()
raw.lab = {early = {type = 'lab', name = 'early', inputs = {'A'}},
  late = {type = 'lab', name = 'late', inputs = {'B'}}}
raw.item['lab-kit'].place_result = 'early'
raw.item['late-kit'] = {type = 'item', name = 'late-kit', place_result = 'late'}
raw.recipe.make_late = recipe('make_late', 'late-kit')
run(raw, function()
  check('LR07', not lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'Two reachable complementary labs cannot supply one full research set')
end)
raw = world()
raw.recipe.make_lab.enabled = false
raw.technology.LabUnlock = research({'A', 'B'})
raw.technology.LabUnlock.effects = {{type = 'unlock-recipe', recipe = 'make_lab'}}
run(raw, function()
  check('LR08', not lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'A lab whose only unlock needs itself remains self-locked')
  check('LR09', researchability.technology_researchability_reason('Probe') == 'no-accepting-lab',
    'Actual researchability rejects a present self-locked accepting lab')
end)
raw.lab.early = {type = 'lab', name = 'early', inputs = {'A'}}
raw.item['early-kit'] = {type = 'item', name = 'early-kit', place_result = 'early'}
raw.recipe.make_early = recipe('make_early', 'early-kit')
raw.technology.LabUnlock.unit.ingredients = {{'A', 1}}
run(raw, function()
  check('LR10', lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'An early lab can independently unlock a later complete lab')
  check('LR11', researchability.technology_researchability_reason('Probe') == nil,
    'A legitimate staged lab unlock remains researchable')
end)
raw.technology.LabUnlock.enabled = false
run(raw, function()
  check('LR12', not lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'A disabled later-lab unlock cannot borrow an early lab witness')
end)
raw = world()
raw.recipe.make_lab.enabled = false
raw.technology.Probe.effects = {{type = 'unlock-recipe', recipe = 'make_lab'}}
run(raw, function()
  check('LR13', researchability.technology_researchability_reason('Probe') == 'no-accepting-lab',
    'The technology under assessment cannot supply its own lab')
end)
raw = world()
raw.item['lab-kit'].place_result = 'wrong-lab'
raw['item-with-entity-data'] = {['alternate-kit'] = {type = 'item-with-entity-data', name = 'alternate-kit', place_result = 'lab'}}
raw.recipe.alternate = recipe('alternate', 'alternate-kit')
run(raw, function()
  check('LR14', lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'A different concrete item type and name can independently place the accepting lab')
end)
raw = world()
raw.recipe.make_lab = nil
local current_line = require('prototypes.mir.platform.factorio.target_profiles').current_factorio_version
local native_lab_loot = current_line == '2.1'
  and {type = 'item', name = 'lab-kit', amount = 1, probability = 1}
  or {item = 'lab-kit', count_min = 1, count_max = 1, probability = 1}
raw.unit = {dropper = {loot = {native_lab_loot}}}
run(raw, function()
  check('LR15', lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'An admitted concrete source can supply the lab item without a recipe')
end)
-- Consume each target's actual enemy-loot contract through lab acquisition,
-- not merely the public source lookup. No combat, native output or save proof.
for _, case in ipairs({
  {id='native-defaults', expected=true},
  {id='native-ranged', minimum=0, maximum=3, probability=0.5, expected=true},
  {id='zero-chance', probability=0, expected=false},
  {id='zero-maximum', minimum=0, maximum=0, expected=false},
  {id='negative-maximum', maximum=-1, expected=false},
  {id='nonfinite-maximum', maximum=math.huge, expected=false},
  {id='malformed-probability', probability='bad', expected=false},
  {id='changed-native-item', product='other-drop', expected=false},
  {id='other-target-shape', foreign=true, expected=false}
}) do
  raw = world()
  raw.recipe.make_lab = nil
  local product = case.product or 'lab-kit'
  local legacy = current_line ~= '2.1'
  if case.foreign then legacy = not legacy end
  local drop = legacy
    and {item=product, count_min=case.minimum, count_max=case.maximum, probability=case.probability}
    or {type='item', name=product, amount_min=case.minimum, amount_max=case.maximum,
      probability=case.probability}
  raw['unit-spawner'] = {wild = {loot = {drop}}}
  run(raw, function()
    local before = fingerprint.of(data.raw)
    check('LRL/'..case.id,lab.valid_research_ingredients({{'A',1},{'B',1}})==case.expected,
      'Native loot identity, counts and chance determine lab acquisition: '..case.id)
    check('LRL/'..case.id..'/research',
      (researchability.technology_researchability_reason('Probe')==nil)==case.expected,
      'Actual researchability consumes the same native loot source: '..case.id)
    check('LRL/'..case.id..'/immutable',fingerprint.of(data.raw)==before,
      'Loot acquisition preserves the supplied prototype facts: '..case.id)
  end)
end
raw = world()
raw.lab.a = {type = 'lab', name = 'a', inputs = {'A'}}
raw.lab.z = {type = 'lab', name = 'z', inputs = {'B'}}
raw.item['a-kit'] = {type = 'item', name = 'a-kit', place_result = 'a'}
raw.item['z-kit'] = {type = 'item', name = 'z-kit', place_result = 'z'}
raw.recipe.make_lab = nil
raw.recipe.make_z = recipe('make_z', 'z-kit')
run(raw, function()
  local selected, status = lab.best_lab_compatible_ingredients({{'A', 2}, {'B', 3}}, 'reduce', {})
  check('LR16', selected and #selected == 1 and selected[1][1] == 'B' and selected[1][2] == 3 and status == 'reduced',
    'An unavailable lexical-first lab cannot supply a reduced subset or its display identity')
  local required = lab.best_lab_compatible_ingredients({{'A', 2}, {'B', 3}}, 'required', {'A', 'B'})
  check('LR17', required == nil, 'Reachability never reduces away declared required packs')
  for _, value in ipairs({'skip', 'engine-default'}) do
    lab_policy = value
    check('LR18-' .. value, lab.best_lab_compatible_ingredients({{'A', 2}, {'B', 3}}, 'strict', {}) == nil,
      'Strict lab policy cannot use an unavailable full lab: ' .. value)
  end
  lab_policy = 'reduce'
end)
raw = world()
run(raw, function(owner)
  check('LR19', lab.valid_research_ingredients({{'A', 1}, {'B', 1}}), 'Initial epoch acquires the lab item')
  local changed = {}; for name, value in pairs(raw.recipe) do if name ~= 'make_lab' then changed[name] = value end end
  recipe_facts.replace_source(changed, recipe_facts.source_epoch())
  check('LR20', not lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'Recipe source replacement invalidates a formerly acquired lab route')
end)
raw = world()
run(raw, function(owner)
  local observer = {visits = 0, stopped = false}
  function observer:reserve_visit() self.visits = self.visits + 1; self.stopped = self.visits >= 8; return not self.stopped end
  function observer:is_stopped() return self.stopped end
  check('LR21', not lab.valid_research_ingredients({{'A', 1}, {'B', 1}}, observer)
    and observer.stopped and observer.visits == 8, 'Cold lab acquisition reserves bounded diagnostic work')
  check('LR22', owner:state_view('item_prototype_index') == nil,
    'A capped diagnostic cannot build the normal comprehensive item index')
  check('LR23', lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'A stopped diagnostic cannot poison ordinary lab admission')
end)
raw = world()
for index = 1, 250 do raw.technology['shared-lab-' .. index] = research({'A', 'B'}) end
run(raw, function(owner)
  local all_reachable = true
  for index = 1, 250 do
    local rejection = researchability.technology_researchability_reason('shared-lab-' .. index)
    if rejection ~= nil then all_reachable = false end
  end
  check('LR24', all_reachable, '250 distinct technology queries retain the same independently acquired complete lab')
  local counters = owner:state_view('compiler_telemetry').counters
  check('LR25', counters.item_prototype_index_builds == 1 and counters.recipe_index_scans == 1,
    'Repeated technology admission builds each existing item/recipe fact index once')
end)
raw = world()
raw.recipe.make_B.enabled = false
raw.recipe.make_lab.ingredients = {{'missing-lab-input', 1}}
raw.technology.PackUnlock = research({'A'})
raw.technology.PackUnlock.effects = {{type = 'unlock-recipe', recipe = 'make_B'}}
run(raw, function(owner)
  recipe_facts.index_view()
  local before = fingerprint.of(owner:snapshot())
  local projected = production.pack_production_rejection_projection('B', {
    limits = {candidates = 4, nodes = 1024, depth = 32, bytes = 8192}})
  check('LR26', projected and projected.status == 'unreachable'
    and projected.first_failure and projected.first_failure.reason == 'no-accepting-lab',
    'The isolated science diagnostic copies the actual item-acquisition service and rejects the unavailable lab')
  check('LR27', fingerprint.of(owner:snapshot()) == before,
    'Lab acquisition diagnostics do not mutate the parent context')
end)
raw = world()
raw['item-with-entity-data'] = {['a-alternate-kit'] = {
  type = 'item-with-entity-data', name = 'a-alternate-kit', place_result = 'lab'}}
raw['assembling-machine'] = {assembler = {type = 'assembling-machine', name = 'assembler'}}
raw.item['assembler-kit'] = {type = 'item', name = 'assembler-kit', place_result = 'assembler'}
raw.item['orphan-kit'] = {type = 'item', name = 'orphan-kit', place_result = 'absent-entity'}
run(raw, function()
  local names = item_facts.placeable_items_for_entity('lab')
  check('LR28', #names == 2 and names[1] == 'a-alternate-kit' and names[2] == 'lab-kit',
    'Exact entity lookup sorts placement items across concrete item types')
  names[1] = 'caller-change'; names[3] = 'caller-addition'
  local again = item_facts.placeable_items_for_entity('lab')
  check('LR29', #again == 2 and again[1] == 'a-alternate-kit',
    'A caller cannot mutate the retained entity placement index')
  check('LR30', #item_facts.placeable_items_for_entity('absent-entity') == 0
    and #item_facts.placeable_items_for_entity('unknown') == 0
    and item_facts.placeable_items_for_entity('assembler')[1] == 'assembler-kit',
    'Exact entity lookup excludes orphan placements and other entities')
  check('LR31', #item_facts.placeable_items_for_entity_types({'lab', 'lab'}) == 2,
    'Existing entity-type lookup retains its sorted deduplicated contract')
end)
raw = world()
run(raw, function()
  check('LR32', lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'Initial exact placement admits an acquired lab')
  raw.item['lab-kit'].place_result = 'different-lab'
  check('LR33', not lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'An indexed placement item changed within the context cannot supply its former lab')
  raw.item['lab-kit'] = nil
  check('LR34', not lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'A withdrawn placement item cannot supply an indexed lab')
end)
raw.item['lab-kit'] = {type = 'item', name = 'lab-kit', place_result = 'different-lab'}
raw.lab['different-lab'] = {type = 'lab', name = 'different-lab', inputs = {'A', 'B'}}
run(raw, function()
  check('LR35', #item_facts.placeable_items_for_entity('lab') == 0
    and item_facts.placeable_items_for_entity('different-lab')[1] == 'lab-kit'
    and lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'A new compiler context adopts changed prototype placement facts')
end)
raw = world()
for index = 1, 500 do
  local lab_name, kit_name = 'unrelated-lab-' .. index, 'unrelated-kit-' .. index
  raw.lab[lab_name] = {type = 'lab', name = lab_name, inputs = {'unrelated-pack'}}
  raw.item[kit_name] = {type = 'item', name = kit_name, place_result = lab_name}
end
for index = 1, 250 do raw.technology['indexed-lab-' .. index] = research({'A', 'B'}) end
run(raw, function(owner)
  local original_lookup = prototype_lookup.item_prototype
  local unrelated_lookups = 0
  prototype_lookup.item_prototype = function(name)
    if name:match('^unrelated%-kit%-') then unrelated_lookups = unrelated_lookups + 1 end
    return original_lookup(name)
  end
  local ok, failure = pcall(function()
    local before = fingerprint.of(data.raw)
    local all_reachable = true
    for index = 1, 250 do
      if researchability.technology_researchability_reason('indexed-lab-' .. index) ~= nil then
        all_reachable = false
      end
    end
    check('LR36', all_reachable and fingerprint.of(data.raw) == before,
      '250 distinct technologies remain researchable without mutating a 501-lab catalogue')
    check('LR37', unrelated_lookups == 0,
      'Accepting-lab acquisition makes zero placement lookups for 500 unrelated lab items; observed=' .. unrelated_lookups)
    local counters = owner:state_view('compiler_telemetry').counters
    check('LR38', counters.item_prototype_index_builds == 1 and counters.recipe_index_scans == 1,
      'The larger lab catalogue still builds each existing item and recipe index once')
  end)
  prototype_lookup.item_prototype = original_lookup
  assert(ok, failure)
end)
-- A prototype category does not supply the machine that constructs a lab.
-- Exercise the actual lab and researchability consumers, rather than a
-- machine-category callback which could bypass placement acquisition.
local capture_frontier_raw
for _, case in ipairs({
  {id='missing-acquisition', expected=false},
  {id='missing-placement', no_placement=true, expected=false},
  {id='initial-machine', initial=true, expected=true},
  {id='self-locked-machine', locked=true, expected=false},
  {id='staged-machine', locked=true, early_lab=true, expected=true},
  {id='circular-machine', circular=true, expected=false},
  {id='alternate-machine', alternate=true, expected=true},
  {id='wrong-surface', initial=true, wrong_surface=true, expected=false},
  {id='fixed-other-recipe',initial=true,fixed='make_A',expected=false},
  {id='fixed-lab-recipe',initial=true,fixed='make_lab',expected=true},
  {id='captured-machine',capture=true,expected=true},
  {id='capture-wrong-target',capture=true,wrong_target=true,expected=false},
  {id='capture-wrong-transform',capture=true,wrong_transform=true,expected=false},
  {id='capture-zero-speed',capture=true,zero_speed=true,expected=false},
  {id='capture-missing-launcher',capture=true,no_launcher=true,expected=false},
  {id='capture-missing-ammo',capture=true,no_ammo=true,expected=false},
  {id='capture-wrong-gun-category',capture=true,wrong_gun=true,expected=false},
  {id='capture-zero-effect-probability',capture=true,zero_effect=true,expected=false},
  {id='capture-incompatible-surfaces',capture=true,capture_surface='different',expected=false},
  {id='capture-common-surface',capture=true,capture_surface='same',expected=true},
  {id='self-locked-capture',capture=true,capture_locked=true,expected=false},
  {id='staged-capture',capture=true,capture_locked=true,early_lab=true,expected=true}
}) do
  raw = world()
  raw.recipe.make_lab.category = 'bio-lab-manufacturing'
  raw['assembling-machine'] = {builder = {type='assembling-machine', name='builder',
    crafting_categories={'bio-lab-manufacturing'}}}
  raw['assembling-machine'].builder.fixed_recipe = case.fixed
  if case.wrong_surface then
    raw['assembling-machine'].builder.surface_conditions = {{property='pressure',min=1000}}
  end
  if not case.no_placement then
    raw.item['builder-kit'] = {type='item',name='builder-kit',place_result='builder'}
  end
  if case.initial or case.locked or case.circular then
    raw.recipe.make_builder = recipe('make_builder','builder-kit',not case.locked)
  end
  if case.locked then
    raw.technology.BuilderUnlock = research({'A'})
    raw.technology.BuilderUnlock.effects = {{type='unlock-recipe',recipe='make_builder'}}
  end
  if case.early_lab then
    raw.lab.early = {type='lab',name='early',inputs={'A'}}
    raw.item['early-kit'] = {type='item',name='early-kit',place_result='early'}
    raw.recipe.make_early = recipe('make_early','early-kit')
  end
  if case.circular then raw.recipe.make_builder.ingredients = {{'lab-kit',1}} end
  if case.capture then
    raw['unit-spawner'] = {wild = {type='unit-spawner',name='wild',
      captured_spawner_entity=case.wrong_transform and 'different-builder' or 'builder'}}
    if case.capture_surface then
      raw['assembling-machine'].builder.surface_conditions = {{property='pressure',min=1000,max=1000}}
      local pressure = case.capture_surface=='same' and 1000 or 2000
      raw['unit-spawner'].wild.surface_conditions = {{property='pressure',min=pressure,max=pressure}}
      raw.planet = {early={name='early',surface_properties={pressure=1000}},
        late={name='late',surface_properties={pressure=2000}}}
    end
    raw['capture-robot'] = {robot = {type='capture-robot',name='robot',
      capture_speed=case.zero_speed and 0 or 1}}
    raw.projectile = {rocket = {type='projectile',name='rocket',action={type='direct',
      action_delivery={type='instant',target_effects={type='create-entity',entity_name='robot',
        probability=case.zero_effect and 0 or 1}}}}}
    raw.ammo = {['capture-ammo'] = {type='ammo',name='capture-ammo',ammo_category='capture',
      ammo_type={target_filter={case.wrong_target and 'other-spawner' or 'wild'},
        action={type='direct',action_delivery={type='projectile',projectile='rocket'}}}}}
    raw.gun = {launcher = {type='gun',name='launcher',attack_parameters={
      ammo_categories={case.wrong_gun and 'other-ammo' or 'capture'}}}}
    if not case.no_launcher then raw.recipe.make_launcher = recipe('make_launcher','launcher') end
    if not case.no_ammo then
      raw.recipe.make_ammunition = recipe('make_ammunition','capture-ammo',not case.capture_locked)
    end
    if case.capture_locked then
      raw.technology.AmmoUnlock = research({'A'})
      raw.technology.AmmoUnlock.effects = {{type='unlock-recipe',recipe='make_ammunition'}}
    end
  end
  if case.alternate then
    raw['assembling-machine']['z-builder'] = {type='assembling-machine',name='z-builder',
      crafting_categories={'bio-lab-manufacturing'}}
    raw['item-with-entity-data'] = {['alternate-builder-kit'] = {
      type='item-with-entity-data',name='alternate-builder-kit',place_result='z-builder'}}
    raw.recipe.make_alternate_builder = recipe('make_alternate_builder','alternate-builder-kit')
  end
  if case.id=='staged-capture' then
    capture_frontier_raw = require('prototypes.mir.core.deepcopy')(raw)
  end
  run(raw, function(owner)
    local before = fingerprint.of(data.raw)
    check('LRM/'..case.id, lab.valid_research_ingredients({{'A',1},{'B',1}})==case.expected,
      'The accepting lab requires an independently obtainable matching machine: '..case.id)
    check('LRM/'..case.id..'/research',
      (researchability.technology_researchability_reason('Probe')==nil)==case.expected,
      'Actual researchability agrees with machine acquisition: '..case.id)
    check('LRM/'..case.id..'/immutable', fingerprint.of(data.raw)==before,
      'Machine acquisition preserves prototype inputs: '..case.id)
    if case.early_lab then
      local routes = require('prototypes.mir.capabilities.science_integration.recipe_route_feasibility')
      check('LRM/'..case.id..'/initial', routes.initial_recipe_witness('make_lab','lab-kit')==nil,
        'A research-gated machine cannot become an initial lab construction witness')
    end
  end)
end
raw = assert(capture_frontier_raw)
raw.recipe.make_lab.category = nil
raw.recipe.make_B.category = 'bio-lab-manufacturing'
raw.recipe.make_launcher.enabled = false
raw.technology.LauncherUnlock = research({'A'})
raw.technology.LauncherUnlock.effects = {{type='unlock-recipe',recipe='make_launcher'}}
run(raw, function()
  check('LRM/capture-frontier/status', production.pack_production_status('B',{})=='research',
    'An enabled pack recipe retains the research-gated native capture route')
  local gates = production.prereq_techs_for_science_pack('B')
  check('LRM/capture-frontier/gates', #gates==2 and gates[1]=='AmmoUnlock' and gates[2]=='LauncherUnlock',
    'The selected frontier retains both capture ammunition and launcher unlocks')
end)
-- Machine acquisition is part of a pack's science frontier, even when the
-- outer pack recipe is already enabled. It must not be flattened to initial
-- availability or lose the actual machine unlock from the selected route.
raw = world()
raw.recipe.make_B.category = 'late-pack-manufacturing'
raw['assembling-machine'] = {builder={type='assembling-machine',name='builder',
  crafting_categories={'late-pack-manufacturing'}}}
raw.item['builder-kit'] = {type='item',name='builder-kit',place_result='builder'}
raw.recipe.make_builder = recipe('make_builder','builder-kit',false)
raw.technology.BuilderUnlock = research({'A'})
raw.technology.BuilderUnlock.effects = {{type='unlock-recipe',recipe='make_builder'}}
run(raw, function()
  check('LRM/frontier/status', production.pack_production_status('B',{})=='research',
    'An enabled pack recipe with a research-gated machine remains a reachable later route')
  local gates = production.prereq_techs_for_science_pack('B')
  check('LRM/frontier/gate', #gates==1 and gates[1]=='BuilderUnlock',
    'The selected science frontier retains the actual machine acquisition unlock')
end)
-- A category shared with a character does not permit manual fluid handling.
-- These scenarios drive the same lab consumer and typed acquisition solver,
-- rather than assuming a fluid in a craftable category is an initial route.
local function fluid_world()
  local next_raw = world()
  next_raw.fluid = {water={type='fluid',name='water'}}
  next_raw.resource = {water={minable={results={{type='fluid',name='water',amount=1}}}}}
  next_raw['mining-drill']={miner={name='miner',resource_categories={'basic-solid'},mining_speed=1,
    output_fluid_box={},vector_to_place_result={0,0}}}
  next_raw.item['miner-kit']={type='item',name='miner-kit',place_result='miner'}
  next_raw.recipe.make_miner=recipe('make_miner','miner-kit')
  return next_raw
end
local function add_fluid_builder(next_raw)
  next_raw['assembling-machine'] = {builder={type='assembling-machine',name='builder',
    crafting_categories={'crafting'},fluid_boxes={{production_type='input'},{production_type='output'}}}}
  next_raw.item['builder-kit'] = {type='item',name='builder-kit',place_result='builder'}
  next_raw.recipe.make_builder = recipe('make_builder','builder-kit')
end
for _, case in ipairs({
  {id='fluid-input',expected=false},
  {id='fluid-output',output=true,expected=false},
  {id='fluid-intermediate',intermediate=true,expected=false},
  {id='same-name-item',item=true,expected=true},
  {id='acquired-input-machine',machine=true,expected=true},
  {id='acquired-output-machine',machine=true,output=true,expected=true},
  {id='wrong-input-fluid-filter',machine=true,filter='acid',expected=false},
  {id='matching-input-fluid-filter',machine=true,filter='water',expected=true},
  {id='wrong-output-fluid-filter',machine=true,output=true,filter='acid',expected=false},
  {id='matching-output-fluid-filter',machine=true,output=true,filter='water',expected=true},
  {id='missing-machine-kit',machine=true,missing_kit=true,expected=false},
  {id='machine-without-fluid-ports',machine=true,no_ports=true,expected=false},
  {id='machine-output-port-only',machine=true,wrong_direction=true,expected=false},
  {id='machine-input-port-only-output',machine=true,output=true,ports={'input'},expected=false},
  {id='untyped-port-default',machine=true,ports={'none'},expected=false},
  {id='bidirectional-input',machine=true,ports={'input-output'},expected=true},
  {id='bidirectional-output',machine=true,output=true,ports={'input-output'},expected=true},
  {id='two-fluid-inputs-one-port',machine=true,two_fluids=true,expected=false},
  {id='two-fluid-inputs-two-ports',machine=true,two_fluids=true,ports={'input','output','input'},expected=true},
  {id='two-fluids-shared-unfiltered-port',machine=true,two_fluids=true,ports={'input','input'},filters={'oil'},expected=false},
  {id='two-fluids-dedicated-then-free',machine=true,two_fluids=true,ports={'input','input'},filters={'water'},expected=true},
  {id='two-fluids-free-then-dedicated',machine=true,two_fluids=true,ports={'input','input'},filters={[2]='water'},expected=true},
  {id='two-fluids-duplicate-filter',machine=true,two_fluids=true,ports={'input','input'},filters={'water','water'},expected=false},
  {id='two-fluids-distinct-filters',machine=true,two_fluids=true,ports={'input','input'},filters={'water','acid'},expected=true},
  {id='two-fluid-outputs-one-port',machine=true,output=true,two_fluids=true,expected=false},
  {id='two-fluid-outputs-two-ports',machine=true,output=true,two_fluids=true,ports={'output','input','output'},expected=true},
  {id='two-output-fluids-shared-free-port',machine=true,output=true,two_fluids=true,ports={'output','output'},filters={'oil'},expected=false},
  {id='two-output-fluids-dedicated-then-free',machine=true,output=true,two_fluids=true,ports={'output','output'},filters={'water'},expected=true},
  {id='two-output-fluids-distinct-filters',machine=true,output=true,two_fluids=true,ports={'output','output'},filters={'acid','water'},expected=true},
  {id='wrong-input-filter-item-alternative',machine=true,filter='acid',alternative=true,expected=true},
  {id='duplicate-fluid-products-filtered-port',machine=true,output=true,duplicate=true,filter='water',expected=true},
  {id='dry-machine-item-alternative',machine=true,no_ports=true,alternative=true,expected=true},
  {id='duplicate-fluid-products-one-port',machine=true,output=true,duplicate=true,expected=true},
  {id='alternative-item-route',alternative=true,expected=true}
}) do
  raw = fluid_world()
  if case.output then
    raw.recipe.make_lab.results[2] = {type='fluid',name='water',amount=1}
  else
    raw.recipe.make_lab.ingredients = {{type=case.item and 'item' or 'fluid',name='water',amount=1}}
  end
  if case.item then
    raw.item.water = {type='item',name='water'}
    raw.resource.water.minable.results[2] = {type='item',name='water',amount=1}
  end
  if case.intermediate then
    raw.resource = {}
    raw.recipe.make_water = recipe('make_water','water')
    raw.recipe.make_water.results[1].type = 'fluid'
  end
  if case.machine then add_fluid_builder(raw) end
  if case.filter then
    raw['assembling-machine'].builder.fluid_boxes[case.output and 2 or 1].filter=case.filter
  end
  if case.ports then
    raw['assembling-machine'].builder.fluid_boxes = {}
    for index, kind in ipairs(case.ports) do
      raw['assembling-machine'].builder.fluid_boxes[index] = {production_type=kind}
    end
  end
  for index, filter in pairs(case.filters or {}) do
    raw['assembling-machine'].builder.fluid_boxes[index].filter=filter
  end
  if case.no_ports then raw['assembling-machine'].builder.fluid_boxes = nil end
  if case.wrong_direction then raw['assembling-machine'].builder.fluid_boxes = {{production_type='output'}} end
  if case.two_fluids then
    raw.fluid.acid = {type='fluid',name='acid'}
    raw.resource.acid = {minable={results={{type='fluid',name='acid',amount=1}}}}
    local entries = case.output and raw.recipe.make_lab.results or raw.recipe.make_lab.ingredients
    entries[#entries+1] = {type='fluid',name='acid',amount=1}
  end
  if case.duplicate then
    raw.recipe.make_lab.results[#raw.recipe.make_lab.results+1] = {type='fluid',name='water',amount=2}
  end
  if case.missing_kit then raw.recipe.make_builder = nil end
  if case.alternative then raw.recipe.alternate_lab = recipe('alternate_lab','lab-kit') end
  run(raw, function()
    local before = fingerprint.of(data.raw)
    check('LRF/'..case.id, lab.valid_research_ingredients({{'A',1},{'B',1}})==case.expected,
      'Fluid recipes require a machine; typed item-only alternatives retain character crafting: '..case.id)
    check('LRF/'..case.id..'/research',
      (researchability.technology_researchability_reason('Probe')==nil)==case.expected,
      'Actual researchability agrees with fluid machine selection: '..case.id)
    check('LRF/'..case.id..'/immutable',fingerprint.of(data.raw)==before,
      'Fluid machine selection preserves prototype inputs: '..case.id)
    if case.intermediate then
      local routes = require('prototypes.mir.capabilities.science_integration.recipe_route_feasibility')
      check('LRF/fluid-intermediate/route',routes.initial_recipe_witness('make_water',{type='fluid',name='water'})==nil,
        'An enabled character-category recipe cannot supply the fluid intermediate itself')
    end
  end)
end
raw = fluid_world()
add_fluid_builder(raw)
raw.recipe.make_B.ingredients = {{type='fluid',name='water',amount=1}}
raw.recipe.make_builder.enabled = false
raw.technology.BuilderUnlock = research({'A'})
raw.technology.BuilderUnlock.effects = {{type='unlock-recipe',recipe='make_builder'}}
run(raw, function()
  check('LRF/frontier/status',production.pack_production_status('B',{})=='research',
    'A character category cannot flatten a fluid-consuming pack behind a gated machine to initial availability')
  local gates = production.prereq_techs_for_science_pack('B')
  check('LRF/frontier/gate',#gates==1 and gates[1]=='BuilderUnlock',
    'The fluid-producing science route retains its actual machine unlock')
end)
-- A filtered early machine cannot erase the later compatible machine's
-- research gate, or bootstrap its own unlock from the pack being assessed.
for _, self_locked in ipairs({false, true}) do
  raw = fluid_world()
  add_fluid_builder(raw)
  raw.recipe.make_B.ingredients = {{type='fluid',name='water',amount=1}}
  raw['assembling-machine'].builder.fluid_boxes[1].filter = 'oil'
  raw['assembling-machine'].late_builder = {name='late_builder',crafting_categories={'crafting'},
    fluid_boxes={{production_type='input',filter='water'}}}
  raw.item['late-kit'] = {type='item',name='late-kit',place_result='late_builder'}
  raw.recipe.make_late_builder = recipe('make_late_builder','late-kit',false)
  raw.technology.LateBuilder = research({self_locked and 'B' or 'A'})
  raw.technology.LateBuilder.effects = {{type='unlock-recipe',recipe='make_late_builder'}}
  run(raw, function()
    check('LRF/filter-frontier/'..tostring(self_locked),
      production.pack_production_status('B',{})==(self_locked and 'unreachable' or 'research'),
      'Only the compatible machine can contribute an acquisition witness')
    local gates=production.prereq_techs_for_science_pack('B')
    check('LRF/filter-frontier/gates/'..tostring(self_locked),
      self_locked and #gates==0 or not self_locked and #gates==1 and gates[1]=='LateBuilder',
      'The science frontier preserves the compatible machine gate and rejects self-locking')
  end)
end
-- Temperature is part of fluid acquisition, including the pack's actual
-- machine/source/unlock chain. All worlds below are complete controlled
-- inputs; these checks do not claim native heat, throughput or logistics proof.
local function temperature_world(demand)
  local r=fluid_world()
  add_fluid_builder(r)
  r.fluid.water.default_temperature=15
  r.fluid.water.max_temperature=500
  r.recipe.make_B.ingredients={{type='fluid',name='water',amount=1,
    temperature=demand.temperature,minimum_temperature=demand.minimum_temperature,
    maximum_temperature=demand.maximum_temperature}}
  return r
end
for _, case in ipairs({
  {id='unconstrained-cold',demand={},expected=true},
  {id='cold-below-minimum',demand={minimum_temperature=100},expected=false},
  {id='cold-at-minimum',demand={minimum_temperature=15},expected=true},
  {id='cold-at-maximum',demand={maximum_temperature=15},expected=true},
  {id='cold-above-maximum',demand={maximum_temperature=10},expected=false},
  {id='exact-cold',demand={temperature=15},expected=true},
  {id='exact-hot-missing',demand={temperature=100},expected=false},
  {id='exact-overrides-range',demand={temperature=15,minimum_temperature=100,maximum_temperature=0},expected=true},
  {id='inverted-range',demand={minimum_temperature=100,maximum_temperature=0},expected=false},
  {id='nonfinite-demand',demand={minimum_temperature=math.huge},expected=false},
  {id='hot-resource',source_temperature=165,demand={minimum_temperature=100},expected=true},
  {id='hot-resource-above-maximum',source_temperature=165,demand={maximum_temperature=100},expected=false},
  {id='recipe-default-cold',producer=true,demand={minimum_temperature=100},expected=false},
  {id='recipe-explicit-hot',producer=true,source_temperature=165,demand={minimum_temperature=100},expected=true},
  {id='recipe-exact-hot',producer=true,source_temperature=165,demand={temperature=165},expected=true},
  {id='recipe-too-hot',producer=true,source_temperature=165,demand={maximum_temperature=100},expected=false},
  {id='cold-and-hot-mixture',mixed=true,demand={temperature=100},expected=true},
  {id='mixture-range',mixed=true,demand={minimum_temperature=50,maximum_temperature=80},expected=true},
  {id='mixture-cannot-overheat',mixed=true,demand={minimum_temperature=200},expected=false},
  {id='mixture-cannot-cool',mixed=true,demand={maximum_temperature=10},expected=false},
  {id='missing-temperature-fact',unknown=true,demand={minimum_temperature=100},expected=false}
}) do
  raw=temperature_world(case.demand)
  raw.resource.water.minable.results[1].temperature=case.source_temperature
  if case.unknown then raw.fluid.water.default_temperature=nil end
  if case.producer then
    raw.resource={}
    raw.recipe.make_water=recipe('make_water','water')
    raw.recipe.make_water.results={{type='fluid',name='water',amount=1,temperature=case.source_temperature}}
  end
  if case.mixed then
    raw.resource.hot_water={minable={results={{type='fluid',name='water',amount=1,temperature=165}}}}
  end
  run(raw,function()
    local before=fingerprint.of(data.raw)
    check('LRT/'..case.id,production.pack_production_status('B',{})==(case.expected and 'initial' or 'unreachable'),
      'Actual pack acquisition respects the available fluid temperatures: '..case.id)
    check('LRT/'..case.id..'/research',
      (researchability.technology_researchability_reason('Probe')==nil)==case.expected,
      'Actual science/lab researchability consumes the temperature demand: '..case.id)
    check('LRT/'..case.id..'/immutable',fingerprint.of(data.raw)==before,
      'Temperature selection preserves prototype inputs: '..case.id)
  end)
end
local temperature_routes=require('prototypes.mir.capabilities.science_integration.recipe_route_feasibility')
raw=temperature_world({})
run(raw,function()
  local state={}
  for _, case in ipairs({
    {id='any',expected=true}, {id='hot',minimum_temperature=100,expected=false},
    {id='cold',maximum_temperature=20,expected=true},
    {id='hot-again',minimum_temperature=100,expected=false},
    {id='exact',temperature=15,expected=true}
  }) do
    local demand={type='fluid',name='water',temperature=case.temperature,
      minimum_temperature=case.minimum_temperature,maximum_temperature=case.maximum_temperature}
    check('LRT/memo/'..case.id,(temperature_routes.acquisition_witness(demand,nil,state)~=nil)==case.expected,
      'Shared query state cannot reuse a different temperature demand: '..case.id)
  end
  check('LRT/callback/boolean',temperature_routes.source_witness(
    {type='fluid',name='water',minimum_temperature=100},{source_witness=function()return true end})==nil,
    'A name-only declared source cannot invent a constrained fluid temperature')
  check('LRT/callback/temperature',temperature_routes.source_witness(
    {type='fluid',name='water',minimum_temperature=100},
    {source_witness=function()return {product={type='fluid',name='water',temperature=165}} end})~=nil,
    'A declared source may supply a concrete matching temperature')
end)
for _, case in ipairs({
  {id='hot-unlock',demand={minimum_temperature=100},expected='research'},
  {id='mixed-unlock',demand={temperature=100},expected='research'},
  {id='self-lock',demand={minimum_temperature=100},self_lock=true,expected='unreachable'},
  {id='cold-research-memo',demand={minimum_temperature=100},cold_only=true,expected='unreachable'}
}) do
  raw=temperature_world(case.demand)
  raw.recipe.make_hot=recipe('make_hot','water',false)
  raw.recipe.make_hot.results={{type='fluid',name='water',amount=1,temperature=case.cold_only and 15 or 165}}
  raw.technology.HeatUnlock=research({case.self_lock and 'B' or 'A'})
  raw.technology.HeatUnlock.effects={{type='unlock-recipe',recipe='make_hot'}}
  if case.cold_only then
    raw.resource={}
    table.insert(raw.recipe.make_B.ingredients,1,{type='fluid',name='water',amount=1,maximum_temperature=20})
  end
  run(raw,function()
    check('LRT/frontier/'..case.id,production.pack_production_status('B',{})==case.expected,
      'A temperature-constrained source retains its actual research boundary: '..case.id)
    if case.expected=='research' then
      local gates=production.prereq_techs_for_science_pack('B')
      check('LRT/frontier/'..case.id..'/gate',#gates==1 and gates[1]=='HeatUnlock',
        'Heating or mixing retains the selected hot-fluid recipe unlock')
    end
  end)
end
for _, case in ipairs({
  {id='conversion-matches',minimum=165,expected=true},
  {id='conversion-too-cold',minimum=200,expected=false},
  {id='conversion-too-hot',maximum=100,expected=false},
  {id='inside-ignores-output-filter',mode='heat-fluid-inside',minimum=100,expected=false},
  {id='default-mode-ignores-output-filter',default_mode=true,minimum=100,expected=false},
  {id='inside-heats-seed',mode='heat-fluid-inside',same_fluid=true,minimum=100,expected=true},
  {id='inside-max-limit',mode='heat-fluid-inside',same_fluid=true,minimum=200,expected=false},
  {id='same-fluid-separate-pipe',same_fluid=true,minimum=165,expected=true},
  {id='same-fluid-no-seed',same_fluid=true,minimum=165,no_seed=true,expected=false},
  {id='inside-no-seed',mode='heat-fluid-inside',same_fluid=true,minimum=100,no_seed=true,expected=false}
}) do
  raw=native_boiler_world()
  if case.mode then raw.boiler.boiler.mode=case.mode end
  if case.default_mode then raw.boiler.boiler.mode=nil end
  if case.same_fluid then
    raw.boiler.boiler.output_fluid_box.filter='water'
    raw.recipe.make_lab.ingredients[1].name='water'
  end
  if case.no_seed then raw.tile={} end
  raw.recipe.make_lab.ingredients[1].minimum_temperature=case.minimum
  raw.recipe.make_lab.ingredients[1].maximum_temperature=case.maximum
  run(raw,function()
    check('LRT/boiler/'..case.id,lab.valid_research_ingredients({{'A',1},{'B',1}})==case.expected,
      'Actual lab acquisition respects boiler mode, seed and temperature: '..case.id)
  end)
end
-- A contextual machine query must try an independently acquired machine
-- before researching another compatible machine. Names do not set science
-- progression, and the researched alternative must remain available when
-- the initial machine fails its real placement/recipe/surface requirements.
for _, case in ipairs({
  {id='initial-alternative',early=true,expected='z_early',queries=0},
  {id='only-researched',expected='a_late'},
  {id='wrong-fixed-recipe',early=true,fixed=true,expected='a_late'},
  {id='missing-placement-item',early=true,missing=true,expected='a_late'},
  {id='circular-initial-machine',early=true,cycle=true,expected='a_late'},
  {id='unreachable-research',blocked=true,expected=false},
  {id='initial-despite-blocked-research',early=true,blocked=true,expected='z_early',queries=0}
}) do
  raw=world()
  raw.item.plate={type='item',name='plate'}
  raw.recipe.plate=recipe('plate','plate')
  raw.recipe.plate.category='smelting'
  raw.furnace={a_late={type='furnace',name='a_late',crafting_categories={'smelting'}}}
  raw.item.a_late={type='item',name='a_late',place_result='a_late'}
  raw.recipe.a_late=recipe('a_late','a_late',false)
  raw.technology.Late=research({case.blocked and 'unavailable-science' or 'A'})
  raw.technology.Late.effects={{type='unlock-recipe',recipe='a_late'}}
  if case.early then
    raw.furnace.z_early={type='furnace',name='z_early',crafting_categories={'smelting'},
      fixed_recipe=case.fixed and 'different-recipe' or nil}
    raw.item.z_early={type='item',name='z_early',place_result=not case.missing and 'z_early' or nil}
    raw.recipe.z_early=recipe('z_early','z_early')
    if case.cycle then raw.recipe.z_early.ingredients={{'plate',1}} end
  end
  local queries=0
  run(raw,function()
    local before=fingerprint.of(data.raw)
    local witness=production.item_acquisition_witness('plate',{}, {})
    check('LRM/'..case.id..'/machine',(witness and witness.machine.prototype or false)==case.expected,
      'The selected machine has a complete applicable acquisition route: '..case.id)
    if case.queries then
      check('LRM/'..case.id..'/work',queries==case.queries,
        'An initial machine avoids unrelated technology/lab traversal')
    end
    if witness and case.expected=='a_late' then
      check('LRM/'..case.id..'/gate',witness.machine.acquisition.unlocker=='Late',
        'A necessary machine research gate remains in the actual acquisition witness')
    end
    local routes=require('prototypes.mir.capabilities.science_integration.recipe_route_feasibility')
    check('LRM/'..case.id..'/initial',
      (routes.initial_recipe_witness('plate','plate')~=nil)==(case.expected=='z_early'),
      'A contextual machine witness cannot contaminate an initial-only query')
    check('LRM/'..case.id..'/immutable',fingerprint.of(data.raw)==before,
      'Machine selection preserves prototype inputs')
  end,function(...)
    queries=queries+1
    return researchability.reason_with_context(...)
  end)
end
-- Consume the shared registry, selector and progression policy with explicit
-- historical platform names. Recipe/ecosystem policy is empty in these cases;
-- final engine catalogues are checked separately by the native fixture.
do
  local shapes = require('prototypes.mir.platform.factorio.target_profiles').current().prototype_shapes
  local old_aliases, old_extra = shapes.science_pack_aliases, shapes.extra_science_progression
  local values = {['mir-science-pack-ingredient-policy']='configured'}
  local saved = {}
  for name, value in pairs({
    ['prototypes.mir.settings.effective']={get=function(name) return values[name] end},
    ['prototypes.mir.streams.registry']={shared={per_level_default=0.1}},
    ['prototypes.mir.capabilities.recipe_productivity.recipe_matching']={buckets_view=function() return {} end},
    ['prototypes.mir.compatibility.policy_authority']={science_roles_for_stream=function() return {} end}
  }) do saved[name]=package.loaded[name]; package.loaded[name]=value end
  local registry = require('prototypes.mir.capabilities.science_integration.pack_registry')
  local policy = require('prototypes.mir.capabilities.science_integration.science_selection_policy')
  local selector = require('prototypes.mir.capabilities.science_integration.science_selector')
  local function names(ingredients)
    local out={}; for _, ingredient in ipairs(ingredients) do out[#out+1]=ingredient[1] end
    return table.concat(out, ',')
  end
  for _, case in ipairs({
    {id='modern',packs={'automation-science-pack','logistic-science-pack','chemical-science-pack','production-science-pack','military-science-pack','utility-science-pack'},
      expected='automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack'},
    {id='0.15-0.16',historical=true,packs={'science-pack-1','science-pack-2','science-pack-3','production-science-pack','military-science-pack','high-tech-science-pack'},
      expected='science-pack-1,science-pack-2,science-pack-3,production-science-pack'},
    {id='0.13-0.14',historical=true,alien=true,packs={'science-pack-1','science-pack-2','science-pack-3','alien-science-pack'},
      expected='science-pack-1,science-pack-2,science-pack-3,alien-science-pack'}
  }) do
    shapes.science_pack_aliases=case.historical and {
      ['automation-science-pack']='science-pack-1', ['logistic-science-pack']='science-pack-2',
      ['chemical-science-pack']='science-pack-3', ['utility-science-pack']='high-tech-science-pack'
    } or nil
    if case.alien then
      for _, role in ipairs({'utility-science-pack','military-science-pack','production-science-pack','space-science-pack'}) do
        shapes.science_pack_aliases[role]='alien-science-pack'
      end
    end
    shapes.extra_science_progression=case.alien and {
      ['alien-science-pack']={'science-pack-1','science-pack-2','science-pack-3','alien-science-pack'}
    } or nil
    raw=world();raw.tool={};raw.lab.lab.inputs={}
    for _, name in ipairs(case.packs) do raw.tool[name]={type='tool',name=name};raw.lab.lab.inputs[#raw.lab.lab.inputs+1]=name end
    raw.tool['external-card']={type='tool',name='external-card'}
    raw.lab.lab.inputs[#raw.lab.lab.inputs+1]='external-card'
    run(raw,function()
      local before=fingerprint.of(data.raw)
      values['mir-science-pack-ingredient-policy']='configured'
      check('LRS/'..case.id..'/default',names(selector.pick_science_for_stream({},'research_character_crafting_speed'))==case.expected,
        'Built-in defaults select actual target science names')
      package.loaded['prototypes.streams.direct-effects']=nil
      local declarations=require('prototypes.streams.direct-effects')
      local expected_character=case.alien and 'alien-science-pack'
        or (case.historical and 'high-tech-science-pack,military-science-pack' or 'utility-science-pack,military-science-pack')
      for _, key in ipairs({'research_character_crafting_speed','research_character_mining_speed',
        'research_character_reach','research_character_walking_speed','research_inventory_capacity'}) do
        check('LRS/'..case.id..'/declaration/'..key,names(selector.pick_science_for_stream(declarations[key],key))==expected_character,
          'Actual MIR declaration preserves its target late-science requirement')
      end
      check('LRS/'..case.id..'/official',table.concat(registry.pack_list_official(),',')==table.concat(case.packs,','),
        'All official includes the target packs but excludes an external card')
      values['mir-science-pack-ingredient-policy']='all-official'
      local selected=selector.apply_science_pack_ingredient_policy({{'external-card',7},{case.packs[1],3}},'probe')
      check('LRS/'..case.id..'/all',#selected==#case.packs and selected[1][1]==case.packs[1] and selected[1][2]==3,
        'All-official preserves inherited amounts and fills the native official set')
      values['mir-science-pack-ingredient-policy']='official-progression'
      selected=selector.apply_science_pack_ingredient_policy({{case.packs[#case.packs],5}},'probe')
      check('LRS/'..case.id..'/progression',#selected==(case.alien and 4 or 5) and selected[1][2]==5,
        'Late native science expands its official predecessors without changing amounts')
      values['mir-science-pack-ingredient-policy']='configured'
      selected=selector.pick_science_for_stream({science_packs={'external-card'}},'probe')
      check('LRS/'..case.id..'/explicit',names(selected)=='external-card',
        'Explicit ecosystem pack identities are not translated')
      local extension=policy.pack_list_for_extension('braking-force')
      check('LRS/'..case.id..'/extension',extension[1]==case.packs[1] and extension[2]==case.packs[2] and extension[3]==case.packs[3],
        'Built-in extension defaults use the same native names')
      check('LRS/'..case.id..'/end-game',policy.end_game_science_pack()==(case.alien and 'alien-science-pack' or nil),
        'End-game lookup uses the same native final-science identity')
      check('LRS/'..case.id..'/immutable',fingerprint.of(data.raw)==before,
        'Science naming does not mutate prototypes')
    end)
  end
  shapes.science_pack_aliases=old_aliases;shapes.extra_science_progression=old_extra
  for _, name in ipairs({'prototypes.mir.settings.effective','prototypes.mir.streams.registry',
    'prototypes.mir.capabilities.recipe_productivity.recipe_matching','prototypes.mir.compatibility.policy_authority'}) do
    package.loaded[name]=saved[name]
  end
end
do
  local shapes = require('prototypes.mir.platform.factorio.target_profiles').current().prototype_shapes
  local previous = shapes.technology_icon_layers
  local icons = require('prototypes.mir.presentation.icon_builder')
  local stream = {overlay=false,icons={
    {icon='__base__/graphics/technology/automation.png',icon_size=128},
    {icon='__base__/graphics/icons/iron-plate.png',icon_size=32,tint={r=0.5,g=1,b=1}}
  }}
  local before=fingerprint.of(stream)
  for _, mode in ipairs({'single','layered','default'}) do
    shapes.technology_icon_layers=mode~='single'
    if mode=='default' then shapes.technology_icon_layers=nil end
    local fields=icons.technology_icon_fields_for_stream(stream)
    if mode=='single' then
      check('LRI/single',fields.icons==nil and fields.icon==stream.icons[1].icon and fields.icon_size==128,
        'Historical presentation supplies the singular icon required by the engine')
    else
      check('LRI/'..mode,fields.icon==nil and fields.icons and #fields.icons==2 and fields.icons[2].tint.r==0.5,
        'Modern presentation preserves every icon layer and its tint')
    end
    check('LRI/'..mode..'/immutable',fingerprint.of(stream)==before,
      'Native presentation projection preserves its source declaration')
  end
  shapes.technology_icon_layers=previous
end
print('MIR-LAB-REACHABILITY-PASS ' .. checks)
