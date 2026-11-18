---
title: "MIR 5 architecture and regression response"
status: current
applies_to: "MIR 5 next patch and stable qualification"
audience: maintainer
doc_type: report
owner: mir-maintainers
last_reviewed: 2026-11-18
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir5-architecture-regression-response-2026-11-18
---

# Architecture and regression response

The inherited-5.0.11 worker reader does not protect every research system, historical version or mod combination. It proves one historical admission and reuses the existing transfer implementation. The broader defect is inconsistent enforcement of shared obligations: origin versus current version, optional absence versus a failed observation, and retained bookkeeping versus preserved native effects. Those inconsistencies require correction across their real consumers.

Retain MIR 5's authored native construction, canonical source, small Generator and edition packaging. Repair and restructure the migration, lifecycle and test-support boundaries. The available evidence does not justify restarting the whole product. A rewrite would still have to preserve existing identities, paid research, partial work, queues and old ownership; it would introduce another migration boundary without recovering facts already erased from a save.

## Scope and evidence

This response assesses the supplied 18 November architecture audit and accompanying analysis as evidence and proposals. Their recommendations are not additional maintainer instructions. Intake identities are retained in primary `build/qualification/mir5-audit-response-blackglass-20261118-r01/intake-r01.json`: audit SHA256 `CF7E4E0BB2BF3DBFD71B4E7DEC8B9DDE0E5D36F4FFBAEDBDA5835177234FE110`; accompanying text SHA256 `D52FC0F179E3BE019FC2214650CF23A2DA1308A0C851A9602C406D0FFB41B0FA`. Originals remain unchanged.

The supplied audit measures revision `f86b82f13dffb6ee182039dabf515ee5bd762de8`, then accounts for required-interface correction #2095 at `3e1bba5d9ee88bffefa0ce97d7d0930e406a40a9`. This response inspected current modules and fetched development through `6e1ac38cda13977b0c649df6402054080ccf60d4`, including separately integrated cap correction #2100 and worker sequence correction #2102. The broader cap work is pushed separately in #2103 at `db0ab5c3da110469f7aa8b023e863cb3b10c07da`. Open PRs are not integrated results.

Fresh Black Glass host controls reproduce the cap failure and exercise its correction. A separate reviewer executed new worker-sequence old-source failures and exact-head passing controls rather than adopting inaccessible historical logs. Current raw custody is identified below. No new native gameplay, reporter-save reproduction, performance result or stable verdict is claimed by this report.

The applicable authorities remain [architecture](../../spec/architecture.md), [runtime](../../spec/runtime.md), [migrations](../../spec/migrations.md), [verification](../../spec/verification.md), the existing [progress record](../progress.md) and original request/continuity inventories. This report is an assessment and action plan, not a replacement specification or second issue ledger.

## Findings and disposition

| Finding | Assessment at this response | Required outcome |
|---|---|---|
| F01: immutable origin used as immediately previous version | Confirmed false refusal. #2102 corrects the version roles without a new schema. Independent Black Glass execution reproduces twelve old-source failures and passes the three new methods and all 153 worker-history methods. All four exact-head checks passed; development integration and identical worker-source readback are confirmed. Native sequence remains open. | Preserve original producer, validate the actual event and target separately; qualify successive updates plus provider addition, ordinary research, save and two cold processes. |
| F02: failed cap observation treated as absent owner | Confirmed fault-path rights loss. #2100 already repairs the bounded native read/rethrow path. #2103 preserves that commit and extends observation-before-write handling across forces, composition, authored prototype admission, queues, legacy markers and force cleanup. | Preserve cause and rights; no dependent writes before failed admission; later valid restoration works; native continuation and persistence qualify the delivered bytes. |
| F03: worker uncertainty suppresses all cap merge work | Confirmed coupling in bootstrap; resulting native continuation remains unqualified. The source force's cap retirement and unrelated destination caps can be suppressed. | Separate the precise uncertain worker operations from independently safe work, using native before/after merge observations. Do not simply remove the guard. |
| F04: optional-absence policy reused for known credit records | Confirmed inconsistency. Collected families reject invalid observations; other descriptors silently omit them, including where a previous ledger exists. Existing tests prove no additional writes, not retained realized productivity. | Specify optional uninvested absence versus state required for prior rights; compare complete effect outcomes at predecessor, callback entry and post-reconciliation. Preserve full signed vectors. |
| F05: required internal exports treated as optional | #2095's four native-credit exports are integrated and must not be reimplemented. `catalogue.restoration_only` still has an empty-list fallback. #2103 explicitly requires its new cap-preflight export. | Reject missing/noncallable required methods before registration or writes. Preserve real optional modules and valid callable results representing absence. |
| F06: inconsistent diagnostics and recovery advice | Shared configuration-change formatting is already used by worker and finite-speed paths. Other rendering policies and overly broad preparation advice remain. | Stable reason/subject/force/context from already observed facts; domain-selected recovery instructions; preserve unexpected causes. No runtime/UI diagnostic dependency. |
| F07: implicit test-world ownership | Borrowed TestCase setup/world methods and imported runtime globals remain. A deferred bootstrap/paid-family dependency cycle is documented. No general order-dependent failure is established. | Ordinary explicit worker-world and credit-world builders, with runtime, target and exact historical inputs. Keep independent assertions outside builders. |
| F08: tests sometimes prove a weaker property than their name | Static source checks and unchanged ledgers have useful limited scope. They do not establish executed cleanup, effects, gameplay or persistence. Temporal sequence coverage missed F01. | Execute deliberate wrong behaviors and later lifecycle steps; keep static checks for actual identity/import contracts. |
| F09: mixed responsibilities in large runtime modules | Worker origin admission, observation, queue reconstruction, transitions, commands and rendering are coupled. File length is a signal, not the diagnosis. | Extract coherent pure observations/readers after their behavior is captured; retain one transition writer. Land mechanical moves separately from accounting changes. |
| F10: historical and reporter closure incomplete | Existing continuity inventory and request ledger explicitly remain incomplete. The 87 original request entries are not 87 unresolved bugs. | Finish mapping each applicable original obligation to implementation, independent regression, exact native evidence or an explicit unresolved decision in the existing authorities. |

