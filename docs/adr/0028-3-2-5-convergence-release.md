---
title: "ADR 0028: MIR 3.2.5 convergence release"
status: current
applies_to: "3.2.5, 2.5.5, 3.3, 2.6"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-08-05
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-3.2.5-convergence-decision
  - mir-c31-obligation-cancellation
  - mir-3.2.5-scope-cut-decision
---

# ADR 0028: MIR 3.2.5 convergence release

## Context

MIR C31 froze the unreleased 3.2.4 research-cost package before the planned 3.2.5 compatibility-observability slice. Releasing both packages would require two player upgrades, two qualification closures, and two publication campaigns while separating features that share settings, ownership, upgrade, diagnostics, and target-projection contracts.

The release state machine is monotonic and has no unpublished-supersession state. C31 therefore cannot be renamed, rewritten, or moved backward through release states.

## Decision

MIR will not publish 3.2.4. C31 remains an immutable, unpublished calibration baseline and is closed by a separate `CandidateClosureRecordV1`. Its product scope is incorporated into the development lineage of one public 3.2.5 convergence release whose public predecessor is 3.2.3. Unperformed C31-specific qualification, sealing, promotion, publication, and public-verification obligations are cancelled; they are not inherited by 3.2.5 under the C31 identity.

The 2026-08-05 maintainer decision narrows 3.2.5 to the product already implemented and extensively development-proven:

- fixed, linear, exponential, and hybrid research costs;
- exact 3.2.3 defaults, direct upgrades, runtime progress preservation, profile migration, coefficient anchoring, and precision compatibility;
- current Base, Space Age, governed ecosystem, and Ice dependency compatibility corrections;
- the admitted bounded `325-B0` research-cost disposition, typed proof assertion, privacy-safe support record, and Factorio 2.0 adapter disposition;
- exact release-specific environment, migration, privacy, localization, performance, manual, protected, seal, publication, and public-byte proof.

Generalized all-stream terminal dispositions, public proof/environment product authorities, universal support-bundle productization, broad remediation catalogs, and a complete all-change Factorio 2.0 projection inventory are deferred explicitly to 3.2.6 or 3.3. Every feature actually shipped in 3.2.5 still requires an exact target disposition. This is an explicit product-scope decision, not permission to omit release proof.

3.2.5 is one release assembled through independent vertical slices. It is not one mega-commit or an unrestricted rewrite. Stable IDs, settings, defaults, and public contracts remain compatible with 3.2.3. Breaking compiler, lifecycle, extension, and process-safety platform work remains in 3.3.

Factorio 2.0 disposition is evaluated for every shipped 3.2.5 feature. No 2.5.5 record, durable branch, candidate, or package authority may be created before public 3.2.5 and a formal feasibility decision.

## Release-value firewall

3.2.5 source freeze is blocked by essential cost semantics and transition proof; exact default, upgrade, configuration-change, save/reload, second-reload, ownership, parser, numeric, and realization parity; release-specific environment locks; privacy, localization, and bounded B0 support proof; package composition and manifest proof; public-contract ABI comparison; explicit Factorio 2.0 dispositions for every shipped feature; a trustworthy release controller; and exact candidate qualification.

3.2.5 source freeze is not blocked by the deferred generalized B2/B3/B4 product surfaces, the broad C1 projection inventory, optional B5 consolidation, the entire script-to-command migration, removal of all checked-in target-line mirrors, every museum installation source lock, MEP-1, typed `SettingSpec`, a runtime service registry, `ProcessIR`, generalized trusted external adapters, or broad generated target projections. Those remain separately governed 3.2.6, 3.3, 2.6, or maintenance work unless a demonstrated defect in the narrowed shipped product earns a bounded correction.

## Consequences

- Players receive one modern upgrade and one combined explanation of the product changes.
- C31 evidence may be used only diagnostically or for an exact unchanged proposition; it cannot qualify 3.2.5 bytes, and proposition reuse does not revive cancelled C31 candidate obligations.
- The primary modern upgrade is 3.2.3 to 3.2.5.
- The final approved delta compares public 3.2.3 with 3.2.5.
- A confirmed P11 defect may still create a minimal 2.5.1 before 2.5.5.
- Package-visible development occurs only while 3.2.5 is `planned`; C32 is frozen after all package-visible slices are integrated.
- A package-visible defect discovered after candidate assignment consumes a later monotonic candidate; the deadline never weakens a gate or mutates frozen candidate bytes.

## Reversal

Before C32 is sealed, individual slices can be removed through their small commits and shadow gates. C31 remains available as the exact cost-model baseline. After publication, product changes use a new release rather than rewriting 3.2.5 history.
