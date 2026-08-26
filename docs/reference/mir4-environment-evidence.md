---
title: "MIR 4 Environment Evidence V1"
status: current
applies_to: "4.0.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-portable-exact-environment-lock
  - mir4-environment-diff
  - mir4-support-bundle-redaction
  - mir4-reproducer-preserving-minimization
---
# MIR 4 Environment Evidence V1

EnvironmentLockV1 is the portable exact identity of a governed Factorio environment. It binds the target, engine executable digest, MIR distribution and source identity, ordered mod archive digests, startup settings, MEP extension digests, and contract closure under mir-canonical-json/1.

The lock deliberately excludes machine paths, host names, user names, credentials, tokens, and other private host state. Those values are neither required for reproduction nor safe to distribute. Inputs containing private field names fail closed. Diagnostic text is redacted before entering SupportBundleV1.

EnvironmentDiffV1 compares two validated locks by governed identity category. SupportBundleV1 carries one exact lock, bounded evidence, redacted diagnostics, and a proposition-specific reproducer signature. The minimizer retains every required witness and its transitive dependencies, removes unrelated context, and must preserve that signature exactly.

Use the MIR command router with mir4 environment-evidence reference to print the F210/F200 reference closure. The dedicated command also provides lock, diff, bundle, minimize, and verify modes. All records are package-excluded developer previews. They grant no prototype writes, player mutation, support claim, signing, release, or publication authority.
