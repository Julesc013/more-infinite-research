---
title: "MIR Canonical JSON V1"
status: current
applies_to: "4.0 developer preview contracts"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-canonical-json-v1-contract
  - mir4-permanent-schema-namespace
  - mir4-stable-diagnostic-registry
  - mir4-v0-v1-compatibility-policy
---
# MIR Canonical JSON V1

`mir-canonical-json/1` is the deterministic wire and digest representation for MIR 4 V1 API, MEP, and platform-lock records. It is a package-excluded developer contract and does not grant compiler, emitter, runtime, signing, publication, or public-support authority.

## Normative authorities

- `spec/canonicalization/mir-canonical-json-v1.json` defines the encoding, Unicode, ordering, number, timestamp, target, unavailable-value, and digest rules.
- `spec/api/mir4-v1/schema-namespace.json` assigns permanent project-owned schema IDs under `https://julesc013.github.io/more-infinite-research/schemas/mir4/v1/`.
- `spec/api/mir4-v1/diagnostics.json` assigns stable codes that are never reused.
- `spec/api/mir4-v1/compatibility.json` makes V0 an explicit migration input only.
- `fixtures/mir4-canonical-json-v1/vectors.json` carries at least 12 positive and 16 negative cross-runtime vectors.

## Canonical form

Input is strict UTF-8 JSON without a BOM. Property names and string values are normalized to NFC; invalid Unicode, duplicate keys, and normalized-key collisions fail closed. Object properties are ordered by ascending UTF-16 code units. Generic array order is preserved. Producers sort and deduplicate set-like arrays before canonicalization; extension closure order is dependency-topological and then ordinal by extension ID; diagnostics are ordered by severity, registry order, code, and path.

Only signed integers in the inclusive range `-9007199254740991` through `9007199254740991` are admitted. Negative zero, fractions, exponent notation, and non-finite values fail closed. Timestamps use UTC second precision exactly as `yyyy-MM-ddTHH:mm:ssZ`. Target IDs use lowercase `fNNN`.

Unavailable data is represented with explicit `status`, `reason`, and `evidence`. It is never converted to zero or an empty available result.

## Digests

The digest input is:

```text
UTF8("mir-canonical-json/1" + NUL + domain + NUL + canonical-json)
```

The top-level `digest` property is omitted from the canonical material. The result is lowercase `sha256:<64-hex>`. API responses, extension envelopes, platform locks, and other record kinds use distinct domains, preventing the same JSON bytes from being treated as different record types.

## Compatibility

V0 readers remain only for deterministic migration. A V0 record is parsed and validated as V0, mapped structurally to V1, canonicalized with this contract, and assigned a new V1 domain-separated digest. V0 digests and placeholder schema IDs are never reused or emitted as V1.

The `canonical-text-v1` mode used by pre-freeze authority receipts is a separate line-ending-stable file hash. It does not replace this JSON record contract.

## Reference checks

```powershell
.	ools\mir.ps1 mir4 sdk generate
.	ools\mir.ps1 mir4 sdk check
.alidation\tests\mir4\Test-MIR4CanonicalizationDiagnosticsT07.ps1
```

PowerShell is the repository implementation. The independent Python reference under `spec/canonicalization/reference/` executes the same vector corpus and is copied into the API V1 preview SDK.
