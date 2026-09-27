---
title: "MIR 4.2 Playtest Findings"
status: current
applies_to: "4.2.0 development"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-09-28
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir42-current-playtest-findings
---
# MIR 4.2 playtest findings

These are direct maintainer findings from 27 September 2026. They reopen player acceptance and define required 4.2 work; they are not controlled performance measurements or release qualification. The maintainer will return for another playtest in several hours or up to 24 hours and has directed implementation to continue without waiting. Retain every original community request identity and decision.

| Finding | Required outcome | Acceptance |
| --- | --- | --- |
| PF-01: Both invocations of `/c game.player.force.research_all_technologies()` caused major lag in 4.2; the maintainer reports that 4.1 completed instantly. | Remove repeated work in mass research processing and improve startup, command processing, save loading and ordinary runtime maintenance. | Bind the exact 4.1 and 4.2 packages, engine and mod/settings profile; measure cold/warm startup, first/repeated mass research and save loading. Exercise cap ownership, queue continuity, force reset/merge and configuration changes. Establish bounded callback work and preserve gameplay semantics. |
| PF-02: Browser labels initially lacked localization and then visibly resolved in sequence after pressing a button. | Provide localized discovery before page visits and a stable first usable view, with smooth bounded background indexing. | Display labels through native localization where appropriate; avoid visible identifier-to-label churn and translation-driven reordering of the open list. Search updates without resubmission, remains honest while indexing, and keeps actions bound to technology IDs. Exercise first opening, locale changes, late/missing callbacks and save/reload. |
| PF-03: Playtesters cannot identify the purpose or operate the browser; it does not help them organize research or view startup settings and absent research. | Make the existing surface an intuitive research encyclopedia and viewer with useful sorting, organization, explicit research-queue ordering, per-research startup settings, and clear views of generated, hidden, not-added and removed research. | A player can locate research, inspect benefits/science/settings, distinguish personal hiding from game availability and absent generation, and organize or explicitly reorder research through clear controls. Filtering alone never changes the force queue. Evaluate first-use tasks with players; extra explanatory label or tooltip text is not the remedy. |
| PF-04: Review engine and API additions from 2.1.7 through the latest available patch. | Adopt applicable capabilities and efficiency improvements through the existing engine-channel review, with narrowly scoped platform adapters. | Bind local engine/runtime API/prototype API/changelog identities; review each intervening official patch and record implemented, applicable pending and irrelevant changes. Preserve older engine contracts. |

The maintainer accepted the replacement shortcut button. Preserve it. Preserve the native research window and existing stable technology/settings identities. Startup settings remain restart-required; viewing or exporting them must not claim live prototype editing. Absent rows require named catalogue/generation evidence, and the interface must not invent technologies or omission reasons.

The nine early development ZIPs are preserved at `dist/mir42-current-development-20260927`. Exact package/engine/profile identity for the reported session still needs confirmation; the existence of that delivery alone does not establish which bytes or other mods were active. Future tested previews must have an obvious latest-preview entry in primary `dist`, exact hashes and visible validation limits. Older playtest packages and their receipts remain immutable.

The maintainer has not yet playtested external mods or compatibility and will do that closer to completion. Do not ask for the complete ecosystem matrix now. Automated checks select changed propositions and unresolved risks, reuse only exact matching trusted evidence, and avoid repeating unaffected load campaigns. The converged preview must include a short human checklist, exact compatible profile locks and the support scope actually proved for each recipe family. The maintainer authorized closing the current Steam session for unattended checks; it had already exited when closure was attempted, so no process was stopped.

## Current development changes

Code review identified repeated maximum-level policy validation on research completion and repeated catalogue/frame construction for an open browser. The current changes cache only validated plain policy outcomes until the configuration lifecycle, keep force and queue checks live, and coalesce an open force's research events into one next-tick refresh. The one-tick subscription exists only while work is pending; load rebinds it without modifying saved state.

Research captions now use native localization. Asynchronous indexing prioritizes the selected research and visible page. Partial callbacks update only an indexing indicator, and localized search or name ordering refreshes once the index settles while retaining the frame, search field and scroll pane. Browse, Queue, Setup and Availability separate the visible tasks. Availability consumes validated, copied generation omissions; it does not infer removed save history.

PREVIEW3 uses package-source fingerprint `F758A8BB4C8FD3509FC8A42B0A2F2FBF45CFB6E21DE7A8961EB8CB5037F62F23`. Its F210 and F200 direct canonical browser checks each passed 93 assertions on Factorio 2.1.20 and 2.0.77. Both were headless with zero native players, so first-use graphical usability, focus/scroll behavior, two-client interaction and actual pending-callback save/reload remain unqualified. The formal assurance attempts stopped on a stale housekeeping lock before testing; the separate direct results are development evidence rather than formal gate passes. The selected programme and development-CI checks also passed directly.

