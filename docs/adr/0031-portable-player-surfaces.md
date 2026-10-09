---
title: "ADR 0031: Portable Player Surfaces and Research Host Ownership"
status: current
applies_to: "4.2.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-09-07
supersedes: []
superseded_by: []
source_of_truth_for:
  - portable-player-surfaces
  - research-surface-host-ownership
---

# ADR 0031: Portable Player Surfaces and Research Host Ownership

## Context

MIR's development research browser already supplies useful per-player filtering, research details, queue requests and MIRSET1 export, but its catalogue extraction, MIR policy projection, GUI construction and host registration are coupled in one runtime module. The maintainer wants filter, sort and personal hide controls inside the in-game research experience, wants new UI/UX work reusable outside MIR, and prefers a small companion for an existing maintained technology UI over a new full tree.

Factorio 2.0.77 and 2.1.17 expose per-player custom GUI roots and `LuaControl.open_technology_gui`, but neither installed `relative_gui_type` enumeration has a technology/research anchor and the runtime API does not expose the vanilla tree widget for node filtering or sorting. `TechnologyPrototype.hidden` is data-stage global state; writable runtime technology availability fields affect force behavior. Neither is a valid implementation of a personal presentation filter.

Ultimate Research Queue 2.x is a current MIT custom research GUI and queue owner on the modern engines. Its inspected 2.1.3 source redirects the vanilla research-open event and exposes a queue-read remote interface, but no documented presentation extension point. Depending on FLib through that project may be appropriate for a companion, but MIR's player package must remain self-contained.

## Decision

MIR 4.2 will keep an embedded, native-styled research browser and refactor it into one canonical portable surface composed of a pure copied-data query/explanation core, a Factorio catalogue adapter, an MIR provider adapter, a bounded translation service and one UI host.

Filter, sort and personal hide controls live in the research surface. Personal hide state changes only the player's view. It cannot mutate prototype hidden flags, force technology enablement, prerequisites, research completion or queue state. The surface offers a native deep link for the selected technology where the exact target supports it.

The query contract is capability-negotiated, versioned, deterministic and bounded. It exposes deep-copied plain DTOs for technology keys, facets, pages, detail and explanations. It does not expose compiler objects, Lua callbacks, GUI references, prototypes, executors or mutation authority. Navigation and enqueue are distinct permission-checked actions and do not grant queue ownership.

The same canonical core is materialized into the MIR package and a package-excluded extraction/conformance fixture. A separately published standalone or companion package is created only after a real consumer, independent packaging demand, stable dependency/version policy and lifecycle proof exist. Stable API/SDK status additionally requires compatibility and deprecation policy; structural extractability alone is not a public support claim.

MIR will evaluate maintained technology UI projects before designing a complete replacement. Integration is admissible only through a documented public upstream hook or equally stable contract. MIR and its companion will not traverse another mod's private GUI tree, read private storage, silently fork upstream source or inherit automatic queue semantics without an explicit ownership contract.

If a companion is admitted, its dependencies point toward its host and optionally MIR; MIR does not hard-depend on the companion, its host or FLib. MIR alone owns its embedded entry point. When a compatible companion becomes the presentation owner through a capability handshake, MIR suppresses only the duplicate host and remains a provider. Removal, disablement or version mismatch restores the embedded host without altering research or queue state.

A complete OEM+ technology tree, ultimate queue and research-screen overhaul is a 4.5 candidate only if evidence shows that the embedded 4.2 surface plus a maintained-host integration cannot satisfy the player contract. It is not a concealed 4.2 dependency.

## Consequences

- MIR 4.2 can deliver useful in-game filtering, sorting, personal hiding, localization, explanations and profiles without claiming unsupported vanilla-widget injection.
- Other mods can eventually consume the core or provider contract without importing MIR's compiler or giving a second component prototype-mutation authority.
- An upstream contribution may be required before Ultimate Research Queue or another host can display MIR facets and explanations natively.
- MIR remains useful and self-contained when the host, companion or FLib is absent.
- Exactly one visible research-surface host and one queue owner are required in every admitted combination.
- Extraction, multiplayer, add/remove/configuration, translation, bounds, performance and both modern target lines become release evidence obligations.

## Alternatives rejected

### Inject buttons into the vanilla technology tree

Rejected for 4.2 because the installed modern APIs expose no supported relative anchor or tree-element mutation surface. A future engine capability can trigger a new decision.

### Hide technologies through prototype or force mutation

Rejected because it is global or gameplay-affecting rather than a personal view preference and can change prerequisites, availability, saves or other players' experience.

### Manipulate an existing mod's GUI by element name

Rejected because private element trees, storage and event behavior are not stable integration contracts and can produce two competing UI owners.

### Fork an existing research UI into MIR

Rejected because it creates a maintenance fork, couples MIR to queue behavior and undermines independent upstream improvements. An explicit maintained fork would require a later product decision, attribution and its own support surface.

### Make FLib or a companion mandatory for MIR

Rejected because each MIR target player ZIP is self-contained and must continue to operate when optional presentation integrations are absent.

### Build the full replacement in 4.2

Rejected because queue ownership, graph layout, interaction design, accessibility, compatibility, performance, migration and removal proof would displace the core industrial-research outcomes. The evidence-led 4.5 candidate preserves that option.

## Reversal

The embedded host can remain the sole implementation if no maintained project publishes a stable hook. A later Factorio API with a supported technology-GUI anchor or a qualified upstream contract may add another host adapter without changing the core DTO contract. Breaking a graduated public contract requires a new major schema, migration/deprecation policy and consumer proof.

The implementation and release gates are maintained in [MIR 4 Integration and Delivery Plan](../releases/mir4-integration-and-delivery-plan.md).
