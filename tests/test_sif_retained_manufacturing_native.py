"""Oppose the real disposable Lua lifecycle with independent owned host tables.

No Factorio process, native serialization, API/queue support or lab claim follows.
"""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/sif-retained-manufacturing-native"
ROWS = [
    ("low_density_structure", ["casting-low-density-structure", "low-density-structure", "scrap-recycling"]),
    ("plastic", ["bioplastic", "plastic-bar"]),
    ("processing_unit", ["processing-unit"]),
    ("rocket_fuel", ["ammonia-rocket-fuel", "rocket-fuel", "rocket-fuel-from-jelly"]),
    ("steel", ["casting-steel", "steel-plate"]),
]
NAME = "mir-fixture-mir5-sif-retained-manufacturing"
PREFIX = "recipe-prod-research_"


class RetainedNativeFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().fixture_root = (FIXTURE / "shared").as_posix()
        self.lua.execute('''
          package.path = fixture_root .. "/?.lua"
          package.cpath = ""
          callbacks, markers, saves, logs = {}, {}, {}, {}
          reset_calls, create_calls, api_calls = 0, 0, 0
          storage = {}
          script = {active_mods={base="2.0.77",quality="2.0.77",["elevated-rails"]="2.0.77",
            ["space-age"]="2.0.77",["space-is-fake"]="1.0.60",["cr-commons"]="1.0.27",
            ["more-infinite-research"]="4.7.20003",
            ["mir-fixture-mir5-sif-retained-manufacturing"]="0.1.0",
            ["mir-fixture-mir5-active-mods-observer"]="0.1.0"}}
          function script.on_init(fn) callbacks.init=fn end
          function script.on_configuration_changed(fn) callbacks.config=fn end
          function script.on_load(fn) callbacks.load=fn end
          function script.on_event(_,fn) callbacks.tick=fn end
          defines={events={on_tick=1}}
          helpers={table_to_json=function(value) markers[#markers+1]=value; return "host-record" end}
          log=function(value) logs[#logs+1]=value end
          game={forces={}}
          local next_index=0
          function new_force(name)
            next_index=next_index+1
            local f={name=name,index=next_index,valid=true,technologies={},recipes={},research_queue={},
              research_progress=0,mining_drill_productivity_bonus=0,laboratory_speed_modifier=0}
            -- Independent vectors, not imported from the fixture or candidate.
            local rows={
              {"low_density_structure",{"casting-low-density-structure","low-density-structure","scrap-recycling"}},
              {"plastic",{"bioplastic","plastic-bar"}}, {"processing_unit",{"processing-unit"}},
              {"rocket_fuel",{"ammonia-rocket-fuel","rocket-fuel","rocket-fuel-from-jelly"}},
              {"steel",{"casting-steel","steel-plate"}}}
            for _,r in ipairs(rows) do
              local n="recipe-prod-research_"..r[1].."-1"
              local effects={}
              for _,recipe in ipairs(r[2]) do
                effects[#effects+1]={type="change-recipe-productivity",recipe=recipe,change=.1}
                f.recipes[recipe]={productivity_bonus=0}
              end
              f.technologies[n]={name=n,valid=true,level=1,researched=false,enabled=true,saved_progress=0,
                prerequisites={},prototype={hidden=true,max_level=4294967295,effects=effects}}
            end
            f.technologies["mining-productivity-3"]={name="mining-productivity-3",valid=true,level=3,
              researched=false,enabled=true,saved_progress=0,prerequisites={},prototype={hidden=false}}
            function f.reset_technology_effects()
              if native_read_only then error("successor reset is forbidden") end
              reset_calls=reset_calls+1
              -- Oppose the observed published source reset/reconciliation:
              -- source R03 captured true despite earlier false assignments.
              if reset_reenables then
                for _,technology in pairs(f.technologies) do technology.enabled=true end
              end
              for _,r in ipairs(rows) do
                local value=f.technologies["recipe-prod-research_"..r[1].."-1"]
                for _,recipe in ipairs(r[2]) do f.recipes[recipe].productivity_bonus=(value.level-1)*.1 end
              end
              f.mining_drill_productivity_bonus=(f.technologies["mining-productivity-3"].level-3)*.1
            end
            function f.add_research(name)
              if native_read_only then error("successor research/queue write is forbidden") end
              local value=f.technologies[name]
              if not value or not value.enabled or (refuse_hidden_queue and value.prototype.hidden) then return false end
              f.research_queue[#f.research_queue+1]=value
              if #f.research_queue==1 then f.current_research=value end
              return true
            end
            -- Exact2.0.77 runtime-api.json SHA256594B4EC9: research_queue and
            -- add_research exist, but LuaForce has no research_queue_enabled.
            -- Reject absent engine members instead of inventing host support.
            local supported={name=true,index=true,valid=true,technologies=true,recipes=true,
              research_queue=true,current_research=true,research_progress=true,
              mining_drill_productivity_bonus=true,laboratory_speed_modifier=true,
              reset_technology_effects=true,add_research=true}
            setmetatable(f,{
              __index=function(_,key)
                if not supported[key] then error("LuaForce doesn't contain key "..tostring(key)) end
              end,
              __newindex=function(value,key,item)
                if not supported[key] then error("LuaForce doesn't contain key "..tostring(key)) end
                rawset(value,key,item)
              end})
            game.forces[name],game.forces[f.index]=f,f
            return f
          end
          function game.create_force(name) create_calls=create_calls+1; return new_force(name) end
          function game.server_save(name) saves[#saves+1]=name end
          game.forces.player=new_force("player")
          remote={call=function(interface,method,index,name)
            api_calls=api_calls+1
            assert(interface=="more-infinite-research.api.v1" and method=="get_research")
            local f=game.forces[index];local t=f.technologies[name]
            if api_missing then return nil,"unavailable" end
            if api_mutates then f.research_progress=f.research_progress+.1 end
            return {name=name,force_index=index,level=api_wrong and t.level+1 or t.level,researched=t.researched,
              enabled=t.enabled,saved_progress=t.saved_progress}
          end}
          function switch_successor()
            script.active_mods["more-infinite-research"]="5.0.20002"
            script.active_mods["mir-fixture-mir5-sif-retained-manufacturing"]="0.2.0"
          end
          function switch_current_entry_successor()
            script.active_mods["more-infinite-research"]="5.0.20010"
            script.active_mods["mir-fixture-mir5-sif-retained-manufacturing"]="0.5.0"
          end
        ''')
        self.lua.execute('''
          script.event_order="level -> mir-fixture-mir5-sif-retained-manufacturing -> space-is-fake -> more-infinite-research"
          event_order_calls=0
          function script.get_event_order() event_order_calls=event_order_calls+1;return script.event_order end
          local proxies,backing={},{}
          local function readonly(value)
            if type(value)~="table" or backing[value] then return value end
            if proxies[value] then return proxies[value] end
            local proxy={};proxies[value]=proxy;backing[proxy]=value
            return setmetatable(proxy,{
              __index=function(_,key) return readonly(value[key]) end,
              __newindex=function(_,key,item)
                if engine_writing then value[key]=item else error("native/source witness write forbidden: "..tostring(key)) end
              end,
              __len=function() return #value end,
              __pairs=function() return function(_,key) local k,v=next(value,key);return k,readonly(v) end,nil,nil end,
              __ipairs=function() return function(_,index) index=index+1;if value[index]~=nil then return index,readonly(value[index]) end end,nil,0 end})
          end
          function guard_force(f)
            local p=readonly(f);game.forces[f.name],game.forces[f.index]=p,p;return p
          end
          function guard_natives()
            native_read_only=true
            guard_force(game.forces.player);guard_force(game.forces['mir5-sif-retained-foreign'])
          end
          function guard_source_witnesses()
            local s=storage.mir5_sif_retained_manufacturing
            s.player=readonly(s.player);s.foreign=readonly(s.foreign)
          end
          function guard_all_storage() storage=readonly(storage) end
          function engine_flags(player,foreign)
            engine_writing=true
            game.forces.player.technologies['recipe-prod-research_processing_unit-1'].enabled=player
            game.forces['mir5-sif-retained-foreign'].technologies['mining-productivity-3'].enabled=foreign
            engine_writing=false
          end
          function run_configuration()
            callback_phase="configuration";mir_config_seen=false
            for name in (script.event_order.." -> "):gmatch("(.-) %-> ") do
              if name=="mir-fixture-mir5-sif-retained-manufacturing" then callbacks.config()
              elseif name=="more-infinite-research" then
                if mir_callback then mir_callback() end;mir_config_seen=true
              end
            end
            callback_phase="after-configuration"
          end
          local create,save,query=game.create_force,game.server_save,remote.call
          local function after_config()
            local role=script.active_mods['mir-fixture-mir5-sif-retained-manufacturing']
            if role=='0.4.0' or role=='0.5.0' then
              assert(callback_phase=="after-configuration" and mir_config_seen,"fresh/API/save before all configuration callbacks")
            end
          end
          game.create_force=function(name) after_config();local f=create(name);return native_read_only and guard_force(f) or f end
          game.server_save=function(name) after_config();return save(name) end
          remote.call=function(...) after_config();return query(...) end
          function observable(value)
            if type(value)~="table" then return value end
            local out={};for k,v in pairs(value) do out[k]=observable(v) end;return out
          end
        ''')
        self.load_control()

    def load_control(self):
        self.lua.execute((FIXTURE / "shared/control.lua").read_text(encoding="utf-8"))

    def storage(self):
        def plain(value):
            if hasattr(value, "items"):
                return {str(k): plain(v) for k, v in value.items()}
            return value
        return json.dumps(plain(self.lua.globals().observable(self.lua.globals().storage)), sort_keys=True)

    def source(self):
        self.lua.execute("callbacks.init(); callbacks.tick()")

    def successor(self):
        self.lua.execute("switch_successor()")
        self.load_control()
        self.lua.execute("callbacks.config(); callbacks.tick()")

    def cold(self):
        before = self.storage()
        counts = self.lua.eval("{#saves,reset_calls,create_calls,api_calls}")
        original = [counts[n] for n in range(1, 5)]
        self.load_control()
        self.lua.execute("callbacks.load()")
        self.assertEqual(before, self.storage())
        self.assertEqual(original[3], self.lua.globals().api_calls)
        self.lua.execute("callbacks.tick()")
        self.assertEqual(before, self.storage())
        self.assertEqual(original[:3], [self.lua.eval("#saves"), self.lua.globals().reset_calls,
                                        self.lua.globals().create_calls])

    def entry_setup(self, player, foreign):
        self.source()
        self.lua.execute("switch_successor();script.active_mods['mir-fixture-mir5-sif-retained-manufacturing']='0.4.0'")
        self.load_control()
        self.lua.execute("guard_natives();guard_source_witnesses()")
        self.lua.globals().engine_flags(player, foreign)

    def current_entry_setup(self, player, foreign):
        self.source()
        self.lua.execute("switch_current_entry_successor()")
        self.load_control()
        self.lua.execute("guard_natives();guard_source_witnesses()")
        self.lua.globals().engine_flags(player, foreign)

    def test_entry_boundary_all_boolean_combinations_and_read_only_colds(self):
        info = json.loads((FIXTURE / "successor-entry-boundary/info.json").read_bytes())
        self.assertEqual((NAME, "0.4.0"), (info["name"], info["version"]))
        self.assertEqual(["base >= 2.0.77", "space-age >= 2.0.77"], info["dependencies"])
        for player in (False, True):
            for foreign in (False, True):
                with self.subTest(player=player, foreign=foreign):
                    self.setUp(); self.entry_setup(player, foreign)
                    self.lua.execute("run_configuration()")
                    self.assertEqual(1, self.lua.globals().create_calls)
                    self.assertEqual(0, self.lua.globals().api_calls)
                    self.assertEqual(1, self.lua.eval("#saves"))
                    self.assertFalse(self.lua.eval("storage.mir5_sif_retained_manufacturing.player.technologies['recipe-prod-research_processing_unit-1'].enabled"))
                    self.assertFalse(self.lua.eval("storage.mir5_sif_retained_manufacturing.foreign.foreign.enabled"))
                    self.lua.execute("callbacks.tick()")
                    self.assertEqual(player, self.lua.eval("markers[2].witnesses.entry_boundary.player_processing_enabled"))
                    self.assertEqual(foreign, self.lua.eval("markers[2].witnesses.entry_boundary.foreign_mining_enabled"))
                    self.assertEqual(player, self.lua.eval("markers[2].witnesses.entry_boundary.flag_deltas.player_processing.entry"))
                    self.assertFalse(self.lua.eval("markers[2].witnesses.entry_boundary.flag_deltas.player_processing.source"))
                    self.assertFalse(self.lua.eval("markers[2].witnesses.entry_boundary.flag_deltas.foreign_mining.source"))
                    self.assertEqual(5, self.lua.eval("(function() local n=0;for _ in pairs(markers[2].witnesses.entry_boundary.player_prototypes) do n=n+1 end;return n end)()"))
                    self.assertEqual(2, self.lua.globals().create_calls)
                    self.lua.execute("guard_all_storage()")
                    self.cold(); self.cold()
                    self.assertEqual(1, self.lua.globals().event_order_calls)
                    self.assertEqual(2, self.lua.globals().reset_calls)

    def test_current_entry_boundary_preserves_source_through_two_read_only_colds(self):
        info = json.loads((FIXTURE / "successor-current-entry-boundary/info.json").read_bytes())
        profile = json.loads((ROOT / "tests/profiles/sif-retained-manufacturing-current-f200-2077.json").read_bytes())
        self.assertEqual((NAME, "0.5.0", "2.0"), (info["name"], info["version"], info["factorio_version"]))
        self.assertEqual(["base >= 2.0.77", "space-age >= 2.0.77"], info["dependencies"])
        self.assertFalse(any(dependency.startswith("more-infinite-research") for dependency in info["dependencies"]))
        self.assertEqual("36F2E9D8C01507C2CBDC01AFF6C87399B40A9E0646F40DEC1F82628F5F50CBAB",
                         profile["archive_sha256"]["more-infinite-research_5.0.20010.zip"])
        for player in (False, True):
            for foreign in (False, True):
                with self.subTest(player=player, foreign=foreign):
                    self.setUp(); self.current_entry_setup(player, foreign)
                    self.lua.execute("run_configuration()")
                    self.assertEqual(1, self.lua.globals().create_calls)
                    self.assertEqual(0, self.lua.globals().api_calls)
                    self.assertEqual(1, self.lua.eval("#saves"))
                    self.lua.execute("callbacks.tick()")
                    self.assertEqual("successor-current-entry-boundary-proposal", self.lua.eval("markers[2].witnesses.role"))
                    self.assertEqual("0.5.0", self.lua.eval("markers[2].witnesses.fixture_version"))
                    self.assertEqual("5.0.20010", self.lua.eval("markers[2].witnesses.successor_mir"))
                    self.assertEqual(player, self.lua.eval("markers[2].witnesses.entry_boundary.player_processing_enabled"))
                    self.assertEqual(foreign, self.lua.eval("markers[2].witnesses.entry_boundary.foreign_mining_enabled"))
                    self.assertFalse(self.lua.eval("markers[2].witnesses.entry_boundary.flag_deltas.player_processing.source"))
                    self.assertFalse(self.lua.eval("markers[2].witnesses.entry_boundary.flag_deltas.foreign_mining.source"))
                    self.assertEqual(2, self.lua.globals().create_calls)
                    self.lua.execute("guard_all_storage()")
                    self.cold(); self.cold()
                    self.assertEqual(4, self.lua.eval("#markers"))
                    self.assertEqual(15, self.lua.globals().api_calls)
                    self.assertEqual(2, self.lua.globals().reset_calls)

    def test_old_entry_role_refuses_current_successor_version_before_mutation(self):
        self.source()
        self.lua.execute("switch_current_entry_successor();script.active_mods['mir-fixture-mir5-sif-retained-manufacturing']='0.4.0'")
        self.load_control()
        before = self.storage()
        with self.assertRaisesRegex(LuaError, "exact closure differs: more-infinite-research"):
            self.lua.execute("callbacks.config()")
        self.assertEqual(before, self.storage())
        self.assertEqual(1, self.lua.eval("#saves"))
        self.assertEqual(1, self.lua.globals().create_calls)

    def test_future_entry_role_refuses_before_mutation(self):
        self.source()
        self.lua.execute("script.active_mods['more-infinite-research']='5.0.20010';script.active_mods['mir-fixture-mir5-sif-retained-manufacturing']='0.6.0'")
        self.load_control()
        before = self.storage()
        with self.assertRaisesRegex(LuaError, "fixture version differs"):
            self.lua.execute("callbacks.config()")
        self.assertEqual(before, self.storage())
        self.assertEqual(1, self.lua.eval("#saves"))
        self.assertEqual(1, self.lua.globals().create_calls)

    def test_source_complete_entry_rejects_preexisting_baseline_without_recapture(self):
        self.entry_setup(True, False)
        self.lua.execute("""
          assert(storage.mir5_sif_retained_manufacturing.phase=="source-complete")
          storage.mir5_sif_retained_manufacturing.entry_boundary={
            player_processing_enabled=false,foreign_mining_enabled=true,
            event_order=script.event_order,original_marker="must remain untouched"}
        """)
        before = self.storage()
        counts = self.lua.eval("{#saves,reset_calls,create_calls,api_calls,event_order_calls}")
        original = [counts[n] for n in range(1, 6)]
        with self.assertRaisesRegex(LuaError, "entry boundary already captured"):
            self.lua.execute("run_configuration()")
        self.assertEqual(before, self.storage())
        self.assertEqual(original, [self.lua.eval("#saves"), self.lua.globals().reset_calls,
                                    self.lua.globals().create_calls, self.lua.globals().api_calls,
                                    self.lua.globals().event_order_calls])

    def test_entry_boundary_refuses_each_post_entry_flag_flip(self):
        for player in (False, True):
            for foreign in (False, True):
                for which in ("player", "foreign"):
                    with self.subTest(player=player, foreign=foreign, which=which):
                        self.setUp(); self.entry_setup(player, foreign)
                        self.lua.execute("run_configuration()")
                        self.lua.globals().engine_flags(not player if which == "player" else player,
                                                        not foreign if which == "foreign" else foreign)
                        before = self.storage()
                        with self.assertRaises(LuaError): self.lua.execute("callbacks.tick()")
                        self.assertEqual(before, self.storage())
                        self.assertEqual(1, self.lua.globals().create_calls)
                        self.assertEqual(1, self.lua.eval("#saves"))

    def test_entry_boundary_refuses_bad_event_order_and_phase(self):
        for order in (None, "", "level -> more-infinite-research", "level -> more-infinite-research -> mir-fixture-mir5-sif-retained-manufacturing", "level -> mir-fixture-mir5-sif-retained-manufacturing -> missing -> more-infinite-research", "level -> mir-fixture-mir5-sif-retained-manufacturing -> mir-fixture-mir5-sif-retained-manufacturing -> more-infinite-research"):
            with self.subTest(order=order):
                self.setUp(); self.entry_setup(False, False)
                self.lua.globals().script.event_order = order
                before = self.storage()
                with self.assertRaises(LuaError): self.lua.execute("callbacks.config()")
                self.assertEqual(before, self.storage())
                self.assertEqual(1, self.lua.globals().create_calls)
        self.setUp(); self.entry_setup(False, False)
        self.lua.execute("storage.mir5_sif_retained_manufacturing.phase='wrong'")
        with self.assertRaises(LuaError): self.lua.execute("callbacks.config()")

    def test_entry_boundary_rejects_pre_mir_nonflag_drift_and_recapture(self):
        mutations = [
            "game.forces.player.technologies['recipe-prod-research_steel-1']=nil",
            "game.forces.player.technologies['recipe-prod-research_steel-1'].level=7",
            "game.forces.player.technologies['recipe-prod-research_rocket_fuel-1'].saved_progress=.41",
            "game.forces.player.recipes['plastic-bar'].productivity_bonus=.3",
            "game.forces.player.research_progress=.43",
            "game.forces.player.research_queue[1]=game.forces.player.research_queue[2]",
            "game.forces.player.technologies['recipe-prod-research_steel-1'].prototype.effects[1].change=.2",
            "game.forces['mir5-sif-retained-foreign'].technologies['mining-productivity-3'].saved_progress=.28",
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.setUp(); self.entry_setup(True, True)
                self.lua.execute("engine_writing=true;" + mutation + ";engine_writing=false")
                before = self.storage()
                with self.assertRaises(LuaError): self.lua.execute("callbacks.config()")
                self.assertEqual(before, self.storage())
                self.assertEqual(1, self.lua.globals().create_calls)
                self.assertEqual(0, self.lua.globals().api_calls)
                self.assertEqual(1, self.lua.eval("#saves"))
        self.setUp(); self.entry_setup(True, False); self.lua.execute("run_configuration()")
        before = self.storage()
        with self.assertRaises(LuaError): self.lua.execute("callbacks.config()")
        self.assertEqual(before, self.storage())
        self.assertEqual(1, self.lua.globals().create_calls)

    def test_entry_boundary_other_mutations_refused(self):
        mutations = [
            "game.forces.player.technologies['recipe-prod-research_steel-1']=nil",
            "game.forces.player.technologies['recipe-prod-research_steel-1'].level=7",
            "game.forces.player.technologies['recipe-prod-research_rocket_fuel-1'].saved_progress=.41",
            "game.forces.player.recipes['plastic-bar'].productivity_bonus=.3",
            "game.forces.player.research_progress=.43",
            "game.forces.player.research_queue[1]=game.forces.player.research_queue[2]",
            "game.forces['mir5-sif-retained-foreign'].technologies['mining-productivity-3'].saved_progress=.28",
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.setUp(); self.entry_setup(True, True); self.lua.execute("run_configuration()")
                self.lua.execute("engine_writing=true;" + mutation + ";engine_writing=false")
                before = self.storage()
                with self.assertRaises(LuaError): self.lua.execute("callbacks.tick()")
                self.assertEqual(before, self.storage())
                self.assertEqual(1, self.lua.globals().create_calls)

    def test_independent_contract_roles_and_exact_profiles(self):
        contract = self.lua.eval('require("contract")')
        for i, (key, recipes) in enumerate(ROWS, 1):
            self.assertEqual(key, contract.rows[i].key)
            self.assertEqual(recipes, list(contract.rows[i].recipes.values()))
        self.assertEqual([3, 2, 1, 3, 2], [len(row[1]) for row in ROWS])
        self.assertEqual("5.0.20002", contract.successor)
        self.assertEqual("5.0.20010", contract.current_successor)
        for role, profile_role, version, mir, digest, dependency in (
            ("published", "published", "0.1.0", "4.7.20003", "FBBA844DD04011A12BB6DA885745B0733AD37FAB181EAAD9EE4346B9B0D32647",
             "more-infinite-research = 4.7.20003"),
            ("successor", "successor", "0.2.0", "5.0.20002", "920C68BD074718AB2A608D8B2FC3657AA1B9C8766A586618C4C0952BA50C3E40",
             "more-infinite-research = 5.0.20002"),
        ):
            info = json.loads((FIXTURE / role / "info.json").read_bytes())
            profile = json.loads((ROOT / f"tests/profiles/sif-retained-manufacturing-{profile_role}-f200-2077.json").read_bytes())
            self.assertEqual((NAME, version, "2.0"), (info["name"], info["version"], info["factorio_version"]))
            self.assertIn(dependency, info["dependencies"])
            self.assertEqual(digest, profile["archive_sha256"][f"more-infinite-research_{mir}.zip"])
            selected = {r["name"]: r["version"] for r in profile["mods"] if r["enabled"]}
            self.assertEqual(9, len(selected))
            self.assertEqual("1.0.60", selected["space-is-fake"])
            self.assertEqual("1.0.27", selected["cr-commons"])
            self.assertEqual(version, selected[NAME])
            self.assertNotIn("recycler", selected)
            self.assertEqual("2.0.77", profile["engine"]["version"])

    def test_actual_lua_lifecycle_preserves_source_and_two_read_only_colds(self):
        self.source()
        self.assertEqual(1, self.lua.eval("#saves"))
        self.successor()
        self.assertEqual(2, self.lua.eval("#saves"))
        self.cold()
        self.cold()
        self.assertEqual(4, self.lua.eval("#markers"))
        self.assertEqual(15, self.lua.globals().api_calls)
        self.assertEqual(2, self.lua.globals().reset_calls)
        self.assertEqual("reload", self.lua.eval("markers[4].stage"))
        self.assertFalse(self.lua.eval("game.forces.player.technologies['recipe-prod-research_processing_unit-1'].enabled"))
        self.assertAlmostEqual(.42, self.lua.eval("game.forces.player.research_progress"))
        self.assertTrue(self.lua.eval("markers[4].witnesses.hidden_library_enqueue_not_exercised"))

    def test_disabled_source_is_seeded_after_reset_side_effects(self):
        self.lua.execute("reset_reenables=true")
        self.source()
        self.assertFalse(self.lua.eval("game.forces.player.technologies['recipe-prod-research_processing_unit-1'].enabled"))
        self.assertFalse(self.lua.eval("game.forces['mir5-sif-retained-foreign'].technologies['mining-productivity-3'].enabled"))
        self.successor()
        self.cold()
        self.cold()

    def test_known_five_row_omission_refuses_before_successor_fixture_mutation(self):
        self.source()
        for key, _ in ROWS:
            self.lua.globals().game.forces.player.technologies[PREFIX + key + "-1"] = None
        self.lua.execute("switch_successor()")
        self.load_control()
        before = self.storage()
        with self.assertRaisesRegex(LuaError, "missing technology recipe-prod-research_low_density_structure-1"):
            self.lua.execute("callbacks.config()")
        self.assertEqual(before, self.storage())
        self.assertEqual(1, self.lua.eval("#saves"))
        self.assertEqual(1, self.lua.globals().create_calls)

    def test_source_colds_also_leave_the_captured_fixture_read_only(self):
        self.source()
        self.cold()
        self.cold()
        self.assertEqual(1, self.lua.eval("#saves"))
        self.assertEqual(0, self.lua.globals().api_calls)
        self.assertEqual(3, self.lua.eval("#markers"))

    def test_captured_paid_queue_native_bonus_and_foreign_opponents_refuse(self):
        changes = [
            "game.forces.player.technologies['recipe-prod-research_steel-1'].level=7",
            "game.forces.player.technologies['recipe-prod-research_processing_unit-1'].enabled=true",
            "game.forces.player.technologies['recipe-prod-research_rocket_fuel-1'].saved_progress=.41",
            "game.forces.player.recipes['plastic-bar'].productivity_bonus=.3",
            "local q=game.forces.player.research_queue;q[1],q[2]=q[2],q[1]",
            "game.forces.player.current_research=game.forces.player.research_queue[2]",
            "game.forces.player.research_progress=.43",
            "game.forces.player.research_queue={};game.forces.player.current_research=nil",
            "game.forces['mir5-sif-retained-foreign'].technologies['mining-productivity-3'].enabled=true",
            "game.forces['mir5-sif-retained-foreign'].technologies['mining-productivity-3'].saved_progress=.28",
        ]
        for change in changes:
            with self.subTest(change=change):
                self.setUp(); self.source(); self.lua.execute(change + ";switch_successor()")
                self.load_control()
                before = self.storage()
                with self.assertRaises(LuaError): self.lua.execute("callbacks.config()")
                self.assertEqual(before, self.storage())
                self.assertEqual(1, self.lua.eval("#saves"))

    def test_wrong_effect_duplicate_scrap_and_visible_rows_refuse(self):
        changes = [
            "t.prototype.hidden=false",
            "t.prototype.max_level=6",
            "t.prototype.effects[1].change=.2",
            "t.prototype.effects[2]=t.prototype.effects[1]",
            "t.prototype.effects[2]={type='change-recipe-productivity',recipe='scrap-recycling',change=.1}",
        ]
        for change in changes:
            with self.subTest(change=change):
                self.setUp(); self.source()
                self.lua.execute("local t=game.forces.player.technologies['recipe-prod-research_processing_unit-1'];"+change+";switch_successor()")
                self.load_control()
                with self.assertRaises(LuaError): self.lua.execute("callbacks.config()")
                self.assertEqual(1, self.lua.eval("#saves"))

    def test_removed_force_queue_switch_read_and_write_are_rejected(self):
        original = (FIXTURE / "shared/control.lua").read_text(encoding="utf-8")
        opponents = [
            original.replace("force.reset_technology_effects()",
                             "force.reset_technology_effects();force.research_queue_enabled=true", 1),
            original.replace("progress=force.research_progress,",
                             "progress=force.research_progress,queue_enabled=force.research_queue_enabled,", 1),
        ]
        for broken in opponents:
            with self.subTest():
                self.assertNotEqual(original, broken)
                self.setUp()
                self.lua.execute(broken)
                with self.assertRaisesRegex(LuaError, "LuaForce doesn't contain key research_queue_enabled"):
                    self.lua.execute("callbacks.init()")
                self.assertEqual(0, self.lua.eval("#saves"))
                self.assertEqual("{}", self.storage())

    def test_wrong_closures_fresh_successor_and_hidden_queue_refusal_stop(self):
        for change in ["script.active_mods.base='2.0.76'", "script.active_mods['space-is-fake']='1.0.78'",
                       "script.active_mods.recycler='2.0.77'", "switch_successor()", "refuse_hidden_queue=true"]:
            with self.subTest(change=change):
                self.setUp(); self.lua.execute(change)
                with self.assertRaises(LuaError): self.lua.execute("callbacks.init()")
                self.assertEqual(0, self.lua.eval("#saves"))
                self.assertEqual("{}", self.storage())

    def test_fresh_rewards_and_api_mutation_opponents_refuse(self):
        for change in ["game.forces['mir5-sif-retained-fresh'].recipes['steel-plate'].productivity_bonus=.1",
                       "game.forces['mir5-sif-retained-fresh'].technologies['recipe-prod-research_steel-1'].level=2",
                       "api_missing=true", "api_wrong=true", "api_mutates=true"]:
            with self.subTest(change=change):
                self.setUp(); self.source(); self.successor(); self.lua.execute(change)
                self.load_control(); self.lua.execute("callbacks.load()")
                before = self.storage()
                with self.assertRaises(LuaError): self.lua.execute("callbacks.tick()")
                self.assertEqual(before, self.storage())
                self.assertEqual(2, self.lua.eval("#saves"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    args, remaining = parser.parse_known_args()
    sys.path.insert(0, args.lua_runtime_dir)
    from lupa.lua52 import LuaRuntime, LuaError
    unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)
