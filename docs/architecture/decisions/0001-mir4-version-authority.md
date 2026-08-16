---
title: "ADR 0001: MIR 4 Version Authority"
status: current
applies_to: "MIR4-R0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-08-16
supersedes: []
superseded_by: []
---

# ADR 0001: MIR 4 Version Authority

## Context

MIR 3 coupled repository, package, target-line, portal, and evidence versions closely enough that a version string could be mistaken for several different identities. MIR 4 begins from one semantic source and independently generated target products, so those identities must be explicit before the first public 4.x artifact exists.

## Decision

MIR 4 keeps source revision, source release version, target identity, distribution version, candidate identity, package identity, qualification identity, and publication identity separate.

The active source generation is `MIR4-R0-pre-release`; no public 4.x identity exists yet. `4.0.0` is reserved as the first stable source release. Its target distributions use the registry in `MIR4-Target-RegistryV1`, not the bare source version.

For source version `4.MINOR.PATCH`, where `PATCH` is 0 through 99:

```text
encoded_patch = target_registry_id * 100 + source_patch
distribution_version = 4.MINOR.encoded_patch
```

The inverse is exact:

```text
target_registry_id = floor(encoded_patch / 100)
source_patch = encoded_patch % 100
```

Thus source `4.0.0` projects to `4.0.32100` for Factorio 2.1 and `4.0.32000` for Factorio 2.0. Every component remains at or below 65535, target codes are registry-assigned integers, and parsing does not depend on leading zeros. Patch 100 is forbidden; the source minor increments and the source patch resets to zero.

The source-seal tag format is `source/4.MINOR.PATCH`. Target tags use `release/<target>/<distribution-version>`. Neither may be allocated or published before MIR 3 EOL.

## Consequences

Repository work may truthfully say that it prepares MIR 4.0.0 while `info.json`, the terminal ZIPs, and the `.9` tags remain immutable MIR 3 authorities. A source milestone cannot silently publish a target package, and a schema change cannot silently imply a player-visible release.

The encoding is decided, tested for uniqueness, ordering, round-trip decoding, bounds, and overflow, but no concrete public version is allocated. Schema versions remain monotonic integers inside each record kind. API and extension-protocol versions do not exist during R0.
