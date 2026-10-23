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
---@field technology_creation boolean @Currently true.
---@field technology_family boolean @Currently true.
---@field recipe_productivity boolean @Currently true.
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

---@alias MIRNativeTechnology table @A normal Factorio technology prototype table. MIR does not define a replacement prototype DSL.

---@class MIRResearchStatus
---@field name string
---@field force_index integer @Positive native uint32 force index.
---@field researched boolean
---@field level integer @Finite native current technology level; not a derived completed-level count.
---@field enabled boolean
---@field saved_progress? number @Present only when the native field is available and finite.
---@field max_level integer @Finite native max level. On Factorio 2.1.23, 4294967295 is the native infinite maximum.

---@class MIRDataApi
---@field get_version fun(): MIRApiVersion @Returns a fresh plain table.
---@field get_capabilities fun(): MIRDataCapabilities @Returns a fresh plain table.
---@field add_technology fun(prototype: MIRNativeTechnology): string @Publishes immediately in the caller's current data stage; raises MIR_API:<MIRDataErrorCode>: <detail> on failure.
---@field add_technologies fun(prototypes: MIRNativeTechnology[]): string[] @Publishes one nonempty dense family immediately and returns names in caller order.
---@field add_productivity fun(prototype: MIRNativeTechnology, recipe_names: string[], change: number): string @Appends one native productivity effect per distinct recipe, then publishes immediately.

---@class MIRRuntimeApi
---@field get_version fun(): MIRApiVersion @Returns a fresh plain table.
---@field get_capabilities fun(): MIRRuntimeCapabilities @Returns a fresh plain table.
---@field get_research fun(force_index: integer, technology_name: string): MIRResearchStatus|nil, MIRResearchErrorCode|nil @Read-only current native snapshot; never initializes storage or changes research.

---Current data-boundary limits, enforced before Generator publication:
---* add_technologies accepts 1..64 dense entries; add_productivity accepts 1..64 distinct recipe names.
---* The boundary copy accepts only plain tables, finite numbers, booleans, nil, and Lua strings no longer than 4096 bytes.
---* A submitted family shares a 512 key/value-entry budget and a maximum table nesting depth of 16; cycles and metatables are rejected.
---* Recipe names are nonempty bounded strings and change must be finite. Factorio remains the final native schema validator.
