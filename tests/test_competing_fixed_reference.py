"""Host controls for four fixed F200 Space Age competing-provider references.

The JSON facts are archive-source inventory only.  They deliberately do not
assert native final-data, preference, ownership, or gameplay behavior.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FACTS_PATH = ROOT / "tests/fixtures/competing-fixed-f200-sa-source-facts.json"
FIXTURE = ROOT / "tests/fixtures/competing-fixed-preference"
PROFILE_ROOT = ROOT / "tests/profiles"
ARCHIVE_LIBRARY = None
ENGINE_SHA = "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B"
OBSERVER_ARCHIVE = "mir-fixture-mir5-active-mods-observer_0.1.0.zip"
OBSERVER_SHA = "723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87"
BUILTINS = (
    ("base", "2.0.77"),
    ("elevated-rails", "2.0.77"),
    ("quality", "2.0.77"),
    ("space-age", "2.0.77"),
)
EXPECTED = {
    "plates": {
        "name": "plates-n-circuit-productivity", "version": "0.0.2",
        "archive": "plates-n-circuit-productivity_0.0.2.zip",
        "profile": "competing-plates-f200-sa-2077.json",
        "ids": ("basic-plate-productivity", "electric-circuit-productivity", "advanced-circuit-productivity"),
    },
    "science-packs": {
        "name": "Science_packs_productivity", "version": "0.0.1",
        "archive": "Science_packs_productivity_0.0.1.zip",
        "profile": "competing-science-packs-f200-sa-2077.json",
        "ids": tuple(
            f"{family}-science-productivity-{level}"
            for family in ("automation", "logistic", "military", "chemical", "production", "utility", "space",
                           "metallurgic", "electromagnetic", "agricultural", "cryogenic", "promethium")
            for level in range(1, 5)
        ),
    },
    "bioflux": {
        "name": "bioflux-productivity", "version": "0.1.0",
        "archive": "bioflux-productivity_0.1.0.zip",
        "profile": "competing-bioflux-f200-sa-2077.json",
        "ids": ("bioflux-productivity",),
    },
    "fish": {
        "name": "fish-productivity", "version": "1.0.0",
        "archive": "fish-productivity_1.0.0.zip",
        "profile": "competing-fish-f200-sa-2077.json",
        "ids": ("fish-breeding-productivity",),
    },
}


class FixedCompetingReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        cls.by_key = {provider["key"]: provider for provider in cls.facts["providers"]}

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          function fixed_competing_preference(path, incoming, setting)
            local reads = {}
            local env = {
              mods = incoming,
              data = {raw = { ["bool-setting"] = setting and {
                ["mir-prefer-this-mod-for-competing-techs"] = setting
              } or {} }},
              type = type, pairs = pairs, error = error,
            }
            env._G = env
            setmetatable(env, {__index=function(_, key)
              reads[key] = (reads[key] or 0) + 1
              error("unexpected fixture global read: " .. tostring(key))
            end})
            local chunk, message = loadfile(path, "t", env)
            assert(chunk, message)
            local ok, result = pcall(chunk)
            local preference = env.data.raw["bool-setting"]["mir-prefer-this-mod-for-competing-techs"]
            return {ok=ok, message=tostring(result), reads=reads,
              default_value=preference and preference.default_value or nil}
          end
        ''')

    @staticmethod
    def _mods(provider=None, version=None):
        values = {name: value for name, value in BUILTINS}
        values["more-infinite-research"] = "4.7.20002"
        values["mir-fixture-mir5-active-mods-observer"] = "0.1.0"
        if provider is not None:
            values[provider] = version
        return values

    def _fixture(self, mods, setting=True):
        return self.lua.eval("fixed_competing_preference")(
            str(FIXTURE / "settings-updates.lua"), self.lua.table_from(mods),
            None if setting is None else self.lua.table_from({"setting_type": "startup", "default_value": setting}),
        )

    def test_portable_facts_describe_exactly_the_four_archive_source_subjects(self):
        self.assertEqual("archive-source-facts-only-not-native-reference", self.facts["status"])
        self.assertEqual(("2.0.77", ENGINE_SHA),
                         (self.facts["engine"]["version"], self.facts["engine"]["sha256"]))
        self.assertEqual(tuple(EXPECTED), tuple(provider["key"] for provider in self.facts["providers"]))
        self.assertEqual([(name, version, True) for name, version in BUILTINS],
                         [(row["name"], row["version"], row["enabled"])
                          for row in self.facts["selection_closure"]["builtins"]])
        self.assertEqual({"archive": OBSERVER_ARCHIVE, "sha256": OBSERVER_SHA},
                         self.facts["selection_closure"]["observer"])
        for key, expected in EXPECTED.items():
            with self.subTest(provider=key):
                actual = self.by_key[key]
                self.assertEqual((expected["name"], expected["version"], expected["archive"]),
                                 (actual["info"]["name"], actual["info"]["version"], actual["archive"]))
                self.assertEqual(expected["ids"], tuple(actual["declared_technology_ids"]))
                self.assertRegex(actual["sha256"], r"^[A-F0-9]{64}$")
                self.assertTrue(actual["source_member"].endswith(".lua"))
        self.assertEqual(48, len(self.by_key["science-packs"]["declared_technology_ids"]))

    def test_four_profiles_are_independent_f200_space_age_upstream_selections(self):
        for key, expected in EXPECTED.items():
            with self.subTest(provider=key):
                profile = json.loads((PROFILE_ROOT / expected["profile"]).read_text(encoding="utf-8"))
                self.assertEqual(("f200", "2.0", "2.0.77", ENGINE_SHA),
                                 (profile["target"], profile["factorio_line"], profile["engine"]["version"],
                                  profile["engine"]["sha256"]))
                self.assertEqual("Defaults", profile["settings_mode"])
                self.assertEqual([name for name, _ in BUILTINS] + [expected["name"],
                                 "mir-fixture-mir5-active-mods-observer"],
                                 [row["name"] for row in profile["mods"]])
                self.assertEqual([version for _, version in BUILTINS] + [expected["version"], "0.1.0"],
                                 [row["version"] for row in profile["mods"]])
                self.assertTrue(all(row["enabled"] is True for row in profile["mods"]))
                self.assertNotIn("more-infinite-research", [row["name"] for row in profile["mods"]])
                self.assertNotIn("mir-fixture-mir5-fixed-competing-preference",
                                 [row["name"] for row in profile["mods"]])
                self.assertEqual({expected["archive"]: self.by_key[key]["sha256"],
                                  OBSERVER_ARCHIVE: OBSERVER_SHA}, profile["archive_sha256"])
                self.assertIn("no native, preference, or gameplay claim", profile["scope"])

    def test_fixed_preference_fixture_accepts_one_exact_provider_and_changes_only_the_default(self):
        for key, expected in EXPECTED.items():
            with self.subTest(provider=key):
                result = self._fixture(self._mods(expected["name"], expected["version"]))
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual({}, dict(result["reads"]))
                self.assertFalse(result["default_value"])
        source = (FIXTURE / "settings-updates.lua").read_text(encoding="utf-8")
        self.assertNotIn("pairs(mods)", source)
        self.assertNotIn("data:extend", source)
        self.assertNotIn("game", source)

    def test_fixed_preference_fixture_refuses_incompatible_or_ambiguous_inputs(self):
        plates = EXPECTED["plates"]
        cases = {
            "absent-provider": (self._mods(), "exactly one supported fixed provider"),
            "wrong-provider-version": (self._mods(plates["name"], "0.0.1"), "unsupported provider version"),
            "two-providers": ({**self._mods(plates["name"], plates["version"]),
                               EXPECTED["fish"]["name"]: EXPECTED["fish"]["version"]},
                              "exactly one supported fixed provider"),
            "wrong-mir": ({**self._mods(plates["name"], plates["version"]), "more-infinite-research": "5.0.20000"},
                          "unexpected F200 Space Age published reference closure"),
        }
        for label, (mods, phrase) in cases.items():
            with self.subTest(case=label):
                result = self._fixture(mods)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
        malformed = self._fixture(self._mods(plates["name"], plates["version"]), setting=None)
        self.assertFalse(malformed["ok"])
        self.assertIn("preference setting is absent or malformed", malformed["message"])

    def test_local_archive_source_matches_portable_facts_when_the_pinned_library_is_present(self):
        if ARCHIVE_LIBRARY is None:
            self.skipTest("archive source verification requires --archive-library")
        if not ARCHIVE_LIBRARY.is_dir():
            self.fail("provided archive library is not a directory: " + str(ARCHIVE_LIBRARY))
        missing = [provider["archive"] for provider in self.facts["providers"]
                   if not (ARCHIVE_LIBRARY / provider["archive"]).is_file()]
        if missing:
            self.fail("provided archive library is missing pinned inputs: " + ", ".join(missing))
        for provider in self.facts["providers"]:
            with self.subTest(provider=provider["key"]):
                path = ARCHIVE_LIBRARY / provider["archive"]
                self.assertEqual(provider["sha256"], hashlib.sha256(path.read_bytes()).hexdigest().upper())
                with zipfile.ZipFile(path) as archive:
                    info_name = next(name for name in archive.namelist() if name.endswith("/info.json"))
                    info = json.loads(archive.read(info_name))
                    source = archive.read(provider["source_member"]).decode("utf-8")
                self.assertEqual(provider["info"], {key: info.get(key, []) if key == "dependencies" else info[key]
                                                    for key in ("name", "version", "factorio_version", "dependencies")})
                names = re.findall(r'\bname\s*=\s*"([^"]+)"', source)
                if provider["key"] == "science-packs":
                    names = [name for name in names if name.endswith(("-1", "-2", "-3", "-4"))
                             and "-science-productivity-" in name]
                self.assertEqual(provider["declared_technology_ids"], names)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    parser.add_argument("--archive-library", type=Path,
                        help="Optional exact archive library for read-only ZIP source verification.")
    args = parser.parse_args()
    ARCHIVE_LIBRARY = args.archive_library.resolve(strict=True) if args.archive_library else None
    if ARCHIVE_LIBRARY is not None and not ARCHIVE_LIBRARY.is_dir():
        parser.error("--archive-library must name a directory")
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(FixedCompetingReferenceTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)