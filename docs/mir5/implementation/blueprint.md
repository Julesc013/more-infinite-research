---
title: "High-level implementation pseudocode"
status: draft
applies_to: "MIR replacement development; explanatory pseudocode, not executable product"
audience: developer
doc_type: implementation-draft
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-implementation-draft-blueprint
---

# High-level implementation pseudocode

**Status:** explanatory draft against the supplied specification and API `1.0.0-draft.2`. These procedures are not runnable Lua. Helper names express a responsibility; they are not permission to create one file per procedure or build an operation registry.

Read [the review](review.md) for unresolved decisions and proposals. Read [the opposing tests](opposing_tests.md) before implementing. All actual historical IDs, cost rules, settings precedence, stage placement and migration values must come from recovery, not from this notation.

## 1. The two flows and their boundary

```text
GAME STARTUP
  lightweight native setting declarations
    -> Factorio reads configured values
    -> explicit MIR code in each required data-stage round
         -> resolve relevant settings
         -> select an authored compatibility/continuity branch
         -> bind exact targets or a separately justified collected set
         -> build detached native prototype(s)
         -> preflight that finite family
         -> publish once
       + independent, explicitly ordered native-owner patches and overrides
    -> Factorio completes prototype validation
    -> startup Lua state is discarded

SAVE / GAMEPLAY
  parse control.lua and import needed callback modules
    -> engine initialization / migrations / load / configuration lifecycle
    -> reconstruct only the state and handlers appropriate to that path
    -> native research is handled by Factorio
    -> MIR handles necessary cap/scripted/UI events and bounded queries
```

The Generator never runs during ordinary gameplay. The Library does not import it. A data-stage map does not become runtime storage. The public Data API can invoke the publication boundary later in another mod's own data-stage callback; it does not queue work for MIR.

## 2. Minimal data shapes and ownership

| Value | Shape and ownership | Lifetime |
|---|---|---|
| Identity/settings catalogue | Small authored plain Lua records; IDs, defaults, units, accepted setting semantics | Separately available in the relevant stage; no prototype-world scan |
| Reusable research template | Native-shaped Lua table; borrowed, never mutated | Its data-stage module |
| Resolved values | Small plain record of relevant effective values; actual zeros/false preserved | One family/feature invocation or explicit immutable setting context |
| Native output | Detached technology table, owned by constructor then publication | Becomes engine prototype input |
| Local family index | `technology_name -> array_index` | One family preflight |
| Collection request map | `product_type -> product_name -> interested authored families` | One justified collection point |
| Runtime state | Only owned persistent contributions/cursors/UI state with actual consumers | Save lifetime |
| API query result | Small detached primitive record | One call |

The temporary branch labels below (`create`, `retain_owner`, etc.) are conceptual control flow. They are not serialized commands, a persistent plan, a new public type hierarchy or a compiler IR.

## 3. Settings: definitions are not configured values

**Source basis:** `SET-01` to `SET-04`; `ARCH-05`.

```text
SETTINGS_ENTRYPOINT:
    catalogue = IMPORT_LIGHTWEIGHT_AUTHORED_IDENTITIES_AND_SETTINGS()
    for each setting declaration in authored order:
        if declaration belongs to this supported engine:
            native_setting = CONSTRUCT_OWNED_NATIVE_SETTING(declaration)
            data:extend([native_setting])

    # Do not inspect recipes, load Generator modules or read a future save.
    # Factorio obtains configured values after the settings rounds.
```

```text
READ_EFFECTIVE_VALUES(family, raw_startup_values, imported_profile):
    rules = REQUIRED_RECOVERY(family.setting_precedence_and_sentinels)
    values = empty small record

    for each setting key actually consumed by family:
        value = RESOLVE_BY_RECOVERED_RULE(
            rules[key], declared_default, raw_startup_values[key],
            imported_profile[key], relevant target availability)
        CHECK_CONSUMED_TYPE_RANGE_AND_UNITS(value, rules[key])
        values[key] = value

    return values
```

