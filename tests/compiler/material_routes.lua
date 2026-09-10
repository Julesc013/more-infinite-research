local records, cached, builds, risks = {}, {}, 0, {}
local function stub(name, value) package.loaded[name] = value or {} end
for _, name in ipairs{"platform.factorio.prototype_lookup","index.item_prototype_facts","core.deepcopy","core.fingerprint","platform.factorio.target_profiles","report.compiler_telemetry","settings.automatic_compiler_policy"} do stub("prototypes.mir." .. name) end
stub("prototypes.mir.core.fingerprint", {of=function() return "test-fingerprint" end})
stub("prototypes.mir.platform.factorio.target_profiles", {current=function() return {} end})
stub("prototypes.mir.report.compiler_telemetry", {count=function() end,observe_max=function() end})
stub("prototypes.mir.settings.automatic_compiler_policy", {current=function() return {apply_changes=true} end})
stub("prototypes.mir.index.recipe_risk_facts", {view=function(name) return risks[name] end})
stub("prototypes.mir.index.recipe_facts", {
  for_each=function(callback)
    builds=builds+1
    for name, fact in pairs(records) do callback(name, fact) end
  end,
  view=function(name) return records[name] end,
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
local function environment(value) records=value; cached={}; builds=0 end
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

local function reviewed_routes(subject, route, risk, route_certificate, active_mods)
  environment({[subject]=route,reclaim=canonical_route("reclaim", "plate", "ore")})
  risks={[subject]=risk,reclaim=risk_row("reclaim")}
  mods=active_mods or {Krastorio2="2.1.2",["Krastorio2-spaced-out"]="2.0.13"}
  local buckets=matcher.recipes_for_stream({
    items={"plate"},
    require_acyclic_process=true,
    reviewed_forward_routes={[subject]=route_certificate}
  },0.02)
  return buckets[1].recipes
end

local valid_route=canonical_route("smelting","ore","plate")
local valid_certificate=certificate("ore","plate")
local valid_risk_row=risk_row("smelting")
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

print("MIR-MATERIAL-ROUTES-PASS " .. count)