---
title: "MIR 2.4.0 Legacy Backport Wave Handoff"
status: current
applies_to: "1.9.4 through 1.3.0"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-14
supersedes: []
superseded_by: []
---

# MIR 2.4.0 Legacy Backport Wave Handoff

This tracked handoff covers the independent release candidates for Factorio 1.1, 1.0, 0.17, 0.16, 0.15, 0.14, and 0.13. It records implementation, exact artifact, validation, seal, and future release-command authority without publishing any candidate.

The published MIR 3.1.5 and MIR 2.4.0 archives are immutable campaign anchors. The public MIR 2.4.0 GitHub asset was independently downloaded and matched SHA-256 `4BA19EA071E6359BC25C58CCD8F65CAF81B4AA675496E2F53175A996C791470C`. Later target branches reconcile the published state without modifying those bytes.

## Campaign Status

All seven branches are `GREEN-RELEASE-READY`, clean, pushed, and equal to their remote heads. Every archive is byte-deterministic, passed its target-specific static gate, loaded from its exact release ZIP on the matching Factorio binary, passed fresh create/reload retention, and has a verified candidate seal.

| Order | Factorio | MIR | Branch head | Archive SHA-256 | Capability mode |
| ---: | --- | ---: | --- | --- | --- |
| 1 | 1.1 | 1.9.4 | `dc6414e21585e8f565947be1c3b59ebe6bf750b8` | `E350F7433F4613DE075F703435EC23FC8000ADF74FCE4F69ACEAC2DD1478BB5D` | adapted native direct effects |
| 2 | 1.0 | 1.8.2 | `b2855c7bbcf5adc69644820491eb8ebc17bcf362` | `740F439060031B6C64925B2CBAC038912703A39F7CC2030775DEFE60C93CADD5` | adapted native direct effects |
| 3 | 0.17 | 1.7.1 | `c59140c1808575bd26bf4156f9a6891d3cf90945` | `E6BA58D6BAAD774712ED175E14361D130A82D7DB6DD881D5B17A3FE6E48CCCC5` | adapted native direct effects |
| 4 | 0.16 | 1.6.0 | `41283b13037fd8b39c875d0d8cdc39ad1e978b23` | `FA1D23E5BBAF466DD609314159A4C61B588EF189630A2422ADCC70D1A16243AD` | adapted native direct effects |
| 5 | 0.15 | 1.5.0 | `c55cba5253f82bc93733522736fa303eda5acfa7` | `3F8D78ECEC9DCCCCF2DD14279DC7E3BD696212F33C3FDD87A924B905223ACBCF` | adapted native direct effects |
| 6 | 0.14 | 1.4.0 | `2e9eab88e3b6ec6ad84460c1d75d8177441182d6` | `39EDE9BA8DA7BDD632828B0B1F055A8681FC1DAB48D7D1B9348D707BB0AF0B93` | finite reconstruction |
| 7 | 0.13 | 1.3.0 | `9037ed01e04961b0b370f082ccafa5ef0b3a34f9` | `36EC72C5D217CE6120C5073A374B6C344BA76DF254480E9A010AA80F6B55C4CC` | finite reconstruction |

## What Was Carried Down

- Stable generated stream and setting identities, iterative graph safety, strict prerequisite ownership, and target-era emission boundaries remain intact.
- Packaging now uses canonical path order, fixed timestamps, fixed compression, LF-normalized text, and an explicit forbidden-entry check.
- Validation accepts an exact candidate ZIP, so the runtime lane tests the same bytes intended for release rather than rebuilding a surrogate.
- Each branch records a complete capability classification, deterministic rebuild, exact-binary identity, qualification summary, and immutable seal.
- Factorio 1.1, 1.0, and 0.17 passed their legitimate prior-version upgrade paths. The older first-qualified lines record prior upgrade as not applicable and passed fresh create plus target-era server reload.

Factorio 1.x through 0.13 cannot represent the `change-recipe-productivity` technology effect. The 2.4.0 vanilla-owner adoption/repair and its low density structure, plastic, processing unit, and rocket fuel configuration cannot be honestly emitted on these engines. Those streams and settings are therefore `omitted-by-capability`; the branches no longer show controls that could only be inert. Factorio 0.14 and 0.13 are explicitly finite reconstructions and make no native-infinite parity claim.

## Release Packet

Run these only after the maintainer's visual review. They are recorded here and remain `NOT-RUN`:

```powershell
git push origin dc6414e21585e8f565947be1c3b59ebe6bf750b8:refs/tags/1.9.4
git push origin b2855c7bbcf5adc69644820491eb8ebc17bcf362:refs/tags/1.8.2
git push origin c59140c1808575bd26bf4156f9a6891d3cf90945:refs/tags/1.7.1
git push origin 41283b13037fd8b39c875d0d8cdc39ad1e978b23:refs/tags/1.6.0
git push origin c55cba5253f82bc93733522736fa303eda5acfa7:refs/tags/1.5.0
git push origin 2e9eab88e3b6ec6ad84460c1d75d8177441182d6:refs/tags/1.4.0
git push origin 9037ed01e04961b0b370f082ccafa5ef0b3a34f9:refs/tags/1.3.0
```

The release archives are the `dist/more-infinite-research_<version>.zip` files on their corresponding branches. Verify each SHA-256 against the table and branch-local `.mir/evidence/<version>-candidate-seal.json` before upload.

All tags, GitHub releases, Mod Portal uploads, and public publication commands remain `NOT-RUN`. Manual visual review remains `PENDING-MAINTAINER`. The 3.1.5 and published 2.4.0 anchors are unchanged. All 31 pre-wave tag object identities are unchanged; the intentionally stale local annotated `2.4.0` tag was not modified.

Detailed machine-readable state is in `.mir/evidence/backport-wave-2.4.0/campaign.json`; initial and final tag audits are beside it.
