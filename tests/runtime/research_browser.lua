local browser_provider = require("__more-infinite-research__/prototypes/mir/runtime/research_browser_mir_provider")
local native_startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")
local native_profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local native_settings_catalog = require("__more-infinite-research__/prototypes/mir/settings/catalog")

-- Keep the portable settings witness independent from generated-stream detail:
-- F200 can legitimately show an owned maximum-level setting without a sealed
-- F210 generation-plan row, family, compiler action, or ownership claim.
local function check_runtime_settings_binding_contract(check)
  local catalogue = {schema = 1, rows = {
    {key = "runtime-settings-bridge-tech", available = true, researched = false,
      queued = false, infinite = false, native_order = "", progression = 1}
  }}
  local function envelope(state, selected, effective)
    local changed_from_default = effective ~= 3
    return {
      schema = 2,
      kind = "portable-research-enrichment",
      caps = {}, families = {}, details = {},
      runtime_settings_bindings = {
        ["runtime-settings-bridge-tech"] = {
          schema = 1,
          source = "generated-stream",
          policy_transport = "settings-derived-v3",
          binding = {
            technology_id = "runtime-settings-bridge-tech",
            declared_key = "bridge-stream",
            setting_name = "ips-max-level-bridge"
          },
          setting = {
            name = "ips-max-level-bridge", default = 3, raw_direct = effective,
            effective = effective, source = "direct", changed = false,
            changed_from_default = changed_from_default, restart_required = true
          },
          selected_effective = selected,
          state = state
        }
      }
    }
  end
  local function binding_detail(value)
    return browser_core.detail(catalogue, "runtime-settings-bridge-tech", value)
  end

  local forged_schema1 = {
    schema = 1,
    runtime_settings_bindings = envelope("finite", 3, 3).runtime_settings_bindings
  }
  local forged_detail = binding_detail(forged_schema1)
  check(forged_detail and forged_detail.runtime_settings_binding == nil,
    "schema-1 enrichment cannot surface a forged runtime settings witness")

  local finite = envelope("finite", 3, 3)
  local finite_detail = binding_detail(finite)
  check(finite_detail and finite_detail.runtime_settings_binding
      and finite_detail.runtime_settings_binding.state == "finite"
      and finite_detail.runtime_settings_binding.selected_effective == 3
      and finite_detail.technology.family == "external" and finite_detail.enrichment == nil,
    "finite runtime settings witness is copied without a family or compiler action")
  finite_detail.runtime_settings_binding.setting.effective = 99
  finite_detail.runtime_settings_binding.binding.declared_key = "poisoned"
  local finite_again = binding_detail(finite)
  check(finite_again.runtime_settings_binding.setting.effective == 3
      and finite_again.runtime_settings_binding.binding.declared_key == "bridge-stream",
    "returned runtime settings witness copy cannot poison its normalized source")

  local infinite = envelope("infinite", "infinite", 0)
  local infinite_detail = binding_detail(infinite)
  check(infinite_detail and infinite_detail.runtime_settings_binding
      and infinite_detail.runtime_settings_binding.state == "infinite"
      and infinite_detail.runtime_settings_binding.setting.effective == 0
      and infinite_detail.technology.family == "external" and infinite_detail.enrichment == nil,
    "infinite runtime settings witness stays separate from productive detail")

  local disabled = envelope("disabled", 3, 3)
  disabled.runtime_settings_bindings["runtime-settings-bridge-tech"].blocked_reason = "maximum_level_late_prototype_mutation"
  local disabled_detail = binding_detail(disabled)
  check(disabled_detail and disabled_detail.runtime_settings_binding
      and disabled_detail.runtime_settings_binding.state == "disabled"
      and disabled_detail.runtime_settings_binding.blocked_reason == "maximum_level_late_prototype_mutation"
      and disabled_detail.technology.cap == nil and disabled_detail.enrichment == nil,
    "disabled runtime settings witness is not an active cap or compiler detail")

  local wrong_key = envelope("finite", 3, 3)
  wrong_key.runtime_settings_bindings["other-technology"] = wrong_key.runtime_settings_bindings["runtime-settings-bridge-tech"]
  wrong_key.runtime_settings_bindings["runtime-settings-bridge-tech"] = nil
  check(browser_core.normalize_enrichment(wrong_key) == nil,
    "runtime settings witness rejects a map-key and technology mismatch")
  local wrong_state = envelope("finite", "infinite", 0)
  check(browser_core.normalize_enrichment(wrong_state) == nil,
    "runtime settings witness rejects a state and selected-value mismatch")
  local wrong_effective = envelope("finite", 3, 4)
  check(browser_core.normalize_enrichment(wrong_effective) == nil,
    "runtime settings witness rejects a selected and effective-setting mismatch")
  local wrong_source = envelope("finite", 3, 3)
  wrong_source.runtime_settings_bindings["runtime-settings-bridge-tech"].source = "native-owner"
  check(browser_core.normalize_enrichment(wrong_source) == nil,
    "runtime settings witness rejects an unapproved policy source")
  local noninteger = envelope("finite", 3.5, 3.5)
  check(browser_core.normalize_enrichment(noninteger) == nil,
    "runtime settings witness rejects a noninteger finite cap")
end

