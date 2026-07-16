---
title: "MIR 2.5.0 Release Notes"
status: current
applies_to: "2.5.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-16
supersedes: []
superseded_by: []
---

# MIR 2.5.0 Release Notes

MIR 2.5.0 updates the Factorio 2.0 line with the persistent content-addressed verification system developed for MIR 3.2.0. Release qualification can now reuse exact trusted proof for unchanged scenarios while rerunning only the package, gameplay, settings, migration, fixture, harness, binary, and dependency inputs that changed.

The release also prevents Factorio 2.0 packages from emitting unsupported `mod-data` prototypes. Because that guard changes packaged data-stage source, the 2.5.0 candidate receives fresh Factorio 2.0 gameplay and upgrade qualification rather than borrowing the MIR 2.4.5 matrix.

Public settings, generated technology IDs, migrations, and runtime-state namespaces remain stable from MIR 2.4.5.
