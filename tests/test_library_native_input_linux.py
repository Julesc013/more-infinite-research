"""Independent mock controls for the narrow Linux Library input leaf.

These controls exercise the hash-bound actor's public leaf functions only.  They
do not open X, start Factorio, inspect /proc, or mutate a mod library.
"""
import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
ACTOR_PATH = ROOT / "tools" / "Invoke-LibraryNativeInputLinux.py"
SPEC = importlib.util.spec_from_file_location("mir_linux_library_input", ACTOR_PATH)
ACTOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ACTOR)


ENGINE_SHA = "A" * 64


def valid_spec(action="escape", **changes):
    spec = {
        "schema": 1,
        "kind": "MIRLibraryNativeInputV1",
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

    keycodes = {"Escape": 9, "Tab": 23, "Shift_L": 50, "e": 26,
                "A": 38, "z": 52, " ": 65}

    def __init__(self, spec, binding, *, stolen_focus=False, mapped=True,
                 title="Factorio 2.1", pid=None, bounds=None, modifiers=0,
                 group=0, reject=None):
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
        self.events = []
        self.focused_window = None

    def window(self, binding, spec):
        return {"pid": self.pid, "bounds": list(self.bounds),
                "mapped": self.mapped, "title": self.title}

    def focus(self, window):
        self.events.append(("focus", window))
        if not self.stolen_focus:
            self.focused_window = window

    def focused(self):
        return self.focused_window

    def modifiers(self):
        return self.modifier_mask

    def keyboard_group(self):
        return self.group

    def keycode(self, symbol):
        return self.keycodes[symbol], symbol == "A"

    def key(self, code, down):
        self.events.append(("key", code, down))
        return 0 if self.reject == "key" else 1

    def motion(self, x, y):
        self.events.append(("motion", x, y))
        return 0 if self.reject == "motion" else 1

    def button(self, down):
        self.events.append(("button", down))
        return 0 if self.reject == "button" else 1

    def sync(self):
        self.events.append(("sync",))


class LibraryNativeInputLinuxTests(unittest.TestCase):
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
             ("button", True), ("sync",), ("button", False), ("sync",)],
        )
        self.assertEqual([row["api"] for row in trace], [
            "XTestFakeMotionEvent", "XTestFakeButtonEvent", "XTestFakeButtonEvent"
        ])
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
                         [("button", True), ("button", False)])
        self.assertEqual([row["api"] for row in trace].count("XTestFakeMotionEvent"), 5)
        self.assertEqual([row["api"] for row in trace].count("XTestFakeButtonEvent"), 2)

    def test_stolen_focus_or_changed_owned_window_refuses_before_an_input_event(self):
        spec = valid_spec("escape")
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
        spec = valid_spec("escape")
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


if __name__ == "__main__":
    unittest.main()
