---
title: "MIR5 completion and long-term engineering plan"
status: current
applies_to: "MIR5 completion and compatible 5.x development"
audience: maintainer-and-contributor
doc_type: implementation-plan
owner: mir-maintainers
last_reviewed: 2026-11-28
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir5-completion-work-packages
---

# MIR5 completion and long-term engineering plan

## Decision and scope

Complete MIR5 and evolve it through compatible 5.x releases. Preserve its native research model, small deterministic Generator, shared edition source and public identities. Concentrate redesign on ownership, saved-work preservation, cohesive feature boundaries, useful public extension capabilities and a simpler developer loop. Reduce duplicated policy and unnecessary work; do not reduce the product, erase history or hide complexity in a large data interpreter to obtain a smaller line count.

The maintainer requested this consolidated programme on 28 November 2026, including source, tooling, documentation, API, support and release improvements. This document is the accepted implementation direction and work-package catalogue. It does **not** assert that proposed code exists or that a stable verdict has passed. The [specification](../../spec/README.md) owns behavior, the [existing request ledger](../../spec/programmes/community-requests.json) owns the original 87 decisions, the [continuity inventory](../../spec/inventory/continuity.json) owns the 17 carried subjects, and [progress](../progress.md) owns current execution/evidence. [TODO](../todo.md) selects the next work; [roadmap](../roadmap.md) sequences it. These views link the same packages rather than creating another request database.

