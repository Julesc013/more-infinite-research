"""One hash-bound input action on an owned private-X Factorio client.

This leaf does not launch/stop a process, select mods, read a save, or grant a
gameplay verdict. The existing native protocol's parent owns those decisions.
Legacy ASCII plans match Invoke-LibraryNativeInput.ps1. The Linux-only input
kinds add one fixed Ctrl+A/Backspace gesture or one vertical wheel step.
Unicode is a separate, unqualified boundary. Validate-only never opens X or
inspects a live process.
"""
import argparse
import ctypes as C
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import time


WHEEL_BUTTONS = {'up': 4, 'down': 5}


class InputError(ValueError):
    def __init__(self, message, trace=None):
        super().__init__(message)
        self.trace = trace if trace is not None else []


def require(condition, message):
    if not condition:
        raise InputError(message)


def integer(value, low=1, high=2**31 - 1):
    return type(value) is int and low <= value <= high


def utc(value):
    require(isinstance(value, str) and re.fullmatch(
        r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,7})?Z', value),
        'start time differs')
    try:
        parsed = datetime.fromisoformat(value[:-1] + '+00:00')
    except ValueError as error:
        raise InputError('start time differs') from error
    return parsed.timestamp()


def validate_spec(spec):
    require(isinstance(spec, dict), 'spec is not an object')
    common = {'schema', 'kind', 'role', 'process_id', 'process_start_utc',
              'engine_sha256', 'action', 'client_width', 'client_height'}
    legacy_actions = {'text': {'text'}, 'click': {'x', 'y'},
                      'drag': {'x', 'y', 'target_x', 'target_y'},
                      'escape': set(), 'inventory': set(), 'tab': set()}
    linux_actions = {'MIRLinuxLibraryNativeClearTextV1': ('clear', set()),
                     'MIRLinuxLibraryNativeWheelV1': ('wheel', {'x', 'y', 'direction'})}
    kind = spec.get('kind')
    action = spec.get('action')
    require(type(spec.get('schema')) is int and spec['schema'] == 1
            and isinstance(kind, str) and (kind == 'MIRLibraryNativeInputV1' or kind in linux_actions),
            'schema differs')
    if kind == 'MIRLibraryNativeInputV1':
        require(isinstance(action, str) and action in legacy_actions, 'action differs')
        extras = legacy_actions[action]
    else:
        expected_action, extras = linux_actions[kind]
        require(action == expected_action, 'action differs')
    require(set(spec) == common | extras, 'spec fields differ')
    require(spec['role'] in ('client-en', 'client-de'), 'client role differs')
    require(integer(spec['process_id']), 'process identity differs')
    utc(spec['process_start_utc'])
    require(isinstance(spec['engine_sha256'], str)
            and re.fullmatch('[A-F0-9]{64}', spec['engine_sha256']), 'engine hash differs')
    width, height = spec['client_width'], spec['client_height']
    require(type(width) is int and type(height) is int
            and (width, height) in ((1280, 720), (2560, 1440)), 'client geometry differs')
    if action == 'text':
        require(isinstance(spec['text'], str)
                and re.fullmatch('[A-Za-z0-9 _-]{1,32}', spec['text']), 'text differs')
    if action in ('click', 'drag', 'wheel'):
        for x, y in [('x', 'y')] + ([('target_x', 'target_y')] if action == 'drag' else []):
            require(integer(spec[x], 2, width - 3) and integer(spec[y], 2, height - 3),
                    'point outside client')
    if action == 'wheel':
        require(isinstance(spec['direction'], str) and spec['direction'] in WHEEL_BUTTONS,
                'wheel direction differs')
    if action == 'drag':
        dx, dy = spec['target_x'] - spec['x'], spec['target_y'] - spec['y']
        require(abs(dx) <= 80 and abs(dy) <= 80 and (dx or dy), 'drag distance differs')
    return spec


def linux_path(value):
    return isinstance(value, str) and value.startswith('/') and '\\' not in value \
        and '\0' not in value and '..' not in PurePosixPath(value).parts \
        and str(PurePosixPath(value)) == value