An import codec decodes bounded data once per stage/context, never executable Lua. Do not infer that a raw value equal to the default means the user did not set it; the input may not expose that distinction. Do not use truthiness as a fallback that loses `false`. Do not conflate absent, inherit, zero and unlimited. The precedence function is deliberately unresolved until the historical behavior is recovered.

## 4. Entrypoints use explicit calls, not a stage planner

**Source basis:** `COMP-02`, `API-02`, `ARCH-06`; refinement P-01.

```text
DATA_ENTRYPOINT:
    values_context = READ_RELEVANT_STARTUP_CONTEXT()
    EMIT_THE_AUTHORED_FAMILIES_ASSIGNED_TO_DATA(values_context)
    # Each assigned family is a direct call or one small authored array loop.

DATA_UPDATES_ENTRYPOINT, only if needed:
    RUN_THE_SPECIFIC_INTEGRATIONS_REQUIRING_THIS_ROUND()

DATA_FINAL_FIXES_ENTRYPOINT:
    RUN_THE_SPECIFIC_LATE_BINDINGS_AND_PATCHES()
    RUN_ENABLED_OVERRIDES_AT_THEIR_DECLARED_RELATIVE_POSITIONS()
```

These labels are a schematic, not an instruction to put every integration before every override. Exact calls and ordering must be selected per recovered family. No universal late finalizer is assumed. If a known collector consumes post-override fields, its call is after that override. If another mod needs an MIR technology in `data-updates`, it cannot be first introduced after that consumer. Tests cover the declared dependency order.

Before importing an optional integration's body, check its relevant mod/setting/capability condition. A previously applied runtime effect can need cleanup even when its new setting is off; that is a separate runtime concern.

## 5. One authored research family, end to end

**Source basis:** `GEN-01`, `GEN-07`, `COMP-01`, `MIG-01`.

```text
INSTALL_RECOVERED_GEAR_RESEARCH(raw_context):
    contract = AUTHORED_RECOVERED_GEAR_CONTRACT
    values = READ_EFFECTIVE_VALUES(contract, raw_context.settings,
                                   raw_context.profile)

    variant = SELECT_EXPLICIT_GEAR_VARIANT(
        relevant active mods, current named prototype fields, target)

    # This branch includes historical identity obligations BEFORE omission.
    disposition = RESOLVE_AUTHORED_GEAR_AVAILABILITY(variant, values)

    if disposition is "not_applicable":
        # Legal only under a recovered rule that creates no violated
        # historical continuity obligation in this supported configuration.
        return ordinary non-applicability

    if disposition is "unsupported":
        REPORT_UNSUPPORTED_REQUIRED_CONTRACT_WITH_EXACT_REASON()
        # Do not relabel this as a successful optional omission.
        # If this violates a required published identity, release is blocked.
        # Never continue after partial mutation pretending success.
        return/raise according to the explicitly approved product policy

    if disposition is "retain_native_owner":
        CHECK_THE_NAMED_OWNER_AND_REQUIRED_CONSUMED_FIELDS()
        return owner retained without duplicate bonus

    if disposition is "patch_native_owner":
        APPLY_THE_SPECIFIC_APPROVED_GEAR_OWNER_PATCH(values)
        return owner patch completed

    if disposition is "preserve_historical_identity":
        output = BUILD_THE_QUALIFIED_PRESERVATION_VARIANT(values)
        INSTALL_OWNED_FAMILY(output)
        return historical identity preserved under its exact contract

    exact_targets = RESOLVE_APPROVED_TARGETS_FOR_VARIANT(variant)
    output = BUILD_RECOVERED_GEAR_NATIVE_PROTOTYPES(
        contract, variant, exact_targets, values)
    INSTALL_OWNED_FAMILY(output)
```

There is no default `preserve_historical_identity` implementation. An empty hidden prototype is not automatically equivalent to the researched technology. No current-save lookup is available here. If the necessary preservation semantics are not recovered, this family is not ready for a compatible release.

The variant selector uses exact binding, explicit combined rules, or a finite reviewed alternative list. Overlapping matches require a documented precedence/combined rule or an error; never accidental first-match ownership. It does not derive science or progression from arbitrary recipe reachability.

