# Agriculture scale witness

This private F210 2.1.23 fixture is a bounded physical scale witness for Space Age agricultural towers. Its three selector fixtures set the fixture-only startup tier to exactly 1, 32, or 128 towers per force. They also select the existing all-official science policy and its promethium gate before MIR emits the agriculture technology.

The core fixture first verifies the unaccelerated candidate definition: the named technology is enabled and infinite, uses the captured default 40000*1.5^(L-1) / 90-second tuning, retains its one-percent displayed effect, and has the exact twelve-pack all-official vector and promethium gate. Only its local data-final stage then changes that verified test-world prototype to one unit and one second. It does not alter the effect, crop timer, spoilage timer, or product source.

For each selected tier, a real lab completes two agriculture levels. The fixture creates N player towers and N zero-research foreign towers on generated native yumako soil, supplies real yumako seeds, and observes exactly 2N native on_tower_planted_seed events. It requires the player plants to retain floor(18000 / 1.01^2) ticks and the foreign plants to retain 18000 ticks. The fixture also records a bounded four-stack native yumako spoilage witness at the unmodified global baseline one. It records a native profiler string for the tower/seed insertion burst, but does not interpret it as a timing result.

The completed world is saved as mir5-native-complete while plants remain in their native lifecycle. Two cold reloads must preserve research, force, tower-event, plant deadline, and spoil-stack deadline witnesses. on_load takes a local read-only snapshot and never repairs storage, technologies, effects, crop timers, or stacks.

This is a candidate-only physical contract until a separately captured published 4.7 F210 package proves the same authored agriculture definition. It cannot claim a published-versus-candidate performance comparison, ordinary tuning qualification, or a generic agriculture workload. Host controls use only small runtime doubles; they do not claim a Factorio execution.

## Published source capture

[`agriculture-published-f210-2123.json`](../../../profiles/agriculture-published-f210-2123.json) predeclares an F210 2.1.23 Defaults `--dump-data` capture of the published 4.7.21002 archive. `Invoke-PrototypeCapture.ps1` receives that archive separately as its sole MIR selection; the profile binds only the exact official closure and active-mods observer. It selects no agriculture core or tier fixture, acceleration, gameplay, save/reload, or benchmark path, and does not change this candidate fixture or its oracle. The capture may determine whether the two definitions can share a witness; actual contract equality and paired 1/32/128 qualification remain pending.
