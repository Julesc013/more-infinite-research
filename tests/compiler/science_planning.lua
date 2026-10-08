-- Controlled module tests, NOT Factorio or real K2 ecosystem qualification.
-- Adapted from the supplied hash-guarded audit witness. Executes current canonical modules in an isolated environment.
local values = {
  ['mir-science-pack-ingredient-policy'] = 'configured',
  ['mir-lab-incompatibility-policy'] = 'reduce'
}
local roles = {}
local unreachable = {}
local derived_buckets = {}
local initially_available_recipes = {}
local derived_unlockers = {}
local native_owner_rejections = {}
local external_owner_records = {}
local owner_diagnostics = {}
local active_mods = {Krastorio2='2.1.2', ['Krastorio2-spaced-out']='2.0.13'}
local known = {'automation-science-pack','logistic-science-pack','military-science-pack',
  'chemical-science-pack','production-science-pack','utility-science-pack','space-science-pack',
  'cryogenic-science-pack','kr-basic-tech-card','kr-matter-tech-card',
  'wood-science-pack','steam-science-pack'}
local exists = {}; for _, n in ipairs(known) do exists[n]=true end
_G.log = function(_) end
_G.data = {raw={lab={},technology={}}, extend=function() error('Unexpected prototype mutation') end}
local function stub(name, value) package.loaded[name] = value end
stub('prototypes.mir.settings.effective', {get=function(n) return values[n] end})
stub('prototypes.mir.pipeline.compiler_context', {current=function() return {
 service=function(_, name)
  if name == 'science.item_acquisition_witness' then
   return function() return {kind='fixture-lab-source'} end -- fixture assumption, not lab acquisition evidence
  end
  assert(name == 'science.pack_production_status', 'Unexpected service: '..name)
  return function(name) return unreachable[name] and 'unreachable' or 'reachable' end -- fixture assumption, not engine evidence
 end
} end})
stub('prototypes.mir.platform.factorio.prototype_lookup', {
 is_space_age=function() return true end,
 item_prototype=function(name) return {place_result=name} end
})
stub('prototypes.mir.index.item_prototype_facts', {placeable_items_for_entity=function(name)
 return data.raw.lab[name] and {name} or {}
end})
local registry = {science_pack_exists=function(n) return exists[n]==true end,
 native_pack_name=function(n) return n end,extra_official_progression=function() return {} end}
