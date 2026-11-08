"""Finite native-continuation ownership controls; not native qualification."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Independent names of the six optional extensions of shared Base research.
# Productivity research and private paid-state holders are outside this policy.
NATIVE_TAILS = (
    "braking-force-8", "inserter-capacity-bonus-8", "laser-shooting-speed-8",
    "research-speed-7", "weapon-shooting-speed-7", "worker-robots-storage-4",
)

# Native Base2.1.23 technology.lua3694-3720 (file0FE834C5) and the exact
# old8643 finite-base-extension-level producer9888359a, independently reviewed
# in historical intent. Icons are a host presentation stand-in. No candidate
# constructor or catalogue supplies these input costs/effects or the8 oracle.
FINITE_SPEED_INPUT = r'''
  function clone_speed(value)
    if type(value)~="table" then return value end
    local out={};for key,item in pairs(value)do out[key]=clone_speed(item)end;return out
  end
  function finite_speed_raw()
    local six={type="technology",name="research-speed-6",upgrade=true,
      icons={{icon="__base__/graphics/technology/research-speed.png",icon_size=256}},
      effects={{type="laboratory-speed",modifier=.6}},
      prerequisites={"research-speed-5","utility-science-pack"},
      unit={count=500,time=30,ingredients={{"automation-science-pack",1},{"logistic-science-pack",1},
        {"chemical-science-pack",1},{"production-science-pack",1},{"utility-science-pack",1}}}}
    local raw={technology={[six.name]=six},tool={},item={},recipe={},lab={}}
    local seven=clone_speed(six)
    seven.name="research-speed-7";seven.level=7;seven.max_level=nil
    seven.prerequisites={"research-speed-6"}
    seven.unit={count=777,ingredients={{"automation-science-pack",1}},time=77}
    raw.technology[seven.name]=seven
    for _,id in ipairs({"research-speed-5","automation-science-pack","logistic-science-pack",
        "chemical-science-pack","production-science-pack","military-science-pack","utility-science-pack"})do
      raw.technology[id]={type="technology",name=id}
      if id~="research-speed-5" then raw.tool[id]={type="tool",name=id} end
    end
    return raw
  end
  function speed_definition(raw)
    for _,row in ipairs(require("compatibility.modern_catalogue").continuations({},raw)) do
      if row.family=="research-speed" then return row end
    end
  end
  function speed_settings(overrides)
    local config=require("research.settings");local startup={}
    for _,spec in ipairs(config.prototypes())do startup[spec.name]={value=spec.default_value}end
    for key,value in pairs(overrides or {})do startup[key]={value=value}end
    return config.resolve(startup)
  end
'''


class ContinuationOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.globals().tail_names = self.lua.table_from(NATIVE_TAILS)
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          modern = require("compatibility.modern_catalogue")
          function ids(rows)
            local result = {}
            for _, row in ipairs(rows) do
              assert(not result[row.id], "duplicate authored continuation")
              result[row.id] = true
            end
            return result
          end
          function foreign_tail(name)
            local facts = {
              ["braking-force-8"]={"braking-force-7", {{type="train-braking-force-bonus", modifier=.27}}},
              ["inserter-capacity-bonus-8"]={"inserter-capacity-bonus-7", {
                {type="inserter-stack-size-bonus", modifier=1}, {type="bulk-inserter-capacity-bonus", modifier=2}}},
              ["laser-shooting-speed-8"]={"laser-shooting-speed-7", {{type="gun-speed", ammo_category="laser", modifier=.27}}},
              ["research-speed-7"]={"research-speed-6", {{type="laboratory-speed", modifier=.27}}},
              ["weapon-shooting-speed-7"]={"weapon-shooting-speed-6", {
                {type="gun-speed", ammo_category="bullet", modifier=.27}, {type="gun-speed", ammo_category="shotgun-shell", modifier=.27}}},
              ["worker-robots-storage-4"]={"worker-robots-storage-3", {{type="worker-robot-storage", modifier=1}}},
            }
            local fact = assert(facts[name])
            return {type="technology", name=name, max_level="infinite",
              prerequisites={fact[1], "foreign-prerequisite"}, effects=fact[2],
              unit={count_formula="123*2^(L-1)", time=37,
                ingredients={{"foreign-science-pack", 2}}}, marker="foreign"}
          end
          function runtime(technologies, creator)
            script = {active_mods={base="2.1.23", ["more-infinite-research"]="5.0.21002"}}
            local calls = {}
            prototypes = {technology=technologies, get_history=function(kind, name)
              assert(kind == "technology" and technologies[name] ~= nil)
              calls[name] = (calls[name] or 0) + 1
              return {created=creator, changed={"science-spread", "another-mod"}}
            end}
            game = setmetatable({}, {__index=function() error("read game during control parsing") end})
            package.loaded["research.catalogue"], package.loaded["runtime.catalogue"] = nil, nil
            return require("runtime.catalogue"), calls
          end
        ''')

    def test_uncolliding_six_native_extensions_remain_declared(self):
        self.lua.execute('''
          local selected, count = ids(modern.continuations({})), 0
          for _ in pairs(selected) do count = count + 1 end
          assert(count == 6)
          for _, name in ipairs(tail_names) do assert(selected[name], name) end
        ''')

    def test_finite_research_speed_uses_historical_eight_without_mutating_seven(self):
        self.lua.execute(FINITE_SPEED_INPUT)
        self.lua.execute('''
          local raw=finite_speed_raw();local six=raw.technology["research-speed-6"]
          local seven=raw.technology["research-speed-7"]
          local unit,effects,prerequisites=seven.unit,seven.effects,seven.prerequisites
          local row=speed_definition(raw)
          assert(row.id=="research-speed-8" and row.level==8 and row.predecessor==seven.name)
          local output=require("research.modern").continuation(row,speed_settings())
          assert(output.name=="research-speed-8" and output.level==8 and output.max_level=="infinite")
          assert(output.unit.count_formula=="1025.15625*1.5^(L-8)" and output.unit.time==120)
          assert(output.effects[1].type=="laboratory-speed" and output.effects[1].modifier==.6)
          assert(output.prerequisites[1]==six.name and output.prerequisites[2]==seven.name)
          assert(output.unit.ingredients[1][1]=="automation-science-pack")
          local writes=0
          require("research.generator").install({output},{raw=raw,extend=function()writes=writes+1 end})
          assert(writes==1 and raw.technology[seven.name]==seven)
          output.effects[1].modifier=9;output.unit.ingredients[1][1]="caller-change"
          assert(seven.unit==unit and seven.effects==effects and seven.prerequisites==prerequisites)
          assert(unit.count==777 and unit.time==77 and unit.ingredients[1][1]=="automation-science-pack")
          assert(effects[1].modifier==.6 and six.unit.count==500 and six.unit.time==30)
          raw.technology[seven.name]=nil
          assert(speed_definition(raw).id=="research-speed-7")
        ''')

    def test_finite_research_speed_tuning_inherits_actual_predecessors(self):
        self.lua.execute(FINITE_SPEED_INPUT)
        self.lua.execute('''
          local row=speed_definition(finite_speed_raw());local build=require("research.modern").continuation
          for _,case in ipairs({
            {{["mir-cost-base-research-speed"]=0},"1165.500140625*1.5^(L-8)",120},
            {{["mir-cost-growth-research-speed"]=0},"1313.13189949337*1.554^(L-8)",120},
            {{["mir-research-time-research-speed"]=0},"1025.15625*1.5^(L-8)",77},
            {{["mir-cost-base-research-speed"]=0,["mir-cost-growth-research-speed"]=0,
              ["mir-research-time-research-speed"]=0},"1207.45760988164*1.554^(L-8)",77}})do
            local out=build(row,speed_settings(case[1]))
            assert(out.unit.count_formula==case[2],out.unit.count_formula)
            assert(out.unit.time==case[3] and out.effects[1].modifier==.6)
          end
          local raw=finite_speed_raw()
          raw.technology["research-speed-7"].effects={{type="laboratory-speed",modifier=.75},
            {type="laboratory-productivity",modifier=.02}}
          row=speed_definition(raw)
          local normal=build(row,speed_settings())
          local changed=build(row,speed_settings({["mir-effect-per-level-research-speed"]=30}))
          assert(normal.effects[1].modifier==.75 and normal.effects[2].modifier==.02)
          assert(changed.effects[1].modifier==.375 and changed.effects[2].modifier==.02)
          raw.technology["research-speed-6"].unit.count=nil
          raw.technology["research-speed-6"].unit.count_formula="500*L"
          local inherited=build(speed_definition(raw),speed_settings({["mir-cost-base-research-speed"]=0,
            ["mir-cost-growth-research-speed"]=0,["mir-research-time-research-speed"]=0}))
          assert(inherited.unit.count_formula=="777" and inherited.unit.time==77)
        ''')

    def test_finite_research_speed_keeps_strict_collision_and_owner_controls(self):
        self.lua.execute(FINITE_SPEED_INPUT)
        self.lua.execute('''
          for _,mode in ipairs({"missing-six","wrong-anchor","malformed-unit","unrelated-effects"})do
            local raw=finite_speed_raw();local seven=raw.technology["research-speed-7"]
            if mode=="missing-six"then raw.technology["research-speed-6"]=nil
            elseif mode=="wrong-anchor"then seven.prerequisites={"research-speed-5"}
            elseif mode=="malformed-unit"then seven.unit.count=-1
            else seven.effects={{type="laboratory-productivity",modifier=.1}} end
            assert(speed_definition(raw).id=="research-speed-7",mode)
          end
          local raw=finite_speed_raw();raw.technology["research-speed-7"].max_level="infinite"
          assert(speed_definition(raw)==nil)
          raw=finite_speed_raw();raw.technology["research-speed-8"]={type="technology",name="research-speed-8"}
          local out=require("research.modern").continuation(speed_definition(raw),speed_settings())
          local writes=0;local generator=require("research.generator")
          local ok,message=pcall(generator.install,{out},{raw=raw,extend=function()writes=writes+1 end})
          assert(not ok and tostring(message):find("duplicate technology research-speed-8",1,true) and writes==0)
          raw.technology["research-speed-8"]=nil
          ok,message=pcall(generator.install,{out,out},{raw=raw,extend=function()writes=writes+1 end})
          assert(not ok and tostring(message):find("duplicate technology research-speed-8",1,true) and writes==0)
          raw.technology["research-speed-8"]={type="technology",name="research-speed-8",level=8,max_level="infinite",
            prerequisites={"research-speed-7"},effects={{type="laboratory-speed",modifier=.5}},
            unit={count_formula="900*L",time=30,ingredients={{"automation-science-pack",1}}}}
          assert(speed_definition(raw)==nil)
        ''')

    def test_finite_research_speed_science_matches_recovered_base_expectation(self):
        import test_science as fixture
        fixture.LuaRuntime = LuaRuntime
        harness = fixture.ScienceTests()
        harness.setUp()
        harness.lua.execute(FINITE_SPEED_INPUT)
        harness.lua.execute('''
          local raw=finite_speed_raw()
          local packs={"automation-science-pack","logistic-science-pack","chemical-science-pack",
            "production-science-pack","military-science-pack","utility-science-pack","space-science-pack"}
          raw.lab.lab={name="lab",inputs=packs};raw.tool["space-science-pack"]={name="space-science-pack"}
          install_sources(raw,false)
          raw["rocket-silo-rocket"]={["rocket-silo-rocket"]={name="rocket-silo-rocket",inventory_size=0}}
          local values=speed_settings();local out=require("research.modern").continuation(speed_definition(raw),values)
          local reports=science.apply_family({out},nil,{raw=raw,options=values.options,target={id="f210"},mods={base="2.1.23"}})
          assert(reports[1].enabled~=false,reports[1].reason)
          assert(names(out.unit.ingredients)=="automation-science-pack:1,logistic-science-pack:1,chemical-science-pack:1,production-science-pack:1,military-science-pack:1,utility-science-pack:1",names(out.unit.ingredients))
          assert(table.concat(out.prerequisites,",")=="research-speed-6,research-speed-7,automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack,military-science-pack,utility-science-pack",table.concat(out.prerequisites,","))
          -- The shifted identity is covered by the actual science pass,
          -- including an inherited retired ingredient/gate, not a name table.
          out.unit.ingredients[#out.unit.ingredients+1]={"space-science-pack",7}
          out.prerequisites[#out.prerequisites+1]="space-science-pack"
          raw.technology["space-science-pack"].enabled=false
          reports=science.apply_family({out},nil,{raw=raw,options=values.options,target={id="f210"},
            mods={base="2.1.23",["space-age"]="2.1.23",["space-is-fake"]="1.0.78"}})
          assert(reports[1].enabled~=false,reports[1].reason)
          assert(not names(out.unit.ingredients):find("space-science-pack",1,true))
          assert(not table.concat(out.prerequisites,","):find("space-science-pack",1,true))
        ''')

    def test_finite_research_speed_runtime_caps_target_only_mir_eight(self):
        self.lua.execute('''
          local seven={name="research-speed-7",valid=true,level=7,enabled=false,researched=true,
            visible_when_disabled=false,saved_progress=0,prototype={name="research-speed-7",max_level=7,enabled=true}}
          local eight={name="research-speed-8",valid=true,level=10,enabled=true,researched=false,
            visible_when_disabled=false,saved_progress=.27,
            prototype={name="research-speed-8",max_level=4294967295,enabled=true}}
          local other={name="foreign-current",valid=true}
          local world={index=1,valid=true,technologies={[seven.name]=seven,[eight.name]=eight,[other.name]=other},
            research_queue={other,eight},current_research=other,research_progress=.42}
          seven.force,eight.force,other.force=world,world,world
          script={active_mods={base="2.1.23",["more-infinite-research"]="5.0.21007",provider="1.0"}}
          prototypes={recipe={},technology=setmetatable({[seven.name]=seven.prototype,[eight.name]=eight.prototype},
            {__pairs=function()error("whole-prototype scan")end}),get_history=function(kind,name)
              assert(kind=="technology" and (name==seven.name or name==eight.name))
              return {created=name==seven.name and "provider" or "more-infinite-research",changed={"science-spread"}}
            end}
          local config=require("research.settings");settings={startup={}}
          for _,spec in ipairs(config.prototypes())do settings.startup[spec.name]={value=spec.default_value}end
          settings.startup["mir-max-level-research-speed"].value=5
          game,storage={forces={[1]=world}},{}
          package.loaded["research.catalogue"],package.loaded["runtime.catalogue"],package.loaded["runtime.configuration"]=nil,nil,nil
          local catalogue=require("runtime.catalogue");local declared=ids(catalogue.declared())
          assert(declared[eight.name] and not declared[seven.name])
          assert(catalogue.finite_research_speed_provider()=="provider")
          assert(not catalogue.externally_supplied_continuation(seven.name))
          local row
          for _,value in ipairs(catalogue.declared())do if value.id==eight.name then row=value end end
          assert(row.progression==8 and row.cap_setting=="mir-max-level-research-speed" and row.family=="research-speed")
          local lifecycle=require("runtime.lifecycle");local limits=lifecycle.cap_limits(world)
          assert(limits[eight.name]==5 and limits[seven.name]==nil)
          lifecycle.on_init()
          assert(not eight.enabled and eight.level==10 and eight.saved_progress==.27 and not eight.researched)
          assert(not seven.enabled and seven.researched and seven.level==7 and not seven.visible_when_disabled)
          assert(#world.research_queue==1 and world.research_queue[1]==other)
          assert(world.current_research==other and world.research_progress==.42)
          assert(storage.mir_caps.owned_disabled[1][eight.name] and not storage.mir_caps.owned_disabled[1][seven.name])
        ''')

    def test_finite_research_speed_runtime_variant_follows_final_creation_custody(self):
        self.lua.execute('''
          for _,mode in ipairs({"own8","foreign8","missing8","wrong8","unknown8","default7"})do
            script={active_mods={base="2.1.23",["more-infinite-research"]="5.0.21007"}}
            local seven={name="research-speed-7",max_level=mode=="default7" and 4294967295 or 7}
            local eight={name="research-speed-8",max_level=mode=="wrong8" and 8 or 4294967295}
            local technologies={[seven.name]=seven,[eight.name]=mode~="missing8" and eight or nil}
            prototypes={technology=technologies,get_history=function(kind,name)
              if name==seven.name then return {created=mode=="default7" and "more-infinite-research" or "provider"}end
              if mode=="unknown8"then return {}end
              return {created=(mode=="own8" or mode=="wrong8") and "more-infinite-research" or "other-provider"}
            end}
            package.loaded["research.catalogue"],package.loaded["runtime.catalogue"]=nil,nil
            local ok,catalogue=pcall(require,"runtime.catalogue")
            if mode=="missing8" or mode=="wrong8" or mode=="unknown8"then assert(not ok,mode)
            else
              assert(ok,tostring(catalogue));local declared=ids(catalogue.declared())
              assert((declared["research-speed-8"]==true)==(mode=="own8"))
              assert((declared["research-speed-7"]==true)==(mode=="default7"))
              assert((catalogue.externally_supplied_continuation("research-speed-7")==true)==(mode=="foreign8"))
            end
          end
        ''')

    def test_finite_research_speed_guard_requires_actual_prior_variant_proof(self):
        self.lua.execute('''
          local guard=require("runtime.finite_research_speed")
          local function marker(provider)
            return {schema=1,technology="research-speed-8",predecessor="research-speed-7",provider=provider}
          end
          local function emitted(cap)
            return {mir={maximum_level_control={policy_version=3,managed_technologies={
              ["research-speed-8"]={technology="research-speed-8",setting="mir-max-level-research-speed",
                source="base-continuation",operation="emit_base_extension",policy_transport="transported-v3",
                ownership_kind="transported-v3",legacy=false,native_finite_stage=false,
                binding_fingerprint="mir32-1234abcd",selected=cap}}}}}
          end
          storage={};guard.on_init(nil);assert(next(storage)==nil);guard.on_load(nil)
          storage={};guard.on_init("provider");local old=storage.mir_finite_research_speed
          assert(old.provider=="provider");guard.on_load("provider");assert(storage.mir_finite_research_speed==old)
          local unrelated={mod_changes={unrelated={old_version="1",new_version="2"}},mod_startup_settings_changed=true}
          assert(guard.preflight(unrelated,"provider")==nil)
          for _,provider in ipairs({false,"other-provider"})do
            local ok,message=pcall(guard.preflight,{},provider or nil)
            assert(not ok and tostring(message):find("finite research-speed ownership",1,true))
            assert(storage.mir_finite_research_speed==old)
          end
          local ok=pcall(guard.preflight,{mod_changes={provider={new_version="2"}}},"provider")
          assert(not ok and storage.mir_finite_research_speed==old)
          for _,old_version in ipairs({"5.0.21007","4.7.21003","4.9.21000"})do
            storage={};local event={mod_changes={["more-infinite-research"]={old_version=old_version,new_version="5.0.21008"}},mod_startup_settings_changed=false}
            assert(not pcall(guard.preflight,event,"provider"));assert(next(storage)==nil)
          end
          for _,cap in ipairs({"infinite",8})do
            storage=emitted(cap);local legacy=storage.mir
            local event={mod_changes={["more-infinite-research"]={old_version="4.7.21003",new_version="5.0.21008"}},mod_startup_settings_changed=false}
            guard.on_load("provider");assert(storage.mir==legacy and storage.mir_finite_research_speed==nil)
            local plan=guard.preflight(event,"provider");assert(plan.provider=="provider" and storage.mir==legacy)
            assert(storage.mir_finite_research_speed==nil);guard.apply(plan)
            assert(storage.mir_finite_research_speed==plan and storage.mir==legacy)
          end
          for _,mode in ipairs({"settings-derived","settings-derived-removal","wrong-id","fingerprint","blocked","finite-holder","startup-change","wrong-event-field","text-event-field","provider-add","provider-update","former-provider-removed","former-provider-updated","unknown-version","wrong-source-edition","noncanonical-version","absent-variant"})do
            storage=emitted("infinite");local bucket=storage.mir.maximum_level_control;local row=bucket.managed_technologies["research-speed-8"]
            local event={mod_changes={["more-infinite-research"]={old_version="4.7.21003",new_version="5.0.21008"}},mod_startup_settings_changed=false}
            if mode=="settings-derived" or mode=="settings-derived-removal"then row.operation="runtime-settings-transport";row.policy_transport="settings-derived-v3";row.ownership_kind="settings-derived-v3";row.technology=nil;row.binding_fingerprint=nil
            elseif mode=="wrong-id"then row.technology="research-speed-7"
            elseif mode=="fingerprint"then row.binding_fingerprint="unknown"
            elseif mode=="blocked"then row.blocked_reason="conflict"
            elseif mode=="finite-holder"then row.native_finite_stage=true
            elseif mode=="startup-change"then event.mod_startup_settings_changed=true;event.startup_settings_changed=false
            elseif mode=="wrong-event-field"then event.mod_startup_settings_changed=nil;event.startup_settings_changed=false
            elseif mode=="text-event-field"then event.mod_startup_settings_changed="false"
            elseif mode=="provider-add"then event.mod_changes.provider={new_version="1"}
            elseif mode=="provider-update"then event.mod_changes.provider={old_version="1",new_version="2"}
            elseif mode=="former-provider-removed"then event.mod_changes.former_provider={old_version="1"}
            elseif mode=="former-provider-updated"then event.mod_changes.former_provider={old_version="1",new_version="2"}
            elseif mode=="unknown-version"then event.mod_changes["more-infinite-research"].old_version="4.9.21000"
            elseif mode=="wrong-source-edition"then event.mod_changes["more-infinite-research"].old_version="4.7.20003"
            elseif mode=="noncanonical-version"then event.mod_changes["more-infinite-research"].old_version="4.07.21003" end
            local ok,message=pcall(guard.preflight,event,(mode~="absent-variant" and mode~="settings-derived-removal") and "provider" or nil)
            assert(not ok,mode);assert(storage.mir_finite_research_speed==nil and storage.mir.maximum_level_control==bucket)
          end
          storage={};local plan=guard.preflight({mod_changes={["more-infinite-research"]={new_version="5.0.21008"}}},"provider")
          assert(plan.provider=="provider" and next(storage)==nil)
          storage={mir_finite_research_speed=marker("provider")};storage.mir_finite_research_speed.schema=9
          assert(not pcall(guard.preflight,{},"provider"));assert(storage.mir_finite_research_speed.schema==9)
          storage={};guard.on_load("provider");assert(next(storage)==nil)
          assert(not pcall(guard.preflight,{mod_changes={["more-infinite-research"]={old_version="5.0.21007",new_version="5.0.21008"}},mod_startup_settings_changed=false},"provider"))
          assert(next(storage)==nil)
        ''')

    def test_finite_research_speed_native_callback_order_preflights_before_writes(self):
        import test_lifecycle as fixture
        fixture.LuaRuntime = LuaRuntime
        harness = fixture.LifecycleTests()
        harness.setUp()
        harness.lua.execute('''
          for _,legacy in ipairs({true,false})do
            local seven=technology("research-speed-7",7,false);seven.researched=true
            local eight=technology("research-speed-8",10,true);eight.saved_progress=.27
            seven.prototype.max_level=7;eight.prototype.max_level=4294967295
            local current=technology("foreign-current",1,true)
            local world=force(1,{[seven.name]=seven,[eight.name]=eight,[current.name]=current},{current,eight},current,.42)
            seven.force,eight.force,current.force=world,world,world
            local saved={}
            if legacy then saved.mir={maximum_level_control={policy_version=3,managed_technologies={
              [eight.name]={technology=eight.name,setting="mir-max-level-research-speed",source="base-continuation",
                operation="emit_base_extension",policy_transport="transported-v3",ownership_kind="transported-v3",
                legacy=false,native_finite_stage=false,binding_fingerprint="mir32-1234abcd",selected="infinite"}}}}
            else setmetatable(saved,{__newindex=function()error("MIR wrote before ownership refusal")end})end
            boot({[1]=world},0,"",saved,nil,0,{base="2.1.23",["more-infinite-research"]="5.0.21007",provider="1"},
              nil,nil,nil,nil,function(kind,name)
                assert(kind=="technology" and (name==seven.name or name==eight.name))
                return {created=name==seven.name and "provider" or "more-infinite-research"}
              end,{[seven.name]=seven.prototype,[eight.name]=eight.prototype})
            -- Existing native mods load before their configuration event. No
            -- marker is available yet on the first admitted legacy entry.
            handlers.load();assert(saved.mir_finite_research_speed==nil and saved.mir_caps==nil)
            local old=legacy and "4.7.21003" or "5.0.21006"
            local ok,message=pcall(handlers.configuration,{mod_changes={["more-infinite-research"]={
              old_version=old,new_version="5.0.21007"}},mod_startup_settings_changed=false})
            if legacy then
              assert(ok,tostring(message));assert(saved.mir_finite_research_speed.provider=="provider")
            else
              assert(not ok and tostring(message):find("finite research-speed ownership",1,true),tostring(message))
              assert(next(saved)==nil)
            end
            assert(seven.level==7 and seven.researched and not seven.enabled)
            assert(eight.level==10 and eight.saved_progress==.27 and eight.enabled)
            assert(world.current_research==current and world.research_progress==.42 and #world.research_queue==2)
          end
        ''')

    def test_each_existing_foreign_infinite_owner_is_preserved(self):
        self.lua.execute('''
          for _, name in ipairs(tail_names) do
            local foreign = foreign_tail(name)
            local effects, unit, prerequisites = foreign.effects, foreign.unit, foreign.prerequisites
            local modifier = effects[1].modifier
            local owners = {}
            local rows = modern.continuations({}, {technology={[name]=foreign}}, owners)
            local selected = ids(rows)
            assert(not selected[name], "MIR retained foreign infinite tail " .. name)
            assert(owners[name] == foreign, "lost the admitted external owner for bounded coverage")
            for _, other in ipairs(tail_names) do
              if other ~= name then assert(selected[other], "lost unrelated tail " .. other) end
            end
            assert(foreign.effects == effects and foreign.effects[1].modifier == modifier)
            assert(foreign.unit == unit and unit.time == 37 and unit.count_formula == "123*2^(L-1)")
            assert(unit.ingredients[1][1] == "foreign-science-pack" and unit.ingredients[1][2] == 2)
            assert(foreign.prerequisites == prerequisites and prerequisites[2] == "foreign-prerequisite")
            assert(foreign.marker == "foreign" and foreign.max_level == "infinite")
          end
        ''')

    def test_multiple_external_native_tails_do_not_hide_unrelated_conflicts(self):
        self.lua.execute('''
          local technologies = {}
          for _, name in ipairs(tail_names) do technologies[name] = foreign_tail(name) end
          assert(next(ids(modern.continuations({}, {technology=technologies}))) == nil)
          local generator = require("research.generator")
          for _, name in ipairs({"recipe-prod-research_gears-1", "mir-legacy-module-credit-speed-module"}) do
            local writes = 0
            local ok, message = pcall(generator.install, {{type="technology", name=name}}, {
              raw={technology={[name]={marker="foreign"}}},
              extend=function() writes = writes + 1 end})
            assert(not ok and tostring(message):find("duplicate technology " .. name, 1, true))
            assert(writes == 0, "foreign conflict wrote prototypes")
          end
        ''')

    def test_internal_native_tail_duplicate_still_fails_before_any_write(self):
        self.lua.execute('''
          local generator, writes = require("research.generator"), 0
          local name = "weapon-shooting-speed-7"
          local ok, message = pcall(generator.install,
            {{type="technology", name=name}, {type="technology", name=name}}, {
              raw={technology={}}, extend=function() writes = writes + 1 end})
          assert(not ok and tostring(message):find("duplicate technology " .. name, 1, true))
          assert(writes == 0, "internal duplicate wrote prototypes")
        ''')

    def test_finite_or_unrelated_colliders_are_not_accepted_as_infinite_owners(self):
        self.lua.execute('''
          for _, name in ipairs(tail_names) do
            for _, mode in ipairs({"finite", "unrelated-effect", "wrong-anchor", "missing-unit"}) do
              local foreign = foreign_tail(name)
              if mode == "finite" then foreign.max_level = nil
              elseif mode == "unrelated-effect" then foreign.effects = {{type="laboratory-productivity", modifier=.1}}
              elseif mode == "wrong-anchor" then foreign.prerequisites = {"foreign-prerequisite"}
              else foreign.unit = nil end
              assert(ids(modern.continuations({}, {technology={[name]=foreign}}))[name],
                "invalid owner silently removed MIR's infinite family: " .. name .. ":" .. mode)
            end
          end
        ''')

    def test_muria_exact_finite_chain_selects_nine_and_preserves_default_effects(self):
        self.lua.execute('''
          local categories = {"bullet", "shotgun-shell", "cannon-shell", "rocket", "explosive-shotgun-shell"}
          local modifiers = {.25, .20, 1.35, .65, .20}
          local function stage(name, predecessor, count)
            local effects = {}
            for i, category in ipairs(categories) do effects[i] = {type="gun-speed", ammo_category=category, modifier=modifiers[i]} end
            return {type="technology", name=name, effects=effects, prerequisites={predecessor, "acidworking-science-pack"},
              unit={count=count, time=60, ingredients={{"automation-science-pack",1},{"logistic-science-pack",1},
                {"chemical-science-pack",1},{"military-science-pack",1},{"utility-science-pack",1},
                {"space-science-pack",1},{"acidworking-science-pack",1}}}}
          end
          local seven = stage("weapon-shooting-speed-7", "weapon-shooting-speed-6", 2500)
          local eight = stage("weapon-shooting-speed-8", "weapon-shooting-speed-7", 5000)
          local raw = {technology={[seven.name]=seven, [eight.name]=eight}}
          local rows = modern.continuations({Muria="1.8.5"}, raw)
          local definition
          for _, row in ipairs(rows) do
            assert(row.id ~= seven.name and row.id ~= eight.name)
            if row.id == "weapon-shooting-speed-9" then assert(not definition); definition = row end
          end
          assert(definition and definition.family == "weapon-shooting-speed" and definition.level == 9)
          assert(definition.predecessor == eight.name and #definition.prerequisites == 1)
          local config, startup = require("research.settings"), {}
          for _, spec in ipairs(config.prototypes()) do startup[spec.name] = {value=spec.default_value} end
          startup["mir-cost-base-weapon-shooting-speed"].value = 0
          startup["mir-cost-growth-weapon-shooting-speed"].value = 0
          startup["mir-research-time-weapon-shooting-speed"].value = 0
          local build = require("research.modern").continuation
          local output = build(definition, config.resolve(startup))
          assert(output.name == "weapon-shooting-speed-9" and output.max_level == "infinite")
          assert(output.prerequisites[1] == eight.name and #output.unit.ingredients == 7)
          assert(output.unit.ingredients[7][1] == "acidworking-science-pack" and output.unit.time == 60)
          assert(load("return function(L) return " .. output.unit.count_formula .. " end")()(9) == 10000)
          for index, effect in ipairs(output.effects) do
            assert(effect.type == "gun-speed" and effect.ammo_category == categories[index])
            assert(math.abs(effect.modifier - modifiers[index]) < 1e-12)
          end
          startup["mir-effect-per-level-weapon-shooting-speed"].value = 20
          local adjusted = build(definition, config.resolve(startup))
          for index, effect in ipairs(adjusted.effects) do assert(math.abs(effect.modifier - modifiers[index]/2) < 1e-12) end
          assert(seven.unit.count == 2500 and eight.unit.count == 5000 and eight.effects[3].modifier == 1.35)
          output.unit.ingredients[7][1] = "caller-mutated"
          assert(eight.unit.ingredients[7][1] == "acidworking-science-pack" and definition.ingredients[7][1] == "acidworking-science-pack")
          local generator, writes = require("research.generator"), 0
          local ok, message = pcall(generator.install, {adjusted}, {
            raw={technology={[adjusted.name]={}}}, extend=function() writes = writes + 1 end})
          assert(not ok and tostring(message):find("duplicate technology weapon-shooting-speed-9", 1, true) and writes == 0)
        ''')

    def test_foreign_creator_remains_external_after_later_modifications(self):
        self.lua.execute('''
          local technologies = setmetatable({}, {__pairs=function() error("world scan") end})
          for _, name in ipairs(tail_names) do technologies[name] = foreign_tail(name) end
          local catalogue, calls = runtime(technologies, "foreign-provider")
          for _ = 1, 2 do
            local declared = ids(catalogue.declared())
            for _, name in ipairs(tail_names) do assert(not declared[name], "claimed foreign tail " .. name) end
          end
          for _, name in ipairs(tail_names) do assert(calls[name] == 1, "creator lookup work " .. name) end
        ''')

    def test_mir_creator_retains_ownership_after_science_spread_modifications(self):
        self.lua.execute('''
          local technologies = {}
          for _, name in ipairs(tail_names) do technologies[name] = foreign_tail(name) end
          local catalogue, calls = runtime(technologies, "more-infinite-research")
          for _ = 1, 2 do
            local declared = ids(catalogue.declared())
            for _, name in ipairs(tail_names) do assert(declared[name], "lost MIR-created tail " .. name) end
          end
          for _, name in ipairs(tail_names) do assert(calls[name] == 1, "creator lookup work " .. name) end
        ''')

    def test_unqualified_muria_provider_changes_refuse_before_mir_state_writes(self):
        import test_lifecycle as fixture
        fixture.LuaRuntime = LuaRuntime
        harness = fixture.LifecycleTests()
        harness.setUp()
        harness.lua.execute('''
          local world=force(1,{}, {},nil,nil)
          for _, change in ipairs({{new_version="1.8.5"},{old_version="1.8.5"}}) do
            local saved=setmetatable({}, {__newindex=function() error("MIR wrote state before provider guard") end})
            boot({[1]=world},0,"",saved,nil,0,{base="2.1.23"})
            local ok,message=pcall(handlers.configuration,{mod_changes={Muria=change}})
            assert(not ok and tostring(message):find("cannot safely add or remove Muria",1,true),tostring(message))
            assert(next(saved)==nil and #world.research_queue==0)
          end
          -- Installing MIR for the first time beside an existing Muria world
          -- does not replace a previous MIR-owned weapon identity.
          boot({[1]=world},0,"",nil,nil,0,{base="2.1.23"})
          handlers.configuration({mod_changes={Muria={new_version="1.8.5"},
            ["more-infinite-research"]={new_version="5.0.21002"}}})
        ''')

    def test_all_six_foreign_creators_stay_out_of_real_cap_admission(self):
        self.lua.execute('''
          local settings_names={
            ["braking-force-8"]="mir-max-level-braking-force",
            ["inserter-capacity-bonus-8"]="mir-max-level-inserter-capacity-bonus",
            ["laser-shooting-speed-8"]="mir-max-level-laser-shooting-speed",
            ["research-speed-7"]="mir-max-level-research-speed",
            ["weapon-shooting-speed-7"]="mir-max-level-weapon-shooting-speed",
            ["worker-robots-storage-4"]="mir-max-level-worker-robots-storage",
          }
          local config=require("research.settings")
          for _,name in ipairs(tail_names) do
            for _,creator in ipairs({"more-infinite-research","foreign-provider"}) do
              for _,enabled in ipairs({false,true}) do
                script={active_mods={base="2.1.23"}}
                settings={startup={}}
                for _,spec in ipairs(config.prototypes()) do settings.startup[spec.name]={value=spec.default_value} end
                settings.startup[settings_names[name]].value=10
                local native={name=name,valid=true,level=11,enabled=enabled,researched=false,
                  visible_when_disabled=false,saved_progress=.27,prototype={enabled=true}}
                local current={name="foreign-current",valid=true}
                local world={index=1,valid=true,technologies={[name]=native,[current.name]=current},
                  research_queue={current,native},current_research=current,research_progress=.42}
                current.force,native.force=world,world
                local reads=0
                prototypes={recipe={},technology=setmetatable({[name]=native.prototype},
                  {__pairs=function() error("cap admission enumerated all prototypes") end}),
                  get_history=function(kind,id)
                    assert(kind=="technology" and id==name);reads=reads+1
                    return {created=creator,changed={"science-spread","more-infinite-research"}}
                  end}
                game={forces={[1]=world}}
                storage={mir_caps={schema=1,owned_disabled={[1]={[name]={disabled=true,visible_when_disabled=false}}}}}
                for _,module in ipairs({"research.catalogue","runtime.catalogue","runtime.lifecycle","runtime.configuration"}) do
                  package.loaded[module]=nil
                end
                local lifecycle=require("runtime.lifecycle")
                local owned=creator=="more-infinite-research"
                local limits=lifecycle.cap_limits(world)
                assert((limits[name]~=nil)==owned,"incorrect cap ownership for "..name)
                lifecycle.on_init()
                assert(native.enabled==(not owned and enabled) and native.visible_when_disabled==owned)
                assert(native.level==11 and native.saved_progress==.27 and not native.researched)
                assert(#world.research_queue==(owned and 1 or 2) and world.research_queue[1]==current)
                assert(world.current_research==current and world.research_progress==.42 and reads==1)
                local records=storage.mir_caps and storage.mir_caps.owned_disabled[1]
                if not owned then assert(records==nil or records[name]==nil,"stale restoration right survived") end
              end
            end
          end
        ''')

    def test_unknown_creation_history_refuses_each_shared_identity(self):
        self.lua.execute('''
          for _,name in ipairs(tail_names) do
            script={active_mods={base="2.1.23"}}
            prototypes={technology={[name]={}},get_history=function() return {changed={"science-spread"}} end}
            package.loaded["research.catalogue"],package.loaded["runtime.catalogue"]=nil,nil
            local ok,message=pcall(require,"runtime.catalogue")
            assert(not ok and tostring(message):find("creation history for "..name,1,true))
          end
        ''')

    def test_exclusive_muria_tail_custody_is_checked_before_cap_admission(self):
        self.lua.execute('''
          for _,creator in ipairs({"more-infinite-research","foreign-provider"}) do
            local name="weapon-shooting-speed-9"
            local prototype={name=name,enabled=true}
            local native={name=name,valid=true,level=11,enabled=true,researched=false,
              visible_when_disabled=false,saved_progress=.27,prototype=prototype}
            local world={index=1,valid=true,technologies={[name]=native},research_queue={}}
            local reads=0
            script={active_mods={base="2.1.23",Muria="1.8.5"}}
            prototypes={recipe={},technology={[name]=prototype},get_history=function(kind,id)
              assert(kind=="technology" and id==name);reads=reads+1
              return {created=creator,changed={"science-spread"}}
            end}
            game=setmetatable({}, {__index=function() error("custody check read game") end})
            storage=setmetatable({}, {__newindex=function() error("custody check wrote state") end})
            for _,module in ipairs({"research.catalogue","runtime.catalogue","runtime.lifecycle","runtime.configuration"}) do
              package.loaded[module]=nil
            end
            local ok,catalogue=pcall(require,"runtime.catalogue")
            assert(reads==1 and native.enabled and native.saved_progress==.27 and next(storage)==nil)
            if creator=="foreign-provider" then
              assert(not ok and tostring(catalogue):find("MIR creation custody for "..name,1,true),tostring(catalogue))
            else
              assert(ok and ids(catalogue.declared())[name] and not catalogue.externally_supplied_continuation(name))
              local config=require("research.settings")
              settings={startup={}}
              for _,spec in ipairs(config.prototypes()) do settings.startup[spec.name]={value=spec.default_value} end
              settings.startup["mir-max-level-weapon-shooting-speed"].value=10
              local lifecycle=require("runtime.lifecycle")
              game,storage={forces={[1]=world}},{}
              assert(lifecycle.cap_limits(world)[name]==10)
              lifecycle.on_init()
              assert(not native.enabled and native.level==11 and native.saved_progress==.27)
              assert(storage.mir_caps.owned_disabled[1][name])
            end
          end
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ContinuationOwnershipTests))
    sys.exit(0 if result.wasSuccessful() else 1)
