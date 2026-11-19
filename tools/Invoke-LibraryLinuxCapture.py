"""Capture one hash-bound private-X window without focusing or injecting input."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import types

def load_checked_module(path, expected_hash, name):
    if not path.is_file() or path.is_symlink():
        raise ValueError('capture helper must be a regular source file')
    raw = path.read_bytes()
    if len(expected_hash) != 64 or hashlib.sha256(raw).hexdigest().upper() != expected_hash.upper():
        raise ValueError('capture helper source hash differs')
    helper = types.ModuleType(name)
    helper.__file__ = str(path)
    # Compile the bytes already verified, without rereading a replaceable path.
    exec(compile(raw, str(path), 'exec'), helper.__dict__)
    return helper


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spec-path', required=True, type=Path)
    parser.add_argument('--spec-sha256', required=True)
    parser.add_argument('--binding-path', required=True, type=Path)
    parser.add_argument('--binding-sha256', required=True)
    parser.add_argument('--input-helper-sha256', required=True)
    parser.add_argument('--window-helper-sha256', required=True)
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    result = {'kind': 'MIRLinuxLibraryCaptureReceiptV1', 'status': 'refused',
              'native_gui_acceptance': False, 'input_events': 0, 'focus_changes': 0}
    try:
        tool_root = Path(__file__).resolve().parent
        helper = load_checked_module(tool_root / 'Invoke-LibraryNativeInputLinux.py',
                                     args.input_helper_sha256, 'mir_linux_capture_input_helper')
        window = load_checked_module(tool_root / 'lib/validation/LinuxLibraryWindow.py',
                                     args.window_helper_sha256, 'mir_linux_capture_window_helper')
        spec = helper.pinned_json(args.spec_path, args.spec_sha256)
        binding = helper.pinned_json(args.binding_path, args.binding_sha256)
        window.validate_spec(spec, binding, helper)
        if args.validate_only:
            result['status'] = 'validated-schema-only'
            result['process_identity_checked'] = False
        else:
            result = window.capture(spec, binding, helper)
        result['input_helper_sha256'] = args.input_helper_sha256.upper()
        result['window_helper_sha256'] = args.window_helper_sha256.upper()
    except Exception as error:
        result['error'] = str(error)[:512]
    print(json.dumps(result, sort_keys=True))
    return 1 if result['status'] == 'refused' else 0


if __name__ == '__main__':
    sys.exit(main())
