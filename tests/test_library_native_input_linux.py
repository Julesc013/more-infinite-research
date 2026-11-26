"""Independent mock controls for the narrow Linux Library input leaf.

These controls exercise the hash-bound actor's public leaf functions only.  They
do not open X, start Factorio, inspect /proc, or mutate a mod library.
"""
import ctypes as C
import importlib.util
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
ACTOR_PATH = ROOT / "tools" / "Invoke-LibraryNativeInputLinux.py"
SPEC = importlib.util.spec_from_file_location("mir_linux_library_input", ACTOR_PATH)
ACTOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ACTOR)


ENGINE_SHA = "A" * 64


def valid_spec(action="escape", **changes):
    spec = {
        "schema": 1,
        "kind": {
            "clear": "MIRLinuxLibraryNativeClearTextV1",
            "wheel": "MIRLinuxLibraryNativeWheelV1",
        }.get(action, "MIRLibraryNativeInputV1"),
        "role": "client-en",
        "process_id": 4242,
        "process_start_utc": "2026-11-17T00:00:00Z",
        "engine_sha256": ENGINE_SHA,
        "action": action,
        "client_width": 1280,
        "client_height": 720,
    }
    if action == "text":
        spec["text"] = "A z"
    elif action == "click":
        spec.update(x=100, y=120)
    elif action == "drag":
        spec.update(x=100, y=100, target_x=180, target_y=140)
    elif action == "wheel":
        spec.update(x=100, y=120, direction="down")
    spec.update(changes)
    return spec


def valid_binding(spec, **changes):
    binding = {
        "schema": 1,
        "kind": "MIRLinuxLibraryInputBindingV1",
        "role": spec["role"],
        "process_id": spec["process_id"],
        "session_id": 51,
        "start_ticks": 9001,
        "engine_path": "/opt/factorio/bin/x64/factorio",
        "display": ":193",
        "xauthority": "/home/jules/private/xauthority",
        "window": 7001,
        "bounds": [0, 0, spec["client_width"], spec["client_height"]],
    }
    binding.update(changes)
    return binding


class MockBackend:
    """A traceable XTest-shaped double; it has no process or X-server effects."""

    keycodes = {"Escape": 9, "Tab": 23, "BackSpace": 22, "Shift_L": 50, "_": 20,
                "Control_L": 37, "e": 26, "a": 38, "A": 38, "z": 52, " ": 65}

    def __init__(self, spec, binding, *, stolen_focus=False, mapped=True,
                 title="Factorio 2.1", pid=None, bounds=None, modifiers=0,
                 group=0, reject=None, close_error=None,
                 changed_window_after_key_events=None, lose_focus_after_key_events=None,
                 shifted_symbols=()):
        self.spec = spec
        self.binding = binding
        self.stolen_focus = stolen_focus
        self.mapped = mapped
        self.title = title
        self.pid = spec["process_id"] if pid is None else pid
        self.bounds = binding["bounds"] if bounds is None else bounds
        self.modifier_mask = modifiers
        self.group = group
        self.reject = reject
        self.close_error = close_error
        self.changed_window_after_key_events = changed_window_after_key_events
        self.lose_focus_after_key_events = lose_focus_after_key_events
        self.shifted_symbols = set(shifted_symbols)
        self.events = []
        self.key_event_count = 0
        self.focused_window = None
        self.close_calls = 0

    def window(self, binding, spec):
        title = self.title
        if (self.changed_window_after_key_events is not None
                and self.key_event_count >= self.changed_window_after_key_events):
            title = "other program"
        return {"pid": self.pid, "bounds": list(self.bounds),
                "mapped": self.mapped, "title": title}

    def focus(self, window):
        self.events.append(("focus", window))
        if not self.stolen_focus:
            self.focused_window = window

    def focused(self):
        if (self.lose_focus_after_key_events is not None
                and self.key_event_count >= self.lose_focus_after_key_events):
            return None
        return self.focused_window

    def modifiers(self):
        return self.modifier_mask

    def keyboard_group(self):
        return self.group

    def keycode(self, symbol):
        return self.keycodes[symbol], symbol == "A" or symbol in self.shifted_symbols

    def key(self, code, down):
        self.events.append(("key", code, down))
        self.key_event_count += 1
        return 0 if self.reject in ("key", ("key", code, down)) else 1

    def motion(self, x, y):
        self.events.append(("motion", x, y))
        return 0 if self.reject == "motion" else 1

    def button(self, down, number=1):
        self.events.append(("button", number, down))
        return 0 if self.reject == "button" else 1

    def sync(self):
        self.events.append(("sync",))

    def close(self):
        self.close_calls += 1
        if self.close_error is not None:
            raise self.close_error



