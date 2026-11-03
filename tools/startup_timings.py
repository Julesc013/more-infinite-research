"""Read native startup timestamps offline; never launches Factorio or predicts time."""
from __future__ import annotations

import argparse
import base64
import csv
from decimal import Decimal
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys

STAMP = re.compile(r"^\s*(\d+\.\d+)\s+(.*)$")
LOADER = re.compile(r"^Loading mod(?: settings)? (\S+) (\S+) \(([^()]+\.lua)\)$")
MARKER = re.compile(r"(?:^|: )\[MIR startup\] stage=([\w-]+) phase=([\w-]+) event=(begin|end|work)(?: |$)")
MILESTONE = re.compile(r"^(?:Checksum (?:for|of) |Prototype list checksum:|Factorio initialised\b|Crop bitmaps\.|Loading sprites|Created an atlas bitmap)")
STAGES = ("settings", "settings-updates", "settings-final-fixes", "data", "data-updates", "data-final-fixes")


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest().upper()


def analyze(raw: bytes, run_id: str) -> dict:
    """Elapsed regions include synchronous engine calls/scheduling, not exclusive CPU."""
    entries = []
    for line_number, line in enumerate(raw.decode("utf-8-sig").splitlines(), 1):
        match = STAMP.match(line)
        if match:
            entries.append((Decimal(match[1]), match[2], line_number))
    issues = []
    monotonic = all(a[0] <= b[0] for a, b in zip(entries, entries[1:]))
    if not monotonic:
        issues.append("native timestamps regress; joined/restarted logs are not one clock")
    loaders, phases, checkpoints, roots, stack, seen = [], [], {}, [], [], set()
    last_stage_end = None
    for index, (when, message, line) in enumerate(entries):
        load = LOADER.match(message)
        if load and load[1] == "more-infinite-research":
            boundary = next((row for row in entries[index + 1:]
                             if LOADER.match(row[1]) or MILESTONE.match(row[1])), None)
            loaders.append(dict(stage=load[3], version=load[2], begin_line=line,
                                end_line=boundary[2] if boundary else None,
                                end_boundary=boundary[1] if boundary else None,
                                seconds=float(boundary[0] - when) if boundary and monotonic else None,
                                status="approximate" if boundary and monotonic else "unavailable"))
        mark = MARKER.search(message)
        if not mark:
            continue
        stage, phase, event = mark.groups()
        checkpoints.setdefault(stage, []).append(when)
        key = (stage, phase)
        if event == "work":
            continue
        if event == "begin":
            if key in seen:
                issues.append("duplicate phase: " + "/".join(key))
            seen.add(key)
            stack.append((key, when, line, len(stack)))
        elif not stack or stack[-1][0] != key:
            issues.append("unmatched end: " + "/".join(key))
        else:
            _, begin, begin_line, depth = stack.pop()
            row = dict(stage=stage, phase=phase, begin_line=begin_line, end_line=line,
                       seconds=float(when - begin) if monotonic else None, depth=depth,
                       status="complete" if monotonic else "unavailable")
            phases.append(row)
            if depth == 0:
                roots.append(row)
            if phase == "stage" and stage == "data-final-fixes":
                last_stage_end = (when, index)
    for (stage, phase), _, line, depth in stack:
        phases.append(dict(stage=stage, phase=phase, begin_line=line, end_line=None,
                           seconds=None, depth=depth, status="incomplete"))
        issues.append("missing end: " + stage + "/" + phase)
    intervals_valid = bool(roots) and not issues
    gaps = [b - a for times in checkpoints.values() for a, b in zip(times, times[1:])]
    post = None
    if last_stage_end and intervals_valid:
        boundary = next((row for row in entries[last_stage_end[1] + 1:]
                         if MILESTONE.match(row[1]) or LOADER.match(row[1])), None)
        if boundary:
            post = dict(seconds=float(boundary[0] - last_stage_end[0]), boundary=boundary[1],
                        end_line=boundary[2], attribution="after MIR; not exclusive MIR work")
    initialized = [when for when, message, _ in entries if message == "Factorio initialised"]
    stage_windows = {}
    for stage in STAGES:
        intervals = [r for r in loaders if r["stage"] == stage + ".lua"]
        stage_windows["approximate_" + stage.replace("-", "_") + "_seconds"] = (
            intervals[0]["seconds"] if len(intervals) == 1 else None)
    return dict(stage_windows, run_id=run_id, log_bytes=len(raw), log_sha256=digest(raw),
                clock="native-log elapsed seconds; separate from actor Stopwatch",
                engine_initialised_seconds=float(initialized[0]) if len(initialized) == 1 and monotonic else None,
                approximate_loader_intervals=loaders,
                loader_status=("not-present" if not loaders else
                               "approximate" if all(r["seconds"] is not None for r in loaders) else "unavailable"),
                loader_warnings=["unavailable loader boundary: " + r["stage"] for r in loaders if r["seconds"] is None],
                approximate_loader_seconds=round(sum(r["seconds"] for r in loaders), 9)
                if loaders and all(r["seconds"] is not None for r in loaders) else None,
                phases=phases,
                scoped_seconds=round(sum(r["seconds"] for r in roots), 9) if intervals_valid else None,
                scoped_status="complete" if intervals_valid else "unavailable",
                longest_observed_checkpoint_gap_seconds=float(max(gaps)) if gaps and intervals_valid else None,
                post_mir_to_next_milestone=post, issues=issues,
                limits=["Printed timestamp resolution is not measurement accuracy; rounded zero is not zero work.",
                        "Loader intervals include inter-script bookkeeping; marker regions are elapsed, not pure CPU.",
                        "No responsive-menu, incremental overhead, deadlock or future-hardware inference."])