stub('prototypes.mir.capabilities.science_integration.pack_registry',registry)
stub('prototypes.mir.streams.registry',{shared={per_level_default=0.1}})
stub('prototypes.mir.capabilities.recipe_productivity.recipe_matching',{buckets_view=function(key) return derived_buckets[key] or {} end})
stub('prototypes.mir.capabilities.science_integration.recipe_unlock_facts',{
 recipe_enabled_without_research=function(recipe_name) return initially_available_recipes[recipe_name] == true end
})
stub('prototypes.mir.compatibility.policy_authority',{science_roles_for_stream=function(_) return roles end})
stub('prototypes.mir.platform.factorio.mods',{snapshot=function() return active_mods end})
local lab = require('prototypes.mir.capabilities.science_integration.lab_compatibility')
local policy = require('prototypes.mir.capabilities.science_integration.science_selection_policy')
local science = {
 science_pack_exists=registry.science_pack_exists,
 native_pack_name=registry.native_pack_name,
 official_progression_packs_for=policy.official_progression_packs_for,
 space_age_progression_packs_for=policy.space_age_progression_packs_for,
 pack_list_all=function() return known end,
 pack_list_official=function()
  local out={}; for _, n in ipairs(known) do if not n:match('^kr%-') then out[#out+1]=n end end; return out
 end,
 is_official_science_pack=function(n) return not n:match('^kr%-') end,
 researchable_unlockers_for_recipe=function(recipe_name) return derived_unlockers[recipe_name] or {} end,
 technology_researchability_reason=function(technology_name) return native_owner_rejections[technology_name] end,
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
check('K04', k2.applies({base='2.1.20',Krastorio2='2.1.2',['Krastorio2-spaced-out']='2.0.13'}) and not k2.applies({base='2.1.19',Krastorio2='2.1.2',['Krastorio2-spaced-out']='2.0.13'}), 'V4 admits the observed 2.1.20 K2/K2SO tuple and rejects an adjacent engine')
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
local active_mods_v3={base='2.1.20',Krastorio2='2.1.3',['Krastorio2-spaced-out']='2.0.13'}
check('V301',k2.policy_id=='K2SciencePhasePolicyV1' and k2.applicability.Krastorio2=='2.1.2'
  and k2.applies(active_mods_v3),'V3 admits only exact base 2.1.20 plus K2 2.1.3 and K2SO 2.0.13 without changing V1 identity')
check('V302',not k2.applies({base='2.1.20',Krastorio2='2.1.4',['Krastorio2-spaced-out']='2.0.13'})
  and not k2.applies({base='2.1.20',Krastorio2='2.1.3',['Krastorio2-spaced-out']='2.0.14'}),'V3 does not admit adjacent K2 or K2SO versions')
check('V303',not k2.applies({base='2.1.14',Krastorio2='2.1.3',['Krastorio2-spaced-out']='2.0.13'}) and not k2.applies({base='2.1.19',Krastorio2='2.1.3',['Krastorio2-spaced-out']='2.0.13'})
  and not k2.applies({base='2.1.22',Krastorio2='2.1.3',['Krastorio2-spaced-out']='2.0.13'})
  and not k2.applies({Krastorio2='2.1.3',['Krastorio2-spaced-out']='2.0.13'}),'V3 rejects adjacent or missing base versions')
local v3_original={
 {name='automation-science-pack',amount=2},
 {name='space-science-pack',amount=3},
 {name='kr-matter-tech-card',amount=7}
}
local v3_normalized,v3_decision=k2.normalize(v3_original,active_mods_v3)
check('V304',v3_decision.policy_id=='K2SciencePhasePolicyV3' and v3_decision.applicable
  and v3_decision.exact_versions.base=='2.1.20' and v3_decision.exact_versions.Krastorio2=='2.1.3'
  and v3_decision.exact_versions['Krastorio2-spaced-out']=='2.0.13','V3 records its selected exact tuple')
check('V305',#v3_normalized==2 and v3_normalized[1].name=='space-science-pack' and v3_normalized[1].amount==3
  and v3_normalized[2].name=='kr-matter-tech-card' and v3_normalized[2].amount==7,'V3 preserves retained ingredient order and amounts')
check('V306',#v3_original==3 and v3_original[1].name=='automation-science-pack' and v3_original[1].amount==2,'V3 normalization does not mutate named input')
check('V307',table.concat(v3_decision.required_any_packs,',')=='kr-matter-tech-card,space-science-pack'
  and v3_decision.status=='normalized','V3 retains sorted late trigger witnesses for lab selection')
local v3_again,v3_again_decision=k2.normalize(v3_normalized,active_mods_v3)
check('V308',names(v3_again)==names(v3_normalized) and v3_again[1].amount==3 and v3_again[2].amount==7
  and v3_again_decision.status=='already-normalized','V3 normalization is idempotent with retained amounts')
local v3_phase_one,v3_phase_one_decision=k2.normalize({{'kr-basic-tech-card',1},{'production-science-pack',4}},active_mods_v3)
check('V309',#v3_phase_one==1 and v3_phase_one[1][1]=='production-science-pack' and v3_phase_one[1][2]==4
  and v3_phase_one_decision.status=='normalized','V3 phase-one normalization retains a nonempty late-compatible result')
local active_mods_v5={base='2.1.21',Krastorio2='2.1.3',['Krastorio2-spaced-out']='2.0.13'}
local v5_normalized,v5_decision=k2.normalize(v3_original,active_mods_v5)
check('V501',v5_decision.policy_id=='K2SciencePhasePolicyV5' and v5_decision.applicable
  and v5_decision.exact_versions.base=='2.1.21','Current reviewed engine has a distinct exact science-policy identity')
check('V502',names(v5_normalized)==names(v3_normalized) and #v5_decision.removed_packs==#v3_decision.removed_packs,
  'Current exact tuple retains the existing phase-two ingredient retirement')
check('V503',not k2.applies({base='2.1.21',Krastorio2='2.1.4',['Krastorio2-spaced-out']='2.0.13'})
  and not k2.applies({base='2.1.21',Krastorio2='2.1.3',['Krastorio2-spaced-out']='2.0.14'}),
  'Current engine admission does not widen the named overhaul releases')
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
-- Derivation must not recast a research-locked external recipe with no
-- researchable unlocker as an early base-science technology. This is a
-- controlled provenance law for dense overhauls, not a claim about any one
-- external modpack.
derived_buckets={derived_blocked={{recipes={'blocked-external-route'}}}}
initially_available_recipes={}
derived_unlockers={['blocked-external-route']={}}
selected=selector.pick_science_for_stream({science_packs='derive-from-unlocks'},'derived_blocked')
check('S05',#selected==0,'Unreachable derived unlock blocks instead of falling back to early science')
-- The previous fallback still applies to a recipe genuinely available at game
-- start. That case has no unlocker by design and is not an unavailable route.
derived_buckets={derived_initial={{recipes={'initial-route'}}}}
initially_available_recipes={['initial-route']=true}
derived_unlockers={['initial-route']={}}
selected=selector.pick_science_for_stream({science_packs='derive-from-unlocks'},'derived_initial')
check('S06',has(selected,'automation-science-pack') and has(selected,'chemical-science-pack'),
  'Initially available derived route retains the ordinary early-science fallback')
-- A valid external unlock keeps its exact science ingredient rather than the
-- fallback. The fact is synthetic; the rule is shared across integrations.
exists['overhaul-science-pack']=true
data.raw.technology['derived-external-unlock']={unit={ingredients={{'overhaul-science-pack',1}}}}
derived_buckets={derived_reachable={{recipes={'reachable-external-route'}}}}
initially_available_recipes={}
derived_unlockers={['reachable-external-route']={'derived-external-unlock'}}
selected=selector.pick_science_for_stream({science_packs='derive-from-unlocks'},'derived_reachable')
check('S07',#selected==1 and has(selected,'overhaul-science-pack'),
  'Reachable derived unlock retains its external science provenance')
derived_buckets={}
initially_available_recipes={}
derived_unlockers={}

-- Native-owner adoption modifies an external technology. It must reject a
-- present owner whose full research route has become unavailable, then leave
-- eligible recipes for ordinary MIR generation. The reason values stand in
-- for the shared technology-researchability service's disabled, cyclic and
-- unreachable-science answers; this is a controlled adapter regression, not
-- a claim about a particular overhaul's final technology graph.
stub('prototypes.mir.index.productivity_owners',{
 recipe_names_from_effects=function(effects)
  local out={};for _,effect in ipairs(effects or {}) do out[#out+1]=effect.recipe end;return out
 end,
 recipe_productivity_effects=function(owner) return owner.effects or {} end,
 recipe_outputs_any_product=function(_, _) return true end,
 has_recipe_productivity_effect=function(owner, recipe_name)
  for _, effect in ipairs(owner.effects or {}) do
   if effect.type=='change-recipe-productivity' and effect.recipe==recipe_name then return true end
  end
  return false
 end,
 recipe_allows_productivity=function(_) return true end,
 blocking_recipe_productivity_owner_records=function(recipe_name, options)
  local records = {}
  for _, record in ipairs(external_owner_records[recipe_name] or {}) do
   if record.action ~= 'replace'
     and not (options and options.ignore_owner and options.ignore_owner(record.tech) == true) then
    records[#records+1]=record
   end
  end
  return records
 end,
 owner_names=function(records)
  local names={}; for _, record in ipairs(records or {}) do names[#names+1]=record.tech end
  table.sort(names); return table.concat(names, ',')
 end,
 owner_kinds=function(records)
  local names={}; for _, record in ipairs(records or {}) do names[#names+1]=record.kind end
  table.sort(names); return table.concat(names, ',')
 end,
 owner_actions=function(records)
  local names={}; for _, record in ipairs(records or {}) do names[#names+1]=record.action end
  table.sort(names); return table.concat(names, ',')
 end
})
stub('prototypes.mir.report.diagnostics_sink',{recipe_owner=function(row) owner_diagnostics[#owner_diagnostics+1]=row end})
stub('prototypes.mir.policy.competing_productivity',{ignores_existing_owner=function() return false end})
stub('prototypes.mir.settings.catalog',{is_default_value=function(_, _) return true end})
stub('prototypes.mir.settings.effect_contracts',{stream_setting_name=function(key) return 'ips-effect-per-level-'..key end,
 stream_descriptor=function(_) return {display_multiplier=1} end})
stub('prototypes.mir.domain.native_owner.cost_model',{
 classify=function(_, _, _) return {research_cost_model='controlled'} end,
 configure=function(model, _) return {count=1,count_formula='1',model=model.research_cost_model}, nil end
})
stub('prototypes.mir.domain.native_owner.contract',{
 snapshot=function(owner) return {name=owner.name,max_level=owner.max_level,prerequisites=owner.prerequisites,unit=owner.unit,effects=owner.effects} end,
 fingerprint=function(_) return 'controlled' end
})
stub('prototypes.mir.platform.factorio.target_line',{feature_enabled=function(name)
 return name=='scripted_techs' or name=='productivity_family_adoption'
end})
values['ips-cost-base-native_owner_probe']=8000
values['ips-cost-linear-increment-native_owner_probe']=0
values['ips-cost-growth-native_owner_probe']=2
values['ips-max-level-native_owner_probe']=0
values['ips-research-time-native_owner_probe']=60
values['ips-effect-per-level-native_owner_probe']=0.1
local native_owner_binding=require('prototypes.mir.planner.native_owner_binding')
data.raw.technology['native-owner-probe']={
 name='native-owner-probe', max_level='infinite', unit={count=1,ingredients={{'automation-science-pack',1}}},
 effects={{type='change-recipe-productivity',recipe='already-owned-route',change=0.1}}
}
local native_owner_spec={native_owner_binding={
 owner='native-owner-probe', eligibility={require_infinite=true,require_existing_recipe_productivity_effects=true},
 effect_scope={type='change-recipe-productivity',products={'native-product'}}, cost_model={}
}}
local native_owner_buckets={{change=0.1,recipes={'new-native-route'}}}
native_owner_rejections={}
local _,native_effects,native_blocked,native_owner_name,native_plan,native_reason=
 native_owner_binding.plan('native_owner_probe',native_owner_spec,native_owner_buckets)
check('N01',native_plan and native_plan.operation=='adopt_native_owner_effects'
 and native_owner_name=='native-owner-probe' and #native_effects==1 and #native_blocked==0 and native_reason==nil,
 'Reachable native owner can adopt its eligible route')
for _, case in ipairs({
 {id='N02',rejection='disabled'},
 {id='N03',rejection='unreachable-prerequisite'},
 {id='N04',rejection='unreachable-science-overhaul-pack'}
}) do
 native_owner_rejections={['native-owner-probe']=case.rejection}
 local fallback, effects, blocked, owner_name, plan, reason=
  native_owner_binding.plan('native_owner_probe',native_owner_spec,native_owner_buckets)
 check(case.id,plan==nil and owner_name==nil and #effects==0 and #fallback==1
  and fallback[1].recipes[1]=='new-native-route' and #blocked==1
  and blocked[1].owner=='native-owner-probe' and reason=='owner_'..case.rejection,
  'Unreachable native owner ('..case.rejection..') falls back without adoption')
end
native_owner_rejections={}

-- Existing external productivity must cooperate with MIR only while it is a
-- usable research route.  The production K2/K2SO fixture keeps its reachable
-- kr-imersite-productivity owner; these controlled cases exercise the shared
-- negative paths without claiming a changed K2 final graph.
local owner_policy=require('prototypes.mir.policy.owner_policy')
local external_owner_bucket={{change=0.1,recipes={'ordinary-k2-material-route'}}}
external_owner_records={['ordinary-k2-material-route']={{
 tech='kr-imersite-productivity',kind='unknown_external',action='skip'
}}}
native_owner_rejections={}
owner_diagnostics={}
local filtered, covered=owner_policy.filter_existing_recipe_productivity(
 'research_material_imersite',{},external_owner_bucket)
check('O01',#filtered==0 and #covered==1 and covered[1].owners=='kr-imersite-productivity' and #owner_diagnostics==1
  and owner_diagnostics[1].reason=='covered_by_existing_infinite_recipe_productivity',
  'Reachable external owner remains the sole material-route owner')
for _, case in ipairs({
 {id='O02',rejection='disabled'},
 {id='O03',rejection='technology-cycle'},
 {id='O04',rejection='unreachable-science-overhaul-pack'}
}) do
 native_owner_rejections={['kr-imersite-productivity']=case.rejection}
 owner_diagnostics={}
 local eligible, skipped=owner_policy.filter_existing_recipe_productivity(
  'research_material_imersite',{},external_owner_bucket)
 check(case.id,#eligible==1 and eligible[1].recipes[1]=='ordinary-k2-material-route' and #skipped==0
   and #owner_diagnostics==1 and owner_diagnostics[1].status=='not_blocking'
   and owner_diagnostics[1].reason=='existing_infinite_recipe_productivity_owner_unresearchable'
   and owner_diagnostics[1].owners=='kr-imersite-productivity'
   and owner_diagnostics[1].owner_rejection==case.rejection,
   'Unresearchable external owner ('..case.rejection..') cannot suppress an ordinary MIR route')
end
native_owner_rejections={}
external_owner_records={}
owner_diagnostics={}

do
 local previous_mods=active_mods
 local previous_modules={};for name,value in pairs(package.loaded) do previous_modules[name]=value end
 active_mods={base='2.0.77',['space-age']='2.0.77',['space-is-fake']='1.0.60'}
 -- Read the actual declarations, including native-owner bindings. Unrelated
 -- overhaul decoration is outside this controlled retention boundary.
 local progression={legacy_max_level=function(_,_,value) return value end,
   attach_py_sample_continuation=function() end}
 for _,name in ipairs({'angel_petrochem_stream_keys','py_chemical_stream_keys',
   'py_forestry_stream_keys','material_stream_keys','k2_material_stream_keys'}) do
  progression[name]=function() return {} end
 end
 stub('prototypes.mir.families.material_progression',progression)
 stub('prototypes.mir.compatibility.overlay_loader',{get=function() return {
  applies_when={mods={}},capabilities={['recipe-productivity']={exact_recipes={},stream={id='unrelated'}}}
 } end})
 stub('prototypes.mir.platform.factorio.target_profiles',{current=function() return {factorio_version='2.0'} end})
 local declarations=require('prototypes.streams.productivity')
 local buckets={{change=0.1,recipes={'bioplastic','plastic-bar'}}}
 local rows={{recipe='bioplastic',owners='plastic-bar-productivity'},
   {recipe='plastic-bar',owners='plastic-bar-productivity'}}
 local function admitted(spec,original,filtered,covered)
  return owner_policy.retained_earned_buckets('research_plastic',spec or declarations.research_plastic,original or buckets,filtered or {},covered or rows)
 end
 check('ER01',admitted(),'Observed F200 SIF paid identity can retain its complete native-covered effects')
 for _, value in ipairs({'1.0.59','1.0.61'}) do
  active_mods['space-is-fake']=value
  check('ER02-'..value,not admitted(),'Unobserved SIF release cannot admit legacy reward retention')
 end
 active_mods['space-is-fake']='1.0.60'
 active_mods.base='2.1.21'
 check('ER03',not admitted(),'F210 does not inherit the F200 retention observation')
 active_mods.base='2.0.77';active_mods['space-age']=nil
 check('ER04',not admitted(),'Absent Space Age cannot admit the observed native owner set')
 active_mods['space-age']='2.0.77'
 check('ER05',not admitted({automatic_family={}}) and not admitted({native_owner_binding={}}),
   'Automatic families and malformed bindings cannot admit stable reward retention')
 check('ER06',not admitted({technology_name='unrelated-identity'}), 'Retention cannot create a replacement identity')
 check('ER07',not admitted(nil,nil,{{change=0.1,recipes={'new-route'}}}),
   'A partially owned active stream cannot become a hidden legacy stream')
 check('ER08',not admitted(nil,{{change=0.1,recipes={'bioplastic'}}}), 'Missing prior recipe cannot be called complete retention')
 check('ER09',not admitted(nil,{{change=0.1,recipes={'bioplastic','plastic-bar','other'}}}),
   'Retention never grants an additional recipe')
 check('ER10',not admitted(nil,{{change=0.1,recipes={'bioplastic','bioplastic'}}}), 'Duplicate recipes are refused')
 check('ER11',not admitted(nil,nil,nil,{{recipe='bioplastic',owners='unrelated-owner'},rows[2]}),
   'Another owner cannot supply the observed coverage')
 check('ER12',not admitted(nil,nil,nil,{rows[1],{recipe='plastic-bar',owners='plastic-bar-productivity,other'}}),
   'An extra owner remains blocking')
 check('ER13',not admitted(nil,nil,nil,{rows[1],rows[1]}), 'Duplicate coverage cannot hide missing coverage')
 for index, change in ipairs({0,-0.1,math.huge,0/0}) do
  check('ER14-'..index,not admitted(nil,{{change=change,recipes={'bioplastic','plastic-bar'}}}),
    'Only positive finite already-admitted effects can be retained')
 end
 check('ER15',not owner_policy.retained_earned_buckets('unobserved',{},buckets,{},rows),
   'Unobserved research is not added by reward retention')
 check('ER16',#buckets==1 and #buckets[1].recipes==2 and buckets[1].change==0.1 and #rows==2,
   'Retention eligibility does not mutate caller buckets or owner records')
 local observed={
  research_low_density_structure={'casting-low-density-structure','low-density-structure','scrap-recycling'},
  research_plastic={'bioplastic','plastic-bar'}, research_processing_unit={'processing-unit','scrap-recycling'},
  research_rocket_fuel={'ammonia-rocket-fuel','rocket-fuel','rocket-fuel-from-jelly'},
  research_steel={'casting-steel','steel-plate'}
 }
 local selected_buckets, adoption_calls, simulate_adoption=nil,0,false
 stub('prototypes.mir.planner.costs',{enabled_for=function() return true end,
  model_for=function() return {count_formula='100*L'} end,max_level_for=function() return 'infinite' end,
  research_time_for=function() return 30 end})
 stub('prototypes.mir.presentation.icon_builder',{technology_icon_fields_for_stream=function() return {icons={}} end})
 stub('prototypes.mir.capabilities.recipe_productivity.planner',{
  match_buckets=function() return selected_buckets end,
  effects_from_buckets=function(_,values)
   local out={};for _,bucket in ipairs(values) do for _,recipe in ipairs(bucket.recipes) do
    out[#out+1]={type='change-recipe-productivity',recipe=recipe,change=bucket.change}
   end end;return out
  end})
 stub('prototypes.mir.planner.native_owner_binding',{plan=function(_,spec,values)
  adoption_calls=adoption_calls+1
  assert(#values==0,'Legacy retention must not feed covered recipes back into native adoption')
  if simulate_adoption then return {},{},{},spec.native_owner_binding.owner,{operation='preserve_native_owner'} end
  return values,{},{}
 end})
 for _,name in ipairs({'prototypes.mir.planner.direct_effects','prototypes.mir.policy.native_effect_coverage',
   'prototypes.mir.settings.automatic_compiler_policy'}) do stub(name,{}) end
 stub('prototypes.mir.planner.requirements',{missing_reason=function() end})
 stub('prototypes.mir.planner.prerequisites',{build_for=function() return {} end})
 stub('prototypes.mir.planner.science',{ingredients_for_stream=function() return {{'automation-science-pack',1}},'full' end})
 stub('prototypes.mir.platform.factorio.target_line',{feature_enabled=function(name) return name~='productivity_family_adoption' end})
 stub('prototypes.mir.settings.effect_scaling',{scale_stream_effects=function(_,_,effects) return effects end})
 stub('prototypes.mir.domain.research_cost.classification',{anchor_level=function() return 1 end})
 stub('prototypes.mir.planner.stream_compiler.discover',{expand_dynamic_items=function(spec) return spec end})
 stub('prototypes.mir.planner.stream_compiler.ownership',{attach_family_recipes=function(_,values) return values end})
 stub('prototypes.mir.planner.stream_compiler.diagnostics',{
  localized_name=function(key) return key end,localized_description=function() return '' end,
  plan_row=function(key,spec,action,reason,diagnostics,extra) extra.action=action;extra.reason=reason;return extra end,
  skip_row=function(_,_,reason) return {action='skip',reason=reason} end,
  retain_earned_effects=function(row) row.fields.hidden=true;return row end})
 stub('prototypes.mir.report.diagnostics_sink',{stream_fields=function() return {} end})
 local qualifier=require('prototypes.mir.planner.stream_compiler.qualify')
 for key,recipes in pairs(observed) do
  local spec=declarations[key]
  selected_buckets={{change=0.1,recipes=recipes}}
  external_owner_records={}
  for _,recipe in ipairs(recipes) do external_owner_records[recipe]={{
   tech=recipe=='scrap-recycling' and 'scrap-recycling-productivity' or spec.native_owner_binding.owner,
   kind='native',action='skip'
  }} end
  local before=adoption_calls
  local row=qualifier.plan(key,spec)
  check('ER17-'..key,row.action=='emit' and row.fields.hidden and row.technology_name=='recipe-prod-'..key..'-1'
    and adoption_calls==before+1,'Actual F200 qualifier retains canonical bound identity '..key)
  local expected_count=key=='research_processing_unit' and 1 or #recipes
  check('ER18-'..key,#row.fields.effects==expected_count,
    'Retention preserves only the published effect count for '..key)
  for _,effect in ipairs(row.fields.effects) do
   check('ER19-'..key..'-'..effect.recipe,effect.change==0.1
     and (key~='research_processing_unit' or effect.recipe=='processing-unit'),
     'Prior effect retained without adding processing-unit scrap recycling')
  end
  simulate_adoption=true
  local adopted=qualifier.plan(key,spec)
  check('ER20-'..key,adopted.action=='adopt' and not adopted.fields,
    'A supported native adoption remains authoritative over retention')
  simulate_adoption=false
 end
 external_owner_records={};owner_diagnostics={}
 for name in pairs(package.loaded) do package.loaded[name]=nil end
 for name,value in pairs(previous_modules) do package.loaded[name]=value end
 active_mods=previous_mods
end

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
-- A restricted early lab must not redefine the intended later science stage.
-- This is a controlled provenance law, not a Lignumis package qualification.
active_mods={}
local lignumis_stage={
  'wood-science-pack','steam-science-pack','automation-science-pack',
  'logistic-science-pack','chemical-science-pack','production-science-pack'
}
data.raw.lab={
 wood={inputs={'wood-science-pack','steam-science-pack'}},
 late={inputs=lignumis_stage}
}
result,status,phase=planner.ingredients_for_stream('research_science_pack_productivity',{science_packs=lignumis_stage})
check('P11',result and #result==6 and status=='full' and #phase.phase_required_packs==6,
 'A complete later lab retains the declared science-productivity stage: '..names(result))
for _, pack in ipairs({'automation-science-pack','logistic-science-pack','chemical-science-pack','production-science-pack'}) do
 unreachable[pack]=true
end
result,status,phase=planner.ingredients_for_stream('research_science_pack_productivity',{science_packs=lignumis_stage})
check('P12',result==nil and status=='required-unreachable' and #phase.retained_required_packs==6,
 'Unavailable declared late ingredients block instead of silently reducing to the restricted early lab')
unreachable={}
-- K2 retirement is an explicit phase action, so its retired early cards do
-- not remain as requirements while the retained late cards still do.
active_mods={Krastorio2='2.1.2',['Krastorio2-spaced-out']='2.0.13'}
data.raw.lab={late={inputs={'space-science-pack','kr-matter-tech-card'}}}
result,status,phase=planner.ingredients_for_stream('research_science_pack_productivity',mixed)
check('P13',result and #result==2 and status=='full' and has(result,'space-science-pack')
  and not has(result,'automation-science-pack') and #phase.retained_required_packs==2,
 'Explicit K2 retirement preserves only the intended retained late requirements: '..names(result))
active_mods=active_mods_v3
result,status,phase=planner.ingredients_for_stream('research_science_pack_productivity',mixed)
check('V310',result and #result==2 and status=='full' and has(result,'space-science-pack')
  and phase.policy_id=='K2SciencePhasePolicyV3' and #phase.retained_required_packs==2,
  'Planner applies only the exact V3 tuple before its normal lab selection: '..names(result))
print('MIR-SCIENCE-PLANNING-PASS '..checks)