## 6. Construction: native output, no aliases into the template

**Source basis:** `GEN-02`, `GEN-03`, `GEN-07`, `SET-02`.

```text
BUILD_RECOVERED_GEAR_NATIVE_PROTOTYPES(contract, variant, targets, values):
    CHECK_REQUIRED_RECOVERED_CONSTANTS_ARE_COMPLETE()

    # Pick the actual native representation, not a generic formula model.
    unit = BUILD_OWNED_NATIVE_UNIT_FOR_THIS_RECOVERED_COST_RULE(values)
    effects = BUILD_OWNED_EFFECTS_FOR_THIS_RECOVERED_RULE(targets, values)

    p = fresh native table:
        type             = "technology"
        name             = contract.actual_released_prototype_id
        effects          = effects
        prerequisites    = fresh array of variant.exact_prerequisites
        unit             = unit
        max_level        = recovered native maximum representation
        icon/icons       = owned applicable presentation fields
        localised_name   = owned applicable localisation expression
        localised_description = owned applicable localisation expression
        other native fields = only the actual inherited/approved fields

    return [p]  # or the actual recovered finite family/continuation
```

A shared `build(template, values)` is useful only where real families share the same transformation. It must receive all transformation inputs explicitly, produce detached output and avoid `data.raw`, `mods`, settings reads, storage, logging and emission. Direct family construction is acceptable and can avoid copying an already complete tree merely to modify several fields.

```text
FORMAT_RECOVERED_COST(values, recovered_rule):
    CHECK_FINITE_CONSUMED_VALUES_AND_EXACT_SENTINEL_MEANINGS()
    if recovered_rule uses native numeric count:
        return that count after its exact approved calculation/rounding
    else:
        return the known native formula with deterministic numeric literals

    # Never enumerate all future infinite levels.
    # Never use load/eval to interpret a player-supplied expression.
    # Never replace all existing families with B * G^(L-L0) + D*(L-L0).
```

For unit-based research, exactly one of `unit.count` or `unit.count_formula` is present. Trigger-based native technologies have a different target-defined contract; the public native-prototype helper must not reject every technology lacking `unit`. Unknown native schema details are validated by the target engine rather than an invented universal validator. Starting levels come from the native identity semantics, not an invented `level` field.

## 7. Private finite-family preflight and publication

**Source basis:** `GEN-04` to `GEN-07`; `API-05`; refinements P-02 to P-04.

```text
INSTALL_OWNED_FAMILY(prototypes):
    n = CHECK_DENSE_POSITIONAL_ARRAY(prototypes)
    APPLY_APPROVED_EMPTY_BATCH_POLICY(n)              # P-02, proposed reject
    local_index = empty name-to-index map
    names = fresh array

    for i from 1 to n:
        p = prototypes[i]
        CHECK_RELEVANT_NATIVE_HEADER_AND_CONSUMED_FIELDS(p, target)
        if local_index contains p.name:
            ERROR_DUPLICATE_ID_BEFORE_WRITES(p.name)
        if data.raw.technology contains p.name:
            ERROR_DUPLICATE_ID_BEFORE_WRITES(p.name)
        local_index[p.name] = i
        names[i] = p.name

    for each p in submitted order:
        CHECK_PREREQUISITES_EXIST_IN_LOCAL_FAMILY_OR_VISIBLE_NATIVE_SET(p)
        CHECK_CONSUMED_SCIENCE_AND_EFFECT_REFERENCES_BY_TARGET_RULE(p)
        CHECK_DECLARED_NUMERIC_AND_COST_SHAPES(p)
        # No inference that mere existence proves researchability/economics.

    CHECK_LOCAL_FAMILY_ACYCLIC(prototypes, local_index)

    # First deliberate prototype write in this creation operation.
    data:extend(prototypes)
    # No try/catch-and-resume around native publication failure.
    # Caller relinquishes ownership; do not retain a second output catalogue.
    return names
```

This preflight does not enumerate unrelated technologies. It accepts internal forward references. It checks each consumed field once where practical, and does not scan a second global representation. It does not claim that arbitrary native errors are rolled back or that later mods cannot edit the result.

