"""Independent timestamp arithmetic and missing/adverse-boundary controls."""
from pathlib import Path
import base64
import gzip
import json
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from startup_timings import analyze, comparison_rows, digest, snapshot_rows


def parse(text):
    return analyze(text.encode(), "synthetic-control")


class StartupTimingTests(unittest.TestCase):
    def test_loader_bounds_exclude_other_mods_and_report_engine_bookkeeping(self):
        row = parse("""1.000 Loading mod settings more-infinite-research 5.0.21003 (settings.lua)
1.250 Loading mod other 1.0.0 (settings.lua)
9.000 Loading mod more-infinite-research 5.0.21003 (data-final-fixes.lua)
9.025 Script @__more-infinite-research__/foo.lua:1: debug
9.500 Checksum for core: 1
14.000 Factorio initialised
""")
        self.assertEqual(row["approximate_loader_seconds"], .75)
        self.assertEqual(row["approximate_settings_seconds"], .25)
        self.assertEqual(row["approximate_data_final_fixes_seconds"], .5)
        self.assertIsNone(row["approximate_data_updates_seconds"])
        self.assertEqual([x["seconds"] for x in row["approximate_loader_intervals"]], [.25, .5])
        self.assertIn("Checksum", row["approximate_loader_intervals"][-1]["end_boundary"])
        self.assertEqual(row["engine_initialised_seconds"], 14)
        self.assertIsNone(row["scoped_seconds"])

    def test_nested_phases_are_not_counted_twice_and_gap_excludes_other_mods(self):
        row = parse("""1.000 [MIR startup] stage=settings phase=stage event=begin
2.000 [MIR startup] stage=settings phase=stage event=end
20.000 [MIR startup] stage=data-final-fixes phase=stage event=begin
20.100 [MIR startup] stage=data-final-fixes phase=recipes event=begin
20.800 [MIR startup] stage=data-final-fixes phase=recipes event=work recipes=4096
21.000 [MIR startup] stage=data-final-fixes phase=recipes event=end
22.000 [MIR startup] stage=data-final-fixes phase=stage event=end
23.500 Checksum of base: 2
""")
        self.assertEqual(row["scoped_seconds"], 3)
        self.assertEqual(row["longest_observed_checkpoint_gap_seconds"], 1)
        self.assertEqual(row["post_mir_to_next_milestone"]["seconds"], 1.5)

    def test_missing_end_and_last_loader_boundary_remain_unavailable(self):
        row = parse("""1.000 Loading mod more-infinite-research 5.0.21003 (data-final-fixes.lua)
1.100 [MIR startup] stage=data-final-fixes phase=stage event=begin
1.200 [MIR startup] stage=data-final-fixes phase=recipes event=begin
9.000 Error: failed to load
""")
        self.assertIsNone(row["scoped_seconds"])
        self.assertIsNone(row["approximate_loader_seconds"])
        self.assertEqual(row["loader_status"], "unavailable")
        self.assertTrue(row["loader_warnings"])
        self.assertEqual(len(row["phases"]), 2)
        self.assertTrue(all(x["status"] == "incomplete" for x in row["phases"]))
        self.assertIsNone(row["post_mir_to_next_milestone"])
        settings_only = parse("1.000 [MIR startup] stage=settings phase=stage event=begin\n2.000 [MIR startup] stage=settings phase=stage event=end\n3.000 Loading mod core 0.0.0 (data.lua)")
        self.assertIsNone(settings_only["post_mir_to_next_milestone"])

    def test_restarts_duplicate_and_crossed_markers_refuse_scoped_total(self):
        for text in (
            "2.000 [MIR startup] stage=data phase=stage event=begin\n1.000 [MIR startup] stage=data phase=stage event=end",
            "1.000 [MIR startup] stage=data phase=stage event=begin\n2.000 [MIR startup] stage=data phase=stage event=end\n3.000 [MIR startup] stage=data phase=stage event=begin\n4.000 [MIR startup] stage=data phase=stage event=end",
            "1.000 [MIR startup] stage=data phase=stage event=begin\n2.000 [MIR startup] stage=data phase=recipes event=begin\n3.000 [MIR startup] stage=data phase=stage event=end",
        ):
            with self.subTest(text=text):
                row = parse(text)
                self.assertIsNone(row["scoped_seconds"])
                self.assertTrue(row["issues"])

    def test_rounded_zero_is_retained_and_untimestamped_output_is_not_timed(self):
        row = parse("1.000 [MIR startup] stage=data phase=stage event=begin\n1.000 [MIR startup] stage=data phase=stage event=end")
        self.assertEqual(row["scoped_seconds"], 0)
        self.assertIn("rounded zero", row["limits"][0])
        self.assertIsNone(parse("[MIR startup] stage=data phase=stage event=begin")["scoped_seconds"])

    def test_closed_stage_work_cannot_create_a_checkpoint_gap(self):
        row = parse("""1.000 [MIR startup] stage=data-final-fixes phase=stage event=begin
2.000 [MIR startup] stage=data-final-fixes phase=stage event=end
100.000 [MIR startup] stage=data-final-fixes phase=recipes event=work recipes=4096
""")
        self.assertIsNone(row["scoped_seconds"])
        self.assertIsNone(row["longest_observed_checkpoint_gap_seconds"])
        self.assertTrue(any("work outside" in issue for issue in row["issues"]))

    def test_different_lifecycle_stages_cannot_nest(self):
        row = parse("""1.000 [MIR startup] stage=settings phase=stage event=begin
2.000 [MIR startup] stage=data-final-fixes phase=stage event=begin
3.000 [MIR startup] stage=data-final-fixes phase=stage event=end
4.000 [MIR startup] stage=settings phase=stage event=end
5.000 Checksum of base: 1
""")
        self.assertIsNone(row["scoped_seconds"])
        self.assertIsNone(row["longest_observed_checkpoint_gap_seconds"])
        self.assertIsNone(row["post_mir_to_next_milestone"])
        self.assertTrue(any("cross-stage" in issue for issue in row["issues"]))

    def test_recompressed_snapshot_bodies_must_match_declared_capsule_pin(self):
        root = Path(__file__).resolve().parents[1] / "spec/evidence"
        with tempfile.TemporaryDirectory() as folder:
            capsule = Path(folder) / "recompressed.gz"
            original = (root / "mir5-beta-00-startup-snapshot-bodies-r01.json.gz").read_bytes()
            capsule.write_bytes(gzip.compress(gzip.decompress(original), compresslevel=1, mtime=7))
            self.assertNotEqual(digest(original), digest(capsule.read_bytes()))
            with self.assertRaisesRegex(ValueError, "snapshot capsule identity mismatch"):
                snapshot_rows(root / "mir5-beta-00-startup-snapshot-r01.json", capsule)

    def test_original_snapshot_keeps_all39_logs_missing_menus_and_identities(self):
        root = Path(__file__).resolve().parents[1] / "spec/evidence"
        rows = snapshot_rows(root / "mir5-beta-00-startup-snapshot-r01.json",
                             root / "mir5-beta-00-startup-snapshot-bodies-r01.json.gz")
        self.assertEqual(len(rows), 39)
        self.assertEqual(len({x["run_id"] for x in rows}), 39)
        self.assertTrue(all(x["scoped_seconds"] is None for x in rows))
        heavy = next(x for x in rows if x["run_id"] == "descriptive-heavy-f210-r04/mir5")
        self.assertEqual(heavy["original_menu_status"], "failed-retained")
        self.assertIsNone(heavy["original_confirmed_settings_seconds"])
        self.assertEqual(heavy["engine_initialised_seconds"], 28.884)
        self.assertAlmostEqual(heavy["approximate_loader_seconds"], .300)

    def test_corrupt_original_binding_and_duplicate_run_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            raw = b"1.000 Factorio initialised\n"
            ref = dict(path="one.log", bytes=len(raw), sha256=digest(raw))
            body = {**ref, "base64": base64.b64encode(raw).decode()}
            row = dict(arm="mir5", archive_version="5.0.21000", raw_log=ref, engine_initialised_log_seconds=1)
            group = dict(cohort="original", engine="2.1.23", workload="synthetic", observation_kind="control", rows=[row])
            snapshot = dict(source_commit="original-control", groups=[group])
            def write_capsule():
                raw_capsule = gzip.compress(json.dumps({"bodies": {"one.log": body}}).encode())
                snapshot["capsule"] = dict(bytes=len(raw_capsule), sha256=digest(raw_capsule))
                (root / "bodies.gz").write_bytes(raw_capsule)
                (root / "snapshot.json").write_text(json.dumps(snapshot))
            write_capsule()
            self.assertEqual(len(snapshot_rows(root / "snapshot.json", root / "bodies.gz")), 1)
            body["sha256"] = "0" * 64
            write_capsule()
            with self.assertRaisesRegex(ValueError, "identity mismatch"):
                snapshot_rows(root / "snapshot.json", root / "bodies.gz")
            body["sha256"] = ref["sha256"]
            write_capsule()
            group["rows"].append(row)
            (root / "snapshot.json").write_text(json.dumps(snapshot))
            with self.assertRaisesRegex(ValueError, "duplicate run"):
                snapshot_rows(root / "snapshot.json", root / "bodies.gz")

    def test_two_original_comparisons_retain_warmups_pilots_and_scored_endpoints(self):
        root = Path(__file__).resolve().parents[1] / "spec/evidence"
        for chain, capsule, count, phase, scored_count, expected_mean in (
            ("candidate502-base-f200-startup-chain-r01.json", "candidate502-base-f200-startup-receipts-r01.json.gz", 41, "block", 12, 10.442205883333333),
            ("f210-current38c-menu-native-chain-r01.json", "f210-current38c-menu-native-receipts-r01.json.gz", 38, "counterbalanced-comparison", 8, 28.3224201375),
        ):
            with self.subTest(chain=chain):
                rows = comparison_rows(root / chain, root / capsule)
                self.assertEqual(len(rows), count)
                self.assertEqual(len({x["run_id"] for x in rows}), count)
                self.assertTrue(all(x["scoped_seconds"] is None for x in rows))
                scored = [x for x in rows if x["phase"] == phase and x["arm"] == "candidate-mir5"]
                self.assertEqual(len(scored), scored_count)
                self.assertAlmostEqual(sum(x["original_confirmed_settings_seconds"] for x in scored) / len(scored), expected_mean)

    def test_cli_refuses_to_overwrite_input_or_existing_output(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / "original.log"
            raw = b"1.000 Factorio initialised\n"
            log.write_bytes(raw)
            reader = Path(__file__).resolve().parents[1] / "tools/startup_timings.py"
            result = subprocess.run([sys.executable, "-B", str(reader), "--log", str(log), "--json", str(log)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(log.read_bytes(), raw)

    def test_current_base_index_preserves_phases_clocks_and_refuses_changed_inputs(self):
        # A deliberately small independent corpus exercises the actual encoded
        # custody format without needing the private native archive in CI.
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            prefix = "native/menu-base-foreground-r01-controller/"
            files, samples = {}, []
            source = dict(player_source="original-source", player_tree="original-tree",
                          candidate_version="5.0.21005", published_version="4.7.21003")
            engine = dict(sha256="original-engine", base_version="2.1.23")
            plans = [("warmup", "candidate-mir5"), ("published-aa", "published-mir4.7"),
                     ("published-aa", "published-mir4.7"), ("latin-comparison", "control-without-mir"),
                     ("latin-comparison", "published-mir4.7"), ("latin-comparison", "candidate-mir5")]
            for ordinal, (phase, arm) in enumerate(plans, 1):
                leaf = "runs/" + str(ordinal)
                version = {"candidate-mir5": "5.0.21005", "published-mir4.7": "4.7.21003",
                           "control-without-mir": None}[arm]
                header = f"1.000 Loading mod more-infinite-research {version} (data-final-fixes.lua)\n"
                files[prefix + leaf + "/factorio.log"] = (
                    (header if version else "") + "1.250 Checksum of base: 1\n4.000 Factorio initialised\n").encode()
                actor_path = leaf + "/responsive-menu-actor/actor-result.json"
                files[prefix + actor_path] = json.dumps(dict(observation=dict(
                    status="owned-menu-settings-response-observed", first_render_observed_seconds=10 + ordinal,
                    confirmed_response_seconds=11 + ordinal))).encode()
                samples.append(dict(plan=dict(ordinal=ordinal, arm=arm, phase=phase,
                                              block=1 if phase == "latin-comparison" else 0),
                                    observation=dict(run_relative_path=leaf, elapsed_seconds=11 + ordinal,
                                                     responsive_menu_actor=dict(path=actor_path,
                                                                                sha256=digest(files[prefix + actor_path])))))
            schedule = [r["plan"] for r in samples]
            packet = dict(schedule=schedule, candidate_source=dict(commit="original-source", player_tree="original-tree"))
            result = dict(samples=samples, schedule=schedule, inputs=dict(engine=engine))
            chain = dict(kind="MIRCurrentBaseResponsiveMenuObservationsV1", source=source,
                         inputs=dict(engine="2.1.23", engine_sha256="original-engine"))

            def write():
                packet_raw = json.dumps(packet).encode()
                result["packet_sha256"] = digest(packet_raw)
                files[prefix + "result.json"] = json.dumps(result).encode()
                files["qualification/menu-base-foreground-r01-controller/packet.json"] = packet_raw
                records = [dict(path=p, bytes=len(raw), sha256=digest(raw), base64=base64.b64encode(raw).decode())
                           for p, raw in files.items()]
                payload = json.dumps(dict(files=records)).encode()
                encoded = base64.b64encode(gzip.compress(payload, mtime=0)) + b"\n"
                chain["custody"] = dict(capsule_sha256=digest(encoded), decoded_payload_sha256=digest(payload))
                chain["execution"] = dict(native_launches=len(samples), packet_sha256=digest(packet_raw),
                                          result_sha256=digest(files[prefix + "result.json"]))
                (root / "bodies.gz.b64").write_bytes(encoded)
                (root / "index.json").write_text(json.dumps(chain))

            def read():
                return comparison_rows(root / "index.json", root / "bodies.gz.b64")

            write()
            rows = read()
            self.assertEqual([r["phase"] for r in rows], [p[0] for p in plans])
            self.assertEqual([r["original_confirmed_settings_seconds"] for r in rows], list(range(12, 18)))
            self.assertTrue(all(r["engine_initialised_seconds"] == 4 for r in rows))
            self.assertTrue(all(r["scoped_seconds"] is None for r in rows))
            self.assertEqual(rows[3]["loader_status"], "not-present")
            self.assertEqual(rows[-1]["approximate_loader_seconds"], .25)
            self.assertEqual(rows[-1]["archive_version"], "5.0.21005")
            # Even re-encoded/re-pinned bodies cannot hide a changed original
            # actor endpoint, schedule, source binding or loaded version.
            samples[-1]["observation"]["elapsed_seconds"] = 99
            write()
            with self.assertRaisesRegex(ValueError, "actor endpoint differs"):
                read()
            samples[-1]["observation"]["elapsed_seconds"] = 17
            result["schedule"] = schedule[:-1]
            write()
            with self.assertRaisesRegex(ValueError, "schedule differs"):
                read()
            result["schedule"] = schedule
            packet["candidate_source"]["commit"] = "different-source"
            write()
            with self.assertRaisesRegex(ValueError, "engine/source differs"):
                read()
            packet["candidate_source"]["commit"] = "original-source"
            files[prefix + "runs/6/factorio.log"] = files[prefix + "runs/6/factorio.log"].replace(b"5.0.21005", b"5.0.21004")
            write()
            with self.assertRaisesRegex(ValueError, "loaded MIR version differs"):
                read()
            chain["custody"]["decoded_payload_sha256"] = "0" * 64
            (root / "index.json").write_text(json.dumps(chain))
            with self.assertRaisesRegex(ValueError, "decoded comparison payload identity mismatch"):
                read()
            (root / "bodies.gz.b64").write_bytes(b"changed capsule")
            with self.assertRaisesRegex(ValueError, "capsule identity mismatch"):
                read()


if __name__ == "__main__":
    unittest.main()
