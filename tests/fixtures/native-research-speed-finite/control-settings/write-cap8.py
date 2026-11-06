"""Encode this exact captured F210 startup map with only cap8 changed.

Only text/tree are reused from the historical writer; its origin-specific CLI
is not invoked. Native2.1.23 readback remains mandatory.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

def text(value):
    raw = value.encode('utf-8')
    assert len(raw) < 255
    if not raw:
        return b'\x01'
    return b'\0' + bytes([len(raw)]) + raw

def tree(value):
    if type(value) is bool:
        return b'\x01\0' + bytes([value])
    if type(value) in (int,float):
        assert value == value and abs(value) <= 2**53
        return b'\x02\0' + struct.pack('<d',value)
    if type(value) is str:
        return b'\x03\0' + text(value)
    assert type(value) is dict
    return b'\x05\0' + struct.pack('<I', len(value)) + b''.join(
        text(key) + tree(child) for key, child in sorted(value.items()))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--startup", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    raw = args.startup.read_bytes()
    assert hashlib.sha256(raw).hexdigest().upper() == "0E0011C794B80EADC68B866A60C2846089B5A3FAA490BADF8C8139A2B4D3F89C"
    values = json.loads(raw)
    assert len(values) == 889 and values["mir-max-level-research-speed"] == 0
    values["mir-max-level-research-speed"] = 8
    body = struct.pack("<4H?", 2, 1, 23, 0, False) + tree({
        "startup": {key: {"value": value} for key, value in values.items()},
        "runtime-global": {}, "runtime-per-user": {}})
    with args.output.open("xb") as stream:
        stream.write(body)
    print(json.dumps({"bytes": len(body), "sha256": hashlib.sha256(body).hexdigest().upper(),
                      "native_readback": "pending"}))