### A concrete local-cycle algorithm

```text
CHECK_LOCAL_FAMILY_ACYCLIC(prototypes, local_index):
    indegree[1..n] = 0
    children[1..n] = empty arrays

    for dependent_index from 1 to n:
        for prerequisite_name in prototypes[dependent_index].prerequisites:
            parent_index = local_index[prerequisite_name]
            if parent_index exists:
                if parent_index == dependent_index:
                    ERROR_SELF_PREREQUISITE()
                append dependent_index to children[parent_index]
                indegree[dependent_index] += 1
            # External edges were checked for existence separately.

    queue = empty dense array
    for i from 1 to n:
        if indegree[i] == 0: append i to queue

    head = 1
    visited = 0
    while head <= queue.length:
        i = queue[head]
        head += 1
        visited += 1
        for child_index in children[i]:
            indegree[child_index] -= 1
            if indegree[child_index] == 0:
                append child_index to queue

    if visited != n:
        ERROR_LOCAL_CYCLE_WITH_BOUNDED_CONTEXT()

    # Do not reorder the submitted publication array as a side effect.
```

Time/space are O(local nodes + local prerequisite edges), with expected constant-time name lookup. The queue uses a head index, not repeated removal of its first element. The remaining nodes on failure are blocked nodes, not necessarily all cycle members. There is no whole-game graph traversal. Foreign paths back into newly added nodes require explicit integration qualification/native final validation.

## 8. Public Data API: copy once, use the same private boundary

**Source basis:** API `1.0.0-draft.2`, `API-02`, `API-05`, `API-06`.

```text
DATA_API.add_technologies(caller_prototypes):
    OWNED = COPY_PLAIN_NATIVE_INPUT_WITH_LIMITS(caller_prototypes)
    return INSTALL_OWNED_FAMILY(OWNED)

DATA_API.add_technology(caller_prototype):
    names = DATA_API.add_technologies([caller_prototype])
    return names[1]

DATA_API.add_productivity(caller_prototype, recipe_names, change):
    REQUIRE_ACTUAL_TARGET_CAPABILITY("native recipe productivity")
    CHECK_DENSE_DISTINCT_RECIPE_NAMES_WITH_SUBMITTED_INPUT_LIMITS(recipe_names)
    APPLY_APPROVED_EMPTY_RECIPE_LIST_POLICY()         # P-02, proposed reject
    CHECK_FINITE_SUPPORTED_NATIVE_CHANGE(change)

    p = COPY_PLAIN_NATIVE_INPUT_WITH_LIMITS(caller_prototype)
    effects = p.effects or new empty array
    seen = map of matching productivity recipe identities already in effects

    for recipe_name in recipe_names in caller order:
        if seen contains recipe_name:
            ERROR_DUPLICATE_MATCHING_EFFECT_BEFORE_WRITES()
        seen[recipe_name] = true
        CHARGE_ONE_OUTPUT_EFFECT_AND_RECIPE_BYTES_TO_PUBLIC_INPUT_BUDGET()
        append fresh native record to effects:
            type = "change-recipe-productivity"
            recipe = recipe_name
            change = change

    p.effects = effects
    names = INSTALL_OWNED_FAMILY([p])
    return names[1]
```

The productivity helper copies the supplied prototype only once and preserves intended pre-existing effects. It neither discovers recipes nor guesses research costs/settings. Distinct API calls with the same name are duplicate errors, not automatic merging. No public `trusted=true` or arbitrary-patch operation is introduced. All calls happen immediately in the caller's data-stage round.

### Bounded input copying

```text
COPY_PLAIN(value, active_path, budget, depth):
    CHARGE_VISIT_AND_CHECK_DEPTH(budget, depth)

    if value is accepted immutable primitive:
        CHECK_FINITE_NUMBER_IF_NUMERIC(value)
        CHARGE_STRING_BYTES_IF_STRING(value)
        return value

    require ordinary table, with no metatable
    require value not in active_path
    active_path.add(value)
    result = fresh table

    for each raw key/value entry in the input table:
        require key has an accepted native-plain key shape
        CHARGE_MATERIALIZED_ENTRY_AND_KEY_BYTES(budget, key)
        result[key] = COPY_PLAIN(child, active_path, budget, depth + 1)

    active_path.remove(value)
    return result
```

