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
source_of_truth_for:
  - terminal-dot5-semantic-baseline-capture-status
---

# MIR 3 Terminal `.5` Baseline Capture

All nine immutable `.5` public archives now have complete, deterministic, package-excluded semantic baselines. Each baseline binds the exact public ZIP and exact target-engine installation, captures declared and realized semantic inventories, classifies every declared/realized/claimed difference, and either records evaluated settings or an independently established engine-capability omission. This closes the B1 baseline-capture gate; it does not close `.5` Mod Portal custody, apply GitHub protections, admit a `.9` product change, freeze `.9` source, or allocate a candidate.

The canonical machine authorities are:

- `.mir/releases/terminal/baselines/<release>/baseline-manifest.json` for each release;
- `.mir/releases/terminal/MIR3-Dot5-Semantic-MatrixV1.json` for the cross-target feature, technology-ID, setting-ID, migration, and compatibility-claim view;
- `.mir/releases/terminal/MIR3-Terminal-Baseline-Capture-QueueV1.json` for completion state.

## Sealed baseline identities

| Release | Realized technologies / effects / settings | Baseline root SHA-256 | Deterministic bundle SHA-256 |
| --- | --- | --- | --- |
| `3.2.5` | `65 / 165 / 66` | `692E071E6057854D090880C6921F17607C3B1BA13587F1846359DC7CED09AB53` | `B8B93128EE68008CC7516882EE1B2172B3BEF07616E9585E8D6F3B0FD8976850` |
| `2.5.5` | `63 / 161 / 66` | `6B74589F413C010AA4BF7F8B178C07054315169802EC1A12AA19FAECD3316FF6` | `F8D6856DB49C6AA05974583D4EBF5B9EC8AF994CDF2732FC766A66FFC369BEE2` |
| `1.9.5` | `11 / 15 / 48` | `BF412FF6CA673F039D43B19D4835152D0CC392C6FDEF65D6E898A1FBB2C9F4B6` | `249EEE0E82976F97D415066A3AE358DDA573B4B36BCD688A64416AC9009C78C0` |
| `1.8.5` | `11 / 15 / 48` | `2193441BFC20C491234EA0A57EDEA64DFDD483EA97471E209DC3578529DCBB2A` | `D829ED59D27CA9432075044F80605045498637AEC98316C0442BC488D8566162` |
| `1.7.5` | `11 / 15 / 43` | `5966912C8A801EC5CD858E688CFC47E12023C411101F54CAD2BC90F8474CD672` | `BBD448F7503F4FF93165D3404DE071E4BD44FA2F06FB8A89880D08C6027C135C` |
| `1.6.5` | `10 / 14 / 43` | `2176FE3DD74488153D42A87CDE6FD9C2D248ACFA9D5094E04378020C6AC6E0F5` | `C501A584B660081ABD813EDAAFF6991FD81A833B916A76725DD9913B0D0502AE` |
| `1.5.5` | `3 / 3 / 43` | `81671E6577CBA23348AA0FDECAD653ED3675182175BF1B3B1413F3E9BF417E5D` | `6312C75046EE7B1FFBF3996F82436BD0F16A9513A25D27DB35BD6B2EC8F2688A` |
| `1.4.5` | `2 / 2 / omitted` | `C0B7E4A9DE2968D778BB180AF3C93AF43D2ADCBEDF43315738897DACD795A672` | `654D36CD0A12FCDF9BA1F066B055783DCB5363B9B77849FDB17BA87F0DCAFCEF` |
| `1.3.5` | `2 / 2 / omitted` | `07B8C5AD6525B8AB19F2ACE430FB7C2FC465910957FD5CD5FAF6C3D2EB3FD43A` | `8A0EB72F5439DC2B9560367711A90DBB3E66EA85C071629B09C93071955D653B` |

The bundle hashes describe deterministic baseline artifacts under `build/terminal/baselines/`; they are not published `.5` package identities and do not authorize publication.

## Realization method and boundary

The observer is a generated, package-excluded mod that depends on the exact frozen MIR ZIP and emits canonical post-final-fixes prototype and evaluated-setting facts. Every observation binds the observer and normalizer hashes, archive and normalized-content hashes, engine executable and installation hashes, official-data tree, target, and semantic digest. Each target was observed twice from isolated state; the tracked evidence was byte-identical across the independent passes.

Factorio `0.13` and `0.14` do not expose the settings-stage interface used by newer engines, so `1.3.5` and `1.4.5` carry an explicit settings capability omission instead of invented zero-valued observations. Only `3.2.5` has a canonical public compatibility-claim authority at its package-source commit; lower releases explicitly record that omission rather than inheriting modern claims.

All 27 original realization findings are closed and the matrix contains no unresolved baseline findings. The `.5` ZIPs remain unchanged. Portal custody and live GitHub protection application remain external gates, and `.9` implementation still requires a separately admitted, reproduced change record.
