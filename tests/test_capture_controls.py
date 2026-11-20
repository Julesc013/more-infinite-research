"""Host-only controls for the MIR5 active-mods observer capture route.

These controls execute the asset-only fixture in isolated Lua 5.2 and parse
the PowerShell wrappers and small synthetic archive metadata. They never launch Factorio.
"""
import argparse
import base64
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/active-mods-observer"
PROTOTYPE_CAPTURE = ROOT / "tools/Invoke-PrototypeCapture.ps1"
REPLAY_CAPTURE = ROOT / "tools/Invoke-ReplayCapture.ps1"
MENU_COMPARISON = ROOT / "tools/Invoke-MenuComparison.ps1"
NATIVE_FIXTURE = ROOT / "tools/Invoke-NativeFixture.ps1"
LIBRARY_ACTIVATION = ROOT / "tools/lib/compatibility/LibraryActivation.ps1"
NATIVE_COMMON = ROOT / "tools/lib/validation/NativeProbeCommon.ps1"


def assert_powershell_parses(path: Path) -> None:
    escaped = str(path).replace("'", "''")
    command = (
        "$tokens=$null;$errors=$null;"
        "[void][System.Management.Automation.Language.Parser]::ParseFile("
        f"'{escaped}',[ref]$tokens,[ref]$errors);"
        "if($errors.Count){$errors | ForEach-Object {$_.ToString()};exit 1}"
    )
    subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )


def prototype_capture_output_budget_binder_cases() -> dict:
    """Call the real capture entry point without admitting an engine process."""
    missing_factorio = ROOT / "build/tmp/capture-budget-binder/missing-factorio.exe"
    missing_profile = ROOT / "build/tmp/capture-budget-binder/missing-profile.json"
    output_root = ROOT / "build/tmp/capture-budget-binder/output"
    common = [
        "pwsh",
        "-NoProfile",
        "-File",
        str(PROTOTYPE_CAPTURE),
        "-ArchiveLibrary",
        str(ROOT),
        "-FactorioBin",
        str(missing_factorio),
        "-ProfilePath",
        str(missing_profile),
        "-OutputRoot",
        str(output_root),
        "-RepoRoot",
        str(ROOT),
    ]

    def invoke(limit: int) -> dict:
        result = subprocess.run(
            [*common, "-MaxNewOutputMiB", str(limit)],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        return {
            "returncode": result.returncode,
            "output": result.stdout + result.stderr,
        }

    return {"eight_gib": invoke(8192), "over_limit": invoke(8193)}


def audio_argument_builder_source() -> str:
    """Load the real shared pure helper without executing a native entry point."""
    path = str(NATIVE_COMMON).replace("'", "''")
    return r"""
$audioTokens=$null;$audioErrors=$null
$audioAst=[Management.Automation.Language.Parser]::ParseFile('__SOURCE__',[ref]$audioTokens,[ref]$audioErrors)
if($audioErrors.Count){throw 'Native common source does not parse'}
$audioFunctions=@($audioAst.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-MIRNativeAudioArguments'},$true))
if($audioFunctions.Count -ne 1){throw 'One real audio argv helper required'}
Invoke-Expression $audioFunctions[0].Extent.Text
""".replace("__SOURCE__", path)


def prototype_capture_argument_cases() -> dict:
    """Execute the actual argv builder without starting capture or an engine."""
    source = str(PROTOTYPE_CAPTURE).replace("'", "''")
    script = audio_argument_builder_source() + r"""
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile('__SOURCE__',[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Capture source does not parse'}
$functions=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-MIR5PrototypeCaptureArguments'},$true))
if($functions.Count -ne 1){throw 'One real capture argv builder required'}
Invoke-Expression $functions[0].Extent.Text
$common=@{ConfigPath='C:/capture/space dir/config.ini';LibraryDirectory='C:/MIR/test mods'}
@{
  default_gui=@(Get-MIR5PrototypeCaptureArguments @common)
  explicit_gui=@(Get-MIR5PrototypeCaptureArguments @common -Headless:$false)
  headless=@(Get-MIR5PrototypeCaptureArguments @common -Headless)
}|ConvertTo-Json -Depth 5 -Compress
""".replace("__SOURCE__", source)
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", script],
        cwd=ROOT, text=True, capture_output=True, check=True,
    )
    return json.loads(result.stdout)


def native_fixture_argument_cases() -> dict:
    """Stop the actual stage at launch validation; no process can be started."""
    source = str(NATIVE_FIXTURE).replace("'", "''")
    with tempfile.TemporaryDirectory(prefix="mir-headless-stage-") as directory:
        scratch = directory.replace("'", "''")
        script = audio_argument_builder_source() + r"""
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile('__SOURCE__',[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Native fixture source does not parse'}
$functions=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Invoke-FixtureStage'},$true))
if($functions.Count -ne 1){throw 'One actual native stage required'}
Invoke-Expression $functions[0].Extent.Text
function Assert-MIRLibraryLaunch {
  param($Activation,$FactorioBin,$Arguments)
  $script:observed=@($Arguments)
  throw 'HOST_ARGV_BOUNDARY'
}
$writeData='__SCRATCH__';$config='C:/capture/space dir/config.ini'
$activation=[pscustomobject]@{library='C:/MIR/test mods'};$engine='must-never-run'
$results=@{}
foreach($case in @(
  @{name='modern_gui';headless=$false;process=$false;historical=$false;version='2.0'},
  @{name='modern_headless';headless=$true;process=$false;historical=$false;version='2.0'},
  @{name='legacy013_gui';headless=$false;process=$true;historical=$true;version='0.13'},
  @{name='legacy014_gui';headless=$false;process=$true;historical=$true;version='0.14'},
  @{name='legacy110_gui';headless=$false;process=$true;historical=$true;version='1.1'},
  @{name='f110_process_gui';headless=$false;process=$true;historical=$false;version='0.13'},
  @{name='legacy110_headless';headless=$true;process=$true;historical=$true;version='1.1'}
)){
  $Headless=$case.headless;$historicalProcess=$case.process;$historical=$case.historical
  $historicalFixture=[pscustomobject]@{factorio_version=$case.version}
  $script:observed=$null
  try{Invoke-FixtureStage -Name 'host-only' -StageArguments @('--benchmark','owned-input.zip')}
  catch{if($_.Exception.Message -cne 'HOST_ARGV_BOUNDARY'){throw}}
  if($null -eq $script:observed){throw 'Stage failed before actual launch arguments'}
  $results[$case.name]=$script:observed
}
$results|ConvertTo-Json -Depth 5 -Compress
""".replace("__SOURCE__", source).replace("__SCRATCH__", scratch)
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", script], cwd=ROOT,
                                text=True, capture_output=True, check=True)
        return json.loads(result.stdout)


def prototype_capture_archive_guard_cases() -> dict:
    """Exercise the real archive gate without running the capture body or engine."""
    with tempfile.TemporaryDirectory(prefix="mir-capture-archive-") as directory:
        root = Path(directory)
        cases = []

        def case(label, version, *, name="more-infinite-research", family="2.0", engine_line="2.0",
                 wrong_hash=False, wrong_root=False, wrong_filename=False, duplicate_info=False):
            library = root / label
            library.mkdir()
            archive_root = f"{name}_{version}"
            path = library / ("renamed.zip" if wrong_filename else archive_root + ".zip")
            info = {"name": name, "version": version, "factorio_version": family}
            with zipfile.ZipFile(path, "w") as value:
                value.writestr(("wrong-root" if wrong_root else archive_root) + "/info.json", json.dumps(info))
                if duplicate_info:
                    value.writestr("second-root/info.json", json.dumps(info))
            cases.append({"label": label, "path": str(path), "library": str(library), "engine_line": engine_line,
                          "sha256": "0" * 64 if wrong_hash else hashlib.sha256(path.read_bytes()).hexdigest().upper()})

        for version in ("1.1.0", "2.5.11", "3.2.11", "4.7.20003", "5.0.21000"):
            line = "2.1" if version in ("3.2.11", "5.0.21000") else "2.0"
            case("valid-" + version, version, family=line, engine_line=line)
        for version in ("0.1.0", "6.0.21000", "1.1.0-rc.1", "1.111111.0", "4.7.3", "5.0.09"):
            case("invalid-" + version, version)
        case("wrong-hash", "1.1.0", wrong_hash=True)
        case("wrong-family", "1.1.0", family="2.1")
        case("wrong-name", "1.1.0", name="another-mod")
        case("wrong-root", "1.1.0", wrong_root=True)
        case("wrong-filename", "1.1.0", wrong_filename=True)
        case("duplicate-info", "1.1.0", duplicate_info=True)
        manifest = root / "cases.json"
        manifest.write_text(json.dumps(cases), encoding="utf-8", newline="\n")
        capture_path = str(PROTOTYPE_CAPTURE).replace("'", "''")
        manifest_path = str(manifest).replace("'", "''")
        command = f"""
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile('{capture_path}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw 'capture parse failed'}}
$names=@('Assert-MIR5PrototypeCapture','Get-MIR5PrototypeCaptureSha256','Get-MIR5PrototypeCaptureMIRArchive')
$functions=@($ast.FindAll({{param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $names}},$true))
if($functions.Count-ne3){{throw 'capture archive functions differ'}}
foreach($function in $functions){{Invoke-Expression $function.Extent.Text}}
$rows=@(foreach($case in (Get-Content -LiteralPath '{manifest_path}' -Raw|ConvertFrom-Json)){{
  try{{
    $identity=Get-MIR5PrototypeCaptureMIRArchive -Archive $case.path -Library $case.library -ExpectedSha256 $case.sha256 -EngineLine $case.engine_line
    [ordered]@{{label=$case.label;accepted=$true;version=$identity.version;error=$null}}
  }}catch{{[ordered]@{{label=$case.label;accepted=$false;error=$_.Exception.Message}}}}
}})
ConvertTo-Json -InputObject $rows -Depth 5 -Compress
"""
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", command], cwd=ROOT,
                                check=True, text=True, capture_output=True)
        return {row["label"]: row for row in json.loads(result.stdout)}