This is a candidate copy policy: repeated acyclic children are copied at their occurrences, producing independent output children; every expansion charges the materialization budget. The active-path set rejects cycles without rejecting legitimate repeated values. Depth/entry/string-byte limits remain to be measured and specified before API stability. No hard number is invented here. Different sharing policies can be considered only with explicit ownership and work-bound tests.

The bounds constrain submitted records, not the entire game. Stable semantic/error expectations must not depend on random hash traversal. Ordered arrays use their actual positional order; named fields are checked in a declared validation order where error precedence matters.

## 9. Existing owners: an explicit patch is not creation

**Source basis:** `GEN-04`, `GEN-06`, `COMP-01`; refinement P-01.

```text
APPLY_ONE_KNOWN_NATIVE_OWNER_PATCH(values):
    owner = LOOK_UP_EXACT_CURRENT_TECHNOLOGY_NAME()
    CHECK_THIS_OWNER_AND_ONLY_THE_REQUIRED_EXPECTED_FIELDS(owner)

    # All calculations use the current relevant fields at this call.
    replacement_effects = BUILD_OWNED_ACCEPTED_EFFECT_ARRAY(owner, values)
    CHECK_NO_UNAUTHORIZED_DUPLICATE_BONUS(replacement_effects)
    replacement_cost = CALCULATE_ONLY_THE_APPROVED_COST_CHANGE_IF_ANY()

    CHECK_ALL_PATCH_PRECONDITIONS_BEFORE_ASSIGNMENTS()
    owner.effects = replacement_effects
    if this specific patch owns a cost change:
        ASSIGN_ONLY_THE_EXACT_DECLARED_UNIT_FIELDS()

    # Do not replace the entire foreign prototype with a cloned old snapshot.
    # Do not change prerequisites, presentation or other fields incidentally.
```

A real patch may own only one scalar and need no effect-array copy. A native-owner case that also creates a continuation must preflight both its additions and patch conditions before intentional writes, then use one explicitly reviewed write order. That specific sequence is not a generic transaction or an invitation to introduce a mutation journal.

No unknown conflict is settled by mod loading order, `owner_mod` text, or unconditional overwrite.

## 10. Broad target collection, only when the retained contract requires it

**Source basis:** `COMP-01`, `COMP-02`, `ARCH-09`; refinement P-07.

```text
COLLECT_APPROVED_TARGETS(active_requests, current_recipe_view):
    interested = typed product-name lookup built from active_requests
    results = one initially empty array per active request
    seen = one initially empty recipe-name set per active request

    for recipe in one relevant current-recipe pass:
        for product in native product entries of recipe:
            consumers = interested[product.type][product.name]
            for each authored consumer in consumers, if any:
                CHARGE_ONE_CANDIDATE_ASSOCIATION_IN_DIAGNOSTIC_TESTS()
                if consumer's finite declared conditions accept(recipe, product):
                    if recipe.name not in seen[consumer]:
                        seen[consumer].add(recipe.name)
                        results[consumer].append(recipe.name)

    for result whose accepted contract requires canonical set ordering:
        sort only that result once by a stable total key
    return results
```

This procedure does not invent research identities or progression. Each predicate preserves the required typed outputs, quantities/probabilities, ignored-productivity exclusions, recycler/catalyst restrictions and appropriate science/progression facts. Matching the product name alone is insufficient.

Use only at the authored round where these facts are valid. Do not keep an unvalidated snapshot across foreign edits or trigger this whole pass from each public API call.

Let P be recipe/product entries visited, C candidate family associations examined, Q any additional field work performed by their predicates, and M emitted matches. The collector is O(P + C + Q + M), plus declared result sorting. C is not necessarily M: predicates may reject many candidates. A predicate that rescans a recipe is not a free constant-time operation; either prepare its genuinely shared per-recipe facts once, or expose and reduce that extra work. Do not retain a world-wide fact snapshot. These distinctions prevent a false output-linear claim.

