---
title: "RecipeVariantPlan Design"
status: draft
applies_to: "post-3.1.0"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# RecipeVariantPlan Design

Recycling-safe duplicate production recipes are explicitly outside the MIR 3.1.0 emission surface. The future feature uses a separate `RecipeVariantPlan`; it is not a branch inside prototype-limit code or the core `GenerationPlan` emitter.

A variant row must own a stable recipe ID, source recipe identity, complete RecipeFactV2 variant snapshot, ingredient/result parity, unlock parity, productivity-effect parity, category and surface conditions, module/effect permissions, maximum-productivity policy, localization, ownership, migration mapping, and `auto_recycle = false` intent. Planning fails closed for probabilistic/shared outputs, catalysts or productivity exclusions, recycling sources, hidden/internal recipes, unresolved unlocks, external duplicate owners, or mod-removal ambiguity.

Acceptance requires deterministic IDs, create/reload/configuration-change/upgrade/mod-removal fixtures, exact unlock and effect parity, duplicate prevention, target-adapter proof, and independent balance review. Optional dedicated machines remain a UI and honor-system layer, not a safety boundary.

This document reserves the contract only. It authorizes no 3.1.0 prototype emission and adds no setting, recipe, machine, migration, or public support claim.
