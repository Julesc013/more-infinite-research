"""Independent Python reference for the package-excluded mir-canonical-json/1 contract."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import unicodedata
from pathlib import Path
from typing import Any

MAX_SAFE_INTEGER = 9_007_199_254_740_991
MAX_DEPTH = 64


class CanonError(ValueError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _normalize(value: str) -> str:
    if any(0xD800 <= ord(char) <= 0xDFFF for char in value):
        raise CanonError("mir4-canon-invalid-unicode")
    return unicodedata.normalize("NFC", value)


def _parse_int(raw: str) -> int:
    if raw == "-0":
        raise CanonError("mir4-canon-negative-zero")
    value = int(raw)
    if value < -MAX_SAFE_INTEGER or value > MAX_SAFE_INTEGER:
        raise CanonError("mir4-canon-unsafe-integer")
    return value


def _parse_float(_: str) -> float:
    raise CanonError("mir4-canon-unsupported-number")


def _parse_constant(_: str) -> None:
    raise CanonError("mir4-canon-invalid-json")


def _object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    originals: dict[str, str] = {}
    for raw_key, value in pairs:
        key = _normalize(raw_key)
        if key in result:
            code = "mir4-canon-duplicate-key" if originals[key] == raw_key else "mir4-canon-unicode-key-collision"
            raise CanonError(code)
        result[key] = value
        originals[key] = raw_key
    return result


def _normalize_values(value: Any, depth: int = 0) -> Any:
    if depth > MAX_DEPTH:
        raise CanonError("mir4-canon-depth")
    if isinstance(value, str):
        return _normalize(value)
    if isinstance(value, list):
        return [_normalize_values(item, depth + 1) for item in value]
    if isinstance(value, dict):
        return {key: _normalize_values(child, depth + 1) for key, child in value.items()}
    return value


def parse(raw_json: str) -> Any:
    if raw_json.startswith("\ufeff"):
        raise CanonError("mir4-canon-utf8-bom")
    try:
        value = json.loads(
            raw_json,
            object_pairs_hook=_object_pairs,
            parse_int=_parse_int,
            parse_float=_parse_float,
            parse_constant=_parse_constant,
        )
    except CanonError:
        raise
    except (json.JSONDecodeError, RecursionError, UnicodeError) as error:
        if "maximum recursion" in str(error).lower():
            raise CanonError("mir4-canon-depth") from error
        raise CanonError("mir4-canon-invalid-json") from error
    return _normalize_values(value)


def _encode_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _encode(value: Any) -> str:
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return _encode_string(value)
    if isinstance(value, list):
        return "[" + ",".join(_encode(item) for item in value) + "]"
    if isinstance(value, dict):
        keys = sorted(value, key=lambda key: key.encode("utf-16-be"))
        return "{" + ",".join(_encode_string(key) + ":" + _encode(value[key]) for key in keys) + "}"
    raise CanonError("mir4-canon-invalid-json")


def canonicalize(raw_json: str) -> str:
    return _encode(parse(raw_json))


def digest(raw_json: str, domain: str) -> str:
    if not domain.startswith("mir4:"):
        raise CanonError("mir4-canon-digest-domain")
    material = ("mir-canonical-json/1\0" + domain + "\0" + canonicalize(raw_json)).encode("utf-8")
    return "sha256:" + hashlib.sha256(material).hexdigest()


def run_vectors(path: Path) -> dict[str, Any]:
    corpus = json.loads(path.read_text(encoding="utf-8"))
    failures: list[str] = []
    for vector in corpus["positive"]:
        try:
            actual = canonicalize(vector["input_json"])
            if actual != vector["canonical_json"]:
                failures.append(vector["id"] + ":canonical")
        except CanonError as error:
            failures.append(vector["id"] + ":" + error.code)
    for vector in corpus["negative"]:
        try:
            canonicalize(vector["input_json"])
            failures.append(vector["id"] + ":accepted")
        except CanonError as error:
            if error.code != vector["diagnostic"]:
                failures.append(vector["id"] + ":" + error.code)
    return {
        "kind": "MIR4CanonicalJsonV1CrossRuntimeResult",
        "schema": 1,
        "runtime": "python",
        "positive": len(corpus["positive"]),
        "negative": len(corpus["negative"]),
        "failures": failures,
        "passed": not failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vectors", type=Path)
    parser.add_argument("--domain")
    args = parser.parse_args()
    if args.vectors:
        result = run_vectors(args.vectors)
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":"), sort_keys=True))
        return 0 if result["passed"] else 1
    raw = sys.stdin.read()
    print(digest(raw, args.domain) if args.domain else canonicalize(raw))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
