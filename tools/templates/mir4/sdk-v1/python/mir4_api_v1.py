"""MIR 4 API V1 package-excluded developer-preview binding."""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import re
import tempfile
import zipfile
from pathlib import Path
from typing import Any, Iterable

SURFACES = frozenset(("continuity-bundle","host-manifest","observation","profile","proof","query","release","target-provider-abi","tooling"))
REQUIRED = frozenset(("availability","canonicalization","capabilities","digest","extensions","items","kind","mutation_authorized","package_visible","page","public_support_claim","schema","source_identity","surface","target","versions"))
MAX_PAGE_ITEMS = 128
MAX_CAPABILITIES = 128
MAX_EXTENSIONS = 32


class SdkError(ValueError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _load_canonical_module() -> Any:
    path = Path(__file__).resolve().parents[2] / "canonical-json-v1" / "python" / "mir4_canonical_json_v1.py"
    if not path.is_file():
        raise SdkError("mir4-sdk-canonical-module-missing")
    spec = importlib.util.spec_from_file_location("mir4_canonical_json_v1", path)
    if spec is None or spec.loader is None:
        raise SdkError("mir4-sdk-canonical-module-missing")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_canon = _load_canonical_module()


def parse(raw_json: str) -> dict[str, Any]:
    value = _canon.parse(raw_json)
    if not isinstance(value, dict):
        raise SdkError("mir4-api-v1-schema")
    return value


def canonicalize(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return _canon.canonicalize(raw)


def digest(value: dict[str, Any]) -> str:
    material = {key: child for key, child in value.items() if key != "digest"}
    return _canon.digest(json.dumps(material, ensure_ascii=False, separators=(",", ":")), "mir4:api-response-v1")


def _ordinal_set(values: Iterable[Any], code: str) -> list[str]:
    result = [str(value) for value in values]
    if result != sorted(set(result), key=lambda item: item.encode("utf-16-be")):
        raise SdkError(code)
    return result


def validate(value: dict[str, Any]) -> dict[str, Any]:
    if set(value) != REQUIRED or value.get("kind") != "MIR4ApiResponseV1" or value.get("schema") != 1:
        raise SdkError("mir4-api-v1-schema")
    if value.get("surface") not in SURFACES:
        raise SdkError("mir4-api-v1-surface")
    target = value.get("target")
    if not isinstance(target, dict) or set(target) != {"id","factorio_line","transport"}:
        raise SdkError("mir4-api-v1-target")
    if not re.fullmatch(r"f[0-9]{3}", str(target.get("id",""))) or not re.fullmatch(r"[0-9]+\.[0-9]+", str(target.get("factorio_line",""))) or not target.get("transport"):
        raise SdkError("mir4-api-v1-target")
    versions = value.get("versions")
    if not isinstance(versions, dict) or not versions.get("source") or not versions.get("distribution"):
        raise SdkError("mir4-api-v1-version")
    if value.get("canonicalization") != "mir-canonical-json/1":
        raise SdkError("mir4-api-v1-canonicalization")
    if value.get("package_visible") is not False or value.get("mutation_authorized") is not False or value.get("public_support_claim") is not False:
        raise SdkError("mir4-api-v1-authority-boundary")
    capabilities = value.get("capabilities")
    if not isinstance(capabilities, list) or len(capabilities) > MAX_CAPABILITIES:
        raise SdkError("mir4-api-v1-capability-cardinality")
    _ordinal_set(capabilities, "mir4-api-v1-capability-order")
    if any(not re.fullmatch(r"[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*", capability) for capability in capabilities):
        raise SdkError("mir4-api-v1-capability")
    availability = value.get("availability")
    if not isinstance(availability, dict) or set(availability) != {"status","reason","evidence"} or availability.get("status") not in ("available","unavailable") or not availability.get("reason"):
        raise SdkError("mir4-api-v1-availability")
    if not isinstance(availability.get("evidence"), list):
        raise SdkError("mir4-api-v1-availability")
    _ordinal_set(availability["evidence"], "mir4-api-v1-evidence-order")
    page = value.get("page")
    items = value.get("items")
    if not isinstance(page, dict) or set(page) != {"offset","limit","returned","total","next_cursor"} or not isinstance(items, list):
        raise SdkError("mir4-api-v1-page")
    offset, limit, returned = page.get("offset"), page.get("limit"), page.get("returned")
    if type(offset) is not int or type(limit) is not int or type(returned) is not int or offset < 0 or limit < 1 or limit > MAX_PAGE_ITEMS or returned < 0 or returned > limit:
        raise SdkError("mir4-api-v1-page")
    if returned != len(items):
        raise SdkError("mir4-api-v1-returned-count")
    total = page.get("total")
    if total is not None and (type(total) is not int or total < 0 or offset + returned > total):
        raise SdkError("mir4-api-v1-page")
    cursor = page.get("next_cursor")
    if cursor is not None and not re.fullmatch(r"[0-9]+", str(cursor)):
        raise SdkError("mir4-api-v1-cursor")
    if availability["status"] == "unavailable" and (total is not None or returned != 0 or items or cursor is not None):
        raise SdkError("mir4-api-v1-unavailable-is-not-zero")
    extensions = value.get("extensions")
    if not isinstance(extensions, dict) or len(extensions) > MAX_EXTENSIONS:
        raise SdkError("mir4-api-v1-extension-cardinality")
    if any(not re.fullmatch(r"[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+", key) for key in extensions):
        raise SdkError("mir4-api-v1-extension-namespace")
    if value.get("digest") != digest(value):
        raise SdkError("mir4-api-v1-digest")
    return value


def negotiate_capabilities(value: dict[str, Any], requested: Iterable[str] = (), required: Iterable[str] = ()) -> dict[str, list[str]]:
    offered = list(validate(value)["capabilities"])
    request = list(requested) or offered
    selected = sorted(set(request).intersection(offered), key=lambda item: item.encode("utf-16-be"))
    missing = sorted(set(required).difference(offered), key=lambda item: item.encode("utf-16-be"))
    if missing:
        raise SdkError("mir4-api-v1-capability-required")
    return {"offered": offered, "selected": selected, "missing": []}


def decode_availability(value: dict[str, Any]) -> dict[str, Any]:
    availability = validate(value)["availability"]
    return {"available": availability["status"] == "available", **copy.deepcopy(availability)}


def bounded_page(value: dict[str, Any], expected_cursor: str | None = None) -> dict[str, Any]:
    response = validate(value)
    if expected_cursor is not None and expected_cursor != str(response["page"]["offset"]):
        raise SdkError("mir4-api-v1-cursor-mismatch")
    return {"items": copy.deepcopy(response["items"]), **copy.deepcopy(response["page"])}


def compare_snapshots(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    left, right = validate(before), validate(after)
    if left["surface"] != right["surface"] or left["target"]["id"] != right["target"]["id"]:
        raise SdkError("mir4-api-v1-snapshot-identity")
    items_changed = canonicalize(left["items"]) != canonicalize(right["items"])
    return {"equal": not items_changed and left["digest"] == right["digest"], "before_digest": left["digest"], "after_digest": right["digest"], "items_changed": items_changed}


def render_diagnostic(diagnostic: dict[str, Any], registry_path: Path | None = None) -> str:
    path = registry_path or Path(__file__).resolve().parents[1] / "diagnostics.json"
    registry = json.loads(path.read_text(encoding="utf-8"))
    if diagnostic.get("code") not in {row["code"] for row in registry["diagnostics"]}:
        raise SdkError("mir4-api-v1-diagnostic-code")
    return f"[{diagnostic['code']}] {diagnostic.get('path') or '$'} {diagnostic.get('message','')}".strip()


def validate_extension(extension: dict[str, Any]) -> dict[str, Any]:
    required = {"kind","schema","extension_id","extension_version","namespace","targets","fragments","canonicalization","digest"}
    if set(extension) != required or extension.get("kind") != "MIR4ExtensionEnvelopeV1" or extension.get("schema") != 1 or extension.get("canonicalization") != "mir-canonical-json/1":
        raise SdkError("mir4-mep-v1-schema")
    forbidden = {"callback","callbacks","compiler_context","data_raw","executor","prototype","prototype_write","safety_kernel","safety_kernel_override"}
    def scan(child: Any) -> None:
        if isinstance(child, dict):
            if forbidden.intersection(child):
                raise SdkError("mir4-mep-v1-forbidden-field")
            for value in child.values():
                scan(value)
        elif isinstance(child, list):
            for value in child:
                scan(value)
    scan(extension)
    material = {key: child for key, child in extension.items() if key != "digest"}
    expected = _canon.digest(json.dumps(material, ensure_ascii=False, separators=(",", ":")), "mir4:extension-envelope-v1")
    if extension.get("digest") != expected:
        raise SdkError("mir4-mep-v1-digest")
    return extension


def verify_manifest(manifest: dict[str, Any], root: Path) -> bool:
    resolved = root.resolve(strict=True)
    rows = manifest.get("files")
    if not isinstance(rows, list) or not rows:
        raise SdkError("mir4-api-v1-manifest-empty")
    seen: set[str] = set()
    for row in rows:
        relative = str(row.get("path","")).replace("\\","/")
        if not relative or relative.startswith("/") or re.match(r"^[A-Za-z]:", relative) or ".." in Path(relative).parts or ":" in relative or relative in seen:
            raise SdkError("mir4-api-v1-manifest-path")
        seen.add(relative)
        path = (resolved / relative).resolve(strict=True)
        if resolved not in path.parents:
            raise SdkError("mir4-api-v1-manifest-path")
        payload = path.read_bytes()
        if row.get("bytes") != len(payload) or row.get("sha256") != hashlib.sha256(payload).hexdigest():
            raise SdkError("mir4-api-v1-manifest-digest")
    return True


def verify_archive(archive: Path) -> bool:
    with tempfile.TemporaryDirectory(prefix="mir4-sdk-v1-") as temporary:
        destination = Path(temporary)
        with zipfile.ZipFile(archive) as bundle:
            for entry in bundle.infolist():
                path = Path(entry.filename)
                if path.is_absolute() or ".." in path.parts or ":" in entry.filename:
                    raise SdkError("mir4-api-v1-archive-path")
            bundle.extractall(destination)
        roots = [path for path in destination.iterdir() if path.is_dir()]
        if len(roots) != 1:
            raise SdkError("mir4-api-v1-archive-root")
        manifest_path = roots[0] / "manifest.json"
        if not manifest_path.is_file():
            raise SdkError("mir4-api-v1-archive-manifest")
        return verify_manifest(json.loads(manifest_path.read_text(encoding="utf-8")), roots[0])


def run_conformance(path: Path) -> dict[str, Any]:
    corpus = json.loads(path.read_text(encoding="utf-8"))
    accepted: list[str] = []
    rejected: list[str] = []
    failures: list[str] = []
    digests: dict[str, str] = {}
    for case in corpus["positive"]:
        try:
            value = validate(parse(case["input_json"]))
            accepted.append(case["id"])
            digests[case["id"]] = value["digest"]
            if value["digest"] != case["digest"] or canonicalize(value) != case["canonical_json"]:
                failures.append(case["id"] + ":identity")
        except (SdkError, ValueError) as error:
            failures.append(case["id"] + ":" + str(error))
    for case in corpus["negative"]:
        try:
            validate(parse(case["input_json"]))
            failures.append(case["id"] + ":accepted")
        except (SdkError, ValueError) as error:
            rejected.append(case["id"])
            code = getattr(error, "code", str(error))
            if code != case["diagnostic"]:
                failures.append(case["id"] + ":" + code)
    return {"schema":1,"kind":"MIR4SdkV1RuntimeConformanceResult","runtime":"python","accepted":accepted,"rejected":rejected,"digests":digests,"failures":failures,"passed":not failures}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--conformance", type=Path)
    parser.add_argument("--verify-archive", type=Path)
    args = parser.parse_args()
    if args.conformance:
        result = run_conformance(args.conformance)
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":"), sort_keys=True))
        return 0 if result["passed"] else 1
    if args.verify_archive:
        verify_archive(args.verify_archive)
        print('{"passed":true,"runtime":"python"}')
        return 0
    raise SdkError("mir4-sdk-v1-command")


if __name__ == "__main__":
    raise SystemExit(main())
