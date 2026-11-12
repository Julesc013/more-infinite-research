"""Pin the lean native-input selections for the Angel/Bob rebalance report.

These are host-only profile checks.  They neither mount a direct library nor
launch Factorio, so they cannot establish the reported startup, productivity,
save, cold-reload, beta, or release outcome.
"""
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PROFILES = ROOT / "tests/profiles"
UPSTREAM_PATH = PROFILES / "angelbob-rebalance-space-age-f210-2123-upstream.json"
RUNTIME_PATH = PROFILES / "angelbob-rebalance-space-age-f210-2123-steel-fixture.json"
CAPTURE_CONTROLLER = ROOT / "tools/Invoke-PrototypeCapture.ps1"
ENGINE = {
    "version": "2.1.23",
    "sha256": "8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38",
    "path": "D:/Games/Factorio/2.1/bin/x64/factorio.exe",
}
MIR_NAME = "more-infinite-research"
MIR_VERSION = "5.0.21013"
MIR_ARCHIVE = "more-infinite-research_5.0.21013.zip"
MIR_SHA256 = "E92714D1E25B5BF5927FD131FF39F51CBB4FB97C305ECE722F7EA2797C88A38F"
FIXTURE_NAME = "mir-fixture-mir5-angelbob-f210-steel"
FIXTURE_VERSION = "0.1.0"
FIXTURE_ARCHIVE = f"{FIXTURE_NAME}_{FIXTURE_VERSION}.zip"
FIXTURE_SHA256 = "B1255AD3F777F188721DFCF4F0655DE9D37531886D730F9A17148F548C2B4C34"
PREOWNED_NAME = "mir-fixture-mir5-preowned-steel"
PREOWNED_SHA256 = "77967A9E8A3F19CE11BF21BCF50AA0B481535ECDD2EA3E449F952603A2AD334B"
CURRENT_DIRECT_OBSERVER_SHA256 = "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C"
OLDER_STANDALONE_OBSERVER_SHA256 = "A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0"

# This is the recursively required closure read from the official rebalance
# 1.3.2 info.json and the exact selected direct-library archive metadata.  It
# deliberately does not turn rebalance's optional integrations into a whole
# modpack fingerprint.
UPSTREAM_MODS = {
    "angelbob-spaceage-rebalance": "1.3.2",
    "angelsbioprocessing": "2.1.1",
    "angelsbioprocessinggraphics": "2.1.0",
    "angelspetrochem": "2.1.3",
    "angelspetrochemgraphics": "2.1.0",
    "angelsrefining": "2.1.2",
    "angelsrefininggraphics": "2.1.0",
    "angelssmelting": "2.1.1",
    "angelssmeltinggraphics": "2.1.1",
    "base": "2.1.23",
    "bobassembly": "3.0.1",
    "bobelectronics": "3.0.1",
    "boblibrary": "3.0.1",
    "boblogistics": "3.0.1",
    "bobmodules": "3.0.1",
    "bobores": "3.0.0",
    "bobplates": "3.0.2",
    "bobpower": "3.0.0",
    "bobrevamp": "3.0.0",
    "bobtech": "3.0.0",
    "elevated-rails": "2.1.23",
    "quality": "2.1.23",
    "recycler": "2.1.23",
    "space-age": "2.1.23",
    "mir-fixture-mir5-active-mods-observer": "0.1.0",
}
BUILTINS = {"base", "elevated-rails", "quality", "recycler", "space-age"}
UPSTREAM_ARCHIVES = {
    "angelbob-spaceage-rebalance_1.3.2.zip": "9A4B1FDA104994955929CA56F6E882A4741F3FF668C3F6948D3C6FF4E5833B00",
    "angelsbioprocessing_2.1.1.zip": "04389A72530BA2A5FC19F615FFE5861D987D251C8193319F9929F029B4A0D566",
    "angelsbioprocessinggraphics_2.1.0.zip": "54D0174D8762B5C3D114742D8C446BBE4F489C04B1399981BB60FC812C085AB0",
    "angelspetrochem_2.1.3.zip": "95FA8F1740A180E5CF5617EFDA7C409A7974E29B236F9F5AB28D789193AC44B4",
    "angelspetrochemgraphics_2.1.0.zip": "DECDC2FCD5BBBDEF70784943C142C30FAA7294B98E814296C5D44D09A9DE4790",
    "angelsrefining_2.1.2.zip": "AF5E79E35E591F68D52F13EDA082950E10AC98A4B7722B3F568D0211E3FEB813",
    "angelsrefininggraphics_2.1.0.zip": "79F373BC628F619EDE3B1875827172390D2C3F5EAB56310F6F1572C4553CB6EF",
    "angelssmelting_2.1.1.zip": "1DFCDD77D075FD545CFEE74BD8A6443E7E90B133D3832FDD47649C84892243A9",
    "angelssmeltinggraphics_2.1.1.zip": "71E89ABF7CC372FADE39B11FB4FE83A1B5E629226AF123BFE8DDA08C7C228DD3",
    "bobassembly_3.0.1.zip": "52C1F487015F1CFA0329A90FAEED4CED7EF4D875A6D91CEDAD011BA3E483F5D6",
    "bobelectronics_3.0.1.zip": "50C2718E38D507CF4D4ACA2DBFE3240997172309413397C9C70083BBAE6927BE",
    "boblibrary_3.0.1.zip": "3DD83A195E120BAECC51A43B0B3EB965C0D419A09883F9DAA018B3921C12D51B",
    "boblogistics_3.0.1.zip": "EA308A09B5601933AA5A75B3C7DACF300A066FA149970DF7868FCF2A73851929",
    "bobmodules_3.0.1.zip": "9AFE9E3E5766513D1542039F08E441C0EFD337468ADCE72D0C27E87C184AB63E",
    "bobores_3.0.0.zip": "7F8E33E35F59BB3F2CD72E3AB2FED30D1C2AE9C117E3731324AC307D9965082B",
    "bobplates_3.0.2.zip": "0C9A4910E2DCAA8DCABBE5BFFA67333F214EAB2EFD8C798D5EF84D90B691862D",
    "bobpower_3.0.0.zip": "C33C7B521BEC061ADF695A14BF3A218259FC0548B5F5AB512E74ECEAEDA39831",
    "bobrevamp_3.0.0.zip": "AEFAC11F71AA82B2385D92FBAC1C22FD6CAEF12E751A85CA63472AE8A4DC5703",
    "bobtech_3.0.0.zip": "397D979976316C3CE082D2AD29A046CCBAA147E412A0AEB727230BDECF665E5B",
    "mir-fixture-mir5-active-mods-observer_0.1.0.zip": OLDER_STANDALONE_OBSERVER_SHA256,
}