def prototype_capture_declared_input_guard_cases() -> dict:
    """Run the real capture prefix through declared-input admission only."""
    source = PROTOTYPE_CAPTURE.read_text(encoding="utf-8")
    boundary = "$buildTmp = Join-Path $repo 'build/tmp'"
    offset = source.index(boundary)
    guard = (
        "Assert-MIRDirectLibraryStartupDeclaredInputs -ProfileDefinition "
        "$profileDefinition -EngineIdentity $engineIdentity -ArchiveHashes "
        "$archiveHashes -ErrorPrefix 'mir5-prototype-capture'"
    )
    if source.count(guard) != 1:
        raise AssertionError("prototype capture declared-input assertion is missing or ambiguous")

    with tempfile.TemporaryDirectory(prefix="mir5-prototype-capture-preflight-") as temp:
        root = Path(temp)
        runner = root / "Invoke-PrototypeCapture-preflight.ps1"
        runner.write_text(source[:offset] + "\nreturn\n", encoding="utf-8", newline="\n")
        engine = root / "engine"
        factorio = engine / "bin/x64/factorio.exe"
        factorio.parent.mkdir(parents=True)
        factorio.write_bytes(b"fake Factorio identity for host-only preflight")
        base = engine / "data/base"
        base.mkdir(parents=True)
        (base / "info.json").write_text(
            json.dumps({"name": "base", "version": "2.1.23", "dependencies": []}),
            encoding="utf-8",
        )
        library = root / "library"
        library.mkdir()
        archive = library / "controlled_1.0.0.zip"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as value:
            value.writestr(
                "controlled_1.0.0/info.json",
                json.dumps(
                    {
                        "name": "controlled",
                        "version": "1.0.0",
                        "factorio_version": "2.1",
                        "dependencies": ["base"],
                    }
                ),
            )
        archive_name = archive.name
        archive_hash = hashlib.sha256(archive.read_bytes()).hexdigest().upper()
        engine_hash = hashlib.sha256(factorio.read_bytes()).hexdigest().upper()
        profile = root / "profile.json"
        output = root / "output"

        def invoke(name: str, declared_engine, declared_archives, *, remove_call: bool = False) -> dict:
            active_runner = runner
            if remove_call:
                active_runner = root / "Invoke-PrototypeCapture-preflight-call-removed.ps1"
                active_runner.write_text(
                    (source[:offset].replace(guard, "", 1)) + "\nreturn\n",
                    encoding="utf-8",
                    newline="\n",
                )
            value = {
                "mods": [
                    {"name": "base", "version": "2.1.23", "enabled": True},
                    {"name": "controlled", "version": "1.0.0", "enabled": True},
                ]
            }
            if declared_engine is not None:
                value["engine"] = declared_engine
            if declared_archives is not None:
                value["archive_sha256"] = declared_archives
            profile.write_text(json.dumps(value), encoding="utf-8")
            result = subprocess.run(
                [
                    "pwsh", "-NoProfile", "-File", str(active_runner),
                    "-ArchiveLibrary", str(library),
                    "-FactorioBin", str(factorio),
                    "-ProfilePath", str(profile),
                    "-OutputRoot", str(output),
                    "-RepoRoot", str(ROOT),
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
            )
            return {
                "returncode": result.returncode,
                "output": result.stdout + result.stderr,
                "output_exists": output.exists(),
                "controls_exist": any(
                    (library / name).exists()
                    for name in ("mod-list.json", "mod-settings.dat", ".mir-active-profile.json")
                ),
            }

        valid_engine = {"version": "2.1.23", "sha256": engine_hash}
        valid_archives = {archive_name: archive_hash}
        legacy = invoke("legacy", None, None)
        partial = invoke("partial", valid_engine, {"removed-provider_9.9.9.zip": "A" * 64})
        valid = invoke("valid", valid_engine, valid_archives)
        wrong_version = invoke("wrong-version", {"version": "2.1.22", "sha256": engine_hash}, valid_archives)
        wrong_engine_hash = invoke("wrong-engine-hash", {"version": "2.1.23", "sha256": "0" * 64}, valid_archives)
        wrong_selected = invoke("wrong-selected", valid_engine, {archive_name: "0" * 64})
        malformed_selected = invoke("malformed-selected", valid_engine, {archive_name: "not-a-sha"})
        malformed_map = invoke("malformed-map", valid_engine, "not-an-archive-map")
        call_removed = invoke("call-removed", valid_engine, {archive_name: "0" * 64}, remove_call=True)
        return {
            "legacy": legacy,
            "partial": partial,
            "valid": valid,
            "wrong_version": wrong_version,
            "wrong_engine_hash": wrong_engine_hash,
            "wrong_selected": wrong_selected,
            "malformed_selected": malformed_selected,
            "malformed_map": malformed_map,
            "call_removed": call_removed,
        }


def prototype_capture_file_settings_guard_cases() -> dict:
    """Exercise the real capture preflight through File-settings admission only."""
    source = PROTOTYPE_CAPTURE.read_text(encoding="utf-8")
    boundary = "$buildTmp = Join-Path $repo 'build/tmp'"
    offset = source.index(boundary)
    settings_call = (
        "$captureSettings = Get-MIR5PrototypeCaptureSettingsArguments "
        "-ProfileDefinition $profileDefinition -Path $SettingsPath "
        "-ExpectedSha256 $ExpectedSettingsSha256"
    )
    if source.count(settings_call) != 1:
        raise AssertionError("prototype capture File-settings admission is missing or ambiguous")

    with tempfile.TemporaryDirectory(prefix="mir5-prototype-capture-file-settings-") as temp:
        root = Path(temp)
        runner = root / "Invoke-PrototypeCapture-file-settings-preflight.ps1"
        old_runner = root / "Invoke-PrototypeCapture-file-settings-preflight-old.ps1"
        runner.write_text(source[:offset] + "\nreturn\n", encoding="utf-8", newline="\n")
        old_runner.write_text(
            source[:offset].replace(settings_call, "", 1) + "\nreturn\n",
            encoding="utf-8",
            newline="\n",
        )
        engine = root / "engine"
        factorio = engine / "bin/x64/factorio.exe"
        factorio.parent.mkdir(parents=True)
        factorio.write_bytes(b"fake F200 capture engine identity for host-only settings admission")
        base = engine / "data/base"
        base.mkdir(parents=True)
        (base / "info.json").write_text(
            json.dumps({"name": "base", "version": "2.0.77", "dependencies": []}),
            encoding="utf-8",
        )
        library = root / "library"
        library.mkdir()
        archive = library / "controlled_1.0.0.zip"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as value:
            value.writestr(
                "controlled_1.0.0/info.json",
                json.dumps(
                    {
                        "name": "controlled",
                        "version": "1.0.0",
                        "factorio_version": "2.0",
                        "dependencies": ["base"],
                    }
                ),
            )
        settings = root / "cap10-settings.dat"
        settings.write_bytes(bytes.fromhex("020001001400000000050000000000"))
        settings_hash = hashlib.sha256(settings.read_bytes()).hexdigest().upper()
        archive_hash = hashlib.sha256(archive.read_bytes()).hexdigest().upper()
        engine_hash = hashlib.sha256(factorio.read_bytes()).hexdigest().upper()
        profile = root / "profile.json"
        output = root / "output"

        def invoke(
            name: str,
            *,
            settings_path: Path | None,
            expected_hash: str | None,
            mode: str = "File",
            profile_hash: str | None = None,
            include_profile_hash: bool = True,
            runner_path: Path = runner,
        ) -> dict:
            value = {
                "target": "f200",
                "factorio_line": "2.0",
                "settings_mode": mode,
                "engine": {"version": "2.0.77", "sha256": engine_hash},
                "archive_sha256": {archive.name: archive_hash},
                "mods": [
                    {"name": "base", "version": "2.0.77", "enabled": True},
                    {"name": "controlled", "version": "1.0.0", "enabled": True},
                ],
            }
            if include_profile_hash:
                value["settings_sha256"] = settings_hash if profile_hash is None else profile_hash
            profile.write_text(json.dumps(value), encoding="utf-8", newline="\n")
            command = [
                "pwsh", "-NoProfile", "-File", str(runner_path),
                "-ArchiveLibrary", str(library),
                "-FactorioBin", str(factorio),
                "-ProfilePath", str(profile),
                "-OutputRoot", str(output),
                "-RepoRoot", str(ROOT),
            ]
            if settings_path is not None:
                command.extend(["-SettingsPath", str(settings_path)])
            if expected_hash is not None:
                command.extend(["-ExpectedSettingsSha256", expected_hash])
            result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
            return {
                "returncode": result.returncode,
                "output": result.stdout + result.stderr,
                "output_exists": output.exists(),
                "controls_exist": any(
                    (library / control).exists()
                    for control in ("mod-list.json", "mod-settings.dat", ".mir-active-profile.json")
                ),
            }

        valid = invoke("valid", settings_path=settings, expected_hash=settings_hash)
        defaults = invoke(
            "defaults", settings_path=None, expected_hash=None,
            mode="Defaults", include_profile_hash=False,
        )
        file_without_inputs = invoke("file-without-inputs", settings_path=None, expected_hash=None)
        path_without_hash = invoke("path-without-hash", settings_path=settings, expected_hash=None)
        hash_without_path = invoke("hash-without-path", settings_path=None, expected_hash=settings_hash)
        malformed_hash = invoke("malformed-hash", settings_path=settings, expected_hash="not-a-sha",
                                profile_hash="not-a-sha")
        default_profile = invoke("default-profile", settings_path=settings, expected_hash=settings_hash,
                                 mode="Defaults", include_profile_hash=False)
        profile_hash_mismatch = invoke("profile-hash-mismatch", settings_path=settings,
                                       expected_hash=settings_hash, profile_hash="A" * 64)
        missing_profile_hash = invoke("missing-profile-hash", settings_path=settings,
                                      expected_hash=settings_hash, include_profile_hash=False)
        missing_file = invoke("missing-file", settings_path=root / "missing.dat", expected_hash=settings_hash)
        settings.write_bytes(b"mutated after hash")
        changed_file = invoke("changed-file", settings_path=settings, expected_hash=settings_hash)
        old_file_without_inputs = invoke(
            "old-file-without-inputs", settings_path=None, expected_hash=None, runner_path=old_runner,
        )
        return {
            "valid": valid,
            "defaults": defaults,
            "file_without_inputs": file_without_inputs,
            "path_without_hash": path_without_hash,
            "hash_without_path": hash_without_path,
            "malformed_hash": malformed_hash,
            "default_profile": default_profile,
            "profile_hash_mismatch": profile_hash_mismatch,
            "missing_profile_hash": missing_profile_hash,
            "missing_file": missing_file,
            "changed_file": changed_file,
            "old_file_without_inputs": old_file_without_inputs,
        }


def prototype_capture_linked_settings_case() -> dict:
    """The real shared reparse guard must reject a linked File-mode input."""
    capture = str(PROTOTYPE_CAPTURE).replace("'", "''")
    activation = str(LIBRARY_ACTIVATION).replace("'", "''")
    script = rf'''
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$tokens=$null;$errors=$null
$captureAst=[Management.Automation.Language.Parser]::ParseFile('{capture}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw 'capture parse failed'}}
$activationAst=[Management.Automation.Language.Parser]::ParseFile('{activation}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw 'activation parse failed'}}
foreach($name in @('Assert-MIR5PrototypeCapture','Get-MIR5PrototypeCaptureSha256','Get-MIR5PrototypeCaptureSettingsArguments')){{
  $node=@($captureAst.FindAll({{param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name}},$true))
  if($node.Count-ne1){{throw ('capture settings function differs: '+$name)}}
  Invoke-Expression $node[0].Extent.Text
}}
$pathNode=@($activationAst.FindAll({{param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq'Assert-MIRLibraryPath'}},$true))
if($pathNode.Count-ne1){{throw 'library path guard differs'}}
Invoke-Expression $pathNode[0].Extent.Text
$root=Join-Path ([IO.Path]::GetTempPath()) ('mir5-capture-linked-settings-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
try{{
  $target=Join-Path $root 'target.dat'
  [IO.File]::WriteAllBytes($target,[Convert]::FromHexString('020001001400000000050000000000'))
  $link=Join-Path $root 'linked.dat'
  [IO.File]::CreateSymbolicLink($link,$target)|Out-Null
  $hash=Get-MIR5PrototypeCaptureSha256 $target
  $accepted=$true;$message=''
  try{{Get-MIR5PrototypeCaptureSettingsArguments @{{settings_mode='File';settings_sha256=$hash}} $link $hash|Out-Null}}catch{{$accepted=$false;$message=$_.Exception.Message}}
  [ordered]@{{accepted=$accepted;message=$message;link_attributes=[string](Get-Item -LiteralPath $link -Force).Attributes}}|ConvertTo-Json -Compress
}} finally {{[IO.Directory]::Delete($root,$true)}}
'''
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-NonInteractive", "-Command", script],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(result.stdout)


def native_fixture_observer_guard_cases() -> dict:
    """Execute the wrapper's isolated observer-binding helper, never its runner."""
    escaped = str(NATIVE_FIXTURE).replace("'", "''")
    command = rf"""
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw ($errors | ForEach-Object {{$_.ToString()}})}}
$definition=@($ast.Find({{param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-FixtureActiveModsObserver'}},$true))
if($definition.Count -ne 1){{throw 'observer helper missing or ambiguous'}}
function Assert-Fixture([bool]$Condition,[string]$Message) {{if(-not $Condition){{throw "[mir5-native-fixture] $Message"}}}}
. ([scriptblock]::Create($definition[0].Extent.Text))
function Invoke-ObserverCase([string]$Name,[object[]]$Rows,[object[]]$Inputs) {{
  try {{[ordered]@{{valid=$true;value=(Get-FixtureActiveModsObserver -Name $Name -ProfileRows $Rows -FixtureInputs $Inputs)}}}}
  catch {{[ordered]@{{valid=$false;message=$_.Exception.Message}}}}
}}
$verified=@([pscustomobject]@{{name='mir-fixture-mir5-active-mods-observer';version='0.1.0';source='fixture-source';archive='fixture.zip';sha256=('A'*64)}})
$selected=@([pscustomobject]@{{name='mir-fixture-mir5-active-mods-observer';version='0.1.0';enabled=$true}})
$cases=[ordered]@{{
  positive=(Invoke-ObserverCase 'mir-fixture-mir5-active-mods-observer' $selected $verified)
  blank=(Invoke-ObserverCase '   ' $selected $verified)
  missing=(Invoke-ObserverCase 'mir-fixture-mir5-active-mods-observer' @([pscustomobject]@{{name='other';version='0.1.0';enabled=$true}}) $verified)
  unselected=(Invoke-ObserverCase 'mir-fixture-mir5-active-mods-observer' @([pscustomobject]@{{name='mir-fixture-mir5-active-mods-observer';version='0.1.0';enabled=$false}}) $verified)
  unverified=(Invoke-ObserverCase 'mir-fixture-mir5-active-mods-observer' $selected @([pscustomobject]@{{name='other';version='0.1.0';source='other';archive='other.zip';sha256=('B'*64)}}))
}}
$cases | ConvertTo-Json -Compress -Depth 6
"""
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return json.loads(result.stdout)


def native_fixture_active_marker_guard_cases() -> dict:
    """Exercise only the finite active-marker reader, never Factorio."""
    escaped = str(NATIVE_FIXTURE).replace("'", "''")
    command = rf"""
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw ($errors | ForEach-Object {{$_.ToString()}})}}
$definition=@($ast.Find({{param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Read-ActiveFixtureMarker'}},$true))
if($definition.Count -ne 1){{throw 'active marker helper missing or ambiguous'}}
function Assert-Fixture([bool]$Condition,[string]$Message) {{if(-not$Condition){{throw "[mir5-native-fixture] $Message"}}}}
. ([scriptblock]::Create($definition[0].Extent.Text))
function Invoke-ActiveCase([string]$Text,[string]$Kind,[string]$Stage) {{
  try {{[ordered]@{{valid=$true;value=(Read-ActiveFixtureMarker $Text $Kind $Stage)}}}}
  catch {{[ordered]@{{valid=$false;message=$_.Exception.Message}}}}
}}
$prepared='[MIR5_RUNTIME_ACTIVE] {{"kind":"repair-stress","stage":"prepared","status":"pending"}}'
$complete='[MIR5_RUNTIME_ACTIVE] {{"kind":"repair-stress","stage":"complete","status":"passed"}}'
$cases=[ordered]@{{
  positive=(Invoke-ActiveCase $prepared 'repair-stress' 'prepared')
  duplicate=(Invoke-ActiveCase ($prepared+"`n"+$prepared) 'repair-stress' 'prepared')
  wrong_kind=(Invoke-ActiveCase $prepared 'agriculture-scale' 'prepared')
  wrong_status=(Invoke-ActiveCase $complete 'repair-stress' 'prepared')
  unsupported_stage=(Invoke-ActiveCase $prepared 'repair-stress' 'other')
}}
$cases | ConvertTo-Json -Compress -Depth 6
"""
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return json.loads(result.stdout)


def native_fixture_active_selection_guard_cases() -> dict:
    """Exercise the finite published/candidate repair selection rule only."""
    escaped = str(NATIVE_FIXTURE).replace("'", "''")
    command = rf"""
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw ($errors | ForEach-Object {{$_.ToString()}})}}
$definition=@($ast.Find({{param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-ActiveFixtureSelection'}},$true))
if($definition.Count -ne 1){{throw 'active selection helper missing or ambiguous'}}
function Assert-Fixture([bool]$Condition,[string]$Message) {{if(-not$Condition){{throw "[mir5-native-fixture] $Message"}}}}
. ([scriptblock]::Create($definition[0].Extent.Text))
function Invoke-SelectionCase([object[]]$Rows,[object[]]$Mir) {{
  try {{Assert-ActiveFixtureSelection 'repair-stress' $Rows $Mir;[ordered]@{{valid=$true}}}}
  catch {{[ordered]@{{valid=$false;message=$_.Exception.Message}}}}
}}
function New-RepairRows([string]$Version) {{@(
  [pscustomobject]@{{name='mir-fixture-mir5-repair-stress-active';version='0.1.0';enabled=$true}},
  [pscustomobject]@{{name='mir-fixture-mir5-repair-stress';version=$Version;enabled=$true}}
)}}
$cases=[ordered]@{{
  published=(Invoke-SelectionCase (New-RepairRows '0.1.0') @([pscustomobject]@{{name='more-infinite-research';version='4.7.21002'}}))
  candidate=(Invoke-SelectionCase (New-RepairRows '0.2.0') @([pscustomobject]@{{name='more-infinite-research';version='5.0.21000'}}))
  candidate_wrong_base=(Invoke-SelectionCase (New-RepairRows '0.1.0') @([pscustomobject]@{{name='more-infinite-research';version='5.0.21000'}}))
  candidate501=(Invoke-SelectionCase (New-RepairRows '0.2.0') @([pscustomobject]@{{name='more-infinite-research';version='5.0.21001'}}))
  candidate501_missing_selector=(Invoke-SelectionCase @([pscustomobject]@{{name='mir-fixture-mir5-repair-stress';version='0.2.0';enabled=$true}}) @([pscustomobject]@{{name='more-infinite-research';version='5.0.21001'}}))
  candidate501_wrong_selector=(Invoke-SelectionCase @([pscustomobject]@{{name='mir-fixture-mir5-repair-stress-active';version='0.2.0';enabled=$true}},[pscustomobject]@{{name='mir-fixture-mir5-repair-stress';version='0.2.0';enabled=$true}}) @([pscustomobject]@{{name='more-infinite-research';version='5.0.21001'}}))
  candidate501_wrong_base=(Invoke-SelectionCase (New-RepairRows '0.1.0') @([pscustomobject]@{{name='more-infinite-research';version='5.0.21001'}}))
  unknown_mir=(Invoke-SelectionCase (New-RepairRows '0.2.0') @([pscustomobject]@{{name='more-infinite-research';version='5.0.21002'}}))
}}
$cases | ConvertTo-Json -Compress -Depth 6
"""
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return json.loads(result.stdout)


def native_fixture_active_create_target_cases() -> dict:
    """Execute the wrapper's own save-target and create-call AST nodes only."""
    escaped = str(NATIVE_FIXTURE).replace("'", "''")
    command = rf"""
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw ($errors | ForEach-Object {{$_.ToString()}})}}
$assignments=@($ast.FindAll({{param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst]}},$true))
$activeSave=@($assignments|Where-Object {{ $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'activeSave' }})
$seed=@($assignments|Where-Object {{ $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'seed' -and $_.Extent.Text -match 'repair-stress' }})
$create=@($assignments|Where-Object {{ $_.Extent.Text -match '^\$record\.create\s*=\s*Invoke-FixtureStage' }})
$createArguments=@($assignments|Where-Object {{ $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'createArguments' }})
$selector=@($ast.FindAll({{param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-FixtureCreateArguments'}},$true))
if($activeSave.Count -ne 1 -or $seed.Count -ne 1 -or $create.Count -ne 1 -or $createArguments.Count -ne 1 -or $selector.Count -ne 1){{throw 'active save target assignments missing or ambiguous'}}
. ([scriptblock]::Create($selector[0].Extent.Text))
function Invoke-TargetCase([bool]$Active,[string]$Kind) {{
  $activeSeed=$Active;$ActiveSeedKind=$Kind;$writeData='D:\owned-write-data';$record=[ordered]@{{}}
  $CaseName=if($Active){{$Kind+'-active'}}else{{'ordinary'}};$CreateOnly=$false
  function Invoke-FixtureStage([string]$Stage,[object[]]$Arguments) {{[pscustomobject]@{{stage=$Stage;arguments=$Arguments;log='unused'}}}}
  . ([scriptblock]::Create($activeSave[0].Extent.Text))
  . ([scriptblock]::Create($seed[0].Extent.Text))
  . ([scriptblock]::Create($createArguments[0].Extent.Text))
  . ([scriptblock]::Create($create[0].Extent.Text))
  [ordered]@{{active_save=$activeSave;seed=$seed;create=$record.create.arguments}}
}}
[ordered]@{{
  repair_active=(Invoke-TargetCase $true 'repair-stress')
  agriculture_active=(Invoke-TargetCase $true 'agriculture-scale')
  ordinary=(Invoke-TargetCase $false '')
}} | ConvertTo-Json -Compress -Depth 6
"""
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return json.loads(result.stdout)


def native_fixture_agriculture_completion_guard_cases() -> dict:
    """Invoke the actual active-seed predicate through a separate caller scope."""
    escaped = str(NATIVE_FIXTURE).replace("'", "''")
    command = rf"""
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw ($errors | ForEach-Object {{$_.ToString()}})}}
$definitions=@($ast.FindAll({{param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Test-HistoricalFixtureSaveComplete'}},$true))
$assignments=@($ast.FindAll({{param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst]}},$true))
$activeSaveCompleteAssignment=@($assignments | Where-Object {{ $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'activeSaveComplete' }})
$completion=@($assignments | Where-Object {{ $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'activeCompletion' }})
if($definitions.Count -ne 1 -or $activeSaveCompleteAssignment.Count -ne 1 -or $completion.Count -ne 1){{throw 'active agriculture completion nodes missing or ambiguous'}}
. ([scriptblock]::Create($definitions[0].Extent.Text))
function Invoke-GovernorStylePredicate([scriptblock]$Predicate) {{
  try {{
    $decision=@(& $Predicate)
    if($decision.Count -ne 1 -or $decision[0] -isnot [bool]){{throw 'completion predicate did not return one bool'}}
    [ordered]@{{valid=$true;result=$decision[0]}}
  }} catch {{[ordered]@{{valid=$false;message=$_.Exception.Message}}}}
}}
function Write-ClosedFixtureSave([string]$Path,[bool]$Complete) {{
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $stream=$null;$zip=$null
  try {{
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
    if($Complete){{
      $root=[IO.Path]::GetFileNameWithoutExtension($Path)
      $entry=$zip.CreateEntry($root+'/level.dat')
      $writer=[IO.StreamWriter]::new($entry.Open())
      try {{$writer.Write('fixture')}} finally {{$writer.Dispose()}}
    }}
  }} finally {{if($null-ne$zip){{$zip.Dispose()}};if($null-ne$stream){{$stream.Dispose()}}}}
}}
function Invoke-ActiveCompletionCase([string]$Name,[AllowNull()][string]$Text,[bool]$SavePresent,[bool]$SaveComplete) {{
  $caseRoot=Join-Path $root $Name
  [IO.Directory]::CreateDirectory($caseRoot)|Out-Null
  $live=Join-Path $caseRoot 'factorio-current.log'
  $activeSave=Join-Path $caseRoot 'mir5-native-active.zip'
  if($null-ne$Text){{[IO.File]::WriteAllText($live,$Text,[Text.UTF8Encoding]::new($false))}}
  if($SavePresent){{Write-ClosedFixtureSave $activeSave $SaveComplete}}
  . ([scriptblock]::Create($activeSaveCompleteAssignment[0].Extent.Text))
  . ([scriptblock]::Create($completion[0].Extent.Text))
  Invoke-GovernorStylePredicate $activeCompletion
}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('mir5-active-completion-'+[Guid]::NewGuid().ToString('N'))
$marker='[MIR5_RUNTIME_ACTIVE] {{"kind":"agriculture-scale","stage":"prepared","status":"pending"}}'
try {{
  $cases=[ordered]@{{
    no_log=(Invoke-ActiveCompletionCase 'no-log' $null $true $true)
    missing_marker=(Invoke-ActiveCompletionCase 'missing-marker' 'Saving finished' $true $true)
    valid=(Invoke-ActiveCompletionCase 'valid' ($marker+"`nSaving finished") $true $true)
    fatal=(Invoke-ActiveCompletionCase 'fatal' ($marker+"`n0.001 Error native failure") $true $true)
    duplicate_marker=(Invoke-ActiveCompletionCase 'duplicate-marker' ($marker+"`n"+$marker+"`nSaving finished") $true $true)
    malformed_marker=(Invoke-ActiveCompletionCase 'malformed-marker' (('[MIR5_RUNTIME_ACTIVE] {{not-json}}')+"`nSaving finished") $true $true)
    unclosed_save=(Invoke-ActiveCompletionCase 'unclosed-save' ($marker+"`nSaving finished") $true $false)
    absent_save=(Invoke-ActiveCompletionCase 'absent-save' ($marker+"`nSaving finished") $false $false)
  }}
  $cases | ConvertTo-Json -Compress -Depth 6
}} finally {{if(Test-Path -LiteralPath $root){{Remove-Item -LiteralPath $root -Recurse -Force}}}}
"""
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return json.loads(result.stdout)


def loaded_selection_launch_cases(*, remove_coverage: bool = False) -> dict:
    """Exercise the actual launch guard over real ZIPs; the endpoint is a counter."""
    scratch = ROOT / "build/tmp"
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="mir-observation-launch-", dir=scratch) as directory:
        root = Path(directory).resolve()
        assert root.is_relative_to(scratch.resolve())
        library = root / "library"
        library.mkdir()
        engine = root / "engine"
        executable = engine / "bin/x64/factorio.exe"
        executable.parent.mkdir(parents=True)
        executable.write_bytes(b"host test; never executed")
        base = engine / "data/base"
        base.mkdir(parents=True)
        (base / "info.json").write_text('{"name":"base","version":"2.1.24"}', encoding="utf-8")
        (base / "data.lua").write_text("-- native loading entry\n", encoding="utf-8")
        write_data = root / "write-data"
        write_data.mkdir()
        config = root / "config.ini"
        config.write_text(
            f"[path]\nread-data={engine / 'data'}\nwrite-data={write_data}\n"
            "[other]\nenable-new-mods=false\n", encoding="utf-8"
        )

        def archive(name: str, scripts: tuple[str, ...], *, prefix: str | None = None) -> dict:
            path = library / f"{name}_1.0.0.zip"
            prefix = prefix or f"{name}_1.0.0"
            with zipfile.ZipFile(path, "w") as z:
                z.writestr(f"{prefix}/info.json", json.dumps({"name": name, "version": "1.0.0"}))
                for script in scripts:
                    z.writestr(f"{prefix}/{script}", "-- host fixture\n")
            return {"name": name, "version": "1.0.0", "path": str(path), "builtin": False,
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest().upper()}

        base_row = {"name": "base", "version": "2.1.24", "path": str(base / "info.json"),
                    "builtin": True, "sha256": "A" * 64}
        ordinary = archive("ordinary", ("data.lua",), prefix="arbitrary-valid-root")
        settings = archive("settings-only", ("settings-updates.lua",))
        assets = archive("assets", ())
        control = archive("control-only", ("control.lua",))
        wrong_case = archive("wrong-case", ("Data.lua",))
        observer = archive("observer", ("data-final-fixes.lua",))
        control_observer = archive("control-observer", ("control.lua",))
        broken = archive("unreadable", ("data.lua",))
        Path(broken["path"]).unlink()
        cases = []

        def case(name: str, rows: list[dict], observer_name: str = "", *,
                 script: str = "data-final-fixes.lua", require: bool = True) -> None:
            cases.append({"name": name, "selected": [base_row, *rows], "observer": observer_name,
                          "script": script, "require": require})

        case("ordinary", [ordinary])
        case("settings", [settings])
        case("assets", [assets])
        case("control-only", [control])
        case("wrong-case", [wrong_case])
        case("valid-observer", [assets, observer], "observer")
        case("missing-observer", [assets], "observer")
        case("disabled-observer", [assets], "observer")  # Present on disk, absent from active selection.
        case("builtin-observer", [assets], "base")
        case("unbound-observer", [assets, {**observer, "sha256": ""}], "observer")
        case("wrong-script", [assets, control_observer], "control-observer")
        case("control-observer", [assets, control_observer], "control-observer", script="control.lua")
        case("duplicate-observer", [assets, observer, observer], "observer")
        case("read-failure", [broken])
        case("no-complete-selection-claim", [assets], require=False)
        definition = root / "cases.json"
        definition.write_text(json.dumps(cases), encoding="utf-8")
        script = r"""
          Set-StrictMode -Version Latest; $ErrorActionPreference='Stop'
          . (Join-Path $env:MIR_TEST_REPO 'tools/lib/compatibility/LibraryActivation.ps1')
          # The unit is launch admission, not activation/custody already covered elsewhere.
          function Assert-MIRLibraryActivation { param($Activation,$OwnedProcesses) }
          if($env:MIR_TEST_REMOVE_COVERAGE-ceq'1') {
            function Assert-MIRLibraryObservationCoverage { param($Activation,$ActiveModsObserver,$ActiveModsObserverScript) }
          }
          $root=$env:MIR_TEST_CASE
          $rows=Get-Content -Raw -LiteralPath (Join-Path $root 'cases.json')|ConvertFrom-Json
          $observations=@(foreach($case in $rows) {
            $activation=[pscustomobject]@{library=(Join-Path $root 'library');engine_data=(Join-Path $root 'engine/data');selected=@($case.selected)}
            $launches=0; $errorText=$null; $errorType=$null
            try {
              Assert-MIRLibraryLaunch -Activation $activation -FactorioBin (Join-Path $root 'engine/bin/x64/factorio.exe') -Arguments @('--config',(Join-Path $root 'config.ini'),'--mod-directory',$activation.library,'--dump-data') -RequireLoadedSelection:$case.require -ActiveModsObserver $case.observer -ActiveModsObserverScript $case.script
              $launches++  # Stubbed child endpoint. No executable is invoked.
            } catch {
              $errorText=$_.Exception.Message
              $errorType=$_.Exception.GetType().FullName
              if($_.Exception.InnerException){$errorType+=' / '+$_.Exception.InnerException.GetType().FullName}
            }
            [ordered]@{name=$case.name;launches=$launches;error=$errorText;error_type=$errorType}
          })
          ConvertTo-Json -InputObject $observations -Depth 10 -Compress
        """
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", script], cwd=ROOT,
                                env={**os.environ, "MIR_TEST_REPO": str(ROOT), "MIR_TEST_CASE": str(root),
                                     "MIR_TEST_REMOVE_COVERAGE": "1" if remove_coverage else "0"},
                                capture_output=True, text=True, check=True)
        return {row["name"]: row for row in json.loads(result.stdout)}


