"""Independent input-observer controls with native-shaped doubles, not native input evidence."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/library-native-input"


def plain(value):
    if not hasattr(value, "items"):
        return value
    values = list(value.items())
    if values and {k for k, _ in values} == set(range(1, len(values)+1)):
        return [plain(value[i]) for i in range(1, len(values)+1)]
    return {k: plain(v) for k, v in values}


class LibraryNativeInputFixtureControls(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().observer_path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().historical_path = (ROOT / "tests/fixtures/migration-origins/f200-110-successor/catalogue.lua").as_posix()
        self.lua.globals().fingerprint = lambda value: json.dumps(plain(value), sort_keys=True)
        self.lua.execute(r'''
          function run_input_observer(target,opponent)
            local historical=assert(loadfile(historical_path))()
            local events={on_player_joined_game=1,on_gui_text_changed=2,on_gui_click=3,on_gui_location_changed=4,
              on_gui_closed=5,on_technology_effects_reset=6,on_player_removed=7}
            local ids={"mir-legacy-module-credit-speed-module","mir-legacy-module-credit-productivity-module",
              "mir-legacy-module-credit-efficiency-module","mir-legacy-cannon-credit-rocket-shooting-speed"}
            local gear,mining="recipe-prod-research_gears-1","recipe-prod-research_mining_drill-1"
            local root_name="mir_research_browser"
            local key="mir5_library_native_input"
            local store,callbacks,interfaces,memory,trace={},{},{},{},{}
            local calls,resets=0,0
            local forces={}
            for force_index,name in ipairs({"player","mir5-migration-origin-f200-110-foreign","mir5-migration-origin-f200-110-detached"}) do
              local force={valid=true,name=name,index=force_index,technologies={},recipes={},research_queue={},research_progress=0,
                manual_mining_speed_modifier=0,worker_robots_battery_modifier=.1}
              for id,effects in pairs(historical.rows) do
                force.technologies[id]={valid=true,name=id,level=2,researched=false,enabled=true,visible_when_disabled=false,
                  saved_progress=0,prototype={hidden=false}}
                for _,effect in ipairs(effects) do
                  if effect.type=="change-recipe-productivity" then force.recipes[effect.recipe]={valid=true,productivity_bonus=0} end
                end
              end
              force.technologies[gear].level=force_index==1 and 3 or 1
              force.recipes["iron-gear-wheel"].productivity_bonus=force_index==1 and .2 or 0
              for index,id in ipairs(ids) do
                force.technologies[id]={valid=true,name=id,level=index<4 and 2 or 1,researched=false,enabled=false,
                  visible_when_disabled=false,saved_progress=0,prototype={hidden=true}}
              end
              for _,recipe in ipairs({"speed-module","productivity-module","efficiency-module"}) do
                force.recipes[recipe].productivity_bonus=.11
              end
              force.get_gun_speed_modifier=function(category)assert(category=="cannon-shell");return 0 end
              if force_index==2 then
                force.current_research=force.technologies[gear];force.research_progress=.42
                force.research_queue={force.technologies[gear],force.technologies["recipe-prod-research_plastic-1"]}
              elseif force_index==3 then force.technologies[gear].saved_progress=.27 end
              forces[name]=force
            end
            local game={forces=forces,players={},connected_players={},tick=0,saves={}}
            local function invalidate(node)
              if type(node)~="table" or node.type==nil then return end
              node.valid=false
              for _,child in pairs(node) do if type(child)=="table" and child.type then invalidate(child) end end
            end
            local function element(kind,name)
              local dimensions={}
              local style=setmetatable({}, {
                __index=function(_,key)
                  if key=="width" or key=="height" then error("write-only LuaStyle convenience attribute was read") end
                  return dimensions[key]
                end,
                __newindex=function(_,key,value)
                  if key=="width" then dimensions.minimal_width=value;dimensions.maximal_width=value
                  elseif key=="height" then dimensions.minimal_height=value;dimensions.maximal_height=value
                  else dimensions[key]=value end
                end,
              })
              local node={valid=true,type=kind,name=name,style=style}
              node.add=function(spec)
                local child=element(spec.type,spec.name);child.text=spec.text;node[spec.name]=child;return child
              end
              node.destroy=function()invalidate(node)end
              return node
            end
            local function connected()
              game.connected_players={}
              for _,p in pairs(game.players) do if p.connected then game.connected_players[#game.connected_players+1]=p end end
            end
            game.get_player=function(index)return game.players[index]end
            game.server_save=function(name)game.saves[#game.saves+1]=name end
            local en,de
            local function build(p,options)
              options=options or memory[p.index]
              local search=options.search or ""
              memory[p.index]={search=search,selected=options.selected,family=options.family,sort=options.sort}
              local root=p.gui.screen[root_name]
              if not root or not root.valid then
                root=element("frame",root_name);root.location=p.remembered_location or {x=200,y=100};root.style.width=1000
                root.get_mod=function()return opponent=="foreign-library-root" and "another-mod" or "more-infinite-research" end
                root.mir_library_filters=element("table","mir_library_filters")
                root.mir_library_filters.mir_library_query=element("textfield","mir_library_query")
                root.mir_library_filters.mir_library_family=element("drop-down","mir_library_family")
                root.mir_library_tabs=element("tabbed-pane","mir_library_tabs")
                p.gui.screen[root_name]=root
              end
              local filters=root.mir_library_filters
              filters.mir_library_query.text=search
              filters.mir_library_family.selected_index=options.family=="all" and 2 or (options.family=="external" and 3 or 1)
              local content=element("flow","mir_library_research_content")
              root.mir_library_tabs.mir_library_research_content=content
              local private=false;for _,id in ipairs(ids) do if search==id then private=true end end
              local present=not private
              if opponent=="private-listed" and private then present=true end
              if opponent=="empty-ordinary" and not private then present=false end
              content.mir_library_results=element("list-box","mir_library_results")
              content.mir_library_results.items=present and {search} or {}
              content.mir_library_results.selected_index=present and 1 or 0
              content.mir_library_detail=element("flow","mir_library_detail")
              content.mir_library_detail[present and "mir_library_detail_title" or "mir_library_detail_empty"]=element("label","label")
              content.mir_library_actions=element("flow","mir_library_actions")
              content.mir_library_actions.mir_library_open_native=element("button","mir_library_open_native")
              content.mir_library_actions.mir_library_open_native.enabled=present
              p.opened=root
              return root
            end
            local function query(p)return p.gui.screen[root_name].mir_library_filters.mir_library_query end
            local function join(index,locale)
              local p=game.players[index]
              if not p then
                p={valid=true,index=index,name=locale=="en" and "MIR5English" or "MIR5Deutsch",locale=locale,
                  connected=true,force=forces.player,gui={screen=element("screen","screen")},display_scale=1,
                  display_resolution={width=1280,height=720}}
                game.players[index]=p
              end
              p.connected=true;connected()
              callbacks.events[1]({player_index=index})
              return p
            end
            game.remove_offline_players=function(indices)
              assert(#indices==1 and indices[1]==de.index and not de.connected)
              if opponent=="removal-no-event" then return end
              local index=indices[1]
              for _,node in pairs(de.gui.screen) do invalidate(node) end
              de.valid=false;game.players[index]=nil
              callbacks.events[7]({player_index=index});connected()
            end
            forces.player.reset_technology_effects=function()
              resets=resets+1
              if opponent~="missing-reset-event" then callbacks.events[6]({force=forces.player}) end
              if resets==1 then
                if opponent=="native-effect-change" then forces.player.recipes["stone-wall"].productivity_bonus=.3 end
                if opponent=="foreign-queue-change" then forces["mir5-migration-origin-f200-110-foreign"].research_progress=.43 end
                if opponent=="replace-query" then
                  local old=query(en);local next=element("textfield","mir_library_query");next.text=old.text
                  en.gui.screen[root_name].mir_library_filters.mir_library_query=next
                end
                if opponent=="lose-query-focus" then en.focused=nil end
              elseif resets==2 then
                if opponent=="steal-other-focus" then en.opened={} end
                if opponent=="lose-other-focus" then en.focused=nil end
              end
            end
            local base=target=="f200" and "2.0.77" or "2.1.23"
            local active={base=base,["more-infinite-research"]=target=="f200" and "5.0.20000" or "5.0.21000",
              [historical.fixture]=target=="f200" and "0.3.0" or "0.4.0",
              ["mir-fixture-mir5-active-mods-observer"]="0.1.0",["mir-fixture-mir5-library-native-input"]="0.1.0"}
            local env={game=game,storage=store,defines={events=events},log=function()end,
              helpers={table_to_json=function()return "{}"end},
              require=function(name)assert(name=="__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue");return historical end,
              remote={add_interface=function(name,value)interfaces[name]=value end,
                call=function(name,method,index,options)
                  assert(name=="more-infinite-research-browser" and method=="open");calls=calls+1;build(game.players[index],options);return true
                end}}
            local function parse()
              callbacks={events={}}
              env.script={active_mods=active,on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,
                on_event=function(event,fn)callbacks.events[event]=fn end}
              setmetatable(env,{__index=_G});assert(loadfile(observer_path,"t",env))()
            end
            local function api()return interfaces["mir5-library-native-input"]end
            local function step(name)
              local value=api().advance(name);trace[#trace+1]=value;return value
            end
            local function click(p,node)
              p.focused=node
              if opponent~="missing-click-event" then callbacks.events[3]({player_index=p.index,element=node}) end
            end
            local function type_text(p,text)
              if not p.focused or not p.focused.valid then return end
              p.focused.text=p.focused.text..text
              callbacks.events[2]({player_index=p.index,element=p.focused})
            end
            local function key_close(p)
              local root=p.gui.screen[root_name]
              p.remembered_location={x=root.location.x,y=root.location.y}
              memory[p.index].search=query(p).text
              if opponent~="root-not-retired" then invalidate(root) end
              p.gui.screen[root_name]=nil;p.opened=nil;p.focused=nil
              if opponent~="missing-close-event" then callbacks.events[5]({player_index=p.index,element=root}) end
            end
            local readonly_report,readonly_load,cold_calls_before,cold_calls_after
            local ok,message=pcall(function()
              parse()
              if opponent=="wrong-initial-credit" then forces.player.technologies[ids[1]].level=1 end
              if opponent=="preexisting-player" then game.players[9]={} end
              if opponent=="extra-mod" then active.extra="1.0.0" end
              callbacks.init()
              local before=fingerprint(store);api().report();api().report();readonly_report=before==fingerprint(store)
              en=join(1,"en");de=join(2,"de")
              if opponent=="out-of-order" then step("prefix");return end
              step("inspect")
              click(en,query(en));type_text(en,"ge");step("prefix")
              if opponent~="short-refresh" then game.tick=game.tick+60 end
              step("refresh");type_text(en,"ars");step("suffix")
              local root=en.gui.screen[root_name];root.location={x=root.location.x-30,y=root.location.y}
              if opponent~="missing-drag-event" then callbacks.events[4]({player_index=en.index,element=root}) end
              step("drag");key_close(en);step("escape");key_close(en);step("inventory")
              local other=en.gui.screen.mir5_input_other.mir5_input_other_query
              click(en,other);type_text(en,"focus");step("foreign-prefix");game.tick=game.tick+60
              step("foreign-refresh");type_text(en," kept");step("foreign-suffix")
              if opponent~="remove-connected" then de.connected=false;connected() end
              step("remove-de");de=join(3,"de");step("replacement");game.tick=game.tick+60;step("save")
              en.connected=false;de.connected=false;connected()
              for _,p in pairs(game.players) do for _,node in pairs(p.gui.screen) do invalidate(node) end;p.gui.screen=element("screen","screen") end
              parse();before=fingerprint(store);callbacks.load();readonly_load=before==fingerprint(store)
              -- Native-shaped MIR join restoration, not an observer open call.
              build(en,memory[en.index]);build(de,memory[de.index]);join(1,"en");join(3,"de")
              if opponent=="cold-lost-query" then query(en).text="wrong" end
              if opponent=="cold-lost-location" then en.gui.screen[root_name].location={x=999,y=100} end
              cold_calls_before=calls
              step("restart");cold_calls_after=calls
              game.tick=game.tick+60;step("complete-save")
            end)
            return {ok=ok,message=tostring(message),trace=trace,saves=game.saves,readonly_report=readonly_report,
              readonly_load=readonly_load,resets=resets,calls=calls,cold_calls_before=cold_calls_before,cold_calls_after=cold_calls_after,
              final=store[key] and api().report(),native_input_evidence=false,final_calls=calls}
          end
        ''')

    def run_case(self, target="f210", opponent=None):
        return plain(self.lua.globals().run_input_observer(target, opponent))

    def test_imported_probe_and_actual_event_observer_keep_the_declared_finite_sequence(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                result = self.run_case(target)
                self.assertTrue(result["ok"], result["message"])
                self.assertTrue(result["readonly_report"])
                self.assertTrue(result["readonly_load"])
                self.assertFalse(result["native_input_evidence"])
                self.assertEqual(result["resets"], 2)
                self.assertEqual(result["saves"], ["mir5-library-native-input-restart", "mir5-library-native-input-complete"])
                final = result["final"]
                self.assertEqual((final["phase"], final["actual_joins"], final["private_queries"]), ("delivered", 5, 48))
                self.assertEqual((final["actual_library_closed_events"], final["actual_drag_events"], final["actual_removed_events"]), (2, 1, 1))
                self.assertTrue(final["imported_earnings"])
                self.assertFalse(final["fixture_seeds_credit"])
                self.assertTrue(final["load_observed"])
                self.assertEqual(final["en_geometry"]["location"], {"x": 170, "y": 100})

    def test_observer_rejects_missing_native_events_mutations_and_lost_cold_views(self):
        opponents = ("wrong-initial-credit", "preexisting-player", "extra-mod", "out-of-order", "private-listed", "empty-ordinary", "foreign-library-root",
                     "missing-click-event", "missing-reset-event", "native-effect-change", "foreign-queue-change", "replace-query",
                     "lose-query-focus", "short-refresh", "missing-drag-event", "root-not-retired", "missing-close-event",
                     "steal-other-focus", "lose-other-focus", "remove-connected", "removal-no-event", "cold-lost-query", "cold-lost-location")
        for target in ("f200", "f210"):
            for opponent in opponents:
                with self.subTest(target=target, opponent=opponent):
                    result = self.run_case(target, opponent)
                    self.assertFalse(result["ok"], result["message"])
                    self.assertFalse(result["native_input_evidence"])
                    if opponent in ("private-listed", "empty-ordinary", "foreign-library-root"):
                        self.assertFalse(result["final"]["readonly_imported_probe"])
                    if opponent.startswith("cold-"):
                        self.assertEqual(result["cold_calls_before"], result["final_calls"])
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        for forbidden in ("script.raise_event", "game.create_player", "__more-infinite-research__", "storage.mir", "technology.level ="):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(LibraryNativeInputFixtureControls))
    sys.exit(0 if result.wasSuccessful() else 1)
