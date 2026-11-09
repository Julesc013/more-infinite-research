---
title: "Prepared MIR-default to full Ferrum worker transition observer"
status: prepared
applies_to: "Exact Factorio 2.1.23, MIR 5.0.21012 and Ferrum 0.1.5"
audience: developer
doc_type: test-fixture
owner: mir-maintainers
last_reviewed: 2026-11-10
supersedes: []
superseded_by: []
---

# Prepared MIR-default to full Ferrum worker transition

This new scenario observes **existing MIR before adding Ferrum**. It does not rename the earlier provider-only Ferrum-to-first-MIR lab/save/cargo result. The player source and all older fixtures, controllers, saves and adverse results remain unchanged. Host physics and preparation are explicitly models; actual research, preparation, configuration, closed saves and cold reloads require a separately reviewed controller and engine execution.

Use the identical `control.lua` as the embedded scenario `__level__` actor throughout. Do not install it as a mod control: its configuration callback records the native frame before MIR, and its next tick checks the settled frame after all configuration callbacks. Preserve both observations on refusal; no native difference is silently attributed to MIR or normalized away.

The lab is a separate disposable data-only mod. It clones only the ordinary lab into its own void-energy speed1001 lab, defines an effect-free continuity sentinel and an unresearched calibration row, and changes only its explicitly owned startup defaults to cap8/enabled. It leaves every worker cost, effect, prerequisite, science contract and ordinary researched flag alone. It accepts only existing science items/tools and includes space science; **actual Ferrum** must add robotics through its final lab patch. The old `4EFF` lab archive/body is not rewritten or reused with a different identity.

## Exact inputs and independent obligations

- Source: Base/Space Age/Quality/Elevated Rails/Recycler2.1.23, MIR5.0.21012, lab0.1.0 and the existing ActiveMods observer0.1.0. Destination adds only official Ferrum0.1.5, PlanetsLib2.4.0 and Spider Launcher2.9.87. No other mod/version or startup setting change is admitted. F200 is deliberately outside this fixture's exact tuple; the existing separate F200 evidence retains its own identity.
- Administrative source prerequisites grant only finite worker1–3 and non-worker science prerequisites. Native bonus3 is checked. The player then earns four default infinite worker completions through actual labs; another force earns three. Both continue to actual native partial worker work (next8 at least.35, next7 at least.27). The latter suspends that work behind unrelated current sentinel progress. An uninvested force keeps worker4 disabled and unrelated current work. No infinite level setter obtains these earnings or partials.
- Before adding the provider, `/mir-worker-storage-recovery prepare` must actually run twice under the unchanged selection. The observer checks the first transferred frame and requires the second to be identical, including native bonus, full work contract, current/ordered queue/saved work and flags. Transfer-generated native callbacks are recorded separately from ordinary completions.
- Provider entry requires exact private/earned/current/queue/suspended preservation, unearned finite4/5, unearned MIR6, retained original finite4 flags and no overlapping public7/8. It compares the independently retained default private contract, not a count reconstructed from clamped current worker4 or an aggregate bonus.
- Each pending private level completes ordinarily, then retires disabled. A controlled queue selection temporarily suspends the unrelated sentinel; its exact previous current/queue/progress/saved frame is restored. The real recovery `resume worker-suspended` command must first append private work without changing the unrelated current. Actual external queue-event ordering remains a native gate; host scheduling does not qualify it.
- Player Ferrum4 and5 then each complete through actual labs, followed by useful MIR6. Entry-unearned assertions remain distinct from these intentional later earnings. Costs675/1012, time60seconds (runtime3600ticks), effect1 and six Ferrum packs stay exact. MIR6 retains `1518.75*1.5^(L-6)`, all seven packs including robotics/electromagnetic and its exact prerequisites. Its native initial integer count is compared to an independent hidden/disabled/effect-free constant-formula `1518.75` calibration technology at map multiplier1; the actor chooses no floor/ceiling and never researches that calibration.
- Every ordinary completion requires `by_script=false`, observed intermediate progress and depletion of every required science pack. Fresh work consumes its exact native evaluated budget; carried partial work records positive bounded actual consumption. Every completion stops the lab and defers selection until a later tick. Final player benefit is11, suspended-force benefit7, uninvested benefit3; all unselected forces and non-earned frame fields remain exact. Physical robot cargo/delivery is explicitly **unperformed for this transition**.

## Minimal governed four-process contract

1. Source server starts the owned scenario. Wait for `source-save` and the closed `mir-ferrum-transition-source.zip`. CRC/hash-check and copy that unprepared save into protected custody **before** issuing any preparation command. While the same unchanged-selection server remains alive, send `/mir-ferrum-transition-probe begin-prepare`, actual `/mir-worker-storage-recovery prepare`, `/mir-ferrum-transition-probe check-prepare-once`, actual `/mir-worker-storage-recovery prepare` again, then `/mir-ferrum-transition-probe prepared`. Require the first success/second idempotent replies, `prepared-save` and a distinct closed `mir-ferrum-transition-prepared.zip`; protect both originals. Do not end the process on the earlier source marker.
2. Destination server loads a new physical copy of the prepared save with only the three official provider archives added. Require the pre-MIR entry and settled `provider-ready`. Issue actual `/mir-worker-storage-recovery resume worker-suspended`, then `/mir-ferrum-transition-probe run-provider`. Require five new ordinary completions (two private, finite4/5, public6), `destination-save`, and the closed `mir-ferrum-transition-destination.zip`. Protect that save without editing/replacing its embedded actor.
3. A separate read-only one-update cold load of a distinct copy of the exact protected destination must emit exactly one `destination-saved-cold`, exit naturally0 and leave its ZIP bytes unchanged.
4. A second distinct process repeats the same immutable one-update check. No persisted cold counter, re-save, second gameplay update or changed actor is admitted.

Root owns the controller, exact archive/engine/package/SDK pins, proper frozen Git runner, real zero-native composition, admission and execution. Reuse the existing direct-library activation/owned-archive/resource/shared-live-log/save-closed predicates and loopback RCON helper; no new orchestration framework. Proposed unchanged bounds are one process at a time,4096MiB,180seconds and64MiB per selection, first-error stop and byte-exact archive/control/original-save restoration. No engines, archive builds, activation or package changes are performed by this source unit.

## Issue1845 scope

Existing reviewed credit/Secretas/prepared-default/post-transition results keep their exact scopes. This case closes no Ferrum transition clause until the four actual processes and independent result review pass. The preceding Ferrum data/lab/save/cargo proof was provider-only before MIR and is not this direction. Exact reporter save/mod histories remain unavailable; that is a limit, not permission to invent recovery inputs.

An already-clamped unprepared world still refuses and requires a protected pre-change original copy. Provider removal/readdition and changed continuations remain explicitly unqualified/refused by the production guard and support guide; this fixture neither tests nor promises them. The issue requests those routes **where promised**; current support makes no inverse-removal recovery promise, and the migration contract says absence cannot preserve state already discarded by the engine. No general or stable acceptance follows from this bounded addition case.
