"""Independent binary-layout and rejection controls; no native-load claim."""
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import read_mod_settings_dat as reader
import write_mod_settings_dat as writer


class ModSettingsDatControls(unittest.TestCase):
    def test_independent_fixed_binary_and_engine_headers(self):
        # Manually specified documented layout, not constructed by the writer.
        root = (b"\x05\x00\x03\x00\x00\x00"
                b"\x00\x0eruntime-global\x05\x00\x00\x00\x00\x00"
                b"\x00\x10runtime-per-user\x05\x00\x00\x00\x00\x00"
                b"\x00\x07startup\x05\x00\x01\x00\x00\x00"
                b"\x00\x01x\x05\x00\x01\x00\x00\x00"
                b"\x00\x05value\x01\x00\x00")
        for version, header in (("2.0.77", bytes.fromhex("020000004d00000000")),
                                ("2.1.23", bytes.fromhex("020001001700000000"))):
            blob = header + root
            self.assertEqual(writer.encode(version, {"x": False}), blob)
            self.assertEqual(reader.decode(blob), {"engine": version, "startup": {"x": False}})

    def test_string_length_boundaries_and_utf8_byte_count(self):
        for size in (0, 1, 254, 255, 256, 65535, 65536, 70000):
            text = "x" * size
            blob = writer.encode("2.0.77", {"s": text})
            prefix = (b"\x01" if not size else b"\x00" +
                      (bytes([size]) if size < 255 else b"\xff" + struct.pack("<I", size)))
            self.assertIn(b"\x03\x00" + prefix + text.encode(), blob)
            self.assertEqual(reader.decode(blob)["startup"]["s"], text)
        text = "é" * 127 + "x"  # 128 characters, 255 UTF-8 bytes.
        blob = writer.encode("2.1.23", {"s": text})
        self.assertIn(b"\x03\x00\x00\xff\xff\x00\x00\x00" + text.encode(), blob)
        self.assertEqual(reader.decode(blob)["startup"]["s"], text)

    def test_scalar_types_and_invalid_inputs(self):
        values = {"false": False, "true": True, "zero": 0, "fraction": -12.5, "empty": ""}
        result = reader.decode(writer.encode("2.1.23", values))["startup"]
        self.assertIs(result["false"], False)
        self.assertIs(type(result["zero"]), float)
        self.assertEqual(result["zero"], 0)
        self.assertEqual(result["fraction"], -12.5)
        self.assertEqual(result["empty"], "")
        for value in (None, [], {}, float("inf"), float("nan"), 2**53 + 1, "x" * (1024 * 1024 + 1)):
            with self.subTest(value=type(value).__name__), self.assertRaises(ValueError):
                writer.encode("2.0.77", {"s": value})
        for version, data in (("2.0.78", {}), ("2.0.77", {"": 0}), ("2.0.77", [])):
            with self.assertRaises(ValueError):
                writer.encode(version, data)

    def test_reject_truncation_corruption_and_trailing_data(self):
        blob = writer.encode("2.0.77", {"flag": False, "profile": "é" * 128})
        for offset in range(len(blob)):
            with self.subTest(truncation=offset), self.assertRaises((ValueError, UnicodeError)):
                reader.decode(blob[:offset])
        for broken in (blob + b"\x00", b"\x03" + blob[1:], blob[:8] + b"\x02" + blob[9:],
                       blob[:9] + b"\x07" + blob[10:], blob.replace("é".encode(), b"\xff\xff", 1)):
            with self.assertRaises((ValueError, UnicodeError)):
                reader.decode(broken)
        malformed_length = writer.encode("2.0.77", {"s": "x" * 255}).replace(
            b"\x03\x00\x00\xff\xff\x00\x00\x00", b"\x03\x00\x00\xff\xfe\x00\x00\x00", 1)
        with self.assertRaises(ValueError):
            reader.decode(malformed_length)
        flag = writer.encode("2.1.23", {"flag": False})
        prefix = b"\x00\x05value"
        for bad in (flag.replace(prefix + b"\x01\x00\x00", prefix + b"\x01\x00\x02", 1),
                    flag.replace(prefix + b"\x01\x00\x00", prefix + b"\x04\x00\x00", 1),
                    flag.replace(prefix + b"\x01\x00\x00", prefix + b"\x01\x01\x00", 1)):
            with self.assertRaises(ValueError):
                reader.decode(bad)

    def test_cli_rejects_duplicates_and_preserves_existing_output(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            data, output = directory / "startup.json", directory / "mod-settings.dat"
            command = [sys.executable, "-B", str(ROOT / "tools/write_mod_settings_dat.py"),
                       "--engine", "2.0.77", "--startup-json", str(data), "--output", str(output)]
            data.write_text('{"x":false,"x":0}', encoding="utf-8")
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertFalse(output.exists())
            data.write_text(json.dumps({"x": False, "n": 0}), encoding="utf-8")
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            original = output.read_bytes()
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertEqual(output.read_bytes(), original)
            check = subprocess.run([sys.executable, "-B", str(ROOT / "tools/read_mod_settings_dat.py"), str(output)],
                                   capture_output=True, check=True, text=True)
            decoded = json.loads(check.stdout)
            self.assertIs(decoded["startup"]["x"], False)
            self.assertEqual(decoded["startup"]["n"], 0)


if __name__ == "__main__":
    unittest.main()