HARD_DEPENDENCIES = {
    "angelbob-spaceage-rebalance": {
        "base", "space-age", "elevated-rails", "quality", "angelsbioprocessing",
        "angelsbioprocessinggraphics", "angelspetrochem", "angelspetrochemgraphics",
        "angelsrefining", "angelsrefininggraphics", "angelssmelting",
        "angelssmeltinggraphics", "bobassembly", "bobelectronics", "boblibrary",
        "boblogistics", "bobmodules", "bobplates", "bobpower", "bobrevamp", "bobtech",
    },
    "angelsbioprocessing": {"angelsrefining", "angelspetrochem", "angelssmelting"},
    "angelspetrochem": {"base", "angelsrefining"},
    "angelssmelting": {"angelsrefining", "angelspetrochem"},
    "bobassembly": {"base", "boblibrary"},
    "bobelectronics": {"base", "boblibrary"},
    "boblogistics": {"base", "boblibrary"},
    "bobmodules": {"base", "boblibrary"},
    "bobores": {"base", "boblibrary"},
    "bobplates": {"base", "boblibrary", "bobores"},
    "bobpower": {"base", "boblibrary"},
    "bobrevamp": {"base", "boblibrary"},
    "bobtech": {"base", "boblibrary"},
}


def read_profile(path):
    return json.loads(path.read_text(encoding="utf-8"))


def mod_versions(profile):
    rows = profile["mods"]
    if len({row["name"] for row in rows}) != len(rows):
        raise AssertionError("profile repeats a mod name")
    if any(row != {"name": row["name"], "version": row["version"], "enabled": True}
           for row in rows):
        raise AssertionError("profile has a disabled or malformed mod row")
    return {row["name"]: row["version"] for row in rows}