local function snapshot(force)
  local rows = {}
  for name, tech in pairs(force.technologies) do
    rows[name] = {enabled=tech.enabled, researched=tech.researched, level=tech.level, progress=tech.saved_progress, visible=tech.visible_when_disabled}
  end
  local queue = {}; for _, tech in ipairs(force.research_queue or {}) do queue[#queue+1]=tech.name end
  return helpers.table_to_json{technologies=rows,queue=queue,progress=force.research_progress}
end
local function find_browser_element(element, tag, value)
  if not (element and element.valid) then return nil end
  if element.tags and element.tags[tag] == value then return element end
  -- LuaGuiElement.children is a Factorio custom table. Traverse its keyed
  -- values so labelled flows remain transparent to fixture assertions.
  for _, child in pairs(element.children or {}) do
    local found = find_browser_element(child, tag, value)
    if found then return found end
  end
  return nil
end
local function find_browser_technology(element, technology)
  if not (element and element.valid) then return nil end
  if element.tags and element.tags.mir_browser=="select" and element.tags.technology==technology then return element end
  for _, child in pairs(element.children or {}) do
    local found=find_browser_technology(child,technology)
    if found then return found end
  end
  return nil
end
local function find_browser_queue_control(element, index, action)
  if not (element and element.valid) then return nil end
  local tags = element.tags
  if tags and tags.mir_browser == action and tags.index == index then return element end
  for _, child in pairs(element.children or {}) do
    local found = find_browser_queue_control(child, index, action)
    if found then return found end
  end
  return nil
end
local function has_browser_fact(element, fact)
  return find_browser_element(element, "mir_browser_fact", fact) ~= nil
end
local function has_numeric_browser_fact(element, fact, captions)
  local value = find_browser_element(element, "mir_browser_fact", fact)
  local caption = value and value.caption
  local argument_count = type(caption) == "table" and captions[caption[1]]
  if not argument_count then return false end
  for index = 2, argument_count + 1 do
    if tonumber(caption[index]) == nil then return false end
  end
  return true
end
local function browser_labels_fit(element, maximum_width)
  if not (element and element.valid) then return false end
  if element.type=="label" and element.style.maximal_width>maximum_width then return false end
  for _, child in pairs(element.children or {}) do
    if not browser_labels_fit(child,maximum_width) then return false end
  end
  return true
end
local function check_research_startup_controls(check, player, enrichment)
  local catalog = native_settings_catalog
  local bindings = enrichment.runtime_settings_bindings or {}
  local names = {}
  for name in pairs(bindings) do names[#names + 1] = name end
  table.sort(names)
  local seen, exercised = {}, 0
  for _, name in ipairs(names) do
    local binding = bindings[name]
    if not seen[binding.source] then
      local key = binding.binding.declared_key
      check(remote.call("more-infinite-research-browser", "open", player.index,
        {tab="research",family="all",mode=1,status=1,sort="progression",search="",selected=name}),
        "native bound research detail opens independently of compiler family")
      local root = player.gui.screen.mir_research_browser
      local pane = find_browser_element(root, "mir_browser_section", "research-detail")
      local maximum = find_browser_element(pane, "mir_browser_setting", binding.binding.setting_name)
      check(maximum and maximum.tags.mir_browser_read_only == true
        and maximum.tags.mir_browser_research_technology == name
        and maximum.tags.mir_browser == nil,
        "selected research exposes its exact read-only maximum setting")
      local enable_name = (binding.source == "generated-stream" and "ips-enable-" or "mir-enable-") .. key
      local enable = find_browser_element(pane, "mir_browser_setting", enable_name)
      check(catalog.spec(enable_name) and enable and enable.type == "checkbox"
        and enable.enabled == false and enable.state == native_startup_settings.get(enable_name)
        and enable.tags.mir_browser_research_technology == name,
        "research startup checkbox preserves its exact effective boolean")
      check(browser_labels_fit(pane, pane.style.maximal_width),
        "research startup controls fit the bounded independent detail pane")
      check(find_browser_element(pane,"mir_browser","open-vanilla")
        and find_browser_element(pane,"mir_browser","enqueue"),
        "research actions remain available above startup controls")
      seen[binding.source], exercised = true, exercised + 1
    end
  end
  check(exercised > 0, "native controller supplies at least one registered research startup binding")
  check(remote.call("more-infinite-research-browser", "open", player.index,
    {tab="research",family="all",mode=1,status=1,sort="progression",search="",selected="mir-browser-test-finite"}),
    "ordinary research detail opens without a MIR binding")
  check(not find_browser_element(player.gui.screen.mir_research_browser,"mir_browser_read_only",true),
    "ordinary research does not acquire unrelated MIR startup controls")
end
local function emitted_productivity_technology(player)
  local names = {}
  for name, technology in pairs(player.force.technologies) do
    for _, effect in pairs(technology.prototype.effects or {}) do
      if effect.type == "change-recipe-productivity" then
        names[#names + 1] = name
        break
      end
    end
  end
  table.sort(names)
  -- A native productivity technology may belong to the base game. Render each
  -- candidate in MIR scope and retain only the provider-recognized detail.
  for _, name in ipairs(names) do
    if remote.call("more-infinite-research-browser","open",player.index,{tab="research",family="mir",mode=1,sort="progression",selected=name,search=""}) then
      local root = player.gui.screen.mir_research_browser
      if has_browser_fact(root,"productivity_increment") and has_browser_fact(root,"productivity_current_cap") then return name end
    end
  end
  return nil
end
script.on_nth_tick(1,function()
  local count=0
  local function check(value,message) assert(value,message); count=count+1 end
  check_runtime_settings_binding_contract(check)
  local force=game.forces.player
  check(force.technologies["mir-browser-test-finite"].research_unit_energy==60,
    "one-second prototype research unit is sixty runtime energy ticks")
  local queue_cache=browser_core.translation_queue.new("en",1)
  local dispatch_cache=browser_core.translation_queue.new("en",1)
  browser_core.translation_queue.reset_catalogue(dispatch_cache,{"numeric-id","declined-id"},"dispatch")
  check(browser_core.translation_queue.dispatch(dispatch_cache,"numeric-id",0,function() return 701 end)
    and dispatch_cache.outstanding==1 and dispatch_cache.pending_by_id[701].key=="numeric-id"
    and dispatch_cache.pending_by_key["numeric-id"]==701 and dispatch_cache.values["numeric-id"]==nil,
    "numeric translation request ID occupies a pending slot")
  check(not browser_core.translation_queue.dispatch(dispatch_cache,"declined-id",0,function() error("declined") end)
    and dispatch_cache.outstanding==1 and dispatch_cache.values["declined-id"]=="declined-id",
    "failed translation dispatch falls back without consuming a slot")
  local priority_cache=browser_core.translation_queue.new("en",1)
  browser_core.translation_queue.reset_catalogue(priority_cache,{"catalogue-a","catalogue-b","catalogue-c","catalogue-d"},"priority")
  check(browser_core.translation_queue.prioritize(priority_cache,{"catalogue-d","catalogue-b","catalogue-d"})
    and browser_core.translation_queue.pop(priority_cache)=="catalogue-d"
    and browser_core.translation_queue.requested(priority_cache,"catalogue-d",801,0)
    and browser_core.translation_queue.pop(priority_cache)=="catalogue-b"
    and priority_cache.outstanding==1 and priority_cache.pending_by_id[801].key=="catalogue-d",
    "visible translation priority reorders only unissued work and retains issued accounting")
  local old_names={}
  for index=1,16 do old_names[index]=string.format("old-%02d",index) end
  browser_core.translation_queue.reset_catalogue(queue_cache,old_names,"catalogue-a")
  for index=1,16 do
    local key=browser_core.translation_queue.pop(queue_cache)
    check(key==old_names[index] and browser_core.translation_queue.requested(queue_cache,key,index,0),"translation initial bounded request "..index)
  end
  check(queue_cache.outstanding==16 and not browser_core.translation_queue.can_request(queue_cache),"translation window reaches its fixed outstanding limit")
  queue_cache=helpers.json_to_table(helpers.table_to_json(queue_cache))
  check(queue_cache.outstanding==16 and queue_cache.pending_by_id[1].key=="old-01"
    and queue_cache.pending_by_key["old-16"]==16,"serialized queue retains issued IDs and only plain data")
  browser_core.translation_queue.reset_catalogue(queue_cache,{"catalogue-b-1","catalogue-b-2"},"catalogue-b")
  browser_core.translation_queue.invalidate_locale(queue_cache,"fr",2)
  browser_core.translation_queue.reset_catalogue(queue_cache,{"current-1","current-2"},"catalogue-c")
  check(queue_cache.outstanding==16 and next(queue_cache.pending_by_key)==nil and not browser_core.translation_queue.can_request(queue_cache),"repeated catalogue and locale invalidations retain stale request slots")
  check(not browser_core.translation_queue.completed(queue_cache,1,"old label must not enter the current locale")
    and queue_cache.outstanding==15 and queue_cache.values["old-01"]==nil,"stale callback releases a slot without publishing its label")
  local current_key=browser_core.translation_queue.pop(queue_cache)
  check(current_key=="current-1" and browser_core.translation_queue.requested(queue_cache,current_key,101,1),"freed stale slot starts current catalogue work")
  for index=2,16 do browser_core.translation_queue.completed(queue_cache,index,"withheld stale label") end
  check(queue_cache.outstanding==1 and queue_cache.pending_by_key["current-1"]==101 and queue_cache.values["old-02"]==nil,"old callbacks preserve current key ownership and never enter labels")
  check(browser_core.translation_queue.completed(queue_cache,101,"Étiquette actuelle") and queue_cache.outstanding==0
    and queue_cache.values["current-1"]=="Étiquette actuelle","current callback resolves after stale work drains")
  local timeout_names={}
  for index=1,16 do timeout_names[index]=string.format("timeout-old-%02d",index) end
  browser_core.translation_queue.reset_catalogue(queue_cache,timeout_names,"catalogue-timeout-old")
  for index=1,16 do
    local key=browser_core.translation_queue.pop(queue_cache)
    check(browser_core.translation_queue.requested(queue_cache,key,200+index,0),"translation timeout request "..index)
  end
  browser_core.translation_queue.reset_catalogue(queue_cache,{"timeout-current"},"catalogue-timeout-current")
  check(browser_core.translation_queue.expire(queue_cache,browser_core.translation_queue.stale_ticks)==16
    and queue_cache.outstanding==0 and queue_cache.values["timeout-current"]==nil
    and #queue_cache.retry_queue==0,"stale timeout releases every superseded slot without retrying into current labels")
  if storage.browser_saved then
    check(snapshot(force)==storage.expected_force,"save/reload retains partial research and queue")
    for _, actual in pairs(game.players) do
      check(remote.call("more-infinite-research-browser","open",actual.index),"saved personal view reopens")
      check(snapshot(force)==storage.expected_force,"reopened GUI retains force state")
    end
    helpers.write_file("browser-reload.json",helpers.table_to_json{status="passed",assertions=count,engine=helpers.game_version,scope="native-single-player-save-reload-with-partial-research"},false)
    script.on_nth_tick(1,nil);return
  end
  check(force.add_research("mir-browser-progress"),"initial queue")
  force.research_progress=0.375
  local before=snapshot(force)
  local catalogue=browser_catalogue.snapshot(force)
  local static_reads=0
  local cache_prototype=setmetatable({}, {__index=function(_,key)
    if key=="max_level" or key=="order" then static_reads=static_reads+1 end
    if key=="max_level" then return "infinite" end
    if key=="order" then return "cache-order" end
  end})
  local cache_technology={name="catalogue-cache-probe",enabled=true,researched=false,
    prototype=cache_prototype,prerequisites={}}
  local cache_force={valid=true,index=937,name="catalogue-cache-force",
    technologies={[cache_technology.name]=cache_technology},research_queue={}}
  local cache_first=browser_catalogue.snapshot(cache_force)
  check(cache_first.rows[1].available and not cache_first.rows[1].researched
    and not cache_first.rows[1].queued and static_reads==2,
    "catalogue cache builds prototype facts once")
  cache_technology.researched=true
  cache_force.research_queue={cache_technology}
  local cache_second=browser_catalogue.snapshot(cache_force)
  check(not cache_second.rows[1].available and cache_second.rows[1].researched
    and cache_second.rows[1].queued and static_reads==2,
    "catalogue cache retains static facts while live force state changes")
  cache_force.name="catalogue-cache-reused-index"
  local cache_reused=browser_catalogue.snapshot(cache_force)
  check(cache_reused.rows[1].researched and static_reads==4,
    "catalogue cache rebuilds when a force index is reused")
  local shortcut=prototypes.shortcut["mir-research-browser"]
  check(shortcut and shortcut.action=="lua" and shortcut.toggleable,"toggleable native browser shortcut")
  local ordering={schema=1,rows={
    {key="later",available=true,researched=false,queued=false,infinite=false,native_order="a",progression=2},
    {key="earlier",available=true,researched=false,queued=false,infinite=false,native_order="z",progression=1}
  }}
  local progression=browser_core.query(ordering,{mode=1,status=1,page=1,search="",sort="progression"})
  local native=browser_core.query(ordering,{mode=1,status=1,page=1,search="",sort="native"})
  check(progression.rows[1].key=="earlier" and native.rows[1].key=="later","progression and native ordering")
  local mir_focus=browser_core.query(catalogue,{mode=1,status=1,page=1,search="mir-browser-test",family="mir"},{schema=1,families={ ["mir-browser-test-finite"]="productivity"}})
  check(#mir_focus.rows==1 and mir_focus.rows[1].key=="mir-browser-test-finite","MIR-focused default family contract")
  local without_mir=browser_core.family_names(nil)
  check(#without_mir==2 and without_mir[1]=="all" and without_mir[2]=="external","provider absence keeps the portable catalogue available")
  local unbounded_productivity={
    schema=2,
    kind="portable-research-enrichment",
    caps={},
    families={["mir-browser-test-finite"]="productivity"},
    details={["mir-browser-test-finite"]={
      schema=1,
      family="productivity",
      action="emit",
      owner={technology_id="mir-browser-test-finite",stream_id="productivity",action="emit",reason="fixture",affected_recipe_ids={"mir-browser-recipe"}},
      compiler_disposition={inclusion="included",action="emit",reason="fixture",route_exclusions={state="no-additional-route-exclusions-published-for-current-row",recipe_ids={}}},
      final_science={rationale="fixture",ingredients={{name="automation-science-pack",amount=1}}},
      current_level=1,
      recipe_benefits={{recipe_id="mir-browser-recipe",effect_change=0.02,current_productivity_bonus=0,maximum_productivity=3,next_level_has_effective_benefit=true}},
      next_level_eligible=true,
      next_level_has_effective_benefit=true
    }}
  }
  local unbounded_detail=browser_core.detail(catalogue,"mir-browser-test-finite",unbounded_productivity)
  check(unbounded_detail and unbounded_detail.enrichment and unbounded_detail.enrichment.effective_cap==nil
    and unbounded_detail.enrichment.next_level_eligible==true
    and unbounded_detail.enrichment.recipe_benefits[1].maximum_productivity==3,"unbounded MIR productivity detail remains provider-visible")
  local recipe_search=browser_core.query(catalogue,{mode=1,status=1,page=1,
    search="browser recipe"},unbounded_productivity)
  check(recipe_search.count==1 and recipe_search.rows[1].key=="mir-browser-test-finite",
    "affected recipe ID discovers its productive research")
  local capped_productivity=helpers.json_to_table(helpers.table_to_json(unbounded_productivity))
  local capped_detail=capped_productivity.details["mir-browser-test-finite"]
  capped_productivity.caps["mir-browser-test-finite"]=3
  capped_detail.effective_cap=3
  capped_detail.settings={
    maximum_level={name="ips-max-level-productivity",default=3,raw_direct=3,effective=3,source="direct",changed=false,changed_from_default=false,restart_required=true},
    enabled={name="ips-enable-productivity",default=true,raw_direct=true,effective=true,source="direct",changed=false,changed_from_default=false,restart_required=true}
  }
  capped_detail.current_level=4
  check(browser_core.normalize_enrichment(capped_productivity)==nil,"explicit eligibility above the finite cap is rejected")
  capped_detail.current_level=3
  capped_detail.next_level_eligible=false
  capped_detail.next_level_has_effective_benefit=false
  capped_detail.recipe_benefits[1].next_level_has_effective_benefit=false
  check(browser_core.normalize_enrichment(capped_productivity)~=nil,"explicit unavailable state inside the finite cap stays accepted")
  capped_detail.next_level_eligible=nil
  capped_detail.next_level_has_effective_benefit=true
  capped_detail.recipe_benefits[1].next_level_has_effective_benefit=true
  check(browser_core.normalize_enrichment(capped_productivity)~=nil,"legacy finite provider retains cap-derived eligibility")
  local finite={mode=2,status=1,page=1,search="mir-browser-test"}
  local infinite={mode=3,status=1,page=1,search="mir-browser-test"}
  local a=browser_core.query(catalogue,finite)
  local b=browser_core.query(catalogue,infinite)
  check(#a.rows==1 and a.rows[1].key=="mir-browser-test-finite","finite personal filter")
  check(#b.rows==1 and b.rows[1].key=="mir-browser-test-infinite","infinite personal filter")
  check(before==snapshot(force),"personal filters changed force state")
  check(finite.mode==2 and infinite.mode==3,"view states not isolated")
  local capped=browser_core.query(catalogue,finite,{schema=1,caps={["mir-browser-test-infinite"]=3}})
  check(#capped.rows==2,"effective MIR cap classification")
  local literal=browser_core.query(catalogue,{mode=1,status=1,page=1,search="%["})
  local spaced_id=browser_core.query(catalogue,{mode=1,status=1,page=1,search=" MIR browser test finite "})
  check(spaced_id.count==1 and spaced_id.rows[1].key=="mir-browser-test-finite",
    "search matches words in stable IDs while localized names are pending")
  check(#literal.rows==0,"literal search")
  local localized=browser_core.query(catalogue,{mode=1,status=1,page=1,search="localized finite"},nil,{["mir-browser-test-finite"]="Localized finite technology"})
  check(#localized.rows==1 and localized.rows[1].key=="mir-browser-test-finite","localized search with stable-ID fallback")
  local localized_ordering={schema=1,rows={
    {key="label-zebra",available=true,researched=false,queued=false,infinite=false,native_order="",progression=1},
    {key="label-alpha",available=true,researched=false,queued=false,infinite=false,native_order="",progression=1},
    {key="label-equal-a",available=true,researched=false,queued=false,infinite=false,native_order="",progression=1},
    {key="label-equal-b",available=true,researched=false,queued=false,infinite=false,native_order="",progression=1},
    {key="label-fallback",available=true,researched=false,queued=false,infinite=false,native_order="",progression=1},
    {key="label-nonlatin",available=true,researched=false,queued=false,infinite=false,native_order="",progression=1}
  }}
  local initial_label=browser_core.query(localized_ordering,{mode=1,status=1,page=1,search="translated later",sort="name-asc"})
  check(#initial_label.rows==0,"untranslated localized search remains incomplete rather than a false match")
  local labels={
    ["label-zebra"]="Apple",
    ["label-alpha"]="Zulu",
    ["label-equal-a"]="Same label",
    ["label-equal-b"]="same label",
    ["label-nonlatin"]="漢字技術"
  }
  local held_name_order=browser_core.query(localized_ordering,{
    mode=1,status=1,page=1,search="",sort="name-asc",name_index_ready=false,fallback_sort="progression"
  },nil,labels)
  check(held_name_order.sort=="progression" and held_name_order.requested_sort=="name-asc"
    and held_name_order.name_index_ready==false and held_name_order.rows[1].key=="label-alpha",
    "partial labels retain the stable browse order until the name index is complete")
  local resolved_labels=browser_core.query(localized_ordering,{mode=1,status=1,page=1,search="translated later",sort="name-asc"},nil,{
    ["label-alpha"]="Translated later"
  })
  check(#resolved_labels.rows==1 and resolved_labels.rows[1].key=="label-alpha","late translation updates the stable selected technology ID")
  local automatic_catalogue={schema=1,rows={
    {key="automatic-a",available=true,researched=false,queued=false,infinite=false,native_order="a",progression=1},
    {key="automatic-z",available=true,researched=false,queued=false,infinite=false,native_order="z",progression=2}
  }}
  local automatic_cache=browser_core.translation_queue.new("en",1)
  browser_core.translation_queue.reset_catalogue(automatic_cache,{"automatic-a","automatic-z"},"automatic-catalogue")
  local automatic_before=browser_core.query(automatic_catalogue,{
    mode=1,status=1,page=1,search="automatic localized",sort="name-asc",
    fallback_sort="progression",name_index_ready=false
  },nil,automatic_cache.values)
  check(#automatic_before.rows==0,"localized search starts empty until its current labels arrive")
  check(browser_core.translation_queue.resolve(automatic_cache,"automatic-a","Zulu automatic localized")
    and browser_core.translation_queue.resolve(automatic_cache,"automatic-z","Alpha automatic localized")
    and browser_core.translation_queue.complete(automatic_cache) and automatic_cache.refresh_pending,
    "final localized index schedules an in-place result refresh")
  local automatic_after=browser_core.query(automatic_catalogue,{
    mode=1,status=1,page=1,search="automatic localized",sort="name-asc",
    fallback_sort="progression",name_index_ready=browser_core.translation_queue.complete(automatic_cache)
  },nil,automatic_cache.values)
  check(#automatic_after.rows==2 and automatic_after.rows[1].key=="automatic-z"
    and automatic_after.sort=="name-asc" and automatic_after.requested_sort=="name-asc",
    "completed localized index updates active search and commits displayed-name order")
  check(browser_core.translation_queue.consume_refresh(automatic_cache)
    and not automatic_cache.refresh_pending and automatic_cache.completed_since_refresh==0,
    "host refresh acknowledgement clears only the delivered current batch")
  local partial_refresh_cache=browser_core.translation_queue.new("en",1)
  local partial_names={}
  for index=1,9 do partial_names[index]=string.format("partial-%02d",index) end
  browser_core.translation_queue.reset_catalogue(partial_refresh_cache,partial_names,"partial-localized-catalogue")
  for index=1,8 do browser_core.translation_queue.resolve(partial_refresh_cache,partial_names[index],"Partial localized "..index) end
  check(partial_refresh_cache.refresh_pending and not browser_core.translation_queue.complete(partial_refresh_cache)
    and browser_core.translation_queue.consume_refresh(partial_refresh_cache)
    and partial_refresh_cache.resolved==8 and partial_refresh_cache.values["partial-09"]==nil,
    "partial localization batches are distinguishable from the one settled result refresh")
  local named=browser_core.query(localized_ordering,{mode=1,status=1,page=1,search="",sort="name-asc"},nil,labels)
  check(named.rows[1].key=="label-zebra" and named.rows[1].display_name=="Apple","displayed label rather than ID determines name order")
  local equal_a,equal_b=nil,nil
  for index,row in ipairs(named.rows) do
    if row.key=="label-equal-a" then equal_a=index end
    if row.key=="label-equal-b" then equal_b=index end
  end
  check(equal_a and equal_b and equal_a<equal_b,"equal normalized displayed labels use stable ascending technology-ID ties")
  local fallback=browser_core.query(localized_ordering,{mode=1,status=1,page=1,search="label-fallback",sort="name-asc"},nil,labels)
  check(#fallback.rows==1 and fallback.rows[1].display_name=="label-fallback","missing translation keeps the displayed stable-ID fallback")
  local nonlatin=browser_core.query(localized_ordering,{mode=1,status=1,page=1,search="漢字",sort="name-asc"},nil,labels)
  check(#nonlatin.rows==1 and nonlatin.rows[1].key=="label-nonlatin","non-Latin localized search preserves UTF-8 text")
  local deep_rows={}
  for index=1,1000 do
    local key=string.format("mir-browser-deep-%04d",index)
    deep_rows[index]={key=key,available=true,researched=false,queued=false,infinite=false,native_order="",progression=index}
  end
  local deep_catalogue={schema=1,rows=deep_rows}
  local deep_page=browser_core.query(deep_catalogue,{mode=1,status=1,page=30,search="",sort="progression"})
  check(deep_page.count==1000 and deep_page.page==30 and #deep_page.rows==20,"deep pages stay bounded beyond 512 catalogue entries")
  local descending_deep=browser_core.query(deep_catalogue,{mode=1,status=1,page=1,search="",sort="name-desc"})
  check(descending_deep.count==1000 and descending_deep.rows[1].key=="mir-browser-deep-1000"
    and descending_deep.rows[20].key=="mir-browser-deep-0981",
    "descending name order remains a strict sort across a deep catalogue")
  local retained_off_page=browser_core.query(deep_catalogue,{mode=1,status=1,page=1,search="",sort="progression"},nil,nil,"mir-browser-deep-0600")
  check(retained_off_page.selected_visible and retained_off_page.page==1 and #retained_off_page.rows==20
    and retained_off_page.rows[1].key=="mir-browser-deep-0001",
    "filtered selection remains visible when it lies beyond the rendered page")
  local deep_localized=browser_core.query(deep_catalogue,{mode=1,status=1,page=1,search="off page localized target",sort="name-asc"},nil,{["mir-browser-deep-0600"]="Off page localized target"})
  check(#deep_localized.rows==1 and deep_localized.rows[1].key=="mir-browser-deep-0600","off-page localized entry is discoverable beyond 512")
  local descending=browser_core.query(catalogue,{mode=1,status=1,page=1,sort="name-desc",search="mir-browser-test"})
  check(#descending.rows==2 and descending.rows[1].key=="mir-browser-test-infinite","descending deterministic sort")
  local excluded_selected=browser_core.query(catalogue,{mode=2,status=1,page=1,search="",sort="progression"},nil,nil,"mir-browser-test-infinite")
  local hidden_selected=browser_core.query(catalogue,{mode=1,status=1,page=1,search="",sort="progression",
    hidden={["mir-browser-test-finite"]=true}},nil,nil,"mir-browser-test-finite")
  local search_mismatched_selected=browser_core.query(catalogue,{mode=1,status=1,page=1,
    search="mir-browser-test-infinite",sort="progression"},nil,nil,"mir-browser-test-finite")
  check(not excluded_selected.selected_visible and not hidden_selected.selected_visible
    and not search_mismatched_selected.selected_visible,
    "mode, hidden, and search exclusions clear retained selection eligibility")
  local player={valid=true,force=force,permission_group={allows_action=function() return false end}}
  local tech=force.technologies["mir-browser-test-finite"]
  check(not browser_actions.can_enqueue(player,tech,defines.input_action.start_research),"permission negative")
  player.permission_group=nil
  check(browser_actions.can_enqueue(player,tech,defines.input_action.start_research),"available research")
  player.force=game.forces.enemy
  check(not browser_actions.can_enqueue(player,tech,defines.input_action.start_research),"cross-force negative")
  player.force=force
  check(not browser_actions.can_enqueue(player,force.current_research,defines.input_action.start_research),"duplicate queue negative")
  check(before==snapshot(force),"predicates changed research state")
  local queued_before=browser_core.query(catalogue,{mode=1,status=4,page=1,search="mir-browser-test-finite"})
  check(#queued_before.rows==0,"initial snapshot excludes unqueued research")
  check(force.add_research("mir-browser-test-finite"),"queue mutation")
  local refreshed_catalogue=browser_catalogue.snapshot(force)
  local queued_after=browser_core.query(refreshed_catalogue,{mode=1,status=4,page=1,search="mir-browser-test-finite"})
  check(#queued_after.rows==1 and queued_after.rows[1].queued,"second snapshot exposes queued research")
  check(force.add_research("mir-browser-queue-later"),"second pending research")
  local queue_before=force.research_queue
  local progress_before=force.research_progress
  player.permission_group={allows_action=function() return false end}
  check(not browser_actions.can_move(player,queue_before,2,1,defines.input_action.move_research),
    "queue movement respects native permission")
  player.permission_group=nil
  check(not browser_actions.can_move(player,queue_before,2,-1,defines.input_action.move_research)
    and browser_actions.can_move(player,queue_before,2,1,defines.input_action.move_research),
    "active research stays fixed while pending research can move")
  local unchanged_queue=snapshot(force)
  check(not browser_actions.move(player,2,1,"stale-technology","mir-browser-queue-later",defines.input_action.move_research)
    and snapshot(force)==unchanged_queue,"stale queue control cannot move another player's new order")
  check(browser_actions.move(player,2,1,"mir-browser-test-finite","mir-browser-queue-later",defines.input_action.move_research),
    "native queue accepts guarded pending swap")
  local moved_queue=force.research_queue
  check(#moved_queue==3 and moved_queue[1].name=="mir-browser-progress"
    and moved_queue[2].name=="mir-browser-queue-later" and moved_queue[3].name=="mir-browser-test-finite"
    and force.current_research.name=="mir-browser-progress" and force.research_progress==progress_before,
    "pending reorder preserves active research and exact progress")
  local prerequisite={valid=true,force=force,name="prerequisite",researched=false,prerequisites={}}
  local dependent={valid=true,force=force,name="dependent",researched=false,prerequisites={prerequisite}}
  check(not browser_actions.can_move(player,{moved_queue[1],prerequisite,dependent},2,1,defines.input_action.move_research)
    and not browser_actions.can_move(player,{moved_queue[1],prerequisite,dependent},3,-1,defines.input_action.move_research),
    "queue controls reject prerequisite reversal before native mutation")
  before=snapshot(force)
  local all=browser_core.query(catalogue,{mode=1,status=1,page=999999,search=""})
  check(#all.rows<=browser_core.page_size and all.page==all.pages,"bounded page clamp")
  -- LuaGameScript cannot create players. Native GUI checks require a real
  -- player from a graphical/client run or a player-bearing save. Report the
  -- zero-player headless scope explicitly instead of claiming GUI coverage.
  local native_false, native_true
  for name, setting in pairs(settings.startup) do
    local prototype=prototypes.mod_setting[name]
    if prototype and prototype.mod=="more-infinite-research" and type(setting.value)=="boolean" then
      if setting.value==false then native_false=native_false or name else native_true=native_true or name end
    end
  end
  check(native_false and native_startup_settings.raw(native_false)==false
    and native_startup_settings.get(native_false)==false,"native direct false remains a setting value")
  check(native_startup_settings.raw("mir-browser-unregistered-setting")==nil,"absent startup value remains absent")
  check(native_true,"native fixture provides a true direct setting")
  local effective_false=native_profile_codec.current_profile{names={native_true},value_resolver=function() return false end}
  check(effective_false.settings[native_true]==false,"effective false overrides direct true during profile export")
  local encoded_false=native_profile_codec.encode(effective_false)
  local decoded_false=encoded_false and native_profile_codec.decode(encoded_false)
  check(decoded_false and decoded_false.settings[native_true]==false,"false effective export survives MIRSET1 roundtrip")
  local native_players=0
  for _, actual in pairs(game.players) do
    native_players=native_players+1
    check(not actual.gui.top.mir_browser_open,"legacy top launcher absent")
    check(remote.call("more-infinite-research-browser","open",actual.index),"native default MIR browser GUI")
    local default_root=actual.gui.screen.mir_research_browser
    check(not has_browser_fact(default_root,"translation_index"),
      "default Browse shows native localized captions without an indexing countdown")
    check(find_browser_element(default_root,"mir_browser","research").toggled
      and not find_browser_element(default_root,"mir_browser","queue").toggled,
      "Browse visibly selects its navigation button")
    local default_list=find_browser_element(default_root,"mir_browser_section","research-list")
    local default_detail=find_browser_element(default_root,"mir_browser_section","research-detail")
    local default_first=find_browser_element(default_root,"mir_browser_first_visible","first")
    local default_selected=find_browser_element(default_root,"mir_browser_selected","selected")
    local default_body=default_root["mir_browser_body"]
    local default_results=default_body and default_body["mir_browser_research_results"]
    local default_search=find_browser_element(default_root,"mir_browser_section","search")
    local default_navigation=default_root["mir_browser_navigation"]
    check(default_body and default_body.type=="flow" and default_body.parent==default_root
      and default_body.style.maximal_height<=420 and (default_body.style.minimal_height or 0)<default_body.style.maximal_height
      and default_results and default_results.type=="flow" and default_results.parent==default_body
      and default_results.style.maximal_height>=80 and (default_results.style.minimal_height or 0)<default_results.style.maximal_height
      and default_list and default_list.type=="scroll-pane" and default_list.style.maximal_width>=240 and default_list.style.maximal_width<=360
      and default_list.parent==default_results and default_list.style.maximal_height>=80 and (default_list.style.minimal_height or 0)<default_list.style.maximal_height
      and default_list.horizontal_scroll_policy=="never" and default_list.vertical_scroll_policy=="auto"
      and default_detail and default_detail.type=="scroll-pane" and default_detail.style.maximal_width>=280 and default_detail.style.maximal_width<=460
      and default_detail.parent==default_results and default_detail.style.maximal_height>=80 and (default_detail.style.minimal_height or 0)<default_detail.style.maximal_height
      and default_detail.horizontal_scroll_policy=="never" and default_detail.vertical_scroll_policy=="auto"
      and default_search and default_search.parent==default_root and default_navigation and default_navigation.parent==default_root,
      "Browse fits bounded list and detail scroll panes beneath fixed controls")
    check(browser_labels_fit(default_detail,default_detail.style.maximal_width),
      "Browse detail labels wrap within their native detail pane")
    check(default_first and default_selected and default_first.tags.technology==default_selected.tags.technology
      and find_browser_element(default_root,"mir_browser","open-vanilla"),
      "initial Browse selection opens detail for the first visible research")
    local selected_technology=default_selected and default_selected.tags.technology
    default_list.scroll_to_bottom()
    check(default_detail.valid and default_selected.valid and default_selected.tags.technology==selected_technology
      and find_browser_element(default_detail,"mir_browser","open-vanilla"),
      "list scrolling retains the selected detail in its independent pane")
    local native_enrichment=browser_provider.snapshot(actual.force)
    local native_family_names=browser_core.family_names(native_enrichment)
    local mir_scope_index, all_family_scope_index
    for index, name in ipairs(native_family_names) do
      if name=="mir" then mir_scope_index=index end
      if name=="all" then all_family_scope_index=index end
    end
    local default_sort=find_browser_element(default_root,"mir_browser","sort")
    local default_scope=find_browser_element(default_root,"mir_browser","family")
    check(default_sort and default_sort.type=="drop-down" and default_sort.selected_index==1,"new personal view defaults to MIR progression")
    check(all_family_scope_index and default_scope and default_scope.type=="drop-down"
      and default_scope.selected_index==(mir_scope_index or all_family_scope_index),
      "new personal view selects declared MIR scope or all when native provider facts are absent")
    check(find_browser_element(default_root,"mir_browser","research") and find_browser_element(default_root,"mir_browser","queue")
      and find_browser_element(default_root,"mir_browser","settings") and find_browser_element(default_root,"mir_browser","availability"),
      "library presents browse, queue, setup and availability navigation")
    check(remote.call("more-infinite-research-browser","open",actual.index,{tab="queue"}),
      "native queue tab opens for the connected player")
    local queue_root=actual.gui.screen.mir_research_browser
    local active_down=find_browser_queue_control(queue_root,1,"queue-down")
    local pending_down=find_browser_queue_control(queue_root,2,"queue-down")
    local last_up=find_browser_queue_control(queue_root,3,"queue-up")
    check(active_down and not active_down.enabled and pending_down and pending_down.enabled
      and last_up and last_up.enabled and pending_down.tags.technology=="mir-browser-queue-later"
      and last_up.tags.adjacent=="mir-browser-queue-later",
      "native queue shows guarded up/down controls for pending entries")
    check_research_startup_controls(check, actual, native_enrichment)
    local filtered_request={tab="research",family="all",mode=2,status=1,sort="progression",
      selected="automation",search="mir-browser-test",page=1}
    check(remote.call("more-infinite-research-browser","open",actual.index,filtered_request),
      "native filtered browser opens with stale external selection")
    local replacement_root=actual.gui.screen.mir_research_browser
    check(has_browser_fact(replacement_root,"translation_index"),
      "localized search shows indexing while its catalogue is incomplete")
    local replacement_detail=find_browser_element(replacement_root,"mir_browser","open-vanilla")
    local replacement_first=find_browser_element(replacement_root,"mir_browser_first_visible","first")
    local replacement_selected=find_browser_element(replacement_root,"mir_browser_selected","selected")
    check(replacement_detail and replacement_first and replacement_selected
      and replacement_detail.tags.technology=="mir-browser-test-finite"
      and replacement_first.tags.technology=="mir-browser-test-finite"
      and replacement_selected.tags.technology=="mir-browser-test-finite",
      "filtered Browse replaces a stale external selection with its only visible research")
    check(remote.call("more-infinite-research-browser","open",actual.index,{mode=2,search="mir-browser-test"}),"native finite GUI")
    check(actual.gui.screen.mir_research_browser.valid,"native frame valid")
    check(remote.call("more-infinite-research-browser","open",actual.index,{mode=3,search="mir-browser-test"}),"native infinite GUI")
    check(remote.call("more-infinite-research-browser","open",actual.index,{tab="settings",search="mir-"}),"native settings GUI")
    check(has_browser_fact(actual.gui.screen.mir_research_browser,"profile_import"),"native settings profile summary")
    check(remote.call("more-infinite-research-browser","open",actual.index,
      {tab="settings",settings_scope="options",search=native_false}),"native false startup setting GUI")
    local false_field=find_browser_element(actual.gui.screen.mir_research_browser,"mir_browser_setting",native_false)
    local false_caption=false_field and false_field.caption
    local effective_caption=type(false_caption)=="table" and false_caption[1]=="mir-browser.setting-with-default"
      and false_caption[2] or false_caption
    check(false_field and false_field.type=="label" and false_field.tags.mir_browser_read_only==true
      and type(effective_caption)=="table" and effective_caption[1]=="mir-browser.setting-off",
      "false startup setting has an explicit read-only Off value")
    check(find_browser_element(actual.gui.screen.mir_research_browser,"mir_browser","settings").toggled,
      "Setup visibly selects its navigation button")
    local native_omissions=browser_provider.omissions(actual.force)
    local has_omission_transport=prototypes.mod_data
      and prototypes.mod_data["more-infinite-research-generation-plan"]~=nil
    if has_omission_transport then
      check(native_omissions and #native_omissions.rows>0,"native generation publishes exact omissions")
    else
      check(native_omissions==nil,"absent generation transport supplies no invented omissions")
    end
    check(remote.call("more-infinite-research-browser","open",actual.index,{tab="availability"}),"native Availability GUI")
    local availability_root=actual.gui.screen.mir_research_browser
    check(find_browser_element(availability_root,"mir_browser","availability").toggled,
      "Availability visibly selects its navigation button")
    if has_omission_transport then
      check(find_browser_element(availability_root,"mir_browser_section","availability"),
        "known omitted streams use their canonical localized title without an explicit name override")
    end
    check(not find_browser_element(availability_root,"mir_browser","enqueue"),"omitted research has no queue action")
    if mir_scope_index then
      local provider_detail_count=0
      for _ in pairs(native_enrichment.details or {}) do provider_detail_count=provider_detail_count+1 end
      check(provider_detail_count>0,"declared MIR scope exposes a nonempty validated provider detail")
      local mir_productivity = emitted_productivity_technology(actual)
      if mir_productivity then
        -- This opens a technology carrying a live productivity effect inside
        -- MIR scope. The provider-recognition pass rejects base-game
        -- productivity effects, so the numeric facts below remain tied to
        -- actual Factorio recipe values.
        check(remote.call("more-infinite-research-browser","open",actual.index,{tab="research",family="mir",mode=1,sort="progression",selected=mir_productivity,search=""}),"native MIR productivity detail GUI")
        local mir_root=actual.gui.screen.mir_research_browser
        check(has_browser_fact(mir_root,"productivity_increment"),"native MIR productivity increment detail")
        check(has_browser_fact(mir_root,"productivity_current_cap"),"native MIR productivity current-limit detail")
        check(has_numeric_browser_fact(mir_root,"productivity_increment",{
          ["mir-browser.productivity-increment"]=1,
          ["mir-browser.productivity-increment-range"]=2
        }),"native MIR provider supplies numerical productivity increment")
        check(has_numeric_browser_fact(mir_root,"productivity_current_cap",{
          ["mir-browser.productivity-current-cap"]=2,
          ["mir-browser.productivity-current-cap-range"]=4
        }),"native MIR provider supplies numerical productivity current limit")
        local benefit = native_enrichment.details[mir_productivity].recipe_benefits[1]
        local icon = benefit and find_browser_element(mir_root,"mir_browser_recipe",benefit.recipe_id)
        check(icon and icon.type=="sprite" and icon.sprite=="recipe/"..benefit.recipe_id
          and icon.tags.mir_browser_recipe_effective==benefit.next_level_has_effective_benefit,
          "MIR productivity detail shows the active improved recipe as a native icon")
      end
    else
      check(not next(native_enrichment.families or {}) and not next(native_enrichment.details or {}),
        "missing MIR scope does not synthesize provider families or details")
    end
    check(remote.call("more-infinite-research-browser","open",actual.index,{tab="research",family="all",mode=1,sort="name-desc",selected="mir-browser-test-finite",search="mir-browser-test"}),"native sorted technology detail GUI")
    local root=actual.gui.screen.mir_research_browser
    local sort_control=find_browser_element(root,"mir_browser","sort")
    check(sort_control and sort_control.type=="drop-down","native sort control")
    local finite_row=find_browser_technology(root,"mir-browser-test-finite")
    check(finite_row and finite_row.caption=="Finite research fixture",
      "visible browser rows use the native localized caption before asynchronous indexing completes")
    local vanilla_link=find_browser_element(root,"mir_browser","open-vanilla")
    check(vanilla_link and vanilla_link.type=="button","native technology link")
    local research_cost=find_browser_element(root,"mir_browser_fact","research_cost")
    check(research_cost and research_cost.caption[1]=="mir-browser.research-cost"
      and research_cost.caption[2]=="1" and research_cost.caption[3]=="1",
      "native research cost converts the fixture's sixty runtime ticks into one second")
    local all_scope=find_browser_element(root,"mir_browser","family")
    check(all_scope and all_scope.type=="drop-down","native all-research scope control")
    local all_scope_index=all_scope.selected_index
    check(remote.call("more-infinite-research-browser","open",actual.index,{family="not-a-browser-family"}),"invalid family request leaves browser open")
    local preserved_scope=find_browser_element(actual.gui.screen.mir_research_browser,"mir_browser","family")
    check(preserved_scope and preserved_scope.selected_index==all_scope_index,"invalid family preserves personal scope")
    check(before==snapshot(force),"native GUI force noninterference")
  end
  local scope=native_players>0 and "exact-package-load-controlled-model-and-native-GUI-objects; rendered-client-and-two-client-GUI-not-qualified"
    or "exact-package-load-controlled-model; native-GUI-objects-rendered-client-and-two-client-GUI-not-qualified"
  helpers.write_file("browser-test.json",helpers.table_to_json{status="passed",assertions=count,scope=scope,native_players=native_players,connected_players=#game.connected_players,native_gui_assertions_exercised=native_players>0,engine=helpers.game_version},false)
  storage.browser_saved=true;storage.expected_force=before
  if #game.connected_players>0 then game.auto_save("mir-browser-acceptance") end
  script.on_nth_tick(1,nil)
end)