def validate_binding(spec, binding):
    fields = {'schema', 'kind', 'role', 'process_id', 'session_id', 'start_ticks',
              'engine_path', 'display', 'xauthority', 'window', 'bounds'}
    require(isinstance(binding, dict) and set(binding) == fields, 'binding fields differ')
    require(type(binding['schema']) is int and binding['schema'] == 1
            and binding['kind'] == 'MIRLinuxLibraryInputBindingV1', 'binding schema differs')
    require(binding['role'] == spec['role'] and type(binding['process_id']) is int
            and binding['process_id'] == spec['process_id'], 'binding process/role differs')
    require(integer(binding['session_id']) and integer(binding['start_ticks'], 1, 2**64 - 1),
            'binding lifetime differs')
    require(linux_path(binding['engine_path'])
            and PurePosixPath(binding['engine_path']).name == 'factorio'
            and linux_path(binding['xauthority']), 'binding path differs')
    require(binding['display'] in (':193', ':194') and integer(binding['window'], 1, 2**32 - 1),
            'private X binding differs')
    require(isinstance(binding['bounds'], list) and all(type(v) is int for v in binding['bounds'])
            and binding['bounds'] == [0, 0, spec['client_width'], spec['client_height']],
            'binding geometry differs')
    return binding


def pinned_json(path, digest):
    require(re.fullmatch('[A-Fa-f0-9]{64}', digest) is not None, 'input hash malformed')
    path = Path(path)
    require(not path.is_symlink() and path.is_file() and 0 < path.stat().st_size <= 8192,
            'input file differs')
    raw = path.read_bytes()
    require(len(raw) <= 8192 and hashlib.sha256(raw).hexdigest().upper() == digest.upper(),
            'input hash differs')
    def unique(pairs):
        value = {}
        for key, child in pairs:
            require(key not in value, 'duplicate JSON member')
            value[key] = child
        return value
    return json.loads(raw, object_pairs_hook=unique)


