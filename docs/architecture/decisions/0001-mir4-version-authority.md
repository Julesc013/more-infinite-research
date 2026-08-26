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
source_of_truth_for:
  - mir4-version-authority
  - mir4-distribution-target-registry
  - mir4-distribution-version-codec
---

# ADR 0001: MIR 4 Version Authority

## Context

MIR 3 coupled repository, package, target-line, portal, and evidence versions closely enough that a version string could be mistaken for several different identities. MIR 4 begins from one semantic source and independently generated target products, so those identities must be explicit before the first public 4.x artifact exists.

## Decision

MIR 4 keeps source revision, source release version, target identity, distribution version, candidate identity, package identity, qualification identity, and publication identity separate.

The active source generation is `MIR4-R0-pre-release`; no public 4.x identity exists yet. `4.0.0` is reserved as the first stable source release. Its target distributions use `MIR4-Target-RegistryV2`, not the bare source version.

The V2 registry owns 17 immutable three-character decimal strings. They are direct Factorio-line codes: `210`, `200`, `110`, `100`, then `018` through `006`. Leading zeroes are part of the identity and are never octal. The V1 target and version records remain byte-frozen historical R0 evidence; they cannot be passed to the executable resolver and define no alias for a V2 code.

For source version `4.MINOR.PATCH`, where `PATCH` is 0 through 99:

```text
encoded_component = decimal(distribution_target_code) * 100 + source_patch
distribution_version = 4.MINOR.ENCODED_COMPONENT
```

The inverse is exact:

```text
distribution_target_code = leftmost three digits of ENCODED_COMPONENT
source_patch = rightmost two digits of ENCODED_COMPONENT
```

Thus source `4.0.0` projects to `4.0.21000` for Factorio 2.1, `4.0.20000` for Factorio 2.0, and `4.0.00600` for Factorio 0.6. The encoded component is rendered as exactly five decimal digits. Code `654` with patch `99` gives the admitted internal upper boundary `65499`, below Factorio's component maximum of `65535`. Patch 100 is forbidden; the source minor increments and the source patch resets to zero.

The signed source-tag format is `v4.MINOR.PATCH`. Signed target tags use `dist/f<distribution_target_code>/v<distribution-version>`. For example, source `4.6.8` and Factorio 2.1 produce `v4.6.8` and `dist/f210/v4.6.21008`. Neither may be allocated or published before MIR 3 EOL; unpublished candidates carry typed candidate identity and no public tag.

## Consequences

Repository work may truthfully say that it prepares MIR 4.0.0 while `info.json`, the terminal ZIPs, and the `.9` tags remain immutable MIR 3 authorities. A source milestone cannot silently publish a target package, and a schema change cannot silently imply a player-visible release.

The encoding is decided and executable, but no concrete public version is allocated. Its conformance authority covers all 17 public targets at source patches `00`, `01`, `08`, `09`, and `99`, the internal `65499` boundary, exact round trips, leading-zero preservation, and fail-closed negative cases. Cross-target numeric ordering is undefined; chronology follows the source release version. Schema versions remain monotonic integers inside each record kind. API and extension-protocol versions do not exist during R0.
