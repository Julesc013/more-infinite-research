---
title: "MIR Lower-Wave 0.17 To 0.6 Release Synthesis"
status: current
applies_to: "1.7.1 through 0.6.0"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-16
supersedes: []
superseded_by: []
---

# MIR Lower-Wave 0.17 To 0.6 Release Synthesis

The twelve independently reconstructed lower targets were qualified from final canonical development anchor `6ac377389d7ffc3576fb39576dab4ace6efaec51`, published in descending target order, publicly re-downloaded, and verified byte-for-byte. On 2026-07-16, the seven museum archives were rebuilt and republished after the shared generator was corrected to emit explicit target-matching `factorio_version` metadata. The machine-readable authority is `.mir/evidence/lower-wave/final-release-ledger.json`.

## Outcome

| MIR | Factorio | Tag commit | ZIP SHA-256 | GitHub | Mod Portal |
| --- | --- | --- | --- | --- | --- |
| 1.7.1 | 0.17.79 | `9d9095c92055aebe557a55a7ab99bb9588fe73fb` | `2B2A395F014BF1C0C08596602A723E51F14199A9196B192858335FFE8ED9B25B` | published and byte-verified | `blocked-missing-MOD_UPLOAD_API_KEY` |
| 1.6.0 | 0.16.51 | `a48509ed1dfbae8eba4b3dc7a701065063c12d5f` | `18EAE70A7FEE1FD50099D15985C4E5BE7DB018592EC3EFFC792950A920714544` | published and byte-verified | `blocked-missing-MOD_UPLOAD_API_KEY` |
| 1.5.0 | 0.15.40 | `c2b526fd6dde81be7703daef53b075a1fd773e09` | `131162AA1A62C05E2C395C3F9D2495178742CD8C5324B058C42995C17F65B4DB` | published and byte-verified | `blocked-missing-MOD_UPLOAD_API_KEY` |
| 1.4.0 | 0.14.23 | `fa192796ab274dd590c65b96d0f3f6a0f35cb155` | `69B7FC86E798937D44DF60E5E6DDC1FA636A10643B2E1BF54A79F5255CF984C1` | published and byte-verified | `blocked-missing-MOD_UPLOAD_API_KEY` |
| 1.3.0 | 0.13.20 | `a33b99c1f39e1e779986a12a558a79ea97e69239` | `B07136627C913BA50C36B4F9453D972047F4FD3666BB9B8A79AB0EEFC9CA1749` | published and byte-verified | `blocked-missing-MOD_UPLOAD_API_KEY` |
| 0.12.0 | 0.12.35 | `82a349bd8137abe21145b321be4edb1e43e1e9e1` | `5171CD073A632AA30769FD9567F44AD2331BB5E7B852EC9F8576798398816612` | corrected archive published and byte-verified | maintainer upload pending |
| 0.11.0 | 0.11.22 | `679774c94bafdaa4d5432b793b8684ee4e43c257` | `38B9DFB72CE5EB0554CF2C9514D9B3D917B322DE5AC955A085A2A1BAADED2DEE` | corrected archive published and byte-verified | maintainer upload pending |
| 0.10.0 | 0.10.12 | `3377f835243c0cf9e7d2c2e76641c2c471341975` | `C2E42E9AE23E4A146F755B60D40009738724E7A0D3670D3B672D2068AE80912E` | corrected archive published and byte-verified | maintainer upload pending |
| 0.9.0 | 0.9.8 | `9325e744f1dd36baa33372dab6e7d9528ccfbab8` | `2114D67493C6B1076B1A71F27DC5197C8789C956570FD274507B8FD807C27D84` | corrected archive published and byte-verified | maintainer upload pending |
| 0.8.0 | 0.8.8 | `080fa92ea38b4b40156f26429bc7cba54948aef0` | `60BA156874CC3EE0C93B93C032BDEC6D8432B5F692009A3277C1890E6D9BF3E6` | corrected archive published and byte-verified | maintainer upload pending |
| 0.7.0 | 0.7.5 | `cb2991e3ea67b0413076c0e6d0dacf29d7f784b6` | `AA328AFF81F3133BAC3F432ADC7AF52CC49EFF43E40D04EAD99DCFBA92542749` | corrected archive published and byte-verified | maintainer upload pending |
| 0.6.0 | 0.6.4 | `12a5683c2aaed745f35e1261b437930a9a1476bc` | `0C53F30AFF4FCC3090323D3B319FAF6DD763D696983F60947BB07AB53617288A` | corrected archive published and byte-verified | maintainer upload pending |

## Boundaries

The 1.7.1 through 1.3.0 packages are canonical MIR 3.1.9-derived target projections, feature-complete for positively supported target capabilities. The 0.12.0 through 0.6.0 packages are finite archive/museum releases. None claims identical MIR 3.1.9 behavior, full modern parity, or broad compatibility beyond named evidence.

Manual technology-tree, icon, locale-fit, and balance judgment remains `PENDING-MAINTAINER` for every target. Automated locale and balance gates passed; manual review was not falsely promoted.

## Later Work

The exact first command for a separately authorized MIR 3.2.0 campaign is:

```powershell
git fetch --all --tags --prune
```

This wave grants no authority to begin MIR 3.2.0 implementation.
