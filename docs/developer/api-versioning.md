---
title: "MIR 4 API Versioning"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-api-versioning-developer-policy
---

# MIR 4 API versioning

API V1 uses permanent schema identities and explicit required-version negotiation. A consumer must reject unsupported required versions and may ignore only fields the schema marks extensible.

V1 preview means the implementation is package-excluded and has no stable public-support promise; it does not mean canonical bytes are informal. Accepted inputs, unavailable values, pagination bounds, extension closure, diagnostic order, and digests are fixed by the schema and conformance corpus for the published asset.

V0 is a migration input, not a second current API. Convert it with the bundled migration helper and validate the V1 result.