### What the cap correction actually establishes

Against the original production source, two lookup/predicate cases and four late-force cases fail the independently expected behavior. The first corrected draft exposed two unwanted unrelated-worker reads; those adverse logs remain preserved. The narrowed implementation passes the existing bounded-event controls. During fresh upstream reconciliation, #2100's original commit and regression were retained rather than overwritten.

The reconciled source passes lifecycle 41 and bootstrap 41 methods. Adjacent focused controls pass legacy-cap-lifecycle 45, discovery 9, continuation-ownership 20, early-target 1, native-owner-adoption 13 and legacy-cap 15; competing productivity retains its one existing skip. These are host methods, not gameplay scenarios. Raw source copies, old failures, draft failures and passing logs remain in primary `build/qualification/cap-admission-errors-blackglass-r01`.

The correction observes the bounded catalogue before dependent cap, queue, legacy-marker or force-retirement writes. Bootstrap obtains the same facts before other initialization/configuration reconcilers write. Ordinary named research events retain subject/queued-unavailable scope. Genuine missing owners and observed incompatible shapes remain non-admission; unexpected failures retain their cause. A live-force index set avoids treating a native invalid-index exception as a missing force lookup protocol.

This is not an atomic rollback implementation. An engine setter can fail after the first write, and engine loading can already have altered effects before MIR receives a callback. Those boundaries require explicit failure handling and native outcome evidence. #2103 does not infer missing history or repair state already discarded by a prior save.

### Worker evidence custody

The original #2102 description names an implementation commit and raw directory that are not available in this primary checkout. The first independent review therefore refused evidence adoption. The follow-up did not invent or relabel those bodies: it executed the exact proposed test body against old source and the exact reviewed new source in separate clean worktrees, preserving its own failures and passes.

The supplemental review is `build/qualification/worker-provider-sequence-review-blackglass-r01/INDEPENDENT-SUPPLEMENTAL-HOST-REVIEW-r02.json`, SHA256 `27A4C64C49A37FFDDC7EE4C1CC9DD3D1BEF9C24E8E030286151B2282667A0245`. It supports source integration only after exact-head required checks pass. It does not adopt missing historical logs or qualify Factorio cold loads.

## Maintainability, duplication and optimization

The supplied audit reports 153 Lua files, 38,632 physical Lua lines, a 143-line Generator and no multi-module cycles in its 323 literal-import edges at its pinned revision. Its exact-text scan found 22 cross-file clone candidates, mostly adapter boilerplate or authored data. Those are limited static observations, not defect counts or a fresh census of later development. No evidence establishes that the general MIR4 compiler has returned.

MIR4 itself already used shared source bindings; describing it as wholly separate copied editions would be inaccurate. Its older planner/compiler representations are materially different from current authored native tables and package-time target adaptation. Retain that simplification. The important present duplication is semantic: equivalent consumers implement absence, provenance or preservation obligations inconsistently, even where their text differs.

