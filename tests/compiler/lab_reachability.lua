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
raw.unit = {dropper = {loot = {{type = 'item', name = 'lab-kit', amount = 1, probability = 1}}}}
run(raw, function()
  check('LR15', lab.valid_research_ingredients({{'A', 1}, {'B', 1}}),
    'An admitted concrete source can supply the lab item without a recipe')
end)
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
print('MIR-LAB-REACHABILITY-PASS ' .. checks)