def file_hash(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest().upper()


def engine_frame(path):
    info = path.stat()
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


def process_guard(spec, binding):
    """Pin exact executable bytes once, then lifetime/inode on every input edge."""
    require(sys.platform == 'linux', 'Linux execution required')
    engine = Path(binding['engine_path'])
    require(engine.resolve(strict=True) == engine and engine.is_file(), 'resolved engine differs')
    expected = engine_frame(engine)
    require(file_hash(engine) == spec['engine_sha256'], 'engine bytes differ')
    proc = Path('/proc') / str(spec['process_id'])
    tick_rate = os.sysconf('SC_CLK_TCK')
    boot = next(int(line.split()[1]) for line in Path('/proc/stat').read_text().splitlines()
                if line.startswith('btime '))
    def guard():
        require(proc.stat().st_uid == os.getuid(), 'process owner differs')
        fields = (proc / 'stat').read_text().rsplit(')', 1)[1].split()
        require(fields[0] not in ('Z', 'X') and int(fields[3]) == binding['session_id']
                and int(fields[19]) == binding['start_ticks'], 'process lifetime differs')
        require(abs(boot + int(fields[19]) / tick_rate - utc(spec['process_start_utc']))
                <= 1 / tick_rate, 'process start time differs')
        require((proc / 'exe').resolve(strict=True) == engine
                and engine_frame(engine) == expected, 'running engine differs')
    guard()
    return guard, lambda: require(file_hash(engine) == spec['engine_sha256'], 'engine changed during input')


# Xlib ABI fields: official XGetWindowAttributes(3) and XGetWindowProperty(3).
# https://xorg.freedesktop.org/archive/X11R7.5/doc/man/man3/XGetWindowAttributes.3.html
class WindowAttributes(C.Structure):
    _fields_ = [(name, C.c_int) for name in ('x', 'y', 'width', 'height', 'border_width', 'depth')] + [
        ('visual', C.c_void_p), ('root', C.c_ulong), ('window_class', C.c_int),
        ('bit_gravity', C.c_int), ('win_gravity', C.c_int), ('backing_store', C.c_int),
        ('backing_planes', C.c_ulong), ('backing_pixel', C.c_ulong), ('save_under', C.c_int),
        ('colormap', C.c_ulong), ('map_installed', C.c_int), ('map_state', C.c_int),
        ('all_event_masks', C.c_long), ('your_event_mask', C.c_long),
        ('do_not_propagate_mask', C.c_long), ('override_redirect', C.c_int), ('screen', C.c_void_p)]


class ClientMessage(C.Structure):
    _fields_ = [
        ('type', C.c_int), ('serial', C.c_ulong), ('send_event', C.c_int),
        ('display', C.c_void_p), ('window', C.c_ulong), ('message_type', C.c_ulong),
        ('format', C.c_int), ('data', C.c_long * 5),
    ]


class XEvent(C.Union):
    _fields_ = [('client_message', ClientMessage), ('pad', C.c_long * 24)]


class LinuxX11:
    def __init__(self, binding):
        self.x = C.CDLL('libX11.so.6')
        self.t = C.CDLL('libXtst.so.6')
        pointer, window = C.c_void_p, C.c_ulong
        def function(lib, name, result, *arguments):
            fn = getattr(lib, name)
            fn.restype, fn.argtypes = result, list(arguments)
        function(self.x, 'XOpenDisplay', pointer, C.c_char_p)
        function(self.x, 'XCloseDisplay', C.c_int, pointer)
        function(self.x, 'XGetWindowAttributes', C.c_int, pointer, window, C.POINTER(WindowAttributes))
        function(self.x, 'XTranslateCoordinates', C.c_int, pointer, window, window, C.c_int, C.c_int,
                 C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(window))
        function(self.x, 'XFetchName', C.c_int, pointer, window, C.POINTER(C.c_void_p))
        function(self.x, 'XFree', C.c_int, pointer)
        function(self.x, 'XInternAtom', window, pointer, C.c_char_p, C.c_int)
        function(self.x, 'XGetWindowProperty', C.c_int, pointer, window, window, C.c_long, C.c_long,
                 C.c_int, window, C.POINTER(window), C.POINTER(C.c_int), C.POINTER(window),
                 C.POINTER(window), C.POINTER(C.c_void_p))
        function(self.x, 'XGetWMProtocols', C.c_int, pointer, window, C.POINTER(C.POINTER(window)),
                 C.POINTER(C.c_int))
        function(self.x, 'XSendEvent', C.c_int, pointer, window, C.c_int, C.c_long, C.POINTER(XEvent))
        function(self.x, 'XSetInputFocus', C.c_int, pointer, window, C.c_int, window)
        function(self.x, 'XGetInputFocus', C.c_int, pointer, C.POINTER(window), C.POINTER(C.c_int))
        function(self.x, 'XSync', C.c_int, pointer, C.c_int)
        function(self.x, 'XSetErrorHandler', pointer, pointer)
        function(self.x, 'XKeysymToKeycode', C.c_ubyte, pointer, window)
        function(self.x, 'XkbKeycodeToKeysym', window, pointer, C.c_ubyte, C.c_uint, C.c_uint)
        function(self.x, 'XkbGetState', C.c_int, pointer, C.c_uint, pointer)
        function(self.x, 'XQueryPointer', C.c_int, pointer, window, C.POINTER(window), C.POINTER(window),
                 C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_uint))
        function(self.t, 'XTestFakeKeyEvent', C.c_int, pointer, C.c_uint, C.c_int, window)
        function(self.t, 'XTestFakeButtonEvent', C.c_int, pointer, C.c_uint, C.c_int, window)
        function(self.t, 'XTestFakeMotionEvent', C.c_int, pointer, C.c_int, C.c_int, C.c_int, window)
        auth = Path(binding['xauthority'])
        info = auth.lstat()
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
                and info.st_mode & 0o077 == 0, 'private X authority differs')
        os.environ['XAUTHORITY'] = str(auth)
        self.d = self.x.XOpenDisplay(binding['display'].encode('ascii'))
        require(bool(self.d), 'private X connection failed')
        # The child has one connection and no threads. Refuse asynchronous X
        # errors instead of letting Xlib exit past the partial-input receipt.
        self.x_error = False
        def failed(display, event):
            self.x_error = True
            return 0
        self.error_callback = C.CFUNCTYPE(C.c_int, pointer, pointer)(failed)
        self.previous_error_handler = self.x.XSetErrorHandler(C.cast(self.error_callback, pointer))
        self.window_id = binding['window']

    def window(self, binding, spec):
        require(not self.x_error, 'private X request failed')
        attrs = WindowAttributes()
        require(self.x.XGetWindowAttributes(self.d, self.window_id, C.byref(attrs)) != 0,
                'window attributes unavailable')
        x, y, child = C.c_int(), C.c_int(), C.c_ulong()
        require(self.x.XTranslateCoordinates(self.d, self.window_id, attrs.root, 0, 0,
                C.byref(x), C.byref(y), C.byref(child)) != 0, 'window origin unavailable')
        name = C.c_void_p()
        try:
            require(self.x.XFetchName(self.d, self.window_id, C.byref(name)) != 0 and bool(name),
                    'window title unavailable')
            raw_title = C.string_at(name)
            require(len(raw_title) <= 256, 'window title is unbounded')
            title = raw_title.decode('utf-8', errors='strict')
        finally:
            if name:
                self.x.XFree(name)
        atom = self.x.XInternAtom(self.d, b'_NET_WM_PID', 1)
        require(atom != 0, 'window process property unavailable')
        actual, fmt, count, remaining, data = C.c_ulong(), C.c_int(), C.c_ulong(), C.c_ulong(), C.c_void_p()
        try:
            status = self.x.XGetWindowProperty(self.d, self.window_id, atom, 0, 1, 0, 6,
                C.byref(actual), C.byref(fmt), C.byref(count), C.byref(remaining), C.byref(data))
            require(status == 0 and actual.value == 6 and fmt.value == 32 and count.value == 1
                    and remaining.value == 0 and bool(data), 'window process property differs')
            # Xlib expands format-32 properties into native unsigned long slots.
            pid = C.cast(data, C.POINTER(C.c_ulong))[0]
        finally:
            if data:
                self.x.XFree(data)
        return {'pid': pid, 'bounds': [x.value, y.value, attrs.width, attrs.height],
                'mapped': attrs.map_state == 2, 'title': title}

    def focus(self, window):
        self.x.XSetInputFocus(self.d, window, 0, 0)
        self.sync()

    def focused(self):
        window, revert = C.c_ulong(), C.c_int()
        require(self.x.XGetInputFocus(self.d, C.byref(window), C.byref(revert)) != 0,
                'focus observation failed')
        return window.value

    def modifiers(self):
        root, child, rx, ry, wx, wy, mask = C.c_ulong(), C.c_ulong(), C.c_int(), C.c_int(), C.c_int(), C.c_int(), C.c_uint()
        require(self.x.XQueryPointer(self.d, self.window_id, C.byref(root), C.byref(child),
                C.byref(rx), C.byref(ry), C.byref(wx), C.byref(wy), C.byref(mask)) != 0,
                'modifier observation failed')
        return mask.value

    def keyboard_group(self):
        # Read only the stable first byte (effective group), avoiding differing
        # historical published layouts for the remainder of XkbStateRec.
        state = C.create_string_buffer(64)
        require(self.x.XkbGetState(self.d, 0x0100, state) == 0, 'keyboard state unavailable')
        return state.raw[0]

    def keycode(self, symbol):
        symbols = {'Escape': 0xFF1B, 'Tab': 0xFF09, 'BackSpace': 0xFF08,
                   'Shift_L': 0xFFE1, 'Control_L': 0xFFE3}
        value = symbols[symbol] if symbol in symbols else ord(symbol)
        code = int(self.x.XKeysymToKeycode(self.d, value))
        require(code != 0, 'key mapping unavailable')
        plain = self.x.XkbKeycodeToKeysym(self.d, code, 0, 0)
        shifted = self.x.XkbKeycodeToKeysym(self.d, code, 0, 1)
        require(value in (plain, shifted), 'key mapping differs')
        return code, value != plain

    def key(self, code, down):
        return self.t.XTestFakeKeyEvent(self.d, code, int(down), 0)

    def motion(self, x, y):
        return self.t.XTestFakeMotionEvent(self.d, -1, x, y, 0)

    def button(self, down, number=1):
        return self.t.XTestFakeButtonEvent(self.d, number, int(down), 0)

    def sync(self):
        self.x.XSync(self.d, 0)
        require(not self.x_error, 'private X request failed')

    def request_close(self, window):
        require(window == self.window_id, 'close request targets a different window')
        protocols_atom = self.x.XInternAtom(self.d, b'WM_PROTOCOLS', 1)
        delete_atom = self.x.XInternAtom(self.d, b'WM_DELETE_WINDOW', 1)
        require(protocols_atom != 0 and delete_atom != 0, 'window close protocol unavailable')
        protocols, count = C.POINTER(C.c_ulong)(), C.c_int()
        try:
            advertised = self.x.XGetWMProtocols(self.d, window, C.byref(protocols), C.byref(count))
            require(advertised != 0 and bool(protocols) and 0 < count.value <= 64
                    and any(protocols[index] == delete_atom for index in range(count.value)),
                    'window did not advertise the close protocol')
        finally:
            if protocols:
                self.x.XFree(protocols)

        # ICCCM ClientMessage format 32 with native long storage in Xlib.
        # Post-measurement cleanup uses CurrentTime when there is no input timestamp.
        event = XEvent()
        message = event.client_message
        message.type, message.display, message.window = 33, self.d, window
        message.message_type, message.format, message.data[0] = protocols_atom, 32, delete_atom
        require(self.x.XSendEvent(self.d, window, 0, 0, C.byref(event)) != 0, 'window close request refused')
        self.sync()

    def close(self):
        try:
            self.x.XCloseDisplay(self.d)
        finally:
            self.x.XSetErrorHandler(self.previous_error_handler)


