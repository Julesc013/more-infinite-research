---@meta

---LuaLS annotations for the current MIR API v1 draft. These declarations do
---not load MIR, register a remote interface, or provide a player implementation.
---The data module is returned by require("__more-infinite-research__.api.v1.data").
---The runtime module is exposed through remote.call("more-infinite-research.api.v1", ...).

---@class MIRApiVersion
---@field major integer @1 for this draft surface.
---@field minor integer @0 for this draft surface.
---@field product string @Current product metadata: "5.0.21000".

---@class MIRDataCapabilities
---@field technology_creation boolean @Implemented only on F200/F210.
---@field technology_family boolean @Implemented only on F200/F210.
---@field recipe_productivity boolean @Implemented only on F200/F210.
---@field research_query boolean @Currently false; use the runtime interface.

---@class MIRRuntimeCapabilities
---@field research_query boolean @True only while the native game.forces table is available.

---@alias MIRDataErrorCode
---| "invalid_definition" # Boundary value, native definition, or local family preflight failed.
---| "duplicate_identity" # A technology or requested productivity effect already exists.
---| "missing_target" # A prerequisite, ingredient, or recipe target is absent.
---| "unsupported_capability" # Data-stage publication is not available.

---@alias MIRResearchErrorCode
---| "invalid_force"
---| "invalid_technology"
---| "game_unavailable"
---| "force_not_found"
---| "technology_not_found"
---| "unsupported_capability"

---@class MIRApiTechnologyUnit
---@field count integer @Positive lossless Lua integer, at most 9007199254740991.
---@field ingredients [string, integer][] @Distinct existing ToolPrototype names on F200, or ItemPrototype names on F210; amount is 1..65535.
---@field time number @Finite seconds in [1/60, 3600000].

---@class MIRApiCraftingSpeedEffect
---@field type "character-crafting-speed"
---@field modifier number @Finite value in (0, 1].

---@class MIRApiTechnology
---@field type "technology"
---@field name string
---@field prerequisites? string[]
---@field unit MIRApiTechnologyUnit
---@field effects? MIRApiCraftingSpeedEffect[] @Only for add_technology/add_technologies.

---@alias MIRNativeMaxLevel integer|string @A finite native maximum, or the native infinite marker when the active target exposes one.

---@class MIRResearchStatus
---@field name string
---@field force_index integer @Positive native uint32 force index.
---@field researched boolean
---@field level integer @Finite native current technology level; not a derived completed-level count.
---@field enabled boolean
---@field saved_progress? number @Present only when the native field is available and finite.
---@field max_level MIRNativeMaxLevel @Native maximum. On Factorio 2.1.23, 4294967295 is the native infinite maximum.

---@class MIRDataApi
---@field get_version fun(): MIRApiVersion @Returns a fresh plain table.
---@field get_capabilities fun(): MIRDataCapabilities @Returns a fresh plain table.
---@field add_technology fun(prototype: MIRApiTechnology): string @Publishes immediately in the caller's current data stage; raises MIR_API:<MIRDataErrorCode>: <detail> on failure.
---@field add_technologies fun(prototypes: MIRApiTechnology[]): string[] @Publishes one nonempty dense family immediately and returns names in caller order.
---@field add_productivity fun(prototype: MIRApiTechnology, recipe_names: string[], change: number): string @Requires no caller effects; appends one native productivity effect per distinct recipe, then publishes immediately.

---@class MIRRuntimeApi
---@field get_version fun(): MIRApiVersion @Returns a fresh plain table.
---@field get_capabilities fun(): MIRRuntimeCapabilities @Returns a fresh plain table.
---@field get_research fun(force_index: integer, technology_name: string): MIRResearchStatus|nil, MIRResearchErrorCode|nil @Read-only current native snapshot; never initializes storage or changes research.

---Current data-boundary limits, enforced before Generator publication:
---* add_technologies accepts 1..64 dense entries; add_productivity accepts 1..64 distinct recipe names.
---* The boundary copy accepts only plain tables, finite numbers, booleans, nil, and Lua strings no longer than 4096 bytes.
---* A submitted family shares a 512 key/value-entry budget and a maximum table nesting depth of 16; cycles and metatables are rejected.
---* API technologies accept only type/name/prerequisites/unit/effects. Unit costs are numeric counts; formulas, caller icons, localization, triggers and arbitrary fields are rejected.
---* Presentation is the MIR-owned packaged thumbnail. add_technology permits only bounded character-crafting-speed effects; add_productivity accepts no caller effects and creates bounded productivity effects itself.
---* F200 science ingredients must be ToolPrototypes. F210 admits its documented concrete ItemPrototype types; names are distinct. Recipe names are nonempty bounded strings and changes are in (0, 1].
