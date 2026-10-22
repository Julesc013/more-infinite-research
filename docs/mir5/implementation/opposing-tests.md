---
title: "Proposed opposing tests for the implementation draft"
status: draft
applies_to: "MIR replacement development; explanatory pseudocode, not executable product"
audience: developer
doc_type: implementation-draft
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-implementation-draft-opposing-tests
---

# Proposed opposing tests

**All tests below are specifications, not executed product tests.** They refine the existing [verification contract](../../../spec/mir5/verification.md) and do not replace its case catalogue, expected behavior or thresholds.

## 1. Test map

| Draft scenario | Independent expectation | Defect deliberately opposed |
|---|---|---|
| `DRAFT-SET-FALSE` | An actual configured false survives resolution | `value or default` loses false |
| `DRAFT-SET-SENTINEL` | Zero, absent, unlimited and inherit follow recovered meanings | Convenient numeric normalization changes settings semantics |
| `DRAFT-SET-PROFILE` | Raw/profile conflicts and values equal to defaults follow baseline precedence | Guessing whether a user explicitly set a value |
| `DRAFT-BUILD-DETACHED` | Changing input/output nested fields cannot change the other owner | Fresh outer table but aliased nested effects/science/icons |
| `DRAFT-BUILD-PURE` | Construction works with world/settings/storage access forbidden | Hidden reads make `build` depend on ambient state |
| `DRAFT-BUILD-TRIGGER` | A supported valid trigger-based technology is not rejected merely for lacking unit | Universal unit requirement in the API validator |
| `DRAFT-FAMILY-FORWARD` | A requires B, supplied in that order, succeeds with B absent initially | Premature foreign-only prerequisite lookup |
| `DRAFT-FAMILY-CYCLE` | A -> B -> A rejects with zero writes | Native failure after partial publication |
| `DRAFT-FAMILY-BLOCKED` | Error does not label every node downstream of a cycle as a cycle member | Incorrect cycle diagnostic |
| `DRAFT-FAMILY-DUPLICATE` | Duplicate input ID or existing target ID rejects before writes | Silent replacement or accidental idempotence |
| `DRAFT-FAMILY-LAST-INVALID` | Invalid final member prevents every intentional family write | Emit-as-you-go loop |
| `DRAFT-API-COPY-LIMIT` | Cycles/metatables/executable input reject; repeated acyclic children charge expanded work | Recursive blowup or hostile metamethod execution |
| `DRAFT-API-PRODUCTIVITY` | Preserve unrelated input effects; append each distinct named effect once | Duplicate bonuses or replacement of supplied effects |
| `DRAFT-API-LATE` | Extension call after MIR final-fixes publishes immediately | Contribution stranded in a processed registry |
| `DRAFT-API-QUERY` | Missing force/technology is reported without storage mutation | Query acts as lazy migration/init |
| `DRAFT-API-LEVEL` | Returned level is the native field | Universal `level - 1` inference |
| `DRAFT-OWNER-SENTINEL` | Narrow patch preserves unrelated foreign fields | Replacing a foreign prototype from an old snapshot |
| `DRAFT-ORDER-CONSUMED` | Declared override/binding order has the accepted result | Deterministic but semantically wrong execution order |
| `DRAFT-COLLECT-COUNTS` | One domain visit, recorded candidate fan-out, exact authorized targets | Hidden family-by-recipe nested scanning |
| `DRAFT-COLLECT-SAFETY` | Same output name with an unsafe return/catalyst route is not silently admitted | Name matching mistaken for economic safety |
| `DRAFT-CONTINUITY-DISABLE` | Existing identity follows approved preservation rule | `enabled=false` means omit every time |
| `DRAFT-RUNTIME-REPEAT` | Same unchanged state reconciled twice has no second bonus | Repeated on-load/configuration accumulation |
| `DRAFT-RUNTIME-RESET` | Explicit native/foreign resets follow recovered baseline rules | Old cached applied value treated as current truth |
| `DRAFT-RUNTIME-JOIN` | Real joining client reconstructs handlers without mutations during on_load | A single-process multi-force test mistaken for multiplayer |
| `DRAFT-RUNTIME-BACKLOG` | Accepted effects/rates/fairness survive increasing relevant population | CPU cap silently reduces effects |
| `DRAFT-LIBRARY-STALE` | Stale reply from old player/force/locale/view cannot alter current view | Asynchronous reply corrupts current UI |
| `DRAFT-LIBRARY-CLOSED` | Closed UI has no unnecessary rebuilding work | Hidden refresh loop |
| `DRAFT-MIGRATION-SETTERS` | Benefits/enablement/progress remain correct after native setters | Checking only a restored level number |
| `DRAFT-PARTIAL-SAVE` | Harness refuses a full-world upgrade using an incomplete catalogue | Destructive save experiment mislabeled as a slice |
| `DRAFT-CUTOVER-MEMBERS` | Exact player member names/bytes survive layout relocation | Staging path leaks into imports/assets/packages |

