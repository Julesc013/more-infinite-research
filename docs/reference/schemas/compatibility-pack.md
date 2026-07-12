---
title: "CompatibilityPack Schema"
status: current
applies_to: "3.1.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# CompatibilityPack Schema

A schema-2 `CompatibilityPack` is a data-only refinement packet. It cannot contain functions, prototype mutation callbacks, emitters, or direct technology definitions.

Every pack declares:

- a stable ID and `mods_any`, optional `mods_all`, and optional `mods_none` applicability groups with comma-separated semantic version comparisons; the legacy `mods` field remains the `mods_any` spelling;
- aliases, exact includes and excludes, family or tier hints, and science roles;
- exact owner claims and reviewed risk overrides;
- positive Factorio target lines;
- fixture and real-mod evidence;
- a claim level and explicit public or internal boundary.

An `allow-reviewed` risk override requires named evidence. Fixture-only packs cannot publish a claim. The registry also rejects duplicate transport keys, pack IDs that differ from their transport key, empty applicability or target sets, and incomplete exact or evidence records.

External fixtures may register a pack through the internal `more-infinite-research-compatibility-pack` `mod-data` prototype. MIR validates the complete packet during final planning and fingerprints the active pack set into `GenerationPlan`. This is not a stable public extension API.

Active fields are production inputs: exact excludes and includes participate in deterministic precedence, aliases and family hints refine structurally discovered candidates, reviewed risk overrides can supersede only the matching named denial, science roles include or exclude declared packs for a stream, and owner claims feed the owner policy. Exact includes cannot bypass target support or a final owner conflict. Equal-precedence conflicting actions fail closed.

`exact-pack` mode requires at least one active validated compatibility pack before it can emit a reviewed generic family. Empty or inapplicable pack transport therefore remains non-materializing.

Compatibility packs never create technologies and cannot bypass target, effect identity, owner, science, lab, prerequisite, loop-safety, whole-plan, or emission validation. Test-only packs are injected by fixtures and never added to the production profile registry.
