"""Worker continuation identity guards; host doubles are not native save proof."""
import argparse
from pathlib import Path
import sys
import unittest

import test_bootstrap as bootstrap_fixture


class WorkerStorageHistoryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (Path(__file__).resolve().parents[1] / "source").as_posix()
        self.lua.execute(r'''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""
          storage={};script={active_mods={base="2.1.24",["more-infinite-research"]="5.0.21009"}}
          function route(last,owner)
            return {technology="worker-robots-storage-"..(last+1),level=last+1,
              predecessor="worker-robots-storage-4",owned=owner~=false,legacy_compatible=true,
              provider=owner==false and "foreign-infinite" or nil,
              finite={{name="worker-robots-storage-4",max_level=last,provider="foreign-finite"}}}
          end
          function upgrade(old,changed)
            return {mod_startup_settings_changed=changed==true,
              mod_changes={["more-infinite-research"]={old_version=old,new_version="5.0.21009"}}}
          end
          history=require("runtime.worker_robot_storage")
        ''')

    def test_fresh_route_is_detached_and_two_cold_loads_are_read_only(self):
        self.lua.execute(r'''
          local selected=route(9);history.on_init(selected)
          local saved=storage.mir_worker_storage_route
          assert(saved.route~=selected and saved.route.finite~=selected.finite)
          selected.finite[1].provider="changed-caller"
          assert(saved.route.finite[1].provider=="foreign-finite")
          for i=1,2 do
            package.loaded["runtime.worker_robot_storage"]=nil
            history=require("runtime.worker_robot_storage");history.on_load(route(9))
            assert(storage.mir_worker_storage_route==saved)
          end
          assert(history.preflight(upgrade("5.0.21008",true),route(9))==nil)
          assert(storage.mir_worker_storage_route==saved)
        ''')

    def test_new_mir_install_has_no_marker_write_until_all_preflights_pass(self):
        self.lua.execute(r'''
          local plan=history.preflight(upgrade(nil),route(4))
          assert(storage.mir_worker_storage_route==nil and plan.route.technology=="worker-robots-storage-5")
          history.apply(plan);assert(storage.mir_worker_storage_route==plan)
        ''')

    def test_changed_endpoint_creator_ownership_and_removal_refuse_without_writes(self):
        self.lua.execute(r'''
          history.on_init(route(9));local saved=storage.mir_worker_storage_route
          for _,opponent in ipairs({"endpoint","finite-creator","infinite-owner","removal"}) do
            local candidate=route(opponent=="endpoint" and 10 or 9,opponent~="infinite-owner")
            if opponent=="finite-creator" then candidate.finite[1].provider="another-mod" end
            if opponent=="removal" then candidate=nil end
            local ok,message=pcall(history.preflight,upgrade("5.0.21008"),candidate)
            assert(not ok and tostring(message):find("MIR-WORKER-HISTORY",1,true),opponent)
            assert(storage.mir_worker_storage_route==saved)
            assert(not pcall(history.on_load,candidate),"cold load accepted "..opponent)
          end
        ''')

    def test_unknown_prior_save_is_not_inferred_from_current_prototype_or_version(self):
        self.lua.execute(r'''
          for _,old in ipairs({"5.0.21008","4.7.21003","4.7.20003"}) do
            local ok,message=pcall(history.preflight,upgrade(old),route(4))
            assert(not ok and tostring(message):find("previous continuation ownership is unknown",1,true))
            assert(storage.mir_worker_storage_route==nil)
          end
          assert(history.preflight(upgrade("5.0.21008"),nil)==nil)
        ''')

    def test_exact_transported_legacy_emission_is_admitted_but_lookalikes_are_not(self):
        self.lua.execute(r'''
          local selected=route(9)
          local row={technology=selected.technology,setting="mir-max-level-worker-robots-storage",
            source="base-continuation",operation="emit_base_extension",policy_transport="transported-v3",
            ownership_kind="transported-v3",legacy=false,native_finite_stage=false,
            binding_fingerprint="mir32-12345678",selected="infinite"}
          storage.mir={maximum_level_control={policy_version=3,managed_technologies={[selected.technology]=row}}}
          local plan=history.preflight(upgrade("4.7.21003"),selected)
          assert(plan and plan.route.technology==selected.technology and storage.mir_worker_storage_route==nil)
          for _,field in ipairs({"operation","source","ownership_kind","policy_transport","binding_fingerprint"}) do
            local old=row[field];row[field]="settings-derived"
            assert(not pcall(history.preflight,upgrade("4.7.21003"),selected),field)
            row[field]=old
          end
          assert(not pcall(history.preflight,upgrade("4.7.21003",true),selected))
          local event=upgrade("4.7.21003");event.mod_changes.foreign={old_version="1.0",new_version="1.1"}
          assert(not pcall(history.preflight,event,selected))
          assert(not pcall(history.preflight,upgrade("4.7.21003"),route(9,false)))
          selected.legacy_compatible=false
          assert(not pcall(history.preflight,upgrade("4.7.21003"),selected))
          assert(storage.mir_worker_storage_route==nil)
        ''')

    def test_malformed_saved_chain_is_rejected(self):
        self.lua.execute(r'''
          for _,opponent in ipairs({"schema","level","gap","provider","endpoint","extra","sparse"}) do
            local selected=route(9);local saved={schema=1,route=selected}
            if opponent=="schema" then saved.schema=2 end
            if opponent=="level" then selected.level=0 end
            if opponent=="gap" then selected.finite[1].name="worker-robots-storage-5" end
            if opponent=="provider" then selected.finite[1].provider="more-infinite-research" end
            if opponent=="endpoint" then selected.predecessor="worker-robots-storage-9" end
            if opponent=="extra" then selected.finite.foreign="ignored" end
            if opponent=="sparse" then selected.finite[3]=selected.finite[1] end
            storage.mir_worker_storage_route=saved
            assert(not pcall(history.on_load,route(9)),opponent)
            assert(storage.mir_worker_storage_route==saved)
          end
        ''')

    def test_bootstrap_refuses_before_lifecycle_or_other_credit_writes(self):
        bootstrap_fixture.LuaRuntime = LuaRuntime
        fixture = bootstrap_fixture.BootstrapTests()
        fixture.setUp()
        fixture.lua.execute(r'''
          install_modules(true,false,false,true)
          install_runtime(nil,{base="2.1.24",["more-infinite-research"]="5.0.21009"})
          local catalogue=require("runtime.catalogue")
          catalogue.worker_storage_route=function()
            return {technology="worker-robots-storage-5",level=5,predecessor="worker-robots-storage-4",
              owned=true,finite={{name="worker-robots-storage-4",max_level=4,provider="planet-provider"}}}
          end
          load_control()
          local ok,message=pcall(handlers.configuration,{mod_startup_settings_changed=false,
            mod_changes={["more-infinite-research"]={old_version="5.0.21008",new_version="5.0.21009"}}})
          assert(not ok and tostring(message):find("MIR-WORKER-HISTORY",1,true),tostring(message))
          assert(#configuration_order==0 and lifecycle_calls.configuration==nil)
          assert(storage.mir_worker_storage_route==nil)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])