Test support is a more evident maintenance problem: the audit identifies 36 test files importing sibling test modules and 30 assigning imported globals. Driver process isolation limits leakage, but does not make those dependencies clear. Extract real builders rather than another configurable fake-engine framework. A helper must not calculate the expected result using the production rule being tested.

No current whole-product performance improvement follows from source length, import counts or host passes. Run the existing matched workload and endpoint in the [performance contract](../../spec/performance.md), including menu/UI behavior and independent scaling axes. Headless Gunmetal functionality cannot establish Windows visual input, cross-host timing or stable performance.

## Community cases and proposed fixes

| Case | Defensible current disposition | Next evidence or repair |
|---|---|---|
| factomacto processing-unit/scrap carrier errors; Ryutavi #1942 | The pasted traces are from older code. Full-vector work and broader family/reference controls exist from 5.0.15. The current original modpack remains unverified; #1942 is open. Attribution to Cerys is the reporter's source analysis, not a newly reproduced result here. | Inspect retained archives/settings and final main/reference/carrier vectors; reproduce the actual selection, then qualify initialization, paid state, ordinary completion and saved successor. |
| Driku 2x price and finite worker9 history | Earlier9 loaded successfully; later old10/11/13/14 traces concern distinct unknown finite ownership. Remove/save/readd demonstrates a changed save loading, not preservation. | Locate retained original save/log/mod custody first. Use the actual old producer and route, preserve 2x paid work and queues, and test the relevant transition. Do not request already held material again. |
| Sage old11 absent route with changed selection | The empty Base-only reader is not a proof for arbitrary prior mod selections. Applicability to Sage remains unverified; no original save is held in the supplied material. | Continue the proved mechanism and opposing cases without claiming Sage closed. Any later exact inputs require their own preserved transition. |
| Kal9001 and DEMEMZEA | Current exact failures and untouched predecessor state remain unverified. Saving without MIR can erase evidence. | Do not classify the original as junk or prescribe resetting it. Distinguish the supported empty inherited route from unknown/paid origins. |
| Gamer433 SE 0.7.57 cargo cap 10 and old-save failure | Cargo capacity and worker speed are separate. The SE speed10 correction does not close the cargo cap or missing-history report. | Verify actual cargo owner, configured cap, native level 10/11 behavior and affected historical save. Preserve earned capacity and partial/queued work. |
| Gamer433 ore extraction #1959 | Still open. Manufacturing drill items does not demonstrate extraction productivity. | Resolve the exact promised research/entity behavior, complete ordinary research and measure ore output under controlled inputs. |
| Advanced K2+SE science #1961 and materials requests | Separate compatibility/coverage obligations. A pack being a research ingredient does not make its recipe productivity-eligible. | Inspect actual recipe/effect permissions; preserve accepted request decisions and measure eligible physical output. Reuse #2099's focused denial evidence within its actual scope. |
| VinHeaven Angel/Bob steel | The supplied successful reporter reply supports that case. | Preserve that confirmation and applicable startup controls; do not generalize it to all Angel/Bob or worker reports. |

Do not implement the pasted suggestions to discard all but the first carrier effect or accept only the descriptor's matching effect. Complete positive and negative vectors can carry real paid entitlements; stripping or ignoring components can make startup succeed while changing research effects. Nor is one load-order dependency a universal defense against later prototype mutation. A named dependency or foreign-mod filter needs a demonstrated compatibility contract, followed by final-vector validation and native preservation evidence.

## Ordered implementation plan

| Order | Concrete work | Completion gate |
|---|---|---|
| 1; underway | Preserve #2102's completed checked integration and reviewed source; review/integrate #2103's additional preflight work against the already merged #2100. | Independent old-red/new-green, opposing cases, preserved commits, all required CI, remote tree readback. Native status stays separate. |
| 2 | Remove the remaining required `restoration_only` fallback and sweep actual required composition consumers. | Missing/false/nonfunction opponents before registration/writes; callable empty/absent results and historical capabilities remain valid. |
| 3 | Qualify the successive-update/provider sequence and cap restoration on exact private next-patch packages. Reuse trusted predecessors. | Protected predecessor, callback-entry observations, ordinary research, effects/queues/partials, successor save and two independent cold processes on affected editions. |
| 4 | Specify and implement force-merge isolation with the smallest necessary pre-merge observations. | Unrelated capped research still works; source metadata retires; worker work on either/both forces is preserved; next completion/configuration and persistence pass. |
| 5 | Resolve known-paid versus optional credit failure disposition. | Complete effect oracle at predecessor/entry/exit; malformed required holders do not silently succeed; legitimate absent uninvested contributions remain optional. No stripping or guessed paid work. |
| 6 | Complete separate old-Base recipe-history work in #2084 and exact carrier-modpack reproduction. | Review exact prior-selection facts, preserve complete vectors, and obtain its missing affected native result. A worker policy is not copied into recipe accounting. |
| 7 | Extract explicit worker/credit world builders, then pure observations and historical readers. | All consumers named; independent assertions unchanged; original published producers retained; mechanical extraction and behavioral changes reviewed separately. |
| 8 | Finish original obligations, GUI/client and measured performance, then qualify final release artifacts. | Existing stable acceptance and publication gates pass; public claims identify exact tested bytes and cases. Beta delivery remains separate. |