## 11. Independent overrides

**Source basis:** `ARCH-02`, `ARCH-06`, `SET-01`, `COMP-02`.

```text
APPLY_PRODUCTIVITY_OVERRIDE(values):
    if recovered setting means "engine unchanged":
        return BEFORE recipe enumeration

    scope = RECOVERED_SUPPORTED_OVERRIDE_SCOPE(values)
    for recipe in exactly that relevant domain:
        READ_ONLY_THE_FIELDS_NEEDED_FOR_THE_ACCEPTED_SAFETY_RULE()
        if recipe qualifies under that rule:
            desired_cap = CALCULATE_RECOVERED_CAP(values, relevant fields)
            CHECK_NATIVE_RANGE_AND_SAFE_SUPPORTED_CASE()
            assign only recipe.maximum_productivity
```

The real self-recycling safeguard may require a separate bounded preparation step; it cannot be replaced with a name check or removed. Global module/efficiency/speed/recycling operations remain their own explicit passes. Combine passes only when the resulting ordering and semantics are proved equivalent; avoid a large fused function just to reduce loop count.

## 12. Runtime registration and reconciliation

**Source basis:** `RUN-01` through `RUN-05`, `DET-05`, `MIG-02`; refinements P-03, P-06, P-08.

```text
CONTROL_PARSE:
    import target runtime adapter
    import small identity/setting metadata
    import every callback module that may be needed in this session
    # Conditional import is valid only when that module cannot later become
    # necessary without a new parse. Runtime-toggleable modules need loading.

    register MIR's static API function table
    register explicit init/load/configuration handlers
    register supported unconditional handlers in a fixed order

ON_INIT:
    initialize only genuinely new MIR-owned state
    # Adding MIR to an existing game is not the same as an empty new world.
    derive eligible baseline observations from actual current native state
    reconcile the enabled feature-specific contributions
    establish conditional subscriptions from accepted MIR state

ON_LOAD:
    attach local references to already-restored state, read-only
    reconstruct permitted conditional subscriptions
    # No game access, storage writes, migration, bonus application or require.

ON_CONFIGURATION_CHANGED:
    verify required state migrations/initialization have completed
    resolve current effective configuration
    perform required one-time cleanup of disabled owned features
    reconcile affected caps/contributions using actual native state
    invalidate only affected reconstructible views/caches
    establish the same conditional subscriptions expected on joining clients
```

Do not assume every save path executes every handler. The engine chooses the lifecycle path. Subscribe shared events through one small explicit owner only when necessary to prevent handler replacement; do not create a general event bus.

### Idempotent reconciliation is not native-bonus maintenance

```text
ON_RELEVANT_RESEARCH_OR_FORCE_EVENT(event):
    family = exact affected-family lookup(event)
    if event affects no MIR scripted/cap behavior:
        return
    if effect is already native:
        do not apply a duplicate Lua bonus
    RECONCILE_THE_SPECIFIC_SCRIPTED_OR_CAP_RULE(family, event.force)
```

```text
RECONCILE_SPECIFIC_SCRIPTED_RULE(force):
    actual = READ_REQUIRED_NATIVE_RESEARCH_AND_TARGET_STATE(force)
    prior = READ_THIS_FEATURE'S_OWN_PERSISTENT_BASELINE()
    desired = COMPUTE_ITS_EXACT_RECOVERED_CONTRIBUTION(actual, settings)

    if ownership/reset preconditions do not establish a safe operation:
        FOLLOW_THE_QUALIFIED_SHARED_WRITER_POLICY_OR_REPORT_CONFLICT()
        return

    if actual owned contribution already satisfies desired:
        return without adding the benefit again

    APPLY_ONLY_THIS_FEATURE'S_KNOWN_TRANSITION(prior, desired, actual)
    record only the durable fields needed to interpret the next transition
```

There is deliberately no universal `current - old_MIR + new_MIR` rule: arbitrary foreign writes, resets and multiplicative effects invalidate it. A last-applied value is not ownership proof. For cap reconciliation, preserve earned investment and foreign disablement; do not blindly set `enabled=true` when a cap is raised. Exact conflict behavior remains to be recovered from each accepted feature contract.

