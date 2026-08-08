---
title: "MIR 3 Terminal Repository Protections"
status: current
applies_to: "MIR 3 terminal programme"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-09
supersedes: []
superseded_by: []
---

# MIR 3 Terminal Repository Protections

This runbook is the settings handoff for the terminal family. The machine authority is `.mir/releases/terminal/MIR3-Terminal-Protection-HandoffV1.json`. Its current status is `specified-not-applied`; repository settings must not be claimed until an application receipt contains the observed pre-change snapshot, returned ruleset IDs, actor, timestamps, and post-change verification.

## Required outcome

Protect `dev`, `main`, and `legacy` from deletion and non-fast-forward updates. Require pull requests, stale-review dismissal, and resolved review threads. `dev` is the terminal integration branch. `main` remains the 3.2 release line, and `legacy` remains the independently qualified 2.5 projection line.

Protect the exact nine terminal tag refs against update and deletion. Tag creation remains closed until the family readiness seal exists. The release maintainer must create each signed annotated tag locally from the exact admitted commit and then push that single tag. A GitHub ruleset cannot substitute for the signed-tag, target-seal, or family-readiness checks.

Do not guess required-check context strings. A required context that no workflow emits can deadlock every protected branch. Discover context names from a successful commit on each workflow path, record their GitHub App integration IDs, and only then activate `required_status_checks`.

## Snapshot before mutation

Run with authenticated GitHub CLI access that can administer repository rulesets:

```powershell
New-Item -ItemType Directory -Force build/results/terminal-protections | Out-Null
gh api repos/Julesc013/more-infinite-research/rulesets --paginate > build/results/terminal-protections/rulesets-before.json
gh api repos/Julesc013/more-infinite-research/branches/dev/protection > build/results/terminal-protections/dev-before.json
gh api repos/Julesc013/more-infinite-research/branches/main/protection > build/results/terminal-protections/main-before.json
gh api repos/Julesc013/more-infinite-research/branches/legacy/protection > build/results/terminal-protections/legacy-before.json
```

Hash and archive those four responses before changing settings. Query successful check runs for the exact admitted heads and capture each required check's `name`, `app.id`, and conclusion. The initial minimum candidates are `Branch Policy / branch-policy` and `MIR / verification-gate`, but they are not authoritative until GitHub returns those exact context identities on the relevant heads.

## Apply and verify

Create one active branch ruleset per branch and one active tag ruleset for the exact refs. Use the repository ruleset REST endpoint, not classic branch protection, so the configuration and returned IDs can be archived uniformly:

```powershell
gh api --method POST repos/Julesc013/more-infinite-research/rulesets --input build/results/terminal-protections/dev-ruleset.json
gh api --method POST repos/Julesc013/more-infinite-research/rulesets --input build/results/terminal-protections/main-ruleset.json
gh api --method POST repos/Julesc013/more-infinite-research/rulesets --input build/results/terminal-protections/legacy-ruleset.json
gh api --method POST repos/Julesc013/more-infinite-research/rulesets --input build/results/terminal-protections/terminal-tags-ruleset.json
gh api repos/Julesc013/more-infinite-research/rulesets --paginate > build/results/terminal-protections/rulesets-after.json
```

Each branch payload must target exactly one `refs/heads/...` include and contain deletion, non-fast-forward, pull-request, and observed required-status-check rules. `main` and `legacy` should require one independent approval when another maintainer is available. A single-maintainer repository uses zero GitHub approvals plus the signed maintainer-acceptance receipt; it must not create a fake reviewer or broad bypass.

The tag payload must target only the nine refs in the machine authority and restrict creation, update, and deletion. The repository administrator is the only emergency bypass actor, bypass is pull-request-only, and every use requires an immutable incident and receipt. A package-visible emergency correction requires a new candidate; bypass never permits overwriting a tag or archive.

After application, verify a throwaway branch cannot push directly to each protected branch, force updates and deletions are rejected, unresolved conversations block merges, missing checks block merges, and an unauthorized terminal tag create/update/delete is rejected. Do not test destructive operations against a real release tag.

## Completion receipt

Record the before/after response hashes, exact ruleset IDs, observed check contexts and integration IDs, administrator, application time, verification time, and negative-test results in the machine authority. Change its status to `applied-and-verified` only after every negative test passes. The protection receipt is package-excluded and must be merged before terminal source freeze.