For each repair, the existing PR records the violated behavior, other consumers of that obligation, independent expected result, deliberately wrong opponent, first possible write, later lifecycle sequence and exact evidence limits. The review must inspect all those consumers rather than equating a local pass with project-wide prevention. No second global registry or universal migration engine is required.

The first source corrections are already concrete. Merge/credit policy and initial fixture decomposition remain several days of engineering and native validation, subject to the actual merge semantics and retained inputs. There is no evidence-based finish time for every original report or stable acceptance yet. The supplied audit's estimates are planning ranges, not release promises.

## Unattended execution and remaining native work

All 2,346 testmod ZIPs, 39,163,726,197 bytes, are copied and independently hash-verified on Gunmetal under `/home/agents/Projects/Factorio/MIR/testmods/<major.minor>`. FTP's zero-byte write refusal remains preserved; the successful SFTP copy and atomic no-replace publication have separate receipts. The frozen source manifest is `39E629AF9FF4F69EC2C7D57359B7BD1652C3F24B7F511DDB62F31C84723102C6`. Original verifier readback SHA256 is `473C0BBACFB7663CEDB075FF4033C37F07D4C8CFA3EC46083A82826CD0AD8F2F`.

Exact headless 2.0.77 and 2.1.24 binaries and their official expansion data are installed in separate versioned headless directories; their inspected hashes are `C9AC91D318BDBCCE5AFAAC30D48F4B71DC38AF257712A5D4D4C4FEB625737198` and `062277B9D91F5DF9E655A77E6A94EC0208E668ECFC1C4424EE1B12C9AAAB2DCF`. These are different variants from the prior full Linux builds and do not inherit their qualification.

Persistent user services with lingering provide supervision independent of this chat. A second read-only final-tree hash pass independently re-read all 2,346 final archives and passed, with its own terminal receipt. No AI loop is needed to hash, dispatch a frozen finite packet, enforce budgets or collect terminal status. Gameplay dispatch still requires reviewed exact packets, exclusive library/native ownership, unchanged resource reserves, bounded process/time/output budgets, original-input protection and terminal receipts. Scheduling unreviewed or stale campaign commands for days would not create useful qualification.

The two Windows source15 producer attempts are closed zero-PID resource refusals, not successful composition/execution. Preserve their original receipts. The 8 GiB scenario budget and reserves remain unchanged, and no further request to free RAM is warranted. A new Linux packet must use the actual headless binary, verified library, current Linux helper closure and checkout-local same-filesystem temporary root; it must pass zero-native Compose and independent review before conditional Execute. This source15 SE cap producer remains a separate pending native assignment.

At this response, the archive transfer and engine provisioning are complete; a reviewed multi-day gameplay queue is not running. The prepared menu A/A remains noise diagnosis only and is not stable performance evidence. Reuse unchanged completed server exports, agriculture, API, effect and historical results under their original identities; do not pad a queue by rerunning them as new progress.

## Conditions for replacing a component

Replace an individual component if its required state cannot be expressed with unambiguous meanings, mutation cannot have one coherent owner, correct changes repeatedly require unrelated infrastructure edits after a reasonable responsibility split, or measured behavior exposes an inherent algorithmic limitation. Any replacement needs explicit old-save compatibility and independent acceptance before use.

None of those conditions has been established for MIR 5 as a whole. The practical decision is substantial targeted correction and component refactoring, with actual preservation outcomes and lifecycle sequences controlling release claims. No finite test set can guarantee arbitrary future mods never alter prototypes; supported updates should nevertheless preserve progress without player resets, and the demonstrated failure classes should have enforced regression opponents across their real consumers.
