# Bob-core material laboratory and alloy-output witness

This private F210 2.1.23 fixture is for the exact no-Angel Bob-core closure
captured in `tests/fixtures/bob-core-f210-captured-facts.json`. Before it
accelerates anything, its data-final stage checks the independent identities,
ordered prerequisites, ordered science vectors, default cost and time,
finite/tail boundary, presentation flags, and recipe-productivity effect for
all fourteen selected technologies: Tin, Lead, Bronze, Gunmetal, Invar,
Nitinol and Copper Tungsten.

It additionally checks two finite, applicable upstream physical routes before
adding a fixture-owned fast machine:

| Route | Native owner | Inputs | Output | Category / time |
| --- | --- | --- | --- | --- |
| `bob-bronze-alloy` | `bob-alloy-processing` | 3 copper plate, 2 tin plate | 5 bronze alloy | `bob-mixing-furnace`, 16 s |
| `bob-gunmetal-alloy` | `bob-zinc-processing` | 8 copper plate, 1 tin plate, 1 zinc plate | 10 gunmetal alloy | `bob-mixing-furnace`, 32 s |

The ingredient/result and owner facts come from the independent captured
Bob-core contract. The category, time, and compatible
`bob-electric-mixing-furnace` identity come from the exact
`bobplates_3.0.2.zip` archive, SHA-256
`0C9A4910E2DCAA8DCABBE5BFFA67333F214EAB2EFD8C798D5EF84D90B691862D`,
member `bobplates/prototypes/recipe/alloy-recipe.lua` and member
`bobplates/prototypes/entity/entities.lua`. The fixture refuses any drift
before it changes a MIR unit or extends its disposable machine clone. It never
patches an upstream recipe, a force recipe bonus, or ordinary material tuning.

On a new disposable world the fixture seeds only the explicit non-MIR
prerequisites. It first performs 100 real crafts of each selected alloy in a
module-free clone of the captured machine while each MIR route has zero
productivity. It then inserts the six independently named science packs into a
real lab and earns three finite levels plus one continuation level for every
family. Finally it performs 100 real crafts of each same untouched native
route with the earned native 8% productivity. The before phase requires the
exact base outputs (500 Bronze and 1,000 Gunmetal); the after phase requires
the native whole-craft rounding range (535–540 Bronze and 1,070–1,080
Gunmetal), with the machine productivity-progress field agreeing with that
mass balance.

The research phase requires 28 native `on_research_finished` events, exact
28/20/16/8/10/4 input consumption
(automation/logistic/chemical/production/space/metallurgic), and a native 8%
bonus on every named material route. The completed archive is
`mir5-native-complete.zip`, as required by `Invoke-NativeFixture.ps1`; the
native runner must then perform two cold reloads, where this fixture only reads
the saved witness.

The host control exercises data-stage rejection, the bounded pre-research
physical input/output phase, and read-only save validation using small Lua
doubles. It does not launch Factorio, establish a native physical result, or
qualify ordinary recipe tuning, arbitrary Bob configurations, foreign-force
behavior, migration, performance, multiplayer, final package, or release.
The current candidate needs a new native production stage and two actual cold
reloads for this added physical-output witness; the earlier Bob-core gameplay
chain remains evidence only for its original 28-lab/save scope.
