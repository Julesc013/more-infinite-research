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

    def plain(value):
        if hasattr(value, 'items'):
            return {str(key): plain(item) for key, item in value.items()}
        if hasattr(value, '__len__') and not isinstance(value, (str, bytes, dict)):
            try:
                return [plain(value[index]) for index in range(1, len(value) + 1)]
            except Exception:
                pass
        return value

    def approved_family_preamble() -> str:
        text = (repo / 'tests/compiler/approved_family_emission.lua').read_text(encoding='utf-8')
        anchor = ("Context.with_active(Context.new({legacy_compiler_export_requested = false}), function()\n"
                  "  local context = Context.current()\n"
                  "  local effect_safety = require(\"prototypes.mir.emit.effect_safety\")")
        position = text.find(anchor)
        if position < 0:
            raise RuntimeError('approved-family active-only command preamble anchor changed')
        return text[:position]

    def command_export_source(shape: str) -> str:
        common = r'''
local commands = require("prototypes.mir.pipeline.commands")
local compiler_input = require("prototypes.mir.domain.compiler.compiler_input")
local function assert_generic_export(exported)
  assert(exported.schema == 4 and exported.state.compilation_snapshot
    and exported.state.qualification_snapshot and exported.state.compiler_input
    and exported.state.qualified_compiler_input,
    "requested Context export retains complete generic compiler state")
  local state_input = exported.state.compiler_input
  local plan_input = exported.state.compilation_plan and exported.state.compilation_plan.compiler_input
  assert(state_input and plan_input and not compiler_input.is_active(state_input)
    and not compiler_input.is_active(plan_input),
    "requested Context export contains no detached active CompilerInput handle")
  compiler_input.verify_untrusted(state_input)
  compiler_input.verify_untrusted(plan_input)
  assert(state_input.input_fingerprint == plan_input.input_fingerprint,
    "exported compilation plan binds its matching generic CompilerInput")
  local original = state_input.input_fingerprint
  plan_input.input_fingerprint = original .. "-outside-writer"
  assert(state_input.input_fingerprint == original,
    "returned Context snapshot keeps nested CompilerInput copies isolated")
  plan_input.input_fingerprint = original
  return {input_fingerprint = original,
    snapshot_fingerprint = exported.state.compilation_snapshot.snapshot_fingerprint,
    plan_input_fingerprint = plan_input.input_fingerprint}
end
'''
        if shape == 'run_all_default':
            body = r'''
local exported = commands.run_all()
local result = assert_generic_export(exported)
result.shape = "run_all_default"
return result
'''
        elif shape == 'run_all_active_only':
            body = r'''
local context = commands.run_all({return_snapshot = false})
assert(not context:legacy_compiler_export_requested(),
  "run_all(false) creates the explicit active-only data-stage Context")
local active = context:state_view("compiler_input")
assert(compiler_input.is_active(active), "active-only Context retains the owned active input")
local late_ok, late_error = pcall(function() return context:snapshot() end)
assert(not late_ok and string.find(tostring(late_error), "cannot export legacy snapshots"),
  "active-only Context refuses a late partial generic export")
return {shape = "run_all_active_only", input_fingerprint = active.input_fingerprint}
'''
        elif shape == 'manual_new_context':
            body = r'''
local context = commands.new_context()
assert(context:legacy_compiler_export_requested(),
  "manual new_context preserves the historical export-capable default")
for _, id in ipairs(commands.order()) do commands.run(id, context) end
local exported = context:snapshot()
local result = assert_generic_export(exported)
result.shape = "manual_new_context"
return result
'''
        else:
            raise ValueError(shape)
        return approved_family_preamble() + common + body

    def run_command_export(shape: str):
        runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
        runtime.globals().source_root = (repo / 'source').as_posix()
        runtime.globals().adapter_root = (repo / 'source/adapters/f200').as_posix()
        runtime.execute("package.path = adapter_root .. '/?.lua;' .. source_root .. '/?.lua;' .. package.path")
        return plain(runtime.execute(command_export_source(shape)))

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
    command_export_control = {
        shape: run_command_export(shape) for shape in (
            'run_all_default', 'run_all_active_only', 'manual_new_context')
    }
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
                      'command_export_control': command_export_control,
                      'sources': {p.as_posix(): hashlib.sha256((repo / p).read_bytes()).hexdigest()
                                  for p in module_paths}}, sort_keys=True))


if __name__ == '__main__':
    main()
