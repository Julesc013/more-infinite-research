---
title: "Factorio 2.1 Experimental Channel Policy"
status: current
applies_to: "F210 until the first official Factorio 2.1 stable release"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-09-01
supersedes: []
superseded_by: []
source_of_truth_for:
  - factorio-2.1-experimental-channel-operator-guidance
---

# Factorio 2.1 experimental channel policy

F210 follows the latest Factorio 2.1 experimental build installed by Steam. It does not pin a long-lived 2.1 patch while no official 2.1 stable line exists. MIR may adopt newer 2.1 APIs and raise its declared Factorio compatibility floor when an exact qualified change requires them.

The selector and the proof identity are different facts:

- `spec/engines/mir4-factorio-2.1-experimental-channel-v1.json` selects the moving `latest-experimental` channel.
- Every build, test, upgrade, performance run, qualification, and release receipt records the exact selected version and executable hash.
- Evidence from one 2.1 patch is not reused for another patch. An update selects a new exact execution identity and requires new affected proof.
- Historical 2.1.14 records remain immutable evidence for the bytes they originally qualified; they are not current F210 selection authority.

Run `./tools/mir.ps1 mir4 factorio-2.1-channel inspect --factorio <path> --output <path>` whenever Steam changes the installation. A version, binary, runtime API, prototype API, or changelog identity change produces a review packet with tasks for:

- exact engine custody and release-note review;
- runtime and prototype API additions, removals, and deprecations;
- implementation and functionality opportunities;
- fixture, runtime, upgrade, reload, and performance impact;
- documentation, locale, UI, and minimum-compatibility impact; and
- detection of the first official 2.1 stable transition.

The scheduled assurance workflow materializes this packet before its normal F210 plan. Review tasks may discover an immediate improvement, a future work item, a compatibility-floor increase, or an explicit no-change disposition. A new API is never silently treated as irrelevant.

When the first official Factorio 2.1 stable release appears, stop using this policy as an automatic selector. Reconfirm the stable channel, minimum version, experimental-to-stable transition proof, support window, and release policy with the maintainer before changing authority.