def snapshot_rows(snapshot_path: Path, capsule_path: Path) -> list[dict]:
    """Re-extract the existing exploratory snapshot without changing its identities."""
    snapshot_raw, capsule_raw = snapshot_path.read_bytes(), capsule_path.read_bytes()
    snapshot = json.loads(snapshot_raw)
    bodies = json.loads(gzip.decompress(capsule_raw))["bodies"]
    def original(ref):
        row = bodies[ref["path"]]
        raw = base64.b64decode(row["base64"], validate=True)
        if len(raw) != row["bytes"] or digest(raw) != row["sha256"].upper():
            raise ValueError("capsule body identity mismatch: " + ref["path"])
        if len(raw) != ref["bytes"] or digest(raw) != ref["sha256"].upper():
            raise ValueError("snapshot reference mismatch: " + ref["path"])
        return raw
    results, seen = [], set()
    for group in snapshot["groups"]:
        for row in group["rows"]:
            ref = row.get("raw_log")
            run_id = group["cohort"] + "/" + row["arm"]
            if run_id in seen:
                raise ValueError("duplicate run identity: " + run_id)
            seen.add(run_id)
            result = analyze(original(ref), run_id) if ref else dict(run_id=run_id, issues=["missing original log"], phases=[])
            result.update(engine=group["engine"], workload=group["workload"],
                          archive_version=row["archive_version"], arm=row["arm"],
                          original_observation_kind=group["observation_kind"],
                          original_menu_status=row.get("menu_status"),
                          original_first_menu_seconds=row.get("first_menu_seconds"),
                          original_confirmed_settings_seconds=row.get("confirmed_settings_seconds"),
                          original_log_path=ref["path"] if ref else None,
                          original_source_commit=snapshot["source_commit"],
                          snapshot_sha256=digest(snapshot_raw), capsule_sha256=digest(capsule_raw),
                          cache_policy="uncontrolled, no reboot/cache clear; original single-pass order",
                          analysis_class="retrospective descriptive only; not a matched MIR-added estimate")
            if ref and result["engine_initialised_seconds"] != row.get("engine_initialised_log_seconds"):
                raise ValueError("initialization endpoint differs from original: " + run_id)
            actor_ref = row.get("raw_menu_actor")
            if actor_ref:
                actor = json.loads(original(actor_ref))
                observation = actor.get("observation") or {}
                for field, actor_field in (("first_menu_seconds", "first_render_observed_seconds"),
                                           ("confirmed_settings_seconds", "confirmed_response_seconds")):
                    if row.get(field) != observation.get(actor_field):
                        raise ValueError("actor endpoint differs: " + run_id + "/" + field)
            results.append(result)
    return results


