---
title: "Angel/Bob native steel witness"
status: current
applies_to: "Factorio 2.1.23, AngelBob Rebalance 1.3.2 and MIR 5.0.21013 qualification"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-11-12
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-angelbob-native-steel-witness
---

# Angel/Bob native steel witness

This disposable exact-closure fixture prepares one real, unscripted laboratory completion of the foreign `steel-plate-productivity` owner. It adds only its own cloned, void-powered fast-laboratory prototype; the foreign technology prototype, ordinary cost, science vector and effect array remain unchanged. Runtime setup seeds only the named prerequisite and laboratory inputs. Actual net science payment must be 1500 of each of the four declared packs, and each named recipe must retain its recorded pre-research bonus plus exactly 0.1 after completion and both cold reads.

The four named effects must each occur once at 0.1; additional valid steel-producer effects remain governed by the unchanged MIR collection rules. A separate paired prototype capture checks other upstream fields/effects and any added routes. The fixture does not claim physical crafting, migration, performance or release acceptance. Host controls and the commands below are preparation, not native results.

The designated native owner verifies the actual standalone 2.1.23 executable against engine SHA256 `8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38`, admits resources and takes exclusive direct-library ownership before execution. Preserve prior controls and distinct archives through the existing guarded staging procedure. The exact player ZIP is 5.0.21013/E92714D1E25B5BF5927FD131FF39F51CBB4FB97C305ECE722F7EA2797C88A38F; the fixture is 0.1.0/6313F6C8665635E280D02C1E7F3184411AEE2A4CBEF5D825AAF597537DD1AC47, 6278 bytes, from raw Git fixture commit `1ee94af0a042d03abda57032435537887009e5bd`. Prepare a checkout-local raw-Git projection containing exactly its five package members, excluding this README. Provision the two owned archives only after retaining previous bytes; do not copy populated dependency libraries.

Set `$mirSteelLibrary`, `$mirSteelEngine`, `$mirSteelMIRArchive` and `$mirSteelProjection` to those verified local inputs. Use one [upstream profile](../../profiles/angelbob-rebalance-space-age-f210-2123-upstream.json) for both data-stage arms: `Invoke-PrototypeCapture` requires MIR outside its profile. The [runtime profile](../../profiles/angelbob-rebalance-space-age-f210-2123-steel-fixture.json) alone selects the fixture and MIR. These commands have not been run as part of preparation:

```powershell
.\tools\Invoke-PrototypeCapture.ps1 -ArchiveLibrary $mirSteelLibrary -FactorioBin $mirSteelEngine -ProfilePath tests/profiles/angelbob-rebalance-space-age-f210-2123-upstream.json -OutputRoot build/tmp/angelbob132-upstream-r01 -ExpectedPeakMemoryMiB 4096 -TimeoutSeconds 240
.\tools\Invoke-PrototypeCapture.ps1 -ArchiveLibrary $mirSteelLibrary -FactorioBin $mirSteelEngine -ProfilePath tests/profiles/angelbob-rebalance-space-age-f210-2123-upstream.json -MIRArchive $mirSteelMIRArchive -ExpectedMIRArchiveSha256 E92714D1E25B5BF5927FD131FF39F51CBB4FB97C305ECE722F7EA2797C88A38F -OutputRoot build/tmp/angelbob132-candidate-r01 -ExpectedPeakMemoryMiB 4096 -TimeoutSeconds 240
.\tools\Invoke-NativeFixture.ps1 -ArchiveLibrary $mirSteelLibrary -FactorioBin $mirSteelEngine -ProfilePath tests/profiles/angelbob-rebalance-space-age-f210-2123-steel-fixture.json -FixtureSources $mirSteelProjection -ExpectedMIRArchiveSha256 E92714D1E25B5BF5927FD131FF39F51CBB4FB97C305ECE722F7EA2797C88A38F -CaseName angelbob-f210-steel -OutputRoot build/tmp/angelbob132-steel-r01 -ExpectedPeakMemoryMiB 4096 -TimeoutSeconds 240
```

The generic runner creates a disposable seed, observes one `initial` marker after a settled non-scripted completion and closed server save, then observes two `reload` markers while keeping the completed save bytes unchanged. Read actual commands, source/package/controller identities, all diagnostics, payment/delta witnesses and control restoration before adopting that result. Retain failures and unavailable inputs without relabelling them as passes.
