"""Independent controls for the bounded MIR 1.1 module credit bridge."""
import argparse
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
DEFINITIONS = ROOT / "source/research/legacy_module_credit_definitions.lua"
RUNTIME = ROOT / "source/runtime/legacy_module_credits.lua"
UINT32_MAX = 4294967295


def py(value):
    if hasattr(value, "items"):
        pairs = list(value.items())
        keys = [key for key, _ in pairs]
        if keys and all(isinstance(key, int) and key > 0 for key in keys) and set(keys) == set(range(1, len(keys) + 1)):
            return [py(value[index]) for index in range(1, len(keys) + 1)]
        return {key: py(item) for key, item in pairs}
    return value


class LegacyModuleCreditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua.globals().definitions_path = DEFINITIONS.as_posix()
        cls.lua.globals().runtime_path = RUNTIME.as_posix()
        cls.lua.execute(r'''
          local UINT32_MAX=4294967295
          local function effects()
            return {
              {type="change-recipe-productivity",recipe="efficiency-module",change=.1},
              {type="change-recipe-productivity",recipe="productivity-module",change=.1},
              {type="change-recipe-productivity",recipe="speed-module",change=.1},
              {type="change-recipe-productivity",recipe="efficiency-module-2",change=.05},
              {type="change-recipe-productivity",recipe="productivity-module-2",change=.05},
              {type="change-recipe-productivity",recipe="speed-module-2",change=.05},
              {type="change-recipe-productivity",recipe="efficiency-module-3",change=.02},
              {type="change-recipe-productivity",recipe="productivity-module-3",change=.02},
              {type="change-recipe-productivity",recipe="speed-module-3",change=.02},
            }
          end
          local function holder(descriptor)
            return {valid=true,name=descriptor.id,level=1,researched=false,enabled=false,visible_when_disabled=false,
              research_unit_count=1,research_unit_energy=1,
              research_unit_ingredients={{name="automation-science-pack",amount=1}},
              prototype={name=descriptor.id,level=1,max_level=UINT32_MAX,hidden=true,enabled=false,
                visible_when_disabled=false,upgrade=true,effects={{type="change-recipe-productivity",recipe=descriptor.recipe,change=descriptor.change}}}}
          end
          local function force(index,level,researched,descriptors)
            local technologies={
              ["recipe-prod-research_modules-1"]={valid=true,name="recipe-prod-research_modules-1",level=level,
                researched=researched,enabled=true,saved_progress=.27,prototype={name="recipe-prod-research_modules-1",level=1,max_level=UINT32_MAX,
                  hidden=false,enabled=true,upgrade=true,effects=effects()}},
            }
            for _,descriptor in ipairs(descriptors) do technologies[descriptor.id]=holder(descriptor) end
            return {valid=true,index=index,technologies=technologies,research_queue={"preserved"},research_progress=.42}
          end
          function legacy_module_credit_environment(target)
            local env={storage={}}
            local callbacks={}
            env.script={active_mods={},on_configuration_changed=function(fn)callbacks.configuration=fn end}
            if target=="f200" then
              env.script.active_mods={base="2.0.77",["more-infinite-research"]="5.0.20000"}
            elseif target=="f210" then
              env.script.active_mods={base="2.1.23",["more-infinite-research"]="5.0.21000"}
            elseif target=="f210-space-age" then
              env.script.active_mods={base="2.1.23",["more-infinite-research"]="5.0.21000",["space-age"]="2.0.77"}
            else error("unknown test target") end
            env.require=function(name)
              assert(name=="research.legacy_module_credit_definitions")
              return assert(loadfile(definitions_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            local runtime=assert(loadfile(runtime_path,"t",env))()
            local definitions=env.require("research.legacy_module_credit_definitions")
            local descriptors=definitions.descriptors()
            local player=force(1,3,false,descriptors)
            local foreign=force(2,1,true,descriptors)
            env.game={forces={player=player,foreign=foreign}}
            local event={mod_changes={ ["more-infinite-research"]={old_version="1.1.0",new_version=env.script.active_mods["more-infinite-research"]}}}
            return {env=env,runtime=runtime,definitions=definitions,descriptors=descriptors,player=player,foreign=foreign,event=event,callbacks=callbacks}
          end
          function legacy_module_credit_success(target)
            local value=legacy_module_credit_environment(target)
            local plan=value.runtime.preflight(value.event)
            assert(plan and plan.target==target and #plan.forces==2)
            assert(plan.forces[1].force==nil and plan.forces[2].force==nil)
            assert(value.env.storage.mir_legacy_module_credits==nil)
            for _,descriptor in ipairs(value.descriptors) do
              assert(value.player.technologies[descriptor.id].level==1)
              assert(value.foreign.technologies[descriptor.id].level==1)
            end
            assert(value.runtime.apply(plan)==true)
            local result={storage=value.env.storage.mir_legacy_module_credits,
              player_main=value.player.technologies["recipe-prod-research_modules-1"].level,
              foreign_main=value.foreign.technologies["recipe-prod-research_modules-1"].level,
              player_saved=value.player.technologies["recipe-prod-research_modules-1"].saved_progress,
              player_queue=value.player.research_queue[1],foreign_progress=value.foreign.research_progress,
              first=value.descriptors[1]}
            result.player_holder=value.player.technologies[result.first.id]
            result.foreign_holder=value.foreign.technologies[result.first.id]
            assert(value.runtime.on_configuration_changed(value.event)==false)
            return result
          end
          function legacy_module_credit_reject_after_preflight()
            local value=legacy_module_credit_environment("f200")
            local plan=value.runtime.preflight(value.event)
            local tampered=value.foreign.technologies[value.descriptors[1].id]
            tampered.prototype.effects[1].change=.02
            local ok,message=pcall(function() value.runtime.apply(plan) end)
            return {ok=ok,message=tostring(message),storage=value.env.storage.mir_legacy_module_credits,
              player_level=value.player.technologies[value.descriptors[1].id].level,
              foreign_level=tampered.level}
          end
          function legacy_module_credit_reject_nondefault_main()
            local value=legacy_module_credit_environment("f200")
            value.player.technologies["recipe-prod-research_modules-1"].prototype.effects[1].change=.2
            local ok,message=pcall(function() value.runtime.preflight(value.event) end)
            return {ok=ok,message=tostring(message),storage=value.env.storage.mir_legacy_module_credits,
              holder=value.player.technologies[value.descriptors[1].id].level}
          end
          function legacy_module_credit_inactive(target,old_version)
            local value=legacy_module_credit_environment(target)
            value.event.mod_changes["more-infinite-research"].old_version=old_version
            local result=value.runtime.preflight(value.event)
            return {result=result,storage=value.env.storage.mir_legacy_module_credits,
              holder=value.player.technologies[value.descriptors[1].id].level}
          end
          function legacy_module_credit_reset_cleanup()
            local value=legacy_module_credit_environment("f200")
            assert(value.runtime.on_configuration_changed(value.event)==true)
            local before={}
            for _,descriptor in ipairs(value.descriptors) do
              local holder=value.player.technologies[descriptor.id]
              before[descriptor.id]=holder.level;holder.enabled=true;holder.visible_when_disabled=true
            end
            local cleaned=value.runtime.on_technology_effects_reset({force=value.player})
            local result={cleaned=cleaned,before=before,holders={}}
            for _,descriptor in ipairs(value.descriptors) do
              local holder=value.player.technologies[descriptor.id]
              result.holders[descriptor.id]={level=holder.level,enabled=holder.enabled,visible=holder.visible_when_disabled}
            end
            return result
          end
        ''')

    def test_detached_definitions_preserve_three_independent_hidden_holders(self):
        self.lua.execute(r'''
          function legacy_module_credit_definition_rows()
            local value=legacy_module_credit_environment("f200")
            local one=value.definitions.technologies();local two=value.definitions.technologies()
            one[1].effects[1].change=.5;one[1].unit.ingredients[1][2]=9
            return {one=one,two=two,descriptors=value.definitions.descriptors()}
          end
        ''')
        result = py(self.lua.eval("legacy_module_credit_definition_rows")())
        self.assertEqual(3, len(result["two"]))
        self.assertEqual(
            ["mir-legacy-module-credit-speed-module", "mir-legacy-module-credit-productivity-module",
             "mir-legacy-module-credit-efficiency-module"],
            [row["name"] for row in result["two"]],
        )
        for row, descriptor in zip(result["two"], result["descriptors"]):
            self.assertEqual((True, False, False, "infinite", 1, 1),
                             (row["hidden"], row["enabled"], row["visible_when_disabled"], row["max_level"],
                              row["unit"]["count"], row["unit"]["time"]))
            self.assertEqual(("change-recipe-productivity", descriptor["recipe"], .01),
                             (row["effects"][0]["type"], row["effects"][0]["recipe"], row["effects"][0]["change"]))
        self.assertEqual(.01, result["two"][0]["effects"][0]["change"])
        self.assertEqual(1, result["two"][0]["unit"]["ingredients"][0][1])

    def test_exact_f200_and_f210_base_preflight_freeze_only_old_completed_levels(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                result = py(self.lua.eval("legacy_module_credit_success")(target))
                self.assertEqual(True, result["storage"]["applied"])
                self.assertEqual((3, 1, .27, "preserved", .42),
                                 (result["player_main"], result["foreign_main"], result["player_saved"],
                                  result["player_queue"], result["foreign_progress"]))
                self.assertEqual((3, False, False),
                                 (result["player_holder"]["level"], result["player_holder"]["enabled"], result["player_holder"]["visible_when_disabled"]))
                self.assertEqual((2, False, False),
                                 (result["foreign_holder"]["level"], result["foreign_holder"]["enabled"], result["foreign_holder"]["visible_when_disabled"]))

    def test_current_shape_drift_or_apply_time_holder_drift_refuses_before_all_writes(self):
        nondefault = py(self.lua.eval("legacy_module_credit_reject_nondefault_main")())
        self.assertFalse(nondefault["ok"])
        self.assertIn("non-current force shape", nondefault["message"])
        self.assertNotIn("storage", nondefault)
        self.assertEqual(1, nondefault["holder"])

        drift = py(self.lua.eval("legacy_module_credit_reject_after_preflight")())
        self.assertFalse(drift["ok"])
        self.assertIn("plan no longer matches", drift["message"])
        self.assertNotIn("storage", drift)
        self.assertEqual((1, 1), (drift["player_level"], drift["foreign_level"]))

    def test_unknown_or_space_age_events_do_not_gain_credit(self):
        for target, old_version in (("f200", "1.0.0"), ("f210-space-age", "1.1.0")):
            with self.subTest(target=target, old_version=old_version):
                result = py(self.lua.eval("legacy_module_credit_inactive")(target, old_version))
                self.assertNotIn("result", result)
                self.assertNotIn("storage", result)
                self.assertEqual(1, result["holder"])

    def test_effect_reset_restores_only_the_owned_hidden_flags_without_changing_levels(self):
        result = py(self.lua.eval("legacy_module_credit_reset_cleanup")())
        self.assertTrue(result["cleaned"])
        for identifier, before in result["before"].items():
            holder = result["holders"][identifier]
            self.assertEqual(before, holder["level"])
            self.assertFalse(holder["enabled"])
            self.assertFalse(holder["visible"])

    def test_runtime_has_no_tick_research_or_recipe_bonus_reconciliation(self):
        source = RUNTIME.read_text(encoding="utf-8")
        self.assertNotIn("on_tick", source)
        self.assertNotIn("on_research_finished", source)
        self.assertNotIn("recipe_bonus", source)
        self.assertIn("function M.preflight(event)", source)
        self.assertIn("function M.apply(plan)", source)
        self.assertIn("function M.on_technology_effects_reset(event)", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    LegacyModuleCreditTests.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LegacyModuleCreditTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
