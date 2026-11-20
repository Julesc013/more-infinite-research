"""Lua5.2 controls for the single authored SE scripted-policy bridge.

The native fixture/custody owns engine and save qualification, not this world.
"""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SpaceExplorationSystemForceTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""
          target={id="f200"};package.loaded["platform.target"]=target
          -- Independently transcribed from the retained native profile, not
          -- generated from the production admission table.
          active={base="2.0.77",["aai-containers"]="0.3.2",["aai-industry"]="0.6.16",
            ["aai-signal-transmission"]="0.5.3",["alien-biomes"]="0.7.4",
            ["alien-biomes-graphics"]="0.7.1",informatron="0.4.0",jetpack="0.4.17",
            robot_attrition="0.6.6",["shield-projector"]="0.2.2",["space-exploration"]="0.7.57",
            ["space-exploration-graphics"]="0.7.5",["space-exploration-graphics-2"]="0.7.2",
            ["space-exploration-graphics-3"]="0.7.2",["space-exploration-graphics-4"]="0.7.2",
            ["space-exploration-graphics-5"]="0.7.3",["space-exploration-menu-simulations"]="0.7.4",
            ["space-exploration-postprocess"]="0.7.5",["more-infinite-research"]="5.0.20018"}
          script={active_mods=active}
          event={mod_startup_settings_changed=false,mod_changes={
            ["more-infinite-research"]={old_version="4.7.20002",new_version="5.0.20018"}}}
          native_writes={};forbidden_writes=0
          function ro(values)return setmetatable({}, {__index=values,
            __pairs=function()return next,values,nil end,__newindex=function()
              forbidden_writes=forbidden_writes+1;error("forbidden native write")end})end
          basic={"artillery","tank","radar","electronics","sulfur-processing","explosives",
            "electricity","fuel-processing","repair-pack"}
          rows={}
          function add_row(name,level,researched)
            local proto={level=level,max_level=level,effects={}}
            local fields={valid=true,name=name,level=level,researched=researched,saved_progress=0,prototype=proto}
            rows[name]=fields;return fields
          end
          for _,name in ipairs(basic)do
            add_row(name,1,true).prototype.effects={{type="unlock-recipe",recipe=name}}
          end
          for _,name in ipairs({"worker-robots-storage-1","worker-robots-storage-2","worker-robots-storage-3",
            "worker-robots-storage-4","mir-worker-storage-default-4","mir-worker-storage-head-4",
            "mir-worker-storage-preservation-4","mir-worker-storage-published517-4"})do
            local level=tonumber(name:match("(%d+)$"));local row=add_row(name,level,false)
            if level==4 then row.prototype.max_level=4294967295 end
          end
          registry=setmetatable({}, {__pairs=function()
            local key
            return function()key=next(rows,key);if key then return key,ro(rows[key])end end
          end,__index=function(_,name)return rows[name]and ro(rows[name])end})
          gun={laser=0,["artillery-shell"]=0};ammo={laser=0}
          fields={valid=true,name="conquest",index=4,ai_controllable=true,players={},
            current_research=nil,research_progress=0,research_queue={},technologies=registry,
            worker_robots_speed_modifier=0,worker_robots_storage_bonus=0,artillery_range_modifier=0,
            get_gun_speed_modifier=function(name)return gun[name]end,
            get_ammo_damage_modifier=function(name)return ammo[name]end,
            set_gun_speed_modifier=function(name,value)
              assert(name=="laser"or name=="artillery-shell");native_writes[#native_writes+1]=name;gun[name]=value end,
            set_ammo_damage_modifier=function(name,value)
              assert(name=="laser");native_writes[#native_writes+1]="damage";ammo[name]=value end}
          force=setmetatable({}, {__index=fields,__newindex=function(_,key,value)
            assert(key=="worker_robots_speed_modifier"or key=="worker_robots_storage_bonus"or key=="artillery_range_modifier")
            native_writes[#native_writes+1]=key;fields[key]=value end})
          foreign=ro{name="player",index=1,worker_robots_storage_bonus=8,
            research_progress=.039024390243902,queue="worker,worker,tail"}
          game={forces={conquest=force,[4]=force,player=foreign,[1]=foreign}}
          policy=require("runtime.space_exploration_system_force")
        ''')

    def rejected(self, mutation, after_preflight=False):
        if after_preflight:
            self.lua.execute("plan=policy.preflight(event)")
        self.lua.execute(mutation)
        ok, message = self.lua.eval("pcall(function() policy.apply(plan) end)" if after_preflight
                                    else "pcall(function() policy.preflight(event) end)")
        self.assertFalse(ok, mutation)
        self.assertTrue(message, mutation)
        self.assertEqual(self.lua.eval("#native_writes"), 0, mutation)
        self.assertEqual(self.lua.eval("forbidden_writes"), 0, mutation)

    def test_source_authored_values_only_on_the_same_production_predicate_with_or_without_observer(self):
        for extra in (None, "mir-fixture-mir5-worker-storage-se-cap-ten-native", "unrelated-unchanged-mod"):
            with self.subTest(extra=extra):
                self.setUp()
                if extra:
                    self.lua.globals().extra_mod = extra
                    self.lua.execute('active[extra_mod]="0.1.0";event.mod_changes[extra_mod]={old_version="0.1.0",new_version="0.1.0"}')
                self.lua.execute('''
                  plan=policy.preflight(event);assert(#native_writes==0)
                  policy.apply(plan)
                  assert(fields.worker_robots_speed_modifier==5.65 and fields.worker_robots_storage_bonus==3)
                  assert(fields.artillery_range_modifier==1.8 and gun["artillery-shell"]==6)
                  assert(gun.laser==2.2 and ammo.laser==5.1 and #native_writes==6)
                  assert(foreign.worker_robots_storage_bonus==8 and foreign.research_progress==.039024390243902)
                  assert(foreign.queue=="worker,worker,tail"and forbidden_writes==0)
                  assert(fields.current_research==nil and #fields.research_queue==0)
                  for _,name in ipairs(basic)do assert(rows[name].researched and rows[name].level==1)end
                  for name,row in pairs(rows)do assert(row.saved_progress==0)end
                  local ok=pcall(function()policy.apply(plan)end);assert(not ok and #native_writes==6)
                ''')

    def test_inactive_or_unrelated_events_do_not_access_the_world(self):
        for mutation in ('target.id="f210"', 'active["space-exploration"]=nil',
                         'active["space-exploration"]="0.7.58"', 'event=nil', 'event.mod_changes={}',
                         'event.mod_changes["more-infinite-research"].old_version="4.7.20003"',
                         'event.mod_changes["more-infinite-research"].new_version="5.0.20019"'):
            with self.subTest(mutation=mutation):
                self.setUp()
                self.lua.execute(mutation + ';game=setmetatable({}, {__index=function()error("world access")end})')
                self.lua.execute("assert(policy.preflight(event)==nil);policy.apply(nil);assert(#native_writes==0)")

    def test_profile_and_configuration_opponents_refuse_before_writes(self):
        mutations = ['event.mod_startup_settings_changed=true', 'event.mod_startup_settings_changed=nil',
                     'active.base="2.0.78"', 'active.Krastorio2="1.0.0"', 'active["space-age"]="2.0.77"',
                     'event.mod_changes.foreign={old_version="1.0.0"}',
                     'event.mod_changes.jetpack={old_version="0.4.16",new_version="0.4.17"}',
                     'event.mod_changes["mir-fixture-mir5-worker-storage-se-cap-ten-native"]={old_version="0.1.0"}',
                     'active["mir-fixture-mir5-worker-storage-se-cap-ten-native"]="0.1.0";event.mod_changes["mir-fixture-mir5-worker-storage-se-cap-ten-native"]={new_version="0.1.0"}']
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.setUp()
                self.rejected(mutation)

    def test_mixed_nonfinite_or_unavailable_scripted_values_are_not_absence(self):
        for mutation in ('fields.worker_robots_speed_modifier=5.65', 'fields.worker_robots_storage_bonus=3',
                         'fields.artillery_range_modifier=1.8', 'gun["artillery-shell"]=6', 'gun.laser=2.2',
                         'ammo.laser=5.1', 'fields.worker_robots_storage_bonus=nil',
                         'fields.worker_robots_storage_bonus=0/0', 'ammo.laser=math.huge',
                         'fields.get_gun_speed_modifier=function()error("unavailable getter")end',
                         'fields.set_ammo_damage_modifier=nil'):
            with self.subTest(mutation=mutation):
                self.setUp()
                self.rejected(mutation)

    def test_any_native_investment_or_nonstandard_system_force_refuses(self):
        for mutation in ('fields.valid=false', 'fields.name="player"', 'fields.index=1', 'fields.ai_controllable=false',
                         'fields.players={foreign}', 'fields.current_research=rows["worker-robots-storage-4"]',
                         'fields.research_progress=.1', 'fields.research_queue={rows["worker-robots-storage-4"]}',
                         'fields.research_queue=false', 'rows["worker-robots-storage-4"].researched=true',
                         'rows["worker-robots-storage-4"].level=5', 'rows["worker-robots-storage-2"].saved_progress=.42',
                         'rows["worker-robots-storage-1"].researched=nil', 'rows.artillery.researched=false',
                         'rows.tank=nil', 'rows.artillery.prototype.max_level=4294967295',
                         'rows.artillery.prototype.effects={{type="worker-robot-storage",modifier=3}}',
                         'rows.artillery.prototype.effects=nil', 'rows["worker-robots-storage-1"].valid=false'):
            with self.subTest(mutation=mutation):
                self.setUp()
                self.rejected(mutation)

    def test_revalidation_refuses_intervening_foreign_changes(self):
        for mutation in ('active.base="2.0.78"', 'event.mod_changes.foreign={new_version="1.0.0"}',
                         'event.mod_startup_settings_changed=true',
                         'fields.worker_robots_storage_bonus=9', 'ammo.laser=.25',
                         'fields.players={foreign}', 'rows["worker-robots-storage-4"].level=5',
                         'game.forces.conquest=foreign'):
            with self.subTest(mutation=mutation):
                self.setUp()
                self.rejected(mutation, after_preflight=True)

    def test_failed_postcondition_propagates_and_cannot_replay_the_plan(self):
        self.lua.execute('''
          plan=policy.preflight(event)
          fields.set_ammo_damage_modifier=function(name,value)
            native_writes[#native_writes+1]="wrong-damage";ammo[name]=value+1 end
          local ok,message=pcall(function()policy.apply(plan)end)
          assert(not ok and message:find("readback differs",1,true) and #native_writes==6)
          assert(plan.used and ammo.laser==6.1)
          ok=pcall(function()policy.apply(plan)end);assert(not ok and #native_writes==6)
        ''')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    args, remaining = parser.parse_known_args()
    sys.path.insert(0, args.lua_runtime_dir)
    global LuaRuntime
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)


if __name__ == "__main__":
    main()