class CaptureControlTests(unittest.TestCase):
    def test_broad_native_receipts_preserve_failures_and_data_only_scope(self):
        payload = (ROOT / "spec/evidence/broad-ecosystem-f210-b2-native-receipts.json.gz").read_bytes()
        self.assertEqual(hashlib.sha256(payload).hexdigest().upper(),
                         "EEABA91C8F39C7348084F987A314999D246C77CDE38AFBE78EAF563AD5124E4A")
        capsule = json.loads(gzip.decompress(payload))
        files = {}
        for row in capsule["files"]:
            value = base64.b64decode(row["base64"], validate=True)
            self.assertEqual(len(value), row["bytes"])
            self.assertEqual(hashlib.sha256(value).hexdigest().upper(), row["sha256"])
            self.assertNotIn(row["path"], files)
            files[row["path"]] = json.loads(value)
        self.assertEqual(len(files), 75)
        native = [value for name, value in files.items() if name.endswith("/result.json")]
        self.assertEqual(len(native), 64)
        self.assertEqual(sum(row["status"] == "completed-data-stage-observation-only" for row in native), 41)
        self.assertEqual(sum(row["status"] == "failed" for row in native), 23)
        self.assertTrue(all(row["library_controls_restored"] for row in native))
        chain = json.loads((ROOT / "spec/evidence/broad-ecosystem-f210-b2-native-chain.json").read_bytes())
        for key in ("full_mod_parity", "research_qualification", "physical_qualification",
                    "save_qualification", "client_qualification", "performance_qualification", "release_qualification"):
            self.assertFalse(chain["claims"][key])
        comparison = files["root-independent-broad-data-readback-r01.json"]["three_arm_public_technology_comparisons"]
        self.assertEqual(sum(not row["unresolved_full_row_differences"] for row in comparison), 11)
        self.assertEqual(len(next(row for row in comparison if row["id"] == "c01")["unresolved_full_row_differences"]), 31)

    @classmethod
    def setUpClass(cls):
        cls.lua = LuaRuntime(unpack_returned_tuples=True)
        cls.lua.execute(r"""
          function execute_active_mods_fixture(path, supplied_mods, provide_mods)
            local lines = {}
            local environment = {
              log = function(message) lines[#lines + 1] = message end
            }
            if provide_mods then environment.mods = supplied_mods end
            setmetatable(environment, {__index = function(_, key) return _G[key] end})
            local chunk, message = loadfile(path, "t", environment)
            if chunk == nil then return false, message, lines end
            local ok, result = pcall(chunk)
            return ok, result, lines
          end
        """)

    def run_fixture(self, mods, provide_mods=True):
        self.lua.globals().fixture_path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().fixture_mods = mods
        self.lua.globals().fixture_has_mods = provide_mods
        return self.lua.eval(
            "execute_active_mods_fixture(fixture_path, fixture_mods, fixture_has_mods)"
        )

    def test_fixture_has_only_the_shared_observer_and_exact_target_metadata(self):
        for member, family, minimum in (("info.json", "2.1", "2.1.23"),
                                        ("info-f200.json", "2.0", "2.0.77")):
            with self.subTest(member=member):
                info = json.loads((FIXTURE / member).read_text(encoding="utf-8"))
                self.assertEqual(info["name"], "mir-fixture-mir5-active-mods-observer")
                self.assertEqual(info["version"], "0.1.0")
                self.assertEqual(info["factorio_version"], family)
                self.assertEqual(info["dependencies"], [f"base >= {minimum}"])
        self.assertEqual(
            sorted(path.name for path in FIXTURE.iterdir()),
            ["data-final-fixes.lua", "info-f200.json", "info.json"],
        )

    def test_complete_selection_rejects_unobservable_mods_before_child_launch(self):
        cases = loaded_selection_launch_cases()
        for name in ("assets", "control-only", "wrong-case"):
            with self.subTest(name=name):
                self.assertEqual(cases[name]["launches"], 0)
                self.assertIn("[mir-library-loaded-observer-required]", cases[name]["error"])
        for name in ("missing-observer", "disabled-observer", "builtin-observer",
                     "unbound-observer", "wrong-script", "duplicate-observer"):
            with self.subTest(name=name):
                self.assertEqual(cases[name]["launches"], 0)
                self.assertIn("[mir-library-loaded-observer", cases[name]["error"])
        self.assertEqual(cases["read-failure"]["launches"], 0)
        self.assertIn("FileNotFoundException", cases["read-failure"]["error_type"])
        self.assertNotIn("loaded-observer-required", cases["read-failure"]["error"])

    def test_complete_selection_allows_real_loading_entries_and_bound_observers(self):
        cases = loaded_selection_launch_cases()
        for name in ("ordinary", "settings", "valid-observer", "control-observer", "no-complete-selection-claim"):
            with self.subTest(name=name):
                self.assertEqual(cases[name]["launches"], 1, cases[name])
                self.assertIsNone(cases[name]["error"])

    def test_launch_opponent_demonstrates_missing_coverage_would_start_asset_case(self):
        cases = loaded_selection_launch_cases(remove_coverage=True)
        self.assertEqual(cases["assets"]["launches"], 1)
        self.assertIsNone(cases["assets"]["error"])

    def test_full_selection_callers_admit_the_same_observer_before_process_start(self):
        script = r"""
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          function Observer-Argument($Command) {
            for($i=0;$i-lt$Command.CommandElements.Count-1;$i++) {
              $e=$Command.CommandElements[$i]
              if($e-is[Management.Automation.Language.CommandParameterAst]-and$e.ParameterName-ceq'ActiveModsObserver') {
                return $Command.CommandElements[$i+1].Extent.Text
              }
            }
            return ''
          }
          function Check-Wiring([string]$Text) {
            $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$t,[ref]$e)
            if($e.Count){return $false}
            $commands=@($ast.FindAll({param($n) $n-is[Management.Automation.Language.CommandAst]},$true))
            $launches=@($commands|Where-Object {$_.GetCommandName()-ceq'Assert-MIRLibraryLaunch'})
            $proofs=@($commands|Where-Object {$_.GetCommandName()-ceq'Assert-MIRLibraryLoadedSelection'})
            $processes=@($commands|Where-Object {$_.GetCommandName()-in@('Invoke-MIRNativeProbeFactorioProcess','Invoke-MIRNativeProbeProcess')})
            if($launches.Count-ne1-or$proofs.Count-ne1-or$processes.Count-ne1){return $false}
            $required=@($launches[0].CommandElements|Where-Object {$_-is[Management.Automation.Language.CommandParameterAst]-and$_.ParameterName-ceq'RequireLoadedSelection'})
            $observer=Observer-Argument $launches[0]
            return $required.Count-eq1-and$observer-ne''-and$observer-ceq(Observer-Argument $proofs[0])-and$launches[0].Extent.StartOffset-lt$processes[0].Extent.StartOffset-and$processes[0].Extent.StartOffset-lt$proofs[0].Extent.StartOffset
          }
          $rows=@(foreach($path in @('tools/Invoke-PrototypeCapture.ps1','tools/Invoke-NativeFixture.ps1','tools/lib/validation/DirectLibraryStartupMeasurement.ps1')) {
            $text=[IO.File]::ReadAllText((Join-Path $env:MIR_TEST_REPO $path))
            $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$t,[ref]$e)
            $launch=@($ast.FindAll({param($n) $n-is[Management.Automation.Language.CommandAst]-and$n.GetCommandName()-ceq'Assert-MIRLibraryLaunch'},$true))[0]
            $flag=@($launch.CommandElements|Where-Object {$_-is[Management.Automation.Language.CommandParameterAst]-and$_.ParameterName-ceq'RequireLoadedSelection'})[0]
            $withoutFlag=$text.Substring(0,$flag.Extent.StartOffset)+$text.Substring($flag.Extent.EndOffset)
            $argument=Observer-Argument $launch
            $wrongCall=$launch.Extent.Text.Replace('-ActiveModsObserver '+$argument,"-ActiveModsObserver 'wrong-observer'")
            $wrongObserver=$text.Substring(0,$launch.Extent.StartOffset)+$wrongCall+$text.Substring($launch.Extent.EndOffset)
            $t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseInput($withoutFlag,[ref]$t,[ref]$e);$flagParses=$e.Count-eq0
            $t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseInput($wrongObserver,[ref]$t,[ref]$e)
            [ordered]@{path=$path;admitted=Check-Wiring $text;missing_flag=Check-Wiring $withoutFlag;different_observer=Check-Wiring $wrongObserver;missing_flag_parses=$flagParses;different_observer_parses=($e.Count-eq0)}
          })
          ConvertTo-Json -InputObject $rows -Depth 6 -Compress
        """
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", script], cwd=ROOT,
                                env={**os.environ, "MIR_TEST_REPO": str(ROOT)},
                                capture_output=True, text=True, check=True)
        for row in json.loads(result.stdout):
            with self.subTest(path=row["path"]):
                self.assertTrue(row["admitted"])
                self.assertFalse(row["missing_flag"])
                self.assertFalse(row["different_observer"])
                self.assertTrue(row["missing_flag_parses"])
                self.assertTrue(row["different_observer_parses"])

    def test_fixture_reports_the_actual_mod_table_in_sorted_order_once(self):
        mods = self.lua.table_from({
            "z-last": "9.0.0",
            "base": "2.1.23",
            "alpha-observer": "0.1.0",
        })
        ok, message, lines = self.run_fixture(mods)
        self.assertTrue(ok, message)
        self.assertEqual(len(lines), 1)
        self.assertEqual(
            lines[1],
            "[MIR_ACTIVE_MODS] alpha-observer@0.1.0|base@2.1.23|z-last@9.0.0",
        )

    def test_fixture_keeps_an_empty_actual_table_distinct_from_missing_mods(self):
        ok, message, lines = self.run_fixture(self.lua.table())
        self.assertTrue(ok, message)
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[1], "[MIR_ACTIVE_MODS] ")

        ok, message, lines = self.run_fixture(None, provide_mods=False)
        self.assertFalse(ok)
        self.assertIn("Factorio data-stage mods dictionary is required", message)
        self.assertEqual(len(lines), 0)

    def test_fixture_rejects_a_non_string_native_mod_dictionary_row(self):
        mods = self.lua.table_from({"base": 2123})
        ok, message, lines = self.run_fixture(mods)
        self.assertFalse(ok)
        self.assertIn("mods must map string names to string versions", message)
        self.assertEqual(len(lines), 0)

    def test_fixture_does_not_touch_product_or_runtime_surfaces(self):
        source = (FIXTURE / "data-final-fixes.lua").read_text(encoding="utf-8")
        self.assertNotIn("require(", source)
        self.assertNotIn("data.raw", source)
        self.assertNotIn("settings", source)
        self.assertNotIn("script.", source)
        self.assertNotIn("game.", source)
        self.assertNotIn("more-infinite-research", source)

    def test_capture_wrappers_forward_an_optional_hash_bound_observer(self):
        prototype = PROTOTYPE_CAPTURE.read_text(encoding="utf-8")
        replay = REPLAY_CAPTURE.read_text(encoding="utf-8")
        menu = MENU_COMPARISON.read_text(encoding="utf-8")
        native_fixture = NATIVE_FIXTURE.read_text(encoding="utf-8")

        for source in (prototype, replay, menu, native_fixture):
            self.assertRegex(source, r"\[string\]\$ActiveModsObserver\s*=\s*''")

        self.assertIn(
            "Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $factorioLog "
            "-LatestInvocation -ActiveModsObserver $activeModsObserver",
            prototype,
        )
        self.assertIn("ActiveModsObserver must be selected exactly once", prototype)
        self.assertIn("ActiveModsObserver must be a hash-bound archive", prototype)
        self.assertIn("active_mods_observer = [ordered]", prototype)
        self.assertIn("-ActiveModsObserver $ActiveModsObserver", replay)
        self.assertIn("-ActiveModsObserver $Inputs.active_mods_observer", menu)
        self.assertIn("active_mods_observer=$activeModsObserver", menu)
        self.assertIn("function Get-FixtureActiveModsObserver", native_fixture)
        self.assertIn("ActiveModsObserver must be a verified FixtureSources input", native_fixture)
        self.assertIn("$activation.selected | Where-Object", native_fixture)
        self.assertIn("$record.active_mods_observer=[ordered]", native_fixture)
        self.assertIn(
            "-LatestInvocation -ActiveModsObserver $activeModsObserverName",
            native_fixture,
        )

    def test_capture_archive_gate_admits_pinned_modern_historical_and_extended_metadata(self):
        cases = prototype_capture_archive_guard_cases()
        for version in ("1.1.0", "2.5.11", "3.2.11", "4.7.20003", "5.0.21000"):
            with self.subTest(version=version):
                case = cases["valid-" + version]
                self.assertTrue(case["accepted"], case["error"])
                self.assertEqual(version, case["version"])

    def test_capture_archive_gate_retains_version_and_immutable_identity_rejections(self):
        cases = prototype_capture_archive_guard_cases()
        rejected = [label for label in cases if not label.startswith("valid-")]
        self.assertEqual(12, len(rejected))
        for label in rejected:
            with self.subTest(case=label):
                self.assertFalse(cases[label]["accepted"])
                self.assertIn("[mir5-prototype-capture]", cases[label]["error"])

    def test_prototype_capture_accepts_the_declared_eight_gib_output_budget_only(self):
        cases = prototype_capture_output_budget_binder_cases()

        self.assertNotEqual(cases["eight_gib"]["returncode"], 0)
        self.assertNotIn("maximum allowed range", cases["eight_gib"]["output"])
        self.assertIn("missing-factorio.exe", cases["eight_gib"]["output"])

        self.assertNotEqual(cases["over_limit"]["returncode"], 0)
        self.assertIn("MaxNewOutputMiB", cases["over_limit"]["output"])
        self.assertIn("maximum allowed range", cases["over_limit"]["output"])
        self.assertNotIn("missing-factorio.exe", cases["over_limit"]["output"])

    def test_prototype_capture_selects_explicit_headless_argv_and_preserves_gui_default(self):
        cases = prototype_capture_argument_cases()
        common = ["--config", "C:/capture/space dir/config.ini", "--mod-directory", "C:/MIR/test mods", "--no-log-rotation"]
        self.assertEqual([*common, "--disable-audio", "--dump-data"], cases["default_gui"])
        self.assertEqual(cases["default_gui"], cases["explicit_gui"])
        # The real headless 2.0.77 CLI rejects --disable-audio. This expected
        # vector also opposes accidentally appending the GUI option universally.
        self.assertEqual([*common, "--dump-data"], cases["headless"])
        source = PROTOTYPE_CAPTURE.read_text(encoding="utf-8")
        self.assertIn("$arguments = @(Get-MIR5PrototypeCaptureArguments -ConfigPath $config -LibraryDirectory $activation.library -Headless:$Headless)", source)
        self.assertIn("headless_requested=[bool]$Headless", source)
        self.assertIn("$record.arguments = $arguments", source)

    def test_native_fixture_shares_headless_selection_and_preserves_legacy_cli_exclusions(self):
        cases = native_fixture_argument_cases()
        common = ["--config", "C:/capture/space dir/config.ini", "--mod-directory", "C:/MIR/test mods", "--no-log-rotation"]
        for name in ("modern_gui", "legacy110_gui", "f110_process_gui"):
            with self.subTest(case=name):
                self.assertEqual([*common, "--disable-audio", "--benchmark", "owned-input.zip"], cases[name])
        for name in ("modern_headless", "legacy013_gui", "legacy014_gui", "legacy110_headless"):
            with self.subTest(case=name):
                self.assertEqual([*common, "--benchmark", "owned-input.zip"], cases[name])
        self.assertIn("headless_requested=[bool]$Headless", NATIVE_FIXTURE.read_text(encoding="utf-8"))

    def test_prototype_capture_refuses_declared_selected_inputs_before_output_or_admission(self):
        cases = prototype_capture_declared_input_guard_cases()

        for name in ("legacy", "partial", "valid"):
            with self.subTest(name=name):
                self.assertEqual(cases[name]["returncode"], 0, cases[name]["output"])
                self.assertFalse(cases[name]["output_exists"])
                self.assertFalse(cases[name]["controls_exist"])

        expected = {
            "wrong_version": "profile engine base differs",
            "wrong_engine_hash": "profile engine hash differs",
            "wrong_selected": "profile selected archive hash differs",
            "malformed_selected": "profile selected archive hash is malformed",
            "malformed_map": "profile archive metadata differs",
        }
        for name, message in expected.items():
            with self.subTest(name=name):
                self.assertNotEqual(cases[name]["returncode"], 0)
                self.assertIn(f"[mir5-prototype-capture] {message}", cases[name]["output"])
                self.assertFalse(cases[name]["output_exists"])
                self.assertFalse(cases[name]["controls_exist"])

        self.assertEqual(cases["call_removed"]["returncode"], 0, cases["call_removed"]["output"])
        self.assertFalse(cases["call_removed"]["output_exists"])
        self.assertFalse(cases["call_removed"]["controls_exist"])

    def test_prototype_capture_binds_only_hash_declared_file_settings_before_admission(self):
        cases = prototype_capture_file_settings_guard_cases()

        for name in ("valid", "defaults"):
            with self.subTest(name=name):
                self.assertEqual(cases[name]["returncode"], 0, cases[name]["output"])
                self.assertFalse(cases[name]["output_exists"])
                self.assertFalse(cases[name]["controls_exist"])

        expected = {
            "file_without_inputs": "File settings profile requires explicit SettingsPath and ExpectedSettingsSha256",
            "path_without_hash": "SettingsPath and ExpectedSettingsSha256 must be supplied together",
            "hash_without_path": "SettingsPath and ExpectedSettingsSha256 must be supplied together",
            "malformed_hash": "ExpectedSettingsSha256 requires a 64-character SHA-256",
            "default_profile": "File settings require profile settings_mode File",
            "profile_hash_mismatch": "File settings profile SHA-256 differs from expected input",
            "missing_profile_hash": "File settings profile requires a 64-character settings_sha256",
            "missing_file": "SettingsPath must name an existing regular file",
            "changed_file": "SettingsPath SHA-256 differs from expected input",
        }
        for name, message in expected.items():
            with self.subTest(name=name):
                self.assertNotEqual(cases[name]["returncode"], 0)
                self.assertIn(f"[mir5-prototype-capture] {message}", cases[name]["output"])
                self.assertFalse(cases[name]["output_exists"])
                self.assertFalse(cases[name]["controls_exist"])

        # The original Defaults-only entry point accepted this File profile
        # without a supplied file. Its acceptance is the counterfactual that
        # the real preflight above must reject.
        self.assertEqual(cases["old_file_without_inputs"]["returncode"], 0,
                         cases["old_file_without_inputs"]["output"])
        self.assertFalse(cases["old_file_without_inputs"]["output_exists"])
        self.assertFalse(cases["old_file_without_inputs"]["controls_exist"])

        linked = prototype_capture_linked_settings_case()
        self.assertFalse(linked["accepted"], linked)
        self.assertIn("[mir-library-reparse]", linked["message"])

        source = PROTOTYPE_CAPTURE.read_text(encoding="utf-8")
        self.assertIn(
            "$captureSettings = Get-MIR5PrototypeCaptureSettingsArguments "
            "-ProfileDefinition $profileDefinition -Path $SettingsPath "
            "-ExpectedSha256 $ExpectedSettingsSha256",
            source,
        )
        self.assertIn("SettingsMode=$captureSettings.SettingsMode", source)
        self.assertIn("$activationArguments.SettingsPath = $captureSettings.SettingsPath", source)
        self.assertIn("$activationArguments.SettingsSha256 = $captureSettings.SettingsSha256", source)
        self.assertIn("$activation = Start-MIRLibraryActivation @activationArguments", source)
        self.assertIn("settings=[ordered]@{mode=$captureSettings.SettingsMode", source)

    def test_native_fixture_active_seed_mode_is_finite_and_deferred(self):
        source = NATIVE_FIXTURE.read_text(encoding="utf-8")
        self.assertIn("[switch]$ActiveSeedOnly", source)
        self.assertIn(
            "[ValidateSet('','repair-stress','agriculture-scale')][string]$ActiveSeedKind=''",
            source,
        )
        self.assertIn("active seed requires a modern installed-MIR fixture run", source)
        self.assertIn("active seed must begin from its own fresh fixture save", source)
        self.assertIn("passed-private-native-active-seed-preparation", source)
        self.assertIn(
            "physical_work='deferred until the benchmark loads this exact active save'",
            source,
        )
        self.assertIn("$activeSaveComplete=${function:Test-HistoricalFixtureSaveComplete}", source)
        self.assertIn("fatal native active preparation diagnostic", source)

    def test_active_repair_forwards_create_to_its_closed_active_save_only(self):
        cases = native_fixture_active_create_target_cases()
        active = r"D:\owned-write-data\saves\mir5-native-active.zip"
        seed = r"D:\owned-write-data\saves\seed.zip"

        self.assertEqual(active, cases["repair_active"]["active_save"])
        self.assertEqual(active, cases["repair_active"]["seed"])
        self.assertEqual(["--create", active, "--map-gen-seed", "424242"], cases["repair_active"]["create"])

        for name in ("agriculture_active", "ordinary"):
            with self.subTest(name=name):
                self.assertEqual(seed, cases[name]["seed"])
                expected = ["--create", seed]
                if name == "agriculture_active":
                    expected += ["--map-gen-seed", "424242"]
                self.assertEqual(expected, cases[name]["create"])

    def test_native_fixture_active_marker_reader_rejects_wrong_or_ambiguous_markers(self):
        cases = native_fixture_active_marker_guard_cases()
        self.assertTrue(cases["positive"]["valid"])
        self.assertEqual(cases["positive"]["value"]["stage"], "prepared")
        for name in ("duplicate", "wrong_kind", "wrong_status", "unsupported_stage"):
            with self.subTest(name=name):
                self.assertFalse(cases[name]["valid"])
                self.assertIn("active", cases[name]["message"])

    def test_agriculture_active_completion_is_self_contained_across_governor_scope(self):
        cases = native_fixture_agriculture_completion_guard_cases()

        for name in ("no_log", "missing_marker", "duplicate_marker", "malformed_marker", "unclosed_save", "absent_save"):
            with self.subTest(name=name):
                self.assertTrue(cases[name]["valid"])
                self.assertFalse(cases[name]["result"])

        self.assertTrue(cases["valid"]["valid"])
        self.assertTrue(cases["valid"]["result"])
        self.assertFalse(cases["fatal"]["valid"])
        self.assertIn("fatal native active preparation diagnostic", cases["fatal"]["message"])

    def test_active_repair_selection_allows_candidate_fixture_v020_and_refuses_drift(self):
        cases = native_fixture_active_selection_guard_cases()
        self.assertTrue(cases["published"]["valid"])
        self.assertTrue(cases["candidate"]["valid"])
        self.assertTrue(cases["candidate501"]["valid"])
        for name in ("candidate_wrong_base", "candidate501_missing_selector", "candidate501_wrong_selector", "candidate501_wrong_base", "unknown_mir"):
            with self.subTest(name=name):
                self.assertFalse(cases[name]["valid"])
                self.assertIn("active", cases[name]["message"])

    def test_native_fixture_observer_binding_rejects_missing_unselected_and_unverified_inputs(self):
        cases = native_fixture_observer_guard_cases()

        self.assertTrue(cases["positive"]["valid"])
        self.assertEqual(
            cases["positive"]["value"],
            {
                "name": "mir-fixture-mir5-active-mods-observer",
                "version": "0.1.0",
                "source": "fixture-source",
                "archive": "fixture.zip",
                "sha256": "A" * 64,
            },
        )
        self.assertTrue(cases["blank"]["valid"])
        self.assertIsNone(cases["blank"]["value"])

        self.assertFalse(cases["missing"]["valid"])
        self.assertIn("must appear exactly once in the profile", cases["missing"]["message"])
        self.assertFalse(cases["unselected"]["valid"])
        self.assertIn("must be selected exactly once", cases["unselected"]["message"])
        self.assertFalse(cases["unverified"]["valid"])
        self.assertIn("must be a verified FixtureSources input", cases["unverified"]["message"])

    def test_native_health_calls_retain_dirty_checkpoint_without_branch_history_audit(self):
        scratch = ROOT / "build/tmp/native-health-control"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as temporary:
            repo = Path(temporary).resolve()
            self.assertTrue(repo.is_relative_to(scratch.resolve()))
            git = ["git", "-C", str(repo), "-c", "core.hooksPath=" + str(repo / "no-hooks"),
                   "-c", "commit.gpgsign=false", "-c", "user.name=MIR Fixture",
                   "-c", "user.email=fixture@example.invalid"]
            subprocess.run([*git, "init", "-q"], check=True, capture_output=True)
            (repo / "anchor.txt").write_text("checkpoint\n", encoding="utf-8")
            subprocess.run([*git, "add", "anchor.txt"], check=True, capture_output=True)
            subprocess.run([*git, "commit", "-qm", "initial"], check=True, capture_output=True)
            for name in ("extra-a", "extra-b", "extra-c", "extra-d", "extra-e"):
                subprocess.run([*git, "branch", name], check=True, capture_output=True)
            health = Path("tools/commands/workspace/Test-MIRDevelopmentHealth.ps1")
            (repo / health).parent.mkdir(parents=True)
            (repo / health).write_bytes((ROOT / health).read_bytes())
            sentinel = repo / "uncommitted.txt"
            sentinel.write_bytes(b"must remain untouched\n")
            for wrapper in (PROTOTYPE_CAPTURE, NATIVE_FIXTURE):
                command = r'''
                  $repo='__REPO__';$tokens=$null;$errors=$null
                  $ast=[System.Management.Automation.Language.Parser]::ParseFile('__WRAPPER__',[ref]$tokens,[ref]$errors)
                  if($errors.Count){throw 'Wrapper parse failed'}
                  $calls=@($ast.FindAll({param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.InvocationOperator -eq 'Ampersand' -and
                    $node.Extent.Text.Contains('Test-MIRDevelopmentHealth.ps1')
                  },$true))
                  if($calls.Count -ne 1){throw 'Expected one native health call'}
                  & ([scriptblock]::Create($calls[0].Extent.Text+' -AsJson'))
                '''.replace("__REPO__", str(repo).replace("'", "''")).replace(
                    "__WRAPPER__", str(wrapper).replace("'", "''"))
                result = subprocess.run(["pwsh", "-NoProfile", "-Command", command],
                                        cwd=repo, check=True, text=True, capture_output=True)
                report = json.loads(result.stdout.lstrip("\ufeff"))
                self.assertEqual(report["mode"], "hook", wrapper.name)
                self.assertTrue(report["checkpoint_required"], wrapper.name)
                self.assertGreater(report["git"]["dirty"]["count"], 0)
                self.assertLessEqual(report["scan_limits"]["max_worktrees"], 2)
                self.assertLessEqual(report["scan_limits"]["max_branches"], 4)
                self.assertTrue(report["git"]["branches"]["truncated"])
                self.assertTrue(all(row["unique_commit_count"] is None
                                    for row in report["git"]["branches"]["rows"]))
                self.assertEqual(sentinel.read_bytes(), b"must remain untouched\n")

    def test_capture_wrappers_remain_powershell_parseable(self):
        for script in (PROTOTYPE_CAPTURE, REPLAY_CAPTURE, MENU_COMPARISON, NATIVE_FIXTURE):
            assert_powershell_parses(script)

    def test_shared_contract_still_has_missing_and_unselected_observer_refusals(self):
        source = LIBRARY_ACTIVATION.read_text(encoding="utf-8")
        self.assertIn("[mir-library-loaded-observer] Observer is not selected.", source)
        self.assertIn(
            "[mir-library-loaded-observation] Expected one complete native mod table.",
            source,
        )
        self.assertIn("[mir-library-loaded-selection] Actual mod names/versions differ from the profile.", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(CaptureControlTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
