---
title: "ADR 0028: MIR 3.2.5 convergence release"
status: current
applies_to: "3.2.5, 2.5.5, 3.3, 2.6"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-08-04
supersedes: []
superseded_by: []
---

# ADR 0028: MIR 3.2.5 convergence release

## Context

MIR C31 froze the unreleased 3.2.4 research-cost package before the planned 3.2.5 compatibility-observability slice. Releasing both packages would require two player upgrades, two qualification closures, and two publication campaigns while separating features that share settings, ownership, upgrade, diagnostics, and target-projection contracts.

The release state machine is monotonic and has no unpublished-supersession state. C31 therefore cannot be renamed, rewritten, or moved backward through release states.

## Decision

MIR will not publish 3.2.4. C31 remains an immutable, unpublished calibration baseline and is closed by a separate `CandidateClosureRecordV1`. Its product scope is incorporated into the development lineage of one public 3.2.5 convergence release whose public predecessor is 3.2.3. Unperformed C31-specific qualification, sealing, promotion, publication, and public-verification obligations are cancelled; they are not inherited by 3.2.5 under the C31 identity.

3.2.5 combines:

- fixed, linear, exponential, and hybrid research costs;
- runtime progress preservation and profile migration;
- subject-level derived dispositions;
- proposition-bound compatibility proof;
- exact environment locks;
- bounded localized support reporting;
- privacy and untrusted-input limits;
- only the behavior-preserving internal consolidations required by those capabilities.

3.2.5 is one release assembled through independent vertical slices. It is not one mega-commit or an unrestricted rewrite. Stable IDs, settings, defaults, and public contracts remain compatible with 3.2.3. Breaking compiler, lifecycle, extension, and process-safety platform work remains in 3.3.

Factorio 2.0 projection is evaluated throughout 3.2.5 development. The final 2.5.5 package is reconstructed from the immutable 3.2.5 semantics and the latest qualified 2.5.x baseline through governed target adapters, then qualified independently.

## Release-value firewall

3.2.5 source freeze is blocked by complete cost semantics and transition proof; exact default, upgrade, configuration-change, and save/reload parity; terminal per-leaf dispositions; proof and environment locks; bounded localized support and privacy contracts; package composition and manifest proof; public-contract ABI comparison; Factorio 2.0 slice dispositions; a trustworthy release controller; and exact candidate qualification.

3.2.5 source freeze is not blocked by completing the entire script-to-command migration, removing all checked-in target-line mirrors, locking every museum installation source, finishing the full MIR Extension Protocol, introducing typed `SettingSpec`, adding a runtime service registry, implementing `ProcessIR`, generalizing trusted external adapters, or building broad generated target projections. Those remain separately governed 3.3, 2.6, or maintenance work unless a demonstrated 3.2.5 release blocker earns a bounded exception.

## Consequences

- Players receive one modern upgrade and one combined explanation of the product changes.
- C31 evidence may be used only diagnostically or for an exact unchanged proposition; it cannot qualify 3.2.5 bytes, and proposition reuse does not revive cancelled C31 candidate obligations.
- The primary modern upgrade is 3.2.3 to 3.2.5.
- The final approved delta compares public 3.2.3 with 3.2.5.
- A confirmed P11 defect may still create a minimal 2.5.1 before 2.5.5.
- Package-visible development occurs only while 3.2.5 is `planned`; C32 is frozen after all package-visible slices are integrated.

## Reversal

Before C32 is sealed, individual slices can be removed through their small commits and shadow gates. C31 remains available as the exact cost-model baseline. After publication, product changes use a new release rather than rewriting 3.2.5 history.
