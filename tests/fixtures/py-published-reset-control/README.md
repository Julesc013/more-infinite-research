# Py published reset control fixture

This private 0.2.0 fixture keeps the integration-catalogue fixture identity so
that the existing `integration-foreign-owner` 0.2.0 migration can be selected
unchanged. It is paired only with published MIR 4.7.20002, never MIR 5.

The source stage is the existing 0.1.0 Py fixture and actor. The control stage
changes only the private fixture/actor versions, so Factorio runs migrations
and configuration callbacks. The actor migration records that it restored its
one owned foreign primary to `enabled=false` before callbacks. This successor
then reads the stored full foreign-force snapshot and requires the named Py
primary to be enabled while every other captured technology field, recipe productivity bonus,
gun modifier and native force modifier remains unchanged. The marker records
that before/after boundary together with the finite profile and primary. The
controller must separately verify the actor's migration log for the same force
and primary, with `expected_disabled=true` and `observed_after=false`, before
accepting the control. The fixture cannot read another mod's private storage.

Run 40089321549 preserves the original observer isolation defect: the observer
incorrectly expected actor storage inside its own mod. The actor's actual
`observed_before=false` and `observed_after=false` prove disablement at migration;
that failed observer establishes no later callback state or causal attribution.

Run 40090561999 preserves a second observer schema defect: the source snapshot
stores each recipe's numeric `productivity_bonus`, while the observer compared
its boolean `enabled` field with that number. It establishes no recipe mutation.
The corrected observer compares the same captured productivity field and keeps
every other expectation unchanged.

Only these exact F200 selections are admitted:

- Py Coal: `pycoalprocessing` 3.0.44 with `pypostprocessing` 3.0.42.
- Py AlienLife/HighTech: the retained 3.0.44/3.0.67/3.0.19 closure.

The fixture has no data-stage writes and never writes technology, recipe,
force, effect, research, queue or actor state. It uses the ordinary private
runner save name solely as a native completion boundary. Its result is a
published-only configuration observation: it establishes no MIR 5 behavior,
gameplay, reload-preservation, save, compatibility or release claim. The
original strict MIR 5 foreign-owner adverse remains a separate result.
