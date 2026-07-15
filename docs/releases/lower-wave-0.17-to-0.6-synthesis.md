---
title: "MIR Lower-Wave 0.17 To 0.6 Release Synthesis"
status: current
applies_to: "1.7.1 through 0.6.0"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-15
supersedes: []
superseded_by: []
---

# MIR Lower-Wave 0.17 To 0.6 Release Synthesis

The twelve independently reconstructed lower targets were qualified from final canonical development anchor `6ac377389d7ffc3576fb39576dab4ace6efaec51`, published in descending target order, publicly re-downloaded, and verified byte-for-byte. The machine-readable authority is `.mir/evidence/lower-wave/final-release-ledger.json`.

## Outcome

| MIR | Factorio | Tag commit | ZIP SHA-256 | GitHub | Mod Portal |
| --- | --- | --- | --- | --- | --- |
| 1.7.1 | 0.17.79 | `9d9095c92055aebe557a55a7ab99bb9588fe73fb` | `2B2A395F014BF1C0C08596602A723E51F14199A9196B192858335FFE8ED9B25B` | published and byte-verified | `blocked-missing-MOD_UPLOAD_API_KEY` |
| 1.6.0 | 0.16.51 | `a48509ed1dfbae8eba4b3dc7a701065063c12d5f` | `18EAE70A7FEE1FD50099D15985C4E5BE7DB018592EC3EFFC792950A920714544` | published and byte-verified | `blocked-missing-MOD_UPLOAD_API_KEY` |
| 1.5.0 | 0.15.40 | `c2b526fd6dde81be7703daef53b075a1fd773e09` | `131162AA1A62C05E2C395C3F9D2495178742CD8C5324B058C42995C17F65B4DB` | published and byte-verified | `blocked-missing-MOD_UPLOAD_API_KEY` |
| 1.4.0 | 0.14.23 | `fa192796ab274dd590c65b96d0f3f6a0f35cb155` | `69B7FC86E798937D44DF60E5E6DDC1FA636A10643B2E1BF54A79F5255CF984C1` | published and byte-verified | `blocked-missing-MOD_UPLOAD_API_KEY` |
| 1.3.0 | 0.13.20 | `a33b99c1f39e1e779986a12a558a79ea97e69239` | `B07136627C913BA50C36B4F9453D972047F4FD3666BB9B8A79AB0EEFC9CA1749` | published and byte-verified | `blocked-missing-MOD_UPLOAD_API_KEY` |
| 0.12.0 | 0.12.35 | `d3681bc202938e06fb965531ddfa764f71ca38ce` | `C98EBB436DD1BA1C4C0C230EB51C637EE42904000C9C7A82C7E7A33F6F5461EF` | historical archive published and byte-verified | archive-only |
| 0.11.0 | 0.11.22 | `e83648f8f9b75f8545e913a9a5288423dbb9ebfa` | `C628FBFA4FC2A811869C5D33245BCBA0D37AA5EE2074ADEC7155874C2081B748` | historical archive published and byte-verified | archive-only |
| 0.10.0 | 0.10.12 | `732ec117f187ccf77325e85023999f869520be9e` | `845CBB69195ED03AF604685137D356E826B29D0570A4A4AFD6C0941E4B23C04F` | historical archive published and byte-verified | archive-only |
| 0.9.0 | 0.9.8 | `210a4556b12a3a40a64337c3535da307c86137e5` | `9FE3117CE3415858506FBA319A2F025F170771590A23C2E160D710F4447A05F1` | historical archive published and byte-verified | archive-only |
| 0.8.0 | 0.8.8 | `e0e297cd0bcc4a38f54d5b2e4b7bc54335785ee3` | `6832B00783657F60D8AE967552CA354D1F73C988A0DFE023999AE81533267D8E` | historical archive published and byte-verified | archive-only |
| 0.7.0 | 0.7.5 | `085d529f52b3f3b2ddf06a682475d2d7124210b7` | `8495146889655FA46233A7B0416F4C67B4E2BF93E984E01F5F8234C9CA6F570F` | historical archive published and byte-verified | archive-only |
| 0.6.0 | 0.6.4 | `a4f82673278f1414eff06f8094ed460851fc112b` | `40EC4F7B07EF4219E74259DA0AA30C8095D8CEA003BDECE90E857D4379DB1C2C` | historical archive published and byte-verified | archive-only |

## Boundaries

The 1.7.1 through 1.3.0 packages are canonical MIR 3.1.9-derived target projections, feature-complete for positively supported target capabilities. The 0.12.0 through 0.6.0 packages are finite archive/museum releases. None claims identical MIR 3.1.9 behavior, full modern parity, or broad compatibility beyond named evidence.

Manual technology-tree, icon, locale-fit, and balance judgment remains `PENDING-MAINTAINER` for every target. Automated locale and balance gates passed; manual review was not falsely promoted.

## Later Work

The exact first command for a separately authorized MIR 3.2.0 campaign is:

```powershell
git fetch --all --tags --prune
```

This wave grants no authority to begin MIR 3.2.0 implementation.