Periodic effects use game ticks and an explicit work count/cursor where needed. Queue fairness, maximum revisit delay and effects under backlog are semantics to preserve/test, not unreported consequences of a CPU budget.

### Research Library

```text
ON_LIBRARY_OPEN(player):
    observe that player's current force, locale, view and actual research state
    build only the requested view using compact metadata and native state
    attach a fresh view-generation token to outstanding translations

ON_TRANSLATION_REPLY(reply):
    if player/view/locale generation is no longer current:
        discard stale reply
    else:
        update that player's current presentation cache/view only

ON_RELEVANT_RESEARCH_OR_CONFIGURATION_CHANGE:
    invalidate only the affected cache/view
    refresh currently open affected views when required
    # Do not rebuild closed windows on every tick.
```

Search can scan the needed catalogue; it is not required to be constant-time. Locale-dependent presentation must not decide game-affecting research identity, order or availability. Native research/queues remain authoritative.

## 13. Runtime API: observation only

**Source basis:** `API-06`, `RUN-01`; current signature preserved.

```text
RUNTIME_API.get_research(force_index, technology_name):
    CHECK_ARGUMENT_SHAPES_WITHOUT_GAME_MUTATION()
    if required game context is unavailable:
        return nil, documented unavailable-context code
    force = LOOK_UP_FORCE(force_index)
    if force does not exist:
        return nil, documented missing-force code
    technology = force.technologies[technology_name]
    if technology does not exist:
        return nil, documented missing-technology code

    result = fresh plain record:
        name = technology.name
        force_index = force.index
        researched = technology.researched
        level = technology.level
        enabled = technology.enabled
        max_level = TARGET_ADAPTER_NORMALIZES_OBSERVED_MAXIMUM()

    if target supports saved_progress observation:
        result.saved_progress = technology.saved_progress
    return result
```

Error-code spellings and absent optional field conventions must be finalized in `api.md`; they are not new methods. Do not invent zero for an unsupported observation, initialize storage, migrate missing data, compute all completed levels as `level - 1`, or expose LuaObjects. `get_version` and `get_capabilities` return small detached actual metadata; they neither certify compatibility nor imply a recurring timer.

## 14. Migration and developer-harness boundary

**Source basis:** `MIG-01` through `MIG-04`, `VER-03`; refinement P-05.

```text
BEFORE_RUNNING_A_FULL_SAVE_UPGRADE_TEST:
    require immutable original fixture and known baseline observations
    require candidate has complete relevant research/settings/state coverage
    if candidate is a partial family experiment:
        refuse full-save test; use a disposable slice fixture instead
    launch only the exact accepted engine/mod/settings/package closure
```

```text
ONE_EXPLICIT_STATE_MIGRATION:
    if this exact state transformation is already complete:
        return
    verify the supported predecessor state shape
    compute the small required owned replacement values
    apply this named transformation only
    record its completion according to the adopted state schema
    # Preserve engine-tracked migration filenames.
    # Do not reset unrelated force research or rewrite all historical state.
```

The engine determines which named migrations run. Ordinary state reconciliation can be idempotent; that does not mean every old migration is executed twice. Avoid calling migration recovery from a query or `on_load`. Native setter side effects must be reflected in the particular migration's tests. Before/after observations include physical/native effects, partial investment, queues, enablement and foreign sentinels—not just equal IDs.

## 15. First implementation, not a whole-product command

Recover and implement the actual gear family in the correct stage, using its actual setting/identity semantics. Add one non-default setting case, one meaningful alias/preflight opponent and a disposable save/reload check. Recover the continuation/cap expectations next; they must be exercised before broad porting.

The next public API proof should cover two independently installed consumers, local forward references, late-stage calls and mutation isolation. No mass feature port, SDK platform, scheduler framework or full migration claim follows from the first working technology.

The authoritative requirements and complete native acceptance remain in the specification. The pseudocode is intentionally explicit about the behaviors still awaiting recovery; implementation must not replace those markers with guesses.