class OwnedMenuCloseTests(unittest.TestCase):
    def test_close_checks_the_exact_owned_window_before_sending(self):
        spec = valid_spec("click")
        binding = valid_binding(spec)
        guard = mock.Mock()
        for changed in ({}, {"pid": 17}, {"mapped": False}, {"bounds": [0, 0, 640, 480]}):
            with self.subTest(changed=changed):
                backend = mock.Mock()
                backend.window.return_value = {
                    "pid": spec["process_id"], "mapped": True, "bounds": binding["bounds"], "title": "Factorio 2.1"
                } | changed
                if changed:
                    with self.assertRaisesRegex(ValueError, "owned window differs"):
                        ACTOR.request_owned_window_close(spec, binding, backend, guard)
                    backend.request_close.assert_not_called()
                else:
                    receipt = ACTOR.request_owned_window_close(spec, binding, backend, guard)
                    backend.request_close.assert_called_once_with(binding["window"])
                    self.assertEqual(receipt["protocol"], "WM_DELETE_WINDOW")

    def test_close_sends_the_advertised_client_message_only(self):
        backend = ACTOR.LinuxX11.__new__(ACTOR.LinuxX11)
        backend.x = mock.Mock()
        backend.d, backend.window_id, backend.x_error = 123, 7001, False
        backend.x.XInternAtom.side_effect = lambda _display, name, _exists: {b"WM_PROTOCOLS": 8, b"WM_DELETE_WINDOW": 11}[name]
        announced = (C.c_ulong * 1)(11)

        def protocols(_display, _window, pointer, count):
            C.cast(pointer, C.POINTER(C.POINTER(C.c_ulong)))[0] = C.cast(announced, C.POINTER(C.c_ulong))
            C.cast(count, C.POINTER(C.c_int))[0] = 1
            return 1

        def delivered(display, window, propagate, mask, event):
            self.assertEqual((display, window, propagate, mask), (123, 7001, 0, 0))
            wire = C.cast(event, C.POINTER(ACTOR.XEvent)).contents.client_message
            self.assertEqual((wire.type, wire.window, wire.message_type, wire.format), (33, 7001, 8, 32))
            self.assertEqual(list(wire.data), [11, 0, 0, 0, 0])
            return 1

        backend.x.XGetWMProtocols.side_effect = protocols
        backend.x.XSendEvent.side_effect = delivered
        backend.request_close(7001)
        backend.x.XSendEvent.assert_called_once()
        backend.x.XSync.assert_called_once_with(123, 0)
        backend.x.XFree.assert_called_once()

        backend.x.XSendEvent.reset_mock()
        announced[0] = 22
        with self.assertRaisesRegex(ValueError, "did not advertise"):
            backend.request_close(7001)
        backend.x.XSendEvent.assert_not_called()


