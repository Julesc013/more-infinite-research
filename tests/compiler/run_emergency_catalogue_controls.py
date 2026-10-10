#!/usr/bin/env python3
"""Run the bounded emergency catalogue controls with a fresh Lua 5.2 VM.

This runner is deliberately a source-control check.  It neither locates mods
nor starts Factorio, so its receipt must not be used as native or save evidence.
"""

from __future__ import print_function

import argparse
import hashlib
import json
import re
import sys
import time
import traceback
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
DEFAULT_RECEIPT = Path("build/test-results/emergency-catalogue-controls.json")
CASES = {
    "lab-reachability-f210": ("f210", Path("tests/compiler/lab_reachability.lua")),
    "lab-reachability-f200": ("f200", Path("tests/compiler/lab_reachability.lua")),
    "finite-f210": ("f210", Path("tests/compiler/base_continuations_finite.lua")),
    "finite-f200": ("f200", Path("tests/compiler/base_continuations_finite.lua")),
    "secretas-biolab-f210": (
        "f210", Path("tests/compiler/secretas_biolab_researchability.lua"),
    ),
    "modern-upgrade-oracle-f210": (
        "f210", Path("tests/runtime/modern_catalogue_upgrade_controls.lua"),
    ),
    "secretas-native-oracle": (
        "f210", Path("tests/runtime/secretas_finite_native_fixture_controls.lua"),
    ),
}
PASS = re.compile(r"^MIR-[A-Z0-9-]+-PASS\s+(\d+)\s*$")
MAX_OUTPUT_LINES = 12
MAX_OUTPUT_LINE_CHARS = 512
MAX_FAILURE_CHARS = 1400


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative_to_repo(path):
    return path.resolve().relative_to(REPO).as_posix()


def in_repo(path, description):
    candidate = path if path.is_absolute() else REPO / path
    candidate = candidate.resolve()
    try:
        candidate.relative_to(REPO)
    except ValueError:
        raise ValueError("%s must be inside the checkout: %s" % (description, candidate))
    return candidate


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--lua-runtime-dir",
        type=Path,
        help="Directory containing an already-installed Lua 5.2 Lupa package.",
    )
    parser.add_argument(
        "--receipt",
        type=Path,
        default=DEFAULT_RECEIPT,
        help="Checkout-relative JSON receipt path (default: %(default)s).",
    )
    parser.add_argument(
        "--case",
        choices=sorted(CASES),
        action="append",
        dest="cases",
        help="Run only this named control; repeat to select several.",
    )
    return parser.parse_args(argv)


def write_receipt(path, receipt):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def install_module_tracker(runtime, target):
    """Record source files resolved by the adapter-then-shared package path."""
    runtime.globals().SOURCE_ROOT = (REPO / "source").as_posix()
    runtime.globals().REPO_ROOT = REPO.as_posix()
    runtime.execute(
        'package.path = SOURCE_ROOT .. "/adapters/%s/?.lua;" .. '
        'SOURCE_ROOT .. "/?.lua;" .. package.path' % target
    )
    runtime.execute(
        r'''
local mir_original_require = require
local mir_source_root = tostring(SOURCE_ROOT):gsub("\\", "/")
__mir_project_modules = {}
__mir_project_module_seen = {}
local function mir_record_module(name)
  local resolved = package.searchpath and package.searchpath(name, package.path) or nil
  if resolved then
    resolved = tostring(resolved):gsub("\\", "/")
    local prefix = mir_source_root .. "/"
    if resolved:sub(1, #prefix) == prefix then
      local relative = resolved:sub(#prefix + 1)
      if not __mir_project_module_seen[relative] then
        __mir_project_module_seen[relative] = true
        table.insert(__mir_project_modules, relative)
      end
    end
  end
end
function require(name)
  local already_loaded = package.loaded[name] ~= nil
  local result, resolved_from = mir_original_require(name)
  if not already_loaded then mir_record_module(name) end
  return result, resolved_from
end
function __mir_sorted_project_modules()
  table.sort(__mir_project_modules)
  return table.concat(__mir_project_modules, "\n")
end
'''
    )


def collect_output(runtime):
    all_lines = []

    def receipt_print(*values):
        line = "\t".join(str(value) for value in values)
        all_lines.append(line[:MAX_OUTPUT_LINE_CHARS])

    runtime.globals().__mir_receipt_print = receipt_print
    runtime.execute("print = function(...) return __mir_receipt_print(...) end")
    return all_lines


