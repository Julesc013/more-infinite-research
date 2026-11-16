"""Offline window/byte/custody opponents; these controls never open X."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock
import zlib


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/lib/validation'))
import LinuxLibraryWindow as WINDOW


def module(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


INPUT = module('mir_linux_capture_test_input', 'tools/Invoke-LibraryNativeInputLinux.py')
CLI = ROOT / 'tools/Invoke-LibraryLinuxCapture.py'
HELPER_SHA = hashlib.sha256((ROOT / 'tools/Invoke-LibraryNativeInputLinux.py').read_bytes()).hexdigest().upper()
WINDOW_SHA = hashlib.sha256((ROOT / 'tools/lib/validation/LinuxLibraryWindow.py').read_bytes()).hexdigest().upper()


def requests():
    spec = {'schema': 1, 'kind': 'MIRLinuxLibraryCapturePlanV1', 'role': 'client-en', 'process_id': 42,
            'process_start_utc': '2026-11-17T00:00:00.000000Z', 'engine_sha256': 'A' * 64,
            'client_width': 1280, 'client_height': 720, 'workspace': '/owned/checkout',
            'output_root': '/owned/checkout/build/p/case/captures', 'name': 'help-en',
            'xwd': {'path': '/usr/bin/xwd', 'bytes': 1234, 'sha256': 'B' * 64}}
    binding = {'schema': 1, 'kind': 'MIRLinuxLibraryInputBindingV1', 'role': 'client-en', 'process_id': 42,
               'session_id': 41, 'start_ticks': 101, 'engine_path': '/owned/engine/bin/x64/factorio',
               'display': ':193', 'xauthority': '/owned/checkout/build/p/case/en/authority',
               'window': 123, 'bounds': [0, 0, 1280, 720]}
    return spec, binding


def xwd(visual=4):
    fields = [100, 7, 2, 24, 1280, 720, 0, 0, 32, 0, 32, 32, 5120, visual,
              0xFF0000, 0xFF00, 0xFF, 8, 256, 256 if visual == 5 else 0, 1280, 720, 0, 0, 0]
    colors = b''.join(struct.pack('>IHHHBB', i * 0x010101, i * 257, i * 257, i * 257, 7, 0)
                      for i in range(256)) if visual == 5 else b''
    return struct.pack('>25I', *fields) + colors + b'\x03\x02\x01\x00' * (1280 * 720)


class CaptureControls(unittest.TestCase):
    def test_finite_capture_schema_and_role_mapping(self):
        spec, binding = requests()
        self.assertIs(WINDOW.validate_spec(spec, binding, INPUT), spec)
        spec['role'] = binding['role'] = 'client-de'
        binding['display'] = ':194'
        WINDOW.validate_spec(spec, binding, INPUT)
        for change in [lambda s, b: s.update(command='anything'),
                       lambda s, b: s.update(name='../foreign'),
                       lambda s, b: s.update(output_root='/outside/capture'),
                       lambda s, b: s.update(output_root='/owned/checkout/build/p'),
                       lambda s, b: s.update(client_width=True),
                       lambda s, b: s.update(xwd={'path': '/bin/sh', 'bytes': 1, 'sha256': 'B' * 64}),
                       lambda s, b: b.update(display=':193'),
                       lambda s, b: b.update(process_id=43)]:
            with self.subTest(change=change):
                bad_spec, bad_binding = copy.deepcopy(spec), copy.deepcopy(binding)
                change(bad_spec, bad_binding)
                with self.assertRaises(ValueError): WINDOW.validate_spec(bad_spec, bad_binding, INPUT)

    def test_schema_only_is_offline_and_hash_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            for name, value in zip(('spec', 'binding'), requests()):
                path = Path(directory) / (name + '.json')
                path.write_text(json.dumps(value), encoding='utf-8')
                paths.append((path, hashlib.sha256(path.read_bytes()).hexdigest().upper()))
            command = [sys.executable, '-B', str(CLI), '--spec-path', str(paths[0][0]), '--spec-sha256', paths[0][1],
                       '--binding-path', str(paths[1][0]), '--binding-sha256', paths[1][1],
                       '--input-helper-sha256', HELPER_SHA, '--window-helper-sha256', WINDOW_SHA, '--validate-only']
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            row = json.loads(result.stdout)
            self.assertEqual(row['status'], 'validated-schema-only')
            self.assertFalse(row['process_identity_checked'])
            self.assertFalse(row['native_gui_acceptance'])
            paths[0][0].write_bytes(paths[0][0].read_bytes() + b' ')
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(json.loads(result.stdout)['status'], 'refused')
            self.assertEqual(sorted(p.name for p in Path(directory).iterdir()), ['binding.json', 'spec.json'])

    def test_cli_refuses_unverified_helper_before_evaluating_its_code(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'lib/validation').mkdir(parents=True)
            (root / 'capture.py').write_bytes(CLI.read_bytes())
            (root / 'Invoke-LibraryNativeInputLinux.py').write_bytes(
                (ROOT / 'tools/Invoke-LibraryNativeInputLinux.py').read_bytes())
            sentinel = root / 'must-not-execute'
            (root / 'lib/validation/LinuxLibraryWindow.py').write_text(
                'from pathlib import Path\nPath(' + repr(str(sentinel)) + ').write_text("executed")\n', encoding='utf-8')
            paths = []
            for name, value in zip(('spec', 'binding'), requests()):
                path = root / (name + '.json'); path.write_text(json.dumps(value), encoding='utf-8')
                paths.append((str(path), hashlib.sha256(path.read_bytes()).hexdigest().upper()))
            result = subprocess.run([sys.executable, '-B', str(root / 'capture.py'),
                '--spec-path', paths[0][0], '--spec-sha256', paths[0][1], '--binding-path', paths[1][0],
                '--binding-sha256', paths[1][1], '--input-helper-sha256', HELPER_SHA,
                '--window-helper-sha256', WINDOW_SHA, '--validate-only'], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(json.loads(result.stdout)['status'], 'refused')
            self.assertFalse(sentinel.exists())

    def test_decoder_preserves_literal_rgb_and_rejects_nonidentity_maps(self):
        for visual in (4, 5):
            with self.subTest(visual=visual):
                png = WINDOW.xwd_to_png(xwd(visual), [0, 0, 1280, 720])
                self.assertEqual(png[:8], b'\x89PNG\r\n\x1a\n')
                offset, compressed, chunks = 8, b'', []
                while offset < len(png):
                    count = struct.unpack('>I', png[offset:offset + 4])[0]
                    kind = png[offset + 4:offset + 8]
                    body = png[offset + 8:offset + 8 + count]
                    self.assertEqual(zlib.crc32(kind + body) & 0xFFFFFFFF,
                                     struct.unpack('>I', png[offset + 8 + count:offset + 12 + count])[0])
                    if kind == b'IDAT': compressed += body
                    chunks.append(kind)
                    offset += count + 12
                self.assertEqual(chunks, [b'IHDR', b'IDAT', b'IEND'])
                self.assertEqual(zlib.decompress(compressed), (b'\x00' + b'\x01\x02\x03' * 1280) * 720)
        raw = xwd(5)
        for bad in [raw[:-1], raw + b'x', raw[:104] + b'\x00\x01' + raw[106:],
                    raw[:100 + 12] + raw[100:112] + raw[124:]]:
            with self.subTest(length=len(bad)), self.assertRaises(ValueError):
                WINDOW.xwd_to_png(bad, [0, 0, 1280, 720])
        with self.assertRaises(ValueError): WINDOW.xwd_to_png(raw, [0, 0, 800, 600])

    def run_capture(self, directory, *, bad_window=False, bad_image=False, run_status=None,
                    guard_failure_at=None, close_failure=False):
        spec, binding = requests()
        paths = {name: Path(directory) / ('capture' + suffix)
                 for name, suffix in [('xwd', '.xwd'), ('stderr', '.stderr'), ('png', '.png')]}
        calls = []
        def guard():
            calls.append('guard')
            if calls.count('guard') == guard_failure_at: raise ValueError('owned lifetime changed')
        class Backend:
            def window(self, actual_binding, actual_spec):
                calls.append('window')
                return {'pid': 99 if bad_window else 42, 'bounds': [0, 0, 1280, 720],
                        'mapped': True, 'title': 'Factorio 2.1.24'}
            def close(self):
                calls.append('close')
                if close_failure: raise ValueError('close failed')
            def focus(self, *args): raise AssertionError('capture must never focus')
            def key(self, *args): raise AssertionError('capture must never inject input')
            def motion(self, *args): raise AssertionError('capture must never inject input')
            def button(self, *args): raise AssertionError('capture must never inject input')
        def run(command, env, actual_paths):
            calls.append('xwd')
            self.assertEqual(command, ['/usr/bin/xwd', '-display', ':193', '-id', '0x7b'])
            self.assertEqual(env['XAUTHORITY'], binding['xauthority'])
            with actual_paths['xwd'].open('xb') as stream: stream.write(b'bad' if bad_image else xwd())
            with actual_paths['stderr'].open('xb') as stream: stream.write(b'')
            return run_status or {'exit_code': 0, 'timed_out': False, 'output_limited': False}
        helper = types.SimpleNamespace(utc=INPUT.utc, validate_binding=INPUT.validate_binding,
                                       process_guard=lambda s, b: (guard, lambda: calls.append('final-hash')),
                                       LinuxX11=lambda b: Backend())
        receipt = WINDOW.capture(spec, binding, helper, pause=lambda seconds: calls.append(('wait', seconds)),
                                 runner=run, path_check=lambda s: paths)
        return receipt, calls, paths

    def test_capture_never_focuses_or_injects_and_binds_before_after(self):
        with tempfile.TemporaryDirectory() as directory:
            row, calls, paths = self.run_capture(directory)
            self.assertEqual(row['status'], 'captured-pending-phase-and-visual-review')
            self.assertFalse(row['native_gui_acceptance'])
            self.assertEqual((row['focus_changes'], row['input_events']), (0, 0))
            self.assertIn(('wait', 1.0), calls)
            self.assertEqual(calls.count('guard'), 4)
            self.assertLess(calls.index(('wait', 1.0)), calls.index('xwd'))
            self.assertEqual(calls[-2:], ['final-hash', 'close'])
            self.assertEqual(row['png']['sha256'], hashlib.sha256(paths['png'].read_bytes()).hexdigest().upper())

    def test_wrong_window_refuses_before_capture_and_retains_raw_on_late_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            row, calls, paths = self.run_capture(directory, bad_window=True)
            self.assertEqual(row['status'], 'refused')
            self.assertNotIn('xwd', calls)
            self.assertFalse(any(p.exists() for p in paths.values()))
        for options in [{'bad_image': True}, {'guard_failure_at': 3}, {'close_failure': True},
                        {'run_status': {'exit_code': 1, 'timed_out': False, 'output_limited': False}},
                        {'run_status': {'exit_code': -9, 'timed_out': True, 'output_limited': False}}]:
            with self.subTest(options=options), tempfile.TemporaryDirectory() as directory:
                row, calls, paths = self.run_capture(directory, **options)
                self.assertEqual(row['status'], 'refused')
                self.assertIn('raw', row)
                self.assertTrue(paths['xwd'].is_file())
                self.assertEqual(calls[-1], 'close')

    def test_output_collision_is_preserved_before_any_backend_or_xwd(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'capture.png'
            path.write_bytes(b'protected')
            spec, binding = requests()
            helper = types.SimpleNamespace(utc=INPUT.utc, validate_binding=INPUT.validate_binding,
                                           process_guard=mock.Mock(side_effect=AssertionError('no guard may begin')))
            row = WINDOW.capture(spec, binding, helper,
                                 path_check=mock.Mock(side_effect=ValueError('existing capture outputs')))
            self.assertEqual(row['status'], 'refused')
            helper.process_guard.assert_not_called()
            self.assertEqual(path.read_bytes(), b'protected')

    def test_live_path_primitives_rehash_tools_and_preserve_existing_files(self):
        # Filesystem-only check on the host; no native/X operation is reached.
        with tempfile.TemporaryDirectory() as directory:
            # The host's temporary directory can itself be a Windows junction
            # or short-name alias. Build a valid canonical fixture; production
            # must continue refusing caller-supplied aliased capture paths.
            workspace = Path(directory).resolve(strict=True) / 'checkout'; workspace.mkdir()
            root = workspace / 'build/p/captures'; root.mkdir(parents=True)
            tool = workspace / 'xwd'; tool.write_bytes(b'pinned-tool')
            spec, _ = requests()
            spec.update(workspace=str(workspace), output_root=str(root),
                        xwd={'path': str(tool), 'bytes': tool.stat().st_size,
                             'sha256': hashlib.sha256(tool.read_bytes()).hexdigest().upper()})
            with mock.patch.object(WINDOW.sys, 'platform', 'linux'), \
                    mock.patch.object(WINDOW.os, 'getuid', return_value=root.stat().st_uid, create=True):
                paths = WINDOW.validate_live_paths(spec)
                paths['png'].write_bytes(b'protected-image')
                with self.assertRaisesRegex(ValueError, 'preserve existing'):
                    WINDOW.validate_live_paths(spec)
                self.assertEqual(paths['png'].read_bytes(), b'protected-image')
                tool.write_bytes(b'changed-tool')
                with self.assertRaisesRegex(ValueError, 'executable bytes differ'):
                    WINDOW.validate_live_paths(spec)

    def test_xwd_supervision_retains_separate_bounded_prefixes(self):
        class Pipe:
            def __init__(self, descriptor): self.descriptor, self.closed = descriptor, False
            def fileno(self): return self.descriptor
            def close(self): self.closed = True
        class Child:
            def __init__(self): self.stdout, self.stderr, self.returncode, self.kills = Pipe(10), Pipe(11), None, 0
            def poll(self): return self.returncode
            def kill(self): self.kills += 1; self.returncode = -9
            def wait(self, timeout):
                if self.returncode is None: self.returncode = 0
                return self.returncode
        for limited in (False, True):
            with self.subTest(limited=limited), tempfile.TemporaryDirectory() as directory:
                paths = {'xwd': Path(directory) / 'raw', 'stderr': Path(directory) / 'stderr'}
                child = Child()
                data = {10: b'abcdef', 11: b'warning'}
                def read(descriptor, count):
                    chunk = data[descriptor][:count]; data[descriptor] = data[descriptor][count:]
                    return chunk
                with mock.patch.object(WINDOW.subprocess, 'Popen', return_value=child) as start, \
                        mock.patch.object(WINDOW.select, 'select', side_effect=lambda fds, *args: (fds, [], [])), \
                        mock.patch.object(WINDOW.os, 'read', side_effect=read), \
                        mock.patch.object(WINDOW, 'XWD_LIMIT_BYTES', 4 if limited else 20):
                    result = WINDOW.run_xwd(['pinned-xwd', '-id', '0x7b'], {'DISPLAY': ':193'}, paths)
                self.assertEqual(start.call_args.args[0], ['pinned-xwd', '-id', '0x7b'])
                self.assertEqual(result['output_limited'], limited)
                self.assertFalse(result['timed_out'])
                self.assertEqual(paths['xwd'].read_bytes(), b'abcde' if limited else b'abcdef')
                self.assertEqual(paths['stderr'].read_bytes(), b'' if limited else b'warning')
                self.assertEqual(child.kills, 1 if limited else 0)
                self.assertTrue(child.stdout.closed and child.stderr.closed)
        with tempfile.TemporaryDirectory() as directory:
            paths = {'xwd': Path(directory) / 'raw', 'stderr': Path(directory) / 'stderr'}
            child = Child()
            with mock.patch.object(WINDOW.subprocess, 'Popen', return_value=child), \
                    mock.patch.object(WINDOW.time, 'monotonic', side_effect=[100, 109]), \
                    mock.patch.object(WINDOW.select, 'select') as read_ready:
                result = WINDOW.run_xwd(['pinned-xwd'], {}, paths)
            self.assertTrue(result['timed_out'])
            self.assertEqual(child.kills, 1)
            read_ready.assert_not_called()
            self.assertEqual(paths['xwd'].read_bytes(), b'')
            self.assertEqual(paths['stderr'].read_bytes(), b'')


if __name__ == '__main__':
    unittest.main()
