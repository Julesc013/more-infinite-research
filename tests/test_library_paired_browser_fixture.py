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
            local raw = { ["string-setting"] = {}, ["bool-setting"] = {} }
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
            local save_ticks = {}
            local profiling = false
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
              local family = element("drop-down", "fixture-family")
              family.items = arm == "published" and {{"mir-browser.scope-all"},{"mir-browser.scope-mir"}}
                or {{"mir-browser.scope-mir"},{"mir-browser.scope-all"}}
              local requested_family = options.family or (arm == "published" and "all" or "mir")
              local choose_all = requested_family == "all" and opponent ~= "wrong-family"
              family.selected_index = arm == "published" and (choose_all and 1 or 2) or (choose_all and 2 or 1)
              player.fixture_family_picker = family
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
                local filters = element("table", "mir_browser_filters")
                family.tags = {mir_browser="family"}
                filters.children = opponent == "missing-family" and {} or {{valid=true,children={family}}}
                if opponent == "duplicate-family" then filters.children[2] = {valid=true,children={family}} end
                if opponent == "unbounded-family-fields" then
                  for index=2,9 do filters.children[index]={valid=true,children={}} end
                end
                body["mir_browser_filters"] = filters
                content["mir_browser_body"] = body
                tabs["mir_browser_research_content"] = content
                root["mir_browser_tabs"] = tabs
              else
                local filters = element("table", "mir_library_filters")
                local tabs = element("tabbed-pane", "mir_library_tabs")
                local stacked = opponent == "narrow-display" or opponent == "bad-stacked-width"
                local content = element(stacked and "scroll-pane" or "table", "mir_library_research_content")
                content.style = {maximal_width=stacked and 430 or 760}
                if stacked then content.vertical_scroll_policy = "auto" else content.column_count = 2 end
                filters["mir_library_query"] = {valid=true, type="textfield", text=options.search}
                if opponent ~= "missing-family" then filters["mir_library_family"] = family end
                content["mir_library_results"] = listbox("mir_library_results")
                local pane_width = stacked and 406 or 294
                content["mir_library_results"].style = {minimal_width=pane_width, maximal_width=pane_width}
                content["mir_library_detail"] = element("scroll-pane", "mir_library_detail")
                local detail_width = stacked and 406 or 442
                if opponent == "bad-stacked-width" then detail_width = 300 end
                content["mir_library_detail"].style = {minimal_width=detail_width, maximal_width=detail_width}
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
                  return {restart=function() profiling=true end, stop=function() profiling=false end}
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
            local retained_probe = opponent ~= nil and string.find(opponent, "retained-", 1, true) == 1
            if retained_probe then
              env.settings.startup["mir5-library-paired-browser-retained-refresh"] = {value=true}
            end
            if opponent == "retained-invalid-setting" then
              env.settings.startup["mir5-library-paired-browser-retained-refresh"].value = "true"
            end
            env.remote.call=function(interface, method, player_index, options)
              if interface ~= "more-infinite-research-browser" or method ~= "open" then error("unexpected public interface call") end
              local player = players[player_index]
              if player == nil then return false end
              if opponent == "deferred-render" then
                for _, capture in ipairs(screenshots) do
                  if string.find(capture.path, "first-open-settled", 1, true) and capture.tick == env.game.tick then
                    error("next action changed GUI before settled screenshot render")
                  end
                end
              end
              calls[#calls+1]={player=player_index, query=options.search, selected=options.selected, tab=options.tab, sort=options.sort, family=options.family}
              action_ticks[#action_ticks+1]=env.game.tick
              if opponent == "remote-false" then return false end
              if opponent == "native-mutation" then force.recipes["iron-gear-wheel"].productivity_bonus=.1 end
              render_public(player, options)
              return true
            end
            env.game={
              players=players, tick=0,
              surfaces={[1]={valid=true, name="nauvis", map_gen_settings={seed=424242, width=0, height=0}}},
              take_screenshot=function(row)
                row.tick=env.game.tick;row.calls_seen=#calls;row.profiling=profiling
                screenshots[#screenshots+1]=row
              end,
              server_save=function(name)
                if opponent == "deferred-render" and name == "mir5-native-complete" then
                  for _, capture in ipairs(screenshots) do
                    if string.find(capture.path, "reopen-settled", 1, true) and capture.tick == env.game.tick then
                      error("final save modal obscured pending settled screenshot render")
                    end
                  end
                end
                saves[#saves+1]=name
                save_ticks[name]=env.game.tick
              end
            }
            setmetatable(env.game,{__index=function(_, key)
              if key == "create_profiler" then error("removed game.create_profiler API was accessed") end
            end})
            if opponent == "wrong-map-seed" then env.game.surfaces[1].map_gen_settings.seed=424243 end
            if opponent == "missing-map-surface" then env.game.surfaces={} end
            if opponent == "missing-map-settings" then env.game.surfaces[1].map_gen_settings=nil end
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
            for _, tick in ipairs({initial_ready_tick,initial_ready_tick+60,initial_ready_tick+120,initial_ready_tick+180,initial_ready_tick+240}) do
              if tick == initial_ready_tick+60 and opponent == "changed-settled-root" then
                en.gui.screen["mir_research_browser"] = {valid=true}
              end
              if tick == initial_ready_tick+60 and opponent == "settled-native-mutation" then
                force.recipes["iron-gear-wheel"].productivity_bonus=.1
              end
              if tick == initial_ready_tick+60 and opponent == "late-family-reset" then
                en.fixture_family_picker.selected_index = arm == "published" and 2 or 1
              end
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
            if opponent == "changed-restart-map-seed" then env.game.surfaces[1].map_gen_settings={seed=424243} end
            ok,message=register_control()
            if not ok then return {ok=false,message=message,markers=markers} end
            ok,message=invoke_load_read_only()
            if not ok then return {ok=false,message=message,markers=markers,load_writes=load_writes} end
            if env.storage["mir5_library_paired_browser"] ~= durable then return {ok=false,message="on_load replaced fixture state",markers=markers} end
            en.connected=false; de.connected=false
            local restart_marker_count_before_event=#markers
            env.game.tick=env.game.tick+1
            ok,message=invoke(callbacks.events[2],{tick=env.game.tick})
            if not ok then return {ok=false,message=message,markers=markers,load_writes=load_writes} end
            local restart_first_event={markers_before=restart_marker_count_before_event,markers_after=#markers,
              calls=#calls,screenshots=#screenshots,joins=durable.join_events}
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
            for _, tick in ipairs({restart_ready_tick,restart_ready_tick+60,restart_ready_tick+119,restart_ready_tick+120}) do
              if tick == restart_ready_tick+120 and opponent == "changed-final-settled-root" then
                en.gui.screen["mir_research_browser"]={valid=true}
              end
              env.game.tick=tick
              ok,message=invoke(callbacks.events[2],{tick=tick})
              if not ok then return {ok=false,message=message,markers=markers,calls=calls} end
            end
            if retained_probe then
              for step=1,40 do
                if durable.phase == "completed" then break end
                if opponent == "retained-native-mutation" and durable.refresh_iterations == 7 then
                  force.recipes["iron-gear-wheel"].productivity_bonus=.1
                end
                if opponent == "retained-lost-final-view" and durable.phase == "retained-after" then
                  en.gui.screen["mir_research_browser"]=nil
                end
                env.game.tick=durable.capture_after_tick
                ok,message=invoke(callbacks.events[2],{tick=env.game.tick})
                if not ok then return {ok=false,message=message,markers=markers,calls=calls} end
              end
              if durable.phase ~= "completed" then return {ok=false,message="retained fixture did not terminate"} end
            end
            return {
              ok=ok,message=message,markers=markers,profiler_labels=profiler_labels,screenshots=screenshots,
              saves=saves,save_ticks=save_ticks,calls=calls,joins=joins,load_writes=load_writes,readiness=readiness,action_ticks=action_ticks,restart_wait=restart_wait,restart_first_event=restart_first_event,
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

    def test_retained_refresh_is_explicitly_opted_in_and_uses_only_fixture_settings(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                ordinary = self.setting_result(arm)
                setting = ordinary["raw"]["bool-setting"]["mir5-library-paired-browser-retained-refresh"]
                self.assertFalse(setting["default_value"])
                selected = self.lua.globals().paired_browser_setting(
                    SETTINGS.as_posix(), (ARMS[arm]["selector"] / "settings-updates-retained.lua").as_posix(), False)
                self.assertTrue(selected["ok"], selected["message"])
                self.assertTrue(selected["raw"]["bool-setting"]["mir5-library-paired-browser-retained-refresh"]["default_value"])
                self.assertEqual(selected["raw"]["string-setting"]["mir5-library-paired-browser-arm"]["default_value"], arm)

    def test_retained_refresh_has_exact_windows_32_iterations_and_unchanged_native_state(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm, "retained-refresh")
                self.assertTrue(result["ok"], result["message"])
                markers = [row for row in result["markers"] if row.get("window_ticks") is not None]
                self.assertEqual([row["stage"] for row in markers],
                                 ["baseline-start", "baseline-end", "post-refresh-start", "post-refresh-end"])
                self.assertEqual([row["refresh_iterations"] for row in markers], [0, 0, 32, 32])
                ticks = [row["tick"] for row in markers]
                self.assertEqual([ticks[1]-ticks[0], ticks[2]-ticks[1], ticks[3]-ticks[2]], [600, 960, 600])
                self.assertEqual(len(result["calls"]), 72)
                self.assertEqual(len(result["screenshots"]), 12)
                self.assertEqual(result["profiler_labels"], ["first_open", "search", "refresh", "reopen"])
                self.assertEqual(result["save_ticks"]["mir5-native-complete"], ticks[-1])
                self.assertTrue(all(row["native_snapshot_unchanged"] for row in markers))
                self.assertEqual(result["load_writes"], 0)

    def test_retained_refresh_rejects_bad_setting_native_mutation_and_lost_final_view(self):
        for arm in ARMS:
            for opponent, reason in [
                ("retained-invalid-setting", "not Boolean"),
                ("retained-native-mutation", "mutated named native research"),
                ("retained-lost-final-view", "root is absent or hidden"),
            ]:
                with self.subTest(arm=arm, opponent=opponent):
                    result = self.runtime_result(arm, opponent)
                    self.assertFalse(result["ok"])
                    self.assertIn(reason, result["message"])

    def test_fixed_map_seed_is_observed_on_creation_initial_host_and_cold_restart(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm)
                self.assertTrue(result["ok"], result["message"])
                ready = [row for row in result["markers"] if row["stage"] == "ready"]
                self.assertEqual(len(ready), 3)
                self.assertEqual([row["map_gen_settings"] for row in ready],
                                 [{"seed": 424242, "width": 0, "height": 0}] * 3)
                for opponent in ("wrong-map-seed", "missing-map-surface", "missing-map-settings",
                                 "changed-restart-map-seed"):
                    with self.subTest(opponent=opponent):
                        refused = self.runtime_result(arm, opponent)
                        self.assertFalse(refused["ok"])
                        self.assertIn("fixed map", refused["message"])

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

    def test_both_arms_follow_four_actions_with_eight_immediate_and_four_settled_pngs(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(result["state"]["phase"], "completed")
                self.assertEqual(result["state"]["action_call_count"], 2)
                self.assertEqual(result["state"]["screenshot_calls"], 12)
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
                    "ready", "ready", "first-open", "search", "refresh", "restart-ready", "ready", "reopen", "completed",
                ])
                self.assertEqual([row["join_events"] for row in result["markers"]], [0, 0, 2, 2, 2, 2, 2, 4, 4])
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
                self.assertTrue(all(row['requested_family'] == 'all' for row in result['markers']))
                self.assertEqual([row['stage'] for row in result['markers'] if row['native_family_verified']],
                                 ['first-open', 'search', 'refresh', 'reopen'])
                self.assertEqual([row["path"] for row in result["screenshots"]], [
                    f"mir5-library-paired-browser/{stage}-{player}.png"
                    for stage in ("first-open", "first-open-settled", "search", "refresh", "reopen", "reopen-settled") for player in (1, 2)
                ])
                self.assertTrue(all(row["show_gui"] and row["force_render"] and row["resolution"] == [1280, 720]
                                    for row in result["screenshots"]))
                self.assertTrue(all(row["profiling"] is False for row in result["screenshots"]))
                immediate = [row for row in result["screenshots"] if "-settled-" not in row["path"]]
                settled = [row for row in result["screenshots"] if "-settled-" in row["path"]]
                self.assertEqual([row["calls_seen"] for row in settled], [2, 2, 8, 8])
                for early, late in zip(immediate[:2] + immediate[-2:], settled):
                    self.assertEqual(late["tick"] - early["tick"], 60)
                    self.assertEqual(late["calls_seen"], early["calls_seen"])

    def test_each_public_call_explicitly_selects_all_research(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm)
                self.assertTrue(result['ok'], result['message'])
                self.assertEqual([row.get('family') for row in result['calls']], ['all'] * 8)

    def test_next_action_waits_after_the_settled_screenshot_request(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm, 'deferred-render')
                self.assertTrue(result['ok'], result['message'])
                late = next(row for row in result['screenshots'] if row['path'].endswith('first-open-settled-2.png'))
                self.assertEqual(result['action_ticks'][2] - late['tick'], 60)

    def test_final_save_waits_for_reopen_render_and_retains_both_observed_roots(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm, "deferred-render")
                self.assertTrue(result["ok"], result["message"])
                late = [r for r in result["screenshots"] if "reopen-settled" in r["path"]]
                self.assertEqual(len(late), 2)
                self.assertEqual([result["save_ticks"]["mir5-native-complete"] - r["tick"] for r in late], [60, 60])
                self.assertEqual(result["saves"], ["mir5-library-paired-browser-restart", "mir5-native-complete"])
                self.assertEqual(len(result["calls"]), 8)
                self.assertEqual(result["state"]["screenshot_calls"], 12)
                refused = self.runtime_result(arm, "changed-final-settled-root")
                self.assertFalse(refused["ok"])
                self.assertIn("final render grace lost the original public Browser root", refused["message"])

    def test_published_family_lookup_rejects_duplicate_or_unbounded_filter_layout(self):
        for opponent, message in [
            ('duplicate-family', 'public browser family selector is duplicated'),
            ('unbounded-family-fields', 'public browser family selector layout differs'),
        ]:
            with self.subTest(opponent=opponent):
                result = self.runtime_result('published', opponent)
                self.assertFalse(result['ok'])
                self.assertIn(message, result['message'])

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
                        {"phase": "restart", "calls": 6, "screenshots": 8},
                    ])
                    self.assertEqual(len(result["screenshots"]), 12)
                    self.assertEqual(result["profiler_labels"], list(profile_reader.ACTIONS))

    def test_readiness_waits_for_the_latest_join_on_initial_and_cold_restart(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm, "staggered-joins")
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(result["readiness"], [
                    {"phase": "initial", "calls": 0, "screenshots": 0},
                    {"phase": "restart", "calls": 6, "screenshots": 8},
                ])
                # One simulated post-load tick now precedes the cold joins;
                # the 120-tick wait after the latest staggered join is intact.
                self.assertEqual(result["action_ticks"], [151,151,271,271,331,331,541+1,541+1])

    def test_restart_ready_waits_without_actions_until_the_host_actually_restarts(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm, "delayed-host-stop")
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(result["restart_wait"], {
                    "phase": "awaiting-cold-restart", "joins": 2,
                    "calls": 6, "screenshots": 8, "saved_state_unchanged": True,
                })
                self.assertEqual(result["profiler_labels"], list(profile_reader.ACTIONS))
                self.assertEqual(len(result["screenshots"]), 12)
                self.assertEqual(result["state"]["join_events"], 4)
                self.assertEqual(result["load_writes"], 0)

    def test_cold_load_emits_one_ready_on_first_event_before_any_new_client_action(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                result = self.runtime_result(arm)
                self.assertTrue(result['ok'], result['message'])
                self.assertEqual(result['restart_first_event'], {
                    'markers_before': 6, 'markers_after': 7,
                    'calls': 6, 'screenshots': 8, 'joins': 2,
                })
                self.assertEqual(sum(row['stage'] == 'ready' for row in result['markers']), 3)
                self.assertEqual(result['load_writes'], 0)

    def test_runtime_rejects_malformed_closure_seed_public_call_shape_and_restart_boundary(self):
        cases = (
            ("wrong-closure", "fixture active-mod closure differs"),
            ("active-research", "fresh paired Browser seed unexpectedly has active research"),
            ("queued-research", "fresh paired Browser seed research queue is not empty"),
            ("remote-false", "public browser interface did not open"),
            ("bad-shape", "public browser detail differs"),
            ("wrong-family", "public browser family scope differs from declared all research"),
            ("missing-family", "public browser family scope differs from declared all research"),
            ("late-family-reset", "public browser family scope differs from declared all research"),
            ("native-mutation", "public Browser actions mutated named native research, queue, or recipes"),
            ("changed-settled-root", "settled capture lost the original public Browser root"),
            ("settled-native-mutation", "public Browser actions mutated named native research, queue, or recipes"),
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

    def test_mir5_browser_observer_accepts_responsive_stacked_geometry(self):
        result = self.runtime_result("mir5", "narrow-display")
        self.assertTrue(result["ok"], result["message"])
        malformed = self.runtime_result("mir5", "bad-stacked-width")
        self.assertFalse(malformed["ok"])
        self.assertIn("MIR5 public browser stacked list/detail geometry differs", malformed["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LibraryPairedBrowserFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
