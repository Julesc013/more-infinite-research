---
title: "Current Development Candidate"
status: current
applies_to: "3.2.0"
audience: release-manager
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-24
supersedes: []
superseded_by: []
---

# Current Development Candidate

> Generated from `.mir/releases.json` by `scripts/Update-MIRGeneratedAuthorityDocs.ps1`. Do not edit candidate identity here.

## Factorio 2.1 development line

| Field | Authority |
| --- | --- |
| MIR version | `3.2.0` |
| Candidate | `C16` |
| Branch | `dev` |
| Package source commit | `0448ceb8d3992082718e2df83bd6a42c56955636` |
| Package source tree | `eb6a5b42676ab65bb95ee7c1422f2191730b1338` |
| Package source SHA-256 | `10BB848EA5899873C42CDF29F676806BC8BE282C2A4BFC09CE760E72331714A7` |
| Archive | `dist/more-infinite-research_3.2.0.zip` |
| Archive bytes | `1014593` |
| Archive entries | `288` |
| Archive SHA-256 | `4646277AC8FBC67D453EAAAEE13C3167630AD94BFE490AD08D592844B6D7B38D` |
| Package content SHA-256 | `10BB848EA5899873C42CDF29F676806BC8BE282C2A4BFC09CE760E72331714A7` |
| Qualification | `focused-automation-passed-full-no-reuse-pending` |
| Publication | `unreleased` |
| Status | `focused-performance-and-semantic-parity-passed-awaiting-full-no-reuse` |

## Superseded candidate

| Field | Authority |
| --- | --- |
| Candidate | `C15` |
| Package source commit | `c3a56e88fa15da7c12db3b0d11c3d4e732935746` |
| Archive bytes | `1000692` |
| Archive entries | `286` |
| Archive SHA-256 | `89158F34FF5C46C133A832E15AB6872925F87A481C49457DEBD61D1B808CBFAA` |
| Reason | C15 passed gameplay, package, K2SO, upgrade, and scale checks but failed the governed fixed-cost performance gate; C16 removes redundant trusted-record validation, copying, fingerprinting, and canonicalization while preserving exact seven-scenario semantic output |

Published baselines remain immutable and development candidates remain unreleased until exact automated, manual, protected, and seal authority agree.
