"""Real file identities and filesystem boundaries; no engine or library inputs."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which("pwsh")


def quote(path: Path | str) -> str:
    return "'" + str(path).replace("'", "''") + "'"


@unittest.skipUnless(PWSH, "PowerShell 7 is required")
class InputFilesystemBoundaries(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / "build/tmp"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="input-filesystem-", dir=scratch)
        self.directory = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def ps(self, body: str, *, env=None):
        script = (
            "$ErrorActionPreference='Stop'; "
            f". {quote(ROOT / 'tools/lib/validation/ImmutableInputStaging.ps1')}; "
            + body
        )
        result = subprocess.run(
            [PWSH, "-NoProfile", "-NonInteractive", "-Command", script],
            cwd=ROOT, env=env, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def test_equal_bytes_are_not_a_file_identity(self):
        source = self.directory / "source.zip"
        copy = self.directory / "copy.zip"
        source.write_bytes(b"same archive bytes\n")
        shutil.copyfile(source, copy)
        result = self.ps(
            f"$a=Get-MIRImmutableInputFileIdentity {quote(source)}; "
            f"$b=Get-MIRImmutableInputFileIdentity {quote(copy)}; "
            f"$again=Get-MIRImmutableInputFileIdentity {quote(source)}; "
            "@{source=$a;copy=$b;again=$again}|ConvertTo-Json -Compress"
        )
        self.assertEqual(result["source"], result["again"])
        self.assertNotEqual(result["source"], result["copy"])

    def test_real_checkout_hardlink_has_the_same_identity(self):
        source = self.directory / "source.zip"
        alias = self.directory / "alias.zip"
        source.write_bytes(b"retained immutable input\n")
        result = self.ps(
            f"Assert-MIRCheckoutHardLinkBoundary -Source {quote(source)} -Destination {quote(alias)}; "
            f"New-Item -ItemType HardLink -Path {quote(alias)} -Target {quote(source)}|Out-Null; "
            f"@{{source=Get-MIRImmutableInputFileIdentity {quote(source)};"
            f"alias=Get-MIRImmutableInputFileIdentity {quote(alias)}}}|ConvertTo-Json -Compress"
        )
        self.assertEqual(result["source"], result["alias"])
        self.assertTrue(os.path.samefile(source, alias))
        self.assertGreaterEqual(source.stat().st_nlink, 2)

    @unittest.skipUnless(sys.platform == "linux", "Linux case-sensitive boundary")
    def test_differently_cased_sibling_is_not_within_root(self):
        admitted = self.directory / "CaseRoot"
        sibling = self.directory / "caseroot"
        admitted.mkdir()
        sibling.mkdir()
        result = self.ps(
            f"$result=try {{ $null=Assert-MIRImmutableInputPathWithin -Root {quote(admitted)} "
            f"-Path {quote(sibling / 'input.zip')} -Context 'opposing sibling'; @{{refused=$false}} }} "
            "catch { @{refused=$true;error=$_.Exception.Message} }; $result|ConvertTo-Json -Compress"
        )
        self.assertTrue(result["refused"])
        self.assertIn("must remain below", result["error"])

    @unittest.skipUnless(sys.platform == "linux", "Linux symlink boundary")
    def test_hardlink_boundary_refuses_symlink_ancestor(self):
        source = self.directory / "source.zip"
        source.write_bytes(b"input")
        alias = self.directory / "linked-directory"
        alias.symlink_to(self.directory, target_is_directory=True)
        result = self.ps(
            f"$result=try {{ Assert-MIRCheckoutHardLinkBoundary -Source {quote(alias / source.name)} "
            f"-Destination {quote(self.directory / 'destination.zip')}; @{{refused=$false}} }} "
            "catch { @{refused=$true;error=$_.Exception.Message} }; $result|ConvertTo-Json -Compress"
        )
        self.assertTrue(result["refused"])
        self.assertIn("mir-hardlink-reparse", result["error"])
        self.assertFalse((self.directory / "destination.zip").exists())

    @unittest.skipUnless(sys.platform == "linux", "Linux descriptor identity")
    def test_path_replacement_cannot_retarget_the_held_descriptor(self):
        source = self.directory / "source.zip"
        original = self.directory / "retained-original.zip"
        source.write_bytes(b"original input")
        before = self.ps(f"Get-MIRImmutableInputFileIdentity {quote(source)}|ConvertTo-Json -Compress")
        wrappers = self.directory / "tool-wrapper"
        wrappers.mkdir()
        wrapper = wrappers / "python3"
        wrapper.write_text(
            f"#!{sys.executable}\n"
            "import os,sys\nfrom pathlib import Path\n"
            f"source=Path({str(source)!r})\noriginal=Path({str(original)!r})\n"
            "source.rename(original)\nsource.write_bytes(b'replacement input')\n"
            f"os.execv({sys.executable!r},[{sys.executable!r},*sys.argv[1:]])\n"
        )
        wrapper.chmod(0o700)
        environment = dict(os.environ, PATH=str(wrappers) + os.pathsep + os.environ.get("PATH", ""))
        during = self.ps(f"Get-MIRImmutableInputFileIdentity {quote(source)}|ConvertTo-Json -Compress", env=environment)
        after = self.ps(f"Get-MIRImmutableInputFileIdentity {quote(source)}|ConvertTo-Json -Compress")
        self.assertEqual(before, during)
        self.assertNotEqual(before, after)
        self.assertEqual(original.read_bytes(), b"original input")
        self.assertEqual(source.read_bytes(), b"replacement input")

    @unittest.skipUnless(sys.platform == "linux", "Linux mount accounting")
    def test_capacity_observes_the_destination_mount(self):
        work_free = shutil.disk_usage(self.directory).free
        root_free = shutil.disk_usage("/").free
        if abs(work_free - root_free) < 256 * 1024**2:
            self.skipTest("A distinct destination mount is needed for this opposing control")
        required = min(work_free, root_free) + 128 * 1024**2
        expected_admit = work_free > root_free
        result = self.ps(
            f"$result=try {{ Assert-MIRImmutableInputCopyCapacity -DestinationDirectory {quote(self.directory / 'not-created' / 'staging')} "
            f"-RequiredBytes {required} -ReserveBytes 0; @{{admitted=$true}} }} "
            "catch { @{admitted=$false;error=$_.Exception.Message} }; $result|ConvertTo-Json -Compress"
        )
        self.assertEqual(result["admitted"], expected_admit, result)

    @unittest.skipUnless(sys.platform == "linux", "Linux development-health mount accounting")
    def test_health_reports_the_checkout_filesystem(self):
        result = subprocess.run(
            [PWSH, "-NoProfile", "-NonInteractive", "-File",
             str(ROOT / "tools/commands/workspace/Test-MIRDevelopmentHealth.ps1"),
             "-AsJson", "-MaxScanSeconds", "1"],
            cwd=ROOT, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(result.stdout)
        expected_mib = shutil.disk_usage(ROOT).free // 1024**2
        self.assertLess(abs(record["disk"]["free_mib"] - expected_mib), 16)

    @unittest.skipUnless(sys.platform == "linux", "Linux hidden library controls")
    def test_output_budget_charges_hidden_active_profile_control(self):
        library, output = self.directory / "library", self.directory / "output"
        library.mkdir()
        output.mkdir()
        (library / ".mir-active-profile.json").write_bytes(b"{}\n")
        result = self.ps(
            f". {quote(ROOT / 'tools/lib/compatibility/LibraryActivation.ps1')}; "
            f". {quote(ROOT / 'tools/lib/validation/NativeProbeResources.ps1')}; "
            f"$lock=[IO.File]::Open({quote(library / '.test-lock')},'CreateNew','ReadWrite','None'); "
            "try { "
            f"$context=[pscustomobject]@{{root={quote(output)};aliases=@();shared_alias_bytes=0L;max_new_output_bytes=1MB;result_reserve_bytes=64KB}}; "
            f"$activation=[pscustomobject]@{{closed=$false;lock=$lock;library={quote(library)};journal=@{{controls=@{{"
            "'mod-list.json'=@{exists=$false};'mod-settings.dat'=@{exists=$false}}}}; "
            "Add-MIRNativeProbeLibraryActivation -Context $context -Activation $activation; "
            "$remaining=Get-MIRNativeProbeRemainingOutputBytes -Context $context; "
            "@{remaining=$remaining}|ConvertTo-Json -Compress "
            "} finally {$lock.Dispose()}"
        )
        self.assertEqual(1024**2 - 64 * 1024 - 3, result["remaining"])

    def test_finite_four_inputs_and_current_helpers_survive_isolated_autocrlf_checkouts(self):
        packet = json.loads(
            (ROOT / "tests/fixtures/worker-storage-finite-four-native.json").read_text(
                encoding="utf-8"
            )
        )
        descriptors = (
            packet["inputs"]["actor_members"] + packet["helper_pins"]
        )
        expected = {row["path"]: row["sha256"].lower() for row in descriptors}
        self.assertEqual(9, len(expected), expected)
        self.assertEqual(9, len(descriptors), descriptors)
        actor = "tests/fixtures/worker-storage-native-observer/control.lua"
        self.assertIn(actor, expected)
        current_helpers = ("tools/lib/validation/LinuxWriteStorage.ps1",)

        attributes = (ROOT / ".gitattributes").read_text(encoding="utf-8")
        rules = [f"{path} text eol=lf" for path in (*expected, *current_helpers)]
        for rule in rules:
            self.assertIn(rule, attributes)

        def git(directory: Path, *arguments: str, text: bool = False):
            result = subprocess.run(
                ["git", "-C", str(directory), *arguments],
                capture_output=True,
                text=text,
                timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result.stdout

        def source_blobs():
            blobs = {}
            for path in (*expected, *current_helpers):
                result = subprocess.run(
                    ["git", "-C", str(ROOT), "show", f"HEAD:{path}"],
                    capture_output=True,
                    timeout=30,
                )
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                # Actor members remain the original frozen inputs. Shared
                # helpers may advance: their current Git blob is the byte
                # authority for this transport test, not permission to change
                # an old execution packet's pin.
                if path.startswith("tests/fixtures/"):
                    self.assertEqual(hashlib.sha256(result.stdout).hexdigest(), expected[path], path)
                blobs[path] = result.stdout
            return blobs

        def initialize(directory: Path, attribute_text: str, blobs: dict[str, bytes]):
            directory.mkdir()
            (directory / ".gitattributes").write_text(
                attribute_text, encoding="utf-8", newline="\n"
            )
            for path, payload in blobs.items():
                destination = directory / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(payload)
            git(directory, "init", "-q")
            git(directory, "config", "user.name", "Finite-four transport control")
            git(directory, "config", "user.email", "finite-four@example.invalid")
            git(directory, "add", ".")
            git(directory, "commit", "-qm", "finite-four transport source")
            expected_tree = {".gitattributes", *blobs}
            tree = set(git(directory, "ls-tree", "-r", "--name-only", "HEAD", text=True).splitlines())
            self.assertEqual(expected_tree, tree)

        def checkout(source: Path, name: str, autocrlf: str) -> Path:
            destination = self.directory / name
            result = subprocess.run(
                ["git", "clone", "--quiet", "--depth=1", "-c",
                 f"core.autocrlf={autocrlf}", source.as_uri(), str(destination)],
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(git(destination, "config", "--local", "--get", "core.autocrlf", text=True).strip(), autocrlf)
            return destination

        blobs = source_blobs()
        transport_hashes = {
            path: hashlib.sha256(payload).hexdigest()
            for path, payload in blobs.items()
        }
        governed = self.directory / "governed-source"
        initialize(governed, attributes, blobs)
        for mode in ("true", "false"):
            checked_out = checkout(governed, f"governed-{mode}", mode)
            for path, pin in transport_hashes.items():
                self.assertEqual(
                    hashlib.sha256((checked_out / path).read_bytes()).hexdigest(),
                    pin,
                    (mode, path),
                )

        # This is the pre-fix counterpart: the same raw Git blobs, but
        # no finite-four eol rules.  A true-autocrlf checkout must alter at
        # least the known observer-control hash, so the production assertion
        # cannot be replaced by a text-only attribute check.
        ungoverned_attributes = "\n".join(
            line for line in attributes.splitlines() if line not in rules
        ) + "\n"
        ungoverned = self.directory / "ungoverned-source"
        initialize(ungoverned, ungoverned_attributes, blobs)
        ungoverned_checkout = checkout(ungoverned, "ungoverned-true", "true")
        actual = (ungoverned_checkout / actor).read_bytes()
        self.assertNotEqual(hashlib.sha256(actual).hexdigest(), expected[actor])
        self.assertIn(b"\r\n", actual)


if __name__ == "__main__":
    unittest.main()
