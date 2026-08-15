---
title: "MIR 3 Terminal Release and MIR 4 Handoff Guide"
status: current
applies_to: "3.2.9-1.3.9"
audience: release-manager
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-15
supersedes: []
superseded_by: []
---

# MIR 3 Terminal Release and MIR 4 Handoff Guide

The nine `.9` archives are the final target-native MIR 3 family. They are source-frozen, triple-reconstructed, automatically qualified, maintainer-accepted, and sealed. Package-visible bytes must not change during branch promotion, tagging, GitHub publication, Mod Portal upload, archival, or MIR 4 bootstrap.

## Target, feature, and omission matrix

| Release | Exact engine | Product delta | Explicit boundary |
| --- | --- | --- | --- |
| `3.2.9` | Factorio 2.1.13 | K2 phasing, alternate science routes, combined direct-effect ownership | Exact named compatibility claims only |
| `2.5.9` | Factorio 2.0.77 | Alternate science routes and combined direct-effect ownership | No K2 2.1 policy projection |
| `1.9.9` | Factorio 1.1.110 | No admitted package delta | Target-native terminal baseline |
| `1.8.9` | Factorio 1.0.0 | No admitted package delta | Factorio 1.0 only; no 0.18 bridge claim |
| `1.7.9` | Factorio 0.17.79 | No admitted package delta | Target-native omissions retained |
| `1.6.9` | Factorio 0.16.51 | No admitted package delta | Target-native omissions retained |
| `1.5.9` | Factorio 0.15.40 | No admitted package delta | Target-native omissions retained |
| `1.4.9` | Factorio 0.14.23 | No admitted package delta | Finite continuation; no modern approximation |
| `1.3.9` | Factorio 0.13.20 | No admitted package delta | Finite continuation; no modern approximation |

## Upgrade matrix

Each target passed two governed paths: `3.2.5/3.2.3`, `2.5.5/2.5.0`, `1.9.5/1.9.4`, `1.8.5/1.8.2`, `1.7.5/1.7.1`, `1.6.5/1.6.0`, `1.5.5/1.5.0`, `1.4.5/1.4.0`, and `1.3.5/1.3.0` to their matching `.9` release.

## Settings and compatibility

No released setting ID, type, default, profile encoding, or scope changed. All settings remain Startup/compile settings and MIRSET1 is unchanged. Public compatibility claims remain limited to exact fixtures or named load-check evidence in `MIR3-Compatibility-ClaimsV1`; the release does not claim every possible mod combination.

## Known limitations

Direct unmodified Cubium 1.0.28 proof remains bounded by archive acquisition and upstream engine compatibility. Historical releases intentionally omit unsupported modern functionality. Mod Portal custody is incomplete until the maintainer uploads each exact ZIP and authenticated redownload plus exact-engine smoke verification succeeds.

## Publication and MIR 4 handoff

Promote only `main` to 3.2.9 and `legacy` to 2.5.9. The seven lower releases remain tag-only. Publish the exact ZIPs whose hashes appear in `SHA256SUMS-MIR-3.txt`. MIR 4 begins from these sealed baselines through explicit target profiles and deterministic lowering; it must not reconstruct MIR 3 authority from mutable branch history.
