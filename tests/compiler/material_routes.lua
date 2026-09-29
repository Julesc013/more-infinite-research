local records, cached, builds, risks = {}, {}, 0, {}
local productivity_owners, recipe_unlocks, technologies = {}, {}, {}
local function stub(name, value) package.loaded[name] = value or {} end
for _, name in ipairs{"platform.factorio.prototype_lookup","index.item_prototype_facts","core.deepcopy","core.fingerprint","platform.factorio.target_profiles","report.compiler_telemetry","settings.automatic_compiler_policy"} do stub("prototypes.mir." .. name) end
local function fingerprint_text(value)
  local kind=type(value)
  if kind=="nil" or kind=="boolean" or kind=="number" or kind=="string" then return kind..":"..tostring(value) end
  local keys={};for key in pairs(value) do keys[#keys+1]=key end
  table.sort(keys,function(left,right) return type(left)==type(right) and tostring(left)<tostring(right) or type(left)<type(right) end)
  local fields={}
  for _,key in ipairs(keys) do fields[#fields+1]=fingerprint_text(key).."="..fingerprint_text(value[key]) end
  return "{"..table.concat(fields,",").."}"
end
local function test_fingerprint(value)
  local hash=2166136261
  for index=1,#fingerprint_text(value) do hash=(hash*65599+string.byte(fingerprint_text(value),index))%4294967291 end
  return "mir32-"..string.format("%08x",hash)
end
stub("prototypes.mir.core.fingerprint", {of=test_fingerprint})
stub("prototypes.mir.platform.factorio.target_profiles", {current=function() return {} end})
stub("prototypes.mir.report.compiler_telemetry", {count=function() end,observe_max=function() end})
stub("prototypes.mir.settings.automatic_compiler_policy", {current=function() return {apply_changes=true} end})
stub("prototypes.mir.index.recipe_risk_facts", {view=function(name) return risks[name] end})
stub("prototypes.mir.index.relationships", {view=function() return {
  technologies_by_recipe_effect=productivity_owners,
  unlocks_by_recipe=recipe_unlocks
} end})
stub("prototypes.mir.platform.factorio.data_raw", {technology=function(name) return technologies[name] end})
stub("prototypes.mir.index.recipe_facts", {
  for_each=function(callback)
    builds=builds+1
    for name, fact in pairs(records) do callback(name, fact) end
  end,
  view=function(name) return records[name] end,
  index_view=function() return {facts=records} end,
  candidate_names=function()
    local names = {}
    for name in pairs(records) do names[#names+1] = name end
    table.sort(names)
    return names
  end
})
stub("prototypes.mir.pipeline.compiler_context", {current=function() return {
  state_view=function(_,name,builder) if not cached[name] then cached[name]=builder() end; return cached[name] end
} end})
local matcher=require("prototypes.mir.capabilities.recipe_productivity.recipe_matching")
local count=0
local function check(value,message) assert(value,message); count=count+1 end
local function recipe(input,output)
 return {allow_productivity=true,variants={{ingredients={{name=input}},results={{name=output,amount=1}}}}}
end
local function environment(value)
  records=value; cached={}; builds=0
  productivity_owners, recipe_unlocks, technologies = {}, {}, {}
end
local forward=recipe("ore","plate")
environment{smelting=forward,gears=recipe("plate","gear")}
check(matcher.material_route_is_acyclic(forward),"ordinary acyclic manufacturing")
check(matcher.material_route_is_acyclic(forward),"repeated query")
check(builds==1,"one graph per compiler context")
check(forward.variants[1].ingredients[1].name=="ore", "input immutability")
environment{smelting=forward,reclaim=recipe("plate","ore")}
check(not matcher.material_route_is_acyclic(forward),"reversible loop rejected")
records.reclaim.variants[1].results[1].amount=0.000000001
cached={}
check(not matcher.material_route_is_acyclic(forward),"small present return does not certify infinite scaling")
environment{self=recipe("ore","ore")}
check(not matcher.material_route_is_acyclic(records.self),"self return rejected")
environment{smelting=forward,first=recipe("plate","gear"),second=recipe("gear","ore")}
check(not matcher.material_route_is_acyclic(forward),"indirect process neighborhood")
environment{smelting=forward}
check(matcher.material_route_is_acyclic(forward),"context isolation")
local denied=recipe("ore","plate"); denied.allow_productivity=false
check(not matcher.material_route_is_acyclic(denied),"no upstream eligibility override")
check(not matcher.material_route_is_acyclic({allow_productivity=true}),"missing variants fail closed")
cached.material_route_graph={complete=false}
check(not matcher.material_route_is_acyclic(forward),"graph budget fails closed")

local function entry(name, amount, changes)
  local value = {type="item", name=name, amount=amount, probability=1, independent_probability=1}
  for field, change in pairs(changes or {}) do value[field] = change end
  return value
end

local function canonical_route(name, input, output, changes)
  local ingredients = {entry(input, 10, changes and changes.ingredients)}
  local results = {entry(output, 5, changes and changes.results)}
  return {
    name=name,
    source_class="ordinary",
    hidden=false,
    allow_productivity=true,
    declared_allow_productivity=true,
    effective_allow_productivity=true,
    effective_maximum_productivity=3.0,
    productive_result_names={output},
    variants={{
      ingredients=ingredients,
      results=results,
      allow_productivity=true,
      declared_allow_productivity=true,
      effective_allow_productivity=true,
      effective_maximum_productivity=3.0
    }}
  }
end

local valid_risk="mir32-0123abcd"
local function risk_row(recipe, changes)
  local row={
    schema=1,
    recipe=recipe,
    hard_flags={},
    review_flags={},
    shared_input_output={},
    evidence_confidence=1.0,
    risk_fingerprint=valid_risk
  }
  for field, value in pairs(changes or {}) do row[field]=value end
  return row
end
local function certificate(input, output, changes)
  return {
    id="material-route-test-v1",
    evidence_id="A05-test-evidence-v1",
    maximum_productivity=3.0,
    profiles={{
      id="locked-k2so-2.0.13",
      mod_locks={Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13"},
      canonical_risk_fingerprint=valid_risk
    }},
    ingredients={entry(input, 10, changes and changes.ingredients)},
    results={entry(output, 5, changes and changes.results)}
  }
end

local function reviewed_routes(subject, route, risk, route_certificate, active_mods, relevant_inputs)
  environment({[subject]=route,reclaim=canonical_route("reclaim", "plate", "ore")})
  risks={[subject]=risk,reclaim=risk_row("reclaim")}
  mods=active_mods or {Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13"}
  if relevant_inputs then
    productivity_owners[subject]=relevant_inputs.owners or {}
    recipe_unlocks[subject]=relevant_inputs.unlocks or {}
    technologies=relevant_inputs.technologies or {}
    for name, witness in pairs(relevant_inputs.witnesses or {}) do records[name]=witness end
  end
  local buckets=matcher.recipes_for_stream({
    items={"plate"},
    require_acyclic_process=true,
    reviewed_forward_routes={[subject]=route_certificate}
  },0.02)
  return buckets[1].recipes
end

local function certificate_required_routes(subject, route, risk, route_certificate, active_mods, graph_override, include_return)
  local available = {[subject]=route}
  if include_return then available.reclaim=canonical_route("reclaim", "plate", "ore") end
  environment(available)
  risks={[subject]=risk}
  mods=active_mods or {Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13"}
  if graph_override then cached.material_route_graph=graph_override end
  local buckets=matcher.recipes_for_stream({
    items={"plate"},
    require_acyclic_process=true,
    require_exact_route_certificate=true,
    reviewed_forward_routes={[subject]=route_certificate}
  },0.02)
  return buckets[1].recipes
end

local function ordinary_acyclic_routes(subject, route, risk)
  environment({[subject]=route})
  risks={[subject]=risk}
  mods={Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13"}
  local buckets=matcher.recipes_for_stream({
    items={"plate"},
    require_acyclic_process=true
  },0.02)
  return buckets[1].recipes
end

local valid_route=canonical_route("smelting","ore","plate")
local valid_certificate=certificate("ore","plate")
local valid_risk_row=risk_row("smelting")
check(table.concat(ordinary_acyclic_routes("smelting",valid_route,valid_risk_row),",")=="smelting","ordinary acyclic route remains admitted without opting into certificates")
check(table.concat(certificate_required_routes("smelting",valid_route,valid_risk_row,valid_certificate),",")=="smelting","exact certificate can require an ordinary acyclic route")
check(#certificate_required_routes("smelting",valid_route,valid_risk_row,nil)==0,"certificate-required route rejects absent certificate despite acyclic graph")
check(#certificate_required_routes("smelting",valid_route,valid_risk_row,valid_certificate,{Krastorio2="2.1.2",["Krastorio2-spaced-out"]="9.9.9"})==0,"certificate-required route rejects wrong locked mod")
check(#certificate_required_routes("smelting",valid_route,valid_risk_row,valid_certificate,{Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13",extra="1.0.0"})==0,"certificate-required route rejects extra mod")
check(#certificate_required_routes("smelting",valid_route,valid_risk_row,certificate("ore","gear"))==0,"certificate-required route rejects output mismatch")
check(#certificate_required_routes("smelting",valid_route,valid_risk_row,valid_certificate,nil,{complete=false})==0,"certificate-required route cannot override graph budget")
local search_edges={}
local previous="plate"
for index=1,30001 do
  local next_name="search-node-"..index
  search_edges[previous]={[next_name]=true}
  previous=next_name
end
check(#certificate_required_routes("smelting",valid_route,valid_risk_row,valid_certificate,nil,{complete=true,edges=search_edges})==0,"certificate-required route cannot override search budget")
check(table.concat(certificate_required_routes("smelting",valid_route,valid_risk_row,valid_certificate,nil,nil,true),",")=="smelting","certificate-required reviewed return accepts exact certificate")
check(#certificate_required_routes("smelting",valid_route,valid_risk_row,certificate("ore","gear"),nil,nil,true)==0,"certificate-required reviewed return rejects invalid certificate")
local certificate_denied_route=canonical_route("smelting","ore","plate")
certificate_denied_route.declared_allow_productivity=false
check(#certificate_required_routes("smelting",certificate_denied_route,valid_risk_row,valid_certificate)==0,"certificate-required route preserves productivity denial")
check(#certificate_required_routes("smelting",valid_route,risk_row("smelting",{review_flags={"cleaning_or_recovery_loop"}}),valid_certificate)==0,"certificate-required route rejects canonical risk")
local observer_certificate=certificate("ore","plate")
observer_certificate.profiles[1].observer_mod_locks={observer="0.1.0"}
check(table.concat(reviewed_routes("smelting",valid_route,valid_risk_row,observer_certificate,{Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13"}),",")=="smelting","optional observer may be absent")
check(table.concat(reviewed_routes("smelting",valid_route,valid_risk_row,observer_certificate,{Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13",observer="0.1.0"}),",")=="smelting","exact optional observer may be present")
check(#reviewed_routes("smelting",valid_route,valid_risk_row,observer_certificate,{Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13",observer="9.9.9"})==0,"wrong observer version rejects reviewed route")
check(table.concat(reviewed_routes("smelting",valid_route,valid_risk_row,valid_certificate),",")=="smelting","reviewed forward route accepts exact ordinary locked fact")
check(#reviewed_routes("smelting",valid_route,valid_risk_row,nil)==0,"no certificate leaves potential return withheld")
check(#reviewed_routes("smelting",valid_route,risk_row("smelting",{hard_flags={"catalyst_or_self_return"}}),valid_certificate)==0,"hard canonical risk cannot be overridden")
check(#reviewed_routes("smelting",valid_route,risk_row("smelting",{review_flags={"cleaning_or_recovery_loop"}}),valid_certificate)==0,"review canonical risk cannot be overridden")
check(#reviewed_routes("smelting",valid_route,risk_row("smelting",{risk_fingerprint="mir32-01234567"}),valid_certificate)==0,"risk fingerprint must match matched version lock")
check(#reviewed_routes("smelting",valid_route,risk_row("smelting",{risk_fingerprint="sha256-0123abcd"}),valid_certificate)==0,"noncanonical risk fingerprint cannot be accepted")
check(#reviewed_routes("smelting",valid_route,valid_risk_row,valid_certificate,{Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.17"})==0,"version lock alternatives cannot cross-bind risk")
check(#reviewed_routes("smelting",valid_route,valid_risk_row,valid_certificate,{Krastorio2="2.1.2"})==0,"missing locked mod rejects reviewed route")
check(#reviewed_routes("smelting",valid_route,valid_risk_row,valid_certificate,{Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13",extra="1.0.0"})==0,"extra active mod rejects reviewed route")
check(#reviewed_routes("smelting",valid_route,valid_risk_row,valid_certificate,{Krastorio2="2.1.2",["Krastorio2-spaced-out"]="9.9.9"})==0,"wrong locked mod version rejects reviewed route")

-- A named-provider certificate retains MIR package-version bookkeeping only
-- when its direct facts and disabled return witnesses still match. An
-- arbitrary extra mod has no complete graph-boundary certificate and remains
-- withheld even if its declared purpose is QoL.
local function blocked_witness(name, input, output)
  return {
    name=name,
    source_class="hidden-internal",
    hidden=true,
    enabled_without_research=false,
    variants={{
      enabled=false,
      hidden=true,
      ingredients={entry(input, 2)},
      results={entry(output, 1)}
    }}
  }
end

local function relevant_certificate()
  local value=certificate("ore","plate")
  value.profiles[1].mod_lock_scope="named-relevant-providers"
  value.relevant_input_contract={
    productivity_owner_technologies={},
    return_path="ore",
    return_witnesses={{
      name="return-witness",
      source_class="hidden-internal",
      hidden=true,
      enabled_without_research=false,
      variants={{
        enabled=false,
        hidden=true,
        ingredients={entry("intermediate", 2)},
        results={entry("ore", 1)}
      }}
    }},
    unlock_technologies={{
      name="plate-unlock",
      science_ingredients={{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1}},
      prerequisites={"precedent"}
    }}
  }
  return value
end
local function relevant_world(changes)
  local value={
    owners={},
    unlocks={"plate-unlock"},
    technologies={
      ["plate-unlock"]={
        unit={ingredients={{"automation-science-pack",1},{"logistic-science-pack",1}}},
        prerequisites={"precedent"}
      }
    },
    witnesses={
      ["return-witness"]=blocked_witness("return-witness", "intermediate", "ore")
    }
  }
  for field, change in pairs(changes or {}) do value[field]=change end
  return value
end
local relevant_certificate_value=relevant_certificate()
local relevant_mods={Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13",["more-infinite-research"]="4.2.20001"}
check(table.concat(reviewed_routes("smelting",valid_route,valid_risk_row,relevant_certificate_value,relevant_mods,relevant_world()),",")=="smelting","relevant-input certificate retains an unchanged route with MIR package-version bookkeeping")
check(#reviewed_routes("smelting",valid_route,valid_risk_row,relevant_certificate_value,{Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13",["more-infinite-research"]="4.2.20001",qol="1.0.0"},relevant_world())==0,"unlisted QoL addition remains withheld without a complete return-graph boundary")
local changed_io_route=canonical_route("smelting","ore","plate")
changed_io_route.variants[1].results[1].amount=6
check(#reviewed_routes("smelting",changed_io_route,valid_risk_row,relevant_certificate_value,relevant_mods,relevant_world())==0,"relevant-input certificate rejects producer output drift")
local changed_permission_route=canonical_route("smelting","ore","plate")
changed_permission_route.declared_allow_productivity=false
changed_permission_route.variants[1].declared_allow_productivity=false
check(#reviewed_routes("smelting",changed_permission_route,valid_risk_row,relevant_certificate_value,relevant_mods,relevant_world())==0,"relevant-input certificate rejects productivity permission drift")
local changed_cap_route=canonical_route("smelting","ore","plate")
changed_cap_route.effective_maximum_productivity=3.01
changed_cap_route.variants[1].effective_maximum_productivity=3.01
check(#reviewed_routes("smelting",changed_cap_route,valid_risk_row,relevant_certificate_value,relevant_mods,relevant_world())==0,"relevant-input certificate rejects domain-cap drift")
check(#reviewed_routes("smelting",valid_route,risk_row("smelting",{review_flags={"cleaning_or_recovery_loop"}}),relevant_certificate_value,relevant_mods,relevant_world())==0,"relevant-input certificate rejects canonical-risk drift")
check(#reviewed_routes("smelting",valid_route,valid_risk_row,relevant_certificate_value,relevant_mods,relevant_world({owners={"external-productivity"}}))==0,"relevant-input certificate rejects productivity-owner drift")
check(#reviewed_routes("smelting",valid_route,valid_risk_row,relevant_certificate_value,relevant_mods,relevant_world({unlocks={"other-unlock"}}))==0,"relevant-input certificate rejects unlock-boundary drift")
check(#reviewed_routes("smelting",valid_route,valid_risk_row,relevant_certificate_value,relevant_mods,relevant_world({technologies={
  ["plate-unlock"]={unit={ingredients={{"automation-science-pack",1},{"chemical-science-pack",1}}},prerequisites={"precedent"}}
}}))==0,"relevant-input certificate rejects unlock-science drift")
check(#reviewed_routes("smelting",valid_route,valid_risk_row,relevant_certificate_value,relevant_mods,relevant_world({technologies={
  ["plate-unlock"]={unit={ingredients={{"automation-science-pack",1},{"logistic-science-pack",1}}},prerequisites={"other-precedent"}}
}}))==0,"relevant-input certificate rejects unlock-prerequisite drift")
local changed_return_certificate=relevant_certificate()
changed_return_certificate.relevant_input_contract.return_path="other-input"
check(#reviewed_routes("smelting",valid_route,valid_risk_row,changed_return_certificate,relevant_mods,relevant_world())==0,"relevant-input certificate rejects return-endpoint drift")
local revealed_witness=relevant_world()
revealed_witness.witnesses["return-witness"].hidden=false
revealed_witness.witnesses["return-witness"].variants[1].hidden=false
check(#reviewed_routes("smelting",valid_route,valid_risk_row,relevant_certificate_value,relevant_mods,revealed_witness)==0,"relevant-input certificate rejects an unhidden return witness")
local enabled_witness=relevant_world()
enabled_witness.witnesses["return-witness"].enabled_without_research=true
enabled_witness.witnesses["return-witness"].variants[1].enabled=true
check(#reviewed_routes("smelting",valid_route,valid_risk_row,relevant_certificate_value,relevant_mods,enabled_witness)==0,"relevant-input certificate rejects an enabled return witness")
local altered_witness=relevant_world()
altered_witness.witnesses["return-witness"].variants[1].results[1].amount=2
check(#reviewed_routes("smelting",valid_route,valid_risk_row,relevant_certificate_value,relevant_mods,altered_witness)==0,"relevant-input certificate rejects same-endpoint return-witness I/O drift")

-- A complete typed return-cone certificate admits an added mod only when its
-- recipe changes are disconnected from this material route.  It includes the
-- direct finished-output producers so a reverse-only alternative cannot hide
-- outside the directed cone.
local function graph_world()
  return {
    smelting=canonical_route("smelting","ore","plate"),
    downstream=canonical_route("downstream","plate","gear")
  }
end
local graph_mods={Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13",qol="1.0.0"}
local function graph_certificate_for(world, bindings)
  environment(world)
  risks={smelting=risk_row("smelting")}
  mods=graph_mods
  productivity_owners=(bindings and bindings.owners) or {}
  recipe_unlocks=(bindings and bindings.unlocks) or {}
  technologies=(bindings and bindings.technologies) or {}
  local facts=assert(matcher.relevant_route_fingerprints(world.smelting))
  local value=certificate("ore","plate")
  value.require_exact_route_certificate=true
  value.profiles[1].mod_lock_scope="relevant-return-graph"
  value.relevant_return_graph_contract=facts
  return value
end
local function graph_routes(world, route_certificate, bindings)
  environment(world)
  risks={smelting=risk_row("smelting")}
  mods=graph_mods
  productivity_owners=(bindings and bindings.owners) or {}
  recipe_unlocks=(bindings and bindings.unlocks) or {}
  technologies=(bindings and bindings.technologies) or {}
  local buckets=matcher.recipes_for_stream({
    items={},
    recipe_patterns={"^smelting$"},
    require_acyclic_process=true,
    reviewed_forward_routes={smelting=route_certificate}
  },0.02)
  return buckets[1].recipes
end
local graph_certificate_value=graph_certificate_for(graph_world())
check(table.concat(graph_routes(graph_world(),graph_certificate_value),",")=="smelting","complete return-graph certificate admits disconnected QoL addition")
local disconnected_world=graph_world()
disconnected_world.qol_utility=canonical_route("qol_utility","coal","ash")
check(table.concat(graph_routes(disconnected_world,graph_certificate_value),",")=="smelting","disconnected added producer remains qualified")
local connected_return_world=graph_world()
connected_return_world.qol_return=canonical_route("qol_return","plate","ore")
check(#graph_routes(connected_return_world,graph_certificate_value)==0,"connected return edge rejects the affected route")
local same_endpoint_world=graph_world()
same_endpoint_world.qol_step=canonical_route("qol_step","plate","qol-intermediate")
same_endpoint_world.qol_same_endpoint=canonical_route("qol_same_endpoint","qol-intermediate","ore")
check(#graph_routes(same_endpoint_world,graph_certificate_value)==0,"same-endpoint alternative return path rejects the affected route")
local producer_world=graph_world()
producer_world.qol_plate=canonical_route("qol_plate","scrap","plate")
check(#graph_routes(producer_world,graph_certificate_value)==0,"connected finished-output producer rejects the affected route")
local hidden_world=graph_world()
hidden_world.downstream.hidden=true
check(#graph_routes(hidden_world,graph_certificate_value)==0,"hidden-state change inside return cone rejects the affected route")
local enabled_world=graph_world()
enabled_world.downstream.enabled_without_research=false
check(#graph_routes(enabled_world,graph_certificate_value)==0,"enabled-state change inside return cone rejects the affected route")
local cap_world=graph_world()
cap_world.smelting.effective_maximum_productivity=3.01
cap_world.smelting.variants[1].effective_maximum_productivity=3.01
check(#graph_routes(cap_world,graph_certificate_value)==0,"higher productivity cap rejects the affected route")
local owner_world=graph_world()
check(#graph_routes(owner_world,graph_certificate_value,{owners={smelting={"external-productivity"}}})==0,"owner change rejects the affected route")
local unlocked_world=graph_world()
local unlock_bindings={
  unlocks={smelting={"plate-unlock"}},
  technologies={ ["plate-unlock"]={unit={ingredients={{"automation-science-pack",1},{"logistic-science-pack",1}}},prerequisites={"precedent"}} }
}
environment(unlocked_world)
risks={smelting=risk_row("smelting")}
mods=graph_mods
productivity_owners=unlock_bindings.owners or {}
recipe_unlocks=unlock_bindings.unlocks
technologies=unlock_bindings.technologies
local unlocked_graph_certificate=graph_certificate_for(unlocked_world,unlock_bindings)
check(table.concat(graph_routes(unlocked_world,unlocked_graph_certificate,unlock_bindings),",")=="smelting","exact unlock binding remains qualified")
local changed_unlock_bindings={
  unlocks={smelting={"plate-unlock"}},
  technologies={ ["plate-unlock"]={unit={ingredients={{"automation-science-pack",1},{"chemical-science-pack",1}}},prerequisites={"precedent"}} }
}
check(#graph_routes(graph_world(),unlocked_graph_certificate,changed_unlock_bindings)==0,"science change rejects the affected route")
local changed_unlock_set={
  unlocks={smelting={"other-unlock"}},
  technologies={ ["other-unlock"]={unit={ingredients={{"automation-science-pack",1}}},prerequisites={"precedent"}} }
}
check(#graph_routes(graph_world(),unlocked_graph_certificate,changed_unlock_set)==0,"unlock change rejects the affected route")

local denied_route=canonical_route("smelting","ore","plate")
denied_route.declared_allow_productivity=false
check(#reviewed_routes("smelting",denied_route,valid_risk_row,valid_certificate)==0,"certificate cannot override declared productivity denial")
local capped_route=canonical_route("smelting","ore","plate")
capped_route.effective_maximum_productivity=3.01
check(#reviewed_routes("smelting",capped_route,valid_risk_row,valid_certificate)==0,"certificate cannot exceed finite productivity cap")
local ignored_stats_route=canonical_route("smelting","ore","plate",{results={ignored_by_stats=1}})
check(#reviewed_routes("smelting",ignored_stats_route,valid_risk_row,certificate("ore","plate",{results={ignored_by_stats=1}}))==0,"ignored-by-stats semantic drift rejects certificate")
local temperature_route=canonical_route("smelting","ore","plate",{results={temperature=42}})
check(table.concat(reviewed_routes("smelting",temperature_route,valid_risk_row,certificate("ore","plate",{results={temperature=42}})),",")=="smelting","exact temperature semantics can be bound")
local fluidbox_route=canonical_route("smelting","ore","plate",{ingredients={fluidbox_index=2}})
check(table.concat(reviewed_routes("smelting",fluidbox_route,valid_risk_row,certificate("ore","plate",{ingredients={fluidbox_index=2}})),",")=="smelting","exact fluidbox semantics can be bound")
local freshness_route=canonical_route("smelting","ore","plate",{results={always_fresh=true}})
check(table.concat(reviewed_routes("smelting",freshness_route,valid_risk_row,certificate("ore","plate",{results={always_fresh=true}})),",")=="smelting","exact freshness semantics can be bound")
local quality_route=canonical_route("smelting","ore","plate",{results={quality_change=1}})
check(table.concat(reviewed_routes("smelting",quality_route,valid_risk_row,certificate("ore","plate",{results={quality_change=1}})),",")=="smelting","exact quality semantics can be bound")
local probabilistic_route=canonical_route("smelting","ore","plate",{results={declared_probability=0.5,probability=0.5,independent_probability=0.5}})
check(#reviewed_routes("smelting",probabilistic_route,valid_risk_row,certificate("ore","plate",{results={declared_probability=0.5,probability=0.5,independent_probability=0.5}}))==0,"declared probability cannot be blessed by an exact certificate")
local shared_route=canonical_route("smelting","ore","plate",{results={name="ore"}})
check(#reviewed_routes("smelting",shared_route,risk_row("smelting",{hard_flags={"catalyst_or_self_return"}}),valid_certificate)==0,"shared input output cannot use certificate")
local catalyst_route=canonical_route("smelting","ore","plate",{results={catalyst_amount=1}})
check(#reviewed_routes("smelting",catalyst_route,valid_risk_row,certificate("ore","plate",{results={catalyst_amount=1}}))==0,"catalyst semantics cannot be blessed by an exact certificate")
local ranged_route=canonical_route("smelting","ore","plate",{results={amount_min=5,amount_max=5}})
check(#reviewed_routes("smelting",ranged_route,valid_risk_row,certificate("ore","plate",{results={amount_min=5,amount_max=5}}))==0,"ranged amounts cannot be blessed by an exact certificate")
local shared_probability_route=canonical_route("smelting","ore","plate",{results={shared_probability=0.5}})
check(#reviewed_routes("smelting",shared_probability_route,valid_risk_row,certificate("ore","plate",{results={shared_probability=0.5}}))==0,"shared probability cannot be blessed by an exact certificate")
local extra_count_route=canonical_route("smelting","ore","plate",{results={extra_count_fraction=0.5}})
check(#reviewed_routes("smelting",extra_count_route,valid_risk_row,certificate("ore","plate",{results={extra_count_fraction=0.5}}))==0,"extra count fraction cannot be blessed by an exact certificate")
local ignored_productivity_route=canonical_route("smelting","ore","plate",{results={ignored_by_productivity=1}})
check(#reviewed_routes("smelting",ignored_productivity_route,valid_risk_row,certificate("ore","plate",{results={ignored_by_productivity=1}}))==0,"ignored productivity cannot be blessed by an exact certificate")
check(#reviewed_routes("smelting",valid_route,risk_row("smelting",{shared_input_output={"ore"}}),valid_certificate)==0,"canonical shared-input-output authority cannot be overridden")
check(#reviewed_routes("smelting",valid_route,risk_row("smelting",{schema=2}),valid_certificate)==0,"risk schema must be canonical")
check(#reviewed_routes("smelting",valid_route,risk_row("other-recipe"),valid_certificate)==0,"risk recipe must bind candidate recipe")
check(#reviewed_routes("smelting",valid_route,risk_row("smelting",{hard_flags={[2]="gap"}}),valid_certificate)==0,"risk arrays must be dense")
local default_disabled_route=canonical_route("smelting","ore","plate")
default_disabled_route.declared_allow_productivity=nil
default_disabled_route.effective_allow_productivity=false
default_disabled_route.allow_productivity=false
default_disabled_route.variants[1].declared_allow_productivity=nil
default_disabled_route.variants[1].effective_allow_productivity=false
check(#reviewed_routes("smelting",default_disabled_route,valid_risk_row,valid_certificate)==0,"certificate cannot override default-disabled productivity")
local variant_denied_route=canonical_route("smelting","ore","plate")
variant_denied_route.variants[1].declared_allow_productivity=false
variant_denied_route.variants[1].effective_allow_productivity=false
check(#reviewed_routes("smelting",variant_denied_route,valid_risk_row,valid_certificate)==0,"certificate cannot override variant-level productivity denial")
local multiple_variant_route=canonical_route("smelting","ore","plate")
multiple_variant_route.variants[2]=multiple_variant_route.variants[1]
check(#reviewed_routes("smelting",multiple_variant_route,valid_risk_row,valid_certificate)==0,"certificate requires one exact final variant")
local unknown_field_route=canonical_route("smelting","ore","plate",{results={future_normalized_semantic=true}})
check(#reviewed_routes("smelting",unknown_field_route,valid_risk_row,certificate("ore","plate",{results={future_normalized_semantic=true}}))==0,"unknown normalized entry fields fail closed")

-- The retained F200 Bob/Angel additions have a typed route boundary. The
-- descriptor may retain that declaration with an unrelated extra mod, but
-- each selected final must carry a required boundary certificate; altered
-- locked providers and F210 still fall back to their established declarations.
local function clone_map(value)
  local out={}
  for key, entry in pairs(value) do out[key]=entry end
  return out
end

local f200_bob_angel_mods={
  base="2.0.77", boblibrary="2.1.0", bobores="2.1.2", bobplates="2.1.1",
  bobelectronics="2.1.1", bobtech="2.1.0", angelsrefining="2.0.4",
  angelsrefininggraphics="2.0.0", angelspetrochem="2.0.3",
  angelspetrochemgraphics="2.0.1", angelssmelting="2.0.5",
  angelssmeltinggraphics="2.0.0", ["more-infinite-research"]="4.2.20000"
}

local function material_streams_for(profile, active_mods, item_names)
  local saved_mods,saved_data=mods,data
  mods=active_mods
  data={extend=function() end}
  local overlay={
    applies_when={mods={"fixture"}},
    capabilities={
      ["recipe-productivity"]={exact_recipes={},deny_risk_flags={},stream={id="fixture"}}
    }
  }
  stub("prototypes.mir.compatibility.overlay_loader",{get=function() return overlay end})
  stub("prototypes.mir.platform.factorio.target_profiles",{current=function() return profile end})
  stub("prototypes.mir.platform.factorio.prototype_lookup",{item_prototype=function(name) return item_names[name] end})
  package.loaded["prototypes.streams.productivity"]=nil
  local streams=require("prototypes.streams.productivity")
  package.loaded["prototypes.streams.productivity"]=nil
  mods,data=saved_mods,saved_data
  return streams
end

local function recipe_patterns(stream)
  return table.concat(stream.groups[1].recipe_patterns,"|")
end

local f200_items={["iron-plate"]={},["angels-wire-platinum"]={}}
local exact_f200_mods=clone_map(f200_bob_angel_mods)
exact_f200_mods["mir-fixture-assert-f200-bob-angel-material-routes-observation"]="0.1.0"
local exact_f200_streams=material_streams_for({factorio_version="2.0"},exact_f200_mods,f200_items)
check(recipe_patterns(exact_f200_streams.research_material_aluminium)=="^bob%-aluminium%-plate$|^angels%-plate%-aluminium$|^angels%-plate%-aluminium%-2$","exact F200 lock retains observed Angel aluminium finals")
check(recipe_patterns(exact_f200_streams.research_material_nickel)=="^bob%-nickel%-plate$|^angels%-plate%-nickel$|^angels%-plate%-nickel%-2$","exact F200 lock retains observed Angel nickel finals")
check(recipe_patterns(exact_f200_streams.research_material_silver)=="^bob%-silver%-plate$|^angels%-plate%-silver$|^angels%-plate%-silver%-2$|^angels%-wire%-silver%-2$","exact F200 lock retains observed Angel silver plate and final-wire routes")
check(recipe_patterns(exact_f200_streams.research_material_gold)=="^bob%-gold%-plate$|^angels%-plate%-gold$|^angels%-plate%-gold%-2$|^angels%-wire%-gold%-2$","exact F200 lock retains observed Angel gold plate and final-wire routes")
check(recipe_patterns(exact_f200_streams.research_material_platinum)=="^angels%-wire%-platinum%-2$","exact F200 lock retains observed Angel platinum final")
check(exact_f200_streams.research_material_nickel.reviewed_forward_routes["angels-plate-nickel"]~=nil and exact_f200_streams.research_material_silver.reviewed_forward_routes["angels-plate-silver"]~=nil,"exact F200 lock retains reviewed return-route certificates")
local f200_nickel_cast_contract=exact_f200_streams.research_material_nickel.reviewed_forward_routes["angels-plate-nickel"].relevant_input_contract
local f200_silver_roll_contract=exact_f200_streams.research_material_silver.reviewed_forward_routes["angels-plate-silver-2"].relevant_input_contract
local f200_nickel_graph_contract=exact_f200_streams.research_material_nickel.reviewed_forward_routes["angels-plate-nickel"].relevant_return_graph_contract
local f200_gold_wire_certificate=exact_f200_streams.research_material_gold.reviewed_forward_routes["angels-wire-gold-2"]
local f200_silver_wire_certificate=exact_f200_streams.research_material_silver.reviewed_forward_routes["angels-wire-silver-2"]
check(f200_nickel_cast_contract.return_path=="angels-liquid-molten-nickel" and #f200_nickel_cast_contract.productivity_owner_technologies==0 and f200_nickel_cast_contract.unlock_technologies[1].name=="angels-nickel-smelting-1" and #f200_nickel_cast_contract.return_witnesses==2 and f200_nickel_cast_contract.return_witnesses[1].name=="bob-silver-from-lead","Nickel certificate binds its observed owner and blocked casting-return witnesses")
check(f200_silver_roll_contract.return_path=="angels-roll-silver" and f200_silver_roll_contract.unlock_technologies[1].name=="angels-silver-casting-2" and #f200_silver_roll_contract.unlock_technologies[1].science_ingredients==3,"Silver certificate binds its observed roll unlock and science boundary")
check(f200_nickel_graph_contract.return_graph_fingerprint=="mir32-a27ea44e" and f200_nickel_graph_contract.bindings_fingerprint=="mir32-ccf3ca93" and f200_nickel_graph_contract.relevant_recipe_count==1488 and exact_f200_streams.research_material_nickel.reviewed_forward_routes["angels-plate-nickel"].require_exact_route_certificate,"Nickel certificate requires its full typed return-graph boundary")
check(f200_gold_wire_certificate and f200_gold_wire_certificate.id=="F200-BA-gold-wire-final-v1" and f200_gold_wire_certificate.require_exact_route_certificate and f200_gold_wire_certificate.relevant_input_contract==nil and f200_gold_wire_certificate.relevant_return_graph_contract.return_graph_fingerprint=="mir32-c4953ea9" and f200_gold_wire_certificate.relevant_return_graph_contract.bindings_fingerprint=="mir32-f029b315","Gold wire final requires its observed acyclic return-cone certificate without a fabricated blocked-return witness")
check(f200_silver_wire_certificate and f200_silver_wire_certificate.id=="F200-BA-silver-wire-final-v1" and f200_silver_wire_certificate.require_exact_route_certificate and f200_silver_wire_certificate.relevant_input_contract==nil and f200_silver_wire_certificate.relevant_return_graph_contract.return_graph_fingerprint=="mir32-99c58542" and f200_silver_wire_certificate.relevant_return_graph_contract.bindings_fingerprint=="mir32-53f936f8","Silver wire final requires its observed acyclic return-cone certificate without a fabricated blocked-return witness")
local f200_complete_certificate_routes={
  research_material_aluminium={"angels-plate-aluminium","angels-plate-aluminium-2"},
  research_material_gold={"angels-plate-gold","angels-plate-gold-2","angels-wire-gold-2"},
  research_material_lead={"angels-plate-lead","angels-plate-lead-2"},
  research_material_nickel={"angels-plate-nickel","angels-plate-nickel-2"},
  research_material_platinum={"angels-wire-platinum-2"},
  research_material_silver={"angels-plate-silver","angels-plate-silver-2","angels-wire-silver-2"},
  research_material_tin={"angels-plate-tin","angels-plate-tin-2"},
  research_material_titanium={"angels-plate-titanium","angels-plate-titanium-2"},
  research_material_copper_tungsten={"bob-copper-tungsten-alloy"},
  research_material_zinc={"angels-plate-zinc","angels-plate-zinc-2"},
  research_material_bronze={"angels-plate-bronze"}, research_material_brass={"angels-plate-brass"},
  research_material_gunmetal={"angels-plate-gunmetal"}, research_material_invar={"angels-plate-invar"},
  research_material_cobalt_steel={"angels-plate-cobalt-steel"}, research_material_nitinol={"angels-plate-nitinol"}
}
local f200_complete_certificate_count=0
for stream_name, recipes in pairs(f200_complete_certificate_routes) do
  local certificates=exact_f200_streams[stream_name].reviewed_forward_routes
  for _, recipe_name in ipairs(recipes) do
    local certificate=certificates and certificates[recipe_name]
    check(certificate and certificate.require_exact_route_certificate and certificate.relevant_return_graph_contract and certificate.relevant_return_graph_contract.schema==1,"exact F200 route has a required typed boundary certificate "..recipe_name)
    f200_complete_certificate_count=f200_complete_certificate_count+1
  end
end
check(f200_complete_certificate_count==26,"all 26 emitted F200 final routes across the sixteen materials retain typed boundary certificates")
check(exact_f200_streams.research_material_imersite.required_items[1]=="kr-imersite-crystal" and exact_f200_streams.research_material_imersite.icon_item=="kr-imersite-powder","F200 route gate preserves Imersite native-owner and MIR-powder identities")
check(exact_f200_streams.research_material_silicon.reviewed_forward_routes["kr-silicon"]~=nil and exact_f200_streams.research_material_glass.reviewed_forward_routes["kr-glass"]~=nil,"F200 route gate preserves retained K2 silicon and glass certificates")

local changed_f200_mods=clone_map(exact_f200_mods)
changed_f200_mods.angelssmelting="2.0.6"
local changed_f200_streams=material_streams_for({factorio_version="2.0"},changed_f200_mods,f200_items)
check(recipe_patterns(changed_f200_streams.research_material_aluminium)=="^bob%-aluminium%-plate$","changed F200 closure leaves Aluminium on Bob declaration")
check(recipe_patterns(changed_f200_streams.research_material_nickel)=="^bob%-nickel%-plate$" and changed_f200_streams.research_material_nickel.reviewed_forward_routes==nil,"changed F200 closure withdraws Angel nickel routes and certificate")
check(recipe_patterns(changed_f200_streams.research_material_silver)=="^bob%-silver%-plate$" and changed_f200_streams.research_material_silver.reviewed_forward_routes==nil,"changed F200 closure withdraws Angel silver routes and certificate")
check(recipe_patterns(changed_f200_streams.research_material_gold)=="^bob%-gold%-plate$" and recipe_patterns(changed_f200_streams.research_material_platinum)=="^bob%-platinum%-plate$","changed F200 closure withdraws unproven Angel gold and platinum finals")

local extra_f200_mods=clone_map(exact_f200_mods)
extra_f200_mods.qol="1.0.0"
local extra_f200_streams=material_streams_for({factorio_version="2.0"},extra_f200_mods,f200_items)
check(recipe_patterns(extra_f200_streams.research_material_lead)=="^bob%-lead%-plate$|^bob%-lead%-plate%-2$|^angels%-plate%-lead$|^angels%-plate%-lead%-2$","disconnected QoL mod retains the F200 Angel lead declaration behind certificates")
check(recipe_patterns(extra_f200_streams.research_material_nickel)=="^bob%-nickel%-plate$|^angels%-plate%-nickel$|^angels%-plate%-nickel%-2$" and extra_f200_streams.research_material_nickel.reviewed_forward_routes["angels-plate-nickel"].require_exact_route_certificate,"disconnected QoL mod retains Nickel only with its complete return-graph certificate")
check(recipe_patterns(extra_f200_streams.research_material_gold)=="^bob%-gold%-plate$|^angels%-plate%-gold$|^angels%-plate%-gold%-2$|^angels%-wire%-gold%-2$" and extra_f200_streams.research_material_gold.reviewed_forward_routes["angels-wire-gold-2"].require_exact_route_certificate,"disconnected QoL mod retains Gold wire only with its complete return-graph certificate")
check(recipe_patterns(extra_f200_streams.research_material_silver)=="^bob%-silver%-plate$|^angels%-plate%-silver$|^angels%-plate%-silver%-2$|^angels%-wire%-silver%-2$" and extra_f200_streams.research_material_silver.reviewed_forward_routes["angels-wire-silver-2"].require_exact_route_certificate,"disconnected QoL mod retains Silver wire only with its complete return-graph certificate")

local changed_mir_version_mods=clone_map(exact_f200_mods)
changed_mir_version_mods["more-infinite-research"]="4.2.20001"
local changed_mir_version_streams=material_streams_for({factorio_version="2.0"},changed_mir_version_mods,f200_items)
check(recipe_patterns(changed_mir_version_streams.research_material_nickel)=="^bob%-nickel%-plate$|^angels%-plate%-nickel$|^angels%-plate%-nickel%-2$" and changed_mir_version_streams.research_material_nickel.reviewed_forward_routes["angels-plate-nickel"]~=nil,"MIR package-version bookkeeping retains the exact Nickel relevant-input routes")
check(recipe_patterns(changed_mir_version_streams.research_material_gold)=="^bob%-gold%-plate$|^angels%-plate%-gold$|^angels%-plate%-gold%-2$|^angels%-wire%-gold%-2$" and changed_mir_version_streams.research_material_gold.reviewed_forward_routes["angels-wire-gold-2"]~=nil,"MIR package-version bookkeeping retains the Gold wire route under its graph certificate")
check(recipe_patterns(changed_mir_version_streams.research_material_silver)=="^bob%-silver%-plate$|^angels%-plate%-silver$|^angels%-plate%-silver%-2$|^angels%-wire%-silver%-2$" and changed_mir_version_streams.research_material_silver.reviewed_forward_routes["angels-wire-silver-2"]~=nil,"MIR package-version bookkeeping retains the Silver wire route under its graph certificate")

local f210_bob_angel_tin_mods={
  base="2.1.20", ["elevated-rails"]="2.1.20", quality="2.1.20", recycler="2.1.20", ["space-age"]="2.1.20",
  boblibrary="3.0.1", bobores="3.0.0", bobplates="3.0.2", bobelectronics="3.0.1", bobtech="3.0.0",
  angelsrefining="2.1.2", angelsrefininggraphics="2.1.0", angelspetrochem="2.1.3", angelspetrochemgraphics="2.1.0",
  angelssmelting="2.1.1", angelssmeltinggraphics="2.1.1", ["more-infinite-research"]="4.2.21000",
  ["mir-fixture-assert-f210-current-bob-angel-tin-route-observer"]="0.1.0"
}
local exact_f210_tin_streams=material_streams_for({factorio_version="2.1"},f210_bob_angel_tin_mods,f200_items)
local exact_f210_tin_certificate=exact_f210_tin_streams.research_material_tin.reviewed_forward_routes
  and exact_f210_tin_streams.research_material_tin.reviewed_forward_routes["angels-plate-tin"]
local exact_f210_tin_roll_certificate=exact_f210_tin_streams.research_material_tin.reviewed_forward_routes
  and exact_f210_tin_streams.research_material_tin.reviewed_forward_routes["angels-plate-tin-2"]
check(recipe_patterns(exact_f210_tin_streams.research_material_tin)=="^angels%-plate%-tin$|^angels%-plate%-tin%-2$","exact current F210 Bob/Angel profile selects only visible Angel Tin finals")
check(exact_f210_tin_certificate and exact_f210_tin_roll_certificate and exact_f210_tin_certificate.require_exact_route_certificate and exact_f210_tin_roll_certificate.require_exact_route_certificate,"exact current F210 Tin finals require reviewed certificates")
check(exact_f210_tin_certificate.id=="F210-BA-tin-casting-final-v1" and exact_f210_tin_certificate.relevant_return_graph_contract.return_graph_fingerprint=="mir32-60b04faf" and exact_f210_tin_certificate.relevant_return_graph_contract.bindings_fingerprint=="mir32-1a2afdfa" and exact_f210_tin_certificate.relevant_input_contract.return_witnesses[1].name=="bob-bronze-alloy" and exact_f210_tin_certificate.relevant_input_contract.unlock_technologies[1].name=="angels-tin-smelting-1","exact current F210 Tin casting certificate binds graph, witness, and unlock")
check(exact_f210_tin_roll_certificate.id=="F210-BA-tin-roll-final-v1" and exact_f210_tin_roll_certificate.relevant_return_graph_contract.return_graph_fingerprint=="mir32-5fc52628" and exact_f210_tin_roll_certificate.relevant_return_graph_contract.bindings_fingerprint=="mir32-2fbc823d" and #exact_f210_tin_roll_certificate.relevant_input_contract.unlock_technologies[1].science_ingredients==2,"exact current F210 Tin rolling certificate binds graph and two-science unlock")

local changed_f210_tin_mods=clone_map(f210_bob_angel_tin_mods)
changed_f210_tin_mods.bobplates="3.0.3"
local changed_f210_tin_streams=material_streams_for({factorio_version="2.1"},changed_f210_tin_mods,f200_items)
check(recipe_patterns(changed_f210_tin_streams.research_material_tin)=="^bob%-tin%-plate$" and changed_f210_tin_streams.research_material_tin.reviewed_forward_routes==nil,"changed F210 Bob provider withdraws Tin finals and certificates")

local missing_f210_tin_mods=clone_map(f210_bob_angel_tin_mods)
missing_f210_tin_mods.angelspetrochem=nil
local missing_f210_tin_streams=material_streams_for({factorio_version="2.1"},missing_f210_tin_mods,f200_items)
check(recipe_patterns(missing_f210_tin_streams.research_material_tin)=="^bob%-tin%-plate$" and missing_f210_tin_streams.research_material_tin.reviewed_forward_routes==nil,"missing F210 Angel provider withdraws Tin finals and certificates")

local f210_streams=material_streams_for({factorio_version="2.1"},exact_f200_mods,f200_items)
check(recipe_patterns(f210_streams.research_material_tin)=="^bob%-tin%-plate$" and recipe_patterns(f210_streams.research_material_gold)=="^bob%-gold%-plate$" and recipe_patterns(f210_streams.research_material_silver)=="^bob%-silver%-plate$" and f210_streams.research_material_nickel.reviewed_forward_routes==nil,"F210 retains F200-only Angel additions outside the exact current Tin certificate")

print("MIR-MATERIAL-ROUTES-PASS " .. count)
