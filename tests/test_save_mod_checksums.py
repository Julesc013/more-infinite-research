"""Independent Factorio 2.0.77 save configuration controls."""

from hashlib import sha256
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile
import zlib


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from read_save_mod_checksums import verify_save


HEADER = bytes.fromhex("020000004d000000") + b"\x00\x00\x08freeplay"
BASE = b"\x04base\x02\x00\x4d" + bytes.fromhex("869c0570")
MIR = b"\x16more-infinite-research\x04\x07\xff\x22\x4e" + bytes.fromhex("d58d411b")
FIXTURE = b"\x06editor\x00\x01\x00"
STOCK = b"\0\0\0\0"
EDITED = bytes.fromhex("61621eff")
WITNESS = {
    "base": {"version": "2.0.77", "data_checksum": 1879415942},
    "more-infinite-research": {"version": "4.7.20002", "data_checksum": 457280981},
    "editor": {"version": "0.1.0", "data_checksum": 0},
}


class SaveModChecksumControls(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.path = Path(temp.name) / "protected.zip"

    def write_map(self, data, second_chunk=False):
        with zipfile.ZipFile(self.path, "w") as archive:
            archive.writestr("protected/level.dat0", zlib.compress(data))
            if second_chunk:
                archive.writestr("another/level.dat0", zlib.compress(data))

    def test_exact_roster_with_large_version_component(self):
        self.write_map(HEADER + b"\x03" + BASE + MIR + FIXTURE + STOCK)
        result = verify_save(self.path, WITNESS)
        self.assertEqual(result["mods"], WITNESS)
        self.assertEqual(result["save_sha256"], sha256(self.path.read_bytes()).hexdigest())

    def test_same_version_with_different_data_checksum_refuses(self):
        self.write_map(HEADER + b"\x03" + BASE + MIR + FIXTURE + EDITED)
        with self.assertRaisesRegex(ValueError, "differs from witness for editor"):
            verify_save(self.path, WITNESS)
        altered = dict(WITNESS, editor={"version": "0.1.0", "data_checksum": 4280181345})
        self.assertEqual(verify_save(self.path, altered)["mods"], altered)

    def test_truncated_table_refuses(self):
        self.write_map(HEADER + b"\x03" + BASE + MIR + FIXTURE + b"\0")
        with self.assertRaisesRegex(ValueError, "truncated"):
            verify_save(self.path, WITNESS)

    def test_different_engine_refuses(self):
        self.write_map(b"\x03" + HEADER[1:] + b"\x03" + BASE + MIR + FIXTURE + STOCK)
        with self.assertRaisesRegex(ValueError, "map version"):
            verify_save(self.path, WITNESS)

    def test_multiple_root_chunks_refuse(self):
        self.write_map(HEADER + b"\x03" + BASE + MIR + FIXTURE + STOCK, second_chunk=True)
        with self.assertRaisesRegex(ValueError, "one root"):
            verify_save(self.path, WITNESS)


if __name__ == "__main__":
    unittest.main()
