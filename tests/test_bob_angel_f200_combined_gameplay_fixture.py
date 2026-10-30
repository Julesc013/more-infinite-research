"""Host controls for the narrow F200 combined-profile steel gameplay witness.

The control executes only against Lua doubles.  It pins independent published
and NoMIR inputs, validates the real-lab/physical-route protocol, and never
launches Factorio or turns this source fixture into native qualification.
"""
import argparse
from copy import deepcopy
import gzip
import hashlib
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/bob-angel-f200-combined-gameplay"
PROFILE = ROOT / "tests/profiles/bob-angel-f200-combined-gameplay-2077-r01.json"
BASE_PROFILE = ROOT / "tests/profiles/bob-angel-full-space-age-f200-2077.json"
ORACLE = ROOT / "tests/fixtures/bob-angel-f200-combined-published-473-expectations.json.gz"
CONTEXT = ROOT / "tests/fixtures/bob-angel-f200-combined-upstream-context.json.gz"
ORACLE_SHA256 = "B80EDB79ABE75F3A19A3D7BD2B9CAB43343807D405C9E474E93219D542EDE633"
CONTEXT_SHA256 = "C5B76C07B66A305099412E2BDBD63855234692C9D5DFF32B3351D0A100A75C7D"
PROFILE_SHA256 = "61CBE6299DD2708079EA80FB3871AC980C6FF7281DD126C61B3126A7FF294857"
CANDIDATE_SHA256 = "8C93C7063B75E0811D1D27036F3596C05EE0A5A965BC259D276160F91D6274BB"
ROW_SHA256 = "7916AC6C1265CC119E4915BB9E2CE23A52D44EA044867516300540BE6B5104CC"
RAW_SHA256 = "AD702CC98FA30A672C8A358305D0F562A5965E51F28CED8D0EFC8ABD26F5F487"
TARGET = "recipe-prod-research_steel-1"
ROUTE = "angels-plate-steel-2"
OWNER = "angels-steel-smelting-2"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def canonical_sha256(value: object) -> str:
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest().upper()


def lua_value(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua_value(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua_value(runtime, item) for item in value])
    return value


class CombinedSteelGameplayFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if sha256(ORACLE) != ORACLE_SHA256:
            raise AssertionError("published combined steel oracle changed")
        if sha256(CONTEXT) != CONTEXT_SHA256:
            raise AssertionError("NoMIR combined steel context changed")
        if sha256(BASE_PROFILE) != PROFILE_SHA256:
            raise AssertionError("combined base profile changed")
        cls.oracle = json.loads(gzip.decompress(ORACLE.read_bytes()).decode("utf-8"))
        cls.context = json.loads(gzip.decompress(CONTEXT.read_bytes()).decode("utf-8"))
        cls.base_profile = json.loads(BASE_PROFILE.read_text(encoding="utf-8"))
        cls.profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        cls.active = {row["name"]: row["version"] for row in cls.profile["mods"] if row["enabled"]}

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().fixture_path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().active_mods = lua_value(self.lua, self.active)

    def test_profile_and_info_pin_real_existing_inputs_without_inventing_fixture_archive_bytes(self):
        self.assertEqual("mir5-bob-angel-f200-combined-gameplay-native-selection", self.profile["kind"])
        self.assertEqual({"version": "2.0.77", "sha256": "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B"},
                         self.profile["engine"])
        self.assertEqual("Defaults", self.profile["settings_mode"])
        self.assertEqual(self.base_profile["mods"] + [
            {"name": "more-infinite-research", "version": "5.0.20000", "enabled": True},
            {"name": "mir-fixture-mir5-bob-angel-f200-combined-gameplay", "version": "0.1.0", "enabled": True},
        ], self.profile["mods"])
        self.assertEqual(38, len(self.active))
        expected_archives = dict(self.base_profile["archive_sha256"])
        expected_archives["more-infinite-research_5.0.20000.zip"] = CANDIDATE_SHA256
        self.assertEqual(expected_archives, self.profile["archive_sha256"])
        self.assertTrue(all(len(value) == 64 and value == value.upper()
                            for value in self.profile["archive_sha256"].values()))
        self.assertEqual({
            "path": "tests/profiles/bob-angel-full-space-age-f200-2077.json",
            "sha256": PROFILE_SHA256,
            "scope": "Exact 36-row F200 2.0.77 Defaults Space Age/BobTech/Angel upstream selection and 32 real direct-library archive pins. The current candidate is pinned separately; no historical or full-catalogue result transfers.",
        }, self.profile["source_selection"])
        self.assertEqual({
            "archive": "more-infinite-research_5.0.20000.zip",
            "sha256": CANDIDATE_SHA256,
            "bytes": 704721,
            "source_scope": "Corrected F200 combined-profile package only. Its independent 69-row public, 28-private-carrier, and 875-setting data admission remains a separate prerequisite.",
        }, self.profile["candidate"])
        self.assertEqual({
            "root": "tests/fixtures/bob-angel-f200-combined-gameplay",
            "included_members": ["info.json", "control.lua"],
            "excluded_members": ["README.md"],
            "scope": "The governed caller must build and pin this exact two-member fixture archive before native dispatch; this profile never invents a fixture archive hash.",
        }, self.profile["fixture"])
        self.assertNotIn("mir-fixture-mir5-bob-angel-f200-combined-gameplay_0.1.0.zip",
                         self.profile["archive_sha256"])

        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(("mir-fixture-mir5-bob-angel-f200-combined-gameplay", "0.1.0", "2.0"),
                         (info["name"], info["version"], info["factorio_version"]))
        self.assertEqual([
            f"{entry['name']} = {entry['version']}"
            for entry in self.profile["mods"]
            if entry["name"] != "mir-fixture-mir5-bob-angel-f200-combined-gameplay"
        ], info["dependencies"])

    def test_independent_complete_steel_row_and_upstream_route_contract_are_exact(self):
        row = self.oracle["technology"]["added"][TARGET]
        self.assertEqual(ROW_SHA256, row["canonical_sha256"])
        self.assertEqual(ROW_SHA256, canonical_sha256(row["row"]))
        self.assertEqual({
            "type": "technology", "name": TARGET, "level": 1, "upgrade": True,
            "max_level": "infinite", "order": "p[research_steel]",
            "prerequisites": ["automation-science-pack", "logistic-science-pack"],
            "unit": {"count_formula": "8000*2^(L-1)", "ingredients": [
                ["automation-science-pack", 1], ["logistic-science-pack", 1]], "time": 60},
            "effects": [
                {"type": "change-recipe-productivity", "recipe": "angels-plate-steel", "change": .1},
                {"type": "change-recipe-productivity", "recipe": ROUTE, "change": .1},
            ],
            "icons": [
                {"icon": "__space-age__/graphics/technology/steel-plate-productivity.png", "icon_size": 256},
                {"icon": "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
                 "icon_size": 128, "scale": .5, "shift": [50, 50], "floating": True},
            ],
            "localised_name": ["technology-name.more-infinite-research.research_steel", ["item-name.steel-plate"]],
            "localised_description": ["technology-description.more-infinite-research.recipe_productivity"],
        }, row["row"])

        self.assertEqual({
            "capture": "EAD7 control-without-mir",
            "path": str(Path(r"D:/Projects/Factorio/more-infinite-research/build/qualification/whole-product-heavy-space-age-f200-admission-r01-controller/native-captures/control-without-mir/write-data/script-output/data-raw-dump.json")),
            "bytes": 64158857, "sha256": RAW_SHA256,
            "engine_sha256": "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B",
        }, self.context["source"])
        raw = self.context["raw"]
        owner = raw["technology"][OWNER]
        self.assertEqual({
            "type": "technology", "name": OWNER,
            "prerequisites": ["angels-strand-casting-1", "angels-steel-smelting-1",
                              "angels-silicon-smelting-1", "angels-manganese-smelting-1"],
            "unit": {"count": 150, "ingredients": [["automation-science-pack", 1], ["logistic-science-pack", 1]], "time": 30},
            "effects": [
                {"type": "unlock-recipe", "recipe": "angels-liquid-molten-steel-2"},
                {"type": "unlock-recipe", "recipe": "angels-liquid-molten-steel-3"},
                {"type": "unlock-recipe", "recipe": "angels-roll-steel"},
                {"type": "unlock-recipe", "recipe": ROUTE},
            ],
        }, {key: owner[key] for key in ("type", "name", "prerequisites", "unit", "effects")})
        route = raw["recipe"][ROUTE]
        self.assertEqual({
            "type": "recipe", "name": ROUTE, "enabled": False, "allow_productivity": True,
            "category": "advanced-crafting", "energy_required": .5,
            "ingredients": [{"type": "item", "name": "angels-roll-steel", "amount": 1}],
            "results": [{"type": "item", "name": "steel-plate", "amount": 4}],
        }, {key: route[key] for key in ("type", "name", "enabled", "allow_productivity", "category", "energy_required", "ingredients", "results")})
        biolab = raw["lab"]["biolab"]
        self.assertEqual({
            "type": "lab", "name": "biolab", "inputs": [
                "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack",
                "bob-advanced-logistic-science-pack", "production-science-pack", "utility-science-pack",
                "space-science-pack", "metallurgic-science-pack", "agricultural-science-pack",
                "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack", "angels-token-bio"],
            "researching_speed": 2, "science_pack_drain_rate_percent": 50, "module_slots": 4,
            "allowed_module_categories": ["productivity", "speed", "efficiency", "quality", "pollution-clean", "pollution-create", "god"],
            "surface_conditions": [{"property": "pressure", "min": 1000, "max": 1000}],
        }, {key: biolab[key] for key in ("type", "name", "inputs", "researching_speed", "science_pack_drain_rate_percent", "module_slots", "allowed_module_categories", "surface_conditions")})

    def runtime_protocol(self, opponent=""):
        self.lua.globals().opponent = opponent
        return self.lua.execute(r'''
          local callbacks, interfaces, logs, saves = {events={}}, {}, 0, 0
          local target_name, route_name, owner_name = "recipe-prod-research_steel-1", "angels-plate-steel-2", "angels-steel-smelting-2"
          local function inventory()
            local values = {}
            return {
              insert=function(stack) values[stack.name]=(values[stack.name] or 0)+stack.count; return stack.count end,
              get_item_count=function(name) return values[name] or 0 end,
              remove=function(stack) local count=math.min(values[stack.name] or 0,stack.count); values[stack.name]=(values[stack.name] or 0)-count; return count end,
              is_empty=function() for _, value in pairs(values) do if value ~= 0 then return false end end return true end,
              values=values,
            }
          end
          local route_recipe={valid=true,enabled=opponent=="route-enabled",productivity_bonus=0}
          local owner_researched=opponent=="owner-preseed"
          local owner={valid=true,name=owner_name}
          setmetatable(owner,{__index=function(_,key) if key=="researched" then return owner_researched end end,
            __newindex=function(_,key,value) if key=="researched" then owner_researched=value;if value and opponent~="owner" then route_recipe.enabled=true end end end})
          local research_ingredients=opponent=="ingredients-order" and {{name="logistic-science-pack",amount=1},{name="automation-science-pack",amount=1}} or {{name="automation-science-pack",amount=opponent=="ingredients-count" and 2 or 1},{name="logistic-science-pack",amount=1}}
          local target={valid=true,name=target_name,level=1,researched=false,enabled=true,research_unit_energy=opponent=="energy-seconds" and 60 or 3600,
            prerequisites={{name="automation-science-pack"},{name="logistic-science-pack"}},prototype={name=target_name,level=1,upgrade=true,max_level=4294967295,order="p[research_steel]",effects={
              {type="change-recipe-productivity",recipe="angels-plate-steel",change=opponent=="effect" and .2 or .1},
              {type="change-recipe-productivity",recipe=route_name,change=.1},
            }},research_unit_ingredients=research_ingredients}
          setmetatable(target,{__index=function(_,key)
            if key=="research_unit_count" then
              if opponent=="stale-count-after-level-two" and target.level==2 then return 8000 end
              return 8000*(2^(target.level-1))
            end
          end})
          if opponent=="prototype-absent" then target.prototype=nil end
          local force={technologies={
            [target_name]=target,[owner_name]=owner,
            ["automation-science-pack"]={valid=true,name="automation-science-pack",researched=false},
            ["logistic-science-pack"]={valid=true,name="logistic-science-pack",researched=false},
          },recipes={[route_name]=route_recipe},research_queue={},current_research=nil}
          target.force=force
          force.add_research=function(value) force.current_research=value;force.research_queue={value};return true end
          local labs, machine = {}, nil
          local surface={
            get_property=function(name) assert(name=="pressure");return 1000 end,
            create_entity=function(spec)
              if spec.name=="biolab" then
                local input=inventory();local lab={valid=true,name="biolab",energy=0,quality={name=opponent=="quality" and "uncommon" or "normal"},
                  prototype={name="biolab",get_researching_speed=opponent~="lab-speed-missing" and function(quality) assert(quality=="normal");if opponent=="lab-speed-nil" then return nil end;return opponent=="lab-speed" and 1 or 2 end or nil,science_pack_drain_rate_percent=opponent=="drain" and 100 or 50,module_inventory_size=4,
                    allowed_module_categories={quality=true},surface_conditions={{property="pressure",min=opponent=="surface" and 999 or 1000,max=1000}},
                    lab_inputs=opponent=="lab-input" and {"automation-science-pack"} or (opponent=="lab-input-table" and {{name="automation-science-pack"},{name="logistic-science-pack"}} or {"automation-science-pack","logistic-science-pack"})},
                  get_inventory=function(index) if index==1 then return input end return nil end}
                labs[#labs+1]=lab;return lab
              end
              assert(spec.name=="assembling-machine-1")
              local input, output=inventory(),inventory()
              machine={valid=true,name="assembling-machine-1",quality={name=opponent=="machine-quality" and "uncommon" or "normal"},energy=0,crafting_progress=0,bonus_progress=0,productivity_bonus=.1,
                prototype={name="assembling-machine-1",get_crafting_speed=opponent~="machine-speed-missing" and function(quality) assert(quality=="normal");return opponent=="machine-speed" and .6 or .5 end or nil,crafting_categories={ ["advanced-crafting"]=opponent~="category" }},
                get_inventory=function(index) if index==4 then return input elseif index==5 then return output end return nil end,
                set_recipe=function(name) machine.recipe=name end,get_recipe=function() return machine.recipe and {name=machine.recipe} or nil end}
              return machine
            end,
          }
          local environment={
            script={active_mods=active_mods,on_init=function(callback)callbacks.init=callback end,on_load=function(callback)callbacks.load=callback end,
              on_event=function(event,callback)callbacks.events[event]=callback end},
            remote={add_interface=function(name,value) interfaces[name]=value end},
            defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1,lab_modules=2,crafter_modules=3,crafter_input=4,crafter_output=5}},
            prototypes={recipe={[route_name]={name=route_name,energy=.5,category=opponent=="route-category" and "crafting" or "advanced-crafting",additional_categories=opponent=="route-additional-category" and {"crafting"} or {},
              ingredients={{type="item",name="angels-roll-steel",amount=1}},products={{type="item",name="steel-plate",amount=4,probability=1,extra_count_fraction=0,ignored_by_productivity=0,ignored_by_stats=0,percent_spoiled=0}}}}},
            game={tick=1,speed=1,forces={player=force},surfaces={[1]=surface},server_save=function(name)assert(name=="mir5-native-complete");saves=saves+1 end},
            storage={},helpers={table_to_json=function(value) assert(value.case=="bob-angel-f200-combined-gameplay");return "{}" end},
            log=function(value)assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "));logs=logs+1 end,
          }
          local native_product=environment.prototypes.recipe[route_name].products[1]
          environment.prototypes.recipe[route_name].ingredients[1].ignored_by_stats=opponent=="ingredient-ignored" and 1 or 0
          if opponent=="product-probability" then native_product.probability=.5 end
          if opponent=="product-probability-missing" then native_product.probability=nil end
          if opponent=="product-extra" then native_product.extra_count_fraction=.1 end
          if opponent=="product-ignored" then native_product.ignored_by_productivity=1 end
          if opponent=="product-stats" then native_product.ignored_by_stats=1 end
          if opponent=="product-spoiled" then native_product.percent_spoiled=.1 end
          if opponent=="product-optional-omitted" then
            native_product.extra_count_fraction=nil;native_product.ignored_by_productivity=nil
            native_product.ignored_by_stats=nil;native_product.percent_spoiled=nil
          end
          environment._G=environment;setmetatable(environment,{__index=function(_,key)return _G[key] end})
          local loaded=pcall(assert(loadfile(fixture_path,"t",environment)))
          local init_ok,init_message=pcall(callbacks.init)
          if not init_ok then return {loaded=loaded,init_ok=false,message=tostring(init_message),logs=logs,saves=saves} end
          target.level,target.researched,force.current_research,force.research_queue=2,false,nil,{}
          route_recipe.productivity_bonus=.1
          for _, lab in ipairs(labs) do lab.get_inventory(1).values["automation-science-pack"]=0;lab.get_inventory(1).values["logistic-science-pack"]=0 end
          local event_ok,event_message=pcall(callbacks.events[2],{research=target,by_script=false})
          if not event_ok then return {loaded=loaded,init_ok=true,event_ok=false,message=tostring(event_message),logs=logs,saves=saves} end
          local research_tick,research_message=pcall(callbacks.events[1])
          if not research_tick then return {loaded=loaded,init_ok=true,event_ok=true,research_tick=false,message=tostring(research_message),logs=logs,saves=saves} end
          for index=1,100 do
            machine.get_inventory(4).values["angels-roll-steel"]=100-index
            machine.get_inventory(5).values["steel-plate"]=(index%10==0) and 8 or 4
            local tick_ok,tick_message=pcall(callbacks.events[1])
            if not tick_ok then return {loaded=loaded,init_ok=true,event_ok=true,physical_ok=false,message=tostring(tick_message)} end
          end
          local report=interfaces["mir5-bob-angel-f200-combined-gameplay"].report()
          if opponent=="saved-scalar" then environment.storage.mir5_bob_angel_f200_combined_gameplay.saved_target_level=nil end
          local live_game=environment.game
          local function storage_only_load()
            environment.game=setmetatable({}, {__index=function() error("on_load game access") end,__newindex=function() error("on_load game write") end})
            local ok,message=pcall(callbacks.load)
            environment.game=live_game
            return ok,message
          end
          local load_one,load_one_message=storage_only_load()
          local reload_one,reload_one_message=pcall(callbacks.events[1])
          local load_two,load_two_message=storage_only_load()
          local reload_two,reload_two_message=pcall(callbacks.events[1])
          return {loaded=loaded,init_ok=true,event_ok=true,research_tick=research_tick,physical_ok=true,
            load_one=load_one,load_one_message=tostring(load_one_message),reload_one=reload_one,reload_one_message=tostring(reload_one_message),
            load_two=load_two,load_two_message=tostring(load_two_message),reload_two=reload_two,reload_two_message=tostring(reload_two_message),
            logs=logs,saves=saves,labs=#labs,phase=environment.storage.mir5_bob_angel_f200_combined_gameplay.phase,
            output=environment.storage.mir5_bob_angel_f200_combined_gameplay.physical_output,
            saved_target_level=environment.storage.mir5_bob_angel_f200_combined_gameplay.saved_target_level,
            current_research_unit_count=target.research_unit_count,current_research_unit_energy=target.research_unit_energy,report=report}
        ''')

    def test_runtime_uses_named_upstream_only_real_labs_real_route_and_two_read_only_reloads(self):
        result = self.runtime_protocol()
        self.assertTrue(result["loaded"])
        self.assertTrue(result["init_ok"])
        self.assertTrue(result["event_ok"])
        self.assertTrue(result["research_tick"])
        self.assertTrue(result["physical_ok"])
        self.assertTrue(result["load_one"], result["load_one_message"])
        self.assertTrue(result["reload_one"], result["reload_one_message"])
        self.assertTrue(result["load_two"], result["load_two_message"])
        self.assertTrue(result["reload_two"], result["reload_two_message"])
        self.assertEqual((100, "complete", 440, 3, 1),
                         (result["labs"], result["phase"], result["output"], result["logs"], result["saves"]))
        self.assertEqual(2, result["saved_target_level"])
        self.assertEqual((16000, 3600),
                         (result["current_research_unit_count"], result["current_research_unit_energy"]))
        self.assertEqual("MIR5BobAngelF200CombinedGameplayReportV1", result["report"]["kind"])
        self.assertEqual("pending-fresh-en-de-library-observations", result["report"]["library_stage"]["status"])
        self.assertEqual(["MIR5English", "MIR5Deutsch"], [result["report"]["library_stage"]["required_roles"][index] for index in (1, 2)])
        self.assertTrue(result["report"]["library_stage"]["fresh_screenshots"])
        self.assertTrue(result["report"]["library_stage"]["fresh_query"])
        self.assertTrue(result["report"]["library_stage"]["role_and_native_state_readback"])
        self.assertFalse(result["report"]["library_stage"]["input_simulation"])
        self.assertFalse(result["report"]["library_stage"]["base_or_space_age_claim"])

    def test_runtime_product_optional_zero_defaults_do_not_change_the_fixed_output(self):
        result = self.runtime_protocol("product-optional-omitted")
        self.assertTrue(result["loaded"])
        self.assertTrue(result["init_ok"])
        self.assertTrue(result["physical_ok"])
        self.assertTrue(result["load_one"])
        self.assertTrue(result["reload_one"])
        self.assertTrue(result["load_two"])
        self.assertTrue(result["reload_two"])
        self.assertEqual((440, "complete"), (result["output"], result["phase"]))

    def test_runtime_refuses_independent_row_lab_owner_or_machine_drift_before_success(self):
        for opponent, phrase in (
            ("energy-seconds", "complete steel technology row differs: "),
            ("prototype-absent", "complete steel technology row differs: prototype_type=nil;max_level=<getter-error>"),
            ("effect", "steel productivity effects differ"),
            ("ingredients-count", "steel research science differs"),
            ("ingredients-order", "steel research science differs"),
            ("drain", "native biolab differs"),
            ("lab-input", "native biolab differs"),
            ("lab-input-table", "native lab input type differs"),
            ("lab-speed-missing", "native biolab differs"),
            ("lab-speed-nil", "native biolab differs"),
            ("lab-speed", "native biolab differs"),
            ("route-category", "steel physical route identity differs"),
            ("product-probability", "steel physical output differs"),
            ("product-probability-missing", "steel physical output differs"),
            ("product-extra", "steel physical output differs"),
            ("product-ignored", "steel physical output differs"),
            ("product-stats", "steel physical output differs"),
            ("product-spoiled", "steel physical output differs"),
            ("ingredient-ignored", "steel physical input differs"),
            ("route-additional-category", "steel physical additional category count differs"),
            ("machine-speed-missing", "unchanged assembling-machine-1 differs"),
            ("machine-speed", "unchanged assembling-machine-1 differs"),
            ("machine-quality", "unchanged assembling-machine-1 differs"),
            ("quality", "native biolab differs"),
            ("surface", "native biolab differs"),
            ("owner-preseed", "named upstream prerequisite was pre-researched"),
            ("route-enabled", "fresh steel route differs"),
            ("owner", "steel force route differs"),
            ("category", "unchanged assembling-machine-1 differs"),
        ):
            with self.subTest(opponent=opponent):
                result = self.runtime_protocol(opponent)
                self.assertTrue(result["loaded"])
                if opponent in ("energy-seconds", "prototype-absent", "effect", "ingredients-count", "ingredients-order", "drain", "lab-input", "lab-input-table", "lab-speed-missing", "lab-speed-nil", "lab-speed", "route-category", "route-additional-category", "product-probability", "product-probability-missing", "product-extra", "product-ignored", "product-stats", "product-spoiled", "ingredient-ignored", "quality", "surface", "owner-preseed", "route-enabled", "owner"):
                    self.assertFalse(result["init_ok"])
                else:
                    self.assertTrue(result["init_ok"])
                    self.assertFalse(result["research_tick"])
                self.assertIn(phrase, result["message"])
                if opponent == "energy-seconds":
                    for detail in (
                        "prototype_type=table",
                        "max_level=number:4294967295",
                        "level=number:1",
                        "upgrade=boolean:true",
                        "order=string:p[research_steel]",
                        "current_level=number:1",
                        "current_research_unit_count=number:8000",
                        "current_research_unit_energy=number:60",
                    ):
                        self.assertIn(detail, result["message"])
                self.assertEqual((0, 0), (result["logs"] or 0, result["saves"] or 0))

    def test_runtime_refuses_a_stale_level_one_cost_after_level_two_before_physical_or_save(self):
        result = self.runtime_protocol("stale-count-after-level-two")
        self.assertTrue(result["loaded"])
        self.assertTrue(result["init_ok"])
        self.assertTrue(result["event_ok"])
        self.assertFalse(result["research_tick"])
        self.assertIn("complete steel technology row differs: ", result["message"])
        self.assertIn("current_level=number:2", result["message"])
        self.assertIn("current_research_unit_count=number:8000", result["message"])
        self.assertIn("current_research_unit_energy=number:3600", result["message"])
        self.assertEqual((0, 0), (result["logs"] or 0, result["saves"] or 0))

    def test_on_load_refuses_missing_storage_only_witness_without_game_access(self):
        result = self.runtime_protocol("saved-scalar")
        self.assertTrue(result["loaded"])
        self.assertTrue(result["init_ok"])
        self.assertTrue(result["event_ok"])
        self.assertTrue(result["research_tick"])
        self.assertTrue(result["physical_ok"])
        self.assertFalse(result["load_one"])
        self.assertIn("cold reload storage witness differs", result["load_one_message"])
        self.assertNotIn("on_load game access", result["load_one_message"])

    def test_fixture_does_not_substitute_mir_research_recipe_enablement_or_library_input(self):
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn('local UPSTREAM = {"automation-science-pack", "logistic-science-pack", OWNER}', source)
        self.assertIn("local LAB_COUNT = 100", source)
        self.assertIn("local EXPECTED_SCIENCE_CONSUMPTION = 4000", source)
        self.assertIn("local EXPECTED_OUTPUT = 440", source)
        self.assertIn('machine.set_recipe(ROUTE)', source)
        self.assertIn('physical_roll_batch=BATCH', source)
        self.assertIn('input_simulation=false', source)
        self.assertNotIn("research_recursive", source)
        self.assertNotIn("enable_all_prototypes", source)
        self.assertNotIn("recipe.enabled =", source)
        self.assertNotIn("target(game.forces.player).researched =", source)
        self.assertNotIn("target(game.forces.player).saved_progress =", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(CombinedSteelGameplayFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