**Evidence baseline:** the five supplied audits and source atlas largely inspect `7a61a657bfc61f10a57ff6e4434ee8db2c070bde`. Repository inspection for this synthesis starts at `cf9403eccd42192b4049a3ada4634f5aba4b98d0`, whose additional [PR #2500](https://github.com/Julesc013/more-infinite-research/pull/2500) identifies failed legacy-worker admission predicates. That is a diagnostic change, not proof of original-save admission. Refresh the actual branch and active PRs before each implementation batch. Supplied pasted texts are earlier assistant reports, not a complete authenticated transcript of every user conversation. Their observations are dated evidence; their suggestions become requirements only through the decisions and existing contracts identified here.

## Current facts, limits and existing work

| Subject | Observation at intake | Consequence |
| --- | --- | --- |
| Published source | GitHub `v5.0.27` is a prerelease, published 27 November 2026; main/tag source is `30e2f04abd5e49d4efb7497e289335dd1434c698`. | Published bytes remain immutable inputs. New dev changes are not a new execution of that release. |
| Held candidate | GitHub `v5.0.25` remains an unpublished draft; later `.26` and `.27` are public. | Preserve the adverse upgrade history and draft disposition; do not publish `.25` merely to fill a sequence. |
| Portal | The public page was observed on 28 November displaying a `.27` edition, including latest-listed `5.0.10027`. | Portal presence does not establish stable acceptance, every edition's delivery or package equality. The maintainer owns that channel. Reconcile standing channel-policy wording explicitly; no publication waiver follows from this observation. |
| Active preservation work | [#2498](https://github.com/Julesc013/more-infinite-research/pull/2498) changed shared worker queue handling; [#2501](https://github.com/Julesc013/more-infinite-research/pull/2501) proposes ordinary-cap readback. | Inspect ownership and merged state; adopt the existing counterexample/change and qualify affected paths rather than implement a competing fix. |
| Active settings/status work | [#2502](https://github.com/Julesc013/more-infinite-research/pull/2502) proposes 110 visible option explanations; [#2503](https://github.com/Julesc013/more-infinite-research/pull/2503) updates current release status. | Review integration, translation/fallback and native rendering independently of source/CI completion. Do not call open PRs merged. |
| Historical native results | [#2499](https://github.com/Julesc013/more-infinite-research/pull/2499) records exact historical upgrades. | Review the original source/package/save and consumed-input applicability; a result-record PR is not a new run on current dev. |
| Original cases | #1806, #1871, #1942, #1944, #1959 and #1961 remain open at intake; #1768 tracks Library and #446 stable acceptance. | Keep each original report's unresolved scope independent of representative successes. |
| Public API | The documented API 1.0 subset is implemented and has scoped evidence. It does not admit ordinary infinite-family declarations, formulas and arbitrary native presentation. | Preserve the current API; implement the expanded capability as an explicitly versioned, tested addition. |
| Stable acceptance | Library timing/retained memory, affected transitions, carried parity and coherent final-candidate applicability remain unfinished. | Neither beta publication nor a passing host suite is the stable verdict. |

Repository census at the intake commit, using tracked-file physical lines including blanks/comments: `source/` has 158 Lua files / 42,269 lines; worker storage 3,817, Library controller 3,437, bootstrap 916, Generator 143. `tools/` has 26 Python files / 10,468 lines and 33 PowerShell files / 15,021 lines; `tests/` has 241 Python files / 133,208 lines and 682 Lua files / 57,983 lines. These are reproducible footprint baselines, not complexity scores; Python files include embedded Lua and some PowerShell includes embedded C#. Different reports' counters must not be combined as a measured trend without the same method and revision.

## Target architecture and deliberate limits

The normative refinements are in [architecture](../../spec/architecture.md), [migrations](../../spec/migrations.md), [runtime](../../spec/runtime.md), [API](../../spec/api.md) and [repository](../../spec/repository.md). The following map explains the design and the cost of each boundary.

| Responsibility | Intended owner | Boundary that keeps it small |
| --- | --- | --- |
| Current family/settings facts | Cohesive ordinary Lua declarations shared only where stages need the same identity or setting fact | No independent copies of current defaults; no production JSON catalogue/compiler. Frozen predecessor facts remain independent. |
| Current research construction | Existing constructors and finite Generator validation/publication | Native tables and formulas; explicit effects and references. No global discovery solver, runtime imports or mod-name branches in the Generator. |
| Provider compatibility | Explicit activation, named bindings and narrow capability adapters | Reuse existing semantics for new names/numbers. Optional absence exits before expensive imports/scans. Different economics or ownership remains a real distinction. |
| Historical interpretation | Small readers for actual published producers and persisted schemas | Return authenticated facts. Never derive an unknown paid price, mask or owner from current defaults or aggregate bonuses. |
| Native observation | Bounded readers with an explicit lifecycle/force scope | Complete-empty, unavailable, malformed and legitimate event-transition observations stay distinct. A frame does not itself grant write authority. |
| Transition admission | Feature-specific decision using known history and current observations | Select a named operation and expected preserved fields; no engine writes and no general serialized transaction language. |
| Native application | One writer for each owned operation | Revalidate at writes, handle reentry and verify outcomes. Preserve foreign fields. A failed setter postcondition is not success or a promise of automatic rollback. |
| Feature lifecycle | Worker, caps, credits and necessary scripted-effect modules | Thin event wiring; ordinary events target the affected force/family where valid. Configuration retains required all-force preflight. |
| Library | Per-player view/state, read-only research projection, rendering/input and translation lifecycle | No second research queue, migration authority, closed-view polling or unconditional refresh. Separate a mechanical move from behavior changes. |
| MIR API / SDK | Versioned capabilities and independently installable examples | Public calls share supported internal operations, detach caller data and preserve ownership. No callbacks, arbitrary patch language or third-party save authority. |
| Developer workflow | One maintained implementation per portable task, narrow OS adapters | Python is the consolidation direction; working PowerShell commands remain real until replaced and verified. No parallel scheduler, runner or evidence platform. |

**Data-driven means extending understood semantics with facts.** A new engine capability or preservation invariant may require a small readable operation. Moving branching into strings, callbacks, giant generated tables or an interpreter does not satisfy this design. Equally, one special case's historical price cannot be generalized away because its data looks similar to another case.

**Compatible evolution means stable contracts, not frozen internals.** Keep technology/setting IDs, public API semantics, published migration filenames, saved schema readers and edition identities stable. Product release, distribution edition, API major/capability and persisted schema are distinct axes. Internal modules and algorithms may evolve without creating MIR6. No design guarantees arbitrary-mod compatibility or zero future defects.

### Rules for decomposition

1. Name the responsibility, its owner, readers/writes and actual second consumer or safety boundary before extracting it.
2. Preserve public entry points and saved identities behind a small facade while moving one cohesive responsibility at a time.
3. Keep historical readers separate from live operations and independently frozen expectations separate from candidate declarations.
4. Do not combine mechanical relocation, behavior correction and performance optimization in one opaque change.
5. Delete the superseded active implementation after callers move and equivalence is established. Preserve necessary historical Git/artifact references; do not leave a permanent dual system.
6. Measure changed authority count, edit spread, imports, work, allocations and state in addition to LOC. A necessary correctness fix may initially add code.

## Work packages

Package IDs below organize execution; they are not replacement requirement IDs. A package is finished only when its listed endpoint is evidenced. Implementation, host verification, native qualification, delivery and original-report resolution remain separate. Dependencies are semantic; independent ready work may proceed while one native job runs.

### WP-01: Current truth and existing work

**Priority:** start now; maintain throughout. **Owners:** documentation/integration. **Contracts:** `REPO-01..03`, `VER-01`, `VER-07..08`, `CONT-15/17`.

Reconcile the active PRs, original incidents and recent release facts in the existing authorities. Mark old current-candidate/worklist entries as historical rather than overwriting their observations. Retain all 87 original IDs/text/decisions and 17 subjects. A source route, archive signature or implemented feature is not a completed qualification. Consolidate equivalent open PRs only after comparing their unique commits, tests and evidence; retain a disposition for every unmatched obligation.

**Exit:** the current progress entry identifies released source, selected candidate or absence of one, owned work, exact remaining gates and next decisive action. TODO and roadmap point to this plan and progress. No original case is closed through a release umbrella, and no obsolete `.4/.5` instruction is active by accident. Existing #2503 is reconciled rather than discarded.

### WP-02: Queue preservation at every actual writer

**Priority:** affected preservation before stable. **Depends on:** current owner/PR inspection in WP-01. **Contracts:** `RUN-02`, `SET-03`, `MIG-01`, `VER-02/03/08`.

Adopt #2501's ordinary-cap setter counterexample and common readback path. Enumerate real queue writers/readers in caps, worker storage, recipe/gun credits, Imersite, finite speed and bootstrap; share only equal semantics. Preserve ordered repeated entries, active/parked research, original paid work and foreign disablement. The native setter can silently omit unqueueable research; success requires a verified resulting frame. Keep unavailable observations distinct from empty queues and handle setter reentry without detached ownership ledgers.

**Exit:** the prior implementation fails an independent retained-entry opponent; the corrected caller detects silent omission, reorder, duplicate loss and failed readback without reporting success. Positive cases preserve unrelated work and write only once where intended. Run the minimum affected native/save/cold-load sequence on the actual candidate; #2498's affected worker routes retain their own replay. The separate sparse-Lua-table audit probe remains a robustness question until native reachability is shown, not invented proof of a current player crash. Do not add speculative rollback or a universal queue journal.

### WP-03: Original incidents and historical recovery

**Priority:** required supported failures before stable; unavailable originals remain individually explicit. **Depends on:** affected repairs, not completion of all restructuring. **Contracts:** `MIG-01`, `VER-03/07/08`, `CONT-07/11/15`.

| Original case | Next discriminating work | Boundary retained |
| --- | --- | --- |
| [#1806](https://github.com/Julesc013/more-infinite-research/issues/1806), first paid mask | Locate original producer/provider/settings history and determine which surviving fact can authenticate rights. | A known Base route cannot authenticate unknown original paid state. |
| [#1871](https://github.com/Julesc013/more-infinite-research/issues/1871), Ferrum addition | Recover the original predecessor state; compare its owner history with the controlled provider sequence. | Controlled removal/return success is not original-case closure. |
| [#1942](https://github.com/Julesc013/more-infinite-research/issues/1942), native credits | Resolve the reported 230/233 archive closure and exact original recipes/references; retain distinct failing versions. | Reduced F200 physical output and all-family host tests do not qualify the missing F210 original. |
| [#1944](https://github.com/Julesc013/more-infinite-research/issues/1944), worker upgrade/fresh initialization | Split reporter routes, including the reported 157-mod history and each fresh-init operation; reuse retained inputs before requesting them again. | Fresh and historical ownership are different admissions. Another reporter's success does not close this one. |
| [#1959](https://github.com/Julesc013/more-infinite-research/issues/1959), SE extraction | Credit existing scoped native measurements; recover actual factory/settings for the reported discrepancy. | Prototype or representative extraction success is not original-factory verification. |
| [#1961](https://github.com/Julesc013/more-infinite-research/issues/1961), K2SE science | Identify exact recipes/profile and native productivity permissions. | Do not override upstream denial or claim all advanced cards from a tested subset. |
| Freaky_Lord and #2500 | Use the failed-predicate diagnostic to identify the actual predecessor/history requirement. | Diagnostics, host checks and DEMEMZEA's separate reproducer do not prove repair. |

Retain DEMEMZEA/imkas's exact successes and changed-dev applicability; Jivaii/Sandeep's distinct initialization cases; and Driku's nondefault **2x research-cost** boundary. Preserve `SCI-UNLOCK-01`, `SCI-RESEARCH-01`, `COMP-TRUE-NUKES-01` and `MP-JOIN-01` in their existing ledger. Reporter silence is not acceptance.

**Exit per case:** original symptom and custody; old failing behavior; independently specified correction; applicable original candidate/native paid completion and save/client observations; verified delivery, or a precise unresolved/support disposition with the missing input named. Never guess lost rights to remove a refusal. Missing one case's inputs does not halt unrelated ready work.

### WP-04: Bounded diagnostics and usable support

**Priority:** independent low-cost repairs alongside preservation. **Contracts:** `RUN-04/05`, `VER-08`, `CONT-16`.

Complete the large-modpack diagnostic roster without truncating through a UTF-8 value or hiding the decisive owner/version. Distinguish required internal hooks from optional integrations; a required missing restoration interface must not silently disable its behavior. Recheck the catalogue's documented lifetime and malformed spoilage-state reachability before changing either contract. Include the available operation, source/engine/owner/schema, stable error category and relevant observed/expected values. Full settings, private paths and saves remain explicit support exports, not automatic telemetry.

**Exit:** focused formatter/contract opponents fail on the old source and verify deterministic bounded output, omission counts and missing-versus-empty behavior. A diagnostic-only change does not claim save repair or trigger an unrelated native campaign. A player can report a symptom without designing a test matrix; maintainers use existing custody and own diagnosis. A one-line report carries available decisive facts, never pretends to reconstruct absent history.

### WP-05: Record compatibility and minimal provenance

**Priority:** design now; fix before the first compatible source-minor transition, earlier if a present required route fails. **Contracts:** `MIG-01/02/06`, `RUN-02`, `API-01`, `CONT-11/14`.

Correct current product/edition decoding and tuple ordering so compatible 5.0 records are not rejected merely by 5.1 metadata. Keep deliberate historical producer bounds fixed where they authenticate a genuinely different format. Inventory every persisted record's creator, reader, writer, schema, cleanup and force/player lifecycle. Capture only the authentic facts needed for the next supported transition before they disappear; preserve original price/effect/setting provenance where required. No recurring full-history mirror or generic mutation journal.

**Exit:** actual current-record host controls accept compatible same-major/minor progression and reject unsupported future schemas or forged owners with zero unauthorized writes. Qualify the real future package when it exists; simulated metadata is not native 5.1 evidence. Save/configuration/repeat/cold-load behavior is idempotent. Published migration filenames and existing readers survive. The ownership table includes worker route, native owner, provider removal, engine checkpoint and SE policy records as well as existing state.

### WP-06: Worker and shared native-work boundaries

**Priority:** first structural implementation after the relevant counterexamples/frames are preserved; continue in bounded slices. **Depends on:** WP-02 and WP-05's contract, not a big-bang rewrite. **Contracts:** `ARCH-02/07/10/12`, `RUN-02/03`, `MIG-01`.

Separate frozen origin readers, current observations, admission, native application and operator/lifecycle commands behind the existing worker entry points. Move family policy out of bootstrap where it obscures event composition. Reuse queue/paid-work primitives in other actual consumers only after comparing their full semantics; worker economics and provider-specific history do not become Generator responsibilities. Ordinary completion should observe only the affected force/family when valid; configuration still preflights every affected force before dependent writes.

Explicitly settle provider removal -> force merge/reset while absent -> provider return. Define source/destination ownership, archival remapping/retirement and repeated application using native evidence; do not assume bonuses or histories add. A deleted/reused force index must not revive another force's work.

**Exit per slice:** one reason to change is isolated, the old duplicate active implementation is removed, callers retain their public/saved identities, adversarial histories still differ correctly, and applicable configuration/completion/provider/force/save/client cases pass. Native mutation retains pre-write revalidation and post-write observations. Record logic/declaration/import/state/work deltas; fewer files or shorter functions alone do not complete the package.

### WP-07: Current declarations and compatibility composition

**Priority:** fix required supported behavior before stable; wider additive integrations follow the roadmap. **Contracts:** `ARCH-06/09/10/12`, `COMP-01..03`, `SET-01/04`, `CONT-01/02/04/05/12`.

Consolidate current identity/settings facts that must change together, equivalent recipe/product validators and reusable native cost/science operations. Keep tuple/named ingredients, catalyst/probability, difficulty and return-value differences explicit until equivalence is proven. Replace incidental packaging-floor, icon or table-order predicates only when they are not part of the required economic/ownership contract. Harmless rename/order/cosmetic opponents and truly changed economics must produce different decisions.

Maintain dependency-valid, meaningful profiles for Base/Space Age, AAI, K2/K2SO/K2SE, SE, Bob/Angel/BobTech/Bob-core, BZ, Py, Armor, ATAN, IR3/IR4, planets, OmniAB and RIC according to their actual ledger decisions. Keep K2SO separate from K2SE, Bob alone separate from Bob+Angel and named supported subsets separate from full suites. Preserve the six OmniAB and eight RIC obligations, including exclusions and unpromised feasibility work.

**Exit:** adding an instance of an existing family/adapter changes declarations, activation and focused tests/docs without a new Generator or runtime mod-name branch. Verify useful research, ordinary effect/physical output, progression and applicable transition/Library behavior; load success alone does not establish compatibility. An unsupported existing identity is preserved or receives its explicit supported transition, never silently discarded to improve speed.

### WP-08: Product, settings and historical parity

**Priority:** all applicable delivered/accepted replacement behavior before stable. **Contracts:** all `CONT-01..16`, `SET-01..04`, `VER-07`.

Reconcile actual historical output, intended settings and test expectations by existing IDs. Finish #2502's native dropdown rendering and fallback/translation checks for the 110 visible values. Determine the two conditional assembling-machine/lab manufacturing families' actual old target/profile output and withholding decisions before restoring or retiring them; their hidden setting IDs alone do not establish universal lost functionality. Preserve science retirement, accepting-lab checks, early/late stages, native owners, cap-zero semantics, nondefault costs, icons, locales and the full authored README.

Retain useful physical outcomes for productivity, machine/module effects, efficiency/speed/quality, recycling, pipeline extent and receiver limits. Check repair, agriculture and spoilage at their actual global/force scope, useful rate, external-writer boundary and remove/readd/clone/destroy/load/client lifecycle. Preserve earned-above-cap and native gun/Tesla/module/cannon/mining/inserter and other admitted continuation obligations. Do not make a negative or upstream-withheld feature appear supported to meet a count.

**Exit:** every existing request/continuity obligation has a current implementation/verification mapping or its preserved explicit accepted/deferred/rejected/upstream/unavailable disposition. Delivered applicable behavior cannot be deferred merely to ease stable. Unadopted weapon-range/health/stack/fuel/queue ideas, required feature-pack splits and default permanent downsides are not silently promoted into stable promises.

### WP-09: Research Library ownership and interaction

**Priority:** existing correctness/interaction before stable; structural extraction as needed. **Depends on:** relevant native readers in WP-02/06. **Contracts:** `RUN-04/05`, `CONT-10`, #1768.

Preserve the accepted stable window, split browse/detail view and narrow fallback, continuous lists, search/dropdowns, localized discovery, availability reasons, effective settings/provenance, personal state, exports and native research handoff. Complete exact-current input, translation, selection/scroll/focus, reconnect and host-restart applicability. Separate per-player state, view projection, translation lifetime, rendering and event orchestration when an actual change/safety boundary warrants it. Any chosen directory move is a separate semantic-neutral operation with import/package checks; no six-file scaffold is required to qualify the existing UI.

**Exit:** two real clients with independent views/languages retain the specified behavior across open/filter/export/close/rejoin/restart. Failed observations display unavailable rather than a convincing zero; recovered observations restore counts and repeated positions. Closed/cleaned views schedule no ongoing Library work; settled views do not repaint merely because they exist. Coalescing refreshes or caching immutable text has explicit invalidation and preserves input responsiveness. Performance conclusions belong to WP-10.

### WP-10: Performance and bounded resource evidence

**Priority:** existing stable gates; optimize only demonstrated cost. **Contracts:** `PERF-01..06`, `VER-05/06`, `CONT-09/10/13`.

Credit already accepted exact startup, Foundation III update/load/soak and API observations without relabelling them current. Bind final applicability by consumed inputs. Repair Library A/A repeatability and restart/save/client attribution before scoring candidate memory or latency; unexplained baseline drift establishes neither a leak nor a pass. Preserve the responsive-menu objective of at least 50% less MIR-added time where the denominator is meaningful, with separately reported total seconds and unchanged product scope.

Measure matched startup, load, update, first/warm Library open, search/translation bursts, post-close retained memory and necessary scripted work. Vary active definitions, unrelated recipes, forces/players and scheduled entities separately. Keep fixed-seed work counts separate from native timing; no hardware clock controls gameplay. Record host preparation, historical fetch, control runtime and native orchestration time separately to target developer-loop cost. The existing runner/governor owns execution and restoration; use one heavy native workload per admitted machine and do not duplicate an active assignment.

**Exit:** predeclared valid controls/tolerances and independent results for the claimed exact candidate; known unexplained variance remains unscored. Reuse unaffected observations under their original identity. No minification, reduced feature set, weakened queue/history checks, unsupported progress bar, or extra permanent polling to make numbers look better. Official lifecycle documentation supplies no general mod-owned loading-bar percentage callback; use bounded phase logs and measured work instead.

### WP-11: Useful public MIR API and SDK

**Priority:** preserve current API for stable; implement the broader additive extension programme through compatible 5.x. **Depends on:** WP-05/07 contracts and relevant WP-02/06 operations. **Contracts:** `API-01..07`, `VER-05/06`, `CONT-14`.

Start with a real independently named companion mod that adds an ordinary infinite productivity family using documented public/native interfaces only. Define the smallest capability needed for native formulas/levels, effect targets, icon/localization, native settings-stage definitions, effective tuning, cap/Library participation and dependency/load-order behavior. API version/capability changes must advertise what is actually implemented. Existing finite API 1.0 inputs/results and absence guards stay compatible. Data calls retain their documented immediate-stage operation rather than queuing work for a MIR finalizer that may already have run.

Extend the proof to genuinely different consumers: an ordinary native bonus, finite-to-infinite continuation and an explicitly admitted provider/earned-work transition where required. External data never grants ownership of another mod's saved state. Use the same supported internal constructors/operations, not a second external implementation or unlimited prototype pass-through.

**Exit per capability:** complete public contract, executable example/types and independently authored conformance for defaults, nondefault cost/cap, disabled settings, meaningful ordinary output, supported stage ordering, MIR absent, old consumer, conflicting/invalid input, upgrade/save/cold-load and actual two-client boundaries where affected. Native formulas remain native. Specify removal/deprecation behavior before claiming it. Unknown legacy consumers remain unknown; an unconsumed preview does not become a second platform. First working example is the initial vertical slice, not proof of every future effect or migration.

### WP-12: Portable tooling with one owner per task

**Priority:** bounded independent improvements throughout; no wholesale language rewrite before preservation. **Contracts:** `REPO-02/03`, `VER-01/06`, `CONT-17`.

Inventory real entry points/callers. Consolidate portable packaging, changelog/release utilities, plan selection, result analysis and reusable process mechanics under Python where replacement reduces duplication. Retain narrowly justified Windows input/process and player-report adapters; do not make players install Python solely to report a bug. Current PowerShell entry points continue until a reviewed replacement exists. Temporary wrappers delegate and own no second plan or policy.

Migrate the host-plan owner only with exact ordered selection, isolated subprocesses, explicit runtime requirements, exit/failure behavior and bounded per-control timeout/cancellation preserved. A non-Lua selection should require only its actual dependencies. CI must install the interpreter before invoking it and bind the implementation/plan, not merely the wrapper hash. Consolidate duplicated historical-fetch declarations while retaining exact commits and each job's isolated checkout. Use the existing dispatcher; do not add a scheduler or giant command framework.

**Exit per seam:** actual Windows/Linux invocations demonstrate equivalent preparation, child identity, timeout/output bounds, cancellation, terminal status, restoration and custody as applicable; old active duplication is removed. Timeout/unavailable/pass/fail remain different. Documentation uses only implemented commands. Preserve unique receipts and protected originals; platform helper replacement does not alter acceptance semantics.

### WP-13: Independent, smaller test support

**Priority:** affected regressions mandatory; support cleanup in bounded slices. **Depends on:** named invariant/consumer. **Contracts:** `VER-01..03/05..08`, `ARCH-12`.

Move reusable construction out of executable sibling test modules and mutable global injection into explicit builders with runtime/source inputs. Reuse existing conversion helpers after comparing sparse arrays, cycles, boolean/numeric keys and failure semantics. Expected science/cost/effect/ownership results stay independently specified or frozen from authenticated historical evidence; never generate the oracle from candidate declarations. Reconcile the retired gear-slice runner's assertions with surviving fixtures or a reasoned historical disposition.

Choose behavior equivalence classes and targeted event sequences rather than all mod combinations. Include relevant fresh/earned/current/parked/queued states, add/remove/readd/replacement, changed price/settings, force lifecycle and cold loads. Deliberate bounded mutations must be detected on high-risk changed rules. Run affected controls first through the actual plan; required CI still applies. Do not impose a new permanent all-repo campaign for every formatting edit.

**Exit:** less setup/policy duplication with the same independent obligations and correct failure sensitivity; old broken implementation still fails. Count assertions only as host scope, never as native coverage. When an oracle was wrong, record the independent reason for correcting it and retain the adverse observation.

### WP-14: Documentation and source atlas that stay useful

**Priority:** current entry points in this change; deeper consolidation alongside touched work. **Contracts:** `REPO-01..05`, `CONT-15/16/17`.

Route contributors through a short current task -> owning contract -> owning source -> actual test command. Keep requirements in specs, implementation facts in source, independent expectations in tests, procedures in development, current execution in progress and original decisions in the existing ledgers. Replace stale active summaries with links; preserve dated evidence through exact Git/artifact references. Do not import all 19 supplied files as another active audit estate or append every terminal transcript to current guidance.

Retain the useful source atlas: intuitive tree, size distribution, dependency navigation, desktop/mobile behavior and downloadable source inventory. Refresh snapshots atomically at one exact commit; mixed-revision views are invalid. Identify literal/static analysis limits, current snapshot identity and offline versus live-network refresh separately. Prefer one reproducible developer extraction path, outside player ZIPs; no runtime catalogue dependency.

**Exit:** working entry links and real clone/build/selected-test/API examples; no duplicate writable acceptance authority; source atlas downloads match displayed revision and live refresh is claimed only when observed. A completed audit finding has an owner/task/disposition instead of surviving as a misleading present-tense paragraph. Preserve full README/catalogue/troubleshooting, licenses, locale keys and complete release histories.

### WP-15: Edition qualification and repeatable releases

**Priority:** final stable gate and every subsequent release. **Depends on:** applicable WP-02..14 evidence; optional restructuring is not an extra veto. **Contracts:** `VER-01/03/05..08`, targets/delivery, `CONT-13/16/17`.

Keep nine stable edition subsets (F013-F017, F100, F110, F200, F210) distinct from the 17 distributed archives and best-effort extras. F018 retains its limited experimental scope and declared floor. Confirm actual installed engine/mod hashes, exact minimum Base floor and modern/historical adapter behavior. A 2.1 minimum is not proof of every later patch. Preserve published archive bytes, migration names, tag identities and historic receipts.

Build one coherent candidate and assemble independent verdicts for feature parity, supported-profile usefulness, migration/client safety, performance improvement, non-regression/determinism and package/delivery identity. Record reused evidence with its original identity plus the consumed-input argument; execute changed/uncertain paths. Review release notes and support limits against those verdicts. Continue using the existing package/freeze/release tools, administration and immutability checks, full draft inventory, anonymous hash readback and primary delivery procedure.

**Exit:** the reviewed candidate passes all applicable gates for its declared maturity, and the same verified artifacts are delivered. The next numeric source version is checked against live public objects at freeze; commits/builds consume no version. Keep the existing daily qualified-beta opportunity at 18:00 Australia/Sydney and checked urgent corrections in the development guide. A weekly planning review is optional and does not replace that schedule or require weekly minors. Compatible 5.1 requires WP-05; a public beta cannot silently waive a known required safety defect. Agent-managed publication remains GitHub-only; this planning change publishes no product, changes no release permission and supplies no stable verdict.

### WP-16: Release visibility and growth research

**Priority:** separate non-blocking research; not a product release gate. **Source:** supplied release-cadence analysis.

Preserve the intended question about genuine update timing, visibility and acquisition, while discarding unsupported certainty. Validate Portal counter semantics, edition effects, API/rendered ranking delay and sampling permissions before collecting a bounded timestamped series. The official API describes `downloads_count` as downloads; neither that field nor a screenshot establishes active users, unique new users or causal growth. Preserve release quality, publicity, audience trends, competition and timing selection as confounders.

**Exit of research design:** an explicit metric/data dictionary, rate limits/backoff and retention, reproducible genuine-release observations, preregistered comparison and uncertainty/out-of-sample checks. Earlier screenshot-derived ratios, release markers and decay estimates stay unverified exploratory associations. No meaningless rank-refresh releases, hidden telemetry, automatic scheduled collection or change to safety gates is authorized by this roadmap. Further forecasting/optimization follows only useful evidence.

## Complete continuity routing

This is a routing map, not a claim that the subject is finished. Update existing subject/request evidence when work lands; do not replace their original fields with this summary.

| Existing subject | Work packages |
| --- | --- |
| CONT-01 catalogue/IDs/effects | WP-07, WP-08 |
| CONT-02 stages/native owners | WP-02, WP-06, WP-07, WP-08 |
| CONT-03 settings/precedence | WP-07, WP-08, WP-11 |
| CONT-04 product targeting | WP-07, WP-08, WP-10 |
| CONT-05 science/labs | WP-07, WP-08, WP-03 |
| CONT-06 overrides/physical outcomes | WP-08, WP-10 |
| CONT-07 caps/paid work/foreign state | WP-02, WP-03, WP-05, WP-06 |
| CONT-08 global contribution scope | WP-06, WP-08 |
| CONT-09 agriculture/repair lifecycle | WP-08, WP-10 |
| CONT-10 Research Library | WP-09, WP-10 |
| CONT-11 persisted history/migrations | WP-03, WP-05, WP-06 |
| CONT-12 bundled integrations | WP-07, WP-08 |
| CONT-13 engine editions | WP-10, WP-15 |
| CONT-14 API/legacy consumers | WP-05, WP-11 |
| CONT-15 original requests/incidents | WP-01, WP-03, WP-08, WP-14 |
| CONT-16 authored player material | WP-04, WP-08, WP-14, WP-15 |
| CONT-17 evidence/artifact custody | WP-01, WP-12, WP-13, WP-15 |

All 87 request records remain in [their existing ledger](../../spec/programmes/community-requests.json). Route UI-01..04/PLAT-UI-01 to WP-09; PROG-01/PIPE-01/K2-01..07/BA-01..16/ECO-*/OAB-01..06/RIC-01..08/SIF-01 to WP-07/08; FLUID-*/NATIVE-01/REPAIR-02 and the other capability proposals to WP-08 under their existing decision; DEV-01 to WP-12/14; DLC-01 and the four named crash/multiplayer records to WP-03/08/15. RIC-07 remains a feasibility probe. `MODE-01`, `PACK-01`, upstream-limited and deferred requests retain their actual dispositions. A count of 87 records or 17 partial subjects is not a completion percentage.

## Execution contract and stopping conditions

The integration owner selects one bounded outcome with existing requirement/incident IDs, exact inputs, permitted files, independent expected result and cheapest decisive checks. Use root plus at most two explicitly owned workers, with one heavy native assignment per admitted machine. One reviewer checks semantics independently; routine hashing, parsing and polling use ordinary tools. Worker assignments and queued jobs require actual acknowledgement, not an assumption that a comment starts an agent.

For every change record: problem/invariant; present/absent/foreign/invested boundaries; implementation and removed duplication; code/data/import/state/work cost; host result; applicable native/result reuse; independent review; remaining uncertainty; delivery status and next concrete action. Existing PR fields and progress are sufficient. Do not build a new governance platform, demand repeated approvals already covered by standing authorization, or reset another contributor's work to a planning commit.

Stable completion has a finite stopping rule: all existing applicable stable obligations and selected current supported failures have adequate coherent-candidate verdicts; unavailable historical routes have their permitted explicit support disposition; exact artifacts are verified and delivered. Optional decomposition, wider new API capabilities and growth research can continue in 5.x. Conversely, an applicable delivered feature cannot be removed from that gate merely by moving its task to a later milestone.

Four maintenance demonstrations assess whether the design improved: add an ordinary built-in family by declarations; add a provider instance through an existing adapter contract; ship an independent ordinary infinite-family consumer through public capabilities; and advance a compatible source minor without losing saved rights. Measure edit spread and remaining policy duplication. These are development outcomes, not claims that MIR can become permanently finished or maintenance-free.

## Sources and intake custody

The [source inventory](../../spec/inventory/sources.json) retains the names, sizes and SHA-256 identities of all 19 supplied inputs plus their evidence classification and this plan's intake source. The source atlas and 51-row question reconciliation are explanatory projections, not a second feature ledger. Original attachment bytes remain unchanged; they are not imported into player source or made mandatory contributor reading.

Primary project references: [intake source](https://github.com/Julesc013/more-infinite-research/tree/cf9403eccd42192b4049a3ada4634f5aba4b98d0), [published release](https://github.com/Julesc013/more-infinite-research/releases/tag/v5.0.27), [current open work](https://github.com/Julesc013/more-infinite-research/pulls), [Portal observation](https://mods.factorio.com/mod/more-infinite-research). Official engine references inspected on 28 November 2026 served version 2.1.25: [data lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html), [LuaForce queue/force lifecycle](https://lua-api.factorio.com/latest/classes/LuaForce.html#research_queue). These documentation observations do not establish native results or every historical engine's behavior. [Portal API metric documentation](https://wiki.factorio.com/Mod_portal_API#Result_Entry) supports the metric-semantics caution in WP-16.
