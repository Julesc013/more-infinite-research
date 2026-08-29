---
title: "Upgrading from MIR 3 to MIR 4"
status: current
applies_to: "MIR 4.0.0 candidates"
audience: player
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-29
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir3-to-mir4-player-upgrade-guide
---

# Upgrading from MIR 3 to MIR 4

MIR 4 keeps the technology IDs, settings, research behavior, migrations and runtime state of the exact terminal MIR 3 package for each target. The distribution version identifies the Factorio line; it is not a promise that every Factorio generation has identical capabilities.

## Direct upgrade paths

| Factorio | MIR 3 predecessor | MIR 4 distribution |
| --- | --- | --- |
| 2.1 | `3.2.11` | `4.0.21000` |
| 2.0 | `2.5.11` | `4.0.20000` |
| 1.1 | `1.9.9` | `4.0.11000` |
| 1.0 | `1.8.9` | `4.0.10000` |

Historical packages are private experimental candidates until separately admitted. Do not infer public support for them from an archive existing.

Before the MIR 4.0 source freeze, F210 qualification follows the exact official Steam experimental 2.1.x installed on the authorized path at or above the unchanged 2.1.8 compatibility floor. The freeze binds one exact engine identity; any later drift requires a rebuilt and requalified candidate. F110 and F100 are reduced LTS targets with explicit omissions and do not claim feature parity with F210 or F200.

## Before upgrading

1. Back up the save and the current mod directory.
2. Record the Factorio version, MIR version, active mod list and MIR startup settings.
3. Use the MIR 4 package for the same Factorio target; do not rename another target package.
4. Remove the predecessor MIR ZIP after placing the new ZIP so only one MIR version is enabled.

## After upgrading

Open the save, confirm the startup settings and active research, inspect representative completed infinite technologies, and verify fractional progress and queue order. Save once, then load the upgraded save twice. Report any missing technology, prerequisite change, lost research progress, reset setting, migration error or unexpected compatibility diagnostic with the original backup and a support snapshot.

The API, SDK, MEP, Inspector, fixtures and governance records are separate GitHub developer assets. They do not belong in the Factorio mod directory and are intentionally absent from Mod Portal player packages.
