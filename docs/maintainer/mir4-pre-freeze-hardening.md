---
title: "MIR 4 Pre-Freeze Hardening"
status: current
applies_to: "MIR 4.0.0 pre-freeze development"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-24
supersedes: []
superseded_by: []
---
# MIR 4 pre-freeze hardening

This control plane prepares dev for a future MIR 4.0.0 freeze without authorizing one. It is package-excluded and fail-closed. The tracked records, commands, and workflows do not allocate a candidate, accept a playtest, create or use production signing keys, seal or promote distributions, mutate main or a legacy line, create tags, upload artifacts to a public service, or make a public compatibility claim.

## Immutable inputs

The post-readiness receipt binds PR 152, its merge commit and tree, the 30-of-30 evidence gate, F210 and F200 development packages, and the package-source fingerprint. The development plan keeps those packages as rehearsal inputs only. A future release run must supply a clean frozen commit/tree and exact candidate identities; development package hashes never become release identities by implication.

Every production workflow accepts the same eight inputs: source release record, candidate ID, source commit, source tree, target distribution record set, release-plan digest, proof root, and seal root. The dispatcher validates the exact inputs and the checked-out repository identity before any phase-specific command can run. While the source-freeze prohibition is present, all release transition phases stop before mutation.

## Pre-freeze checks

Run:

    .\tools\mir.ps1 release doctor --json --explain

The doctor checks the authority schemas and bindings, remote-ruleset snapshot, immutable action pins, publisher confinement, V1 default extension path, package identity, preview contract, and release workflow contract. Human signing input and explicit playtest acceptance remain blockers and are reported as such.

Audit the recorded branch and tag policy with:

    .\tools\mir.ps1 rulesets audit --json

The snapshot is evidence of the observed GitHub configuration, not permission to relax it. dev and main remain merge-only; release refs prohibit deletion and non-fast-forward changes; v4.* and dist/* updates or deletions remain blocked.

## Manual playtest evidence

Prepare isolated F210 or F200 sessions with release playtest-prepare. The command verifies the candidate, predecessor, and engine hashes before copying inputs into the session. Use release playtest-capture to retain only the named log, save, screenshot, and note files. Finish with release playtest-finalize --decision <ACCEPTED|CHANGES-REQUESTED|REJECTED> --reviewer <identity>.

Automation never invents a playtest result. Finalization requires an explicit human decision and records release_authority=false. Steam Factorio is used only for the current 2.1 engine; the preserved D:\Programs\Factorio\2.0 installation is used for 2.0.

## Public preview assets

The only release-facing preview assets are:

- mir4-api-sdk-v1-preview.zip
- mir4-mep-v1-preview.zip
- mir4-reference-extension-v1-preview.zip
- mir4-inspector-v1-preview.zip

Each archive contains source commit/tree/clean-state metadata, the exact contract set and digest, file hashes, MPL-2.0 inventory, generated-source map, conformance status, a preview notice, SPDX 2.3 SBOM, and public-safe provenance. V0 is migration input only and is not emitted as a release asset.

## Publisher and recovery boundaries

Build and qualification workflows cannot publish. The target-publication workflow has no repository checkout or build step, has read-only repository permissions, runs only on the confined mir4-publisher runner, and requires the external seal verifier under MIR_PUBLISHER_HOME to return a matching explicit publication admission before it can invoke the external client. Missing, false, or identity-mismatched admission fails closed. Tokens and signing material must stay outside the repository and all build worktrees.

The restore-drill workflow runs the offline W08 rehearsal only. It does not restore a production private key or publish. Production signing remains blocked until the maintainer provides an approved protected secret authority and completes the human recovery ceremony described in the release-governance runbook.
