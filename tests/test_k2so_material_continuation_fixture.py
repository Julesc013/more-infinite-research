"""Independent host controls for the staged K2SO continuation native observer.

The world supplies explicit native outcomes; these tests check observer logic and
scenario construction. They do not establish Factorio gameplay or preservation.
"""

from __future__ import annotations

import argparse
import json
import sys
import unittest
from pathlib import Path

from k2so_material_continuation_world import EARLY, FIXTURE, FixtureWorld


ROOT = Path(__file__).resolve().parents[1]
PROBE = "mir-k2so-material-continuation-probe"
FOREIGN = "mir-k2so-material-continuation-foreign"
KEY = "mir5_k2so_material_continuation"
ROLES = ("source", "upgrade", "finite", "relaxed")
ENGINE_SHA = "062277B9D91F5DF9E655A77E6A94EC0208E668ECFC1C4424EE1B12C9AAAB2DCF"
DEPENDENCIES = {
    "base": "2.1.24", "elevated-rails": "2.1.24", "quality": "2.1.24",
    "recycler": "2.1.24", "space-age": "2.1.24", "flib": "0.17.2",
    "k2so-assets": "1.0.7", "Krastorio2": "2.1.4", "Krastorio2-spaced-out": "2.0.19",
    "Krastorio2Assets": "2.1.0", "Krastorio2MenuSimulations": "2.1.0",
    "xy-k2so-enhancements-nulls-fork": "0.8.3", "mir-fixture-mir5-active-mods-observer": "0.1.0",
}
ARCHIVES = {
    "flib_0.17.2.zip": "0A48C15DC0FC6C13BB3FE8293BA6CB35A07F3B0F37D37ACB50AB30E32E8E019D",
    "k2so-assets_1.0.7.zip": "C3E11214407B08120B2EE717405D3B0398F533647695AB2E6EF6DF9267D62017",
    "Krastorio2_2.1.4.zip": "9E5A56AC52BA0DD96A2D9FFBEFB8B242270EC946159D3DBED77B24B3C1C7147E",
    "Krastorio2-spaced-out_2.0.19.zip": "8FCA3A3C202DD4939D5D85ACE93BE775CEDFE3D02FBDAF9DB78B77883B2C662B",
    "Krastorio2Assets_2.1.0.zip": "39EF950EC8B21A40357DD0240EF8389501EE75CCA82717F2773B98554DA46E29",
    "Krastorio2MenuSimulations_2.1.0.zip": "3A485B449B356DC4B3EB4233DE4E803B3A001259FBC251BDC9F9D9120B3C53A7",
    "xy-k2so-enhancements-nulls-fork_0.8.3.zip": "930F43B96B04012FEF090C40D8B16A6B3F259D1713C86CF59DFF3E9A5A97E2BE",
    "mir-fixture-mir5-active-mods-observer_0.1.0.zip": "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C",
}


