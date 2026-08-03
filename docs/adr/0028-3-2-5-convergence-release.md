---
title: "ADR 0028: MIR 3.2.5 convergence release"
status: current
applies_to: "3.2.5, 2.5.5, 3.3, 2.6"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-08-03
supersedes: []
superseded_by: []
---

# ADR 0028: MIR 3.2.5 convergence release

## Context

MIR C31 froze the unreleased 3.2.4 research-cost package before the planned 3.2.5 compatibility-observability slice. Releasing both packages would require two player upgrades, two qualification closures, and two publication campaigns while separating features that share settings, ownership, upgrade, diagnostics, and target-projection contracts.

The release state machine is monotonic and has no unpublished-supersession state. C31 therefore cannot be renamed, rewritten, or moved backward through release states.

## Decision

MIR will not publish 3.2.4. C31 remains an immutable, unpublished calibration baseline and is closed by a separate `CandidateClosureRecordV1`. Its product work becomes development lineage for one public 3.2.5 convergence release whose public predecessor is 3.2.3.

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

## Consequences

- Players receive one modern upgrade and one combined explanation of the product changes.
- C31 evidence may be used only diagnostically or for an exact unchanged proposition; it cannot qualify 3.2.5 bytes.
- The primary modern upgrade is 3.2.3 to 3.2.5.
- The final approved delta compares public 3.2.3 with 3.2.5.
- A confirmed P11 defect may still create a minimal 2.5.1 before 2.5.5.
- Package-visible development occurs only while 3.2.5 is `planned`; C32 is frozen after all package-visible slices are integrated.

## Reversal

Before C32 is sealed, individual slices can be removed through their small commits and shadow gates. C31 remains available as the exact cost-model baseline. After publication, product changes use a new release rather than rewriting 3.2.5 history.
