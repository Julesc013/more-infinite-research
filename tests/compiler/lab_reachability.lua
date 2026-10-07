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
local function run(raw, callback)
  _G.data = {raw = raw, extend = function() error('Unexpected prototype mutation') end}
  local owner = context.new()
  owner:set_service('science.pack_production_status', production.pack_production_status)
  owner:set_service('science.item_acquisition_witness', production.item_acquisition_witness or function() return nil end)
  owner:set_service('science.independent_pack_acquisition_witness', production.independent_pack_acquisition_witness)
  owner:set_service('science.technology_researchability_reason', researchability.reason_with_context)
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
  return next_raw
end
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
-- source offset. Consume that source through lab construction and research.
local function native_pump_world()
  local r = world()
  r['assembling-machine'] = {builder={type='assembling-machine',name='builder',
    crafting_categories={'chemistry'},fluid_boxes={{production_type='input'}}}}
  r.item['builder-kit'] = {type='item',name='builder-kit',place_result='builder'}
  r.recipe.make_builder = recipe('make_builder','builder-kit')
  r.recipe.make_lab.category = 'chemistry'
  r.recipe.make_lab.ingredients = {{type='fluid',name='water',amount=1}}
  r.fluid = {water={type='fluid',name='water'}}
  r['offshore-pump'] = {native={type='offshore-pump',name='native',
    fluid_source_offset={0,-1},pumping_speed=20,fluid_box={production_type='output'}}}
  r.tile = {water={type='tile',name='water',fluid='water'}}
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
  {id='missing-machine-kit',machine=true,missing_kit=true,expected=false},
  {id='machine-without-fluid-ports',machine=true,no_ports=true,expected=false},
  {id='machine-output-port-only',machine=true,wrong_direction=true,expected=false},
  {id='machine-input-port-only-output',machine=true,output=true,ports={'input'},expected=false},
  {id='untyped-port-default',machine=true,ports={'none'},expected=false},
  {id='bidirectional-input',machine=true,ports={'input-output'},expected=true},
  {id='bidirectional-output',machine=true,output=true,ports={'input-output'},expected=true},
  {id='two-fluid-inputs-one-port',machine=true,two_fluids=true,expected=false},
  {id='two-fluid-inputs-two-ports',machine=true,two_fluids=true,ports={'input','output','input'},expected=true},
  {id='two-fluid-outputs-one-port',machine=true,output=true,two_fluids=true,expected=false},
  {id='two-fluid-outputs-two-ports',machine=true,output=true,two_fluids=true,ports={'output','input','output'},expected=true},
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
  if case.ports then
    raw['assembling-machine'].builder.fluid_boxes = {}
    for index, kind in ipairs(case.ports) do
      raw['assembling-machine'].builder.fluid_boxes[index] = {production_type=kind}
    end
  end
  if case.no_ports then raw['assembling-machine'].builder.fluid_boxes = nil end
  if case.wrong_direction then raw['assembling-machine'].builder.fluid_boxes = {{production_type='output'}} end
  if case.two_fluids then
    raw.fluid.acid = {type='fluid',name='acid'}
    raw.resource.water.minable.results[2] = {type='fluid',name='acid',amount=1}
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
print('MIR-LAB-REACHABILITY-PASS ' .. checks)