def project_inputs(runtime, test_path):
    loaded = runtime.globals().__mir_sorted_project_modules()
    modules = [line for line in str(loaded).splitlines() if line]
    hashes = {
        relative_to_repo(Path(__file__)): sha256(Path(__file__)),
        relative_to_repo(test_path): sha256(test_path),
    }
    if test_path.name == "modern_catalogue_upgrade_controls.lua":
        fixture = REPO / "fixtures/assert-upgrade-4-0-21000-to-4-1-21000/control.lua"
        hashes[relative_to_repo(fixture)] = sha256(fixture)
    if test_path.name == "secretas_finite_native_fixture_controls.lua":
        fixture = REPO / "fixtures/assert-secretas-finite-continuation-hotfix/control.lua"
        hashes[relative_to_repo(fixture)] = sha256(fixture)
    for module in modules:
        source = (REPO / "source" / module).resolve()
        if not source.is_file():
            raise RuntimeError("tracked source module is no longer a file: source/%s" % module)
        hashes[relative_to_repo(source)] = sha256(source)
    return modules, hashes


def execute_case(lua_runtime, name, target, relative_test):
    test_path = in_repo(relative_test, "test input")
    started = time.monotonic()
    runtime = lua_runtime(register_eval=False, register_builtins=False, max_memory=48 * 1024 * 1024)
    output = collect_output(runtime)
    install_module_tracker(runtime, target)
    status = "failed"
    failure = None
    try:
        if test_path.name == "secretas_finite_native_fixture_controls.lua":
            fixture = REPO / "fixtures/assert-secretas-finite-continuation-hotfix/control.lua"
            runtime.globals().MIR_SECRETAS_FINITE_CONTROL_SOURCE = fixture.read_text(encoding="utf-8-sig")
        runtime.execute(test_path.read_text(encoding="utf-8-sig"))
        markers = [PASS.match(line) for line in output]
        markers = [marker for marker in markers if marker]
        if not markers:
            raise AssertionError("control did not emit a MIR-*-PASS assertion marker")
        status = "passed"
        assertions = sum(int(marker.group(1)) for marker in markers)
    except BaseException as error:  # Preserve a receipt for every selected control.
        assertions = 0
        failure = ("%s: %s" % (type(error).__name__, error))[:MAX_FAILURE_CHARS]
    try:
        modules, inputs = project_inputs(runtime, test_path)
    except BaseException as error:
        modules, inputs = [], {
            relative_to_repo(Path(__file__)): sha256(Path(__file__)),
            relative_to_repo(test_path): sha256(test_path),
        }
        status = "failed"
        assertions = 0
        failure = ("%s: %s" % (type(error).__name__, error))[:MAX_FAILURE_CHARS]
    result = {
        "assertion_count": assertions,
        "duration_ms": int((time.monotonic() - started) * 1000),
        "id": name,
        "input_sha256": inputs,
        "lua_version": str(runtime.eval("_VERSION")),
        "loaded_project_modules": ["source/" + module for module in modules],
        "observed_count": sum(line.startswith("OBSERVED\t") for line in output),
        "output_tail": output[-MAX_OUTPUT_LINES:],
        "status": status,
        "target": target,
        "test": relative_to_repo(test_path),
    }
    if failure:
        result["failure"] = failure
    return result


def main(argv):
    args = parse_args(argv)
    receipt_path = in_repo(args.receipt, "receipt")
    requested = args.cases or [
        "lab-reachability-f210",
        "lab-reachability-f200",
        "finite-f210",
        "finite-f200",
        "secretas-biolab-f210",
        "modern-upgrade-oracle-f210",
    ]
    receipt = {
        "contract": "controlled source checks only; not native Factorio, package, or save evidence",
        "controls": [],
        "lupa": {},
        "schema": 1,
    }
    try:
        if args.lua_runtime_dir:
            runtime_dir = args.lua_runtime_dir.resolve()
            if not runtime_dir.is_dir():
                raise ValueError("--lua-runtime-dir is not a directory: %s" % runtime_dir)
            sys.path.insert(0, str(runtime_dir))
            runtime_source = "explicit --lua-runtime-dir"
        else:
            runtime_source = "normal Python import"
        import lupa
        from lupa import lua52
        lua_runtime = lua52.LuaRuntime
        module_path = Path(lua52.__file__).resolve()
        receipt["lupa"] = {
            "lua52_module": module_path.name,
            "lua52_module_sha256": sha256(module_path),
            "runtime_source": runtime_source,
            "version": getattr(lupa, "__version__", "unknown"),
        }
        for name in requested:
            target, test = CASES[name]
            result = execute_case(lua_runtime, name, target, test)
            receipt["controls"].append(result)
            print("%s %s assertions=%s" % (result["status"].upper(), name, result["assertion_count"]))
        versions = {item["lua_version"] for item in receipt["controls"]}
        receipt["lupa"]["lua_versions"] = sorted(versions)
    except BaseException as error:
        receipt["runner_error"] = ("%s: %s" % (type(error).__name__, error))[:MAX_FAILURE_CHARS]
        traceback.print_exc()
    write_receipt(receipt_path, receipt)
    print("receipt %s" % relative_to_repo(receipt_path))
    return 0 if receipt.get("controls") and all(item["status"] == "passed" for item in receipt["controls"]) and "runner_error" not in receipt else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
