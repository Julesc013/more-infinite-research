---
title: "MIR 2.5.5 Release Notes"
status: current
applies_to: "2.5.5"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-07
supersedes: []
superseded_by: []
---

# MIR 2.5.5 Release Notes

MIR 2.5.5 brings the 3.2.5 research-cost corrections to Factorio 2.0 while preserving the existing 2.5.0 compatibility surface.

## Highlights

- Adds fixed, linear, exponential, and hybrid research-cost models.
- Preserves completed science-unit work when costs change during an upgrade or configuration change.
- Retains stable settings and technology identities from MIR 2.5.0.
- Emits the bounded research-cost support proposition through a privacy-safe log record.
- Keeps MIR `mod-data` output and modern productivity-family adoption compiled out on Factorio 2.0.

## Upgrade

The direct supported transition is MIR 2.5.0 to 2.5.5 on Factorio 2.0.77. The governed five-archetype matrix covers Base, Space Age native ownership, automatic family creation, base continuations, and source-mod removal.

## Candidate identity

- Candidate: `2.5-P12`
- Package source: `689940f436b004cf4e5981f1944ddb04eaa17367`
- Archive SHA-256: `03DFC05F94435FAACB86F19D1BF0BCD160C515C46B8372C483EEBAEB5208A41C`
- Content SHA-256: `047B3442067FEA6D43EEE8DE4C79BE6FD265B92A059B546F6EC4D5C986CCF154`

Protected qualification and publication remain pending during the GitHub Actions outage.
