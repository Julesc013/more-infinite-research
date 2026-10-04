---
title: "MIR 4 Environment Evidence V1"
status: current
applies_to: "MIR 4.0.0+ developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-04
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

The diagnostic converter and both private-value validators share the credential text grammar in `tools/mir/application/assurance/EnvironmentEvidence.ps1`. It covers labelled tokens, access tokens, secrets, passwords and API keys, including quoted values with spaces or escaped quotes, plus Basic and Bearer authorization headers. Quoted values remain quoted after replacement; `<redacted>` is the exact placeholder. A placeholder followed by private suffix text remains sensitive. Conversion preserves the input record and converges when repeated.

The consumed A14 support-export test includes 75 synthetic assertions for these formats, both validation paths, safe text and repeated conversion. Those controls establish developer-export behavior for the tested text grammar. Candidate-bound support-export acceptance and the standalone startup-crash collector retain their separate qualification requirements.

The separate standalone collector, `scripts/Collect-MIRPlayerReport.ps1`, runs outside Factorio and keeps its Windows PowerShell-compatible redactor in that self-contained script. It covers the tested quoted credential, Basic/Bearer header, home-path and email forms in both captured logs and mod-list text. Quoted values remain valid JSON, and the manifest hashes the captured redacted bytes and records mod-list changes. Logs retain their existing 8 MiB tail limit; mod lists over 2 MiB are omitted. Settings remain hash-only, and saves and mod-package payloads are excluded. The consumed release-asset test executes the real script through PowerShell 7 and, on Windows, Windows PowerShell 5.1, including input preservation, tail/size boundaries and repeated redaction. These controlled reports do not qualify a Factorio package, prove every possible private text form safe, or replace review before sharing. The two-file collector download still binds exact frozen-source bytes and requires its own release readback.

EnvironmentDiffV1 compares two validated locks by governed identity category. SupportBundleV1 carries one exact lock, bounded evidence, redacted diagnostics, and a proposition-specific reproducer signature. The minimizer retains every required witness and its transitive dependencies, removes unrelated context, and must preserve that signature exactly.

Use the MIR command router with mir4 environment-evidence reference to print the F210/F200 reference closure. The dedicated command also provides lock, diff, bundle, minimize, and verify modes. All records are package-excluded developer previews. They grant no prototype writes, player mutation, support claim, signing, release, or publication authority.
