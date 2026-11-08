---
title: "MIR 5.0.10 hotfix findings"
status: "candidate evidence; publication pending"
applies_to: "MIR 5.0.10 GitHub prerelease candidate"
audience: "maintainers"
doc_type: "release finding record"
owner: "mir-maintainers"
last_reviewed: "2026-11-09"
supersedes: []
superseded_by: []
source_of_truth_for:
  - "MIR 5.0.10 worker-provider and Space Is Fake affected evidence summary"
---

# MIR 5.0.10 hotfix findings

This record describes the bounded WorkerRobotCargoSizeResearch and Space Is Fake evidence for the frozen MIR 5.0.10 candidate. It is not a stable-acceptance verdict and does not announce a release.

## Candidate and current state

The accepted player source is `8e5ce79be9595c888ed6cad4aa8d2eecd325767d`, whose player tree is `f4e45e5667146ec57dee763137ea386f080b7bd0`; the publication reconciliation is `be6b06dba9a4338756737b569c6b55e2123e7161`, with tree `416e7b290caa3ce2c164e5496d482a2041e43e90`, and it does not change the player source tree.

The frozen 5.0.21010 player archive hash is `C625D648978F6FE677B5EDC5C68090A2AA9A939D48A54A736610D55E47337806`. The selected 174-check suite passed on the accepted `8e5ce79b` candidate; fresh required CI for reconciliation head `be6b06d` is pending, and no GitHub release has been published.

The exact independent review is retained without transformation in [candidate510-independent-review-r01.json](../../spec/evidence/candidate510-independent-review-r01.json), SHA-256 `d6639bb8959b479344d1b23a17aad5ea00f6a16845d3fb06c433ee96764f9e16`.

## What failed and what the candidate changes

Published 5.0.21009 reproduces the duplicate `worker-robots-storage-4` preflight failure with the selected worker provider. The candidate preserves the provider's finite 4–7 chain, emits MIR `worker-robots-storage-8` after its actual endpoint, and leaves an external infinite level 8 alone when the provider owns that tail.

The earlier Space Is Fake behavior targeted a small continuation-name set, which could miss the final emitted catalogue after policy and gate processing. The candidate applies the retired-space-role policy at final science binding so that the affected final output removes retired white science without globally deleting still-valid science, gates, effects, or foreign research.

## Affected observations

The finite default, finite SIF, verified-upstream-source reconstruction, and provider-infinite data-stage captures pass for the accepted source. They show the expected finite handoff or external infinite owner; the source reconstruction is based on selected verified upstream blobs, not an official WorkerRobotCargoSizeResearch download and not the reporter's full modpack.

The expanded all-science and end-game-gate capture, driven by controller `fcb364cda9229e1679fc6b6c8eff02323efabdab`, checks 130 MIR-added technologies against the no-MIR upstream difference and reports no retired white science in the applicable final output. It is a Factorio data-stage observation, not a gameplay or save claim.

The Base and combined SIF/worker native fixtures on Factorio 2.1.23 each complete a real MIR level-8 lab research, preserve foreign finite levels 4–7 with their +1 effect, and pass two byte-identical cold reloads. The combined fixture also witnesses the retired-white-science result.

The expanded all-science plus space-gate native profile at reconciliation head `be6b06d` also completes real MIR level 8 to level 9/bonus 8, retains foreign finite levels 4–7, observes retired white science absent, and passes two byte-identical cold reloads.

The provider-first boundary begins with controlled prerequisites only through provider level 6, then earns provider level 7 through a real biolab completion. That provider-only save passes two byte-identical cold reloads; adding corrected MIR first verifies the preserved state before test stimulus, then completes real MIR level 8 and again passes two byte-identical cold reloads.

The native values 0.42 and 0.27 are controlled progress-preservation sentinels, not earned science. The actual research witnesses are the explicitly recorded provider level-7 and MIR level-8 lab completions.

## Rejected controller observations

Controller version 0.1.0 tried to read unsupported `LuaTechnology.amount` while it only needed prerequisite names; `1e046ae3c08a601942efc5984c4cc96edd959a69` corrects that fixture API use. Controller version 0.1.2 confused current research progress with another technology's saved progress; `1e571eb5` corrects the observation and `5b24c839f30081e20c621097f0576499ac5e89c2` clears a stale reload flag before first add.

Those are preserved adverse controller results, not product pass/fail evidence. They are why the retained record identifies the exact controller revisions and does not reuse an earlier fixture result as if it were later controller evidence.

## Boundaries and next work

The positive save route is an earned provider level 7 followed by first addition of corrected MIR; it does not claim safety for a provider add, removal, or change after MIR worker research is already earned. Existing 4.7.3 Linux native evidence remains evidence only for its original scope and is not relabelled as 5.0.10 coverage.

The bounded follow-up is to retain source-level finite/infinite provider reproductions, one candidate-specific SIF-plus-provider normal-pipeline capture, and the small native first-add controller with exact fixture API/property checks. This is targeted regression maintenance, not a repository reorganisation or a new testing campaign.

Before any GitHub prerelease, the reconciliation-head CI, frozen inventory and asset hashes, administration and immutability probes, staged-asset checks, anonymous download hash verification, and local `dist` custody must pass. Publication must remain a prerelease and must describe these boundaries accurately.