def verify_owned_window(spec, binding, backend, guard):
    guard()
    observed = backend.window(binding, spec)
    require(observed['pid'] == spec['process_id'] and observed['bounds'] == binding['bounds']
            and observed['mapped'] is True and 'factorio' in observed['title'].casefold(),
            'owned window differs')


def request_owned_window_close(spec, binding, backend, guard):
    validate_spec(spec)
    validate_binding(spec, binding)
    verify_owned_window(spec, binding, backend, guard)
    backend.request_close(binding['window'])
    return {'protocol': 'WM_DELETE_WINDOW', 'process_id': binding['process_id'], 'window': binding['window']}


def perform(spec, binding, backend, guard, pause=time.sleep):
    validate_spec(spec)
    validate_binding(spec, binding)
    trace, held, held_button = [], [], None
    def checked_window(focused=True):
        verify_owned_window(spec, binding, backend, guard)
        if focused:
            require(backend.focused() == binding['window'], 'owned window lost focus')
    def emit(api, call, **facts):
        checked_window()
        row = {'api': api, 'cleanup': False, 'accepted_by_xtest': False, **facts}
        trace.append(row)
        result = call()
        row['result'] = result
        row['accepted_by_xtest'] = type(result) is int and result != 0
        require(row['accepted_by_xtest'], api + ' refused')
        return result
    def key(code, down):
        nonlocal held
        emit('XTestFakeKeyEvent', lambda: backend.key(code, down), keycode=code, down=down)
        if down:
            held.append(code)
        elif code in held:
            held.remove(code)
        backend.sync()
    def button(number, down):
        nonlocal held_button
        emit('XTestFakeButtonEvent', lambda: backend.button(down, number), button=number, down=down)
        held_button = number if down else None
        backend.sync()
    def move(x, y):
        emit('XTestFakeMotionEvent', lambda: backend.motion(x, y), x=x, y=y)
        backend.sync()
    def typed(symbol, delay):
        code, shifted = backend.keycode(symbol)
        shift, _ = backend.keycode('Shift_L') if shifted else (0, False)
        if shifted:
            key(shift, True)
        key(code, True)
        pause(delay)
        key(code, False)
        if shifted:
            key(shift, False)
    def clear_text():
        control, control_shifted = backend.keycode('Control_L')
        select_all, select_all_shifted = backend.keycode('a')
        backspace, backspace_shifted = backend.keycode('BackSpace')
        require(not (control_shifted or select_all_shifted or backspace_shifted),
                'key mapping differs')
        key(control, True)
        key(select_all, True)
        pause(.1)
        key(select_all, False)
        key(control, False)
        pause(.05)
        key(backspace, True)
        pause(.1)
        key(backspace, False)
    try:
        checked_window(False)
        backend.focus(binding['window'])
        checked_window()
        require(backend.modifiers() & ~16 == 0 and backend.keyboard_group() == 0,
                'unexpected held modifiers, buttons, or keyboard group')
        action = spec['action']
        if action == 'clear':
            clear_text()
        elif action == 'text':
            for symbol in spec['text']:
                typed(symbol, .05)
        elif action in ('escape', 'inventory', 'tab'):
            typed({'escape': 'Escape', 'inventory': 'e', 'tab': 'Tab'}[action], .1)
        else:
            move(spec['x'], spec['y'])
            button_number = WHEEL_BUTTONS[spec['direction']] if action == 'wheel' else 1
            button(button_number, True)
            pause(.1)
            if action == 'drag':
                for step in range(1, 5):
                    pause(.04)
                    move(round(spec['x'] + (spec['target_x'] - spec['x']) * step / 4),
                         round(spec['y'] + (spec['target_y'] - spec['y']) * step / 4))
                pause(.1)
            button(button_number, False)
        checked_window()
    except Exception as error:
        raise InputError(str(error), trace) from error
    finally:
        # Release only inputs accepted as held by this action, even when its
        # client vanished. Cleanup never sends a new down/motion request.
        for code in reversed(held):
            try:
                result = backend.key(code, False)
                trace.append({'api': 'XTestFakeKeyEvent', 'cleanup': True, 'keycode': code,
                              'down': False, 'result': result,
                              'accepted_by_xtest': type(result) is int and result != 0})
                backend.sync()
            except Exception as error:
                trace.append({'api': 'cleanup-error', 'cleanup': True, 'error': type(error).__name__})
        if held_button is not None:
            try:
                result = backend.button(False, held_button)
                trace.append({'api': 'XTestFakeButtonEvent', 'cleanup': True, 'button': held_button,
                              'down': False, 'result': result,
                              'accepted_by_xtest': type(result) is int and result != 0})
                backend.sync()
            except Exception as error:
                trace.append({'api': 'cleanup-error', 'cleanup': True, 'error': type(error).__name__})
    return trace


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spec-path', required=True, type=Path)
    parser.add_argument('--spec-sha256', required=True)
    parser.add_argument('--binding-path', required=True, type=Path)
    parser.add_argument('--binding-sha256', required=True)
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    result = {'kind': 'MIRLinuxLibraryNativeInputReceiptV1', 'status': 'refused',
              'native_gui_acceptance': False, 'trace': []}
    try:
        spec = validate_spec(pinned_json(args.spec_path, args.spec_sha256))
        binding = validate_binding(spec, pinned_json(args.binding_path, args.binding_sha256))
        result.update(action=spec['action'], role=spec['role'])
        if args.validate_only:
            result['status'] = 'validated-schema-only'
            result['native_process_identity_checked'] = False
        else:
            guard, final_hash = process_guard(spec, binding)
            backend = LinuxX11(binding)
            action_error = None
            try:
                result['trace'] = perform(spec, binding, backend, guard)
                final_hash()
            except Exception as error:
                action_error = error
                if isinstance(error, InputError) and error.trace:
                    result['trace'] = error.trace
            finally:
                try:
                    backend.close()
                except Exception as error:
                    result['connection_close_error'] = type(error).__name__
                    if action_error is None:
                        action_error = InputError('X connection close failed', result['trace'])
            if action_error is not None:
                raise action_error
            result['status'] = 'input-requests-accepted-pending-native-observation'
            result['native_process_identity_checked'] = True
    except Exception as error:
        result['error'] = str(error)[:512]
        if isinstance(error, InputError) and error.trace:
            result['trace'] = error.trace
    print(json.dumps(result, sort_keys=True))
    return 1 if result['status'] == 'refused' else 0


if __name__ == '__main__':
    sys.exit(main())