class AngelBobRebalanceSpaceAgeProfileTests(unittest.TestCase):
    def test_upstream_profile_is_exact_lean_required_closure(self):
        profile = read_profile(UPSTREAM_PATH)
        self.assertEqual(profile["schema"], 1)
        self.assertEqual(profile["kind"], "mir5-angelbob-rebalance-space-age-f210-upstream-preparation-selection")
        self.assertEqual(profile["target"], "f210-standalone")
        self.assertEqual(profile["factorio_line"], "2.1")
        self.assertEqual(profile["engine"], ENGINE)
        self.assertEqual(profile["settings_mode"], "Defaults")
        self.assertEqual(mod_versions(profile), UPSTREAM_MODS)
        self.assertEqual(profile["archive_sha256"], UPSTREAM_ARCHIVES)
        self.assertNotIn(MIR_NAME, mod_versions(profile))
        self.assertEqual("0.1.0", mod_versions(profile)["mir-fixture-mir5-active-mods-observer"])
        for depender, requirements in HARD_DEPENDENCIES.items():
            self.assertIn(depender, UPSTREAM_MODS)
            self.assertTrue(requirements <= UPSTREAM_MODS.keys(), depender)
        expected_archives = {
            f"{name}_{version}.zip" for name, version in UPSTREAM_MODS.items() if name not in BUILTINS
        }
        self.assertEqual(set(profile["archive_sha256"]), expected_archives)
        self.assertIn(CURRENT_DIRECT_OBSERVER_SHA256, profile["scope"])
        self.assertIn(OLDER_STANDALONE_OBSERVER_SHA256, profile["scope"])
        self.assertIn("Preparation only", profile["scope"])

    def test_capture_controller_requires_the_upstream_profile_and_separate_mir_arguments(self):
        """Keep the actual capture entry point, not a look-alike profile, honest.

        Invoke-PrototypeCapture deliberately owns the MIR selection outside the
        loaded profile. This keeps the one upstream profile reusable by the
        no-MIR and candidate arms while retaining the exact candidate tuple the
        caller must supply.
        """
        upstream = read_profile(UPSTREAM_PATH)
        self.assertNotIn(MIR_NAME, mod_versions(upstream))
        self.assertNotIn(MIR_ARCHIVE, upstream["archive_sha256"])
        self.assertEqual(MIR_VERSION, "5.0.21013")
        self.assertRegex(MIR_SHA256, r"^[A-F0-9]{64}$")

        controller = CAPTURE_CONTROLLER.read_text(encoding="utf-8")
        self.assertIn("[string]$MIRArchive = ''", controller)
        self.assertIn("[string]$ExpectedMIRArchiveSha256 = ''", controller)
        self.assertIn(
            "profile must omit MIR; MIRArchive is the sole explicit MIR selection",
            controller,
        )
        self.assertIn(
            "$hasMIRArchive -eq (-not [string]::IsNullOrWhiteSpace($ExpectedMIRArchiveSha256))",
            controller,
        )
        self.assertIn(
            "Get-MIR5PrototypeCaptureMIRArchive -Archive $MIRArchive -Library $library -ExpectedSha256 $ExpectedMIRArchiveSha256 -EngineLine $engineLine",
            controller,
        )

    def test_runtime_profile_is_the_final_fixture_strict_closure_with_pins(self):
        upstream = read_profile(UPSTREAM_PATH)
        runtime = read_profile(RUNTIME_PATH)
        self.assertEqual(runtime["schema"], 1)
        self.assertEqual(
            runtime["kind"],
            "mir5-angelbob-rebalance-space-age-f210-steel-fixture-preparation-selection",
        )
        self.assertEqual(runtime["target"], "f210")
        self.assertEqual(runtime["factorio_line"], "2.1")
        self.assertEqual(runtime["engine"], ENGINE)
        self.assertEqual(runtime["settings_mode"], "Defaults")
        expected_mods = dict(UPSTREAM_MODS)
        expected_mods[MIR_NAME] = MIR_VERSION
        expected_mods[FIXTURE_NAME] = FIXTURE_VERSION
        expected_mods[PREOWNED_NAME] = "0.1.0"
        self.assertEqual(mod_versions(runtime), expected_mods)
        self.assertEqual(len(mod_versions(runtime)), 28)
        expected_archives = dict(UPSTREAM_ARCHIVES)
        expected_archives[MIR_ARCHIVE] = MIR_SHA256
        expected_archives[FIXTURE_ARCHIVE] = FIXTURE_SHA256
        expected_archives[PREOWNED_NAME + "_0.1.0.zip"] = PREOWNED_SHA256
        self.assertEqual(runtime["archive_sha256"], expected_archives)
        self.assertEqual(
            {name: version for name, version in mod_versions(runtime).items()
             if name not in {MIR_NAME, FIXTURE_NAME, PREOWNED_NAME}},
            mod_versions(upstream),
        )
        self.assertIn("mir-fixture-mir5-active-mods-observer", mod_versions(runtime))
        self.assertIn(FIXTURE_SHA256, runtime["scope"])
        self.assertIn("7682bytes", runtime["scope"])
        self.assertIn("NOT the reporter modpack", runtime["scope"])
        self.assertIn("Preparation only", runtime["scope"])

    def test_preowned_capture_adds_only_the_explicit_controlled_provider(self):
        profile = read_profile(PROFILES / "angelbob-rebalance-space-age-f210-2123-preowned-upstream.json")
        self.assertEqual(mod_versions(profile), {**UPSTREAM_MODS, PREOWNED_NAME: "0.1.0"})
        self.assertEqual(profile["archive_sha256"], {**UPSTREAM_ARCHIVES, PREOWNED_NAME + "_0.1.0.zip": PREOWNED_SHA256})
        self.assertNotIn(MIR_NAME, mod_versions(profile))
        self.assertIn("not a full reporter-pack", profile["scope"])

if __name__ == "__main__":
    unittest.main(verbosity=2)
