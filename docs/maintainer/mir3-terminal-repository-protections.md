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

This runbook applies the package-excluded authority in `.mir/releases/terminal/MIR3-Terminal-Protection-HandoffV1.json`. Its current status is `corrected-ready-for-application-blocked-external-auth`. Do not claim repository protections until the authority contains returned production ruleset IDs, immutable snapshots, an authenticated actor, timestamps, and passing negative tests.

## Branch model

`dev` is pull-request-only terminal integration. It requires the exact successful GitHub Actions contexts `branch-policy` and `verification-gate`, both from App ID `15368`, resolved review threads, deletion protection, and non-fast-forward protection.

`main` and `legacy` are promotion refs, not development branches. They must accept only an exact governed fast-forward promotion by the repository owner after the promotion commit has both required checks. Requiring a pull request on these refs would contradict the release topology: `main` advances to the immutable 3.2.9 commit, while `legacy` advances to the independently qualified dual-parent 2.5.9 integration. Their integrity/check rules have no bypass; a separate update restriction names the only actor allowed to perform the fast-forward.

Integrity rules and actor/update rules are intentionally separate. An actor allowed to satisfy an update restriction cannot thereby bypass required checks, deletion protection, or non-fast-forward protection.

## Tag model

The nine published `.5` refs are immutable immediately and have no bypass:

```text
3.2.5  2.5.5  1.9.5  1.8.5  1.7.5  1.6.5  1.5.5  1.4.5  1.3.5
```

The nine future `.9` refs use a separate create-once lifecycle. Before family readiness, creation is restricted. After the valid family-readiness receipt authorizes local signed annotated tags, only the exact maintainer actor may create them. Update and deletion are non-bypassable from the start. After GitHub returns all nine expected refs and their tag objects are verified, remove the creation-gate ruleset; the immutable update/deletion ruleset remains.

Rulesets do not prove signatures, seals, or family readiness. Those remain release-authority gates.

## Snapshot and canary

Authenticate `gh` as an actor able to administer repository rulesets, then create the output directory and snapshot the unmodified settings:

```powershell
gh auth status -h github.com
New-Item -ItemType Directory -Force build/results/terminal-protections | Out-Null
gh api repos/Julesc013/more-infinite-research/rulesets --paginate | Set-Content build/results/terminal-protections/rulesets-before.json
gh api repos/Julesc013/more-infinite-research/branches/dev/protection | Set-Content build/results/terminal-protections/dev-before.json
gh api repos/Julesc013/more-infinite-research/branches/main/protection | Set-Content build/results/terminal-protections/main-before.json
gh api repos/Julesc013/more-infinite-research/branches/legacy/protection | Set-Content build/results/terminal-protections/legacy-before.json
```

Hash every response before mutation. Pre-create only disposable refs matching `refs/heads/canary/mir3-terminal-protection-*` and `refs/tags/canary/mir3-terminal-protection-*`. Apply `canary-branch.json` and `canary-tag.json`, then prove direct branch update, non-fast-forward update, deletion, tag creation, tag update, and tag deletion are rejected. Never direct a canary payload at `dev`, `main`, `legacy`, or a release tag. Remove the canary rulesets before deleting the disposable refs, and archive the returned IDs and negative-test output.

## Production application

Post the JSON payloads from `.mir/releases/terminal/protections` in this order:

1. `dot5-immutable.json`
2. `dot9-immutable.json`
3. `dot9-creation-gate.json`
4. `dev-integrity.json`
5. `dev-workflow.json`
6. `main-integrity.json`
7. `main-promotion.json`
8. `legacy-integrity.json`
9. `legacy-promotion.json`

Use `gh api --method POST repos/Julesc013/more-infinite-research/rulesets --input <payload>`. Stop on the first rejected payload. Do not edit a payload interactively to “make it work”; record the API response, correct the governed payload in a PR, rerun the canary, and begin production application from a verified snapshot.

After application, query all rulesets again and verify exact target conditions, rule types, bypass actors, required context strings, integration IDs, and enforcement state. Prove direct `dev` pushes fail, unqualified promotion updates fail, force updates and deletions fail, and unauthorized release-tag create/update/delete operations fail using disposable refs or API evaluation—never real releases.

## Receipt and recovery

The application receipt records before/after hashes, returned ruleset IDs, observed check identities, administrator, timestamps, and every negative result. Set `applied-and-verified` only after the repository returns and enforces the exact intended state.

If application is interrupted, do not delete or weaken a successfully applied integrity ruleset. Snapshot current state, compare returned rulesets by exact name and payload, resume only missing steps, and repeat all negative tests. A protection bypass never authorizes tag/archive replacement or package mutation; any package-visible correction requires a new candidate after source freeze.
