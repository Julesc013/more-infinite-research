"""Independent controls for the F100/F110 laser save-transition fixture, not native evidence."""
import argparse
from copy import deepcopy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/f100-f110-laser"
PACKS = ["automation-science-pack", "chemical-science-pack", "logistic-science-pack",
         "military-science-pack", "utility-science-pack"]


def lua_value(lua, value):
    if isinstance(value, dict):
        return lua.table_from({k: lua_value(lua, v) for k, v in value.items()})
    if isinstance(value, list):
        return lua.table_from([lua_value(lua, v) for v in value])
    return value


class LaserFixtureControls(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          function laser_data(path, stage_path, row)
            local stage=assert(loadfile(stage_path))()
            local env={mods={base=stage.base,["more-infinite-research"]=stage.mir},
              data={raw={technology={[stage.laser]=row}}},require=function(name)
                assert(name=="stage");return stage
              end}
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(assert(loadfile(path,"t",env)));return ok,tostring(message)
          end
          function laser_flow(path, source_stage, successor_stage, opponent)
            local global,markers,saves={},0,0
            local source=assert(loadfile(source_stage))();local destination=assert(loadfile(successor_stage))()
            local current_stage=source
            local packs={"automation-science-pack","chemical-science-pack","logistic-science-pack",
              "military-science-pack","utility-science-pack"}
            local input={}
            function input.insert(row)
              for _,stack in ipairs(input)do if stack.name==row.name then stack.count=stack.count+row.count;return row.count end end
              input[#input+1]={valid_for_read=true,name=row.name,count=row.count,durability=1};return row.count
            end
            local function consume(units)
              for _,stack in ipairs(input)do
                if units==1 then stack.count=stack.count-1 else stack.durability=1-units end
              end
            end
            local lab={valid=true,active=true,energy=0,get_inventory=function()return input end}
            local forces={}
            local function force(name)
              local queue,progress,saved={},0,{}
              local f={name=name,valid=true,technologies={},worker_robots_speed_modifier=0,
                manual_mining_speed_modifier=0,laboratory_speed_modifier=0,laboratory_productivity_bonus=0,
                research_queue_enabled=false,bonus=2.5}
              local laser={name=source.laser,valid=true,level=8,researched=false,enabled=true,
                visible_when_disabled=true,prerequisites={},research_unit_count=1,research_unit_energy=60,
                prototype={max_level=12,effects={{type="gun-speed",ammo_category=source.ammo,modifier=.01}}}}
              local probe={name="braking-force-1",valid=true,level=1,researched=false,enabled=true,prerequisites={}}
              laser.force,probe.force=f,f
              f.technologies[source.laser]=laser;f.technologies[probe.name]=probe
              setmetatable(f,{__index=function(_,key)
                if key=="research_queue"then return queue elseif key=="current_research"then return queue[1]
                elseif key=="research_progress"then return progress end
              end,__newindex=function(t,key,value)
                if key=="research_queue"then queue=value;progress=0
                elseif key=="research_progress"then progress=value else rawset(t,key,value)end
              end})
              function f.get_gun_speed_modifier(ammo)assert(ammo==current_stage.ammo);return f.bonus end
              function f.enable_all_prototypes()end
              function f.add_research(value)queue[#queue+1]=value;return true end
              function f.get_saved_technology_progress(value)return saved[value.name]end
              function f.set_saved_technology_progress(value,amount)saved[value.name]=amount end
              f.saved=saved;forces[name]=f;return f
            end
            local player=force("player")
            local game={tick=0,forces=forces,surfaces={{create_entity=function()return lab end}}}
            function game.create_force(name)return force(name)end
            function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
            local function load_control(stage)
              current_stage=stage
              local callbacks={}
              local env={global=global,game=game,settings={startup={
                ["mir-max-level-laser-shooting-speed"]={value=12},
                ["mir-effect-per-level-laser-shooting-speed"]={value=1},
                ["mir-research-time-laser-shooting-speed"]={value=1}}},
                require=function(name)assert(name=="stage");return stage end,
                defines={inventory={lab_input=1},events={on_tick=1,on_research_finished=2}},
                script={active_mods={base=stage.base,["more-infinite-research"]=stage.mir,
                  ["mir-fixture-f100-f110-laser"]=stage.fixture},on_init=function(f)callbacks.init=f end,
                  on_configuration_changed=function(f)callbacks.config=f end,on_load=function(f)callbacks.load=f end,
                  on_event=function(e,f)callbacks[e]=f end},
                log=function(text)assert(text:match('^%[MIR5_NATIVE_FIXTURE%] RESULT '));markers=markers+1 end}
              env._G=env;setmetatable(env,{__index=_G})
              assert(loadfile(path,"t",env))();return callbacks,env
            end
            local function invoke(callback,event)
              local ok,message=pcall(callback,event)
              return ok,tostring(message)
            end
            local function tick(c)game.tick=game.tick+1;return invoke(c[1])end
            local function failure(message)return {ok=false,message=message,markers=markers,saves=saves}end
            local src=load_control(source)
            local ok,message=invoke(src.init);if not ok then return failure(message)end
            consume(1);player.technologies[source.laser].level=9;player.bonus=2.51;player.research_queue={}
            ok,message=invoke(src[2],{research=player.technologies[source.laser]});if not ok then return failure(message)end
            ok,message=tick(src);if not ok then return failure(message)end
            for _=1,2 do invoke(src.load);ok,message=tick(src);if not ok then return failure(message)end end
            local state=global.mir_f100_f110_laser
            for _,f in pairs(forces)do
              local value=f.technologies[source.laser];f.technologies[source.laser]=nil
              value.name=destination.laser;value.prototype.effects[1].ammo_category=destination.ammo
              f.technologies[destination.laser]=value
              f.saved[destination.laser]=f.saved[source.laser];f.saved[source.laser]=nil
            end
            local target=player.technologies[destination.laser]
            local foreign=forces["mir-laser-foreign"]
            if opponent=="old-identity"then player.technologies[source.laser]=target
            elseif opponent=="level"then target.level=8
            elseif opponent=="bonus"then player.bonus=2.5
            elseif opponent=="queue"then player.research_progress=.41
            elseif opponent=="foreign-enable"then foreign.technologies[destination.laser].enabled=true
            elseif opponent=="foreign-visible"then foreign.technologies[destination.laser].visible_when_disabled=true
            elseif opponent=="suspended"then forces["mir-laser-suspended"].saved[destination.laser]=.26
            elseif opponent=="foreign-queue"then foreign.research_progress=.41
            elseif opponent=="source-count"then state.source_labs=0
            elseif opponent=="source-phase"then state.phase="source-lab"
            elseif opponent=="effect"then target.prototype.effects[1].modifier=.02
            elseif opponent=="max-level"then target.prototype.max_level=11
            end
            local dst=load_control(destination)
            invoke(dst.load);ok,message=invoke(dst.config);if not ok then return failure(message)end
            -- Several ordinary ticks after configuration must not be mistaken for cold reloads.
            for _=1,3 do ok,message=tick(dst);if not ok then return failure(message)end end
            local spent=state.successor_units
            if opponent=="science"then spent=spent+1/60 end
            consume(spent);target.level=10;player.bonus=2.52
            player.research_queue={player.technologies["braking-force-1"]}
            ok,message=invoke(dst[2],{research=target});if not ok then return failure(message)end
            if opponent=="duplicate"then state.successor_labs=2 end
            ok,message=tick(dst);if not ok then return failure(message)end
            if opponent=="cold-drift"then foreign.research_progress=.41 end
            for _=1,2 do invoke(dst.load);ok,message=tick(dst);if not ok then return failure(message)end end
            return {ok=true,markers=markers,saves=saves,source=state.source_labs,successor=state.successor_labs,
              level=target.level,bonus=player.bonus,spent=state.successor_units,phase=state.phase}
          end
        ''')

    def row(self, role):
        old = role == "source"
        prefix = "laser-turret-speed-" if old else "laser-shooting-speed-"
        return {
            "type": "technology", "name": prefix + "8", "level": 8, "max_level": 12, "upgrade": True,
            "unit": {"count_formula": "1*(1*1^(L-8))", "time": 1, "ingredients": [[n, 1] for n in PACKS]},
            "effects": [{"type": "gun-speed", "ammo_category": "laser-turret" if old else "laser", "modifier": .01}],
            "prerequisites": ["chemical-science-pack", prefix + "6", prefix + "7", "logistic-science-pack",
                              "military-science-pack", "utility-science-pack"],
        }

    def run_flow(self, opponent=""):
        return self.lua.eval("laser_flow")(
            str(FIXTURE / "shared/control.lua"), str(FIXTURE / "source/stage.lua"),
            str(FIXTURE / "successor/stage.lua"), opponent)

    def test_acceleration_uses_the_retained_double_effect_setting(self):
        self.lua.execute('''
          data={raw={}}
          local fields={
            ["bool-setting"]={"mir-enable-laser-shooting-speed"},
            ["int-setting"]={"mir-cost-base-laser-shooting-speed","mir-cost-linear-increment-laser-shooting-speed",
              "mir-max-level-laser-shooting-speed","mir-research-time-laser-shooting-speed"},
            ["double-setting"]={"mir-cost-growth-laser-shooting-speed","mir-effect-per-level-laser-shooting-speed"}}
          for kind,names in pairs(fields)do
            data.raw[kind]={}
            for _,name in ipairs(names)do data.raw[kind][name]={setting_type="startup",default_value=0}end
          end
        ''')
        self.lua.execute(f'assert(loadfile({str(FIXTURE / "shared/settings-updates.lua")!r}))()')
        self.assertEqual(self.lua.eval('data.raw["double-setting"]["mir-effect-per-level-laser-shooting-speed"].default_value'), 1)

    def test_preflight_validates_exact_rows_without_mutating_them(self):
        for role in ("source", "successor"):
            row = self.row(role)
            ok, message = self.lua.eval("laser_data")(
                str(FIXTURE / "shared/data-final-fixes.lua"), str(FIXTURE / role / "stage.lua"), lua_value(self.lua, row))
            self.assertTrue(ok, message)
            for field, value in (("max_level", 11), ("level", 9), ("enabled", False)):
                bad = deepcopy(row); bad[field] = value
                ok, _ = self.lua.eval("laser_data")(
                    str(FIXTURE / "shared/data-final-fixes.lua"), str(FIXTURE / role / "stage.lua"), lua_value(self.lua, bad))
                self.assertFalse(ok)
        self.assertNotIn("data:extend", (FIXTURE / "shared/data-final-fixes.lua").read_text())

    def test_one_real_source_and_successor_completion_then_independent_reload_witnesses(self):
        r = self.run_flow()
        self.assertTrue(r["ok"], r["message"])
        self.assertEqual((1, 1, 10, 6, 2), (r["source"], r["successor"], r["level"], r["markers"], r["saves"]))
        self.assertAlmostEqual(r["bonus"], 2.52)
        self.assertAlmostEqual(r["spent"], 35 / 60)
        self.assertEqual(r["phase"], "successor-complete")

    def test_missing_migration_earned_effects_queues_and_foreign_ownership_are_rejected(self):
        for opponent in ("old-identity", "level", "bonus", "queue", "foreign-enable", "foreign-visible",
                         "suspended", "foreign-queue", "source-count", "source-phase", "effect", "max-level"):
            with self.subTest(opponent=opponent):
                r = self.run_flow(opponent)
                self.assertFalse(r["ok"])
                self.assertEqual((3, 1), (r["markers"], r["saves"]))

    def test_wrong_science_duplicate_lab_and_cold_drift_remain_failures(self):
        for opponent, phrase in (("science", "science consumption"), ("duplicate", "lab count"), ("cold-drift", "foreign queue")):
            with self.subTest(opponent=opponent):
                r = self.run_flow(opponent)
                self.assertFalse(r["ok"])
                self.assertIn(phrase, r["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LaserFixtureControls)).wasSuccessful())
