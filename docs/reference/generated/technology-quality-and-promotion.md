---
title: "Technology Quality And Promotion Inventory"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-24
supersedes: []
superseded_by: []
---

# Technology Quality And Promotion Inventory

> Generated from `.mir/technology-quality-profiles.json` and `.mir/technology-governance.json`. Governance records, not this table, are authoritative.

## Quality profiles

| Profile | Candidate class | Members | Clusters max | Progression max | Science tiers max | Labs min | Owner conflicts max |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `base-continuation-v1` | `base-continuation` | 1-1 | 1 | 16 | 4 | 1 | 0 |
| `exact-overhaul-material-v1` | `exact-overhaul-material` | 1-128 | 32 | 64 | 4 | 1 | 0 |
| `existing-stream-attachment-v1` | `existing-stream-attachment` | 1-512 | 128 | 128 | 6 | 1 | 0 |
| `native-owner-patch-v1` | `native-owner-patch` | 1-64 | 16 | 64 | 6 | 1 | 0 |
| `new-lab-manufacturing-v1` | `new-lab-manufacturing` | 2-16 | 8 | 16 | 2 | 2 | 0 |
| `new-machine-manufacturing-v1` | `new-machine-manufacturing` | 2-64 | 16 | 32 | 3 | 1 | 0 |
| `process-family-experimental-v1` | `process-family-experimental` | 2-64 | 16 | 32 | 4 | 1 | 0 |

Every profile also binds explicit semantic and observational evidence lists in the machine authority. Missing measurements remain incomplete and cannot pass promotion admission.

## Reviewed automatic-generation authorizations

| Authorization | Trust | Pack | Family | Stream | Provider version |
| --- | --- | --- | --- | --- | --- |
| `mir.reviewed.compiler-contract-fixture-v1` | `mir-reviewed` | `pack-operational` | `assembling-machine-manufacturing` | `research_auto_assembling_machine` | `family-rule-v3` |
| `mir.reviewed.semantic-family-fixture-v1` | `mir-reviewed` | `semantic-family-fixture` | `assembling-machine-manufacturing` | `research_auto_assembling_machine` | `family-rule-v3` |
| `mir.reviewed.upgrade-automatic-family-v1` | `mir-reviewed` | `mir-upgrade-automatic-family` | `assembling-machine-manufacturing` | `research_auto_assembling_machine` | `family-rule-v3` |

## Lifecycle record counts

| Record class | Count |
| --- | ---: |
| `approvals` | 0 |
| `promotions` | 0 |
| `applicability_envelopes` | 0 |
| `migrations` | 0 |

A zero promotion count is explicit: broad automatic creation remains disabled and no candidate is represented as promoted without a passing assessment, human approval, applicability envelope, migration decision, and upgrade evidence.
