---
title: "Technology Lifecycle Schemas"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# Technology Lifecycle Schemas

MIR uses one governed record chain for fixed and procedural technology work. `.mir/technology-lifecycle.json` owns record versions, approval decisions, identity transitions, migration strategies, tooling paths, and lifecycle invariants. Lua validators own data-stage records; offline review artifacts use canonical SHA-256 transport fingerprints.

## Records

| Record | Purpose |
| --- | --- |
| `TechnologyCandidate` schema 1 | Describes a semantic capability and typed subjects discovered by providers or the compatibility-preserving stream planner without choosing a released identity. |
| `TechnologyDesign` schema 2 | Describes one materialization alternative and its complete prototype projection. |
| `TechnologyQualification` schema 1 | Compatibility name for the schema-1 hard-safety qualification contract. |
| `SafetyQualification` schema 1 | Evaluates one design in one exact context and returns `qualified`, `proposal`, or `rejected` from explicit hard-gate states. |
| `DesignAssessment` schema 1 | Records design-quality evaluation independently from hard safety and promotion trust. |
| `PromotionAuthorization` schema 1 | Binds a named authorization, exact subject, trust class, provider version, and evidence without changing safety or quality. |
| `TechnologyQualityAssessment` schema 1 | Applies one governed quality profile to an exact candidate, design, qualification, metric set, and evidence set without granting promotion authority. |
| `TechnologyApproval` schema 1 | Records an approved, quarantined, or demoted maintainer decision with applicability, exact selected alternative, field locks, adaptive envelopes, evidence, reviewer, and time. |
| `TechnologyApplicabilityEnvelope` schema 1 | Binds approved scope to exact Factorio lines, features, mods, finite structural predicates, positive and negative examples, and a maximum count of newly matched subjects. |
| `TechnologyPromotion` schema 1 | Advances an identity through one permitted transition and binds an approval plus exact design fingerprint. |
| `TechnologyMigration` schema 1 | Governs released identity changes and their save behavior. |
| `TechnologyCatalog` schema 2 | Canonically inventories every applicable materializing and safe diagnostic alternative with its exact qualification, then records deterministic current selections. It has no mutation or publication authority. |
| `TechnologyPromotionAdmission` schema 1 | Fails closed over the exact catalog alternative, passing quality assessment, approval, applicability envelope, evidence, identity edge, migration policy, and field locks. |

Every compilation materializes the context-owned schema-2 catalog before the GenerationPlan is finalized. The catalog's pure selection policy sorts independent alternatives, excludes rejections, and records one current selection per candidate. The GenerationPlan must be an exact projection of those selections. Diagnostics control only whether detailed internal projections are published; they do not control whether the canonical catalog exists. The catalog cannot publish or mutate a prototype.

Reviewed automatic generation is not authorized by an external pack's self-description. A pack must reference an exact authorization in MIR's source-owned promotion registry, and the pack ID, family ID, provider ID, provider version, trust class, and authorization ID must all match. Only `mir-reviewed` and `protected-release` satisfy reviewed mode; `fixture-only`, `local-user`, and `external-mod-author` remain non-promoting evidence classes.

## Identity transitions

Identity transitions are deliberately one-way:

```text
unassigned -> provisional -> reserved -> stable-unreleased -> released -> retired
```

A technology name does not advance the state. A promotion record advances exactly one edge and binds the candidate, approval, approved design fingerprint, migration policy, version, and evidence. Quarantine and demotion lower approval or qualification standing; they never silently delete, rename, or un-research a released technology.

Released identity changes require a migration strategy: `retain-hidden-alias`, `retain-visible-alias`, `in-place-compatible`, or `retire-with-replacement`.

## Review tools

Export a full GenerationPlan artifact into a durable catalog:

```powershell
.\scripts\Export-MIRTechnologyCatalog.ps1 -GenerationPlanPath out\generation-plan.json -OutputPath out\technology-catalog.json
```

Evaluate the selected alternative against a governed profile, produce a deterministic review dossier, and enforce promotion admission:

```powershell
.\scripts\New-MIRTechnologyQualityAssessment.ps1 -CatalogPath out\technology-catalog.json -CandidateId <candidate> -ProfileId release -MetricsPath metrics.json -EvidencePath evidence.json -OutputPath assessment.json
.\scripts\New-MIRTechnologyReviewDossier.ps1 -CatalogPath out\technology-catalog.json -CandidateId <candidate> -AssessmentPath assessment.json -OutputPath dossier.json
.\scripts\Test-MIRTechnologyPromotionAdmission.ps1 -CatalogPath out\technology-catalog.json -CandidateId <candidate> -AssessmentPath assessment.json -ApprovalPath approval.json -PromotionPath promotion.json -EvidencePath evidence.json -OutputPath admission.json
```

Compare leaf-field values and enforce an approval's locks:

```powershell
.\scripts\Compare-MIRTechnologyDesigns.ps1 -BeforePath before.json -AfterPath after.json -ApprovalPath approval.json -OutputPath diff.json
```

Create deterministic approval, quarantine, demotion, promotion, or migration records from a review request:

```powershell
.\scripts\New-MIRTechnologyLifecycleRecord.ps1 -Kind Approval -InputPath request.json -OutputPath approval.json
```

Exact approved design fingerprints return `APPROVED`. Unchanged designs return `UNCHANGED`; adaptive changes return `TARGETED_REVIEW`; unreviewed changes return `REVIEW_REQUIRED`; locked drift returns `REJECTED_LOCK_VIOLATION`.

Passing hard safety gates never creates approval, advances identity, expands applicability, or raises a public compatibility claim.

An approved decision must carry both a non-empty exact mod closure and a machine-readable applicability envelope. A label is not an envelope. The envelope is independently fingerprinted, requires positive and negative examples, and fails closed when its target line, feature set, mod closure, structural predicates, or `maximum_new_matches` bound is not satisfied. See [TechnologyApplicabilityEnvelope](technology-applicability-envelope.md).