class LibraryNativeInputLinuxTests(unittest.TestCase):
    def write_pinned_json(self, root, name, value):
        path = Path(root) / name
        raw = json.dumps(value, separators=(",", ":")).encode("utf-8")
        path.write_bytes(raw)
        return path, hashlib.sha256(raw).hexdigest().upper()

    def invoke_main(self, spec, binding, *, validate_only=False, guard=None, final_hash=None,
                    backend=None):
        with tempfile.TemporaryDirectory() as directory:
            spec_path, spec_hash = self.write_pinned_json(directory, "spec.json", spec)
            binding_path, binding_hash = self.write_pinned_json(directory, "binding.json", binding)
            arguments = [
                "actor", "--spec-path", str(spec_path), "--spec-sha256", spec_hash,
                "--binding-path", str(binding_path), "--binding-sha256", binding_hash,
            ]
            if validate_only:
                arguments.append("--validate-only")
            output = io.StringIO()
            guard = guard or (lambda: None)
            final_hash = final_hash or (lambda: None)
            with mock.patch.object(sys, "argv", arguments), \
                    mock.patch.object(sys, "stdout", output), \
                    mock.patch.object(ACTOR, "process_guard", return_value=(guard, final_hash)), \
                    mock.patch.object(ACTOR, "LinuxX11", return_value=backend):
                status = ACTOR.main()
            return status, json.loads(output.getvalue())

    def perform(self, spec, backend=None, binding=None, fail_guard_at=None):
        binding = binding or valid_binding(spec)
        backend = backend or MockBackend(spec, binding)
        calls = []

        def guard():
            calls.append("guard")
            if fail_guard_at is not None and len(calls) == fail_guard_at:
                raise ACTOR.InputError("guard refused")

        pauses = []
        trace = ACTOR.perform(spec, binding, backend, guard, pauses.append)
        return trace, backend, calls, pauses

    def assert_refuses(self, call, message):
        with self.assertRaisesRegex(ACTOR.InputError, message):
            call()

    def test_legacy_schema_accepts_only_the_exact_ascii_action_shape(self):
        for action in ("escape", "inventory", "tab", "text", "click", "drag"):
            with self.subTest(action=action):
                spec = valid_spec(action)
                self.assertIs(ACTOR.validate_spec(spec), spec)
                binding = valid_binding(spec)
                self.assertIs(ACTOR.validate_binding(spec, binding), binding)

        self.assert_refuses(
            lambda: ACTOR.validate_spec(valid_spec("escape", unexpected=True)), "spec fields differ"
        )
        self.assert_refuses(
            lambda: ACTOR.validate_spec(valid_spec("escape", process_id=True)), "process identity differs"
        )
        self.assert_refuses(
            lambda: ACTOR.validate_spec(valid_spec("click", x=1)), "point outside client"
        )
        self.assert_refuses(
            lambda: ACTOR.validate_spec(valid_spec("escape", client_width=1920)), "client geometry differs"
        )
        unicode_spec = valid_spec("text", kind="MIRLibraryNativeUnicodeTextV1", text="café")
        self.assert_refuses(lambda: ACTOR.validate_spec(unicode_spec), "schema differs")
        self.assert_refuses(
            lambda: ACTOR.validate_spec(valid_spec("text", text="café")), "text differs"
        )

    def test_linux_clear_schema_is_distinct_from_the_unchanged_legacy_actions(self):
        clear = valid_spec("clear")
        self.assertIs(ACTOR.validate_spec(clear), clear)
        self.assert_refuses(
            lambda: ACTOR.validate_spec(valid_spec("clear", kind="MIRLibraryNativeInputV1")),
            "action differs",
        )
        self.assert_refuses(
            lambda: ACTOR.validate_spec(
                valid_spec("escape", kind="MIRLinuxLibraryNativeClearTextV1")
            ),
            "action differs",
        )
        self.assert_refuses(
            lambda: ACTOR.validate_spec(valid_spec("clear", text="gear")),
            "spec fields differ",
        )

    def test_linux_wheel_schema_accepts_one_bounded_vertical_step(self):
        for direction in ("up", "down"):
            spec = valid_spec("wheel", direction=direction)
            self.assertIs(ACTOR.validate_spec(spec), spec)
        for changed, reason in (
            ({"direction": "left"}, "wheel direction differs"),
            ({"direction": []}, "wheel direction differs"),
            ({"count": 2}, "spec fields differ"),
            ({"x": 1}, "point outside client"),
            ({"kind": "MIRLibraryNativeInputV1"}, "action differs"),
        ):
            with self.subTest(changed=changed):
                self.assert_refuses(lambda: ACTOR.validate_spec(valid_spec("wheel", **changed)), reason)

    def test_binding_requires_exact_role_identity_private_display_paths_and_bounds(self):
        spec = valid_spec("escape")
        for changed, message in (
            ({"role": "client-de"}, "binding process/role differs"),
            ({"process_id": 4243}, "binding process/role differs"),
            ({"session_id": True}, "binding lifetime differs"),
            ({"engine_path": "/opt/factorio/../factorio"}, "binding path differs"),
            ({"display": ":195"}, "private X binding differs"),
            ({"bounds": [0, 0, 1279, 720]}, "binding geometry differs"),
        ):
            with self.subTest(changed=changed):
                self.assert_refuses(
                    lambda changed=changed: ACTOR.validate_binding(spec, valid_binding(spec, **changed)),
                    message,
                )

    def test_click_uses_owned_window_then_motion_button_down_and_button_up(self):
        spec = valid_spec("click")
        trace, backend, _, pauses = self.perform(spec)
        self.assertEqual(pauses, [0.1])
        self.assertEqual(
            backend.events,
            [("focus", 7001), ("motion", 100, 120), ("sync",),
             ("button", 1, True), ("sync",), ("button", 1, False), ("sync",)],
        )
        self.assertEqual([row["api"] for row in trace], [
            "XTestFakeMotionEvent", "XTestFakeButtonEvent", "XTestFakeButtonEvent"
        ])
        self.assertTrue(all(row["accepted_by_xtest"] and not row["cleanup"] for row in trace))

    def test_linux_wheel_sends_one_matching_button_pair_through_the_input_guards(self):
        for direction, number in (("up", 4), ("down", 5)):
            with self.subTest(direction=direction):
                trace, backend, calls, _ = self.perform(valid_spec("wheel", direction=direction))
                self.assertEqual(calls, ["guard"] * 6)
                self.assertEqual(
                    backend.events,
                    [("focus", 7001), ("motion", 100, 120), ("sync",),
                     ("button", number, True), ("sync",), ("button", number, False), ("sync",)],
                )
                self.assertEqual([(row["button"], row["down"]) for row in trace[1:]],
                                 [(number, True), (number, False)])
                self.assertTrue(all(row["accepted_by_xtest"] and not row["cleanup"] for row in trace))

    def test_text_keeps_shift_only_for_the_uppercase_character_and_handles_space(self):
        spec = valid_spec("text")
        trace, backend, _, pauses = self.perform(spec)
        self.assertEqual(pauses, [0.05, 0.05, 0.05])
        self.assertEqual(
            [event for event in backend.events if event[0] == "key"],
            [("key", 50, True), ("key", 38, True), ("key", 38, False),
             ("key", 50, False), ("key", 65, True), ("key", 65, False),
             ("key", 52, True), ("key", 52, False)],
        )
        self.assertEqual(len(trace), 8)
        self.assertTrue(all(row["api"] == "XTestFakeKeyEvent" for row in trace))

    def test_material_filter_accepts_the_identifier_and_releases_shift_after_underscore(self):
        selection = valid_spec("text", text="research_material_aluminium")
        self.assertIs(ACTOR.validate_spec(selection), selection)
        spec = valid_spec("text", text="a_z")
        binding = valid_binding(spec)
        backend = MockBackend(spec, binding, shifted_symbols=("_",))
        trace, _, _, _ = self.perform(spec, backend=backend, binding=binding)
        self.assertEqual(
            [event for event in backend.events if event[0] == "key"],
            [("key", 38, True), ("key", 38, False),
             ("key", 50, True), ("key", 20, True), ("key", 20, False),
             ("key", 50, False), ("key", 52, True), ("key", 52, False)],
        )
        self.assertTrue(all(edge["accepted_by_xtest"] and not edge["cleanup"] for edge in trace))

    def test_escape_inventory_and_tab_have_one_exact_key_pair(self):
        for action, code in (("escape", 9), ("inventory", 26), ("tab", 23)):
            with self.subTest(action=action):
                spec = valid_spec(action)
                trace, backend, _, pauses = self.perform(spec)
                self.assertEqual(pauses, [0.1])
                self.assertEqual(
                    [event for event in backend.events if event[0] == "key"],
                    [("key", code, True), ("key", code, False)],
                )
                self.assertEqual([row["down"] for row in trace], [True, False])

    def test_linux_clear_emits_only_control_a_then_backspace(self):
        spec = valid_spec("clear")
        trace, backend, _, pauses = self.perform(spec)
        self.assertEqual(pauses, [0.1, 0.05, 0.1])
        self.assertEqual(
            [event for event in backend.events if event[0] == "key"],
            [("key", 37, True), ("key", 38, True), ("key", 38, False),
             ("key", 37, False), ("key", 22, True), ("key", 22, False)],
        )
        self.assertEqual(
            [(row["keycode"], row["down"], row["cleanup"]) for row in trace],
            [(37, True, False), (38, True, False), (38, False, False),
             (37, False, False), (22, True, False), (22, False, False)],
        )
        self.assertTrue(all(row["accepted_by_xtest"] for row in trace))

    def test_linux_clear_refuses_a_nonplain_key_mapping_before_any_key(self):
        spec = valid_spec("clear")
        binding = valid_binding(spec)
        backend = MockBackend(spec, binding, shifted_symbols={"a"})
        with self.assertRaisesRegex(ACTOR.InputError, "key mapping differs") as caught:
            self.perform(spec, backend=backend, binding=binding)
        self.assertEqual(caught.exception.trace, [])
        self.assertFalse(any(event[0] == "key" for event in backend.events))

    def test_drag_uses_only_its_finite_100_by_40_schedule(self):
        spec = valid_spec("drag")
        trace, backend, _, pauses = self.perform(spec)
        self.assertEqual(pauses, [0.1, 0.04, 0.04, 0.04, 0.04, 0.1])
        self.assertEqual(
            [event for event in backend.events if event[0] == "motion"],
            [("motion", 100, 100), ("motion", 120, 110), ("motion", 140, 120),
             ("motion", 160, 130), ("motion", 180, 140)],
        )
        self.assertEqual([event for event in backend.events if event[0] == "button"],
                         [("button", 1, True), ("button", 1, False)])
        self.assertEqual([row["api"] for row in trace].count("XTestFakeMotionEvent"), 5)
        self.assertEqual([row["api"] for row in trace].count("XTestFakeButtonEvent"), 2)

    def test_stolen_focus_or_changed_owned_window_refuses_before_an_input_event(self):
        spec = valid_spec("clear")
        binding = valid_binding(spec)
        for backend, message in (
            (MockBackend(spec, binding, stolen_focus=True), "owned window lost focus"),
            (MockBackend(spec, binding, title="other program"), "owned window differs"),
            (MockBackend(spec, binding, mapped=False), "owned window differs"),
        ):
            with self.subTest(message=message):
                with self.assertRaises(ACTOR.InputError) as caught:
                    self.perform(spec, backend=backend, binding=binding)
                self.assertIn(message, str(caught.exception))
                self.assertEqual(caught.exception.trace, [])
                self.assertFalse(any(event[0] in ("key", "motion", "button") for event in backend.events))

    def test_live_window_pid_or_geometry_mismatch_refuses_before_an_input_event(self):
        spec = valid_spec("clear")
        binding = valid_binding(spec)
        for backend in (
            MockBackend(spec, binding, pid=4243),
            MockBackend(spec, binding, bounds=[0, 0, 1280, 719]),
        ):
            with self.subTest(backend=backend):
                with self.assertRaisesRegex(ACTOR.InputError, "owned window differs") as caught:
                    self.perform(spec, backend=backend, binding=binding)
                self.assertEqual(caught.exception.trace, [])
                self.assertFalse(any(event[0] in ("key", "motion", "button") for event in backend.events))

    def test_refused_xtest_event_retains_the_attempted_trace(self):
        spec = valid_spec("escape")
        binding = valid_binding(spec)
        backend = MockBackend(spec, binding, reject="key")
        with self.assertRaisesRegex(ACTOR.InputError, "XTestFakeKeyEvent refused") as caught:
            self.perform(spec, backend=backend, binding=binding)
        self.assertEqual(len(caught.exception.trace), 1)
        self.assertEqual(caught.exception.trace[0]["api"], "XTestFakeKeyEvent")
        self.assertFalse(caught.exception.trace[0]["accepted_by_xtest"])
        self.assertFalse(caught.exception.trace[0]["cleanup"])

    def test_guard_loss_releases_only_the_action_owned_key_and_preserves_trace(self):
        spec = valid_spec("text", text="z")
        binding = valid_binding(spec)
        backend = MockBackend(spec, binding)
        with self.assertRaisesRegex(ACTOR.InputError, "guard refused") as caught:
            self.perform(spec, backend=backend, binding=binding, fail_guard_at=4)
        trace = caught.exception.trace
        self.assertEqual(
            [(row["down"], row["cleanup"]) for row in trace if row["api"] == "XTestFakeKeyEvent"],
            [(True, False), (False, True)],
        )
        self.assertEqual([event for event in backend.events if event[0] == "key"],
                         [("key", 52, True), ("key", 52, False)])

    def test_guard_loss_after_drag_button_down_releases_only_that_button(self):
        spec = valid_spec("drag")
        binding = valid_binding(spec)
        backend = MockBackend(spec, binding)
        with self.assertRaisesRegex(ACTOR.InputError, "guard refused") as caught:
            self.perform(spec, backend=backend, binding=binding, fail_guard_at=5)
        trace = caught.exception.trace
        buttons = [row for row in trace if row["api"] == "XTestFakeButtonEvent"]
        self.assertEqual([(row["down"], row["cleanup"]) for row in buttons],
                         [(True, False), (False, True)])
        self.assertEqual([event for event in backend.events if event[0] == "motion"],
                         [("motion", 100, 100)])

    def test_guard_loss_releases_only_the_accepted_wheel_button(self):
        spec = valid_spec("wheel", direction="down")
        binding = valid_binding(spec)
        backend = MockBackend(spec, binding)
        with self.assertRaisesRegex(ACTOR.InputError, "guard refused") as caught:
            self.perform(spec, backend=backend, binding=binding, fail_guard_at=5)
        buttons = [row for row in caught.exception.trace if row["api"] == "XTestFakeButtonEvent"]
        self.assertEqual([(row["button"], row["down"], row["cleanup"]) for row in buttons],
                         [(5, True, False), (5, False, True)])
        self.assertEqual([event for event in backend.events if event[0] == "button"],
                         [("button", 5, True), ("button", 5, False)])

    def test_clear_guard_loss_mid_chord_releases_a_then_control_without_new_input(self):
        spec = valid_spec("clear")
        binding = valid_binding(spec)
        backend = MockBackend(spec, binding)
        with self.assertRaisesRegex(ACTOR.InputError, "guard refused") as caught:
            self.perform(spec, backend=backend, binding=binding, fail_guard_at=5)
        trace = caught.exception.trace
        self.assertEqual(
            [(row["keycode"], row["down"], row["cleanup"]) for row in trace],
            [(37, True, False), (38, True, False), (38, False, True),
             (37, False, True)],
        )
        self.assertEqual(
            [event for event in backend.events if event[0] == "key"],
            [("key", 37, True), ("key", 38, True), ("key", 38, False),
             ("key", 37, False)],
        )

    def test_clear_rechecks_lifetime_window_and_foreground_before_each_key_edge(self):
        spec = valid_spec("clear")
        binding = valid_binding(spec)

        def lifetime_changed():
            lifetime_changed.calls += 1
            if lifetime_changed.calls == 4:
                raise ACTOR.InputError("process lifetime differs")

        lifetime_changed.calls = 0
        cases = (
            (MockBackend(spec, binding), lifetime_changed, "process lifetime differs"),
            (MockBackend(spec, binding, changed_window_after_key_events=1),
             lambda: None, "owned window differs"),
            (MockBackend(spec, binding, lose_focus_after_key_events=1),
             lambda: None, "owned window lost focus"),
        )
        for backend, guard, message in cases:
            with self.subTest(message=message), self.assertRaisesRegex(ACTOR.InputError, message) as caught:
                ACTOR.perform(spec, binding, backend, guard, lambda _: None)
            self.assertEqual(
                [event for event in backend.events if event[0] == "key"],
                [("key", 37, True), ("key", 37, False)],
            )
            self.assertEqual(
                [(row["keycode"], row["down"], row["cleanup"])
                 for row in caught.exception.trace],
                [(37, True, False), (37, False, True)],
            )

    def test_clear_refusal_at_select_key_releases_the_accepted_control_modifier(self):
        spec = valid_spec("clear")
        binding = valid_binding(spec)
        backend = MockBackend(spec, binding, reject=("key", 38, True))
        with self.assertRaisesRegex(ACTOR.InputError, "XTestFakeKeyEvent refused") as caught:
            self.perform(spec, backend=backend, binding=binding)
        self.assertEqual(
            [(row["keycode"], row["down"], row["cleanup"], row["accepted_by_xtest"])
             for row in caught.exception.trace],
            [(37, True, False, True), (38, True, False, False),
             (37, False, True, True)],
        )
        self.assertEqual(
            [event for event in backend.events if event[0] == "key"],
            [("key", 37, True), ("key", 38, True), ("key", 37, False)],
        )

    def test_non_numlock_modifier_or_nonzero_keyboard_group_refuses_before_input(self):
        spec = valid_spec("escape")
        binding = valid_binding(spec)
        for backend in (
            MockBackend(spec, binding, modifiers=1),
            MockBackend(spec, binding, group=1),
        ):
            with self.subTest(backend=backend):
                with self.assertRaisesRegex(ACTOR.InputError, "unexpected held modifiers"):
                    self.perform(spec, backend=backend, binding=binding)
                self.assertFalse(any(event[0] == "key" for event in backend.events))

    def test_validate_only_never_opens_x_or_reads_the_nonexistent_process_paths(self):
        spec = valid_spec("clear", process_id=999_991)
        binding = valid_binding(
            spec,
            engine_path="/missing/factorio/bin/x64/factorio",
            xauthority="/missing/private/Xauthority",
        )
        with tempfile.TemporaryDirectory() as directory:
            spec_path, spec_hash = self.write_pinned_json(directory, "spec.json", spec)
            binding_path, binding_hash = self.write_pinned_json(directory, "binding.json", binding)
            output = io.StringIO()
            arguments = [
                "actor", "--spec-path", str(spec_path), "--spec-sha256", spec_hash,
                "--binding-path", str(binding_path), "--binding-sha256", binding_hash,
                "--validate-only",
            ]
            with mock.patch.object(sys, "argv", arguments), \
                    mock.patch.object(sys, "stdout", output), \
                    mock.patch.object(ACTOR, "process_guard", side_effect=AssertionError("process read")), \
                    mock.patch.object(ACTOR, "LinuxX11", side_effect=AssertionError("X open")):
                self.assertEqual(ACTOR.main(), 0)
        receipt = json.loads(output.getvalue())
        self.assertEqual(receipt["status"], "validated-schema-only")
        self.assertFalse(receipt["native_gui_acceptance"])
        self.assertFalse(receipt["native_process_identity_checked"])
        self.assertEqual(receipt["trace"], [])

    def test_pinned_json_refuses_wrong_hash_duplicate_keys_and_oversize_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            normal = root / "normal.json"
            normal.write_bytes(b'{"value":1}')
            with self.assertRaisesRegex(ACTOR.InputError, "input hash differs"):
                ACTOR.pinned_json(normal, "A" * 64)

            duplicate = root / "duplicate.json"
            duplicate_raw = b'{"value":1,"value":2}'
            duplicate.write_bytes(duplicate_raw)
            duplicate_hash = hashlib.sha256(duplicate_raw).hexdigest().upper()
            with self.assertRaisesRegex(ACTOR.InputError, "duplicate JSON member"):
                ACTOR.pinned_json(duplicate, duplicate_hash)

            oversize = root / "oversize.json"
            oversize_raw = b"{" + b" " * 8191 + b"}"
            oversize.write_bytes(oversize_raw)
            oversize_hash = hashlib.sha256(oversize_raw).hexdigest().upper()
            with self.assertRaisesRegex(ACTOR.InputError, "input file differs"):
                ACTOR.pinned_json(oversize, oversize_hash)

    def test_main_keeps_the_accepted_trace_when_final_engine_hash_refuses(self):
        spec = valid_spec("escape")
        binding = valid_binding(spec)
        backend = MockBackend(spec, binding)

        def final_hash():
            raise ACTOR.InputError("engine changed during input")

        status, receipt = self.invoke_main(
            spec, binding, backend=backend, final_hash=final_hash
        )
        self.assertEqual(status, 1)
        self.assertEqual(receipt["status"], "refused")
        self.assertFalse(receipt["native_gui_acceptance"])
        self.assertEqual(receipt["error"], "engine changed during input")
        self.assertEqual(backend.close_calls, 1)
        self.assertEqual(
            [(row["api"], row["accepted_by_xtest"]) for row in receipt["trace"]],
            [("XTestFakeKeyEvent", True), ("XTestFakeKeyEvent", True)],
        )

    def test_main_keeps_the_accepted_trace_when_connection_close_refuses(self):
        spec = valid_spec("escape")
        binding = valid_binding(spec)
        backend = MockBackend(spec, binding, close_error=RuntimeError("synthetic close error"))
        status, receipt = self.invoke_main(spec, binding, backend=backend)
        self.assertEqual(status, 1)
        self.assertEqual(receipt["status"], "refused")
        self.assertFalse(receipt["native_gui_acceptance"])
        self.assertEqual(receipt["error"], "X connection close failed")
        self.assertEqual(receipt["connection_close_error"], "RuntimeError")
        self.assertEqual(backend.close_calls, 1)
        self.assertEqual(
            [(row["api"], row["accepted_by_xtest"]) for row in receipt["trace"]],
            [("XTestFakeKeyEvent", True), ("XTestFakeKeyEvent", True)],
        )


if __name__ == "__main__":
    unittest.main()
