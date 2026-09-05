-- Controlled module tests, NOT Factorio or real K2 ecosystem qualification.
-- Adapted from the supplied hash-guarded audit witness. Executes current canonical modules in an isolated environment.
local values = {
  ['mir-science-pack-ingredient-policy'] = 'configured',
  ['mir-lab-incompatibility-policy'] = 'reduce'
}
local roles = {}
local unreachable = {}
local active_mods = {Krastorio2='2.1.2', ['Krastorio2-spaced-out']='2.0.13'}
local known = {'automation-science-pack','logistic-science-pack','military-science-pack',
  'chemical-science-pack','production-science-pack','utility-science-pack','space-science-pack',
  'cryogenic-science-pack','kr-basic-tech-card','kr-matter-tech-card'}
local exists = {}; for _, n in ipairs(known) do exists[n]=true end
_G.log = function(_) end
_G.data = {raw={lab={},technology={}}, extend=function() error('Unexpected prototype mutation') end}
local function stub(name, value) package.loaded[name] = value end
stub('prototypes.mir.settings.effective', {get=function(n) return values[n] end})
stub('prototypes.mir.pipeline.compiler_context', {current=function() return {
 service=function(_, name)
  assert(name == 'science.pack_production_status', 'Unexpected service: '..name)
  return function(name) return unreachable[name] and 'unreachable' or 'reachable' end -- fixture assumption, not engine evidence
 end
} end})
stub('prototypes.mir.platform.factorio.prototype_lookup', {is_space_age=function() return true end})
local registry = {science_pack_exists=function(n) return exists[n]==true end}
stub('prototypes.mir.capabilities.science_integration.pack_registry',registry)
stub('prototypes.mir.streams.registry',{shared={per_level_default=0.1}})
stub('prototypes.mir.capabilities.recipe_productivity.recipe_matching',{buckets_view=function() return {} end})
stub('prototypes.mir.compatibility.policy_authority',{science_roles_for_stream=function(_) return roles end})
stub('prototypes.mir.platform.factorio.mods',{snapshot=function() return active_mods end})
local lab = require('prototypes.mir.capabilities.science_integration.lab_compatibility')
local policy = require('prototypes.mir.capabilities.science_integration.science_selection_policy')
local science = {
 science_pack_exists=registry.science_pack_exists,
 official_progression_packs_for=policy.official_progression_packs_for,
 space_age_progression_packs_for=policy.space_age_progression_packs_for,
 pack_list_all=function() return known end,
 pack_list_official=function()
  local out={}; for _, n in ipairs(known) do if not n:match('^kr%-') then out[#out+1]=n end end; return out
 end,
 is_official_science_pack=function(n) return not n:match('^kr%-') end,
 best_lab_compatible_ingredients=lab.best_lab_compatible_ingredients,
 valid_research_ingredients=lab.valid_research_ingredients
}
stub('prototypes.mir.capabilities.science_integration.science_packs',science)
local selector = require('prototypes.mir.capabilities.science_integration.science_selector')
local k2 = require('prototypes.mir.compatibility.policies.k2_science_phase')
local planner = require('prototypes.mir.planner.science')
local checks=0
local function check(id, condition, detail)
 checks=checks+1
 if not condition then error('FAILED '..id..': '..detail) end
 print('OBSERVED\t'..id..'\t'..detail)
end
local function names(xs)
 local out={}; for _, v in ipairs(xs or {}) do out[#out+1]=v.name or v[1] end; return table.concat(out,',')
end
local function has(xs,n)
 for _,v in ipairs(xs or {}) do if (v.name or v[1])==n then return true end end; return false
end
check('K01', k2.applies(active_mods), 'V1 admits exactly K2 2.1.2 plus K2SO 2.0.13')
check('K02', not k2.applies({Krastorio2='2.1.2',['Krastorio2-spaced-out']='2.0.17'}), 'V1 does not admit K2SO 2.0.17')
check('K03', not k2.applies({['Krastorio2-spaced-out']='1.6.21'}), 'V1 does not admit standalone K2SO 1.6.21')
local original={{'kr-basic-tech-card',1},{'automation-science-pack',1},{'production-science-pack',1}}
local norm,decision=k2.normalize(original,active_mods)
check('K04',not has(norm,'kr-basic-tech-card') and has(norm,'automation-science-pack'),'Phase one removes basic card but retains automation')
check('K05',#original==3 and original[1][1]=='kr-basic-tech-card','Normalization does not mutate input')
local advanced={{'automation-science-pack',1},{'logistic-science-pack',1},{'military-science-pack',1},{'chemical-science-pack',1},{'space-science-pack',1},{'kr-matter-tech-card',1}}
norm,decision=k2.normalize(advanced,active_mods)
check('K06',#norm==2 and has(norm,'space-science-pack') and has(norm,'kr-matter-tech-card'),'Phase two retains only the late fixture packs')
local again=k2.normalize(norm,active_mods)
check('K07',names(norm)==names(again),'Phase normalization is idempotent on fixture')
local nochange=k2.normalize(advanced,{Krastorio2='2.1.2',['Krastorio2-spaced-out']='2.0.17'})
check('K08',names(nochange)==names(advanced) and nochange~=advanced,'Out-of-envelope normalization returns copied unchanged input')
roles={{role='exclude',pack='automation-science-pack'}}
local spec={science_packs={'automation-science-pack','utility-science-pack'}}
local selected=selector.pick_science_for_stream(spec,'audit_stream')
check('S01',not has(selected,'automation-science-pack'),'Configured mode preserves the exclusion')
values['mir-science-pack-ingredient-policy']='official-progression'
selected=selector.pick_science_for_stream(spec,'audit_stream')
check('S02',not has(selected,'automation-science-pack'),'Official progression respects compatibility exclusion')
values['mir-science-pack-ingredient-policy']='all-official'
selected=selector.pick_science_for_stream(spec,'audit_stream')
check('S03',not has(selected,'automation-science-pack'),'All-official respects compatibility exclusion')
roles={{role='exclude',pack='cryogenic-science-pack'}}
values['mir-science-pack-ingredient-policy']='configured'
selected=selector.pick_science_for_stream({science_packs={'space-science-pack'}},'research_ice')
check('S04',has(selected,'cryogenic-science-pack'),'Declared hard-required cryogenic pack defeats exclusion')
roles={}
data.raw.lab={
 early={inputs={'automation-science-pack','logistic-science-pack','military-science-pack','chemical-science-pack'}},
 late={inputs={'space-science-pack','kr-matter-tech-card'}}
}
local mixed={science_packs={}}
for _, ingredient in ipairs(advanced) do mixed.science_packs[#mixed.science_packs+1]=ingredient[1] end
local result,status,phase=planner.ingredients_for_stream('audit_stream',mixed)
check('L01',status=='full' and #result==2 and has(result,'space-science-pack'),
 'Planner retains late-phase intent before reduction: '..names(result))
local phased=k2.normalize(advanced,active_mods)
local alternative,altstatus=lab.best_lab_compatible_ingredients(phased,'audit_stream',{})
check('L02',altstatus=='full' and #alternative==2 and has(alternative,'space-science-pack'),
 'Same inputs have a valid two-pack late lab solution when phase is resolved first: '..names(alternative))
values['mir-lab-incompatibility-policy']='skip'
result,status,phase=planner.ingredients_for_stream('audit_stream',mixed)
check('L03',result~=nil and #result==2 and status=='full','Skip accepts the phase-normalized compatible set')
values['mir-lab-incompatibility-policy']='engine-default'
result,status,phase=planner.ingredients_for_stream('audit_stream',mixed)
check('L04',result~=nil and #result==2 and status=='unchanged','Engine-default preserves the phase-normalized compatible set')
-- Additional adversarial cases beyond the original witness.
for _, mode in ipairs({'configured','space','space-and-promethium','space-age-progression','official-progression','all-official','all'}) do
 values['mir-science-pack-ingredient-policy']=mode
 roles={{role='exclude',pack='automation-science-pack'},{role='include',pack='automation-science-pack'}}
 local xs=selector.pick_science_for_stream(spec,'audit_stream')
 check('X-'..mode,not has(xs,'automation-science-pack'),'Expansion cannot undo an exclusion')
end
values['mir-science-pack-ingredient-policy']='configured'
roles={}
values['mir-lab-incompatibility-policy']='reduce'
data.raw.lab={earlier={inputs={'production-science-pack','utility-science-pack'}},late={inputs={'space-science-pack'}}}
result,status,phase=planner.ingredients_for_stream('audit_stream',{science_packs={'automation-science-pack','production-science-pack','utility-science-pack','space-science-pack'}})
check('P01',result and #result==1 and has(result,'space-science-pack'),'Larger pre-phase subset cannot defeat intended late phase')
unreachable['space-science-pack']=true
result,status,phase=planner.ingredients_for_stream('audit_stream',{science_packs={'production-science-pack','space-science-pack'}})
check('P02',result==nil and status=='phase-trigger-unreachable','Unreachable phase trigger blocks instead of regressing phase')
unreachable={}
local saved_required=selector.required_science_packs_for_stream
selector.required_science_packs_for_stream=function() return {'automation-science-pack'} end
result,status,phase=planner.ingredients_for_stream('audit_stream',mixed)
check('P03',result==nil and status=='required-retired-conflict','Hard requirement and retirement conflict explicitly')
selector.required_science_packs_for_stream=saved_required
data.raw.lab={}
result,status=planner.ingredients_for_stream('audit_stream',mixed)
check('P04',result==nil,'No laboratory means no emitted research')
data.raw.lab={late={inputs={'space-science-pack','cryogenic-science-pack'}}}
result,status=planner.ingredients_for_stream('research_ice',{science_packs={'space-science-pack'}})
check('P05',result and has(result,'cryogenic-science-pack'),'Hard progression requirement survives full planning')
unreachable['cryogenic-science-pack']=true
result,status=planner.ingredients_for_stream('research_ice',{science_packs={'space-science-pack'}})
check('P06',result==nil and status=='required-unreachable','Unreachable hard requirement cannot be reduced away')
unreachable={}
roles={{role='exclude',pack='space-science-pack'}}
result,status=planner.ingredients_for_stream('audit_stream',{science_packs={'space-science-pack'}})
check('P07',result==nil,'Empty final selection fails closed')
roles={}
active_mods={Krastorio2='2.1.2',['Krastorio2-spaced-out']='2.0.17'}
data.raw.lab={early={inputs={'automation-science-pack','logistic-science-pack','military-science-pack','chemical-science-pack'}},late={inputs={'space-science-pack','kr-matter-tech-card'}}}
result,status,phase=planner.ingredients_for_stream('audit_stream',mixed)
check('P08',result and #result==4 and phase.status=='not-applicable','Out-of-envelope ordinary planner behavior is preserved')
local ties={{'production-science-pack',7},{'utility-science-pack',9}}
data.raw.lab={z={inputs={'utility-science-pack'}},a={inputs={'production-science-pack'}}}
result,status=lab.best_lab_compatible_ingredients(ties,'tie',{})
check('P09',result and result[1][1]=='production-science-pack' and result[1][2]==7,'Lab tie is lexical and preserves ingredient amounts')
check('P10',ties[1][2]==7 and #ties==2,'Lab reduction does not mutate caller input')
print('MIR-SCIENCE-PLANNING-PASS '..checks)