class K2SOMaterialContinuationFixtureTests(unittest.TestCase):
    runtime_type = None

    def setUp(self):
        self.world = FixtureWorld(self.runtime_type)
        self.lua = self.world.lua

    def call(self, handler, event=None):
        ok, message = self.lua.eval("world_call")(handler, event)
        self.assertTrue(ok, message)

    def tick(self, count=1, scripted=False):
        return self.lua.eval("world_tick")(count, scripted)

    def until(self, predicate, limit=20000):
        for _ in range(limit):
            if self.lua.eval(predicate):
                return
            self.tick()
        self.fail(f"bounded mocked input sequence did not reach {predicate}")

    def source(self):
        self.world.load("source")
        self.call("init")
        self.until("#saves==1")

    def upgrade(self):
        self.source()
        self.world.execute("world_add_tails()")
        self.world.load("upgrade")
        self.call("configuration")
        self.until("#saves==2")

    def finite(self):
        self.upgrade()
        self.world.execute('''
          for _,force in pairs(game.forces)do
            for _,family in ipairs{"rare_metals","silicon","glass"}do
              world_set_state(force.name,"recipe-prod-research_material_"..family.."-4",{enabled=false,visible_when_disabled=true})
            end
          end
          world_set_work("player",{"mir-k2so-material-continuation-probe"},0)
        ''')
        self.world.load("finite")
        self.call("configuration")
        self.until("#saves==3")

    def relaxed(self):
        self.finite()
        self.world.execute('''
          for _,force in pairs(game.forces)do
            for _,family in ipairs{"rare_metals","silicon","glass"}do
              world_set_state(force.name,"recipe-prod-research_material_"..family.."-4",{enabled=force.name=="player",visible_when_disabled=false})
            end
          end
        ''')
        self.world.load("relaxed")
        self.call("configuration")
        self.until("#saves==4")

    def data_world(self, role):
        """Declared prototype inputs, independent of both renderer and actor."""
        technologies={}
        declarations=(
            ("rare_metals", ("kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals"),
             ("automation-science-pack","logistic-science-pack","chemical-science-pack"),
             ("automation-science-pack","logistic-science-pack","chemical-science-pack","kr-rare-metal-processing","kr-enriched-ores")),
            ("silicon", ("kr-silicon",), ("automation-science-pack","logistic-science-pack"),
             ("automation-science-pack","logistic-science-pack","kr-silicon-processing")),
            ("glass", ("kr-glass",), ("automation-science-pack","logistic-science-pack","chemical-science-pack"),
             ("automation-science-pack","logistic-science-pack","chemical-science-pack","kr-stone-processing")),
        )
        for family,recipes,science,prerequisites in declarations:
            early=f"recipe-prod-research_material_{family}-1"
            technologies[early]={"type":"technology","name":early,"level":1,"max_level":3,"upgrade":True,"enabled":True,
                "prerequisites":list(prerequisites),"effects":[{"type":"change-recipe-productivity","recipe":r,"change":.02} for r in recipes],
                "unit":{"count_formula":"200*2^(L-1)","time":30,"ingredients":[[s,1] for s in science]}}
            if role!="source":
                late=f"recipe-prod-research_material_{family}-4"
                technologies[late]={"type":"technology","name":late,"level":4,"max_level":"infinite","upgrade":True,"enabled":True,
                    "prerequisites":[early,"space-science-pack"],"effects":[{"type":"change-recipe-productivity","recipe":r,"change":.02} for r in recipes],
                    "unit":{"count_formula":"1600+200*(L-4)","time":30,"ingredients":[["space-science-pack",1]]}}
        raw={"technology":technologies,"lab":{
            "lab":{"type":"lab","name":"lab","energy_source":{"type":"electric","usage_priority":"secondary-input"},
                "researching_speed":1,"inputs":["automation-science-pack","logistic-science-pack","chemical-science-pack","space-science-pack"]},
            "k2so-white-lab":{"type":"lab","name":"k2so-white-lab","energy_source":{"type":"electric"},
                "inputs":["space-science-pack"]}},
            "int-setting":{f"ips-max-level-research_material_{family}":{"type":"int-setting","default_value":0} for family in EARLY}}
        self.lua.globals().prototype_inputs=self.lua.table_from(raw,recursive=True)
        self.lua.globals().fixture_data_file=str(FIXTURE/"fixture_data.lua")
        self.lua.execute('''
          local function clone(value)
            if type(value)~="table"then return value end
            local result={}for k,v in pairs(value)do result[k]=clone(v)end return result
          end
          table.deepcopy=clone
          data={raw=prototype_inputs,extend=function(self,rows)
            for _,row in ipairs(rows)do
              assert(self.raw[row.type][row.name]==nil,"duplicate fixture prototype")
              self.raw[row.type][row.name]=row
            end
          end}
          fixture_data=assert(loadfile(fixture_data_file))()
        ''')
        return raw

    @staticmethod
    def plain(value):
        if hasattr(value,"items"):
            return {key:K2SOMaterialContinuationFixtureTests.plain(member) for key,member in value.items()}
        return value

    def test_data_adds_only_probe_after_full_named_original_lab_validation(self):
        for role in ROLES:
            with self.subTest(role=role):
                self.data_world(role)
                original=self.plain(self.lua.eval("data.raw"))
                self.lua.eval("fixture_data.prototypes")(role)
                self.lua.eval("fixture_data.validate")(role)
                after=self.plain(self.lua.eval("data.raw"))
                for name,row in original["technology"].items():
                    self.assertEqual(after["technology"][name],row)
                for name,row in original["lab"].items():
                    self.assertEqual(after["lab"][name],row)
                self.assertEqual(set(after["technology"])-set(original["technology"]),{PROBE})
                self.assertEqual(after["lab"],original["lab"])
                self.lua.eval("fixture_data.settings")(role)
                for family in EARLY:
                    self.assertEqual(self.lua.eval(f'data.raw["int-setting"]["ips-max-level-research_material_{family}"].default_value'),3 if role=="finite" else 0)

    def test_data_refuses_wrong_cost_science_effect_progression_without_publishing_a_lab(self):
        opponents=(
            ('data.raw.technology["recipe-prod-research_material_glass-1"].unit.count_formula="1"',"cost/time"),
            ('data.raw.technology["recipe-prod-research_material_glass-4"].unit.time=1',"cost/time"),
            ('data.raw.technology["recipe-prod-research_material_silicon-4"].unit.ingredients={{"automation-science-pack",1}}',"science"),
            ('data.raw.technology["recipe-prod-research_material_glass-4"].effects[1].change=.01',"effect differs"),
            ('data.raw.technology["recipe-prod-research_material_rare_metals-4"].max_level=3',"progression/enablement"),
            ('data.raw.technology["recipe-prod-research_material_silicon-4"].prerequisites={"space-science-pack"}',"prerequisites"),
        )
        for mutation,reason in opponents:
            with self.subTest(mutation=mutation):
                self.data_world("upgrade")
                self.lua.execute(mutation)
                before=self.plain(self.lua.eval("data.raw"))
                with self.assertRaisesRegex(Exception,reason):
                    self.lua.eval("fixture_data.validate")("upgrade")
                self.assertEqual(self.plain(self.lua.eval("data.raw")),before)
                self.assertEqual(self.plain(self.lua.eval("data.raw.lab")),before["lab"])

    def test_named_original_lab_cannot_be_replaced_by_an_alternative_white_lab(self):
        self.data_world("upgrade")
        self.lua.execute('data.raw.lab["lab"].inputs={"chemical-science-pack"}')
        with self.assertRaisesRegex(Exception,"named original lab does not accept"):
            self.lua.eval("fixture_data.validate")("upgrade")

    def test_published_source_data_refuses_any_unexpected_continuation(self):
        for family in EARLY:
            with self.subTest(family=family):
                self.data_world("source")
                self.lua.execute(f'data.raw.technology["recipe-prod-research_material_{family}-4"]={{name="unexpected"}}')
                with self.assertRaisesRegex(Exception,"published source unexpectedly has a material continuation"):
                    self.lua.eval("fixture_data.validate")("source")

    def test_named_original_lab_and_temporary_speed_restore_an_observed_nonzero_baseline(self):
        self.world.execute("game.forces.player.laboratory_speed_modifier=.25")
        self.world.load("source")
        self.call("init")
        self.tick(3)
        self.assertEqual(self.lua.eval(f"storage.{KEY}.lab_speed_baseline"), .25)
        self.assertEqual(self.lua.eval("game.forces.player.laboratory_speed_modifier"), 115199.25)
        self.until("#saves==1")
        self.assertEqual(self.lua.eval("game.forces.player.laboratory_speed_modifier"), .25)
        self.assertEqual(self.lua.eval(f"storage.{KEY}.player.laboratory_speed_modifier"), .25)
        self.world.load("source")
        self.call("load")
        self.tick()
        self.assertEqual(self.lua.eval("game.forces.player.laboratory_speed_modifier"), .25)

    def test_nonzero_productivity_or_nonfinite_speed_baseline_refuses_before_fixture_writes(self):
        opponents=(
            ("game.forces.player.laboratory_speed_modifier=.25; game.forces.player.laboratory_productivity_bonus=.1",
             "laboratory baseline is invalid", .25, .1),
            ("game.forces.player.laboratory_speed_modifier=math.huge",
             "laboratory baseline is invalid", float("inf"), 0),
        )
        for setup, reason, speed, productivity in opponents:
            with self.subTest(setup=setup):
                world=FixtureWorld(self.runtime_type)
                world.execute(setup)
                world.load("source")
                ok,message=world.evaluate("world_call")("init",None)
                self.assertTrue(ok,message)
                with self.assertRaisesRegex(Exception,reason):
                    world.evaluate("world_tick")(2,False)
                self.assertEqual(world.evaluate("game.forces.player.laboratory_speed_modifier"),speed)
                self.assertEqual(world.evaluate("game.forces.player.laboratory_productivity_bonus"),productivity)
                self.assertFalse(world.evaluate('game.forces.player.technologies["automation-science-pack"].researched'))
                self.assertIsNone(world.evaluate(f'game.forces["{FOREIGN}"]'))
                self.assertEqual(world.evaluate("#world_labs"),0)
                self.assertEqual(world.evaluate("#saves"),0)
                self.assertEqual(world.evaluate("#game.forces.player.research_queue"),0)

    def test_private_lab_substitution_or_missed_speed_restoration_refuses_before_save(self):
        text=(FIXTURE/"fixture_control.lua").read_text(encoding="utf-8")
        private=text.replace('local LAB = "lab"','local LAB = "mir-k2so-material-continuation-lab"')
        self.world.load("source",actor_source=private)
        self.call("init")
        self.tick()
        with self.assertRaisesRegex(Exception,"fixture must use the named original lab"):
            self.tick()
        self.assertEqual(self.lua.eval("#saves"),0)

        restored=text.replace("set_running(state, false)\n    restore_lab_speed(state)\n    state.job_finished", "set_running(state, false)\n    state.job_finished", 1)
        self.world=FixtureWorld(self.runtime_type)
        self.lua=self.world.lua
        self.world.execute("game.forces.player.laboratory_speed_modifier=.25")
        self.world.load("source",actor_source=restored)
        self.call("init")
        with self.assertRaisesRegex(Exception,"laboratory baseline changed"):
            self.until("#saves==1")
        self.assertEqual(self.lua.eval("#saves"),0)

    def test_lab_entity_boundary_refuses_readonly_and_unknown_actor_access_before_science_or_save(self):
        self.world.execute('''
          local lab=game.surfaces[1].create_entity{name="lab",position={0,0},force=game.forces.player}
          lab.energy=100;lab.disabled_by_script=true;lab.destructible=false;lab.minable=false;lab.operable=false
          assert(lab.energy==100 and lab.disabled_by_script and not lab.destructible and not lab.minable and not lab.operable)
        ''')
        for statement in ('return world_labs[1].unknown_fixture_member', 'world_labs[1].unknown_fixture_member=true', 'world_labs[1].name="lab"'):
            with self.subTest(statement=statement):
                with self.assertRaisesRegex(Exception,"LuaEntity field"):
                    self.world.execute(statement)

        text=(FIXTURE/"fixture_control.lua").read_text(encoding="utf-8")
        anchor='state.lab=game.surfaces[1].create_entity{name=LAB,position={0,0},force=force}\n      set_running(state,false)'
        self.assertEqual(text.count(anchor),1)
        opponents=(
            ('state.lab.name=LAB', 'LuaEntity field: name'),
            ('local ignored=state.lab.unknown_fixture_member or false', 'LuaEntity field: unknown_fixture_member'),
        )
        for mutation,reason in opponents:
            with self.subTest(mutation=mutation):
                self.world=FixtureWorld(self.runtime_type)
                self.lua=self.world.lua
                actor=text.replace(anchor, 'state.lab=game.surfaces[1].create_entity{name=LAB,position={0,0},force=force}\n      '+mutation+'\n      set_running(state,false)')
                self.world.load("source",actor_source=actor)
                self.call("init")
                with self.assertRaisesRegex(Exception,reason):
                    self.tick(2)
                self.assertEqual(self.lua.eval("#saves"),0)
                self.assertEqual(self.lua.eval("#game.forces.player.research_queue"),0)
                self.assertTrue(self.lua.eval("world_labs[1].get_inventory(1).is_empty()"))

    def test_wrong_difficulty_api_field_is_a_live_rejected_opponent(self):
        text=(FIXTURE/"fixture_control.lua").read_text(encoding="utf-8")
        self.assertEqual(text.count("game.difficulty_settings.technology_price_multiplier"),1)
        opponent=text.replace("game.difficulty_settings.technology_price_multiplier","game.difficulty_settings.research_price_multiplier")
        self.world.load("source",actor_source=opponent)
        ok,message=self.lua.eval("world_call")("init",None)
        self.assertFalse(ok)
        self.assertIn("unknown DifficultySettings field: research_price_multiplier",message)
        self.assertIsNone(self.lua.eval(f"storage.{KEY}"))

    def test_force_boundary_rejects_removed_and_unknown_native_api_members(self):
        for statement in (
            "return game.forces.player.research_queue_enabled",
            "game.forces.player.unavailable_fixture_property=true",
            "return game.forces.player.unavailable_fixture_property",
        ):
            with self.subTest(statement=statement):
                with self.assertRaisesRegex(Exception,"LuaForce field"):
                    self.world.execute(statement)
        text=(FIXTURE/"fixture_control.lua").read_text(encoding="utf-8")
        anchor='assert_lab_baseline(state,"source setup")\n      for _, name in ipairs(PREREQUISITES)'
        self.assertEqual(text.count(anchor),1)
        opponent=text.replace(anchor,'assert_lab_baseline(state,"source setup")\n      force.research_queue_enabled=true\n      for _, name in ipairs(PREREQUISITES)')
        self.world.load("source",actor_source=opponent)
        self.call("init")
        with self.assertRaisesRegex(Exception,"LuaForce field: research_queue_enabled"):
            self.tick(2)
        self.assertEqual(self.lua.eval("#saves"),0)
        self.assertEqual(self.lua.eval(f"storage.{KEY}.finished"),0)

    def test_missing_per_tick_power_refill_cannot_hide_behind_unlimited_mock_energy(self):
        text=(FIXTURE/"fixture_control.lua").read_text(encoding="utf-8")
        original="if not state.job_finished then set_running(state,true); refill(state); return end"
        self.assertEqual(text.count(original),1)
        opponent=text.replace(original,"if not state.job_finished then refill(state); return end")
        self.world.load("source",actor_source=opponent)
        self.call("init")
        self.tick(3)
        with self.assertRaisesRegex(Exception,"bounded host lab energy exhausted"):
            self.tick()
        self.assertEqual(self.lua.eval("#saves"),0)
        self.assertEqual(self.lua.eval(f"storage.{KEY}.finished"),0)

    def test_unplanned_science_in_lab_prevents_successful_budget_acceptance(self):
        self.world.load("source")
        self.call("init")
        self.tick(2)
        self.world.execute('world_labs[1].get_inventory(1).set("space-science-pack",1)')
        with self.assertRaisesRegex(Exception,"exact science budget"):
            self.until("#saves==1")
        self.assertEqual(self.lua.eval("#saves"),0)

    def test_unrelated_research_callback_has_no_observer_accounting_authority(self):
        self.world.load("source")
        self.call("init")
        self.tick(2)
        event=self.lua.eval('{research=game.forces.player.technologies["automation-science-pack"],by_script=true}')
        self.call("research",event)
        self.assertEqual(self.lua.eval(f"storage.{KEY}.finished"),0)
        self.assertEqual(self.lua.eval(f"storage.{KEY}.work_index"),1)
        self.assertEqual(self.lua.eval("game.forces.player.research_progress"),0)
        self.assertEqual(self.lua.eval("#saves"),0)

    def test_source_observes_nine_ordinary_finite_completions_and_exact_supplied_science(self):
        self.source()
        self.assertEqual(self.lua.eval(f"storage.{KEY}.finished"), 9)
        self.assertEqual(self.lua.eval(f"storage.{KEY}.phase"), "complete")
        for pack, count in (("automation-science-pack", 4200), ("logistic-science-pack", 4200), ("chemical-science-pack", 2800)):
            self.assertEqual(self.lua.eval(f'storage.{KEY}.consumed["{pack}"]'), count)
        self.assertEqual(self.lua.eval(f'storage.{KEY}.consumed["space-science-pack"]'),0)
        for family, recipes in EARLY.items():
            row = f'game.forces.player.technologies["recipe-prod-research_material_{family}-1"]'
            self.assertEqual(self.lua.eval(row+".level"), 3)
            self.assertTrue(self.lua.eval(row+".researched"))
            self.assertIsNone(self.lua.eval(f'game.forces.player.technologies["recipe-prod-research_material_{family}-4"]'))
            for recipe in recipes:
                self.assertAlmostEqual(self.lua.eval(f'game.forces.player.recipes["{recipe}"].productivity_bonus'), .06)
        self.assertEqual(self.lua.eval("#saves"), 1)
        self.assertEqual(self.lua.eval("markers[1].witnesses.actual_lab_completions"), 9)

    def test_all_roles_preserve_paid_effects_partial_work_queues_and_foreign_disablements(self):
        self.relaxed()
        self.assertEqual(self.lua.eval("#saves"), 4)
        self.assertEqual(self.lua.eval(f"storage.{KEY}.finished"), 3)
        self.assertEqual(self.lua.eval(f'storage.{KEY}.consumed["space-science-pack"]'), 3440)
        self.assertEqual(self.lua.eval(f'storage.{KEY}.consumed["automation-science-pack"]'), 20)
        self.assertEqual(self.lua.eval('game.forces.player.technologies["recipe-prod-research_material_silicon-4"].level'), 7)
        self.assertAlmostEqual(self.lua.eval('game.forces.player.recipes["kr-silicon"].productivity_bonus'), .12)
        for recipe in ("kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals", "kr-glass"):
            self.assertAlmostEqual(self.lua.eval(f'game.forces.player.recipes["{recipe}"].productivity_bonus'), .08)
        for family in EARLY:
            row=f'game.forces["{FOREIGN}"].technologies["recipe-prod-research_material_{family}-4"]'
            self.assertEqual(self.lua.eval(row+".level"), 4)
            self.assertFalse(self.lua.eval(row+".enabled"))
            self.assertFalse(self.lua.eval(row+".researched"))
        self.assertIsNone(self.lua.eval("game.forces.player.current_research"))
        self.assertEqual(self.lua.eval("#game.forces.player.research_queue"), 0)
        self.assertEqual(self.lua.eval("markers[2].witnesses.science_consumed['space-science-pack']"), 5160)
        self.assertAlmostEqual(self.lua.eval("markers[2].witnesses.player.progress"), .2)
        self.assertEqual(self.lua.eval("#markers[2].witnesses.player.queue"), 3)
        self.assertEqual(self.lua.eval("#markers[3].witnesses.player.queue"), 1)

    def test_successor_cannot_initialize_a_fresh_world_or_skip_protected_stage(self):
        for role in ("upgrade", "finite", "relaxed"):
            with self.subTest(role=role):
                world=FixtureWorld(self.runtime_type)
                world.load(role)
                ok,message=world.evaluate("world_call")("init", None)
                self.assertFalse(ok)
                self.assertIn("successor cannot initialize a fresh world", message)
                ok,message=world.evaluate("world_call")("configuration", None)
                self.assertFalse(ok)
                self.assertIn("protected predecessor stage differs", message)
                self.assertEqual(world.evaluate("#saves"), 0)

    def test_source_requires_actual_unearned_state_and_absent_late_rows(self):
        for mutation in (
            "world_add_tails()",
            'game.forces.player.recipes["kr-silicon"].productivity_bonus=.02',
            'world_set_state("player","recipe-prod-research_material_glass-1",{level=2})',
        ):
            with self.subTest(mutation=mutation):
                world=FixtureWorld(self.runtime_type)
                world.execute(mutation)
                world.load("source")
                ok,message=world.evaluate("world_call")("init", None)
                self.assertTrue(ok,message)
                with self.assertRaisesRegex(Exception,"published initial material state|source has unearned material bonus"):
                    world.evaluate("world_tick")(2,False)
                self.assertEqual(world.evaluate("#saves"),0)

    def test_scripted_or_forged_research_events_cannot_count_as_ordinary_work(self):
        self.world.load("source")
        self.call("init")
        self.tick(2)
        self.assertEqual(self.lua.eval(f"storage.{KEY}.phase"),"work")
        event=self.lua.eval('{research=game.forces.player.current_research,by_script=true}')
        ok,message=self.lua.eval("world_call")("research",event)
        self.assertFalse(ok)
        self.assertIn("unexpected ordinary completion",message)
        self.assertEqual(self.lua.eval(f"storage.{KEY}.finished"),0)
        event=self.lua.eval('{research={name=game.forces.player.current_research.name,force=game.forces.player},by_script=false}')
        ok,message=self.lua.eval("world_call")("research",event)
        self.assertFalse(ok)
        self.assertEqual(self.lua.eval(f"storage.{KEY}.finished"),0)

    def test_foreign_change_during_research_cannot_become_the_saved_baseline(self):
        opponents=(
            (f'game.forces["{FOREIGN}"].recipes["kr-glass"].productivity_bonus=.02',
             "foreign.*paid recipe changed|foreign.*bonus"),
            (f'game.forces["{FOREIGN}"].laboratory_productivity_bonus=.1',
             "foreign.*laboratory modifiers changed"),
        )
        for mutation,reason in opponents:
            with self.subTest(mutation=mutation):
                self.world=FixtureWorld(self.runtime_type)
                self.lua=self.world.lua
                self.world.load("source")
                self.call("init")
                self.tick(2)
                self.world.execute(mutation)
                with self.assertRaisesRegex(Exception,reason):
                    self.until("#saves==1")
                self.assertEqual(self.lua.eval("#saves"),0)

    def test_save_requires_two_elapsed_ticks_and_rechecks_the_complete_snapshot(self):
        self.world.load("source")
        self.call("init")
        self.until(f"storage.{KEY}.phase=='settle'")
        self.assertEqual(self.lua.eval("#saves"),0)
        self.call("tick")
        self.call("tick")
        self.assertEqual(self.lua.eval("#saves"),0)
        self.tick()
        self.assertEqual(self.lua.eval("#saves"),0)
        self.world.execute('world_set_state("player","recipe-prod-research_material_glass-1",{saved_progress=.1})')
        with self.assertRaisesRegex(Exception,"saved flags/work changed"):
            self.tick()
        self.assertEqual(self.lua.eval("#saves"),0)

    def test_complete_roles_allow_two_read_only_callback_reloads(self):
        for saved_count,role in enumerate(ROLES,1):
            with self.subTest(role=role):
                self.world=FixtureWorld(self.runtime_type)
                self.lua=self.world.lua
                getattr(self,role)()
                for _ in range(2):
                    before=self.plain(self.lua.eval(f"storage.{KEY}"))
                    self.world.execute(f"saved_state_reference=storage.{KEY};saved_lab_reference=storage.{KEY}.lab")
                    self.world.load(role)
                    self.world.execute('''
                      local denied=setmetatable({}, {__index=function()error("on_load world access")end,
                        __newindex=function()error("on_load state write")end})
                      scenario_environment.game=denied;scenario_environment.storage=denied
                    ''')
                    self.call("load")
                    self.world.execute("scenario_environment.game=game;scenario_environment.storage=storage;observation_locked=true")
                    self.tick()
                    self.assertEqual(self.lua.eval("#saves"),saved_count)
                    self.assertEqual(self.lua.eval("markers[#markers].stage"),"reload")
                    self.assertTrue(self.lua.eval("markers[#markers].witnesses.on_load_read_only"))
                    self.assertEqual(self.plain(self.lua.eval(f"storage.{KEY}")),before)
                    self.assertTrue(self.lua.eval(f"rawequal(storage.{KEY},saved_state_reference)"))
                    self.assertTrue(self.lua.eval(f"rawequal(storage.{KEY}.lab,saved_lab_reference)"))
                    self.world.execute("observation_locked=false")

    def test_cold_effect_or_work_loss_fails_before_success_marker(self):
        self.upgrade()
        old_markers=self.lua.eval("#markers")
        self.world.load("upgrade")
        self.call("load")
        self.world.execute('game.forces.player.recipes["kr-silicon"].productivity_bonus=.06')
        with self.assertRaisesRegex(Exception,"cold player paid recipe changed"):
            self.tick()
        self.assertEqual(self.lua.eval("#markers"),old_markers)

    def test_cap_transition_rejects_earned_loss_bad_restoration_and_autoqueue(self):
        self.upgrade()
        self.world.execute(f"before_cap=storage.{KEY}.player;before_foreign=storage.{KEY}.foreign")
        # Copy plain snapshots, not the live world, to keep each opponent isolated.
        self.world.execute('''
          function copy_snapshot(value)
            if type(value)~="table"then return value end
            local result={}for k,v in pairs(value)do result[k]=copy_snapshot(v)end return result
          end
          function cap_snapshot()
            local result=copy_snapshot(before_cap)
            for name,value in pairs(result.technologies)do
              if name:sub(-2)=="-4"then value.enabled=false;value.visible=true end
            end
            result.technologies["recipe-prod-research_material_silicon-4"].saved_progress=.2
            result.current="mir-k2so-material-continuation-probe";result.queue={result.current};result.progress=0
            return result
          end
          function assert_cap(candidate)
            local ok,message=pcall(fixture_actor.assert_transition,candidate,before_cap,"finite","player",false,before_cap)
            return ok,tostring(message)
          end
        ''')
        ok,message=self.lua.eval("assert_cap(cap_snapshot())")
        self.assertTrue(ok,message)
        for mutation in (
            'candidate.technologies["recipe-prod-research_material_silicon-4"].level=4',
            'candidate.technologies["recipe-prod-research_material_silicon-4"].saved_progress=0',
            'candidate.bonuses["kr-glass"]=.06',
            'candidate.queue={"recipe-prod-research_material_silicon-4",candidate.current}',
            'candidate.technologies["recipe-prod-research_material_glass-4"].enabled=true',
        ):
            with self.subTest(mutation=mutation):
                self.world.execute("candidate=cap_snapshot();"+mutation)
                result=self.lua.eval("assert_cap(candidate)")
                self.assertFalse(result[0])

    def test_profile_and_wrapper_bindings_keep_one_explicit_dependency_closure(self):
        for index, role in enumerate(ROLES, 1):
            with self.subTest(role=role):
                profile = json.loads((ROOT / "tests" / "profiles" / f"k2so-material-continuation-{role}-f210-2124.json").read_text())
                self.assertEqual(profile["target"], "f210")
                self.assertEqual(profile["factorio_line"], "2.1")
                self.assertEqual(profile["engine"], {"version": "2.1.24", "sha256": ENGINE_SHA})
                self.assertEqual(profile["settings_mode"], "Defaults")
                expected = dict(DEPENDENCIES)
                expected["more-infinite-research"] = "5.0.21017" if role == "source" else "5.0.21018"
                expected["mir-fixture-k2so-material-continuation"] = f"0.{index}.0"
                rows = profile["mods"]
                self.assertEqual(len(rows), len(expected))
                self.assertEqual({row["name"]: row["version"] for row in rows}, expected)
                self.assertTrue(all(row["enabled"] is True for row in rows))
                self.assertEqual(profile["archive_sha256"], ARCHIVES)
                info = json.loads((FIXTURE / role / "info.json").read_text())
                self.assertEqual(info["name"], "mir-fixture-k2so-material-continuation")
                self.assertEqual(info["version"], f"0.{index}.0")
                self.assertEqual(info["dependencies"], [
                    "base = 2.1.24", "space-age = 2.1.24", "Krastorio2 = 2.1.4",
                    "Krastorio2-spaced-out = 2.0.19", "xy-k2so-enhancements-nulls-fork = 0.8.3",
                    "more-infinite-research = "+expected["more-infinite-research"],
                ])
                wrappers={"info.json","control.lua","data.lua","data-final-fixes.lua","settings-updates.lua"}
                self.assertEqual({path.name for path in (FIXTURE/role).iterdir()},wrappers)
                projection={path.name for path in (FIXTURE/role).iterdir()}
                for name in ("fixture_control.lua","fixture_data.lua"):
                    self.assertTrue((FIXTURE/name).is_file())
                    projection.add(name)
                self.assertEqual(projection,wrappers|{"fixture_control.lua","fixture_data.lua"})
                self.assertEqual(len(projection),7)
                for filename,module,method in (
                    ("control.lua","fixture_control","apply"),
                    ("data.lua","fixture_data","prototypes"),
                    ("data-final-fixes.lua","fixture_data","validate"),
                    ("settings-updates.lua","fixture_data","settings"),
                ):
                    expected_wrapper=f'require("__mir-fixture-k2so-material-continuation__/{module}").{method}("{role}")'
                    self.assertEqual((FIXTURE/role/filename).read_text().strip(),expected_wrapper)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    args, remaining = parser.parse_known_args()
    sys.path.insert(0, str(Path(args.lua_runtime_dir)))
    from lupa.lua52 import LuaRuntime
    K2SOMaterialContinuationFixtureTests.runtime_type = LuaRuntime
    unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)


if __name__ == "__main__":
    main()
