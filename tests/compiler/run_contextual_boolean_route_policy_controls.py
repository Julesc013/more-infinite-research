#!/usr/bin/env python3
"""Run the real Context Boolean-acquisition route-policy control.

This source-bound Lua 5.2 check starts no Factorio process and materializes no
package.  It loads the actual compiler modules and supplies only a compact
prototype registry for a concrete S/T/Y/P preferred-route case.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


PACK_MODULE = Path("source/prototypes/mir/capabilities/science_integration/pack_production_reachability.lua")
FIXTURE = Path("tests/compiler/contextual_boolean_route_policy.lua")
PACK_MODULE_NAME = "prototypes.mir.capabilities.science_integration.pack_production_reachability"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--lua-runtime-dir", required=True)
    parser.add_argument("--target", required=True, choices=("f200", "f210"))
    return parser.parse_args()


def escaped_lua_path(path: Path) -> str:
    return str(path.resolve()).replace("\\", "/").replace('"', '\\"')


def instrument_pack_module(source: str) -> str:
    """Expose exact private key helpers only inside this controlled Lua VM."""
    positive = "local function positive_witness_memo_key(identity, visiting_packs, visiting_technologies)\n"
    if source.count(positive) != 1:
        raise RuntimeError("Could not locate the positive research-unlock key helper")
    source = source.replace(
        positive,
        "local contextual_boolean_route_policy_positive_key_calls = 0\n"
        + positive
        + "  contextual_boolean_route_policy_positive_key_calls = "
        "contextual_boolean_route_policy_positive_key_calls + 1\n",
        1,
    )
    terminal = "\nreturn M\n"
    if source.count(terminal) != 1:
        raise RuntimeError("Could not locate the pack-production module return")
    hooks = r'''
M.__mir_contextual_boolean_route_policy_test_hooks = {
  positive_witness_memo_key = positive_witness_memo_key,
  negative_witness_memo_key = negative_witness_memo_key,
  research_unlocked_output_witness = research_unlocked_output_witness,
  positive_key_call_count = function()
    return contextual_boolean_route_policy_positive_key_calls
  end,
  reset_positive_key_call_count = function()
    contextual_boolean_route_policy_positive_key_calls = 0
  end
}
'''
    return source.replace(terminal, "\n" + hooks + "return M\n", 1)


def bootstrap(target: str) -> str:
    return rf'''
_G.log = function() end
_G.mods = {{base = true}}
_G.settings = {{startup = {{}}}}
_G.feature_flags = {{}}
_G.os = nil
-- Match Factorio's lualib/util.lua rather than relying on the product
-- fallback.  The fallback cannot preserve aliases, cycles, or metatables,
-- while the compiler's Context snapshots use all three properties.  Keep this
-- host fixture free of os/io/debug so it remains a data-stage shaped control.
function table.deepcopy(object)
  local lookup_table = {{}}
  local function _copy(value)
    if type(value) ~= "table" then
      return value
    elseif lookup_table[value] then
      return lookup_table[value]
    end
    local new_table = {{}}
    lookup_table[value] = new_table
    for index, value in pairs(value) do
      new_table[_copy(index)] = _copy(value)
    end
    return setmetatable(new_table, getmetatable(value))
  end
  return _copy(object)
end
_G.util = {{table = {{deepcopy = table.deepcopy}}}}
_G.util.copy = _G.util.table.deepcopy

local deepcopy_meta = {{marker = "fixture-deepcopy-meta"}}
local deepcopy_alias = setmetatable({{value = "alias"}}, deepcopy_meta)
local deepcopy_input = {{first = deepcopy_alias, second = deepcopy_alias}}
deepcopy_input.self = deepcopy_input
local deepcopy_copy = table.deepcopy(deepcopy_input)
if deepcopy_copy == deepcopy_input or deepcopy_copy.self ~= deepcopy_copy
  or deepcopy_copy.first == deepcopy_alias or deepcopy_copy.first ~= deepcopy_copy.second
  or getmetatable(deepcopy_copy.first) ~= deepcopy_meta then
  error("Fixture Factorio-compatible table.deepcopy contract failed")
end
_G.data = {{raw = {{
  item = {{
    seed = {{}},
    ["placement-kit"] = {{place_result = "fixture-lab"}},
    S = {{}}, T = {{}}, V = {{}}, Y = {{}}, P = {{}}
  }},
  tool = {{}}, module = {{}}, ammo = {{}}, capsule = {{}}, gun = {{}}, armor = {{}},
  ["repair-tool"] = {{}}, ["item-with-entity-data"] = {{}}, ["item-with-inventory"] = {{}},
  ["item-with-label"] = {{}}, ["item-with-tags"] = {{}}, ["selection-tool"] = {{}},
  ["copy-paste-tool"] = {{}}, blueprint = {{}}, ["blueprint-book"] = {{}},
  ["deconstruction-item"] = {{}}, ["upgrade-item"] = {{}}, ["spidertron-remote"] = {{}},
  ["rail-planner"] = {{}}, ["space-platform-starter-pack"] = {{}},
  fluid = {{}},
  lab = {{["fixture-lab"] = {{inputs = {{"V", "P"}}}}}},
  character = {{player = {{crafting_categories = {{"crafting"}}}}}},
  resource = {{
    ["seed-patch"] = {{minable = {{result = "seed", count = 1}}}},
    ["placement-patch"] = {{minable = {{result = "placement-kit", count = 1}}}}
  }},
  tree = {{}}, plant = {{}}, ["asteroid-chunk"] = {{}}, ["unit-spawner"] = {{}}, unit = {{}},
  turret = {{}}, ["assembling-machine"] = {{}}, ["rocket-silo"] = {{}},
  ["rocket-silo-rocket"] = {{}}, ["cargo-landing-pad"] = {{}}, tile = {{}},
  ["offshore-pump"] = {{}}, boiler = {{}}, surface = {{}}, ["space-location"] = {{}}, planet = {{}},
  recipe = {{
    ["r_s0"] = {{name = "r_s0", enabled = false, category = "crafting",
      ingredients = {{{{type = "item", name = "T", amount = 1}}}},
      results = {{{{type = "item", name = "S", amount = 1}}}}}},
    ["r_s1"] = {{name = "r_s1", enabled = false, category = "crafting",
      ingredients = {{{{type = "item", name = "seed", amount = 1}}}},
      results = {{{{type = "item", name = "S", amount = 1}}}}}},
    ["r_ta"] = {{name = "r_ta", enabled = false, category = "crafting",
      ingredients = {{{{type = "item", name = "S", amount = 1}}}},
      results = {{{{type = "item", name = "T", amount = 1}}}}}},
    ["r_tb"] = {{name = "r_tb", enabled = false, category = "crafting",
      ingredients = {{{{type = "item", name = "seed", amount = 1}}}},
      results = {{{{type = "item", name = "T", amount = 1}}}}}},
    ["r_v"] = {{name = "r_v", enabled = false, category = "crafting",
      ingredients = {{{{type = "item", name = "T", amount = 1}}}},
      results = {{{{type = "item", name = "V", amount = 1}}}}}},
    ["r_y"] = {{name = "r_y", enabled = false, category = "crafting",
      ingredients = {{{{type = "item", name = "S", amount = 1}}}},
      results = {{{{type = "item", name = "Y", amount = 1}}}}}},
    ["r_p"] = {{name = "r_p", enabled = false, category = "crafting",
      ingredients = {{{{type = "item", name = "Y", amount = 1}}, {{type = "item", name = "T", amount = 1}}}},
      results = {{{{type = "item", name = "P", amount = 1}}}}}}
  }},
  technology = {{
    S0 = {{name = "S0", enabled = true, research_trigger = {{type = "craft-item", item = "seed"}},
      effects = {{{{type = "unlock-recipe", recipe = "r_s0"}}}}}},
    S1 = {{name = "S1", enabled = true, research_trigger = {{type = "craft-item", item = "seed"}},
      effects = {{{{type = "unlock-recipe", recipe = "r_s1"}}}}}},
    TA = {{name = "TA", enabled = true, research_trigger = {{type = "craft-item", item = "seed"}},
      effects = {{{{type = "unlock-recipe", recipe = "r_ta"}}}}}},
    TB = {{name = "TB", enabled = true, research_trigger = {{type = "craft-item", item = "seed"}},
      effects = {{{{type = "unlock-recipe", recipe = "r_tb"}}}}}},
    V = {{name = "V", enabled = true, research_trigger = {{type = "craft-item", item = "seed"}},
      effects = {{{{type = "unlock-recipe", recipe = "r_v"}}}}}},
    Y0 = {{name = "Y0", enabled = true, research_trigger = {{type = "craft-item", item = "seed"}},
      effects = {{{{type = "unlock-recipe", recipe = "r_y"}}}}}},
    P0 = {{name = "P0", enabled = true, research_trigger = {{type = "craft-item", item = "seed"}},
      effects = {{{{type = "unlock-recipe", recipe = "r_p"}}}}}}
  }}
}}, extend = function() error("Fixture must not mutate prototypes") end}}
_G.MIR_TEST_TARGET = "{target}"
'''


def main() -> int:
    args = arguments()
    repo = Path(args.repo_root).resolve()
    runtime_dir = Path(args.lua_runtime_dir).resolve()
    if not runtime_dir.is_dir():
        raise RuntimeError(f"Lua runtime directory is unavailable: {runtime_dir}")
    sys.path.insert(0, str(runtime_dir))
    from lupa import lua52

    source = (repo / PACK_MODULE).read_text(encoding="utf-8")
    instrumented_source = instrument_pack_module(source)
    fixture = (repo / FIXTURE).read_text(encoding="utf-8")
    adapter_root = repo / "source" / "adapters" / args.target
    if not adapter_root.is_dir():
        raise RuntimeError(f"Missing target adapter: {adapter_root}")
    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(
        'package.path = "' + escaped_lua_path(repo / "source" / "?.lua") + ';'
        + escaped_lua_path(adapter_root / "?.lua") + ';" .. package.path'
    )
    runtime.execute(bootstrap(args.target))
    runtime.execute(
        "package.preload[" + json.dumps(PACK_MODULE_NAME) + "] = function()\n"
        "  local chunk, load_error = load(" + json.dumps(instrumented_source, ensure_ascii=False)
        + ", '@contextual-boolean-route-policy-pack-module')\n"
        "  if not chunk then error(load_error, 0) end\n"
        "  return chunk()\n"
        "end\n"
    )
    result = runtime.execute(fixture)
    record = {
        "status": "MIR-CONTEXTUAL-BOOLEAN-ROUTE-POLICY-CONTROLS-PASSED",
        "target": args.target,
        "assertions": int(result["assertions"]),
        "cold_available": bool(result["cold_available"]),
        "warm_available": bool(result["warm_available"]),
        "boolean_hits": int(result["boolean_hits"]),
        "r29_key_reuse": bool(result["r29_key_reuse"]),
        "r29_opaque_fallback": bool(result["r29_opaque_fallback"]),
        "r29_opaque_key_fallback": bool(result["r29_opaque_key_fallback"]),
        "r29_negative_hit": bool(result["r29_negative_hit"]),
        "source_sha256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture.encode("utf-8")).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    if (record["assertions"] < 14 or not record["cold_available"] or not record["warm_available"]
            or record["boolean_hits"] < 1 or not record["r29_key_reuse"]
            or not record["r29_opaque_fallback"] or not record["r29_opaque_key_fallback"]
            or not record["r29_negative_hit"]):
        raise RuntimeError(f"Unexpected Boolean route-policy result: {record}")
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
