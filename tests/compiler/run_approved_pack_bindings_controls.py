"""Execute approved pack-reference bindings; no Factorio or production claims."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo-root', required=True)
    parser.add_argument('--lua-runtime-dir', required=True)
    args = parser.parse_args()
    repo = Path(args.repo_root).resolve()
    sys.path.insert(0, str(Path(args.lua_runtime_dir).resolve()))
    from lupa import lua52

    lua = lua52.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().repo_source = (repo / 'source').as_posix()
    lua.execute('''
      package.path = repo_source .. '/?.lua;' .. package.path
      data = {raw = {}, extend = function() error('No test mutation admission') end}
      mods = {base = '2.0.77'}
      log = function() end
      package.loaded['prototypes.mir.platform.factorio.target_profiles'] = {
        current_factorio_version = '2.0',
        current = function() return {prototype_shapes = {}} end
      }
      package.loaded['prototypes.mir.domain.streams.descriptor'] = {normalize = function(_, value) return value end}
      package.loaded['prototypes.mir.platform.factorio.target_line'] = {stream_supported = function() return true end}
      package.loaded['prototypes.streams.init'] = {research_iron = {items = {'iron-plate'}}}
      package.loaded['prototypes.mir.compatibility.profiles'] = {apply = function() end}
      for _, name in ipairs({'pack_production_reachability', 'recipe_route_feasibility',
                            'production_route_policy', 'technology_researchability'}) do
        package.preload['prototypes.mir.capabilities.science_integration.' .. name] = function()
          error('Prohibited former discovery module: ' .. name)
        end
      end
    ''')
    fixture = repo / 'tests/compiler/approved_pack_bindings.lua'
    assertions = lua.execute(fixture.read_text(encoding='utf-8'))
    # Separate runtime: actual F200 adapters/catalogue/planner/common emitter;
    # none of the facade fixture's module substitutions apply here.
    emitted = lua52.LuaRuntime(unpack_returned_tuples=True)
    emitted.globals().source_root = (repo / 'source').as_posix()
    emitted.globals().adapter_root = (repo / 'source/adapters/f200').as_posix()
    emitted.execute("package.path = adapter_root .. '/?.lua;' .. source_root .. '/?.lua;' .. package.path")
    emission_fixture = repo / 'tests/compiler/approved_family_emission.lua'
    emission = emitted.execute(emission_fixture.read_text(encoding='utf-8'))
    # Exercise the complete actual catalogue/planner/emitter path in a fresh
    # runtime with no host os table; the
    # fixture checks unavailable timing instead of inventing a zero duration.
    clockless = lua52.LuaRuntime(unpack_returned_tuples=True)
    clockless.globals().source_root = (repo / 'source').as_posix()
    clockless.globals().adapter_root = (repo / 'source/adapters/f200').as_posix()
    clockless.execute("package.path = adapter_root .. '/?.lua;' .. source_root .. '/?.lua;' .. package.path; os = nil")
    clockless_emission = clockless.execute(emission_fixture.read_text(encoding='utf-8'))
    assert int(clockless_emission['assertions']) == int(emission['assertions']) + 2
    assert int(clockless_emission['rows']) == int(emission['rows'])
    assert int(clockless_emission['operations']) == int(emission['operations'])
    stubbed_modules = {'prototypes.mir.platform.factorio.target_profiles',
                       'prototypes.mir.domain.streams.descriptor',
                       'prototypes.mir.platform.factorio.target_line',
                       'prototypes.streams.init', 'prototypes.mir.compatibility.profiles'}
    module_paths = [fixture.relative_to(repo), emission_fixture.relative_to(repo), Path(__file__).resolve().relative_to(repo)]
    for name, _ in lua.globals().package.loaded.items():
        if str(name).startswith('prototypes.') and name not in stubbed_modules:
            path = Path('source') / (str(name).replace('.', '/') + '.lua')
            if (repo / path).is_file():
                module_paths.append(path)
    for name, _ in emitted.globals().package.loaded.items():
        if str(name).startswith('prototypes.'):
            relative = Path(str(name).replace('.', '/') + '.lua')
            for root in (Path('source/adapters/f200'), Path('source')):
                if (repo / root / relative).is_file():
                    module_paths.append(root / relative)
                    break
    print(json.dumps({'status': 'MIR-APPROVED-PACK-BINDINGS-PASSED', 'assertions': assertions,
                      'scope': 'controlled-approved-reference-graph-and-facade-not-native-qualification',
                      'factorio_processes': 0, 'runtime': 'Lua 5.2',
                      'stubbed_module_boundaries': sorted(stubbed_modules),
                      'emission_control': {'assertions': int(emission['assertions']),
                                           'catalogue_rows': int(emission['rows']),
                                           'operations': int(emission['operations']),
                                           'stubbed_module_boundaries': [], 'target': 'f200'},
                      'clockless_emission_control': {'assertions': int(clockless_emission['assertions']),
                                                    'catalogue_rows': int(clockless_emission['rows']),
                                                    'operations': int(clockless_emission['operations']),
                                                    'stubbed_module_boundaries': [], 'target': 'f200'},
                      'sources': {p.as_posix(): hashlib.sha256((repo / p).read_bytes()).hexdigest()
                                  for p in module_paths}}, sort_keys=True))


if __name__ == '__main__':
    main()
