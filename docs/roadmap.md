---
title: "MIR5 roadmap"
status: current
applies_to: "MIR5 stable completion and compatible 5.x evolution"
audience: maintainer-and-contributor
doc_type: roadmap
owner: mir-maintainers
last_reviewed: 2026-11-28
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir5-milestone-sequencing
---

# MIR5 roadmap

The [completion plan](implementation/mir5-completion-plan.md) defines the design and 16 work packages. This page orders outcomes; [TODO](todo.md) selects assignments and [progress](progress.md) records actual implementation, qualification and delivery. Milestones have evidence-based exit conditions, not invented dates or completion percentages.

## Milestones

| Milestone | Outcome and packages | Exit condition |
| --- | --- | --- |
| 0 — One current programme | WP-01/14: reconciled audits, current entry points, existing IDs/owners, actionable plan/spec/TODO/roadmap | Checked documentation integrated into `dev`; no claimed runtime repair or stable verdict from planning alone. |
| 1 — Safe next correction | WP-02/03/04/08: existing cap/worker fixes, original-case discrimination, bounded diagnostics and option help | Each included repair has an old-source regression, applicable exact native preservation and reviewed limits; package and release gates pass for declared maturity. |
| 2 — Coherent stable MIR5 | Applicable WP-02..10/13/15: delivered parity, useful supported integrations, saves/clients, Library and valid resource evidence across intended stable subsets | Independent feature, profile, migration/client, performance, non-regression/determinism and artifact verdicts apply to one frozen candidate. Required known failures remain blockers; permitted unavailable histories remain explicit support limits. |
| 3 — Easier compatible extension | WP-05/06/07/11: compatible minor readers, cohesive worker/current-policy modules and real external infinite-family capabilities | Existing saves/API consumers remain compatible; a built-in instance and independent companions use documented shared semantics; physical output and applicable save/client outcomes are established. |
| 4 — Lower maintenance and release cost | WP-09/12/13/14/15: measured Library improvements, Python portable seams, independent test builders, concise docs and repeatable release assembly | Duplication and unnecessary work removed with actual callers, custody and gates preserved. No parallel legacy/new orchestration authority remains after each cutover. |
| Separate research | WP-16: genuine-release timing, visibility and acquisition | Metric validity, bounded data collection and defensible uncertainty before optimization; no effect on product safety or required release timing. |

These are not serial waiting rooms. Required preservation fixes and their counterexamples come before a broad rewrite. Independent tooling/documentation and extension design can advance while native work is owned elsewhere. A correctness-enabling extraction can precede stable; optional reorganization is not a new stable prerequisite. Existing applicable delivered behavior cannot be moved to milestone 3 merely to make milestone 2 easier.

## Version and release policy

The next changed public source version is selected against actual live tags/releases at freeze; the intake expected `.28` after published `.27`, but builds, commits and documentation updates consume no number. Preserve the held `.25` disposition and every published byte. Source-minor rollover requires WP-05 and its applicable native evidence; an API addition alone does not force a product-major rewrite.

Keep the existing [release opportunities](development.md#source-release-versions-and-maturity), including the recorded daily qualified-beta opportunity at 18:00 Australia/Sydney and checked urgent corrections. This roadmap changes neither that schedule nor publication authorization. A suggested weekly planning review may organize work, but does not replace the current release policy or require a weekly minor. A candidate ships only after its applicable gates; the calendar cannot supply acceptance.

GitHub maturity, Portal availability and stable acceptance are separate facts. Agent-managed releases remain GitHub-only under the existing contract; the maintainer owns Portal actions. The observed `.27` Portal presence must not be used to silently amend channel policy or declare all edition artifacts verified. This roadmap authorizes no publication action by itself.

## What long-term success looks like

An ordinary family or provider instance uses existing declarations and operations with focused checks. A new semantic operation has one clear owner, bounded work and independent evidence. Historical readers retain authentic old facts, while current settings and public API capabilities evolve deliberately. A contributor can find the owning source and run real local commands without reading the historical evidence archive. A release owner can determine the candidate and unresolved gates from a concise current view.

The product remains MIR5 while these public/saved contracts remain compatible. Internal code is free to become smaller and more cohesive. No fixed LOC quota, universal mod support, permanent bug-free guarantee or promise that maintenance will end is part of this roadmap.
