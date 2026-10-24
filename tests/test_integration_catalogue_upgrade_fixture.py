import argparse
import copy
import json
import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/integration-catalogue-upgrade"
FOREIGN_OWNER = ROOT / "tests/fixtures/integration-foreign-owner"
RECOVERED = ROOT / "tests/fixtures/armor-py-f200-472-recovered-facts.json"
BASE_ORACLE = ROOT / "spec/inventory/modern-f200-470.json"
CONTINUATIONS = ROOT / "tests/fixtures/native-modded-continuations-f200-captured-facts.json"
PY_PUBLISHED_RESET = ROOT / "spec/evidence/py-published-reset-control-native-chain.json"
F200_RUNTIME_API_CANDIDATES = (
    os.environ.get("MIR_F200_RUNTIME_API"),
    "D:/Games/Factorio/2.0/doc-html/runtime-api.json",
    "D:/Programs/Factorio/2.0/doc-html/runtime-api.json",
)


def f200_runtime_api_path():
    for candidate in F200_RUNTIME_API_CANDIDATES:
        if candidate:
            path = Path(candidate)
            if path.is_file():
                return path
    return None


def py(value):
    if hasattr(value, "keys"):
        keys = list(value.keys())
        if keys and all(isinstance(key, int) for key in keys):
            return [py(value[key]) for key in range(1, max(keys) + 1)]
        return {key: py(value[key]) for key in keys}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        out = runtime.table()
        for key, item in value.items():
            out[key] = lua(runtime, item)
        return out
    if isinstance(value, list):
        out = runtime.table()
        for index, item in enumerate(value, 1):
            out[index] = lua(runtime, item)
        return out
    return value


def merge_row(base, patch):
    value = copy.deepcopy(base)
    for key, item in patch.items():
        if isinstance(item, dict) and isinstance(value.get(key), dict):
            value[key] = merge_row(value[key], item)
        else:
            value[key] = copy.deepcopy(item)
    return value


class IntegrationCatalogueUpgradeFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.recovered = {row["id"]: row for row in json.loads(RECOVERED.read_text(encoding="utf-8"))["profiles"]}
        cls.base = next(row for row in json.loads(BASE_ORACLE.read_text(encoding="utf-8"))["profiles"] if row["id"] == "base-f200")
        cls.continuations = json.loads(CONTINUATIONS.read_text(encoding="utf-8"))
        cls.py_published_reset = json.loads(PY_PUBLISHED_RESET.read_text(encoding="utf-8"))

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("function load_plan(path) return assert(loadfile(path))() end")
        self.plan = py(self.lua.eval("load_plan")((FIXTURE / "catalogue.lua").as_posix()))

    def _expected_public(self, identifier):
        base = {row["name"] for row in self.base["technology_owner_progression_facts"]}
        base -= {
            "recipe-prod-research_oil_cracking_productivity-1",
            "recipe-prod-research_oil_processing_productivity-1",
        } if identifier.startswith("py-") else set()
        extras = {
            "armor-bobwarfare": {"recipe-prod-research_armor_components-1"},
            "py-coal": {"recipe-prod-research_material_py_log-1", "recipe-prod-research_material_py_log-4"},
            "py-alienlife-hightech": {
                "recipe-prod-research_breeding-1", "recipe-prod-research_supercapacitor-1",
                "recipe-prod-research_superconductor-1",
            },
        }[identifier]
        return base | extras

    def _expected_preflight(self, identifier):
        recovered = self.recovered[identifier]
        rows = {}
        for values in recovered["named_rows"].values():
            for row in values:
                rows[row["name"]] = row
        common = self.continuations["common_published_rows"]["laser-shooting-speed-8"]
        profile = next(row for row in self.continuations["profiles"] if row["id"] == identifier)
        patch = profile["published_field_changes"].get("laser-shooting-speed-8", {})
        rows["laser-shooting-speed-8"] = merge_row(common, patch)
        return rows

    def _run_data(self, stage, raw, mods):
        self.lua.globals().stage_path = (FIXTURE / stage / "data-final-fixes.lua").as_posix()
        self.lua.globals().common_path = (FIXTURE / "data-final-common.lua").as_posix()
        self.lua.globals().catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        self.lua.execute(r'''
          function run_integration_data(raw, mods)
            local env = {data={raw=raw}, mods=mods}
            env.require = function(name)
              if name == "__mir-fixture-mir5-integration-catalogue-upgrade__/catalogue" then
                return assert(loadfile(catalogue_path, "t", env))()
              end
              if name == "__mir-fixture-mir5-integration-catalogue-upgrade__/data-final-common" then
                return assert(loadfile(common_path, "t", env))()
              end
              error("unexpected fixture require: " .. tostring(name))
            end
            env._G = env
            setmetatable(env, {__index=function(_, key) return _G[key] end})
            local ok, message = pcall(function() assert(loadfile(stage_path, "t", env))() end)
            return {ok=ok, message=tostring(message), raw=raw}
          end
        ''')
        return self.lua.eval("run_integration_data")(lua(self.lua, raw), lua(self.lua, mods))

    def test_compact_public_rows_are_exactly_recovered_not_candidate_derived(self):
        expected_counts = {"armor-bobwarfare": 55, "py-coal": 54, "py-alienlife-hightech": 55}
        for identifier, expected_count in expected_counts.items():
            with self.subTest(profile=identifier):
                profile = self.plan["profiles"][identifier]
                self.assertEqual(self._expected_public(identifier), set(profile["public"]))
                self.assertEqual(expected_count, len(profile["public"]))
                self.assertEqual("laser-shooting-speed-8", profile["continuation"])
                self.assertIn(profile["primary"], profile["public"])
                self.assertIn(profile["continuation"], profile["public"])

    def test_preflight_rows_match_independent_published_facts(self):
        for identifier in self.plan["profiles"]:
            with self.subTest(profile=identifier):
                expected = self._expected_preflight(identifier)
                profile = self.plan["profiles"][identifier]
                self.assertEqual(set(expected), set(profile["preflight_names"]))
                self.assertEqual(expected, profile["preflight"])

    def test_finite_py_log_is_explicitly_early_three_then_tail_four(self):
        coal = self.plan["profiles"]["py-coal"]
        self.assertEqual({
            "early": "recipe-prod-research_material_py_log-1", "tail": "recipe-prod-research_material_py_log-4",
            "early_level": 3, "tail_level": 5,
        }, coal["finite"])
        self.assertEqual(3, coal["preflight"][coal["finite"]["early"]]["max_level"])
        self.assertEqual(50_000_000, coal["preflight"][coal["finite"]["tail"]]["max_level"])
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn("value.level, value.researched = finite.early_level, true", control)
        self.assertIn("value.level, value.researched = finite.tail_level, false", control)
        self.assertNotIn("finite.tail_level, true", control)

    def test_published_py_successor_exceptions_are_bound_to_the_independent_published_control(self):
        evidence = self.py_published_reset
        self.assertEqual("published-only-configuration-boundary-observation-completed", evidence["status"])
        self.assertFalse(evidence["release_qualification"])
        accepted = evidence["accepted_observation"]
        self.assertEqual(40091620986, accepted["run"])
        self.assertEqual({"tag": "v4.7.2", "archive": "more-infinite-research_4.7.20002.zip"},
                         {key: accepted["published_mir4"][key] for key in ("tag", "archive")})
        expected = {
            "py-coal": ("recipe-prod-research_material_py_log-4", 54),
            "py-alienlife-hightech": ("recipe-prod-research_breeding-1", 55),
        }
        profiles = {row["id"]: row for row in accepted["profiles"]}
        self.assertEqual(set(expected), set(profiles))
        for identifier, (primary, rows) in expected.items():
            with self.subTest(profile=identifier):
                row = profiles[identifier]
                self.assertEqual({
                    "primary": primary, "force": 5,
                    "correlated_actor_migration": {
                        "actor": "mir5-integration-foreign-owner", "force": 5,
                        "technology": primary,
                        "expected_disabled": True, "observed_before": False, "observed_after": False,
                    },
                    "observed_configuration_boundary": {
                        "source_primary_enabled": False, "post_configuration_primary_enabled": True,
                        "primary_visible_when_disabled": False, "checked_technology_rows": rows,
                    },
                }, {key: row[key] for key in ("primary", "force", "correlated_actor_migration",
                                               "observed_configuration_boundary")})

    def test_data_preflight_accelerates_only_the_two_real_lab_rows(self):
        for identifier, profile in self.plan["profiles"].items():
            raw = {"technology": copy.deepcopy(profile["preflight"]), "untouched": {"flag": 19}}
            for stage, mir, fixture in (("published-4.7", "4.7.20002", "0.1.0"), ("mir5", "5.0.20000", "0.2.0")):
                mods = {"base": "2.0.77", "more-infinite-research": mir,
                        "mir-fixture-mir5-integration-catalogue-upgrade": fixture}
                mods.update(profile["requires"])
                with self.subTest(profile=identifier, stage=stage):
                    result = self._run_data(stage, copy.deepcopy(raw), mods)
                    self.assertTrue(result["ok"], result["message"])
                    actual = py(result["raw"])
                    for name in profile["preflight_names"]:
                        unit = actual["technology"][name]["unit"]
                        if name in (profile["primary"], profile["continuation"]):
                            self.assertEqual((None, "1", 1), (unit.get("count"), unit["count_formula"], unit["time"]))
                        else:
                            expected = profile["preflight"][name]["unit"]
                            self.assertEqual(expected, unit)
                    self.assertEqual(19, actual["untouched"]["flag"])

    def test_data_preflight_rejects_named_effect_or_profile_drift_before_mutation(self):
        for identifier, profile in self.plan["profiles"].items():
            raw = {"technology": copy.deepcopy(profile["preflight"])}
            bad_effect = copy.deepcopy(raw)
            bad_effect["technology"][profile["primary"]]["effects"][0]["change"] = 0.03
            mods = {"base": "2.0.77", "more-infinite-research": "4.7.20002",
                    "mir-fixture-mir5-integration-catalogue-upgrade": "0.1.0"}
            mods.update(profile["requires"])
            with self.subTest(profile=identifier, opponent="effect"):
                result = self._run_data("published-4.7", bad_effect, mods)
                self.assertFalse(result["ok"])
                self.assertIn("published row differs before acceleration", result["message"])
                self.assertEqual(profile["preflight"][profile["primary"]]["unit"], py(result["raw"])["technology"][profile["primary"]]["unit"])
            with self.subTest(profile=identifier, opponent="closure"):
                missing = dict(mods)
                missing.pop(next(iter(profile["requires"])))
                result = self._run_data("published-4.7", copy.deepcopy(raw), missing)
                self.assertFalse(result["ok"])
                self.assertRegex(result["message"], r"(profile closure differs|no admitted integration profile)")

    def test_control_registers_without_game_or_storage_access_and_keeps_native_boundaries(self):
        self.lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        self.lua.execute(r'''
          function parse_integration_control(source)
            local callbacks, forbidden = {events={}}, {}
            local active = {base="2.0.77", ["more-infinite-research"]=source and "4.7.20002" or "5.0.20000",
              ["mir-fixture-mir5-integration-catalogue-upgrade"]=source and "0.1.0" or "0.2.0",
              boblibrary="2.1.0", bobwarfare="2.1.0"}
            local env = {
              require=function(name)
                assert(name == "__mir-fixture-mir5-integration-catalogue-upgrade__/catalogue")
                return assert(loadfile(catalogue_path, "t", _G))()
              end,
              script={active_mods=active, on_init=function(fn) callbacks.init=fn end,
                on_load=function(fn) callbacks.load=fn end, on_configuration_changed=function(fn) callbacks.configuration=fn end,
                on_event=function(event, fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}},
            }
            env._G=env
            setmetatable(env,{__index=function(_, key)
              if key == "game" or key == "storage" then forbidden[key]=true; return nil end
              return _G[key]
            end})
            local ok,message=pcall(function() assert(loadfile(control_path, "t", env))() end)
            return {ok=ok,message=tostring(message),callbacks=callbacks,forbidden=forbidden}
          end
        ''')
        for source in (True, False):
            with self.subTest(source=source):
                result = self.lua.eval("parse_integration_control")(source)
                self.assertTrue(result["ok"], result["message"])
                self.assertIsNone(result["forbidden"]["game"])
                self.assertIsNone(result["forbidden"]["storage"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])
                self.assertIsNotNone(result["callbacks"]["init"] if source else result["callbacks"]["configuration"])

    def _run_published_py_successor_config(self, identifier, opponent=None):
        self.lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        self.lua.execute(r'''
          function run_published_py_successor_config(identifier, opponent)
            local callbacks, logs = {}, {}
            local function make_force(plan, force_fields, primary_enabled, other_enabled)
              local values, writes = {}, {}
              local force = {valid=true, technologies={}, recipes={}, research_queue={}, research_progress=0,
                current_research=nil, _values=values, _writes=writes,
                get_gun_speed_modifier=function() error("unexpected gun lookup") end}
              for _, name in ipairs(plan.public) do
                local maximum = 4294967295
                if plan.finite ~= nil and name == plan.finite.early then maximum = plan.finite.early_level
                elseif plan.finite ~= nil and name == plan.finite.tail then maximum = 50000000 end
                local value = {valid=true, name=name, level=1, researched=false, enabled=true,
                  visible_when_disabled=false, saved_progress=0, prototype={max_level=maximum,effects={}},
                  research_unit_ingredients={}}
                if name == plan.primary then value.enabled = primary_enabled end
                if name == plan.continuation and other_enabled ~= nil then value.enabled = other_enabled end
                values[name] = value
                force.technologies[name] = setmetatable({}, {
                  __index=value,
                  __newindex=function(_, key, next)
                    if name == plan.primary then writes[#writes + 1] = {key=key, value=next} end
                    value[key] = next
                  end,
                })
              end
              for _, field in ipairs(force_fields) do force[field] = 0 end
              return force
            end
            local function snapshot(force, plan, force_fields)
              local out = {technologies={}, effects={}, recipes={}, guns={}, fields={}}
              for _, name in ipairs(plan.public) do
                local value = force._values[name]
                out.technologies[name] = {level=value.level, researched=value.researched, enabled=value.enabled,
                  visible=value.visible_when_disabled, saved=value.saved_progress, maximum=value.prototype.max_level}
                out.effects[name] = "{}"
              end
              for _, field in ipairs(force_fields) do out.fields[field] = force[field] end
              return out
            end
            local env, plan, force_fields
            local profile_mods = {
              ["py-coal"] = {pycoalprocessing="3.0.44"},
              ["py-alienlife-hightech"] = {
                pycoalprocessing="3.0.44", pyalienlife="3.0.67", pyhightech="3.0.19",
              },
            }
            assert(profile_mods[identifier] ~= nil)
            local active = {base="2.0.77", ["more-infinite-research"]="5.0.20000",
              ["mir-fixture-mir5-integration-catalogue-upgrade"]="0.2.0"}
            for name, version in pairs(profile_mods[identifier]) do active[name] = version end
            env = {
              require=function(name)
                assert(name == "__mir-fixture-mir5-integration-catalogue-upgrade__/catalogue")
                return assert(loadfile(catalogue_path, "t", env))()
              end,
              script={active_mods=active,
                on_init=function(fn) callbacks.init=fn end, on_load=function(fn) callbacks.load=fn end,
                on_configuration_changed=function(fn) callbacks.configuration=fn end,
                on_event=function(event, fn) callbacks[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}},
              helpers={table_to_json=function(value) payload=value; return "<fixture-payload>" end},
              log=function(value) logs[#logs + 1] = value end,
            }
            env._G=env
            setmetatable(env, {__index=function(_, key) return _G[key] end})
            local catalogue = assert(loadfile(catalogue_path, "t", env))()
            plan, force_fields = catalogue.profiles[identifier], catalogue.force_fields
            local player, paused = make_force(plan, force_fields, true), make_force(plan, force_fields, true)
            local foreign = make_force(plan, force_fields, opponent ~= "restored-disabled", true)
            local foreign_snapshot = snapshot(foreign, plan, force_fields)
            foreign_snapshot.technologies[plan.primary].enabled = opponent == "source-enabled"
            if opponent == "wrong-visibility" then foreign._values[plan.primary].visible_when_disabled = true end
            if opponent == "primary-level" then foreign._values[plan.primary].level = 2 end
            if opponent == "other-enabled" then foreign._values[plan.continuation].enabled = false end
            local foreign_index = opponent == "wrong-force" and 6 or 5
            local inventory = {clear=function() end, insert=function() return 128 end}
            local state = {phase="source-complete", profile=identifier, paused_index=4, foreign_index=foreign_index,
              source_snapshot=snapshot(player, plan, force_fields), paused_snapshot=snapshot(paused, plan, force_fields),
              foreign_snapshot=foreign_snapshot, player_queue={current=false, queue={}, progress=0},
              lab={valid=true, active=false, energy=0, get_inventory=function(kind) assert(kind == 1); return inventory end}}
            env.storage=setmetatable({}, {
              __index=function(_, key)
                if key == "mir5_integration_catalogue_upgrade" then return state end
                error("read outside fixture private storage: " .. tostring(key))
              end,
              __newindex=function() error("unexpected fixture storage write") end,
            })
            env.game={tick=0,forces={player=player,[4]=paused,[foreign_index]=foreign}}
            local ok, message = pcall(function()
              assert(loadfile(control_path, "t", env))()
              callbacks.configuration()
            end)
            return {ok=ok, message=tostring(message), logs=logs, payload=payload, phase=state.phase,
              source_enabled=state.foreign_snapshot.technologies[plan.primary].enabled,
              foreign_enabled=foreign._values[plan.primary].enabled, foreign_writes=foreign._writes}
          end
        ''')
        return py(self.lua.eval("run_published_py_successor_config")(identifier, opponent))

    def test_published_py_successors_accept_only_the_published_enabled_boundary_and_request_actor_log_correlation(self):
        boundaries = {
            "py-coal": ("recipe-prod-research_material_py_log-4", 54, "[MIR5_INTEGRATION_PYCOAL_FOREIGN]"),
            "py-alienlife-hightech": ("recipe-prod-research_breeding-1", 55, "[MIR5_INTEGRATION_PYALIEN_FOREIGN]"),
        }
        for identifier, (primary, rows, marker) in boundaries.items():
            with self.subTest(profile=identifier):
                actor = self._run_foreign_owner_migration(
                    {"force_index": 5, "technology": primary, "disabled": True},
                    technology_name=primary, force_index=5, enabled=False,
                )
                self.assertTrue(actor["ok"], actor["message"])
                self.assertEqual("[MIR5_FOREIGN_OWNER_MIGRATION] <fixture-payload>", actor["marker"])
                self.assertEqual({
                    "actor": "mir5-integration-foreign-owner", "force": 5,
                    "technology": primary, "expected_disabled": True,
                    "observed_before": False, "observed_after": False,
                }, py(actor["payload"]))
                result = self._run_published_py_successor_config(identifier)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual("await-successor-labs", result["phase"])
                self.assertFalse(result["source_enabled"])
                self.assertTrue(result["foreign_enabled"])
                self.assertFalse(result["foreign_writes"])
                self.assertEqual([marker + " CONFIGURATION <fixture-payload>"], result["logs"])
                self.assertEqual({
                    "actor": "mir5-integration-foreign-owner", "actor_migration_log_required": True,
                    "force": 5, "technology": primary,
                    "expected_disabled": True, "source_enabled": False, "post_configuration_enabled": True,
                    "visibility": False, "checked_technology_rows": rows,
                }, result["payload"])

    def test_published_py_successors_reject_restoration_and_any_other_boundary_drift_before_state_changes(self):
        opponents = {
            "restored-disabled": "pre-successor foreign technology state changed",
            "wrong-force": "published Py foreign successor boundary differs",
            "source-enabled": "published Py disabled primary witness differs",
            "wrong-visibility": "pre-successor foreign technology state changed",
            "primary-level": "pre-successor foreign technology state changed",
            "other-enabled": "pre-successor foreign technology state changed",
        }
        for identifier in ("py-coal", "py-alienlife-hightech"):
            for opponent, expected in opponents.items():
                with self.subTest(profile=identifier, opponent=opponent):
                    result = self._run_published_py_successor_config(identifier, opponent)
                    self.assertFalse(result["ok"])
                    self.assertIn(expected, result["message"])
                    self.assertEqual("source-complete", result["phase"])
                    self.assertFalse(result["foreign_writes"])
                    self.assertFalse(result["logs"])

    def _run_read_only_integration_migration(self, profile, expected, actual):
        migration = FIXTURE / "migrations/0.2.0.lua"
        self.lua.globals().migration_path = migration.as_posix()
        self.lua.execute(r'''
          function run_read_only_integration_migration(profile, expected, actual)
            local function immutable(value)
              if type(value) ~= "table" then return value end
              local values = {}
              for key, item in pairs(value) do values[key] = immutable(item) end
              return setmetatable({}, {
                __index=values,
                __newindex=function(_, key) error("unexpected fixture write: " .. tostring(key)) end,
                __pairs=function() return pairs(values) end,
                __len=function() return #values end,
              })
            end
            local marker, payload
            local game
            if actual == nil then
              game=setmetatable({}, {
                __index=function(_, key) error("unexpected nonarmor force lookup: " .. tostring(key)) end,
                __newindex=function(_, key) error("unexpected nonarmor write: " .. tostring(key)) end,
              })
            else
              local primary = immutable({
                valid=true,
                level=actual.level,
                researched=actual.researched,
                enabled=actual.enabled,
                visible_when_disabled=actual.visible,
                saved_progress=actual.saved,
                prototype={max_level=actual.maximum},
              })
              local foreign = immutable({valid=true, technologies={
                ["recipe-prod-research_armor_components-1"]=primary,
              }})
              game=immutable({forces={[71]=foreign}})
            end
            local state = {foreign_index=71, profile=profile}
            if expected ~= nil then state.foreign_snapshot={technologies={
              ["recipe-prod-research_armor_components-1"]=expected,
            }} end
            local env = {
              storage=immutable({mir5_integration_catalogue_upgrade=state}),
              game=game,
              helpers={table_to_json=function(value) payload=value; return "<fixture-payload>" end},
              log=function(value) marker=value end,
            }
            env._G=env
            setmetatable(env, {__index=function(_, key) return _G[key] end,
              __newindex=function(_, key) error("unexpected global write: " .. tostring(key)) end})
            local ok, message=pcall(function() assert(loadfile(migration_path, "t", env))() end)
            return {ok=ok, message=tostring(message), marker=marker, payload=payload}
          end
        ''')
        return self.lua.eval("run_read_only_integration_migration")(
            profile,
            lua(self.lua, expected) if expected is not None else None,
            lua(self.lua, actual) if actual is not None else None,
        )

    def test_successor_migration_observes_foreign_snapshot_before_callbacks_without_writes(self):
        expected = {
            "level": 2, "researched": False, "enabled": False, "visible": False,
            "saved": 0.0, "maximum": 4_294_967_295,
        }
        actual = dict(expected, enabled=True)
        result = self._run_read_only_integration_migration("armor-bobwarfare", expected, actual)
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual("[MIR5_INTEGRATION_PRECONFIG_FOREIGN] <fixture-payload>", result["marker"])
        payload = py(result["payload"])
        self.assertEqual("0.2.0", payload["fixture_migration"])
        self.assertEqual("recipe-prod-research_armor_components-1", payload["technology"])
        self.assertEqual(71, payload["force"])
        self.assertEqual(expected, payload["expected"])
        self.assertEqual(actual, payload["actual"])
        self.assertNotEqual(payload["expected"]["enabled"], payload["actual"]["enabled"])

    def test_successor_migration_skips_nonarmor_profiles_without_force_lookup(self):
        result = self._run_read_only_integration_migration("py-coal", None, None)
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual("[MIR5_INTEGRATION_PRECONFIG_FOREIGN] <fixture-payload>", result["marker"])
        self.assertEqual({
            "fixture_migration": "0.2.0",
            "profile": "py-coal",
            "status": "not-applicable",
            "reason": "foreign-armor-probe",
        }, py(result["payload"]))

    def _run_foreign_owner_source(self, technology_name, *, force_name="mir5-integration-catalogue-upgrade-foreign",
                                  call_force_index=71, present=True, initially_enabled=True):
        control = FOREIGN_OWNER / "source" / "control.lua"
        self.lua.globals().foreign_owner_source_path = control.as_posix()
        self.lua.execute(r'''
          function run_foreign_owner_source(technology_name, options)
            local interface, methods
            local storage, writes = {}, {}
            local values = {valid=true, name=technology_name, enabled=options.initially_enabled}
            local primary = setmetatable({}, {
              __index=values,
              __newindex=function(_, key, value) writes[#writes + 1]=key; values[key]=value end,
            })
            local technologies = {}
            if options.present then technologies[technology_name]=primary end
            local foreign = {valid=true, name=options.force_name, technologies=technologies}
            local env = {
              storage=storage,
              game={forces={[71]=foreign}},
              remote={add_interface=function(name, value)
                if interface ~= nil then error("duplicate interface") end
                interface, methods = name, value
              end},
            }
            env._G=env
            setmetatable(env, {__index=function(_, key) return _G[key] end})
            local loaded, message = pcall(function() assert(loadfile(foreign_owner_source_path, "t", env))() end)
            if not loaded then return {loaded=false, message=tostring(message)} end
            local ok, call_message = pcall(function() methods.record_and_disable(options.call_force_index, technology_name) end)
            return {loaded=true, ok=ok, message=tostring(call_message), interface=interface,
              enabled=values.enabled, writes=writes, witness=storage.mir5_integration_foreign_owner}
          end
        ''')
        return self.lua.eval("run_foreign_owner_source")(technology_name, lua(self.lua, {
            "force_name": force_name, "call_force_index": call_force_index, "present": present,
            "initially_enabled": initially_enabled,
        }))

    def _run_foreign_owner_migration(self, state, *, technology_name="recipe-prod-research_armor_components-1",
                                     force_name="mir5-integration-catalogue-upgrade-foreign", force_index=71,
                                     present=True, enabled=True):
        migration = FOREIGN_OWNER / "successor" / "migrations" / "0.2.0.lua"
        self.lua.globals().foreign_owner_migration_path = migration.as_posix()
        self.lua.execute(r'''
          function run_foreign_owner_migration(state, options)
            local writes, marker, payload = {}, nil, nil
            local values = {valid=true, name=options.technology_name, enabled=options.enabled}
            local primary=setmetatable({}, {
              __index=values,
              __newindex=function(_, key, value)
                writes[#writes + 1]=key
                values[key]=value
              end,
            })
            local technologies={}
            if options.present then technologies[options.technology_name]=primary end
            local foreign={valid=true, name=options.force_name, technologies=technologies}
            local env={
              storage={mir5_integration_foreign_owner=state},
              game={forces={[options.force_index]=foreign}},
              helpers={table_to_json=function(value) payload=value; return "<fixture-payload>" end},
              log=function(value) marker=value end,
            }
            env._G=env
            setmetatable(env, {__index=function(_, key) return _G[key] end})
            local ok,message=pcall(function() assert(loadfile(foreign_owner_migration_path, "t", env))() end)
            return {ok=ok,message=tostring(message),enabled=values.enabled,writes=writes,marker=marker,payload=payload}
          end
        ''')
        return self.lua.eval("run_foreign_owner_migration")(lua(self.lua, state), lua(self.lua, {
            "technology_name": technology_name, "force_name": force_name, "force_index": force_index,
            "present": present, "enabled": enabled,
        }))

    def test_foreign_owner_actor_records_and_disables_only_named_integration_primaries(self):
        for primary in (
            "recipe-prod-research_armor_components-1",
            "recipe-prod-research_material_py_log-4",
            "recipe-prod-research_breeding-1",
        ):
            with self.subTest(primary=primary):
                good = self._run_foreign_owner_source(primary)
                self.assertTrue(good["loaded"], good["message"])
                self.assertTrue(good["ok"], good["message"])
                self.assertEqual("mir5-integration-foreign-owner", good["interface"])
                self.assertFalse(good["enabled"])
                self.assertEqual(["enabled"], py(good["writes"]))
                self.assertEqual({
                    "force_index": 71,
                    "technology": primary,
                    "disabled": True,
                }, py(good["witness"]))

        opponents = (
            ("non-actor technology", "laser-shooting-speed-8", {}, "outside the integration primary set"),
            ("wrong force", "recipe-prod-research_armor_components-1", {"force_name": "other-foreign-force"}, "foreign force differs"),
            ("missing technology", "recipe-prod-research_armor_components-1", {"present": False}, "named primary technology is absent"),
            ("invalid force index", "recipe-prod-research_armor_components-1", {"call_force_index": 0}, "foreign force identity differs"),
            ("already disabled", "recipe-prod-research_armor_components-1", {"initially_enabled": False}, "not initially enabled"),
        )
        for label, name, options, expected in opponents:
            with self.subTest(opponent=label):
                result = self._run_foreign_owner_source(name, **options)
                self.assertTrue(result["loaded"], result["message"])
                self.assertFalse(result["ok"])
                self.assertIn(expected, result["message"])
                self.assertFalse(py(result["writes"]))
                self.assertIsNone(result["witness"])

    def test_foreign_owner_successor_migration_restores_only_its_saved_disabled_flag(self):
        for primary in (
            "recipe-prod-research_armor_components-1",
            "recipe-prod-research_material_py_log-4",
            "recipe-prod-research_breeding-1",
        ):
            with self.subTest(primary=primary):
                state = {"force_index": 71, "technology": primary, "disabled": True}
                result = self._run_foreign_owner_migration(
                    state, technology_name=primary, enabled=True
                )
                self.assertTrue(result["ok"], result["message"])
                self.assertFalse(result["enabled"])
                self.assertEqual(["enabled"], py(result["writes"]))
                self.assertEqual("[MIR5_FOREIGN_OWNER_MIGRATION] <fixture-payload>", result["marker"])
                self.assertEqual({
                    "actor": "mir5-integration-foreign-owner",
                    "force": 71,
                    "technology": primary,
                    "expected_disabled": True,
                    "observed_before": True,
                    "observed_after": False,
                }, py(result["payload"]))

    def test_foreign_owner_successor_refuses_bad_witnesses_before_writing(self):
        valid = {"force_index": 71, "technology": "recipe-prod-research_armor_components-1", "disabled": True}
        opponents = (
            ("absent witness", None, {}, "absent or malformed"),
            ("malformed witness", {"force_index": 71, "technology": valid["technology"], "disabled": False}, {}, "absent or malformed"),
            ("wrong force", valid, {"force_name": "other-foreign-force"}, "stored foreign force differs"),
            ("missing technology", valid, {"present": False}, "stored primary technology is absent"),
            ("non-actor technology", {"force_index": 71, "technology": "laser-shooting-speed-8", "disabled": True},
             {"technology_name": "laser-shooting-speed-8"}, "outside the integration primary set"),
            ("invalid stored index", {"force_index": 0, "technology": valid["technology"], "disabled": True}, {}, "absent or malformed"),
        )
        for label, state, options, expected in opponents:
            with self.subTest(opponent=label):
                result = self._run_foreign_owner_migration(state, **options)
                self.assertFalse(result["ok"])
                self.assertIn(expected, result["message"])
                self.assertFalse(py(result["writes"]))
                self.assertIsNone(result["marker"])
                self.assertIsNone(result["payload"])

    def test_foreign_owner_actor_stages_are_bound_and_successor_has_no_configuration_handler(self):
        source_info = json.loads((FOREIGN_OWNER / "source" / "info.json").read_text(encoding="utf-8"))
        successor_info = json.loads((FOREIGN_OWNER / "successor" / "info.json").read_text(encoding="utf-8"))
        self.assertEqual("0.1.0", source_info["version"])
        self.assertEqual("0.2.0", successor_info["version"])
        self.assertIn("mir-fixture-mir5-integration-catalogue-upgrade = 0.1.0", source_info["dependencies"])
        self.assertIn("mir-fixture-mir5-integration-catalogue-upgrade = 0.2.0", successor_info["dependencies"])
        successor = (FOREIGN_OWNER / "successor" / "control.lua").read_text(encoding="utf-8")
        self.assertNotIn("on_configuration_changed", successor)
        integration = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn('remote.call(FOREIGN_OWNER, "record_and_disable", foreign.index, plan.primary)', integration)
        self.assertNotIn("foreign_primary.enabled, foreign_primary.visible_when_disabled", integration)
        self.assertNotIn("foreign_primary.enabled =", integration)
        self.assertIn("foreign_primary.visible_when_disabled = false", integration)

    def test_fixture_never_writes_effects_or_uses_a_generic_research_solver(self):
        text = "\n".join(path.read_text(encoding="utf-8") for path in FIXTURE.rglob("*.lua"))
        self.assertIn('local SAVE = "mir5-native-complete"', text)
        self.assertIn("queued_progress=.42", text)
        self.assertIn("paused_progress=.27", text)
        self.assertIn("foreign_disablement_checked=true", text)
        self.assertIn("script.on_load(function()", text)
        self.assertNotIn("productivity_bonus =", text)
        self.assertNotIn("research_queue_enabled", text)
        self.assertNotIn("enable_all_prototypes() end", text)
        self.assertNotIn("game.technology_prototypes", text)
        self.assertNotIn("prototypes.technology", text)
        self.assertNotIn("require(\"research.", text)
        self.assertNotIn("__more-infinite-research__", text)

    def _published_py_reset_control(self, identifier, opponent=None):
        path = FIXTURE.parent / "py-published-reset-control"
        mods = {"base": "2.0.77", "more-infinite-research": "4.7.20002",
                "mir-fixture-mir5-integration-catalogue-upgrade": "0.2.0",
                "mir-fixture-mir5-integration-foreign-owner": "0.2.0",
                "mir-fixture-mir5-active-mods-observer": "0.1.0"}
        profile = json.loads((FIXTURE.parents[1] / "profiles" /
                              f"{identifier}-f200-2077.json").read_text(encoding="utf-8"))
        mods.update({row["name"]: row["version"] for row in profile["mods"]
                     if row.get("enabled", True)})
        if opponent == "wrong-mir":
            mods["more-infinite-research"] = "5.0.20000"
        self.lua.execute(r'''
          function run_published_py_control(path, active, profile, primary, opponent)
            local callbacks, events, payloads, saves = {}, {}, {}, {}
            local function readonly(fields)
              return setmetatable({}, {
                __index=fields,
                __newindex=function() error("observer attempted a native or stored-state write") end,
                __pairs=function() return next, fields, nil end,
              })
            end
            local function row(level, enabled, maximum)
              return readonly{level=level, researched=false, enabled=enabled,
                visible=false, saved=0, maximum=maximum}
            end
            local before = readonly{
              technologies=readonly{
                [primary]=row(5, opponent == "source-enabled", 50000000),
                ["laser-shooting-speed-8"]=row(8, true, "infinite"),
              },
              recipes=readonly{fixture_recipe=.1}, guns=readonly{bullet=.1},
              fields=readonly{manual_mining_speed_modifier=0},
            }
            local function technology(name, level, enabled, maximum)
              return readonly{valid=true, name=name, level=level, researched=false,
                enabled=enabled, visible_when_disabled=false, saved_progress=0,
                prototype=readonly{max_level=maximum}}
            end
            local force = readonly{
              valid=true, name="mir5-integration-catalogue-upgrade-foreign",
              technologies=readonly{
                [primary]=technology(primary, opponent == "primary-level" and 6 or 5,
                  opponent ~= "primary-disabled", 50000000),
                ["laser-shooting-speed-8"]=technology("laser-shooting-speed-8", 8,
                  opponent ~= "other-enabled", "infinite"),
              },
              recipes=readonly{fixture_recipe=readonly{valid=true,
                productivity_bonus=opponent == "recipe" and .2 or .1}},
              get_gun_speed_modifier=function() return opponent == "gun" and .2 or .1 end,
              manual_mining_speed_modifier=opponent == "force" and 1 or 0,
            }
            local state = readonly{phase="source-complete", profile=profile,
              foreign_index=5, foreign_snapshot=before}
            -- Factorio's storage belongs to this fixture alone. The actor's
            -- private key is absent and any attempted cross-mod read must fail.
            local own = {mir5_integration_catalogue_upgrade=state}
            local env = {
              storage=setmetatable({}, {
                __index=function(_, key)
                  if own[key] == nil then error("read outside fixture private storage: " .. key) end
                  return own[key]
                end,
                __newindex=function() error("observer attempted a storage write") end,
              }),
              game={forces={[5]=force}, server_save=function(name) saves[#saves+1]=name end},
              script={active_mods=active,
                on_configuration_changed=function(fn) callbacks.config=fn end,
                on_load=function(fn) callbacks.load=fn end,
                on_event=function(id, fn) events[id]=fn end},
              defines={events={on_tick=1}}, log=function() end,
              helpers={table_to_json=function(value) payloads[#payloads+1]=value; return "{}" end},
            }
            setmetatable(env, {__index=_G})
            local ok, message = pcall(function()
              assert(loadfile(path .. "/data-final-fixes.lua", "t", {mods=active,
                pairs=pairs, error=error}))()
              assert(loadfile(path .. "/control.lua", "t", env))()
              callbacks.config()
              events[1]()
              callbacks.load()
              events[1]()
            end)
            return {ok=ok, message=tostring(message), payloads=payloads, saves=saves}
          end
        ''')
        return py(self.lua.eval("run_published_py_control")(
            path.as_posix(), lua(self.lua, mods), identifier,
            self.plan["profiles"][identifier]["primary"], opponent))

    def test_published_py_observer_uses_only_its_own_storage_and_read_only_native_objects(self):
        for identifier in ("py-coal", "py-alienlife-hightech"):
            with self.subTest(profile=identifier):
                result = self._published_py_reset_control(identifier)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(["mir5-native-complete"], result["saves"])
                witnesses = result["payloads"][0]
                self.assertEqual(identifier, witnesses["profile"])
                self.assertFalse(witnesses["source_enabled"])
                self.assertTrue(witnesses["post_configuration_enabled"])
                self.assertTrue(witnesses["migration_actor_log_required"])
                self.assertEqual(2, witnesses["checked_technology_rows"])

    def test_published_py_observer_rejects_changed_state_and_mir5_without_weakening_ownership(self):
        for opponent in ("wrong-mir", "source-enabled", "primary-disabled", "primary-level",
                         "other-enabled", "recipe", "gun", "force"):
            with self.subTest(opponent=opponent):
                result = self._published_py_reset_control("py-coal", opponent)
                self.assertFalse(result["ok"], opponent)
                self.assertEqual({}, result["saves"])

    def test_documented_force_fields_exist_in_exact_f200_api_when_installed(self):
        runtime_api = f200_runtime_api_path()
        if runtime_api is None:
            self.skipTest("F200 runtime API documentation is not installed")
        document = json.loads(runtime_api.read_text(encoding="utf-8"))
        lua_force = next(row for row in document["classes"] if row["name"] == "LuaForce")
        fields = {row["name"] for row in lua_force["attributes"]}
        self.assertTrue(set(self.plan["force_fields"]) <= fields)
        self.assertNotIn("research_queue_enabled", fields)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(IntegrationCatalogueUpgradeFixtureTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
