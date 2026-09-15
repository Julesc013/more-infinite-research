---
title: "MIR 4.1.0 Local Delivery Index"
status: current
applies_to: "Published MIR 4.1.0 custody"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-09-15
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir410-local-delivery-index
---

# MIR 4.1.0 — published local release index

[Published GitHub release](https://github.com/Julesc013/more-infinite-research/releases/tag/v4.1.0). The nine public release assets are external custody bytes; a primary checkout may materialize verified local copies under `dist`, but a clean source checkout does not claim to contain them.

> This file indexes immutable published 4.1.0 delivery only. It is not the live MIR 4.2 candidate or execution authority. Use the tracked [current-candidate view](releases/current-candidate.md) and [executable queue](../TODO.md) for current development; a qualified 4.2 maintainer handoff belongs in `dist/playtest/`, not in this 4.1 index.

| Target | Verified local-delivery location when materialized | Mod Portal copy location when materialized |
| --- | --- | --- |
| Factorio 2.1 | `dist/more-infinite-research_4.1.21000.zip` | `dist/mod-portal/4.1.0/f210/mod-portal.md` |
| Factorio 2.0 | `dist/more-infinite-research_4.1.20000.zip` | `dist/mod-portal/4.1.0/f200/mod-portal.md` |
| Factorio 1.1 | `dist/more-infinite-research_4.1.11000.zip` | `dist/mod-portal/4.1.0/f110/mod-portal.md` |
| Factorio 1.0 | `dist/more-infinite-research_4.1.10000.zip` | `dist/mod-portal/4.1.0/f100/mod-portal.md` |

The associated release notes, upgrade guide, closure receipt, checksums, and local-delivery verification are likewise retained only with the materialized local-delivery custody set; this document does not make broken source-checkout links to them.

This index is for the published 4.1.0 assets only. MIR 4.2 development may create private candidates under its governed custody paths, but no 4.2 candidate is a published release or a replacement for the verified 4.1 files linked here.

F210 4.1.21000 is listed on the Mod Portal; its API SHA-1 matches the local ZIP. F200/F110/F100 uploads were not listed at the handoff observation and remain for maintainer disposition. No fresh Portal ZIP download was performed. F200 was human-verified. F210 was accepted under the maintainer's direct-playtest waiver, retaining its existing automated qualification.

The published source is `3562377b520cccb071b97b3968946eae7024c950`, tree `e094f72aa59ecb994f12bb33c399022f20e94165`. That was the main/dev identity at release closure. The README restoration completed at main `f458598732e9583a9d086032ebfbe9ffb747d130` and dev `3683369ba00cfbdd7f8872a5a1b24f0d59f31062`, with identical historical tree `a95caf6e96ec9b0eef4eb19677e9a8192821f522`. Development [PR #253](https://github.com/Julesc013/more-infinite-research/pull/253) established the later MIR 4.2 programme and remains a historical checkpoint at `abe152a332741db268a39b5088866e5aab634fed`, not the live `dev` identity. Current development does not require main/dev tree equality. The signed v4.1.0 tag object is `9e5e63ef45b9d583d3f463fbfa737eb2c3a6b69f`.

Public signer fingerprint: `SHA256:McpdYUux7BcYmBkf75fGuHSn/lYkTHB6ngMOdUJ5ggQ`. Unchanged technical seal: `71F57BA7201C2DBA775C8BE27459FB078E511DE267D0377210763CF0E13D2E6A`.

Use this checkout as the working home:

- `source`: current authored player source.
- `targets`: target definitions.
- `docs`: repository documentation.
- `dist`: published packages and supporting assets.
- `dist/mod-portal/4.1.0`: prepared upload text.
- `dist/release-4.1.0`: release notes, upgrade guide and local receipt copies.
- `build/workspace-delivery/`: optional local-delivery reconstruction working area, not a tracked source-checkout promise.

Historical tracked ZIPs remain in `dist` when the local delivery set is materialized because existing source and evidence refer to them. The original immutable release ledger remains at `E:\MIR_EVIDENCE_HOME\m41-release-readiness\3562377b`. The reviewed handoff is external custody source A08, `MIR_REVIEWED_HANDOFF_2026-09-05.zip`, SHA-256 `52540eaa1c978fc64497f7317be03cf976106e0efd7ced43948f860bf70b4b83`, 3,500,568 bytes, recorded in `spec/programmes/inputs/synthesis-2026-09-05/SOURCES.json`; it is not claimed to be in this checkout. No sealed package was rebuilt. The subsequent README and package-excluded governance correction preserves the published source and assets.

This index records a local-delivery role without treating ignored local outputs as repository authority. The supported `pwsh tools/mir.ps1 release deliver --manifest <file> --source-root <directory>` command provides resumable, hash-verified local delivery; it does not build, publish, or select a future release. The README restoration and permanent primary-checkout completion rule are in [PR #251](https://github.com/Julesc013/more-infinite-research/pull/251), merged and forward-integrated through PR #252; all required workflows passed.