def comparison_rows(chain_path: Path, capsule_path: Path) -> list[dict]:
    """Read the two existing Base/heavy comparison formats; no new experiment."""
    chain_raw, capsule_raw = chain_path.read_bytes(), capsule_path.read_bytes()
    chain = json.loads(chain_raw)
    pin = chain["receipt_capsule"]
    if len(capsule_raw) != pin["bytes"] or digest(capsule_raw) != pin["sha256"]:
        raise ValueError("comparison capsule identity mismatch")
    capsule = json.loads(gzip.decompress(capsule_raw))
    members = capsule.get("files", capsule.get("records"))
    bodies = {r["path"]: r for r in members}
    if len(bodies) != len(members):
        raise ValueError("duplicate capsule path")
    def original(path):
        row = bodies[path]
        key = "base64" if "base64" in row else "raw_utf8_base64"
        raw = base64.b64decode(row[key], validate=True)
        if len(raw) != row["bytes"] or digest(raw) != row["sha256"]:
            raise ValueError("comparison body identity mismatch: " + path)
        return raw
    if chain["kind"] == "MIRCandidate502BaseF200StartupCompletionChainV1":
        source, engine, workload = chain["candidate"]["source"], chain["engine"]["version"], "Base"
        prefix = "native-output/native/"
        result = original(prefix + "result.json")
        if digest(result) != chain["original_result_sha256"]:
            raise ValueError("original result identity mismatch")
        observations = [(r["plan"], r["observation"],
                         prefix + r["observation"]["run_relative_path"] + "/factorio.log",
                         prefix + r["observation"]["responsive_menu_actor"]["path"])
                        for r in json.loads(result)["samples"]]
    elif chain["kind"] == "MIRCurrent38cCompleteMenuComparisonNativeChainV1":
        source, engine, workload = chain["candidate_source"], chain["inputs"]["factorio"]["base_version"], "Heavy Space Age"
        observations = [(r["schedule"], r, r["native_log"]["path"], r["actor"]["path"])
                        for r in chain["observations"]]
    else:
        raise ValueError("unsupported retained comparison kind")
    results, seen = [], set()
    for plan, observation, log_path, actor_path in observations:
        run_id = chain_path.stem + "/" + str(plan["ordinal"])
        if run_id in seen:
            raise ValueError("duplicate comparison run")
        seen.add(run_id)
        raw, actor = original(log_path), json.loads(original(actor_path))
        observed = actor["observation"]
        if observed["confirmed_response_seconds"] != observation["elapsed_seconds"]:
            raise ValueError("original actor endpoint differs: " + run_id)
        versions = {m[2] for line in raw.decode("utf-8-sig").splitlines()
                    if (stamp := STAMP.match(line)) and (m := LOADER.match(stamp[2]))
                    and m[1] == "more-infinite-research"}
        if len(versions) > 1:
            raise ValueError("multiple loaded MIR versions: " + run_id)
        row = analyze(raw, run_id)
        row.update(engine=engine, workload=workload, archive_version=next(iter(versions), None),
                   arm=plan["arm"], phase=plan["phase"], block=plan["block"],
                   original_menu_status=observed["status"], original_observation_kind="ordinary-responsive-menu",
                   original_first_menu_seconds=observed["first_render_observed_seconds"],
                   original_confirmed_settings_seconds=observation["elapsed_seconds"], original_log_path=log_path,
                   original_source_commit=source, snapshot_sha256=digest(chain_raw), capsule_sha256=digest(capsule_raw),
                   cache_policy="original matched campaign policy; retain warmup/pilot/block distinction",
                   analysis_class="scoped attribution only; original matched verdict/uncertainty unchanged")
        results.append(row)
    return results


CSV_FIELDS = ["run_id", "engine", "workload", "archive_version", "arm", "phase", "block", "original_menu_status",
              "original_observation_kind",
              "original_first_menu_seconds", "original_confirmed_settings_seconds",
              "engine_initialised_seconds", "approximate_loader_seconds", "scoped_seconds", "scoped_status",
              *["approximate_" + stage.replace("-", "_") + "_seconds" for stage in STAGES],
              "loader_status", "loader_warnings", "issues",
              "longest_observed_checkpoint_gap_seconds", "log_bytes", "log_sha256", "original_log_path",
              "original_source_commit", "snapshot_sha256", "capsule_sha256", "cache_policy", "analysis_class"]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--log", type=Path)
    choice.add_argument("--snapshot", type=Path)
    choice.add_argument("--comparison", type=Path, help="existing Base/heavy comparison chain")
    parser.add_argument("--bodies", type=Path, help="retained snapshot body capsule")
    parser.add_argument("--run-id")
    parser.add_argument("--expected-sha256")
    parser.add_argument("--json", type=Path)
    parser.add_argument("--csv", type=Path)
    args = parser.parse_args()
    if args.snapshot or args.comparison:
        if not args.bodies or args.expected_sha256 or args.run_id:
            parser.error("--snapshot/--comparison need --bodies; --run-id/--expected-sha256 apply to --log")
        rows = snapshot_rows(args.snapshot, args.bodies) if args.snapshot else comparison_rows(args.comparison, args.bodies)
    else:
        if args.bodies:
            parser.error("--bodies requires --snapshot or --comparison")
        raw = args.log.read_bytes()
        if args.expected_sha256 and digest(raw) != args.expected_sha256.upper():
            parser.error("log SHA256 mismatch")
        rows = [analyze(raw, args.run_id or args.log.name)]
    if args.json and args.csv and args.json.resolve() == args.csv.resolve():
        parser.error("JSON and CSV outputs must differ")
    # Never overwrite original evidence (including an accidentally selected log).
    for path in (args.json, args.csv):
        if path and path.exists():
            parser.error("output already exists: " + str(path))
    output = json.dumps(rows, indent=2, ensure_ascii=False) + "\n"
    if args.json:
        with args.json.open("x", encoding="utf-8") as handle:
            handle.write(output)
    if args.csv:
        with args.csv.open("x", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS, extrasaction="ignore", lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
    if not args.json and not args.csv:
        sys.stdout.write(output)


if __name__ == "__main__":
    main()
