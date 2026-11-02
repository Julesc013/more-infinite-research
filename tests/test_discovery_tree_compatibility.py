"""Independent Discovery Tree availability controls; no native/algorithm claim."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DiscoveryTreeCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          model, caps = require("presentation.library_model"), require("runtime.caps")
          name = "research-speed-7"
          native = {name=name, valid=true, level=11, enabled=false, researched=false,
            visible_when_disabled=false, saved_progress=.27,
            prototype={max_level=4294967295, hidden=false, effects={{type="laboratory-speed",modifier=.6}}},
            prerequisites={automation={name="automation",researched=true}},
            research_unit_count=100, research_unit_energy=60, research_unit_ingredients={{name="automation-science-pack",amount=1}}}
          force = {valid=true,index=1,technologies={[name]=native},research_queue={}}
          declared = {{id=name,family="research-speed",progression=7,settings={},cap_setting="mir-max-level-research-speed"}}
          context = {discovery_tree=true, private_credit_ids={}}
        ''')

    def test_hidden_native_state_cannot_be_bypassed_by_filters_search_or_detail(self):
        self.lua.execute('''
          for _, family in ipairs({"mir","all","external","research-speed"}) do
            for _, visibility in ipairs({1,2,3}) do
              local view={family=family,visibility=visibility,hidden={[name]=true},search="research",selected=name}
              assert(#model.rows(force,declared,view,{},context)==0)
              local detail,reason=model.detail(force,declared,view,{},context)
              assert(detail==nil and reason=="technology_not_found")
            end
          end
          assert(native.enabled==false and native.visible_when_disabled==false and native.saved_progress==.27)
        ''')

    def test_discovery_and_reset_transitions_are_read_live_without_view_recreation(self):
        self.lua.execute('''
          local view={family="all",selected=name}
          assert(#model.rows(force,declared,view,{},context)==0)
          native.enabled=true
          assert(#model.rows(force,declared,view,{},context)==1 and model.detail(force,declared,view,{},context))
          native.enabled=false
          assert(#model.rows(force,declared,view,{},context)==0)
          native.enabled=true -- upstream None/reset mode restores availability
          assert(#model.rows(force,declared,view,{},context)==1)
          context.discovery_tree=false
          native.enabled=false
          assert(#model.rows(force,declared,view,{},context)==1,"absent-mod behavior changed")
        ''')

    def test_private_credits_remain_internal_even_when_enabled_or_personally_unhidden(self):
        self.lua.execute('''
          context.private_credit_ids[name]=true; native.enabled=true
          assert(#model.rows(force,declared,{family="all",visibility=3},{},context)==0)
          assert(model.detail(force,declared,{selected=name},{},context)==nil)
          assert(native.level==11 and native.saved_progress==.27)
        ''')

    def test_cap_does_not_reveal_hidden_research_or_restore_over_upstream_state(self):
        self.lua.execute('''
          native.enabled=true
          local ownership=caps.reconcile(force,{[name]=10},{}) -- earlier ordinary MIR cap
          assert(native.visible_when_disabled==true and native.enabled==false)
          native.enabled=false -- actual upstream update says still hidden
          caps.reconcile(force,{[name]=10},ownership,nil,nil,true)
          assert(native.visible_when_disabled==false and ownership[1][name].discovery_enabled==false)
          caps.reconcile(force,{[name]=0},ownership,nil,nil,true)
          assert(native.enabled==false and native.visible_when_disabled==false and ownership[1]==nil)
          assert(native.level==11 and native.saved_progress==.27 and #force.research_queue==0)
        ''')

    def test_only_fresh_upstream_events_replace_capped_discovery_observations(self):
        self.lua.execute('''
          native.enabled=true
          local ownership=caps.reconcile(force,{[name]=10},{},nil,nil,true)
          assert(not native.enabled and not native.visible_when_disabled and ownership[1][name].discovery_enabled)
          caps.reconcile(force,{[name]=10},ownership,nil,nil,false)
          assert(ownership[1][name].discovery_enabled==true,"MIR's own disablement erased discovery")
          context.discovery_visibility={[name]=ownership[1][name].discovery_enabled}
          assert(#model.rows(force,declared,{family="all"},{},context)==1)
          native.enabled=false -- fresh upstream restriction
          caps.reconcile(force,{[name]=10},ownership,nil,nil,true)
          context.discovery_visibility={[name]=ownership[1][name].discovery_enabled}
          assert(#model.rows(force,declared,{family="all"},{},context)==0)
        ''')

    def test_force_discovery_and_cap_observations_do_not_cross_forces(self):
        self.lua.execute('''
          local ownership={}
          native.enabled=true; caps.reconcile(force,{[name]=10},ownership,nil,nil,true)
          local other={valid=true,index=2,technologies={[name]={name=name,level=11,enabled=false,
            visible_when_disabled=false}},research_queue={}}
          caps.reconcile(other,{[name]=10},ownership,nil,nil,true)
          assert(ownership[1][name].discovery_enabled==true and ownership[2][name].discovery_enabled==false)
          assert(not native.enabled and not other.technologies[name].enabled)
        ''')

    def test_research_event_reapplies_all_owned_caps_after_discovery_changes_the_force(self):
        # Reuse the existing native-object/event fixture, never its expectations.
        import test_lifecycle as fixture
        fixture.LuaRuntime = LuaRuntime
        harness = fixture.LifecycleTests()
        harness.setUp()
        harness.lua.execute('''
          local native=technology("research-speed-7",11,true)
          local other=technology("foreign-finished",1,true)
          local world=force(1,{[native.name]=native,[other.name]=other},{},nil,nil)
          native.force,other.force=world,world
          boot({[1]=world},0,"",nil,nil,0,{base="2.1.23",discovery_tree="1.0.12"},nil,
            {["mir-max-level-research-speed"]=10})
          handlers.init()
          local lifecycle=require("runtime.lifecycle")
          assert(not native.enabled and not native.visible_when_disabled)
          assert(lifecycle.discovery_visibility(world)[native.name])
          native.enabled=true -- Discovery Tree re-evaluates the whole force first
          handlers.events[4]({research=other})
          assert(not native.enabled,"unrelated finished ID left MIR's cap re-enabled")
          assert(lifecycle.discovery_visibility(world)[native.name])
          native.enabled=false -- now hidden by upstream instead
          handlers.events[4]({research=other})
          assert(lifecycle.discovery_visibility(world)[native.name]==nil)
        ''')

    def test_sif_paid_holders_are_private_only_in_the_profile_that_emits_them(self):
        self.lua.execute('''
          local names={"research_low_density_structure","research_plastic","research_processing_unit",
            "research_rocket_fuel","research_steel"}
          local target=require("platform.target")
          target.id,target.factorio_version,target.minimum_base="f200","2.0","2.0.77"
          for _, sif in ipairs({false,true}) do
            script={active_mods={base="2.0.77",["space-age"]="2.0.77"}}
            if sif then script.active_mods["space-is-fake"]="1.0.60" end
            package.loaded["research.catalogue"],package.loaded["runtime.catalogue"]=nil,nil
            local catalogue=require("runtime.catalogue")
            local private=catalogue.internal_credit_ids()
            assert(private["mir-k2-imersite-staged-state-1"] and private["mir-k2-imersite-continuation-state-4"])
            for _, family in ipairs(names) do
              local id="recipe-prod-"..family.."-1"
              assert((private[id]==true)==sif,"incorrect private profile for "..id)
              if sif then
                local holder={name=id,enabled=true,level=3,researched=false}
                local world={technologies={[id]=holder},research_queue={}}
                for _, discovery in ipairs({false,true}) do
                  local facts={private_credit_ids=private,discovery_tree=discovery}
                  assert(#model.rows(world,{}, {family="all",visibility=3},{},facts)==0)
                  assert(model.detail(world,{}, {selected=id},{},facts)==nil)
                  assert(holder.level==3 and holder.enabled)
                end
              end
            end
          end
        ''')

    def test_discovery_cannot_reenable_retired_competing_productivity(self):
        import test_competing_productivity as fixture
        fixture.LuaRuntime = LuaRuntime
        harness = fixture.CompetingProductivityTests()
        harness.setUp()
        harness.lua.execute('''
          local contract=require("compatibility.competing_productivity").select(exact_active(),f200_target())
          local world=force_from_contract(contract)
          local mods=exact_active(); mods.discovery_tree="1.0.10"
          local runtime=install_competing(true,world,mods)
          runtime.on_init()
          for _, item in ipairs(contract.bindings) do
            local native=world.technologies[item.id]
            assert(not native.enabled and not native.visible_when_disabled)
            native.enabled=true -- upstream whole-force refresh
          end
          runtime.on_research_finished({research={name="foreign-finished",force=world}})
          for _, item in ipairs(contract.bindings) do
            assert(not world.technologies[item.id].enabled and not world.technologies[item.id].visible_when_disabled)
          end
          settings={global={}}
          assert(not runtime.on_discovery_tree_queue_changed({force=world}),"invented queued mode on1.0.10")
          runtime=install_competing(false,world,mods)
          runtime.on_configuration_changed()
          for _, item in ipairs(contract.bindings) do assert(not world.technologies[item.id].enabled) end
          assert(world.research_progress==.42 and #world.research_queue==0)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(DiscoveryTreeCompatibilityTests))
    sys.exit(0 if result.wasSuccessful() else 1)
