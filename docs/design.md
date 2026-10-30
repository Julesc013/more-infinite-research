---
title: "Synthesized design and decisions"
status: current
applies_to: "MIR development"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-10-30
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

## What changed, and what startup still does

MIR 4.7.3 constructed research through stream/base-continuation plans, qualification and compilation records. MIR 5 selects authored definitions, constructs detached native technologies, checks their consumed references and publishes the complete owned family once. Keeping the intended technologies, settings and earned bonuses is the preservation requirement; the construction machinery changed.

The startup-path review at `44cf71d5c73e1ebb60f08c1ef49dcd7b5ba667b7` found these remaining costs. These are source observations, not elapsed-time measurements or a proof that every modpack is valid.

| Path | Work and boundary |
|---|---|
| [Catalogue construction](../source/research/modern.lua) | Copy selected authored fields into owned native tables and resolve their settings. Output size still matters. These copies prevent later writes from changing shared definitions. |
| [Product targeting](../source/research/product_target_extension.lua) and [collector](../source/compatibility/product_targets.lua) | Prepare the selected bindings once and share one recipe/product pass across eligible families. With no eligible rules, skip that pass. Literal rules avoid item-pattern enumeration; enabled patterns compare selected rules against relevant item/entity classes or recipe names, so their cost also depends on pattern count. Sort actual matched output, not a serialized world. |
| [Science projection](../source/research/science.lua) | Share one prepared lab view and cached lab decisions across the owned family. The opt-in all-science policy and failed named-source replacement have separate bounded direct-source collections. The default path does not use those collections to reconstruct foreign researchability. |
| [Generator](../source/research/generator.lua) | Check submitted native shapes, exact consumed references and cycles within the submitted family, then publish once. No foreign technology discovery, fixed point, world fingerprint or future-level enumeration. Invalid submitted input can still deliberately refuse startup. |
| [Finalizer and overrides](../source/data-final-fixes.lua) | Perform the selected native-owner/compatibility checks, preserve credit identities and apply enabled patches. A whole-recipe override necessarily visits its recipe domain. The named prerequisite repair can inspect its relevant reachable prerequisites; it is separate from ordinary generation. |

Existing [collector](../tests/test_product_targets.py), [extension](../tests/test_product_target_extension.py), [science](../tests/test_science.py) and [Generator](../tests/test_generator.py) opponents check shared passes, inactive paths, unrelated-domain growth, preserved foreign state and publication boundaries. They establish work shape and correctness on those inputs. They do not measure startup, large-factory update time, retained memory or the original severe-loading incident.

The [performance table](support.md#performance-claims) separates player-visible totals from MIR-associated increments. In the accepted F210 Base experiment, the published median is 11.2465 seconds and the candidate median is 10.6683 seconds, saving about 0.58 seconds overall. Subtracting the same no-MIR median gives a much larger descriptive percentage reduction of the small observed increment; it is not direct Lua timing or a confidence interval. The separately qualified Bob/Angel/Space Age experiment saves about 2.60 seconds overall on its own exact candidate and inputs.

The reported multi-minute/hour cases still need a grounded before/after diagnosis. A short Generator, a small Base increment or a previously accepted large-profile result does not close that question. Locate the delayed phase in the original engine log, preserve an old release's error or timeout as observed, and test the uninstrumented candidate under declared controls. Change a remaining operation only when its consumer, required invariant and opposing evidence justify the correction.

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
