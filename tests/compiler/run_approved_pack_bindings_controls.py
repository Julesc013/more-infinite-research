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
    module_paths = [Path('source/prototypes/mir/capabilities/science_integration/pack_bindings.lua'),
                    Path('source/prototypes/mir/streams/registry.lua'), fixture.relative_to(repo)]
    print(json.dumps({'status': 'MIR-APPROVED-PACK-BINDINGS-PASSED', 'assertions': assertions,
                      'scope': 'controlled-approved-references-not-factory-acquisition-or-native-qualification',
                      'factorio_processes': 0, 'runtime': 'Lua 5.2',
                      'sources': {p.as_posix(): hashlib.sha256((repo / p).read_bytes()).hexdigest()
                                  for p in module_paths}}, sort_keys=True))


if __name__ == '__main__':
    main()
