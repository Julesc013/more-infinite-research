"""Host controls for the bounded F200 paired public-browser fixture.

They exercise fixture-owned Lua with small native-shaped doubles and check
profiler action tokens against synthetic reader examples. They do not launch
Factorio, measure native durations, or establish a timing/memory/native result.
"""
import argparse
import json
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import read_library_profiles as profile_reader

FIXTURE = ROOT / "tests/fixtures/library-paired-browser"
CONTROL = FIXTURE / "control.lua"
SETTINGS = FIXTURE / "settings.lua"
ARMS = {
    "published": {
        "profile": ROOT / "tests/profiles/library-paired-browser-published-f200-2077.json",
        "selector": FIXTURE / "arm-published",
        "mir_version": "4.7.20002",
        "archive": "F3943EB4D69CCDAC41BD9F922AD03A5C78F34F22D8E7FA5A88A7A658AB1010B7",
    },
    "mir5": {
        "profile": ROOT / "tests/profiles/library-paired-browser-mir5-f200-2077.json",
        "selector": FIXTURE / "arm-mir5",
        "mir_version": "5.0.20000",
        "archive": "2BBDBA9A0B816AC383CEA116CDF86D587BC34EFF7E1C5ACE2583F1DA98F9E842",
    },
}
OBSERVER_SHA = "723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87"
ENGINE_SHA = "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B"


