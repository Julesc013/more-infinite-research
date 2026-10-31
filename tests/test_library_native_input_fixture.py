"""Independent input-observer controls with native-shaped doubles, not native input evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

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
    def test_input_metadata_keeps_required_versions_without_mir_runtime_order_edges(self):
        historical = "mir-fixture-mir5-migration-origin-f200-110-source"
        fixture = "mir-fixture-mir5-library-native-input"
        cases = {
            "f200": ("2.0.77", "5.0.20000", "0.3.0",
                      ROOT / "tests/profiles/library-native-input-imported110-f200-2077-r12.json",
                      FIXTURE / "info-input-identity-f200.json"),
            "f210": ("2.1.23", "5.0.21000", "0.4.0",
                      ROOT / "tests/profiles/library-native-input-imported110-f210-2123-r12.json",
                      FIXTURE / "info-input-identity-f210.json"),
        }
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn(f'require("__{historical}__/catalogue")', control)
        self.assertIn('script.active_mods["more-infinite-research"]', control)
        self.assertIn("script.active_mods[historical.fixture]", control)
        parser = ROOT / "tools/lib/compatibility/LibraryActivation.ps1"

        for target, (base, mir, source_version, profile_path, info_path) in cases.items():
            with self.subTest(target=target):
                info = json.loads(info_path.read_text(encoding="utf-8"))
                profile = json.loads(profile_path.read_text(encoding="utf-8"))
                expected_dependencies = [
                    f"base = {base}",
                    f"~ more-infinite-research = {mir}",
                    f"~ {historical} = {source_version}",
                ]
                self.assertEqual(info["dependencies"], expected_dependencies)
                self.assertEqual(
                    [(row["name"], row["version"], row["enabled"]) for row in profile["mods"]],
                    [
                        ("base", base, True),
                        ("mir-fixture-mir5-active-mods-observer", "0.1.0", True),
                        ("more-infinite-research", mir, True),
                        (historical, source_version, True),
                        (fixture, "0.3.0", True),
                    ],
                )
                # Factorio orders runtime handlers by dependency depth then natural
                # mod name.  The two order-neutral required rows leave this observer
                # at base depth, before MIR and the historical fixture.
                order = [
                    "base",
                    "mir-fixture-mir5-active-mods-observer",
                    fixture,
                    "more-infinite-research",
                    historical,
                ]
                self.assertLess(order.index(fixture), order.index("more-infinite-research"))
                self.assertLess(order.index(fixture), order.index(historical))

                def quote(path):
                    return str(path).replace("'", "''")

                command = f"""
                    $ErrorActionPreference = 'Stop'
                    . '{quote(parser)}'
                    $info = Get-Content -Raw -LiteralPath '{quote(info_path)}' | ConvertFrom-Json -AsHashtable
                    $profile = Get-Content -Raw -LiteralPath '{quote(profile_path)}' | ConvertFrom-Json -AsHashtable
                    $rows = @($info.dependencies | ForEach-Object {{ ConvertFrom-MIRDependencyString -Dependency $_ }})
                    if ($rows.Count -ne 3 -or $rows[0].kind -cne 'required' -or -not $rows[0].required) {{ throw 'base dependency is not required' }}
                    foreach ($row in @($rows[1], $rows[2])) {{
                      if ($row.kind -cne 'no_order' -or -not $row.required) {{ throw 'order-neutral dependency is not required' }}
                    }}
                    $selected = [Collections.Generic.List[object]]::new()
                    foreach ($row in @($profile.mods)) {{
                      $metadata = if ($row.name -ceq '{fixture}') {{ $info }} else {{ @{{ dependencies = @() }} }}
                      $selected.Add([pscustomobject]@{{ name = $row.name; version = $row.version; info = $metadata }})
                    }}
                    Assert-MIRLibraryDependencies -Selected $selected.ToArray()
                """
                completed = subprocess.run(
                    ["pwsh", "-NoProfile", "-NonInteractive", "-Command", command],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)

    def test_order_neutral_input_archives_use_the_canonical_two_member_policy(self):
        record = json.loads(
            (ROOT / "spec/evidence/library-input-order-neutral-prepared-r01.json").read_text(encoding="utf-8")
        )
        fixture = "mir-fixture-mir5-library-native-input_0.3.0"
        cases = {
            "f200": "tests/fixtures/library-native-input/info-input-identity-f200.json",
            "f210": "tests/fixtures/library-native-input/info-input-identity-f210.json",
        }
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()

        def raw_git_head(path):
            return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT)

        def write_archive(output, members):
            with zipfile.ZipFile(
                output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
            ) as archive:
                for destination, contents in members:
                    entry = zipfile.ZipInfo(
                        f"{fixture}/{destination}", date_time=(1980, 1, 1, 0, 0, 0)
                    )
                    entry.create_system = 3
                    entry.external_attr = 0o100644 << 16
                    entry.compress_type = zipfile.ZIP_DEFLATED
                    archive.writestr(entry, contents, compresslevel=9)

        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            for target, info_source in cases.items():
                with self.subTest(target=target):
                    profile = next(
                        row
                        for row in record["profiles"]
                        if row["target"] == target and row["mode"] == "input"
                    )
                    members = {row["destination"]: row for row in profile["owned_fixture"]["members"]}
                    self.assertEqual(set(members), {"control.lua", "info.json"})
                    self.assertEqual(members["control.lua"]["source"], "tests/fixtures/library-native-input/control.lua")
                    self.assertEqual(members["info.json"]["source"], info_source)
                    control = raw_git_head(members["control.lua"]["source"])
                    info = raw_git_head(members["info.json"]["source"])
                    for destination, contents in (("control.lua", control), ("info.json", info)):
                        self.assertEqual(len(contents), members[destination]["bytes"])
                        self.assertEqual(
                            hashlib.sha256(contents).hexdigest().upper(),
                            members[destination]["sha256"],
                        )

                    output = temporary / f"{target}.zip"
                    write_archive(output, (("control.lua", control), ("info.json", info)))
                    raw = output.read_bytes()
                    self.assertEqual(len(raw), profile["owned_fixture"]["bytes"])
                    self.assertEqual(
                        hashlib.sha256(raw).hexdigest().upper(), profile["owned_fixture"]["sha256"]
                    )
                    self.assertEqual(
                        profile["archive_sha256"]["mir-fixture-mir5-library-native-input_0.3.0.zip"],
                        profile["owned_fixture"]["sha256"],
                    )
                    with zipfile.ZipFile(output) as archive:
                        infos = archive.infolist()
                        self.assertEqual(
                            [entry.filename for entry in infos],
                            [f"{fixture}/control.lua", f"{fixture}/info.json"],
                        )
                        for entry in infos:
                            self.assertEqual(entry.date_time, (1980, 1, 1, 0, 0, 0))
                            self.assertEqual(entry.create_system, 3)
                            self.assertEqual(entry.external_attr, 0o100644 << 16)
                            self.assertEqual(entry.compress_type, zipfile.ZIP_DEFLATED)
                    if target == "f200":
                        self.assertEqual(len(raw), 7996)
                        self.assertEqual(
                            hashlib.sha256(raw).hexdigest().upper(),
                            "6BD418D9EE0B6DE418B1C6BD8835B8E405779F250EB637221AED2B5F451B9C38",
                        )
                        crlf_checkout = temporary / "crlf-checkout-control.lua"
                        crlf_checkout.write_bytes(control.replace(b"\n", b"\r\n"))
                        self.assertNotEqual(crlf_checkout.read_bytes(), control)
                        crlf_output = temporary / "f200-crlf-checkout.zip"
                        write_archive(
                            crlf_output,
                            (("control.lua", crlf_checkout.read_bytes()), ("info.json", info)),
                        )
                        self.assertNotEqual(crlf_output.read_bytes(), raw)

    def test_support_export_report_tick_profiles_cross_bind_canonical_raw_archives(self):
        record = json.loads(
            (ROOT / "spec/evidence/library-support-exports-report-tick-prepared-r01.json").read_text(encoding="utf-8")
        )
        fixture = "mir-fixture-mir5-library-native-input_0.4.0"
        self.assertEqual(record["fixture_implementation_commit"], "7122f73ee9ae50dc395e7b6d295ea7fda3e24117")

        def raw_git(revision, path):
            return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT)

        def canonical_archive(output, members):
            with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
                for member, contents in members:
                    entry = zipfile.ZipInfo(
                        f"{fixture}/{member['destination']}", date_time=(1980, 1, 1, 0, 0, 0)
                    )
                    entry.create_system = 3
                    entry.external_attr = 0o100644 << 16
                    entry.compress_type = zipfile.ZIP_DEFLATED
                    archive.writestr(entry, contents, compresslevel=9)

        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            for row in record["profiles"]:
                with self.subTest(target=row["target"]):
                    profile_path = ROOT / row["profile"]["path"]
                    profile_raw = profile_path.read_bytes()
                    profile = json.loads(profile_raw)
                    owned = row["owned_fixture"]
                    self.assertEqual(len(profile_raw), row["profile"]["bytes"])
                    self.assertEqual(hashlib.sha256(profile_raw).hexdigest().upper(), row["profile"]["sha256"])
                    self.assertEqual(profile["archive_sha256"], row["archive_sha256"])
                    self.assertEqual(profile["archive_sha256"][owned["name"]], owned["sha256"])
                    self.assertEqual([member["destination"] for member in owned["members"]], [
                        "control.lua", "support-exports.lua", "info.json"
                    ])
                    contents = []
                    for member in owned["members"]:
                        self.assertEqual(member["source_revision"], record["fixture_implementation_commit"])
                        blob = subprocess.check_output(
                            ["git", "rev-parse", f"{member['source_revision']}:{member['source']}"],
                            cwd=ROOT,
                            text=True,
                        ).strip()
                        raw = raw_git(member["source_revision"], member["source"])
                        self.assertEqual(blob, member["git_blob"])
                        self.assertEqual(len(raw), member["bytes"])
                        self.assertEqual(hashlib.sha256(raw).hexdigest().upper(), member["sha256"])
                        contents.append((member, raw))
                    output = temporary / f"{row['target']}.zip"
                    canonical_archive(output, contents)
                    archive_raw = output.read_bytes()
                    self.assertEqual(len(archive_raw), owned["bytes"])
                    self.assertEqual(hashlib.sha256(archive_raw).hexdigest().upper(), owned["sha256"])
                    with zipfile.ZipFile(output) as archive:
                        infos = archive.infolist()
                        self.assertEqual(
                            [entry.filename for entry in infos],
                            [f"{fixture}/{member['destination']}" for member in owned["members"]],
                        )
                        for entry in infos:
                            self.assertEqual(entry.date_time, (1980, 1, 1, 0, 0, 0))
                            self.assertEqual(entry.create_system, 3)
                            self.assertEqual(entry.external_attr, 0o100644 << 16)
                            self.assertEqual(entry.compress_type, zipfile.ZIP_DEFLATED)

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
                  display_resolution={width=1280,height=720},controller_type=locale=="en" and 7 or 11}
                game.players[index]=p
              end
              if opponent=="controller-type-non-scalar" and locale=="de" then p.controller_type="cutscene" end
              p.connected=true;connected()
              if locale=="de" and (opponent=="pending-locale" or opponent=="locale-never-ready") then p.locale="en" end
              if opponent=="unexpected-client-name" and locale=="de" then p.name="UnexpectedDeutsch" end
              callbacks.events[1]({player_index=index})
              if locale=="de" and opponent=="pending-locale" then
                local observed=interfaces["mir5-library-native-input"].report()
                assert(observed.en_index==0 and observed.de_index==index and observed.de_locale=="en")
                p.locale="de"
              end
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
              ["mir-fixture-mir5-active-mods-observer"]="0.1.0",["mir-fixture-mir5-library-native-input"]="0.3.0"}
            local env={game=game,storage=store,defines={events=events,gui_type={custom=99},controllers={character=7,cutscene=11}},log=function()end,
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
              local event_element=root
              if opponent=="invalid-close-element" then event_element={valid=false}
              elseif opponent=="absent-close-element" then event_element=nil
              elseif opponent=="wrong-close-element" then event_element=element("frame","unrelated") end
              if opponent~="missing-close-event" then callbacks.events[5]({
                player_index=opponent=="wrong-close-player" and de.index or p.index,
                gui_type=opponent=="wrong-close-type" and 1 or 99,element=event_element}) end
              if opponent=="duplicate-close-event" then callbacks.events[5]({player_index=p.index,gui_type=99,element=root}) end
            end
            local readonly_report,readonly_load,cold_calls_before,cold_calls_after,initial_report,missing_query_report,missing_query_readonly,opened_getter_report,opened_getter_readonly
            local ok,message=pcall(function()
              parse()
              if opponent=="wrong-initial-credit" then forces.player.technologies[ids[1]].level=1 end
              if opponent=="preexisting-player" then game.players[9]={} end
              if opponent=="extra-mod" then active.extra="1.0.0" end
              callbacks.init()
              local before=fingerprint(store);initial_report=api().report();api().report();readonly_report=before==fingerprint(store)
              en=join(0,"en");de=join(2,"de")
              if opponent=="duplicate-initial-join" then join(0,"en") end
              if opponent=="out-of-order" then step("prefix");return end
              step("inspect")
              if opponent=="join-during-input" then join(2,"de") end
              if opponent=="observe-missing-query" then
                local filters=en.gui.screen[root_name].mir_library_filters;local saved=filters.mir_library_query
                filters.mir_library_query=nil;local before=fingerprint(store);missing_query_report=api().report()
                missing_query_readonly=before==fingerprint(store);filters.mir_library_query=saved
              end
              if opponent=="observe-opened-getter-error" then
                local saved=en.opened;en.opened=nil
                setmetatable(en,{__index=function(_,key)if key=="opened" then error("fixture opened getter") end end})
                local before=fingerprint(store);opened_getter_report=api().report()
                opened_getter_readonly=before==fingerprint(store);setmetatable(en,nil);en.opened=saved
              end
              if opponent=="settled-before-drag" or opponent=="pre-drag-event-only" then
                local root=en.gui.screen[root_name];root.location={x=265,y=24}
                callbacks.events[4]({player_index=en.index,element=root})
              end
              click(en,query(en));type_text(en,"ge");step("prefix")
              if opponent~="short-refresh" then game.tick=game.tick+60 end
              step("refresh");type_text(en,"ars");step("suffix")
              local root=en.gui.screen[root_name];root.location={x=root.location.x-30,y=root.location.y}
              if opponent=="wrong-drag-x" then root.location.x=root.location.x+1 end
              if opponent=="wrong-drag-y" then root.location.y=root.location.y+1 end
              if opponent~="missing-drag-event" and opponent~="pre-drag-event-only" then callbacks.events[4]({player_index=en.index,element=root}) end
              if opponent=="multiple-drag-events" then callbacks.events[4]({player_index=en.index,element=root}) end
              if opponent=="unarmed-close-event" then callbacks.events[5]({player_index=en.index,gui_type=99,element={valid=false}}) end
               if opponent=="opened-nil" then en.opened=nil
               elseif opponent=="opened-foreign" then
                 local foreign=element("frame","foreign-opened");foreign.get_mod=function()return "fixture"end;en.opened=foreign
               end
              step("drag");key_close(en);step("escape");key_close(en);step("inventory")
              local other=en.gui.screen.mir5_input_other.mir5_input_other_query
              click(en,other);type_text(en,"focus");step("foreign-prefix");game.tick=game.tick+60
              step("foreign-refresh");type_text(en," kept");step("foreign-suffix")
              if opponent~="remove-connected" then de.connected=false;connected() end
              step("remove-de");de=join(opponent=="removed-index-reused" and 2 or 3,"de");step("replacement");game.tick=game.tick+60;step("save")
              en.connected=false;de.connected=false;connected()
              for _,p in pairs(game.players) do for _,node in pairs(p.gui.screen) do invalidate(node) end;p.gui.screen=element("screen","screen") end
              parse();before=fingerprint(store);callbacks.load();readonly_load=before==fingerprint(store)
              -- Native-shaped MIR join restoration, not an observer open call.
              build(en,memory[en.index]);build(de,memory[de.index]);join(opponent=="changed-restart-index" and 4 or 0,"en")
              if opponent=="duplicate-restart-role" then join(0,"en") end
              join(3,"de")
              if opponent=="cold-lost-query" then query(en).text="wrong" end
              if opponent=="cold-lost-location" then en.gui.screen[root_name].location={x=999,y=100} end
              cold_calls_before=calls
              step("restart");cold_calls_after=calls
              game.tick=game.tick+60;step("complete-save")
            end)
            return {ok=ok,message=tostring(message),trace=trace,saves=game.saves,readonly_report=readonly_report,
              initial_report=initial_report,missing_query_report=missing_query_report,missing_query_readonly=missing_query_readonly,
              opened_getter_report=opened_getter_report,opened_getter_readonly=opened_getter_readonly,
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

    def test_readonly_reports_expose_actual_library_and_foreign_input_state(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                result = self.run_case(target)
                self.assertTrue(result["ok"], result["message"])
                self.assertTrue(result["readonly_report"])
                self.assertTrue(result["readonly_load"])
                self.assertIs(result["initial_report"]["en_input"], False)
                self.assertIs(result["initial_report"]["de_input"], False)
                self.assertEqual((result["initial_report"]["en_controller_type"], result["initial_report"]["de_controller_type"]), (False, False))
                self.assertEqual(result["initial_report"]["controller_constants"], {"character": 7, "cutscene": 11})
                phases = {row["phase"]: row for row in result["trace"]}
                initial = phases["text-prefix"]
                self.assertEqual(initial["en_input"], {"library_open": True, "library_query": "", "foreign_open": False, "foreign_query": False,
                                                       "opened_kind": "table", "opened_is_library_root": True})
                self.assertEqual((initial["en_controller_type"], initial["de_controller_type"]), (7, 11))
                self.assertEqual(initial["controller_constants"], {"character": 7, "cutscene": 11})
                self.assertEqual(initial["de_input"]["library_query"], "recipe-prod-research_mining_drill-1")
                self.assertEqual((initial["de_input"]["opened_kind"], initial["de_input"]["opened_is_library_root"]), ("table", True))
                self.assertEqual(phases["prefix-refresh"]["en_input"]["library_query"], "ge")
                self.assertEqual(phases["drag"]["en_input"]["library_query"], "gears")
                foreign = phases["foreign-prefix"]["en_input"]
                self.assertEqual(foreign, {"library_open": False, "library_query": False, "foreign_open": True, "foreign_query": "",
                                           "opened_kind": "table", "opened_is_library_root": False})
                self.assertEqual(phases["foreign-refresh"]["en_input"]["foreign_query"], "focus")
                self.assertEqual(phases["foreign-suffix"]["en_input"]["foreign_query"], "focus")
                restored = phases["disconnect-de"]["en_input"]
                self.assertEqual(restored, {"library_open": True, "library_query": "gears", "foreign_open": False, "foreign_query": False,
                                            "opened_kind": "table", "opened_is_library_root": True})

    def test_inspect_opened_snapshots_are_transient_readonly_observations(self):
        expected_private_query = "mir-legacy-cannon-credit-rocket-shooting-speed"
        expected_input = lambda query: {
            "library_open": True,
            "library_query": query,
            "foreign_open": False,
            "foreign_query": False,
            "opened_kind": "table",
            "opened_is_library_root": True,
        }
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                result = self.run_case(target)
                self.assertTrue(result["ok"], result["message"])
                inspect = next(row for row in result["trace"] if row["phase"] == "text-prefix")
                snapshots = inspect["inspect_opened_snapshots"]
                self.assertEqual(
                    snapshots,
                    {
                        "after_exclusion_probe": {"tick": 0, "en_input": expected_input(expected_private_query), "de_input": expected_input(expected_private_query), "en_controller_type": 7, "de_controller_type": 11},
                        "after_final_open_en": {"tick": 0, "en_input": expected_input(""), "de_input": expected_input(expected_private_query), "en_controller_type": 7, "de_controller_type": 11},
                        "after_final_open_de": {"tick": 0, "en_input": expected_input(""), "de_input": expected_input("recipe-prod-research_mining_drill-1"), "en_controller_type": 7, "de_controller_type": 11},
                    },
                )
                self.assertEqual((inspect["en_controller_type"], inspect["de_controller_type"]), (7, 11))
                invalid = self.run_case(target, "controller-type-non-scalar")
                self.assertTrue(invalid["ok"], invalid["message"])
                invalid_inspect = next(row for row in invalid["trace"] if row["phase"] == "text-prefix")
                self.assertTrue(all(row["en_controller_type"] == 7 and row["de_controller_type"] is False
                                    for row in invalid_inspect["inspect_opened_snapshots"].values()))
                self.assertEqual((invalid_inspect["en_controller_type"], invalid_inspect["de_controller_type"]), (7, False))
                self.assertIs(result["final"]["inspect_opened_snapshots"], False)
                self.assertEqual((result["final"]["private_queries"], result["calls"]), (48, 69))

    def test_report_distinguishes_missing_textfield_and_foreign_open_identity(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                missing = self.run_case(target, "observe-missing-query")
                self.assertTrue(missing["ok"], missing["message"])
                self.assertTrue(missing["missing_query_readonly"])
                self.assertIs(missing["missing_query_report"]["en_input"]["library_query"], False)
                self.assertIs(missing["missing_query_report"]["en_input"]["library_open"], True)
                self.assertEqual((missing["missing_query_report"]["en_input"]["opened_kind"],
                                  missing["missing_query_report"]["en_input"]["opened_is_library_root"]), ("table", True))
                getter = self.run_case(target, "observe-opened-getter-error")
                self.assertTrue(getter["ok"], getter["message"])
                self.assertTrue(getter["opened_getter_readonly"])
                self.assertEqual((getter["opened_getter_report"]["en_input"]["opened_kind"],
                                  getter["opened_getter_report"]["en_input"]["opened_is_library_root"]),
                                 ("getter-error", False))
                stolen = self.run_case(target, "steal-other-focus")
                self.assertFalse(stolen["ok"], stolen["message"])
                self.assertIs(stolen["final"]["en_input"]["foreign_open"], False)
                self.assertEqual(stolen["final"]["en_input"]["foreign_query"], "focus")

    def test_drag_uses_the_last_observed_location_and_requires_new_events(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                result = self.run_case(target, "settled-before-drag")
                self.assertTrue(result["ok"], result["message"])
                final = result["final"]
                self.assertEqual(final["initial_location"], {"x": 200, "y": 100})
                self.assertEqual(final["drag_baseline"], {"x": 265, "y": 24})
                self.assertEqual(final["drag_events_before"], 1)
                self.assertEqual(final["actual_drag_events"], 2)
                self.assertEqual(final["en_geometry"]["location"], {"x": 235, "y": 24})
                self.assertTrue(result["readonly_report"])
                multiple = self.run_case(target, "multiple-drag-events")
                self.assertTrue(multiple["ok"], multiple["message"])
                self.assertEqual(multiple["final"]["drag_events_before"], 0)
                self.assertEqual(multiple["final"]["actual_drag_events"], 2)
                self.assertEqual(multiple["final"]["en_geometry"]["location"], {"x": 170, "y": 100})
                for opponent in ("pre-drag-event-only", "wrong-drag-x", "wrong-drag-y"):
                    with self.subTest(opponent=opponent):
                        rejected = self.run_case(target, opponent)
                        self.assertFalse(rejected["ok"], rejected["message"])
                        self.assertIn("actual native drag differs: baseline=", rejected["message"])
                        self.assertEqual(rejected["final"]["phase"], "drag")
                        self.assertEqual(rejected["saves"], {})

    def test_custom_close_observes_retired_elements_without_losing_event_requirement(self):
        for target in ("f200", "f210"):
            for opponent in ("invalid-close-element", "absent-close-element", "duplicate-close-event", "unarmed-close-event"):
                with self.subTest(target=target, opponent=opponent):
                    result = self.run_case(target, opponent)
                    self.assertTrue(result["ok"], result["message"])
                    self.assertEqual(result["final"]["actual_library_closed_events"], 2)
                    observations = result["final"]["actual_library_close_observations"]
                    self.assertEqual([row["ordinal"] for row in observations], [1, 2])
                    self.assertTrue(all(row["accepted"] for row in observations))
                    if opponent in ("invalid-close-element", "absent-close-element"):
                        self.assertTrue(all(not row["element_valid"] for row in observations))
            for opponent in ("missing-close-event", "wrong-close-player", "wrong-close-type", "wrong-close-element", "root-not-retired"):
                with self.subTest(target=target, opponent=opponent):
                    result = self.run_case(target, opponent)
                    self.assertFalse(result["ok"], result["message"])
                    self.assertIn("actual key did not retire", result["message"])
                    self.assertEqual(result["saves"], {})

    def test_armed_close_retains_raw_scalars_before_player_phase_and_custom_type_filters(self):
        for target in ("f200", "f210"):
            for opponent, actual_player, actual_name, actual_type in (
                ("wrong-close-type", 0, "MIR5English", 1),
                ("wrong-close-player", 2, "MIR5Deutsch", 99),
            ):
                with self.subTest(target=target, opponent=opponent):
                    result = self.run_case(target, opponent)
                    self.assertFalse(result["ok"], result["message"])
                    self.assertEqual(result["final"]["phase"], "escape")
                    self.assertEqual(result["final"]["close_expected"], {"phase": "escape", "player_index": 0, "ordinal": 1})
                    observations = result["final"]["actual_library_close_observations"]
                    self.assertEqual(len(observations), 1)
                    row = observations[0]
                    self.assertEqual(
                        (row["phase"], row["armed_phase"], row["player_index"], row["player_lookup_ok"], row["player_name"], row["armed_player_index"], row["ordinal"]),
                        ("escape", "escape", actual_player, True, actual_name, 0, 1),
                    )
                    self.assertIsInstance(row["tick"], int)
                    self.assertEqual((row["gui_type"], row["expected_gui_type"], row["element_type"], row["element_name"]),
                                     (actual_type, 99, "table", "mir_research_browser"))
                    self.assertTrue(row["element_present"])
                    self.assertFalse(row["accepted"])

    def test_arm_close_retains_safe_opened_scalars_when_ownership_is_absent(self):
        expected = {
            "opened-nil": (("opened_type=nil", "opened_is_root=false", "opened_name=<absent>", "opened_mod=<absent>"),
                           ("nil", False)),
            "opened-foreign": (("opened_type=table", "opened_is_root=false", "opened_name=foreign-opened", "opened_mod=fixture"),
                               ("table", False)),
        }
        for target in ("f200", "f210"):
            for opponent, (scalars, report_state) in expected.items():
                with self.subTest(target=target, opponent=opponent):
                    result = self.run_case(target, opponent)
                    self.assertFalse(result["ok"], result["message"])
                    self.assertIn("declared key close has no owned opened Library:", result["message"])
                    for scalar in scalars:
                        self.assertIn(scalar, result["message"])
                    self.assertEqual((result["final"]["en_input"]["opened_kind"],
                                      result["final"]["en_input"]["opened_is_library_root"]), report_state)
                    self.assertEqual(result["final"]["phase"], "escape")
                    self.assertEqual(result["final"]["actual_library_closed_events"], 0)
                    self.assertEqual(result["saves"], {})

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

    def test_join_identity_survives_pending_german_locale_with_zero_english_index(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                result = self.run_case(target, "pending-locale")
                self.assertTrue(result["ok"], result["message"])
                self.assertIs(type(result["final"]["en_index"]), int)
                self.assertEqual(result["final"]["en_index"], 0)
                self.assertEqual(result["final"]["actual_joins"], 5)

    def test_pending_locale_and_unknown_name_cannot_pass_inspection(self):
        for target in ("f200", "f210"):
            for opponent in ("locale-never-ready", "unexpected-client-name"):
                with self.subTest(target=target, opponent=opponent):
                    result = self.run_case(target, opponent)
                    self.assertFalse(result["ok"], result["message"])
                    self.assertEqual(result["final"]["private_queries"], 0)

    def test_join_phase_and_retained_identity_are_required(self):
        for target in ("f200", "f210"):
            for opponent in ("duplicate-initial-join", "join-during-input", "removed-index-reused",
                             "changed-restart-index", "duplicate-restart-role"):
                with self.subTest(target=target, opponent=opponent):
                    result = self.run_case(target, opponent)
                    self.assertFalse(result["ok"], result["message"])


class LibrarySupportExportObserverControls(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().support_path = (FIXTURE / "support-exports.lua").as_posix()
        self.lua.globals().fingerprint = lambda value: json.dumps(plain(value), sort_keys=True)
        self.lua.execute(r'''
          function run_export_observer(target,opponent)
            local key="mir5_library_native_input"
            local base=target=="f200"and"2.0.77"or"2.1.23"
            local mir=target=="f200"and"5.0.20000"or"5.0.21000"
            local original="mir-fixture-mir5-migration-origin-f200-110-source"
            local fixture=target=="f200"and"0.3.0"or"0.4.0"
            local callbacks,interfaces,store,players,decoded={},{},{},{},{}
            local native,logs,saves,write_calls=1,0,0,0
            local env={storage=store,settings={startup={disabled={value=false},zero={value=0},normal={value=15}}}}
            env._G=env;setmetatable(env,{__index=_G})
            local game={players={},connected_players={},forces={player={}},tick=0}
            env.game=game
            function game.get_player(index)assert(index~=nil);return players[index]end
            function game.server_save(name)assert(name=="mir5-library-support-exports-restart"or name=="mir5-native-complete");saves=saves+1 end
            local function node(parent,spec,mod)
              local value={valid=true,type=spec.type,name=spec.name,parent=parent,tags=spec.tags or{},children={},style={},
                location={x=140,y=16},text=spec.text,read_only=spec.read_only}
              if parent then parent[spec.name]=value;parent.children[#parent.children+1]=value end
              function value.get_mod()return mod end
              function value.add(s)return node(value,s,mod)end
              function value.destroy()
                value.valid=false
                for _,child in ipairs(value.children)do if child.valid then child.destroy()end end
                if parent and parent[value.name]==value then parent[value.name]=nil end
              end
              return value
            end
            local function player(index,locale)
              local p={index=index,locale=locale,name=locale=="en"and"MIR5English"or"MIR5Deutsch",valid=true,connected=true,force=game.forces.player,
                display_scale=1,display_resolution={width=1280,height=720},gui={screen=node(nil,{type="screen",name="screen"},"fixture")}}
              players[index]=p;return p
            end
            local function browser(index,options)
              local p=players[index];local root=p.gui.screen.mir_research_browser
              if not root then
                root=node(p.gui.screen,{type="frame",name="mir_research_browser",tags={["more-infinite-research.library-root.v1"]=true}},"more-infinite-research")
                local tabs=node(root,{type="tabbed-pane",name="mir_library_tabs"},"more-infinite-research")
                local settings=node(tabs,{type="flow",name="mir_library_settings_content"},"more-infinite-research")
                local toolbar=node(settings,{type="flow",name="mir_library_settings_toolbar"},"more-infinite-research")
                for _,name in ipairs({"settings","compact"})do node(toolbar,{type="button",name="mir_library_export_"..name},"more-infinite-research")end
                local help=node(tabs,{type="flow",name="mir_library_help_content"},"more-infinite-research")
                node(help,{type="button",name="mir_library_export_diagnostics"},"more-infinite-research")
              end
              root.mir_library_tabs.selected_tab_index=options.tab=="help"and 4 or 3
              return true
            end
            env.helpers={table_to_json=function()return"host-only projection"end,decode_string=function(x)return x end,
              json_to_table=function(x)return decoded[x]end,write_file=function()write_calls=write_calls+1;error("observer must not write export files")end}
            env.remote={add_interface=function(n,m)interfaces[n]=m end,call=function(n,method,...)
              if n=="more-infinite-research-browser"then return browser(...)end
              assert(n=="more-infinite-research-settings"and method=="validate_string")
              return{valid=opponent~="invalid-profile",recognized=2,invalid=0,unknown=0}
            end}
            env.log=function()logs=logs+1 end
            env.defines={events={on_player_joined_game=1,on_gui_click=2,on_console_command=3}}
            env.script={active_mods={base=base,["more-infinite-research"]=mir,[original]=fixture,
              ["mir-fixture-mir5-active-mods-observer"]="0.1.0",["mir-fixture-mir5-library-native-input"]="0.4.0"},
              on_init=function(f)callbacks.init=f end,on_load=function(f)callbacks.load=f end,
              on_event=function(id,f)callbacks[id]=f end}
            local context={key=key,interface="mir5-library-native-input",historical_fixture=original,
              world=function()return{serial=native}end,
              assert_world=function()assert(store[key].native.serial==native,"protected native state changed")end,
              imported=function()assert(native==1,"actual imported credit changed")end}
            local function register()
              assert(loadfile(support_path,"t",env))().register(context)
              return interfaces[context.interface]
            end
            local api=register();callbacks.init();assert(api.report().phase=="ready")
            local en,de=player(0,"en"),player(2,"de")
            game.players,game.connected_players={[0]=en,[2]=de},{en,de}
            local function joined(index)
              local p=players[index]
              if p==de and (opponent=="pending-locale"or opponent=="locale-never-ready")then p.locale="en"end
              if p==de and opponent=="unexpected-client-name"then p.name="UnexpectedDeutsch"end
              callbacks[1]({player_index=index})
              if p==de and opponent=="pending-locale"then
                assert(api.report().geometry.de.index==2 and api.report().geometry.de.locale=="en")
                p.locale="de"
              end
            end
            if opponent=="reverse-role-order"then
              joined(2);joined(0)
            else joined(0);joined(2)end
            if opponent=="duplicate-initial-join"then joined(0)end
            local sequence={"en-full","en-compact","en-diagnostics","de-full","de-compact","de-diagnostics",
              "en-foreign","en-full-before-failure","en-settings-failure","en-diagnostics-before-failure",
              "en-diagnostics-failure","de-rejoin-full","en-restart-full"}
            for index,action in ipairs(sequence)do
              if action=="en-foreign"then en.gui.screen.mir_research_browser.destroy()end -- Host simulation of a separately required actual key.
              if index==1 and opponent=="early-server-commands"then
                callbacks[3]({command="mir-settings-export"});callbacks[3]({command="mir-diagnostics-export"})
              end
              if index==5 and opponent=="early-rejoin"then joined(2)end
              if action=="de-rejoin-full"and opponent~="missing-rejoin"and opponent~="duplicate-initial-join"and opponent~="early-rejoin"then
                joined(opponent=="wrong-role-rejoin"and 0 or 2)
                if opponent=="duplicate-rejoin"then joined(2)end
              end
              if action=="en-restart-full"then
                if opponent~="early-server-commands"then
                  callbacks[3]({command="mir-settings-export",player_index=opponent=="zero-server-index"and 0 or nil})
                  callbacks[3]({command=opponent=="duplicate-settings-command"and"mir-settings-export"or"mir-diagnostics-export"})
                end
                api.checkpoint()
                if opponent=="missing-restart"then store[key].phase="ready"else
                  api=register();local saved=env.game;env.game=setmetatable({},{__index=function()error("on_load game access")end})
                  local before=fingerprint(store);callbacks.load();assert(fingerprint(store)==before);env.game=saved
                  if opponent=="post-load-server-command"then callbacks[3]({command="mir-settings-export"})end
                  if opponent=="reverse-role-order"then
                    joined(2);joined(0)
                  else
                    joined(0)
                    if opponent~="duplicate-rejoin"then joined(opponent=="duplicate-restart-role"and 0 or 2)end
                  end
                end
              end
              api.prepare(action)
              local p=action:sub(1,2)=="en"and en or de
              local root=p.gui.screen.mir_research_browser
              local button,content,kind
              if action=="en-foreign"then button=p.gui.screen.mir_export_foreign.mir_library_export_settings
              else
                local help=action:find("diagnostics",1,true)~=nil
                content=root.mir_library_tabs[help and"mir_library_help_content"or"mir_library_settings_content"]
                kind=help and"diagnostics"or(action:find("compact",1,true)and"compact"or"full")
                button=(help and content or content.mir_library_settings_toolbar)["mir_library_export_"..(kind=="full"and"settings"or kind)]
                local old=content.mir_library_export_profile
                if old and opponent~="stale-preview"then old.destroy()end
                if action~="en-settings-failure"and action~="en-diagnostics-failure"then
                  local token=p.locale.."-"..index
                  local values=kind=="compact"and{}or{disabled=false,zero=0,normal=15}
                  if opponent=="false-zero"then values.zero=false end
                  decoded[token]={metadata={exported_by=opponent=="wrong-user"and"other"or p.name,mir_version=mir},settings=values}
                  node(content,{type="text-box",name="mir_library_export_profile",text="MIRSET1:"..token,read_only=opponent~="editable"},"more-infinite-research")
                end
              end
              if opponent=="native-mutation"then native=2 end
              if opponent=="setting-mutation"then env.settings.startup.zero.value=1 end
              if opponent~="missing-click"then callbacks[2]({element=button,player_index=opponent=="wrong-player"and 3 or p.index})end
              if opponent=="duplicate-click"then callbacks[2]({element=button,player_index=p.index})end
              api.check(action)
            end
            local before=fingerprint(store);local result=api.report();local first_tick=result.tick
            game.tick=game.tick+1
            local second=api.report();assert(fingerprint(store)==before)
            assert(type(first_tick)=="number" and type(second.tick)=="number" and second.tick==first_tick+1)
            assert(result.phase=="completed"and result.actual_clicks==13 and result.actual_joins==5 and saves==2 and logs==13 and write_calls==0)
            assert(result.server_commands==2 and result.server_command_counts["mir-settings-export"]==1
              and result.server_command_counts["mir-diagnostics-export"]==1)
            assert(result.joins_by_phase.initial.en==1 and result.joins_by_phase.initial.de==1
              and result.joins_by_phase.rejoin.en==0 and result.joins_by_phase.rejoin.de==1
              and result.joins_by_phase.restart.en==1 and result.joins_by_phase.restart.de==1)
            if opponent=="report-clock" then return first_tick,second.tick end
            return result.actual_clicks,result.actual_joins,saves,write_calls
          end
        ''')

    def test_export_sequence_uses_real_event_observations_and_read_only_restart_contract(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.assertEqual(self.lua.globals().run_export_observer(target, ""), (13, 5, 2, 0))

    def test_export_report_tick_is_monotonic_and_read_only(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.assertEqual(self.lua.globals().run_export_observer(target, "report-clock"), (0, 1))

    def test_initial_and_restart_roles_can_arrive_in_either_order(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.assertEqual(self.lua.globals().run_export_observer(target, "reverse-role-order"), (13, 5, 2, 0))

    def test_named_export_client_can_join_before_its_locale_is_ready(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.assertEqual(self.lua.globals().run_export_observer(target, "pending-locale"), (13, 5, 2, 0))

    def test_export_pair_requires_ready_locales_and_declared_names(self):
        for target in ("f200", "f210"):
            for opponent in ("locale-never-ready", "unexpected-client-name"):
                with self.subTest(target=target, opponent=opponent):
                    with self.assertRaises(Exception):
                        self.lua.globals().run_export_observer(target, opponent)

    def test_missing_clicks_wrong_player_values_mutation_and_missing_lifecycle_are_rejected(self):
        for target in ("f200", "f210"):
            for opponent in ("missing-click", "duplicate-click", "wrong-player", "invalid-profile", "false-zero",
                             "wrong-user", "editable", "stale-preview", "native-mutation", "setting-mutation", "missing-rejoin", "missing-restart"):
                with self.subTest(target=target, opponent=opponent):
                    with self.assertRaises(Exception):
                        self.lua.globals().run_export_observer(target, opponent)

    def test_distinct_server_commands_and_exact_client_role_phases_are_required(self):
        for target in ("f200", "f210"):
            for opponent in ("duplicate-settings-command", "early-server-commands", "post-load-server-command",
                             "wrong-role-rejoin", "duplicate-initial-join", "duplicate-rejoin",
                             "duplicate-restart-role", "early-rejoin"):
                with self.subTest(target=target, opponent=opponent):
                    with self.assertRaises(Exception):
                        self.lua.globals().run_export_observer(target, opponent)

    def test_zero_player_index_cannot_impersonate_absent_server_event_origin(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                with self.assertRaises(Exception):
                    self.lua.globals().run_export_observer(target, "zero-server-index")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    sys.exit(0 if result.wasSuccessful() else 1)
