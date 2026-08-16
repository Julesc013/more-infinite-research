---
title: "ADR 0006: MIR 4 Local Artifact and Approved Delta Authorities"
status: accepted
applies_to: "MIR4-R0 and later governed bootstrap work"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-08-17
supersedes: []
superseded_by: []
---

# ADR 0006: MIR 4 Local Artifact and Approved Delta Authorities

## Decision

MIR defines two reusable, package-excluded authority families with no upward implication:

- `MIRLocalArtifactLaneAuthorizationV1` authorizes bounded private construction, local validation, candidate-bound evidence export, and controlled transfer between maintainer-controlled private machines.
- `MIRApprovedDeltaV1` classifies one reviewed difference bound to exact sources, targets, paths, Git blobs, byte digests, semantic effects, forbidden side effects, and fresh proof obligations.

The authority ladder is explicit:

```text
local artifact lane -> construction and local testing only
approved delta      -> exact difference classification only
target admission    -> eligibility for release qualification
release contract    -> product obligation
seal                -> exact-byte release authorization
publication         -> exact sealed-byte transfer
```

No lower row authorizes a higher row.

## First applications

`MIR4LocalPlaytestShadowAuthorizationV1` admits only f200, f110, and f100 beneath ignored `build/mir4/local-playtest-shadow`. It leaves their release admission blocked by MIR 3 custody and EOL. It forbids public identity, tags, `dist/` writes, uploads, publication, production seals, public release or beta claims, broad support claims, wildcard targets, and generic gate waivers. Because the artifacts use intended numeric versions, transfer is restricted to maintainer-controlled private machines.

`MIR4ApprovedBootstrapCorrectionDeltaV1` applies `MIRApprovedDeltaV1` to `MIR3-TERM-0033`. It admits exactly the two recorded Lua byte transitions for f210 and does not amend `MIR4-Equivalence-PolicyV1`. The comparator accepts baseline metadata differences plus those exact deltas, then requires the remaining difference set to be empty. Lower targets do not inherit the correction; each remains governed by its own source identity and target-local proof.

## Fail-closed constraints

These authorities never contain or imply gate bypasses, failure waivers, ignored failures, path globs, directory allowances, wildcard targets, public release authority, sealing authority, or publication authority. Source, target, plan, profile, or byte drift expires the applicable authorization. A later formal target admission supersedes the private lane without rewriting its historical record.

## Consequences

Private playtest candidates, migration rehearsals, diagnostic reproducers, and reconstruction drills can be produced without misclassifying them as releases. Exact reviewed bootstrap corrections have a reusable typed representation without weakening baseline package equivalence. Promotion still requires the separate target-admission, qualification, human-review, signing, sealing, custody, and publication gates.
