"""Keep historical oracles independent of the editable MIR5 source layout."""
from pathlib import Path
import unittest
from unittest import mock

import historical_sources


ROOT = Path(__file__).resolve().parents[2]
SOURCE = "source/prototypes/streams/productivity.lua"
SHA256 = "EA66B64C03943A99B877847FD6E3903A099C83AB0333A441A29957C1C2142853"


class HistoricalSourceTests(unittest.TestCase):
    def test_reads_the_exact_independent_published_stream(self):
        data = historical_sources.read_published_source(ROOT, SOURCE, SHA256)
        self.assertIn(b"research_auto_assembling_machine", data)
        self.assertIn(b"research_auto_lab", data)

    def test_does_not_read_a_current_worktree_file(self):
        with mock.patch.object(Path, "read_bytes", side_effect=AssertionError("live file read")):
            self.assertTrue(historical_sources.read_published_source(ROOT, SOURCE, SHA256))

    def test_rejects_changed_expected_bytes(self):
        with self.assertRaisesRegex(AssertionError, "Captured historical evidence changed"):
            historical_sources.read_published_source(ROOT, SOURCE, "0" * 64)

    def test_rejects_ambiguous_paths_and_missing_hashes(self):
        for path in ("../source.lua", "/source.lua", "source//file", "source\\file", "HEAD:file"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                historical_sources.read_published_source(ROOT, path, SHA256)
        with self.assertRaises(ValueError):
            historical_sources.read_published_source(ROOT, SOURCE, "")

    def test_missing_object_is_a_failure_without_worktree_or_network_fallback(self):
        with mock.patch.object(historical_sources, "PUBLISHED_COMMIT", "0" * 40):
            with self.assertRaisesRegex(AssertionError, "fetch exact commit"):
                historical_sources.read_published_source(ROOT, SOURCE, SHA256)


if __name__ == "__main__":
    unittest.main(verbosity=2)
