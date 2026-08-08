---
title: "MIR 3 Terminal .5 Baseline Capture"
status: current
applies_to: "3.2.5, 2.5.5, 1.9.5, 1.8.5, 1.7.5, 1.6.5, 1.5.5, 1.4.5, 1.3.5"
audience: release-manager
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-09
supersedes: []
superseded_by: []
---

# MIR 3 Terminal `.5` Baseline Capture

All nine immutable `.5` public archives now have deterministic package-excluded static baseline captures. This is a progress boundary, not B1 completion: exact public identities, package composition, declared semantic inventories, retained engine-load evidence, and explicit capability omissions are captured, while full realized prototype, setting-default, and compatibility observation exports remain pending.

The canonical machine authorities are:

- `.mir/releases/terminal/baselines/<release>/baseline-manifest.json` for each release;
- `.mir/releases/terminal/MIR3-Dot5-Semantic-MatrixV1.json` for the cross-target feature, technology-ID, setting-ID, migration, and compatibility-claim view;
- `.mir/releases/terminal/MIR3-Terminal-Baseline-Capture-QueueV1.json` for completion state.

## Calibrated identities

| Release | Baseline root SHA-256 | Deterministic calibration bundle SHA-256 |
| --- | --- | --- |
| `3.2.5` | `2C6F1E61D359B8680B6FEA3C4EF8CD9F775E851EFAA7A13D1231036530C17596` | `E3165E789E05385D3F037CE73709BE481AC6F89C1BCFD01AB36EF80196E9CCA6` |
| `2.5.5` | `7ACE30AB13C5C532863A942A74C3959FED8980A8BA588C381E0591286E8BBE1B` | `31E0AD38897CAAE26B80870C36F3548EBC38F74564DDB91FC5F67609319D18DB` |
| `1.9.5` | `34BA4397E569A52E40317FC2E75E5CF173B1476706546ED70718D08A7D7F7377` | `6EA05D14B8E93232A275B7D79547F20A54F4B56BAA8FD6B9F1958762AD79CAA5` |
| `1.8.5` | `5B85A4FB23EB06AD63AC97132CC0C78205E2473304291081FDD554D6B4F576D3` | `2D410ACBDFC736C5E77DC607FC0B526E3A15790D329D82A6268CC4EB4B62E8BE` |
| `1.7.5` | `59497401C8CF701B08F6927DE428C7C25F8B900F5C0F73D9DD46ADBE572F034F` | `70FCF025F71D8D683D1AA2728C6FA20D6EF61FABF5310BCF2B2BF24958E4DA2E` |
| `1.6.5` | `3EE468E58F7A507316877E79D9F71C2F6A6FE7213AC375243B4ABD5D4E20B5C6` | `AE612D533E3586FED0B20F83914F8A3828A546DEA053BAD68CB5B146FC760E01` |
| `1.5.5` | `25E83329D5C9BE664DA0A97D1BDA51C42F358B6B9217D66725AEBD8A81351697` | `DECF3E910360D8AF93B64222D4BC64E4A1AA168F67FD09DD014F04BF61B1C738` |
| `1.4.5` | `724FD0A4B54AD9D3BBF79C254AAA1499DE2342E263B2C2C1D900E95182958E91` | `EF93D401C794E7F862E5EF4DC57A2C77A8F650FBC489CC25E21118562B1FF709` |
| `1.3.5` | `369B54B23FA58E3F814113E6830F01372E91856B31A567C58C923CA365F21761` | `FB6EA09DEB429E4ED2A60CF2F4FD613850C79CCF0BB7CF1BA622A56759814282` |

The bundle hashes describe deterministic calibration artifacts under `build/terminal/baselines/`; they are not published `.5` package identities and do not authorize publication.

## Truthful open boundary

Each manifest remains `calibration-incomplete`. Across the family, 27 named findings remain open: one realized-prototype export, one evaluated setting-default export, and one claim-matrix realization finding per release. Historical claim authorities that do not exist at the package-source commit are recorded as unavailable; modern claims are never projected backward.

Do not mark a queue row complete until the exact target engine supplies actual data or an engine-capability omission is independently established, every declared/realized/claimed contradiction is classified, and the final bundle repeats deterministically. No candidate assignment, `.9` source freeze, product edit, or `.5` package rewrite is authorized by this capture.
