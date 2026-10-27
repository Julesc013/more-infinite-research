"""Independent q009/q010 F210 Bob+Angel data-final pipeline control.

The compact context contains upstream prototypes only.  Its B6 rows are a
separate historical oracle: current candidate data is never an input to these
expectations or to source admission.
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
SOURCE_ROOT = ROOT / "source"
CONTEXT = ROOT / "tests/fixtures/bob-angel-f210-upstream-context.json.gz"
MAX_CONTEXT_BYTES = 2 * 1024 * 1024
R04_PLAN_SHA256 = "524425A246135ECAA957A472D1E70B87D96F21CD2164887E78D8CC0ED9693E85"
F210_SHA256 = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
PUBLISHED_B6_SHA256 = "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852"
CAPTURE_HASHES = {
    "base": {
        "upstream_result": "C5D5F65FC0412D88A5A6CAFD1E439214D87CDE451D1BA1586A4CB0FB4CB22E1E",
        "upstream_raw": "77EAA31B5BA3BC58915E717FD2243BAF1FD6ACFFD9EA9328CC7CFAB8998E1BD3",
        "published_result": "C34FEA8FE3FD291167FC78622FF3B9892F6843C91F6AF59D055E3EDA9717898E",
        "published_raw": "742447E96872EE100F7ACF1131C16C89631057144E98AA1FBC5CC61C00FF4E55",
    },
    "space_age": {
        "upstream_result": "17DEC8EB28C63818458414D338116F5172608EF0CFA8ED90445EACD642CF547C",
        "upstream_raw": "3CEA9040B2ABCB5BD9E8615AC2866A798DACE7B6B31A999CB498B8CFCCA8AB92",
        "published_result": "688BF167F8CA500DB9FA65240B1A16EA2D735141BF5233F807BE77C3958C1C38",
        "published_raw": "A8935196FBF9A58DA01BB26EFD739CE74941DB2885C6A1514E9379F64A33C3C1",
    },
}

# Independent B6 settings receipts: q009 Base and q010 Space Age each expose
# all seven startup controls for these twenty material families.  The source
# catalogue is not an oracle for this finite visibility set.
PUBLISHED_SETTINGS_RECEIPTS = {
    "base": {
        "result_sha256": "C34FEA8FE3FD291167FC78622FF3B9892F6843C91F6AF59D055E3EDA9717898E",
        "settings_sha256": "E6B637555269C37B07108DE4F9342B6AEB9A55403F52DFCBE8403349647105B3",
    },
    "space_age": {
        "result_sha256": "E0B9A8A6473FFB1ED23365AA9F2C14F57A0DF411C6D10F46E112D9534DCC0CCA",
        "settings_sha256": "5385BE2E5B4ADD9EC17FAFEB7AB2A01FA60987AAEA849C77347618BD5E8CBBA4",
    },
}
BOB_ANGEL_MATERIAL_FAMILIES = (
    "aluminium", "brass", "bronze", "cobalt_steel", "copper_tungsten",
    "glycerol", "gold", "gunmetal", "hydrochloric_acid", "hydrofluoric_acid",
    "invar", "lead", "nickel", "nitinol", "nitric_acid", "platinum",
    "silver", "tin", "titanium", "zinc",
)
MATERIAL_SETTING_PREFIXES = (
    "ips-enable-", "ips-cost-base-", "ips-cost-linear-increment-",
    "ips-cost-growth-", "ips-max-level-", "ips-research-time-",
    "ips-effect-per-level-",
)


def _lua_value(lua, value):
    if isinstance(value, dict):
        table = lua.table()
        for key, nested in value.items():
            table[key] = _lua_value(lua, nested)
        return table
    if isinstance(value, list):
        table = lua.table()
        for index, nested in enumerate(value, start=1):
            table[index] = _lua_value(lua, nested)
        return table
    return value


def _plain(value):
    if not hasattr(value, "items"):
        return value
    items = dict(value.items())
    if items and set(items) == set(range(1, len(items) + 1)):
        return [_plain(items[index]) for index in range(1, len(items) + 1)]
    return {key: _plain(nested) for key, nested in items.items()}


def _contract(row):
    fields = (
        "type", "name", "icon", "icon_size", "icons", "localised_name", "localised_description",
        "level", "upgrade", "max_level", "order", "enabled", "hidden", "visible_when_disabled",
        "show_levels_info", "prerequisites", "effects", "unit",
    )
    return {key: row.get(key) for key in fields}


class BobAngelF210PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if CONTEXT.stat().st_size > MAX_CONTEXT_BYTES:
            raise AssertionError("Bob+Angel F210 upstream context exceeds 2 MiB compressed")
        cls.context = json.loads(gzip.decompress(CONTEXT.read_bytes()))
        if cls.context.get("schema") != "MIR5BobAngelF210UpstreamPipelineContextV1":
            raise AssertionError("Bob+Angel F210 context schema changed")

    def stage(self, case, startup=None, raw=None, mods=None, expect_failure=False):
        source = self.context["cases"][case]
        raw = deepcopy(source["raw"] if raw is None else raw)
        mods = deepcopy(source["selection"] if mods is None else mods)
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.globals().captured_raw = _lua_value(lua, raw)
        lua.globals().active_mods = _lua_value(lua, mods)
        lua.globals().startup_values = _lua_value(lua, startup or {})
        lua.execute(r'''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua"; package.cpath=""
          mods,script,helpers,log=active_mods,nil,{},function() end
          data={raw=captured_raw}; settings_rows,emitted,technology_publications={},{},0
          function data:extend(rows)
            local published=false
            for _,row in ipairs(rows) do
              self.raw[row.type]=self.raw[row.type] or {}
              assert(self.raw[row.type][row.name]==nil,"duplicate "..row.type..":"..row.name)
              self.raw[row.type][row.name]=row
              if row.setting_type=="startup" then settings_rows[row.name]=row end
              if row.type=="technology" then emitted[row.name]=row; published=true end
            end
            if published then technology_publications=technology_publications+1 end
          end
          local target=require("platform.target")
          target.id,target.factorio_version,target.minimum_base="f210","2.1","2.1.23"
          target.distribution_version,target.cargo_research="5.0.21000",true
          target.recipe_probability,target.receiver_limits,target.productivity_ignores_stats="independent_probability",true,true
          assert(loadfile(player_root.."/settings.lua"))()
          local declared={}
          for name,row in pairs(settings_rows) do declared[name]={value=row.default_value} end
          for name,value in pairs(startup_values) do
            assert(declared[name]~=nil,"unknown startup override "..tostring(name))
            declared[name]={value=value}
          end
          settings={startup=declared}
          assert(loadfile(player_root.."/data.lua"))()
          emitted,technology_publications={},0
          outcome,message=pcall(function() assert(loadfile(player_root.."/data-final-fixes.lua"))() end)
          if outcome then declared_runtime=require("research.catalogue").declared() end
        ''')
        if expect_failure:
            self.assertFalse(lua.globals().outcome)
        else:
            self.assertTrue(lua.globals().outcome, str(lua.globals().message))
        return lua

    def _rows(self, lua):
        # Published B6 rows include both authored technologies and named
        # upstream owners that the data-final patch preserves in place (for
        # example Space Age steel).  Compare the actual final prototype
        # surface, while retaining `emitted` separately for no-write guards.
        rows = _plain(lua.globals().data.raw)["technology"]
        rows.update(_plain(lua.globals().emitted))
        return rows

    def _expected(self, case):
        return self.context["cases"][case]["expected_published_technologies"]

    @staticmethod
    def _setting_rows(lua):
        return _plain(lua.globals().settings_rows)

    def test_context_is_bounded_upstream_only_and_binds_exact_r04_inputs(self):
        self.assertLessEqual(CONTEXT.stat().st_size, MAX_CONTEXT_BYTES)
        self.assertEqual(R04_PLAN_SHA256, self.context["r04"]["plan_sha256"])
        self.assertEqual(F210_SHA256, self.context["r04"]["engine_sha256"])
        self.assertEqual(PUBLISHED_B6_SHA256, self.context["r04"]["published_archive_sha256"])
        self.assertIn("candidate raw", self.context["projection_rules"]["excludes"])
        self.assertIn("candidate expectations", self.context["projection_rules"]["excludes"])
        for case, expected_id in (("base", "q009"), ("space_age", "q010")):
            with self.subTest(case=case):
                source = self.context["cases"][case]
                self.assertEqual(expected_id, source["case_id"])
                self.assertEqual("MIR5PrototypeCaptureV1", source["source_result"]["kind"])
                self.assertEqual("completed-data-stage-observation-only", source["source_result"]["status"])
                self.assertEqual(CAPTURE_HASHES[case]["upstream_result"], source["source_result"]["sha256"])
                self.assertEqual(CAPTURE_HASHES[case]["upstream_raw"], source["source_data_raw_dump"]["sha256"])
                self.assertEqual("MIR5PrototypeCaptureV1", source["published_result"]["kind"])
                self.assertEqual("completed-data-stage-observation-only", source["published_result"]["status"])
                self.assertEqual(CAPTURE_HASHES[case]["published_result"], source["published_result"]["sha256"])
                self.assertEqual(CAPTURE_HASHES[case]["published_raw"], source["published_data_raw_dump"]["sha256"])
                self.assertEqual(PUBLISHED_B6_SHA256, source["published_result"]["mir_archive"]["sha256"])
                self.assertEqual(source["projection_counts"], {
                    kind: len(rows) for kind, rows in source["raw"].items()
                })
                self.assertNotIn("more-infinite-research", source["selection"])
                self.assertIn("bobplates", source["selection"])
                self.assertIn("bobrevamp", source["selection"])
                self.assertIn("bobtech", source["selection"])
                self.assertIn("angelssmelting", source["selection"])
                # These are the actual MIR continuations, not the unchanged
                # finite upstream level-7 inputs that the first projection used.
                correction = self.context["projection_correction"]
                self.assertEqual("948706da28a350ad83cf5c1be016bced4ae4dbd1", correction["prior_context_commit"])
                self.assertEqual("F5A6130BAD696A130CDBD717918377CDCEF1A518D7E465FE9D0E33202F65E9F4",
                                 correction["prior_context_sha256"])
                for family in ("braking-force", "laser-shooting-speed"):
                    name = family + "-8"
                    row = self._expected(case)[name]
                    self.assertNotIn(family + "-7", self._expected(case))
                    self.assertNotIn(name, source["raw"]["technology"])
                    self.assertEqual("infinite", row["max_level"])
                    self.assertEqual(8, row["level"])
                    binding = correction["rows"][case][name]
                    self.assertEqual(family + "-7", binding["replaces_expected_id"])
                    self.assertEqual(CAPTURE_HASHES[case]["published_raw"], binding["published_raw_sha256"])
                    self.assertEqual(binding["row_sha256"], hashlib.sha256(
                        json.dumps(row, sort_keys=True, separators=(",", ":")).encode()).hexdigest().upper())
        self.assertNotIn("space-age", self.context["cases"]["base"]["selection"])
        self.assertIn("space-age", self.context["cases"]["space_age"]["selection"])

    def test_full_settings_data_and_final_pipeline_matches_independent_b6_rows(self):
        for case, expected_count in (("base", 12), ("space_age", 11)):
            with self.subTest(case=case):
                rows = self._rows(self.stage(case))
                expected = self._expected(case)
                self.assertEqual(expected_count, len(expected))
                for name, published in expected.items():
                    self.assertIn(name, rows, name)
                    self.assertEqual(_contract(published), _contract(rows[name]), name)
        base_rows = self._rows(self.stage("base"))
        space_rows = self._rows(self.stage("space_age"))
        self.assertIn("recipe-prod-research_material_copper_tungsten-1", base_rows)
        self.assertNotIn("recipe-prod-research_material_copper_tungsten-1", space_rows)
        for rows in (base_rows, space_rows):
            self.assertNotIn("recipe-prod-research_material_aluminium-1", rows)

    def test_full_bob_angel_material_settings_keep_the_b6_visible_absence_and_partial_closure_hidden(self):
        for case in ("base", "space_age"):
            with self.subTest(case=case):
                source = self.context["cases"][case]
                receipt = PUBLISHED_SETTINGS_RECEIPTS[case]
                self.assertTrue(all(len(receipt[field]) == 64 for field in receipt))
                active = self._setting_rows(self.stage(case))
                partial_mods = deepcopy(source["selection"])
                partial_mods.pop("bobtech")
                partial = self._setting_rows(self.stage(case, mods=partial_mods))
                for family in BOB_ANGEL_MATERIAL_FAMILIES:
                    for prefix in MATERIAL_SETTING_PREFIXES:
                        name = f"{prefix}research_material_{family}"
                        self.assertIn(name, active)
                        self.assertNotIn("hidden", active[name], name)
                        self.assertIn(name, partial)
                        self.assertIs(partial[name].get("hidden"), True, name)
                        self.assertEqual(
                            {key: value for key, value in active[name].items() if key != "hidden"},
                            {key: value for key, value in partial[name].items() if key != "hidden"},
                            name,
                        )

    def test_carbon_keeps_published_products_when_angel_repurposes_the_recipe(self):
        raw = self.context["cases"]["space_age"]["raw"]
        self.assertEqual([{"type": "item", "name": "angels-solid-carbon", "amount": 2}],
                         raw["recipe"]["carbon"]["results"])
        self.assertFalse(raw["recipe"]["carbon"]["allow_productivity"])
        row = self._rows(self.stage("space_age"))["recipe-prod-research_carbon-1"]
        # Exact B6 q010 effect vector, independently retained in A8935196…C3C1.
        self.assertEqual([
            {"type": "change-recipe-productivity", "recipe": "burnt-spoilage", "change": 0.05},
            {"type": "change-recipe-productivity", "recipe": "coal-synthesis", "change": 0.02},
        ], row["effects"])

    def test_configured_and_disabled_streams_preserve_named_boundaries(self):
        base_default = self._rows(self.stage("base"))
        base_configured = self._rows(self.stage("base", {
            "ips-cost-base-research_breeding": 250,
            "ips-cost-growth-research_breeding": 3,
            "ips-research-time-research_breeding": 45,
            "ips-effect-per-level-research_breeding": 25,
        }))
        breeding = base_configured["recipe-prod-research_breeding-1"]
        self.assertEqual("250*3^(L-1)", breeding["unit"]["count_formula"])
        self.assertEqual(45, breeding["unit"]["time"])
        self.assertEqual(
            [row["recipe"] for row in base_default["recipe-prod-research_breeding-1"]["effects"]],
            [row["recipe"] for row in breeding["effects"]],
        )
        self.assertEqual([0.25] * 9, [row["change"] for row in breeding["effects"]])
        base_disabled = self._rows(self.stage("base", {"ips-enable-research_breeding": False}))
        self.assertFalse(base_disabled["recipe-prod-research_breeding-1"]["enabled"])
        self.assertEqual(base_default["recipe-prod-research_breeding-1"]["effects"],
                         base_disabled["recipe-prod-research_breeding-1"]["effects"])

        space_default = self._rows(self.stage("space_age"))
        space_configured = self._rows(self.stage("space_age", {
            "ips-cost-base-research_steel": 250,
            "ips-cost-linear-increment-research_steel": 3,
            "ips-cost-growth-research_steel": 1.5,
            "ips-research-time-research_steel": 45,
            "ips-effect-per-level-research_steel": 25,
        }))
        steel = space_configured["steel-plate-productivity"]
        self.assertEqual("(250+3*(L-1))*1.5^(L-1)", steel["unit"]["count_formula"])
        self.assertEqual(45, steel["unit"]["time"])
        self.assertEqual(
            ["steel-plate", "casting-steel", "angels-plate-steel", "angels-plate-steel-2"],
            [effect["recipe"] for effect in steel["effects"]],
        )
        self.assertEqual([0.25] * 4, [effect["change"] for effect in steel["effects"]])
        space_disabled = self._rows(self.stage("space_age", {"ips-enable-research_steel": False}))
        disabled_effects = space_disabled["steel-plate-productivity"]["effects"]
        self.assertEqual(space_default["steel-plate-productivity"]["effects"][:2], disabled_effects)
        self.assertEqual(["steel-plate", "casting-steel"], [effect["recipe"] for effect in disabled_effects])

    def test_named_route_owner_and_science_drift_refuse_before_technology_publication(self):
        scenarios = (
            ("base", lambda raw: raw["recipe"].pop("bob-copper-tungsten-alloy"), "bob-copper-tungsten-alloy"),
            ("base", lambda raw: raw["technology"]["bob-advanced-logistic-science-pack"]["effects"].clear(),
             "Bob advanced science route"),
            ("space_age", lambda raw: raw["technology"]["steel-plate-productivity"]["effects"].pop(0),
             "steel-plate-productivity existing effect"),
            ("space_age", lambda raw: raw["technology"]["steel-plate-productivity"]["effects"].append(
                deepcopy(raw["technology"]["steel-plate-productivity"]["effects"][0])),
             "steel-plate-productivity existing effect"),
            ("space_age", lambda raw: raw["technology"]["steel-plate-productivity"]["effects"].append(
                {"type": "change-recipe-productivity", "recipe": "angels-plate-steel", "change": 0.1}),
             "steel-plate-productivity already owns Angel steel"),
        )
        for case, mutate, expected in scenarios:
            with self.subTest(case=case, expected=expected):
                raw = deepcopy(self.context["cases"][case]["raw"])
                mutate(raw)
                lua = self.stage(case, raw=raw, expect_failure=True)
                self.assertIn(expected, str(lua.globals().message))
                self.assertEqual(0, lua.globals().technology_publications)

    def test_consumed_recipe_fields_accept_unconsumed_flags_and_reject_invalid_science_output(self):
        enabled = deepcopy(self.context["cases"]["base"]["raw"])
        enabled["recipe"]["angels-solid-sulfur"]["enabled"] = True
        lua = self.stage("base", raw=enabled)
        self.assertIn("recipe-prod-research_sulfur-1", self._rows(lua))

        default_output = deepcopy(self.context["cases"]["base"]["raw"])
        science = default_output["recipe"]["bob-advanced-logistic-science-pack"]
        science["allow_productivity"] = False
        science["results"][0].pop("amount")
        lua = self.stage("base", raw=default_output)
        self.assertIn("research-speed-7", self._rows(lua))

        for bad in (0, float("nan"), float("inf")):
            with self.subTest(probability=repr(bad)):
                raw = deepcopy(self.context["cases"]["base"]["raw"])
                raw["recipe"]["bob-advanced-logistic-science-pack"]["results"][0]["probability"] = bad
                lua = self.stage("base", raw=raw, expect_failure=True)
                self.assertIn("bob-advanced-logistic-science-pack", str(lua.globals().message))
                self.assertEqual(0, lua.globals().technology_publications)

    def test_space_age_steel_accepts_foreign_effect_order_but_preserves_named_owner_boundary(self):
        raw = deepcopy(self.context["cases"]["space_age"]["raw"])
        effects = raw["technology"]["steel-plate-productivity"]["effects"]
        raw["technology"]["steel-plate-productivity"]["effects"] = [
            {"type": "nothing", "effect_description": "foreign-but-retained"}, effects[1], effects[0]
        ]
        rows = self._rows(self.stage("space_age", raw=raw))
        steel = rows["steel-plate-productivity"]
        self.assertEqual("foreign-but-retained", steel["effects"][0]["effect_description"])
        self.assertEqual(
            {"steel-plate", "casting-steel", "angels-plate-steel", "angels-plate-steel-2"},
            {effect.get("recipe") for effect in steel["effects"] if effect.get("recipe") is not None},
        )

    def test_space_age_productivity_denied_breeding_and_acid_routes_are_admitted_as_captured(self):
        raw = self.context["cases"]["space_age"]["raw"]
        self.assertFalse(raw["recipe"]["fish-breeding"]["allow_productivity"])
        self.assertFalse(raw["recipe"]["acid-neutralisation"]["allow_productivity"])
        rows = self._rows(self.stage("space_age"))
        breeding = rows["recipe-prod-research_breeding-1"]
        acid = rows["recipe-prod-research_sulfuric_acid_productivity-1"]
        self.assertIn("fish-breeding", [effect["recipe"] for effect in breeding["effects"]])
        self.assertIn("acid-neutralisation", [effect["recipe"] for effect in acid["effects"]])

    def test_runtime_cap_declarations_keep_base_copper_tungsten_and_space_age_steel_boundaries(self):
        base = {row["id"]: row for row in _plain(self.stage("base").globals().declared_runtime)}
        self.assertEqual(
            {"recipe-prod-research_material_copper_tungsten-1", "recipe-prod-research_material_copper_tungsten-4"},
            {name for name in base if name.startswith("recipe-prod-research_material_copper_tungsten-")},
        )
        for name in ("recipe-prod-research_material_copper_tungsten-1", "recipe-prod-research_material_copper_tungsten-4"):
            row = base[name]
            self.assertEqual("research_material_copper_tungsten", row["family"])
            self.assertEqual("ips-max-level-research_material_copper_tungsten", row["cap_setting"])
            self.assertEqual(["bob-copper-tungsten-alloy"], row["productivity_recipes"])
        self.assertFalse(_plain(self.stage("base").globals().settings_rows)[
            "ips-enable-research_material_copper_tungsten"].get("hidden", False))

        space = {row["id"]: row for row in _plain(self.stage("space_age").globals().declared_runtime)}
        self.assertNotIn("recipe-prod-research_material_copper_tungsten-1", space)
        steel = space["steel-plate-productivity"]
        self.assertEqual("nativeowner", steel["ownership_kind"])
        self.assertEqual(
            ["steel-plate", "casting-steel", "angels-plate-steel", "angels-plate-steel-2"],
            steel["native_admission"]["recipes"],
        )

    def test_profile_is_f210_local_nonoverlapping_and_returns_fresh_data(self):
        context = self.context["cases"]["base"]
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.globals().mods_for_test = _lua_value(lua, deepcopy(context["selection"]))
        profile, first, second, pure_angel, full_bob, core, f200 = lua.execute(r'''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua"; package.cpath=""
          local target=require("platform.target")
          target.id,target.factorio_version,target.minimum_base="f210","2.1","2.1.23"
          local profile=require("compatibility.bob_angel_f210_profile")
          local data=require("compatibility.modern_catalogue.bob_angel_f210")
          local selected=profile.select(mods_for_test)
          local first,second=data.delta(selected),data.delta(selected)
          first.additions[1].effects[1].recipe="mutated-only-here"
          local pure={}; for k,v in pairs(mods_for_test) do pure[k]=v end; pure.bobplates=nil
          local bob={}; for k,v in pairs(mods_for_test) do bob[k]=v end; bob.angelssmelting=nil
          local core={}; for k,v in pairs(mods_for_test) do core[k]=v end; core.angelssmelting=nil
          local pure_selected,bob_selected,core_selected=profile.select(pure),profile.select(bob),profile.select(core)
          target.id="f200"; local legacy=profile.select(mods_for_test)
          return selected,first,second,pure_selected,bob_selected,core_selected,legacy
        ''')
        self.assertEqual("base", profile)
        self.assertNotEqual(first["additions"][1]["effects"][1]["recipe"],
                            second["additions"][1]["effects"][1]["recipe"])
        self.assertIsNone(pure_angel)
        self.assertIsNone(full_bob)
        self.assertIsNone(core)
        self.assertIsNone(f200)

    def test_asset_only_mods_and_equivalent_unlocks_do_not_disable_the_combined_profile(self):
        for case in ("base", "space_age"):
            source = self.context["cases"][case]
            baseline = self.stage(case)
            active = deepcopy(source["selection"])
            active["Krastorio2Assets"] = "2.0.0"
            active["k2so-assets"] = "2.0.0"
            raw = deepcopy(source["raw"])
            owner_name = "lithium-processing" if case == "space_age" else "bob-lithium-processing"
            owner = raw["technology"][owner_name]
            owner["effects"].append(next(deepcopy(effect) for effect in owner["effects"]
                                         if effect.get("type") == "unlock-recipe" and effect.get("recipe") == "lithium-plate"))
            lua = self.stage(case, raw=raw, mods=active)
            rows = self._rows(lua)
            for name, expected in self._expected(case).items():
                self.assertEqual(_contract(expected), _contract(rows[name]))
            self.assertEqual(_plain(baseline.globals().settings_rows), _plain(lua.globals().settings_rows))
            self.assertEqual(_plain(baseline.globals().declared_runtime), _plain(lua.globals().declared_runtime))

    def test_asset_only_mods_do_not_deactivate_other_provider_profiles(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        core, tech, warfare, py = lua.execute(r'''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua"; package.cpath=""
          local target=require("platform.target")
          target.id,target.factorio_version,target.minimum_base="f210","2.1","2.1.23"
          local assets={Krastorio2Assets="2.1.0",["k2so-assets"]="1.0.7"}
          local function copy(source)
            local out={}; for key,value in pairs(source) do out[key]=value end
            for key,value in pairs(assets) do out[key]=value end
            return out
          end
          local core=copy({base="2.1.23",["space-age"]="2.1.23",boblibrary="3",bobores="1",bobplates="1",bobelectronics="1",bobtech="1"})
          local tech=copy({base="2.1.23",["space-age"]="2.1.23",boblibrary="3",bobores="1",bobplates="1",bobelectronics="1",bobtech="1",
            angelsrefining="1",angelsrefininggraphics="1",angelspetrochem="1",angelspetrochemgraphics="1",angelssmelting="1",angelssmeltinggraphics="1"})
          local warfare=copy({bobwarfare="1"})
          local py=copy({pycoalprocessing="1",pyalienlife="1",pyhightech="1"})
          return require("compatibility.bob_core_profile").applies(core),
            require("compatibility.bob_tech_profile").applies(tech),
            require("compatibility.bob_warfare_profile").applies(warfare),
            require("compatibility.py_profile").select(py)
        ''')
        self.assertTrue(core)
        self.assertTrue(tech)
        self.assertTrue(warfare)
        self.assertEqual({"coal": False, "hightech": True}, _plain(py))

    def test_native_steel_preserves_foreign_unlocks_that_share_recipe_names(self):
        raw = deepcopy(self.context["cases"]["space_age"]["raw"])
        foreign = [
            {"type": "unlock-recipe", "recipe": "casting-steel"},
            {"type": "unlock-recipe", "recipe": "angels-plate-steel-2"},
        ]
        raw["technology"]["steel-plate-productivity"]["effects"] = foreign + raw["technology"]["steel-plate-productivity"]["effects"]
        lua = self.stage("space_age", raw=raw)
        row = _plain(lua.globals().data.raw.technology["steel-plate-productivity"])
        self.assertEqual(foreign, row["effects"][:2])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobAngelF210PipelineTests)
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)