## Scoped command performance observation

The native base-only Factorio 2.1.20 command comparison reproduced the reported regression and measured the optimized PREVIEW3 package. Each exact package used a fresh private save and the real `force.research_all_technologies()` call, with native Factorio profiler log values. No graphical player or browser action was present.

| Exact package | First command | Repeated command | Completion events, first / repeat |
| --- | ---: | ---: | ---: |
| Published 4.1 F210 | 154.937 ms | 43.680 ms | 250 / 63 |
| Preserved early 4.2 F210 | 6,373.641 ms | 1,446.626 ms | 249 / 62 |
| Optimized PREVIEW3 F210 | 98.141 ms | 15.095 ms | 249 / 62 |

These are single observations rather than a statistical benchmark or a general startup/save-load claim. The two 4.2 observations had the same completion-event counts; the optimized command was about 65 times faster on its first call and 96 times faster on the repeat in this scope. Static diagnosis identifies repeated policy validation on the completion-event path; caching removes that repeated work while retaining live force and queue checks.

The primary checkout's `build/tmp/mir42-integration/preview3-performance-terminal-readback.json` binds exact packages, engine, native logs and retained failed wrappers. This private evidence is intentionally excluded from Git and player ZIPs. The 4.1 and early 4.2 harness failures remain failed even though their native timer/counter facts were independently verified. The optimized benchmark exited naturally with code zero. Its earlier create wrapper also remains failed after a temporary-file enumeration race; the successfully created exact save was retained for the one remaining benchmark. Existing saves, startup loading, caps/configuration lifecycles and an open browser remain separate acceptance work.

The updated F210 and F200 development packages are in the primary checkout's `dist/mir42-preview-performance-20260927`, with their source, narrow browser checks and this performance record bound in the playtest manifest. The local `dist/LATEST-MIR42-PREVIEW.md` instructions identify the current Steam package and the deferred compatibility checklist. These delivery files are intentionally excluded from Git. This delivery grants no release qualification or publication authority.

## Native graphical follow-up

On 28 September, a private base-only PREVIEW3 load on Factorio 2.1.20 produced five engine-rendered screenshots with one connected player. The first capture still showed the game's load-consistency overlay; it does not prove the first usable browser frame. The settled Browse screenshot showed localized technology captions. Setup displayed `nil` for false-valued startup settings, Availability displayed no omissions, and the navigation buttons did not identify the selected view. The freeplay cutscene was still active, so focus, Escape handling and ordinary player interaction remain unqualified.

The graphical attempt and image review are retained in `build/private-probes/mir42-f210-preview3-graphical-v2`. Its predecessor stopped before private-profile loading when Steam requested a restart and remains a failed attempt. The successor used the official Steamworks development AppID hint in its private working directory; installed Steam files were unchanged. After all capture stages, the wrapper closed its own process as planned. Native exit `-1` is recorded as that forced closure, not natural engine success.

A separate two-tick native headless diagnosis of the unchanged PREVIEW3 ZIP found 98 sealed generation rows and 51 valid omissions with a matching public fingerprint. The provider supplied those omissions correctly. The UI discarded the whole view when a known stream used its ordinary canonical localized title rather than an explicit name override. The corrected view uses that established title for known streams and retains rejection of malformed or unknown identities.

The runtime startup reader also collapsed a present `false` into `nil`, and effective-profile export could replace a resolver's `false` with the direct setting's `true`. Both paths now preserve false values. Navigation buttons use the engine's native toggled state. The existing browser fixture tests native false-value/profile behavior and records connected-player count and whether native GUI assertions actually ran. Factorio cannot create a player through LuaGameScript; a discarded fixture attempt using that nonexistent API remains a failed check. Zero-player headless checks do not establish native GUI coverage, rendered-client usability, actual localization timing, save/reload or two-client acceptance.

The exact PREVIEW4 F210 ZIP passed 98 canonical controlled headless assertions on 2.1.20 with zero players. A separate one-launch graphical observation, retained in `build/private-probes/mir42-f210-preview4-graphical`, exited its private freeplay cutscene through the documented player API. Its five capture stages had one connected player and an opened browser frame. Native assertions checked all four tab states, ten false-valued startup settings and the canonical localized omission-title path. Image review confirmed highlighted navigation, `false` values in Setup and visible not-added rows. Closure was again planned and forced; these observations do not grant release qualification, Escape/input or two-client acceptance.

The new images also retain unresolved presentation defects: Browse has no initial benefit/detail subject, Setup repeats long setting titles and unrounded decimal values, and an omitted Space Age capture-robot stream references an item locale unavailable in base-only play. These remain browser work, not accepted usability or localization outcomes. The existing PREVIEW3 command timings belong to its earlier bytes and are not rebound to PREVIEW4.
