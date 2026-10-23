"""Host command behavior with identity codecs; no native file/codec evidence."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SettingsCommandsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()

        def decode(text):
            try:
                value = json.loads(text)
            except (ValueError, TypeError):
                return None
            return self.lua.table_from(value, recursive=True) if isinstance(value, (dict, list)) else value

        self.lua.globals().decode_json = decode
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          messages, writes = {}, {}
          helpers = {
            game_version = "2.1.23",
            json_to_table = decode_json,
            encode_string = function(text) return text end,
            decode_string = function(text) return text end,
            write_file = function(path, data, append, index)
              writes[#writes + 1] = {path=path, data=data, append=append, player_index=index}
            end
          }
          script = {active_mods = {["more-infinite-research"] = "5.0.21000"}}
          player = {name = "Alice", print = function(text) messages[#messages+1] = text end}
          game = {get_player = function(index) return index == 1 and player or nil end}
          log = function(text) messages[#messages+1] = text end
          storage = setmetatable({}, {__index=function() error("read storage") end,
            __newindex=function() error("write storage") end})
          settings = {startup = {}}
          local catalogue = require("research.settings")
          for _, definition in ipairs(catalogue.prototypes()) do
            settings.startup[definition.name] = {value=definition.default_value}
          end
          commands = require("runtime.settings_commands")
        ''')

    def export(self, parameter=None, player=True):
        command = self.lua.table_from({"parameter": parameter, "player_index": 1 if player else None})
        self.lua.globals().commands.export(command)
        row = self.lua.globals().writes[1]
        return row, json.loads(row["data"].removeprefix("MIRSET1:").strip())

    def test_full_export_preserves_effective_values_and_command_metadata(self):
        imported = json.dumps({"schema": 1, "settings": {"ips-cost-base-research_gears": 17}})
        self.lua.globals().settings.startup["mir-settings-profile-import"].value = imported
        row, profile = self.export()
        self.assertEqual(row["path"], "more-infinite-research/settings/mir-settings-profile.txt")
        self.assertFalse(row["append"])
        self.assertEqual(row["player_index"], 1)
        self.assertTrue(row["data"].endswith("\n"))
        self.assertEqual(profile["settings"]["ips-cost-base-research_gears"], 17)
        self.assertEqual(len(profile["settings"]), 9)
        self.assertEqual(profile["metadata"], {
            "export_mode": "full", "exported_by": "Alice", "factorio_version": "2.1.23",
            "import_setting": "mir-settings-profile-import", "mir_version": "5.0.21000"})
        self.assertIn("9 settings, full", self.lua.globals().messages[1])

    def test_compact_option_filename_sanitization_and_server_metadata(self):
        row, profile = self.export("  --compact ../my profile  ", player=False)
        self.assertEqual(row["path"], "more-infinite-research/settings/..-my-profile.txt")
        self.assertEqual(profile["metadata"]["export_mode"], "compact")
        self.assertEqual(profile["metadata"]["exported_by"], "server")
        # The shipped canonical codec serializes an empty table as [].
        self.assertEqual(profile["settings"], [])
        self.assertIsNone(row["player_index"])
        self.assertIn("[more-infinite-research]", self.lua.globals().messages[1])

    def test_non_compact_name_and_old_file_api_fallback(self):
        self.lua.execute('''
          game.write_file = helpers.write_file
          helpers.write_file = nil
        ''')
        row, profile = self.export("compactly.txt")
        self.assertEqual(row["path"], "more-infinite-research/settings/compactly.txt")
        self.assertEqual(profile["metadata"]["export_mode"], "full")
        self.assertEqual(len(profile["settings"]), 9)

    def test_missing_file_api_and_codec_failure_do_not_report_success(self):
        self.lua.execute('''
          helpers.write_file = nil
          commands.export({player_index=1})
          assert(#writes == 0 and messages[1]:find("file export API is not available", 1, true))
          helpers.encode_string = function() return nil end
          commands.export({player_index=1})
          assert(#writes == 0 and messages[2]:find("profile string encoding failed", 1, true))
          helpers.encode_string = function(text) return text end
          setmetatable(game, {__index=function(_, key) error("unknown LuaGameScript member: " .. key) end})
          commands.export({player_index=1})
          assert(#writes == 0 and messages[3]:find("file export API is not available", 1, true))
        ''')

    def test_validation_reports_counts_without_applying_imports(self):
        payload = json.dumps({"schema": 1, "settings": {
            "ips-cost-base-research_gears": 17, "ips-enable-research_gears": "invalid",
            "other-mod-setting": 4}})
        command = self.lua.table_from({"player_index": 1, "parameter": payload})
        self.lua.globals().commands.validate(command)
        self.assertIn("1 recognized settings, 1 invalid values, 1 ignored", self.lua.globals().messages[1])
        self.assertEqual(self.lua.globals().settings.startup["ips-cost-base-research_gears"].value, 8000)
        self.lua.globals().commands.validate(self.lua.table_from({"player_index": 1, "parameter": "bad"}))
        self.assertIn("Invalid MIR settings profile", self.lua.globals().messages[2])
        self.assertIsNone(self.lua.globals().writes[1])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])
