---
title: "MIR 4.2 Compatibility Scope and Player Playtest Plan"
status: current
applies_to: "4.2.0 development"
audience: maintainer
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-09-27
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir42-player-compatibility-playtest-plan
---
# MIR 4.2 compatibility scope and player playtests

The maintainer has deferred compatibility playtesting until implementation converges. Their 27 September feedback covers browser/usability and reported command lag; it is not qualification of external mods. Keep automated integration work progressing without asking the maintainer to wait through every combination's loading screens.

The [operating programme](../../spec/programmes/mir4-4x-operating-programme-v1.json) and [81-request ledger](../../spec/programmes/community-requests.json) retain the accepted scope and individual decisions. This page organizes that scope for later player checks; it grants no support claim. Each delivered profile must identify exact engine, external mod versions/archive hashes, settings, MIR ZIP and the recipe/technology behavior proved. Support is bounded by actual eligible routes and ownership, not every recipe carrying a familiar material name.

| Area | Intended 4.2 outcome | Profile separation |
| --- | --- | --- |
| Base and official DLC | Existing research, science/prerequisite correctness, settings, caps, save upgrades and the intuitive research library | Base-only and Space Age; other DLC subsets only when they cover a distinct capability risk |
| K2 / K2 Spaced Out | Late science phase selection and eligible rare metals, imersite, silicon and glass manufacturing; retain upstream-owned productivity | Standalone K2 and K2SO as distinct supported-engine locks; K2 + Space Exploration only if their actual dependencies permit that lock |
| Bob's / Angel's | Requested aluminium, gold, lead, nickel, platinum, silver, tin, titanium, copper tungsten, zinc, bronze, brass, gunmetal, invar, cobalt steel and nitinol families; useful progression and continuous science demand | Bob-only, Angel-only and combined, with exact available outputs and excluded routes |
| OmniAB | Useful ordinary material routes, canonical ownership, rescue/progression preservation and extraction-tier lifecycle cooperation | Named dependency-valid suite subsets, with planet/alternative-start modes separately identified |
| Real Industrial Chemistry (RIC) | Useful manufacturing, mode-aware progression, laboratory handoff, closed-loop restraint and OpenPit ownership | `real-industrial-chemistry` with its actual dependencies and modes; AAI coexistence is a distinct profile |
| AAI / BZ | Eligible manufacturing aliases, science/lab integration and coexistence | Actual suite contents and compatible versions; loader/container/industry evidence does not automatically cover the whole suite |
| Pyanodons / Space Exploration / IR3 / IR4 | Named useful compatible subsets, with explicit blockers for unsupported processes | Separate overhauls and engine lines; never combine incompatible overhauls into a universal test pack |
| Planet and Space Age ecosystem mods | Eligible routes and progression under named planets and starts | Test only admitted exact combinations and their distinctive progression/ownership risks |

The lower rows remain integration work or investigation, not promises of full-pack support. IR4 has a normal-path native load observation and five final-data recipe observations. Tin plate, bronze ingot, iron gear and steel plate explicitly disallow productivity and remain omitted. The existing advanced-circuit research also needs review: its retained MIR science/prerequisites differ from the observed IR4 unlock. The five-fact runner failed its footprint limit despite native exit zero; neither run qualifies recipe coverage or gameplay. The exact failed receipt and facts are retained under `build/private-probes/mir42-f200-ir4-final-data-facts/run-6d179bb8f9d746f0ae60533e725ee7bc/`. Earlier old-archive failures on 2.1.20 remain failures. They are not silently relabelled as support for newer archives or another engine.

Existing narrow integrations also need affected regression checks: clean-filter crafting, ash separation, nuclear science-pack productivity, mining-drill manufacturing, loader/belt manufacturing, AAI container/industry coexistence, and coexistence with Fluid Must Flow, Robot Attrition, Jetpack and Equipment Gantry. Their [support lanes](../../spec/compatibility/support-lanes.json) preserve the exact behavior boundaries. Recovery/recycling/recolouring/compression loops and upstream productivity denial stay independently reviewed; no blanket productivity override is intended.

## What the maintainer will test

The converged preview will contain a short checklist and exact prepared profile locks. Start with base/Space Age and the maintainer's normal overhaul/save. Add only a representative profile for a genuinely different unresolved player risk: an industrial progression/ownership transition, a settings/save upgrade, or two-client browser/queue behavior. A Bob/Angel, K2, OmniAB or RIC walkthrough is assigned only when that profile's implementation and automated checks are ready. No current request asks the maintainer to test all profiles now.

Player tasks concentrate on visible outcomes: find and organize research without coaching; inspect benefits, science and startup setup; identify personally hidden versus verified not-added research; explicitly organize the force queue; research the next useful material level; compare first/repeated mass-research responsiveness; save/reload without losing the selected view or queue. A changed sort/filter must not reorder the force queue. Two clients may choose different views while sharing the same force research state.

Automated checks own recipe-level inclusion/exclusion, exact ownership, science reachability, caps and effect bounds, package contents, engine loads and controlled lifecycle cases. They select changed propositions and unresolved risks, reuse only exact trusted fingerprints, and run one heavy engine campaign at a time. Do not retest every item/recipe manually or enumerate the Cartesian product of modpacks. A fresh final candidate still needs its required checks; previous development evidence is reused only for the proposition and exact inputs it actually proved.

The release's actual support list will be generated from its qualified matrix and exact package manifests. The current library and public generation records must explain supported, absent and excluded rows without inventing technologies. Technology/settings identities and older supported engine contracts remain stable; capability-limited historical packages do not inherit all modern integrations merely because they share the 4.2 version.