def plain(value, seen=None):
    if not hasattr(value, "items"):
        return value
    seen = set() if seen is None else seen
    if id(value) in seen:
        raise AssertionError("fixture result is cyclic")
    seen.add(id(value))
    entries = list(value.items())
    keys = [key for key, _ in entries]
    if keys and all(isinstance(key, int) and key >= 1 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        result = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else:
        result = {key: plain(item, seen) for key, item in entries}
    seen.remove(id(value))
    return result


class LibraryPairedBrowserFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().control_path = CONTROL.as_posix()
        self.lua.globals().saved_state_fingerprint = lambda value: json.dumps(plain(value), sort_keys=True)
        self.lua.globals().settings_path = SETTINGS.as_posix()
        self.lua.globals().published_selector = (ARMS["published"]["selector"] / "settings-updates.lua").as_posix()
        self.lua.globals().mir5_selector = (ARMS["mir5"]["selector"] / "settings-updates.lua").as_posix()
        self.lua.execute(r'''
          function paired_browser_setting(settings_path, selector_path, omit_setting)
            local raw = { ["string-setting"] = {} }
            local data = {raw = raw}
            function data:extend(rows)
              for _, row in ipairs(rows) do raw[row.type][row.name] = row end
            end
            local env = {data = data}
            env._G = env
            setmetatable(env, {__index = _G})
            local settings_chunk = assert(loadfile(settings_path, "t", env))
            local ok, message = pcall(settings_chunk)
            if not ok then return {ok=false, message=tostring(message), raw=raw} end
            if omit_setting then raw["string-setting"]["mir5-library-paired-browser-arm"] = nil end
            local selector_chunk = assert(loadfile(selector_path, "t", env))
            ok, message = pcall(selector_chunk)
            return {ok=ok, message=tostring(message), raw=raw}
          end

          function paired_browser_parse(path)
            local callbacks, reads = {events = {}}, {}
            local env = {
              script = {
                active_mods = {},
                on_init = function(callback) callbacks.init = callback end,
                on_load = function(callback) callbacks.load = callback end,
                on_event = function(event, callback) callbacks.events[event] = callback end
              },
              defines = {events = {on_player_joined_game = 1, on_tick = 2}}
            }
            env._G = env
            setmetatable(env, {__index = function(_, key)
              if key == "game" or key == "storage" or key == "settings" or key == "remote" or key == "helpers" then
                reads[key] = (reads[key] or 0) + 1
                error("fixture control accessed " .. key .. " while registering callbacks")
              end
              return _G[key]
            end})
            local chunk, message = loadfile(path, "t", env)
            if not chunk then return {ok=false, message=tostring(message), reads=reads, callbacks=callbacks} end
            local ok, result = pcall(chunk)
            return {ok=ok, message=tostring(result), reads=reads, callbacks=callbacks}
          end

          function paired_browser_runtime(path, arm, opponent)
            local callbacks, markers, profiler_labels, screenshots, saves, calls, joins = {events = {}}, {}, {}, {}, {}, {}, {}
            local action_ticks = {}
            local gear = "recipe-prod-research_gears-1"
            local mining = "recipe-prod-research_mining_drill-1"
            local force = {
              valid=true, index=1, name="player", current_research=nil,
              research_progress=0, research_queue={}, technologies={}, recipes={}
            }
            for _, name in ipairs({gear, mining}) do
              force.technologies[name] = {
                valid=true, name=name, level=1, researched=false, enabled=true,
                visible_when_disabled=false, research_unit_count=200, research_unit_energy=60
              }
            end
            force.recipes["iron-gear-wheel"] = {valid=true, name="iron-gear-wheel", productivity_bonus=0}
            force.recipes["electric-mining-drill"] = {valid=true, name="electric-mining-drill", productivity_bonus=0}
            if opponent == "active-research" then force.current_research = force.technologies[gear] end
            if opponent == "queued-research" then force.research_queue = {force.technologies[gear]} end

            local function element(kind, name)
              return {valid=true, type=kind, name=name}
            end
            local function listbox(name)
              local value = element("list-box", name)
              value.items = {"selected native result"}
              value.selected_index = 1
              return value
            end
            local function render_public(player, options)
              local root = element("frame", "mir_research_browser")
              root.visible = true
              if arm == "published" then
                local tabs = element("tabbed-pane", "mir_browser_tabs")
                local content = element("flow", "mir_browser_research_content")
                local body = element("flow", "mir_browser_body")
                local panes = element("flow", "mir_browser_research_results")
                local list_column = element("flow", "mir_browser_research_list")
                content["mir_browser_search"] = {valid=true, type="textfield", text=options.search}
                list_column["mir_browser_research_entries"] = listbox("mir_browser_research_entries")
                panes["mir_browser_research_list"] = list_column
                panes["mir_browser_research_detail"] = element("flow", "mir_browser_research_detail")
                body["mir_browser_research_results"] = panes
                content["mir_browser_body"] = body
                tabs["mir_browser_research_content"] = content
                root["mir_browser_tabs"] = tabs
              else
                local filters = element("table", "mir_library_filters")
                local tabs = element("tabbed-pane", "mir_library_tabs")
                local content = element("flow", "mir_library_research_content")
                filters["mir_library_query"] = {valid=true, type="textfield", text=options.search}
                content["mir_library_results"] = listbox("mir_library_results")
                content["mir_library_detail"] = element("flow", "mir_library_detail")
                tabs["mir_library_research_content"] = content
                root["mir_library_filters"] = filters
                root["mir_library_tabs"] = tabs
              end
              if opponent == "bad-shape" then
                if arm == "published" then
                  root["mir_browser_tabs"]["mir_browser_research_content"]["mir_browser_body"]["mir_browser_research_results"]["mir_browser_research_detail"] = nil
                else
                  root["mir_library_tabs"]["mir_library_research_content"]["mir_library_detail"] = nil
                end
              end
              player.gui.screen["mir_research_browser"] = root
            end

            local en = {valid=true, index=1, name="MIR5English", locale="en", connected=false, force=force, gui={screen={}}}
            local de = {valid=true, index=2, name="MIR5Deutsch", locale="de", connected=false, force=force, gui={screen={}}}
            if opponent == "bad-join-name" then en.name = "WrongPlayer" end
            local players = {[1]=en, [2]=de}
            local active = {
              base="2.0.77", ["more-infinite-research"]=(arm == "published" and "4.7.20002" or "5.0.20000"),
              ["mir-fixture-mir5-library-paired-browser"]="0.1.0",
              ["mir-fixture-mir5-active-mods-observer"]="0.1.0",
              ["mir-fixture-mir5-library-paired-browser-arm-" .. arm]="0.1.0"
            }
            if opponent == "wrong-closure" then active.intruder = "1.0.0" end

            local env = {
              script = {
                active_mods=active,
                on_init=function(callback) callbacks.init=callback end,
                on_load=function(callback) callbacks.load=callback end,
                on_event=function(event, callback) callbacks.events[event]=callback end
              },
              defines={events={on_player_joined_game=1,on_tick=2}},
              settings={startup={["mir5-library-paired-browser-arm"]={value=arm}}},
              storage={},
              helpers={
                table_to_json=function(row) markers[#markers+1]=row; return "fixture-marker" end,
                create_profiler=function(stopped)
                  if stopped ~= true then error("helpers.create_profiler must receive true") end
                  return {restart=function() end, stop=function() end}
                end
              },
              remote={interfaces={["more-infinite-research-browser"]={open=true}}},
              log=function(value)
                if type(value) == "table" and value[2] == "[MIR5_LIBRARY_PROFILE] " then
                  profiler_labels[#profiler_labels+1]=value[3]
                elseif type(value) == "string" then
                  local name, ordinal = string.match(value, "^%[MIR5_LIBRARY_PAIRED_BROWSER_JOIN%] ([A-Za-z0-9_%-]+) ([0-9]+)$")
                  if name then joins[#joins+1] = {name=name, ordinal=tonumber(ordinal)} end
                end
              end
            }
            env.remote.call=function(interface, method, player_index, options)
              if interface ~= "more-infinite-research-browser" or method ~= "open" then error("unexpected public interface call") end
              local player = players[player_index]
              if player == nil then return false end
              calls[#calls+1]={player=player_index, query=options.search, selected=options.selected, tab=options.tab, sort=options.sort}
              action_ticks[#action_ticks+1]=env.game.tick
              if opponent == "remote-false" then return false end
              if opponent == "native-mutation" then force.recipes["iron-gear-wheel"].productivity_bonus=.1 end
              render_public(player, options)
              return true
            end
            env.game={
              players=players, tick=0,
              take_screenshot=function(row) screenshots[#screenshots+1]=row end,
              server_save=function(name) saves[#saves+1]=name end
            }
            setmetatable(env.game,{__index=function(_, key)
              if key == "create_profiler" then error("removed game.create_profiler API was accessed") end
            end})
            env._G=env
            setmetatable(env,{__index=function(_, key) return _G[key] end})
            local function invoke(callback, event)
              local ok, result=pcall(callback,event)
              return ok,tostring(result)
            end
            local function register_control()
              callbacks = {events = {}}
              local chunk, message=loadfile(path,"t",env)
              if not chunk then return false, tostring(message) end
              return invoke(chunk)
            end
            local ok, message=register_control()
            if not ok then return {ok=false,message=message} end
            ok, message=invoke(callbacks.init)
            if not ok then return {ok=false,message=message,markers=markers} end

            -- The prepared seed was created by on_init.  The ordinary initial
            -- host is a new Lua state, so re-register callbacks before its
            -- read-only on_load and first runtime tick.
            local durable, original_storage = env.storage["mir5_library_paired_browser"], env.storage
            local load_writes=0
            local function invoke_load_read_only()
              local before = saved_state_fingerprint(original_storage)
              env.storage=setmetatable({}, {
                __index=function(_, key) return original_storage[key] end,
                __newindex=function() load_writes=load_writes+1; error("on_load wrote fixture storage") end
              })
              local loaded_ok, loaded_message=invoke(callbacks.load)
              env.storage=original_storage
              if loaded_ok and saved_state_fingerprint(original_storage) ~= before then
                return false, "on_load changed nested fixture storage"
              end
              return loaded_ok, loaded_message
            end
            ok, message=register_control()
            if not ok then return {ok=false,message=message,markers=markers} end
            ok, message=invoke_load_read_only()
            if not ok then return {ok=false,message=message,markers=markers,load_writes=load_writes} end
            if env.storage["mir5_library_paired_browser"] ~= durable then return {ok=false,message="on_load replaced fixture state",markers=markers} end
            local ready_markers_before_tick=#markers
            env.game.tick=1
            ok,message=invoke(callbacks.events[2],{tick=1})
            if not ok then return {ok=false,message=message,markers=markers,load_writes=load_writes} end
            local ready_markers_after_tick=#markers

            local readiness = {}
            if opponent == "late-initial-locale" or opponent == "duplicate-locales" then de.locale="en" end
            if opponent == "unsupported-locale" then de.locale="fr" end
            en.connected=true
            ok, message=invoke(callbacks.events[1],{player_index=1})
            if not ok then return {ok=false,message=message,markers=markers} end
            if opponent == "staggered-joins" then env.game.tick=31 end
            de.connected=true
            ok, message=invoke(callbacks.events[1],{player_index=2})
            if not ok then return {ok=false,message=message,markers=markers} end
            local initial_ready_tick=env.game.tick+120
            local initial_probes=opponent == "staggered-joins" and {32,121,150} or {2,120}
            for _, tick in ipairs(initial_probes) do
              env.game.tick=tick
              ok,message=invoke(callbacks.events[2],{tick=tick})
              if not ok then return {ok=false,message=message,markers=markers,calls=calls} end
            end
            readiness[#readiness+1]={phase="initial",calls=#calls,screenshots=#screenshots}
            if opponent == "late-initial-locale" then de.locale="de" end
            for _, tick in ipairs({initial_ready_tick,initial_ready_tick+60,initial_ready_tick+120,initial_ready_tick+180}) do
              env.game.tick=tick
              ok,message=invoke(callbacks.events[2],{tick=tick})
              if not ok then return {ok=false,message=message,markers=markers,calls=calls} end
            end
            local restart_wait
            if opponent == "delayed-host-stop" then
              local before=saved_state_fingerprint(original_storage)
              local save_tick=env.game.tick
              for _, offset in ipairs({1,60,240,600}) do
                env.game.tick=save_tick+offset
                ok,message=invoke(callbacks.events[2],{tick=env.game.tick})
                if not ok then return {ok=false,message=message,markers=markers,calls=calls} end
              end
              restart_wait={phase=durable.phase,joins=durable.join_events,
                calls=#calls,screenshots=#screenshots,
                saved_state_unchanged=saved_state_fingerprint(original_storage)==before}
            end
            if opponent == "no-cold-load" then
              en.connected=false; de.connected=false
              en.connected=true
              ok,message=invoke(callbacks.events[1],{player_index=1})
              if not ok then return {ok=false,message=message,markers=markers} end
              de.connected=true
              ok,message=invoke(callbacks.events[1],{player_index=2})
              if ok then
                env.game.tick=env.game.tick+120
                ok,message=invoke(callbacks.events[2],{tick=env.game.tick})
              end
              return {ok=ok,message=message,markers=markers}
            end
            ok,message=register_control()
            if not ok then return {ok=false,message=message,markers=markers} end
            ok,message=invoke_load_read_only()
            if not ok then return {ok=false,message=message,markers=markers,load_writes=load_writes} end
            if env.storage["mir5_library_paired_browser"] ~= durable then return {ok=false,message="on_load replaced fixture state",markers=markers} end
            en.connected=false; de.connected=false
            if opponent == "late-restart-locale" then de.locale="en" end
            en.connected=true
            ok,message=invoke(callbacks.events[1],{player_index=1})
            if not ok then return {ok=false,message=message,markers=markers,load_writes=load_writes} end
            local first_restart_join_tick=env.game.tick
            if opponent == "staggered-joins" then env.game.tick=env.game.tick+30 end
            de.connected=true
            ok,message=invoke(callbacks.events[1],{player_index=2})
            if not ok then return {ok=false,message=message,markers=markers,load_writes=load_writes} end
            local restart_ready_tick=env.game.tick+120
            local restart_probes=opponent == "staggered-joins"
              and {env.game.tick+1,first_restart_join_tick+120,restart_ready_tick-1}
              or {env.game.tick+1,restart_ready_tick-1}
            for _, tick in ipairs(restart_probes) do
              env.game.tick=tick
              ok,message=invoke(callbacks.events[2],{tick=tick})
              if not ok then return {ok=false,message=message,markers=markers,calls=calls} end
            end
            readiness[#readiness+1]={phase="restart",calls=#calls,screenshots=#screenshots}
            if opponent == "late-restart-locale" then de.locale="de" end
            for _, tick in ipairs({restart_ready_tick,restart_ready_tick+60}) do
              env.game.tick=tick
              ok,message=invoke(callbacks.events[2],{tick=tick})
              if not ok then return {ok=false,message=message,markers=markers,calls=calls} end
            end
            return {
              ok=ok,message=message,markers=markers,profiler_labels=profiler_labels,screenshots=screenshots,
              saves=saves,calls=calls,joins=joins,load_writes=load_writes,readiness=readiness,action_ticks=action_ticks,restart_wait=restart_wait,
              ready_markers_before_tick=ready_markers_before_tick,
              ready_markers_after_tick=ready_markers_after_tick,
              state=env.storage["mir5_library_paired_browser"]
            }
          end
        ''')

    def setting_result(self, arm, omit_setting=False):
        selector = self.lua.globals().published_selector if arm == "published" else self.lua.globals().mir5_selector
        return plain(self.lua.globals().paired_browser_setting(self.lua.globals().settings_path, selector, omit_setting))

    def runtime_result(self, arm, opponent=None):
        return plain(self.lua.globals().paired_browser_runtime(self.lua.globals().control_path, arm, opponent))

    def test_load_guard_rejects_nested_saved_state_writes_on_both_loads(self):
        original = CONTROL.read_text(encoding="utf-8")
        anchor = "script.on_load(function()"
        self.assertEqual(original.count(anchor), 1)
        for phase in ("awaiting-clients", "awaiting-cold-restart"):
            mutated = original.replace(anchor, anchor + (
                '\n  if storage[KEY].phase == "' + phase + '" then '
                'storage[KEY].unused_probe = {nested = true} end'))
            with tempfile.TemporaryDirectory(prefix="mir5-paired-load-") as work:
                path = Path(work) / "control.lua"
                path.write_text(mutated, encoding="utf-8")
                for arm in ARMS:
                    with self.subTest(arm=arm, phase=phase):
                        result = plain(self.lua.globals().paired_browser_runtime(path.as_posix(), arm, None))
                        self.assertFalse(result["ok"])
                        self.assertIn("on_load changed nested fixture storage", result["message"])

    def test_profiles_select_exactly_one_f200_public_arm(self):
        root_info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual((root_info["name"], root_info["version"], root_info["factorio_version"]),
                         ("mir-fixture-mir5-library-paired-browser", "0.1.0", "2.0"))
        self.assertEqual(root_info["dependencies"], ["base >= 2.0.77"])
        for arm, expected in ARMS.items():
            with self.subTest(arm=arm):
                profile = json.loads(expected["profile"].read_text(encoding="utf-8"))
                selector_name = f"mir-fixture-mir5-library-paired-browser-arm-{arm}"
                self.assertEqual((profile["kind"], profile["target"], profile["factorio_line"],
                                  profile["engine"]["version"], profile["engine"]["sha256"], profile["settings_mode"]),
                                 ("mir5-library-paired-browser-f200-native-selection", "f200", "2.0",
                                  "2.0.77", ENGINE_SHA, "Defaults"))
                self.assertEqual([(row["name"], row["version"]) for row in profile["mods"]], [
                    ("base", "2.0.77"),
                    ("mir-fixture-mir5-active-mods-observer", "0.1.0"),
                    ("more-infinite-research", expected["mir_version"]),
                    ("mir-fixture-mir5-library-paired-browser", "0.1.0"),
                    (selector_name, "0.1.0"),
                ])
                archive = {"mir-fixture-mir5-active-mods-observer_0.1.0.zip": OBSERVER_SHA}
                archive[f"more-infinite-research_{expected['mir_version']}.zip"] = expected["archive"]
                self.assertEqual(profile["archive_sha256"], archive)
                info = json.loads((expected["selector"] / "info.json").read_text(encoding="utf-8"))
                self.assertEqual((info["name"], info["version"], info["factorio_version"]),
                                 (selector_name, "0.1.0", "2.0"))
                self.assertEqual(info["dependencies"], [
                    "base >= 2.0.77", f"more-infinite-research = {expected['mir_version']}",
                    "mir-fixture-mir5-library-paired-browser = 0.1.0",
                ])

    def test_selectors_change_only_fixture_owned_default(self):
        for arm, expected_default in (("published", "published"), ("mir5", "mir5")):
            with self.subTest(arm=arm):
                result = self.setting_result(arm)
                self.assertTrue(result["ok"], result["message"])
                row = result["raw"]["string-setting"]["mir5-library-paired-browser-arm"]
                self.assertEqual((row["setting_type"], row["default_value"], row["allowed_values"][0], row["allowed_values"][1]),
                                 ("startup", expected_default, "published", "mir5"))
        missing = self.setting_result("published", omit_setting=True)
        self.assertFalse(missing["ok"])
        self.assertIn("selector is absent", missing["message"])

    def test_control_registers_without_runtime_access_or_imports(self):
        result = plain(self.lua.globals().paired_browser_parse(self.lua.globals().control_path))
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual(result["reads"], {})
        self.assertEqual(len(result["callbacks"]["events"]), 2)
        self.assertTrue(result["callbacks"]["init"])
        self.assertTrue(result["callbacks"]["load"])
        source = CONTROL.read_text(encoding="utf-8")
        self.assertNotIn("require(", source)
        self.assertNotIn("remote.add_interface", source)
        self.assertNotIn("on_research_finished", source)

    def test_both_arms_follow_the_same_four_action_eight_png_cold_restart_protocol(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(result["state"]["phase"], "completed")
                self.assertEqual(result["state"]["action_call_count"], 2)
                self.assertEqual(result["state"]["screenshot_calls"], 8)
                self.assertEqual(result["profiler_labels"], ["first_open", "search", "refresh", "reopen"])
                self.assertEqual([(row["player"], row["query"], row["selected"], row["tab"], row["sort"])
                                  for row in result["calls"]], [
                    (1, "gears", "recipe-prod-research_gears-1", "research", "progression"),
                    (2, "mining", "recipe-prod-research_mining_drill-1", "research", "progression"),
                    (1, "recipe prod research gears", "recipe-prod-research_gears-1", "research", "progression"),
                    (2, "recipe prod research mining drill", "recipe-prod-research_mining_drill-1", "research", "progression"),
                    (1, "recipe prod research gears", "recipe-prod-research_gears-1", "research", "progression"),
                    (2, "recipe prod research mining drill", "recipe-prod-research_mining_drill-1", "research", "progression"),
                    (1, "gears", "recipe-prod-research_gears-1", "research", "progression"),
                    (2, "mining", "recipe-prod-research_mining_drill-1", "research", "progression"),
                ])
                self.assertEqual(result["saves"], ["mir5-library-paired-browser-restart", "mir5-native-complete"])
                self.assertEqual(result["load_writes"], 0)
                self.assertEqual(result["ready_markers_before_tick"], 1)
                self.assertEqual(result["ready_markers_after_tick"], 2)
                self.assertEqual([row["stage"] for row in result["markers"]], [
                    "ready", "ready", "first-open", "search", "refresh", "restart-ready", "reopen", "completed",
                ])
                self.assertEqual([row["join_events"] for row in result["markers"]], [0, 0, 2, 2, 2, 2, 4, 4])
                self.assertEqual(result["joins"], [
                    {"name": "MIR5English", "ordinal": 1},
                    {"name": "MIR5Deutsch", "ordinal": 2},
                    {"name": "MIR5English", "ordinal": 3},
                    {"name": "MIR5Deutsch", "ordinal": 4},
                ])
                self.assertTrue(all(row["native_snapshot_unchanged"] for row in result["markers"]))
                action_markers = [row for row in result["markers"] if row["stage"] in {"first-open", "search", "refresh", "reopen"}]
                self.assertEqual([row["action_call_count"] for row in action_markers], [2, 2, 2, 2])
                self.assertTrue(all(row["profiler_observation_only"] for row in result["markers"]))
                self.assertTrue(all(row["performance_acceptance"] is False for row in result["markers"]))
                self.assertEqual([row["path"] for row in result["screenshots"]], [
                    f"mir5-library-paired-browser/{stage}-{player}.png"
                    for stage in ("first-open", "search", "refresh", "reopen") for player in (1, 2)
                ])
                self.assertTrue(all(row["show_gui"] and row["force_render"] and row["resolution"] == [1280, 720]
                                    for row in result["screenshots"]))

    def test_emitted_profiler_actions_match_the_shared_reader_contract(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(result["profiler_labels"], list(profile_reader.ACTIONS))
                for action in result["profiler_labels"]:
                    # These durations are grammar examples, not observations.
                    for role, rendered in (("server", "Duration: 1.000000ms"),
                                           ("en", "Duration: 1.000000ms"),
                                           ("de", "Dauer: 1.000000\u202fms")):
                        marker = f"{profile_reader.MARKER}{action} {rendered}"
                        parsed, _ = profile_reader._parse_marker(role, marker)
                        self.assertEqual(parsed, action)

    def test_profiler_uses_helpers_and_never_the_removed_game_member(self):
        source = CONTROL.read_text(encoding="utf-8")
        self.assertIn("helpers.create_profiler(true)", source)
        self.assertNotIn("game.create_profiler", source)
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm)
                self.assertTrue(result["ok"], result["message"])

    def test_native_locale_may_settle_after_initial_and_cold_restart_joins(self):
        for arm in ARMS:
            for opponent in ("late-initial-locale", "late-restart-locale"):
                with self.subTest(arm=arm, opponent=opponent):
                    result = self.runtime_result(arm, opponent)
                    self.assertTrue(result["ok"], result["message"])
                    self.assertEqual(result["readiness"], [
                        {"phase": "initial", "calls": 0, "screenshots": 0},
                        {"phase": "restart", "calls": 6, "screenshots": 6},
                    ])
                    self.assertEqual(len(result["screenshots"]), 8)
                    self.assertEqual(result["profiler_labels"], list(profile_reader.ACTIONS))

    def test_readiness_waits_for_the_latest_join_on_initial_and_cold_restart(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm, "staggered-joins")
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(result["readiness"], [
                    {"phase": "initial", "calls": 0, "screenshots": 0},
                    {"phase": "restart", "calls": 6, "screenshots": 6},
                ])
                self.assertEqual(result["action_ticks"], [151,151,211,211,271,271,481,481])

    def test_restart_ready_waits_without_actions_until_the_host_actually_restarts(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm, "delayed-host-stop")
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(result["restart_wait"], {
                    "phase": "awaiting-cold-restart", "joins": 2,
                    "calls": 6, "screenshots": 6, "saved_state_unchanged": True,
                })
                self.assertEqual(result["profiler_labels"], list(profile_reader.ACTIONS))
                self.assertEqual(len(result["screenshots"]), 8)
                self.assertEqual(result["state"]["join_events"], 4)
                self.assertEqual(result["load_writes"], 0)

    def test_runtime_rejects_malformed_closure_seed_public_call_shape_and_restart_boundary(self):
        cases = (
            ("wrong-closure", "fixture active-mod closure differs"),
            ("active-research", "fresh paired Browser seed unexpectedly has active research"),
            ("queued-research", "fresh paired Browser seed research queue is not empty"),
            ("remote-false", "public browser interface did not open"),
            ("bad-shape", "public browser detail differs"),
            ("native-mutation", "public Browser actions mutated named native research, queue, or recipes"),
            ("bad-join-name", "fixture join identity or ordinal differs"),
            ("duplicate-locales", "fixture clients have duplicate locales"),
            ("unsupported-locale", "fixture requires exact en and de clients"),
            ("no-cold-load", "reopen requires the requested cold host restart"),
        )
        for arm in ARMS:
            for opponent, expected in cases:
                with self.subTest(arm=arm, opponent=opponent):
                    result = self.runtime_result(arm, opponent)
                    self.assertFalse(result["ok"])
                    self.assertIn(expected, result["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LibraryPairedBrowserFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
