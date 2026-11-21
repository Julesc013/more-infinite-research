---
title: "Worker storage cap-ten data observer fixture"
status: current
applies_to: "Gamer433 data-stage preparation"
audience: developer
doc_type: test-guide
owner: mir-maintainers
last_reviewed: 2026-11-20
---

# Worker storage cap-ten data observer fixture

This data-stage-only fixture records the exact sorted active-mod table and the seven declared worker-storage startup setting values from `settings.startup[name].value`. It does not create a world or save, inspect prototypes, change settings or defaults, manipulate forces, or establish a research, cap-ten, cargo, gameplay, or release result.

The canonical metadata targets Factorio2.1; the committed `info-f200.json` is the narrow alternate metadata selected by the revision-pinned fixture packager for Factorio2.0. Both require MIR and keep the same fixture identity/version. This observer archive is deliberately distinct from any later full cargo actor archive; a source-to-candidate scenario must use identical bytes for its selected full actor, not infer that identity from this data-only observer.

The marker records actual typed values, including `false` and zero. A later data-capture reader must compare every logged value with the hash-bound requested settings file. The observer does not inspect `default_value`, so a prototype default cannot substitute for a loaded setting.
