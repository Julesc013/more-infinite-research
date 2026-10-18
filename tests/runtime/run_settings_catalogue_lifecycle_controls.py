#!/usr/bin/env python3
"""Exercise the settings catalogue after Factorio control parsing has closed require()."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


SOURCES = (
    Path("source/prototypes/mir/settings/catalog.lua"),
    Path("source/prototypes/mir/settings/compiler_profile.lua"),
    Path("source/prototypes/mir/runtime/research_browser_mir_provider.lua"),
    Path("source/prototypes/mir/runtime/startup_settings.lua"),
)


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--lua-runtime-dir", required=True)
    parser.add_argument("--target", required=True, choices=("f200", "f210"))
    return parser.parse_args()


def lua_path(path: Path) -> str:
    return str(path.resolve()).replace("\\", "/").replace('"', '\\"')


def source_digest(repo: Path, target: str) -> str:
    digest = hashlib.sha256()
    for source in SOURCES + (Path(f"source/adapters/{target}/prototypes/mir/platform/factorio/target_profiles.lua"),):
        digest.update(source.as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update((repo / source).read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def prepare_runtime(repo: Path, target: str):
    from lupa import lua52

    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(
        'package.path = "'
        + lua_path(repo / "source" / "?.lua")
        + ";"
        + lua_path(repo / "source" / "adapters" / target / "?.lua")
        + ';" .. package.path'
    )
    runtime.execute(
        r'''
settings = {startup = {
  ["mir-compiler-profile"] = {value = "full"},
  ["mir-max-level-braking-force"] = {value = 3}
}}
prototypes = {mod_data = {}, mod_setting = {
  ["mir-max-level-braking-force"] = {
    mod = "more-infinite-research", setting_type = "startup", default_value = 3
  }
}}
local raw_require = require
parse_phase = true
require = function(name)
  if not parse_phase then error("[mir-settings-catalog-post-parse-require] " .. tostring(name), 2) end
  return raw_require(name)
end
package.preload["prototypes.mir.runtime.maximum_level_control"] = function()
  return {runtime_settings_bindings = function() return {
    ["runtime-settings-bridge-tech"] = {
      schema = 1, source = "generated-stream", policy_transport = "settings-derived-v3",
      binding = {
        technology_id = "runtime-settings-bridge-tech", declared_key = "bridge-stream",
        setting_name = "mir-max-level-braking-force"
      },
      selected_effective = 3, state = "finite"
    }
  } end}
end
package.preload["prototypes.mir.platform.factorio.browser_host"] = function()
  return {prototype_collections = function() return prototypes end}
end
'''
    )
    return runtime


def fixed_lifecycle(runtime):
    return runtime.execute(
        r'''
local catalogue = require("prototypes.mir.settings.catalog")
local compiler_profile = require("prototypes.mir.settings.compiler_profile")
local provider = require("prototypes.mir.runtime.research_browser_mir_provider")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local fingerprint = require("prototypes.mir.core.fingerprint")
local before = catalogue.all_specs()
local before_fingerprint = fingerprint.of(before)
assert(catalogue.spec("mir-compiler-profile").default_value == "full")
assert(compiler_profile.get(target_line.factorio_version) == "full")
parse_phase = false
local after = catalogue.all_specs()
local after_fingerprint = fingerprint.of(after)
assert(before_fingerprint == after_fingerprint, "catalogue specs changed after parser closure")
assert(catalogue.spec("mir-compiler-profile").default_value == "full")
assert(catalogue.default_value("mir-compiler-profile") == "full")
assert(catalogue.validate_value("mir-compiler-profile", "full") == false)
local snapshot = provider.snapshot({valid = true, technologies = {
  ["runtime-settings-bridge-tech"] = {valid = true}
}})
assert(snapshot.runtime_settings_bindings["runtime-settings-bridge-tech"] ~= nil,
  "provider runtime path did not reach the parser-safe catalogue")
return #after, before_fingerprint, after_fingerprint
'''
    )


def old_shape_must_fail(repo: Path, target: str) -> None:
    source = (repo / "source/prototypes/mir/settings/catalog.lua").read_text(encoding="utf-8")
    import_line = 'local compiler_profile = require("prototypes.mir.settings.compiler_profile")\n'
    eager_use = "    compiler_profile.prototype(),"
    if source.count(import_line) != 1 or source.count(eager_use) != 1:
        raise RuntimeError("settings catalogue no longer has the reviewed eager compiler-profile shape")
    old_source = source.replace(import_line, "", 1).replace(
        eager_use,
        '    require("prototypes.mir.settings.compiler_profile").prototype(),',
        1,
    )
    runtime = prepare_runtime(repo, target)
    runtime.globals().old_catalogue_source = old_source
    result = runtime.execute(
        r'''
package.preload["prototypes.mir.settings.catalog"] = function()
  return assert(load(old_catalogue_source, "old-settings-catalogue", "t", _ENV))()
end
local catalogue = require("prototypes.mir.settings.catalog")
parse_phase = false
local ok, message = pcall(catalogue.all_specs)
return ok, tostring(message)
'''
    )
    if result[0] or "[mir-settings-catalog-post-parse-require] prototypes.mir.settings.compiler_profile" not in result[1]:
        raise RuntimeError(f"the deliberately old lazy catalogue did not fail after parser closure: {result!r}")


def main() -> int:
    args = arguments()
    repo = Path(args.repo_root).resolve()
    runtime_dir = Path(args.lua_runtime_dir).resolve()
    if not runtime_dir.is_dir():
        raise RuntimeError(f"Lua 5.2 runtime is unavailable: {runtime_dir}")
    sys.path.insert(0, str(runtime_dir))
    result = fixed_lifecycle(prepare_runtime(repo, args.target))
    old_shape_must_fail(repo, args.target)
    record = {
        "status": "MIR-SETTINGS-CATALOGUE-LIFECYCLE-CONTROLS-PASSED",
        "target": args.target,
        "spec_count": int(result[0]),
        "spec_fingerprint": result[1],
        "source_sha256": source_digest(repo, args.target),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())