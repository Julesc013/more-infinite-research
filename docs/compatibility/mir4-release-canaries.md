---
title: "MIR 4 Exact Release Compatibility Canaries"
status: current
applies_to: "4.0.0 pre-freeze T13"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-28
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-t13-exact-release-canary-contract
  - mir4-t13-lifecycle-reload-proof
  - mir4-t13-target-upgrade-binding
  - mir4-t13-claim-limitations-and-expiry
  - mir4-f200-k2so-custody-closure
---
# MIR 4 Exact Release Compatibility Canaries

T13 turns the exact environment work into eight bounded release-qualification inputs: base and official closure, Cubium, Corrundum, Recycler Progression, F210 K2/K2SO, F200 standalone K2SO, selected AAI, and selected BZ. Together they cover eleven exact F210/F200 captures.

Every capture binds an EnvironmentLockV1, exact engine executable and MIR candidate digests, the complete retained mod archive closure, startup settings, the T12 ProcessIR snapshot, and technology-unlock, recipe, and productivity-owner counts. Its lifecycle evidence consists of the successful T12 engine create-save operation followed by two one-tick benchmark reloads. Each reload must exit successfully, remain below the 300-second affected-closure budget, and leave the save byte-identical.

The target-wide upgrade proof is deliberately shared rather than fabricated per ecosystem. F210 binds the exact 3.2.11 to 4.0.21000 matrix across base, Space Age owner, automatic family, continuation, and mod-set-change archetypes. F200 binds the exact 2.5.11 to 4.0.20000 target-local predecessor case. Both matrices require first and second upgraded-save reload assertions. Third-party archives are unchanged across that MIR-owned state transition; their exact interaction is covered by the closure-specific clean-load and double-reload evidence.

The original T12 F200 K2SO blocker is historical evidence, not current state. T13 joins scenario dependency rows back to the authoritative lock and proves custody of the four previously unresolved archives by exact version and SHA-256. The tracked T13 supplement contains the resulting exact F200 K2SO lock and ProcessIR snapshot; no substitute archive was invented or downloaded.

## Claim boundary

The disposition qualified-exact-release-canary means the named locked environment passed the stated lifecycle and target-transition gates. It does not mean every behavior in an external mod is supported. Each record carries its precise support statement, limitations, compatibility-authority references, and five expiry triggers:

- engine executable digest changes;
- MIR candidate package digest changes;
- exact archive closure changes;
- startup-settings digest changes;
- governed compatibility policy or fixture changes.

ProcessIR remains conservative. A clean-loading canary can still contain FailHardSafety, ReviewRequired, or UNKNOWN process dispositions; those outcomes prevent automatic synthesis and are not converted into compatibility failures or safe-process claims.

T13 is package-excluded release-qualification evidence. It does not itself authorize a public support claim, source freeze, signing, sealing, promotion, or publication.

The canonical canary application is `tools/mir/application/inspection/CompatibilityCanary.ps1`, and its canonical exporter is `tools/mir/cli/Export-MIR4CompatibilityCanaryRecords.ps1`. The former library and command paths are read-only compatibility forwarders. The Inspector/compatibility migration binds these paths while preserving the tracked T13 receipt and manifest byte-for-byte.

## Commands

Check the tracked reference:

~~~powershell
.\tools\mir.ps1 mir4 release-canaries check
.\tools\mir.ps1 mir4 inspector-compatibility-migration check
~~~

Rebuild the reference only after exact T12 captures and both target upgrade matrices exist:

~~~powershell
.\tools\mir.ps1 mir4 release-canaries export --capture-root build/mir4/t13-exact-captures --upgrade-root build/mir4/t13-release-canaries/upgrades --publish-reference
~~~

Raw Factorio logs and host paths remain local. The tracked reference contains portable log digests and bounded records only.
