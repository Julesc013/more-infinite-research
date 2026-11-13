"""Independent host controls for withheld native settings and proven cap release.

Fake forces exercise real catalogue/lifecycle/caps and selector code. The
composed control also consumes actual data-stage output from a separate Lua
state; none qualifies native effects or save persistence.
"""
import argparse
from pathlib import Path
import sys
import unittest

import test_lifecycle as fixture
import test_generator as generator_fixture
import test_native_owner_fallback as fallback_fixture


class WithheldRuntimeTests(unittest.TestCase):
    def setUp(self):
        fixture.LuaRuntime = LuaRuntime
        harness = fixture.LifecycleTests()
        harness.setUp()
        self.lua = harness.lua
        self.lua.execute(r'''
          owner_rows={
            {"low-density-structure-productivity","research_low_density_structure",
              {"low-density-structure","casting-low-density-structure"}},
            {"plastic-bar-productivity","research_plastic",{"plastic-bar","bioplastic"}},
            {"processing-unit-productivity","research_processing_unit",{"processing-unit"}},
            {"rocket-fuel-productivity","research_rocket_fuel",
              {"rocket-fuel","rocket-fuel-from-jelly","ammonia-rocket-fuel"}},
            {"steel-plate-productivity","research_steel",{"steel-plate","casting-steel"}}
          }
          active={base="2.1.23",["space-age"]="2.1.23"}
          function metadata(generated)
            local withheld={}
            for _,row in ipairs(owner_rows) do withheld[row[1]]={family=row[2],generated=generated} end
            return {["more-infinite-research-native-adoptions"]={data={schema=1,owners={},withheld=withheld}}}
          end
          function world_for(enabled)
            local technologies={}
            for _,row in ipairs(owner_rows) do
              local native=technology(row[1],3,enabled)
              native.prototype.max_level=4294967295
              native.prototype.effects={}
              for _,recipe in ipairs(row[3]) do
                native.prototype.effects[#native.prototype.effects+1]={
                  type="change-recipe-productivity",recipe=recipe,change=.1}
              end
              technologies[row[1]]=native
            end
            local world=force(41,technologies,{},nil,.42)
            world.foreign_state="preserve"
            for _,native in pairs(technologies) do native.force=world end
            return world
          end
          function parse(world,data,saved,configured_effect,history,native_prototypes)
            local settings={}
            for _,row in ipairs(owner_rows) do
              settings["ips-max-level-"..row[2]]=2
              if configured_effect then settings["ips-effect-per-level-"..row[2]]=configured_effect end
            end
            boot({[41]=world},0,"",saved,nil,0,active,nil,settings,{},data,history,native_prototypes)
            return require("runtime.lifecycle"),require("runtime.catalogue")
          end
          function present(rows,name)
            for _,row in ipairs(rows) do if row.id==name then return row end end
          end
          function legacy_for(world)
            local old={policy_version=3,managed_technologies={},disabled_by_cap={[41]={}},
              visibility_by_cap={[41]={}},unique={keep=true}}
            for _,row in ipairs(owner_rows) do
              local name,setting=row[1],"ips-max-level-"..row[2]
              local key=table.concat({name,setting,"native-owner","preserve_native_owner"},string.char(0))
              old.managed_technologies[name]={technology=name,setting=setting,source="native-owner",
                operation="preserve_native_owner",policy_transport="transported-v3",
                ownership_kind="transported-v3",legacy=false,selected=2,binding_fingerprint="mir32-1234abcd"}
              old.disabled_by_cap[41][name]={policy_version=3,force_index=41,cap=2,
                binding_fingerprint="mir32-1234abcd",ownership_key=key,
                ownership_kind="transported-v3",enabled_before_cap=true}
              old.visibility_by_cap[41][name]={policy_version=3,force_index=41,
                ownership_key=key,ownership_kind="transported-v3",value=false}
              world.technologies[name].visible_when_disabled=true
            end
            return old
          end
        ''')

    def test_new_metadata_never_caps_or_cancels_native_research(self):
        self.lua.execute(r'''
          for _,enabled in ipairs({true,false}) do
            local world=world_for(enabled)
            local current=world.technologies[owner_rows[1][1]]
            world._queue={current};world.current_research=current
            local queue=world._queue
            local lifecycle,catalogue=parse(world,metadata(false))
            handlers.init()
            local limits=lifecycle.cap_limits(world)
            for _,row in ipairs(owner_rows) do
              assert(present(catalogue.declared(),row[1])==nil,"withheld native entered public catalogue")
              assert(present(catalogue.declared(),"recipe-prod-"..row[2].."-1")==nil,"false generated phantom")
              assert(limits[row[1]]==nil,"withheld native received a new/public limit")
              assert(world.technologies[row[1]].enabled==enabled,"metadata changed foreign enablement")
              assert(not world.technologies[row[1]].visible_when_disabled,"metadata changed visibility")
              lifecycle.on_research_finished({research=world.technologies[row[1]]})
            end
            assert(world._queue==queue and world.current_research==current and world.research_progress==.42)
            assert(world.cancelled==0 and world.foreign_state=="preserve" and storage.mir_caps==nil)
          end
        ''')

    def test_existing_true_and_false_caps_release_without_new_authority(self):
        self.lua.execute(r'''
          for _,enabled in ipairs({true,false}) do
            local world=world_for(enabled)
            parse(world,nil);handlers.init()
            local saved=storage
            for _,row in ipairs(owner_rows) do
              assert(saved.mir_caps.owned_disabled[41][row[1]].disabled==enabled)
              assert(not world.technologies[row[1]].enabled and world.technologies[row[1]].visible_when_disabled)
            end
            -- Rejected settings must not become the expected native effect:
            -- the unchanged .1 prototype still admits release with requested50.
            local lifecycle=parse(world,metadata(false),saved,50)
            handlers.configuration({})
            for _,row in ipairs(owner_rows) do
              local native=world.technologies[row[1]]
              assert(native.enabled==enabled and not native.visible_when_disabled)
              assert(native.level==3 and not native.researched and native.prototype.effects[1].change==.1)
              lifecycle.on_research_started({research=native})
              assert(native.enabled==enabled,"event reapplied withheld cap")
            end
            assert(storage.mir_caps==nil and world.foreign_state=="preserve")
          end
        ''')

    def test_named_event_releases_only_the_matching_owned_row(self):
        self.lua.execute(r'''
          local world=world_for(true)
          parse(world,nil);handlers.init()
          local lifecycle=parse(world,metadata(false),storage)
          local first=world.technologies[owner_rows[1][1]]
          lifecycle.on_research_reversed({research=first})
          assert(first.enabled and not first.visible_when_disabled)
          for i=2,#owner_rows do
            local name=owner_rows[i][1]
            assert(not world.technologies[name].enabled and storage.mir_caps.owned_disabled[41][name])
          end
          assert(storage.mir_caps.owned_disabled[41][first.name]==nil)
        ''')

    def test_changed_native_prototype_cannot_release_owned_flags(self):
        self.lua.execute(r'''
          local world=world_for(true)
          parse(world,nil);handlers.init()
          local saved=storage
          world.technologies[owner_rows[1][1]].prototype.effects[1].change=.2
          parse(world,metadata(false),saved);handlers.configuration({})
          local native=world.technologies[owner_rows[1][1]]
          assert(not native.enabled and native.visible_when_disabled,"unqualified replacement revealed")
          assert(storage.mir_caps==nil,"unbound restoration right retained")
        ''')

    def test_verified_legacy_caps_restore_without_becoming_current_caps(self):
        self.lua.execute(r'''
          local world=world_for(false)
          local old=legacy_for(world)
          parse(world,metadata(false),{mir={maximum_level_control=old}})
          handlers.configuration({})
          for _,row in ipairs(owner_rows) do
            assert(world.technologies[row[1]].enabled and not world.technologies[row[1]].visible_when_disabled)
          end
          assert(storage.mir.maximum_level_control==old and old.unique.keep)
          assert(storage.mir_caps.legacy_caps_checked and next(storage.mir_caps.owned_disabled)==nil)
        ''')

    def test_negative_malformed_and_foreign_legacy_proofs_do_not_restore(self):
        self.lua.execute(r'''
          for _,opponent in ipairs({"false-baseline","bare-boolean","wrong-key","wrong-cap","wrong-fingerprint",
              "changed-prototype"}) do
            local world=world_for(false)
            local old=legacy_for(world)
            for _,row in ipairs(owner_rows) do
              local proof=old.disabled_by_cap[41][row[1]]
              if opponent=="false-baseline" then proof.enabled_before_cap=false
              elseif opponent=="bare-boolean" then old.disabled_by_cap[41][row[1]]=true
              elseif opponent=="wrong-key" then proof.ownership_key="foreign"
              elseif opponent=="wrong-cap" then proof.cap=1
              elseif opponent=="wrong-fingerprint" then proof.binding_fingerprint="mir32-ffffffff"
              else world.technologies[row[1]].prototype.effects[1].change=.2 end
            end
            parse(world,metadata(false),{mir={maximum_level_control=old}});handlers.configuration({})
            for _,row in ipairs(owner_rows) do assert(not world.technologies[row[1]].enabled,opponent) end
            assert(next(storage.mir_caps.owned_disabled)==nil)
          end
        ''')

    def test_selection_forwarding_cache_identity_detachment_and_fallback_rights(self):
        self.lua.execute(r'''
          -- Count calls around the real selector; no selection rows are faked.
          local modern=require("compatibility.modern_catalogue")
          local original=modern.select
          local calls,last_map=0,nil
          modern.select=function(active_mods,raw,withheld)
            calls,last_map=calls+1,withheld
            assert(raw==nil,"runtime guessed raw prototype facts")
            return original(active_mods,raw,withheld)
          end
          local world=world_for(true)
          local data=metadata(true)
          local generated=technology("recipe-prod-research_processing_unit-1",3,true)
          generated.force=world;world.technologies[generated.name]=generated
          local lifecycle,runtime=parse(world,data)
          assert(last_map and last_map["processing-unit-productivity"].generated)
          handlers.init()
          assert(not generated.enabled,"real lifecycle did not cap authored fallback")
          assert(world.technologies["processing-unit-productivity"].enabled,"fallback capped native owner")
          local rows=runtime.declared()
          assert(present(rows,generated.name) and not present(rows,"processing-unit-productivity"))
          local before=calls;runtime.declared();assert(calls==before,"cache rebuilt identical input identity")
          local pure=require("research.catalogue")
          local off={["processing-unit-productivity"]={family="research_processing_unit",generated=false}}
          assert(not present(pure.declared(nil,off),generated.name))
          local on={["processing-unit-productivity"]={family="research_processing_unit",generated=true}}
          local copy=pure.declared(nil,on)
          present(copy,generated.name).family="tampered"
          assert(present(pure.declared(nil,on),generated.name).family=="research_processing_unit")
          assert(present(pure.declared(),"processing-unit-productivity"),"default cache reused withheld rows")
          local restore=runtime.restoration_only();restore[1].native_admission.recipes[1]="tampered"
          assert(runtime.restoration_only()[1].native_admission.recipes[1]~="tampered")
          modern.select=original
        ''')

    def test_actual_data_stage_metadata_controls_only_the_emitted_fallback(self):
        fallback_fixture.LuaRuntime = LuaRuntime
        fallback_fixture.NativeOwnerFallbackTests.setUpClass()
        for uncovered in (False, True):
            with self.subTest(uncovered=uncovered):
                self.setUp()
                data_case = fallback_fixture.NativeOwnerFallbackTests().boot(
                    "research_processing_unit", uncovered=uncovered, combined=True)
                before = data_case.owner_rows()
                data_case.pipeline()
                self.assertEqual(before, data_case.owner_rows())
                private = fallback_fixture.fixture.plain(data_case.lua.globals().data.raw[
                    "mod-data"]["more-infinite-research-native-adoptions"].data)
                self.lua.globals().actual_data = generator_fixture.lua_table(self.lua, {
                    "more-infinite-research-native-adoptions": {"data": private}})
                self.lua.globals().actual_generated = uncovered
                self.lua.globals().actual_technologies = generator_fixture.lua_table(self.lua,
                    fallback_fixture.fixture.plain(data_case.lua.globals().data.raw.technology))
                self.lua.execute(r'''
                  local world=world_for(true)
                  local native=world.technologies["processing-unit-productivity"]
                  native.saved_progress=0 -- actual native queued technologies always expose this getter
                  world._queue={native};world.current_research=native
                  local queued=world._queue
                  local id="recipe-prod-research_processing_unit-1"
                  local emitted_prototypes={}
                  -- Materialize the actual emitted MIR definitions rather
                  -- than inventing a partial post-data control-stage world.
                  local function install(name,level)
                    if world.technologies[name] then return end
                    local proto=actual_technologies[name];assert(proto,"missing actual source "..name)
                    proto.level=proto.level or tonumber(name:match("%-(%d+)$"))or 1
                    if proto.max_level=="infinite"then proto.max_level=4294967295 end
                    if proto.enabled==nil then proto.enabled=true end
                    if proto.hidden==nil then proto.hidden=false end
                    if proto.visible_when_disabled==nil then proto.visible_when_disabled=false end
                    proto.ignore_tech_cost_multiplier=proto.ignore_tech_cost_multiplier or false
                    local unit=proto.unit
                    proto.research_unit_count_formula=unit.count_formula
                    proto.research_unit_count=unit.count
                    proto.research_unit_energy=unit.time*60
                    proto.research_unit_ingredients={}
                    for i,pack in ipairs(unit.ingredients)do proto.research_unit_ingredients[i]={name=pack[1],amount=pack[2]}end
                    local prerequisites={}
                    for _,prerequisite in ipairs(proto.prerequisites or{})do prerequisites[prerequisite]={name=prerequisite}end
                    proto.prerequisites=prerequisites
                    for _,effect in ipairs(proto.effects)do if effect.hidden==nil then effect.hidden=false end end
                    local row=technology(name,level or proto.level,proto.enabled)
                    row.visible_when_disabled=proto.visible_when_disabled;row.saved_progress=0
                    row.research_unit_count=unit.count
                    if name=="worker-robots-storage-4"or name=="mir-worker-storage-default-4"or name=="mir-worker-storage-preservation-4"then
                      assert(unit.count_formula=="675*1.5^(L-4)");row.research_unit_count=675
                    end
                    row.research_unit_energy=proto.research_unit_energy;row.research_unit_ingredients=proto.research_unit_ingredients
                    row.prerequisites={};row.prototype=proto;row.force=world;world.technologies[name]=row
                    emitted_prototypes[name]=proto
                  end
                  for _,name in ipairs({"worker-robots-storage-4","mir-worker-storage-default-4","mir-worker-storage-head-4","mir-worker-storage-preservation-4"})do install(name)end
                  -- This force has no paid Base worker rows. The model's
                  -- native contribution is a literal zero, not recovery input.
                  world.worker_robots_storage_bonus=0
                  active["more-infinite-research"]=require("platform.target").distribution_version
                  local credits=actual_data["more-infinite-research-native-adoptions"].data.credits
                  for family in pairs(credits) do
                    local main="recipe-prod-"..family.."-1"
                    install(main,main==id and actual_generated and 3 or 1)
                  end
                  for _,d in ipairs(require("research.native_credit_definitions").collected_descriptors(credits)) do
                    install(d.main_id,d.main_id==id and actual_generated and 3 or 1)
                    install(d.positive_id);install(d.negative_id)
                  end
                  local lifecycle,runtime=parse(world,actual_data,nil,17,function(_,name)
                    assert(actual_technologies[name],"creation claim lacks actual source")
                    return {created="more-infinite-research"}
                  end,emitted_prototypes)
                  handlers.init()
                  assert(native.enabled and native.level==3 and native.researched==false)
                  assert(world._queue==queued and world.current_research==native and world.research_progress==.42)
                  assert(lifecycle.cap_limits(world)[native.name]==nil)
                  assert(not present(runtime.declared(),native.name))
                  local generated=present(runtime.declared(),id)
                  assert((generated~=nil)==actual_generated)
                  if actual_generated then
                    assert(lifecycle.cap_limits(world)[id]==2,"fallback limit="..tostring(lifecycle.cap_limits(world)[id]))
                    assert(not world.technologies[id].enabled,"fallback was not capped")
                  else assert(lifecycle.cap_limits(world)[id]==nil) end
                ''')

    def test_unknown_wrong_family_and_untyped_metadata_refuse(self):
        self.lua.execute(r'''
          for _,kind in ipairs({"unknown","wrong-family","untyped"}) do
            local data=metadata(false)
            local withheld=data["more-infinite-research-native-adoptions"].data.withheld
            if kind=="unknown" then withheld.foreign={family="research_steel",generated=false}
            elseif kind=="wrong-family" then withheld["steel-plate-productivity"].family="research_plastic"
            else withheld["steel-plate-productivity"].generated=0 end
            assert(not pcall(parse,world_for(true),data),kind.." metadata accepted")
          end
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(WithheldRuntimeTests))
    sys.exit(0 if result.wasSuccessful() else 1)
