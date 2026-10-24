"""Host controls for the SCI-RESEARCH-01 representative fixture, not native evidence."""
import argparse
import json
from pathlib import Path
import sys
import unittest

from native_credit_oracle import verified_public_rows


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/foreign-research-preservation"
SOURCE = FIXTURE / "published-4.7"
DESTINATION = FIXTURE / "mir5"
UNRESOLVED = FIXTURE / "mir5-unresolved"
PROFILE = ROOT / "tests/profiles/foreign-research-preservation-f210.json"


class ForeignResearchPreservationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          function foreign_fixture_data(path)
            fixture_rows = nil
            data = {extend = function(_, rows) fixture_rows = rows end}
            local chunk, message = loadfile(path, "t", _G)
            assert(chunk, message)
            chunk()
            return fixture_rows
          end

          function run_foreign_research_transition(source_path, destination_path, opponent)
            local callbacks = {}
            local marker_count, source_saves, destination_saves = 0, 0, 0
            local force = {
              valid = true,
              index = 1,
              laboratory_speed_modifier = 0,
              recipes = {['iron-gear-wheel'] = {productivity_bonus = 0}},
              technologies = {}
            }
            function force.enable_all_prototypes() end
            setmetatable(force, {__newindex = function(self, key, value)
              if key == 'research_queue_enabled' then error('removed native API member') end
              if key == 'research_queue' then
                rawset(self, 'current_research', value[1])
              end
              rawset(self, key, value)
            end})

            local function prerequisite()
              return {research_recursive = function()
                -- An opponent for the real prerequisite's native bonus. The
                -- fixture must establish its baseline after all setup.
                force.laboratory_speed_modifier = force.laboratory_speed_modifier + .1
              end}
            end
            local function technology(name, level, max_level, finite, laboratory_speed, gear_bonus)
              local state = {
                name = name, level = level, researched = false, enabled = true,
                visible_when_disabled = false, saved_progress = 0,
                prototype = {max_level = max_level}, prerequisites = {prerequisite()}
              }
              return setmetatable({}, {
                __index = function(_, key) return state[key] end,
                __newindex = function(_, key, value)
                  if key == "researched" and value == true then
                    if finite then
                      state.researched = true
                    else
                      state.level = state.level + 1
                      state.researched = false
                    end
                    if laboratory_speed then
                      force.laboratory_speed_modifier = force.laboratory_speed_modifier + laboratory_speed
                    end
                    if gear_bonus then
                      force.recipes['iron-gear-wheel'].productivity_bonus =
                        force.recipes['iron-gear-wheel'].productivity_bonus + gear_bonus
                    end
                    return
                  end
                  state[key] = value
                end
              })
            end

            force.technologies['Space-Lab-Research-61'] =
              technology('Space-Lab-Research-61', 61, 61, true, .061, nil)
            force.technologies['Space-Lab-Research-62'] =
              technology('Space-Lab-Research-62', 62, 62, true, .062, nil)
            force.technologies['research-speed-7'] =
              technology('research-speed-7', 7, 4294967295, false, .6, nil)
            force.technologies['recipe-prod-research_gears-1'] =
              technology('recipe-prod-research_gears-1', 1, 4294967295, false, nil, .1)

            local storage = {}
            local game = {
              forces = {player = force},
              server_save = function(name)
                assert(name == 'mir5-native-complete', 'fixture must use existing native runner save')
                if storage.mir5_foreign_research_preservation.phase == 'seeded-4.7' then
                  source_saves = source_saves + 1
                else
                  destination_saves = destination_saves + 1
                end
              end
            }

            local function load_control(path, mir_version, fixture_version)
              local callbacks_for_load = {}
              local environment = {
                script = {
                  active_mods = {
                    base = '2.1.23', ['more-infinite-research'] = mir_version,
                    ['mir-fixture-mir5-foreign-research-preservation'] = fixture_version
                  },
                  on_init = function(callback) callbacks_for_load.on_init = callback end,
                  on_load = function(callback) callbacks_for_load.on_load = callback end,
                  on_configuration_changed = function(callback)
                    callbacks_for_load.on_configuration_changed = callback
                  end,
                  on_event = function(event, callback)
                    callbacks_for_load.on_event = {event = event, callback = callback}
                  end
                },
                defines = {events = {on_tick = 1}},
                storage = storage,
                game = game,
                helpers = {table_to_json = function() return '{}' end},
                log = function(message)
                  assert(message:match('^%[MIR5_NATIVE_FIXTURE%] RESULT '), 'unsupported native runner marker')
                  marker_count = marker_count + 1
                end
              }
              environment._G = environment
              setmetatable(environment, {__index = function(_, key) return _G[key] end})
              local chunk, message = loadfile(path, 't', environment)
              assert(chunk, message)
              assert(pcall(chunk))
              return callbacks_for_load
            end

            local source = load_control(source_path, '4.7.21000', '0.1.0')
            assert(type(source.on_init) == 'function' and type(source.on_event) == 'table')
            assert(pcall(source.on_init))
            assert(pcall(source.on_event.callback))
            assert(storage.mir5_foreign_research_preservation.phase == 'seeded-4.7')
            assert(pcall(source.on_load))
            assert(pcall(source.on_event.callback))

            if opponent == 'queue' then table.remove(force.research_queue, 2)
            elseif opponent == 'foreign-progress' then force.research_progress = .12
            elseif opponent == 'mir-progress' then force.technologies['recipe-prod-research_gears-1'].saved_progress = .13
            elseif opponent == 'foreign-effect' then force.laboratory_speed_modifier = force.laboratory_speed_modifier + .061
            elseif opponent == 'foreign-level' then force.technologies['Space-Lab-Research-61'].researched = false
            end

            local destination = load_control(destination_path, '5.0.21000', '0.2.0')
            assert(type(destination.on_configuration_changed) == 'function'
              and type(destination.on_load) == 'function' and type(destination.on_event) == 'table')
            assert(pcall(destination.on_configuration_changed))
            assert(pcall(destination.on_event.callback))
            assert(storage.mir5_foreign_research_preservation.phase == 'completed')
            local state = storage.mir5_foreign_research_preservation
            local completed_phase = state.phase
            assert(pcall(destination.on_load))
            assert(state.phase == completed_phase, 'on_load wrote fixture storage')
            assert(pcall(destination.on_event.callback))

            return {
              marker_count = marker_count,
              source_saves = source_saves,
              destination_saves = destination_saves,
              foreign_level = force.technologies['Space-Lab-Research-61'].level,
              foreign_researched = force.technologies['Space-Lab-Research-61'].researched,
              native_level = force.technologies['research-speed-7'].level,
              gear_level = force.technologies['recipe-prod-research_gears-1'].level,
              gear_bonus = force.recipes['iron-gear-wheel'].productivity_bonus,
              laboratory_speed_modifier = force.laboratory_speed_modifier,
              saved_lab_modifier = state.laboratory_speed_modifier,
              current_research = force.current_research.name,
              queue_count = #force.research_queue,
              foreign_progress = force.research_progress,
              mir_progress = force.technologies['recipe-prod-research_gears-1'].saved_progress,
              direct_setter = state.direct_native_setter_completion
            }
          end

          function reject_missing_foreign_seed(destination_path)
            local callbacks = {}
            local environment = {
              script = {
                active_mods = {base = '2.1.23', ['more-infinite-research'] = '5.0.21000'},
                on_configuration_changed = function(callback) callbacks.changed = callback end,
                on_load = function(callback) callbacks.loaded = callback end,
                on_event = function(_, callback) callbacks.tick = callback end
              },
              defines = {events = {on_tick = 1}}, storage = {},
              game = {forces = {player = {technologies = {}, recipes = {}}}},
              helpers = {table_to_json = function() return '{}' end}, log = function() end
            }
            environment._G = environment
            setmetatable(environment, {__index = function(_, key) return _G[key] end})
            local chunk, message = loadfile(destination_path, 't', environment)
            assert(chunk, message)
            assert(pcall(chunk))
            return pcall(callbacks.changed)
          end
        ''')

    def test_unresolved_startup_role_is_distinct_and_keeps_playable_roles_unchanged(self):
        info = json.loads((UNRESOLVED / 'info.json').read_text())
        destination = json.loads((DESTINATION / 'info.json').read_text())
        self.assertEqual(info['name'], destination['name'])
        self.assertEqual(info['dependencies'], destination['dependencies'])
        self.assertEqual(info['version'], '0.3.0')
        self.assertEqual((UNRESOLVED / 'data.lua').read_bytes(), (DESTINATION / 'data.lua').read_bytes())
        self.assertFalse((UNRESOLVED / 'data-updates.lua').exists())
        profile = json.loads((ROOT / 'tests/profiles/foreign-research-unresolved-f210-2123.json').read_text())
        self.assertEqual(profile['engine'], {'version': '2.1.23',
                         'sha256': 'FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060'})
        self.assertEqual(profile['mods'], [
            {'name': 'base', 'version': '2.1.23', 'enabled': True},
            {'name': 'more-infinite-research', 'version': '5.0.21000', 'enabled': True},
            {'name': info['name'], 'version': '0.3.0', 'enabled': True},
        ])
        self.assertEqual(set(profile['fixture']['included_members']),
                         {path.name for path in UNRESOLVED.iterdir() if path.is_file()})
        self.assertEqual(profile['consumer_markers'], ['MIR5_FOREIGN_UNRESOLVED'])

    def test_unresolved_data_preflight_rejects_drift_without_repairing_inputs(self):
        from test_generator import plain_lua
        self.lua.execute(r'''
          function unresolved_data_context(rows, path, opponent)
            local raw = {tool={},recipe={},technology={['recipe-prod-research_gears-1']={name='recipe-prod-research_gears-1'}}}
            for _, row in ipairs(rows) do raw[row.type][row.name] = row end
            local active = {base='2.1.23',['more-infinite-research']='5.0.21000',
              ['mir-fixture-mir5-foreign-research-preservation']='0.3.0'}
            local foreign = raw.technology['Space-Lab-Research-61']
            if opponent=='producer' then raw.recipe['mir5-foreign-astral-insight-pack']={name='producer'}
            elseif opponent=='science' then foreign.unit.ingredients[3][1]='automation-science-pack'
            elseif opponent=='effect' then foreign.effects[1].modifier=.1
            elseif opponent=='cost' then foreign.unit.count=1
            elseif opponent=='missing-gear' then raw.technology['recipe-prod-research_gears-1']=nil
            elseif opponent=='version' then active['more-infinite-research']='5.0.20000' end
            local env={mods=active,data={raw=raw,extend=function()error('unexpected data write')end}}
            env._G=env;setmetatable(env,{__index=_G})
            return {raw=raw,run=function()return pcall(assert(loadfile(path,'t',env)))end}
          end
        ''')
        for opponent in ('', 'producer', 'science', 'effect', 'cost', 'missing-gear', 'version'):
            rows = self.lua.eval('foreign_fixture_data')((UNRESOLVED / 'data.lua').as_posix())
            context = self.lua.eval('unresolved_data_context')(
                rows, (UNRESOLVED / 'data-final-fixes.lua').as_posix(), opponent)
            before = plain_lua(context['raw'])
            returned = context['run']()
            ok = returned[0] if isinstance(returned, tuple) else returned
            self.assertEqual(ok, not opponent, opponent)
            self.assertEqual(before, plain_lua(context['raw']), opponent)

    def test_unresolved_init_witness_is_read_only_and_rejects_foreign_or_mir_drift(self):
        self.lua.execute(r'''
          function unresolved_runtime(path, opponent)
            local function readonly(value)
              return setmetatable({}, {__index=value,__newindex=function()error('unexpected native write')end})
            end
            local technologies = {}
            for _, level in ipairs({61,62}) do
              local modifier = level/1000
              if level==61 and opponent=='rounding' then modifier=.061000000685453 end
              if level==61 and opponent=='effect' then modifier=.062 end
              local prototype=readonly({max_level=level,effects={readonly({type='laboratory-speed',modifier=modifier})}})
              technologies['Space-Lab-Research-'..level]=readonly({valid=true,name='Space-Lab-Research-'..level,
                level=(level==61 and opponent=='level')and 60 or level,
                researched=opponent=='researched',enabled=opponent~='disabled',prototype=prototype})
            end
            technologies['recipe-prod-research_gears-1']=readonly({valid=true,level=1,researched=false})
            if opponent=='missing-gear' then technologies['recipe-prod-research_gears-1']=nil end
            local recipes={['iron-gear-wheel']=readonly({productivity_bonus=opponent=='gear-bonus'and .1 or 0})}
            if opponent=='producer' then recipes['mir5-foreign-astral-insight-pack']=readonly({valid=true})end
            local force=readonly({valid=true,technologies=readonly(technologies),recipes=readonly(recipes),
              laboratory_speed_modifier=opponent=='lab-bonus'and .061 or 0})
            local active={base='2.1.23',['more-infinite-research']=opponent=='version'and'5.0.20000'or'5.0.21000',
              ['mir-fixture-mir5-foreign-research-preservation']='0.3.0'}
            local init,payload,logs
            logs=0
            local env={script={active_mods=active,on_init=function(callback)assert(init==nil);init=callback end},
              game=setmetatable({},{__index=function()error('parse read game')end}),
              storage=setmetatable({},{__index=function()error('read storage')end,__newindex=function()error('write storage')end}),
              helpers={table_to_json=function(value)payload=value;return '{}'end},
              log=function(value)assert(value=='[MIR5_FOREIGN_UNRESOLVED] RESULT {}');logs=logs+1 end}
            env._G=env;setmetatable(env,{__index=_G})
            local parsed,message=pcall(assert(loadfile(path,'t',env)))
            if not parsed then return {ok=false,message=tostring(message),parsed=false}end
            assert(type(init)=='function');env.game=readonly({forces=readonly({player=force})})
            local ok,reason=pcall(init)
            return {ok=ok,message=tostring(reason),parsed=true,logs=logs,payload=payload}
          end
        ''')
        for opponent in ('', 'rounding', 'effect', 'level', 'researched', 'disabled',
                         'producer', 'missing-gear', 'gear-bonus', 'lab-bonus', 'version'):
            result = self.lua.eval('unresolved_runtime')((UNRESOLVED / 'control.lua').as_posix(), opponent)
            self.assertTrue(result['parsed'], result['message'])
            self.assertEqual(result['ok'], opponent in ('', 'rounding'), result['message'])
            self.assertEqual(result['logs'], 1 if result['ok'] else 0)
            if result['ok']:
                self.assertEqual(result['payload']['case'], 'SCI-RESEARCH-01-unresolved')
                self.assertEqual(result['payload']['qualification'], 'representative-unresolved-source-startup-only')
                self.assertTrue(result['payload']['named_pack_recipe_absent'])

    def test_versioned_fixture_identity_and_destination_profile_are_pinned(self):
        source = json.loads((SOURCE / "info.json").read_text(encoding="utf-8"))
        destination = json.loads((DESTINATION / "info.json").read_text(encoding="utf-8"))
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(source["name"], destination["name"])
        self.assertEqual(source["version"], "0.1.0")
        self.assertEqual(destination["version"], "0.2.0")
        self.assertEqual(source["dependencies"], ["base = 2.1.23", "more-infinite-research = 4.7.21000"])
        self.assertEqual(destination["dependencies"], ["base = 2.1.23", "more-infinite-research = 5.0.21000"])
        self.assertEqual(profile["mods"], [
            {"name": "base", "version": "2.1.23", "enabled": True},
            {"name": "more-infinite-research", "version": "5.0.21000", "enabled": True},
            {"name": source["name"], "version": "0.2.0", "enabled": True},
        ])

    def test_both_data_variants_define_the_same_finite_foreign_effect_and_flow(self):
        rows_by_version = []
        for directory in (SOURCE, DESTINATION):
            self.lua.globals().fixture_data_path = (directory / "data.lua").as_posix()
            rows = self.lua.eval("foreign_fixture_data(fixture_data_path)")
            science, prerequisite, research = rows[1], rows[2], rows[3]
            self.assertEqual(science["type"], "tool")
            self.assertEqual(science["name"], "mir5-foreign-astral-insight-pack")
            self.assertEqual(science["durability"], 1)
            self.assertEqual(prerequisite["name"], "mir5-foreign-astral-theory-17")
            self.assertEqual(prerequisite["prerequisites"][1], "chemical-science-pack")
            self.assertEqual(prerequisite["unit"]["ingredients"][3][1], science["name"])
            self.assertEqual(research["name"], "Space-Lab-Research-61")
            self.assertIsNone(research["level"])
            self.assertEqual(research["max_level"], 61)
            self.assertTrue(research["upgrade"])
            self.assertEqual(research["prerequisites"][1], prerequisite["name"])
            self.assertEqual(research["unit"]["count"], 61)
            self.assertEqual(research["unit"]["time"], 61)
            self.assertEqual(research["unit"]["ingredients"][3][1], science["name"])
            self.assertEqual(research["effects"][1]["type"], "laboratory-speed")
            self.assertAlmostEqual(research["effects"][1]["modifier"], 0.061)
            pending = rows[4]
            self.assertEqual(pending["name"], "Space-Lab-Research-62")
            self.assertEqual(pending["prerequisites"][1], research["name"])
            self.assertEqual(pending["max_level"], 62)
            self.assertAlmostEqual(pending["effects"][1]["modifier"], 0.062)
            rows_by_version.append((science["name"], prerequisite["name"], research["effects"][1]["modifier"]))
        self.assertEqual(rows_by_version[0], rows_by_version[1])

    def test_representative_pack_has_a_producer_and_a_single_accepting_lab(self):
        source = SOURCE / "data-updates.lua"
        self.assertEqual(source.read_bytes(), (DESTINATION / "data-updates.lua").read_bytes())
        self.lua.globals().source_updates_path = source.as_posix()
        self.lua.execute('''
          local pack = "mir5-foreign-astral-insight-pack"
          local produced
          data = {raw={lab={lab={inputs={"automation-science-pack","chemical-science-pack","utility-science-pack"}}}},
            extend=function(_, rows) assert(#rows == 1); produced=rows[1] end}
          assert(dofile(source_updates_path) == nil)
          assert(produced.type == "recipe" and produced.name == pack and produced.enabled == true)
          assert(produced.ingredients[1].name == "iron-plate" and produced.ingredients[1].amount == 1)
          assert(produced.results[1].type == "item" and produced.results[1].name == pack
            and produced.results[1].amount == 1)
          assert(#data.raw.lab.lab.inputs == 4 and data.raw.lab.lab.inputs[4] == pack)
        ''')

    def test_source_configuration_transition_and_reload_preserve_foreign_and_mir_effects(self):
        self.lua.globals().source_control_path = (SOURCE / "control.lua").as_posix()
        self.lua.globals().destination_control_path = (DESTINATION / "control.lua").as_posix()
        result = self.lua.eval(
            "run_foreign_research_transition(source_control_path, destination_control_path)"
        )
        self.assertEqual(result["source_saves"], 1)
        self.assertEqual(result["destination_saves"], 1)
        self.assertEqual(result["marker_count"], 4)
        self.assertEqual(result["foreign_level"], 61)
        self.assertTrue(result["foreign_researched"])
        self.assertEqual(result["native_level"], 8)
        self.assertEqual(result["gear_level"], 3)
        self.assertAlmostEqual(result["gear_bonus"], 0.2)
        self.assertAlmostEqual(result["laboratory_speed_modifier"], 0.961)
        self.assertAlmostEqual(result["saved_lab_modifier"], 0.961)
        self.assertEqual(result["direct_setter"], "foreign-finite-61,native-lab-speed,mir-gear-levels")
        self.assertEqual(result["current_research"], "Space-Lab-Research-62")
        self.assertEqual(result["queue_count"], 2)
        self.assertAlmostEqual(result["foreign_progress"], 0.42)
        self.assertAlmostEqual(result["mir_progress"], 0.27)

    def test_transition_rejects_lost_investment_queue_earned_state_or_duplicate_effect(self):
        self.lua.globals().source_control_path = (SOURCE / "control.lua").as_posix()
        self.lua.globals().destination_control_path = (DESTINATION / "control.lua").as_posix()
        for opponent in ("queue", "foreign-progress", "mir-progress", "foreign-effect", "foreign-level"):
            with self.subTest(opponent=opponent):
                self.lua.globals().opponent = opponent
                passed, message = self.lua.eval(
                    "pcall(run_foreign_research_transition, source_control_path, destination_control_path, opponent)"
                )
                self.assertFalse(passed)
                expected = "duplicated or removed" if opponent == "foreign-effect" else "changed"
                self.assertIn(expected, str(message))

    def test_destination_rejects_a_created_world_without_the_published_seed(self):
        self.lua.globals().destination_control_path = (DESTINATION / "control.lua").as_posix()
        passed, message = self.lua.eval("reject_missing_foreign_seed(destination_control_path)")
        self.assertFalse(passed)
        self.assertIn("published 4.7 representative seed witness is absent", str(message))

    def test_real_mir5_publication_never_certifies_or_changes_unrelated_foreign_research(self):
        # Reuse the explicit authored-reference world fixture, while exercising
        # the actual data-final entrypoint and default values, not a stubbed
        # research publisher. Full output equality has its separate oracle.
        import test_generator
        test_generator.LuaRuntime = LuaRuntime
        host = test_generator.GeneratorTests("runTest")
        host.setUp()
        host.lua.execute('''
          local environment = full_world({})
          local foreign_effect = {type="laboratory-speed",modifier=.061}
          local foreign = {type="technology",name="Space-Lab-Research-61",max_level=61,
            prerequisites={"foreign-unfamiliar-frontier"},effects={foreign_effect},
            unit={count=61,time=61,ingredients={{"foreign-unfamiliar-science",1}}}}
          environment.raw.technology[foreign.name] = foreign
          setmetatable(environment.raw.technology, {__pairs=function()
            error("MIR5 enumerated unrelated foreign research")
          end})
          local original_effects, original_unit = foreign.effects,foreign.unit
          settings,mods,data,helpers,log={startup=defaults()},{},environment,nil,function() end
          assert(dofile(data_final_path) == nil and environment.writes == 1 and #environment.emitted == 73)
          foreign_output, foreign_recipes = environment.emitted, environment.raw.recipe
          assert(environment.raw.technology[foreign.name] == foreign)
          assert(foreign.effects == original_effects and foreign.effects[1] == foreign_effect
            and foreign_effect.modifier == .061 and foreign.unit == original_unit)
          assert(foreign.max_level == 61 and foreign.prerequisites[1] == "foreign-unfamiliar-frontier")
        ''')
        actual = {
            row["name"]: test_generator.plain_lua(row)
            for row in host.lua.globals().foreign_output.values()
        }
        public = verified_public_rows(
            actual,
            {str(name) for name in host.lua.globals().foreign_recipes.keys()},
        )
        self.assertEqual(len(public), 53)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ForeignResearchPreservationTests))
    sys.exit(0 if result.wasSuccessful() else 1)
