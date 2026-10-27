---
title: "Synthesized design and decisions"
status: current
applies_to: "MIR development"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-10-27
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-design-guide
---

# Synthesized design and decisions

## Adopted design

MIR uses a small **Generator** to construct native technology prototypes from authored definitions and effective settings. Keep exact, explicit compatibility rules outside it. Preserve the complete applicable product, not the old machinery.

Unify public extension terminology as **MIR API**. Its data and runtime surfaces follow Factorio lifecycle boundaries. The **SDK** is developer material that demonstrates and checks those interfaces. It is not another in-game execution platform.

The existing MEP was a separately distributed data-only preview with no authorized player emission. This is a controlled interface transition, not a claim that the old and new APIs are identical. Audit real consumers before removing their contracts. The inspected `docs/EXTENSION-PROTOCOL.md` is a historical input; do not implement its planner workflow again.

## What the supplied plans taught us

The strongest common idea is reducing responsibilities, not replacing one large representation with another. Explicit declarations, independently observed effects, native engine behavior, stable IDs and bounded tasks are retained.

The adopted contracts resolve source placement, omission policy, complete applicable Library/runtime parity, bounded collection and native formula ownership. The canonical `source/` tree implements those responsibilities; exact unfinished qualification stays in the progress record.

| Decision | Reason |
|---|---|
| One `source/` player root | The inspected repository explicitly selects it; staging is a path convenience, not a permanent major-version architecture. |
| Generator in prototype stage | Current mods/settings/prototypes exist there. No external preprocessing dependency or custom packed research artifact. |
| Native-shaped tables | Avoid a second schema, IR, expression language and schema-to-code compiler. |
| Immediate data API | A dependent extension may execute after MIR's finalizer. No queue that assumes a later MIR pass. |
| Minimal runtime queries | No arbitrary callback hosting, hidden registration registry or whole-configuration dumps. |
| Explicit small copies at ownership boundaries | Pure-looking constructors can still alias caller arrays. Test isolation without a certificate/proxy framework. |
| Necessary collection outside Generator | Preserve existing broad recipe/settings behavior without per-family whole-world scans or invented research. |
| Complete stable-release parity | Smaller code is not equivalent if it removes Library, caps, migrations, settings or useful integrations. |
| Canonical unversioned roots | Player source, requirements, docs and tooling use their final responsibilities; historical inputs retain exact immutable references. |

## Things not to promise

Performance evidence retains its exact workload and source identity; a final-current-package performance verdict remains open. No finite test suite proves universal crash-freedom. Expected constant-time named lookup does not make arbitrary output constant time. Supporting more active effects creates real work. Offline inventories, small native tables and a short Generator reduce risk; only observed native results establish improvement.

Continue from the exact completed native observations rather than replaying them under a new name. Remaining migration, mod/settings, client, runtime and stress cases follow the ordered progress worklist. Matched same-output replay and menu measurements supply the separate performance verdict.

## What stays out

No production compiler/planner/solver fallback, whole-world snapshots, generic patch language, recurrent native-bonus handlers, mandatory MEP transport, SDK in the player ZIP, automatic copying of all preview systems, new always-on instrumentation or universal agent-management framework. AIDE may assist externally after demonstrating value, but does not own research or release truth.

## What must not disappear

Existing IDs and tuning; settings defaults and sentinels; broad targeting where delivered; native owners; hidden carriers; earned-above-cap behavior; global/scripted contribution baselines; useful Library behavior; historical target subsets; migration scripts still required; known regression expectations; original request IDs and unresolved decisions.

The authoritative details are in the [specification](../spec/README.md). This page is explanatory, not a duplicate second specification.

## Refinements in this revision

Determinism now has its own focused contract rather than an absolute slogan. The final picture separates setting declaration, effective values, startup prototype construction, engine retention and save runtime. Released identities do not enter a generic skip branch. Local-family forward references, input/output alias isolation and immediate extension publication have explicit boundaries.

The API draft uses an independent major namespace and adds only the finite-family operation justified by forward prerequisites. Native-owner patches remain narrow; metadata discovery, callback hosting and a universal status registry are not prerequisites. The visual atlas is derived from one graph catalogue and remains outside player packages.
