"""Host command behavior with identity codecs; no native file/codec evidence."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SettingsCommandsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()

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
        self.assertEqual(len(profile["settings"]), 888)
        self.assertEqual(profile["metadata"], {
            "export_mode": "full", "exported_by": "Alice", "factorio_version": "2.1.23",
            "import_setting": "mir-settings-profile-import", "mir_version": "5.0.21000"})
        self.assertIn("888 settings, full", self.lua.globals().messages[1])

    def test_compact_option_filename_sanitization_and_server_metadata(self):
        row, profile = self.export("  --compact ../my profile  ", player=False)
        self.assertEqual(row["path"], "more-infinite-research/settings/..-my-profile.txt")
        self.assertEqual(profile["metadata"]["export_mode"], "compact")
        self.assertEqual(profile["metadata"]["exported_by"], "server")
        # The shipped canonical codec serializes an empty table as [].
        self.assertEqual(profile["settings"], [])
        self.assertEqual(row["player_index"], 0)
        self.assertIn("[more-infinite-research]", self.lua.globals().messages[1])

    def test_non_compact_name_and_old_file_api_fallback(self):
        self.lua.execute('''
          game.write_file = helpers.write_file
          helpers.write_file = nil
        ''')
        row, profile = self.export("compactly.txt")
        self.assertEqual(row["path"], "more-infinite-research/settings/compactly.txt")
        self.assertEqual(profile["metadata"]["export_mode"], "full")
        self.assertEqual(len(profile["settings"]), 888)

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

    def test_export_returns_the_same_string_and_catches_write_failure(self):
        self.lua.execute('''
          settings.startup["ips-enable-research_gears"].value=false
          settings.startup["ips-max-level-research_gears"].value=0
          local encoded, filename=commands.export({player_index=1})
          assert(writes[1].data == encoded .. "\\n" and writes[1].path == filename)
          local decoded=require("research.settings_profile").decode(encoded,helpers)
          assert(decoded.settings["ips-enable-research_gears"] == false)
          assert(decoded.settings["ips-max-level-research_gears"] == 0)
          local compact=commands.export({player_index=1,parameter="--compact"})
          assert(require("research.settings_profile").decode(compact,helpers).settings["ips-enable-research_gears"] == false)
          helpers.write_file=function() error("disk denied") end
          local failed, reason=commands.export({player_index=1})
          assert(failed == nil and reason:find("disk denied",1,true))
          assert(messages[#messages]:find("export failed",1,true))
          assert(settings.startup["ips-enable-research_gears"].value == false)
        ''')

    def test_diagnostics_are_bounded_local_overwrites_with_exact_false_state(self):
        self.lua.execute('''
          player.index=1
          local original={name="fixture-research",level=2,researched=false,enabled=false,visible_when_disabled=false}
          local technology=setmetatable({},{__index=original,__newindex=function() error("native mutation") end})
          player.force={name="fixture-force",index=7,technologies={[original.name]=technology},
            current_research=technology,research_progress=.42,research_queue={technology},manual_mining_speed_modifier=0}
          local before=settings.startup["ips-cost-base-research_gears"].value
          local diagnostics=require("runtime.diagnostics")
          for i=2,40 do player.force.research_queue[i]=technology end
          local encoded=diagnostics.export(1,original.name)
          assert(encoded and #writes==2)
          assert(writes[1].player_index==1 and writes[2].player_index==1)
          assert(writes[2].path=="more-infinite-research/mir.log" and writes[2].append==false)
          assert(writes[2].data:find("Selected researched: false",1,true))
          assert(writes[2].data:find("Native total manual_mining_speed_modifier: 0",1,true))
          assert(writes[2].data:find("factorio-current.log separately",1,true))
          assert(writes[2].data:find("remaining entries omitted after 32",1,true))
          assert(#player.force.research_queue==40)
          assert(writes[1].data==encoded .. "\\n")
          if #encoded<=32768 then assert(writes[2].data:find(encoded,1,true))
          else assert(writes[2].data:find("omitted here",1,true)) end
          diagnostics.startup("configuration")
          assert(#writes==3 and writes[3].player_index==0 and writes[3].append==false)
          assert(not writes[3].data:find("MIRSET1 profile:",1,true))
          for i=1,512 do script.active_mods[string.rep("m",170)..i]="1.2.3" end
          diagnostics.startup("initialization")
          assert(#writes[4].data<=65536 and writes[4].data:find("list omitted",1,true))
          script.active_mods={}
          for i=1,512 do script.active_mods[string.rep("m",170)..i]=string.rep("1",60) end
          diagnostics.startup("initialization")
          assert(#writes[5].data<=65536 and writes[5].data:find("Report truncated",1,true))
          assert(settings.startup["ips-cost-base-research_gears"].value==before)
          diagnostics.export(nil)
          assert(writes[6].player_index==0 and writes[7].player_index==0)
          local bob={name="Bob",force=player.force,print=player.print}
          game.get_player=function(index) return index==1 and player or index==2 and bob end
          diagnostics.export(2,original.name)
          assert(writes[8].player_index==2 and writes[9].player_index==2)
          assert(writes[8].data:find('"exported_by":"Bob"',1,true))
        ''')

    def test_diagnostics_report_failure_retains_full_settings_without_native_writes(self):
        self.lua.execute('''
          local diagnostics=require("runtime.diagnostics")
          local old=helpers.write_file
          helpers.write_file=function(path,...)
            if path==diagnostics.filename then error("report denied") end
            return old(path,...)
          end
          local encoded, err=diagnostics.export(1)
          assert(encoded==nil and err:find("report denied",1,true))
          assert(#writes==1 and writes[1].path:find("mir-settings-profile.txt",1,true))
          assert(messages[#messages]:find("diagnostics export failed",1,true))
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])
