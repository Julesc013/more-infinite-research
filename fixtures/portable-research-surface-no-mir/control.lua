script.on_nth_tick(1, function()
  local assertions = 0
  local function check(value, message) assert(value, message); assertions = assertions + 1 end
  local force = game.forces.player
  check(not remote.interfaces["more-infinite-research-browser"], "fixture has no MIR browser host")
  check(storage.research_browser == nil, "fixture requires no MIR private state")

  local catalogue = portable_factorio_catalogue.snapshot(force)
  check(catalogue and catalogue.schema == 1 and catalogue.kind == "portable-factorio-research-catalogue", "generic Factorio DTO catalogue")
  local finite = portable_core.query(catalogue, {mode = 2, status = 1, page = 2, search = "portable-surface-item"})
  check(finite.count == 25 and finite.pages == 2 and finite.page == 2 and #finite.rows == 5, "positive filtering and pagination")
  check(finite.rows[1].key == "portable-surface-item-21" and finite.rows[5].key == "portable-surface-item-25", "deterministic DTO order")
  local search = portable_core.query(catalogue, {mode = 1, status = 1, page = 1, search = "item-07"})
  check(search.count == 1 and search.rows[1].key == "portable-surface-item-07", "plain literal search")
  local infinite = portable_core.query(catalogue, {mode = 3, status = 1, page = 1, search = "portable-surface"})
  check(infinite.count == 1 and infinite.rows[1].key == "portable-surface-infinite", "positive infinite filter")
  local hidden = portable_core.query(catalogue, {mode = 1, status = 1, page = 1, search = "item-07", hidden = {["portable-surface-item-07"] = true}})
  check(hidden.count == 0, "personal hidden view is presentation-only")

  local bare = portable_core.detail(catalogue, "portable-surface-item-07")
  local enrichment = {schema = 1, families = {["portable-surface-item-07"] = "example"}, details = {["portable-surface-item-07"] = {action = "generated", family = "example"}}}
  local enriched = portable_core.detail(catalogue, "portable-surface-item-07", enrichment)
  check(bare and bare.enrichment == nil and bare.technology.family == "external", "provider absence removes enrichment only")
  check(enriched and enriched.enrichment.action == "generated" and enriched.technology.family == "example", "optional copied enrichment attaches")
  local function enrichment_limit(details)
    local result, reason = portable_core.detail(catalogue, "portable-surface-item-07", {schema = 1, details = {["portable-surface-item-07"] = details}})
    return result == nil and reason == "enrichment-limit"
  end
  local wide = {}
  for i = 1, portable_core.detail_node_limit do wide[i] = "x" end
  check(enrichment_limit(wide), "wide detail enrichment fails closed")
  local deep, cursor = {}, {}
  deep.next = cursor
  for _ = 1, portable_core.detail_depth_limit do
    local child = {}
    cursor.next, cursor = child, child
  end
  check(enrichment_limit(deep), "over-depth detail enrichment fails closed")
  check(enrichment_limit({value = string.rep("x", portable_core.detail_string_limit + 1)}), "oversized string detail enrichment fails closed")
  check(enrichment_limit({[string.rep("k", portable_core.detail_key_length + 1)] = "x"}), "oversized key detail enrichment fails closed")
  local unchanged = portable_core.query(catalogue, {mode = 1, status = 1, page = 1, search = "portable-surface-item"}, enrichment)
  check(unchanged.count == 25, "provider absence does not remove catalogue rows")
  helpers.write_file("portable-research-surface-no-mir.json", helpers.table_to_json({status = "passed", assertions = assertions, engine = helpers.game_version, scope = "exact-canonical-core-and-generic-factorio-adapter-without-mir"}), false)
  script.on_nth_tick(1, nil)
end)
