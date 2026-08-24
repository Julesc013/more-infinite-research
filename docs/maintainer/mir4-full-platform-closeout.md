---
title: "MIR 4 Full-Platform Private Closeout"
status: current
applies_to: "4.0.0 M4C02-09-24H"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-24
supersedes: []
superseded_by: []
---

# MIR 4 full-platform private closeout

`Export-MIR4FullPlatform24HRecords.ps1` is an evidence-only adapter for the M4C02 W00–W09 programme. It gathers the exact named records required by the full-platform steer into `build/mir4/m4c02-full-platform-24h`. It does not become a product, policy, compiler, release, or publication authority.

Generate every wave record against one clean commit and tree first. Materialize the exact verification plan, complete the governed campaign, and create the aggregate evidence bundle. Then run the exporter with those three evidence paths. The exporter rejects wave records that expose a different commit or tree.

The first export may omit `-LunaAuditPath`; that produces a packet marked `PENDING-INDEPENDENT-LUNA-AUDIT`. After an independent GPT-5.6 Luna review of the exact same commit and tree, create a local audit input conforming to `spec/schemas/mir4-luna-audit-input-v1.schema.json` and rerun with `-LunaAuditPath`. An `ACCEPT` input is rejected if it contains a B0 finding, recommends against merge, or binds another source identity.

Every named output is a `MIR4FullPlatformRecordV1` evidence envelope. Wave outputs are embedded without rewriting their original authority or digest, and the envelope records the upstream byte hash, validator, governing authority, maturity, package visibility, public-proof status, and exact source identity. `SHA256SUMS.json` covers the other 38 files and intentionally excludes itself.

Open blockers are not release defects that this adapter may waive. The original closeout record correctly prohibited Dev integration within that evidence run and remains immutable. PR #151 was subsequently reviewed, passed the hosted MIR gates, and merged to `dev` at commit `3a58d3753bedcaf1107b76655117e0ff84dac960` under separate integration authority. `.mir/releases/waves/mir4-r0/MIR4-Release-Readiness-ReconciliationV1.json` is the append-only reconciliation; it does not rewrite the closeout.

`BLOCKED-HUMAN-SECRET-INPUT` still prohibits source freeze, M4RC1 allocation, signing, sealing, ledger initialization, `main` promotion, tags, and publication. The reconciliation scopes independent-consumer, exact ProcessIR, trusted timing/capacity, f018 engine, museum custody, successor-host, and technology/compatibility acceptance blockers so optional component or target work cannot falsely block unrelated Dev readiness or falsely authorize a player release.