Do not count these as thirty passing tests or silently add them to the baseline's executed test totals. Merge useful cases into the existing test catalogue under its original requirement IDs when implementing, avoiding duplicate scenarios/launches.

## 2. Creation preflight test pseudocode

```text
TEST_INVALID_FINAL_MEMBER_HAS_NO_WRITES:
    world = minimal independently authored visible prototype fixture
    submitted = [valid_A, valid_B, invalid_C_with_missing_required_recipe]
    observer = fresh write-observing host adapter

    call candidate installation
    assert documented error class
    assert observer.write_count == 0
    assert world equals original world
```

A host fixture can prove MIR's preflight path. It cannot prove that Factorio's native schema accepts the positive path. That is a separate native test. No broad engine API abstraction is required in product code merely because the test observes writes.

```text
TEST_LOCAL_FORWARD_REFERENCE:
    world contains external prerequisite P, but not A or B
    submitted = [A requires B, B requires P]
    result = install(submitted)
    assert returned names == [A, B]
    assert published prototypes retain submitted order/content
```

```text
TEST_LOCAL_CYCLE:
    submitted = [A requires B, B requires A, C requires B]
    expect invalid-definition/local-cycle result and zero writes
    do not assert that C is itself a cycle member
```

## 3. Alias and boundary-copy tests

```text
TEST_DETACHED_OUTPUT:
    template = independent native-shaped fixture with nested effects,
               ingredients, prerequisites and presentation fields
    output = build(template, explicit_values)
    change output.effects[1].change
    assert template.effects[1].change unchanged
    change template.unit.ingredients[1].amount
    assert output.unit.ingredients[1].amount unchanged
```

Actual Lua fixtures must use the native representation and table indexing, not an invented `.amount` field for every tuple. The pseudocode names the observed quantity; it is not a replacement schema.

```text
TEST_SHARED_ACYCLIC_INPUT_WORK_BOUND:
    construct a small DAG whose child table is referenced repeatedly
    use public copy policy and instrument expanded entries/bytes
    expect either an accepted detached output within limits,
           or the specified limit error BEFORE publication
    never silently truncate or recurse without a work bound
```

## 4. Settings and cost expectations are recovered independently

```text
RECOVER_EXPECTATION_FOR_ONE_FAMILY:
    pin exact released package and intended accepted correction if applicable
    capture actual IDs/defaults/profile rules/prototypes and native observations
    review the resulting compact fixture before candidate implementation

TEST_CANDIDATE:
    default_case = evaluate(candidate, recovered default inputs)
    assert accepted native fields and meanings match independent fixture
    changed_case = evaluate(candidate, one relevant changed setting)
    assert intended changed behavior, not merely setting visibility
```

At native cost boundaries test starting level, finite tail, first continuation, finite cap, earned-above-cap and supported high levels. Preserve grouping/rounding of historical formulas. A host mathematical evaluation is not a native-rounding oracle.

## 5. Metamorphic work tests

```text
TEST_UNRELATED_RECIPE_GROWTH_WITH_EXACT_BINDINGS:
    fix selected definitions, exact references, settings and engine
    run diagnostic candidate against small valid background
    add unrelated recipes without modifying consumed references
    run diagnostic candidate again
    assert equal intended technology output
    assert equal exact-binding lookup/build counts
    # Whole Factorio startup may increase for the added recipes themselves.
```

For broad operations, vary visited recipes, matching product entries, candidate families per product and accepted effects separately. Assert the bound including rejected candidate associations. Measure normal player packages separately from diagnostic builds.

## 6. Continuity and runtime

```text
TEST_RECONCILE_UNCHANGED_STATE_TWICE:
    load independent feature fixture with known native and foreign state
    reconcile once
    observe owned and unrelated fields
    reconcile again without relevant input changes
    assert same feature result and unrelated sentinels
```

Then alter a native/foreign baseline/reset condition and verify its separately specified policy. Idempotence on unchanged state does not prove cooperation with an unknown writer.

```text
TEST_FULL_UPGRADE:
    require candidate's complete relevant catalogue and bridges
    copy immutable original fixture; never overwrite original
    observe original baseline in its original environment
    load copy with candidate in declared environment
    capture earliest available state and post-migration/configuration state
    verify native effects, hidden carriers, cap ownership, queue and progress
    save candidate copy
    cold reload independently twice and repeat relevant observations
    run genuine client join/rejoin/restart where affected
```

Any lost historical state before an observable callback must be diagnosed against the original baseline. Do not overwrite expected state with the candidate's reduced result.

## 7. Test selection and stopping

A documentation draft runs document/link/membership checks. It does not justify rerunning all native scenarios. A pure Generator change runs relevant host tests and native positive cases; a runtime/migration change adds its affected save/client cases. Shared settings/target changes widen affected coverage.

The first implementation unit ends when its recovered behavior, opposing tests and required native observation are demonstrated or the precise missing engine/fixture is reported. It does not end by expanding the task into a new framework. API stability and full replacement release remain separate later verdicts.
